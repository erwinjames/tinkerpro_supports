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
import '../platform_info.dart';
import '../models/chat_models.dart';
import '../services/call_service.dart';
import '../services/chat_prefs.dart';
import '../services/chat_realtime.dart';
import '../services/chat_service.dart';
import '../services/chat_state.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'accept_ticket_dialog.dart';
import 'chat_participants_screen.dart';

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

  final Conversation? conversation;
  final int myUserId;
  final ChatService service;
  final ChatRealtimeService realtime;
  final ApiClient api;
  final ChatPrefs chatPrefs;

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

  final List<_PendingAttachment> _pending = [];

  final Map<int, TicketStatusInfo> _ticketStatuses = {};
  final Set<int> _ticketBusy = {};
  bool _ticketRefreshing = false;

  final Set<String> _seenMessageKeys = {};
  bool _seededMessageKeys = false;

  static String _messageKey(Message m) => m.clientNonce.isNotEmpty
      ? 'n:${m.clientNonce}'
      : 'i:${m.id ?? m.createdAt}';

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

    widget.realtime.currentlyViewedConv.value = widget.conversationId;

    widget.realtime.onlineUsers.addListener(_onPresenceChange);

    widget.chatPrefs.addListener(_onPresenceChange);
  }

  void _onPresenceChange() {
    if (mounted) setState(() {});
  }

  String? _lastComposerText;
  void _onComposerChanged() {
    if (!mounted) return;
    setState(() {});

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

      _refreshTicketStatuses();
    }
  }

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

  bool get _identifiesSenders {
    final conv = widget.conversation;
    if (conv == null) return _thread.detail?.type != 'dm';
    return conv.type != 'dm' || conv.isExternal;
  }

  bool _isPageSender(ConversationMember? member) =>
      member != null && member.username.startsWith('fb_ai_');

  bool _isStaff(ConversationMember? member) =>
      member != null &&
      member.role != 'customer' &&
      member.role != 'guest' &&
      !member.username.startsWith('fb_');

  _BubbleTone _toneFor(ConversationMember? member) {
    if (_isPageSender(member)) return _BubbleTone.page;
    if (_isStaff(member)) return _BubbleTone.agent;
    return _BubbleTone.peer;
  }

  String? _senderTag(ConversationMember? member) {
    if (member == null) return null;
    if (_isPageSender(member)) return 'PAGE';
    if (_isStaff(member)) return 'AGENT';
    return null;
  }

  Map<int, ConversationMember> get _memberById => {
    for (final m in _thread.detail?.participants ?? const []) m.id: m,
  };

  String? _avatarUrl(String? relPath) {
    if (relPath == null || relPath.isEmpty) return null;
    final clean = relPath.replaceAll(RegExp(r'^/+'), '');
    return '${widget.api.baseUrl}/$clean';
  }

  Future<void> _moveToInbox() async {
    final ok = await widget.service.moveRequestToInbox(widget.conversationId);
    if (!mounted) return;
    _toast(
      ok
          ? 'Moved to inbox — the support team can see it now'
          : 'Could not move this conversation',
    );
    if (ok) setState(() {});
  }

  Future<void> _acceptTicket(int ticketId) async {
    if (_ticketBusy.contains(ticketId)) return;

    final choice = await AcceptTicketDialog.show(
      context,
      ticketId: ticketId,
      conversationId: widget.conversationId,
      service: widget.service,
    );
    if (choice == null || !mounted) return;

    setState(() => _ticketBusy.add(ticketId));
    final ok = await widget.service.acceptTicket(
      ticketId,
      widget.myUserId,
      alias: choice.alias,
      saveAliasDefault: choice.saveDefault,
      greetingMessage: choice.greetingMessage,
    );
    if (!mounted) return;
    setState(() => _ticketBusy.remove(ticketId));
    _toast(
      ok
          ? 'Ticket ${formatTicketNo(ticketId)} accepted'
          : 'Could not accept ticket',
    );
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
      backgroundColor: context.brand.surface,
      isScrollControlled: true,
      builder: (_) => _TicketDetailSheet(detail: detail),
    );
  }

  ({int id, TicketStatusInfo status})? _activeTicket() {
    for (final m in _thread.messages) {
      final ref = detectTicketRef(m.body);
      if (ref == null) continue;
      final st = _ticketStatuses[ref.id];
      if (st == null || st.isClosed) continue;
      return (id: ref.id, status: st);
    }
    return null;
  }

  String _ticketStatusLabel(TicketStatusInfo st) {
    if (st.isNew) return 'New';
    if (st.isInProgress) return 'In progress';
    if (st.isResolved) return 'Resolved';
    return 'Closed';
  }

  void _markNewestRead() {
    if (_thread.messages.isEmpty) return;
    final newest = _thread.messages.first;
    final id = newest.id;
    if (id == null) return;
    _thread.scheduleMarkRead(id);
  }

  void _maybeLoadOlder() {
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

  Message? _replyTo;

  bool get _chatLocked {
    final conv = widget.conversation;
    if (conv == null) return false;
    if (!_isCustomerSupportThread(conv)) return false;
    return !_hasFiledTicket();
  }

  bool _isCustomerSupportThread(Conversation conv) {
    final topic = conv.topic?.trim().toLowerCase() ?? '';
    return topic.startsWith('customer:') || topic.startsWith('guest:');
  }

  bool _hasFiledTicket() {
    for (final m in _thread.messages) {
      if (detectTicketRef(m.body) != null) return true;
    }
    return false;
  }

  bool get _canQuoteReply {
    final conv = widget.conversation;
    if (conv != null) return !conv.isFacebook;
    return _thread.detail?.source != 'facebook';
  }

  String _quotePrefix(Message target) {
    final quoted = parseQuotedBody(target.body);
    final cleaned = (quoted?.reply ?? target.body).trim();
    var preview = cleaned.replaceAll(RegExp(r'\s+'), ' ');
    if (preview.length > 200) preview = preview.substring(0, 200);
    if (preview.isEmpty) {
      preview = target.attachments.isNotEmpty ? '[attachment]' : '';
    }
    final sender = target.senderAlias.isNotEmpty
        ? target.senderAlias
        : (_memberById[target.senderId]?.displayName ?? 'them');
    final idTag = target.id != null ? ' [#${target.id}]' : '';
    return '> @$sender$idTag: $preview\n\n';
  }

  Future<void> _handleSend() async {
    if (!_canSend) return;
    final target = _replyTo;
    final text = target == null
        ? _composer.text
        : _quotePrefix(target) + _composer.text;
    final ready = _pending
        .where((p) => p.status == _UploadStatus.ready)
        .map((p) => p.attachment!)
        .toList(growable: false);
    setState(() {
      _composer.clear();
      _replyTo = null;
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

  static const _callableRoles = {'admin', 'super_admin', 'user'};

  bool get _peerCallable {
    final role = widget.conversation?.peer?.role.trim().toLowerCase();
    return role != null && _callableRoles.contains(role);
  }

  bool get _isMultiparty {
    final t = widget.conversation?.type;
    return t == 'group' || t == 'channel';
  }

  Future<void> _placeCall(CallMedia media) async {
    final calls = widget.calls;
    final conv = widget.conversation;
    if (calls == null) return;
    if (conv == null) return;
    if (!_isMultiparty && (conv.type != 'dm' || conv.peer == null)) {
      _toast('Calls are DM-only for now');
      return;
    }
    if (!_isMultiparty && !_peerCallable) {
      _toast('Calls aren\'t available for this user');
      return;
    }

    if (calls.isInLiveCall) {
      _toast('Already in a call');
      return;
    }
    if (calls.isIncomingRinging) {
      _toast('Answer incoming call first');
      return;
    }
    if (calls.isActive) {
      calls.forceReset();
    }

    final bool ok;
    if (_isMultiparty) {
      final detail = await widget.service.conversation(widget.conversationId);
      if (!mounted) return;
      final members = (detail?.participants ?? [])
          .where((m) => m.id != widget.myUserId)
          .map((m) => {'id': m.id, 'name': m.displayName})
          .toList();
      if (members.isEmpty) {
        _toast('No one else in this conversation');
        return;
      }
      if (members.length > kMeshMaxPeers) {
        _toast('GROUP CALLS SUPPORT UP TO ${kMeshMaxPeers + 1} PEOPLE');
        return;
      }
      ok = await calls.placeGroupCall(
        conversationId: widget.conversationId,
        groupName: conv.name,
        members: members,
        media: media,
      );
    } else {
      ok = await calls.placeCall(
        peerId: conv.peer!.id,
        peerName: conv.peer!.displayName,
        media: media,
      );
    }
    if (!ok && mounted) {
      _toast('Could not start call');
    }
  }

  bool get _callsAllowed {
    if (_activeTicket() != null) return false;
    final conv = widget.conversation;
    if (conv != null) return !conv.isExternal;
    final detail = _thread.detail;
    if (detail != null) return !detail.isExternal;
    return false;
  }

  List<_HeaderAction> _buildHeaderActions({required bool isDm}) {
    final canCall =
        _callsAllowed &&
        widget.calls != null &&
        ((isDm && _peerCallable) || _isMultiparty);
    final actions = <_HeaderAction>[];

    final ticket = _activeTicket();
    if (ticket != null) {
      final st = ticket.status;
      final id = ticket.id;
      if (_ticketBusy.contains(id)) {
        actions.add(
          const _HeaderAction(
            icon: Icons.hourglass_top_rounded,
            label: 'Working…',
            primary: true,
          ),
        );
      } else if (st.isNew) {
        actions.add(
          _HeaderAction(
            icon: Icons.check_rounded,
            label: 'Claim ticket #$id',
            primary: true,
            onTap: () => _acceptTicket(id),
          ),
        );
      } else if (st.isInProgress && st.assignedAgentId == widget.myUserId) {
        actions.add(
          _HeaderAction(
            icon: Icons.flag_rounded,
            label: 'Resolve ticket #$id',
            primary: true,
            onTap: () => _resolveTicket(id),
          ),
        );
      }
    }

    if (canCall) {
      actions
        ..add(
          _HeaderAction(
            icon: Icons.call_rounded,
            label: 'Voice call',
            onTap: () => _placeCall(CallMedia.voice),
          ),
        )
        ..add(
          _HeaderAction(
            icon: Icons.videocam_rounded,
            label: 'Video call',
            onTap: () => _placeCall(CallMedia.video),
          ),
        );
    }

    final conv = widget.conversation;
    if (conv != null &&
        conv.isFacebook &&
        conv.fbMoved == 0 &&
        widget.api.hasPermission('chat') &&
        widget.api.hasPermission('messageRequests')) {
      actions.add(
        _HeaderAction(
          icon: Icons.move_to_inbox_rounded,
          label: 'Move to inbox',
          onTap: _moveToInbox,
        ),
      );
    }

    if (ticket != null) {
      final id = ticket.id;
      actions.add(
        _HeaderAction(
          icon: Icons.confirmation_number_rounded,
          label: 'Ticket #$id details',
          onTap: () => _openTicketDetail(id),
        ),
      );
    }

    if (!isDm && ticket == null) {
      actions.add(
        _HeaderAction(
          icon: Icons.group_rounded,
          label: 'Members',
          onTap: _openParticipants,
        ),
      );
    }
    return actions;
  }

  Future<void> _showMessageMenu(Message m) async {
    final id = m.id;
    if (id == null) return;
    final isPinned = _thread.isPinned(id);
    final choice = await showModalBottomSheet<_MsgAction>(
      context: context,
      backgroundColor: context.brand.surface,
      builder: (_) => _MessageActionSheet(
        isPinned: isPinned,
        hasBody: m.body.trim().isNotEmpty,
        canReply: _canQuoteReply,
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case _MsgAction.reply:
        setState(() => _replyTo = m);
        _composerFocus.requestFocus();
        break;
      case _MsgAction.pin:
        final ok = await _thread.pin(id);
        if (mounted && !ok) _toast('Could not pin message');
        break;
      case _MsgAction.unpin:
        final ok = await _thread.unpin(id);
        if (mounted && !ok) _toast('Could not unpin message');
        break;
      case _MsgAction.copy:
        await Clipboard.setData(ClipboardData(text: m.body));
        if (mounted) _toast('COPIED');
        break;
    }
  }

  Future<void> _showPinnedSheet() async {
    final toUnpin = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: context.brand.surface,
      isScrollControlled: true,
      builder: (_) => _PinnedListSheet(pinned: _thread.pinned),
    );
    if (!mounted || toUnpin == null) return;
    final ok = await _thread.unpin(toUnpin);
    if (mounted && !ok) _toast('Could not unpin message');
  }

  Future<void> _showAttachmentSheet() async {
    final picked = await showModalBottomSheet<_PickerChoice>(
      context: context,
      backgroundColor: context.brand.surface,
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
      _toast('Could not pick image');
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
      _toast('Could not pick file');
    }
  }

  void _enqueueUpload(File file) {
    const maxBytes = 25 * 1024 * 1024;
    final size = file.lengthSync();
    if (size <= 0 || size > maxBytes) {
      _toast('File too large — max 25 mb');
      return;
    }
    final pending = _PendingAttachment(file: file, sizeBytes: size);
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

    if (outcome.error != null && mounted) {
      _toast('Upload failed · ${outcome.error!}');
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
    final livePeerOnline =
        peer != null && widget.realtime.onlineUsers.value.contains(peer.id);
    final peerOnline = livePeerOnline || (peer?.isOnline ?? false);
    final peerLastSeen = peer == null
        ? null
        : formatLastSeen(online: peerOnline, lastSeenAt: peer.lastSeenAt);

    final headerTicket = _activeTicket();
    final subLabel = headerTicket != null
        ? 'Ticket #${headerTicket.id} · ${_ticketStatusLabel(headerTicket.status)}'
        : conv == null
        ? 'Direct message'
        : isDm
        ? (peerLastSeen ?? (peerOnline ? 'Online' : 'Offline'))
        : isChannel
        ? 'Channel · ${conv.visibility}'
        : '${conv.participantCount} members';

    final typingNames = _thread.typingNames;
    final typing = typingNames.isEmpty ? null : _describeTyping(typingNames);
    final isGroupLike = conv != null && !isDm;
    final b = context.brand;

    return Scaffold(
      backgroundColor: b.canvas,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppHeaderBand(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
            child: Row(
              children: [
                AppIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _HeaderChip(
                    child: Row(
                      children: [
                        _HeaderAvatar(
                          name: title,
                          group: isGroupLike,
                          channel: isChannel,
                          facebook: conv?.isFacebook ?? false,
                          showPresence: isDm && peer != null,
                          online: peerOnline,
                          url: _avatarUrl(peer?.avatar),
                          headers: widget.api.authHeaders(),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Semantics(
                            header: true,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                const SizedBox(height: 1),
                                AnimatedSwitcher(
                                  duration:
                                      MediaQuery.of(context).disableAnimations
                                      ? Duration.zero
                                      : const Duration(milliseconds: 200),
                                  child: Text(
                                    typing ?? subLabel,
                                    key: ValueKey(typing ?? subLabel),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: typing != null
                                              ? Brand.orange
                                              : Colors.white.withValues(
                                                  alpha: 0.75,
                                                ),
                                          fontWeight: typing != null
                                              ? FontWeight.w600
                                              : FontWeight.w500,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _HeaderActions(actions: _buildHeaderActions(isDm: isDm)),
              ],
            ),
          ),
          if (_thread.pinned.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: _PinnedBanner(
                pinned: _thread.pinned,
                onTap: _showPinnedSheet,
              ),
            ),
          Expanded(
            child: _thread.messages.isEmpty && _thread.loading
                ? const _ThreadSkeleton()
                : _thread.messages.isEmpty
                ? const EmptyState(
                    icon: Icons.forum_rounded,
                    label: 'No messages yet',
                    hint: 'Say something to get the conversation going.',
                  )
                : Builder(
                    builder: (_) {
                      final msgs = _thread.messages;

                      final fresh = <String>{};
                      for (final m in msgs) {
                        final key = _messageKey(m);
                        if (_seenMessageKeys.add(key) && _seededMessageKeys) {
                          fresh.add(key);
                        }
                      }
                      _seededMessageKeys = true;

                      final myNewestIndex = msgs.indexWhere(
                        (m) => m.senderId == widget.myUserId,
                      );
                      return ListView.builder(
                        controller: _scroll,
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                        itemCount: msgs.length + (_thread.hasMore ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (i == msgs.length) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
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

                          final groupedBelow =
                              i > 0 && _isGrouped(msgs[i], msgs[i - 1]);

                          final above = i + 1 < msgs.length
                              ? msgs[i + 1]
                              : null;
                          final startsRun =
                              above == null ||
                              above.senderId != m.senderId ||
                              !_sameDay(m.createdAt, above.createdAt);
                          final member = _memberById[m.senderId];

                          final isOldestOfDay =
                              i == msgs.length - 1 ||
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
                            showSender: _identifiesSenders,
                            startsRun: startsRun,
                            tone: mine ? _BubbleTone.mine : _toneFor(member),
                            senderTag: _senderTag(member),
                            senderName: m.senderAlias.isNotEmpty
                                ? m.senderAlias
                                : (member?.displayName ?? ''),
                            senderAvatarUrl: _avatarUrl(member?.avatar),
                            api: widget.api,
                            service: widget.service,
                            onRetry: m.status == MessageStatus.failed
                                ? () => _thread.retry(m)
                                : null,
                          );

                          if (m.id != null) {
                            bubble = GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onLongPress: () => _showMessageMenu(m),
                              child: bubble,
                            );
                          }

                          if (isOldestOfDay) {
                            bubble = Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _DateSeparator(iso: m.createdAt),
                                bubble,
                              ],
                            );
                          }

                          return _MessageAppear(
                            animate: i < 4 && fresh.contains(_messageKey(m)),
                            fromRight: mine,
                            child: bubble,
                          );
                        },
                      );
                    },
                  ),
          ),
          _TypingDots(label: typing),
          _Composer(
            controller: _composer,
            focusNode: _composerFocus,
            canSend: _canSend,
            locked: _chatLocked,
            replyTo: _replyTo,
            replyToName: _replyTo == null
                ? null
                : (_replyTo!.senderAlias.isNotEmpty
                      ? _replyTo!.senderAlias
                      : (_memberById[_replyTo!.senderId]?.displayName ??
                            'message')),
            onCancelReply: () => setState(() => _replyTo = null),
            onSend: _handleSend,
            onAttach: _showAttachmentSheet,
            pending: _pending.isEmpty
                ? null
                : _PendingStrip(
                    pending: _pending,
                    onRetry: _retryUpload,
                    onRemove: _removePending,
                  ),
          ),
        ],
      ),
    );
  }
}

String _describeTyping(List<String> names) {
  if (names.isEmpty) return '';
  if (names.length == 1) return '${names.first} is typing…';
  if (names.length == 2) return '${names[0]} and ${names[1]} are typing…';
  return '${names.first} and ${names.length - 1} others are typing…';
}

class _HeaderAction {
  const _HeaderAction({
    required this.icon,
    required this.label,
    this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;
}

class _HeaderActions extends StatelessWidget {
  const _HeaderActions({required this.actions});

  final List<_HeaderAction> actions;

  static const int _maxVisible = 3;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    final overflow = actions.length > _maxVisible;
    final visible = overflow ? actions.take(_maxVisible - 1).toList() : actions;
    final hidden = overflow
        ? actions.skip(_maxVisible - 1).toList()
        : const <_HeaderAction>[];
    final children = <Widget>[];
    for (final a in visible) {
      if (children.isNotEmpty) children.add(const SizedBox(width: 8));
      children.add(
        a.primary
            ? _PrimaryHeaderButton(action: a)
            : AppIconButton(icon: a.icon, tooltip: a.label, onPressed: a.onTap),
      );
    }
    if (hidden.isNotEmpty) {
      children
        ..add(const SizedBox(width: 8))
        ..add(
          PopupMenuButton<int>(
            tooltip: 'More actions',
            position: PopupMenuPosition.under,
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.12),
              foregroundColor: Colors.white,
              fixedSize: const Size(44, 44),
              minimumSize: const Size(44, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Brand.radius),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
              ),
            ),
            icon: const Icon(
              Icons.more_vert_rounded,
              size: 21,
              color: Colors.white,
            ),
            onSelected: (i) => hidden[i].onTap?.call(),
            itemBuilder: (_) => [
              for (var i = 0; i < hidden.length; i++)
                PopupMenuItem<int>(
                  value: i,
                  enabled: hidden[i].onTap != null,
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(hidden[i].icon, size: 20),
                    title: Text(hidden[i].label),
                  ),
                ),
            ],
          ),
        );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}

class _PrimaryHeaderButton extends StatelessWidget {
  const _PrimaryHeaderButton({required this.action});

  final _HeaderAction action;

  @override
  Widget build(BuildContext context) {
    final enabled = action.onTap != null;
    return Tooltip(
      message: action.label,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: action.label,
        child: Material(
          color: enabled ? Brand.orange : Colors.white.withValues(alpha: 0.12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Brand.radius),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: action.onTap,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(
                action.icon,
                size: 21,
                color: enabled
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.6),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderAvatar extends StatelessWidget {
  const _HeaderAvatar({
    required this.name,
    required this.group,
    required this.channel,
    required this.facebook,
    required this.showPresence,
    required this.online,
    required this.headers,
    this.url,
  });

  static const double _size = 40;
  static const Color _fbBlue = Color(0xFF0866FF);

  final String name;
  final bool group;
  final bool channel;
  final bool facebook;
  final bool showPresence;
  final bool online;
  final String? url;
  final Map<String, String> headers;

  @override
  Widget build(BuildContext context) {
    final Widget base = group && !facebook
        ? Container(
            width: _size,
            height: _size,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: Icon(
              channel ? Icons.tag_rounded : Icons.group_rounded,
              size: 20,
              color: Colors.white,
            ),
          )
        : Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.35),
                width: 1.5,
              ),
            ),
            child: AppAvatar(
              name: name.isEmpty ? '?' : name,
              size: _size - 3,
              imageUrl: url,
              headers: headers,
            ),
          );
    Widget? badge;
    if (facebook) {
      badge = Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: _fbBlue,
          shape: BoxShape.circle,
          border: Border.all(color: Brand.navy, width: 2),
        ),
        child: const Icon(
          Icons.facebook_rounded,
          size: 11,
          color: Colors.white,
        ),
      );
    } else if (showPresence) {
      badge = Container(
        width: 13,
        height: 13,
        decoration: BoxDecoration(
          color: online ? Brand.success : const Color(0xFF8A99AD),
          shape: BoxShape.circle,
          border: Border.all(color: Brand.navy, width: 2.5),
        ),
      );
    }
    return ExcludeSemantics(
      child: SizedBox(
        width: _size,
        height: _size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            base,
            if (badge != null) Positioned(right: -1, bottom: -1, child: badge),
          ],
        ),
      ),
    );
  }
}

class _ThreadSkeleton extends StatelessWidget {
  const _ThreadSkeleton();

  static const _rows = [
    (false, 180.0, 40.0),
    (true, 140.0, 40.0),
    (false, 230.0, 58.0),
    (true, 200.0, 40.0),
    (false, 120.0, 40.0),
    (true, 240.0, 58.0),
    (false, 170.0, 40.0),
    (true, 110.0, 40.0),
  ];

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading messages',
      child: ListView(
        reverse: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        children: [
          for (final (mine, width, height) in _rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisAlignment: mine
                    ? MainAxisAlignment.end
                    : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!mine) ...[
                    const Skeleton(width: 30, height: 30, radius: 15),
                    const SizedBox(width: 8),
                  ],
                  Skeleton(width: width, height: height, radius: 18),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

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
      height: 84,
      padding: const EdgeInsets.only(bottom: 10),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: pending.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
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
    final b = context.brand;
    const size = 64.0;
    final radius = BorderRadius.circular(12);
    return SizedBox(
      width: size + 10,
      height: size + 10,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            bottom: 0,
            child: Container(
              width: size,
              height: size,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: b.surfaceHi,
                borderRadius: radius,
                border: Border.all(color: b.rule, width: 1),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  pending.isImage
                      ? Image.file(
                          pending.file,
                          fit: BoxFit.cover,
                          excludeFromSemantics: true,
                        )
                      : Center(
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Text(
                              pending.displayName,
                              style: text.labelSmall,
                              textAlign: TextAlign.center,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                  if (pending.status == _UploadStatus.uploading)
                    Container(
                      color: b.canvas.withValues(alpha: 0.55),
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
                  if (pending.status == _UploadStatus.failed)
                    Material(
                      color: b.canvas.withValues(alpha: 0.65),
                      child: InkWell(
                        onTap: onRetry,
                        child: const Center(
                          child: Icon(
                            Icons.refresh_rounded,
                            color: Brand.danger,
                            size: 24,
                            semanticLabel: 'Retry upload',
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: Tooltip(
              message: 'Remove',
              child: Semantics(
                button: true,
                label: 'Remove attachment',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onRemove,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: b.paper,
                      shape: BoxShape.circle,
                      border: Border.all(color: b.surface, width: 2),
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      size: 13,
                      color: b.surface,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _PickerChoice { camera, gallery, file }

enum _MsgAction { reply, pin, unpin, copy }

class _PinnedBanner extends StatelessWidget {
  const _PinnedBanner({required this.pinned, required this.onTap});

  final List<PinnedMessage> pinned;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final latest = pinned.first;
    final extra = pinned.length - 1;
    final preview = latest.body.trim().isEmpty
        ? 'Attachment'
        : latest.body.trim().replaceAll('\n', ' ');
    return AppCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              children: [
                IconTile(icon: Icons.push_pin_rounded, size: 34, iconSize: 17),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        extra > 0 ? 'Pinned · ${pinned.length}' : 'Pinned',
                        style: text.labelMedium?.copyWith(
                          color: b.signalInk,
                          fontWeight: FontWeight.w700,
                        ),
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
                Icon(Icons.chevron_right_rounded, size: 20, color: b.paperDim),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetTitle extends StatelessWidget {
  const _SheetTitle(this.label, {this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: context.brand.signal),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.titleMedium),
          ),
        ],
      ),
    );
  }
}

class _MessageActionSheet extends StatelessWidget {
  const _MessageActionSheet({
    required this.isPinned,
    required this.hasBody,
    required this.canReply,
  });

  final bool isPinned;
  final bool hasBody;
  final bool canReply;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _SheetTitle('Message'),
            const Hairline(),
            if (canReply)
              ListTile(
                leading: Icon(
                  Icons.reply_rounded,
                  color: context.brand.paper,
                  size: 20,
                ),
                title: const Text('Reply'),
                onTap: () => Navigator.of(context).pop(_MsgAction.reply),
              ),
            if (isPinned)
              ListTile(
                leading: Icon(
                  Icons.push_pin_rounded,
                  color: context.brand.paper,
                  size: 20,
                ),
                title: const Text('Unpin message'),
                onTap: () => Navigator.of(context).pop(_MsgAction.unpin),
              )
            else
              ListTile(
                leading: Icon(
                  Icons.push_pin_rounded,
                  color: context.brand.paper,
                  size: 20,
                ),
                title: const Text('Pin message'),
                onTap: () => Navigator.of(context).pop(_MsgAction.pin),
              ),
            if (hasBody)
              ListTile(
                leading: Icon(
                  Icons.copy_rounded,
                  color: context.brand.paper,
                  size: 20,
                ),
                title: const Text('Copy text'),
                onTap: () => Navigator.of(context).pop(_MsgAction.copy),
              ),
          ],
        ),
      ),
    );
  }
}

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
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _SheetTitle('Pinned messages', icon: Icons.push_pin_rounded),
            const Hairline(),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: pinned.length,
                separatorBuilder: (_, _) => const Hairline(),
                itemBuilder: (_, i) {
                  final p = pinned[i];
                  final body = p.body.trim().isEmpty
                      ? 'Attachment'
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
                      style: text.labelSmall?.copyWith(
                        color: context.brand.paperDim,
                      ),
                    ),
                    trailing: IconButton(
                      tooltip: 'Unpin',
                      icon: const Icon(
                        Icons.push_pin_rounded,
                        color: Brand.signal,
                        size: 20,
                      ),
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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _SheetTitle('Attach'),
            const Hairline(),
            if (kIsMobilePlatform) ...[
              ListTile(
                leading: Icon(
                  Icons.camera_alt_rounded,
                  color: context.brand.paper,
                  size: 20,
                ),
                title: const Text('Camera'),
                onTap: () => Navigator.of(context).pop(_PickerChoice.camera),
              ),
              ListTile(
                leading: Icon(
                  Icons.image_rounded,
                  color: context.brand.paper,
                  size: 20,
                ),
                title: const Text('Gallery'),
                onTap: () => Navigator.of(context).pop(_PickerChoice.gallery),
              ),
            ],
            ListTile(
              leading: Icon(
                Icons.attach_file_rounded,
                color: context.brand.paper,
                size: 20,
              ),
              title: const Text('File'),
              onTap: () => Navigator.of(context).pop(_PickerChoice.file),
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.canSend,
    required this.locked,
    required this.onSend,
    required this.onAttach,
    this.replyTo,
    this.replyToName,
    this.onCancelReply,
    this.pending,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool canSend;

  final bool locked;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final Message? replyTo;
  final String? replyToName;
  final VoidCallback? onCancelReply;
  final Widget? pending;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(22);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: b.surface,
        border: Border(
          top: BorderSide(
            color: b.isDark ? Colors.white.withValues(alpha: 0.10) : b.rule,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ?pending,
              if (replyTo != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: b.surfaceHi,
                    borderRadius: BorderRadius.circular(Brand.radius),
                    border: Border.all(color: b.rule),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(width: 3, color: b.signal),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.reply_rounded,
                                  size: 18,
                                  color: b.signalInk,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Replying to ${replyToName ?? 'message'}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: text.labelMedium?.copyWith(
                                          color: b.signalInk,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _replyPreview(replyTo!).isEmpty
                                            ? 'Original message'
                                            : _replyPreview(replyTo!),
                                        style: text.bodySmall,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Cancel reply',
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                  ),
                                  onPressed: onCancelReply,
                                  style: IconButton.styleFrom(
                                    foregroundColor: b.paperDim,
                                    minimumSize: const Size(44, 44),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (locked)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: b.surfaceHi,
                    borderRadius: BorderRadius.circular(Brand.radius),
                    border: Border.all(color: b.rule),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 18,
                        color: b.paperDim,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Messaging unlocks once the customer files a ticket.',
                          style: text.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Tooltip(
                    message: 'Attach',
                    child: Material(
                      color: b.surfaceHi,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: locked ? null : onAttach,
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Icon(
                            Icons.add_rounded,
                            size: 24,
                            semanticLabel: 'Attach',
                            color: locked
                                ? b.paperDim.withValues(alpha: 0.5)
                                : b.paper,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      enabled: !locked,
                      maxLines: 5,
                      minLines: 1,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: locked ? 'Messaging locked' : 'Message',
                        isDense: true,
                        filled: true,
                        fillColor: b.surfaceHi,
                        constraints: const BoxConstraints(minHeight: 44),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: radius,
                          borderSide: BorderSide(color: b.rule),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: radius,
                          borderSide: BorderSide(color: b.rule),
                        ),
                        disabledBorder: OutlineInputBorder(
                          borderRadius: radius,
                          borderSide: BorderSide(color: b.rule),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: radius,
                          borderSide: BorderSide(color: b.signal, width: 1.5),
                        ),
                      ),
                      style: text.bodyLarge,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _SendButton(enabled: canSend, onPressed: onSend),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final reduce = MediaQuery.of(context).disableAnimations;
    return Tooltip(
      message: 'Send',
      child: Semantics(
        button: true,
        enabled: enabled,
        label: 'Send',
        child: AnimatedScale(
          duration: reduce ? Duration.zero : const Duration(milliseconds: 180),
          curve: Curves.easeOutBack,
          scale: enabled ? 1 : 0.92,
          child: AnimatedContainer(
            duration: reduce
                ? Duration.zero
                : const Duration(milliseconds: 180),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: enabled ? Brand.orange : brand.surfaceHi,
              shape: BoxShape.circle,
            ),
            child: Material(
              type: MaterialType.transparency,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: enabled ? onPressed : null,
                child: Icon(
                  Icons.send_rounded,
                  size: 20,
                  color: enabled ? Colors.white : brand.paperDim,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _replyPreview(Message m) {
  final quoted = parseQuotedBody(m.body);
  final raw = (quoted?.reply ?? m.body).trim().replaceAll(RegExp(r'\s+'), ' ');
  if (raw.isNotEmpty) return raw;
  return m.attachments.isNotEmpty ? '[attachment]' : '';
}

enum _BubbleTone { mine, page, agent, peer }

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
    this.showSender = false,
    this.startsRun = true,
    this.tone = _BubbleTone.peer,
    this.senderTag,
    this.senderName = '',
    this.senderAvatarUrl,
    this.onRetry,
  });

  final Message message;
  final bool mine;
  final ChatTheme theme;
  final bool isNewestMine;

  final bool pinned;

  final bool suppressMeta;

  final bool grouped;

  final Map<int, int> readCursors;

  final int otherParticipantCount;

  final bool showSender;
  final bool startsRun;

  final _BubbleTone tone;

  final String? senderTag;
  final String senderName;
  final String? senderAvatarUrl;

  bool get showSenderHeader => startsRun;

  final ApiClient api;
  final ChatService service;
  final VoidCallback? onRetry;

  Color get _tagColour =>
      tone == _BubbleTone.page ? Brand.pageVoice : theme.accent;

  Color get _onMine =>
      theme.mineBorder.computeLuminance() > 0.5 ? Brand.navy : Colors.white;

  BorderRadius get _bubbleRadius {
    const r = Radius.circular(18);
    const tail = Radius.circular(6);
    final tailed = !grouped;
    return BorderRadius.only(
      topLeft: r,
      topRight: r,
      bottomLeft: !mine && tailed ? tail : r,
      bottomRight: mine && tailed ? tail : r,
    );
  }

  Color _bubbleFill(BuildContext context) {
    if (tone == _BubbleTone.mine) return theme.mineBorder;
    final tint = switch (tone) {
      _BubbleTone.mine => theme.mineBg,
      _BubbleTone.page => Brand.pageVoice.withValues(alpha: 0.22),
      _BubbleTone.agent => context.brand.surfaceHi,
      _BubbleTone.peer => context.brand.surface,
    };
    return Color.alphaBlend(tint, context.brand.canvas);
  }

  List<BoxShadow> _bubbleShadow(BuildContext context) => context.brand.shadow;

  Color _bubbleBorder(BuildContext context) => switch (tone) {
    _BubbleTone.mine => theme.mineBorder,
    _BubbleTone.page => Brand.pageVoice,
    _BubbleTone.agent => context.brand.paperDim.withValues(alpha: 0.55),
    _BubbleTone.peer => context.brand.rule,
  };

  String? get _seenLabel {
    if (!isNewestMine) return null;
    final mid = message.id;
    if (mid == null) return null;
    if (otherParticipantCount <= 0) return null;
    final seenCount = readCursors.values
        .where((cursor) => cursor >= mid)
        .length;
    if (seenCount <= 0) return null;
    if (otherParticipantCount == 1) return 'Seen';
    return 'Seen by $seenCount';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final align = mine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final hasBody = message.body.trim().isNotEmpty;
    final quoted = parseQuotedBody(message.body);
    final bubbleText = (quoted?.reply ?? message.body).trim();
    final seen = _seenLabel;

    final gutter = showSender && !mine;

    return Padding(
      padding: EdgeInsets.only(
        top: grouped ? 1 : 6,
        bottom: suppressMeta ? 1 : 6,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (gutter) ...[
            SizedBox(
              width: 30,
              child: showSenderHeader
                  ? _SenderAvatar(
                      name: senderName,
                      url: senderAvatarUrl,
                      headers: api.authHeaders(),
                    )
                  : null,
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: align,
              children: [
                if (gutter && showSenderHeader && senderName.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 2, bottom: 3),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            senderName,
                            style: text.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: context.brand.paperDim,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (senderTag != null) ...[
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: _tagColour.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              senderTag!,
                              style: text.labelMedium?.copyWith(
                                fontSize: 9.5,
                                height: 1.3,
                                fontWeight: FontWeight.w700,
                                color: _tagColour,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                if (message.attachments.isNotEmpty) ...[
                  _AttachmentList(
                    message: message,
                    mine: mine,
                    api: api,
                    service: service,
                  ),
                  if (hasBody) const SizedBox(height: 6),
                ],
                if (hasBody) ...[
                  if (quoted != null) ...[
                    Transform.translate(
                      offset: const Offset(0, 10),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.68,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Color.alphaBlend(
                              context.brand.surfaceHi.withValues(alpha: 0.75),
                              context.brand.canvas,
                            ),
                            borderRadius: BorderRadius.circular(14),
                            border: Border(
                              left: BorderSide(
                                color: mine
                                    ? theme.mineBorder
                                    : context.brand.paperDim,
                                width: 3,
                              ),
                            ),
                          ),
                          child: Text(
                            quoted.preview,
                            style: text.bodySmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (bubbleText.isNotEmpty)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.78,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: _bubbleFill(context),
                          borderRadius: _bubbleRadius,
                          border: Border.all(
                            color: _bubbleBorder(context),
                            width: 1,
                          ),
                          boxShadow: _bubbleShadow(context),
                        ),
                        child: Text(
                          bubbleText,
                          style: text.bodyLarge?.copyWith(
                            color: mine ? _onMine : null,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ),
                ],
                if (pinned)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(
                      mainAxisAlignment: mine
                          ? MainAxisAlignment.end
                          : MainAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.push_pin_rounded,
                          size: 11,
                          color: theme.accent,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          'Pinned',
                          style: text.labelSmall?.copyWith(color: theme.accent),
                        ),
                      ],
                    ),
                  ),
                if (!suppressMeta) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: mine
                        ? MainAxisAlignment.end
                        : MainAxisAlignment.start,
                    children: [
                      if (message.status == MessageStatus.sending) ...[
                        Icon(
                          Icons.schedule_rounded,
                          size: 12,
                          color: context.brand.paperDim,
                        ),
                        const SizedBox(width: 4),
                        Text('Sending…', style: text.labelMedium),
                      ] else if (message.status == MessageStatus.failed)
                        InkWell(
                          onTap: onRetry,
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 8,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.error_outline_rounded,
                                  size: 14,
                                  color: Brand.danger,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Failed · Tap to retry',
                                  style: text.labelMedium?.copyWith(
                                    color: Brand.danger,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else if (message.fbUndelivered) ...[
                        Icon(
                          Icons.error_outline_rounded,
                          size: 12,
                          color: Brand.danger,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          message.fbDelivery == 'blocked'
                              ? 'Not sent — assistant owns this thread'
                              : 'Not delivered to Messenger',
                          style: text.labelMedium?.copyWith(
                            color: Brand.danger,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _shortTime(message.createdAt),
                          style: text.labelMedium,
                        ),
                      ] else ...[
                        Text(
                          _shortTime(message.createdAt),
                          style: text.labelMedium,
                        ),
                        if (seen != null) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.done_all_rounded,
                            size: 13,
                            color: theme.accent,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            seen,
                            style: text.labelMedium?.copyWith(
                              color: theme.accent,
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SenderAvatar extends StatelessWidget {
  const _SenderAvatar({
    required this.name,
    required this.url,
    required this.headers,
  });

  final String name;
  final String? url;
  final Map<String, String> headers;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+'))
      ..removeWhere((p) => p.isEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final fallback = Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: brand.surfaceHi, shape: BoxShape.circle),
      child: Text(
        _initials,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: brand.paperDim,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    final src = url;
    if (src == null || src.isEmpty) return fallback;

    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: src,
        httpHeaders: headers,
        width: 30,
        height: 30,
        fit: BoxFit.cover,
        placeholder: (_, _) => fallback,
        errorWidget: (_, _, _) => fallback,
      ),
    );
  }
}

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
      label = 'Ticket';
      bg = context.brand.surfaceHi;
      fg = context.brand.paperDim;
    } else if (st.isNew) {
      label = 'New';
      bg = Brand.signal;
      fg = context.brand.canvas;
    } else if (st.isInProgress) {
      label = st.agentName != null && st.agentName!.isNotEmpty
          ? 'In progress · ${st.agentName!}'
          : 'In progress';
      bg = Colors.transparent;
      fg = Brand.signal;
      border = Brand.signal;
    } else if (st.isResolved) {
      label = 'Resolved';
      bg = context.brand.surfaceHi;
      fg = context.brand.paperDim;
    } else {
      label = 'Closed';
      bg = context.brand.surfaceHi;
      fg = context.brand.paperDim;
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
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

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
                const Icon(
                  Icons.confirmation_number_rounded,
                  size: 18,
                  color: Brand.signal,
                ),
                const SizedBox(width: 8),
                Text('Ticket ${_fmtNo()}', style: text.labelLarge),
                const SizedBox(width: 12),
                Flexible(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _TicketPill(
                      status: TicketStatusInfo(
                        status: detail.status,
                        agentName: detail.agentName,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Hairline(),
            const SizedBox(height: 16),
            if (detail.subject.isNotEmpty) ...[
              Text(detail.subject, style: text.titleMedium ?? text.bodyLarge),
              const SizedBox(height: 8),
            ],
            if (detail.description.isNotEmpty)
              Text(detail.description, style: text.bodyMedium),
            const SizedBox(height: 16),
            _DetailRow(label: 'Priority', value: _capitalize(detail.priority)),
            if (detail.businessName != null)
              _DetailRow(label: 'Business', value: detail.businessName!),
            if (detail.customerName != null)
              _DetailRow(label: 'Customer', value: detail.customerName!),
            if (detail.agentName != null)
              _DetailRow(label: 'Agent', value: detail.agentName!),
            if (detail.createdAt != null)
              _DetailRow(label: 'Created', value: detail.createdAt!),
          ],
        ),
      ),
    );
  }
}

String _capitalize(String v) {
  final t = v.trim();
  if (t.isEmpty) return t;
  return t[0].toUpperCase() + t.substring(1).toLowerCase();
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
          SizedBox(width: 90, child: Text(label, style: text.labelMedium)),
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
    final b = context.brand;
    if (label.isEmpty) return const SizedBox(height: 14);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: b.surfaceHi,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: b.rule),
          ),
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

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
    return true;
  }
}

String _formatDaySeparator(String iso) {
  try {
    final dt = DateTime.parse(iso.replaceAll(' ', 'T'));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thatDay = DateTime(dt.year, dt.month, dt.day);
    final daysAgo = today.difference(thatDay).inDays;

    if (daysAgo == 0) return 'Today';
    if (daysAgo == 1) return 'Yesterday';
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    if (daysAgo < 7) return weekdays[dt.weekday - 1];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
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
        crossAxisAlignment: mine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
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
    final aspect =
        (attachment.width != null &&
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
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: context.brand.surfaceHi,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.brand.rule, width: 1),
            ),
            child: CachedNetworkImage(
              imageUrl: url,
              httpHeaders: api.authHeaders(),
              fit: BoxFit.cover,
              placeholder: (_, _) =>
                  const Skeleton(height: double.infinity, radius: 0),
              errorWidget: (_, _, _) => Center(
                child: Icon(
                  Icons.broken_image_rounded,
                  color: context.brand.paperDim,
                  size: 24,
                ),
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
      backgroundColor: context.brand.canvas,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppHeaderBand(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 14),
            child: Row(
              children: [
                AppIconButton(
                  icon: Icons.close_rounded,
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Photo',
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4,
                child: CachedNetworkImage(
                  imageUrl: url,
                  httpHeaders: api.authHeaders(),
                  placeholder: (_, _) => const SizedBox(
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
          ),
        ],
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
    if (m == 'application/pdf') return Icons.picture_as_pdf_rounded;
    if (m.contains('word')) return Icons.description_rounded;
    if (m.contains('sheet') || m.contains('excel')) {
      return Icons.table_chart_rounded;
    }
    if (m.contains('presentation') || m.contains('powerpoint')) {
      return Icons.slideshow_rounded;
    }
    if (m.startsWith('text/')) return Icons.notes_rounded;
    return Icons.insert_drive_file_rounded;
  }

  Future<void> _open() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final url = widget.service.attachmentUrl(widget.attachment.id);
      final response = await http.get(
        Uri.parse(url),
        headers: widget.api.authHeaders(),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (mounted) _toast('Download failed');
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
      if (mounted) _toast('Download failed');
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
      borderRadius: BorderRadius.circular(14),
      child: Container(
        constraints: const BoxConstraints(minWidth: 200, minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: context.brand.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.brand.rule, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconTile(icon: _icon, size: 36, iconSize: 19),
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
                  Text(
                    widget.attachment.formattedSize(),
                    style: text.labelMedium,
                  ),
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
                : Icon(
                    Icons.download_rounded,
                    size: 18,
                    color: context.brand.paperDim,
                  ),
          ],
        ),
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

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Brand.radiusLg),
        color: Colors.white.withValues(alpha: 0.08),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: child,
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots({required this.label});

  final String? label;

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  void _sync() {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final want = widget.label != null && !reduce;
    if (want && !_c.isAnimating) {
      _c.repeat();
    } else if (!want && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _TypingDots old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final label = widget.label;
    return AnimatedSize(
      duration: reduce ? Duration.zero : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomLeft,
      child: label == null
          ? const SizedBox(width: double.infinity, height: 0)
          : Semantics(
              liveRegion: true,
              label: label,
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: b.surface,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(18),
                          topRight: Radius.circular(18),
                          bottomRight: Radius.circular(18),
                          bottomLeft: Radius.circular(6),
                        ),
                        border: Border.all(color: b.rule),
                        boxShadow: b.shadow,
                      ),
                      child: AnimatedBuilder(
                        animation: _c,
                        builder: (context, _) {
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var i = 0; i < 3; i++) ...[
                                if (i > 0) const SizedBox(width: 5),
                                _Dot(
                                  color: b.signal,
                                  t: _c.isAnimating
                                      ? (((_c.value + 1) - i * 0.18) % 1.0)
                                      : null,
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.labelMedium?.copyWith(color: b.paperDim),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.t});

  final Color color;
  final double? t;

  @override
  Widget build(BuildContext context) {
    final phase = t == null ? 0.5 : (1 - (t! * 2 - 1).abs());
    final size = 6.0 + phase * 2.0;
    return SizedBox(
      width: 8,
      height: 10,
      child: Center(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.45 + phase * 0.55),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class _MessageAppear extends StatefulWidget {
  const _MessageAppear({
    required this.animate,
    required this.fromRight,
    required this.child,
  });

  final bool animate;
  final bool fromRight;
  final Widget child;

  @override
  State<_MessageAppear> createState() => _MessageAppearState();
}

class _MessageAppearState extends State<_MessageAppear>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: widget.animate ? 0 : 1,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.value != 1 && _c.isAnimating == false) {
      if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
        _c.value = 1;
      } else {
        _c.forward();
      }
    }
  }

  @override
  void didUpdateWidget(covariant _MessageAppear old) {
    super.didUpdateWidget(old);
    if (widget.animate && !old.animate) {
      if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
        _c.value = 1;
      } else {
        _c.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(widget.fromRight ? 0.06 : -0.06, 0.12),
          end: Offset.zero,
        ).animate(curve),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curve),
          alignment: widget.fromRight
              ? Alignment.bottomRight
              : Alignment.bottomLeft,
          child: widget.child,
        ),
      ),
    );
  }
}
