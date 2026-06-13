import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, PlatformException;
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

import '../api_client.dart';
import '../models/chat_models.dart';
import '../services/call_service.dart';
import '../services/chat_prefs.dart';
import '../services/chat_realtime.dart';
import '../services/chat_service.dart';
import '../services/chat_state.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'chat_participants_screen.dart';

/// Full-screen conversation view. Subscribes to the conversation's Pusher
/// channel on init, unsubscribes on dispose via [ChatThread.dispose].
class ChatThreadScreen extends StatefulWidget {
  const ChatThreadScreen({
    super.key,
    required this.conversationId,
    required this.conversation,
    required this.myUserId,
    required this.service,
    required this.realtime,
    required this.api,
    required this.chatPrefs,
    this.calls,
  });

  final int conversationId;

  /// Seed metadata (name, peer) used for the header. May be null if the
  /// conversation was created a moment ago and the inbox hasn't rehydrated.
  final Conversation? conversation;
  final int myUserId;
  final ChatService service;
  final ChatRealtimeService realtime;
  final ApiClient api;
  final ChatPrefs chatPrefs;

  /// WebRTC call wiring. Null until HomeShell has finished bootstrap; in that
  /// case the call buttons are hidden.
  final CallService? calls;

  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen> {
  late final ChatThread _thread;
  final _composer = TextEditingController();
  final _composerFocus = FocusNode();
  final _scroll = ScrollController();
  final _picker = ImagePicker();

  /// Pending attachments — picked locally, uploaded in the background, sent
  /// when the user taps Send.
  final List<_PendingAttachment> _pending = [];

  /// Live status for any ticket referenced in this thread, keyed by public
  /// ticket number. Drives the inline Accept (claim) / Resolve footer that
  /// mirrors the web chat. Empty for ordinary conversations.
  final Map<int, TicketStatusInfo> _ticketStatuses = {};
  final Set<int> _ticketBusy = {};
  bool _ticketRefreshing = false;

  @override
  void initState() {
    super.initState();
    _thread = ChatThread(
      conversationId: widget.conversationId,
      myUserId: widget.myUserId,
      service: widget.service,
      realtime: widget.realtime,
    );
    _thread.addListener(_onThreadChange);
    _thread.loadInitial().then((_) {
      _markNewestRead();
      _refreshTicketStatuses();
    });
    _scroll.addListener(_maybeLoadOlder);
    _composer.addListener(_onComposerChanged);

    // Tell the FCM handler we're viewing this conversation so it can
    // suppress local notifications for incoming messages on this thread.
    widget.realtime.currentlyViewedConv.value = widget.conversationId;

    // Live presence dot in the header.
    widget.realtime.onlineUsers.addListener(_onPresenceChange);
    // Theme changes (Settings → chat theme picker) should immediately
    // re-tint the bubbles in any open thread.
    widget.chatPrefs.addListener(_onPresenceChange);
  }

  void _onPresenceChange() {
    if (mounted) setState(() {});
  }

  String? _lastComposerText;
  void _onComposerChanged() {
    if (!mounted) return;
    setState(() {});
    // Only fire typing on actual user edits, not clear() calls from our
    // own send. And only while the field is non-empty.
    final text = _composer.text;
    if (text.isNotEmpty && text != _lastComposerText) {
      _thread.notifyTyping();
    }
    _lastComposerText = text;
  }

  void _onThreadChange() {
    if (mounted) {
      setState(() {});
      _markNewestRead();
      // A new 👋/✅ ticket bubble may have arrived (or a new ticket was
      // submitted) — re-pull live statuses so the footer stays accurate.
      _refreshTicketStatuses();
    }
  }

  /// Scan the thread for ticket references and refresh their live status via
  /// getTicketsByIds. No-op (and clears) when the thread has no tickets, so
  /// ordinary DMs never hit the endpoint.
  Future<void> _refreshTicketStatuses() async {
    if (_ticketRefreshing) return;
    final ids = <int>{};
    for (final m in _thread.messages) {
      final ref = detectTicketRef(m.body);
      if (ref != null) ids.add(ref.id);
    }
    if (ids.isEmpty) {
      if (_ticketStatuses.isNotEmpty && mounted) {
        setState(() => _ticketStatuses.clear());
      }
      return;
    }
    _ticketRefreshing = true;
    final map = await widget.service.ticketStatuses(ids.toList());
    _ticketRefreshing = false;
    if (!mounted || map.isEmpty) return;
    setState(() {
      _ticketStatuses
        ..clear()
        ..addAll(map);
    });
  }

  Future<void> _acceptTicket(int ticketId) async {
    if (_ticketBusy.contains(ticketId)) return;
    setState(() => _ticketBusy.add(ticketId));
    final ok = await widget.service.acceptTicket(ticketId, widget.myUserId);
    if (!mounted) return;
    setState(() => _ticketBusy.remove(ticketId));
    _toast(ok ? 'Ticket #$ticketId accepted' : 'Could not accept ticket');
    if (ok) await _refreshTicketStatuses();
  }

  Future<void> _resolveTicket(int ticketId) async {
    if (_ticketBusy.contains(ticketId)) return;
    setState(() => _ticketBusy.add(ticketId));
    final ok = await widget.service.resolveTicket(ticketId, widget.myUserId);
    if (!mounted) return;
    setState(() => _ticketBusy.remove(ticketId));
    _toast(ok ? 'Ticket #$ticketId resolved' : 'Could not resolve ticket');
    if (ok) await _refreshTicketStatuses();
  }

  Future<void> _openTicketDetail(int ticketId) async {
    final detail = await widget.service.ticketDetail(ticketId);
    if (!mounted) return;
    if (detail == null) {
      _toast('Ticket details unavailable');
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Brand.surface,
      isScrollControlled: true,
      builder: (_) => _TicketDetailSheet(detail: detail),
    );
  }

  /// The ticket to surface in the header: the most recent non-closed ticket
  /// referenced in this thread whose live status we know. Null when the
  /// conversation has no actionable ticket. Mirrors the web's
  /// activeHeaderTicket(), but also surfaces NEW tickets so they can be
  /// claimed straight from the header.
  ({int id, TicketStatusInfo status})? _activeTicket() {
    for (final m in _thread.messages) {
      // messages are newest-first, so the first hit is the latest ticket.
      final ref = detectTicketRef(m.body);
      if (ref == null) continue;
      final st = _ticketStatuses[ref.id];
      if (st == null || st.isClosed) continue;
      return (id: ref.id, status: st);
    }
    return null;
  }

  String _ticketStatusLabel(TicketStatusInfo st) {
    if (st.isNew) return 'NEW';
    if (st.isInProgress) return 'IN PROGRESS';
    if (st.isResolved) return 'RESOLVED';
    return 'CLOSED';
  }

  /// Fire a debounced markRead for the newest known message id. Called
  /// after the initial load and whenever a new message arrives while the
  /// thread is open. The thread's internal monotonic guard handles dupes.
  void _markNewestRead() {
    if (_thread.messages.isEmpty) return;
    final newest = _thread.messages.first; // sorted DESC
    final id = newest.id;
    if (id == null) return;
    _thread.scheduleMarkRead(id);
  }

  void _maybeLoadOlder() {
    // ListView is reversed — `maxScrollExtent` is the "top" of history.
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 160) {
      _thread.loadOlder();
    }
  }

  bool get _canSend {
    if (_chatLocked) return false;
    if (_pending.any((p) => p.status == _UploadStatus.uploading)) return false;
    final hasReady = _pending.any((p) => p.status == _UploadStatus.ready);
    return _composer.text.trim().isNotEmpty || hasReady;
  }

  /// True when this is a customer/guest portal support thread that has no
  /// filed ticket at all. Staff can't message the customer until a ticket
  /// exists in the thread; once any ticket has been filed (whatever its
  /// status — including resolved / closed) the composer stays open. Internal
  /// staff DMs, ordinary staff groups, and channels are never locked.
  bool get _chatLocked {
    final conv = widget.conversation;
    if (conv == null) return false;
    if (!_isCustomerSupportThread(conv)) return false;
    return !_hasFiledTicket();
  }

  /// Customer / guest portal support threads are server-created groups whose
  /// `topic` is keyed `customer:<id>` or `guest:<id>` (see ChatFacade —
  /// addCustomer / createGuestSupportConversation). Ordinary staff groups
  /// have a null topic, DMs carry a peer instead, so the topic prefix is the
  /// reliable signal that the other side is a portal customer.
  bool _isCustomerSupportThread(Conversation conv) {
    final topic = conv.topic?.trim().toLowerCase() ?? '';
    return topic.startsWith('customer:') || topic.startsWith('guest:');
  }

  /// True when the thread contains at least one filed ticket, in any status.
  /// Detected purely from the ticket system-messages already in the thread,
  /// so it doesn't depend on live ticket-status loading.
  bool _hasFiledTicket() {
    for (final m in _thread.messages) {
      if (detectTicketRef(m.body) != null) return true;
    }
    return false;
  }

  Future<void> _handleSend() async {
    if (!_canSend) return;
    final text = _composer.text;
    final ready = _pending
        .where((p) => p.status == _UploadStatus.ready)
        .map((p) => p.attachment!)
        .toList(growable: false);
    setState(() {
      _composer.clear();
      _pending.removeWhere((p) => p.status == _UploadStatus.ready);
    });
    await _thread.send(text, attachments: ready);
  }

  Future<void> _openParticipants() async {
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder: (_) => ChatParticipantsScreen(
          service: widget.service,
          realtime: widget.realtime,
          conversationId: widget.conversationId,
          myUserId: widget.myUserId,
        ),
      ),
    );
    if (!mounted) return;
    if (result == participantsResultLeft) {
      Navigator.of(context).pop();
    }
  }

  /// Roles allowed to place / receive voice & video calls. Customer (and any
  /// other non-staff) DMs don't get call buttons — calling is a staff-to-staff
  /// feature. Compared case-insensitively against the peer's `role`.
  static const _callableRoles = {'admin', 'super_admin', 'user'};

  /// True when the DM peer is a staff member eligible for calls. Drives both
  /// the header buttons and the [_placeCall] guard so the two never disagree.
  bool get _peerCallable {
    final role = widget.conversation?.peer?.role.trim().toLowerCase();
    return role != null && _callableRoles.contains(role);
  }

  /// Group/channel calls require an SFU — for the MVP we only place
  /// two-party DM calls. The button is hidden in non-DM threads and in DMs
  /// with a non-callable peer (see [_callableRoles]).
  Future<void> _placeCall(CallMedia media) async {
    final calls = widget.calls;
    final conv = widget.conversation;
    if (calls == null) return;
    if (conv == null || conv.type != 'dm' || conv.peer == null) {
      _toast('CALLS ARE DM-ONLY FOR NOW');
      return;
    }
    if (!_peerCallable) {
      _toast('CALLS AREN\'T AVAILABLE FOR THIS USER');
      return;
    }

    // Block only when there's an actual peer connection in progress. Stuck
    // `calling` / `ringing` (caller-side) phases are recovered by force-
    // resetting — they're a sign the previous attempt was abandoned, not a
    // live call we need to protect.
    if (calls.isInLiveCall) {
      _toast('ALREADY IN A CALL');
      return;
    }
    if (calls.isIncomingRinging) {
      _toast('ANSWER INCOMING CALL FIRST');
      return;
    }
    if (calls.isActive) {
      // Stuck caller-side: clear it so the user can start fresh.
      calls.forceReset();
    }

    final ok = await calls.placeCall(
      peerId: conv.peer!.id,
      peerName: conv.peer!.displayName,
      media: media,
    );
    if (!ok && mounted) {
      _toast('COULD NOT START CALL');
    }
  }

  Widget? _buildHeaderActions({required bool isDm, required bool peerOnline}) {
    final canCall = widget.calls != null && isDm && _peerCallable;
    final children = <Widget>[];

    // Ticket controls live in the upper-right header so staff can see at a
    // glance that the conversation has a ticket and Claim / Resolve it
    // without scrolling. Shown only when there's an active, non-closed
    // ticket. The orange button is the primary action; the ticket icon
    // opens full details.
    final ticket = _activeTicket();
    if (ticket != null) {
      final st = ticket.status;
      final id = ticket.id;
      if (_ticketBusy.contains(id)) {
        children.add(const _HeaderTicketButton(
          icon: Icons.hourglass_top,
          tooltip: 'Working…',
        ));
      } else if (st.isNew) {
        children.add(_HeaderTicketButton(
          icon: Icons.check,
          tooltip: 'Claim ticket #$id',
          onTap: () => _acceptTicket(id),
        ));
      } else if (st.isInProgress && st.assignedAgentId == widget.myUserId) {
        children.add(_HeaderTicketButton(
          icon: Icons.flag_outlined,
          tooltip: 'Resolve ticket #$id',
          onTap: () => _resolveTicket(id),
        ));
      }
      children
        ..add(const SizedBox(width: 6))
        ..add(StationAction(
          icon: Icons.confirmation_number_outlined,
          tooltip: 'Ticket #$id details',
          onPressed: () => _openTicketDetail(id),
        ));
    }

    if (canCall) {
      if (children.isNotEmpty) children.add(const SizedBox(width: 6));
      children
        ..add(StationAction(
          icon: Icons.call,
          tooltip: 'Voice call',
          onPressed: () => _placeCall(CallMedia.voice),
        ))
        ..add(const SizedBox(width: 6))
        ..add(StationAction(
          icon: Icons.videocam_outlined,
          tooltip: 'Video call',
          onPressed: () => _placeCall(CallMedia.video),
        ));
    }
    // Members icon — hidden while a ticket is active so the ticket controls
    // have room in the header (the ticket-details sheet lists participants).
    if (!isDm && ticket == null) {
      if (children.isNotEmpty) children.add(const SizedBox(width: 6));
      children.add(StationAction(
        icon: Icons.group_outlined,
        tooltip: 'Members',
        onPressed: _openParticipants,
      ));
    }
    if (children.isEmpty) return null;
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }

  /// Long-press menu on a message: pin / unpin (staff action) + copy.
  Future<void> _showMessageMenu(Message m) async {
    final id = m.id;
    if (id == null) return;
    final isPinned = _thread.isPinned(id);
    final choice = await showModalBottomSheet<_MsgAction>(
      context: context,
      backgroundColor: Brand.surface,
      builder: (_) => _MessageActionSheet(
        isPinned: isPinned,
        hasBody: m.body.trim().isNotEmpty,
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case _MsgAction.pin:
        final ok = await _thread.pin(id);
        if (mounted && !ok) _toast('COULD NOT PIN MESSAGE');
        break;
      case _MsgAction.unpin:
        final ok = await _thread.unpin(id);
        if (mounted && !ok) _toast('COULD NOT UNPIN MESSAGE');
        break;
      case _MsgAction.copy:
        await Clipboard.setData(ClipboardData(text: m.body));
        if (mounted) _toast('COPIED');
        break;
    }
  }

  /// Bottom sheet listing every pinned message, with an unpin action on each.
  Future<void> _showPinnedSheet() async {
    final toUnpin = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Brand.surface,
      isScrollControlled: true,
      builder: (_) => _PinnedListSheet(pinned: _thread.pinned),
    );
    if (!mounted || toUnpin == null) return;
    final ok = await _thread.unpin(toUnpin);
    if (mounted && !ok) _toast('COULD NOT UNPIN MESSAGE');
  }

  Future<void> _showAttachmentSheet() async {
    final picked = await showModalBottomSheet<_PickerChoice>(
      context: context,
      backgroundColor: Brand.surface,
      builder: (_) => const _AttachmentPickerSheet(),
    );
    if (!mounted || picked == null) return;
    switch (picked) {
      case _PickerChoice.camera:
        await _addFromImagePicker(ImageSource.camera);
        break;
      case _PickerChoice.gallery:
        await _addFromImagePicker(ImageSource.gallery);
        break;
      case _PickerChoice.file:
        await _addFromFilePicker();
        break;
    }
  }

  Future<void> _addFromImagePicker(ImageSource source) async {
    try {
      final x = await _picker.pickImage(source: source, imageQuality: 92);
      if (x == null) return;
      _enqueueUpload(File(x.path));
    } on PlatformException catch (e) {
      _toast('PICKER UNAVAILABLE: ${e.code}');
    } catch (_) {
      _toast('COULD NOT PICK IMAGE');
    }
  }

  Future<void> _addFromFilePicker() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.first.path;
      if (path == null) return;
      _enqueueUpload(File(path));
    } catch (_) {
      _toast('COULD NOT PICK FILE');
    }
  }

  void _enqueueUpload(File file) {
    const maxBytes = 25 * 1024 * 1024;
    final size = file.lengthSync();
    if (size <= 0 || size > maxBytes) {
      _toast('FILE TOO LARGE — MAX 25 MB');
      return;
    }
    final pending = _PendingAttachment(
      file: file,
      sizeBytes: size,
    );
    setState(() => _pending.add(pending));
    _runUpload(pending);
  }

  Future<void> _runUpload(_PendingAttachment pending) async {
    setState(() {
      pending.status = _UploadStatus.uploading;
      pending.error = null;
    });
    final outcome = await widget.service.uploadAttachment(
      file: pending.file,
      conversationId: widget.conversationId,
    );
    if (!mounted) return;
    setState(() {
      if (outcome.attachment == null) {
        pending.status = _UploadStatus.failed;
        pending.error = outcome.error;
      } else {
        pending.attachment = outcome.attachment;
        pending.status = _UploadStatus.ready;
      }
    });
    // Surface the server's reason so the user knows what to do next
    // (file too large / type not allowed / storage problem / etc.).
    if (outcome.error != null && mounted) {
      _toast('UPLOAD FAILED · ${outcome.error!.toUpperCase()}');
    }
  }

  void _retryUpload(_PendingAttachment p) => _runUpload(p);

  void _removePending(_PendingAttachment p) {
    setState(() => _pending.remove(p));
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    // Clear the "currently viewed" signal first — if any FCM events are
    // still in flight when we pop, they should not be suppressed.
    if (widget.realtime.currentlyViewedConv.value == widget.conversationId) {
      widget.realtime.currentlyViewedConv.value = null;
    }
    widget.realtime.onlineUsers.removeListener(_onPresenceChange);
    widget.chatPrefs.removeListener(_onPresenceChange);
    _thread.removeListener(_onThreadChange);
    _thread.dispose();
    _composer.dispose();
    _composerFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conv = widget.conversation;
    final title = conv?.name ?? 'Conversation';
    final isDm = conv?.type == 'dm';
    final isChannel = conv?.type == 'channel';
    final peer = conv?.peer;
    final livePeerOnline = peer != null &&
        widget.realtime.onlineUsers.value.contains(peer.id);
    final peerOnline = livePeerOnline || (peer?.isOnline ?? false);
    final peerLastSeen = peer == null
        ? null
        : formatLastSeen(online: peerOnline, lastSeenAt: peer.lastSeenAt);
    // When the conversation has an active ticket, the header reads as a
    // ticket workspace (TICKET #id · STATUS) rather than "GROUP · N MEMBERS",
    // so the ticket is obvious at a glance and the members chrome steps aside.
    final headerTicket = _activeTicket();
    final subLabel = headerTicket != null
        ? 'TICKET #${headerTicket.id} · ${_ticketStatusLabel(headerTicket.status)}'
        : conv == null
            ? 'DIRECT MESSAGE'
            : isDm
                ? 'DM · ${peerLastSeen ?? (peerOnline ? 'ONLINE' : 'OFFLINE')}'
                : isChannel
                    ? 'CHANNEL · ${conv.visibility.toUpperCase()}'
                    : 'GROUP · ${conv.participantCount} MEMBERS';

    return StationScaffold(
      stationNumber: '05',
      stationLabel: subLabel,
      title: title,
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      trailing: _buildHeaderActions(isDm: isDm, peerOnline: peerOnline),
      child: Column(
        children: [
          if (_thread.pinned.isNotEmpty) ...[
            _PinnedBanner(
              pinned: _thread.pinned,
              onTap: _showPinnedSheet,
            ),
            const Hairline(),
          ],
          Expanded(
            child: _thread.messages.isEmpty && _thread.loading
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Brand.signal,
                      ),
                    ),
                  )
                : _thread.messages.isEmpty
                    ? Center(
                        child: Text(
                          'Say something to get started.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      )
                    : Builder(
                    builder: (_) {
                      final msgs = _thread.messages; // DESC by id
                      // Index of my most recent (newest-first) message. The
                      // "Seen by" indicator is rendered only under that one
                      // bubble, matching iMessage / Messenger conventions.
                      final myNewestIndex = msgs
                          .indexWhere((m) => m.senderId == widget.myUserId);
                      return ListView.builder(
                        controller: _scroll,
                        reverse: true,
                        padding: const EdgeInsets.only(bottom: 12),
                        itemCount: msgs.length + (_thread.hasMore ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (i == msgs.length) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(
                                child: SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Brand.signal,
                                  ),
                                ),
                              ),
                            );
                          }
                          final m = msgs[i];
                          final mine = m.senderId == widget.myUserId;
                          final isNewestMine = mine && i == myNewestIndex;

                          // Grouping vs the visually-next bubble below (i-1,
                          // which is newer). Suppress our meta line if that
                          // bubble is from the same sender within 2 min —
                          // it carries the timestamp for the whole group.
                          final groupedBelow = i > 0 &&
                              _isGrouped(msgs[i], msgs[i - 1]);

                          // Date separator goes ABOVE the oldest message of a
                          // day (in reversed ListView, that's higher on screen).
                          final isOldestOfDay = i == msgs.length - 1 ||
                              !_sameDay(m.createdAt, msgs[i + 1].createdAt);

                          Widget bubble = _MessageBubble(
                            message: m,
                            mine: mine,
                            isNewestMine: isNewestMine,
                            suppressMeta: groupedBelow && !isNewestMine,
                            grouped: groupedBelow,
                            pinned: _thread.isPinned(m.id),
                            readCursors: _thread.readCursors,
                            otherParticipantCount:
                                (_thread.totalParticipants - 1).clamp(0, 1000),
                            theme: widget.chatPrefs.theme,
                            api: widget.api,
                            service: widget.service,
                            onRetry: m.status == MessageStatus.failed
                                ? () => _thread.retry(m)
                                : null,
                          );

                          // Long-press a persisted message to pin/unpin it.
                          // Optimistic (id == null) messages can't be pinned.
                          if (m.id != null) {
                            bubble = GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onLongPress: () => _showMessageMenu(m),
                              child: bubble,
                            );
                          }

                          if (!isOldestOfDay) return bubble;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _DateSeparator(iso: m.createdAt),
                              bubble,
                            ],
                          );
                        },
                      );
                    },
                  ),
          ),
          if (_thread.typingNames.isNotEmpty)
            _TypingStrip(names: _thread.typingNames),
          if (_pending.isNotEmpty) ...[
            const Hairline(),
            _PendingStrip(
              pending: _pending,
              onRetry: _retryUpload,
              onRemove: _removePending,
            ),
          ],
          const Hairline(),
          _Composer(
            controller: _composer,
            focusNode: _composerFocus,
            canSend: _canSend,
            locked: _chatLocked,
            onSend: _handleSend,
            onAttach: _showAttachmentSheet,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────── pending state ──────────────────

enum _UploadStatus { uploading, ready, failed }

class _PendingAttachment {
  _PendingAttachment({required this.file, required this.sizeBytes});
  final File file;
  final int sizeBytes;
  Attachment? attachment;
  String? error;
  _UploadStatus status = _UploadStatus.uploading;

  String get displayName {
    final s = file.path;
    final i = s.lastIndexOf('/');
    return i < 0 ? s : s.substring(i + 1);
  }

  bool get isImage {
    final lower = file.path.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.heic');
  }
}

// ─────────────────────────────────────────── pending strip ──────────────────

class _PendingStrip extends StatelessWidget {
  const _PendingStrip({
    required this.pending,
    required this.onRetry,
    required this.onRemove,
  });

  final List<_PendingAttachment> pending;
  final void Function(_PendingAttachment) onRetry;
  final void Function(_PendingAttachment) onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 88,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: pending.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final p = pending[i];
          return _PendingChip(
            pending: p,
            onRetry: () => onRetry(p),
            onRemove: () => onRemove(p),
          );
        },
      ),
    );
  }
}

class _PendingChip extends StatelessWidget {
  const _PendingChip({
    required this.pending,
    required this.onRetry,
    required this.onRemove,
  });

  final _PendingAttachment pending;
  final VoidCallback onRetry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final size = 68.0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Brand.surfaceHi,
            border: Border.all(color: Brand.rule, width: 1),
          ),
          child: pending.isImage
              ? Image.file(pending.file, fit: BoxFit.cover)
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(
                      pending.displayName,
                      style: text.labelMedium,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
        ),
        if (pending.status == _UploadStatus.uploading)
          Positioned.fill(
            child: Container(
              color: Brand.canvas.withValues(alpha: 0.55),
              child: const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Brand.signal,
                  ),
                ),
              ),
            ),
          ),
        if (pending.status == _UploadStatus.failed)
          Positioned.fill(
            child: GestureDetector(
              onTap: onRetry,
              child: Container(
                color: Brand.canvas.withValues(alpha: 0.65),
                child: const Center(
                  child: Icon(Icons.refresh, color: Brand.signal, size: 22),
                ),
              ),
            ),
          ),
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                color: Brand.canvas,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 14, color: Brand.paper),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────── picker sheet ───────────────────

enum _PickerChoice { camera, gallery, file }

enum _MsgAction { pin, unpin, copy }

/// Compact banner pinned above the message list. Shows the most recent pin
/// (single-line) plus a "+N more" hint; tapping opens the full list.
class _PinnedBanner extends StatelessWidget {
  const _PinnedBanner({required this.pinned, required this.onTap});

  final List<PinnedMessage> pinned;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final latest = pinned.first;
    final extra = pinned.length - 1;
    final preview = latest.body.trim().isEmpty
        ? '[attachment]'
        : latest.body.trim().replaceAll('\n', ' ');
    return Material(
      color: Brand.surface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Row(
            children: [
              const Icon(Icons.push_pin, size: 16, color: Brand.signal),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      extra > 0
                          ? 'PINNED · ${pinned.length}'
                          : 'PINNED',
                      style: text.labelSmall
                          ?.copyWith(color: Brand.signal, letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right,
                  size: 18, color: Brand.paperDim),
            ],
          ),
        ),
      ),
    );
  }
}

/// Long-press action sheet for a single message.
class _MessageActionSheet extends StatelessWidget {
  const _MessageActionSheet({required this.isPinned, required this.hasBody});

  final bool isPinned;
  final bool hasBody;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: Brand.surface,
          border: Border(top: BorderSide(color: Brand.signal, width: 2)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('MESSAGE', style: text.labelLarge),
            const SizedBox(height: 8),
            const Hairline(),
            if (isPinned)
              ListTile(
                leading: const Icon(Icons.push_pin_outlined,
                    color: Brand.paper, size: 20),
                title: const Text('Unpin message'),
                onTap: () => Navigator.of(context).pop(_MsgAction.unpin),
              )
            else
              ListTile(
                leading:
                    const Icon(Icons.push_pin, color: Brand.paper, size: 20),
                title: const Text('Pin message'),
                onTap: () => Navigator.of(context).pop(_MsgAction.pin),
              ),
            if (hasBody)
              ListTile(
                leading: const Icon(Icons.copy_outlined,
                    color: Brand.paper, size: 20),
                title: const Text('Copy text'),
                onTap: () => Navigator.of(context).pop(_MsgAction.copy),
              ),
          ],
        ),
      ),
    );
  }
}

/// Full list of pinned messages. Returns the message id to unpin (or null).
class _PinnedListSheet extends StatelessWidget {
  const _PinnedListSheet({required this.pinned});

  final List<PinnedMessage> pinned;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        decoration: const BoxDecoration(
          color: Brand.surface,
          border: Border(top: BorderSide(color: Brand.signal, width: 2)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.push_pin, size: 14, color: Brand.signal),
                const SizedBox(width: 6),
                Text('PINNED MESSAGES', style: text.labelLarge),
              ],
            ),
            const SizedBox(height: 8),
            const Hairline(),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: pinned.length,
                separatorBuilder: (_, __) => const Hairline(),
                itemBuilder: (_, i) {
                  final p = pinned[i];
                  final body = p.body.trim().isEmpty
                      ? '[attachment]'
                      : p.body.trim();
                  return ListTile(
                    title: Text(
                      body,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium,
                    ),
                    subtitle: Text(
                      p.senderName.isEmpty ? '—' : p.senderName,
                      style: text.labelSmall?.copyWith(color: Brand.paperDim),
                    ),
                    trailing: IconButton(
                      tooltip: 'Unpin',
                      icon: const Icon(Icons.push_pin_outlined,
                          color: Brand.signal, size: 20),
                      onPressed: () => Navigator.of(context).pop(p.messageId),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentPickerSheet extends StatelessWidget {
  const _AttachmentPickerSheet();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: Brand.surface,
          border: Border(top: BorderSide(color: Brand.signal, width: 2)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('ATTACH', style: text.labelLarge),
            const SizedBox(height: 8),
            const Hairline(),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined,
                  color: Brand.paper, size: 20),
              title: const Text('Camera'),
              onTap: () => Navigator.of(context).pop(_PickerChoice.camera),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined,
                  color: Brand.paper, size: 20),
              title: const Text('Gallery'),
              onTap: () => Navigator.of(context).pop(_PickerChoice.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.attach_file_outlined,
                  color: Brand.paper, size: 20),
              title: const Text('File'),
              onTap: () => Navigator.of(context).pop(_PickerChoice.file),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────── composer ───────────────────────

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.canSend,
    required this.locked,
    required this.onSend,
    required this.onAttach,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool canSend;

  /// When true the customer hasn't filed (an open) ticket yet, so the whole
  /// composer — input, attach, and send — is disabled and a hint is shown.
  final bool locked;
  final VoidCallback onSend;
  final VoidCallback onAttach;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom > 0 ? 8 : 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (locked)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline,
                      size: 14, color: Brand.paperDim),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'WAITING FOR A TICKET — MESSAGING UNLOCKS ONCE THE '
                      'CUSTOMER FILES ONE',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: Brand.paperDim, letterSpacing: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                tooltip: 'Attach',
                onPressed: locked ? null : onAttach,
                icon: Icon(Icons.add,
                    color: locked ? Brand.paperDim : Brand.paper),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: !locked,
                  maxLines: 4,
                  minLines: 1,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    labelText: locked ? 'MESSAGING LOCKED' : 'MESSAGE',
                  ),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                tooltip: 'Send',
                onPressed: canSend ? onSend : null,
                icon: Icon(
                  Icons.arrow_upward,
                  color: canSend ? Brand.signal : Brand.paperDim,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────── message bubble ────────────────

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.api,
    required this.service,
    required this.theme,
    this.isNewestMine = false,
    this.suppressMeta = false,
    this.grouped = false,
    this.pinned = false,
    this.readCursors = const {},
    this.otherParticipantCount = 0,
    this.onRetry,
  });

  final Message message;
  final bool mine;
  final ChatTheme theme;
  final bool isNewestMine;

  /// Whether this message is currently pinned in the conversation. Drives a
  /// small pin marker in the meta line.
  final bool pinned;

  /// Suppress the timestamp / seen-by line under this bubble. Used when
  /// the bubble below is from the same sender within 2 min — that newer
  /// bubble carries the meta for the whole group.
  final bool suppressMeta;

  /// Reduced vertical padding when grouped with the bubble below, so a
  /// run of messages from one person reads as a block, not discrete lines.
  final bool grouped;

  /// Other participants' read cursors (user_id → last_read_message_id).
  /// Only consulted on the newest mine bubble.
  final Map<int, int> readCursors;

  /// Number of other participants in the conversation (excluding self).
  /// For DMs this is 1; for groups/channels, the rest of the room.
  final int otherParticipantCount;

  final ApiClient api;
  final ChatService service;
  final VoidCallback? onRetry;

  /// "Seen" / "Seen by N" / null. Only computed when this is the newest
  /// message I sent and the server has assigned it an id.
  String? get _seenLabel {
    if (!isNewestMine) return null;
    final mid = message.id;
    if (mid == null) return null;
    if (otherParticipantCount <= 0) return null;
    final seenCount =
        readCursors.values.where((cursor) => cursor >= mid).length;
    if (seenCount <= 0) return null;
    if (otherParticipantCount == 1) return 'SEEN';
    return 'SEEN BY $seenCount';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final align = mine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final hasBody = message.body.trim().isNotEmpty;
    final seen = _seenLabel;

    return Padding(
      padding: EdgeInsets.only(
        top: grouped ? 1 : 6,
        bottom: suppressMeta ? 1 : 6,
      ),
      child: Column(
        crossAxisAlignment: align,
        children: [
          if (message.attachments.isNotEmpty) ...[
            _AttachmentList(
              message: message,
              mine: mine,
              api: api,
              service: service,
            ),
            if (hasBody) const SizedBox(height: 6),
          ],
          if (hasBody)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78,
              ),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: mine ? theme.mineBg : theme.theirBg,
                  border: Border.all(
                    color: mine ? theme.mineBorder : theme.theirBorder,
                    width: 1,
                  ),
                ),
                child: Text(message.body, style: text.bodyMedium),
              ),
            ),
          if (pinned)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                mainAxisAlignment:
                    mine ? MainAxisAlignment.end : MainAxisAlignment.start,
                children: [
                  Icon(Icons.push_pin, size: 11, color: theme.accent),
                  const SizedBox(width: 3),
                  Text('PINNED',
                      style: text.labelSmall?.copyWith(color: theme.accent)),
                ],
              ),
            ),
          if (!suppressMeta) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment:
                  mine ? MainAxisAlignment.end : MainAxisAlignment.start,
              children: [
                if (message.status == MessageStatus.sending)
                  Text('SENDING…', style: text.labelMedium)
                else if (message.status == MessageStatus.failed)
                  InkWell(
                    onTap: onRetry,
                    child: Text(
                      'FAILED · TAP TO RETRY',
                      style: text.labelMedium?.copyWith(color: Brand.signal),
                    ),
                  )
                else ...[
                  Text(_shortTime(message.createdAt), style: text.labelMedium),
                  if (seen != null) ...[
                    const SizedBox(width: 8),
                    Text(seen,
                        style:
                            text.labelMedium?.copyWith(color: theme.accent)),
                  ],
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Prominent orange circular header button for the primary ticket action
/// (Claim / Resolve). Sits in the chat header's trailing row beside the
/// members icon so the ticket is impossible to miss. Footprint (32×32)
/// matches [StationAction] so they line up. [onTap] null → disabled look.
class _HeaderTicketButton extends StatelessWidget {
  const _HeaderTicketButton({
    required this.icon,
    required this.tooltip,
    this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: onTap == null ? Brand.surfaceHi : Brand.signal,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(
              icon,
              size: 18,
              color: onTap == null ? Brand.paperDim : Brand.canvas,
            ),
          ),
        ),
      ),
    );
  }
}

/// Status pill: NEW · IN PROGRESS (· agent) · RESOLVED · CLOSED. Falls back
/// to a neutral "Ticket #" chip while the live status is still loading.
class _TicketPill extends StatelessWidget {
  const _TicketPill({required this.status});
  final TicketStatusInfo? status;

  @override
  Widget build(BuildContext context) {
    final st = status;
    late final String label;
    late final Color bg;
    late final Color fg;
    Color? border;

    if (st == null) {
      label = 'TICKET';
      bg = Brand.surfaceHi;
      fg = Brand.paperDim;
    } else if (st.isNew) {
      label = 'NEW';
      bg = Brand.signal;
      fg = Brand.canvas;
    } else if (st.isInProgress) {
      label = st.agentName != null && st.agentName!.isNotEmpty
          ? 'IN PROGRESS · ${st.agentName!.toUpperCase()}'
          : 'IN PROGRESS';
      bg = Colors.transparent;
      fg = Brand.signal;
      border = Brand.signal;
    } else if (st.isResolved) {
      label = 'RESOLVED';
      bg = Brand.surfaceHi;
      fg = Brand.paperDim;
    } else {
      label = 'CLOSED';
      bg = Brand.surfaceHi;
      fg = Brand.paperDim;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: border == null ? null : Border.all(color: border, width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

/// Bottom sheet showing the full ticket row (chat.getTicketDetail).
class _TicketDetailSheet extends StatelessWidget {
  const _TicketDetailSheet({required this.detail});
  final TicketDetail detail;

  String _fmtNo() {
    final n = detail.ticketNumber ?? detail.id;
    return '#$n';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.confirmation_number_outlined,
                    size: 18, color: Brand.signal),
                const SizedBox(width: 8),
                Text('TICKET ${_fmtNo()}', style: text.labelLarge),
                const Spacer(),
                _TicketPill(
                  status: TicketStatusInfo(
                    status: detail.status,
                    agentName: detail.agentName,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Hairline(),
            const SizedBox(height: 16),
            if (detail.subject.isNotEmpty) ...[
              Text(detail.subject,
                  style: text.titleMedium ?? text.bodyLarge),
              const SizedBox(height: 8),
            ],
            if (detail.description.isNotEmpty)
              Text(detail.description, style: text.bodyMedium),
            const SizedBox(height: 16),
            _DetailRow(label: 'PRIORITY', value: detail.priority.toUpperCase()),
            if (detail.businessName != null)
              _DetailRow(label: 'BUSINESS', value: detail.businessName!),
            if (detail.customerName != null)
              _DetailRow(label: 'CUSTOMER', value: detail.customerName!),
            if (detail.agentName != null)
              _DetailRow(label: 'AGENT', value: detail.agentName!),
            if (detail.createdAt != null)
              _DetailRow(label: 'CREATED', value: detail.createdAt!),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: text.labelMedium),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(value, style: text.bodyMedium)),
        ],
      ),
    );
  }
}

class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.iso});
  final String iso;

  @override
  Widget build(BuildContext context) {
    final label = _formatDaySeparator(iso);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          const Expanded(child: Hairline()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          const Expanded(child: Hairline()),
        ],
      ),
    );
  }
}

/// Two messages are "grouped" if they're from the same sender and
/// created ≤ 2 min apart. Failed / sending optimistic messages never
/// count as grouped (they need their own status meta).
bool _isGrouped(Message older, Message newer) {
  if (older.senderId != newer.senderId) return false;
  if (older.status != MessageStatus.sent ||
      newer.status != MessageStatus.sent) {
    return false;
  }
  try {
    final a = DateTime.parse(older.createdAt.replaceAll(' ', 'T'));
    final b = DateTime.parse(newer.createdAt.replaceAll(' ', 'T'));
    return b.difference(a).inMinutes.abs() <= 2;
  } catch (_) {
    return false;
  }
}

bool _sameDay(String a, String b) {
  try {
    final x = DateTime.parse(a.replaceAll(' ', 'T'));
    final y = DateTime.parse(b.replaceAll(' ', 'T'));
    return x.year == y.year && x.month == y.month && x.day == y.day;
  } catch (_) {
    return true; // on parse failure, don't insert a separator
  }
}

/// "TODAY" / "YESTERDAY" / "MONDAY" / "05 APR" / "05 APR 2024".
String _formatDaySeparator(String iso) {
  try {
    final dt = DateTime.parse(iso.replaceAll(' ', 'T'));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thatDay = DateTime(dt.year, dt.month, dt.day);
    final daysAgo = today.difference(thatDay).inDays;

    if (daysAgo == 0) return 'TODAY';
    if (daysAgo == 1) return 'YESTERDAY';
    const weekdays = [
      'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY',
      'FRIDAY', 'SATURDAY', 'SUNDAY',
    ];
    if (daysAgo < 7) return weekdays[dt.weekday - 1];
    const months = [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
    ];
    final dd = dt.day.toString().padLeft(2, '0');
    final mon = months[dt.month - 1];
    if (dt.year == now.year) return '$dd $mon';
    return '$dd $mon ${dt.year}';
  } catch (_) {
    return '';
  }
}

class _AttachmentList extends StatelessWidget {
  const _AttachmentList({
    required this.message,
    required this.mine,
    required this.api,
    required this.service,
  });

  final Message message;
  final bool mine;
  final ApiClient api;
  final ChatService service;

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width * 0.78;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          for (final a in message.attachments) ...[
            if (a.isImage)
              _ImageAttachment(attachment: a, api: api, service: service)
            else
              _FileAttachment(attachment: a, api: api, service: service),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _ImageAttachment extends StatelessWidget {
  const _ImageAttachment({
    required this.attachment,
    required this.api,
    required this.service,
  });
  final Attachment attachment;
  final ApiClient api;
  final ChatService service;

  @override
  Widget build(BuildContext context) {
    final url = service.attachmentUrl(attachment.id);
    final aspect = (attachment.width != null &&
            attachment.height != null &&
            attachment.height! > 0)
        ? attachment.width! / attachment.height!
        : 1.5;

    return GestureDetector(
      onTap: () => _openImageViewer(context, url, api),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 280),
        child: AspectRatio(
          aspectRatio: aspect.clamp(0.6, 2.5),
          child: Container(
            decoration: BoxDecoration(
              color: Brand.surfaceHi,
              border: Border.all(color: Brand.rule, width: 1),
            ),
            child: CachedNetworkImage(
              imageUrl: url,
              httpHeaders: api.authHeaders(),
              fit: BoxFit.cover,
              placeholder: (_, __) => const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Brand.signal,
                  ),
                ),
              ),
              errorWidget: (_, __, ___) => const Center(
                child: Icon(Icons.broken_image_outlined,
                    color: Brand.paperDim, size: 24),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void _openImageViewer(BuildContext context, String url, ApiClient api) {
  Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _ImageViewerScreen(url: url, api: api),
    ),
  );
}

class _ImageViewerScreen extends StatelessWidget {
  const _ImageViewerScreen({required this.url, required this.api});
  final String url;
  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.canvas,
      appBar: AppBar(
        backgroundColor: Brand.canvas,
        elevation: 0,
        iconTheme: const IconThemeData(color: Brand.paper),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 4,
          child: CachedNetworkImage(
            imageUrl: url,
            httpHeaders: api.authHeaders(),
            placeholder: (_, __) => const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Brand.signal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FileAttachment extends StatefulWidget {
  const _FileAttachment({
    required this.attachment,
    required this.api,
    required this.service,
  });
  final Attachment attachment;
  final ApiClient api;
  final ChatService service;

  @override
  State<_FileAttachment> createState() => _FileAttachmentState();
}

class _FileAttachmentState extends State<_FileAttachment> {
  bool _busy = false;

  IconData get _icon {
    final m = widget.attachment.mimeType;
    if (m == 'application/pdf') return Icons.picture_as_pdf_outlined;
    if (m.contains('word')) return Icons.description_outlined;
    if (m.contains('sheet') || m.contains('excel')) {
      return Icons.table_chart_outlined;
    }
    if (m.contains('presentation') || m.contains('powerpoint')) {
      return Icons.slideshow_outlined;
    }
    if (m.startsWith('text/')) return Icons.notes_outlined;
    return Icons.insert_drive_file_outlined;
  }

  Future<void> _open() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // Download to a temp file with the session cookie, then hand to the
      // OS default handler. Open succeeds even if the browser isn't logged in.
      final url = widget.service.attachmentUrl(widget.attachment.id);
      final response = await http.get(
        Uri.parse(url),
        headers: widget.api.authHeaders(),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (mounted) _toast('DOWNLOAD FAILED');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/chat_${widget.attachment.id}_${widget.attachment.originalName}';
      final f = File(path);
      await f.writeAsBytes(response.bodyBytes, flush: true);
      final result = await OpenFilex.open(path);
      if (result.type != ResultType.done && mounted) {
        _toast('NO APP TO OPEN ${widget.attachment.mimeType}');
      }
    } catch (_) {
      if (mounted) _toast('DOWNLOAD FAILED');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: _open,
      child: Container(
        constraints: const BoxConstraints(minWidth: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Brand.surface,
          border: Border.all(color: Brand.rule, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon, size: 22, color: Brand.signal),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.attachment.originalName,
                    style: text.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(widget.attachment.formattedSize(),
                      style: text.labelMedium),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Brand.signal,
                    ),
                  )
                : const Icon(Icons.download_outlined,
                    size: 18, color: Brand.paperDim),
          ],
        ),
      ),
    );
  }
}

/// Small "Alice is typing…" / "Alice and Bob are typing…" strip shown above
/// the composer. Animated ellipsis keeps it from feeling static without
/// pulling in a full animation framework.
class _TypingStrip extends StatefulWidget {
  const _TypingStrip({required this.names});
  final List<String> names;

  @override
  State<_TypingStrip> createState() => _TypingStripState();
}

class _TypingStripState extends State<_TypingStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _describe(List<String> names) {
    if (names.isEmpty) return '';
    if (names.length == 1) return '${names.first} is typing';
    if (names.length == 2) return '${names[0]} and ${names[1]} are typing';
    return '${names.first} and ${names.length - 1} others are typing';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          const SizedBox(width: 16),
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) {
              final dots = (_ctrl.value * 3).floor() + 1;
              return Text(
                '·' * dots,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Brand.signal,
                    ),
              );
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _describe(widget.names).toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

String _shortTime(String iso) {
  if (iso.isEmpty) return '';
  try {
    final dt = DateTime.parse(iso.replaceAll(' ', 'T'));
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  } catch (_) {
    return '';
  }
}

