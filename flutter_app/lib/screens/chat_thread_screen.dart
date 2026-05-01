import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
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
    _thread.loadInitial().then((_) => _markNewestRead());
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
    }
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
    if (_pending.any((p) => p.status == _UploadStatus.uploading)) return false;
    final hasReady = _pending.any((p) => p.status == _UploadStatus.ready);
    return _composer.text.trim().isNotEmpty || hasReady;
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

  /// Group/channel calls require an SFU — for the MVP we only place
  /// two-party DM calls. The button is hidden in non-DM threads.
  Future<void> _placeCall(CallMedia media) async {
    final calls = widget.calls;
    final conv = widget.conversation;
    if (calls == null) return;
    if (conv == null || conv.type != 'dm' || conv.peer == null) {
      _toast('CALLS ARE DM-ONLY FOR NOW');
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
    final canCall = widget.calls != null && isDm;
    if (!canCall && isDm) return null;
    final children = <Widget>[];
    if (canCall) {
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
    if (!isDm) {
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
    final subLabel = conv == null
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

                          final bubble = _MessageBubble(
                            message: m,
                            mine: mine,
                            isNewestMine: isNewestMine,
                            suppressMeta: groupedBelow && !isNewestMine,
                            grouped: groupedBelow,
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
    required this.onSend,
    required this.onAttach,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool canSend;
  final VoidCallback onSend;
  final VoidCallback onAttach;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom > 0 ? 8 : 12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            tooltip: 'Attach',
            onPressed: onAttach,
            icon: const Icon(Icons.add, color: Brand.paper),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              maxLines: 4,
              minLines: 1,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(labelText: 'MESSAGE'),
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
    this.readCursors = const {},
    this.otherParticipantCount = 0,
    this.onRetry,
  });

  final Message message;
  final bool mine;
  final ChatTheme theme;
  final bool isNewestMine;

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

