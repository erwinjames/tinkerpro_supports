import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:home_widget/home_widget.dart';

import '../api_client.dart';
import '../push_service.dart';
import '../services/announcement_service.dart';
import '../services/app_handoff.dart';
import '../services/chat_app_launcher.dart';
import '../services/chat_prefs.dart';
import '../services/reminder_service.dart';
import '../services/call_service.dart';
import '../services/chat_realtime.dart';
import '../services/chat_service.dart';
import '../services/chat_state.dart';
import '../services/file_service.dart';
import '../services/incoming_call_service.dart';
import '../services/license_service.dart';
import '../services/notification_center.dart';
import '../services/notification_service.dart';
import '../services/services.dart';
import '../services/task_service.dart';
import '../services/theme_prefs.dart';
import '../services/update_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'announcement_dialog.dart';
import 'auth_screens.dart';
import 'call_screen.dart';
import 'chat_inbox_screen.dart';
import 'chat_thread_screen.dart';
import 'dashboard_screen.dart';
import 'update_dialog.dart';
import 'customer_list_screen.dart';
import 'file_list_screen.dart';
import 'lead_list_screen.dart';
import 'license_list_screen.dart';
import 'ticket_list_screen.dart';
import 'task_list_screen.dart';
import 'menu_screen.dart';
import 'reminders_screen.dart';
import 'settings_screen.dart';

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
  String? _stackTabId;
  late final NotificationCenter _notifications;

  late final ChatService _chatService;
  late final ChatRealtimeService _chatRealtime;
  ChatInbox? _chatInbox;
  CallService? _callService;
  StreamSubscription<IncomingCallEvent>? _incomingCallSub;
  AppNotificationCenter? _appNotifications;
  late final AnnouncementService _announcements;
  StreamSubscription<Map<String, dynamic>>? _announcementSub;
  StreamSubscription<Uri?>? _widgetClickSub;
  static bool _widgetLaunchHandled = false;
  bool _callScreenOpen = false;
  int? _myUserId;

  bool _chatStarted = false;

  late final FileService _fileService = FileService(widget.api);
  late final TaskService _taskService = TaskService(widget.api);
  late final LicenseService _licenseService = LicenseService(widget.api);

  List<String> _visibleIds = const [];
  List<String> _overflowIds = const [];
  String? _overflowId;
  bool _signingOut = false;

  String? _chatBootstrapError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _notifications = NotificationCenter(
      leads: widget.leads,
      customers: widget.customers,
      allowLeads: () => widget.api.canAccess('clientOffer', 'clientOffer'),
      allowCustomers: () => widget.api.canAccess('customer', 'customer'),
    );
    widget.push.registerCurrentDevice();
    _notifications.refresh();

    _chatService = ChatService(widget.api);
    _chatRealtime = ChatRealtimeService(widget.api);
    _announcements = AnnouncementService(widget.api);
    _announcements.addListener(_onAnnouncementsChanged);
    unawaited(_announcements.refresh());
    if (widget.api.canAccess('chat', 'chat')) {
      _chatStarted = true;
      _bootstrapChat();
    }
    _syncPermissions();
    unawaited(_refreshChatApp());
    unawaited(ReminderService(widget.api).refreshQuietly());
    _listenForReminderWidget();
    _checkForUpdate();
  }

  void _listenForReminderWidget() {
    if (!Platform.isAndroid) return;
    _widgetClickSub = HomeWidget.widgetClicked.listen(_openFromWidget);
    if (_widgetLaunchHandled) return;
    HomeWidget.initiallyLaunchedFromHomeWidget().then((uri) {
      _widgetLaunchHandled = true;
      _openFromWidget(uri);
    }).catchError((_) {});
  }

  void _openFromWidget(Uri? uri) {
    if (!ReminderWidget.isRemindersUri(uri)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || RemindersScreen.isOpen) return;
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => RemindersScreen(api: widget.api),
      ));
    });
  }

  Future<void> _checkForUpdate() async {
    final service = UpdateService(widget.api);
    final update = await service.check();
    if (!mounted || update == null) return;
    await UpdateDialog.show(context, update, service);
  }

  Future<void> _syncPermissions() async {
    final result = await widget.auth.syncSession();
    if (!mounted) return;
    if (result.signedOut) {
      if (_signingOut) return;
      _signingOut = true;
      final message = result.message;
      if (message != null && message != 'No active session') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 6),
          ),
        );
      }
      await _handleStaleSession();
      return;
    }
    if (!_chatStarted && widget.api.canAccess('chat', 'chat')) {
      _chatStarted = true;
      _bootstrapChat();
    }
    if (result.changed) {
      setState(() {});
      unawaited(_notifications.refresh());
    }
  }

  Future<void> _bootstrapChat() async {
    if (!mounted) return;
    setState(() => _chatBootstrapError = null);

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
      setState(
        () => _chatBootstrapError =
            probe.error ??
            'Could not load chat. Check your connection or sign in again.',
      );
      return;
    }
    final inbox = ChatInbox(_chatService, _chatRealtime);
    final calls = CallService(
      realtime: _chatRealtime,
      chat: _chatService,
      myUserId: uid,
      ignoreIncoming: () => ChatAppLauncher.instance.installed,
    );
    calls.addListener(_onCallChange);

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
          break;
      }
    });

    final appNotifications = AppNotificationCenter(
      NotificationService(widget.api),
      _chatRealtime,
    );

    setState(() {
      _myUserId = uid;
      _chatInbox = inbox;
      _callService = calls;
      _appNotifications = appNotifications;
    });
    _notifications.attachAlerts(appNotifications);
    unawaited(appNotifications.load());
    inbox.addListener(_onInboxChange);

    _announcementSub?.cancel();
    _announcementSub = _chatRealtime.announcementEvents.listen(
      _announcements.ingest,
    );

    widget.push.bindCurrentlyViewedConv(_chatRealtime.currentlyViewedConv);
    widget.push.bindChatPrefs(widget.chatPrefs);
    widget.push.pendingChatNavigation.addListener(_consumePendingChatNav);
    _chatRealtime.currentlyViewedConv.addListener(_onCurrentConvChanged);

    unawaited(_chatRealtime.connect(uid));
    unawaited(inbox.load());

    _consumePendingChatNav();
  }

  void _onAnnouncementsChanged() {
    if (!mounted || !_announcements.hasPending) return;
    if (_callScreenOpen || AnnouncementDialog.isOpen) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_callScreenOpen || AnnouncementDialog.isOpen) return;
      AnnouncementDialog.show(
        context,
        service: _announcements,
        api: widget.api,
      );
    });
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          api: widget.api,
          auth: widget.auth,
          push: widget.push,
          chatPrefs: widget.chatPrefs,
          themePrefs: widget.themePrefs,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  void _onInboxChange() {
    if (_chatInbox?.authFailed == true) {
      _handleStaleSession();
    }
  }

  Future<void> _handleStaleSession() async {
    final reason = _chatInbox?.authFailedMessage;
    if (reason != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(reason), duration: const Duration(seconds: 6)),
      );
    }
    try {
      await widget.push.releaseCurrentDevice();
    } catch (_) {}
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

  bool _redirectChat({int? conversationId}) {
    if (!ChatAppLauncher.instance.installed) return false;
    unawaited(_handOffToChatApp(conversationId));
    return true;
  }

  Future<void> _handOffToChatApp(int? conversationId) async {
    String? handoff;
    if (await ChatAppLauncher.instance.trustsInstalledChatApp()) {
      handoff = await AppHandoff.mint(widget.api);
    }
    final ok = await ChatAppLauncher.instance.open(
      conversationId: conversationId,
      handoff: handoff,
    );
    if (ok || !mounted) return;
    setState(() {});
    if (conversationId != null) {
      _goToTabId('chat');
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openThreadFromNav(conversationId),
      );
    } else {
      _goToTabId('chat');
    }
  }

  Future<void> _refreshChatApp() async {
    final before = ChatAppLauncher.instance.installed;
    final now = await ChatAppLauncher.instance.refresh();
    if (mounted && before != now) setState(() {});
  }

  void _goToTabId(String id) {
    if (!mounted) return;
    if (id == 'chat' && _redirectChat()) return;
    final i = _visibleIds.indexOf(id);
    if (i >= 0) {
      setState(() {
        _index = i;
        _overflowId = null;
      });
      return;
    }
    if (_overflowIds.contains(id)) setState(() => _overflowId = id);
  }

  Future<void> _consumePendingChatNav() async {
    final convId = widget.push.pendingChatNavigation.consume();
    if (convId == null || !mounted) return;
    if (_redirectChat(conversationId: convId)) return;
    _goToTabId('chat');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openThreadFromNav(convId);
    });
  }

  void _openThreadFromNav(int convId) {
    final inbox = _chatInbox;
    final uid = _myUserId;
    if (inbox == null || uid == null || !mounted) return;
    final match = inbox.conversations.where((c) => c.id == convId).toList();
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
        _appNotifications?.load();
        unawaited(_announcements.refresh());
        unawaited(_syncPermissions());
        unawaited(_refreshChatApp());
        unawaited(ReminderService(widget.api).refreshQuietly());
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
    _widgetClickSub?.cancel();
    _callService?.removeListener(_onCallChange);
    _callService?.dispose();
    _announcementSub?.cancel();
    _announcements.removeListener(_onAnnouncementsChanged);
    _announcements.dispose();
    _notifications.attachAlerts(null);
    _appNotifications?.dispose();
    _chatRealtime.dispose();
    _chatInbox?.dispose();
    _notifications.dispose();
    super.dispose();
  }

  static const _candidateTabs = <_TabDef>[
    _TabDef(
      'home',
      'Home',
      Icons.space_dashboard_outlined,
      Icons.space_dashboard_rounded,
      'dashboard',
    ),
    _TabDef(
      'chat',
      'Chat',
      Icons.chat_bubble_outline_rounded,
      Icons.chat_bubble_rounded,
      'chat',
    ),
    _TabDef(
      'bir',
      'BIR',
      Icons.description_outlined,
      Icons.description_rounded,
      'customer',
    ),
    _TabDef(
      'lead',
      'Leads',
      Icons.local_fire_department_outlined,
      Icons.local_fire_department_rounded,
      'clientOffer',
    ),
    _TabDef(
      'ticket',
      'Tickets',
      Icons.confirmation_number_outlined,
      Icons.confirmation_number_rounded,
      'ticket',
    ),
    _TabDef(
      'files',
      'Files',
      Icons.folder_outlined,
      Icons.folder_rounded,
      'files',
    ),
    _TabDef(
      'task',
      'Tasks',
      Icons.checklist_rounded,
      Icons.fact_check_rounded,
      'task',
    ),
    _TabDef(
      'license',
      'License',
      Icons.vpn_key_outlined,
      Icons.vpn_key_rounded,
      'licensekey',
    ),
  ];

  static const _kMaxPrimaryTabs = 4;

  static const _menuTab = _TabDef(
    'menu',
    'Menu',
    Icons.grid_view_outlined,
    Icons.grid_view_rounded,
    null,
  );

  @override
  Widget build(BuildContext context) {
    final api = widget.api;
    final chatInbox = _chatInbox;
    final chatReady = chatInbox != null && _myUserId != null;

    final allowed = _candidateTabs
        .where((t) => api.canAccess(t.permission!, t.permission))
        .toList();
    final primary = allowed.take(_kMaxPrimaryTabs).toList();
    final overflow = allowed
        .skip(_kMaxPrimaryTabs)
        .where((t) => _kMenuShortcutIds.contains(t.id))
        .toList();
    final visible = <_TabDef>[...primary, _menuTab];
    _visibleIds = [for (final t in visible) t.id];
    _overflowIds = [for (final t in overflow) t.id];

    final maxIndex = visible.length - 1;
    final effectiveIndex = _index < 0
        ? 0
        : (_index > maxIndex ? maxIndex : _index);
    if (effectiveIndex != _index) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _index != effectiveIndex) {
          setState(() => _index = effectiveIndex);
        }
      });
    }

    final overflowIndex = _overflowId == null
        ? -1
        : _overflowIds.indexOf(_overflowId!);
    if (_overflowId != null && overflowIndex < 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _overflowId = null);
      });
    }
    final stackIndex = overflowIndex >= 0
        ? visible.length + overflowIndex
        : effectiveIndex;
    final navIndex = overflowIndex >= 0 ? maxIndex : effectiveIndex;

    final stackIds = [
      for (final t in visible) t.id,
      for (final t in overflow) t.id,
    ];
    _stackTabId = stackIndex >= 0 && stackIndex < stackIds.length
        ? stackIds[stackIndex]
        : null;

    final screens = [
      for (final t in visible)
        _buildTabScreen(t.id, chatInbox, chatReady, overflow),
      for (final t in overflow)
        _buildTabScreen(t.id, chatInbox, chatReady, overflow),
    ];

    return PopScope(
      canPop: overflowIndex < 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _overflowId != null) {
          setState(() => _overflowId = null);
        }
      },
      child: Scaffold(
        body: IndexedStack(index: stackIndex, children: screens),
        bottomNavigationBar: _BottomNav(
          index: navIndex,
          tabs: visible,
          chatUnread: chatInbox?.unreadTotal ?? 0,
          onChanged: (i) {
            if (visible[i].id == 'chat' && _redirectChat()) return;
            setState(() {
              _index = i;
              _overflowId = null;
            });
          },
          inbox: chatInbox,
        ),
      ),
    );
  }

  static const _kMenuShortcutIds = {'home', 'chat', 'bir', 'lead', 'ticket'};

  static const _kShortcutMeta = <String, (String, Color)>{
    'home': ('Overview and recent activity', Brand.signal),
    'chat': ('Messages and conversations', Brand.info),
    'bir': ('BIR registration clients', Color(0xFF8B5CF6)),
    'lead': ('Leads and inquiries', Color(0xFFF97316)),
    'ticket': ('Support tickets', Brand.danger),
  };

  Widget _buildTabScreen(
    String id,
    ChatInbox? chatInbox,
    bool chatReady,
    List<_TabDef> overflow,
  ) {
    final api = widget.api;
    final inOverflow = overflow.any((t) => t.id == id);
    final backToMenu = inOverflow
        ? () {
            if (mounted) setState(() => _overflowId = null);
          }
        : null;
    switch (id) {
      case 'home':
        return DashboardScreen(
          api: api,
          dashboard: widget.dashboard,
          notifications: _notifications,
          onOpenLeads: () => _goToTabId('lead'),
          onOpenChat: () => _goToTabId('chat'),
          active: _stackTabId == 'home',
          onOpenTab: _goToTabId,
          openableTabs: {..._visibleIds, ..._overflowIds},
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
                onOpenSettings: _openSettings,
                notifications: _appNotifications,
                sharedNotifications: _notifications,
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
          onBack: backToMenu,
        );
      case 'lead':
        return LeadListScreen(
          service: widget.leads,
          notifications: _notifications,
          onBack: backToMenu,
        );
      case 'ticket':
        return TicketListScreen(service: widget.tickets, onBack: backToMenu);
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
          shortcuts: [
            for (final t in overflow)
              MenuShortcut(
                id: t.id,
                label: t.label,
                subtitle: _kShortcutMeta[t.id]?.$1 ?? '',
                icon: t.selectedIcon,
                color: _kShortcutMeta[t.id]?.$2 ?? Brand.signal,
              ),
          ],
          onOpenShortcut: _goToTabId,
        );
    }
    return const SizedBox.shrink();
  }
}

class _ChatBootstrapSplash extends StatelessWidget {
  const _ChatBootstrapSplash({this.error, this.onRetry, this.onSignOut});

  final String? error;
  final VoidCallback? onRetry;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return Scaffold(
      backgroundColor: b.canvas,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppHeaderBand(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Messages',
                  style: text.labelMedium?.copyWith(
                    color: Brand.orange,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
                Semantics(
                  header: true,
                  child: Text(
                    'Chat',
                    style: text.headlineLarge?.copyWith(color: Colors.white),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  error == null ? 'Connecting…' : 'Connection problem',
                  style: text.labelMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: error == null
                ? const SkeletonList(
                    count: 7,
                    padding: EdgeInsets.fromLTRB(20, 16, 20, 16),
                  )
                : Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 380),
                        child: AppCard(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Center(
                                child: IconTile(
                                  icon: Icons.cloud_off_rounded,
                                  color: Brand.danger,
                                  size: 56,
                                  iconSize: 28,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Chat unavailable',
                                style: text.titleLarge,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                error!,
                                style: text.bodyMedium?.copyWith(
                                  color: b.paperDim,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 24),
                              if (onRetry != null)
                                SignalButton(
                                  label: 'Retry',
                                  icon: Icons.refresh_rounded,
                                  onPressed: onRetry,
                                ),
                              if (onSignOut != null) ...[
                                const SizedBox(height: 12),
                                GhostButton(
                                  label: 'Sign out',
                                  icon: Icons.logout_rounded,
                                  onPressed: onSignOut!,
                                ),
                              ],
                            ],
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

class _BottomNav extends StatefulWidget {
  const _BottomNav({
    required this.index,
    required this.tabs,
    required this.chatUnread,
    required this.onChanged,
    required this.inbox,
  });

  final int index;
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

  Widget _withBadge(Widget icon, int count, Color ring) {
    if (count <= 0) return icon;
    final label = count > 99 ? '99+' : count.toString();
    return Semantics(
      label: '$count unread',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          icon,
          Positioned(
            right: -10,
            top: -7,
            child: ExcludeSemantics(
              child: Container(
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                padding: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Brand.danger,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: ring, width: 2),
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final chatUnread = widget.inbox?.unreadTotal ?? widget.chatUnread;
    final tabs = widget.tabs;
    if (tabs.length < 2) return const SizedBox.shrink();
    final selected = widget.index.clamp(0, tabs.length - 1);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    const barHeight = 66.0;
    const bubble = 56.0;
    const lift = 26.0;

    return SizedBox(
      height: barHeight + lift + bottomInset,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemW = constraints.maxWidth / tabs.length;
          return TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: selected.toDouble()),
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 460),
            curve: Curves.easeOutCubic,
            builder: (context, pos, _) {
              final centerX = itemW * (pos + 0.5);
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: barHeight + bottomInset,
                    child: CustomPaint(
                      painter: _NotchBarPainter(
                        centerX: centerX,
                        notchRadius: bubble / 2 + 7,
                        color: b.isDark ? const Color(0xFF12304F) : Brand.navy,
                        shadow: Brand.navy.withValues(
                          alpha: b.isDark ? 0.55 : 0.32,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: bottomInset,
                    height: barHeight,
                    child: Row(
                      children: [
                        for (var i = 0; i < tabs.length; i++)
                          SizedBox(
                            width: itemW,
                            height: barHeight,
                            child: _NavItem(
                              tab: tabs[i],
                              active: i == selected,
                              badge: tabs[i].id == 'chat' ? chatUnread : 0,
                              reduceMotion: reduceMotion,
                              textStyle: text.labelSmall,
                              withBadge: _withBadge,
                              onTap: () {
                                if (i != selected) {
                                  HapticFeedback.selectionClick();
                                }
                                widget.onChanged(i);
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: centerX - bubble / 2,
                    bottom: bottomInset + barHeight - lift - 6,
                    width: bubble,
                    height: bubble,
                    child: IgnorePointer(
                      child: _NavBubble(
                        icon: tabs[selected].selectedIcon,
                        reduceMotion: reduceMotion,
                        badge: tabs[selected].id == 'chat' ? chatUnread : 0,
                        withBadge: _withBadge,
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _NotchBarPainter extends CustomPainter {
  _NotchBarPainter({
    required this.centerX,
    required this.notchRadius,
    required this.color,
    required this.shadow,
  });

  final double centerX;
  final double notchRadius;
  final Color color;
  final Color shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..moveTo(0, 0);
    final start = centerX - notchRadius * 2;
    final end = centerX + notchRadius * 2;
    path.lineTo(start, 0);
    path.cubicTo(
      centerX - notchRadius * 1.1,
      0,
      centerX - notchRadius * 1.15,
      notchRadius * 1.15,
      centerX,
      notchRadius * 1.15,
    );
    path.cubicTo(
      centerX + notchRadius * 1.15,
      notchRadius * 1.15,
      centerX + notchRadius * 1.1,
      0,
      end,
      0,
    );
    path.lineTo(size.width, 0);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    canvas.drawShadow(path, shadow, 12, false);
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_NotchBarPainter old) =>
      old.centerX != centerX ||
      old.notchRadius != notchRadius ||
      old.color != color ||
      old.shadow != shadow;
}

class _NavBubble extends StatelessWidget {
  const _NavBubble({
    required this.icon,
    required this.reduceMotion,
    required this.badge,
    required this.withBadge,
  });

  final IconData icon;
  final bool reduceMotion;
  final int badge;
  final Widget Function(Widget, int, Color) withBadge;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(icon),
      tween: Tween<double>(begin: reduceMotion ? 1 : 0.6, end: 1),
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 360),
      curve: Curves.easeOutBack,
      builder: (context, t, child) =>
          Transform.scale(scale: t.clamp(0.0, 1.2), child: child),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Brand.orange,
          boxShadow: [
            BoxShadow(
              color: Brand.navy.withValues(alpha: 0.28),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: withBadge(
          Icon(icon, size: 24, color: Colors.white),
          badge,
          Brand.orange,
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.tab,
    required this.active,
    required this.badge,
    required this.reduceMotion,
    required this.textStyle,
    required this.withBadge,
    required this.onTap,
  });

  final _TabDef tab;
  final bool active;
  final int badge;
  final bool reduceMotion;
  final TextStyle? textStyle;
  final Widget Function(Widget, int, Color) withBadge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final idle = Colors.white.withValues(alpha: 0.66);
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 240);
    return Semantics(
      button: true,
      selected: active,
      label: badge > 0 ? '${tab.label}, $badge unread' : tab.label,
      excludeSemantics: true,
      child: Tooltip(
        message: tab.label,
        child: InkResponse(
          onTap: onTap,
          radius: 36,
          highlightColor: Colors.transparent,
          splashColor: Colors.white.withValues(alpha: 0.08),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedOpacity(
                opacity: active ? 0 : 1,
                duration: duration,
                child: withBadge(
                  Icon(tab.icon, size: 22, color: idle),
                  badge,
                  Brand.navy,
                ),
              ),
              const SizedBox(height: 4),
              AnimatedSlide(
                offset: active ? const Offset(0, 0.25) : Offset.zero,
                duration: duration,
                curve: Curves.easeOut,
                child: AnimatedDefaultTextStyle(
                  duration: duration,
                  style: (textStyle ?? const TextStyle()).copyWith(
                    fontSize: 11,
                    height: 1.1,
                    color: active ? Colors.white : idle,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  ),
                  child: Text(
                    tab.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabDef {
  const _TabDef(
    this.id,
    this.label,
    this.icon,
    this.selectedIcon,
    this.permission,
  );

  final String id;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String? permission;
}
