import 'dart:convert';

import '../api_client.dart';
import '../models/user_admin_models.dart';

class UserAdminResult {
  UserAdminResult({required this.ok, this.message, this.slug});
  final bool ok;
  final String? message;
  final String? slug;
}

class UserAdminService {
  UserAdminService(this._api);
  final ApiClient _api;

  Future<List<AdminUser>> list({int page = 1, int limit = 100}) async {
    try {
      final res = await _api.get('users', {'page': '$page', 'limit': '$limit'});
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
    int? branchId,
  }) async {
    return _mutate('addUsers', {
      'userfullname': fullName.trim(),
      'username': username.trim(),
      'user_email': email.trim(),
      'useremail': email.trim(),
      'password': password,
      'role': role,
      'permissions': _encodePermissions(permissions),
      'email_verified': '1',
      if (branchId != null) 'branch_id': '$branchId',
    });
  }

  Future<UserAdminResult> update({
    required int id,
    required String fullName,
    required String email,
    required String role,
    required Map<String, bool> permissions,
    int? branchId,
  }) async {
    return _mutate('updateUsers', {
      'user_id': '$id',
      'id': '$id',
      'userfullname': fullName.trim(),
      'user_email': email.trim(),
      'useremail': email.trim(),
      'role': role,
      'permissions': _encodePermissions(permissions),
      if (branchId != null) 'branch_id': '$branchId',
    });
  }

  Future<List<RoleOption>> rolesList() async {
    try {
      final res = await _api.get('roles.list');
      if (res['status'] != 'success') return const [];
      final raw = res['data'];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => RoleOption.fromJson(Map<String, dynamic>.from(e)))
            .where((r) => r.slug.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<Map<String, Map<String, bool>>> roleDefaults() async {
    try {
      final res = await _api.get('getRoleDefaults');
      if (res['status'] == 'success') {
        return parseRoleDefaults(res['role_defaults']);
      }
    } catch (_) {}
    return const {};
  }

  Future<UserAdminResult> assignRole(
    int id,
    String role,
    Map<String, bool> permissions,
  ) => _mutate('assignUserRole', {
    'id': '$id',
    'role': role,
    'permissions': _encodePermissions(permissions),
  });

  Future<UserAdminResult> saveRoleDefaults(
    String role,
    Map<String, bool> permissions,
  ) => _mutate('saveRoleDefaults', {
    'role': role,
    'permissions': _encodePermissions(permissions),
  });

  Future<UserAdminResult> syncRoleDefaultsToUsers(String role) =>
      _mutate('syncRoleDefaultsToUsers', {'role': role});

  Future<UserAdminResult> createRole({
    required String label,
    required String description,
    required Map<String, bool> permissions,
  }) async {
    try {
      final res = await _api.post(
        'roles.create',
        body: {
          'label': label.trim(),
          'description': description.trim(),
          'permissions': _encodePermissions(permissions),
        },
      );
      final ok = res['status'] == 'success';
      return UserAdminResult(
        ok: ok,
        message: res['message']?.toString(),
        slug: res['slug']?.toString(),
      );
    } catch (_) {
      return UserAdminResult(ok: false, message: 'Network error');
    }
  }

  Future<UserAdminResult> deleteRole(String slug) =>
      _mutate('roles.delete', {'slug': slug});

  Future<List<Branch>> branches({String search = ''}) async {
    try {
      final res = await _api.get('branches.list', {
        if (search.trim().isNotEmpty) 'search': search.trim(),
      });
      if (res['status'] != 'success') return const [];
      final raw = res['data'];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => Branch.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<List<Branch>> branchOptions() async {
    try {
      final res = await _api.get('branches.options');
      final raw = res['data'];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => Branch.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<UserAdminResult> saveBranch({
    int id = 0,
    required String name,
    required String code,
    String address = '',
    String contactNumber = '',
    String status = 'active',
    bool isMain = false,
  }) => _mutate('branches.save', {
    'id': '$id',
    'name': name.trim(),
    'code': code.trim().toUpperCase(),
    'address': address.trim(),
    'contact_number': contactNumber.trim(),
    'status': status,
    'is_main': isMain ? '1' : '0',
  });

  Future<UserAdminResult> deleteBranch(int id) =>
      _mutate('branches.delete', {'id': '$id'});

  Future<UserAdminResult> delete(int id) =>
      _mutate('deleteUser', {'id': '$id'});

  Future<String?> generateInvite(String role) async {
    try {
      final res = await _api.post(
        'generateRegistrationInvite',
        body: {'role': role},
      );
      if (res['status'] == 'success' || res['success'] == true) {
        final url = res['public_url']?.toString() ?? '';
        return url.isEmpty ? null : url;
      }
    } catch (_) {}
    return null;
  }

  Future<UserAdminResult> toggleStatus(int id, bool active) => _mutate(
    'toggleUserStatus',
    {'id': '$id', 'status': active ? 'active' : 'disabled'},
  );

  String _encodePermissions(Map<String, bool> permissions) {
    final normalized = normalizePermissions(permissions);
    final map = <String, int>{
      for (final k in kUserPermissionKeys) k: (normalized[k] ?? false) ? 1 : 0,
    };
    return jsonEncode(map);
  }

  Future<UserAdminResult> _mutate(
    String action,
    Map<String, String> body,
  ) async {
    try {
      final res = await _api.post(action, body: body);
      final ok = res['success'] == true || res['status'] == 'success';
      return UserAdminResult(ok: ok, message: res['message']?.toString());
    } catch (e) {
      return UserAdminResult(ok: false, message: 'Network error');
    }
  }
}
