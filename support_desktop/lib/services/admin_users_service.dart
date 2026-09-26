import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../api_client.dart' show ApiClient;

class AdminUsersPermsResult {
  AdminUsersPermsResult({
    required this.ok,
    required this.message,
    required this.field,
    required this.permissions,
    required this.json,
    required this.modulesOn,
    required this.modulesTotal,
  });
  final bool ok;
  final String message;
  final String field;
  final Map<String, dynamic> permissions;
  final String json;
  final int modulesOn;
  final int modulesTotal;
}

class AdminUsersApi {
  AdminUsersApi(this.api);
  final ApiClient api;

  static String s(Map m, String k) => (m[k] ?? '').toString();

  Future<List<Map<String, dynamic>>> users() async {
    final res = await api.get('users', {'limit': '250'});
    return _rows(res['data']);
  }

  Future<({List<Map<String, dynamic>> items, int total})> usersPage({
    required int page,
    required int limit,
    required String search,
  }) async {
    final res = await api.get('users', {
      'page': '$page',
      'limit': '$limit',
      'search': search,
    });
    return (
      items: _rows(res['data']),
      total: int.tryParse(s(res, 'totalRecords')) ?? 0,
    );
  }

  Future<List<Map<String, dynamic>>> branchOptions() async {
    try {
      final res = await api.get('branches.options');
      return _rows(res['data']);
    } catch (_) {
      return const [];
    }
  }

  Future<List<Map<String, dynamic>>> roles() async {
    try {
      final res = await api.get('roles.list');
      if (res['status'] == 'success') return _rows(res['data']);
    } catch (_) {}
    return const [];
  }

  Future<Map<String, dynamic>> userById(String id) =>
      api.get('getUserbyID', {'id': id});

  Future<AdminUsersPermsResult> perms(
    String op, {
    Map<String, dynamic> permissions = const {},
    String? key,
    bool? value,
    String? role,
    bool modalSet = false,
    Map<String, String> form = const {},
  }) async {
    final res = await api.post(
      'desktopUsersPerms',
      body: {
        'op': op,
        'permissions': jsonEncode(permissions),
        'key': ?key,
        if (value != null) 'value': value ? '1' : '0',
        'role': ?role,
        if (modalSet) 'set': 'modal',
        ...form,
      },
    );
    final p = res['permissions'] is Map
        ? Map<String, dynamic>.from(res['permissions'] as Map)
        : <String, dynamic>{};
    return AdminUsersPermsResult(
      ok: res['status'] == 'success',
      message: s(res, 'message'),
      field: s(res, 'field'),
      permissions: p,
      json: s(res, 'permissions_json'),
      modulesOn: int.tryParse(s(res, 'modules_on')) ?? 0,
      modulesTotal: int.tryParse(s(res, 'modules_total')) ?? 0,
    );
  }

  Future<Map<String, dynamic>> addUser(Map<String, String> body) =>
      api.post('addUsers', body: body);

  Future<Map<String, dynamic>> updateUser(Map<String, String> body) =>
      api.post('updateUsers', body: body);

  Future<Map<String, dynamic>> toggleStatus(String id, String status) =>
      api.post('toggleUserStatus', body: {'id': id, 'status': status});

  Future<Map<String, dynamic>> deleteUser(String id) =>
      api.post('deleteUser', body: {'id': id});

  Future<Map<String, dynamic>> accessDirect(
    String id, {
    String? permissionsJson,
    String? role,
  }) {
    return api.post(
      'updateUserAccessDirect',
      body: {
        'id': id,
        'role': ?role,
        'permissions': ?permissionsJson,
      },
    );
  }

  Future<Map<String, dynamic>> assignRole(
    String id,
    String role,
    String permissionsJson,
  ) {
    return api.post(
      'assignUserRole',
      body: {'id': id, 'role': role, 'permissions': permissionsJson},
    );
  }

  Future<Map<String, dynamic>> publicLink(String id) =>
      api.post('generatePublicLink', body: {'user_id': id});

  Future<Map<String, dynamic>> invite({
    required String role,
    required bool employmentForm,
    required String branchId,
  }) {
    return api.post(
      'generateRegistrationInvite',
      body: {
        'role': role,
        'employment_form': employmentForm ? '1' : '0',
        'branch_id': branchId.isEmpty ? '0' : branchId,
      },
    );
  }

  Future<Map<String, dynamic>> emailInvite(String token, String email) =>
      api.post(
        'emailRegistrationInvite',
        body: {'token': token, 'email': email},
      );

  Future<Map<String, dynamic>> verifyAdmin(String password) =>
      api.post('verifyAdmin', body: {'password': password});

  Future<Map<String, dynamic>> importCsv({
    required String path,
    required bool dryRun,
    required String mode,
    required String permissions,
    required bool withPreferences,
  }) {
    return api.uploadFiles(
      'importUsersCsv',
      fields: {
        'dry_run': dryRun ? '1' : '0',
        'mode': mode,
        'permissions': permissions,
        'with_preferences': withPreferences ? '1' : '0',
      },
      filePaths: [path],
      fileField: 'file',
    );
  }

  Future<String> downloadCsv(Map<String, String> query) async {
    final url = api.actionUrl('exportUsersCsv', query);
    final res = await http.get(Uri.parse(url), headers: api.authHeaders());
    if (res.statusCode != 200) {
      String msg = 'HTTP ${res.statusCode}';
      try {
        final d = jsonDecode(res.body);
        if (d is Map && d['message'] != null) msg = '${d['message']}';
      } catch (_) {}
      throw HttpException(msg);
    }
    final cd = res.headers['content-disposition'] ?? '';
    final m = RegExp(r'filename="?([^";]+)"?').firstMatch(cd);
    final name = m?.group(1) ?? 'users-export.csv';
    Directory? dir;
    try {
      dir = await getDownloadsDirectory();
    } catch (_) {}
    dir ??= await getApplicationDocumentsDirectory();
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(res.bodyBytes);
    return file.path;
  }

  static List<Map<String, dynamic>> _rows(dynamic raw) {
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }
}
