import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../api_client.dart';
import '../models/chat_models.dart';
import '../services/call_service.dart';
import '../services/chat_realtime.dart';
import '../services/chat_service.dart';
import '../services/lan_presence.dart';
import '../services/remote_access_service.dart';
import '../services/ringtone_service.dart';
import '../services/session_store.dart';
import '../theme.dart';
import 'call_screen.dart';

/// Single-thread chat surface for the employee desktop client.
///
/// There is only one conversation per store — the support thread the
/// server returned via [ChatService.employeeStart]. So unlike the
/// staff/customer apps, no inbox or thread switcher; the screen renders
/// the message list directly and the call button rings every admin
/// participant in parallel (first to answer wins).
class EmployeeChatScreen extends StatefulWidget {
  const EmployeeChatScreen({
    super.key,
    required this.api,
    required this.chat,
    required this.realtime,
    required this.calls,
    required this.lan,
    required this.store,
    required this.info,
  });

  final ApiClient api;
  final ChatService chat;
  final ChatRealtimeService realtime;
  final CallService calls;
  final LanPresence lan;
  final SessionStore store;
  final EmployeeChatInfo info;

  @override
  State<EmployeeChatScreen> createState() => _EmployeeChatScreenState();
}

class _EmployeeChatScreenState extends State<EmployeeChatScreen> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _loading = true;
  bool _callScreenOpen = false;
  bool _invitePromptOpen = false;
  // Tracks /remote messages the user has already answered (Allow or
  // Deny) so the inline card doesn't keep showing buttons after the
  // response was sent.
  final Set<Object> _resolvedRemotes = {};
  StreamSubscription<ChatMessage>? _msgSub;
  StreamSubscription<ConversationInvite>? _inviteSub;

  /// Mutable copy of the seed info — gets swapped wholesale when the
  /// user accepts an Add-Participant invite from a colleague (we
  /// re-key onto the inviter's conversation_id).
  late EmployeeChatInfo _info;

  int get _convId => _info.conversationId;
  int get _meId => _info.meId;

  List<({int id, String name})> get _adminPeers => _info.participants
      .where((p) => p.userId != _meId && p.role != 'guest')
      .map((p) => (
            id: p.userId,
            name: p.fullName.isNotEmpty ? p.fullName : p.username,
          ))
      .toList();

  @override
  void initState() {
    super.initState();
    _info = widget.info;
    _loadHistory();
    _msgSub = widget.realtime.messageEvents.listen(_onIncoming);
    _inviteSub =
        widget.realtime.conversationCreatedEvents.listen(_onConversationInvite);
    widget.calls.addListener(_onCallChange);
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _inviteSub?.cancel();
    widget.calls.removeListener(_onCallChange);
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final list = await widget.chat.history(_convId);
    if (!mounted) return;
    setState(() {
      _messages
        ..clear()
        ..addAll(list.reversed); // chat_service returns newest-first
      // Suppress the inline /remote card for everything that's
      // already in the chat backlog. Only NEW /remote messages
      // arriving via _onIncoming after this point will render the
      // Allow/Deny card. Old ones become regular text bubbles.
      for (final m in _messages) {
        if (m.senderId != _meId &&
            m.body.toLowerCase().contains('/remote')) {
          _resolvedRemotes.add(m.id);
        }
      }
      _loading = false;
    });
    _scrollToBottom();
  }

  void _onIncoming(ChatMessage m) {
    if (m.conversationId != _convId) return;
    if (mounted) {
      setState(() => _messages.add(m));
      _scrollToBottom();
      // Light ping if the message is from someone else.
      if (m.senderId != _meId) {
        unawaited(RingtoneService.instance.ping());
      }
      // /remote messages are rendered as interactive cards inline in
      // the chat (see _buildBubble). No dialog needed — user just
      // taps Allow/Deny on the bubble itself.
    }
  }

  /// True when `m` is an incoming `/remote` request that hasn't been
  /// resolved yet. Used by the bubble renderer to swap in the
  /// interactive Allow/Deny card.
  bool _isPendingRemoteRequest(ChatMessage m) {
    if (m.senderId == _meId) return false;
    if (!m.body.toLowerCase().contains('/remote')) return false;
    if (_resolvedRemotes.contains(m.id)) return false;
    return true;
  }

  /// User tapped Deny on a /remote card. Mark the message resolved
  /// so the buttons go away, and post a denial reply.
  Future<void> _denyRemoteAccess(ChatMessage m) async {
    setState(() => _resolvedRemotes.add(m.id));
    await widget.chat.send(
      convId: _convId,
      body: 'Remote access denied.',
      clientNonce: _newNonce(),
    );
  }

  /// User tapped Allow on a /remote card. Configure RustDesk for
  /// password-mode auto-accept (so the employee doesn't get a second
  /// confirmation inside RustDesk itself), then reply in chat with
  /// both the ID and the freshly-generated password.
  Future<void> _allowRemoteAccess(ChatMessage m) async {
    setState(() => _resolvedRemotes.add(m.id));

    final available = await RemoteAccessService.instance.isAvailable();
    if (!available) {
      await widget.chat.send(
        convId: _convId,
        body: 'Remote access unavailable — the bundled RustDesk failed '
            'to extract on this machine. Reinstall the employee app, or '
            'install RustDesk from https://rustdesk.com.',
        clientNonce: _newNonce(),
      );
      if (mounted) _toast('RustDesk not available');
      return;
    }

    final session = await RemoteAccessService.instance
        .prepareForIncoming(retryFor: const Duration(seconds: 10));
    if (session == null) {
      await widget.chat.send(
        convId: _convId,
        body: 'RustDesk started but no ID was generated yet. Please '
            'wait a moment and ask the admin to send /remote again.',
        clientNonce: _newNonce(),
      );
      if (mounted) _toast('RustDesk ID not ready — retry in a moment');
      return;
    }

    // Reply with both ID and password. The web admin recognises this
    // Web admin's chat.php renders this exact prefix into a clickable
    // rustdesk://connect/<id> link + a click-to-copy password chip.
    // Admin clicks → RustDesk opens → admin types the password →
    // employee gets a one-tap Accept popup → connected.
    final body = session.password != null
        ? 'Remote access approved. RustDesk ID: ${session.id}, '
            'password: ${session.password}'
        : 'Remote access approved. RustDesk ID: ${session.id}';
    await widget.chat.send(
      convId: _convId,
      body: body,
      clientNonce: _newNonce(),
    );
    if (mounted) {
      _toast('Tap Accept on the RustDesk popup when admin connects');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  /// Crockford-base32 ULID-ish nonce. Server uses it to dedupe retries
  /// of the same logical send (network blip → user re-tap).
  String _newNonce() {
    const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
    final rng = Random();
    var ts = DateTime.now().millisecondsSinceEpoch;
    final buf = StringBuffer();
    for (var i = 0; i < 10; i++) {
      buf.write(alphabet[ts & 0x1F]);
      ts >>= 5;
    }
    for (var i = 0; i < 16; i++) {
      buf.write(alphabet[rng.nextInt(32)]);
    }
    return buf.toString();
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    _composer.clear();
    final msg = await widget.chat.send(
      convId: _convId,
      body: text,
      clientNonce: _newNonce(),
    );
    if (msg != null && mounted) {
      // Optimistic-ish: server returned the canonical message; insert
      // unless the realtime stream already delivered it.
      if (!_messages.any((m) => m.id == msg.id)) {
        setState(() => _messages.add(msg));
        _scrollToBottom();
      }
    }
  }

  Future<void> _attach() async {
    final result = await FilePicker.platform.pickFiles(withData: false);
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) {
      _toast('Could not access that file (no path).');
      return;
    }

    final ChatAttachment att;
    try {
      att = await widget.chat.uploadAttachment(_convId, File(path));
    } on UploadException catch (e) {
      if (mounted) _toast('Upload failed: ${e.message}');
      return;
    } catch (e) {
      if (mounted) _toast('Upload failed: $e');
      return;
    }

    final msg = await widget.chat.send(
      convId: _convId,
      body: '',
      clientNonce: _newNonce(),
      attachmentIds: [att.id],
    );
    if (msg != null && mounted && !_messages.any((m) => m.id == msg.id)) {
      setState(() => _messages.add(msg));
      _scrollToBottom();
    }
  }

  Future<void> _placeCall(CallMedia media) async {
    if (_adminPeers.isEmpty) {
      _toast('No support staff available right now.');
      return;
    }
    final ok = await widget.calls.placeCall(
      peers: _adminPeers,
      media: media,
    );
    if (!ok && mounted) {
      _toast('Could not start call.');
    }
  }

  void _onCallChange() {
    if (!mounted) return;
    if (widget.calls.isActive && !_callScreenOpen) {
      _callScreenOpen = true;
      Navigator.of(context, rootNavigator: true)
          .push(MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => CallScreen(calls: widget.calls),
          ))
          .whenComplete(() => _callScreenOpen = false);
    }
  }

  /// Open the LAN-peers picker. Picking a colleague calls
  /// `chat.addToConversation` server-side, which adds them to the
  /// current thread AND fires `conversation.created` on their end so
  /// their app prompts them to switch.
  Future<void> _openAddParticipantSheet() async {
    final picked = await showModalBottomSheet<LanPeer>(
      context: context,
      backgroundColor: Brand.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _LanPickerSheet(lan: widget.lan),
    );
    if (picked == null || !mounted) return;

    final ok = await widget.chat.addToConversation(
      conversationId: _convId,
      peerUserId: picked.userId,
    );
    if (!mounted) return;
    _toast(ok
        ? 'Invited ${picked.storeName.isEmpty ? "Store ${picked.userId}" : picked.storeName}'
        : 'Could not invite ${picked.storeName}');
    if (ok) {
      // Refresh participants so the AppBar subtitle picks up the new
      // member immediately. Server already added them; this is a UI
      // sync, not a write.
      final parts = await widget.chat.fetchParticipants(_convId);
      if (!mounted || parts.isEmpty) return;
      setState(() {
        _info = EmployeeChatInfo(
          conversationId: _info.conversationId,
          meId: _info.meId,
          meName: _info.meName,
          storeName: _info.storeName,
          participants: parts,
        );
      });
    }
  }

  /// Inbound `conversation.created` — a colleague just added me to
  /// their support thread. Prompt before doing anything; switching
  /// blows away our current scrollback (B's old solo thread is
  /// preserved server-side but no longer rendered locally), so we
  /// don't auto-accept.
  Future<void> _onConversationInvite(ConversationInvite invite) async {
    if (!mounted || _invitePromptOpen) return;
    if (invite.conversationId == _convId) return; // already there
    final inviter = invite.inviterName.isEmpty ? 'A colleague' : invite.inviterName;

    _invitePromptOpen = true;
    final accept = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.group_add, size: 36, color: Brand.signal),
        title: Text('$inviter wants you in their chat'),
        content: const Text(
          'Joining will switch your support thread to theirs. Your '
          'previous chat history with admin stays on the server but '
          "won't show on this device anymore.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Join'),
          ),
        ],
      ),
    );
    _invitePromptOpen = false;
    if (accept != true || !mounted) return;
    await _switchPrimaryConversation(invite.conversationId);
  }

  /// Re-key the chat screen onto a different `conversation_id`. Touches
  /// every layer of state: realtime channel subscriptions, persistent
  /// session store, in-memory message list, and the participant cache
  /// the AppBar / call-fan-out reads from.
  Future<void> _switchPrimaryConversation(int newConvId) async {
    final oldConvId = _convId;
    if (oldConvId == newConvId) return;

    // Realtime: subscribe before unsubscribing so we never have a
    // window where neither channel is live (matters less for chat,
    // but keeps a clean handover).
    await widget.realtime.subscribeConversation(newConvId);
    widget.realtime.unsubscribeConversation(oldConvId);

    // Persist so a relaunch lands directly on the new thread, not the
    // old one (chat.employeeStart would re-bind to the old id by
    // matching store_name otherwise).
    await widget.store.saveIdentity(
      userId: _info.meId,
      convId: newConvId,
    );

    // Pull participants for the new conv (mostly admin staff + the
    // inviter) so the AppBar subtitle and the call fan-out know who
    // to ring.
    final parts = await widget.chat.fetchParticipants(newConvId);

    if (!mounted) return;
    setState(() {
      _info = EmployeeChatInfo(
        conversationId: newConvId,
        meId: _info.meId,
        meName: _info.meName,
        storeName: _info.storeName,
        participants: parts,
      );
      _messages.clear();
      _loading = true;
    });
    await _loadHistory();
    if (!mounted) return;
    _toast('Switched to the group chat');
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Brand.surface,
      appBar: AppBar(
        backgroundColor: Brand.canvas,
        foregroundColor: Brand.textPrimary,
        elevation: 0,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: Brand.signal,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.support_agent,
                  color: Brand.canvas, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_info.storeName,
                      style: text.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(
                    'Support team · ${_adminPeers.length} agent${_adminPeers.length == 1 ? '' : 's'}',
                    style: text.bodySmall?.copyWith(color: Brand.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Add a colleague from this Wi-Fi',
            icon: const Icon(Icons.person_add_alt_1),
            onPressed: _openAddParticipantSheet,
          ),
          IconButton(
            tooltip: 'Voice call',
            icon: const Icon(Icons.call),
            onPressed: () => _placeCall(CallMedia.voice),
          ),
          IconButton(
            tooltip: 'Video call',
            icon: const Icon(Icons.videocam),
            onPressed: () => _placeCall(CallMedia.video),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : _messages.isEmpty
                    ? _buildEmptyState(text)
                    : _buildList(text),
          ),
          _buildComposer(),
        ],
      ),
    );
  }

  Widget _buildEmptyState(TextTheme text) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.waving_hand_outlined,
              size: 48, color: Brand.signal),
          const SizedBox(height: 12),
          Text('Say hi!', style: text.titleMedium),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Send a message to start chatting with the support team.',
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: Brand.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(TextTheme text) {
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _messages.length,
      itemBuilder: (_, i) => _buildBubble(_messages[i], text),
    );
  }

  Widget _buildBubble(ChatMessage m, TextTheme text) {
    // Special-case incoming /remote: render an interactive card
    // instead of plain text. Eliminates the showDialog dependency
    // entirely (Flutter Linux desktop dialogs have a habit of
    // getting swallowed by the GTK shell).
    if (_isPendingRemoteRequest(m)) {
      return _buildRemoteRequestCard(m, text);
    }

    final mine = m.senderId == _meId;
    final align = mine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final color = mine ? Brand.signal : Brand.canvas;
    final fg = mine ? Brand.canvas : Brand.textPrimary;
    final radius = const Radius.circular(14);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 460),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.only(
                topLeft: radius,
                topRight: radius,
                bottomLeft: mine ? radius : const Radius.circular(4),
                bottomRight: mine ? const Radius.circular(4) : radius,
              ),
              border: mine ? null : Border.all(color: Brand.stroke),
            ),
            child: Column(
              crossAxisAlignment: align,
              children: [
                if (m.body.isNotEmpty)
                  Text(m.body,
                      style: text.bodyMedium?.copyWith(color: fg)),
                if (m.attachments.isNotEmpty)
                  ..._renderAttachments(m, mine, text),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Attachments render as click-to-download rows. Inline image preview
  /// would need a cookie-aware HTTP client (CachedNetworkImage doesn't
  /// share Dio's cookie jar) — punt on that until there's a real ask.
  /// Inline /remote request card with Allow / Deny buttons. Replaces
  /// the previous showDialog approach — dialogs were getting eaten by
  /// the Linux GTK shell on this build, so we render the prompt right
  /// in the message stream where it can't be missed or hidden.
  Widget _buildRemoteRequestCard(ChatMessage m, TextTheme text) {
    String inviterName = 'Admin';
    for (final p in _info.participants) {
      if (p.userId == m.senderId && p.fullName.isNotEmpty) {
        inviterName = p.fullName;
        break;
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Brand.canvas,
            border: Border.all(color: Brand.signal, width: 1.4),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.desktop_windows_outlined,
                      color: Brand.signal, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$inviterName wants remote access',
                      style: text.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Approving will open RustDesk and share its ID. Each '
                'connection still requires a second confirmation inside '
                'RustDesk before any control is granted.',
                style: text.bodySmall?.copyWith(color: Brand.textMuted),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => _denyRemoteAccess(m),
                    child: const Text('Deny'),
                  ),
                  const SizedBox(width: 4),
                  FilledButton.icon(
                    onPressed: () => _allowRemoteAccess(m),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Allow'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _renderAttachments(ChatMessage m, bool mine, TextTheme text) {
    return m.attachments.map((att) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: InkWell(
          onTap: () => _openAttachment(att),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.insert_drive_file,
                  size: 18, color: mine ? Brand.canvas : Brand.signal),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(
                  att.originalName,
                  style: text.bodySmall?.copyWith(
                    color: mine ? Brand.canvas : Brand.signal,
                    decoration: TextDecoration.underline,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  Future<void> _openAttachment(ChatAttachment att) async {
    // Stream to a temp file so the OS handler can open it.
    try {
      final url = widget.chat.attachmentUrl(att.id);
      final dir = Directory.systemTemp.createTempSync('chat_dl_');
      final f = File('${dir.path}/${att.originalName}');
      await widget.api.rawDio.download(url, f.path);
      final res = await OpenFilex.open(f.path);
      if (res.type != ResultType.done && mounted) {
        _toast('No app to open this file type.');
      }
    } catch (_) {
      if (mounted) _toast('Could not open attachment.');
    }
  }

  Widget _buildComposer() {
    return Container(
      decoration: BoxDecoration(
        color: Brand.canvas,
        border: Border(top: BorderSide(color: Brand.stroke)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            icon: const Icon(Icons.attach_file),
            tooltip: 'Attach a file',
            onPressed: _attach,
          ),
          Expanded(
            child: TextField(
              controller: _composer,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: const InputDecoration(
                hintText: 'Type a message',
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(width: 4),
          FilledButton.icon(
            onPressed: _send,
            icon: const Icon(Icons.send, size: 16),
            label: const Text('Send'),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet listing LAN-discovered colleagues. Live — rebuilds when
/// peers come online or drop off (presence broadcast every 3s, prune
/// after 10s of silence). Tapping a row pops the sheet with the chosen
/// peer; the chat screen then calls `chat.addToConversation`.
class _LanPickerSheet extends StatelessWidget {
  const _LanPickerSheet({required this.lan});
  final LanPresence lan;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Brand.stroke,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  const Icon(Icons.wifi_find, color: Brand.signal),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Add a colleague', style: text.titleMedium),
                        Text(
                          'Other employees on this Wi-Fi',
                          style: text.bodySmall
                              ?.copyWith(color: Brand.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            Expanded(
              child: ValueListenableBuilder<List<LanPeer>>(
                valueListenable: lan.peers,
                builder: (_, peers, __) {
                  if (peers.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.search_off,
                                color: Brand.textMuted, size: 32),
                            const SizedBox(height: 8),
                            Text(
                              'No colleagues detected on this network yet.',
                              textAlign: TextAlign.center,
                              style: text.bodyMedium
                                  ?.copyWith(color: Brand.textMuted),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Make sure they're on the same Wi-Fi and the "
                              'app is open.',
                              textAlign: TextAlign.center,
                              style: text.bodySmall
                                  ?.copyWith(color: Brand.textMuted),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: peers.length,
                    itemBuilder: (_, i) {
                      final p = peers[i];
                      return ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Brand.signal,
                          child: Icon(Icons.storefront,
                              color: Brand.canvas, size: 18),
                        ),
                        title: Text(p.storeName.isEmpty
                            ? 'Store ${p.userId}'
                            : p.storeName),
                        subtitle: Text(
                          p.address,
                          style: text.bodySmall
                              ?.copyWith(color: Brand.textMuted),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).pop(p),
                      );
                    },
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
