// The bottom bar is permission-driven: HomeShell builds it from the tabs the
// signed-in user can actually reach (see _candidateTabs) plus an always-on
// MENU, so the visible set — and its screens — vary per user.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../api_client.dart';
import '../push_service.dart';
import '../services/chat_prefs.dart';
import '../services/call_service.dart';
import '../services/chat_realtime.dart';
import '../services/chat_service.dart';
import '../services/chat_state.dart';
import '../services/file_service.dart';
import '../services/incoming_call_service.dart';
import '../services/license_service.dart';
import '../services/notification_center.dart';
import '../services/services.dart';
import '../services/task_service.dart';
import '../services/theme_prefs.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'auth_screens.dart';
import 'call_screen.dart';
import 'chat_inbox_screen.dart';
import 'chat_thread_screen.dart';
import 'dashboard_screen.dart';
import 'customer_list_screen.dart';
import 'file_list_screen.dart';
import 'lead_list_screen.dart';
import 'license_list_screen.dart';
import 'ticket_list_screen.dart';
import 'task_list_screen.dart';
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

  /// Whether we've kicked off the chat bootstrap. Gated on the `chat`
  /// permission so users without chat access never spin up realtime / inbox /
  /// CallKit. Lets [_syncPermissions] start chat later if access is granted
  /// mid-session without double-bootstrapping.
  bool _chatStarted = false;

  // Backing services for the permission-driven primary tabs. Cheap (they only
  // hold an ApiClient), created once so tab rebuilds don't churn instances.
  late final FileService _fileService = FileService(widget.api);
  late final TaskService _taskService = TaskService(widget.api);
  late final LicenseService _licenseService = LicenseService(widget.api);

  /// Ids of the tabs currently on the bar, in display order (set in [build]).
  /// Lets intent-based jumps (chat / leads) resolve to the tab's live
  /// position without hardcoded indices, since the bar is now dynamic.
  List<String> _visibleIds = const [];

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
    // Only bootstrap chat for users entitled to it. Without the `chat`
    // permission the tab is hidden anyway (see build's `allowed` set), so
    // there's no reason to open realtime / inbox / CallKit for them.
    if (widget.api.hasPermission('chat')) {
      _chatStarted = true;
      _bootstrapChat();
    }
    _syncPermissions();
  }

  /// Pull fresh feature permissions in the background so the Menu's
  /// permission-gated entries (e.g. Task) reflect the user's current
  /// entitlements — including changes made on the web side since the last
  /// login, and the upgrade case where an older build never persisted them.
  Future<void> _syncPermissions() async {
    final changed = await widget.auth.refreshPermissions();
    if (!mounted) return;
    // Chat access may have been granted since login. If we skipped the
    // startup bootstrap, spin it up now so the tab lights up without a
    // relaunch. The `_chatStarted` guard prevents a double bootstrap.
    if (!_chatStarted && widget.api.hasPermission('chat')) {
      _chatStarted = true;
      _bootstrapChat();
    }
    if (changed) setState(() {});
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

  /// Switch to the tab with [id] if it's currently on the bar. No-op when the
  /// user isn't entitled to it (or it was capped out of the primary set) — the
  /// feature is still reachable through MENU.
  void _goToTabId(String id) {
    final i = _visibleIds.indexOf(id);
    if (i >= 0 && mounted) setState(() => _index = i);
  }

  Future<void> _consumePendingChatNav() async {
    final convId = widget.push.pendingChatNavigation.consume();
    if (convId == null || !mounted) return;
    _goToTabId('chat'); // switch to CHAT tab if it's on the bar
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

  /// Ordered candidate primary destinations for the bottom bar. The bar
  /// surfaces the first [_kMaxPrimaryTabs] the user is entitled to (in this
  /// order), then always appends MENU — so the bar is filled with pages the
  /// user can actually reach instead of fixed slots that blink out. Anything
  /// not shown here is still reachable through the MENU directory.
  static const _candidateTabs = <_TabDef>[
    _TabDef('home', 'HOME', Icons.fiber_manual_record_outlined, 'dashboard'),
    _TabDef('chat', 'CHAT', Icons.chat_bubble_outline, 'chat'),
    _TabDef('bir', 'BIR', Icons.description_outlined, 'customer'),
    _TabDef(
        'lead', 'LEAD', Icons.local_fire_department_outlined, 'clientOffer'),
    _TabDef('ticket', 'TICKET', Icons.confirmation_number_outlined, 'ticket'),
    _TabDef('files', 'FILES', Icons.folder_outlined, 'files'),
    _TabDef('task', 'TASK', Icons.checklist_outlined, 'task'),
    _TabDef('license', 'LICENSE', Icons.vpn_key_outlined, 'licensekey'),
  ];

  /// Max primary tabs before MENU. Keeps the bar to at most five cells (the
  /// original layout width) even for users entitled to everything.
  static const _kMaxPrimaryTabs = 4;

  /// MENU — the always-present directory / settings / sign-out escape hatch.
  static const _menuTab =
      _TabDef('menu', 'MENU', Icons.grid_view_outlined, null);

  @override
  Widget build(BuildContext context) {
    final api = widget.api;
    final chatInbox = _chatInbox;
    final chatReady = chatInbox != null && _myUserId != null;

    // The bar = the user's first N accessible primaries, then MENU.
    final primary = _candidateTabs
        .where((t) => api.hasPermission(t.permission!))
        .take(_kMaxPrimaryTabs)
        .toList();
    final visible = <_TabDef>[...primary, _menuTab];
    _visibleIds = [for (final t in visible) t.id];

    // Keep the active tab in range as the tab set changes with permissions;
    // clamp for this frame and normalise _index just after so intent jumps
    // resolve against a valid position.
    final maxIndex = visible.length - 1;
    final effectiveIndex =
        _index < 0 ? 0 : (_index > maxIndex ? maxIndex : _index);
    if (effectiveIndex != _index) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _index != effectiveIndex) {
          setState(() => _index = effectiveIndex);
        }
      });
    }

    final screens = [
      for (final t in visible) _buildTabScreen(t.id, chatInbox, chatReady),
    ];

    return Scaffold(
      body: IndexedStack(index: effectiveIndex, children: screens),
      bottomNavigationBar: _BottomNav(
        index: effectiveIndex,
        tabs: visible,
        chatUnread: chatInbox?.unreadTotal ?? 0,
        onChanged: (i) => setState(() => _index = i),
        inbox: chatInbox,
      ),
    );
  }

  /// Build the screen for a given tab id. Backing services are memoized on the
  /// state, so rebuilds (tab switches, unread ticks) don't churn instances or
  /// reset list state.
  Widget _buildTabScreen(String id, ChatInbox? chatInbox, bool chatReady) {
    final api = widget.api;
    switch (id) {
      case 'home':
        return DashboardScreen(
          api: api,
          dashboard: widget.dashboard,
          notifications: _notifications,
          onOpenLeads: () => _goToTabId('lead'),
          onOpenChat: () => _goToTabId('chat'),
        );
      case 'chat':
        return chatReady
            ? ChatInboxScreen(
                service: _chatService,
                realtime: _chatRealtime,
                inbox: chatInbox!,
                myUserId: _myUserId!,
                api: api,
                chatPrefs: widget.chatPrefs,
                onSignOut: _handleStaleSession,
                calls: _callService,
              )
            : _ChatBootstrapSplash(
                error: _chatBootstrapError,
                onRetry: _bootstrapChat,
                onSignOut: _handleStaleSession,
              );
      case 'bir':
        return CustomerListScreen(
          service: widget.customers,
          notifications: _notifications,
        );
      case 'lead':
        return LeadListScreen(
          service: widget.leads,
          notifications: _notifications,
        );
      case 'ticket':
        return TicketListScreen(service: widget.tickets);
      case 'files':
        return FileListScreen(service: _fileService);
      case 'task':
        return TaskListScreen(service: _taskService);
      case 'license':
        return LicenseListScreen(service: _licenseService);
      case 'menu':
        return MenuScreen(
          api: api,
          auth: widget.auth,
          push: widget.push,
          chatPrefs: widget.chatPrefs,
          themePrefs: widget.themePrefs,
        );
    }
    return const SizedBox.shrink();
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
    required this.tabs,
    required this.chatUnread,
    required this.onChanged,
    required this.inbox,
  });

  /// Position of the active tab within [tabs].
  final int index;

  /// The tabs to render, in display order (already permission-filtered and
  /// capped by HomeShell). [onChanged] reports the tapped tab's position.
  final List<_TabDef> tabs;
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

  // Reference-style docked nav: a floating rounded near-black bar with the
  // primaries split around a raised center action (MENU). Kept dark in both
  // themes to match the design — the dark bar reads well on the light canvas.
  static const Color _kBarColor = Color(0xFF161512);
  static const Color _kNavInactive = Color(0xFF9A968E);

  @override
  Widget build(BuildContext context) {
    final chatUnread = widget.inbox?.unreadTotal ?? widget.chatUnread;
    final tabs = widget.tabs;
    if (tabs.isEmpty) return const SizedBox.shrink();

    // MENU (always the last tab) becomes the raised center action; the
    // primaries split evenly to its left and right. Empty spacers pad the
    // shorter side so the gap — and the FAB — stay centered.
    final menuIndex = tabs.length - 1;
    final primaryCount = menuIndex;
    final leftItems = <int>[for (var i = 0; i < (primaryCount / 2).ceil(); i++) i];
    final rightItems = <int>[
      for (var i = leftItems.length; i < primaryCount; i++) i
    ];
    final maxSide = leftItems.length > rightItems.length
        ? leftItems.length
        : rightItems.length;

    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return SafeArea(
      top: false,
      child: SizedBox(
        height: 100,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // ── Floating rounded dark bar ─────────────────────────────────
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Container(
                  height: 60,
                  decoration: BoxDecoration(
                    color: _kBarColor,
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.28),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      for (var s = 0; s < maxSide - leftItems.length; s++)
                        const Expanded(child: SizedBox()),
                      for (final i in leftItems)
                        Expanded(
                            child:
                                _navItem(context, i, chatUnread, reduceMotion)),
                      const SizedBox(width: 60), // gap under the center FAB
                      for (final i in rightItems)
                        Expanded(
                            child:
                                _navItem(context, i, chatUnread, reduceMotion)),
                      for (var s = 0; s < maxSide - rightItems.length; s++)
                        const Expanded(child: SizedBox()),
                    ],
                  ),
                ),
              ),
            ),
            // ── Raised center action (MENU) ───────────────────────────────
            Positioned(
              top: 18,
              left: 0,
              right: 0,
              child: Center(
                child: _centerFab(menuIndex, widget.index == menuIndex),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navItem(
      BuildContext context, int i, int chatUnread, bool reduceMotion) {
    final item = widget.tabs[i];
    final active = i == widget.index;
    final color = active ? Brand.signal : _kNavInactive;
    final showChatBadge = item.id == 'chat' && chatUnread > 0;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onChanged(i);
      },
      borderRadius: BorderRadius.circular(18),
      splashColor: Brand.signalGlow(0.12),
      highlightColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 240),
              curve: Curves.easeOutBack,
              scale: active ? 1.14 : 1.0,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(item.icon, size: 22, color: color),
                  if (showChatBadge)
                    Positioned(
                      top: -4,
                      right: -8,
                      child: Container(
                        constraints:
                            const BoxConstraints(minWidth: 14, minHeight: 14),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: Brand.signal,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _kBarColor, width: 1.4),
                        ),
                        child: Text(
                          chatUnread > 99 ? '99+' : chatUnread.toString(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
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
            const SizedBox(height: 4),
            Text(
              item.label,
              maxLines: 1,
              style:
                  (Theme.of(context).textTheme.labelMedium ?? const TextStyle())
                      .copyWith(
                fontSize: 8.5,
                letterSpacing: 1.3,
                color: color,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _centerFab(int menuIndex, bool active) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onChanged(menuIndex);
      },
      child: AnimatedScale(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutBack,
        scale: active ? 1.06 : 1.0,
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Brand.signal,
            // Ring in the bar colour makes the FAB read as docked into the bar.
            border: Border.all(color: _kBarColor, width: 3),
            boxShadow: [
              BoxShadow(
                color: Brand.signalGlow(0.4),
                blurRadius: 10,
                spreadRadius: 0.5,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: const Icon(Icons.grid_view_rounded,
              color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

/// A candidate / visible bottom-nav destination. [permission] is the key that
/// must be granted for the tab to appear (`null` = always shown, i.e. MENU).
/// [id] is the stable identity used both to build the tab's screen and to
/// resolve intent-based jumps (chat / leads) against the dynamic bar.
class _TabDef {
  const _TabDef(this.id, this.label, this.icon, this.permission);

  final String id;
  final String label;
  final IconData icon;
  final String? permission;
}
