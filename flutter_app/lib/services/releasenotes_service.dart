// API layer for the Release Notes feature. All endpoints live on `api.php`:
//   * getReleaseNotes    GET   page,limit,search,filterVersion?,filterActionType?
//                              → {data:[...], total, limit, page}
//   * AddReleaseNotes    POST  version, actiontype, notes  → {success}
//   * updateReleaseNotes POST  id, version, actiontype, notes → {success}
//   * deleteReleaseNotes POST  id                          → {success}
//   * getActionTypes     GET                               → {success, data:[{id,type}]}
//   * getposversion      GET   page,limit                  → {data:[{id,version,...}]}

import '../api_client.dart';
import '../models/releasenotes_models.dart';

class ReleaseNotesResult {
  ReleaseNotesResult({required this.ok, this.message});
  final bool ok;
  final String? message;
}

class ReleaseNotesService {
  ReleaseNotesService(this._api);
  final ApiClient _api;

  /// Fetch a page of release notes. We pull a large page so the mobile list
  /// is simple (pull-to-refresh, no infinite scroll yet). Returns an empty
  /// list on any failure so the UI still renders.
  Future<List<ReleaseNote>> list({int page = 1, int limit = 100}) async {
    try {
      final res = await _api.get('getReleaseNotes', {
        'page': '$page',
        'limit': '$limit',
      });
      final raw = res['data'];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => ReleaseNote.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  /// Versions for the picker (from `getposversion`). Empty on failure.
  Future<List<PosVersionRef>> listVersions() async {
    try {
      final res = await _api.get('getposversion', {
        'page': '1',
        'limit': '500',
      });
      final raw = res['data'];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => PosVersionRef.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  /// Action types for the picker (from `getActionTypes`). Empty on failure.
  Future<List<ActionType>> listActionTypes() async {
    try {
      final res = await _api.get('getActionTypes');
      final raw = res['data'];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => ActionType.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  /// Create a note. [versionId] is a posversion ID, [actionTypeId] an action ID.
  Future<ReleaseNotesResult> add({
    required int versionId,
    required int actionTypeId,
    required String notes,
  }) async {
    return _mutate('AddReleaseNotes', {
      'version': '$versionId',
      'actiontype': '$actionTypeId',
      'notes': notes.trim(),
    });
  }

  Future<ReleaseNotesResult> update({
    required int id,
    required int versionId,
    required int actionTypeId,
    required String notes,
  }) async {
    return _mutate('updateReleaseNotes', {
      'id': '$id',
      'version': '$versionId',
      'actiontype': '$actionTypeId',
      'notes': notes.trim(),
    });
  }

  Future<ReleaseNotesResult> delete(int id) =>
      _mutate('deleteReleaseNotes', {'id': '$id'});

  Future<ReleaseNotesResult> _mutate(
      String action, Map<String, String> body) async {
    try {
      final res = await _api.post(action, body: body);
      final ok = res['success'] == true || res['status'] == 'success';
      return ReleaseNotesResult(ok: ok, message: res['message']?.toString());
    } catch (e) {
      return ReleaseNotesResult(ok: false, message: 'Network error');
    }
  }
}
