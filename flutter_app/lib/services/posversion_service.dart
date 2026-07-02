// API layer for the POS Version feature. All endpoints live on `api.php`:
//   * getposversion    GET   page,limit,search   → {data:[...], totalRecords}
//   * addposversion    POST  version, release_date
//   * updateposversion POST  id, version, date
//   * deleteposversion POST  id                   → {success}

import '../api_client.dart';
import '../models/posversion_models.dart';

class PosVersionResult {
  PosVersionResult({required this.ok, this.message});
  final bool ok;
  final String? message;
}

class PosVersionService {
  PosVersionService(this._api);
  final ApiClient _api;

  /// Fetch a page of POS versions. The backend paginates; we pull a large
  /// page so the mobile list is simple (pull-to-refresh, no infinite scroll
  /// yet). Returns an empty list on any failure so the UI still renders.
  Future<List<PosVersion>> list({int page = 1, int limit = 100}) async {
    try {
      final res = await _api.get('getposversion', {
        'page': '$page',
        'limit': '$limit',
      });
      final raw = res['data'];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => PosVersion.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  /// Create a version. [date] is the release date (YYYY-MM-DD); the backend
  /// expects it under the `release_date` field on add.
  Future<PosVersionResult> add({
    required String version,
    required String date,
  }) async {
    return _mutate('addposversion', {
      'version': version.trim(),
      'release_date': date,
    });
  }

  /// Update a version. On update the backend expects the release date under
  /// the `date` field (not `release_date`).
  Future<PosVersionResult> update({
    required int id,
    required String version,
    required String date,
  }) async {
    return _mutate('updateposversion', {
      'id': '$id',
      'version': version.trim(),
      'date': date,
    });
  }

  Future<PosVersionResult> delete(int id) =>
      _mutate('deleteposversion', {'id': '$id'});

  Future<PosVersionResult> _mutate(
      String action, Map<String, String> body) async {
    try {
      final res = await _api.post(action, body: body);
      final ok = res['success'] == true || res['status'] == 'success';
      return PosVersionResult(ok: ok, message: res['message']?.toString());
    } catch (e) {
      return PosVersionResult(ok: false, message: 'Network error');
    }
  }
}
