import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, KeyDownEvent, LogicalKeyboardKey;
import 'package:flutter_webrtc/flutter_webrtc.dart'
    show navigator, MediaDeviceInfo;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import '../api_client.dart';
import '../models/chat_models.dart';
import '../platform_info.dart';
import '../services/call_service.dart';
import '../services/chat_realtime.dart';
import '../services/chat_service.dart';
import '../services/lan_presence.dart';
import '../services/remote_access_service.dart';
import '../services/ringtone_service.dart';
import '../services/session_store.dart';
import '../services/support_notifier.dart';
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
    this.sinceMessageId,
    this.onTicketClosed,
    this.scopedTicketId,
    this.initialAccepted,
    this.initiallyResolved = false,
  });

  final ApiClient api;
  final ChatService chat;
  final ChatRealtimeService realtime;
  final CallService calls;
  final LanPresence lan;
  final SessionStore store;
  final EmployeeChatInfo info;

  /// When non-null, only messages with `persistedId >= sinceMessageId`
  /// render — older history is filtered out of the loaded list and
  /// "load older" stops at the anchor. Set when the user enters the
  /// chat by filing a ticket from HelpGuideScreen so the thread
  /// starts at the ticket bubble and unrelated prior chatter from
  /// past tickets stays hidden. Null means full-history (legacy
  /// behavior).
  final int? sinceMessageId;

  /// Invoked when the chat detects that the scoped ticket has been
  /// resolved by an admin. The caller (HelpGuideScreen) supplies a
  /// closure that re-renders the guide screen in place of this chat
  /// route, so the employee lands back at the FAQ once their issue
  /// is closed out. Only fires while [sinceMessageId] is non-null
  /// (scoped mode); legacy unscoped chat keeps its existing behavior.
  final void Function(BuildContext context)? onTicketClosed;

  /// Scope the chat to a specific ticket *without* a local anchor bubble —
  /// used when the employee enters an existing ticket number (one they
  /// filed on the web). Takes precedence over parsing [sinceMessageId].
  final int? scopedTicketId;

  /// Initial accepted state for the explicit-scoping path: true when the
  /// looked-up ticket is already claimed (so we open straight into the
  /// live chat), false to show the "waiting for support to accept" card
  /// until the accept event arrives over realtime.
  final bool? initialAccepted;

  /// When opening an already resolved/closed ticket by number, the chat
  /// is a read-back view — there's nothing left to wait on, so the
  /// "ticket still pending" back-navigation guard must not trap the user.
  final bool initiallyResolved;

  @override
  State<EmployeeChatScreen> createState() => _EmployeeChatScreenState();
}

class _EmployeeChatScreenState extends State<EmployeeChatScreen>
    with WindowListener {
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
  StreamSubscription<MessageRead>? _readSub;
  StreamSubscription<int>? _deletedSub;
  StreamSubscription<PinnedEvent>? _pinnedSub;

  /// Pinned support instructions for this conversation (read-only here).
  List<PinnedMessage> _pinned = [];

  /// Per-user `last_read_message_id` populated from realtime read
  /// events. Drives the "no one else has seen this message yet" gate
  /// on the Unsend menu item — Unsend disappears once any other
  /// participant's cursor passes the message id.
  final Map<int, int> _readCursorsByUser = {};

  /// Active reply target — when non-null the composer shows a
  /// quote preview above it, and the next send prepends a quoted line
  /// to the body. Cleared on send or by tapping the preview's ✕.
  ChatMessage? _replyContext;

  /// Ticket id this chat is scoped to (parsed from the body of the
  /// message at `widget.sinceMessageId`). Used to recognise the
  /// matching "✅ … marked ticket #N as resolved" event and trigger
  /// the back-to-Help-Guide flow. Null while unscoped or until the
  /// anchor message has been parsed.
  int? _scopedTicketId;

  /// Latches once we've already navigated away on a resolved event,
  /// so a duplicate event or a late-arriving second resolved message
  /// can't fire onTicketClosed twice (which would push two new help
  /// guide screens on top of each other).
  bool _closedFromResolution = false;

  /// True once the scoped ticket has been accepted by an admin. While
  /// false in scoped mode the composer is replaced with a "Waiting
  /// for support" card — the cashier shouldn't be peppering an
  /// unassigned ticket with messages. Flips on a `👋 X has accepted
  /// ticket #N` event matching [_scopedTicketId] arriving via the
  /// realtime stream, OR when the same event is found in the loaded
  /// history (covers the warm-restart case where admin had already
  /// accepted before this screen opened). Always true outside scoped
  /// mode so legacy unscoped chat keeps its existing behavior.
  bool _ticketAccepted = false;

  /// True once the newest ticket on this thread has been marked resolved by
  /// an admin. Locks the composer (read-only banner) and greys the header
  /// actions so the employee can't keep chatting on a closed ticket — the
  /// same rule the web guest panel and admin composer enforce. Unlike the
  /// scoped resolved-navigation, this also covers the unscoped main support
  /// thread, where there's no route to bounce back to. Cleared when a fresh
  /// ticket is filed/accepted (a new active ticket reopens the chat).
  bool _ticketResolved = false;

  /// The chat is closed to new input when opened onto an already-resolved
  /// ticket OR the tracked ticket has just been resolved live.
  bool get _chatClosed => widget.initiallyResolved || _ticketResolved;

  /// Ticket # this screen tracks, for the status poll. Set in _loadHistory.
  int? _pollTicketNo;

  /// Polls the tracked ticket's real status so live accept/resolve transitions
  /// land even when the announcement bubbles never reach this client (they're
  /// unreliable). Stops once the ticket is resolved (terminal) or on dispose.
  Timer? _ticketPoll;

  void _startTicketPolling() {
    if (_ticketPoll != null || _pollTicketNo == null) return;
    // Keep polling even after the ticket resolves: an agent can RE-ENGAGE a
    // resolved ticket from the web (reopens it → in_progress), and the employee
    // should unlock live. The poll only stops on dispose. Acts on transitions.
    _ticketPoll = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted || _pollTicketNo == null) return;
      final st = await widget.chat.ticketStatus(_pollTicketNo!);
      if (!mounted || st == null) return;
      final status = (st['status'] ?? '').toString().toLowerCase();
      if (status.isEmpty) return;
      if (status == 'resolved' || status == 'closed') {
        if (!_ticketResolved) _handleTicketResolved(); // transition → lock/bounce
      } else if (status == 'in_progress' || status == 'assigned') {
        if (_ticketResolved || !_ticketAccepted) {
          setState(() {
            _ticketResolved = false;
            _ticketAccepted = true; // (re)claimed → composer unlocks live
          });
        }
      } else if (status == 'new') {
        if (_ticketResolved || (_scopedTicketId != null && _ticketAccepted)) {
          setState(() {
            _ticketResolved = false;
            if (_scopedTicketId != null) _ticketAccepted = false;
          });
        }
      }
    });
  }

  /// The tracked ticket is resolved: lock the composer AND — if this screen was
  /// opened with a close callback (the scoped/live ticket flow) — bounce back to
  /// the caller (the AI/chatbot screen), so the cashier isn't stranded in a
  /// read-only thread. Driven by the authoritative status (poll / send-response
  /// / bubble), not just the "resolved" announcement bubble which may never
  /// arrive. Guarded by [_closedFromResolution] so it fires exactly once;
  /// review mode (initiallyResolved) sets that flag up front so it stays put.
  void _handleTicketResolved({String? agentName, int? ticketNo}) {
    if (!mounted) return;
    final firstTime = !_ticketResolved;
    setState(() => _ticketResolved = true);
    if (_closedFromResolution || widget.onTicketClosed == null) return;
    _closedFromResolution = true;
    unawaited(widget.store.clearPendingTicket());
    unawaited(_applyWindowLock(false));
    if (firstTime) {
      final who = (agentName != null && agentName.isNotEmpty) ? agentName : 'support';
      final no = ticketNo ?? _scopedTicketId ?? _pollTicketNo;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(no != null
            ? 'Ticket ${fmtTicketNo(no)} resolved by $who.'
            : 'Ticket resolved by $who.'),
        duration: const Duration(seconds: 2),
      ));
    }
    // Let the snackbar register before tearing the route down.
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      widget.onTicketClosed!(context);
    });
  }

  /// Fold a ticket lifecycle event into [_ticketResolved]: a resolved event
  /// closes the chat; a fresh submit/accept reopens it. Called for every
  /// ticket bubble in history and every live one, in all modes.
  void _applyTicketLifecycle(_TicketEvent ev) {
    switch (ev.kind) {
      case _TicketEventKind.resolved:
        _ticketResolved = true;
        break;
      case _TicketEventKind.submitted:
      case _TicketEventKind.accepted:
        _ticketResolved = false;
        break;
    }
  }

  /// id of the message currently being hovered. Drives the
  /// fade-in/out of the inline ⋮ action button next to each bubble
  /// (mouse-only — long-press has been removed in favour of the
  /// hover-reveal pattern that mirrors the web admin).
  int? _hoveredMessageId;

  /// Files the user has picked but not yet sent. Rendered as a strip
  /// of preview tiles above the composer — each tile shows the file
  /// icon/thumbnail + name and (during upload) a per-file progress
  /// bar. The tiles persist across composer changes; pressing Send
  /// uploads them all in sequence, then posts a single message with
  /// every resulting attachment id bound to it. Pressing ✕ on a tile
  /// removes it from the queue (disabled mid-upload).
  final List<_PendingAttachment> _pendingAttachments = [];

  /// True while [_send] is mid-flight uploading the pending queue.
  /// Disables the picker, the remove buttons and the Send button so a
  /// stray tap can't kick off a duplicate batch.
  bool _isSending = false;

  /// Most recent `busy` presence from a *different* terminal in our
  /// conversation. While non-null, this terminal's call buttons grey
  /// out and a banner appears so a tech doesn't fire a competing call
  /// while a colleague's call is in flight. Cleared on matching `free`
  /// from the same callId, or by [_presenceAutoClear] (heartbeat
  /// fallback when the busy emitter crashes silently).
  CallPresence? _colleagueInCall;
  Timer? _presenceAutoClear;

  /// Camera availability for the video-call button.
  ///   null  → still probing (button disabled, "Checking for a camera…")
  ///   false → no camera found (button stays disabled)
  ///   true  → at least one camera detected (button enabled)
  /// Re-probed on device hot-plug via mediaDevices.ondevicechange so a
  /// webcam plugged into the POS box after launch lights the button up.
  bool? _hasCamera;

  /// Microphone availability for the voice-call button. Same tri-state
  /// semantics as [_hasCamera]:
  ///   null  → still probing (button disabled, "Checking for a microphone…")
  ///   false → no microphone found (button stays disabled)
  ///   true  → at least one microphone detected (button enabled)
  /// Re-probed on the same device-change hook as the camera so a headset
  /// plugged into the POS box after launch lights the button up.
  bool? _hasMic;

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
    // We're now looking at the thread: clear the unread badge and stop
    // the global SupportNotifier from firing banners / OS toasts /
    // pings — this screen surfaces incoming messages inline and plays
    // its own chime. Reset on dispose so alerts resume once we leave.
    SupportNotifier.instance.chatOpen = true;
    _loadHistory();
    _msgSub = widget.realtime.messageEvents.listen(_onIncoming);
    _inviteSub =
        widget.realtime.conversationCreatedEvents.listen(_onConversationInvite);
    _presenceSub =
        widget.realtime.callPresenceEvents.listen(_onCallPresence);
    _readSub = widget.realtime.readEvents.listen(_onMessageRead);
    _deletedSub =
        widget.realtime.messageDeletedEvents.listen(_onMessageDeleted);
    _pinnedSub = widget.realtime.pinnedEvents.listen(_onPinnedEvent);
    _loadPinned();
    widget.calls.addListener(_onCallChange);
    // Probe for a camera + microphone so the video-call button only
    // enables when a camera is present and the voice-call button only
    // when a mic is present. Re-probe whenever devices change (webcam or
    // headset plugged/unplugged on the POS terminal).
    _detectMediaDevices();
    navigator.mediaDevices.ondevicechange = (_) => _detectMediaDevices();
    // Desktop-only window lock during the waiting-for-acceptance
    // phase. Apply the initial state on the next frame, after
    // _loadHistory has settled _ticketAccepted from any cached
    // backlog; otherwise we'd briefly lock then immediately unlock
    // for a chat the admin already accepted.
    if (_isDesktop) {
      windowManager.addListener(this);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _applyWindowLock(_shouldLockWindow);
      });
    }
  }

  @override
  void dispose() {
    // Leaving the thread — let the global notifier alert again.
    SupportNotifier.instance.chatOpen = false;
    if (_isDesktop) {
      windowManager.removeListener(this);
      // Always release on tear-down — a parent route (HelpGuide /
      // call screen) shouldn't inherit our locked window state.
      unawaited(_applyWindowLock(false));
    }
    _msgSub?.cancel();
    _inviteSub?.cancel();
    _presenceSub?.cancel();
    _readSub?.cancel();
    _deletedSub?.cancel();
    _pinnedSub?.cancel();
    _presenceAutoClear?.cancel();
    _highlightClearTimer?.cancel();
    _ticketPoll?.cancel();
    navigator.mediaDevices.ondevicechange = null;
    widget.calls.removeListener(_onCallChange);
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Enumerate media devices and flip [_hasCamera] / [_hasMic] based on
  /// whether any `videoinput` / `audioinput` is present. Any failure (no
  /// WebRTC backend, permission denied) is treated as "not present" so the
  /// call buttons stay disabled rather than offering a call that can't
  /// capture the media it needs.
  Future<void> _detectMediaDevices() async {
    bool foundCamera = false;
    bool foundMic = false;
    try {
      final List<MediaDeviceInfo> devices =
          await navigator.mediaDevices.enumerateDevices();
      foundCamera = devices.any((d) => d.kind == 'videoinput');
      foundMic = devices.any((d) => d.kind == 'audioinput');
    } catch (_) {
      foundCamera = false;
      foundMic = false;
    }
    if (!mounted) return;
    if (_hasCamera != foundCamera || _hasMic != foundMic) {
      setState(() {
        _hasCamera = foundCamera;
        _hasMic = foundMic;
      });
    }
  }

  /// True on desktop platforms only — window_manager APIs are noop
  /// (and missing plugin registrants) on mobile.
  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// True when the chat should commandeer the foreground: scoped
  /// mode AND ticket not yet accepted AND not yet resolved-routed.
  bool get _shouldLockWindow =>
      widget.sinceMessageId != null &&
      !_ticketAccepted &&
      !_closedFromResolution;

  /// Currently-applied window-lock state. Used to short-circuit
  /// repeated setAlwaysOnTop / setPreventClose calls — the
  /// underlying Win32 API is fine being called repeatedly, but it
  /// flickers the title bar in some Windows builds.
  bool _windowLockApplied = false;

  Future<void> _applyWindowLock(bool lock) async {
    if (!_isDesktop) return;
    if (_windowLockApplied == lock) return;
    _windowLockApplied = lock;
    try {
      await windowManager.setAlwaysOnTop(lock);
      await windowManager.setPreventClose(lock);
      if (lock) {
        // Pull focus the moment the lock engages so a cashier who
        // had another app focused doesn't have to alt-tab back.
        await windowManager.show();
        await windowManager.focus();
      }
    } catch (e) {
      // Plugin can transiently fail on engine-restart / hot-reload —
      // not actionable, just log.
      debugPrint('[chat] window lock $lock failed: $e');
    }
  }

  /// WindowListener override — fires when the user clicks the X
  /// button (or Alt+F4). While the lock is engaged we refuse to
  /// close: the window comes back to the foreground instead so the
  /// waiting card stays visible. preventClose=true + this callback
  /// is what makes "force open" work for a deliberate close attempt.
  @override
  void onWindowClose() async {
    if (!_isDesktop) return;
    if (!_shouldLockWindow) {
      // Outside the locked phase, honour the close — the cashier
      // explicitly asked to quit.
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
      return;
    }
    // Locked: just re-focus.
    await windowManager.show();
    await windowManager.focus();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
          'Please stay on this screen until support accepts your ticket.',
        ),
        duration: Duration(seconds: 2),
      ));
    }
  }

  Future<void> _loadHistory() async {
    final list = await widget.chat.history(_convId);
    if (!mounted) return;
    final anchor = widget.sinceMessageId;
    // Decide where the visible history starts. Normally that's the explicit
    // `sinceMessageId` anchor. When the employee tracked a ticket by number
    // (scopedTicketId set, no anchor) there's no anchor, so derive one from
    // the "🎫 Ticket #N submitted" bubble for that ticket — the moment the
    // ticket was opened — and start there instead of dumping the entire
    // conversation backlog. If that bubble isn't in this conversation we
    // fall back to showing everything (safer than hiding the whole chat).
    int? scopedStart = anchor;
    if (scopedStart == null && widget.scopedTicketId != null) {
      for (final m in list) {
        final ev = _detectTicketEvent(m.body);
        if (ev != null &&
            ev.kind == _TicketEventKind.submitted &&
            ev.id == widget.scopedTicketId) {
          scopedStart = m.persistedId;
          break;
        }
      }
      // No "🎫 Ticket #N submitted" bubble for this ticket in the
      // conversation (e.g. a ticket filed via the customer-ticket web form,
      // which never posted a chat bubble). Start a FRESH scope — anchor past
      // the newest existing message so the store's prior backlog stays hidden
      // and only messages from here forward show — instead of dumping the
      // whole conversation history.
      if (scopedStart == null) {
        var maxId = 0;
        for (final m in list) {
          final pid = m.persistedId ?? 0;
          if (pid > maxId) maxId = pid;
        }
        scopedStart = maxId + 1;
      }
    }
    final start = scopedStart;
    final scoped = start == null
        ? list
        : list
            .where((m) => (m.persistedId ?? 0) >= start)
            .toList(growable: false);
    // Pull the ticket id out of the anchor message so we can match
    // a resolved event later. The anchor is the "🎫 Ticket #N
    // submitted…" bubble HelpGuideScreen posted on Contact Support.
    // Explicit scoping (employee entered a ticket number) wins over
    // parsing the anchor bubble.
    if (widget.scopedTicketId != null) {
      _scopedTicketId = widget.scopedTicketId;
    } else if (anchor != null) {
      ChatMessage? anchorMsg;
      for (final m in scoped) {
        if ((m.persistedId ?? 0) == anchor) {
          anchorMsg = m;
          break;
        }
      }
      if (anchorMsg != null) {
        final ev = _detectTicketEvent(anchorMsg.body);
        if (ev != null && ev.kind == _TicketEventKind.submitted) {
          _scopedTicketId = ev.id;
        }
      }
    }
    // Outside scoped mode the chat is always "open" — there's no
    // ticket to gate on. In scoped mode, check whether the loaded
    // history already contains a `👋 X has accepted ticket #N`
    // event matching the scoped ticket id (covers warm restarts
    // where the admin accepted before this screen opened); if so,
    // the waiting card never shows.
    bool initiallyAccepted;
    if (widget.initialAccepted != null) {
      // Caller already resolved the claimed/unclaimed state from the
      // ticket lookup — trust it. A later live `accepted` event still
      // flips the waiting card via _onIncoming.
      initiallyAccepted = widget.initialAccepted!;
    } else {
      initiallyAccepted = anchor == null || _scopedTicketId == null;
      if (!initiallyAccepted && _scopedTicketId != null) {
        for (final m in scoped) {
          final ev = _detectTicketEvent(m.body);
          if (ev != null &&
              ev.kind == _TicketEventKind.accepted &&
              ev.id == _scopedTicketId) {
            initiallyAccepted = true;
            break;
          }
        }
      }
    }
    _ticketAccepted = initiallyAccepted;
    // First pass: derive a fast initial state from ticket bubbles in history
    // (resolved→lock, submit/accept→open). scoped is oldest→newest so the last
    // ticket event wins; also remember the newest ticket # for the fetch below.
    int? latestBubbleTicketNo;
    for (final m in scoped) {
      final ev = _detectTicketEvent(m.body);
      if (ev != null) {
        _applyTicketLifecycle(ev);
        latestBubbleTicketNo = ev.id;
      }
    }
    // Authoritative pass: ask the server for the CURRENT status of the ticket
    // this chat is about. The "accepted"/"resolved" announcement bubbles don't
    // reliably reach this client, and info.ticketStatus is only a launch-time
    // snapshot (stale the moment a new ticket is filed) — both caused wrong
    // states (resumed-unlocked-after-resolve, and stuck "waiting to accept"
    // after an accept). getTicketsByIds is the source of truth. Falls back to
    // the launch snapshot only if the lookup fails.
    final currentTicketNo = _scopedTicketId ?? latestBubbleTicketNo;
    _pollTicketNo = currentTicketNo;
    Map<String, dynamic>? liveTicket;
    if (currentTicketNo != null) {
      liveTicket = await widget.chat.ticketStatus(currentTicketNo);
      if (!mounted) return;
    }
    final liveStatus =
        (liveTicket?['status'] ?? '').toString().toLowerCase();
    if (liveStatus == 'resolved' || liveStatus == 'closed') {
      _ticketResolved = true;
    } else if (liveStatus == 'in_progress' || liveStatus == 'assigned') {
      _ticketResolved = false;
      _ticketAccepted = true; // an agent has claimed it → composer opens
    } else if (liveStatus == 'new') {
      _ticketResolved = false;
      // Unclaimed: the scoped "waiting for support" card should show.
      if (_scopedTicketId != null) _ticketAccepted = false;
    } else if (liveTicket == null && widget.info.isTicketClosed) {
      // Lookup failed → fall back to the launch snapshot so a resolved ticket
      // still locks rather than resuming open.
      _ticketResolved = true;
    }
    // Opened straight onto a resolved/closed ticket (entered by number):
    // mark it already-closed so the back-nav guard lets the user leave
    // and a stray live resolved event can't double-fire onTicketClosed.
    if (widget.initiallyResolved) {
      _closedFromResolution = true;
    }
    // Warm-restart resolution check. If the ticket was already resolved when
    // this screen opened (history carries a `✅ … as resolved` event), show it
    // read-only for review — do NOT bounce away (the user tapped "Chat with
    // support" to look at it; auto-closing the window was the bug). Mark it
    // handled + drop the pending pointer so no live event re-fires a nav.
    if (anchor != null && _scopedTicketId != null) {
      for (final m in scoped) {
        final ev = _detectTicketEvent(m.body);
        if (ev != null &&
            ev.kind == _TicketEventKind.resolved &&
            ev.id == _scopedTicketId) {
          _closedFromResolution = true;
          _ticketResolved = true;
          unawaited(widget.store.clearPendingTicket());
          unawaited(_applyWindowLock(false));
          break;
        }
      }
    }
    setState(() {
      _messages
        ..clear()
        // chat_service.history() now returns ascending (oldest → newest)
        // so we append in order — newest ends up at the bottom of the
        // ListView where new messages from _onIncoming also land.
        // (Reversing here is what flipped the badges so #22 appeared
        // above #17 in the chat.)
        ..addAll(scoped);
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
    // Already resolved when the screen OPENS (e.g. the user tapped "Chat with
    // support" to review a closed ticket) → show it read-only, do NOT bounce
    // away (mark it handled so a later event can't fire a navigation). A resolve
    // that happens WHILE viewing an active chat DOES bounce back (see
    // _handleTicketResolved, driven by the poll). Always poll: an agent can
    // re-engage a resolved ticket from the web, and the employee unlocks live.
    if (_ticketResolved) _closedFromResolution = true;
    _startTicketPolling();
  }

  void _onIncoming(ChatMessage m) {
    if (m.conversationId != _convId) return;
    if (mounted) {
      setState(() => _messages.add(m));
      _scrollToBottom();
      // Light ping if the message is from someone else.
      if (m.senderId != _meId) {
        unawaited(RingtoneService.instance.ping());
        _notifyIfReplyToMe(m);
      }
      // /remote messages are rendered as interactive cards inline in
      // the chat (see _buildBubble). No dialog needed — user just
      // taps Allow/Deny on the bubble itself.

      // Composer lock, all modes: a live resolve closes the chat; a fresh
      // submit/accept reopens it. Keeps the unscoped main support thread in
      // sync (the scoped resolved-navigation below only covers scoped chats).
      {
        final lifeEv = _detectTicketEvent(m.body);
        if (lifeEv != null) _applyTicketLifecycle(lifeEv);
      }

      // Ticket-accepted unlock. While we're in scoped mode and the
      // ticket hasn't been accepted yet, the composer is replaced by
      // a "Waiting for support" card. The moment a matching
      // accepted event lands, flip the flag so the composer renders
      // and the employee can chat.
      if (!_ticketAccepted && _scopedTicketId != null) {
        final ev = _detectTicketEvent(m.body);
        if (ev != null &&
            ev.kind == _TicketEventKind.accepted &&
            ev.id == _scopedTicketId) {
          _ticketAccepted = true;
          // Already inside a setState above; the next build picks up
          // the new value. No SnackBar — the inline acceptance
          // badge in the chat itself is the signal.
          //
          // We intentionally keep the persisted pending pointer so an
          // accidental close after acceptance still resumes on the
          // same scoped chat. It only gets wiped on resolution.
          //
          // Release the desktop window lock — the chat is now fully
          // interactive and the cashier can switch between apps.
          unawaited(_applyWindowLock(false));
        }
      }

      // Ticket-resolved auto-close: a live "resolved" bubble bounces the
      // employee back to the chatbot (via _handleTicketResolved). The status
      // poll drives the same path even if this bubble never arrives.
      if (!_closedFromResolution) {
        final ev = _detectTicketEvent(m.body);
        if (ev != null && ev.kind == _TicketEventKind.resolved) {
          _handleTicketResolved(agentName: ev.agentName, ticketNo: ev.id);
        }
      }
    }
  }

  /// Surface a SnackBar when an incoming message quotes me. The quote
  /// prefix shape is "> @{name}: …" — we compare against the
  /// employee's `meName` so the toast only fires for replies actually
  /// addressed to this account.
  void _notifyIfReplyToMe(ChatMessage m) {
    final match = RegExp(r'^>\s*@([^:\n]+):').firstMatch(m.body);
    if (match == null) return;
    final target = (match.group(1) ?? '').trim().toLowerCase();
    if (target.isEmpty) return;
    final mine = widget.info.meName.trim().toLowerCase();
    if (target != mine) return;
    final replierName = widget.info.participants
            .firstWhere(
              (p) => p.userId == m.senderId,
              orElse: () => widget.info.participants.first,
            )
            .fullName
            .trim()
            .isEmpty
        ? 'Someone'
        : widget.info.participants
            .firstWhere((p) => p.userId == m.senderId)
            .fullName;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        children: [
          const Icon(Icons.reply, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text('$replierName replied to your message')),
        ],
      ),
      duration: const Duration(seconds: 3),
      backgroundColor: Brand.signal,
      behavior: SnackBarBehavior.floating,
    ));
  }

  /// True when `m` is an incoming `/remote` request that hasn't been
  /// resolved yet AND is addressed to this employee. The bubble
  /// renderer swaps in the interactive Allow/Deny card when this
  /// returns true.
  ///
  /// Targeting is now REQUIRED: the body must include `@{uid}` and
  /// the uid must equal `_meId`. Untargeted /remote messages don't
  /// trigger the card on anyone — that prevents the Allow/Deny
  /// prompt from leaking to every colleague in a shared thread.
  /// Admins should drive `/remote` through the Confirm button on a
  /// /request bubble (which always emits the @{uid} target) or type
  /// `/remote @{uid}` explicitly.
  bool _isPendingRemoteRequest(ChatMessage m) {
    if (m.senderId == _meId) return false;
    final body = m.body.toLowerCase();
    if (!body.contains('/remote')) return false;
    if (_resolvedRemotes.contains(m.id)) return false;
    final mention =
        RegExp(r'/remote\s+@(\d+)\b').firstMatch(body);
    if (mention == null) return false;
    final targetId = int.tryParse(mention.group(1) ?? '');
    if (targetId == null || targetId != _meId) return false;
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

  /// Post a remote-desktop-access request bubble on the employee's
  /// behalf. The body embeds `[uid:{meId}]` so the admin's Confirm
  /// button can send a /remote targeted at this exact employee —
  /// without that, /remote broadcasts to every colleague in the
  /// conversation and ALL of them see the Allow/Deny card.
  ///
  /// Avoids embedding the literal string "/remote" so the message
  /// doesn't accidentally trip the inline /remote-card renderer on
  /// other colleagues sharing the same thread.
  Future<void> _sendRemoteAccessRequest() async {
    final me = widget.info.meName.isEmpty ? 'A teammate' : widget.info.meName;
    final body =
        '🖥️ $me [uid:$_meId] is requesting a remote-desktop session. '
        'Admin: tap Confirm in your chat to start the handoff.';
    final msg = await widget.chat.send(
      convId: _convId,
      body: body,
      clientNonce: _newNonce(),
    );
    if (msg != null && mounted && !_messages.any((m) => m.id == msg.id)) {
      setState(() => _messages.add(msg));
      _scrollToBottom();
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Remote access requested — support will start the session shortly.'),
      ));
    }
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
        outcome.ticketId != null ? ' ${fmtTicketNo(outcome.ticketId!)}' : '';
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
    if (_isSending) return;
    final text = _composer.text.trim();
    // With pending attachments we allow an empty body — that just
    // sends a message with the files and no caption. Plain text-only
    // sends still require something to type.
    if (text.isEmpty && _pendingAttachments.isEmpty) return;
    // Slash-commands hijack the send action so they never hit the wire
    // as a chat message. `/ticket` opens the ticket form; on submit
    // it returns an outcome which we then post back into the chat as
    // a confirmation bubble.
    if (_isSlashCommand(text, '/ticket')) {
      _composer.clear();
      await _openTicketForm();
      return;
    }
    // Employee asks an admin to start a remote-desktop session. Accept
    // `/request`, `@request`, and the intuitive `/remote` / `@remote` too
    // (on the employee side there's nothing to target — it just means "please
    // remote in", same as /request; the admin drives the actual `/remote @uid`
    // from the request bubble). Drops a clearly-formatted ask into the thread.
    if (_isSlashCommand(text, '/request') ||
        _isSlashCommand(text, '@request') ||
        _isSlashCommand(text, '/remote') ||
        _isSlashCommand(text, '@remote')) {
      _composer.clear();
      await _sendRemoteAccessRequest();
      return;
    }
    // If a reply was queued from the message menu, prepend a quote.
    // Client-side quoting (no schema change) — the body becomes:
    //   > @sender [#{id}]: original preview…
    //   [blank]
    //   the reply
    // The `[#id]` is the target message's persisted id; the quote
    // renderer parses it back out and makes the chip clickable so the
    // viewer can jump to the original. Falls back to a plain chip
    // (no jump) when no id is available (e.g., quoting a still-
    // optimistic message).
    String finalText = text;
    final reply = _replyContext;
    if (reply != null) {
      final senderName = reply.senderId == _meId
          ? 'you'
          : (widget.info.participants
                  .firstWhere(
                    (p) => p.userId == reply.senderId,
                    orElse: () => widget.info.participants.first,
                  )
                  .fullName
                  .isNotEmpty
              ? widget.info.participants
                  .firstWhere((p) => p.userId == reply.senderId)
                  .fullName
              : 'them');
      final preview = _quotePreviewOf(reply);
      final shortPreview =
          preview.length > 200 ? '${preview.substring(0, 200)}…' : preview;
      final targetId = reply.persistedId;
      final tag = targetId != null ? ' [#$targetId]' : '';
      finalText = '> @$senderName$tag: $shortPreview\n\n$text';
      setState(() => _replyContext = null);
    }
    _composer.clear();

    // Upload phase: walk the pending queue, surfacing per-file progress
    // on each tile via setState. We upload sequentially (not in parallel)
    // so the user's network isn't fan-saturated by a 10-file batch — a
    // single bad mobile-hotspot connection would otherwise stall every
    // upload at once. Any failure aborts the batch: we keep the failed
    // tile + any not-yet-uploaded tiles visible (with their error) so the
    // user can retry without re-picking everything.
    final attachmentIds = <int>[];
    if (_pendingAttachments.isNotEmpty) {
      setState(() => _isSending = true);
      for (final p in List<_PendingAttachment>.from(_pendingAttachments)) {
        try {
          final att = await widget.chat.uploadAttachment(
            _convId,
            p.file,
            onProgress: (sent, total) {
              if (!mounted) return;
              if (total <= 0) return;
              setState(() {
                p.progress = sent / total;
                p.uploading = true;
              });
            },
          );
          attachmentIds.add(att.id);
          if (mounted) {
            setState(() {
              p.progress = 1.0;
              p.uploading = false;
              p.uploaded = true;
            });
          }
        } on UploadException catch (e) {
          if (mounted) {
            setState(() {
              p.uploading = false;
              p.errorMsg = e.message;
              _isSending = false;
            });
            _toast('Upload failed: ${e.message}');
          }
          // Put the typed text back so the user can retry without
          // losing what they wrote.
          if (text.isNotEmpty) _composer.text = text;
          return;
        } catch (e) {
          if (mounted) {
            setState(() {
              p.uploading = false;
              p.errorMsg = e.toString();
              _isSending = false;
            });
            _toast('Upload failed: $e');
          }
          if (text.isNotEmpty) _composer.text = text;
          return;
        }
      }
    }

    final msg = await widget.chat.send(
      convId: _convId,
      body: finalText,
      clientNonce: _newNonce(),
      attachmentIds: attachmentIds,
    );
    if (mounted) {
      setState(() {
        _pendingAttachments.clear();
        _isSending = false;
      });
    }
    if (msg != null && mounted) {
      // Optimistic-ish: server returned the canonical message; insert
      // unless the realtime stream already delivered it.
      if (!_messages.any((m) => m.id == msg.id)) {
        setState(() => _messages.add(msg));
        _scrollToBottom();
      }
    } else if (msg == null && mounted && widget.chat.lastSendTicketClosed) {
      // The ticket was resolved/closed server-side — lock (and bounce back to
      // the chatbot) now, the authoritative signal in case the "resolved"
      // bubble never landed. Keep the draft for a fresh ticket.
      if (text.isNotEmpty) _composer.text = text;
      _handleTicketResolved();
    }
  }

  /// File picker: multi-select. Files just go onto the [_pendingAttachments]
  /// queue — actual upload happens when the user clicks Send. Picking
  /// is disabled mid-send so a stray click can't append a file into a
  /// batch that's already uploading.
  Future<void> _attach() async {
    if (_isSending) return;
    final result = await FilePicker.platform.pickFiles(
      withData: false,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;
    final added = <_PendingAttachment>[];
    for (final pf in result.files) {
      final p = pf.path;
      if (p == null || p.isEmpty) continue;
      added.add(_PendingAttachment(File(p), pf.size));
    }
    if (added.isEmpty) {
      _toast('Could not access the selected file(s).');
      return;
    }
    setState(() => _pendingAttachments.addAll(added));
  }

  /// Remove a single pending tile from the queue. Disabled while a
  /// send is in flight (the tile is rendering its own progress bar
  /// and removing mid-upload would orphan the request).
  void _removePending(_PendingAttachment p) {
    if (_isSending) return;
    setState(() => _pendingAttachments.remove(p));
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

  void _onMessageRead(MessageRead ev) {
    if (!mounted) return;
    // Track the latest cursor per user so we can gate Unsend on
    // "nobody else has seen this yet". Only widen — never lower —
    // because messages arrive out of order on slow connections.
    final cur = _readCursorsByUser[ev.userId] ?? 0;
    if (ev.lastReadMessageId > cur) {
      setState(() => _readCursorsByUser[ev.userId] = ev.lastReadMessageId);
    }
  }

  void _onMessageDeleted(int messageId) {
    if (!mounted) return;
    final before = _messages.length;
    _messages.removeWhere((m) => m.id == messageId);
    if (_messages.length != before) setState(() {});
  }

  Future<void> _loadPinned() async {
    final pins = await widget.chat.listPinned(_convId);
    if (!mounted) return;
    setState(() => _pinned = pins);
  }

  void _onPinnedEvent(PinnedEvent e) {
    if (!mounted || e.conversationId != _convId) return;
    setState(() {
      _pinned.removeWhere((p) => p.messageId == e.messageId);
      if (e.pinned && e.entry != null) {
        _pinned.insert(0, e.entry!);
      }
    });
  }

  /// True when any other participant's read cursor has already
  /// reached [m.id]. Drives the Unsend menu-item gate. Returns false
  /// for messages that haven't been persisted yet (id is a temp
  /// string nonce, no persistedId).
  bool _isSeenByOther(ChatMessage m) {
    final mid = m.persistedId;
    if (mid == null) return false;
    for (final entry in _readCursorsByUser.entries) {
      if (entry.key == _meId) continue;
      if (entry.value >= mid) return true;
    }
    return false;
  }

  Future<void> _showMessageActions(ChatMessage m, Offset globalPos) async {
    // Optimistic / failed messages have a string nonce id, not a
    // persisted int — they can't be acted on via the server endpoints.
    final mid = m.persistedId;
    if (mid == null) return;
    final mine = m.senderId == _meId;
    final canUnsend = mine && !_isSeenByOther(m);
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPos.dx,
        globalPos.dy,
        overlay.size.width - globalPos.dx,
        overlay.size.height - globalPos.dy,
      ),
      items: [
        const PopupMenuItem(
          value: 'reply',
          height: 38,
          child: Row(children: [
            Icon(Icons.reply, size: 16, color: Brand.textPrimary),
            SizedBox(width: 10),
            Text('Reply', style: TextStyle(fontSize: 13.5)),
          ]),
        ),
        const PopupMenuItem(
          value: 'delete',
          height: 38,
          child: Row(children: [
            Icon(Icons.delete_outline, size: 16, color: Brand.textPrimary),
            SizedBox(width: 10),
            Text('Delete', style: TextStyle(fontSize: 13.5)),
          ]),
        ),
        if (canUnsend) const PopupMenuDivider(height: 4),
        if (canUnsend)
          const PopupMenuItem(
            value: 'unsend',
            height: 38,
            child: Row(children: [
              Icon(Icons.undo, size: 16, color: Brand.danger),
              SizedBox(width: 10),
              Text('Unsend',
                  style: TextStyle(
                      fontSize: 13.5,
                      color: Brand.danger,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
      ],
    );
    if (result == null || !mounted) return;
    switch (result) {
      case 'reply':
        setState(() => _replyContext = m);
        break;
      case 'delete':
        final ok = await widget.chat.hideMessageForMe(mid);
        if (!mounted) return;
        if (ok) {
          setState(() => _messages.removeWhere((x) => x.id == m.id));
        } else {
          _toast('Could not hide message.');
        }
        break;
      case 'unsend':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Unsend message?'),
            content: const Text(
                'This removes the message for everyone in the chat. You can only unsend before anyone else has read it.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: TextButton.styleFrom(foregroundColor: Brand.danger),
                  child: const Text('Unsend')),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
        final res = await widget.chat.deleteMessage(mid);
        if (!mounted) return;
        if (res['success'] == true) {
          setState(() => _messages.removeWhere((x) => x.id == m.id));
        } else {
          final msg = (res['message'] ?? 'Could not unsend message.').toString();
          _toast(msg);
        }
        break;
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
      builder: (_) => _LanPickerSheet(lan: widget.lan, myUserId: _meId),
    );
    if (picked == null || !mounted) return;

    // Same store identity (same underlying user) → they already share this
    // conversation, so there's nothing to "add" — just confirm they're here.
    if (picked.userId == _meId) {
      _toast('${picked.displayName} is on this network — '
          'already in this chat.');
      return;
    }

    final ok = await widget.chat.addToConversation(
      conversationId: _convId,
      peerUserId: picked.userId,
    );
    if (!mounted) return;
    _toast(ok
        ? 'Invited ${picked.displayName}'
        : 'Could not invite ${picked.displayName}');
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
          employeeName: _info.employeeName,
          participants: parts,
          ticketStatus: _info.ticketStatus,
          ticketNumber: _info.ticketNumber,
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
        employeeName: _info.employeeName,
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
    // While the scoped ticket is still pending (created, not yet
    // resolved), block back-navigation out of the chat. The cashier
    // must wait for support to mark it resolved — at which point
    // [_closedFromResolution] flips and we let the route pop.
    final hasPendingTicket =
        _scopedTicketId != null && !_closedFromResolution;
    return PopScope(
      canPop: !hasPendingTicket,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !hasPendingTicket) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'Ticket ${fmtTicketNo(_scopedTicketId!)} is still pending — please wait for support to resolve it before leaving.',
          ),
          duration: const Duration(seconds: 3),
        ));
      },
      child: Scaffold(
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
          // In resolved-review mode every live action is disabled — the
          // ticket is closed, so no remote/add/call, only reading.
          // Remote-desktop password is desktop-only (RustDesk lives on the
          // POS box); the mobile APK hides this entirely.
          if (kIsDesktopPlatform)
            IconButton(
              tooltip: _chatClosed
                  ? 'Ticket is resolved'
                  : (_ticketAccepted
                      ? 'Show remote-desktop password (for first-time setup)'
                      : 'Waiting for support to accept your ticket'),
              icon: const Icon(Icons.vpn_key_outlined),
              onPressed: (_ticketAccepted && !_chatClosed)
                  ? _showRemotePasswordSheet
                  : null,
            ),
          IconButton(
            tooltip: _chatClosed
                ? 'Ticket is resolved'
                : (_ticketAccepted
                    ? 'Add a colleague on this network'
                    : 'Waiting for support to accept your ticket'),
            icon: const Icon(Icons.person_add_alt_1),
            onPressed: (_ticketAccepted && !_chatClosed)
                ? _openAddParticipantSheet
                : null,
          ),
          IconButton(
            tooltip: _chatClosed
                ? 'Ticket is resolved'
                : (!_ticketAccepted
                    ? 'Waiting for support to accept your ticket'
                    : (_colleagueInCall != null
                        ? '${_colleagueInCall!.fromName} is on a call — please wait'
                        : (_hasMic == null
                            ? 'Checking for a microphone…'
                            : (_hasMic == false
                                ? 'No microphone detected'
                                : 'Voice call')))),
            icon: const Icon(Icons.call),
            // Disabled while probing (_hasMic == null) and when no mic is
            // found (_hasMic == false); only a detected microphone (== true)
            // enables it, alongside the existing gates — same treatment as
            // the video-call button below with the camera.
            onPressed:
                (!_ticketAccepted ||
                        _chatClosed ||
                        _colleagueInCall != null ||
                        _hasMic != true)
                    ? null
                    : () => _placeCall(CallMedia.voice),
          ),
          IconButton(
            tooltip: _chatClosed
                ? 'Ticket is resolved'
                : (!_ticketAccepted
                    ? 'Waiting for support to accept your ticket'
                    : (_colleagueInCall != null
                        ? '${_colleagueInCall!.fromName} is on a call — please wait'
                        : (_hasCamera == null
                            ? 'Checking for a camera…'
                            : (_hasCamera == false
                                ? 'No camera detected'
                                : 'Video call')))),
            icon: const Icon(Icons.videocam),
            // Disabled while probing (_hasCamera == null) and when no
            // camera is found (_hasCamera == false); only a detected
            // camera (== true) enables it, alongside the existing gates.
            onPressed: (!_ticketAccepted ||
                    _chatClosed ||
                    _colleagueInCall != null ||
                    _hasCamera != true)
                ? null
                : () => _placeCall(CallMedia.video),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          if (_colleagueInCall != null) _buildColleagueCallBanner(),
          if (_pinned.isNotEmpty) _buildPinnedBanner(),
          Expanded(
            // While the scoped ticket is still pending acceptance,
            // overlay a centered "waiting" card on top of the chat
            // list. The ticket bubble at the top stays visible, the
            // composer below stays mounted but disabled — the card
            // is purely a visual block, not a layout replacement,
            // so nothing reflows when the ticket gets accepted.
            child: Stack(
              children: [
                Positioned.fill(
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : _messages.isEmpty
                          ? _buildEmptyState(text)
                          : _buildList(text),
                ),
                if (!_ticketAccepted)
                  Positioned.fill(
                    child: AbsorbPointer(
                      child: Container(
                        // Soft scrim so the ticket bubble and any
                        // future admin messages are still legible
                        // behind the card, but inert.
                        color: Brand.surface.withValues(alpha: 0.72),
                        alignment: Alignment.center,
                        child: _buildAwaitingAcceptCard(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Composer stays mounted so its layout footprint never
          // changes — inputs disable themselves when !_ticketAccepted.
          _buildComposer(),
        ],
      ),
    ),
    );
  }

  /// Centered overlay shown over the message list while the scoped
  /// ticket is still pending acceptance. The composer stays mounted
  /// below (but disabled) and the ticket bubble at the top stays
  /// visible — this card is purely an attention-getter that explains
  /// what the cashier is waiting on.
  Widget _buildAwaitingAcceptCard() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
        decoration: BoxDecoration(
          color: Brand.canvas,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Brand.stroke),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: Brand.signal.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const SizedBox(
                width: 28, height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.6, color: Brand.signal),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Waiting for support to accept your ticket…',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: Brand.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _scopedTicketId != null
                  ? 'Ticket ${fmtTicketNo(_scopedTicketId!)} is in the support queue. '
                      'Chat and call options will unlock as soon as an '
                      'admin accepts it.'
                  : 'Your ticket is in the support queue. Chat and call '
                      'options will unlock as soon as an admin accepts it.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                color: Brand.textMuted,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Read-only banner of pinned support instructions, above the chat.
  Widget _buildPinnedBanner() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 132),
      decoration: const BoxDecoration(
        color: Color(0xFFFFF7ED),
        border: Border(bottom: BorderSide(color: Brand.stroke)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _pinned.map((p) {
            final text = p.body.replaceAll(RegExp(r'\s+'), ' ').trim();
            return InkWell(
              onTap: () => _showPinnedMessage(p),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.push_pin, size: 13, color: Brand.signal),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: RichText(
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        text: TextSpan(
                          style: const TextStyle(
                              fontSize: 12.5,
                              color: Brand.textPrimary,
                              height: 1.4),
                          children: [
                            TextSpan(
                              text: '${p.senderName}: ',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFC2410C),
                              ),
                            ),
                            TextSpan(text: text),
                          ],
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right,
                        size: 16, color: Brand.textMuted),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  /// Show a pinned message in full (the banner truncates to two lines).
  void _showPinnedMessage(PinnedMessage p) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.push_pin, size: 18, color: Brand.signal),
            const SizedBox(width: 8),
            const Expanded(child: Text('Pinned message')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                p.senderName,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFC2410C),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                p.body.trim(),
                style: const TextStyle(
                    fontSize: 14, color: Brand.textPrimary, height: 1.45),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
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
  /// The employee never sees which individual agent it is — the whole support
  /// team is just "Support". Rewrite system messages that embed an agent's
  /// name before they're shown. (Ticket accept/resolve badges are already
  /// generic; this covers the plain remote-session note the server stamps with
  /// the agent's name.)
  String _maskAgentName(String body) {
    if (body.contains('Remote session ended by ')) {
      return body.replaceFirst(
        RegExp(r'Remote session ended by [^\n]*'),
        'Remote session ended by support.',
      );
    }
    return body;
  }

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
    // Desktop only — remote desktop (RustDesk) doesn't exist on the mobile
    // APK, so there a /remote message just renders as a normal bubble.
    if (kIsDesktopPlatform && _isPendingRemoteRequest(m)) {
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
    // Per-message GlobalKey so jump-to-reply can ensureVisible() this
    // bubble. Stored across rebuilds in _messageKeys.
    final mid = m.persistedId;
    final bubbleKey = mid != null
        ? (_messageKeys[mid] ??= GlobalKey())
        : null;
    final isHighlighted =
        mid != null && _highlightedMessageId == mid;
    final isHovered = mid != null && _hoveredMessageId == mid;
    final canAct = mid != null;

    final bubble = AnimatedContainer(
      key: bubbleKey,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
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
        border: isHighlighted
            ? Border.all(color: Brand.signal, width: 2)
            : (mine ? null : Border.all(color: Brand.stroke)),
        boxShadow: isHighlighted
            ? [
                BoxShadow(
                  color: Brand.signal.withValues(alpha: 0.30),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: align,
        children: [
          ..._renderBodyWithQuote(_maskAgentName(m.body), mine, fg, text, m.senderId),
          if (m.attachments.isNotEmpty)
            ..._renderAttachments(m, mine, text),
        ],
      ),
    );

    // ⋮ action button — visible on hover, sits just outside the
    // bubble (left of mine, right of theirs) so it doesn't crowd the
    // bubble content. Mirrors the web admin pattern.
    //
    // Builder captures the button's own local context so the menu
    // anchors next to the button — without it, findRenderObject()
    // returns the chat screen's box and the menu pops at (0,0).
    final actionBtn = AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: isHovered ? 1 : 0,
      child: IgnorePointer(
        ignoring: !isHovered,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: Builder(builder: (btnCtx) {
            return InkWell(
              onTap: canAct
                  ? () {
                      final rb = btnCtx.findRenderObject() as RenderBox?;
                      final overlay = Overlay.of(btnCtx)
                          .context
                          .findRenderObject() as RenderBox?;
                      if (rb == null || overlay == null) return;
                      final btnPos =
                          rb.localToGlobal(Offset.zero, ancestor: overlay);
                      // Open the menu just below the button so it
                      // anchors visually to where the user clicked.
                      _showMessageActions(
                        m,
                        Offset(btnPos.dx, btnPos.dy + rb.size.height),
                      );
                    }
                  : null,
              child: Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.more_horiz,
                  size: 16,
                  color: Brand.textMuted,
                ),
              ),
            );
          }),
        ),
      ),
    );

    final children = mine
        ? <Widget>[actionBtn, const SizedBox(width: 4), Flexible(child: bubble)]
        : <Widget>[Flexible(child: bubble), const SizedBox(width: 4), actionBtn];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MouseRegion(
        onEnter: canAct ? (_) => setState(() => _hoveredMessageId = mid) : null,
        onExit: canAct
            ? (_) {
                if (_hoveredMessageId == mid) {
                  setState(() => _hoveredMessageId = null);
                }
              }
            : null,
        child: Row(
          mainAxisAlignment:
              mine ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: children,
        ),
      ),
    );
  }

  /// Splits a message body into an optional "quoted reply" chip and
  /// the main reply text. Detects the format the composer emits:
  ///
  ///     > @sender [#42]: original preview…       ← `[#42]` optional
  ///     [blank line]
  ///     the reply
  ///
  /// When the quote prefix contains `[#id]`, the chip is tappable and
  /// scrolls the chat to the target message + flashes it. Without the
  /// id (older replies pre-dating the embed) the chip is static.
  List<Widget> _renderBodyWithQuote(
      String body, bool mine, Color fg, TextTheme text, int bubbleSenderId) {
    if (body.isEmpty) return const [];
    // The \r?\n\r?\n separator covers both LF and CRLF — HTML form
    // POSTs (from the web admin) normalize line breaks to CRLF, so
    // anything stored after a web-side send has \r\n\r\n between the
    // quote prefix and the reply.
    final match = RegExp(
            r'^>\s*@([^\[:\n]+?)(?:\s*\[#(\d+)\])?\s*:[ \t]*([^\n]*?)(?:\r?\n\r?\n([\s\S]+))?$')
        .firstMatch(body);
    if (match == null) {
      return [Text(body, style: text.bodyMedium?.copyWith(color: fg))];
    }
    final sender = (match.group(1) ?? '').trim();
    final targetIdRaw = match.group(2);
    final targetId = targetIdRaw != null ? int.tryParse(targetIdRaw) : null;
    // Legacy replies (sent before the preview-strip fix) baked nested
    // quote prefixes into the chip text. Strip leading "> @sender: "
    // segments at render time so the chip displays only the actual
    // content the sender wrote, regardless of how the body was stored.
    final preview =
        _stripNestedQuotes((match.group(3) ?? '').trim()).isEmpty
            ? '[attachment]'
            : _stripNestedQuotes((match.group(3) ?? '').trim());
    final reply = (match.group(4) ?? '').trim();
    // Quote-chip palette: on my (orange) bubbles the chip needs to
    // contrast against orange, so we use white-tinted; on theirs the
    // chip uses the standard subtle/stroke neutrals.
    final quoteBg = mine
        ? Colors.white.withValues(alpha: 0.18)
        : Brand.subtle;
    final quoteAccent = mine
        ? Colors.white.withValues(alpha: 0.55)
        : Brand.signal;
    final quoteSender = mine
        ? Colors.white.withValues(alpha: 0.95)
        : Brand.signal;
    final quoteText = mine
        ? Colors.white.withValues(alpha: 0.78)
        : Brand.textMuted;
    final chip = Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(8, 5, 10, 6),
      decoration: BoxDecoration(
        color: quoteBg,
        borderRadius: BorderRadius.circular(6),
        border: Border(left: BorderSide(color: quoteAccent, width: 2.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            sender,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: quoteSender,
              letterSpacing: -0.05,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            preview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              color: quoteText,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
    return [
      Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _jumpToQuoteTarget(
              targetId, sender, preview, bubbleSenderId),
          borderRadius: BorderRadius.circular(6),
          child: chip,
        ),
      ),
      if (reply.isNotEmpty)
        Text(reply, style: text.bodyMedium?.copyWith(color: fg)),
    ];
  }

  /// Resolve a quote-chip tap to a specific message id. Prefers the
  /// `[#id]` embedded in the prefix; falls back to a sender+preview
  /// search. If the target isn't in the loaded window, auto-loads
  /// older pages until found or history is exhausted.
  Future<void> _jumpToQuoteTarget(int? embeddedId, String sender,
      String preview, int bubbleSenderId) async {
    final hitId =
        _findQuoteTarget(embeddedId, sender, preview, bubbleSenderId);
    if (hitId != null) {
      _jumpToMessage(hitId);
      return;
    }
    // Page older. Hard-cap at 20 pages so a pathological input can't
    // hammer the server.
    for (var i = 0; i < 20; i++) {
      final oldestId = _messages
          .map((m) => m.persistedId)
          .whereType<int>()
          .fold<int?>(null, (acc, id) => acc == null || id < acc ? id : acc);
      if (oldestId == null) break;
      // Don't page past the ticket anchor — pre-anchor history is
      // intentionally hidden in scoped mode.
      final anchor = widget.sinceMessageId;
      if (anchor != null && oldestId <= anchor) break;
      final older = await widget.chat.history(_convId, beforeId: oldestId);
      if (!mounted) return;
      if (older.isEmpty) break;
      final scopedOlder = anchor == null
          ? older
          : older
              .where((m) => (m.persistedId ?? 0) >= anchor)
              .toList(growable: false);
      if (scopedOlder.isEmpty) break;
      setState(() {
        _messages.insertAll(0, scopedOlder);
      });
      final retry =
          _findQuoteTarget(embeddedId, sender, preview, bubbleSenderId);
      if (retry != null) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (!mounted) return;
        _jumpToMessage(retry);
        return;
      }
    }
    _toast('Original message not found in this conversation.');
  }

  /// Search the currently-loaded [_messages] for the message a quote
  /// chip references. "you" in the quote prefix is resolved against
  /// `bubbleSenderId` — the user who *sent* the quoting bubble — not
  /// the viewer, because that's whose POV the quote was written from.
  int? _findQuoteTarget(int? embeddedId, String sender, String preview,
      int bubbleSenderId) {
    if (embeddedId != null) {
      for (final m in _messages) {
        if (m.persistedId == embeddedId) return embeddedId;
      }
      return null;
    }
    final senderLower = sender.toLowerCase();
    final previewNorm =
        preview.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
    for (final m in _messages) {
      final mid = m.persistedId;
      if (mid == null) continue;
      final body = m.body.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (!body.toLowerCase().startsWith(previewNorm)) continue;
      if (senderLower == 'you') {
        if (m.senderId != bubbleSenderId) continue;
      } else {
        final p = widget.info.participants.firstWhere(
          (p) => p.userId == m.senderId,
          orElse: () => widget.info.participants.first,
        );
        if (p.fullName.toLowerCase() != senderLower) continue;
      }
      return mid;
    }
    return null;
  }

  /// Strips leading `> @sender [#id]?:` segments from a chip's
  /// preview text. Older replies (sent before the preview was
  /// cleaned at send time) embedded nested quote prefixes inside
  /// the chip — applying this at render time hides that gunk so the
  /// chip shows just the actual content the original sender wrote.
  String _stripNestedQuotes(String preview) {
    final re = RegExp(
        r'^>\s*@[^\[:\n]+?(?:\s*\[#\d+\])?\s*:\s*');
    var s = preview;
    for (var i = 0; i < 8 && re.hasMatch(s); i++) {
      s = s.replaceFirst(re, '').trim();
    }
    return s;
  }

  String _quotePreviewOf(ChatMessage m) {
    final stripQuote = RegExp(
            r'^>\s*@[^\[:\n]+?(?:\s*\[#\d+\])?\s*:[ \t]*[^\n]*?(?:\r?\n\r?\n([\s\S]+))?$')
        .firstMatch(m.body);
    final cleaned =
        stripQuote != null ? (stripQuote.group(1) ?? '').trim() : m.body;
    final preview = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (preview.isNotEmpty) return preview;
    if (m.attachments.isEmpty) return '';
    final first = m.attachments.first;
    final label = first.mimeType.startsWith('image/')
        ? '[image]'
        : '[file: ${first.originalName}]';
    return m.attachments.length > 1
        ? '$label +${m.attachments.length - 1}'
        : label;
  }

  /// Highlights the target message + scrolls it into view when the
  /// quote chip is tapped. Uses a per-message GlobalKey looked up
  /// from [_messageKeys] (populated in the list builder) and a
  /// transient _highlightedMessageId so the bubble flashes briefly.
  final Map<int, GlobalKey> _messageKeys = {};
  int? _highlightedMessageId;
  Timer? _highlightClearTimer;

  Future<void> _jumpToMessage(int messageId) async {
    // The bubble is rendered via ListView.builder which destroys
    // off-screen children. If currentContext is null, scroll
    // approximately to the target's index first so the lazy builder
    // mounts the row, then call ensureVisible for precise alignment.
    final ctxQuickAccess = _messageKeys[messageId]?.currentContext;
    if (ctxQuickAccess == null) {
      final idx = _messages.indexWhere((m) => m.persistedId == messageId);
      if (idx < 0) {
        _toast('Original message not in this view.');
        return;
      }
      // ~80px is a reasonable per-bubble average (text + padding +
      // bottom margin). Doesn't need to be exact — we follow up with
      // ensureVisible which centers precisely.
      const approxItemExtent = 80.0;
      final target = (idx * approxItemExtent)
          .clamp(_scroll.position.minScrollExtent,
                 _scroll.position.maxScrollExtent);
      await _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
      // Let the builder mount the row that just scrolled into view.
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!mounted) return;
    }
    final ctx = _messageKeys[messageId]?.currentContext;
    if (ctx != null && ctx.mounted) {
      // ignore: use_build_context_synchronously
      await Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: 0.35,
      );
    }
    if (!mounted) return;
    setState(() => _highlightedMessageId = messageId);
    _highlightClearTimer?.cancel();
    _highlightClearTimer = Timer(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      setState(() => _highlightedMessageId = null);
    });
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
        'Ticket ${fmtTicketNo(ev.id)} submitted',
        ev.subject.isEmpty ? null : '"${ev.subject}"',
      ),
      _TicketEventKind.accepted => (
        Icons.check_circle_outline,
        const Color(0xFF2563EB),
        // Privacy: never surface the support agent's username — always
        // show a generic line regardless of who accepted the ticket.
        'Support agent accepted ticket ${fmtTicketNo(ev.id)}',
        ev.subject.isEmpty ? "We'll help you from here." : '"${ev.subject}"',
      ),
      _TicketEventKind.resolved => (
        Icons.task_alt_outlined,
        Brand.success,
        'Ticket ${fmtTicketNo(ev.id)} resolved',
        // Privacy: never surface the agent's username — always "by support".
        'by support',
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
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (dialogCtx) {
        return FutureBuilder<TicketDetail?>(
          future: tickets.getTicketDetail(ticketId),
          builder: (ctx, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return _TicketDetailDialogShell(
                ticketId: ticketId,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 56),
                  child: Center(
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Brand.signal)),
                ),
              );
            }
            final d = snap.data;
            if (d == null) {
              return _TicketDetailDialogShell(
                ticketId: ticketId,
                child: const Padding(
                  padding: EdgeInsets.fromLTRB(28, 8, 28, 32),
                  child: Text(
                    "Couldn't load this ticket. It may have been removed.",
                    style: TextStyle(color: Brand.textMuted, fontSize: 13.5),
                  ),
                ),
              );
            }
            return _TicketDetailDialog(detail: d);
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
    // The employee never sees which individual agent it is — the whole team is
    // just "Support". (m.senderId identifies the agent internally for the RustDesk
    // handoff, but their name is never surfaced here.)
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
                      'Support wants remote access',
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
    final images = m.attachments.where((a) => a.isImage).toList();
    final files = m.attachments.where((a) => !a.isImage).toList();
    final widgets = <Widget>[];
    if (images.length >= 2) {
      // Collapse 2+ images into a single stacked-card preview so a
      // 5-attachment message doesn't take up the entire chat pane.
      // Tapping the stack opens a swipeable gallery showing all of
      // them.
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 6),
        child: _buildImageStack(images),
      ));
    } else if (images.length == 1) {
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 6),
        child: InkWell(
          onTap: () => _showImageGallery(images, 0),
          borderRadius: BorderRadius.circular(10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                  maxWidth: 240, maxHeight: 240, minWidth: 120),
              child: _AuthImage(
                dio: widget.api.rawDio,
                url: widget.chat.attachmentUrl(images.first.id),
                fit: BoxFit.cover,
                cacheWidth: 480,
              ),
            ),
          ),
        ),
      ));
    }
    for (final att in files) {
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 6),
        child: InkWell(
          onTap: () => _showAttachmentOptions(att),
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
      ));
    }
    return widgets;
  }

  /// Polaroid-style stacked-card preview for multi-image attachments.
  /// The top card sits straight; up-to-2 peek cards behind it are
  /// rotated at opposing angles (±0.08 rad ≈ ±4.5°) so the back
  /// images poke out from underneath the top card and the user can
  /// see they're real images, not just blank rectangles. Each peek
  /// shows the matching image from [images] so a 3-photo message
  /// previews all 3. A count badge in the bottom-right shows the
  /// total; tapping anywhere opens the gallery.
  Widget _buildImageStack(List<ChatAttachment> images) {
    const tile = 220.0;
    // Cap visible layers at 3 (top + 2 peeks). Beyond that, the count
    // badge does the heavy lifting and stacking more cards just makes
    // the bubble taller for no extra information.
    final visible = images.take(3).toList();
    // Rotation angles for the peek cards: index 0 is the top (no
    // rotation), 1 tilts right, 2 tilts left — mirrors the natural
    // "scattered photo" look from the user's reference image.
    const angles = [0.0, 0.08, -0.08];
    // Outer canvas needs slack for the rotation overflow + downward
    // peek so the rotated corners don't clip.
    return InkWell(
      onTap: () => _showImageGallery(images, 0),
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: tile + 36,
        height: tile + 36,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // Render back-to-front: last visible card is deepest, so
            // we iterate from the end and let the natural Stack z-order
            // bring the first image to the top.
            for (int i = visible.length - 1; i >= 0; i--)
              Transform.rotate(
                angle: angles[i],
                child: Container(
                  width: tile,
                  height: tile,
                  decoration: BoxDecoration(
                    color: Brand.canvas,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Brand.stroke, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  // Inner padding gives the polaroid-like white border
                  // around each photo — also stops a fully-black image
                  // from visually merging with its neighbour.
                  padding: const EdgeInsets.all(3),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: _AuthImage(
                      dio: widget.api.rawDio,
                      url: widget.chat.attachmentUrl(visible[i].id),
                      fit: BoxFit.cover,
                      cacheWidth: 480,
                    ),
                  ),
                ),
              ),
            // Count badge sits on top of the un-rotated top card.
            Positioned(
              right: 14,
              bottom: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.photo_library_outlined,
                        size: 13, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(
                      '${images.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Tap on a non-image attachment — bottom sheet offering Open
  /// (download → temp → OS handler) or Save to Downloads. Useful
  /// because the file might be a zip / installer / spreadsheet and we
  /// can't preview it; either let the OS open it or let the user
  /// stash it in their Downloads for later.
  Future<void> _showAttachmentOptions(ChatAttachment att) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(att.originalName,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                    '${att.mimeType.isEmpty ? "file" : att.mimeType} · ${_formatBytes(att.byteSize)}'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: const Text('Open'),
                subtitle: const Text('Hand off to the OS default app'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _openAttachment(att);
                },
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Save to Downloads'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _saveAttachmentToDownloads(att);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// Swipeable full-screen gallery for one or more image attachments
  /// from the same message. The PageView lets the user flick left/
  /// right between images; the Save button targets whichever image
  /// is on screen, and the filename badge updates live with the page.
  Future<void> _showImageGallery(
    List<ChatAttachment> images,
    int initialIndex,
  ) async {
    if (images.isEmpty) return;
    final pageCtrl = PageController(initialPage: initialIndex);
    var currentIndex = initialIndex;
    // Keyboard nav: ← / → page between images, Esc closes. Wrapping
    // in a Focus with autofocus puts key events on the gallery while
    // the dialog is up; the InteractiveViewer/PageView don't claim
    // arrow keys so this stays free.
    void prev() {
      if (pageCtrl.page != null && pageCtrl.page! > 0) {
        pageCtrl.previousPage(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    }

    void next() {
      if (pageCtrl.page != null && pageCtrl.page! < images.length - 1) {
        pageCtrl.nextPage(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    }

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setLocal) {
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(16),
            child: Focus(
              autofocus: true,
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                  prev();
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                  next();
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.escape) {
                  Navigator.of(ctx).pop();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Stack(
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(ctx).pop(),
                  child: const SizedBox.expand(),
                ),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                        maxWidth: 1100, maxHeight: 800),
                    child: PageView.builder(
                      controller: pageCtrl,
                      itemCount: images.length,
                      onPageChanged: (i) =>
                          setLocal(() => currentIndex = i),
                      itemBuilder: (_, i) {
                        return InteractiveViewer(
                          panEnabled: true,
                          minScale: 0.5,
                          maxScale: 4.0,
                          child: _AuthImage(
                            dio: widget.api.rawDio,
                            url: widget.chat.attachmentUrl(images[i].id),
                            fit: BoxFit.contain,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                // Page indicator — pill in the top-center showing
                // "2 / 5" when there's more than one image.
                if (images.length > 1)
                  Positioned(
                    top: 12, left: 0, right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${currentIndex + 1} / ${images.length}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                // Prev / next arrow buttons. Only shown when there's
                // more than one image; each is disabled at the
                // appropriate end so the user can't page past the
                // bounds. Pages animate so the swipe feel and the
                // arrow-click feel match.
                if (images.length > 1) ...[
                  Positioned(
                    left: 12, top: 0, bottom: 0,
                    child: Center(
                      child: Material(
                        color: Colors.black.withValues(alpha: 0.55),
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: 'Previous',
                          icon: const Icon(Icons.chevron_left,
                              color: Colors.white, size: 28),
                          onPressed: currentIndex == 0
                              ? null
                              : () => pageCtrl.previousPage(
                                    duration:
                                        const Duration(milliseconds: 220),
                                    curve: Curves.easeOut,
                                  ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 12, top: 0, bottom: 0,
                    child: Center(
                      child: Material(
                        color: Colors.black.withValues(alpha: 0.55),
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: 'Next',
                          icon: const Icon(Icons.chevron_right,
                              color: Colors.white, size: 28),
                          onPressed: currentIndex == images.length - 1
                              ? null
                              : () => pageCtrl.nextPage(
                                    duration:
                                        const Duration(milliseconds: 220),
                                    curve: Curves.easeOut,
                                  ),
                        ),
                      ),
                    ),
                  ),
                ],
                Positioned(
                  top: 8, right: 8,
                  child: Row(
                    children: [
                      Material(
                        color: Colors.black.withValues(alpha: 0.55),
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: 'Save to Downloads',
                          icon: const Icon(Icons.download_outlined,
                              color: Colors.white),
                          onPressed: () =>
                              _saveAttachmentToDownloads(images[currentIndex]),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Material(
                        color: Colors.black.withValues(alpha: 0.55),
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: 'Close',
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 12, bottom: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${images[currentIndex].originalName} · '
                      '${_formatBytes(images[currentIndex].byteSize)}',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
            ),
          );
        });
      },
    );
    pageCtrl.dispose();
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

  /// Copy the attachment to the user's Downloads folder under its
  /// original filename, de-duplicating with `(1)`, `(2)`, … if the
  /// name is taken. Cookie auth carries via the shared Dio instance.
  Future<void> _saveAttachmentToDownloads(ChatAttachment att) async {
    try {
      final downloads = await getDownloadsDirectory();
      final dirPath = downloads?.path ?? Directory.systemTemp.path;
      var target = File('$dirPath${Platform.pathSeparator}${att.originalName}');
      if (await target.exists()) {
        final dot = att.originalName.lastIndexOf('.');
        final base =
            dot > 0 ? att.originalName.substring(0, dot) : att.originalName;
        final ext = dot > 0 ? att.originalName.substring(dot) : '';
        var i = 1;
        while (await target.exists()) {
          target = File('$dirPath${Platform.pathSeparator}$base ($i)$ext');
          i++;
        }
      }
      final url = widget.chat.attachmentUrl(att.id);
      await widget.api.rawDio.download(url, target.path);
      if (mounted) _toast('Saved to ${target.path}');
    } catch (e) {
      if (mounted) _toast('Save failed: $e');
    }
  }

  Widget _buildComposer() {
    // Resolved-review mode: the thread is read-only — show a banner instead
    // of the input so the employee can read the history but can't keep
    // chatting on a closed ticket. Covers both opening straight onto a
    // resolved ticket (initiallyResolved) and a live resolve landing while
    // the chat is open (_ticketResolved), including the main support thread.
    if (_chatClosed) {
      return Container(
        decoration: const BoxDecoration(
          color: Brand.canvas,
          border: Border(top: BorderSide(color: Brand.stroke)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
        child: Row(
          children: [
            const Icon(Icons.lock_outline, size: 18, color: Brand.textMuted),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'This ticket is resolved — you can review it but can’t send '
                'new messages. File a new ticket if you need more help.',
                style: TextStyle(
                    fontSize: 12.5, color: Brand.textMuted, height: 1.4),
              ),
            ),
          ],
        ),
      );
    }
    // Disabled in two scenarios that share the same UX: mid-upload
    // (existing) and pre-acceptance (new). Both grey out the row so
    // a stray click can't desync state. We keep them separate
    // because the hints differ — uploading says "Uploading…", waiting
    // says "Waiting for support to accept your ticket".
    final waiting = !_ticketAccepted;
    final disabled = _isSending || waiting;
    final hint = waiting
        ? 'Waiting for support to accept your ticket…'
        : (_isSending ? 'Uploading…' : 'Type a message');
    return Container(
      decoration: BoxDecoration(
        color: Brand.canvas,
        border: Border(top: BorderSide(color: Brand.stroke)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_replyContext != null) _buildReplyBar(),
          if (_pendingAttachments.isNotEmpty) _buildPendingAttachmentsStrip(),
          Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            icon: const Icon(Icons.attach_file),
            tooltip: waiting
                ? 'Waiting for support to accept your ticket'
                : (_isSending ? 'Uploading…' : 'Attach a file'),
            onPressed: disabled ? null : _attach,
          ),
          Expanded(
            child: TextField(
              controller: _composer,
              minLines: 1,
              maxLines: 5,
              enabled: !disabled,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: hint,
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(width: 4),
          FilledButton.icon(
            onPressed: disabled ? null : _send,
            icon: _isSending
                ? const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send, size: 16),
            label: Text(_isSending ? 'Sending' : 'Send'),
          ),
        ],
      ),
        ],
      ),
    );
  }

  /// Horizontally-scrollable strip of preview tiles for every file
  /// the user has queued but not yet sent. Sits between the reply
  /// bar (if any) and the composer row.
  Widget _buildPendingAttachmentsStrip() {
    return Container(
      height: 78,
      margin: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: _pendingAttachments.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => _buildPendingTile(_pendingAttachments[i]),
      ),
    );
  }

  Widget _buildPendingTile(_PendingAttachment p) {
    final name = p.file.path.split(Platform.pathSeparator).last;
    final isImage = _looksLikeImage(name);
    final sizeLabel = _formatBytes(p.sizeBytes);
    return Container(
      width: 180,
      decoration: BoxDecoration(
        color: Brand.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Brand.stroke),
      ),
      padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 40, height: 40,
              child: isImage
                  ? Image.file(p.file, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _genericFileIcon())
                  : _genericFileIcon(),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                if (p.errorMsg != null)
                  Text('Failed: ${p.errorMsg}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 10, color: Colors.redAccent))
                else if (p.uploading || p.progress > 0)
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: p.progress.clamp(0.0, 1.0),
                            minHeight: 4,
                            backgroundColor: Brand.stroke,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text('${(p.progress * 100).clamp(0, 100).toInt()}%',
                          style: const TextStyle(
                              fontSize: 10, color: Brand.textMuted)),
                    ],
                  )
                else
                  Text(sizeLabel,
                      style: const TextStyle(
                          fontSize: 10, color: Brand.textMuted)),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
            icon: const Icon(Icons.close, size: 14),
            tooltip: 'Remove',
            onPressed: _isSending ? null : () => _removePending(p),
          ),
        ],
      ),
    );
  }

  Widget _genericFileIcon() => Container(
        color: Brand.canvas,
        alignment: Alignment.center,
        child: const Icon(Icons.insert_drive_file_outlined,
            size: 22, color: Brand.textMuted),
      );

  static bool _looksLikeImage(String filename) {
    final lower = filename.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp');
  }

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    var n = bytes.toDouble();
    while (n >= 1024 && i < units.length - 1) {
      n /= 1024;
      i++;
    }
    return '${n.toStringAsFixed(n < 10 && i > 0 ? 1 : 0)} ${units[i]}';
  }

  /// Quote preview shown above the composer while a reply is active.
  /// The Send handler reads _replyContext and prepends a quoted line
  /// to the body before posting, then clears the context.
  Widget _buildReplyBar() {
    final r = _replyContext!;
    final senderName = r.senderId == _meId
        ? 'you'
        : (widget.info.participants
                .firstWhere(
                  (p) => p.userId == r.senderId,
                  orElse: () => widget.info.participants.first,
                )
                .fullName
                .isNotEmpty
            ? widget.info.participants
                .firstWhere((p) => p.userId == r.senderId)
                .fullName
            : 'them');
    final preview = _quotePreviewOf(r);
    final shortPreview =
        preview.length > 140 ? '${preview.substring(0, 140)}…' : preview;
    return Container(
      margin: const EdgeInsets.fromLTRB(4, 0, 4, 6),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        color: Brand.signal.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border(
            left: BorderSide(color: Brand.signal, width: 3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.reply, size: 14, color: Brand.signal),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              text: TextSpan(
                style: const TextStyle(fontSize: 12, color: Brand.textPrimary),
                children: [
                  TextSpan(
                    text: senderName,
                    style: const TextStyle(
                      color: Brand.signal,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const TextSpan(text: '  '),
                  TextSpan(
                    text: shortPreview.isEmpty ? '(empty)' : shortPreview,
                    style: const TextStyle(color: Brand.textMuted),
                  ),
                ],
              ),
            ),
          ),
          InkWell(
            onTap: () => setState(() => _replyContext = null),
            borderRadius: BorderRadius.circular(4),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, size: 14, color: Brand.textMuted),
            ),
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
  const _LanPickerSheet({required this.lan, required this.myUserId});
  final LanPresence lan;
  final int myUserId;

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
                        Text('Colleagues on this network',
                            style: text.titleMedium),
                        Text(
                          'Employees with the app open nearby',
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
                              "Make sure they're on the same network and the "
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
                      // Same underlying identity (same store) → they already
                      // share this chat; show them as simply "online". A peer
                      // from a different store can be added to the thread.
                      final sameStore = p.userId == myUserId;
                      final initial = p.displayName.isNotEmpty
                          ? p.displayName.characters.first.toUpperCase()
                          : '?';
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Brand.signal,
                          child: Text(initial,
                              style: const TextStyle(
                                  color: Brand.canvas,
                                  fontWeight: FontWeight.w700)),
                        ),
                        title: Text(p.displayName),
                        subtitle: Text(
                          sameStore
                              ? 'Online · ${p.address}'
                              : '${p.storeName} · ${p.address}',
                          style: text.bodySmall
                              ?.copyWith(color: Brand.textMuted),
                        ),
                        trailing: sameStore
                            ? const _OnlineDot()
                            : const Icon(Icons.person_add_alt_1,
                                color: Brand.signal),
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

/// Small green "online" indicator for same-store colleagues in the roster.
class _OnlineDot extends StatelessWidget {
  const _OnlineDot();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: const BoxDecoration(
            color: Color(0xFF22C55E),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        const Text('Online',
            style: TextStyle(
                fontSize: 12,
                color: Brand.textMuted,
                fontWeight: FontWeight.w600)),
      ],
    );
  }
}

/// Centered desktop dialog shell for the ticket detail flow. Shared by
/// the loading / error / loaded states so the transition between them
/// doesn't jump. Replaces an earlier bottom-sheet design that read as
/// mobile-style on a 1920px POS workstation.
class _TicketDetailDialogShell extends StatelessWidget {
  const _TicketDetailDialogShell({
    required this.ticketId,
    required this.child,
  });
  final int ticketId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Brand.canvas,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 48),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 560,
          maxHeight: 640,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header row — small "Ticket #N" label on the left, close
            // affordance on the right. Reads like Linear/Notion dialogs.
            Container(
              padding: const EdgeInsets.fromLTRB(24, 18, 12, 14),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Brand.stroke),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Brand.signal.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.confirmation_number_outlined,
                      size: 15,
                      color: Brand.signal,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Ticket #$ticketId',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Brand.textPrimary,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(8),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.close,
                          size: 18, color: Brand.textMuted),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(child: child),
          ],
        ),
      ),
    );
  }
}

/// Renders the full ticket record inside the centered dialog.
/// Layout: status + priority pills, subject, description, then a
/// 2-column meta grid (Customer/Business/Agent/Created/Updated) so we
/// use the dialog's horizontal space efficiently instead of stacking
/// every key/value on its own line.
class _TicketDetailDialog extends StatelessWidget {
  const _TicketDetailDialog({required this.detail});
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

    final metaTiles = <Widget>[
      if (detail.customerName.isNotEmpty)
        _MetaTile(
            icon: Icons.person_outline,
            label: 'Customer',
            value: detail.customerName),
      if (detail.businessName.isNotEmpty)
        _MetaTile(
            icon: Icons.storefront_outlined,
            label: 'Business',
            value: detail.businessName),
      _MetaTile(
        icon: Icons.support_agent_outlined,
        label: 'Assigned to',
        value:
            detail.agentName.isEmpty ? 'Unassigned' : detail.agentName,
        muted: detail.agentName.isEmpty,
      ),
      if (detail.createdAt.isNotEmpty)
        _MetaTile(
            icon: Icons.event_outlined,
            label: 'Created',
            value: detail.createdAt),
      if (detail.updatedAt.isNotEmpty &&
          detail.updatedAt != detail.createdAt)
        _MetaTile(
            icon: Icons.update_outlined,
            label: 'Last update',
            value: detail.updatedAt),
    ];

    return _TicketDetailDialogShell(
      ticketId: detail.id,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
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
            const SizedBox(height: 18),
            Text(
              detail.subject.isEmpty ? '(no subject)' : detail.subject,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: Brand.textPrimary,
                letterSpacing: -0.3,
                height: 1.25,
              ),
            ),
            if (detail.description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Brand.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: Brand.stroke.withValues(alpha: 0.65)),
                ),
                child: Text(
                  detail.description,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: Brand.textPrimary,
                    height: 1.5,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            // 2-column meta grid. LayoutBuilder so it cleanly collapses
            // to a single column if the dialog is constrained narrow.
            LayoutBuilder(
              builder: (context, constraints) {
                final twoCol = constraints.maxWidth >= 420;
                if (!twoCol) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final t in metaTiles)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: t,
                        ),
                    ],
                  );
                }
                return Wrap(
                  spacing: 20,
                  runSpacing: 12,
                  children: [
                    for (final t in metaTiles)
                      SizedBox(
                        width: (constraints.maxWidth - 20) / 2,
                        child: t,
                      ),
                  ],
                );
              },
            ),
          ],
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

/// Two-line meta tile for the desktop dialog's 2-column grid. Top
/// line is the label (small + muted), bottom line is the value
/// (bold). Reads as a key/value card rather than a table row, which
/// scans cleaner on wide surfaces.
class _MetaTile extends StatelessWidget {
  const _MetaTile({
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(icon, size: 13, color: Brand.textMuted),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11.5,
                color: Brand.textMuted,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Padding(
          padding: const EdgeInsets.only(left: 19),
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontStyle: muted ? FontStyle.italic : FontStyle.normal,
              color: muted ? Brand.textMuted : Brand.textPrimary,
              fontWeight: muted ? FontWeight.w500 : FontWeight.w600,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

/// Network image fetched through Dio so the PHPSESSID cookie carries
/// — Flutter's stock NetworkImage uses HttpClient (no cookies) and
/// the `chat.downloadAttachment` endpoint would 401. Bytes are cached
/// in widget state for the lifetime of this widget; the chat list
/// recycling re-instantiates `_AuthImage` per visible bubble which is
/// fine for current message volumes.
class _AuthImage extends StatefulWidget {
  const _AuthImage({
    required this.dio,
    required this.url,
    this.fit = BoxFit.cover,
    this.cacheWidth,
  });
  final Dio dio;
  final String url;
  final BoxFit fit;
  final int? cacheWidth;

  @override
  State<_AuthImage> createState() => _AuthImageState();
}

class _AuthImageState extends State<_AuthImage> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final res = await widget.dio.get<List<int>>(
        widget.url,
        options: Options(
          responseType: ResponseType.bytes,
          // Don't blow up on non-2xx — surface them as failed state.
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      if (!mounted) return;
      if (res.statusCode == 200 && res.data != null) {
        setState(() => _bytes = Uint8List.fromList(res.data!));
      } else {
        setState(() => _failed = true);
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Container(
        color: Brand.subtle,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(16),
        child: const Icon(Icons.broken_image_outlined,
            color: Brand.textMuted),
      );
    }
    if (_bytes == null) {
      return Container(
        color: Brand.subtle,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(16),
        child: const SizedBox(
          width: 18, height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return Image.memory(
      _bytes!,
      fit: widget.fit,
      cacheWidth: widget.cacheWidth,
      gaplessPlayback: true,
    );
  }
}

/// A file the user has picked but not yet sent. Lives in
/// `_EmployeeChatScreenState._pendingAttachments` while the preview
/// tile is on screen, and during the [_send] upload phase its
/// progress/uploading/errorMsg fields are mutated in-place to drive
/// the tile's per-file LinearProgressIndicator.
class _PendingAttachment {
  _PendingAttachment(this.file, this.sizeBytes);
  final File file;
  final int sizeBytes;
  double progress = 0.0;
  bool uploading = false;
  bool uploaded = false;
  String? errorMsg;
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
