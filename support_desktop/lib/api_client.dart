import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Default API base URL used on a fresh install (no server stored in prefs
/// yet). Points at the live server; override at build time with
///   flutter run --dart-define=TPS_BASE_URL=https://support.tinkerpro.io
/// A value the user enters on the connect screen always takes precedence.
const String _kDefaultBaseUrl = String.fromEnvironment(
  'TPS_BASE_URL',
  defaultValue: 'https://support.tinkerpro.io',
);

/// Thin wrapper around `api.php` on the TinkerPro Support backend.
///
/// The backend identifies authenticated users via the PHP session cookie, so
/// after every request we capture the Set-Cookie header and replay it on the
/// next one. The server URL and cookie persist across app launches.
class ApiClient {
  ApiClient._(
    this._prefs,
    this._baseUrl,
    this._cookie,
    this._userId,
    this._username,
  );

  static const _kBaseUrlKey = 'server_base_url';
  static const _kCookieKey = 'session_cookie';
  static const _kUserIdKey = 'session_user_id';
  static const _kUsernameKey = 'session_username';

  final SharedPreferences _prefs;
  String _baseUrl;
  String _cookie;
  int? _userId;
  String? _username;

  static Future<ApiClient> load() async {
    final prefs = await SharedPreferences.getInstance();
    return ApiClient._(
      prefs,
      prefs.getString(_kBaseUrlKey) ?? _kDefaultBaseUrl,
      prefs.getString(_kCookieKey) ?? '',
      prefs.getInt(_kUserIdKey),
      prefs.getString(_kUsernameKey),
    );
  }

  String get baseUrl => _baseUrl;
  bool get hasBaseUrl => _baseUrl.isNotEmpty;
  bool get hasSession => _cookie.isNotEmpty;

  /// Authenticated user id captured at login time. Survives app restarts
  /// alongside the cookie so the chat layer doesn't need an extra
  /// roundtrip to learn who's signed in.
  int? get userId => _userId;

  /// Authenticated username captured at login time — surfaced in the
  /// chat header so the active identity is unambiguous when an admin
  /// switches accounts on the device.
  String? get username => _username;

  Future<void> setBaseUrl(String value) async {
    _baseUrl = value.trim().replaceAll(RegExp(r'/+$'), '');
    await _prefs.setString(_kBaseUrlKey, _baseUrl);
  }

  /// Forget the configured server so the app returns to the server-config
  /// screen and the live default applies on next entry. Device-scoped, so
  /// deliberately kept out of [clearSession]. Pair with [clearSession] when
  /// switching servers, since a session cookie never crosses servers.
  Future<void> clearBaseUrl() async {
    _baseUrl = '';
    await _prefs.remove(_kBaseUrlKey);
  }

  /// Persist the authenticated user id. Called by AuthService.login after
  /// a successful login (and any other endpoint that reliably returns it).
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

  /// User-scoped SharedPreferences keys that must be wiped when an account
  /// changes. Anything device-scoped (e.g. `server_base_url`) is excluded.
  /// Centralised here so a future feature can register its keys without
  /// bug-hunting across the app for every "logout doesn't really logout"
  /// edge case.
  static const _kUserScopedKeys = <String>[
    _kCookieKey,
    _kUserIdKey,
    _kUsernameKey,
    'notif_last_lead_id',
    'notif_last_customer_id',
  ];

  /// Idempotent: wipe every per-user value from local state. Called on
  /// both logout *and* the first step of login, so a stale cookie /
  /// notification cursor / cached user id from a previous account can
  /// never bleed through into a new session.
  Future<void> clearSession() async {
    _cookie = '';
    _userId = null;
    _username = null;
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

  /// Cookie header for use by callers that need to fetch authed binary
  /// content outside of [get] / [post] (e.g. CachedNetworkImage for chat
  /// attachments). Empty map when no session is active.
  Map<String, String> authHeaders() {
    return _cookie.isEmpty ? const {} : <String, String>{'Cookie': _cookie};
  }

  /// Full GET URL for an `api.php?action=...` action. Handy for image / file
  /// loaders that need a `String` URL rather than a [Uri].
  String actionUrl(String action, [Map<String, String>? query]) {
    return _uri(action, query).toString();
  }

  Future<void> _absorbCookie(http.Response response) async {
    final setCookie = response.headers['set-cookie'];
    if (setCookie == null || setCookie.isEmpty) return;

    // The http package combines multiple Set-Cookie headers into one
    // comma-joined string. A successful PHP login emits MULTIPLE
    // `PHPSESSID=...` Set-Cookie entries:
    //   1. one from `session_start()` at the top of api.php (the
    //      pre-login, anonymous session id),
    //   2. one from `session_regenerate_id(true)` after auth succeeds
    //      (the new, logged-in session id),
    //   3. one from the explicit `setcookie(session_name(), ...)` in
    //      bindSession() with the remember-me lifetime.
    //
    // Per RFC 6265 the LAST one wins. Picking the first leaves us with
    // an anonymous cookie that the server will reject as Unauthorized.
    final allSessIds = RegExp(r'PHPSESSID=([^;,\s]+)')
        .allMatches(setCookie)
        .toList();
    if (allSessIds.isNotEmpty) {
      _cookie = 'PHPSESSID=${allSessIds.last.group(1)}';
      await _prefs.setString(_kCookieKey, _cookie);
      return;
    }

    // Legacy fallback — first name=value pair before any attribute.
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

  /// Multipart POST for endpoints that read `$_FILES` (e.g. file_upload).
  /// [fields] are plain form fields; each path in [filePaths] is attached
  /// under [fileField] (use a `name[]` field for PHP array uploads).
  Future<Map<String, dynamic>> uploadFiles(
    String action, {
    Map<String, String> fields = const {},
    required List<String> filePaths,
    String fileField = 'files[]',
  }) async {
    final req = http.MultipartRequest('POST', _uri(action));
    req.headers.addAll(_headers());
    req.fields.addAll(fields);
    for (final path in filePaths) {
      req.files.add(await http.MultipartFile.fromPath(fileField, path));
    }
    final response = await http.Response.fromStream(await req.send());
    await _absorbCookie(response);
    return _decode(response);
  }

  /// POST a JSON body for endpoints that read `php://input` (e.g.
  /// addHelpTopic) rather than `$_POST`.
  Future<Map<String, dynamic>> postJson(
    String action, {
    required Map<String, dynamic> body,
  }) async {
    final response = await http.post(
      _uri(action),
      headers: {..._headers(), 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    await _absorbCookie(response);
    return _decode(response);
  }

  /// POST to a non-`api.php` script (e.g. `task.php`, `projects.php`). The
  /// admin webapp exposes most of the task-feature endpoints as AJAX POSTs
  /// against those files (not via the api.php action dispatcher), so this
  /// is the entry point the Flutter TaskService uses for them. Same
  /// cookie auth + JSON decode as `post()`.
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

  /// GET a non-`api.php` script. Some admin endpoints (e.g. `task-poll.php`)
  /// live outside the action dispatcher; this is the GET counterpart to
  /// [postPath]. Same cookie auth + JSON decode.
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
