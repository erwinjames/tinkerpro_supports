import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String _kDefaultBaseUrl = String.fromEnvironment(
  'TPS_BASE_URL',
  defaultValue: 'https://support.tinkerpro.io',
);

class UploadTimeoutException implements Exception {
  UploadTimeoutException(this.limit);

  final Duration limit;

  @override
  String toString() =>
      'Upload stalled — no reply within ${limit.inMinutes} min.';
}

class ApiClient {
  ApiClient._(
    this._prefs,
    this._baseUrl,
    this._cookie,
    this._userId,
    this._username,
    this._userRole,
    this._permissions,
  );

  static const _kBaseUrlKey = 'server_base_url';
  static const _kCookieKey = 'session_cookie';
  static const _kUserIdKey = 'session_user_id';
  static const _kUsernameKey = 'session_username';
  static const _kUserRoleKey = 'session_user_role';
  static const _kPermissionsKey = 'session_permissions';

  final SharedPreferences _prefs;
  String _baseUrl;
  String _cookie;
  int? _userId;
  String? _username;
  String? _userRole;
  Map<String, bool> _permissions;

  static Future<ApiClient> load() async {
    final prefs = await SharedPreferences.getInstance();
    return ApiClient._(
      prefs,
      prefs.getString(_kBaseUrlKey) ?? _kDefaultBaseUrl,
      prefs.getString(_kCookieKey) ?? '',
      prefs.getInt(_kUserIdKey),
      prefs.getString(_kUsernameKey),
      prefs.getString(_kUserRoleKey),
      _decodePermissions(prefs.getString(_kPermissionsKey)),
    );
  }

  static Map<String, bool> _decodePermissions(String? stored) {
    if (stored == null || stored.isEmpty) return <String, bool>{};
    try {
      final decoded = jsonDecode(stored);
      if (decoded is Map) {
        return decoded
            .map((k, v) => MapEntry(k.toString(), v == true));
      }
    } catch (_) {}
    return <String, bool>{};
  }

  String get baseUrl => _baseUrl;
  bool get hasBaseUrl => _baseUrl.isNotEmpty;
  bool get hasSession => _cookie.isNotEmpty;

  int? get userId => _userId;

  String? get username => _username;

  Map<String, bool> get permissions => Map.unmodifiable(_permissions);

  /// Role slug from the server session (`super_admin`, `admin`, `user`, …).
  String? get userRole => _userRole;

  /// Mirrors the backend's PERM_FULL_ACCESS_ROLES, which is `['super_admin']`.
  /// Gates the few actions reserved for full-access accounts.
  bool get isSuperAdmin =>
      (_userRole ?? '').trim().toLowerCase() == 'super_admin';

  bool hasPermission(String feature) => _permissions[feature] == true;

  Future<void> setBaseUrl(String value) async {
    _baseUrl = value.trim().replaceAll(RegExp(r'/+$'), '');
    await _prefs.setString(_kBaseUrlKey, _baseUrl);
  }

  Future<void> clearBaseUrl() async {
    _baseUrl = '';
    await _prefs.remove(_kBaseUrlKey);
  }

  Future<void> setUserId(int? id) async {
    _userId = id;
    if (id == null) {
      await _prefs.remove(_kUserIdKey);
    } else {
      await _prefs.setInt(_kUserIdKey, id);
    }
  }

  Future<void> setUsername(String? name) async {
    _username = name;
    if (name == null || name.isEmpty) {
      await _prefs.remove(_kUsernameKey);
    } else {
      await _prefs.setString(_kUsernameKey, name);
    }
  }

  Future<void> setUserRole(String? role) async {
    _userRole = role;
    if (role == null || role.isEmpty) {
      await _prefs.remove(_kUserRoleKey);
    } else {
      await _prefs.setString(_kUserRoleKey, role);
    }
  }

  Future<void> setPermissions(Map<String, bool> perms) async {
    _permissions = Map<String, bool>.from(perms);
    if (_permissions.isEmpty) {
      await _prefs.remove(_kPermissionsKey);
    } else {
      await _prefs.setString(_kPermissionsKey, jsonEncode(_permissions));
    }
  }

  static const _kUserScopedKeys = <String>[
    _kCookieKey,
    _kUserIdKey,
    _kUsernameKey,
    _kUserRoleKey,
    _kPermissionsKey,
    'notif_last_lead_id',
    'notif_last_customer_id',
  ];

  Future<void> clearSession() async {
    _cookie = '';
    _userId = null;
    _username = null;
    _userRole = null;
    _permissions = <String, bool>{};
    for (final key in _kUserScopedKeys) {
      await _prefs.remove(key);
    }
  }

  Uri _uri(String action, [Map<String, String>? extraQuery]) {
    final params = <String, String>{'action': action, ...?extraQuery};
    return Uri.parse('$_baseUrl/api.php').replace(queryParameters: params);
  }

  Map<String, String> _headers() {
    return <String, String>{
      if (_cookie.isNotEmpty) 'Cookie': _cookie,
      'Accept': 'application/json',
    };
  }

  Map<String, String> authHeaders() {
    return _cookie.isEmpty ? const {} : <String, String>{'Cookie': _cookie};
  }

  String actionUrl(String action, [Map<String, String>? query]) {
    return _uri(action, query).toString();
  }

  Future<void> _absorbCookie(http.Response response) async {
    final setCookie = response.headers['set-cookie'];
    if (setCookie == null || setCookie.isEmpty) return;

    final allSessIds = RegExp(r'PHPSESSID=([^;,\s]+)')
        .allMatches(setCookie)
        .toList();
    if (allSessIds.isNotEmpty) {
      _cookie = 'PHPSESSID=${allSessIds.last.group(1)}';
      await _prefs.setString(_kCookieKey, _cookie);
      return;
    }

    final firstPair = setCookie.split(';').first.trim();
    if (firstPair.isEmpty) return;
    _cookie = firstPair;
    await _prefs.setString(_kCookieKey, _cookie);
  }

  Future<Map<String, dynamic>> get(String action,
      [Map<String, String>? query]) async {
    final response =
        await http.get(_uri(action, query), headers: _headers());
    await _absorbCookie(response);
    return _decode(response);
  }

  Future<Map<String, dynamic>> post(
    String action, {
    Map<String, String>? body,
  }) async {
    final response = await http.post(
      _uri(action),
      headers: _headers(),
      body: body,
    );
    await _absorbCookie(response);
    return _decode(response);
  }

  Future<Map<String, dynamic>> postPath(
    String path, {
    Map<String, String>? body,
  }) async {
    final cleanPath = path.replaceAll(RegExp(r'^/+'), '');
    final response = await http.post(
      Uri.parse('$_baseUrl/$cleanPath'),
      headers: _headers(),
      body: body,
    );
    await _absorbCookie(response);
    return _decode(response);
  }

  Future<Map<String, dynamic>> getPath(
    String path, [
    Map<String, String>? query,
  ]) async {
    final cleanPath = path.replaceAll(RegExp(r'^/+'), '');
    final uri = Uri.parse('$_baseUrl/$cleanPath')
        .replace(queryParameters: query);
    final response = await http.get(uri, headers: _headers());
    await _absorbCookie(response);
    return _decode(response);
  }

  Future<Map<String, dynamic>> postJson(
    String action, {
    Map<String, dynamic>? body,
  }) async {
    final response = await http.post(
      _uri(action),
      headers: {
        ..._headers(),
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body ?? const {}),
    );
    await _absorbCookie(response);
    return _decode(response);
  }

  Future<Map<String, dynamic>> postMultipart(
    String action, {
    Map<String, String>? fields,
    Map<String, String>? files,
  }) async {
    return _sendMultipart(_uri(action), fields: fields, files: files);
  }

  Future<Map<String, dynamic>> postPathMultipart(
    String path, {
    Map<String, String>? query,
    Map<String, String>? fields,
    Map<String, String>? files,
  }) async {
    final cleanPath = path.replaceAll(RegExp(r'^/+'), '');
    final uri = Uri.parse('$_baseUrl/$cleanPath')
        .replace(queryParameters: query);
    return _sendMultipart(uri, fields: fields, files: files);
  }

  Future<Map<String, dynamic>> postPathMultipartFiles(
    String path, {
    Map<String, String>? query,
    Map<String, String>? fields,
    List<({String field, String path})> files = const [],
  }) async {
    final cleanPath = path.replaceAll(RegExp(r'^/+'), '');
    final uri = Uri.parse('$_baseUrl/$cleanPath')
        .replace(queryParameters: query);
    final request = http.MultipartRequest('POST', uri);
    if (_cookie.isNotEmpty) request.headers['Cookie'] = _cookie;
    request.headers['Accept'] = 'application/json';
    if (fields != null) request.fields.addAll(fields);
    for (final f in files) {
      if (f.path.isEmpty) continue;
      request.files.add(await http.MultipartFile.fromPath(f.field, f.path));
    }
    final response = await _finishMultipart(request);
    await _absorbCookie(response);
    return _decode(response);
  }

  Future<Map<String, dynamic>> _sendMultipart(
    Uri uri, {
    Map<String, String>? fields,
    Map<String, String>? files,
  }) async {
    final request = http.MultipartRequest('POST', uri);
    if (_cookie.isNotEmpty) request.headers['Cookie'] = _cookie;
    request.headers['Accept'] = 'application/json';
    if (fields != null) request.fields.addAll(fields);
    if (files != null) {
      for (final entry in files.entries) {
        if (entry.value.isEmpty) continue;
        request.files
            .add(await http.MultipartFile.fromPath(entry.key, entry.value));
      }
    }
    final response = await _finishMultipart(request);
    await _absorbCookie(response);
    return _decode(response);
  }

  Future<http.Response> _finishMultipart(http.MultipartRequest request) async {
    final length = request.contentLength;
    final budget = Duration(
      seconds: 60 + (length / (32 * 1024)).ceil(),
    );
    final capped = budget > const Duration(minutes: 30)
        ? const Duration(minutes: 30)
        : budget;
    try {
      final streamed = await request.send().timeout(capped);
      return await http.Response.fromStream(streamed).timeout(capped);
    } on TimeoutException {
      throw UploadTimeoutException(capped);
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'HTTP ${response.statusCode} from ${response.request?.url}',
      );
    }
    final trimmed = response.body.trim();
    if (trimmed.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) return decoded;
      return <String, dynamic>{'data': decoded};
    } catch (_) {
      throw HttpException('Non-JSON response: $trimmed');
    }
  }
}

class HttpException implements Exception {
  HttpException(this.message);
  final String message;
  @override
  String toString() => message;
}
