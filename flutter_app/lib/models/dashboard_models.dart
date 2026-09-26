int _toInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.round();
  if (v is String) return int.tryParse(v) ?? double.tryParse(v)?.round() ?? 0;
  if (v is bool) return v ? 1 : 0;
  return 0;
}

double _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

String _toStr(dynamic v) => v == null ? '' : v.toString();

Map<String, dynamic> _asMap(dynamic v) {
  if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
  return const {};
}

Map<String, int> _intMap(dynamic v) {
  final out = <String, int>{};
  if (v is Map) {
    v.forEach((k, val) => out[k.toString()] = _toInt(val));
  }
  return out;
}

List<int> _intList(dynamic v) {
  if (v is List) return v.map(_toInt).toList();
  return const [];
}

List<String> _strList(dynamic v) {
  if (v is List) return v.map(_toStr).toList();
  return const [];
}

class ChartEntry {
  const ChartEntry(this.label, this.value);
  final String label;
  final int value;
}

List<ChartEntry> _entries(dynamic v) {
  if (v is Map) {
    return [
      for (final e in v.entries) ChartEntry(e.key.toString(), _toInt(e.value)),
    ];
  }
  if (v is List) {
    return [
      for (var i = 0; i < v.length; i++) ChartEntry(i.toString(), _toInt(v[i])),
    ];
  }
  return const [];
}

class TimeSeries {
  const TimeSeries({required this.labels, required this.values});

  final List<String> labels;
  final Map<String, List<int>> values;

  static const empty = TimeSeries(labels: [], values: {});

  bool get isEmpty => values.isEmpty;

  List<int>? operator [](String key) => values[key];

  bool has(String key) => values.containsKey(key);

  factory TimeSeries.fromJson(dynamic raw, Set<String> skip) {
    final map = _asMap(raw);
    if (map.isEmpty) return empty;
    final values = <String, List<int>>{};
    map.forEach((k, v) {
      if (k == 'labels' || skip.contains(k)) return;
      if (v is List) values[k] = _intList(v);
    });
    return TimeSeries(labels: _strList(map['labels']), values: values);
  }
}

class FeedItem {
  const FeedItem({
    required this.key,
    required this.kind,
    required this.icon,
    required this.title,
    required this.body,
    required this.who,
    required this.tag,
    required this.href,
    required this.ago,
  });

  final String key;
  final String kind;
  final String icon;
  final String title;
  final String body;
  final String who;
  final String tag;
  final String href;
  final int ago;

  factory FeedItem.fromJson(Map<String, dynamic> j) => FeedItem(
    key: _toStr(j['key']),
    kind: _toStr(j['kind']),
    icon: _toStr(j['icon']),
    title: _toStr(j['title']),
    body: _toStr(j['body']),
    who: _toStr(j['who']),
    tag: _toStr(j['tag']),
    href: _toStr(j['href']),
    ago: _toInt(j['ago']),
  );
}

class OnlineStaff {
  const OnlineStaff({
    required this.id,
    required this.fullName,
    required this.username,
    required this.role,
    required this.picture,
    required this.ago,
  });

  final int id;
  final String fullName;
  final String username;
  final String role;
  final String picture;
  final int ago;

  String get displayName => fullName.trim().isNotEmpty
      ? fullName.trim()
      : (username.trim().isNotEmpty ? username.trim() : 'User');

  factory OnlineStaff.fromJson(Map<String, dynamic> j) => OnlineStaff(
    id: _toInt(j['id']),
    fullName: _toStr(j['full_name']),
    username: _toStr(j['username']),
    role: _toStr(j['role']),
    picture: _toStr(j['profile_picture']).trim(),
    ago: _toInt(j['ago']),
  );
}

class DashboardLive {
  const DashboardLive({
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
  final TimeSeries series;
  final TimeSeries heartbeat;
  final List<FeedItem> activity;
  final List<OnlineStaff> online;
  final Map<String, List<ChartEntry>> charts;
  final DateTime? serverTime;

  bool hasChart(String key) => charts.containsKey(key);

  List<ChartEntry> chart(String key) => charts[key] ?? const [];

  factory DashboardLive.fromJson(Map<String, dynamic> j) {
    final chartsRaw = _asMap(j['charts']);
    final charts = <String, List<ChartEntry>>{};
    chartsRaw.forEach((k, v) => charts[k] = _entries(v));
    final activity = j['activity'];
    final online = j['online'];
    return DashboardLive(
      totals: _intMap(j['totals']),
      pulse: _intMap(j['pulse']),
      series: TimeSeries.fromJson(j['series'], const {'days'}),
      heartbeat: TimeSeries.fromJson(j['heartbeat'], const {'hours'}),
      activity: activity is List
          ? activity
                .whereType<Map>()
                .map((e) => FeedItem.fromJson(_asMap(e)))
                .toList()
          : const [],
      online: online is List
          ? online
                .whereType<Map>()
                .map((e) => OnlineStaff.fromJson(_asMap(e)))
                .toList()
          : const [],
      charts: charts,
      serverTime: DateTime.tryParse(
        _toStr(j['server_time']).replaceFirst(' ', 'T'),
      ),
    );
  }
}

class LicenseRevenue {
  const LicenseRevenue({
    required this.available,
    required this.total,
    required this.month,
    required this.today,
    required this.paidCount,
    required this.monthCount,
    required this.pendingCount,
    required this.pendingValue,
    required this.defaultPrice,
    required this.complete,
  });

  final bool available;
  final double total;
  final double month;
  final double today;
  final int paidCount;
  final int monthCount;
  final int pendingCount;
  final double pendingValue;
  final double? defaultPrice;
  final bool complete;

  double get average => paidCount > 0 ? total / paidCount : 0;
}

class VendorRequestRow {
  const VendorRequestRow({
    required this.quantity,
    required this.amount,
    required this.paid,
    required this.paidAt,
  });

  final int quantity;
  final double amount;
  final bool paid;
  final String paidAt;

  factory VendorRequestRow.fromJson(Map<String, dynamic> j) => VendorRequestRow(
    quantity: _toInt(j['quantity']) < 1 ? 1 : _toInt(j['quantity']),
    amount: _toDouble(j['amount']),
    paid: _toStr(j['payment_status']) == 'paid',
    paidAt: _toStr(j['paid_at']),
  );
}
