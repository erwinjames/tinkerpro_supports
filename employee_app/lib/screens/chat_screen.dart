import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
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
import '../services/ticket_service.dart';
import '../theme.dart';
import 'call_screen.dart';
import 'ticket_form_screen.dart';

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
  StreamSubscription<CallPresence>? _presenceSub;

  /// Most recent `busy` presence from a *different* terminal in our
  /// conversation. While non-null, this terminal's call buttons grey
  /// out and a banner appears so a tech doesn't fire a competing call
  /// while a colleague's call is in flight. Cleared on matching `free`
  /// from the same callId, or by [_presenceAutoClear] (heartbeat
  /// fallback when the busy emitter crashes silently).
  CallPresence? _colleagueInCall;
  Timer? _presenceAutoClear;

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
    _presenceSub =
        widget.realtime.callPresenceEvents.listen(_onCallPresence);
    widget.calls.addListener(_onCallChange);
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _inviteSub?.cancel();
    _presenceSub?.cancel();
    _presenceAutoClear?.cancel();
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
        // chat_service.history() now returns ascending (oldest → newest)
        // so we append in order — newest ends up at the bottom of the
        // ListView where new messages from _onIncoming also land.
        // (Reversing here is what flipped the badges so #22 appeared
        // above #17 in the chat.)
        ..addAll(list);
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

    final svc = RemoteAccessService.instance;

    final available = await svc.isAvailable();
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

    // First-time setup: if the employee hasn't picked a password yet,
    // prompt for one inline. The password is what admin will type into
    // RustDesk's "Verify password" prompt, so the employee should also
    // set this same password in RustDesk → Settings → Security
    // → Permanent password.
    if (!await svc.hasUserChosenPassword()) {
      if (!mounted) return;
      final picked = await _promptForPassword(context, initial: '');
      if (picked == null || picked.isEmpty) {
        await widget.chat.send(
          convId: _convId,
          body: 'Remote access setup not completed — employee did not '
              'choose a password. Please ask them to retry /remote.',
          clientNonce: _newNonce(),
        );
        setState(() => _resolvedRemotes.remove(m.id));
        return;
      }
      await svc.setStoredPermanentPassword(picked);
      if (mounted) {
        await _showPostSetupReminderDialog(picked);
      }
    }

    final session = await svc.prepareForIncoming(
        retryFor: const Duration(seconds: 10));
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
          info: _info,
          store: widget.store,
          api: widget.api,
        ),
      ),
    );
    if (outcome == null || !mounted) return;
    // Post a confirmation back into the support thread so admins see
    // the ticket land in chat in real time.
    final ticketRef =
        outcome.ticketId != null ? ' #${outcome.ticketId}' : '';
    final note = '🎫 Ticket$ticketRef submitted: "${outcome.subject}"\n'
        'Business: ${outcome.businessName} (${outcome.vatLabel})\n'
        'Priority: ${outcome.priority.toUpperCase()}';
    final msg = await widget.chat.send(
      convId: _convId,
      body: note,
      clientNonce: _newNonce(),
    );
    if (msg != null && mounted && !_messages.any((m) => m.id == msg.id)) {
      setState(() => _messages.add(msg));
      _scrollToBottom();
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Ticket submitted. Support will reach out shortly.'),
      ));
    }
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    // Slash-commands hijack the send action so they never hit the wire
    // as a chat message. `/ticket` opens the ticket form; on submit
    // it returns an outcome which we then post back into the chat as
    // a confirmation bubble.
    if (_isSlashCommand(text, '/ticket')) {
      _composer.clear();
      await _openTicketForm();
      return;
    }
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

  void _onCallPresence(CallPresence pres) {
    // Echoes of our own emit are noise — skip them.
    if (pres.fromId == _meId) return;
    if (!mounted) return;
    if (pres.isBusy) {
      _presenceAutoClear?.cancel();
      // 5-minute safety net: if the colleague's terminal crashes
      // without releasing, we don't want to lock our own buttons
      // forever. Real calls outlive 5 min sometimes, but at that
      // point we'd rather risk a false-free than a permanent stick.
      _presenceAutoClear = Timer(const Duration(minutes: 5), () {
        if (!mounted) return;
        setState(() => _colleagueInCall = null);
      });
      setState(() => _colleagueInCall = pres);
    } else if (pres.isFree) {
      // Only clear if the free matches the call we're tracking — out
      // of order frees from older calls shouldn't unlock a newer one.
      final current = _colleagueInCall;
      if (current != null && current.callId == pres.callId) {
        _presenceAutoClear?.cancel();
        _presenceAutoClear = null;
        setState(() => _colleagueInCall = null);
      }
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
  /// Show the active RustDesk permanent password (user-chosen or the
  /// auto-derived fingerprint default), with a copy button and an
  /// Edit button so the employee can replace it with one they'll
  /// remember. After editing, they paste it into RustDesk's Settings
  /// → Security → Permanent password — once per Windows install.
  Future<void> _showRemotePasswordSheet() async {
    final svc = RemoteAccessService.instance;
    var password = await svc.derivePermanentPassword();
    var userChosen = await svc.hasUserChosenPassword();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Brand.canvas,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            Future<void> editPassword() async {
              final next = await _promptForPassword(
                  ctx, initial: userChosen ? password : '');
              if (next == null) return; // cancelled
              await svc.setStoredPermanentPassword(next);
              password = await svc.derivePermanentPassword();
              userChosen = await svc.hasUserChosenPassword();
              setSheet(() {});
              if (mounted) {
                _toast(next.isEmpty
                    ? 'Reverted to auto-generated password'
                    : 'Password updated — set the new one in RustDesk');
              }
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                28 + MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Remote desktop password',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: editPassword,
                        icon: const Icon(Icons.edit, size: 16),
                        label: Text(userChosen ? 'Change' : 'Set my own'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    userChosen
                        ? 'You picked this password. Open RustDesk → Settings → Security → Permanent password → set it to the value below.'
                        : 'Auto-generated for this machine. Open RustDesk → Settings → Security → Permanent password → set it to the value below — or tap "Set my own" to use a password you\'ll remember.',
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                    decoration: BoxDecoration(
                      color: Brand.surface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            password,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 18,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Copy',
                          icon: const Icon(Icons.copy),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: password));
                            _toast('Password copied');
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Whatever shows here is what gets sent to admin every '
                    'time you tap Allow on a /remote — make sure RustDesk\'s '
                    'permanent password matches.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Shown right after the employee picks their password the first
  /// time. Reminds them to set the SAME value in RustDesk's own
  /// Settings → Security → Permanent password — without that step,
  /// admin's connect attempt will fail with "Wrong password".
  Future<void> _showPostSetupReminderDialog(String password) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('One more step'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Now set the SAME password inside RustDesk so admin can '
              'connect. Open RustDesk → Settings → Security → "Use both '
              'passwords" → "Set permanent password" → paste the value '
              'below.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Brand.surface,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      password,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy',
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: password));
                      _toast('Copied');
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK, done'),
          ),
        ],
      ),
    );
  }

  Future<String?> _promptForPassword(
    BuildContext ctx, {
    required String initial,
  }) async {
    final controller = TextEditingController(text: initial);
    final formKey = GlobalKey<FormState>();
    return showDialog<String?>(
      context: ctx,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Pick a remote desktop password'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'e.g. store-front-2026',
                helperText: 'Min 6 characters. Empty resets to auto-generated.',
              ),
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return null; // empty = clear
                if (t.length < 6) return 'At least 6 characters';
                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (!(formKey.currentState?.validate() ?? false)) return;
                Navigator.of(ctx).pop(controller.text.trim());
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

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
            tooltip: 'Show remote-desktop password (for first-time setup)',
            icon: const Icon(Icons.vpn_key_outlined),
            onPressed: _showRemotePasswordSheet,
          ),
          IconButton(
            tooltip: 'Add a colleague from this Wi-Fi',
            icon: const Icon(Icons.person_add_alt_1),
            onPressed: _openAddParticipantSheet,
          ),
          IconButton(
            tooltip: _colleagueInCall != null
                ? '${_colleagueInCall!.fromName} is on a call — please wait'
                : 'Voice call',
            icon: const Icon(Icons.call),
            onPressed: _colleagueInCall != null
                ? null
                : () => _placeCall(CallMedia.voice),
          ),
          IconButton(
            tooltip: _colleagueInCall != null
                ? '${_colleagueInCall!.fromName} is on a call — please wait'
                : 'Video call',
            icon: const Icon(Icons.videocam),
            onPressed: _colleagueInCall != null
                ? null
                : () => _placeCall(CallMedia.video),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          if (_colleagueInCall != null) _buildColleagueCallBanner(),
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

  Widget _buildColleagueCallBanner() {
    final pres = _colleagueInCall!;
    final mediaLabel = pres.media == 'video' ? 'video call' : 'voice call';
    return Material(
      color: const Color(0xFFFFF7E6),
      child: InkWell(
        // Tapping does nothing meaningful — the banner is informational,
        // but wrap in InkWell so a tech gets ripple feedback if they try.
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(
                Icons.phone_in_talk_outlined,
                size: 18,
                color: Color(0xFFB45309),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${pres.fromName.isEmpty ? 'A colleague' : pres.fromName} is on a $mediaLabel with support',
                  style: const TextStyle(
                    color: Color(0xFF92400E),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
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

  /// Ticket-lifecycle messages are formatted server-side as plain
  /// chat text ("🎫 Ticket #N submitted: …", "👋 X has accepted ticket
  /// #N (\"S\") and will be helping you from here.", "✅ X marked
  /// ticket #N (\"S\") as resolved…"). Parse those into structured
  /// records here so the renderer can show a clean centered badge
  /// instead of a regular bubble.
  _TicketEvent? _detectTicketEvent(String body) {
    if (body.isEmpty) return null;
    // Submitted — line 1 is "🎫 Ticket #N submitted: <subject>".
    final mSub = RegExp(r'^🎫\s*Ticket\s*#(\d+)\s+submitted(?::\s*(.+))?$',
            multiLine: false)
        .firstMatch(body.split('\n').first);
    if (mSub != null) {
      return _TicketEvent(
        kind: _TicketEventKind.submitted,
        id: int.tryParse(mSub.group(1) ?? '0') ?? 0,
        subject: (mSub.group(2) ?? '').trim(),
      );
    }
    // Accepted — "👋 {agent} has accepted ticket #N (\"S\") …"
    final mAcc =
        RegExp(r'^👋\s*(.+?)\s+has accepted ticket\s*#(\d+)(?:\s*\("([^"]*)"\))?')
            .firstMatch(body);
    if (mAcc != null) {
      return _TicketEvent(
        kind: _TicketEventKind.accepted,
        agentName: mAcc.group(1)?.trim() ?? '',
        id: int.tryParse(mAcc.group(2) ?? '0') ?? 0,
        subject: (mAcc.group(3) ?? '').trim(),
      );
    }
    // Resolved — "✅ {agent} marked ticket #N (\"S\") as resolved…"
    final mRes = RegExp(
            r'^✅\s*(.+?)\s+marked ticket\s*#(\d+)(?:\s*\("([^"]*)"\))?\s+as resolved')
        .firstMatch(body);
    if (mRes != null) {
      return _TicketEvent(
        kind: _TicketEventKind.resolved,
        agentName: mRes.group(1)?.trim() ?? '',
        id: int.tryParse(mRes.group(2) ?? '0') ?? 0,
        subject: (mRes.group(3) ?? '').trim(),
      );
    }
    return null;
  }

  Widget _buildBubble(ChatMessage m, TextTheme text) {
    // Special-case incoming /remote: render an interactive card
    // instead of plain text. Eliminates the showDialog dependency
    // entirely (Flutter Linux desktop dialogs have a habit of
    // getting swallowed by the GTK shell).
    if (_isPendingRemoteRequest(m)) {
      return _buildRemoteRequestCard(m, text);
    }

    // Ticket lifecycle (submitted / accepted / resolved) renders as a
    // centered status badge instead of a left/right-aligned bubble so
    // it reads as a system event, not a participant's chat line.
    final ev = _detectTicketEvent(m.body);
    if (ev != null) {
      return _buildTicketBadge(ev);
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

  /// Centered system badge for a ticket lifecycle event. Visual:
  /// pill with leading icon chip + status line + optional subject /
  /// agent name on the second line. Reads as system metadata (not a
  /// participant's chat line) because of the centered alignment and
  /// the brand-tinted surface.
  Widget _buildTicketBadge(_TicketEvent ev) {
    final (icon, accent, primaryLine, secondaryLine) = switch (ev.kind) {
      _TicketEventKind.submitted => (
        Icons.confirmation_number_outlined,
        Brand.signal,
        'Ticket #${ev.id} submitted',
        ev.subject.isEmpty ? null : '"${ev.subject}"',
      ),
      _TicketEventKind.accepted => (
        Icons.check_circle_outline,
        const Color(0xFF2563EB),
        ev.agentName.isEmpty
            ? 'Ticket #${ev.id} accepted'
            : '${ev.agentName} accepted ticket #${ev.id}',
        ev.subject.isEmpty ? "We'll help you from here." : '"${ev.subject}"',
      ),
      _TicketEventKind.resolved => (
        Icons.task_alt_outlined,
        Brand.success,
        'Ticket #${ev.id} resolved',
        ev.agentName.isEmpty ? null : 'by ${ev.agentName}',
      ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _showTicketDetailSheet(ev.id),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 5, 12, 5),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: accent.withValues(alpha: 0.30)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Icon(icon, size: 10, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            primaryLine,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: accent,
                              letterSpacing: -0.05,
                              height: 1.2,
                            ),
                          ),
                          if (secondaryLine != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 1),
                              child: Text(
                                secondaryLine,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Brand.textMuted,
                                  fontWeight: FontWeight.w500,
                                  height: 1.2,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.chevron_right_rounded,
                        size: 14, color: accent.withValues(alpha: 0.6)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Opens a bottom sheet with the full ticket record (subject,
  /// description, status, priority, agent, customer, timestamps).
  /// Fetched lazily — keeps the chat history light and ensures the
  /// view reflects any status changes since the badge was rendered.
  Future<void> _showTicketDetailSheet(int ticketId) async {
    final tickets = TicketService(widget.api);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return FutureBuilder<TicketDetail?>(
          future: tickets.getTicketDetail(ticketId),
          builder: (ctx, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return _TicketDetailShell(
                ticketId: ticketId,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 36),
                  child: Center(
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Brand.signal)),
                ),
              );
            }
            final d = snap.data;
            if (d == null) {
              return _TicketDetailShell(
                ticketId: ticketId,
                child: const Padding(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 28),
                  child: Text(
                    "Couldn't load this ticket. It may have been removed.",
                    style: TextStyle(color: Brand.textMuted, fontSize: 13.5),
                  ),
                ),
              );
            }
            return _TicketDetailSheet(detail: d);
          },
        );
      },
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

/// Bottom-sheet container shared by the loading/error/loaded states of
/// the ticket detail flow. Keeps a consistent height + handle so the
/// transition between states doesn't jump.
class _TicketDetailShell extends StatelessWidget {
  const _TicketDetailShell({required this.ticketId, required this.child});
  final int ticketId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Brand.canvas,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Brand.stroke,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                children: [
                  Text(
                    'Ticket #$ticketId',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Brand.textMuted,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close,
                        size: 20, color: Brand.textMuted),
                    onPressed: () => Navigator.of(context).pop(),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

/// Renders the full ticket record inside the bottom sheet. Layout:
/// status pill + priority pill at the top, then subject + description,
/// then a key/value list of customer/business/agent/dates.
class _TicketDetailSheet extends StatelessWidget {
  const _TicketDetailSheet({required this.detail});
  final TicketDetail detail;

  @override
  Widget build(BuildContext context) {
    final (statusColor, statusLabel) = switch (detail.status) {
      'new' => (const Color(0xFF2563EB), 'New'),
      'assigned' || 'in_progress' =>
        (const Color(0xFF2563EB), 'In progress'),
      'resolved' => (Brand.success, 'Resolved'),
      'closed' => (Brand.textMuted, 'Closed'),
      _ => (Brand.textMuted, detail.status),
    };
    final (priorityColor, priorityLabel) = switch (detail.priority) {
      'low' => (Brand.success, 'Low'),
      'medium' => (Brand.warning, 'Medium'),
      'high' => (Brand.danger, 'Urgent'),
      _ => (Brand.textMuted, detail.priority),
    };

    return _TicketDetailShell(
      ticketId: detail.id,
      child: Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _StatusPill(color: statusColor, label: statusLabel),
                  _StatusPill(color: priorityColor, label: priorityLabel),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                detail.subject.isEmpty ? '(no subject)' : detail.subject,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Brand.textPrimary,
                  letterSpacing: -0.2,
                  height: 1.3,
                ),
              ),
              if (detail.description.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  detail.description,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Brand.textPrimary,
                    height: 1.5,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              const Divider(height: 1, color: Brand.stroke),
              const SizedBox(height: 14),
              if (detail.customerName.isNotEmpty)
                _MetaRow(
                    icon: Icons.person_outline,
                    label: 'Customer',
                    value: detail.customerName),
              if (detail.businessName.isNotEmpty)
                _MetaRow(
                    icon: Icons.storefront_outlined,
                    label: 'Business',
                    value: detail.businessName),
              _MetaRow(
                icon: Icons.support_agent_outlined,
                label: 'Assigned to',
                value: detail.agentName.isEmpty ? 'Unassigned' : detail.agentName,
                muted: detail.agentName.isEmpty,
              ),
              if (detail.createdAt.isNotEmpty)
                _MetaRow(
                    icon: Icons.event_outlined,
                    label: 'Created',
                    value: detail.createdAt),
              if (detail.updatedAt.isNotEmpty &&
                  detail.updatedAt != detail.createdAt)
                _MetaRow(
                    icon: Icons.update_outlined,
                    label: 'Last update',
                    value: detail.updatedAt),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.icon,
    required this.label,
    required this.value,
    this.muted = false,
  });
  final IconData icon;
  final String label;
  final String value;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Brand.textMuted),
          const SizedBox(width: 10),
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Brand.textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontStyle: muted ? FontStyle.italic : FontStyle.normal,
                color: muted ? Brand.textMuted : Brand.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _TicketEventKind { submitted, accepted, resolved }

/// Decoded ticket-lifecycle event extracted from a chat message body.
/// Used by [_EmployeeChatScreenState._buildTicketBadge] to render a
/// centered system-style badge instead of a regular bubble.
class _TicketEvent {
  _TicketEvent({
    required this.kind,
    required this.id,
    this.agentName = '',
    this.subject = '',
  });
  final _TicketEventKind kind;
  final int id;
  final String agentName;
  final String subject;
}
