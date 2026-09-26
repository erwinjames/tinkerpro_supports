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
    this._permissions,
  );

  static const _kBaseUrlKey = 'server_base_url';
  static const _kCookieKey = 'session_cookie';
  static const _kUserIdKey = 'session_user_id';
  static const _kUsernameKey = 'session_username';
  static const _kPermissionsKey = 'session_permissions';
  static const _kUserRoleKey = 'session_user_role';
  static const _kHiddenFeaturesKey = 'session_hidden_features';
  static const _kRememberedEmailKey = 'login_remembered_email';

  final SharedPreferences _prefs;
  String _baseUrl;
  String _cookie;
  int? _userId;
  String? _username;
  Map<String, bool> _permissions;

  static Future<ApiClient> load() async {
    final prefs = await SharedPreferences.getInstance();
    return ApiClient._(
      prefs,
      prefs.getString(_kBaseUrlKey) ?? _kDefaultBaseUrl,
      prefs.getString(_kCookieKey) ?? '',
      prefs.getInt(_kUserIdKey),
      prefs.getString(_kUsernameKey),
      _decodePermissions(prefs.getString(_kPermissionsKey)),
    );
  }

  static Map<String, bool> _decodePermissions(String? stored) {
    if (stored == null || stored.isEmpty) return <String, bool>{};
    try {
      final decoded = jsonDecode(stored);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v == true));
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

  bool hasPermission(String feature) => _permissions[feature] == true;

  Set<String> get hiddenFeatures =>
      (_prefs.getStringList(_kHiddenFeaturesKey) ?? const <String>[]).toSet();

  Future<void> setHiddenFeatures(Iterable<String> keys) async {
    final list = keys.where((k) => k.trim().isNotEmpty).toSet().toList()
      ..sort();
    if (list.isEmpty) {
      await _prefs.remove(_kHiddenFeaturesKey);
    } else {
      await _prefs.setStringList(_kHiddenFeaturesKey, list);
    }
  }

  bool canAccess(String feature, [String? permission]) {
    if (hiddenFeatures.contains(feature)) return false;
    if (permission == null) return true;
    return hasPermission(permission);
  }

  String get rememberedEmail => _prefs.getString(_kRememberedEmailKey) ?? '';

  Future<void> setRememberedEmail(String? email) async {
    final value = (email ?? '').trim();
    if (value.isEmpty) {
      await _prefs.remove(_kRememberedEmailKey);
    } else {
      await _prefs.setString(_kRememberedEmailKey, value);
    }
  }

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

  String get userRole => _prefs.getString(_kUserRoleKey) ?? '';

  bool get isSuperAdmin => userRole.trim().toLowerCase() == 'super_admin';

  bool get canManageEmployment {
    if (!hasSession) return false;
    if (hiddenFeatures.contains('employment')) return false;
    final role = userRole.trim().toLowerCase();
    if (role == 'super_admin') return true;
    if (!hasPermission('user')) return false;
    if (!_permissions.containsKey('employmentInfo')) return role == 'admin';
    return hasPermission('employmentInfo');
  }

  Future<void> setUserRole(String? role) async {
    final value = (role ?? '').trim();
    if (value.isEmpty) {
      await _prefs.remove(_kUserRoleKey);
    } else {
      await _prefs.setString(_kUserRoleKey, value);
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
    _kPermissionsKey,
    _kUserRoleKey,
    _kHiddenFeaturesKey,
    'notif_last_lead_id',
    'notif_last_customer_id',
  ];

  Future<void> clearSession() async {
    _cookie = '';
    _userId = null;
    _username = null;
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

  static Map<String, String> _parseCookieJar(String stored) {
    final jar = <String, String>{};
    for (final part in stored.split(';')) {
      final pair = part.trim();
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      jar[pair.substring(0, eq)] = pair.substring(eq + 1);
    }
    return jar;
  }

  Future<void> _absorbCookie(http.Response response) async {
    final setCookie = response.headers['set-cookie'];
    if (setCookie == null || setCookie.isEmpty) return;

    final jar = _parseCookieJar(_cookie);
    for (final raw in setCookie.split(RegExp(r',(?=\s*[A-Za-z0-9_\-]+=)'))) {
      final segments = raw.split(';');
      final pair = segments.first.trim();
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      final name = pair.substring(0, eq);
      final value = pair.substring(eq + 1);
      final expired =
          value.isEmpty ||
          value == 'deleted' ||
          segments.skip(1).any((a) {
            final attr = a.trim().toLowerCase();
            return attr == 'max-age=0' || attr.startsWith('max-age=-');
          });
      if (expired) {
        jar.remove(name);
      } else {
        jar[name] = value;
      }
    }

    final next = jar.entries.map((e) => '${e.key}=${e.value}').join('; ');
    if (next == _cookie) return;
    _cookie = next;
    if (next.isEmpty) {
      await _prefs.remove(_kCookieKey);
    } else {
      await _prefs.setString(_kCookieKey, next);
    }
  }

  Future<Map<String, dynamic>> get(
    String action, [
    Map<String, String>? query,
  ]) async {
    final response = await http.get(_uri(action, query), headers: _headers());
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

  Future<Map<String, dynamic>> postBytes(
    String action, {
    required List<int> bytes,
    Map<String, String>? query,
    String contentType = 'application/octet-stream',
  }) async {
    final response = await http.post(
      _uri(action, query),
      headers: {..._headers(), 'Content-Type': contentType},
      body: bytes,
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
    final uri = Uri.parse(
      '$_baseUrl/$cleanPath',
    ).replace(queryParameters: query);
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
      headers: {..._headers(), 'Content-Type': 'application/json'},
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
    final uri = Uri.parse(
      '$_baseUrl/$cleanPath',
    ).replace(queryParameters: query);
    return _sendMultipart(uri, fields: fields, files: files);
  }

  Future<Map<String, dynamic>> postPathMultipartFiles(
    String path, {
    Map<String, String>? query,
    Map<String, String>? fields,
    List<({String field, String path})> files = const [],
  }) async {
    final cleanPath = path.replaceAll(RegExp(r'^/+'), '');
    final uri = Uri.parse(
      '$_baseUrl/$cleanPath',
    ).replace(queryParameters: query);
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

  Uri pathUri(String path, [Map<String, String>? query]) {
    final cleanPath = path.replaceAll(RegExp(r'^/+'), '');
    return Uri.parse('$_baseUrl/$cleanPath').replace(queryParameters: query);
  }

  Future<http.Response> rawGet(Uri uri, {bool json = true}) async {
    final response = await http.get(
      uri,
      headers: json ? _headers() : authHeaders(),
    );
    await _absorbCookie(response);
    return response;
  }

  Future<http.Response> rawPostForm(Uri uri, Map<String, String> body) async {
    final response = await http.post(uri, headers: _headers(), body: body);
    await _absorbCookie(response);
    return response;
  }

  Future<http.Response> rawPostMultipart(
    Uri uri, {
    Map<String, String>? fields,
    List<({String field, String path})> files = const [],
  }) async {
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
    return response;
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
        request.files.add(
          await http.MultipartFile.fromPath(entry.key, entry.value),
        );
      }
    }
    final response = await _finishMultipart(request);
    await _absorbCookie(response);
    return _decode(response);
  }

  Future<http.Response> _finishMultipart(http.MultipartRequest request) async {
    final length = request.contentLength;
    final budget = Duration(seconds: 60 + (length / (32 * 1024)).ceil());
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
        _messageFromBody(response.body) ??
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

String? _messageFromBody(String body) {
  final trimmed = body.trim();
  if (trimmed.isEmpty) return null;
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is Map) {
      final message = decoded['message'];
      if (message is String && message.trim().isNotEmpty) {
        return message.trim();
      }
    }
  } catch (_) {}
  return null;
}
