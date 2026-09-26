import '../api_client.dart';

class ProfileStats {
  ProfileStats(this.raw);

  final Map<String, dynamic> raw;

  Map<String, dynamic> _map(Object? v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  Map<String, dynamic> get profile => _map(raw['profile']);
  Map<String, dynamic> get has => _map(raw['has']);
  Map<String, dynamic> get kpis => _map(raw['kpis']);
  Map<String, dynamic> get charts => _map(raw['charts']);
  Map<String, dynamic> get series => _map(raw['series']);
  String get mode => '${raw['mode'] ?? ''}';

  bool hasFlag(String k) => has[k] == true;

  int kpi(String k) => num.tryParse('${kpis[k] ?? ''}')?.toInt() ?? 0;

  int? kpiOrNull(String k) {
    final v = kpis[k];
    if (v == null) return null;
    return num.tryParse('$v')?.round();
  }

  String kpiText(String k) => '${kpis[k] ?? ''}';

  int get profileId => num.tryParse('${profile['id'] ?? ''}')?.toInt() ?? 0;
  bool get online => profile['online'] == true;
  int? get lastSeenAgo {
    final v = profile['last_seen_ago'];
    if (v == null) return null;
    return num.tryParse('$v')?.round();
  }

  String get firstSeen => '${profile['first_seen'] ?? ''}';

  List<String> seriesLabels() {
    final v = series['labels'];
    return v is List ? [for (final e in v) '$e'] : const [];
  }

  List<int>? seriesValues(String key) {
    final v = series[key];
    if (v is! List) return null;
    return [for (final e in v) num.tryParse('$e')?.toInt() ?? 0];
  }

  Map<String, int> chartCounts(String key) {
    final v = charts[key];
    if (v is! Map) return const {};
    return {
      for (final e in v.entries)
        '${e.key}': num.tryParse('${e.value}')?.toInt() ?? 0,
    };
  }
}

class ProfileService {
  ProfileService(this.api);

  final ApiClient api;

  String url(String path) {
    if (path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '${api.baseUrl}/${path.replaceAll(RegExp(r'^/+'), '')}';
  }

  Map<String, String> get authHeaders => api.authHeaders();

  Future<ProfileStats> load({int userId = 0}) async {
    final res = userId > 0
        ? await api.get('userProfileStats', {'user_id': '$userId'})
        : await api.get('myProfileStats');
    final data = res['data'];
    if (res['status'] != 'success' || data is! Map) {
      throw StateError('bad payload');
    }
    return ProfileStats(Map<String, dynamic>.from(data));
  }
}
