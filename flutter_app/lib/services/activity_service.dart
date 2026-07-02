// API layer for the Activity Logs feature (read-only). The single endpoint
// lives on `api.php`:
//   * getActivityLogs  GET  page,limit,search  → {data:[...], totalRecords}

import '../api_client.dart';
import '../models/activity_models.dart';

class ActivityService {
  ActivityService(this._api);
  final ApiClient _api;

  /// Fetch a page of activity logs. Pull a large page so the mobile list is
  /// simple (pull-to-refresh, no infinite scroll yet). [search] matches the
  /// action, details, or username server-side. Returns an empty list on any
  /// failure so the UI still renders.
  Future<List<ActivityLog>> list({
    String? search,
    int page = 1,
    int limit = 100,
  }) async {
    try {
      final res = await _api.get('getActivityLogs', {
        'page': '$page',
        'limit': '$limit',
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      });
      final raw = res['data'];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => ActivityLog.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    return const [];
  }
}
