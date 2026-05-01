import 'dart:async';

import 'package:flutter/material.dart';

import '../api_client.dart';
import '../push_service.dart';
import '../services/chat_prefs.dart';
import '../services/call_service.dart';
import '../services/chat_realtime.dart';
import '../services/chat_service.dart';
import '../services/chat_state.dart';
import '../services/incoming_call_service.dart';
import '../services/notification_center.dart';
import '../services/services.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'auth_screens.dart';
import 'call_screen.dart';
import 'chat_inbox_screen.dart';
import 'chat_screen.dart'; // ignore: unused_import — retained in case we revert
import 'chat_thread_screen.dart';
import 'dashboard_screen.dart';
import 'customer_list_screen.dart';
import 'lead_list_screen.dart';
// TICKET tab is parked while CHAT takes its slot. Keep the import + screen
// wiring around so we can flip it back without rewriting the shell.
import 'ticket_list_screen.dart'; // ignore: unused_import
import 'menu_screen.dart';

/// The five bottom-nav destinations for the main app shell. Every other
/// section (Blog, Release Notes, Activity Logs, etc.) lives in the Menu tab.
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.api,
    required this.push,
    required this.auth,
    required this.dashboard,
    required this.customers,
    required this.leads,
    required this.tickets,
    required this.chatPrefs,
  });

  final ApiClient api;
  final PushService push;
  final AuthService auth;
  final DashboardService dashboard;
  final CustomerService customers;
  final LeadService leads;
  final TicketService tickets;
  final ChatPrefs chatPrefs;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;
  late final NotificationCenter _notifications;

  // Chat wiring — resolved asynchronously because we need the user id
  // from the session before we can subscribe to `private-user-{me}`.
  late final ChatService _chatService;
  late final ChatRealtimeService _chatRealtime;
  ChatInbox? _chatInbox;
  CallService? _callService;
  StreamSubscription<IncomingCallEvent>? _incomingCallSub;
  bool _callScreenOpen = false;
  int? _myUserId;

  /// Set when [_bootstrapChat] couldn't resolve a user id. Surfaced in
  /// [_ChatBootstrapSplash] alongside a retry button — without this,
  /// an unreachable backend or expired session left the user stuck on
  /// a spinner forever.
  String? _chatBootstrapError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _notifications = NotificationCenter(
      leads: widget.leads,
      customers: widget.customers,
    );
    widget.push.registerCurrentDevice();
    _notifications.refresh();

    _chatService = ChatService(widget.api);
    _chatRealtime = ChatRealtimeService(widget.api);
    _bootstrapChat();
  }

  Future<void> _bootstrapChat() async {
    if (!mounted) return;
    setState(() => _chatBootstrapError = null);

    // Trust the cached user id but probe the cookie before we proceed.
    // A stale cookie (e.g. upgraded from an older build that captured
    // the wrong Set-Cookie value, or a session that has since expired)
    // would otherwise let the chat tab open with an "always-empty" inbox
    // because the server keeps rejecting the requests as Unauthorized.
    final cached = widget.api.userId;
    if (cached != null && cached > 0) {
      final alive = await _chatService.sessionAlive();
      if (!mounted) return;
      if (!alive) {
        await _handleStaleSession();
        return;
      }
    }

    final probe = await widget.auth.currentUserIdWithReason();
    if (!mounted) return;
    final uid = probe.userId;
    if (uid == null) {
      // Either the session expired, the backend is unreachable, or the
      // currentUserId timeout fired. Surface the actual reason so the
      // user knows whether to retry or sign in again.
      setState(() => _chatBootstrapError = probe.error ??
          'Could not load chat. Check your connection or sign in again.');
      return;
    }
    final inbox = ChatInbox(_chatService, _chatRealtime);
    final calls = CallService(
      realtime: _chatRealtime,
      chat: _chatService,
      myUserId: uid,
    );
    calls.addListener(_onCallChange);

    // Bridge CallKit accept/decline taps into the WebRTC state machine.
    // The native sheet shown from the FCM background handler doesn't know
    // anything about CallService — it can only emit IncomingCallEvents,
    // which we route here.
    IncomingCallEvents.instance.start();
    _incomingCallSub = IncomingCallEvents.instance.stream.listen((evt) {
      switch (evt.action) {
        case IncomingCallAction.accept:
          calls.acceptIncomingFromPush(
            callId: evt.callId,
            callerId: evt.callerId,
            callerName: evt.callerName,
            media: evt.media,
          );
          break;
        case IncomingCallAction.decline:
        case IncomingCallAction.timeout:
          calls.declineIncomingFromPush(
            callId: evt.callId,
            callerId: evt.callerId,
            media: evt.media,
          );
          break;
        case IncomingCallAction.ended:
          // CallKit sheet went away (e.g. caller hung up before we picked).
          // No state to clean here unless we'd already accepted, in which
          // case the regular call_service flow handles it.
          break;
      }
    });

    setState(() {
      _myUserId = uid;
      _chatInbox = inbox;
      _callService = calls;
    });
    // If the cookie ever goes stale mid-session (server restart, idle
    // timeout, manual session destroy from the web side), the next inbox
    // load will bubble up authFailed — bounce to login then.
    inbox.addListener(_onInboxChange);

    // Tell PushService which conv is on screen — it consults this to
    // suppress chat banners while the user is viewing the thread.
    widget.push.bindCurrentlyViewedConv(_chatRealtime.currentlyViewedConv);
    // And give it the user's chat-bubble toggle so foreground FCMs honour
    // the Settings preference.
    widget.push.bindChatPrefs(widget.chatPrefs);
    // And listen for "user tapped a chat banner" → switch tab + open thread.
    widget.push.pendingChatNavigation.addListener(_consumePendingChatNav);
    // Dismiss any leftover chat-head bubble for whichever conversation
    // the user just opened in-app — no point hovering a bubble over the
    // thread they're already reading.
    _chatRealtime.currentlyViewedConv.addListener(_onCurrentConvChanged);

    // Inbox must NOT be blocked on the realtime handshake. Soketi may be
    // down / unreachable / slow — REST chat still works, we just won't
    // see live updates. Fire both in parallel and let each settle on its
    // own pace.
    unawaited(_chatRealtime.connect(uid));
    unawaited(inbox.load());

    // In case a tap happened before this listener was wired up (e.g. cold
    // start from a notification), drain it now.
    _consumePendingChatNav();
  }

  void _onInboxChange() {
    if (_chatInbox?.authFailed == true) {
      _handleStaleSession();
    }
  }

  /// Full sign-out: FCM unregister + server logout + local cache wipe +
  /// replace the route stack with the login screen. Called from both the
  /// stale-session path *and* the explicit "Sign out" action on the chat
  /// inbox empty state — so the user always has an escape hatch when
  /// they're confused about which account is active.
  Future<void> _handleStaleSession() async {
    // Best-effort FCM token release (cookie still valid here).
    try {
      await widget.push.releaseCurrentDevice();
    } catch (_) {}
    // Server logout + local cookie/user-id/notification-cursor wipe.
    try {
      await widget.auth.logout();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => LoginScreen(
          api: widget.api,
          auth: widget.auth,
          chatPrefs: widget.chatPrefs,
        ),
      ),
      (_) => false,
    );
  }

  void _onCurrentConvChanged() {
    final id = _chatRealtime.currentlyViewedConv.value;
    if (id != null) widget.push.dismissBubble(id);
  }

  Future<void> _consumePendingChatNav() async {
    final convId = widget.push.pendingChatNavigation.consume();
    if (convId == null || !mounted) return;
    setState(() => _index = 2); // switch to CHAT tab
    // Defer one frame so the IndexedStack is on screen first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openThreadFromNav(convId);
    });
  }

  void _openThreadFromNav(int convId) {
    final inbox = _chatInbox;
    final uid = _myUserId;
    if (inbox == null || uid == null || !mounted) return;
    final match =
        inbox.conversations.where((c) => c.id == convId).toList();
    final conv = match.isNotEmpty ? match.first : null;
    inbox.markLocallyRead(convId);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatThreadScreen(
          conversationId: convId,
          conversation: conv,
          myUserId: uid,
          service: _chatService,
          realtime: _chatRealtime,
          api: widget.api,
          chatPrefs: widget.chatPrefs,
          calls: _callService,
        ),
      ),
    );
  }

  /// Push the call screen the moment a call becomes active (incoming offer
  /// or our own outgoing placeCall). Pop happens inside CallScreen when the
  /// service settles back to idle.
  void _onCallChange() {
    final calls = _callService;
    if (calls == null || !mounted) return;
    if (calls.isActive && !_callScreenOpen) {
      _callScreenOpen = true;
      Navigator.of(context, rootNavigator: true)
          .push(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => CallScreen(calls: calls),
            ),
          )
          .whenComplete(() => _callScreenOpen = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _chatRealtime.pause();
        break;
      case AppLifecycleState.resumed:
        _chatRealtime.resume();
        _chatInbox?.reload();
        break;
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.push.pendingChatNavigation.removeListener(_consumePendingChatNav);
    _incomingCallSub?.cancel();
    _callService?.removeListener(_onCallChange);
    _callService?.dispose();
    _chatRealtime.dispose();
    _chatInbox?.dispose();
    _notifications.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatInbox = _chatInbox;
    final chatTab = (chatInbox == null || _myUserId == null)
        ? _ChatBootstrapSplash(
            error: _chatBootstrapError,
            onRetry: _chatBootstrapError == null ? null : _bootstrapChat,
            onSignOut:
                _chatBootstrapError == null ? null : _handleStaleSession,
          )
        : ChatInboxScreen(
            service: _chatService,
            realtime: _chatRealtime,
            inbox: chatInbox,
            myUserId: _myUserId!,
            api: widget.api,
            chatPrefs: widget.chatPrefs,
            onSignOut: _handleStaleSession,
            calls: _callService,
          );

    final screens = [
      DashboardScreen(
        dashboard: widget.dashboard,
        notifications: _notifications,
        onNavigate: (i) => setState(() => _index = i),
      ),
      CustomerListScreen(
        service: widget.customers,
        notifications: _notifications,
      ),
      // TICKET tab — bring back when chat is retired:
      // TicketListScreen(service: widget.tickets),
      chatTab,
      LeadListScreen(
        service: widget.leads,
        notifications: _notifications,
      ),
      MenuScreen(
        api: widget.api,
        auth: widget.auth,
        push: widget.push,
        chatPrefs: widget.chatPrefs,
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: _BottomNav(
        index: _index,
        chatUnread: chatInbox?.unreadTotal ?? 0,
        onChanged: (i) => setState(() => _index = i),
        inbox: chatInbox,
      ),
    );
  }
}

/// Shown in the CHAT tab slot while we're still resolving the user id.
/// Short-lived (one HTTP call) on the happy path. When [error] is set
/// (e.g. timeout, expired session, unreachable backend) the splash
/// switches to a recoverable error state with retry + sign-out buttons
/// so the user is never stuck on a silent spinner.
class _ChatBootstrapSplash extends StatelessWidget {
  const _ChatBootstrapSplash({this.error, this.onRetry, this.onSignOut});

  final String? error;
  final VoidCallback? onRetry;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Brand.canvas,
      body: Center(
        child: error == null
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Brand.signal,
                ),
              )
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'CHAT UNAVAILABLE',
                      style: text.labelLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Hairline(),
                    const SizedBox(height: 16),
                    Text(
                      error!,
                      style: text.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    if (onRetry != null)
                      SizedBox(
                        width: 200,
                        child: SignalButton(
                          label: 'Retry',
                          icon: Icons.refresh,
                          onPressed: onRetry,
                        ),
                      ),
                    if (onSignOut != null) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: 200,
                        child: GhostButton(
                          label: 'Sign out',
                          onPressed: onSignOut!,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}

class _BottomNav extends StatefulWidget {
  const _BottomNav({
    required this.index,
    required this.chatUnread,
    required this.onChanged,
    required this.inbox,
  });

  final int index;
  final int chatUnread;
  final ValueChanged<int> onChanged;
  final ChatInbox? inbox;

  @override
  State<_BottomNav> createState() => _BottomNavState();
}

class _BottomNavState extends State<_BottomNav> {
  @override
  void initState() {
    super.initState();
    widget.inbox?.addListener(_onChange);
  }

  @override
  void didUpdateWidget(covariant _BottomNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.inbox != widget.inbox) {
      oldWidget.inbox?.removeListener(_onChange);
      widget.inbox?.addListener(_onChange);
    }
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.inbox?.removeListener(_onChange);
    super.dispose();
  }

  static const _items = [
    _NavItem(label: 'HOME', icon: Icons.fiber_manual_record_outlined),
    _NavItem(label: 'BIR', icon: Icons.description_outlined),
    // TICKET tab parked — restore this entry to bring it back:
    // _NavItem(label: 'TICKET', icon: Icons.confirmation_number_outlined),
    _NavItem(label: 'CHAT', icon: Icons.chat_bubble_outline),
    _NavItem(label: 'LEAD', icon: Icons.local_fire_department_outlined),
    _NavItem(label: 'MENU', icon: Icons.grid_view_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final chatUnread = widget.inbox?.unreadTotal ?? widget.chatUnread;

    return Container(
      decoration: const BoxDecoration(
        color: Brand.canvas,
        border: Border(top: BorderSide(color: Brand.rule, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: SafeArea(
        top: false,
        child: Row(
          children: List.generate(_items.length, (i) {
            final active = i == widget.index;
            final item = _items[i];
            final showChatBadge = item.label == 'CHAT' && chatUnread > 0;
            return Expanded(
              child: InkWell(
                onTap: () => widget.onChanged(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Icon(
                            item.icon,
                            size: 20,
                            color: active ? Brand.signal : Brand.paperDim,
                          ),
                          if (showChatBadge)
                            Positioned(
                              top: -4,
                              right: -8,
                              child: Container(
                                constraints: const BoxConstraints(
                                  minWidth: 14,
                                  minHeight: 14,
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Brand.signal,
                                  borderRadius: BorderRadius.circular(8),
                                  border:
                                      Border.all(color: Brand.canvas, width: 1),
                                ),
                                child: Text(
                                  chatUnread > 99
                                      ? '99+'
                                      : chatUnread.toString(),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Brand.canvas,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                    height: 1.1,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.label,
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(
                              fontSize: 9,
                              letterSpacing: 2.2,
                              color: active ? Brand.signal : Brand.paperDim,
                              fontWeight:
                                  active ? FontWeight.w700 : FontWeight.w500,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem({required this.label, required this.icon});
  final String label;
  final IconData icon;
}
