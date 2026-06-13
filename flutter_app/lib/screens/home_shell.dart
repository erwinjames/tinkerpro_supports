// CHAT tab is parked while TASK takes its slot — the chat services
// (realtime, inbox, call) still bootstrap at startup so re-enabling
// the tab is a one-line revert. Silence analyzer noise about the
// parked code paths so it doesn't drown out real warnings.
// ignore_for_file: unused_field, unused_element, unused_element_parameter

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
import '../services/theme_prefs.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import '../services/task_service.dart'; // ignore: unused_import — parked TASK tab, see _items
import 'auth_screens.dart';
import 'call_screen.dart';
// CHAT tab is parked while TASK takes its slot. Keep the imports + service
// wiring around so we can flip it back without rewriting the shell — the
// chat realtime / inbox / call services still bootstrap at startup so the
// channel subscription stays warm for live notifications.
import 'chat_inbox_screen.dart'; // ignore: unused_import
import 'chat_screen.dart'; // ignore: unused_import
import 'chat_thread_screen.dart'; // ignore: unused_import
import 'dashboard_screen.dart';
import 'customer_list_screen.dart';
import 'lead_list_screen.dart';
// TICKET tab is parked while TASK takes its slot. Keep the import + screen
// wiring around so we can flip it back without rewriting the shell.
import 'ticket_list_screen.dart'; // ignore: unused_import
import 'task_list_screen.dart'; // ignore: unused_import — parked TASK tab, see _items
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
    required this.themePrefs,
  });

  final ApiClient api;
  final PushService push;
  final AuthService auth;
  final DashboardService dashboard;
  final CustomerService customers;
  final LeadService leads;
  final TicketService tickets;
  final ChatPrefs chatPrefs;
  final ThemePrefs themePrefs;

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
          themePrefs: widget.themePrefs,
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
    // CHAT occupies the third tab slot. The realtime / inbox bootstrap runs
    // at startup; until it resolves a user id we show the bootstrap splash
    // (or a recoverable error). TASK is parked for the future — see the
    // commented entry below (and the _items list) to swap it back in.
    final chatInbox = _chatInbox;
    final chatReady = chatInbox != null && _myUserId != null;

    final screens = [
      DashboardScreen(
        dashboard: widget.dashboard,
        notifications: _notifications,
        onNavigate: (i) => setState(() => _index = i),
        onOpenChat: () => setState(() => _index = 2),
      ),
      CustomerListScreen(
        service: widget.customers,
        notifications: _notifications,
      ),
      // CHAT tab. To restore TASK in this slot later, swap this back to
      //   TaskListScreen(service: TaskService(widget.api))
      // and flip the _items entry from CHAT back to TASK.
      chatReady
          ? ChatInboxScreen(
              service: _chatService,
              realtime: _chatRealtime,
              inbox: chatInbox,
              myUserId: _myUserId!,
              api: widget.api,
              chatPrefs: widget.chatPrefs,
              onSignOut: _handleStaleSession,
              calls: _callService,
            )
          : _ChatBootstrapSplash(
              error: _chatBootstrapError,
              onRetry: _bootstrapChat,
              onSignOut: _handleStaleSession,
            ),
      LeadListScreen(
        service: widget.leads,
        notifications: _notifications,
      ),
      MenuScreen(
        api: widget.api,
        auth: widget.auth,
        push: widget.push,
        chatPrefs: widget.chatPrefs,
        themePrefs: widget.themePrefs,
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
    // CHAT lives in this slot. TASK is parked for the future — swap this
    // entry back to the TASK item (and the matching screen in HomeShell)
    // to restore it:
    //   _NavItem(label: 'TASK', icon: Icons.task_alt_outlined),
    // TICKET is also parked:
    //   _NavItem(label: 'TICKET', icon: Icons.confirmation_number_outlined),
    _NavItem(label: 'CHAT', icon: Icons.chat_bubble_outline),
    _NavItem(label: 'LEAD', icon: Icons.local_fire_department_outlined),
    _NavItem(label: 'MENU', icon: Icons.grid_view_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final chatUnread = widget.inbox?.unreadTotal ?? widget.chatUnread;
    // Honour the OS "reduce motion" setting — the gliding aura and the
    // scale/tracking pops collapse to instant state changes for users who
    // opt out (a11y: prefers-reduced-motion).
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final slide =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 340);

    return Container(
      decoration: BoxDecoration(
        color: Brand.canvas,
        border: const Border(top: BorderSide(color: Brand.rule, width: 1)),
        // A faint upward shadow lifts the bar off the content above so it
        // reads as a distinct console rather than a flat strip.
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.40),
            blurRadius: 22,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final itemWidth = constraints.maxWidth / _items.length;
            return Stack(
              children: [
                // ── The signal aura: a broadcast tick + soft halo that
                //    glides under the active station. This sliding accent is
                //    the premium signature; the rest of the bar stays quiet.
                AnimatedPositioned(
                  duration: slide,
                  curve: Curves.easeOutCubic,
                  left: widget.index * itemWidth,
                  width: itemWidth,
                  top: 0,
                  bottom: 0,
                  child: const IgnorePointer(child: _StationAura()),
                ),
                Row(
                  children: List.generate(_items.length, (i) {
                    final active = i == widget.index;
                    final item = _items[i];
                    final showChatBadge =
                        item.label == 'CHAT' && chatUnread > 0;
                    return Expanded(
                      child: InkWell(
                        onTap: () => widget.onChanged(i),
                        splashColor: Brand.signalGlow(0.12),
                        highlightColor: Colors.transparent,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedScale(
                                duration: reduceMotion
                                    ? Duration.zero
                                    : const Duration(milliseconds: 280),
                                curve: Curves.easeOutBack,
                                scale: active ? 1.14 : 1.0,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Icon(
                                      item.icon,
                                      size: 20,
                                      color: active
                                          ? Brand.signal
                                          : Brand.paperDim,
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
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                                color: Brand.canvas, width: 1),
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
                              ),
                              const SizedBox(height: 7),
                              AnimatedDefaultTextStyle(
                                duration: reduceMotion
                                    ? Duration.zero
                                    : const Duration(milliseconds: 220),
                                curve: Curves.easeOut,
                                style: (Theme.of(context)
                                            .textTheme
                                            .labelMedium ??
                                        const TextStyle())
                                    .copyWith(
                                  fontSize: 9,
                                  letterSpacing: active ? 2.8 : 2.2,
                                  color:
                                      active ? Brand.signal : Brand.paperDim,
                                  fontWeight: active
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                                child: Text(item.label),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The active-station accent that slides beneath the selected nav item:
/// a thin "broadcast tick" pinned under the top rule plus a soft radial
/// halo the active icon sits within. Drawn behind the row, sized to one
/// nav cell by its [AnimatedPositioned] parent.
class _StationAura extends StatelessWidget {
  const _StationAura();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Broadcast tick — flush under the top hairline.
        Container(
          height: 3,
          width: 26,
          decoration: BoxDecoration(
            color: Brand.signal,
            borderRadius: BorderRadius.circular(99),
            boxShadow: [
              BoxShadow(
                color: Brand.signalGlow(0.7),
                blurRadius: 10,
                spreadRadius: 0.5,
              ),
            ],
          ),
        ),
        // Soft halo the active icon sits within.
        Expanded(
          child: Center(
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Brand.signalGlow(0.22),
                    Brand.signalGlow(0.0),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NavItem {
  const _NavItem({required this.label, required this.icon});
  final String label;
  final IconData icon;
}
