import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api_client.dart';
import '../services/profile_service.dart';
import '../shell_icons.dart';
import '../theme.dart';
import '../widgets/tp_loader.dart';

const _kBrand = Color(0xFFFF7D00);
const _kInfo = Color(0xFF2563EB);
const _kLive = Color(0xFF0E9F6E);
const _kInk = Color(0xFF0B1B30);
const _kMuted = Color(0xFF8496A9);
const _kWarn = Color(0xFFD97706);
const _kDanger = Color(0xFFDC2626);

const _kStatusColors = <String, Color>{
  'new': _kInfo,
  'assigned': Color(0xFF7C3AED),
  'in_progress': _kWarn,
  'resolved': _kLive,
  'closed': _kMuted,
};

const _kPriorityColors = <String, Color>{
  'low': _kMuted,
  'medium': _kInfo,
  'high': _kWarn,
  'urgent': _kDanger,
};

const _kMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

Future<void> showProfilePanel(
  BuildContext context, {
  required ApiClient api,
  int userId = 0,
  String? seedName,
  String? seedAvatar,
  String? selfName,
  String? selfRole,
  VoidCallback? onEditProfile,
  VoidCallback? onActivityLog,
  VoidCallback? onDesktopSettings,
}) {
  final self = userId <= 0 || userId == api.userId;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close profile',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (ctx, _, _) => ProfilePanel(
      api: api,
      userId: self ? 0 : userId,
      seedName: self ? (selfName ?? api.username ?? '') : (seedName ?? ''),
      seedRole: self ? (selfRole ?? '') : '',
      seedAvatar: seedAvatar ?? '',
      onEditProfile: onEditProfile,
      onActivityLog: onActivityLog,
      onDesktopSettings: onDesktopSettings,
    ),
    transitionBuilder: (ctx, anim, _, child) {
      final fade = CurvedAnimation(parent: anim, curve: Curves.ease);
      final slide = CurvedAnimation(
        parent: anim,
        curve: const Cubic(.2, .8, .2, 1),
        reverseCurve: Curves.easeIn,
      );
      return Stack(children: [
        Positioned.fill(
          child: IgnorePointer(
            child: FadeTransition(
              opacity: fade,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                child: const ColoredBox(color: Color(0x730B1B30)),
              ),
            ),
          ),
        ),
        SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(-1.02, 0),
            end: Offset.zero,
          ).animate(slide),
          child: child,
        ),
      ]);
    },
  );
}

class _Pal {
  _Pal(BuildContext context)
      : dark = Theme.of(context).brightness == Brightness.dark,
        b = context.brand;
  final bool dark;
  final BrandColors b;

  Color get body => dark ? b.canvas : const Color(0xFFF6F8FB);
  Color get card => dark ? b.surface : Colors.white;
  Color get border => dark ? b.rule : const Color(0xFFE6EBF2);
  Color get ink => dark ? b.paper : _kInk;
  Color get sub => dark ? b.paperDim : const Color(0xFF5A6B80);
  Color get text => dark ? b.paperDim : const Color(0xFF33465C);
  Color get track => dark ? b.surfaceHi : const Color(0xFFEDF1F6);
  Color get grid =>
      dark ? Colors.white.withValues(alpha: 0.06) : const Color(0x0F0B1B30);
}

class ProfilePanel extends StatefulWidget {
  const ProfilePanel({
    super.key,
    required this.api,
    this.userId = 0,
    this.seedName = '',
    this.seedRole = '',
    this.seedAvatar = '',
    this.onEditProfile,
    this.onActivityLog,
    this.onDesktopSettings,
  });

  final ApiClient api;
  final int userId;
  final String seedName;
  final String seedRole;
  final String seedAvatar;
  final VoidCallback? onEditProfile;
  final VoidCallback? onActivityLog;
  final VoidCallback? onDesktopSettings;

  @override
  State<ProfilePanel> createState() => _ProfilePanelState();
}

class _ProfilePanelState extends State<ProfilePanel> {
  late final ProfileService _svc = ProfileService(widget.api);
  ProfileStats? _data;
  bool _loading = false;
  bool _failed = false;
  int _req = 0;
  Timer? _timer;
  DateTime? _updated;
  final ScrollController _scroll = ScrollController();

  bool get _peer => widget.userId > 0;

  bool get _isSelf {
    if (!_peer) return true;
    final id = _data?.profileId ?? 0;
    return id > 0 && id == widget.api.userId;
  }

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    final req = ++_req;
    try {
      final d = await _svc.load(userId: widget.userId);
      if (!mounted || req != _req) return;
      setState(() {
        _data = d;
        _failed = false;
        _updated = DateTime.now();
      });
      if (kDebugMode && Platform.environment['TP_PROFILE_SCROLL'] == '1') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.jumpTo(_scroll.position.maxScrollExtent);
          }
        });
      }
    } catch (_) {
      if (!mounted || req != _req) return;
      if (_data == null) setState(() => _failed = true);
    } finally {
      if (req == _req) _loading = false;
    }
  }

  void _close() => Navigator.of(context).maybePop();

  void _then(VoidCallback f) {
    Navigator.of(context).pop();
    f();
  }

  @override
  Widget build(BuildContext context) {
    final p = _Pal(context);
    final w = math.min(440.0, MediaQuery.sizeOf(context).width * 0.92);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _close,
      },
      child: Focus(
        autofocus: true,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Material(
            color: p.body,
            elevation: 0,
            child: Container(
              width: w,
              height: double.infinity,
              decoration: BoxDecoration(
                color: p.body,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x470B1B30),
                    blurRadius: 60,
                    offset: Offset(24, 0),
                  ),
                ],
              ),
              child: Column(children: [
                _header(),
                Expanded(child: _body(p)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final d = _data;
    final prof = d?.profile ?? const <String, dynamic>{};
    final name = '${prof['full_name'] ?? ''}'.trim().isNotEmpty
        ? '${prof['full_name']}'
        : ('${prof['username'] ?? ''}'.trim().isNotEmpty
            ? '${prof['username']}'
            : (widget.seedName.isNotEmpty
                ? widget.seedName
                : (_peer ? 'Profile' : '')));
    final role = _titleCase(
        '${prof['role'] ?? ''}'.isNotEmpty ? '${prof['role']}' : widget.seedRole);
    final email = '${prof['email'] ?? ''}';
    final avatar = d != null ? '${prof['avatar'] ?? ''}' : widget.seedAvatar;
    final online = d?.online ?? false;
    final ago = d?.lastSeenAgo;

    final bits = <String>[];
    if (d != null) {
      final fs = DateTime.tryParse(d.firstSeen.replaceFirst(' ', 'T'));
      if (fs != null) {
        bits.add('Active since ${_kMonths[fs.month - 1]} ${fs.year}');
      }
      if (!online && ago != null) bits.add('Last seen ${_agoText(ago)}');
    }

    return Stack(children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0C233E), Color(0xFF16375C)],
          ),
        ),
        child: Row(children: [
          _Avatar(
            url: _svc.url(avatar),
            headers: _svc.authHeaders,
            name: name,
            online: online,
            presenceTitle: d == null
                ? 'Checking presence…'
                : (online
                    ? 'Online'
                    : (ago != null ? 'Last seen ${_agoText(ago)}' : 'Away')),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17.9,
                          height: 1.2,
                          letterSpacing: -0.18,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 7),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    if (role.isNotEmpty)
                      _Chip(
                        text: role,
                        bg: const Color(0x2EFF7D00),
                        fg: const Color(0xFFFFB066),
                      ),
                    if (d != null)
                      _Chip(
                        text: online ? 'Online' : 'Away',
                        bg: online
                            ? const Color(0x2E0E9F6E)
                            : const Color(0x1FFFFFFF),
                        fg: online
                            ? const Color(0xFF5AD3A6)
                            : const Color(0xFFC7D0DB),
                      ),
                  ]),
                  if (email.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      const Icon(Fa.envelope,
                          size: 11, color: Color(0xB8FFFFFF)),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(email,
                            style: const TextStyle(
                                color: Color(0xB8FFFFFF),
                                fontSize: 12.2,
                                height: 1.3)),
                      ),
                    ]),
                  ],
                  if (bits.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(bits.join(' · '),
                        style: const TextStyle(
                            color: Color(0x80FFFFFF),
                            fontSize: 11.5,
                            height: 1.3)),
                  ],
                ],
              ),
            ),
          ),
        ]),
      ),
      Positioned(
        top: 14,
        right: 14,
        child: _CloseButton(onTap: _close),
      ),
    ]);
  }

  Widget _body(_Pal p) {
    final d = _data;
    if (d == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
        child: Align(
          alignment: Alignment.topLeft,
          child: _failed
              ? SizedBox(
                  width: double.infinity,
                  child: Text(
                    'Could not load ${_peer ? 'this profile' : 'your stats'} right now.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: _kMuted, fontSize: 12.2),
                  ),
                )
              : Row(children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: TpLoader(
                      strokeWidth: 2,
                      color: _kBrand,
                      backgroundColor: Color(0x40FF7D00),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(_peer ? 'Loading profile…' : 'Loading your stats…',
                      style: TextStyle(color: p.sub, fontSize: 13.6)),
                ]),
        ),
      );
    }
    final self = _isSelf;
    final showActions =
        self && (widget.onEditProfile != null || widget.onActivityLog != null);
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 26),
      children: [
        _tiles(d, p, self),
        const SizedBox(height: 14),
        _trendCard(d, p, self),
        ..._statusCard(d, p, self),
        ..._priorityCard(d, p),
        if (showActions)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(children: [
              if (widget.onEditProfile != null)
                Expanded(
                  child: _ActionButton(
                    icon: Fa.userCog,
                    label: 'Edit profile',
                    primary: true,
                    onTap: () => _then(widget.onEditProfile!),
                  ),
                ),
              if (widget.onEditProfile != null && widget.onActivityLog != null)
                const SizedBox(width: 8),
              if (widget.onActivityLog != null)
                Expanded(
                  child: _ActionButton(
                    icon: Fa.history,
                    label: 'Activity log',
                    onTap: () => _then(widget.onActivityLog!),
                  ),
                ),
            ]),
          ),
        const SizedBox(height: 10),
        Text(
          _updated == null ? '' : 'Updated ${_clock(_updated!)}',
          textAlign: TextAlign.center,
          style: const TextStyle(color: _kMuted, fontSize: 10.9),
        ),
        if (self && widget.onDesktopSettings != null) ...[
          const SizedBox(height: 6),
          Center(
            child: _FooterLink(
              icon: Fa.desktop,
              label: 'Desktop app settings',
              onTap: () => _then(widget.onDesktopSettings!),
            ),
          ),
        ],
      ],
    );
  }

  Widget _tiles(ProfileStats d, _Pal p, bool self) {
    final customer = d.mode == 'customer';
    final tiles = <_TileData>[];
    if (d.hasFlag('ticket')) {
      tiles.add(_TileData('Resolved', Fa.checkCircleSolid,
          _fmt(d.kpi('tickets_resolved')),
          '${d.kpi('resolved_today')} today · ${_fmt(d.kpi('resolved_30d'))} in 30d'));
      tiles.add(_TileData('Open now', Fa.inbox, _fmt(d.kpi('tickets_open')),
          '${d.kpi('tickets_hot')} high priority'));
      tiles.add(_TileData('Resolve rate', Fa.tachometerAlt,
          '${d.kpi('resolve_rate')}%',
          '${_fmt(d.kpi('tickets_assigned'))}${customer ? ' filed all-time' : ' assigned all-time'}'));
      tiles.add(_TileData(customer ? 'Avg. turnaround' : 'Avg. handling',
          Fa.stopwatch, _durationText(d.kpiOrNull('avg_resolve_minutes')),
          'Created to resolved'));
    }
    if (d.hasFlag('chat')) {
      tiles.add(_TileData('Chat messages', Fa.comments,
          _fmt(d.kpi('messages_total')),
          '${d.kpi('messages_today')} today · ${_fmt(d.kpi('messages_30d'))} in 30d'));
      tiles.add(_TileData('Conversations', Fa.commentDots,
          _fmt(d.kpi('conversations')),
          self ? 'Threads you replied in' : 'Threads they replied in'));
    }
    if (d.hasFlag('task')) {
      tiles.add(_TileData('Open tasks', Fa.tasks, _fmt(d.kpi('tasks_open')),
          '${d.kpi('tasks_overdue')} overdue'));
      tiles.add(_TileData('Tasks done', Fa.clipboardCheck,
          _fmt(d.kpi('tasks_done')), 'Completed'));
    }
    final streak = d.kpi('streak_days');
    final lastActive = d.kpiText('last_active');
    tiles.add(_TileData(
      'Active streak',
      Fa.fire,
      streak > 0 ? '$streak${streak == 1 ? ' day' : ' days'}' : '—',
      streak > 0
          ? 'Days in a row'
          : (lastActive.isNotEmpty
              ? 'Last active ${_dateText(lastActive)}'
              : 'No activity yet'),
    ));
    final busiest = d.kpi('busiest_count');
    tiles.add(_TileData(
      'Busiest day',
      Fa.chartBar,
      busiest > 0 ? _fmt(busiest) : '—',
      busiest > 0
          ? '${d.kpiText('busiest_label')} · tickets, chats & actions'
          : 'Last 14 days',
    ));
    tiles.add(_TileData('Actions logged', Fa.bolt, _fmt(d.kpi('actions_total')),
        '${d.kpi('actions_today')} today · ${_fmt(d.kpi('actions_30d'))} in 30d'));

    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 10));
      if (i + 1 >= tiles.length) {
        rows.add(_Tile(data: tiles[i], p: p));
      } else {
        rows.add(IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: _Tile(data: tiles[i], p: p)),
            const SizedBox(width: 10),
            Expanded(child: _Tile(data: tiles[i + 1], p: p)),
          ]),
        ));
      }
    }
    return Column(children: rows);
  }

  Widget _trendCard(ProfileStats d, _Pal p, bool self) {
    final labels = d.seriesLabels();
    final sets = <_Series>[
      if (d.seriesValues('resolved') case final v?) _Series('Resolved', v, _kBrand),
      if (d.seriesValues('tickets') case final v?) _Series('Assigned', v, _kInfo),
      if (d.seriesValues('messages') case final v?)
        _Series('Chat messages', v, _kLive),
      if (d.seriesValues('actions') case final v?) _Series('Actions', v, _kMuted),
    ];
    return _Card(
      p: p,
      icon: Fa.waveSquare,
      title: self ? 'My activity' : 'Activity',
      sub: 'Last 14 days',
      child: SizedBox(
        height: 180,
        child: _TrendChart(labels: labels, sets: sets, p: p),
      ),
    );
  }

  List<Widget> _statusCard(ProfileStats d, _Pal p, bool self) {
    final rows = d.chartCounts('ticketStatus');
    final total = rows.values.fold<int>(0, (a, b) => a + b);
    if (!d.hasFlag('ticket') || total == 0) return const [];
    final keys = rows.keys.toList();
    return [
      _Card(
        p: p,
        icon: Fa.ticketAlt,
        title: self ? 'My tickets' : 'Tickets',
        sub: '${_fmt(total)} total',
        child: LayoutBuilder(builder: (context, c) {
          final dw = c.maxWidth * 0.46;
          return Row(children: [
            SizedBox(
              width: dw,
              height: 92,
              child: _Donut(
                values: [for (final k in keys) rows[k]!],
                colors: [for (final k in keys) _kStatusColors[k] ?? _kMuted],
                labels: [for (final k in keys) _titleCase(k)],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < keys.length; i++) ...[
                    if (i > 0) const SizedBox(height: 7),
                    Row(children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: _kStatusColors[keys[i]] ?? _kMuted,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_titleCase(keys[i]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: p.text, fontSize: 12)),
                      ),
                      Text(
                        '${_fmt(rows[keys[i]]!)} · ${_pct(rows[keys[i]]!, total)}%',
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 12,
                            fontWeight: FontWeight.w700),
                      ),
                    ]),
                  ],
                ],
              ),
            ),
          ]);
        }),
      ),
    ];
  }

  List<Widget> _priorityCard(ProfileStats d, _Pal p) {
    final rows = d.chartCounts('ticketPriority');
    final total = rows.values.fold<int>(0, (a, b) => a + b);
    if (!d.hasFlag('ticket') || total == 0) return const [];
    final order = [
      for (final k in const ['urgent', 'high', 'medium', 'low'])
        if (rows.containsKey(k)) k,
    ];
    return [
      _Card(
        p: p,
        icon: Fa.flag,
        title: 'By priority',
        child: Column(children: [
          for (var i = 0; i < order.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _PriorityBar(
              label: _titleCase(order[i]),
              value: rows[order[i]]!,
              pct: _pct(rows[order[i]]!, total),
              color: _kPriorityColors[order[i]] ?? _kMuted,
              p: p,
            ),
          ],
        ]),
      ),
    ];
  }
}

class _TileData {
  const _TileData(this.label, this.icon, this.value, this.sub);
  final String label;
  final IconData icon;
  final String value;
  final String sub;
}

class _Series {
  const _Series(this.label, this.values, this.color);
  final String label;
  final List<int> values;
  final Color color;
}

class _Tile extends StatelessWidget {
  const _Tile({required this.data, required this.p});
  final _TileData data;
  final _Pal p;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(data.icon, size: 10, color: _kMuted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(data.label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: _kMuted,
                      fontSize: 10.2,
                      letterSpacing: 0.72,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(data.value,
              style: TextStyle(
                  color: p.ink,
                  fontSize: 23.2,
                  height: 1.1,
                  fontWeight: FontWeight.w800)),
          if (data.sub.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(data.sub,
                style: TextStyle(color: p.sub, fontSize: 11.2, height: 1.3)),
          ],
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.p,
    required this.icon,
    required this.title,
    required this.child,
    this.sub,
  });
  final _Pal p;
  final IconData icon;
  final String title;
  final String? sub;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 13, color: _kBrand),
            const SizedBox(width: 7),
            Expanded(
              child: Text(title,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 13.1,
                      fontWeight: FontWeight.w700)),
            ),
            if (sub != null && sub!.isNotEmpty)
              Text(sub!.toUpperCase(),
                  style: const TextStyle(
                      color: _kMuted,
                      fontSize: 10.6,
                      letterSpacing: 0.64,
                      fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.labels, required this.sets, required this.p});
  final List<String> labels;
  final List<_Series> sets;
  final _Pal p;

  static const _tick = TextStyle(color: _kMuted, fontSize: 9);

  @override
  Widget build(BuildContext context) {
    final n = labels.length;
    var peak = 0;
    for (final s in sets) {
      for (final v in s.values) {
        if (v > peak) peak = v;
      }
    }
    final step = _niceStep(peak);
    final maxY = peak == 0 ? step : (peak / step).ceil() * step;
    final every = n > 7 ? (n / 7).ceil() : 1;
    final drawn = sets.reversed.toList();
    return Column(children: [
      Expanded(
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: math.max(1, n - 1).toDouble(),
            minY: 0,
            maxY: maxY.toDouble(),
            borderData: FlBorderData(show: false),
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: step.toDouble(),
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: p.grid, strokeWidth: 1),
            ),
            titlesData: FlTitlesData(
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: step.toDouble(),
                  reservedSize: 26,
                  getTitlesWidget: (v, meta) => SideTitleWidget(
                    meta: meta,
                    space: 5,
                    child: Text(_fmt(v.round()), style: _tick),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: 1,
                  reservedSize: 18,
                  getTitlesWidget: (v, meta) {
                    final i = v.round();
                    if ((v - i).abs() > 0.001 ||
                        i < 0 ||
                        i >= n ||
                        i % every != 0) {
                      return const SizedBox.shrink();
                    }
                    return SideTitleWidget(
                      meta: meta,
                      space: 4,
                      child: Text(labels[i], style: _tick),
                    );
                  },
                ),
              ),
            ),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                tooltipBorderRadius: BorderRadius.circular(8),
                tooltipPadding: const EdgeInsets.all(10),
                getTooltipColor: (_) => _kInk,
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                getTooltipItems: (spots) => [
                  for (var k = 0; k < spots.length; k++)
                    LineTooltipItem(
                      '${k == 0 ? '${_labelAt(spots[k].x)}\n' : ''}'
                      '${drawn[spots[k].barIndex].label}: ${_fmt(spots[k].y.round())}',
                      TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        shadows: [
                          Shadow(
                              color: drawn[spots[k].barIndex].color,
                              blurRadius: 0),
                        ],
                      ),
                    ),
                ],
              ),
              getTouchedSpotIndicator: (bar, idx) => [
                for (final _ in idx)
                  TouchedSpotIndicatorData(
                    FlLine(color: p.grid, strokeWidth: 1),
                    FlDotData(
                      getDotPainter: (spot, pct, b, i) => FlDotCirclePainter(
                        radius: 4,
                        color: b.color ?? _kMuted,
                        strokeWidth: 0,
                        strokeColor: Colors.transparent,
                      ),
                    ),
                  ),
              ],
            ),
            lineBarsData: [
              for (final s in drawn)
                LineChartBarData(
                  spots: [
                    for (var i = 0; i < n && i < s.values.length; i++)
                      FlSpot(i.toDouble(), s.values[i].toDouble()),
                  ],
                  isCurved: true,
                  curveSmoothness: 0.38,
                  preventCurveOverShooting: true,
                  color: s.color,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: s.color.withValues(alpha: 0x22 / 255),
                  ),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 6),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 10,
        runSpacing: 4,
        children: [
          for (final s in sets)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: s.color.withValues(alpha: 0x22 / 255),
                  border: Border.all(color: s.color, width: 1.6),
                ),
              ),
              const SizedBox(width: 4),
              Text(s.label,
                  style: TextStyle(color: p.sub, fontSize: 10, height: 1.2)),
            ]),
        ],
      ),
    ]);
  }

  String _labelAt(double x) {
    final i = x.round();
    return i >= 0 && i < labels.length ? labels[i] : '';
  }
}

class _Donut extends StatefulWidget {
  const _Donut({required this.values, required this.colors, required this.labels});
  final List<int> values;
  final List<Color> colors;
  final List<String> labels;

  @override
  State<_Donut> createState() => _DonutState();
}

class _DonutState extends State<_Donut> {
  int _touched = -1;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final size = math.min(c.maxWidth, c.maxHeight);
      final outer = size / 2 - 4;
      final inner = outer * 0.64;
      final shown = [
        for (var i = 0; i < widget.values.length; i++)
          if (widget.values[i] > 0) i,
      ];
      final hit = _touched >= 0 && _touched < shown.length ? shown[_touched] : -1;
      return Stack(alignment: Alignment.center, children: [
        PieChart(
          PieChartData(
            startDegreeOffset: -90,
            sectionsSpace: 0,
            centerSpaceRadius: inner,
            pieTouchData: PieTouchData(
              touchCallback: (e, r) {
                final idx = e.isInterestedForInteractions
                    ? (r?.touchedSection?.touchedSectionIndex ?? -1)
                    : -1;
                if (idx != _touched) setState(() => _touched = idx);
              },
            ),
            sections: [
              for (final i in shown)
                PieChartSectionData(
                  value: widget.values[i].toDouble(),
                  color: widget.colors[i],
                  radius: (outer - inner) + (hit == i ? 4 : 0),
                  showTitle: false,
                ),
            ],
          ),
        ),
        if (hit >= 0)
          IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: _kInk,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('${widget.labels[hit]}: ${_fmt(widget.values[hit])}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ),
          ),
      ]);
    });
  }
}

class _PriorityBar extends StatelessWidget {
  const _PriorityBar({
    required this.label,
    required this.value,
    required this.pct,
    required this.color,
    required this.p,
  });
  final String label;
  final int value;
  final int pct;
  final Color color;
  final _Pal p;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Row(children: [
        Expanded(
          child: Text(label, style: TextStyle(color: p.text, fontSize: 11.8)),
        ),
        Text('${_fmt(value)} · $pct%',
            style: TextStyle(
                color: p.ink, fontSize: 11.8, fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 7,
          color: p.track,
          alignment: Alignment.centerLeft,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: pct / 100),
            duration: const Duration(milliseconds: 400),
            curve: Curves.ease,
            builder: (_, f, _) => FractionallySizedBox(
              widthFactor: f.clamp(0, 1),
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.bg, required this.fg});
  final String text;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text.toUpperCase(),
          style: TextStyle(
              color: fg,
              fontSize: 10.6,
              height: 1.3,
              letterSpacing: 0.53,
              fontWeight: FontWeight.w700)),
    );
  }
}

class _Avatar extends StatefulWidget {
  const _Avatar({
    required this.url,
    required this.headers,
    required this.name,
    required this.online,
    required this.presenceTitle,
  });
  final String url;
  final Map<String, String> headers;
  final String name;
  final bool online;
  final String presenceTitle;

  @override
  State<_Avatar> createState() => _AvatarState();
}

class _AvatarState extends State<_Avatar> {
  bool _hover = false;
  bool _broken = false;

  @override
  void didUpdateWidget(covariant _Avatar old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _broken = false;
  }

  void _zoom() {
    showDialog<void>(
      context: context,
      barrierColor: const Color(0xD90B1B30),
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.of(ctx).pop(),
        child: Material(
          color: Colors.transparent,
          child: Stack(children: [
            Center(
              child: InteractiveViewer(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Image.network(
                    widget.url,
                    headers: widget.headers,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 18,
              right: 18,
              child: _CloseButton(onTap: () => Navigator.of(ctx).pop()),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasImg = widget.url.isNotEmpty && !_broken;
    final fallback = const Center(
      child: Icon(Fa.user, size: 30, color: Color(0x99FFFFFF)),
    );
    return MouseRegion(
      cursor: hasImg ? SystemMouseCursors.zoomIn : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: hasImg ? _zoom : null,
        child: SizedBox(
          width: 84,
          height: 84,
          child: Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0x1AFFFFFF),
                border: Border.all(color: const Color(0x38FFFFFF), width: 3),
              ),
              child: ClipOval(
                child: hasImg
                    ? Image.network(
                        widget.url,
                        headers: widget.headers,
                        fit: BoxFit.cover,
                        width: 78,
                        height: 78,
                        errorBuilder: (_, _, _) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted && !_broken) {
                              setState(() => _broken = true);
                            }
                          });
                          return fallback;
                        },
                      )
                    : fallback,
              ),
            ),
            Positioned(
              right: 4,
              bottom: 4,
              child: Tooltip(
                message: widget.presenceTitle,
                child: Container(
                  width: 19,
                  height: 19,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.online ? _kLive : _kMuted,
                    border:
                        Border.all(color: const Color(0xFF12304F), width: 3),
                  ),
                ),
              ),
            ),
            if (hasImg)
              Positioned(
                right: -2,
                top: -2,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _hover ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: AnimatedScale(
                      scale: _hover ? 1 : 0.7,
                      duration: const Duration(milliseconds: 180),
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: _kBrand,
                        ),
                        alignment: Alignment.center,
                        child: const Icon(Fa.expand,
                            size: 10, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _CloseButton extends StatefulWidget {
  const _CloseButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Close profile',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _hover ? Colors.white : const Color(0xEBFFFFFF),
            ),
            alignment: Alignment.center,
            child: const Icon(Fa.times, size: 14, color: Color(0xFF16375C)),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = _Pal(context);
    final fg = widget.primary ? Colors.white : p.ink;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          transform: Matrix4.translationValues(0, _hover ? -1 : 0, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: widget.primary ? _kBrand : p.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: widget.primary ? _kBrand : p.border),
            boxShadow: _hover
                ? const [
                    BoxShadow(
                        color: Color(0x1A0B1B30),
                        blurRadius: 16,
                        offset: Offset(0, 6)),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, size: 12.5, color: fg),
              const SizedBox(width: 7),
              Flexible(
                child: Text(widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: fg,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FooterLink extends StatefulWidget {
  const _FooterLink({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_FooterLink> createState() => _FooterLinkState();
}

class _FooterLinkState extends State<_FooterLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = _Pal(context);
    final color = _hover ? _kBrand : p.sub;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(widget.icon, size: 10.5, color: color),
            const SizedBox(width: 6),
            Text(widget.label,
                style: TextStyle(
                    color: color,
                    fontSize: 11.2,
                    fontWeight: FontWeight.w600,
                    decoration:
                        _hover ? TextDecoration.underline : TextDecoration.none,
                    decorationColor: color)),
          ]),
        ),
      ),
    );
  }
}

String _fmt(int n) {
  final neg = n < 0;
  final s = n.abs().toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return neg ? '-$out' : out.toString();
}

int _pct(int v, int total) => total == 0 ? 0 : (v / total * 100).round();

String _titleCase(String s) => s
    .replaceAll('_', ' ')
    .replaceAllMapped(RegExp(r'\b\w'), (m) => m[0]!.toUpperCase());

String _durationText(int? mins) {
  if (mins == null) return '—';
  final m = math.max(0, mins);
  if (m < 60) return '${m}m';
  final h = m ~/ 60;
  if (h < 24) return '${h}h ${m % 60}m';
  final d = h ~/ 24;
  if (d < 30) return '${d}d ${h % 24}h';
  return '${d ~/ 30}mo';
}

String _agoText(int sec) {
  final s = math.max(0, sec);
  if (s < 60) return 'just now';
  final m = s ~/ 60;
  if (m < 60) return '${m}m ago';
  final h = m ~/ 60;
  if (h < 24) return '${h}h ago';
  return '${h ~/ 24}d ago';
}

String _dateText(String ymd) {
  final d = DateTime.tryParse(ymd.replaceFirst(' ', 'T'));
  if (d == null) return ymd;
  return '${_kMonths[d.month - 1]} ${d.day}';
}

String _clock(DateTime t) {
  final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final mm = t.minute.toString().padLeft(2, '0');
  return '${h12.toString().padLeft(2, '0')}:$mm ${t.hour < 12 ? 'AM' : 'PM'}';
}

int _niceStep(int peak) {
  if (peak <= 0) return 1;
  var mag = 1;
  while (true) {
    for (final f in const [1, 2, 4, 5]) {
      final step = f * mag;
      if ((peak / step).ceil() <= 8) return step;
    }
    mag *= 10;
  }
}
