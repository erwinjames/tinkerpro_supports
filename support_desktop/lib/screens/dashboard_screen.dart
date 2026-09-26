import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/dashboard_data_service.dart';
import '../services/live_sync.dart';
import '../services/notification_center.dart';
import '../services/services.dart';
import '../widgets/dashboard_charts.dart';
import '../widgets/premium.dart';
import '../widgets/tp_loader.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.dashboard,
    required this.notifications,
    required this.onNavigate,
    required this.onOpenChat,
    this.onNavigateKey,
  });

  final DashboardService dashboard;
  final NotificationCenter notifications;
  final ValueChanged<int> onNavigate;
  final VoidCallback onOpenChat;
  final ValueChanged<String>? onNavigateKey;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

enum _LiveMode { live, paused, offline }

class _DashboardScreenState extends State<DashboardScreen>
    with LiveRefresh<DashboardScreen> {
  static const _pollMs = 15000;

  late final DashboardDataService _data = DashboardDataService(
    widget.dashboard.api,
  );
  final ValueNotifier<DateTime> _tick = ValueNotifier(DateTime.now());
  final ScrollController _scroll = ScrollController();

  DesktopDashboard? _dash;
  bool _loading = true;
  String? _error;
  _LiveMode _mode = _LiveMode.live;
  DateTime? _fetchedAt;
  Duration _serverOffset = Duration.zero;
  int _pollSeq = 0;
  bool _inFlight = false;
  Timer? _clock;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      _tick.value = DateTime.now();
    });
    _load();
  }

  @override
  void dispose() {
    _clock?.cancel();
    _poll?.cancel();
    _tick.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _absorbServerTime(DashSnapshot s) {
    final st = s.serverTime;
    if (st != null) _serverOffset = st.difference(DateTime.now());
    _fetchedAt = DateTime.now();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _dash == null;
      _error = null;
    });
    DesktopDashboard? d;
    try {
      d = await _data.fetch();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (d != null) {
        _dash = d;
        _absorbServerTime(d.snapshot);
        _mode = _LiveMode.live;
      } else if (_dash == null) {
        _error = 'Could not load the dashboard.';
      }
    });
    _schedule();
    widget.notifications.refresh();
    _debugScroll();
  }

  @override
  List<String> get liveKeys => const ['dashboard', 'task'];

  @override
  void onLiveChange() => _silentReload();

  bool _silentBusy = false;

  Future<void> _silentReload() async {
    if (_silentBusy || _dash == null || _mode == _LiveMode.paused) return;
    _silentBusy = true;
    DesktopDashboard? d;
    try {
      d = await _data.fetch();
    } catch (_) {}
    _silentBusy = false;
    if (!mounted || d == null) return;
    final fresh = d;
    setState(() {
      _dash = fresh;
      _absorbServerTime(fresh.snapshot);
      if (_mode == _LiveMode.offline) _mode = _LiveMode.live;
    });
  }

  void _debugScroll() {
    if (!kDebugMode) return;
    final px = double.tryParse(Platform.environment['TP_DASH_SCROLL'] ?? '');
    if (px == null) return;
    Future<void> jump() async {
      for (var k = 0; k < 6; k++) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (!mounted || !_scroll.hasClients) return;
        _scroll.jumpTo(px.clamp(0, _scroll.position.maxScrollExtent));
      }
    }

    jump();
  }

  void _schedule() {
    _poll?.cancel();
    if (_mode == _LiveMode.paused) return;
    setState(() => _pollSeq++);
    _poll = Timer.periodic(const Duration(milliseconds: _pollMs), (_) {
      _livePoll();
      if (mounted) setState(() => _pollSeq++);
    });
  }

  Future<void> _livePoll() async {
    if (_inFlight || _mode == _LiveMode.paused || _dash == null) return;
    if (!mounted || !Visibility.of(context)) return;
    _inFlight = true;
    DashSnapshot? s;
    try {
      s = await _data.live();
    } catch (_) {}
    _inFlight = false;
    if (!mounted || _mode == _LiveMode.paused) return;
    setState(() {
      if (s == null) {
        _mode = _LiveMode.offline;
      } else {
        _mode = _LiveMode.live;
        _dash = _dash!.withSnapshot(s);
        _absorbServerTime(s);
      }
    });
  }

  void _togglePause() {
    if (_mode == _LiveMode.paused) {
      setState(() => _mode = _LiveMode.live);
      _livePoll();
      _schedule();
    } else {
      _poll?.cancel();
      setState(() => _mode = _LiveMode.paused);
    }
  }

  static const _hrefKeys = {
    'license': 'licensekey',
    'activity_logs': 'activitylogs',
    'files-management': 'files',
    'z-reading-request': 'zreading',
    'release_notes': 'releasenotes',
    'pos-version': 'posversion',
    'blog': 'blogposts',
    'posts': 'blogposts',
    'client-credentials': 'credentials',
    'help': 'helpPage',
    'employment-information': 'employment',
    'vendor-management': 'vendorportal',
    'taxpayer-portal': 'taxpayerportal',
    'app-downloads': 'appdownloads',
    'feedback': 'feedbackinbox',
  };

  VoidCallback? _hrefTap(String href) {
    switch (href) {
      case 'clientOffer':
        return () => widget.onNavigate(0);
      case 'chat':
        return widget.onOpenChat;
    }
    final go = widget.onNavigateKey;
    if (go == null || href.isEmpty) return null;
    var page = href.split('?').first.split('#').first;
    page = page.replaceAll(RegExp(r'\.php$'), '').replaceAll(RegExp(r'^/+'), '');
    if (page.isEmpty) return null;
    final key = _hrefKeys[page] ?? page;
    return () => go(key);
  }

  @override
  Widget build(BuildContext context) {
    final c = DashColors.of(context);
    final d = _dash;
    return StationScaffold(
      stationNumber: '00',
      stationLabel: 'DASHBOARD',
      title: 'Dashboard',
      padding: EdgeInsets.zero,
      leading: ValueListenableBuilder<DateTime>(
        valueListenable: _tick,
        builder: (context, now, _) {
          final t = now.add(_serverOffset);
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _dateLabel(t).toUpperCase(),
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.4,
                  color: c.muted2,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _timeLabel(t),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: c.inkSoft,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          );
        },
      ),
      trailing: _LivePill(
        mode: _mode,
        tick: _tick,
        fetchedAt: _fetchedAt,
        pollSeq: _pollSeq,
        pollMs: _pollMs,
        onToggle: _togglePause,
      ),
      child: _loading && d == null
          ? const Center(child: TpLoader())
          : d == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _error ?? 'Could not load the dashboard.',
                    style: TextStyle(color: c.muted),
                  ),
                  const SizedBox(height: 12),
                  GhostButton(label: 'Retry', onPressed: _load),
                ],
              ),
            )
          : _buildBody(context, c, d),
    );
  }

  Widget _buildBody(BuildContext context, DashColors c, DesktopDashboard d) {
    final snap = d.snapshot;
    var section = 0;
    var fig = 0;
    String nextSection() => (++section).toString().padLeft(2, '0');
    String nextFig() => (++fig).toString().padLeft(2, '0');

    final children = <Widget>[];

    if (!d.hasAnything) {
      children.add(_BlankState(c: c));
    }

    if (d.chips.isNotEmpty) {
      children.add(
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final chip in d.chips)
              _SignalChip(
                chip: chip,
                value: snap.pulse[chip.id] ?? 0,
                onTap: _hrefTap(chip.href),
              ),
          ],
        ),
      );
    }

    if (d.pulseCells.isNotEmpty) {
      children.add(_BandTitle(c: c, name: 'Today', meta: 'since midnight'));
      children.add(_PulseBand(cells: d.pulseCells, pulse: snap.pulse));
    }

    if (d.heartbeatOk || d.feedOk) {
      children.add(
        _SectionTitle(
          num: nextSection(),
          name: 'Live Signal',
          meta: 'last 24 hours',
        ),
      );
      final hbFig = d.heartbeatOk ? nextFig() : '';
      final feedFig = d.feedOk ? nextFig() : '';
      final hb = d.heartbeatOk
          ? _ChartCard(
              icon: Icons.graphic_eq,
              title: 'Activity Heartbeat',
              fig: hbFig,
              extra: const _StreamingPill(),
              expand: true,
              child: _heartbeat(c, snap.heartbeat),
            )
          : null;
      final feed = d.feedOk
          ? _ChartCard(
              icon: Icons.satellite_alt_outlined,
              title: 'Activity Stream',
              fig: feedFig,
              extra: d.perms['activitylogs'] == true
                  ? _Presence(online: snap.online)
                  : null,
              bodyPadding: EdgeInsets.zero,
              expand: true,
              child: _Feed(
                items: snap.activity,
                tick: _tick,
                fetchedAt: _fetchedAt,
                perms: d.perms,
                onTap: _hrefTap,
              ),
            )
          : null;
      children.add(
        LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth >= 992;
            if (!wide) {
              return Column(
                children: [
                  if (hb != null) SizedBox(height: 416, child: hb),
                  if (hb != null && feed != null) const SizedBox(height: 16),
                  if (feed != null) SizedBox(height: 416, child: feed),
                ],
              );
            }
            final hbFlex = feed != null ? 8 : 12;
            final feedFlex = hb != null ? 4 : 5;
            return SizedBox(
              height: 416,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (hb != null) Expanded(flex: hbFlex, child: hb),
                  if (hb != null && feed != null) const SizedBox(width: 16),
                  if (feed != null) Expanded(flex: feedFlex, child: feed),
                  if (hb == null) const Spacer(flex: 7),
                ],
              ),
            );
          },
        ),
      );
    }

    if (d.statCards.isNotEmpty) {
      children.add(
        _SectionTitle(num: nextSection(), name: 'Totals', meta: '14-day trend'),
      );
      children.add(
        LayoutBuilder(
          builder: (context, box) {
            final cols = box.maxWidth >= 1200
                ? 4
                : box.maxWidth >= 992
                ? 3
                : box.maxWidth >= 600
                ? 2
                : 1;
            const gap = 16.0;
            final w = (box.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final card in d.statCards)
                  SizedBox(
                    width: w,
                    height: 183,
                    child: _StatCard(
                      card: card,
                      value: snap.totals[card.key] ?? 0,
                      series: card.series.isEmpty
                          ? null
                          : snap.series[card.series],
                      onTap: _hrefTap(card.href),
                    ),
                  ),
              ],
            );
          },
        ),
      );
    }

    final rev = d.revenue;
    if (rev != null) {
      children.add(
        _SectionTitle(
          num: nextSection(),
          name: 'License Revenue',
          meta: 'vendor payments',
        ),
      );
      children.add(_RevenuePanel(rev: rev));
    }

    for (final group in d.chartGroups) {
      if (group.items.isEmpty) continue;
      children.add(
        _SectionTitle(num: nextSection(), name: group.name, meta: group.meta),
      );
      final figs = [for (final _ in group.items) nextFig()];
      children.add(
        _ChartGrid(
          items: group.items,
          figs: figs,
          chartBuilder: (item, bodyH) => _chartFor(c, item, snap, bodyH),
          bodyHeight: (item) => _bodyHeight(item, snap),
        ),
      );
    }

    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 40),
      children: children,
    );
  }

  Widget _heartbeat(DashColors c, DashHeartbeat hb) {
    if (hb.isEmpty) return const DashNoData(height: 320);
    const defs = [
      ['actions', 'Staff actions'],
      ['messages', 'Chat messages'],
      ['tickets', 'Tickets'],
      ['emails', 'Emails'],
      ['files', 'File uploads'],
    ];
    final colors = {
      'actions': DashColors.brand,
      'messages': c.seriesInk,
      'tickets': DashColors.pos,
      'emails': DashColors.info,
      'files': DashColors.warn,
    };
    return DashHeartbeatChart(
      labels: hb.labels,
      height: 320,
      series: [
        for (final def in defs)
          if (hb.series[def[0]] != null)
            DashHeartbeatSeries(def[1], colors[def[0]]!, hb.series[def[0]]!),
      ],
    );
  }

  static const _doughnuts = <String, List<Object>>{
    'ticketStatusChart': ['ticketStatus', true, 'palette'],
    'licenseChart': ['license', false, 'brandInk'],
    'custStepChart': ['customerSteps', false, 'inkBrand'],
    'zreadStatusChart': ['zreadStatus', true, 'palette'],
    'emailStatusChart': ['emailStatus', true, 'palette'],
    'fileTypeChart': ['fileType', true, 'palette'],
    'taskStatusChart': ['taskStatus', true, 'palette'],
  };

  static const _bars = <String, List<Object>>{
    'leadTypeChart': ['leadType', false, 'Leads'],
    'custProvChart': ['customerProv', false, 'Customers'],
    'ticketPrioChart': ['ticketPriority', true, 'Tickets'],
    'notesVersionChart': ['notesVersion', false, 'Notes'],
  };

  static const _lines = <String, List<Object>>{
    'ticketMonthChart': ['ticketMonth', 'Tickets'],
    'emailMonthChart': ['emailMonth', 'Emails'],
    'fileMonthChart': ['fileMonth', 'Files'],
    'barcodeMonthChart': ['barcodeMonth', 'Barcodes'],
  };

  double _bodyHeight(DashChartItem item, DashSnapshot snap) {
    if (item.kind == 'doughnut') {
      final def = _doughnuts[item.id];
      final data = def == null ? null : snap.charts[def[0] as String];
      final rows = data == null || data.isEmpty ? 0 : data.labels.length;
      final legendH = rows * 17.0 + (rows - 1).clamp(0, 99) * 9.0;
      return legendH > 176 ? legendH : 176;
    }
    return item.height > 0 ? item.height : 240;
  }

  Widget _chartFor(
    DashColors c,
    DashChartItem item,
    DashSnapshot snap,
    double bodyH,
  ) {
    final dn = _doughnuts[item.id];
    if (dn != null) {
      final data = snap.charts[dn[0] as String] ?? const DashSeriesData([], []);
      if (data.isEmpty) {
        return Row(
          children: const [DashNoData(width: 152, height: 152), Spacer()],
        );
      }
      final labels = dn[1] == true
          ? data.labels.map(dashTitleCase).toList()
          : data.labels;
      final colors = switch (dn[2]) {
        'brandInk' => [DashColors.brand, c.seriesInk],
        'inkBrand' => [c.seriesInk, DashColors.brand],
        _ => c.palette,
      };
      return DashDoughnut(labels: labels, values: data.values, colors: colors);
    }
    final bar = _bars[item.id];
    if (bar != null) {
      final data =
          snap.charts[bar[0] as String] ?? const DashSeriesData([], []);
      if (data.isEmpty) return DashNoData(height: bodyH);
      final labels = bar[1] == true
          ? data.labels.map(dashTitleCase).toList()
          : data.labels;
      return DashBarChart(
        labels: labels,
        values: data.values,
        unit: bar[2] as String,
        height: bodyH,
      );
    }
    final line = _lines[item.id];
    if (line != null) {
      final data =
          snap.charts[line[0] as String] ?? const DashSeriesData([], []);
      if (data.isEmpty) return DashNoData(height: bodyH);
      return DashLineChart(
        labels: data.labels,
        values: data.values,
        unit: line[1] as String,
        height: bodyH,
      );
    }
    return DashNoData(height: bodyH);
  }
}

String _dateLabel(DateTime d) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
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
  return '${days[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}';
}

String _timeLabel(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}

String _agoText(double sec) {
  final s = sec < 0 ? 0 : sec.round();
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

String _peso(double v) {
  final fixed = v.abs().toStringAsFixed(2);
  final parts = fixed.split('.');
  return '${v < 0 ? '-' : ''}₱${dashFmt(int.parse(parts[0]))}.${parts[1]}';
}

IconData _faIcon(String fa) {
  switch (fa) {
    case 'fa-ticket-alt':
      return Icons.confirmation_number_outlined;
    case 'fa-check':
      return Icons.check;
    case 'fa-user-plus':
      return Icons.person_add_alt_1;
    case 'fa-key':
      return Icons.key;
    case 'fa-comment-dots':
      return Icons.sms_outlined;
    case 'fa-envelope':
      return Icons.mail_outline;
    case 'fa-file-upload':
      return Icons.upload_file;
    case 'fa-receipt':
      return Icons.receipt_long_outlined;
    case 'fa-barcode':
      return Icons.qr_code_2;
    case 'fa-tasks':
      return Icons.checklist;
    case 'fa-bolt':
      return Icons.bolt;
    case 'fa-user-clock':
      return Icons.person_search;
    case 'fa-handshake':
      return Icons.handshake_outlined;
    case 'fa-users':
      return Icons.groups_2_outlined;
    case 'fa-user-tie':
      return Icons.badge_outlined;
    case 'fa-id-card':
      return Icons.credit_card;
    case 'fa-blog':
      return Icons.rss_feed;
    case 'fa-user-shield':
      return Icons.admin_panel_settings_outlined;
    case 'fa-paper-plane':
      return Icons.send_outlined;
    case 'fa-envelope-open':
      return Icons.drafts_outlined;
    case 'fa-file':
      return Icons.insert_drive_file_outlined;
    case 'fa-folder-open':
      return Icons.folder_open_outlined;
    case 'fa-code-branch':
      return Icons.account_tree_outlined;
    case 'fa-clipboard-list':
      return Icons.assignment_outlined;
    case 'fa-map-marker-alt':
      return Icons.location_on_outlined;
    case 'fa-exclamation-circle':
      return Icons.error_outline;
    case 'fa-chart-line':
      return Icons.show_chart;
    case 'fa-check-circle':
      return Icons.check_circle_outline;
  }
  return Icons.circle_outlined;
}

class _BlankState extends StatelessWidget {
  const _BlankState({required this.c});
  final DashColors c;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.line),
      ),
      child: Column(
        children: [
          Icon(Icons.lock_outline, size: 34, color: c.muted2),
          const SizedBox(height: 14),
          Text(
            'Nothing to show yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Your account doesn’t have access to any of the modules this dashboard reports on. Ask an administrator to grant the permissions you need.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: c.muted),
          ),
        ],
      ),
    );
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill({
    required this.mode,
    required this.tick,
    required this.fetchedAt,
    required this.pollSeq,
    required this.pollMs,
    required this.onToggle,
  });

  final _LiveMode mode;
  final ValueNotifier<DateTime> tick;
  final DateTime? fetchedAt;
  final int pollSeq;
  final int pollMs;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final c = DashColors.of(context);
    final offline = mode == _LiveMode.offline;
    final paused = mode == _LiveMode.paused;
    final wordColor = offline
        ? DashColors.neg
        : paused
        ? c.muted
        : DashColors.pos;
    final dotColor = offline
        ? DashColors.neg
        : paused
        ? c.muted2
        : DashColors.pos;
    return Container(
      height: 42,
      padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
      decoration: BoxDecoration(
        color: offline ? DashColors.neg.withValues(alpha: 0.09) : c.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: offline ? DashColors.neg.withValues(alpha: 0.35) : c.line,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                offline ? 'OFFLINE' : (paused ? 'PAUSED' : 'LIVE'),
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.9,
                  color: wordColor,
                ),
              ),
              const SizedBox(width: 10),
              Container(width: 1, height: 14, color: c.line),
              const SizedBox(width: 10),
              SizedBox(
                width: 92,
                child: ValueListenableBuilder<DateTime>(
                  valueListenable: tick,
                  builder: (context, now, _) {
                    final at = fetchedAt;
                    final label = offline
                        ? 'reconnecting…'
                        : paused
                        ? 'paused'
                        : at == null
                        ? 'syncing…'
                        : 'updated ${_agoText(now.difference(at).inMilliseconds / 1000)}';
                    return Text(
                      label,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 11,
                        color: c.muted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              Tooltip(
                message: paused ? 'Resume live updates' : 'Pause live updates',
                child: Material(
                  color: c.surface2,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onToggle,
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: Icon(
                        paused ? Icons.play_arrow : Icons.pause,
                        size: 14,
                        color: c.muted,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (mode == _LiveMode.live)
            Positioned(
              left: -12,
              right: -8,
              bottom: 0,
              child: TweenAnimationBuilder<double>(
                key: ValueKey(pollSeq),
                tween: Tween(begin: 0, end: 1),
                duration: Duration(milliseconds: pollMs),
                builder: (context, v, _) => Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: v,
                    child: Container(
                      height: 2,
                      color: DashColors.brand.withValues(alpha: 0.5),
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

class _SignalChip extends StatefulWidget {
  const _SignalChip({required this.chip, required this.value, this.onTap});
  final DashChip chip;
  final int value;
  final VoidCallback? onTap;

  @override
  State<_SignalChip> createState() => _SignalChipState();
}

class _SignalChipState extends State<_SignalChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = DashColors.of(context);
    final alert = widget.chip.level == 'alert' && widget.value > 0;
    final critical = widget.chip.level == 'critical' && widget.value > 0;
    final fg = alert
        ? DashColors.brand700
        : critical
        ? DashColors.neg
        : (_hover ? c.ink : c.muted);
    final numColor = alert
        ? DashColors.brand700
        : critical
        ? DashColors.neg
        : c.ink;
    final dot = alert
        ? DashColors.brand
        : critical
        ? DashColors.neg
        : c.muted2;
    final bg = alert
        ? c.brand050
        : critical
        ? DashColors.neg.withValues(alpha: 0.09)
        : c.surface;
    final border = alert
        ? DashColors.brand.withValues(alpha: 0.4)
        : critical
        ? DashColors.neg.withValues(alpha: 0.35)
        : (_hover ? c.inkSoft : c.line);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          transform: Matrix4.translationValues(0, _hover ? -1 : 0, 0),
          padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: border),
            boxShadow: [
              BoxShadow(
                color: DashColors.inkHex.withValues(
                  alpha: _hover ? 0.08 : 0.04,
                ),
                blurRadius: _hover ? 8 : 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 9),
              Text(
                dashFmt(widget.value),
                style: TextStyle(
                  fontSize: 14.7,
                  fontWeight: FontWeight.w700,
                  color: numColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 9),
              Text(
                widget.chip.label.toUpperCase(),
                style: TextStyle(
                  fontSize: 10.2,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BandTitle extends StatelessWidget {
  const _BandTitle({required this.c, required this.name, required this.meta});
  final DashColors c;
  final String name;
  final String meta;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Row(
        children: [
          Text(
            name.toUpperCase(),
            style: TextStyle(
              fontSize: 10.6,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.9,
              color: c.ink,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Container(height: 1, color: c.line)),
          const SizedBox(width: 12),
          Text(
            meta.toUpperCase(),
            style: TextStyle(
              fontSize: 10.2,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: c.muted2,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.num,
    required this.name,
    required this.meta,
  });
  final String num;
  final String name;
  final String meta;

  @override
  Widget build(BuildContext context) {
    final c = DashColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 30, bottom: 22),
      child: Row(
        children: [
          Container(
            height: 22,
            constraints: const BoxConstraints(minWidth: 22),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.brand050,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              num,
              style: const TextStyle(
                fontSize: 9.6,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
                color: DashColors.brand700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            name.toUpperCase(),
            style: TextStyle(
              fontSize: 10.6,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.9,
              color: c.ink,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Container(height: 1, color: c.line)),
          const SizedBox(width: 12),
          Text(
            meta.toUpperCase(),
            style: TextStyle(
              fontSize: 10.2,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: c.muted2,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseBand extends StatelessWidget {
  const _PulseBand({required this.cells, required this.pulse});
  final List<DashPulseCell> cells;
  final Map<String, int> pulse;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => _band(
        context,
        ResponsiveGrid.columnsFor(cells.length, box.maxWidth, 150, 0, max: 6),
      ),
    );
  }

  Widget _band(BuildContext context, int cols) {
    final c = DashColors.of(context);
    final rows = <List<DashPulseCell>>[];
    for (var i = 0; i < cells.length; i += cols) {
      rows.add(
        cells.sublist(i, i + cols > cells.length ? cells.length : i + cols),
      );
    }
    Widget cell(DashPulseCell p, bool lastCol) => Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        border: Border(
          right: lastCol ? BorderSide.none : BorderSide(color: c.lineSoft),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: c.brand050,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  _faIcon(p.icon),
                  size: 11,
                  color: DashColors.brand600,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  p.label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.3,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.3,
                    color: c.muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            dashFmt(pulse[p.id] ?? 0),
            style: TextStyle(
              fontSize: 24.8,
              fontWeight: FontWeight.w700,
              height: 1.1,
              color: c.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.line),
        boxShadow: [
          BoxShadow(
            color: DashColors.inkHex.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var r = 0; r < rows.length; r++)
            Container(
              decoration: BoxDecoration(
                border: r == rows.length - 1
                    ? null
                    : Border(bottom: BorderSide(color: c.lineSoft)),
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < rows[r].length; i++)
                      Expanded(
                        flex: i == rows[r].length - 1
                            ? cols - rows[r].length + 1
                            : 1,
                        child: cell(rows[r][i], i == rows[r].length - 1),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChartCard extends StatefulWidget {
  const _ChartCard({
    required this.icon,
    required this.title,
    required this.fig,
    required this.child,
    this.extra,
    this.bodyPadding = const EdgeInsets.all(18),
    this.expand = false,
  });

  final IconData icon;
  final String title;
  final String fig;
  final Widget child;
  final Widget? extra;
  final EdgeInsets bodyPadding;
  final bool expand;

  @override
  State<_ChartCard> createState() => _ChartCardState();
}

class _ChartCardState extends State<_ChartCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = DashColors.of(context);
    final body = Padding(padding: widget.bodyPadding, child: widget.child);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _hover
                ? (c.dark ? c.muted2 : const Color(0xFFCFD8E4))
                : c.line,
          ),
          boxShadow: [
            BoxShadow(
              color: DashColors.inkHex.withValues(alpha: _hover ? 0.1 : 0.04),
              blurRadius: _hover ? 18 : 2,
              offset: Offset(0, _hover ? 6 : 1),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Container(
              constraints: const BoxConstraints(minHeight: 58),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.lineSoft)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: c.brand050,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      widget.icon,
                      size: 14,
                      color: DashColors.brand600,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.8,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                  ),
                  if (widget.extra != null) ...[
                    const SizedBox(width: 10),
                    widget.extra!,
                  ],
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: c.surface2,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      widget.fig,
                      style: TextStyle(
                        fontSize: 9.3,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.9,
                        color: c.muted2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (widget.expand) Expanded(child: body) else body,
          ],
        ),
      ),
    );
  }
}

class _StreamingPill extends StatelessWidget {
  const _StreamingPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: DashColors.pos.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: DashColors.pos,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'STREAMING',
            style: TextStyle(
              fontSize: 8.8,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
              color: DashColors.pos,
            ),
          ),
        ],
      ),
    );
  }
}

class _Presence extends StatelessWidget {
  const _Presence({required this.online});
  final List<DashOnline> online;

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    final a = parts.first[0];
    final b = parts.length > 1 ? parts.last[0] : '';
    return (a + b).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final c = DashColors.of(context);
    final label = TextStyle(
      fontSize: 9.3,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.3,
      color: c.muted2,
    );
    if (online.isEmpty) return Text('NOBODY ONLINE', style: label);
    final shown = online.take(3).toList();
    final rest = online.length - shown.length;
    final avatars = <Widget>[
      for (final u in shown)
        Tooltip(
          message: u.name,
          child: _avatar(
            c,
            _initials(u.name),
            c.seriesInk,
            c.dark ? DashColors.inkHex : Colors.white,
          ),
        ),
      if (rest > 0) _avatar(c, '+$rest', c.brand050, DashColors.brand700),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 26 + (avatars.length - 1) * 18.0,
          height: 26,
          child: Stack(
            children: [
              for (var i = 0; i < avatars.length; i++)
                Positioned(left: i * 18.0, child: avatars[i]),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text('${online.length} ONLINE', style: label),
      ],
    );
  }

  Widget _avatar(DashColors c, String text, Color bg, Color fg) => Container(
    width: 26,
    height: 26,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: bg,
      shape: BoxShape.circle,
      border: Border.all(color: c.surface, width: 2),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 9.3, fontWeight: FontWeight.w700, color: fg),
    ),
  );
}

class _Feed extends StatelessWidget {
  const _Feed({
    required this.items,
    required this.tick,
    required this.fetchedAt,
    required this.perms,
    required this.onTap,
  });

  final List<DashActivity> items;
  final ValueNotifier<DateTime> tick;
  final DateTime? fetchedAt;
  final Map<String, bool> perms;
  final VoidCallback? Function(String) onTap;

  static const _hrefPerm = {
    'ticket': 'ticket',
    'clientOffer': 'clientOffer',
    'license': 'licensekey',
    'activity_logs': 'activitylogs',
    'chat': 'chat',
    'emails': 'emails',
    'files-management': 'files',
    'z-reading-request': 'zreading',
    'barcode': 'barcode',
    'release_notes': 'releasenotes',
    'task': 'task',
  };

  @override
  Widget build(BuildContext context) {
    final c = DashColors.of(context);
    if (items.isEmpty) {
      return Center(
        child: Text(
          'NO RECENT ACTIVITY.',
          style: TextStyle(
            fontSize: 11.8,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.7,
            color: c.muted2,
          ),
        ),
      );
    }
    return Stack(
      children: [
        ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: items.length,
          itemBuilder: (context, i) {
            final a = items[i];
            final allowed = perms[_hrefPerm[a.href] ?? ''] == true;
            return _FeedRow(
              item: a,
              last: i == items.length - 1,
              tick: tick,
              fetchedAt: fetchedAt,
              onTap: allowed ? onTap(a.href) : null,
            );
          },
        ),
        Positioned(
          left: 0,
          right: 6,
          bottom: 0,
          height: 32,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [c.surface.withValues(alpha: 0), c.surface],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FeedRow extends StatefulWidget {
  const _FeedRow({
    required this.item,
    required this.last,
    required this.tick,
    required this.fetchedAt,
    this.onTap,
  });

  final DashActivity item;
  final bool last;
  final ValueNotifier<DateTime> tick;
  final DateTime? fetchedAt;
  final VoidCallback? onTap;

  @override
  State<_FeedRow> createState() => _FeedRowState();
}

class _FeedRowState extends State<_FeedRow> {
  bool _hover = false;

  (Color, Color) _markColors(DashColors c, String kind) {
    switch (kind) {
      case 'ticket':
        return (c.ink.withValues(alpha: 0.07), c.ink);
      case 'lead':
      case 'barcode':
        return (c.brand050, DashColors.brand600);
      case 'license':
      case 'task':
        return (DashColors.pos.withValues(alpha: 0.12), DashColors.pos);
      case 'email':
      case 'file':
        return (DashColors.info.withValues(alpha: 0.09), DashColors.info);
      case 'zread':
      case 'note':
        return (DashColors.warn.withValues(alpha: 0.1), DashColors.warn);
    }
    return (c.surface2, c.muted);
  }

  @override
  Widget build(BuildContext context) {
    final c = DashColors.of(context);
    final a = widget.item;
    final (bg, fg) = _markColors(c, a.kind);
    final link = widget.onTap != null;
    return MouseRegion(
      cursor: link ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: link ? (_) => setState(() => _hover = true) : null,
      onExit: link ? (_) => setState(() => _hover = false) : null,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: _hover ? c.surface2 : null,
            border: Border(
              left: BorderSide(
                color: _hover ? DashColors.brand : Colors.transparent,
                width: 2,
              ),
              bottom: widget.last
                  ? BorderSide.none
                  : BorderSide(color: c.lineSoft),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                margin: const EdgeInsets.only(top: 1),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(_faIcon(a.icon), size: 12, color: fg),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      a.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.2,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text.rich(
                      TextSpan(
                        children: [
                          if (a.who.isNotEmpty)
                            TextSpan(
                              text: a.who,
                              style: TextStyle(
                                color: c.inkSoft,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          if (a.who.isNotEmpty && a.body.isNotEmpty)
                            const TextSpan(text: ' · '),
                          TextSpan(text: a.body),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.9,
                        color: c.muted,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: ValueListenableBuilder<DateTime>(
                  valueListenable: widget.tick,
                  builder: (context, now, _) {
                    final base = widget.fetchedAt ?? now;
                    final secs =
                        a.ago + now.difference(base).inMilliseconds / 1000;
                    return Text(
                      _agoText(secs).toUpperCase(),
                      style: TextStyle(
                        fontSize: 9.3,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
                        color: c.muted2,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatefulWidget {
  const _StatCard({
    required this.card,
    required this.value,
    required this.series,
    this.onTap,
  });

  final DashStatCard card;
  final int value;
  final List<int>? series;
  final VoidCallback? onTap;

  @override
  State<_StatCard> createState() => _StatCardState();
}

class _StatCardState extends State<_StatCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = DashColors.of(context);
    final primary = widget.card.primary;
    final series = widget.series;
    final today = series == null || series.isEmpty ? null : series.last;
    final up = today != null && today > 0;

    Widget delta;
    if (widget.card.series.isEmpty) {
      delta = _delta(c, Icons.storage_rounded, 'ALL TIME', false, primary);
    } else if (series == null || series.isEmpty) {
      delta = _delta(c, null, 'NO TREND', false, primary);
    } else if (up) {
      delta = _delta(
        c,
        Icons.show_chart,
        '+${dashFmt(today)} TODAY',
        true,
        primary,
      );
    } else {
      delta = _delta(c, Icons.remove, 'NONE TODAY', false, primary);
    }

    final decoration = primary
        ? BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hover ? DashColors.brand : DashColors.inkHex,
            ),
            gradient: const LinearGradient(
              begin: Alignment(-0.35, -1),
              end: Alignment(0.35, 1),
              stops: [0, 0.62],
              colors: [Color(0xFF12253C), DashColors.inkHex],
            ),
            boxShadow: [
              BoxShadow(
                color: _hover
                    ? DashColors.brand.withValues(alpha: 0.45)
                    : DashColors.inkHex.withValues(alpha: 0.04),
                blurRadius: _hover ? 40 : 2,
                spreadRadius: _hover ? -20 : 0,
                offset: Offset(0, _hover ? 18 : 1),
              ),
            ],
          )
        : BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hover
                  ? (c.dark ? c.muted2 : const Color(0xFFCFD8E4))
                  : c.line,
            ),
            boxShadow: [
              BoxShadow(
                color: DashColors.inkHex.withValues(alpha: _hover ? 0.1 : 0.04),
                blurRadius: _hover ? 18 : 2,
                offset: Offset(0, _hover ? 6 : 1),
              ),
            ],
          );

    final iconActive = _hover;
    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          transform: Matrix4.translationValues(0, _hover ? -2 : 0, 0),
          decoration: decoration,
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              if (primary) ...[
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(1.16, -1.4),
                        radius: 1.1,
                        colors: [
                          DashColors.brand.withValues(alpha: 0.22),
                          DashColors.brand.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(-1.2, 1.4),
                        radius: 1.0,
                        colors: [
                          DashColors.brand.withValues(alpha: 0.09),
                          DashColors.brand.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 2,
                child: AnimatedFractionallySizedBox(
                  duration: const Duration(milliseconds: 320),
                  alignment: Alignment.centerLeft,
                  widthFactor: _hover ? 1 : 0,
                  child: Container(color: DashColors.brand),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: iconActive
                                ? DashColors.brand
                                : primary
                                ? DashColors.brand.withValues(alpha: 0.16)
                                : c.brand050,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: primary && !iconActive
                                  ? DashColors.brand.withValues(alpha: 0.32)
                                  : Colors.transparent,
                            ),
                          ),
                          child: Icon(
                            _faIcon(widget.card.icon),
                            size: 16,
                            color: iconActive
                                ? Colors.white
                                : primary
                                ? DashColors.brand
                                : DashColors.brand600,
                          ),
                        ),
                        const Spacer(),
                        AnimatedOpacity(
                          duration: const Duration(milliseconds: 240),
                          opacity: _hover && widget.onTap != null ? 1 : 0,
                          child: Icon(
                            Icons.open_in_new,
                            size: 13,
                            color: primary
                                ? DashColors.brand
                                : DashColors.brand600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          dashFmt(widget.value),
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            height: 1,
                            letterSpacing: -1.1,
                            color: primary ? Colors.white : c.ink,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        if (primary && widget.value > 0) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: DashColors.brand,
                              borderRadius: BorderRadius.circular(999),
                              boxShadow: [
                                BoxShadow(
                                  color: DashColors.brand.withValues(
                                    alpha: 0.2,
                                  ),
                                  spreadRadius: 3,
                                ),
                              ],
                            ),
                            child: const Text(
                              'NEW',
                              style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.85,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 9),
                    Text(
                      widget.card.label.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.2,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.3,
                        color: primary
                            ? Colors.white.withValues(alpha: 0.62)
                            : c.muted,
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      height: 30,
                      child: Row(
                        children: [
                          if (widget.card.series.isNotEmpty &&
                              series != null &&
                              series.length >= 2)
                            Expanded(
                              child: DashSparkline(
                                data: series,
                                primary: primary,
                              ),
                            )
                          else
                            const Spacer(),
                          const SizedBox(width: 12),
                          delta,
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _delta(
    DashColors c,
    IconData? icon,
    String text,
    bool up,
    bool primary,
  ) {
    final Color bg;
    final Color fg;
    if (primary) {
      bg = up
          ? DashColors.brand.withValues(alpha: 0.2)
          : Colors.white.withValues(alpha: 0.1);
      fg = up ? const Color(0xFFFFC48A) : Colors.white.withValues(alpha: 0.82);
    } else {
      bg = up ? DashColors.pos.withValues(alpha: 0.12) : c.surface2;
      fg = up ? DashColors.pos : c.muted;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: fg),
            const SizedBox(width: 5),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 9.6,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _RevenuePanel extends StatelessWidget {
  const _RevenuePanel({required this.rev});
  final DashRevenue rev;

  @override
  Widget build(BuildContext context) {
    final c = DashColors.of(context);
    final panel = BoxDecoration(
      color: c.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: c.ink.withValues(alpha: 0.08)),
      boxShadow: [
        BoxShadow(
          color: DashColors.inkHex.withValues(alpha: 0.12),
          blurRadius: 40,
          spreadRadius: -24,
          offset: const Offset(0, 18),
        ),
      ],
    );
    if (!rev.available) {
      return Container(
        decoration: panel,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Text(
          'No vendor license payments have been taken on this install yet.',
          style: TextStyle(fontSize: 14, color: c.muted),
        ),
      );
    }
    final figs = [
      _RevFig(
        'Earned all time',
        _peso(rev.total),
        '${dashFmt(rev.paidCount)} key${rev.paidCount == 1 ? '' : 's'} paid for',
        lead: true,
      ),
      _RevFig(
        'This month',
        _peso(rev.month),
        '${dashFmt(rev.monthCount)} this month · ${_peso(rev.today)} today',
      ),
      _RevFig(
        'Average per key',
        _peso(rev.average),
        'Default price ${_peso(rev.defaultPrice ?? 0)}',
      ),
      _RevFig(
        'Started, not paid',
        dashFmt(rev.pendingCount),
        '${_peso(rev.pendingValue)} not collected',
      ),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final cols = box.maxWidth > 1200
            ? 4
            : box.maxWidth > 640
            ? 2
            : 1;
        final rows = <List<_RevFig>>[];
        for (var i = 0; i < figs.length; i += cols) {
          rows.add(figs.sublist(i, i + cols));
        }
        return Container(
          decoration: panel,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var r = 0; r < rows.length; r++)
                Container(
                  decoration: BoxDecoration(
                    border: r == 0
                        ? null
                        : Border(
                            top: BorderSide(
                              color: c.ink.withValues(alpha: 0.08),
                            ),
                          ),
                  ),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < rows[r].length; i++)
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                border: i == 0
                                    ? null
                                    : Border(
                                        left: BorderSide(
                                          color: c.ink.withValues(alpha: 0.08),
                                        ),
                                      ),
                              ),
                              child: rows[r][i],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _RevFig extends StatelessWidget {
  const _RevFig(this.label, this.value, this.note, {this.lead = false});
  final String label;
  final String value;
  final String note;
  final bool lead;

  @override
  Widget build(BuildContext context) {
    final c = DashColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: lead
          ? BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                stops: const [0, 0.7],
                colors: [c.brand050, c.surface],
              ),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10.9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: c.muted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 25.6,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: lead ? DashColors.brand700 : c.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          Text(note, style: TextStyle(fontSize: 12.5, color: c.muted)),
        ],
      ),
    );
  }
}

class _ChartGrid extends StatelessWidget {
  const _ChartGrid({
    required this.items,
    required this.figs,
    required this.chartBuilder,
    required this.bodyHeight,
  });

  final List<DashChartItem> items;
  final List<String> figs;
  final Widget Function(DashChartItem, double) chartBuilder;
  final double Function(DashChartItem) bodyHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 992;
        final count = items.length;
        int span(DashChartItem i) {
          if (!wide) return 12;
          if (i.width != null) return i.width!;
          if (count >= 3) return 4;
          return 6;
        }

        final rows = <List<int>>[];
        var cur = <int>[];
        var used = 0;
        for (var i = 0; i < count; i++) {
          final s = span(items[i]);
          if (used + s > 12 && cur.isNotEmpty) {
            rows.add(cur);
            cur = [];
            used = 0;
          }
          cur.add(i);
          used += s;
        }
        if (cur.isNotEmpty) rows.add(cur);

        const gap = 16.0;
        final unit = (box.maxWidth + gap) / 12;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var r = 0; r < rows.length; r++) ...[
              if (r > 0) const SizedBox(height: 18),
              Builder(
                builder: (context) {
                  var bodyH = 0.0;
                  for (final i in rows[r]) {
                    final h = bodyHeight(items[i]);
                    if (h > bodyH) bodyH = h;
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var k = 0; k < rows[r].length; k++) ...[
                        if (k > 0) const SizedBox(width: gap),
                        SizedBox(
                          width: unit * span(items[rows[r][k]]) - gap,
                          child: _ChartCard(
                            icon: _faIcon(items[rows[r][k]].icon),
                            title: items[rows[r][k]].title,
                            fig: figs[rows[r][k]],
                            child: SizedBox(
                              height: bodyH,
                              child: chartBuilder(items[rows[r][k]], bodyH),
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ],
          ],
        );
      },
    );
  }
}
