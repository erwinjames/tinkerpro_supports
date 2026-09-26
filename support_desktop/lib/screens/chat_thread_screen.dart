import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show
        Clipboard,
        ClipboardData,
        HardwareKeyboard,
        KeyEvent,
        KeyDownEvent,
        LogicalKeyboardKey;
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
import '../services/chat_ui_data_service.dart';
import '../services/chatflow_service.dart';
import '../services/chatflow_thread_extras.dart';
import '../services/sound_engine.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'chat_participants_screen.dart';
import 'chat_ui_widgets.dart';
import '../widgets/tp_loader.dart';

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
    this.embedded = false,
    this.onClosed,
    this.ui,
    this.onInboxReload,
    this.conversations,
  });

  final int conversationId;
  final Conversation? conversation;
  final int myUserId;
  final ChatService service;
  final ChatRealtimeService realtime;
  final ApiClient api;
  final ChatPrefs chatPrefs;
  final CallService? calls;
  final bool embedded;
  final VoidCallback? onClosed;
  final ChatUiDataService? ui;
  final VoidCallback? onInboxReload;
  final List<Conversation> Function()? conversations;

  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

Future<bool> _chatConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool danger = false,
}) async {
  final ok = await showWebModal<bool>(
    context,
    title: title,
    icon: danger ? Icons.warning_amber_rounded : Icons.help_outline,
    width: 460,
    builder: (_) => Text(message, style: Theme.of(context).textTheme.bodyMedium),
    actions: (ctx) => [
      GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx, false)),
      danger
          ? DangerButton(label: confirmLabel, onPressed: () => Navigator.pop(ctx, true))
          : SignalButton(label: confirmLabel, onPressed: () => Navigator.pop(ctx, true)),
    ],
  );
  return ok ?? false;
}

class _Gate {
  const _Gate({
    this.locked = false,
    this.aiOwned = false,
    this.ticketId,
    this.status,
    this.claimedByOther = false,
    this.agentName = '',
    this.willReopen = false,
    this.willEmail = false,
  });
  final bool locked;
  final bool aiOwned;
  final int? ticketId;
  final String? status;
  final bool claimedByOther;
  final String agentName;
  final bool willReopen;
  final bool willEmail;
}

String _fmtTicketNo(int id) => '#${id.toString().padLeft(4, '0')}';

final RegExp _quoteRe = RegExp(
    r'^>\s*@([^\[:\n]+?)(?:\s*\[#(\d+)\])?\s*:[ \t]*([^\n]*?)(?:\r?\n\r?\n([\s\S]+))?$');

class _Quoted {
  const _Quoted(this.sender, this.targetId, this.preview, this.reply);
  final String sender;
  final int targetId;
  final String preview;
  final String reply;
}

String _stripNestedQuotes(String preview) {
  final re = RegExp(r'^>\s*@[^\[:\n]+?(?:\s*\[#\d+\])?\s*:\s*');
  var s = preview;
  for (var i = 0; i < 8 && re.hasMatch(s); i++) {
    s = s.replaceFirst(re, '').trim();
  }
  return s;
}

_Quoted? _parseQuoted(String body) {
  final m = _quoteRe.firstMatch(body);
  if (m == null) return null;
  final p = _stripNestedQuotes((m.group(3) ?? '').trim());
  return _Quoted(
    (m.group(1) ?? '').trim(),
    int.tryParse(m.group(2) ?? '') ?? 0,
    p.isEmpty ? '[attachment]' : p,
    (m.group(4) ?? '').trim(),
  );
}

class _ChatThreadScreenState extends State<ChatThreadScreen> {
  late final ChatThread _thread;
  late final ChatflowService _flow = ChatflowService(widget.api);
  late final ChatflowThreadExtras _extras;
  late final ChatUiDataService _ui;
  bool _ownsUi = false;
  final _composer = TextEditingController();
  late final FocusNode _composerFocus =
      FocusNode(onKeyEvent: _handleComposerKey);
  final _scroll = ScrollController();

  final List<_PendingAttachment> _pending = [];

  final Map<int, TicketStatusInfo> _ticketStatuses = {};
  final Set<String> _busy = {};
  bool _ticketRefreshing = false;

  List<Map<String, dynamic>> _participants = const [];
  Message? _replyTo;
  final List<DateTime> _sendTimes = [];
  bool _fbHandoverBlocked = false;
  StreamSubscription<Map<String, dynamic>>? _reactSub;

  @override
  void initState() {
    super.initState();
    _thread = ChatThread(
      conversationId: widget.conversationId,
      myUserId: widget.myUserId,
      service: widget.service,
      realtime: widget.realtime,
    );
    _ownsUi = widget.ui == null;
    _ui = widget.ui ?? ChatUiDataService(widget.api);
    if (_ownsUi) _ui.refresh();
    _ui.addListener(_onPresenceChange);
    _extras = ChatflowThreadExtras(_flow, widget.conversationId);
    _extras.addListener(_onPresenceChange);
    _thread.addListener(_onThreadChange);
    _thread.loadInitial().then((_) {
      _markNewestRead();
      _refreshTicketStatuses();
    });
    _scroll.addListener(_maybeLoadOlder);
    _composer.addListener(_onComposerChanged);
    _loadParticipants();

    widget.realtime.currentlyViewedConv.value = widget.conversationId;
    _reactSub = widget.realtime.reactionEvents.listen(_onReactionEvent);

    widget.realtime.onlineUsers.addListener(_onPresenceChange);
    widget.chatPrefs.addListener(_onPresenceChange);
  }

  bool _visible = true;
  ValueListenable<TickerModeData>? _tickerMode;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final n = TickerMode.getValuesNotifier(context);
    if (!identical(n, _tickerMode)) {
      _tickerMode?.removeListener(_onTickerModeChange);
      _tickerMode = n..addListener(_onTickerModeChange);
      _applyVisibility(n.value.enabled);
    }
  }

  void _onTickerModeChange() {
    final n = _tickerMode;
    if (n != null && mounted) _applyVisibility(n.value.enabled);
  }

  void _applyVisibility(bool visible) {
    if (visible == _visible) return;
    _visible = visible;
    if (visible) {
      widget.realtime.currentlyViewedConv.value = widget.conversationId;
      _markNewestRead();
    } else if (widget.realtime.currentlyViewedConv.value ==
        widget.conversationId) {
      widget.realtime.currentlyViewedConv.value = null;
    }
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

  Future<void> _loadParticipants() async {
    final r = await _flow.conversation(widget.conversationId);
    if (!mounted || !r.ok) return;
    final raw = r.data['participants'];
    setState(() {
      _participants = [
        if (raw is List)
          for (final p in raw)
            if (p is Map) Map<String, dynamic>.from(p),
      ];
    });
  }

  String _senderName(int senderId) {
    for (final p in _participants) {
      if (int.tryParse('${p['id']}') == senderId) {
        final f = '${p['full_name'] ?? ''}';
        if (f.isNotEmpty) return f;
        final u = '${p['username'] ?? ''}';
        if (u.isNotEmpty) return u;
      }
    }
    return 'User $senderId';
  }

  ChatConvMeta get _meta => _ui.meta(widget.conversationId);

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

  Iterable<Message> get _visibleMessages =>
      _thread.messages.where((m) => !_extras.isRemoved(m.id));

  List<({int id, TicketStatusInfo t})> _openTicketsOnThread() {
    final seen = <int>{};
    final out = <({int id, TicketStatusInfo t})>[];
    for (final m in _visibleMessages) {
      final ref = detectTicketRef(m.body);
      if (ref == null || !seen.add(ref.id)) continue;
      final t = _ticketStatuses[ref.id];
      if (t == null || t.isResolved || t.isClosed) continue;
      out.add((id: ref.id, t: t));
    }
    return out;
  }

  ({int id, TicketStatusInfo t})? _activeHeaderTicket() {
    for (final m in _visibleMessages) {
      final ref = detectTicketRef(m.body);
      if (ref == null) continue;
      final t = _ticketStatuses[ref.id];
      if (t == null || !t.isInProgress) continue;
      if (t.assignedAgentId != widget.myUserId) continue;
      return (id: ref.id, t: t);
    }
    return null;
  }

  ({int id, TicketStatusInfo t})? _activeHeaderReopenTicket() {
    for (final m in _visibleMessages) {
      final ref = detectTicketRef(m.body);
      if (ref == null) continue;
      final t = _ticketStatuses[ref.id];
      if (t == null) continue;
      if (t.isResolved || t.isClosed) return (id: ref.id, t: t);
      return null;
    }
    return null;
  }

  ({int id, TicketStatusInfo t})? _activeHeaderAcceptTicket() {
    for (final m in _visibleMessages) {
      final ref = detectTicketRef(m.body);
      if (ref == null) continue;
      final t = _ticketStatuses[ref.id];
      if (t == null || !t.isNew) continue;
      return (id: ref.id, t: t);
    }
    return null;
  }

  _Gate _gate() {
    final meta = _meta;
    if (meta.fbAiOwned) {
      return const _Gate(locked: true, aiOwned: true);
    }
    for (final o in _openTicketsOnThread()) {
      if (o.t.isInProgress && o.t.assignedAgentId == widget.myUserId) {
        return _Gate(ticketId: o.id, status: o.t.status);
      }
    }
    TicketRef? ref;
    TicketRef? liveRef;
    for (final m in _visibleMessages) {
      final r = detectTicketRef(m.body);
      if (r == null) continue;
      ref ??= r;
      final cached = _ticketStatuses[r.id];
      if (cached == null || (!cached.isResolved && !cached.isClosed)) {
        liveRef = r;
        break;
      }
    }
    ref = liveRef ?? ref;
    if (ref == null) return const _Gate();
    final t = _ticketStatuses[ref.id];
    if (t == null) return _Gate(locked: true, ticketId: ref.id);
    final assignedTo = t.assignedAgentId ?? 0;
    final isGuestConv = meta.guestStatus.isNotEmpty && meta.guestStatus != 'none';
    if ((t.isResolved || t.isClosed) && (meta.isDesktopApp || isGuestConv)) {
      return _Gate(
        ticketId: ref.id,
        status: t.status,
        willReopen: true,
        willEmail: isGuestConv && !meta.isDesktopApp,
      );
    }
    final claimedByMe = t.isInProgress && assignedTo > 0 && assignedTo == widget.myUserId;
    final claimedByOther = t.isInProgress && assignedTo > 0 && assignedTo != widget.myUserId;
    return _Gate(
      locked: !claimedByMe,
      ticketId: ref.id,
      status: t.status,
      claimedByOther: claimedByOther,
      agentName: t.agentName ?? '',
    );
  }

  Future<void> _acceptTicket(int ticketId) async {
    final key = 'accept-$ticketId';
    if (_busy.contains(key)) return;
    final choice = await showDialog<_AcceptChoice>(
      context: context,
      builder: (_) => _AcceptTicketDialog(
        flow: _flow,
        ticketId: ticketId,
        conversationId: widget.conversationId,
      ),
    );
    if (!mounted || choice == null) return;
    setState(() => _busy.add(key));
    final res = await _flow.acceptTicket(
      ticketId: ticketId,
      agentId: widget.myUserId,
      alias: choice.alias,
      saveDefault: choice.saveDefault,
      greetingMessage: choice.greetingMessage,
    );
    if (!mounted) return;
    setState(() => _busy.remove(key));
    _toast(res.ok ? 'Ticket accepted' : (res.message ?? 'Could not accept ticket'));
    await _refreshTicketStatuses();
  }

  Future<void> _resolveTickets(List<int> ids) async {
    if (ids.isEmpty || _busy.contains('resolve')) return;
    final many = ids.length > 1;
    final ok = await _chatConfirm(
      context,
      title: many
          ? 'Resolve ${ids.length} tickets?'
          : 'Resolve ticket ${_fmtTicketNo(ids.first)}?',
      message: many
          ? 'Marks every open ticket on this chat as resolved '
              '(${ids.map(_fmtTicketNo).join(', ')}).\n\n'
              'They came from chats that were merged — a confirmation is posted for each.'
          : 'This will post a confirmation in the chat.',
      confirmLabel: many ? 'Resolve all' : 'Mark resolved',
    );
    if (!ok || !mounted) return;
    setState(() => _busy.add('resolve'));
    var done = 0;
    var failed = 0;
    for (final id in ids) {
      final r = await _flow.resolveTicket(id, widget.myUserId);
      if (r.ok) {
        done++;
      } else {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() => _busy.remove('resolve'));
    if (done > 0 && failed == 0) {
      _toast(done > 1 ? '$done tickets resolved' : 'Ticket resolved');
    } else if (done > 0) {
      _toast('$done resolved, $failed failed');
    } else {
      _toast('Could not resolve ticket${ids.length > 1 ? 's' : ''}');
    }
    await _refreshTicketStatuses();
    if (done > 0) widget.onInboxReload?.call();
  }

  Future<void> _reopenTicket(int ticketId) async {
    if (_busy.contains('reopen')) return;
    final ok = await _chatConfirm(
      context,
      title: 'Reopen this ticket?',
      message: 'Puts ticket ${_fmtTicketNo(ticketId)} back in progress under '
          'your name and lets both sides carry on in this chat.',
      confirmLabel: 'Reopen ticket',
    );
    if (!ok || !mounted) return;
    setState(() => _busy.add('reopen'));
    final r = await _flow.reopenTicketAsAgent(widget.conversationId);
    if (!mounted) return;
    setState(() => _busy.remove('reopen'));
    if (!r.ok) {
      _toast(r.message ?? 'Could not reopen the ticket');
      return;
    }
    _toast('Ticket reopened');
    widget.onInboxReload?.call();
    await _refreshTicketStatuses();
  }

  Future<void> _openTicketDetail(int ticketId) async {
    final detail = await widget.service.ticketDetail(ticketId);
    if (!mounted) return;
    if (detail == null) {
      _toast('Ticket details unavailable');
      return;
    }
    final no = detail.ticketNumber ?? detail.id;
    await showWebModal<void>(
      context,
      title: 'Ticket #$no',
      subtitle: detail.subject.isEmpty ? null : detail.subject,
      icon: Icons.confirmation_number_outlined,
      width: 620,
      builder: (_) => _TicketDetailBody(detail: detail),
      actions: (ctx) => [
        GhostButton(
          label: 'Close',
          onPressed: () => Navigator.of(ctx).pop(),
        ),
      ],
    );
  }

  String _ticketStatusLabel(TicketStatusInfo st) {
    if (st.isNew) return 'New';
    if (st.isInProgress) return 'In progress';
    if (st.isResolved) return 'Resolved';
    return 'Closed';
  }

  ({int id, TicketStatusInfo status})? _subTicket() {
    for (final m in _visibleMessages) {
      final ref = detectTicketRef(m.body);
      if (ref == null) continue;
      final st = _ticketStatuses[ref.id];
      if (st == null || st.isClosed) continue;
      return (id: ref.id, status: st);
    }
    return null;
  }

  void _markNewestRead() {
    if (!_visible) return;
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
    if (_gate().locked) return false;
    if (_pending.any((p) => p.status == _UploadStatus.uploading)) return false;
    final hasReady = _pending.any((p) => p.status == _UploadStatus.ready);
    return _composer.text.trim().isNotEmpty || hasReady;
  }

  KeyEventResult _handleComposerKey(FocusNode node, KeyEvent event) {
    final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!isEnter) return KeyEventResult.ignored;
    if (HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      _handleSend();
    }
    return KeyEventResult.handled;
  }

  Future<void> _handleSend() async {
    if (_pending.any((p) => p.status == _UploadStatus.uploading)) return;
    if (_gate().locked) {
      _toast('Accept the ticket before replying to the customer.');
      return;
    }
    final text = _composer.text.trim();
    final ready = _pending
        .where((p) => p.status == _UploadStatus.ready)
        .map((p) => p.attachment!)
        .toList(growable: false);
    if (text.isEmpty && ready.isEmpty) return;

    final now = DateTime.now();
    _sendTimes.removeWhere(
        (t) => now.difference(t) >= const Duration(milliseconds: 3000));
    if (_sendTimes.length >= 5) {
      _toast("You're sending messages too quickly. Please slow down.");
      return;
    }

    var finalText = text;
    final reply = _replyTo;
    if (reply != null && reply.id != null) {
      final r = await _flow.replyBody(
        conversationId: widget.conversationId,
        replyToId: reply.id!,
        body: text,
      );
      if (!mounted) return;
      if (!r.ok || r.data['body'] == null) {
        _toast(r.message ?? 'Could not send reply');
        return;
      }
      finalText = '${r.data['body']}';
    }
    _sendTimes.add(now);
    setState(() {
      _replyTo = null;
      _composer.clear();
      _pending.removeWhere((p) => p.status == _UploadStatus.ready);
    });
    await _thread.send(finalText, attachments: ready);
  }

  void _close() {
    if (widget.onClosed != null) {
      widget.onClosed!();
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _openParticipants() async {
    final result = await ChatParticipantsScreen.show(
      context,
      service: widget.service,
      realtime: widget.realtime,
      conversationId: widget.conversationId,
      myUserId: widget.myUserId,
    );
    if (!mounted) return;
    if (result == participantsResultLeft) {
      widget.onInboxReload?.call();
      _close();
    } else {
      _loadParticipants();
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
      _toast('Answer the incoming call first');
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
        _toast('No one else is in this conversation');
        return;
      }
      if (members.length > kMeshMaxPeers) {
        _toast('Group calls support up to ${kMeshMaxPeers + 1} people');
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

  Future<void> _togglePriority() async {
    final next = !_meta.priority;
    final err = await _ui.setPriority(widget.conversationId, next);
    if (err != null && mounted) _toast('Could not update priority: $err');
  }

  Future<void> _toggleArchive() async {
    final next = !_meta.archived;
    final err = await _ui.setArchived(widget.conversationId, next);
    if (!mounted) return;
    _toast(err == null
        ? (next ? 'Archived' : 'Moved to inbox')
        : 'Could not ${next ? 'archive' : 'unarchive'}: $err');
  }

  Future<void> _hideConversation() async {
    final name = widget.conversation?.name ?? '';
    final ok = await _chatConfirm(
      context,
      title: 'Hide this conversation?',
      message: 'Hides ${name.isEmpty ? 'this conversation' : name} from your '
          'inbox.\n\nThis only affects your account — the other participants '
          'still see it, and a new message brings it back.',
      confirmLabel: 'Hide',
    );
    if (!ok || !mounted) return;
    final err = await _ui.hideForMe(widget.conversationId);
    if (!mounted) return;
    if (err == null) {
      widget.onInboxReload?.call();
      _close();
    } else {
      _toast('Could not hide: $err');
    }
  }

  Future<void> _rename() async {
    final current = widget.conversation?.name ?? '';
    final ctrl = TextEditingController(text: current);
    final name = await showWebModal<String>(
      context,
      title: 'Rename conversation',
      icon: Icons.edit_outlined,
      width: 460,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Use something you’ll recognise — the customer’s real name, for example.',
            style: Theme.of(ctx).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            onSubmitted: (v) => Navigator.of(ctx).pop(v),
          ),
        ],
      ),
      actions: (ctx) => [
        GhostButton(label: 'Cancel', onPressed: () => Navigator.of(ctx).pop()),
        SignalButton(
            label: 'Rename', onPressed: () => Navigator.of(ctx).pop(ctrl.text)),
      ],
    );
    ctrl.dispose();
    if (name == null || !mounted) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      _toast('Name cannot be empty');
      return;
    }
    if (trimmed == current) return;
    final r = await _flow.renameConversation(widget.conversationId, trimmed);
    if (!mounted) return;
    if (r.ok) {
      widget.onInboxReload?.call();
      _toast('Renamed');
    } else {
      _toast('Could not rename${r.message == null ? '' : ': ${r.message}'}');
    }
  }

  Future<void> _moveRequest() async {
    if (_busy.contains('fb')) return;
    setState(() => _busy.add('fb'));
    final r = await _flow.moveRequestToInbox(widget.conversationId);
    if (!mounted) return;
    setState(() => _busy.remove('fb'));
    if (r.ok) {
      _ui.patch(widget.conversationId, fbMoved: true);
      widget.onInboxReload?.call();
      _toast('Moved to agents — support can now reply');
    } else {
      _toast(r.message ?? 'Could not move to agents');
    }
  }

  Future<void> _returnRequest() async {
    if (_busy.contains('fb')) return;
    final ok = await _chatConfirm(
      context,
      title: 'Move back to Facebook Chats?',
      message: 'Puts this thread back under the Facebook Chats tab and removes '
          'every member who has no Facebook chat access.',
      confirmLabel: 'Move back',
    );
    if (!ok || !mounted) return;
    setState(() => _busy.add('fb'));
    final r = await _flow.returnRequestToFacebook(widget.conversationId);
    if (!mounted) return;
    setState(() => _busy.remove('fb'));
    if (r.ok) {
      _ui.patch(widget.conversationId, fbMoved: false, priority: false);
      widget.onInboxReload?.call();
      final dropped = int.tryParse('${r.data['removed'] ?? 0}') ?? 0;
      _toast(dropped > 0
          ? 'Back in Facebook Chats — removed $dropped member${dropped == 1 ? '' : 's'} without access'
          : 'Back in Facebook Chats');
    } else {
      _toast(r.message ?? 'Could not move back to Facebook Chats');
    }
  }

  Future<void> _returnToAi() async {
    if (_busy.contains('fb')) return;
    setState(() => _busy.add('fb'));
    final r = await _flow.fbReturnToAi(widget.conversationId);
    if (!mounted) return;
    setState(() => _busy.remove('fb'));
    if (r.ok) {
      _ui.patch(widget.conversationId, fbAiOwned: true);
      widget.onInboxReload?.call();
      _toast('Handed back to the Page AI');
    } else {
      _toast(r.message ?? 'Could not hand back to the AI');
    }
  }

  Future<void> _takeOver() async {
    if (_busy.contains('takeover')) return;
    setState(() => _busy.add('takeover'));
    final r = await _flow.fbTakeOver(widget.conversationId);
    if (!mounted) return;
    setState(() => _busy.remove('takeover'));
    if (r.ok) {
      _ui.patch(widget.conversationId, fbAiOwned: false);
      widget.onInboxReload?.call();
      _toast('You now control this conversation');
    } else {
      final msg = r.message ?? 'Could not take over from the AI';
      if (RegExp('conversation control|conversation routing|handover',
              caseSensitive: false)
          .hasMatch(msg)) {
        setState(() => _fbHandoverBlocked = true);
      }
      _toast(msg);
    }
  }

  Future<void> _showMoreMenu(Offset pos, {required bool isDm}) async {
    final m = _meta;
    final type = widget.conversation?.type;
    final picked = await showChatMenu(context, pos, [
      ChatMenuEntry('priority', m.priority ? 'Remove priority' : 'Mark as priority'),
      if (type == 'group') const ChatMenuEntry('rename', 'Rename'),
      if (!isDm) const ChatMenuEntry('members', 'Members'),
      ChatMenuEntry('archive', m.archived ? 'Move to inbox' : 'Archive'),
      const ChatMenuEntry('delete', 'Delete for me', danger: true),
    ]);
    if (!mounted) return;
    switch (picked) {
      case 'priority':
        await _togglePriority();
        break;
      case 'rename':
        await _rename();
        break;
      case 'members':
        await _openParticipants();
        break;
      case 'archive':
        await _toggleArchive();
        break;
      case 'delete':
        await _hideConversation();
        break;
    }
  }

  List<Widget> _buildHeaderActions({required bool isDm}) {
    final meta = _meta;
    final gate = _gate();
    final isGuest = meta.guestStatus.isNotEmpty && meta.guestStatus != 'none';
    final canCall = widget.calls != null &&
        !meta.isFacebook &&
        !isGuest &&
        ((isDm && _peerCallable) || _isMultiparty);
    final children = <Widget>[];
    final fbBusy = _busy.contains('fb');

    if (meta.isFacebook && _ui.canMessageRequests && !meta.fbMoved) {
      children.add(_HeaderTicketButton(
        icon: Icons.reply_all,
        label: 'Move to agents',
        tooltip: 'Move to the whole support team so any agent can reply',
        onTap: fbBusy ? null : _moveRequest,
      ));
    }
    if (meta.isFacebook && _ui.canMessageRequests && meta.fbMoved) {
      children.add(_HeaderTicketButton(
        icon: Icons.reply,
        label: 'Back to Facebook',
        tooltip: 'Move back to Facebook Chats and drop agents without Facebook access',
        onTap: fbBusy ? null : _returnRequest,
      ));
    }
    if (meta.isFacebook && !meta.fbAiOwned) {
      children.add(_HeaderTicketButton(
        icon: Icons.smart_toy_outlined,
        label: 'Return to AI',
        tooltip: 'Hand this conversation back to the Page AI assistant',
        onTap: fbBusy ? null : _returnToAi,
      ));
    }

    final accept = _activeHeaderAcceptTicket();
    if (accept != null) {
      final busy = _busy.contains('accept-${accept.id}');
      children.add(_HeaderTicketButton(
        icon: busy ? Icons.hourglass_top : Icons.check,
        label: busy ? 'Working…' : 'Accept ticket ${_fmtTicketNo(accept.id)}',
        tooltip: 'Accept ticket ${_fmtTicketNo(accept.id)}',
        onTap: busy ? null : () => _acceptTicket(accept.id),
      ));
    }
    final reopen = accept == null ? _activeHeaderReopenTicket() : null;
    if (reopen != null) {
      final busy = _busy.contains('reopen');
      children.add(_HeaderTicketButton(
        icon: busy ? Icons.hourglass_top : Icons.undo,
        label: busy ? 'Working…' : 'Reopen ticket ${_fmtTicketNo(reopen.id)}',
        tooltip: 'Reopen ticket ${_fmtTicketNo(reopen.id)}',
        onTap: busy ? null : () => _reopenTicket(reopen.id),
      ));
    }
    final openAll = _openTicketsOnThread();
    ({int id, TicketStatusInfo t})? mineOpen;
    for (final o in openAll) {
      if (o.t.isInProgress && o.t.assignedAgentId == widget.myUserId) {
        mineOpen = o;
        break;
      }
    }
    final active = mineOpen ?? _activeHeaderTicket();
    if (active != null) {
      final ids = openAll.isNotEmpty ? openAll.map((o) => o.id).toList() : [active.id];
      final many = ids.length > 1;
      final busy = _busy.contains('resolve');
      children.add(_HeaderTicketButton(
        icon: busy ? Icons.hourglass_top : Icons.flag_outlined,
        label: busy
            ? 'Working…'
            : many
                ? 'Resolve ${ids.length} tickets'
                : 'Resolve ticket ${_fmtTicketNo(active.id)}',
        tooltip: many
            ? 'Mark all ${ids.length} open tickets on this chat resolved'
            : 'Mark ticket ${_fmtTicketNo(active.id)} resolved',
        onTap: busy ? null : () => _resolveTickets(ids),
      ));
    }
    final detailTicket = _subTicket();
    if (detailTicket != null) {
      children.add(ChatIconBtn(
        icon: Icons.confirmation_number_outlined,
        tooltip: 'Ticket ${_fmtTicketNo(detailTicket.id)} details',
        onPressed: () => _openTicketDetail(detailTicket.id),
      ));
    }

    if (canCall) {
      final locked = gate.locked;
      children
        ..add(ChatIconBtn(
          icon: Icons.call_outlined,
          tooltip: locked ? 'Available once the ticket is claimed' : 'Voice call',
          onPressed: locked ? null : () => _placeCall(CallMedia.voice),
        ))
        ..add(ChatIconBtn(
          icon: Icons.videocam_outlined,
          tooltip: locked ? 'Available once the ticket is claimed' : 'Video call',
          onPressed: locked ? null : () => _placeCall(CallMedia.video),
        ));
    }
    children.add(Builder(
      builder: (bctx) => ChatIconBtn(
        icon: Icons.more_horiz,
        tooltip: 'More actions',
        onPressed: () {
          final box = bctx.findRenderObject() as RenderBox?;
          final pos = box == null
              ? Offset.zero
              : box.localToGlobal(Offset(0, box.size.height + 6));
          _showMoreMenu(pos, isDm: isDm);
        },
      ),
    ));
    return children;
  }

  bool _seenByOther(int id) =>
      _thread.readCursors.values.any((c) => c >= id);

  Future<void> _showMessageMenu(Message m, Offset position) async {
    final id = m.id;
    if (id == null) return;
    final mine = m.senderId == widget.myUserId;
    final pinned = _extras.pinned != null ? _extras.isPinned(id) : _thread.isPinned(id);
    final canUnsend = mine && !_seenByOther(id);
    final picked = await showChatMenu(context, position, [
      const ChatMenuEntry('reply', 'Reply'),
      const ChatMenuEntry('forward', 'Forward'),
      const ChatMenuEntry('delete', 'Delete'),
      ChatMenuEntry(pinned ? 'unpin' : 'pin', pinned ? 'Unpin' : 'Pin'),
      if (canUnsend) const ChatMenuEntry('unsend', 'Unsend', danger: true),
      if (m.body.trim().isNotEmpty) const ChatMenuEntry('copy', 'Copy text'),
    ]);
    if (!mounted || picked == null) return;
    await _handleMsgAction(m, picked);
  }

  Future<void> _handleMsgAction(Message m, String act) async {
    final id = m.id;
    if (id == null) return;
    switch (act) {
      case 'reply':
        setState(() => _replyTo = m);
        _composerFocus.requestFocus();
        break;
      case 'forward':
        await _forward(id);
        break;
      case 'delete':
        final r = await _flow.hideMessageForMe(id);
        if (!mounted) return;
        if (r.ok) {
          _extras.markRemoved(id);
        } else {
          _toast(r.message ?? 'Could not hide message');
        }
        break;
      case 'unsend':
        final ok = await _chatConfirm(
          context,
          title: 'Unsend this message?',
          message: 'It will be removed from the conversation for everyone.',
          confirmLabel: 'Unsend',
          danger: true,
        );
        if (!ok || !mounted) return;
        final r = await _flow.deleteMessage(id);
        if (!mounted) return;
        if (r.ok) {
          _extras.markRemoved(id);
        } else {
          _toast(r.message ?? 'Could not unsend message');
        }
        break;
      case 'pin':
        final r = await _flow.pinMessage(id);
        if (!mounted) return;
        if (r.ok) {
          await _extras.refresh();
          _toast('Message pinned');
        } else {
          _toast(r.message ?? 'Could not pin message');
        }
        break;
      case 'unpin':
        await _unpin(id);
        break;
      case 'copy':
        await Clipboard.setData(ClipboardData(text: m.body));
        if (mounted) _toast('Copied');
        break;
    }
  }

  Future<void> _unpin(int id) async {
    final r = await _flow.unpinMessage(id);
    if (!mounted) return;
    if (r.ok) {
      await _extras.refresh();
    } else {
      _toast(r.message ?? 'Could not unpin message');
    }
  }

  Future<void> _forward(int messageId) async {
    final convs = widget.conversations?.call() ?? const <Conversation>[];
    final target = await showDialog<int>(
      context: context,
      builder: (_) => _ForwardDialog(conversations: convs),
    );
    if (target == null || !mounted) return;
    final r = await _flow.forward(messageId, target);
    if (!mounted) return;
    if (r.ok) {
      _toast('Message forwarded');
      widget.onInboxReload?.call();
    } else {
      _toast(r.message ?? 'Could not forward message');
    }
  }

  Future<void> _showReactBar(Message m, Offset position) async {
    final id = m.id;
    if (id == null) return;
    final mine = _extras.myReaction(id, widget.myUserId);
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final picked = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      items: [
        PopupMenuItem<String>(
          enabled: false,
          height: 44,
          child: Builder(
            builder: (mctx) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final e in kChatReactionEmojis)
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => Navigator.of(mctx).pop(e),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: e == mine
                          ? BoxDecoration(
                              color: Brand.signalGlow(0.15),
                              shape: BoxShape.circle,
                            )
                          : null,
                      child: Text(e, style: const TextStyle(fontSize: 20)),
                    ),
                  ),
                if (mine != null)
                  Tooltip(
                    message: 'Remove reaction',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => Navigator.of(mctx).pop(''),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.close, size: 16),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
    if (picked == null || !mounted) return;
    final r = await _flow.react(id, picked);
    if (!mounted) return;
    if (r.ok) {
      final raw = r.data['reactions'];
      _extras.applyReactions(id, [
        if (raw is List)
          for (final x in raw)
            if (x is Map) ChatReaction.fromJson(Map<String, dynamic>.from(x)),
      ]);
    } else {
      _toast(r.message ?? 'Could not react');
    }
  }

  Future<void> _showPinnedList() async {
    final pinned = _extras.pinned ?? _thread.pinned;
    final toUnpin = await showWebModal<int>(
      context,
      title: 'Pinned messages',
      subtitle: '${pinned.length} pinned in this conversation',
      icon: Icons.push_pin_outlined,
      width: 560,
      bodyPadding: EdgeInsets.zero,
      builder: (_) => _PinnedListBody(pinned: pinned),
      actions: (ctx) => [
        GhostButton(
          label: 'Close',
          onPressed: () => Navigator.of(ctx).pop(),
        ),
      ],
    );
    if (!mounted || toUnpin == null) return;
    await _unpin(toUnpin);
  }

  Future<void> _addFromFilePicker() async {
    if (_gate().locked) {
      _toast('Accept the ticket before attaching.');
      return;
    }
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: true,
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;
      for (final f in result.files) {
        final path = f.path;
        if (path != null) _enqueueUpload(File(path));
      }
    } catch (_) {
      _toast('Could not pick file');
    }
  }

  void _enqueueUpload(File file) {
    final size = file.lengthSync();
    if (size > ChatflowService.maxUploadBytes) {
      _toast('File too large — max 1 GB');
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
    final outcome = await _flow.upload(pending.file, widget.conversationId);
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
    if (outcome.attachment == null && mounted) {
      _toast('Upload failed: ${outcome.error ?? 'unknown error'}');
    }
  }

  void _retryUpload(_PendingAttachment p) => _runUpload(p);

  void _removePending(_PendingAttachment p) {
    setState(() => _pending.remove(p));
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _onReactionEvent(Map<String, dynamic> d) {
    final cid = int.tryParse('${d['conversation_id'] ?? ''}') ?? 0;
    final mid = int.tryParse('${d['message_id'] ?? ''}') ?? 0;
    if (mid <= 0 || (cid > 0 && cid != widget.conversationId)) return;
    final raw = d['reactions'];
    final next = <ChatReaction>[
      if (raw is List)
        for (final x in raw)
          if (x is Map) ChatReaction.fromJson(Map<String, dynamic>.from(x)),
    ];
    int others(List<ChatReaction> list) => list.fold(
        0,
        (n, r) => n + r.userIds.where((u) => u != widget.myUserId).length);
    final before = others(_extras.reactions(mid));
    final after = others(next);
    final mine = _thread.messages
        .any((m) => m.id == mid && m.senderId == widget.myUserId);
    _extras.applyReactions(mid, next);
    if (mine && after > before) SoundEngine.instance.reaction('$mid:$after');
  }

  @override
  void dispose() {
    _reactSub?.cancel();
    _tickerMode?.removeListener(_onTickerModeChange);
    if (widget.realtime.currentlyViewedConv.value == widget.conversationId) {
      widget.realtime.currentlyViewedConv.value = null;
    }
    widget.realtime.onlineUsers.removeListener(_onPresenceChange);
    widget.chatPrefs.removeListener(_onPresenceChange);
    _ui.removeListener(_onPresenceChange);
    if (_ownsUi) _ui.dispose();
    _extras.removeListener(_onPresenceChange);
    _extras.dispose();
    _thread.removeListener(_onThreadChange);
    _thread.dispose();
    _composer.dispose();
    _composerFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String _replyPreview(Message m) {
    final q = _parseQuoted(m.body);
    final cleaned = q != null ? q.reply : m.body;
    var preview = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (preview.length > 140) preview = preview.substring(0, 140);
    if (preview.isEmpty && m.attachments.isNotEmpty) {
      final first = m.attachments.first;
      preview = first.isImage ? '[image]' : '[file: ${first.originalName}]';
      if (m.attachments.length > 1) preview += ' +${m.attachments.length - 1}';
    }
    return preview;
  }

  String _quoteTarget(_Quoted q) {
    if (q.targetId > 0) {
      for (final t in _thread.messages) {
        if (t.id == q.targetId) {
          return t.senderId == widget.myUserId ? 'You' : _senderName(t.senderId);
        }
      }
    }
    final me = (widget.api.username ?? '').trim().toLowerCase();
    if (me.isNotEmpty && q.sender.toLowerCase() == me) return 'You';
    return q.sender.isEmpty ? 'someone' : q.sender;
  }

  String _replyHead(bool mine, int senderId, _Quoted q) {
    final author = mine ? 'You' : _senderName(senderId);
    final target = _quoteTarget(q);
    if (author == 'You' && target == 'You') return 'You replied to yourself';
    if (author == 'You') return 'You replied to $target';
    if (target == 'You') return '$author replied to you';
    if (target == author) return '$author replied to themselves';
    return '$author replied to $target';
  }

  Widget _gateNote(_Gate gate) {
    final text = Theme.of(context).textTheme;
    Widget box(IconData icon, String msg, {Widget? action}) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7ED),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFFED7AA)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: const Color(0xFFC2410C)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(msg,
                    style: text.bodySmall
                        ?.copyWith(color: const Color(0xFFC2410C))),
              ),
              if (action != null) ...[const SizedBox(width: 10), action],
            ],
          ),
        );
    if (!gate.locked) {
      if (gate.willReopen) {
        return box(
          Icons.restore,
          'This ticket is ${gate.status ?? 'resolved'}. Replying reopens it'
          '${gate.willEmail ? ' and emails the customer their ticket number, so they can open this chat again.' : ' and puts it back in your queue.'}',
        );
      }
      return const SizedBox.shrink();
    }
    if (gate.aiOwned) {
      if (_fbHandoverBlocked) {
        return box(
          Icons.smart_toy_outlined,
          'The Page AI assistant is handling this conversation. Its replies appear here for reference. '
          'Replying from here needs conversation control enabled for this Page on Facebook.',
        );
      }
      final busy = _busy.contains('takeover');
      return box(
        Icons.smart_toy_outlined,
        'The Page AI assistant is handling this conversation. Its replies appear here for reference. '
        'Take over to answer this customer yourself.',
        action: SignalButton(
          label: busy ? 'Taking over…' : 'Take over',
          icon: Icons.headset_mic_outlined,
          busy: busy,
          onPressed: busy ? null : _takeOver,
        ),
      );
    }
    if (gate.status == 'resolved' || gate.status == 'closed') {
      return box(Icons.lock_outline,
          'This ticket is ${gate.status}. Reopen it from the header to carry on here, or the customer can start a new one.');
    }
    if (gate.claimedByOther) {
      final who = gate.agentName.isNotEmpty ? gate.agentName : 'another agent';
      return box(Icons.lock_outline,
          'This ticket is being handled by $who. Only they can reply or call.');
    }
    if (gate.status == 'new') {
      final id = gate.ticketId;
      final busy = id != null && _busy.contains('accept-$id');
      return box(
        Icons.pan_tool_outlined,
        'Accept this ticket to start replying to the customer.',
        action: id == null
            ? null
            : SignalButton(
                label: busy ? 'Accepting…' : 'Accept ticket',
                icon: Icons.check,
                busy: busy,
                onPressed: busy ? null : () => _acceptTicket(id),
              ),
      );
    }
    return box(Icons.lock_outline, 'Checking ticket status…');
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
    final headerTicket = _subTicket();
    final subLabel = headerTicket != null
        ? 'Ticket ${_fmtTicketNo(headerTicket.id)} · ${_ticketStatusLabel(headerTicket.status)}'
        : conv == null
            ? 'Direct message'
            : isDm
                ? (peerOnline
                    ? 'Online'
                    : peerLastSeen == null
                        ? 'Offline'
                        : 'Last seen ${peerLastSeen.toLowerCase()}')
                : isChannel
                    ? '${conv.visibility == 'private' ? 'Private channel' : 'Public channel'} · ${conv.participantCount} members'
                    : 'Group · ${conv.participantCount} members';
    final dotColor = headerTicket != null
        ? Brand.signal
        : (isDm && peerOnline ? Brand.success : const Color(0xFFCBD5E1));
    final gate = _gate();
    final pinned = _extras.pinned ?? _thread.pinned;

    final tk = ChatTokens.of(context);
    return Scaffold(
      backgroundColor: tk.bg,
      body: CallbackShortcuts(
        bindings: {
          if (!widget.embedded)
            const SingleActivator(LogicalKeyboardKey.escape): _close,
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ThreadHeader(
              title: title,
              subLabel: _meta.isDesktopApp
                  ? (subLabel.isEmpty ? 'POS App' : '$subLabel · POS App')
                  : subLabel,
              dotColor: dotColor,
              onBack: widget.embedded ? null : _close,
              compact: !widget.embedded,
              actions: _buildHeaderActions(isDm: isDm),
            ),
            if (pinned.isNotEmpty)
              _PinnedBanner(
                pinned: pinned,
                onTap: _showPinnedList,
              ),
            Expanded(
              child: Container(
                color: tk.bg,
                child: _messageList(),
              ),
            ),
            if (_thread.typingNames.isNotEmpty)
              Container(
                color: tk.bg,
                child: _TypingStrip(names: _thread.typingNames),
              ),
            if (_pending.isNotEmpty)
              Container(
                decoration: BoxDecoration(
                  color: context.brand.surface,
                  border: Border(top: BorderSide(color: context.brand.rule)),
                ),
                child: _PendingStrip(
                  pending: _pending,
                  onRetry: _retryUpload,
                  onRemove: _removePending,
                ),
              ),
            if (_replyTo != null)
              _ReplyBar(
                sender: _senderName(_replyTo!.senderId),
                preview: _replyPreview(_replyTo!),
                onClear: () => setState(() => _replyTo = null),
              ),
            _Composer(
              controller: _composer,
              focusNode: _composerFocus,
              canSend: _canSend,
              locked: gate.locked,
              note: _gateNote(gate),
              compact: !widget.embedded,
              onSend: _handleSend,
              onAttach: _addFromFilePicker,
            ),
          ],
        ),
      ),
    );
  }

  Widget _messageList() {
    final msgs = _visibleMessages.toList();
    if (msgs.isEmpty && _thread.loading) {
      return const Center(child: TpLoader());
    }
    if (msgs.isEmpty) {
      return const EmptyState(
        icon: Icons.chat_bubble_outline,
        label: 'No messages yet',
        hint: 'Say something to get started.',
      );
    }
    return LayoutBuilder(
      builder: (_, box) {
        final maxBubble = (box.maxWidth * (widget.embedded ? 0.68 : 0.8))
            .clamp(160.0, 680.0)
            .toDouble();
        final myNewestIndex =
            msgs.indexWhere((m) => m.senderId == widget.myUserId);
        final pinnedList = _extras.pinned;
        return ListView.builder(
          controller: _scroll,
          reverse: true,
          padding: EdgeInsets.fromLTRB(widget.embedded ? 24 : 12, 12,
              widget.embedded ? 24 : 12, 12),
          itemCount: msgs.length + (_thread.hasMore ? 1 : 0),
          itemBuilder: (_, i) {
            if (i == msgs.length) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: TpLoader(
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
            final groupedBelow = i > 0 && _isGrouped(msgs[i], msgs[i - 1]);
            final isOldestOfDay = i == msgs.length - 1 ||
                !_sameDay(m.createdAt, msgs[i + 1].createdAt);
            final quoted = _parseQuoted(m.body);
            final canAct = m.id != null && m.status == MessageStatus.sent;

            Widget bubble = _MessageBubble(
              message: m,
              mine: mine,
              maxWidth: maxBubble,
              isNewestMine: isNewestMine,
              suppressMeta: groupedBelow && !isNewestMine,
              grouped: groupedBelow,
              pinned: pinnedList != null
                  ? _extras.isPinned(m.id)
                  : _thread.isPinned(m.id),
              readCursors: _thread.readCursors,
              otherParticipantCount:
                  (_thread.totalParticipants - 1).clamp(0, 1000),
              theme: widget.chatPrefs.theme,
              api: widget.api,
              service: widget.service,
              quoted: quoted,
              replyHead: quoted == null ? null : _replyHead(mine, m.senderId, quoted),
              reactions: _extras.reactions(m.id),
              myUserId: widget.myUserId,
              reactorName: _senderName,
              onReact: canAct ? (pos) => _showReactBar(m, pos) : null,
              onMenu: canAct ? (pos) => _showMessageMenu(m, pos) : null,
              onRetry: m.status == MessageStatus.failed
                  ? () => _thread.retry(m)
                  : null,
            );

            if (canAct) {
              bubble = GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPressStart: (d) =>
                    _showMessageMenu(m, d.globalPosition),
                onSecondaryTapUp: (d) =>
                    _showMessageMenu(m, d.globalPosition),
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
    );
  }
}

class _AcceptChoice {
  const _AcceptChoice(this.alias, this.saveDefault, this.greetingMessage);
  final String alias;
  final bool saveDefault;
  final String? greetingMessage;
}

class _AcceptTicketDialog extends StatefulWidget {
  const _AcceptTicketDialog({
    required this.flow,
    required this.ticketId,
    required this.conversationId,
  });
  final ChatflowService flow;
  final int ticketId;
  final int conversationId;

  @override
  State<_AcceptTicketDialog> createState() => _AcceptTicketDialogState();
}

class _AcceptTicketDialogState extends State<_AcceptTicketDialog> {
  final _alias = TextEditingController();
  final _custom = TextEditingController();
  bool _saveDefault = false;
  bool _touched = false;
  String _value = '__auto__';
  List<GreetingTemplate> _templates = const [];
  String _ticketNo = '';
  Timer? _debounce;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _ticketNo = _fmtTicketNo(widget.ticketId);
    _loadTemplates();
    widget.flow.myAlias(widget.conversationId).then((r) {
      if (!mounted || !r.ok || _touched || _alias.text.isNotEmpty) return;
      final a = r.data['alias'] ?? r.data['default_alias'] ?? '';
      _alias.text = '$a';
      _alias.selection =
          TextSelection(baseOffset: 0, extentOffset: _alias.text.length);
      _loadTemplates();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _alias.dispose();
    _custom.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    final r = await widget.flow.acceptGreetings(widget.ticketId, _alias.text.trim());
    if (!mounted) return;
    setState(() {
      if (r.templates.isNotEmpty) _templates = r.templates;
      _ticketNo = r.ticketNo;
    });
  }

  void _onAlias(String _) {
    _touched = true;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _loadTemplates);
  }

  GreetingTemplate? get _selected {
    for (final t in _templates) {
      if (t.value == _value) return t;
    }
    return null;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    String? greeting;
    if (_value == '__custom__') {
      final t = _custom.text.trim();
      greeting = t.isEmpty ? null : t;
    } else if (_value != '__auto__') {
      final fresh = await widget.flow.acceptGreetings(widget.ticketId, _alias.text.trim());
      for (final t in fresh.templates) {
        if (t.value == _value) greeting = t.text;
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop(_AcceptChoice(_alias.text.trim(), _saveDefault, greeting));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final sel = _selected;
    return WebModal(
      title: 'Accept ticket',
      icon: Icons.check_circle_outline,
      width: 480,
      actions: [
        GhostButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
        SignalButton(
          label: 'Accept ticket',
          icon: Icons.check,
          busy: _submitting,
          onPressed: _submitting ? null : _submit,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'Choose the name the customer sees on this ticket ('),
              TextSpan(text: _ticketNo, style: const TextStyle(fontWeight: FontWeight.w700)),
              const TextSpan(text: '). Your real name stays visible to the team.'),
            ]),
            style: text.bodySmall,
          ),
          const SizedBox(height: 12),
          Text('ALIAS FOR THIS TICKET', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          TextField(
            controller: _alias,
            autofocus: true,
            maxLength: 60,
            decoration: const InputDecoration(hintText: 'e.g. Maya', counterText: ''),
            onChanged: _onAlias,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Checkbox(
                value: _saveDefault,
                onChanged: (v) => setState(() => _saveDefault = v ?? false),
              ),
              Text('Save as my default alias', style: text.bodySmall),
            ],
          ),
          Text('Leave blank to appear as “Support agent”.', style: text.bodySmall),
          const Divider(height: 28),
          Text('GREETING MESSAGE', style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _templates.any((t) => t.value == _value) ? _value : null,
            isExpanded: true,
            items: [
              for (final t in _templates)
                DropdownMenuItem(value: t.value, child: Text(t.label, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _value = v ?? '__auto__'),
          ),
          if (_value == '__custom__') ...[
            const SizedBox(height: 8),
            TextField(
              controller: _custom,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(hintText: 'Type your greeting message…'),
            ),
          ] else if (sel != null && sel.text != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: context.brand.surfaceHi,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: context.brand.rule),
              ),
              child: Text(sel.text!, style: text.bodySmall),
            ),
          ],
        ],
      ),
    );
  }
}

class _ForwardDialog extends StatefulWidget {
  const _ForwardDialog({required this.conversations});
  final List<Conversation> conversations;

  @override
  State<_ForwardDialog> createState() => _ForwardDialogState();
}

class _ForwardDialogState extends State<_ForwardDialog> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final f = _filter.toLowerCase();
    final rows = widget.conversations
        .where((c) => f.isEmpty || c.name.toLowerCase().contains(f))
        .toList();
    return WebModal(
      title: 'Forward to…',
      icon: Icons.forward_outlined,
      width: 480,
      height: 560,
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
            child: SearchField(
              hint: 'Search conversations…',
              width: null,
              autofocus: true,
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
          Divider(height: 1, color: context.brand.rule),
          Expanded(
            child: rows.isEmpty
                ? const EmptyState(icon: Icons.forum_outlined, label: 'No conversations', hint: '')
                : ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (_, i) {
                      final c = rows[i];
                      final name = c.name.isEmpty ? '—' : c.name;
                      final initials = name
                          .split(RegExp(r'\s+'))
                          .where((s) => s.isNotEmpty)
                          .map((s) => s[0])
                          .join()
                          .toUpperCase();
                      return WebTableRow(
                        onTap: () => Navigator.of(context).pop(c.id),
                        cells: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: Brand.signal,
                            child: Text(
                              initials.length > 2 ? initials.substring(0, 2) : initials,
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Text(name, style: text.bodyMedium)),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ReplyBar extends StatelessWidget {
  const _ReplyBar({required this.sender, required this.preview, required this.onClear});
  final String sender;
  final String preview;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final tk = ChatTokens.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
      decoration: BoxDecoration(
        color: tk.surfaceSoft,
        border: Border(top: BorderSide(color: tk.borderSoft)),
      ),
      child: Row(
        children: [
          const Icon(Icons.reply, size: 16, color: Color(0xFFFF7D00)),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '$sender ', style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: preview),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: tk.text),
            ),
          ),
          IconButton(
            tooltip: 'Clear reply',
            icon: const Icon(Icons.close, size: 16),
            onPressed: onClear,
          ),
        ],
      ),
    );
  }
}

class _ThreadHeader extends StatelessWidget {
  const _ThreadHeader({
    required this.title,
    required this.subLabel,
    required this.dotColor,
    required this.actions,
    this.onBack,
    this.compact = false,
  });

  final String title;
  final String subLabel;
  final Color dotColor;
  final List<Widget> actions;
  final VoidCallback? onBack;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = ChatTokens.of(context);
    final online = dotColor == Brand.success;
    return Container(
      height: compact ? 60 : 76,
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 24),
      decoration: BoxDecoration(
        color: t.surface.withValues(alpha: 0.85),
        border: Border(bottom: BorderSide(color: t.borderSoft)),
      ),
      child: Row(
        children: [
          if (onBack != null) ...[
            ChatIconBtn(
              icon: Icons.arrow_back,
              tooltip: 'Back',
              size: compact ? 32 : 38,
              onPressed: onBack,
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: ChatHeaderTitle(
              title: title,
              subtitle: subLabel,
              dotColor: online ? null : dotColor,
              online: online,
              compact: compact,
            ),
          ),
          for (final a in actions) ...[
            SizedBox(width: compact ? 4 : 8),
            compact && a is ChatIconBtn
                ? ChatIconBtn(
                    icon: a.icon,
                    tooltip: a.tooltip,
                    onPressed: a.onPressed,
                    size: 32,
                    iconSize: 13,
                  )
                : a,
          ],
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
    final s = file.path.replaceAll('\\', '/');
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
    return SizedBox(
      height: 92,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
        scrollDirection: Axis.horizontal,
        itemCount: pending.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
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
    const size = 68.0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: context.brand.surfaceHi,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.brand.rule, width: 1),
          ),
          child: pending.isImage
              ? Image.file(pending.file, fit: BoxFit.cover)
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.insert_drive_file_outlined,
                            size: 18, color: Brand.signal),
                        const SizedBox(height: 2),
                        Text(
                          pending.displayName,
                          style: text.labelSmall,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
        ),
        if (pending.status == _UploadStatus.uploading)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(child: TpLoader()),
            ),
          ),
        if (pending.status == _UploadStatus.failed)
          Positioned.fill(
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: onRetry,
                child: Tooltip(
                  message: 'Retry upload',
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Brand.danger),
                    ),
                    child: const Center(
                      child: Icon(Icons.refresh, color: Brand.danger, size: 22),
                    ),
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          top: -7,
          right: -7,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                  color: Brand.navy,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 13, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PinnedBanner extends StatelessWidget {
  const _PinnedBanner({required this.pinned, required this.onTap});

  final List<PinnedMessage> pinned;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final latest = pinned.first;
    final preview = latest.body.trim().isEmpty
        ? 'Attachment'
        : latest.body.trim().replaceAll('\n', ' ');
    return Material(
      color: const Color(0xFFFFF7ED),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 8, 16, 8),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFFED7AA))),
          ),
          child: Row(
            children: [
              const Icon(Icons.push_pin, size: 15, color: Brand.signal),
              const SizedBox(width: 10),
              Text(
                pinned.length > 1 ? 'Pinned (${pinned.length})' : 'Pinned',
                style: text.bodySmall?.copyWith(
                    color: Brand.signal, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(color: context.brand.paper),
                ),
              ),
              const SizedBox(width: 8),
              Text('View all',
                  style: text.bodySmall?.copyWith(
                      color: Brand.signal, fontWeight: FontWeight.w600)),
              const Icon(Icons.chevron_right, size: 16, color: Brand.signal),
            ],
          ),
        ),
      ),
    );
  }
}

class _PinnedListBody extends StatelessWidget {
  const _PinnedListBody({required this.pinned});

  final List<PinnedMessage> pinned;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (pinned.isEmpty) {
      return const EmptyState(
        icon: Icons.push_pin_outlined,
        label: 'Nothing pinned',
        hint: 'Right-click a message to pin it.',
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final p in pinned)
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: context.brand.rule)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.push_pin, size: 16, color: Brand.signal),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.senderName.isEmpty ? '—' : p.senderName,
                        style: text.bodySmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        p.body.trim().isEmpty ? 'Attachment' : p.body.trim(),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(p.messageId),
                  icon: const Icon(Icons.push_pin_outlined, size: 16),
                  label: const Text('Unpin'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.canSend,
    required this.locked,
    required this.note,
    required this.onSend,
    required this.onAttach,
    this.compact = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool canSend;
  final bool locked;
  final bool compact;
  final Widget note;
  final VoidCallback onSend;
  final VoidCallback onAttach;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final tk = ChatTokens.of(context);
    final pill = BorderRadius.circular(22);
    final hPad = compact ? 10.0 : 20.0;
    return Container(
      decoration: BoxDecoration(
        color: tk.surface,
        border: Border(top: BorderSide(color: tk.borderSoft)),
      ),
      padding: EdgeInsets.fromLTRB(hPad, 14, hPad, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          note,
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Tooltip(
                message: 'Attach',
                child: MouseRegion(
                  cursor: locked ? SystemMouseCursors.basic : SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: locked ? null : onAttach,
                    child: _RoundIcon(
                      icon: Icons.attach_file,
                      enabled: !locked,
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
                  textInputAction: TextInputAction.newline,
                  style: text.bodyMedium,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: locked
                        ? 'Messaging locked'
                        : 'Type a message…  (Enter to send, Shift+Enter for new line)',
                    filled: true,
                    fillColor: tk.surfaceSoft,
                    hintStyle: TextStyle(fontSize: 14, color: tk.subtle),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 13),
                    border: OutlineInputBorder(
                      borderRadius: pill,
                      borderSide: BorderSide(color: tk.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: pill,
                      borderSide: BorderSide(color: tk.border),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: pill,
                      borderSide: BorderSide(color: tk.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: pill,
                      borderSide:
                          const BorderSide(color: ChatTokens.primary),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Send',
                child: MouseRegion(
                  cursor: canSend
                      ? SystemMouseCursors.click
                      : SystemMouseCursors.basic,
                  child: GestureDetector(
                    onTap: canSend ? onSend : null,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: canSend ? ChatTokens.gradient : null,
                        color: canSend ? null : const Color(0xFFE5E7EB),
                        boxShadow: canSend
                            ? [
                                BoxShadow(
                                  color: ChatTokens.primary
                                      .withValues(alpha: 0.32),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(
                        Icons.send_rounded,
                        size: 18,
                        color:
                            canSend ? Colors.white : const Color(0xFF94A3B8),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.enabled});
  final IconData icon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ChatTokens.of(context).surfaceSoft,
        border: Border.all(color: ChatTokens.of(context).border),
      ),
      child: Icon(icon,
          size: 18,
          color: enabled
              ? ChatTokens.of(context).muted
              : ChatTokens.of(context).muted.withValues(alpha: 0.4)),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.api,
    required this.service,
    required this.theme,
    required this.maxWidth,
    this.isNewestMine = false,
    this.suppressMeta = false,
    this.grouped = false,
    this.pinned = false,
    this.readCursors = const {},
    this.otherParticipantCount = 0,
    this.onRetry,
    this.quoted,
    this.replyHead,
    this.reactions = const [],
    this.myUserId = 0,
    this.reactorName,
    this.onReact,
    this.onMenu,
  });

  final Message message;
  final bool mine;
  final ChatTheme theme;
  final double maxWidth;
  final bool isNewestMine;
  final bool pinned;
  final bool suppressMeta;
  final bool grouped;
  final Map<int, int> readCursors;
  final int otherParticipantCount;
  final ApiClient api;
  final ChatService service;
  final VoidCallback? onRetry;
  final _Quoted? quoted;
  final String? replyHead;
  final List<ChatReaction> reactions;
  final int myUserId;
  final String Function(int)? reactorName;
  final void Function(Offset)? onReact;
  final void Function(Offset)? onMenu;

  String? get _seenLabel {
    if (!isNewestMine) return null;
    final mid = message.id;
    if (mid == null) return null;
    if (otherParticipantCount <= 0) return null;
    final seenCount =
        readCursors.values.where((cursor) => cursor >= mid).length;
    if (seenCount <= 0) return null;
    if (otherParticipantCount == 1) return 'Seen';
    return 'Seen by $seenCount';
  }

  Color get _mineColor {
    if (theme.key == 'signal' || theme.key == 'mono') {
      return const Color(0xFF0C0A09);
    }
    return theme.accent;
  }

  Color get _accent =>
      theme.key == 'mono' ? Brand.signal : theme.accent;

  String _reactors(ChatReaction r) {
    final names = <String>[];
    if (r.userIds.contains(myUserId)) names.add('You');
    for (final u in r.userIds) {
      if (u != myUserId) names.add(reactorName?.call(u) ?? 'User $u');
    }
    return names.join(', ');
  }

  Widget _quoteBlock(BuildContext context, ChatTokens tk) {
    final q = quoted!;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Column(
        crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.reply, size: 12, color: tk.subtle),
              const SizedBox(width: 4),
              Flexible(
                child: Text(replyHead ?? '',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: tk.subtle)),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            margin: const EdgeInsets.only(bottom: 2),
            decoration: BoxDecoration(
              color: tk.surfaceSoft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: tk.borderSoft),
            ),
            child: Text(
              q.preview,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: tk.muted),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = _content(context);
    if (onReact == null && onMenu == null) return content;
    return _HoverActions(
      mine: mine,
      onReact: onReact,
      onMenu: onMenu,
      child: content,
    );
  }

  Widget _content(BuildContext context) {
    final align = mine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bodyText = quoted != null ? quoted!.reply : message.body;
    final hasBody = bodyText.trim().isNotEmpty;
    final seen = _seenLabel;
    final tk = ChatTokens.of(context);
    final meta = TextStyle(
      fontSize: 10.5,
      color: tk.subtle,
      fontWeight: FontWeight.w500,
    );
    const r = Radius.circular(18);
    const tail = Radius.circular(6);

    return Padding(
      padding: EdgeInsets.only(
        top: grouped ? 1 : 6,
        bottom: suppressMeta ? 1 : 6,
      ),
      child: Column(
        crossAxisAlignment: align,
        children: [
          if (quoted != null && !hasBody) _quoteBlock(context, tk),
          if (message.attachments.isNotEmpty) ...[
            _AttachmentList(
              message: message,
              mine: mine,
              maxWidth: maxWidth,
              api: api,
              service: service,
            ),
            if (hasBody) const SizedBox(height: 4),
          ],
          if (quoted != null && hasBody) _quoteBlock(context, tk),
          if (hasBody)
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                decoration: BoxDecoration(
                  color: mine ? _mineColor : tk.surface,
                  borderRadius: BorderRadius.only(
                    topLeft: r,
                    topRight: r,
                    bottomLeft: mine ? r : tail,
                    bottomRight: mine ? tail : r,
                  ),
                  border: mine
                      ? null
                      : Border.all(color: tk.borderSoft, width: 1),
                  boxShadow: mine
                      ? [
                          BoxShadow(
                            color: const Color(0xFF0C0A09)
                                .withValues(alpha: 0.18),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: const Color(0xFF0C0A09)
                                .withValues(alpha: 0.04),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                ),
                child: Text(
                  bodyText,
                  style: TextStyle(
                    fontSize: 14,
                    color: mine ? Colors.white : tk.text,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          if (reactions.any((r) => r.count > 0))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final r in reactions.where((r) => r.count > 0))
                    Tooltip(
                      message: _reactors(r),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: r.userIds.contains(myUserId)
                              ? Brand.signalGlow(0.12)
                              : tk.surface,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: r.userIds.contains(myUserId)
                                ? Brand.signal
                                : tk.borderSoft,
                          ),
                        ),
                        child: Text('${r.emoji} ${r.count}',
                            style: TextStyle(fontSize: 12, color: tk.text)),
                      ),
                    ),
                ],
              ),
            ),
          if (pinned)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.push_pin, size: 11, color: _accent),
                  const SizedBox(width: 3),
                  Text('Pinned', style: meta.copyWith(color: _accent)),
                ],
              ),
            ),
          if (!suppressMeta) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.status == MessageStatus.sending)
                  Text('Sending…', style: meta)
                else if (message.status == MessageStatus.failed)
                  InkWell(
                    onTap: onRetry,
                    child: Text(
                      'Failed · click to retry',
                      style: meta.copyWith(
                          color: Brand.danger, fontWeight: FontWeight.w700),
                    ),
                  )
                else ...[
                  Text(_shortTime(message.createdAt), style: meta),
                  if (seen != null) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.done_all, size: 13, color: _accent),
                    const SizedBox(width: 3),
                    Text(seen,
                        style: meta.copyWith(
                            color: _accent, fontWeight: FontWeight.w600)),
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

class _HoverActions extends StatefulWidget {
  const _HoverActions({
    required this.mine,
    required this.child,
    this.onReact,
    this.onMenu,
  });
  final bool mine;
  final Widget child;
  final void Function(Offset)? onReact;
  final void Function(Offset)? onMenu;

  @override
  State<_HoverActions> createState() => _HoverActionsState();
}

class _HoverActionsState extends State<_HoverActions> {
  bool _hover = false;

  Widget _btn(IconData icon, String tip, void Function(Offset)? cb) {
    return Builder(
      builder: (bctx) => Tooltip(
        message: tip,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: cb == null
              ? null
              : () {
                  final box = bctx.findRenderObject() as RenderBox?;
                  final pos = box == null
                      ? Offset.zero
                      : box.localToGlobal(Offset(0, box.size.height + 4));
                  cb(pos);
                },
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Icon(icon, size: 16, color: ChatTokens.of(bctx).muted),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final actions = AnimatedOpacity(
      opacity: _hover ? 1 : 0,
      duration: const Duration(milliseconds: 120),
      child: IgnorePointer(
        ignoring: !_hover,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _btn(Icons.sentiment_satisfied_alt_outlined, 'React', widget.onReact),
            _btn(Icons.more_horiz, 'More', widget.onMenu),
          ],
        ),
      ),
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Row(
        mainAxisAlignment: widget.mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: widget.mine
            ? [actions, Flexible(child: widget.child)]
            : [Flexible(child: widget.child), actions],
      ),
    );
  }
}

class _HeaderTicketButton extends StatelessWidget {
  const _HeaderTicketButton({
    required this.icon,
    required this.label,
    this.tooltip,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip ?? label,
      child: Material(
        color: enabled ? Brand.signal : context.brand.surfaceHi,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 16,
                    color: enabled ? Colors.white : context.brand.paperDim),
                const SizedBox(width: 6),
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: enabled ? Colors.white : context.brand.paperDim,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
        ),
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
    if (st == null) return const StatusPill(label: 'Ticket');
    if (st.isNew) return const StatusPill(label: 'New', color: Brand.signal);
    if (st.isInProgress) {
      return StatusPill(
        label: st.agentName != null && st.agentName!.isNotEmpty
            ? 'In progress · ${st.agentName!}'
            : 'In progress',
        color: Brand.info,
      );
    }
    if (st.isResolved) {
      return const StatusPill(label: 'Resolved', color: Brand.success);
    }
    return const StatusPill(label: 'Closed');
  }
}

class _TicketDetailBody extends StatelessWidget {
  const _TicketDetailBody({required this.detail});
  final TicketDetail detail;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = detail.priority.trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Status', style: text.bodySmall),
            const SizedBox(width: 10),
            _TicketPill(
              status: TicketStatusInfo(
                status: detail.status,
                agentName: detail.agentName,
              ),
            ),
          ],
        ),
        if (detail.description.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.brand.surfaceHi,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.brand.rule),
            ),
            child: SelectableText(detail.description, style: text.bodyMedium),
          ),
        ],
        const SizedBox(height: 12),
        StationDataRow(
          label: 'Priority',
          value: p.isEmpty ? '—' : '${p[0].toUpperCase()}${p.substring(1)}',
        ),
        if (detail.businessName != null)
          StationDataRow(label: 'Business', value: detail.businessName!),
        if (detail.customerName != null)
          StationDataRow(label: 'Customer', value: detail.customerName!),
        if (detail.agentName != null)
          StationDataRow(label: 'Agent', value: detail.agentName!),
        if (detail.createdAt != null)
          StationDataRow(label: 'Created', value: detail.createdAt!),
      ],
    );
  }
}

class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.iso});
  final String iso;

  @override
  Widget build(BuildContext context) {
    final label = _formatDaySeparator(iso);
    if (label.isEmpty) return const SizedBox(height: 8);
    final t = ChatTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: t.borderSoft),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0C0A09).withValues(alpha: 0.04),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: t.muted,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
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
    required this.maxWidth,
    required this.api,
    required this.service,
  });

  final Message message;
  final bool mine;
  final double maxWidth;
  final ApiClient api;
  final ChatService service;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth.clamp(160.0, 420.0)),
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          for (final a in message.attachments) ...[
            if (a.isImage)
              _ImageAttachment(attachment: a, api: api, service: service)
            else
              _FileAttachment(attachment: a, api: api, service: service),
            const SizedBox(height: 4),
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

    return MouseRegion(
      cursor: SystemMouseCursors.zoomIn,
      child: GestureDetector(
        onTap: () => _openImageViewer(context, url, api, attachment),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280),
          child: AspectRatio(
            aspectRatio: aspect.clamp(0.6, 2.5),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: context.brand.surfaceHi,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.brand.rule, width: 1),
              ),
              child: CachedNetworkImage(
                imageUrl: url,
                httpHeaders: api.authHeaders(),
                fit: BoxFit.cover,
                placeholder: (_, _) => const Center(child: TpLoader()),
                errorWidget: (_, _, _) => Center(
                  child: Icon(Icons.broken_image_outlined,
                      color: context.brand.paperDim, size: 24),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void _openImageViewer(
    BuildContext context, String url, ApiClient api, Attachment attachment) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.85),
    builder: (_) => _ImageViewer(url: url, api: api, name: attachment.originalName),
  );
}

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.url, required this.api, required this.name});
  final String url;
  final ApiClient api;
  final String name;

  @override
  Widget build(BuildContext context) {
    void close() => Navigator.of(context).pop();
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): close},
      child: Focus(
        autofocus: true,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(onTap: close),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(48, 72, 48, 48),
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4,
                  child: CachedNetworkImage(
                    imageUrl: url,
                    httpHeaders: api.authHeaders(),
                    fit: BoxFit.contain,
                    placeholder: (_, _) => const SizedBox(
                      width: 20,
                      height: 20,
                      child: TpLoader(
                        strokeWidth: 2,
                        color: Brand.signal,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 16,
              left: 24,
              right: 16,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                  Material(
                    color: Colors.white.withValues(alpha: 0.12),
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: 'Close',
                      onPressed: close,
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
        _toast('No app to open ${widget.attachment.mimeType}');
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
    return Material(
      color: context.brand.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _open,
        child: Container(
          constraints: const BoxConstraints(minWidth: 220),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: context.brand.rule, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconTile(icon: _icon, size: 36),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.attachment.originalName,
                      style: text.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(widget.attachment.formattedSize(),
                        style: text.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: TpLoader(
                        strokeWidth: 2,
                        color: Brand.signal,
                      ),
                    )
                  : Icon(Icons.download_outlined,
                      size: 18, color: context.brand.paperDim),
            ],
          ),
        ),
      ),
    );
  }
}

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
    final style = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 2, 24, 6),
      child: Row(
        children: [
          Flexible(
            child: Text(
              _describe(widget.names),
              style: style?.copyWith(fontStyle: FontStyle.italic),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, _) {
              final dots = (_ctrl.value * 3).floor() + 1;
              return SizedBox(
                width: 24,
                child: Text(
                  '.' * dots,
                  style: style?.copyWith(
                      color: Brand.signal, fontWeight: FontWeight.w700),
                ),
              );
            },
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
