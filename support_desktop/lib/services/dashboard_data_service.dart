import '../api_client.dart';

String _s(dynamic v) => v == null ? '' : '$v';
int _i(dynamic v) => v is int
    ? v
    : v is num
    ? v.toInt()
    : int.tryParse(_s(v)) ?? (double.tryParse(_s(v))?.toInt() ?? 0);
double _f(dynamic v) => v is num ? v.toDouble() : double.tryParse(_s(v)) ?? 0;
bool _b(dynamic v) => v == true || v == 1 || v == '1' || v == 'true';

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Map<String, dynamic>> _maps(dynamic raw) {
  if (raw is! List) return const [];
  return raw.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
}

List<int> _ints(dynamic raw) =>
    raw is List ? raw.map(_i).toList() : const <int>[];

class DashSeriesData {
  const DashSeriesData(this.labels, this.values);
  final List<String> labels;
  final List<int> values;

  bool get isEmpty => values.isEmpty || values.every((v) => v == 0);

  factory DashSeriesData.fromRaw(dynamic raw) {
    if (raw is Map) {
      return DashSeriesData(
        raw.keys.map((k) => '$k').toList(),
        raw.values.map(_i).toList(),
      );
    }
    return const DashSeriesData([], []);
  }
}

class DashChip {
  const DashChip(this.id, this.label, this.href, this.level);
  final String id;
  final String label;
  final String href;
  final String level;
}

class DashPulseCell {
  const DashPulseCell(this.id, this.label, this.icon);
  final String id;
  final String label;
  final String icon;
}

class DashStatCard {
  const DashStatCard({
    required this.key,
    required this.label,
    required this.icon,
    required this.series,
    required this.href,
    required this.primary,
  });
  final String key;
  final String label;
  final String icon;
  final String series;
  final String href;
  final bool primary;
}

class DashChartItem {
  const DashChartItem({
    required this.id,
    required this.title,
    required this.icon,
    required this.kind,
    required this.height,
    this.width,
  });
  final String id;
  final String title;
  final String icon;
  final String kind;
  final double height;
  final int? width;
}

class DashChartGroup {
  const DashChartGroup(this.name, this.meta, this.items);
  final String name;
  final String meta;
  final List<DashChartItem> items;
}

class DashRevenue {
  const DashRevenue({
    required this.available,
    required this.total,
    required this.month,
    required this.today,
    required this.paidCount,
    required this.monthCount,
    required this.average,
    required this.pendingCount,
    required this.pendingValue,
    required this.defaultPrice,
  });
  final bool available;
  final double total;
  final double month;
  final double today;
  final int paidCount;
  final int monthCount;
  final double average;
  final int pendingCount;
  final double pendingValue;
  final double? defaultPrice;

  factory DashRevenue.fromJson(Map<String, dynamic> j) => DashRevenue(
    available: _b(j['available']),
    total: _f(j['total']),
    month: _f(j['month']),
    today: _f(j['today']),
    paidCount: _i(j['paid_count']),
    monthCount: _i(j['month_count']),
    average: _f(j['average']),
    pendingCount: _i(j['pending_count']),
    pendingValue: _f(j['pending_value']),
    defaultPrice: j['default_price'] == null ? null : _f(j['default_price']),
  );
}

class DashActivity {
  const DashActivity({
    required this.key,
    required this.kind,
    required this.icon,
    required this.title,
    required this.body,
    required this.who,
    required this.href,
    required this.ago,
  });
  final String key;
  final String kind;
  final String icon;
  final String title;
  final String body;
  final String who;
  final String href;
  final int ago;
}

class DashOnline {
  const DashOnline(this.id, this.name, this.picture);
  final int id;
  final String name;
  final String picture;
}

class DashHeartbeat {
  const DashHeartbeat(this.labels, this.series);
  final List<String> labels;
  final Map<String, List<int>> series;
  bool get isEmpty => labels.isEmpty || series.isEmpty;
}

class DashSnapshot {
  const DashSnapshot({
    required this.totals,
    required this.pulse,
    required this.series,
    required this.heartbeat,
    required this.activity,
    required this.online,
    required this.charts,
    required this.serverTime,
  });

  final Map<String, int> totals;
  final Map<String, int> pulse;
  final Map<String, List<int>> series;
  final DashHeartbeat heartbeat;
  final List<DashActivity> activity;
  final List<DashOnline> online;
  final Map<String, DashSeriesData> charts;
  final DateTime? serverTime;

  factory DashSnapshot.fromJson(Map<String, dynamic> j) {
    Map<String, int> intMap(dynamic raw) =>
        _map(raw).map((k, v) => MapEntry(k, _i(v)));
    final seriesRaw = _map(j['series']);
    final series = <String, List<int>>{};
    seriesRaw.forEach((k, v) {
      if (k == 'labels' || k == 'days') return;
      if (v is List) series[k] = _ints(v);
    });
    final hbRaw = _map(j['heartbeat']);
    final hb = <String, List<int>>{};
    for (final k in const [
      'actions',
      'messages',
      'tickets',
      'emails',
      'files',
    ]) {
      if (hbRaw[k] is List) hb[k] = _ints(hbRaw[k]);
    }
    final labels = hbRaw['labels'] is List
        ? (hbRaw['labels'] as List).map(_s).toList()
        : <String>[];
    final charts = <String, DashSeriesData>{};
    _map(j['charts']).forEach((k, v) => charts[k] = DashSeriesData.fromRaw(v));
    final st = _s(j['server_time']).trim();
    return DashSnapshot(
      totals: intMap(j['totals']),
      pulse: intMap(j['pulse']),
      series: series,
      heartbeat: DashHeartbeat(labels, hb),
      activity: _maps(j['activity'])
          .map(
            (a) => DashActivity(
              key: _s(a['key']),
              kind: _s(a['kind']),
              icon: _s(a['icon']),
              title: _s(a['title']),
              body: _s(a['body']),
              who: _s(a['who']),
              href: _s(a['href']),
              ago: _i(a['ago']),
            ),
          )
          .toList(),
      online: _maps(j['online'])
          .map(
            (u) => DashOnline(
              _i(u['id']),
              _s(u['full_name']).isNotEmpty
                  ? _s(u['full_name'])
                  : (_s(u['username']).isNotEmpty ? _s(u['username']) : 'User'),
              _s(u['profile_picture']).trim(),
            ),
          )
          .toList(),
      charts: charts,
      serverTime: st.isEmpty
          ? null
          : DateTime.tryParse(st.replaceFirst(' ', 'T')),
    );
  }
}

class DesktopDashboard {
  const DesktopDashboard({
    required this.perms,
    required this.isAdminView,
    required this.chips,
    required this.pulseCells,
    required this.statCards,
    required this.heartbeatOk,
    required this.feedOk,
    required this.chartGroups,
    required this.revenue,
    required this.hasAnything,
    required this.snapshot,
  });

  final Map<String, bool> perms;
  final bool isAdminView;
  final List<DashChip> chips;
  final List<DashPulseCell> pulseCells;
  final List<DashStatCard> statCards;
  final bool heartbeatOk;
  final bool feedOk;
  final List<DashChartGroup> chartGroups;
  final DashRevenue? revenue;
  final bool hasAnything;
  final DashSnapshot snapshot;

  DesktopDashboard withSnapshot(DashSnapshot s) => DesktopDashboard(
    perms: perms,
    isAdminView: isAdminView,
    chips: chips,
    pulseCells: pulseCells,
    statCards: statCards,
    heartbeatOk: heartbeatOk,
    feedOk: feedOk,
    chartGroups: chartGroups,
    revenue: revenue,
    hasAnything: hasAnything,
    snapshot: s,
  );

  factory DesktopDashboard.fromJson(Map<String, dynamic> j) {
    final rev = j['revenue'];
    return DesktopDashboard(
      perms: _map(j['perms']).map((k, v) => MapEntry(k, _b(v))),
      isAdminView: _b(j['is_admin_view']),
      chips: _maps(j['chips'])
          .map(
            (c) => DashChip(
              _s(c['id']),
              _s(c['label']),
              _s(c['href']),
              _s(c['level']),
            ),
          )
          .toList(),
      pulseCells: _maps(j['pulse_cells'])
          .map((c) => DashPulseCell(_s(c['id']), _s(c['label']), _s(c['icon'])))
          .toList(),
      statCards: _maps(j['stat_cards'])
          .map(
            (c) => DashStatCard(
              key: _s(c['key']),
              label: _s(c['label']),
              icon: _s(c['icon']),
              series: _s(c['series']),
              href: _s(c['href']),
              primary: _b(c['primary']),
            ),
          )
          .toList(),
      heartbeatOk: _b(j['heartbeat_ok']),
      feedOk: _b(j['feed_ok']),
      chartGroups: _maps(j['chart_groups'])
          .map(
            (g) => DashChartGroup(
              _s(g['name']),
              _s(g['meta']),
              _maps(g['items'])
                  .map(
                    (i) => DashChartItem(
                      id: _s(i['id']),
                      title: _s(i['title']),
                      icon: _s(i['icon']),
                      kind: _s(i['kind']),
                      height: i['height'] == null ? 0 : _f(i['height']),
                      width: i['w'] == null ? null : _i(i['w']),
                    ),
                  )
                  .toList(),
            ),
          )
          .toList(),
      revenue: rev is Map
          ? DashRevenue.fromJson(Map<String, dynamic>.from(rev))
          : null,
      hasAnything: _b(j['has_anything']),
      snapshot: DashSnapshot.fromJson(_map(j['snapshot'])),
    );
  }
}

class DashboardDataService {
  DashboardDataService(this.api);
  final ApiClient api;

  Future<DesktopDashboard?> fetch() async {
    final res = await api.get('desktopDashboard');
    if (res['success'] != true) return null;
    return DesktopDashboard.fromJson(res);
  }

  Future<DashSnapshot?> live() async {
    final res = await api.get('dashboardLive');
    if (res['status'] != 'success' || res['data'] is! Map) return null;
    return DashSnapshot.fromJson(Map<String, dynamic>.from(res['data']));
  }
}
