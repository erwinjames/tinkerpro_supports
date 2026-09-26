import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/activity_models.dart';
import '../services/activity_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';

const String activityMapTileKey = String.fromEnvironment('MAP_TILE_KEY');

typedef ActivityCountSink = void Function(int? count);

String activityErrorText(Object error) {
  var raw = error
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('HttpException: ', '')
      .trim();
  if (raw.startsWith('Non-JSON response')) {
    return 'The server did not return activity data. '
        'Your session may have expired — sign in again and retry.';
  }
  if (raw.isEmpty) return 'Could not reach the server.';
  if (raw.length > 180) raw = '${raw.substring(0, 180)}…';
  return raw;
}

const List<String> _months = [
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

String _two(int n) => n.toString().padLeft(2, '0');

String activityIsoDay(DateTime d) =>
    '${d.year}-${_two(d.month)}-${_two(d.day)}';

String activityLongWhen(String raw) {
  if (raw.trim().isEmpty) return '—';
  final dt = DateTime.tryParse(raw.trim().replaceFirst(' ', 'T'));
  if (dt == null) return raw;
  final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final suffix = dt.hour < 12 ? 'AM' : 'PM';
  return '${_months[dt.month - 1]} ${dt.day}, ${dt.year} · '
      '$hour:${_two(dt.minute)}:${_two(dt.second)} $suffix';
}

String activityShortWhen(String raw) {
  if (raw.isEmpty) return '—';
  final dt = DateTime.tryParse(raw.trim().replaceFirst(' ', 'T'));
  if (dt == null) return raw;
  final diff = DateTime.now().difference(dt);
  if (diff.isNegative) return 'now';
  if (diff.inSeconds < 60) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return activityIsoDay(dt);
}

String activityCoords(double lat, double lon) =>
    '${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}';

String activityMetres(int? value) {
  final m = value ?? 0;
  if (m <= 0) return '—';
  if (m >= 1000) return '${(m / 1000).toStringAsFixed(1)} km';
  return '$m m';
}

String activityDistance(double km) {
  if (km < 1) return '${(km * 1000).round()} m';
  return '${km.toStringAsFixed(km < 10 ? 2 : 1)} km';
}

String activitySourceLabel(String source) {
  switch (source) {
    case 'device':
      return 'Device fix';
    case 'ip':
      return 'IP estimate';
    default:
      return 'No coordinates';
  }
}

Color activitySourceColor(String source) {
  switch (source) {
    case 'device':
      return Brand.success;
    case 'ip':
      return Brand.info;
    default:
      return const Color(0xFF64748B);
  }
}

double _haversine(TracePoint a, TracePoint b) {
  const r = 6371.0;
  final dLat = (b.lat - a.lat) * math.pi / 180;
  final dLon = (b.lon - a.lon) * math.pi / 180;
  final la1 = a.lat * math.pi / 180;
  final la2 = b.lat * math.pi / 180;
  final h =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.sin(dLon / 2) * math.sin(dLon / 2) * math.cos(la1) * math.cos(la2);
  return 2 * r * math.asin(math.min(1, math.sqrt(h)));
}

double activityTrackDistance(List<TracePoint> track) {
  var total = 0.0;
  for (var i = 1; i < track.length; i++) {
    total += _haversine(track[i - 1], track[i]);
  }
  return total;
}

Future<void> openActivityMap(
  BuildContext context,
  double lat,
  double lon,
  String label,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final coords = '${lat.toStringAsFixed(6)},${lon.toStringAsFixed(6)}';
  final name = label.trim().isEmpty ? 'Activity' : label.trim();
  final geo = Uri.parse('geo:$coords?q=$coords(${Uri.encodeComponent(name)})');
  final web = Uri.parse('https://www.google.com/maps?q=$coords');
  try {
    if (await launchUrl(geo, mode: LaunchMode.externalApplication)) return;
  } catch (_) {}
  try {
    if (await launchUrl(web, mode: LaunchMode.externalApplication)) return;
  } catch (_) {}
  messenger?.showSnackBar(
    const SnackBar(content: Text('No map app available.')),
  );
}

class ActivityFilterMenu extends StatelessWidget {
  const ActivityFilterMenu({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.labelOf,
  });

  final IconData icon;
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final String Function(String)? labelOf;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final active = value.isNotEmpty;
    return Material(
      color: active ? b.tint(b.signal, 0.1) : b.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Brand.radius),
        side: BorderSide(
          color: active ? b.signal.withValues(alpha: 0.45) : b.rule,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: PopupMenuButton<String>(
        tooltip: label,
        position: PopupMenuPosition.under,
        onSelected: onChanged,
        itemBuilder: (_) => <PopupMenuEntry<String>>[
          PopupMenuItem<String>(value: '', child: Text(label)),
          for (final o in options)
            PopupMenuItem<String>(
              value: o,
              child: Text(
                labelOf?.call(o) ?? o,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        child: SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(icon, size: 18, color: active ? b.signalInk : b.paperDim),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    active ? (labelOf?.call(value) ?? value) : label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelLarge?.copyWith(
                      color: active ? b.signalInk : b.paper,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                Icon(Icons.expand_more_rounded, size: 18, color: b.paperDim),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ActivityKindTile extends StatelessWidget {
  const ActivityKindTile({
    super.key,
    required this.icon,
    required this.color,
    this.size = 36,
    this.animate = false,
  });

  final IconData icon;
  final Color color;
  final double size;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final tile = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: IconTile(
        icon: icon,
        color: color,
        size: size,
        iconSize: size * 0.5,
      ),
    );
    if (!animate || reduce) return tile;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.72, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutBack,
      builder: (_, v, child) => Transform.scale(scale: v, child: child),
      child: tile,
    );
  }
}

class ActivityRise extends StatefulWidget {
  const ActivityRise({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<ActivityRise> createState() => _ActivityRiseState();
}

class _ActivityRiseState extends State<ActivityRise>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOut,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.07),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));
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
    final steps = widget.index < 0 ? 0 : (widget.index > 7 ? 7 : widget.index);
    if (steps == 0) {
      _c.forward();
      return;
    }
    Future<void>.delayed(Duration(milliseconds: 45 * steps), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _fade,
    child: SlideTransition(position: _slide, child: widget.child),
  );
}

class ActivityPillRow extends StatelessWidget {
  const ActivityPillRow({super.key, required this.label, required this.pill});

  final String label;
  final Widget pill;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: b.rule)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            SizedBox(width: 120, child: Text(label, style: text.bodySmall)),
            const SizedBox(width: 12),
            Expanded(
              child: Align(alignment: Alignment.centerLeft, child: pill),
            ),
          ],
        ),
      ),
    );
  }
}

class ActivityMapPanel extends StatelessWidget {
  const ActivityMapPanel({
    super.key,
    required this.lat,
    required this.lon,
    this.caption = '',
  });

  final double lat;
  final double lon;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    return AppCard(
      radius: Brand.radiusLg,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ActivityMiniMap(lat: lat, lon: lon),
          const SizedBox(height: 10),
          Text(activityCoords(lat, lon), style: text.bodyMedium),
          if (caption.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(caption, style: text.bodySmall),
          ],
          const SizedBox(height: 2),
          Text(
            activityMapTileKey.trim().isEmpty
                ? 'Tiles © Esri'
                : '© OpenStreetMap contributors · CARTO',
            style: text.labelSmall?.copyWith(color: b.paperDim),
          ),
          const SizedBox(height: 10),
          SignalButton(
            label: 'View on map',
            icon: Icons.map_rounded,
            onPressed: () => openActivityMap(context, lat, lon, caption),
          ),
        ],
      ),
    );
  }
}

class ActivityMiniMap extends StatelessWidget {
  const ActivityMiniMap({super.key, required this.lat, required this.lon});

  final double lat;
  final double lon;

  static const int _zoom = 14;
  static const double _tile = 256;
  static const double _height = 150;

  String _url(int x, int y, bool dark) {
    final key = activityMapTileKey.trim();
    if (key.isNotEmpty) {
      final style = dark ? 'dark_all' : 'light_all';
      return 'https://a.basemaps.cartocdn.com/$style/$_zoom/$x/$y.png'
          '?api_key=${Uri.encodeComponent(key)}';
    }
    return 'https://server.arcgisonline.com/ArcGIS/rest/services/'
        'World_Street_Map/MapServer/tile/$_zoom/$y/$x';
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return ClipRRect(
      borderRadius: BorderRadius.circular(Brand.radius),
      child: Container(
        height: _height,
        decoration: BoxDecoration(
          color: b.surfaceHi,
          border: Border.all(color: b.rule),
          borderRadius: BorderRadius.circular(Brand.radius),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 320.0;
            final span = math.pow(2, _zoom).toDouble();
            final world = span * _tile;
            final px = (lon + 180) / 360 * world;
            final rad = lat * math.pi / 180;
            final py =
                (1 - math.log(math.tan(rad) + 1 / math.cos(rad)) / math.pi) /
                2 *
                world;
            final left = px - width / 2;
            final top = py - _height / 2;
            final x0 = (left / _tile).floor();
            final x1 = ((left + width) / _tile).floor();
            final y0 = (top / _tile).floor();
            final y1 = ((top + _height) / _tile).floor();
            final count = span.toInt();
            final tiles = <Widget>[];
            for (var tx = x0; tx <= x1; tx++) {
              for (var ty = y0; ty <= y1; ty++) {
                if (ty < 0 || ty >= count) continue;
                final wrapped = ((tx % count) + count) % count;
                tiles.add(
                  Positioned(
                    left: tx * _tile - left,
                    top: ty * _tile - top,
                    width: _tile,
                    height: _tile,
                    child: Image.network(
                      _url(wrapped, ty, b.isDark),
                      fit: BoxFit.fill,
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                );
              }
            }
            return Stack(
              fit: StackFit.expand,
              children: [
                ...tiles,
                Center(
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Brand.danger,
                      shape: BoxShape.circle,
                      border: Border.all(color: Brand.white, width: 3),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class ActivityTraceStop extends StatelessWidget {
  const ActivityTraceStop({
    super.key,
    required this.point,
    required this.selected,
    required this.isLast,
  });

  final TracePoint point;
  final bool selected;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final color = activitySourceColor(point.source);
    final meta = <String>[
      activitySourceLabel(point.source),
      if (point.accuracyM != null) '±${activityMetres(point.accuracyM)}',
      if (point.events > 1) '${point.events} events',
    ].join(' · ');
    return InkWell(
      onTap: () => openActivityMap(context, point.lat, point.lon, point.action),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        decoration: BoxDecoration(
          border: isLast ? null : Border(bottom: BorderSide(color: b.rule)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                color: selected ? color : color.withValues(alpha: 0.45),
                shape: BoxShape.circle,
                border: Border.all(color: color),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    point.action.isEmpty ? 'Activity' : point.action,
                    style: text.bodyMedium?.copyWith(
                      color: b.paper,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${activityLongWhen(point.createdAt)} · $meta',
                    style: text.bodySmall,
                    maxLines: 2,
                  ),
                  if (point.address.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      point.address,
                      style: text.bodySmall?.copyWith(color: b.paperDim),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    activityCoords(point.lat, point.lon),
                    style: text.labelSmall?.copyWith(color: b.paperDim),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.open_in_new_rounded, size: 16, color: b.signal),
          ],
        ),
      ),
    );
  }
}

class ActivityFeedView<T> extends StatefulWidget {
  const ActivityFeedView({
    super.key,
    required this.loading,
    required this.rows,
    required this.itemBuilder,
    required this.onRefresh,
    required this.emptyLabel,
    required this.emptyHint,
    this.error,
    this.emptyIcon = Icons.manage_search_rounded,
    this.pageSize = 25,
    this.footerNoun = 'entries',
    this.resetToken,
  });

  final bool loading;
  final String? error;
  final List<T> rows;
  final Widget Function(BuildContext context, T row, int index) itemBuilder;
  final Future<void> Function() onRefresh;
  final String emptyLabel;
  final String emptyHint;
  final IconData emptyIcon;
  final int pageSize;
  final String footerNoun;
  final Object? resetToken;

  @override
  State<ActivityFeedView<T>> createState() => _ActivityFeedViewState<T>();
}

class _ActivityFeedViewState<T> extends State<ActivityFeedView<T>> {
  final _scroll = ScrollController();
  late int _limit = widget.pageSize;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant ActivityFeedView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.resetToken != oldWidget.resetToken) {
      _limit = widget.pageSize;
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels < pos.maxScrollExtent - 420) return;
    _more();
  }

  void _more() {
    if (_limit >= widget.rows.length) return;
    setState(() => _limit += widget.pageSize);
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final error = widget.error;

    Widget body;
    if (widget.loading) {
      body = const SkeletonList(count: 7);
    } else if (error != null) {
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 48),
          EmptyState(
            label: 'Could not load',
            hint: error,
            icon: Icons.wifi_off_rounded,
            action: SignalButton(
              label: 'Retry',
              icon: Icons.refresh_rounded,
              onPressed: widget.onRefresh,
            ),
          ),
        ],
      );
    } else if (widget.rows.isEmpty) {
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 48),
          EmptyState(
            label: widget.emptyLabel,
            hint: widget.emptyHint,
            icon: widget.emptyIcon,
          ),
        ],
      );
    } else {
      final visible = widget.rows.length < _limit ? widget.rows.length : _limit;
      body = ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: visible + 1,
        itemBuilder: (context, i) {
          if (i < visible) {
            return widget.itemBuilder(context, widget.rows[i], i);
          }
          if (visible < widget.rows.length) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
              child: GhostButton(label: 'Load more', onPressed: _more),
            );
          }
          return Padding(
            padding: const EdgeInsets.fromLTRB(2, 10, 0, 20),
            child: Text(
              'End of the list · ${widget.rows.length} ${widget.footerNoun}',
              style: text.bodySmall,
            ),
          );
        },
      );
    }

    return RefreshIndicator(
      color: b.signal,
      backgroundColor: b.surface,
      onRefresh: widget.onRefresh,
      child: body,
    );
  }
}

class ActivityDetailField {
  const ActivityDetailField(this.label, this.value, {this.mono = false});

  final String label;
  final String value;
  final bool mono;
}

class ActivityDetailGroup {
  const ActivityDetailGroup(this.title, this.fields);

  final String title;
  final List<ActivityDetailField> fields;
}

class ActivityDetailSheet extends StatefulWidget {
  const ActivityDetailSheet({
    super.key,
    required this.service,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.groups,
    this.pills = const <Widget>[],
    this.note = '',
    this.noteLabel = 'Details',
    this.traceQuery,
    this.heartbeatQuery,
    this.lat,
    this.lon,
    this.coordSource = 'none',
    this.mapCaption = '',
  });

  final ActivityService service;
  final String eyebrow;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<ActivityDetailGroup> groups;
  final List<Widget> pills;
  final String note;
  final String noteLabel;
  final Map<String, String>? traceQuery;
  final Map<String, String>? heartbeatQuery;
  final double? lat;
  final double? lon;
  final String coordSource;
  final String mapCaption;

  @override
  State<ActivityDetailSheet> createState() => _ActivityDetailSheetState();
}

class _ActivityDetailSheetState extends State<ActivityDetailSheet> {
  ActivityTrace? _trace;
  TracePresence? _presence;
  Timer? _live;
  bool _loading = false;
  bool _failed = false;

  bool get _privileged =>
      widget.service.isSuperAdmin && widget.traceQuery != null;

  @override
  void initState() {
    super.initState();
    if (!_privileged) return;
    _loading = true;
    _loadTrace();
    _startLive();
  }

  void _startLive() {
    if (_live != null || _beatQuery == null) return;
    _live = Timer.periodic(const Duration(seconds: 15), (_) => _poll());
  }

  Map<String, String>? get _beatQuery =>
      widget.heartbeatQuery ?? _trace?.heartbeatQuery;

  @override
  void dispose() {
    _live?.cancel();
    super.dispose();
  }

  Future<void> _loadTrace() async {
    ActivityTrace? trace;
    try {
      trace = await widget.service.traceFor(widget.traceQuery!);
    } catch (_) {
      trace = null;
    }
    if (!mounted) return;
    setState(() {
      _trace = trace;
      _presence = trace?.user ?? _presence;
      _loading = false;
      _failed = trace == null;
    });
    _startLive();
  }

  Future<void> _poll() async {
    final query = _beatQuery;
    if (query == null) return;
    final beat = await widget.service.heartbeatFor(query);
    if (!mounted || beat == null) return;
    setState(() => _presence = beat.user ?? _presence);
    final trace = _trace;
    if (trace != null && beat.latestId > trace.latestId) _loadTrace();
  }

  @override
  Widget build(BuildContext context) {
    final trace = _trace;
    final point = trace?.selected;
    final lat = point?.lat ?? widget.lat;
    final lon = point?.lon ?? widget.lon;
    final source = point?.source ?? widget.coordSource;

    return FractionallySizedBox(
      heightFactor: 0.92,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          _header(context),
          const SizedBox(height: 18),
          for (final group in widget.groups) ...[
            SectionHeader(title: group.title),
            AppCard(
              radius: Brand.radiusLg,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  for (final f in group.fields)
                    StationDataRow(
                      label: f.label,
                      value: f.value.isEmpty ? '—' : f.value,
                      valueStyle: f.mono
                          ? Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: context.brand.paper,
                              fontWeight: FontWeight.w500,
                              fontFamily: 'monospace',
                            )
                          : null,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],
          if (lat != null && lon != null) ...[
            SectionHeader(
              title: 'Map',
              trailing: StatusPill(
                label: activitySourceLabel(source),
                color: activitySourceColor(source),
                dot: true,
              ),
            ),
            ActivityMapPanel(
              lat: lat,
              lon: lon,
              caption: point?.address.isNotEmpty == true
                  ? point!.address
                  : widget.mapCaption,
            ),
            const SizedBox(height: 18),
          ],
          if (widget.note.isNotEmpty) ...[
            SectionHeader(title: widget.noteLabel),
            GlassPanel(
              accent: widget.color,
              child: SelectableText(
                widget.note,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
            ),
            const SizedBox(height: 18),
          ],
          if (_privileged) _tracePane(context),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final presence = _presence;
    final trace = _trace;
    return GlassPanel(
      accent: widget.color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                widget.eyebrow,
                style: text.labelMedium?.copyWith(
                  color: b.signal,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const Spacer(),
              if (_privileged && !_loading)
                StatusPill(
                  label: trace == null || !trace.live
                      ? 'Static record'
                      : presence == null
                      ? 'Live · watching'
                      : (presence.isOnline
                            ? 'Live · online now'
                            : 'Offline · last trace'),
                  color: presence?.isOnline == true
                      ? Brand.success
                      : (trace?.live == true ? Brand.info : b.paperDim),
                  dot: true,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ActivityKindTile(
                icon: widget.icon,
                color: widget.color,
                size: 46,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: text.titleLarge?.copyWith(color: b.paper),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle,
                        style: text.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (widget.pills.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: widget.pills),
          ],
          if (presence != null && presence.lastSeen.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Last seen ${activityLongWhen(presence.lastSeen)}',
              style: text.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  Widget _tracePane(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (_loading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Trace'),
          AppCard(
            radius: Brand.radiusLg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Skeleton(width: 170, height: 14),
                SizedBox(height: 12),
                Skeleton(width: 230, height: 11),
                SizedBox(height: 10),
                Skeleton(width: 190, height: 11),
              ],
            ),
          ),
        ],
      );
    }
    final trace = _trace;
    if (trace == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Trace'),
          AppCard(
            radius: Brand.radiusLg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _failed
                      ? 'Could not reach the trace service.'
                      : 'No trace available for this entry.',
                  style: text.bodySmall,
                ),
                const SizedBox(height: 12),
                GhostButton(
                  label: 'Retry',
                  icon: Icons.refresh_rounded,
                  onPressed: () {
                    setState(() => _loading = true);
                    _loadTrace();
                  },
                ),
              ],
            ),
          ),
        ],
      );
    }

    final stops = trace.track;
    final recent = stops.reversed.take(12).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final section in trace.sections) ...[
          SectionHeader(title: section.title),
          AppCard(
            radius: Brand.radiusLg,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                for (final f in section.fields)
                  if (f.tag.isNotEmpty)
                    ActivityPillRow(
                      label: f.label,
                      pill: StatusPill(
                        label: activitySourceLabel(f.tag),
                        color: activitySourceColor(f.tag),
                        dot: true,
                      ),
                    )
                  else
                    StationDataRow(
                      label: f.label,
                      value: f.value.isEmpty ? '—' : f.value,
                      valueStyle: f.mono
                          ? Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: context.brand.paper,
                              fontWeight: FontWeight.w500,
                              fontFamily: 'monospace',
                            )
                          : null,
                    ),
              ],
            ),
          ),
          const SizedBox(height: 18),
        ],
        const SectionHeader(title: 'Trace'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            GlowBadge(
              label: '${stops.length} located stops',
              color: Brand.info,
              icon: Icons.place_outlined,
            ),
            GlowBadge(
              label: '${trace.deviceFixes} device fixes',
              color: Brand.success,
              icon: Icons.my_location_rounded,
            ),
            GlowBadge(
              label: 'Path ${activityDistance(activityTrackDistance(stops))}',
              color: Brand.signal,
              icon: Icons.route_rounded,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (stops.isEmpty)
          AppCard(
            radius: Brand.radiusLg,
            child: Text(
              trace.emptyNote.isEmpty
                  ? 'No coordinates recorded for this entry.'
                  : trace.emptyNote,
              style: text.bodySmall,
            ),
          )
        else ...[
          AppCard(
            radius: Brand.radiusLg,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                for (final p in recent)
                  ActivityTraceStop(
                    point: p,
                    selected: p.ids.any(trace.selectedIds.contains),
                    isLast: identical(p, recent.last),
                  ),
              ],
            ),
          ),
          if (stops.length > recent.length) ...[
            const SizedBox(height: 8),
            Text(
              'Showing the newest ${recent.length} of ${stops.length} stops.',
              style: text.bodySmall,
            ),
          ],
          if (trace.trackNote.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(trace.trackNote, style: text.bodySmall),
          ],
        ],
      ],
    );
  }
}
