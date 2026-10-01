import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String _kDefaultBaseUrl = String.fromEnvironment(
  'TPS_BASE_URL',
  defaultValue: 'https://support.tinkerpro.com',
);

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

  final SharedPreferences _prefs;
  String _baseUrl;
  String _cookie;
  int? _userId;
  String? _username;
  Map<String, bool> _permissions;

  DateTime? _coolDownUntil;
  String _coolDownMessage = '';

  bool get coolingDown =>
      _coolDownUntil != null && DateTime.now().isBefore(_coolDownUntil!);

  Duration get coolDownLeft =>
      coolingDown ? _coolDownUntil!.difference(DateTime.now()) : Duration.zero;

  String get coolDownMessage => _coolDownMessage;

  void _guard() {
    if (coolingDown) {
      throw RateLimitedException(
        _coolDownMessage.isEmpty
            ? 'The server is busy. Please try again shortly.'
            : _coolDownMessage,
        coolDownLeft,
      );
    }
  }

  void _startCoolDown(int seconds, String message) {
    final s = seconds.clamp(1, 3600);
    final until = DateTime.now().add(Duration(seconds: s));
    if (_coolDownUntil == null || until.isAfter(_coolDownUntil!)) {
      _coolDownUntil = until;
    }
    _coolDownMessage = message;
  }

  static bool _isLoopback(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    return host == 'localhost' || host == '::1' || host.startsWith('127.');
  }

  static Future<ApiClient> load() async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, bool> perms = const {};
    final rawPerms = prefs.getString(_kPermissionsKey);
    if (rawPerms != null && rawPerms.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawPerms);
        if (decoded is Map) {
          perms = decoded.map((k, v) => MapEntry(k.toString(), v == true));
        }
      } catch (_) {}
    }
    var base = prefs.getString(_kBaseUrlKey) ?? _kDefaultBaseUrl;
    final moved = base.replaceFirst(
      '://support.tinkerpro.io',
      '://support.tinkerpro.com',
    );
    if (moved != base) {
      base = moved;
      await prefs.setString(_kBaseUrlKey, base);
    }
    if (kReleaseMode && _isLoopback(base) && !_isLoopback(_kDefaultBaseUrl)) {
      base = _kDefaultBaseUrl;
      perms = const {};
      await prefs.setString(_kBaseUrlKey, base);
      for (final k in [
        _kCookieKey,
        _kUserIdKey,
        _kUsernameKey,
        _kPermissionsKey,
      ]) {
        await prefs.remove(k);
      }
    }
    return ApiClient._(
      prefs,
      base,
      prefs.getString(_kCookieKey) ?? '',
      prefs.getInt(_kUserIdKey),
      prefs.getString(_kUsernameKey),
      perms,
    );
  }

  String get baseUrl => _baseUrl;
  bool get hasBaseUrl => _baseUrl.isNotEmpty;
  bool get hasSession => _cookie.isNotEmpty;

  int? get userId => _userId;

  String? get username => _username;

  Map<String, bool> get permissions => Map.unmodifiable(_permissions);

  bool hasPermission(String feature) => _permissions[feature] == true;

  Future<void> setPermissions(Map<String, bool> perms) async {
    _permissions = Map<String, bool>.from(perms);
    if (_permissions.isEmpty) {
      await _prefs.remove(_kPermissionsKey);
    } else {
      await _prefs.setString(_kPermissionsKey, jsonEncode(_permissions));
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

  static const _kUserScopedKeys = <String>[
    _kCookieKey,
    _kUserIdKey,
    _kUsernameKey,
    _kPermissionsKey,
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

  Future<void> _absorbCookie(http.Response response) async {
    final setCookie = response.headers['set-cookie'];
    if (setCookie == null || setCookie.isEmpty) return;

    final allSessIds = RegExp(
      r'PHPSESSID=([^;,\s]+)',
    ).allMatches(setCookie).toList();
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

  Future<Map<String, dynamic>> get(
    String action, [
    Map<String, String>? query,
  ]) async {
    _guard();
    final response = await http.get(_uri(action, query), headers: _headers());
    await _absorbCookie(response);
    return _decode(response);
  }

  Future<Map<String, dynamic>> post(
    String action, {
    Map<String, String>? body,
  }) async {
    _guard();
    final response = await http.post(
      _uri(action),
      headers: _headers(),
      body: body,
    );
    await _absorbCookie(response);
    return _decode(response);
  }

  Future<Map<String, dynamic>> uploadFiles(
    String action, {
    Map<String, String> fields = const {},
    required List<String> filePaths,
    String fileField = 'files[]',
  }) async {
    _guard();
    final req = http.MultipartRequest('POST', _uri(action));
    req.headers.addAll(_headers());
    req.fields.addAll(fields);
    for (final path in filePaths) {
      req.files.add(await http.MultipartFile.fromPath(fileField, path));
    }
    _guard();
    final response = await http.Response.fromStream(await req.send());
    await _absorbCookie(response);
    return _decode(response);
  }

  Future<Map<String, dynamic>> postPathMultipart(
    String path, {
    Map<String, String>? query,
    Map<String, String> fields = const {},
    Map<String, String> files = const {},
  }) async {
    final cleanPath = path.replaceAll(RegExp(r'^/+'), '');
    final uri = Uri.parse(
      '$_baseUrl/$cleanPath',
    ).replace(queryParameters: query);
    _guard();
    final req = http.MultipartRequest('POST', uri);
    req.headers.addAll(_headers());
    req.fields.addAll(fields);
    for (final e in files.entries) {
      if (e.value.isEmpty) continue;
      req.files.add(await http.MultipartFile.fromPath(e.key, e.value));
    }
    _guard();
    final response = await http.Response.fromStream(await req.send());
    await _absorbCookie(response);
    return _decode(response);
  }

  Future<Map<String, dynamic>> postPathMultipartFiles(
    String path, {
    Map<String, String>? query,
    Map<String, String> fields = const {},
    List<({String field, String path})> files = const [],
  }) async {
    final cleanPath = path.replaceAll(RegExp(r'^/+'), '');
    final uri = Uri.parse(
      '$_baseUrl/$cleanPath',
    ).replace(queryParameters: query);
    _guard();
    final req = http.MultipartRequest('POST', uri);
    req.headers.addAll(_headers());
    req.fields.addAll(fields);
    for (final f in files) {
      if (f.path.isEmpty) continue;
      req.files.add(await http.MultipartFile.fromPath(f.field, f.path));
    }
    _guard();
    final response = await http.Response.fromStream(await req.send());
    await _absorbCookie(response);
    return _decode(response);
  }

  Future<Map<String, dynamic>> postJson(
    String action, {
    required Map<String, dynamic> body,
  }) async {
    _guard();
    final response = await http.post(
      _uri(action),
      headers: {..._headers(), 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    await _absorbCookie(response);
    return _decode(response);
  }

  Future<Map<String, dynamic>> postPath(
    String path, {
    Map<String, String>? body,
  }) async {
    final cleanPath = path.replaceAll(RegExp(r'^/+'), '');
    _guard();
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
    _guard();
    final response = await http.get(uri, headers: _headers());
    await _absorbCookie(response);
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode == 429 || response.statusCode == 503) {
      Map<String, dynamic> body = const {};
      try {
        final d = jsonDecode(response.body.trim());
        if (d is Map<String, dynamic>) body = d;
      } catch (_) {}
      final header = int.tryParse(response.headers['retry-after'] ?? '');
      final fromBody = int.tryParse(
        '${body['retry_after'] ?? body['lockout_seconds'] ?? ''}',
      );
      final wait = header ?? fromBody ?? 30;
      final msg =
          body['message']?.toString() ??
          'The server is busy. Please try again shortly.';
      final isLogin =
          response.request?.url.queryParameters['action'] == 'login';
      if (!isLogin) _startCoolDown(wait, msg);
      return {
        ...body,
        'success': false,
        'message': msg,
        'retry_after': wait,
        'rate_limited': true,
      };
    }
    if (response.statusCode == 401) {
      try {
        final d = jsonDecode(response.body.trim());
        if (d is Map<String, dynamic> && d['session_lost'] == true) return d;
      } catch (_) {}
    }
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

class RateLimitedException implements Exception {
  RateLimitedException(this.message, this.retryAfter);
  final String message;
  final Duration retryAfter;
  @override
  String toString() => message;
}

class HttpException implements Exception {
  HttpException(this.message);
  final String message;
  @override
  String toString() => message;
}
