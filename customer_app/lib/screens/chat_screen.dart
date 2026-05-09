import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../widgets/authed_image.dart';

import '../api_client.dart';
import '../models/chat_models.dart';
import '../models/customer_models.dart';
import '../services/call_service.dart';
import '../services/chat_realtime.dart';
import '../services/chat_service.dart';
import '../services/ringtone_service.dart';
import '../services/session_store.dart';
import '../services/ticket_service.dart';
import '../theme.dart';
import 'ticket_form_screen.dart';

/// Customer-facing chat thread. Mirrors the web portal's floating chat
/// panel: Messenger-style bubbles, sender label + role badge above
/// incoming messages, image previews, typing indicator, "Seen" pip, and
/// a voice call button in the header that fan-rings every admin.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.api,
    required this.customer,
    required this.chat,
    required this.realtime,
    required this.calls,
    required this.portalInfo,
    required this.store,
  });

  final ApiClient api;
  final Customer customer;
  final ChatService chat;
  final ChatRealtimeService realtime;
  final CallService? calls;
  final PortalGroupInfo? portalInfo;
  final SessionStore store;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  // Shared with the dashboard so realtime + calls keep working when this
  // screen is popped. We do NOT dispose them here — the dashboard owns
  // their lifetime.
  ChatService get _chat => widget.chat;
  ChatRealtimeService get _realtime => widget.realtime;
  CallService? get _calls => widget.calls;

  PortalGroupInfo? _info;
  final List<ChatMessage> _messages = [];
  final Map<int, DateTime> _typing = {};
  final Map<int, int> _readBy = {}; // user_id → last_read_message_id
  Timer? _typingExpire;

  StreamSubscription<ChatMessage>? _msgSub;
  StreamSubscription<TypingEvent>? _typingSub;
  StreamSubscription<MessageRead>? _readSub;
  StreamSubscription<int>? _deletedSub;
  late Set<int> _hiddenIds = widget.store.hiddenMessageIds;

  final _composer = TextEditingController();
  final _scroll = ScrollController();
  bool _hydrating = true;
  String? _hydrateError;
  int _myLastReadAcked = 0;

  /// Pre-uploaded attachments waiting to be cited on the next send.
  final List<ChatAttachment> _pendingAttachments = [];
  bool _uploading = false;
  Timer? _typingDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _composer.addListener(() => setState(() {})); // re-eval send button
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _typingExpire?.cancel();
    _typingDebounce?.cancel();
    _msgSub?.cancel();
    _typingSub?.cancel();
    _readSub?.cancel();
    _deletedSub?.cancel();
    // Don't dispose realtime / calls — they're owned by DashboardScreen
    // and need to keep running after we pop (so an incoming admin call
    // still rings while the customer's on the dashboard).
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_info == null) return;
    if (state == AppLifecycleState.resumed) {
      _realtime.resume(
          shadowUserId: _info!.meId, conversationId: _info!.conversationId);
    } else if (state == AppLifecycleState.paused) {
      _realtime.pause();
    }
  }

  Future<void> _bootstrap() async {
    // Reuse the dashboard's already-hydrated info if available — saves an
    // HTTP round-trip and avoids a flash of "loading" when the user
    // bounces between dashboard and chat.
    var info = widget.portalInfo;
    info ??= await _chat.portalGroup();
    if (!mounted) return;
    if (info == null || info.conversationId <= 0) {
      setState(() {
        _hydrating = false;
        _hydrateError =
            'Could not open the support thread. Pull to retry.';
      });
      return;
    }
    final history = await _chat.history(info.conversationId, limit: 100);
    if (!mounted) return;
    setState(() {
      _info = info;
      _messages
        ..clear()
        ..addAll(history);
      info!.readCursors.forEach((uid, cur) {
        _readBy[uid] = cur;
      });
      _hydrating = false;
    });
    _wireRealtime(info);
    _scrollToBottom();
    _maybeMarkRead();
  }

  void _wireRealtime(PortalGroupInfo info) {
    // Realtime is already connected by DashboardScreen — but if for some
    // reason it isn't (rare edge case where the dashboard's portalGroup
    // failed but ours succeeded), connect it now.
    if (!_realtime.isConnected) {
      _realtime.connect(
          shadowUserId: info.meId, conversationId: info.conversationId);
    }
    _msgSub = _realtime.messageEvents.listen(_onIncomingMessage);
    _typingSub = _realtime.typingEvents.listen(_onTyping);
    _readSub = _realtime.readEvents.listen(_onRead);
    _deletedSub = _realtime.messageDeletedEvents.listen(_onMessageDeleted);
  }

  void _onMessageDeleted(int messageId) {
    // Server announced an unsend. Drop the row from local state so the
    // bubble disappears immediately. Same code-path covers our own
    // outgoing unsend (we round-trip through the server first, then
    // Pusher delivers the deletion back to us).
    setState(() {
      _messages.removeWhere(
          (m) => m.persistedId != null && m.persistedId == messageId);
    });
  }

  void _onIncomingMessage(ChatMessage m) {
    // Same-nonce dedupe: server-confirmed copy of an optimistic message.
    final byNonce = m.clientNonce.isEmpty
        ? -1
        : _messages.indexWhere((x) => x.clientNonce == m.clientNonce);
    if (byNonce >= 0) {
      setState(() => _messages[byNonce] = m);
      _maybeMarkRead();
      return;
    }
    // Same-id dedupe.
    if (_messages.any((x) => x.persistedId != null && x.persistedId == m.persistedId)) {
      return;
    }
    setState(() => _messages.add(m));
    if (_info != null && m.senderId != _info!.meId) {
      unawaited(RingtoneService.instance.ping());
    }
    _scrollToBottom();
    _maybeMarkRead();
  }

  void _onTyping(TypingEvent ev) {
    if (_info == null || ev.conversationId != _info!.conversationId) return;
    if (ev.userId == _info!.meId) return;
    setState(() {
      _typing[ev.userId] = DateTime.now();
    });
    _typingExpire?.cancel();
    _typingExpire = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      final now = DateTime.now();
      setState(() {
        _typing.removeWhere(
            (_, ts) => now.difference(ts) > const Duration(seconds: 35) ||
                now.difference(ts) > const Duration(seconds: 4));
      });
    });
  }

  void _onRead(MessageRead ev) {
    setState(() {
      final cur = _readBy[ev.userId] ?? 0;
      if (ev.lastReadMessageId > cur) {
        _readBy[ev.userId] = ev.lastReadMessageId;
      }
    });
  }

  Future<void> _maybeMarkRead() async {
    if (_info == null || _messages.isEmpty) return;
    final last = _messages.last;
    final id = last.persistedId;
    if (id == null || id <= _myLastReadAcked) return;
    _myLastReadAcked = id;
    await _chat.markRead(_info!.conversationId, id);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  String _newNonce() {
    const A = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
    final r = Random();
    var t = DateTime.now().millisecondsSinceEpoch;
    final b = StringBuffer();
    for (var i = 0; i < 10; i++) {
      b.write(A[t & 31]);
      t = t >> 5;
    }
    for (var i = 0; i < 16; i++) {
      b.write(A[r.nextInt(32)]);
    }
    return b.toString();
  }

  Future<void> _sendMessage() async {
    if (_info == null) return;
    final body = _composer.text.trim();
    final pendingIds = _pendingAttachments.map((a) => a.id).toList();
    if (body.isEmpty && pendingIds.isEmpty) return;
    // Slash-commands hijack the send action so they never hit the wire as
    // a chat message. `/ticket` is the only one for now — opens the
    // ticket form, then posts a confirmation bubble back when the
    // submission succeeds.
    if (pendingIds.isEmpty && _isSlashCommand(body, '/ticket')) {
      _composer.clear();
      await _openTicketForm();
      return;
    }
    final nonce = _newNonce();
    final optimistic = ChatMessage(
      id: 'tmp-$nonce',
      conversationId: _info!.conversationId,
      senderId: _info!.meId,
      body: body,
      clientNonce: nonce,
      createdAt: DateTime.now().toIso8601String(),
      attachments: List.of(_pendingAttachments),
      optimistic: true,
    );
    setState(() {
      _messages.add(optimistic);
      _composer.clear();
      _pendingAttachments.clear();
    });
    _scrollToBottom();
    final saved = await _chat.send(
      convId: _info!.conversationId,
      body: body,
      clientNonce: nonce,
      attachmentIds: pendingIds,
    );
    if (!mounted) return;
    if (saved == null) {
      setState(() => _messages.removeWhere((m) => m.clientNonce == nonce));
      return;
    }
    setState(() {
      // Look up by id OR nonce so a Pusher race doesn't dup.
      final byId = saved.persistedId == null
          ? -1
          : _messages.indexWhere(
              (m) => m.persistedId == saved.persistedId);
      if (byId >= 0) {
        _messages[byId] = saved;
        return;
      }
      final byNonce = _messages.indexWhere((m) => m.clientNonce == nonce);
      if (byNonce >= 0) {
        _messages[byNonce] = saved;
      } else {
        _messages.add(saved);
      }
    });
  }

  bool _isSlashCommand(String body, String command) {
    final trimmed = body.trim();
    if (trimmed.toLowerCase() == command.toLowerCase()) return true;
    return trimmed.toLowerCase().startsWith('${command.toLowerCase()} ');
  }

  Future<void> _openTicketForm() async {
    final tickets = TicketService(widget.api);
    final outcome = await Navigator.of(context).push<TicketSubmitOutcome>(
      MaterialPageRoute(
        builder: (_) => TicketFormScreen(
          tickets: tickets,
          customer: widget.customer,
          store: widget.store,
          api: widget.api,
        ),
      ),
    );
    if (outcome == null || !mounted) return;
    // Post a confirmation back into the support thread so the customer
    // and the assigned agent both see the ticket land in chat.
    final ticketRef = outcome.ticketId != null ? ' #${outcome.ticketId}' : '';
    final note = '🎫 Ticket$ticketRef submitted: "${outcome.subject}"\n'
        'Business: ${outcome.businessName} (${outcome.vatLabel})\n'
        'Priority: ${outcome.priority.toUpperCase()}';
    _composer.text = note;
    await _sendMessage();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Ticket submitted. Support will reach out shortly.'),
      ));
    }
  }

  void _onComposerChanged(String value) {
    if (value.trim().isEmpty || _info == null) return;
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(milliseconds: 600), () {
      _chat.notifyTyping(_info!.conversationId);
    });
  }

  Future<void> _attachFile() async {
    if (_info == null) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Brand.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Brand.stroke,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            ListTile(
              leading: const Icon(Icons.image_outlined, color: Brand.signal),
              title: const Text('Photo from gallery'),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined,
                  color: Brand.signal),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading:
                  const Icon(Icons.attach_file, color: Brand.signal),
              title: const Text('Document'),
              onTap: () => Navigator.pop(context, 'file'),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
    if (action == null) return;
    File? file;
    if (action == 'gallery') {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked != null) file = File(picked.path);
    } else if (action == 'camera') {
      if (!await Permission.camera.request().isGranted) return;
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.camera);
      if (picked != null) file = File(picked.path);
    } else if (action == 'file') {
      final res = await FilePicker.platform.pickFiles();
      final p = res?.files.single.path;
      if (p != null) file = File(p);
    }
    if (file == null) return;
    setState(() => _uploading = true);
    final att = await _chat.uploadAttachment(_info!.conversationId, file);
    if (!mounted) return;
    setState(() {
      _uploading = false;
      if (att != null) _pendingAttachments.add(att);
    });
    if (att == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not upload that file.')));
    }
  }

  Future<void> _placeCall() async {
    debugPrint('[call-ui] tap voice; _info=${_info != null} _calls=${_calls != null}');
    if (_info == null) {
      _toast('Chat is still loading — try again in a moment.');
      return;
    }
    if (_calls == null) {
      _toast('Voice call is still warming up — try again in a moment.');
      return;
    }

    // permission_handler only supports Android / iOS / macOS / Windows for
    // microphone — on Linux it returns `denied` even though PulseAudio/ALSA
    // is happy to give us audio. Skip the wrapper on those platforms and
    // let getUserMedia surface the real native permission flow.
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      final status = await Permission.microphone.request();
      debugPrint('[call-ui] mic permission status=$status');
      if (!status.isGranted) {
        _toast('Microphone permission is required to make a call.');
        return;
      }
    }

    final admins = _info!.participants
        .where((p) =>
            p.userId != _info!.meId &&
            (p.role == 'admin' || p.role == 'super_admin'))
        .map((p) => (id: p.userId, name: p.displayName))
        .toList();
    debugPrint('[call-ui] candidate admins: ${admins.map((a) => '${a.id}:${a.name}').toList()}');
    if (admins.isEmpty) {
      _toast('No support staff are available to call right now.');
      return;
    }
    final ok = await _calls!.placeCall(peers: admins, media: CallMedia.voice);
    debugPrint('[call-ui] placeCall returned $ok');
    if (!ok) {
      _toast('Could not start the call. Please try again.');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      duration: const Duration(seconds: 3),
    ));
  }

  /// Long-press action sheet on a chat bubble. Two ops:
  ///   • Unsend — server-side delete (sender-only). Soketi broadcasts the
  ///     deletion so admins / other devices drop the bubble live.
  ///   • Delete for me — local hide. Persisted in SharedPreferences so
  ///     refreshing the thread keeps it hidden on this device, but
  ///     other participants are unaffected.
  Future<void> _showMessageActions(ChatMessage m, PortalGroupInfo info) async {
    // Optimistic placeholders never have a real id — there's nothing to
    // server-delete or persistently hide yet. Also nothing useful to do
    // on them, so swallow the long-press.
    if (m.persistedId == null) return;

    final mine = m.senderId == info.meId;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Brand.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Brand.stroke,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            // Unsend is sender-only — show but disable on others' bubbles
            // so the menu still reads consistently.
            ListTile(
              leading: Icon(
                Icons.undo,
                color: mine ? Brand.danger : Brand.textMuted,
              ),
              title: Text(
                'Unsend',
                style: TextStyle(
                  color: mine ? Brand.textPrimary : Brand.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                mine
                    ? 'Removes this message for everyone in the chat.'
                    : 'You can only unsend your own messages.',
                style: const TextStyle(fontSize: 12.5),
              ),
              enabled: mine,
              onTap: mine ? () => Navigator.pop(context, 'unsend') : null,
            ),
            ListTile(
              leading: const Icon(Icons.visibility_off_outlined,
                  color: Brand.textPrimary),
              title: const Text('Delete for me',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text(
                'Hides this message on this device. The other person still sees it.',
                style: TextStyle(fontSize: 12.5),
              ),
              onTap: () => Navigator.pop(context, 'hide'),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    final id = m.persistedId!;
    if (action == 'unsend') {
      // Optimistic: drop the bubble immediately. The Pusher
      // message.deleted event will arrive shortly and is a no-op
      // (already gone). On failure we put it back.
      final removed = m;
      setState(() => _messages.removeWhere(
          (x) => x.persistedId != null && x.persistedId == id));
      final ok = await _chat.deleteMessage(id);
      if (!ok && mounted) {
        setState(() {
          _messages.add(removed);
          _messages.sort((a, b) =>
              (a.persistedId ?? 0).compareTo(b.persistedId ?? 0));
        });
        _toast("Couldn't unsend that message.");
      }
    } else if (action == 'hide') {
      await widget.store.hideMessageId(id);
      if (!mounted) return;
      setState(() => _hiddenIds = widget.store.hiddenMessageIds);
    }
  }

  Future<void> _openAttachment(ChatAttachment a) async {
    final url = _chat.attachmentUrl(a.id);
    if (a.isImage) {
      // Lightweight in-app preview for images.
      Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => _ImagePreviewScreen(
            api: widget.api, url: url, title: a.originalName),
      ));
      return;
    }
    // Non-image attachments (PDF, doc, csv, etc.). v1 strategy: copy the
    // download URL to the clipboard and surface a SnackBar — the customer
    // can paste it into their browser, which already has cookie auth from
    // the portal session if they were chatting in the web portal too.
    // A future iteration can stream-download via Dio (the cookie jar is
    // shared) into a tmp file and hand to OpenFilex for a real in-app
    // open. Skipped for v1 to keep the dependency surface small.
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Download link copied: ${a.originalName}'),
      action: SnackBarAction(
        label: 'OK',
        onPressed: () =>
            ScaffoldMessenger.of(context).hideCurrentSnackBar(),
      ),
    ));
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return Scaffold(
      appBar: _buildAppBar(info),
      body: _hydrating
          ? const Center(child: CircularProgressIndicator(color: Brand.signal))
          : _hydrateError != null
              ? _ErrorPlaceholder(
                  message: _hydrateError!, onRetry: _bootstrap)
              : _buildChatBody(info!),
    );
  }

  PreferredSizeWidget _buildAppBar(PortalGroupInfo? info) {
    return AppBar(
      backgroundColor: Brand.canvas,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: const Border(bottom: BorderSide(color: Brand.stroke)),
      titleSpacing: 0,
      title: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: Brand.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.chat_bubble,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    info?.groupName ?? 'Support',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: Brand.textPrimary,
                    ),
                  ),
                  Row(
                    children: const [
                      Icon(Icons.circle, color: Brand.success, size: 8),
                      SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          'Chat with our support team',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11.5, color: Brand.textMuted),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.phone_outlined, color: Brand.signal),
          tooltip: 'Voice call support',
          onPressed: _placeCall,
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildChatBody(PortalGroupInfo info) {
    return Column(
      children: [
        Expanded(child: _buildMessageList(info)),
        _buildTypingRow(info),
        _buildPendingRow(),
        _buildComposer(),
      ],
    );
  }

  Widget _buildMessageList(PortalGroupInfo info) {
    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Brand.signalGlow(0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.waving_hand,
                    color: Brand.signal, size: 26),
              ),
              const SizedBox(height: 12),
              const Text(
                'Say hi!',
                style: TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 17),
              ),
              const SizedBox(height: 4),
              const Text(
                'Send a message to start chatting with the support team.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Brand.textMuted, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }
    final peerReadMax = _peerReadMax(info);
    // Filter out locally "Delete for me" entries before computing streak
    // positions — otherwise the gap of a hidden message would still
    // shape the bubble corners awkwardly.
    final visible = _messages
        .where((m) => m.persistedId == null || !_hiddenIds.contains(m.persistedId!))
        .toList(growable: false);
    if (visible.isEmpty && _messages.isEmpty) {
      // Already covered by the empty state above.
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      itemCount: visible.length,
      itemBuilder: (_, i) {
        final m = visible[i];
        final prev = i > 0 ? visible[i - 1] : null;
        final next = i < visible.length - 1 ? visible[i + 1] : null;
        final pos = _streakPos(m, prev, next);
        final showSeen = peerReadMax >= (m.persistedId ?? 0) &&
            m.senderId == info.meId &&
            m == _lastSeenMine(info, peerReadMax, visible);
        return GestureDetector(
          onLongPress: () => _showMessageActions(m, info),
          child: _MessageBubble(
            api: widget.api,
            chat: _chat,
            message: m,
            info: info,
            streakPos: pos,
            showSeen: showSeen,
            onAttachmentTap: _openAttachment,
          ),
        );
      },
    );
  }

  int _peerReadMax(PortalGroupInfo info) {
    var max = 0;
    _readBy.forEach((uid, v) {
      if (uid != info.meId && v > max) max = v;
    });
    return max;
  }

  /// Identity-based "last seen mine" lookup. Returns the message itself
  /// instead of an index so it works against [visible] (post-filter) just
  /// as well as the raw list.
  ChatMessage? _lastSeenMine(
      PortalGroupInfo info, int peerReadMax, List<ChatMessage> source) {
    for (var i = source.length - 1; i >= 0; i--) {
      final m = source[i];
      if (m.senderId == info.meId &&
          m.persistedId != null &&
          m.persistedId! <= peerReadMax) {
        return m;
      }
    }
    return null;
  }

  String _streakPos(ChatMessage m, ChatMessage? prev, ChatMessage? next) {
    bool sameDay(String a, String b) {
      try {
        final da = DateTime.parse(a.replaceAll(' ', 'T'));
        final db = DateTime.parse(b.replaceAll(' ', 'T'));
        return da.year == db.year && da.month == db.month && da.day == db.day;
      } catch (_) {
        return true;
      }
    }

    final prevSame = prev != null &&
        prev.senderId == m.senderId &&
        sameDay(prev.createdAt, m.createdAt);
    final nextSame = next != null &&
        next.senderId == m.senderId &&
        sameDay(next.createdAt, m.createdAt);
    if (!prevSame && !nextSame) return 'solo';
    if (!prevSame && nextSame) return 'start';
    if (prevSame && nextSame) return 'mid';
    return 'end';
  }

  Widget _buildTypingRow(PortalGroupInfo info) {
    if (_typing.isEmpty) return const SizedBox.shrink();
    final names = _typing.keys
        .map((uid) {
          final p = info.participants.firstWhere(
              (x) => x.userId == uid,
              orElse: () => ChatParticipant(
                  userId: uid, username: 'User $uid', fullName: '', role: ''));
          return p.displayName;
        })
        .take(2)
        .toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: Row(
        children: [
          const _TypingDots(),
          const SizedBox(width: 8),
          Text(
            names.length == 1
                ? '${names.first} is typing…'
                : '${names.join(', ')} are typing…',
            style: const TextStyle(
                color: Brand.textMuted, fontSize: 12, fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingRow() {
    if (_pendingAttachments.isEmpty && !_uploading) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          if (_uploading)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Brand.signal),
                  ),
                  SizedBox(width: 6),
                  Text('Uploading…',
                      style: TextStyle(
                          fontSize: 11.5, color: Color(0xFFC2410C))),
                ],
              ),
            ),
          ..._pendingAttachments.asMap().entries.map((e) {
            final idx = e.key;
            final a = e.value;
            return Container(
              padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_iconForMime(a.mimeType),
                      size: 14, color: const Color(0xFFC2410C)),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: Text(
                      a.originalName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFFC2410C)),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 14),
                    color: const Color(0xFFC2410C),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    onPressed: () => setState(() {
                      _pendingAttachments.removeAt(idx);
                    }),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildComposer() {
    final hasContent =
        _composer.text.trim().isNotEmpty || _pendingAttachments.isNotEmpty;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 12, 12),
        decoration: const BoxDecoration(
          color: Brand.canvas,
          border: Border(top: BorderSide(color: Brand.stroke)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              icon: const Icon(Icons.add_circle_outline, color: Brand.signal),
              onPressed: _attachFile,
              tooltip: 'Attach',
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Brand.subtle,
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: TextField(
                  controller: _composer,
                  onChanged: _onComposerChanged,
                  textInputAction: TextInputAction.newline,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: 'Aa',
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _SendButton(enabled: hasContent, onTap: _sendMessage),
          ],
        ),
      ),
    );
  }
}

// ── Helpers / sub-widgets ────────────────────────────────────────────────

IconData _iconForMime(String mime) {
  if (mime.startsWith('image/')) return Icons.image_outlined;
  if (mime == 'application/pdf') return Icons.picture_as_pdf_outlined;
  if (mime.contains('word')) return Icons.description_outlined;
  if (mime.contains('excel') || mime.contains('spreadsheet')) {
    return Icons.table_chart_outlined;
  }
  if (mime.contains('csv')) return Icons.list_alt;
  if (mime.startsWith('text/')) return Icons.notes;
  return Icons.attach_file;
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.api,
    required this.chat,
    required this.message,
    required this.info,
    required this.streakPos,
    required this.showSeen,
    required this.onAttachmentTap,
  });

  final ApiClient api;
  final ChatService chat;
  final ChatMessage message;
  final PortalGroupInfo info;
  final String streakPos;
  final bool showSeen;
  final ValueChanged<ChatAttachment> onAttachmentTap;

  bool get mine => message.senderId == info.meId;

  ChatParticipant? _sender() {
    for (final p in info.participants) {
      if (p.userId == message.senderId) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final sender = _sender();
    final showSenderLabel =
        !mine && (streakPos == 'start' || streakPos == 'solo');
    final showAvatar =
        !mine && (streakPos == 'end' || streakPos == 'solo');
    final senderName = sender?.displayName ?? 'User ${message.senderId}';
    final role = sender?.role ?? '';

    return Padding(
      padding: EdgeInsets.only(
          top: streakPos == 'start' || streakPos == 'solo' ? 12 : 2),
      child: Row(
        mainAxisAlignment:
            mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine)
            SizedBox(
              width: 30,
              child: showAvatar
                  ? _Avatar(name: senderName, seed: message.senderId)
                  : const SizedBox.shrink(),
            ),
          if (!mine) const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment:
                  mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (showSenderLabel)
                  Padding(
                    padding: const EdgeInsets.only(left: 10, bottom: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          senderName,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Brand.textMuted,
                          ),
                        ),
                        if (role == 'admin' || role == 'super_admin') ...[
                          const SizedBox(width: 6),
                          _RoleBadge(role: role),
                        ],
                      ],
                    ),
                  ),
                _bubble(context, role),
                if (showSeen)
                  const Padding(
                    padding: EdgeInsets.only(top: 4, right: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, size: 8, color: Brand.signal),
                        SizedBox(width: 4),
                        Text('Seen',
                            style: TextStyle(
                                fontSize: 10.5, color: Brand.textMuted)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(BuildContext context, String role) {
    final isSuper = role == 'super_admin';
    final bg = mine
        ? Brand.primary
        : isSuper
            ? const LinearGradient(
                colors: [Color(0xFF312E81), Color(0xFF4F46E5)])
            : null;
    final solid = mine
        ? null
        : isSuper
            ? null
            : (role == 'admin' ? const Color(0xFFEEF2FF) : Brand.subtle);
    final fg = mine || isSuper ? Colors.white : Brand.textPrimary;

    final radius = BorderRadius.only(
      topLeft: Radius.circular(streakPos == 'mid' || streakPos == 'end' && !mine
          ? 6
          : 18),
      topRight: Radius.circular(mine && (streakPos == 'mid' || streakPos == 'end')
          ? 6
          : 18),
      bottomLeft: Radius.circular(
          !mine && (streakPos == 'start' || streakPos == 'mid') ? 6 : 18),
      bottomRight: Radius.circular(
          mine && (streakPos == 'start' || streakPos == 'mid') ? 6 : 18),
    );

    return Container(
      constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.74),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: bg,
        color: solid,
        borderRadius: radius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.body.isNotEmpty)
            Text(
              message.body,
              style: TextStyle(
                color: fg,
                fontSize: 14.5,
                height: 1.36,
              ),
            ),
          if (message.attachments.isNotEmpty)
            ...message.attachments.map((a) => Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _AttachmentChip(
                    api: api,
                    attachment: a,
                    url: chat.attachmentUrl(a.id),
                    onTap: () => onAttachmentTap(a),
                    onLight: !(mine || isSuper),
                  ),
                )),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.seed});
  final String name;
  final int seed;
  Color _toneFor(int s) {
    const tones = [
      Color(0xFF06B6D4),
      Color(0xFF10B981),
      Color(0xFFF59E0B),
      Color(0xFFEC4899),
      Color(0xFF4F46E5),
    ];
    return tones[s.abs() % tones.length];
  }

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: _toneFor(seed),
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});
  final String role;
  @override
  Widget build(BuildContext context) {
    final isSuper = role == 'super_admin';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: isSuper ? const Color(0xFF312E81) : const Color(0xFF4F46E5),
        borderRadius: BorderRadius.circular(999),
      ),
      // Customer-facing wording: "ADMIN" is internal jargon. From the
      // customer's seat in the support thread, every staff replier is
      // simply "Support" — much friendlier and avoids leaking the staff
      // role hierarchy. Super-admins still get a distinct visual via
      // the deeper indigo background above.
      child: const Text(
        'SUPPORT',
        style: TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({
    required this.api,
    required this.attachment,
    required this.url,
    required this.onTap,
    required this.onLight,
  });
  final ApiClient api;
  final ChatAttachment attachment;
  final String url;
  final VoidCallback onTap;
  final bool onLight;

  String _bytesFmt(int n) {
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    if (attachment.isImage) {
      return GestureDetector(
        onTap: onTap,
        child: AuthedImage(
          api: api,
          url: url,
          width: 220,
          maxHeight: 240,
          borderRadius: BorderRadius.circular(12),
          placeholder: const SizedBox(
            width: 220,
            height: 140,
            child: Center(
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Brand.signal),
            ),
          ),
          errorWidget: const Padding(
            padding: EdgeInsets.all(20),
            child: Icon(Icons.broken_image, color: Colors.white70),
          ),
        ),
      );
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: onLight ? const Color(0xFFE0E7FF) : Colors.white24,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_iconForMime(attachment.mimeType),
                size: 18,
                color: onLight ? const Color(0xFF4338CA) : Colors.white),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.originalName,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: onLight ? Brand.textPrimary : Colors.white,
                  ),
                ),
                Text(
                  _bytesFmt(attachment.byteSize),
                  style: TextStyle(
                    fontSize: 11,
                    color: onLight
                        ? Brand.textMuted
                        : Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.enabled, required this.onTap});
  final bool enabled;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          gradient: enabled ? Brand.primary : null,
          color: enabled ? null : const Color(0xFFE2E8F0),
          borderRadius: BorderRadius.circular(20),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: Brand.signalGlow(0.32),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Icon(
          Icons.send_rounded,
          color: enabled ? Colors.white : const Color(0xFF94A3B8),
          size: 18,
        ),
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final v = (sin((_c.value * 2 * pi) - i * 0.4) + 1) / 2;
            return Container(
              margin: const EdgeInsets.only(right: 3),
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: Brand.textMuted.withValues(alpha: 0.3 + 0.7 * v),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}

class _ImagePreviewScreen extends StatelessWidget {
  const _ImagePreviewScreen({
    required this.api,
    required this.url,
    required this.title,
  });
  final ApiClient api;
  final String url;
  final String title;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          title,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 4,
          child: AuthedImage(
            api: api,
            url: url,
            fit: BoxFit.contain,
            placeholder: const CircularProgressIndicator(color: Brand.signal),
            errorWidget: const Icon(Icons.broken_image,
                color: Colors.white, size: 64),
          ),
        ),
      ),
    );
  }
}

class _ErrorPlaceholder extends StatelessWidget {
  const _ErrorPlaceholder({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, color: Brand.danger, size: 36),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Brand.textMuted, fontSize: 13.5, height: 1.45),
            ),
            const SizedBox(height: 18),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
