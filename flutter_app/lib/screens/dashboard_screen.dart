import 'dart:async';

import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models/dashboard_models.dart';
import '../services/notification_center.dart';
import '../services/services.dart';
import '../theme.dart';
import '../widgets/dashboard_charts.dart';
import '../widgets/premium.dart';
import 'notification_panel.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.api,
    required this.dashboard,
    required this.notifications,
    required this.onOpenLeads,
    required this.onOpenChat,
    this.active = true,
    this.onOpenTab,
    this.openableTabs = const {},
  });

  final ApiClient api;
  final DashboardService dashboard;
  final NotificationCenter notifications;
  final VoidCallback onOpenLeads;
  final VoidCallback onOpenChat;
  final bool active;
  final ValueChanged<String>? onOpenTab;
  final Set<String> openableTabs;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

enum _LiveMode { live, paused, offline }

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  static const _pollEvery = Duration(seconds: 15);
  static const _revenueEvery = Duration(minutes: 5);

  DashboardLive? _live;
  LicenseRevenue? _revenue;
  bool _revenueLoading = false;
  DateTime? _revenueAt;
  bool _loading = true;
  bool _inFlight = false;
  bool _paused = false;
  bool _offline = false;
  bool _foreground = true;
  DateTime? _fetchedAt;
  Duration _serverOffset = Duration.zero;
  Timer? _pollTimer;
  Timer? _tickTimer;
  final ValueNotifier<DateTime> _now = ValueNotifier(DateTime.now());
  bool _showAllFeed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.notifications.addListener(_onNotificationsChanged);
    _fetch(manual: true);
    _schedule();
  }

  @override
  void didUpdateWidget(covariant DashboardScreen old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) {
      if (widget.active) _fetch();
      _schedule();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.notifications.removeListener(_onNotificationsChanged);
    _pollTimer?.cancel();
    _tickTimer?.cancel();
    _now.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    if (fg == _foreground) return;
    _foreground = fg;
    if (fg && widget.active) _fetch();
    _schedule();
  }

  void _onNotificationsChanged() {
    if (mounted) setState(() {});
  }

  bool get _running => widget.active && _foreground && !_paused;

  void _schedule() {
    _pollTimer?.cancel();
    _tickTimer?.cancel();
    if (!widget.active || !_foreground) return;
    _tickTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _now.value = DateTime.now(),
    );
    if (_paused) return;
    _pollTimer = Timer.periodic(_pollEvery, (_) => _fetch());
  }

  void _togglePause() {
    setState(() => _paused = !_paused);
    if (!_paused) _fetch();
    _schedule();
  }

  Future<void> _fetch({bool manual = false}) async {
    if (_inFlight) return;
    if (!manual && !_running) return;
    _inFlight = true;
    try {
      final live = await widget.dashboard.live();
      if (!mounted) return;
      final server = live.serverTime;
      setState(() {
        _live = live;
        _offline = false;
        _loading = false;
        _fetchedAt = DateTime.now();
        if (server != null) _serverOffset = server.difference(DateTime.now());
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _offline = true;
        _loading = false;
      });
    } finally {
      _inFlight = false;
    }
    if (manual) widget.notifications.refresh();
    final at = _revenueAt;
    if (_section('dashboardRevenue') &&
        (manual ||
            at == null ||
            DateTime.now().difference(at) >= _revenueEvery)) {
      unawaited(_loadRevenue());
    }
  }

  Future<void> _refresh() => _fetch(manual: true);

  Future<void> _loadRevenue() async {
    if (_revenueLoading) return;
    setState(() => _revenueLoading = true);
    final rev = await widget.dashboard.licenseRevenue(
      serverNow: DateTime.now().add(_serverOffset),
    );
    if (!mounted) return;
    setState(() {
      _revenueLoading = false;
      _revenueAt = DateTime.now();
      if (rev != null || _revenue == null) _revenue = rev;
    });
  }

  String get _role => widget.api.userRole.trim().toLowerCase();

  bool get _isAdminView => _role == 'admin' || _role == 'super_admin';

  bool _section(String slug) {
    final api = widget.api;
    if (api.isSuperAdmin) return true;
    final p = api.permissions;
    if (p.containsKey('dashboard') && p['dashboard'] != true) return false;
    if (!p.containsKey(slug)) {
      return slug != 'dashboardRevenue' || _isAdminView;
    }
    return p[slug] == true;
  }

  bool _canOpen(String href) {
    final tab = _tabFor(href);
    if (tab == null) return false;
    if (widget.onOpenTab != null) return widget.openableTabs.contains(tab);
    return tab == 'lead' || tab == 'chat';
  }

  void _open(String href) {
    final tab = _tabFor(href);
    if (tab == null) return;
    if (widget.onOpenTab != null) {
      widget.onOpenTab!(tab);
    } else if (tab == 'lead') {
      widget.onOpenLeads();
    } else if (tab == 'chat') {
      widget.onOpenChat();
    }
  }

  VoidCallback? _tapFor(String href) =>
      _canOpen(href) ? () => _open(href) : null;

  String? _tabFor(String href) {
    switch (href) {
      case 'ticket':
        return 'ticket';
      case 'clientOffer':
        return 'lead';
      case 'customer':
        return 'bir';
      case 'license':
        return 'license';
      case 'task':
        return 'task';
      case 'files-management':
        return 'files';
      case 'chat':
        return 'chat';
    }
    return null;
  }

  String _greeting(DateTime now) {
    final h = now.hour;
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  _LiveMode get _mode => _paused
      ? _LiveMode.paused
      : (_offline ? _LiveMode.offline : _LiveMode.live);

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final today = DateTime.now();
    final dateLabel =
        '${_weekday(today)}, ${_month(today)} ${today.day}, ${today.year}';
    final username = widget.api.username ?? '';
    final firstName = username.trim().split(RegExp(r'[\s._@-]+')).first;
    final greeting = firstName.isEmpty
        ? _greeting(today)
        : '${_greeting(today)}, ${firstName[0].toUpperCase()}${firstName.substring(1)}';

    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: b.canvas,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppHeaderBand(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            dateLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.labelMedium?.copyWith(
                              color: Brand.orange,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Semantics(
                            header: true,
                            child: Text(
                              greeting,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: text.headlineMedium?.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    NotificationBell(
                      count: widget.notifications.unseenCount,
                      onPressed: () =>
                          NotificationPanel.show(context, widget.notifications),
                      tooltip: 'Notifications',
                    ),
                    const SizedBox(width: 8),
                    StationAction(
                      icon: Icons.refresh_rounded,
                      tooltip: 'Refresh',
                      onPressed: _refresh,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _LiveBar(
                  mode: _mode,
                  fetchedAt: _fetchedAt,
                  now: _now,
                  serverOffset: _serverOffset,
                  onToggle: _togglePause,
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: b.signal,
              backgroundColor: b.surface,
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                children: [
                  if (_loading && _live == null)
                    const _DashboardSkeleton()
                  else if (_live == null)
                    GlassPanel(
                      padding: const EdgeInsets.all(16),
                      child: EmptyState(
                        label: 'Dashboard unavailable',
                        hint:
                            'Could not reach the server. Pull down to try again.',
                        icon: Icons.cloud_off_rounded,
                        action: GhostButton(
                          label: 'Retry',
                          icon: Icons.refresh_rounded,
                          onPressed: _refresh,
                        ),
                      ),
                    )
                  else
                    ..._sections(_live!),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _sections(DashboardLive live) {
    final out = <Widget>[];
    var sectionNo = 0;
    var figNo = 0;
    var revealNo = 0;
    String nextFig() => (++figNo).toString().padLeft(2, '0');
    void add(Widget child) => out.add(_Reveal(index: revealNo++, child: child));
    Widget head(String name, String meta) =>
        _NumberedHeader(number: ++sectionNo, name: name, meta: meta);

    final chips = _section('dashboardSignals')
        ? _chipDefs
              .where(
                (c) =>
                    live.pulse.containsKey(c.id) &&
                    !(_isAdminView && c.hideForAdmin),
              )
              .toList()
        : const <_ChipDef>[];
    final cells = _section('dashboardToday')
        ? _pulseDefs
              .where(
                (c) =>
                    live.pulse.containsKey(c.id) &&
                    !(_isAdminView && c.hideForAdmin),
              )
              .toList()
        : const <_PulseDef>[];
    final cards = _section('dashboardTotals')
        ? _statDefs
              .where(
                (c) =>
                    live.totals.containsKey(c.key) &&
                    !(_isAdminView && _adminHidden.contains(c.key)),
              )
              .toList()
        : const <_StatDef>[];
    final heartbeatOk =
        _section('dashboardHeartbeat') && !live.heartbeat.isEmpty;
    final feedPerms =
        live.pulse.isNotEmpty ||
        live.totals.isNotEmpty ||
        live.activity.isNotEmpty;
    final feedOk = _section('dashboardFeed') && feedPerms;
    final showPresence = live.pulse.containsKey('staff_online');
    final revenueOk = _section('dashboardRevenue');

    final groups = [
      for (final g in _chartGroups)
        if (_section(g.perm))
          (
            g,
            g.items
                .where(
                  (i) =>
                      live.hasChart(i.key) && !(_isAdminView && i.hideForAdmin),
                )
                .toList(),
          ),
    ].where((e) => e.$2.isNotEmpty).toList();

    final hasAnything =
        chips.isNotEmpty ||
        cells.isNotEmpty ||
        cards.isNotEmpty ||
        heartbeatOk ||
        feedOk ||
        groups.isNotEmpty ||
        revenueOk;
    if (!hasAnything) {
      return [
        const AppCard(
          child: EmptyState(
            label: 'Nothing to show yet',
            hint:
                'Your account doesn’t have access to any of the modules this dashboard reports on. Ask an administrator to grant the permissions you need.',
            icon: Icons.lock_rounded,
          ),
        ),
      ];
    }

    if (chips.isNotEmpty) {
      add(
        _SignalChips(
          chips: chips,
          pulse: live.pulse,
          tapFor: (c) => _tapFor(c.href),
        ),
      );
      out.add(const SizedBox(height: 22));
    }

    if (cells.isNotEmpty) {
      add(const _BandHeader(name: 'Today', meta: 'since midnight'));
      add(_TodayGrid(cells: cells, pulse: live.pulse));
      out.add(const SizedBox(height: 24));
    }

    if (heartbeatOk || feedOk) {
      add(head('Live Signal', 'last 24 hours'));
      if (heartbeatOk) {
        add(_HeartbeatCard(fig: nextFig(), heartbeat: live.heartbeat));
        out.add(const SizedBox(height: 12));
      }
      if (feedOk) {
        add(
          _FeedCard(
            fig: nextFig(),
            items: live.activity,
            online: showPresence ? live.online : null,
            baseUrl: widget.api.baseUrl,
            headers: widget.api.authHeaders(),
            fetchedAt: _fetchedAt,
            now: _now,
            showAll: _showAllFeed,
            onToggleAll: () => setState(() => _showAllFeed = !_showAllFeed),
            tapFor: (item) => _tapFor(item.href),
          ),
        );
      }
      out.add(const SizedBox(height: 24));
    }

    if (cards.isNotEmpty) {
      add(head('Totals', '14-day trend'));
      add(
        _TotalsGrid(
          cards: cards,
          totals: live.totals,
          series: live.series,
          tapFor: (c) => _tapFor(c.href),
        ),
      );
      out.add(const SizedBox(height: 24));
    }

    if (revenueOk) {
      add(head('License Revenue', 'vendor payments'));
      add(_RevenueCard(revenue: _revenue, loading: _revenueLoading));
      out.add(const SizedBox(height: 24));
    }

    for (final (g, items) in groups) {
      add(head(g.name, g.meta));
      for (var i = 0; i < items.length; i++) {
        if (i > 0) out.add(const SizedBox(height: 12));
        add(
          _ChartCard(
            fig: nextFig(),
            item: items[i],
            data: live.chart(items[i].key),
          ),
        );
      }
      out.add(const SizedBox(height: 24));
    }

    return out;
  }
}

class _ChipDef {
  const _ChipDef(
    this.id,
    this.label,
    this.href,
    this.level,
    this.icon, {
    this.hideForAdmin = false,
  });
  final String id;
  final String label;
  final String href;
  final String level;
  final IconData icon;
  final bool hideForAdmin;
}

const _chipDefs = <_ChipDef>[
  _ChipDef(
    'tickets_open',
    'Open Tickets',
    'ticket',
    'alert',
    Icons.confirmation_number_rounded,
  ),
  _ChipDef(
    'tickets_unassigned',
    'Unassigned',
    'ticket',
    'critical',
    Icons.person_off_rounded,
  ),
  _ChipDef(
    'tickets_hot',
    'High Priority',
    'ticket',
    'critical',
    Icons.priority_high_rounded,
  ),
  _ChipDef(
    'chat_waiting',
    'Chats Waiting',
    'chat',
    'alert',
    Icons.forum_rounded,
  ),
  _ChipDef(
    'zread_pending',
    'Z-Read Pending',
    'z-reading-request',
    'alert',
    Icons.receipt_long_rounded,
    hideForAdmin: true,
  ),
  _ChipDef(
    'tasks_open',
    'My Open Tasks',
    'task',
    'alert',
    Icons.checklist_rounded,
    hideForAdmin: true,
  ),
  _ChipDef(
    'staff_online',
    'Staff Online',
    'activity_logs',
    'none',
    Icons.people_alt_rounded,
  ),
];

class _PulseDef {
  const _PulseDef(this.id, this.label, this.icon, {this.hideForAdmin = false});
  final String id;
  final String label;
  final IconData icon;
  final bool hideForAdmin;
}

const _pulseDefs = <_PulseDef>[
  _PulseDef('tickets_today', 'Tickets In', Icons.confirmation_number_rounded),
  _PulseDef('resolved_today', 'Resolved', Icons.check_rounded),
  _PulseDef('leads_today', 'New Leads', Icons.person_add_alt_1_rounded),
  _PulseDef('license_today', 'Keys Activated', Icons.vpn_key_rounded),
  _PulseDef('messages_today', 'Chat Messages', Icons.chat_rounded),
  _PulseDef(
    'emails_today',
    'Emails Sent',
    Icons.mail_rounded,
    hideForAdmin: true,
  ),
  _PulseDef(
    'files_today',
    'Files Uploaded',
    Icons.upload_file_rounded,
    hideForAdmin: true,
  ),
  _PulseDef(
    'zread_today',
    'Z-Read Requests',
    Icons.receipt_long_rounded,
    hideForAdmin: true,
  ),
  _PulseDef(
    'barcodes_today',
    'Barcodes Made',
    Icons.qr_code_2_rounded,
    hideForAdmin: true,
  ),
  _PulseDef(
    'tasks_due_today',
    'Tasks Due',
    Icons.checklist_rounded,
    hideForAdmin: true,
  ),
  _PulseDef('actions_today', 'Staff Actions', Icons.bolt_rounded),
];

class _StatDef {
  const _StatDef(
    this.key,
    this.label,
    this.icon,
    this.href,
    this.series, {
    this.primary = false,
  });
  final String key;
  final String label;
  final IconData icon;
  final String href;
  final String series;
  final bool primary;
}

const _adminHidden = {
  'tasks',
  'emailsSent',
  'subscribers',
  'files',
  'collections',
  'zreads',
  'barcodes',
  'creds',
  'posversions',
  'notes',
};

const _statDefs = <_StatDef>[
  _StatDef(
    'newLeads',
    'New Leads',
    Icons.person_search_rounded,
    'clientOffer',
    'leads',
    primary: true,
  ),
  _StatDef(
    'leads',
    'Total Leads',
    Icons.handshake_rounded,
    'clientOffer',
    'leads',
  ),
  _StatDef(
    'tickets',
    'Total Tickets',
    Icons.confirmation_number_rounded,
    'ticket',
    'tickets',
  ),
  _StatDef('customers', 'BIR Customers', Icons.groups_rounded, 'customer', ''),
  _StatDef('clients', 'Clients', Icons.badge_rounded, 'client', ''),
  _StatDef(
    'licenses',
    'License Keys',
    Icons.vpn_key_rounded,
    'license',
    'licenses',
  ),
  _StatDef('posts', 'Blog Posts', Icons.article_rounded, 'blog', 'posts'),
  _StatDef(
    'users',
    'System Users',
    Icons.admin_panel_settings_rounded,
    'user',
    '',
  ),
  _StatDef('tasks', 'My Open Tasks', Icons.checklist_rounded, 'task', 'tasks'),
  _StatDef('emailsSent', 'Emails Sent', Icons.send_rounded, 'emails', 'emails'),
  _StatDef(
    'subscribers',
    'Subscribers',
    Icons.mark_email_read_rounded,
    'emails',
    '',
  ),
  _StatDef(
    'files',
    'Files Stored',
    Icons.insert_drive_file_rounded,
    'files-management',
    'files',
  ),
  _StatDef(
    'collections',
    'Collections',
    Icons.folder_open_rounded,
    'files-management',
    '',
  ),
  _StatDef(
    'zreads',
    'Z-Read Requests',
    Icons.receipt_long_rounded,
    'z-reading-request',
    'zreads',
  ),
  _StatDef(
    'barcodes',
    'Barcodes Issued',
    Icons.qr_code_2_rounded,
    'barcode',
    'barcodes',
  ),
  _StatDef(
    'creds',
    'Credential Records',
    Icons.key_rounded,
    'client-credentials',
    'creds',
  ),
  _StatDef(
    'posversions',
    'POS Versions',
    Icons.account_tree_rounded,
    'pos-version',
    '',
  ),
  _StatDef(
    'notes',
    'Release Notes',
    Icons.assignment_rounded,
    'release_notes',
    'notes',
  ),
];

enum _ChartKind { donut, bar, line }

enum _ColorSet { palette, license, steps }

class _ChartItem {
  const _ChartItem(
    this.key,
    this.title,
    this.icon,
    this.kind, {
    this.hideForAdmin = false,
    this.titleCase = false,
    this.colors = _ColorSet.palette,
    this.unit = '',
  });
  final String key;
  final String title;
  final IconData icon;
  final _ChartKind kind;
  final bool hideForAdmin;
  final bool titleCase;
  final _ColorSet colors;
  final String unit;
}

class _ChartGroup {
  const _ChartGroup(this.name, this.meta, this.perm, this.items);
  final String name;
  final String meta;
  final String perm;
  final List<_ChartItem> items;
}

const _chartGroups = <_ChartGroup>[
  _ChartGroup('Status Overview', 'health signals', 'dashboardStatus', [
    _ChartItem(
      'ticketStatus',
      'Tickets by Status',
      Icons.confirmation_number_rounded,
      _ChartKind.donut,
      titleCase: true,
    ),
    _ChartItem(
      'license',
      'License Keys Usage',
      Icons.vpn_key_rounded,
      _ChartKind.donut,
      colors: _ColorSet.license,
    ),
    _ChartItem(
      'customerSteps',
      'BIR Registration Completion',
      Icons.groups_rounded,
      _ChartKind.donut,
      colors: _ColorSet.steps,
    ),
    _ChartItem(
      'zreadStatus',
      'Z-Reading by Status',
      Icons.receipt_long_rounded,
      _ChartKind.donut,
      hideForAdmin: true,
      titleCase: true,
    ),
    _ChartItem(
      'emailStatus',
      'Email Delivery',
      Icons.mail_rounded,
      _ChartKind.donut,
      hideForAdmin: true,
      titleCase: true,
    ),
    _ChartItem(
      'fileType',
      'Files by Collection Type',
      Icons.folder_open_rounded,
      _ChartKind.donut,
      hideForAdmin: true,
      titleCase: true,
    ),
    _ChartItem(
      'taskStatus',
      'My Tasks by Status',
      Icons.checklist_rounded,
      _ChartKind.donut,
      hideForAdmin: true,
      titleCase: true,
    ),
  ]),
  _ChartGroup('Distribution', 'market & geography', 'dashboardDistribution', [
    _ChartItem(
      'leadType',
      'Leads by Business Type',
      Icons.handshake_rounded,
      _ChartKind.bar,
      unit: 'Leads',
    ),
    _ChartItem(
      'customerProv',
      'BIR Customers by Province',
      Icons.place_rounded,
      _ChartKind.bar,
      unit: 'Customers',
    ),
    _ChartItem(
      'notesVersion',
      'Release Notes by POS Version',
      Icons.account_tree_rounded,
      _ChartKind.bar,
      unit: 'Notes',
    ),
  ]),
  _ChartGroup('Activity', 'priority & trend', 'dashboardTrends', [
    _ChartItem(
      'ticketPriority',
      'Tickets by Priority',
      Icons.error_rounded,
      _ChartKind.bar,
      titleCase: true,
      unit: 'Tickets',
    ),
    _ChartItem(
      'ticketMonth',
      'Ticket Activity — Last 6 Months',
      Icons.show_chart_rounded,
      _ChartKind.line,
      unit: 'Tickets',
    ),
  ]),
  _ChartGroup('Throughput', 'last 6 months', 'dashboardThroughput', [
    _ChartItem(
      'emailMonth',
      'Emails Sent',
      Icons.send_rounded,
      _ChartKind.line,
      unit: 'Emails',
    ),
    _ChartItem(
      'fileMonth',
      'File Uploads',
      Icons.insert_drive_file_rounded,
      _ChartKind.line,
      unit: 'Files',
    ),
    _ChartItem(
      'barcodeMonth',
      'Barcodes Issued',
      Icons.qr_code_2_rounded,
      _ChartKind.line,
      unit: 'Barcodes',
    ),
  ]),
];

class _LiveBar extends StatelessWidget {
  const _LiveBar({
    required this.mode,
    required this.fetchedAt,
    required this.now,
    required this.serverOffset,
    required this.onToggle,
  });

  final _LiveMode mode;
  final DateTime? fetchedAt;
  final ValueNotifier<DateTime> now;
  final Duration serverOffset;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final dim = Colors.white.withValues(alpha: 0.72);
    final onGlass = b.paper;
    final onGlassDim = b.paperDim;
    final color = switch (mode) {
      _LiveMode.live =>
        b.isDark ? const Color(0xFF4ADE80) : const Color(0xFF15803D),
      _LiveMode.paused => onGlassDim,
      _LiveMode.offline =>
        b.isDark ? const Color(0xFFFF8A8E) : const Color(0xFFB4191D),
    };
    final word = switch (mode) {
      _LiveMode.live => 'Live',
      _LiveMode.paused => 'Paused',
      _LiveMode.offline => 'Offline',
    };
    return ValueListenableBuilder<DateTime>(
      valueListenable: now,
      builder: (context, current, _) {
        final at = fetchedAt;
        final detail = switch (mode) {
          _LiveMode.paused => 'paused',
          _LiveMode.offline => 'reconnecting…',
          _LiveMode.live =>
            at == null
                ? 'syncing…'
                : 'updated ${_agoText(current.difference(at).inSeconds)}',
        };
        final server = current.add(serverOffset);
        return Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  button: true,
                  label: mode == _LiveMode.paused
                      ? 'Resume live updates'
                      : 'Pause live updates',
                  child: GlassPanel(
                    padding: EdgeInsets.zero,
                    radius: 999,
                    accent: color,
                    onTap: onToggle,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 10, 0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _PulseDot(
                              color: color,
                              animate:
                                  mode == _LiveMode.live &&
                                  !(MediaQuery.maybeOf(
                                        context,
                                      )?.disableAnimations ??
                                      false),
                            ),
                            const SizedBox(width: 8),
                            AnimatedSwitcher(
                              duration:
                                  (MediaQuery.maybeOf(
                                        context,
                                      )?.disableAnimations ??
                                      false)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 220),
                              transitionBuilder: (child, anim) =>
                                  FadeTransition(
                                    opacity: anim,
                                    child: SizeTransition(
                                      axis: Axis.horizontal,
                                      sizeFactor: anim,
                                      child: child,
                                    ),
                                  ),
                              child: Text(
                                word,
                                key: ValueKey<String>(word),
                                style: text.labelLarge?.copyWith(color: color),
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 12,
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                              color: onGlassDim.withValues(alpha: 0.35),
                            ),
                            Flexible(
                              child: Text(
                                detail,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.labelMedium?.copyWith(
                                  color: onGlassDim,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              mode == _LiveMode.paused
                                  ? Icons.play_arrow_rounded
                                  : Icons.pause_rounded,
                              size: 18,
                              color: onGlass,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Icon(Icons.schedule_rounded, size: 15, color: dim),
            const SizedBox(width: 5),
            Text(
              '${_two(server.hour)}:${_two(server.minute)}:${_two(server.second)}',
              style: text.labelLarge?.copyWith(
                color: Colors.white,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Reveal extends StatefulWidget {
  const _Reveal({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _c.value = 1;
      return;
    }
    final delay = Duration(
      milliseconds: (widget.index * 55).clamp(0, 330).toInt(),
    );
    Future<void>.delayed(delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.035),
          end: Offset.zero,
        ).animate(curve),
        child: widget.child,
      ),
    );
  }
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget tile() => const AppCard(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Row(
        children: [
          Skeleton(width: 18, height: 18, radius: 6),
          SizedBox(width: 8),
          Skeleton(width: 26, height: 18),
          SizedBox(width: 8),
          Expanded(child: Skeleton(height: 12)),
        ],
      ),
    );
    Widget stat() => const AppCard(
      padding: EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Skeleton(width: 32, height: 32, radius: 10),
          SizedBox(height: 12),
          Skeleton(width: 70, height: 26),
          SizedBox(height: 8),
          Skeleton(width: 100, height: 12),
          SizedBox(height: 12),
          Skeleton(height: 26),
        ],
      ),
    );
    Widget header() => const Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Skeleton(width: 110, height: 16),
          SizedBox(width: 12),
          Expanded(child: SizedBox()),
          Skeleton(width: 70, height: 12),
        ],
      ),
    );
    return Semantics(
      label: 'Loading dashboard',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Grid(
              columns: 2,
              spacing: 10,
              children: [tile(), tile(), tile(), tile()],
            ),
            const SizedBox(height: 22),
            header(),
            const AppCard(
              padding: EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Skeleton(height: 44)),
                      SizedBox(width: 12),
                      Expanded(child: Skeleton(height: 44)),
                      SizedBox(width: 12),
                      Expanded(child: Skeleton(height: 44)),
                    ],
                  ),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: Skeleton(height: 44)),
                      SizedBox(width: 12),
                      Expanded(child: Skeleton(height: 44)),
                      SizedBox(width: 12),
                      Expanded(child: Skeleton(height: 44)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            header(),
            const AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Skeleton(width: 30, height: 30, radius: 10),
                      SizedBox(width: 10),
                      Skeleton(width: 150, height: 14),
                    ],
                  ),
                  SizedBox(height: 16),
                  Skeleton(height: 200, radius: 12),
                ],
              ),
            ),
            const SizedBox(height: 24),
            header(),
            _Grid(columns: 2, children: [stat(), stat()]),
          ],
        ),
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color, required this.animate});
  final Color color;
  final bool animate;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant _PulseDot old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.animate && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 14,
      height: 14,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Stack(
          alignment: Alignment.center,
          children: [
            if (widget.animate)
              Container(
                width: 6 + 8 * _c.value,
                height: 6 + 8 * _c.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.35 * (1 - _c.value)),
                ),
              ),
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccentTile extends StatelessWidget {
  const _AccentTile({
    required this.icon,
    this.color,
    this.size = 40,
    this.iconSize = 20,
  });

  final IconData icon;
  final Color? color;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final c = color ?? b.signal;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        color: c.withValues(alpha: b.isDark ? 0.18 : 0.12),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Icon(icon, size: iconSize, color: c),
    );
  }
}

class _NumberedHeader extends StatelessWidget {
  const _NumberedHeader({
    required this.number,
    required this.name,
    required this.meta,
  });

  final int number;
  final String name;
  final String meta;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Brand.radiusSm),
              color: b.signal.withValues(alpha: b.isDark ? 0.18 : 0.12),
              border: Border.all(color: b.signal.withValues(alpha: 0.4)),
            ),
            child: Text(
              number.toString().padLeft(2, '0'),
              style: text.labelMedium?.copyWith(
                color: b.isDark ? b.signal : b.signalInk,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(name, style: text.titleMedium),
          const SizedBox(width: 12),
          const Expanded(child: _SectionRule()),
          const SizedBox(width: 12),
          Text(meta, style: text.labelMedium),
        ],
      ),
    );
  }
}

class _BandHeader extends StatelessWidget {
  const _BandHeader({required this.name, required this.meta});

  final String name;
  final String meta;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(name, style: text.titleMedium),
          const SizedBox(width: 12),
          const Expanded(child: _SectionRule()),
          const SizedBox(width: 12),
          Text(meta, style: text.labelMedium),
        ],
      ),
    );
  }
}

class _SectionRule extends StatelessWidget {
  const _SectionRule();

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Container(height: 1, color: b.rule);
  }
}

class _AnimatedCount extends StatelessWidget {
  const _AnimatedCount({required this.value, this.style});
  final int value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: value.toDouble(), end: value.toDouble()),
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(
        formatCount(v.round()),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _SignalChips extends StatelessWidget {
  const _SignalChips({
    required this.chips,
    required this.pulse,
    required this.tapFor,
  });

  final List<_ChipDef> chips;
  final Map<String, int> pulse;
  final VoidCallback? Function(_ChipDef) tapFor;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    Widget chip(_ChipDef c) {
      final value = pulse[c.id] ?? 0;
      final hot = value > 0 && c.level != 'none';
      final accent = c.level == 'critical' ? Brand.danger : b.signal;
      final color = !hot
          ? b.paperDim
          : (c.level == 'critical'
                ? (b.isDark ? const Color(0xFFFF8A8E) : const Color(0xFFB4191D))
                : b.signalInk);
      final panel = GlassPanel(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        accent: hot ? accent : b.paperDim,
        blur: 12,
        onTap: tapFor(c),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 26),
          child: Row(
            children: [
              Icon(c.icon, size: 16, color: hot ? color : b.paperDim),
              const SizedBox(width: 8),
              _AnimatedCount(
                value: value,
                style: text.titleMedium?.copyWith(
                  color: hot ? color : b.paper,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  c.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelMedium?.copyWith(
                    color: hot ? b.paper : b.paperDim,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      return panel;
    }

    return _Grid(
      columns: 2,
      spacing: 10,
      stretchLast: true,
      children: [for (final c in chips) chip(c)],
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({
    required this.columns,
    required this.children,
    this.spacing = 12,
    this.stretchLast = false,
  });

  final int columns;
  final List<Widget> children;
  final double spacing;
  final bool stretchLast;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      final slice = children.skip(i).take(columns).toList();
      if (rows.isNotEmpty) rows.add(SizedBox(height: spacing));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = 0; j < columns; j++) ...[
                if (j > 0 && (j < slice.length || !stretchLast))
                  SizedBox(width: spacing),
                if (j < slice.length)
                  Expanded(child: slice[j])
                else if (!stretchLast)
                  const Expanded(child: SizedBox()),
              ],
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

class _TodayGrid extends StatelessWidget {
  const _TodayGrid({required this.cells, required this.pulse});

  final List<_PulseDef> cells;
  final Map<String, int> pulse;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    const columns = 3;
    final divider = b.paperDim.withValues(alpha: 0.22);
    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += columns) {
      final slice = cells.skip(i).take(columns).toList();
      if (rows.isNotEmpty) rows.add(Container(height: 1, color: divider));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = 0; j < slice.length; j++) ...[
                if (j > 0) Container(width: 1, color: divider),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              slice[j].icon,
                              size: 13,
                              color: b.isDark ? b.signal : b.signalInk,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                slice[j].label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.labelSmall?.copyWith(
                                  color: b.paperDim,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        _AnimatedCount(
                          value: pulse[slice[j].id] ?? 0,
                          style: text.headlineMedium?.copyWith(
                            color: b.paper,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return GlassPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.icon,
    required this.fig,
    required this.title,
    this.trailing,
  });

  final IconData icon;
  final String fig;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        _AccentTile(icon: icon, size: 32, iconSize: 16),
        const SizedBox(width: 10),
        Text(
          fig,
          style: text.labelSmall?.copyWith(
            color: b.paperDim,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: text.titleSmall,
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
  }
}

class _HeartbeatCard extends StatelessWidget {
  const _HeartbeatCard({required this.fig, required this.heartbeat});

  final String fig;
  final TimeSeries heartbeat;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final defs = <(String, String, Color)>[
      ('actions', 'Staff actions', ChartPalette.brand),
      ('messages', 'Chat messages', ChartPalette.ink(b)),
      ('tickets', 'Tickets', ChartPalette.live),
      ('emails', 'Emails', ChartPalette.info),
      ('files', 'File uploads', ChartPalette.warn),
    ];
    final series = [
      for (final d in defs)
        if (heartbeat.has(d.$1))
          ChartSeries(label: d.$2, color: d.$3, values: heartbeat[d.$1]!),
    ];
    return AppCard(
      radius: Brand.radiusLg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHeader(
            icon: Icons.monitor_heart_rounded,
            fig: fig,
            title: 'Activity Heartbeat',
            trailing: const GlowBadge(
              label: 'Streaming',
              color: Brand.success,
              icon: Icons.graphic_eq_rounded,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              for (final s in series)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: s.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      s.label,
                      style: text.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (series.isEmpty)
            const _NoData(height: 200)
          else
            AreaChart(
              labels: heartbeat.labels,
              series: series,
              stacked: true,
              height: 220,
            ),
        ],
      ),
    );
  }
}

class _NoData extends StatelessWidget {
  const _NoData({this.height = 160});
  final double height;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return SizedBox(
      height: height,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insights_rounded, size: 26, color: b.paperDim),
            const SizedBox(height: 6),
            Text('No data yet', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _FeedCard extends StatelessWidget {
  const _FeedCard({
    required this.fig,
    required this.items,
    required this.online,
    required this.baseUrl,
    required this.headers,
    required this.fetchedAt,
    required this.now,
    required this.showAll,
    required this.onToggleAll,
    required this.tapFor,
  });

  static const _collapsed = 6;

  final String fig;
  final List<FeedItem> items;
  final List<OnlineStaff>? online;
  final String baseUrl;
  final Map<String, String> headers;
  final DateTime? fetchedAt;
  final ValueNotifier<DateTime> now;
  final bool showAll;
  final VoidCallback onToggleAll;
  final VoidCallback? Function(FeedItem) tapFor;

  String? _avatar(String path) {
    if (path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '$baseUrl/${path.replaceAll(RegExp(r'^/+'), '')}';
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final visible = showAll ? items : items.take(_collapsed).toList();
    final people = online;
    return AppCard(
      radius: Brand.radiusLg,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHeader(
            icon: Icons.satellite_alt_rounded,
            fig: fig,
            title: 'Activity Stream',
          ),
          if (people != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (people.isNotEmpty)
                  SizedBox(
                    width:
                        22.0 * (people.length.clamp(1, 3)) +
                        (people.length > 3 ? 22 : 0) +
                        6,
                    height: 28,
                    child: Stack(
                      children: [
                        for (var i = 0; i < people.length && i < 3; i++)
                          Positioned(
                            left: i * 22.0,
                            child: Tooltip(
                              message: people[i].displayName,
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: b.surface,
                                    width: 2,
                                  ),
                                ),
                                child: AppAvatar(
                                  name: people[i].displayName,
                                  size: 24,
                                  imageUrl: _avatar(people[i].picture),
                                  headers: headers,
                                ),
                              ),
                            ),
                          ),
                        if (people.length > 3)
                          Positioned(
                            left: 3 * 22.0,
                            child: Container(
                              width: 28,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: b.surfaceHi,
                                border: Border.all(color: b.surface, width: 2),
                              ),
                              child: Text(
                                '+${people.length - 3}',
                                style: text.labelSmall?.copyWith(
                                  color: b.paper,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                StatusPill(
                  label: people.isEmpty
                      ? 'Nobody online'
                      : '${people.length} online',
                  color: people.isEmpty ? b.paperDim : Brand.success,
                  dot: true,
                ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: EmptyState(
                label: 'No recent activity',
                hint: 'New tickets, leads and staff actions stream in here.',
                icon: Icons.timeline_rounded,
              ),
            )
          else ...[
            for (var i = 0; i < visible.length; i++) ...[
              if (i > 0)
                const Padding(
                  padding: EdgeInsets.only(left: 50),
                  child: Hairline(),
                ),
              _FeedRow(
                item: visible[i],
                fetchedAt: fetchedAt,
                now: now,
                onTap: tapFor(visible[i]),
              ),
            ],
            if (items.length > _collapsed)
              TextButton(
                onPressed: onToggleAll,
                child: Text(showAll ? 'Show less' : 'Show all ${items.length}'),
              ),
          ],
        ],
      ),
    );
  }
}

class _FeedRow extends StatelessWidget {
  const _FeedRow({
    required this.item,
    required this.fetchedAt,
    required this.now,
    required this.onTap,
  });

  final FeedItem item;
  final DateTime? fetchedAt;
  final ValueNotifier<DateTime> now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final style = _feedStyle(item, b);
    final sub = [
      if (item.who.isNotEmpty) item.who,
      if (item.body.isNotEmpty) item.body,
    ].join(' · ');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Brand.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AccentTile(
              icon: style.$1,
              color: style.$2,
              size: 36,
              iconSize: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall,
                  ),
                  if (sub.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text.rich(
                      TextSpan(
                        children: [
                          if (item.who.isNotEmpty)
                            TextSpan(
                              text: item.who,
                              style: TextStyle(
                                color: b.paper,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          if (item.who.isNotEmpty && item.body.isNotEmpty)
                            const TextSpan(text: ' · '),
                          if (item.body.isNotEmpty) TextSpan(text: item.body),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            ValueListenableBuilder<DateTime>(
              valueListenable: now,
              builder: (context, current, _) {
                final base = fetchedAt ?? current;
                final secs = item.ago + current.difference(base).inSeconds;
                return Text(_agoText(secs), style: text.labelSmall);
              },
            ),
          ],
        ),
      ),
    );
  }
}

(IconData, Color) _feedStyle(FeedItem item, BrandColors b) {
  switch (item.kind) {
    case 'ticket':
      return (Icons.confirmation_number_rounded, ChartPalette.ink(b));
    case 'lead':
      return (Icons.person_add_alt_1_rounded, b.signal);
    case 'barcode':
      return (Icons.qr_code_2_rounded, b.signal);
    case 'license':
      return (Icons.badge_rounded, Brand.success);
    case 'task':
      return (
        item.icon == 'fa-check-circle'
            ? Icons.check_circle_rounded
            : Icons.checklist_rounded,
        Brand.success,
      );
    case 'email':
      return (Icons.mail_rounded, ChartPalette.info);
    case 'file':
      return (Icons.upload_file_rounded, ChartPalette.info);
    case 'zread':
      return (Icons.receipt_long_rounded, ChartPalette.warn);
    case 'note':
      return (Icons.assignment_rounded, ChartPalette.warn);
    case 'staff':
      return (Icons.bolt_rounded, b.paperDim);
  }
  return (Icons.circle_rounded, b.paperDim);
}

class _TotalsGrid extends StatelessWidget {
  const _TotalsGrid({
    required this.cards,
    required this.totals,
    required this.series,
    required this.tapFor,
  });

  final List<_StatDef> cards;
  final Map<String, int> totals;
  final TimeSeries series;
  final VoidCallback? Function(_StatDef) tapFor;

  @override
  Widget build(BuildContext context) {
    return _Grid(
      columns: 2,
      children: [
        for (final c in cards)
          _StatTile(
            def: c,
            value: totals[c.key] ?? 0,
            trend: c.series.isEmpty ? null : (series[c.series] ?? const []),
            onTap: tapFor(c),
          ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.def,
    required this.value,
    required this.trend,
    required this.onTap,
  });

  final _StatDef def;
  final int value;
  final List<int>? trend;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final hotPrimary = def.primary && value > 0;
    final t = trend;
    final todayCount = t == null || t.isEmpty ? 0 : t.last;
    final deltaColor = todayCount > 0 ? Brand.success : b.paperDim;
    final card = AppCard(
      onTap: onTap,
      radius: Brand.radiusLg,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      borderColor: hotPrimary ? b.signal.withValues(alpha: 0.5) : null,
      color: hotPrimary ? b.tint(b.signal, 0.07) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _AccentTile(icon: def.icon, size: 34, iconSize: 17),
              const Spacer(),
              if (hotPrimary)
                const GlowBadge(label: 'New')
              else if (onTap != null)
                Icon(Icons.arrow_outward_rounded, size: 16, color: b.paperDim),
            ],
          ),
          const SizedBox(height: 12),
          _AnimatedCount(
            value: value,
            style: text.headlineLarge?.copyWith(
              color: b.paper,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            def.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall?.copyWith(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 10),
          if (t != null) ...[
            Sparkline(values: t, height: 26),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  t.isEmpty
                      ? Icons.remove_rounded
                      : (todayCount > 0
                            ? Icons.trending_up_rounded
                            : Icons.remove_rounded),
                  size: 14,
                  color: deltaColor,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    t.isEmpty
                        ? 'No trend'
                        : (todayCount > 0
                              ? '+${formatCount(todayCount)} today'
                              : 'None today'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelMedium?.copyWith(color: deltaColor),
                  ),
                ),
              ],
            ),
          ] else ...[
            const Spacer(),
            Row(
              children: [
                Icon(Icons.storage_rounded, size: 14, color: b.paperDim),
                const SizedBox(width: 4),
                Text('All time', style: text.labelMedium),
              ],
            ),
          ],
        ],
      ),
    );
    return card;
  }
}

class _RevenueCard extends StatelessWidget {
  const _RevenueCard({required this.revenue, required this.loading});

  final LicenseRevenue? revenue;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final r = revenue;
    if (r == null) {
      return AppCard(
        radius: Brand.radiusLg,
        child: loading
            ? const _Grid(
                columns: 2,
                spacing: 10,
                children: [
                  Skeleton(height: 92, radius: 10),
                  Skeleton(height: 92, radius: 10),
                  Skeleton(height: 92, radius: 10),
                  Skeleton(height: 92, radius: 10),
                ],
              )
            : Text(
                'No vendor license payments have been taken on this install yet.',
                style: text.bodySmall,
              ),
      );
    }
    Widget fig(String label, String value, String note, {bool lead = false}) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: lead
              ? b.signal.withValues(alpha: b.isDark ? 0.18 : 0.12)
              : b.surfaceHi,
          borderRadius: BorderRadius.circular(Brand.radiusLg),
          border: Border.all(
            color: lead ? b.signal.withValues(alpha: 0.4) : b.rule,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.labelSmall?.copyWith(
                color: lead ? b.signalInk : b.paperDim,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: text.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: lead ? b.signalInk : b.paper,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(note, maxLines: 2, style: text.labelMedium),
          ],
        ),
      );
    }

    return AppCard(
      radius: Brand.radiusLg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Grid(
            columns: 2,
            spacing: 10,
            children: [
              fig(
                'Earned all time',
                formatPeso(r.total),
                '${formatCount(r.paidCount)} key${r.paidCount == 1 ? '' : 's'} paid for',
                lead: true,
              ),
              fig(
                'This month',
                formatPeso(r.month),
                '${formatCount(r.monthCount)} this month · ${formatPeso(r.today)} today',
              ),
              fig(
                'Average per key',
                formatPeso(r.average),
                r.defaultPrice == null
                    ? 'Across all paid keys'
                    : 'Default price ${formatPeso(r.defaultPrice!)}',
              ),
              fig(
                'Started, not paid',
                formatCount(r.pendingCount),
                '${formatPeso(r.pendingValue)} not collected',
              ),
            ],
          ),
          if (loading || !r.complete) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (loading) ...[
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: b.paperDim,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    loading
                        ? 'Updating…'
                        : 'Some vendor details could not be loaded.',
                    style: text.labelSmall,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.fig, required this.item, required this.data});

  final String fig;
  final _ChartItem item;
  final List<ChartEntry> data;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final labels = [
      for (final e in data) item.titleCase ? _titleCase(e.label) : e.label,
    ];
    final values = [for (final e in data) e.value];
    final empty = values.every((v) => v == 0);
    Widget body;
    if (empty) {
      body = _NoData(height: item.kind == _ChartKind.donut ? 132 : 180);
    } else {
      switch (item.kind) {
        case _ChartKind.donut:
          final colors = switch (item.colors) {
            _ColorSet.license => [ChartPalette.brand, ChartPalette.ink(b)],
            _ColorSet.steps => [ChartPalette.ink(b), ChartPalette.brand],
            _ColorSet.palette => ChartPalette.categorical(b),
          };
          body = DonutChart(labels: labels, values: values, colors: colors);
        case _ChartKind.bar:
          body = BarChart(labels: labels, values: values, height: 220);
        case _ChartKind.line:
          body = AreaChart(
            labels: labels,
            series: [
              ChartSeries(
                label: item.unit,
                color: ChartPalette.brand,
                values: values,
              ),
            ],
            height: 200,
            labelFormatter: _shortMonth,
            unit: item.unit,
          );
      }
    }
    return AppCard(
      radius: Brand.radiusLg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHeader(icon: item.icon, fig: fig, title: item.title),
          const SizedBox(height: 16),
          body,
        ],
      ),
    );
  }
}

String _shortMonth(String label) {
  final parts = label.trim().split(RegExp(r'\s+'));
  if (parts.length == 2 && parts[1].length == 4) {
    return '${parts[0]} ’${parts[1].substring(2)}';
  }
  return label;
}

String _titleCase(String s) => s
    .replaceAll('_', ' ')
    .split(' ')
    .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
    .join(' ');

String _agoText(int sec) {
  final s = sec < 0 ? 0 : sec;
  if (s < 10) return 'just now';
  if (s < 60) return '${s}s ago';
  final m = s ~/ 60;
  if (m < 60) return '${m}m ago';
  final h = m ~/ 60;
  if (h < 24) return '${h}h ago';
  final d = h ~/ 24;
  if (d < 30) return '${d}d ago';
  return '${d ~/ 30}mo ago';
}

String _two(int n) => n.toString().padLeft(2, '0');

String _month(DateTime d) {
  const names = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return names[d.month - 1];
}

String _weekday(DateTime d) {
  const names = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  return names[d.weekday - 1];
}
