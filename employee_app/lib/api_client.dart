import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Base URL of the TinkerPro server. Override at build time:
///   flutter run --dart-define=TPS_BASE_URL=https://tinkerpro.example.com
const String _kDefaultBaseUrl = String.fromEnvironment(
  'TPS_BASE_URL',
  defaultValue: 'http://10.0.2.2/tinkerpro_support',
);

/// Origin that hosts the admin Help Center content. The Help Guide fetches
/// `help.public` and resolves `/uploads/help/*` images against THIS base —
/// intentionally decoupled from [_kDefaultBaseUrl] so the FAQ can be curated
/// on a dedicated support site regardless of which TinkerPro server the
/// employee logs into. Override at build time:
///   flutter run --dart-define=TPS_HELP_BASE_URL=https://example.com/path
const String kHelpBaseUrl = String.fromEnvironment(
  'TPS_HELP_BASE_URL',
  defaultValue: 'https://support.tinkerpro.com.ph',
);

/// Single source of HTTP truth for the customer app.
///
/// • Cookie jar persists `PHPSESSID` across app launches → TIN+branch login
///   stays alive until the customer hits Logout (server-side
///   `logoutCustomerPortal` clears the session).
/// • All chat APIs that need to differentiate the staff session from the
///   portal session get `as_portal=1` automatically appended — see
///   [ApiClient.postChat] / [ApiClient.getChat]. The server's
///   chatResolveActor() helper then routes us through the customer-shadow-
///   user path so participation, signaling, and notifications all line up
///   with the right identity.
class ApiClient {
  ApiClient._(this._dio, this._jar);

  final Dio _dio;
  final PersistCookieJar _jar;

  String get baseUrl => _dio.options.baseUrl;

  /// Escape hatch for callers that need to issue a non-JSON request
  /// (e.g. binary downloads via [ApiClientImageBytes]). They get the
  /// fully-configured Dio instance — cookie jar is still applied.
  Dio get rawDio => _dio;

  static Future<ApiClient> create({String? overrideBaseUrl}) async {
    final dir = await getApplicationDocumentsDirectory();
    final jar = PersistCookieJar(
      ignoreExpires: true, // PHPSESSID is session-only without explicit Expires
      storage: FileStorage('${dir.path}/.cookies'),
    );
    final base = _normalizeBaseUrl(overrideBaseUrl ?? _kDefaultBaseUrl);
    final dio = Dio(BaseOptions(
      baseUrl: base,
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      followRedirects: true,
      validateStatus: (s) => s != null && s < 500,
    ));
    dio.interceptors.add(CookieManager(jar));
    if (kDebugMode) {
      dio.interceptors.add(LogInterceptor(
        request: false,
        requestBody: false,
        responseBody: false,
        responseHeader: false,
      ));
    }
    return ApiClient._(dio, jar);
  }

  /// Reset persistent state. Used on logout so the next launch starts on
  /// the login screen with no stale `PHPSESSID`.
  Future<void> wipeCookies() async {
    await _jar.deleteAll();
  }

  /// Inspect cookies for a given URL — handy when debugging session
  /// continuity from native code.
  Future<List<Cookie>> cookiesFor(String url) async {
    return _jar.loadForRequest(Uri.parse(url));
  }

  // ── Generic ────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> get(String action,
      {Map<String, dynamic>? params}) async {
    final res = await _dio.get<dynamic>(
      '/api.php',
      queryParameters: {'action': action, ...?params},
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> post(String action,
      {Map<String, dynamic>? body}) async {
    final fd = FormData.fromMap(body ?? const <String, dynamic>{});
    final res = await _dio.post<dynamic>(
      '/api.php',
      queryParameters: {'action': action},
      data: fd,
    );
    return _decode(res);
  }

  // ── Chat-guest helpers (auto-add as_guest=1) ──────────────────────────

  /// Same as [get] but stamps `as_guest=1` so chatResolveActor() routes
  /// us through the guest-shadow-user path. The employee desktop app
  /// authenticates as a guest user keyed on store name (created by
  /// `chat.employeeStart`), so every chat request needs this flag to
  /// avoid getting routed onto the wrong session if a stale staff/portal
  /// cookie ever ends up in the same jar.
  Future<Map<String, dynamic>> getChat(String action,
      {Map<String, dynamic>? params}) {
    return get(action, params: {'as_guest': '1', ...?params});
  }

  Future<Map<String, dynamic>> postChat(String action,
      {Map<String, dynamic>? body}) {
    return post(action, body: {'as_guest': '1', ...?body});
  }

  /// Multipart upload (for chat attachments). Returns the decoded JSON.
  Future<Map<String, dynamic>> uploadChat(
    String action, {
    required Map<String, dynamic> fields,
    required MultipartFile file,
    String fileField = 'file',
    void Function(int sent, int total)? onProgress,
  }) async {
    final fd = FormData.fromMap({
      'as_guest': '1',
      ...fields,
      fileField: file,
    });
    final res = await _dio.post<dynamic>(
      '/api.php',
      queryParameters: {'action': action},
      data: fd,
      onSendProgress: onProgress,
    );
    return _decode(res);
  }

  /// Generic multipart POST. Distinct from [uploadChat] in that it does
  /// NOT auto-stamp `as_guest=1` — endpoints like `create_ticket` don't
  /// route through chatResolveActor and should not receive that flag.
  Future<Map<String, dynamic>> upload(
    String action, {
    Map<String, dynamic> fields = const {},
    MultipartFile? file,
    String fileField = 'file',
    void Function(int sent, int total)? onProgress,
  }) async {
    final fd = FormData.fromMap({
      ...fields,
      if (file != null) fileField: file,
    });
    final res = await _dio.post<dynamic>(
      '/api.php',
      queryParameters: {'action': action},
      data: fd,
      onSendProgress: onProgress,
    );
    return _decode(res);
  }

  /// Build a URL pointing at an api.php action — used by image widgets that
  /// fetch with cookies via cached_network_image / a custom HTTP client.
  String actionUrl(String action, [Map<String, String>? params]) {
    final qs = <String>['action=${Uri.encodeQueryComponent(action)}'];
    params?.forEach((k, v) {
      qs.add('${Uri.encodeQueryComponent(k)}=${Uri.encodeQueryComponent(v)}');
    });
    return '$baseUrl/api.php?${qs.join('&')}';
  }

  Map<String, dynamic> _decode(Response<dynamic> res) {
    if (res.statusCode == 401 || res.statusCode == 403) {
      return {'success': false, 'message': 'Unauthorized'};
    }
    final data = res.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {'success': false, 'message': 'Bad response'};
  }

  /// Tolerate `--dart-define=TPS_BASE_URL=domain.com/path` (no scheme) by
  /// auto-prepending `https://`. Pure-host inputs like `192.168.1.5` are
  /// allowed for local dev — those default to `http://`. Without this
  /// guard Dio crashes at construction time with
  /// "Must be a valid URL on platforms other than Web".
  static String _normalizeBaseUrl(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return s;
    final hasScheme = s.startsWith(RegExp(r'[a-zA-Z][a-zA-Z0-9+\-.]*://'));
    if (!hasScheme) {
      // Local-style hosts (no dot or ending in .local) → http; anything
      // public → https. This matches how a person would type the URL.
      final hostPart = s.split(RegExp(r'[/?#]'))[0];
      final looksPublic = hostPart.contains('.') &&
          !hostPart.endsWith('.local') &&
          !hostPart.startsWith('localhost') &&
          !RegExp(r'^\d+\.\d+\.\d+\.\d+').hasMatch(hostPart);
      s = (looksPublic ? 'https://' : 'http://') + s;
    }
    // Trim trailing slash so `/api.php` joins cleanly.
    if (s.endsWith('/')) s = s.substring(0, s.length - 1);
    return s;
  }
}
