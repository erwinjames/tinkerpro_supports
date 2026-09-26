import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' hide Path;
import 'package:url_launcher/url_launcher.dart';

import '../../api_client.dart';
import '../../theme.dart';
import '../../widgets/tp_loader.dart';

const _kDetailPath = 'utils/models/get_log_detail.php';
const _kGreen = Color(0xFF16A34A);
const _kRouteEndpoint = 'https://router.project-osrm.org/route/v1/driving/';
const _kRouteMinKm = 0.03;
const _kRouteMaxKm = 600.0;
const _kRouteWorkers = 3;
const _kStackBelow = 900.0;

final Map<String, _Route?> _routeCache = {};

Future<void> showActivityTraceDialog(
  BuildContext context, {
  required ApiClient api,
  required String tileKey,
  required String fallbackTitle,
  required Map<String, String> query,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0x800F172A),
    builder: (_) => ActivityTraceDialog(
      api: api,
      tileKey: tileKey,
      fallbackTitle: fallbackTitle,
      query: query,
    ),
  );
}

class _Route {
  const _Route(this.line, this.km);
  final List<LatLng> line;
  final double km;
}

class _Pt {
  _Pt(this.raw)
    : lat = _num(raw['lat']),
      lon = _num(raw['lon']),
      source = (raw['source'] ?? '').toString(),
      accuracy = _num(raw['accuracy_m']),
      events = _num(raw['events']).toInt(),
      ids = raw['ids'] is List
          ? [for (final i in raw['ids'] as List) _num(i).toInt()]
          : [_num(raw['id']).toInt()];

  final Map<String, dynamic> raw;
  final double lat;
  final double lon;
  final String source;
  final double accuracy;
  final int events;
  final List<int> ids;

  LatLng get ll => LatLng(lat, lon);
  String s(String k) => (raw[k] ?? '').toString();
}

class _Seg {
  _Seg(this.a, this.b)
    : line = [a.ll, b.ll],
      routable =
          _haversine(a, b) >= _kRouteMinKm && _haversine(a, b) <= _kRouteMaxKm;
  final _Pt a;
  final _Pt b;
  List<LatLng> line;
  bool routed = false;
  final bool routable;
  double roadKm = 0;
}

class _TileSource {
  const _TileSource(this.url, this.subdomains, this.maxZoom, this.attribution);
  final String url;
  final List<String> subdomains;
  final int maxZoom;
  final List<(String, String?)> attribution;
}

const _osmAttrib = [
  ('© ', null),
  ('OpenStreetMap', 'https://www.openstreetmap.org/copyright'),
  (' contributors', null),
];
const _cartoAttrib = [
  ..._osmAttrib,
  (' © ', null),
  ('CARTO', 'https://carto.com/attributions'),
];

List<_TileSource> _tileSources(String key) {
  final k = key.trim();
  return [
    if (k.isNotEmpty)
      _TileSource(
        'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png?api_key=${Uri.encodeQueryComponent(k)}',
        const ['a', 'b', 'c', 'd'],
        20,
        _cartoAttrib,
      ),
    const _TileSource(
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}',
      [],
      19,
      [('Tiles © ', null), ('Esri', 'https://www.esri.com/')],
    ),
    const _TileSource(
      'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
      ['a', 'b', 'c', 'd'],
      20,
      _cartoAttrib,
    ),
  ];
}

double _num(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}') ?? 0;
}

double _haversine(_Pt a, _Pt b) {
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

String _fmtDistance(double km) {
  if (km < 1) return '${(km * 1000).round()} m';
  return '${km.toStringAsFixed(km < 10 ? 2 : 1)} km';
}

String _fmtAccuracy(double m) {
  if (m == 0) return '';
  return m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '${m.round()} m';
}

const _months = [
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

String _fmtDate(dynamic v) {
  final s = (v ?? '').toString();
  if (s.isEmpty) return '—';
  final d = DateTime.tryParse(s.replaceFirst(' ', 'T'));
  if (d == null) return s;
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final mm = d.minute.toString().padLeft(2, '0');
  final ss = d.second.toString().padLeft(2, '0');
  return '${_months[d.month - 1]} ${d.day}, ${d.year}, $h:$mm:$ss ${d.hour < 12 ? 'AM' : 'PM'}';
}

class _Ld {
  _Ld(BuildContext context)
    : dark = Theme.of(context).brightness == Brightness.dark,
      b = context.brand;
  final bool dark;
  final BrandColors b;

  Color get card => dark ? b.surface : Colors.white;
  Color get side => dark ? b.surfaceHi : const Color(0xFFFAFAF9);
  Color get rule => dark ? b.rule : const Color(0xFFE2E8F0);
  Color get fieldRule => dark ? b.rule : const Color(0xFFEEF2F7);
  Color get ink => dark ? b.paper : const Color(0xFF0F172A);
  Color get muted => dark ? b.paperDim : const Color(0xFF64748B);
  Color get faint => const Color(0xFF94A3B8);
  Color get chipText => dark ? b.paperDim : const Color(0xFF475569);
  Color get box => dark ? b.surface : Colors.white;
  Color get mapBg => dark ? b.canvas : const Color(0xFFEEF2F7);
}

class ActivityTraceDialog extends StatefulWidget {
  const ActivityTraceDialog({
    super.key,
    required this.api,
    required this.tileKey,
    required this.fallbackTitle,
    required this.query,
  });

  final ApiClient api;
  final String tileKey;
  final String fallbackTitle;
  final Map<String, String> query;

  @override
  State<ActivityTraceDialog> createState() => _ActivityTraceDialogState();
}

class _ActivityTraceDialogState extends State<ActivityTraceDialog>
    with TickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();
  late final List<_TileSource> _sources = _tileSources(widget.tileKey);
  final MapController _map = MapController();
  final GlobalKey _popupKey = GlobalKey();

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _res;
  List<_Pt> _track = const [];
  List<int> _selected = const [];
  Map<String, dynamic>? _live;
  Map<String, dynamic>? _user;
  int _latestId = 0;
  List<_Seg> _segments = const [];
  int _gen = 0;
  int _tileIndex = 0;
  int _tileErrors = 0;
  int? _popup;
  int _mapVersion = 0;
  bool _mapReady = false;
  Timer? _timer;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _closed = true;
    _gen++;
    _timer?.cancel();
    _pulse.dispose();
    _map.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await widget.api.getPath(_kDetailPath, widget.query);
      if (!mounted) return;
      if (res['success'] != true) {
        setState(() {
          _loading = false;
          _error = (res['message'] ?? 'Could not load this entry.').toString();
        });
        return;
      }
      setState(() {
        _loading = false;
        _res = res;
        _live = res['live'] is Map
            ? Map<String, dynamic>.from(res['live'] as Map)
            : null;
        _user = res['user'] is Map
            ? Map<String, dynamic>.from(res['user'] as Map)
            : null;
        _latestId = _live == null ? 0 : _num(_live!['latest_id']).toInt();
        _mapVersion++;
        _mapReady = false;
        _applyTrack(res);
      });
      if (_track.isNotEmpty && _live != null) _startLive();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().contains('HTTP 403')
            ? 'Super admin clearance required to view the activity trace.'
            : 'Could not reach the trace service.';
      });
    }
  }

  void _applyTrack(Map<String, dynamic> res) {
    final raw = res['track'] is List ? res['track'] as List : const [];
    _track = [
      for (final p in raw)
        if (p is Map) _Pt(Map<String, dynamic>.from(p)),
    ];
    _selected = res['selected_ids'] is List
        ? [for (final i in res['selected_ids'] as List) _num(i).toInt()]
        : const [];
    _popup = null;
    _gen++;
    _segments = [
      for (var i = 1; i < _track.length; i++) _Seg(_track[i - 1], _track[i]),
    ];
    _routeSegments(_gen);
  }

  void _routeSegments(int gen) {
    final pending = _segments.where((s) => s.routable).toList();
    if (pending.isEmpty) return;
    var cursor = 0;
    Future<void> next() async {
      while (!_closed && gen == _gen && cursor < pending.length) {
        final seg = pending[cursor++];
        final result = await _fetchSegment(seg.a, seg.b);
        if (_closed || gen != _gen) return;
        if (result != null) {
          setState(() {
            seg.line = result.line;
            seg.roadKm = result.km;
            seg.routed = true;
          });
        }
      }
    }

    for (var w = 0; w < _kRouteWorkers; w++) {
      next();
    }
  }

  Future<_Route?> _fetchSegment(_Pt a, _Pt b) async {
    final key =
        '${a.lat.toStringAsFixed(5)},${a.lon.toStringAsFixed(5)}|${b.lat.toStringAsFixed(5)},${b.lon.toStringAsFixed(5)}';
    if (_routeCache.containsKey(key)) return _routeCache[key];
    final url =
        '$_kRouteEndpoint${a.lon.toStringAsFixed(6)},${a.lat.toStringAsFixed(6)};${b.lon.toStringAsFixed(6)},${b.lat.toStringAsFixed(6)}?overview=full&geometries=geojson&alternatives=false&steps=false';
    try {
      final r = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode < 200 || r.statusCode >= 300) return null;
      final data = jsonDecode(r.body);
      _Route? result;
      if (data is Map && data['code'] == 'Ok' && data['routes'] is List) {
        final routes = data['routes'] as List;
        final route = routes.isEmpty ? null : routes.first;
        final coords = route is Map && route['geometry'] is Map
            ? (route['geometry'] as Map)['coordinates']
            : null;
        if (coords is List && coords.length > 1) {
          result = _Route([
            for (final c in coords)
              if (c is List && c.length > 1) LatLng(_num(c[1]), _num(c[0])),
          ], _num(route is Map ? route['distance'] : 0) / 1000);
        }
      }
      _routeCache[key] = result;
      return result;
    } catch (_) {
      return null;
    }
  }

  void _startLive() {
    _timer?.cancel();
    if (_live == null) return;
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _pollLive());
  }

  Future<void> _pollLive() async {
    final live = _live;
    if (_closed || live == null) {
      _timer?.cancel();
      return;
    }
    final kind = (live['kind'] ?? '').toString();
    final q = <String, String>{'live': '1', 'live_kind': kind};
    if (kind == 'download') {
      q['collection_id'] = (live['collection_id'] ?? '').toString();
    } else {
      q['user_id'] = (live['user_id'] ?? '').toString();
    }
    try {
      final res = await widget.api.getPath(_kDetailPath, q);
      if (!mounted || res['success'] != true) return;
      setState(() {
        _user = res['user'] is Map
            ? Map<String, dynamic>.from(res['user'] as Map)
            : null;
      });
      final latest = _num(res['latest_id']).toInt();
      if (latest <= _latestId) return;
      _latestId = latest;
      await _refreshTrack();
    } catch (_) {}
  }

  Future<void> _refreshTrack() async {
    try {
      final res = await widget.api.getPath(_kDetailPath, widget.query);
      if (!mounted || res['success'] != true) return;
      setState(() {
        if (res['live'] is Map) {
          final id = _num((res['live'] as Map)['latest_id']).toInt();
          if (id != 0) _latestId = id;
        }
        _applyTrack(res);
      });
    } catch (_) {}
  }

  void _onTileError() {
    _tileErrors++;
    if (_tileErrors < 4 || _tileIndex + 1 >= _sources.length) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _tileErrors < 4) return;
      setState(() {
        _tileIndex++;
        _tileErrors = 0;
      });
    });
  }

  double get _pathKm {
    var total = 0.0;
    for (final s in _segments) {
      total += s.routed && s.roadKm > 0 ? s.roadKm : _haversine(s.a, s.b);
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final ld = _Ld(context);
    final screen = MediaQuery.sizeOf(context);
    const inset = 24.0;
    final w = math.min(1180.0, screen.width - inset * 2).clamp(280.0, 1180.0);
    final maxH = math.max(200.0, screen.height - inset * 2);
    final stacked = screen.width <= _kStackBelow;
    final ready = !_loading && _error == null && _res != null;
    final fixedH = ready ? maxH : null;

    Widget body;
    if (_loading) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const TpLoader(size: 44),
            const SizedBox(height: 12),
            Text(
              'Loading trace…',
              style: TextStyle(fontSize: 13, color: ld.muted),
            ),
          ],
        ),
      );
    } else if (!ready) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: Text(
          _error ?? 'Could not load this entry.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: ld.muted),
        ),
      );
    } else if (stacked) {
      body = SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: ld.side,
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
              child: _side(ld),
            ),
            Container(height: 1, color: ld.rule),
            SizedBox(height: 340, child: _mapPane(ld)),
          ],
        ),
      );
    } else {
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: math.min(340.0, w / 2),
            decoration: BoxDecoration(
              color: ld.side,
              border: Border(right: BorderSide(color: ld.rule)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
              child: _side(ld),
            ),
          ),
          Expanded(child: _mapPane(ld)),
        ],
      );
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          insetPadding: const EdgeInsets.all(inset),
          backgroundColor: ld.card,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: w,
            height: fixedH,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxH),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(ld),
                  if (fixedH != null) Expanded(child: body) else body,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(_Ld ld) {
    final res = _res;
    final title = res == null
        ? widget.fallbackTitle
        : (res['title'] ?? 'Entry').toString();
    final sub = res == null
        ? ''
        : ((res['subtitle'] ?? '').toString().isEmpty
              ? ''
              : _fmtDate(res['subtitle']));
    final eyebrow = res == null
        ? 'Activity trace'
        : (res['eyebrow'] ?? 'Activity trace').toString();
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 16, 14, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kGreen.withValues(alpha: 0.08), ld.card],
          stops: const [0, 0.68],
        ),
        border: Border(bottom: BorderSide(color: ld.rule)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Icon(Icons.route, size: 13, color: _kGreen),
                    Text(
                      eyebrow.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: _kGreen,
                        letterSpacing: 1.2,
                      ),
                    ),
                    _livePill(),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: ld.ink,
                    letterSpacing: -0.2,
                  ),
                ),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: ld.muted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.close, size: 20, color: ld.faint),
          ),
        ],
      ),
    );
  }

  Widget _livePill() {
    String label;
    bool on;
    String tip = '';
    if (_res == null) {
      label = 'Offline';
      on = false;
    } else if (_live == null) {
      label = 'Static record';
      on = false;
    } else if (_user == null) {
      label = 'Live · watching';
      on = true;
      tip = 'Polling for new activity every 15 seconds';
    } else {
      on = _user!['is_online'] == true;
      label = on ? 'Live · online now' : 'Offline · last trace';
      final seen = (_user!['last_seen'] ?? '').toString();
      tip = seen.isEmpty ? '' : 'Last seen ${_fmtDate(seen)}';
    }
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: on ? const Color(0xFFECFDF5) : const Color(0xFFF1F5F9),
        border: Border.all(
          color: on ? const Color(0xFFA7F3D0) : const Color(0xFFE2E8F0),
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          on
              ? _pulseDot(7, const Color(0xFF10B981))
              : Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: Color(0xFF94A3B8),
                    shape: BoxShape.circle,
                  ),
                ),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: on ? const Color(0xFF047857) : const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
    return tip.isEmpty ? pill : Tooltip(message: tip, child: pill);
  }

  Widget _pulseDot(double size, Color color, {Border? border}) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final t = _pulse.value;
        final k = t < 0.7 ? t / 0.7 : 1.0;
        final alpha = t < 0.7 ? 0.55 * (1 - k) : 0.0;
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: border,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF10B981).withValues(alpha: alpha),
                spreadRadius: 7 * k,
              ),
              if (border != null)
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.35),
                  offset: const Offset(0, 1),
                  blurRadius: 4,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionTitle(_Ld ld, String t, bool first) => Padding(
    padding: EdgeInsets.only(top: first ? 0 : 18, bottom: 8),
    child: Text(
      t.toUpperCase(),
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 1,
        color: ld.faint,
      ),
    ),
  );

  Widget _sourceTag(String source) {
    final (label, icon, bg, fg, bd) = switch (source) {
      'device' => (
        'Device fix',
        Icons.gps_fixed,
        const Color(0xFFECFDF5),
        const Color(0xFF047857),
        const Color(0xFFA7F3D0),
      ),
      'ip' => (
        'IP estimate',
        Icons.public,
        const Color(0xFFEFF6FF),
        const Color(0xFF1D4ED8),
        const Color(0xFFBFDBFE),
      ),
      _ => (
        'No coordinates',
        null,
        const Color(0xFFF1F5F9),
        const Color(0xFF64748B),
        const Color(0xFFE2E8F0),
      ),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: bd),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 11, color: fg),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(_Ld ld, Map f, bool last) {
    final tag = (f['tag'] ?? '').toString();
    final mono = f['mono'] == true;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: ld.fieldRule)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              (f['k'] ?? '').toString(),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: ld.muted,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: tag.isNotEmpty
                ? _sourceTag(tag)
                : SelectableText(
                    (f['v'] ?? '').toString(),
                    style: TextStyle(
                      fontSize: mono ? 12 : 12.5,
                      color: ld.ink,
                      fontFamily: mono ? 'JetBrainsMono' : null,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _chip(_Ld ld, String strong, String rest, {bool lead = true}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: ld.box,
        border: Border.all(color: ld.rule),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text.rich(
        TextSpan(
          style: TextStyle(fontSize: 11.5, color: ld.chipText),
          children: [
            if (!lead) TextSpan(text: rest),
            TextSpan(
              text: strong,
              style: TextStyle(fontWeight: FontWeight.w700, color: ld.ink),
            ),
            if (lead) TextSpan(text: rest),
          ],
        ),
      ),
    );
  }

  Widget _side(_Ld ld) {
    final res = _res!;
    final sections = res['sections'] is List
        ? res['sections'] as List
        : const [];
    final children = <Widget>[];
    for (final s in sections) {
      if (s is! Map) continue;
      children.add(
        _sectionTitle(ld, (s['title'] ?? '').toString(), children.isEmpty),
      );
      final fields = s['fields'] is List ? s['fields'] as List : const [];
      for (var i = 0; i < fields.length; i++) {
        final f = fields[i];
        if (f is Map) children.add(_field(ld, f, i == fields.length - 1));
      }
    }
    final note = res['note'];
    if (note != null && note.toString().isNotEmpty) {
      children.add(
        _sectionTitle(
          ld,
          (res['note_label'] ?? 'Details').toString(),
          children.isEmpty,
        ),
      );
      children.add(
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: ld.box,
            border: Border.all(color: ld.rule),
            borderRadius: BorderRadius.circular(10),
          ),
          child: SelectableText(
            note.toString(),
            style: TextStyle(fontSize: 12.5, color: ld.ink, height: 1.6),
          ),
        ),
      );
    }
    final deviceFixes = _track.where((p) => p.source == 'device').length;
    children.add(_sectionTitle(ld, 'Trace', children.isEmpty));
    children.add(
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip(ld, '${_track.length}', ' located stops'),
            _chip(ld, '$deviceFixes', ' device fixes'),
            _chip(ld, _fmtDistance(_pathKm), 'Path ', lead: false),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget _mapPane(_Ld ld) {
    final res = _res!;
    if (_track.isEmpty) {
      return Container(
        color: ld.mapBg,
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.map_outlined, size: 28, color: Color(0xFFCBD5E1)),
            const SizedBox(height: 8),
            Text(
              (res['empty_note'] ?? 'No coordinates recorded for this entry.')
                  .toString(),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: ld.muted),
            ),
          ],
        ),
      );
    }
    return Container(
      color: ld.mapBg,
      child: Stack(
        children: [
          Positioned.fill(child: _mapWidget()),
          Positioned(top: 10, left: 10, child: _zoomControls()),
          Positioned(left: 12, bottom: 12, child: _mapNote(res)),
          Positioned(right: 0, bottom: 0, child: _attribution()),
        ],
      ),
    );
  }

  Widget _mapNote(Map<String, dynamic> res) {
    final note = (res['track_note'] ?? '').toString();
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.1),
            offset: const Offset(0, 4),
            blurRadius: 12,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 22,
                  height: 3,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _kGreen,
                      borderRadius: BorderRadius.all(Radius.circular(2)),
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    (res['track_label'] ?? 'Movement path').toString(),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F172A),
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 22,
                  height: 2,
                  child: CustomPaint(painter: _DashPainter()),
                ),
                const SizedBox(width: 7),
                const Flexible(
                  child: Text(
                    'Direct line where no road route exists',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF64748B),
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (note.isNotEmpty)
            Text(
              note,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF475569),
                height: 1.5,
              ),
            ),
        ],
      ),
    );
  }

  Widget _zoomControls() {
    Widget btn(String label, VoidCallback onTap, bool enabled, bool top) {
      return Material(
        color: Colors.white,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: top
                  ? const Border(bottom: BorderSide(color: Color(0xFFCCCCCC)))
                  : null,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                height: 1,
                color: enabled ? Colors.black : const Color(0xFFBBBBBB),
              ),
            ),
          ),
        ),
      );
    }

    return StreamBuilder<MapEvent>(
      stream: _map.mapEventStream,
      builder: (context, _) {
        final maxZ = _sources[_tileIndex].maxZoom.toDouble();
        final zoom = _mapReady ? _map.camera.zoom : 0.0;
        return Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: Colors.black.withValues(alpha: 0.2),
              width: 2,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                btn('+', () => _zoomBy(1), !_mapReady || zoom < maxZ, true),
                btn('−', () => _zoomBy(-1), !_mapReady || zoom > 0, false),
              ],
            ),
          ),
        );
      },
    );
  }

  void _zoomBy(double d) {
    if (!_mapReady) return;
    final cam = _map.camera;
    final maxZ = _sources[_tileIndex].maxZoom.toDouble();
    _map.move(cam.center, (cam.zoom + d).clamp(0.0, maxZ).roundToDouble());
  }

  Widget _attribution() {
    final parts = _sources[_tileIndex].attribution;
    return Container(
      color: Colors.white.withValues(alpha: 0.8),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Text.rich(
        TextSpan(
          style: const TextStyle(
            fontSize: 12,
            height: 1.4,
            color: Color(0xFF333333),
          ),
          children: [
            for (final (text, url) in parts)
              url == null
                  ? TextSpan(text: text)
                  : WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => launchUrl(
                            Uri.parse(url),
                            mode: LaunchMode.externalApplication,
                          ),
                          child: Text(
                            text,
                            style: const TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: Color(0xFF0078A8),
                            ),
                          ),
                        ),
                      ),
                    ),
          ],
        ),
      ),
    );
  }

  Widget _mapWidget() {
    final src = _sources[_tileIndex];
    final lastIndex = _track.length - 1;
    final pins = <Marker>[];
    final circles = <CircleMarker>[];
    final coarse = <Polyline>[];
    for (var i = 0; i < _track.length; i++) {
      final p = _track[i];
      final kind = p.ids.any(_selected.contains)
          ? 'selected'
          : (i == lastIndex ? 'current' : '');
      final size = kind == 'selected'
          ? 20.0
          : (kind == 'current' ? 18.0 : 14.0);
      pins.add(
        Marker(
          point: p.ll,
          width: size,
          height: size,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _openPopup(i),
              child: _pin(p.source, kind, size),
            ),
          ),
        ),
      );
      if (p.source == 'device' && p.accuracy > 0) {
        if (p.accuracy > 2000) {
          coarse.add(
            Polyline(
              points: _ring(p.ll, p.accuracy),
              color: _kGreen.withValues(alpha: 0.45),
              strokeWidth: 1.5,
              pattern: StrokePattern.dashed(segments: const [5, 7]),
            ),
          );
        } else {
          circles.add(
            CircleMarker(
              point: p.ll,
              radius: p.accuracy,
              useRadiusInMeter: true,
              color: _kGreen.withValues(alpha: 0.07),
              borderColor: _kGreen.withValues(alpha: 0.55),
              borderStrokeWidth: 1,
            ),
          );
        }
      }
    }
    final lines = <Polyline>[
      for (final s in _segments)
        Polyline(
          points: s.line,
          color: const Color(
            0xFFBBF7D0,
          ).withValues(alpha: s.routed ? 0.45 : 0.25),
          strokeWidth: 9,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
      for (final s in _segments)
        Polyline(
          points: s.line,
          color: _kGreen.withValues(alpha: s.routed ? 0.95 : 0.6),
          strokeWidth: s.routed ? 4 : 3,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
          pattern: s.routed
              ? const StrokePattern.solid()
              : StrokePattern.dashed(segments: const [5, 8]),
        ),
    ];
    final popupIndex = _popup;
    return FlutterMap(
      key: ValueKey('ldmap$_mapVersion'),
      mapController: _map,
      options: MapOptions(
        backgroundColor: const Color(0xFFEEF2F7),
        maxZoom: src.maxZoom.toDouble(),
        minZoom: 0,
        initialCameraFit: CameraFit.coordinates(
          coordinates: [for (final p in _track) p.ll],
          padding: const EdgeInsets.all(42),
          maxZoom: 16,
          forceIntegerZoomLevel: true,
        ),
        onMapReady: () {
          if (mounted) setState(() => _mapReady = true);
        },
        onTap: (_, _) {
          if (_popup != null) setState(() => _popup = null);
        },
      ),
      children: [
        TileLayer(
          key: ValueKey('tiles$_tileIndex'),
          urlTemplate: src.url,
          subdomains: src.subdomains,
          maxNativeZoom: src.maxZoom,
          maxZoom: src.maxZoom.toDouble(),
          retinaMode: RetinaMode.isHighDensity(context),
          userAgentPackageName: 'io.tinkerpro.support_desktop',
          errorTileCallback: (_, _, _) => _onTileError(),
        ),
        PolylineLayer(polylines: lines),
        if (circles.isNotEmpty) CircleLayer(circles: circles),
        if (coarse.isNotEmpty) PolylineLayer(polylines: coarse),
        MarkerLayer(markers: pins),
        if (popupIndex != null && popupIndex < _track.length)
          MarkerLayer(
            markers: [
              Marker(
                point: _track[popupIndex].ll,
                width: 360,
                height: 300,
                alignment: Alignment.topCenter,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: _popupCard(_track[popupIndex], popupIndex),
                ),
              ),
            ],
          ),
      ],
    );
  }

  void _openPopup(int i) {
    setState(() => _popup = i);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _popup != i || !_mapReady || i >= _track.length) return;
      final box = _popupKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final cam = _map.camera;
      final view = cam.nonRotatedSize;
      final at = cam.latLngToScreenOffset(_track[i].ll);
      final size = box.size;
      final left = at.dx - size.width / 2;
      final right = at.dx + size.width / 2;
      final top = at.dy - size.height;
      const pad = 5.0;
      var dx = 0.0;
      var dy = 0.0;
      if (left < pad) {
        dx = left - pad;
      } else if (right > view.width - pad) {
        dx = right - (view.width - pad);
      }
      if (top < pad) dy = top - pad;
      if (dx == 0 && dy == 0) return;
      final center = cam.screenOffsetToLatLng(
        Offset(view.width / 2 + dx, view.height / 2 + dy),
      );
      _map.move(center, cam.zoom);
    });
  }

  List<LatLng> _ring(LatLng c, double meters) {
    const d = Distance();
    return [for (var deg = 0; deg <= 360; deg += 5) d.offset(c, meters, deg)];
  }

  Widget _pin(String source, String kind, double size) {
    final color = kind == 'selected'
        ? const Color(0xFF0F172A)
        : kind == 'current'
        ? const Color(0xFFF97316)
        : source == 'device'
        ? _kGreen
        : const Color(0xFF3B82F6);
    final border = Border.all(
      color: Colors.white,
      width: kind == 'selected' ? 3 : 2.5,
    );
    if (kind == 'current') return _pulseDot(size, color, border: border);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: border,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.35),
            offset: const Offset(0, 1),
            blurRadius: 4,
          ),
        ],
      ),
    );
  }

  Widget _popupCard(_Pt p, int index) {
    const meta = TextStyle(
      fontSize: 11,
      color: Color(0xFF64748B),
      height: 1.55,
    );
    final events = p.events > 1 ? p.events : 1;
    final span = events > 1
        ? '${_fmtDate(p.s('first_at'))} → ${_fmtDate(p.s('created_at'))}'
        : _fmtDate(p.s('created_at'));
    final action = p.s('action').isEmpty ? 'Activity' : p.s('action');
    final address = p.s('address');
    final location = p.s('location');
    final src = p.source == 'device'
        ? 'Device fix${p.accuracy > 0 ? ' ±${_fmtAccuracy(p.accuracy)}' : ''}'
        : 'IP estimate${location.isNotEmpty ? ' · $location' : ''}';
    final tail =
        '$src${events > 1 ? ' · $events events here' : ''} · stop ${index + 1} of ${_track.length}';
    final pinHalf = p.ids.any(_selected.contains)
        ? 10.0
        : (index == _track.length - 1 ? 9.0 : 7.0);
    return Padding(
      key: _popupKey,
      padding: EdgeInsets.only(bottom: pinHalf),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 224, maxWidth: 344),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  offset: const Offset(0, 3),
                  blurRadius: 14,
                ),
              ],
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 13, 24, 13),
                  child: IntrinsicWidth(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          action,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                            height: 1.55,
                          ),
                        ),
                        if (address.isNotEmpty)
                          Text(
                            address,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF047857),
                              height: 1.55,
                            ),
                          ),
                        Text(span, style: meta),
                        SelectableText(
                          '${p.lat.toStringAsFixed(6)}, ${p.lon.toStringAsFixed(6)}',
                          style: meta,
                        ),
                        Text(tail, style: meta),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => setState(() => _popup = null),
                      child: const SizedBox(
                        width: 24,
                        height: 24,
                        child: Center(
                          child: Text(
                            '×',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF757575),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(
            width: 20,
            height: 10,
            child: CustomPaint(painter: _TipPainter()),
          ),
        ],
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  const _DashPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _kGreen.withValues(alpha: 0.7)
      ..strokeWidth = size.height;
    final y = size.height / 2;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, y),
        Offset(math.min(x + 4, size.width), y),
        paint,
      );
      x += 7;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TipPainter extends CustomPainter {
  const _TipPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.4), 2, false);
    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
