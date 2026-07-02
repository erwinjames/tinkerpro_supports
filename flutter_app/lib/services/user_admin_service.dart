// API layer for the Users / User Management feature. All endpoints live on
// `api.php`:
//   * users            GET                                  → {data:[...], totalRecords}
//   * addUsers         POST userfullname, username, user_email, password, role, permissions(JSON)
//   * updateUsers      POST user_id, userfullname, user_email, role, permissions(JSON)
//   * getUserbyID      GET  id                               → single user
//   * deleteUser       POST id                               → {status:'success'}
//   * toggleUserStatus POST id, status('active'|'disabled')  → {status:'success'}

import 'dart:convert';

import '../api_client.dart';
import '../models/user_admin_models.dart';

class UserAdminResult {
  UserAdminResult({required this.ok, this.message});
  final bool ok;
  final String? message;
}

class UserAdminService {
  UserAdminService(this._api);
  final ApiClient _api;

  /// Fetch a page of users. The backend paginates; pull a large page so the
  /// mobile list stays simple. Returns an empty list on any failure so the UI
  /// still renders. Handles both a wrapped `{data:[...]}` and a bare array.
  Future<List<AdminUser>> list({int page = 1, int limit = 100}) async {
    try {
      final res = await _api.get('users', {
        'page': '$page',
        'limit': '$limit',
      });
      final raw = res['data'] ?? res;
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => AdminUser.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<UserAdminResult> add({
    required String fullName,
    required String username,
    required String email,
    required String password,
    required String role,
    required Map<String, bool> permissions,
  }) async {
    return _mutate('addUsers', {
      'userfullname': fullName.trim(),
      'username': username.trim(),
      'user_email': email.trim(),
      'useremail': email.trim(),
      'password': password,
      'role': role,
      'permissions': _encodePermissions(permissions),
    });
  }

  Future<UserAdminResult> update({
    required int id,
    required String fullName,
    required String email,
    required String role,
    required Map<String, bool> permissions,
  }) async {
    return _mutate('updateUsers', {
      'user_id': '$id',
      'id': '$id',
      'userfullname': fullName.trim(),
      'user_email': email.trim(),
      'useremail': email.trim(),
      'role': role,
      'permissions': _encodePermissions(permissions),
    });
  }

  Future<UserAdminResult> delete(int id) =>
      _mutate('deleteUser', {'id': '$id'});

  /// Generate a shareable 2-hour registration link for [role]. Returns the
  /// public URL, or null on failure.
  Future<String?> generateInvite(String role) async {
    try {
      final res =
          await _api.post('generateRegistrationInvite', body: {'role': role});
      if (res['status'] == 'success' || res['success'] == true) {
        final url = res['public_url']?.toString() ?? '';
        return url.isEmpty ? null : url;
      }
    } catch (_) {}
    return null;
  }

  /// Enable/disable an account. Backend expects 'active' or 'disabled'.
  Future<UserAdminResult> toggleStatus(int id, bool active) => _mutate(
        'toggleUserStatus',
        {'id': '$id', 'status': active ? 'active' : 'disabled'},
      );

  // Encode the feature-flag map to a JSON string of 1/0 values, as the backend
  // stores and diffs (e.g. {"dashboard":1,"ticket":0,...}).
  String _encodePermissions(Map<String, bool> permissions) {
    final map = <String, int>{
      for (final k in kUserPermissionKeys) k: (permissions[k] ?? false) ? 1 : 0,
    };
    return jsonEncode(map);
  }

  Future<UserAdminResult> _mutate(
      String action, Map<String, String> body) async {
    try {
      final res = await _api.post(action, body: body);
      final ok = res['success'] == true || res['status'] == 'success';
      return UserAdminResult(ok: ok, message: res['message']?.toString());
    } catch (e) {
      return UserAdminResult(ok: false, message: 'Network error');
    }
  }
}
