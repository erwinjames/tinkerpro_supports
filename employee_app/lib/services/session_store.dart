import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'ticket_service.dart' show ShopInfo;

/// Tiny wrapper around SharedPreferences for the values the employee app
/// needs to remember across launches: the store name they entered on
/// first launch, and the resolved chat identity returned by
/// `chat.employeeStart` so we can skip the round-trip on warm starts.
///
/// PHPSESSID itself is held by Dio's PersistCookieJar, which writes to
/// the app's documents dir — that's the cookie that makes a re-installed
/// app resume the same session as long as the OS preserves the data dir.
/// On a true wipe (uninstall → reinstall), we fall back to calling
/// `chat.employeeStart` again with the stored store name; the server
/// looks the user up by name and returns the same ids.
class SessionStore {
  SessionStore._(this._prefs);
  final SharedPreferences _prefs;

  static const _kStoreName = 'employee_store_name';
  static const _kFullName  = 'employee_full_name';
  static const _kUserId    = 'employee_user_id';
  static const _kConvId    = 'employee_conv_id';
  static const _kPosHost          = 'pos_db_host';
  static const _kPosPort          = 'pos_db_port';
  static const _kPosManualHost    = 'pos_db_manual_host';
  static const _kPosManualPort    = 'pos_db_manual_port';
  static const _kPosStandalone    = 'pos_standalone';
  static const _kDeviceId         = 'lan_device_id';
  static const _kShopJson         = 'pos_shop_info_json';
  static const _kShopAt           = 'pos_shop_info_saved_at';
  static const _kHelpJson         = 'help_topics_json';
  static const _kHelpAt           = 'help_topics_saved_at';
  static const _kPendingAnchor    = 'pending_ticket_anchor_msg_id';
  static const _kPendingTicketId  = 'pending_ticket_id';
  static const _kTinkerChatApiKey = 'tinker_chat_api_key';
  static const _kServerBaseUrl    = 'server_base_url';
  static const _kHelpBaseUrl      = 'help_base_url';
  static const _kWsHost           = 'ws_host';
  static const _kWsPort           = 'ws_port';
  static const _kWsKey            = 'ws_key';
  static const _kWsTls            = 'ws_tls';
  static const _kWsPath           = 'ws_path';
  static const _kLastActiveAt     = 'last_active_at';

  static Future<SessionStore> open() async {
    final prefs = await SharedPreferences.getInstance();
    final s = SessionStore._(prefs);
    // Seed the manual POS target from the installer-written hint
    // (Windows-only, Terminal-mode installs). One-shot: only fires
    // when SharedPreferences has nothing yet, so a cashier who later
    // changes the target via in-app config keeps their choice on
    // subsequent launches.
    await s._seedFromInstallerHint();
    return s;
  }

  /// Look for `%PROGRAMDATA%\TinkerPro\pos_target.json` (written by
  /// the Inno installer for "Terminal" and "Standalone" modes) and
  /// copy `{host, port, mode}` into prefs if we don't already have a
  /// target. The installer runs elevated so it can write to
  /// ProgramData; the app runs as the cashier and only needs read
  /// access. Failure here is silent — discovery still works as a
  /// fallback.
  ///
  /// `mode == "standalone"` also flips [isPosStandalone] on, which
  /// tells the ticket form to only look at the local XAMPP and, if
  /// there isn't one, ask for the shop name instead of a LAN host.
  Future<void> _seedFromInstallerHint() async {
    if (!Platform.isWindows) return;
    if (hasPosManualTarget) return;
    final programData =
        Platform.environment['PROGRAMDATA'] ?? r'C:\ProgramData';
    final hintFile =
        File('$programData${Platform.pathSeparator}TinkerPro'
            '${Platform.pathSeparator}pos_target.json');
    try {
      if (!await hintFile.exists()) return;
      final raw = await hintFile.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final mode = (decoded['mode'] ?? '').toString().trim().toLowerCase();
      if (mode == 'standalone') {
        await setPosStandalone(true);
      }
      final host = (decoded['host'] ?? '').toString().trim();
      if (host.isEmpty) return;
      final port = int.tryParse((decoded['port'] ?? '3306').toString());
      await setPosManualTarget(host, port);
    } catch (_) {
      // Malformed hint, permission denied, etc. — just fall back to
      // discovery on first ticket open.
    }
  }

  String? get storeName => _prefs.getString(_kStoreName);

  /// The cashier's own full name, captured on the setup screen alongside
  /// the store name. The store name is the account/inbox identity + resume
  /// key; this is the person operating the terminal, stamped on tickets so
  /// support knows who filed each one.
  String? get employeeFullName => _prefs.getString(_kFullName);

  int? get userId => _prefs.getInt(_kUserId);
  int? get convId => _prefs.getInt(_kConvId);

  bool get isConfigured => (storeName ?? '').trim().isNotEmpty;

  /// TinkerPro server origin this device talks to. On desktop this stays
  /// null and the compile-time `TPS_BASE_URL` default is used. On the
  /// mobile APK it's populated from the scanned sync QR so the phone hits
  /// the same server the desktop is logged into. Null → fall back to the
  /// baked-in default.
  String? get serverBaseUrl {
    final v = _prefs.getString(_kServerBaseUrl);
    return (v == null || v.trim().isEmpty) ? null : v.trim();
  }

  Future<void> saveServerBaseUrl(String? url) async {
    if (url == null || url.trim().isEmpty) {
      await _prefs.remove(_kServerBaseUrl);
    } else {
      await _prefs.setString(_kServerBaseUrl, url.trim());
    }
  }

  /// Help Center origin carried in the sync QR (optional).
  String? get helpBaseUrl {
    final v = _prefs.getString(_kHelpBaseUrl);
    return (v == null || v.trim().isEmpty) ? null : v.trim();
  }

  Future<void> saveHelpBaseUrl(String? url) async {
    if (url == null || url.trim().isEmpty) {
      await _prefs.remove(_kHelpBaseUrl);
    } else {
      await _prefs.setString(_kHelpBaseUrl, url.trim());
    }
  }

  /// Realtime (Soketi) connection carried in the sync QR from the desktop.
  /// Lets the phone reach the same WebSocket endpoint the desktop uses, so
  /// live ticket/chat/call events arrive without restarting the app. Null
  /// host → fall back to the compile-time default (derived from the API URL).
  String? get wsHost {
    final v = _prefs.getString(_kWsHost);
    return (v == null || v.trim().isEmpty) ? null : v.trim();
  }

  int get wsPort => _prefs.getInt(_kWsPort) ?? 0;
  String get wsKey => _prefs.getString(_kWsKey) ?? '';
  bool get wsTls => _prefs.getBool(_kWsTls) ?? false;
  String get wsPath => _prefs.getString(_kWsPath) ?? '';

  bool get hasWsConfig => (wsHost ?? '').isNotEmpty && wsPort > 0;

  /// Wall-clock of the last user activity / foreground use. Drives the
  /// mobile inactivity timeout — when the app has been idle/away longer than
  /// the limit, the session is ended and the user has to re-sync.
  DateTime? get lastActiveAt {
    final ms = _prefs.getInt(_kLastActiveAt);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> setLastActiveAt(DateTime t) =>
      _prefs.setInt(_kLastActiveAt, t.millisecondsSinceEpoch);

  Future<void> clearLastActiveAt() => _prefs.remove(_kLastActiveAt);

  Future<void> saveWsConfig({
    required String host,
    required int port,
    required String key,
    required bool tls,
    required String path,
  }) async {
    if (host.trim().isEmpty || port <= 0) {
      await _prefs.remove(_kWsHost);
      await _prefs.remove(_kWsPort);
      await _prefs.remove(_kWsKey);
      await _prefs.remove(_kWsTls);
      await _prefs.remove(_kWsPath);
      return;
    }
    await _prefs.setString(_kWsHost, host.trim());
    await _prefs.setInt(_kWsPort, port);
    await _prefs.setString(_kWsKey, key.trim());
    await _prefs.setBool(_kWsTls, tls);
    await _prefs.setString(_kWsPath, path.trim());
  }

  Future<void> saveStoreName(String name) =>
      _prefs.setString(_kStoreName, name.trim());

  Future<void> saveEmployeeFullName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return _prefs.remove(_kFullName);
    return _prefs.setString(_kFullName, trimmed);
  }

  /// Stable per-install id. Two terminals that sign in with the SAME store
  /// name share one identity (user id), so the LAN roster keys on this
  /// instead — otherwise they'd hide each other as "my own device".
  /// Generated + persisted on first read; survives restarts.
  String get deviceId {
    var id = _prefs.getString(_kDeviceId);
    if (id == null || id.isEmpty) {
      id = 'dev_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
          '_${Random().nextInt(0x7fffffff).toRadixString(36)}';
      _prefs.setString(_kDeviceId, id); // fire-and-forget persist
    }
    return id;
  }

  Future<void> saveIdentity({required int userId, required int convId}) async {
    await _prefs.setInt(_kUserId, userId);
    await _prefs.setInt(_kConvId, convId);
  }

  /// Last LAN host:port where we successfully reached the POS `tinkerpro`
  /// MariaDB. Cached so the ticket form doesn't re-scan the subnet on
  /// every open. Cleared on a connection failure so the next attempt
  /// re-discovers (e.g., the POS box got a new DHCP lease, or the
  /// merchant moved MariaDB to a non-default port).
  String? get posHost => _prefs.getString(_kPosHost);
  int? get posPort => _prefs.getInt(_kPosPort);

  Future<void> setPosTarget(String? host, int? port) async {
    if (host == null || host.isEmpty) {
      await _prefs.remove(_kPosHost);
      await _prefs.remove(_kPosPort);
      return;
    }
    await _prefs.setString(_kPosHost, host);
    if (port == null) {
      await _prefs.remove(_kPosPort);
    } else {
      await _prefs.setInt(_kPosPort, port);
    }
  }

  /// Admin-supplied POS host/port pinned at install time (or from the
  /// "Edit POS server" panel later). Distinct from [posHost] — that's the
  /// last auto-discovered target and gets cleared on failures; this one
  /// is intentional configuration and only changes when an admin sets or
  /// unsets it. When present, PosShopService skips discovery entirely
  /// and connects directly here.
  String? get posManualHost => _prefs.getString(_kPosManualHost);
  int? get posManualPort => _prefs.getInt(_kPosManualPort);

  bool get hasPosManualTarget {
    final h = posManualHost;
    return h != null && h.trim().isNotEmpty;
  }

  Future<void> setPosManualTarget(String? host, int? port) async {
    if (host == null || host.trim().isEmpty) {
      await _prefs.remove(_kPosManualHost);
      await _prefs.remove(_kPosManualPort);
      return;
    }
    await _prefs.setString(_kPosManualHost, host.trim());
    await _prefs.setInt(_kPosManualPort, port ?? 3306);
  }

  /// Standalone install (single PC = both POS server and register),
  /// flagged by the installer via the `mode` field in the hint file.
  /// When true the ticket form only probes the local XAMPP and, if it
  /// isn't there, asks for the shop name instead of a LAN host/port.
  bool get isPosStandalone => _prefs.getBool(_kPosStandalone) ?? false;

  Future<void> setPosStandalone(bool value) async {
    if (value) {
      await _prefs.setBool(_kPosStandalone, true);
    } else {
      await _prefs.remove(_kPosStandalone);
    }
  }

  /// Last ShopInfo we successfully read from the POS MariaDB. Persisted
  /// so the ticket form can render business name + VAT label instantly on
  /// every open and refresh in the background, instead of paying the full
  /// handshake-auth-select round trip (~5–7s with reverse-DNS stall) on
  /// each /ticket invocation.
  ShopInfo? get cachedShop {
    final raw = _prefs.getString(_kShopJson);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return ShopInfo.fromJson(decoded.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  /// Wall-clock time of the last successful POS read. Returned alongside
  /// [cachedShop] callers want to show "Last refreshed …" or apply a TTL
  /// in the future — current behavior is no TTL, refresh-on-open.
  DateTime? get cachedShopAt {
    final ms = _prefs.getInt(_kShopAt);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> saveCachedShop(ShopInfo info) async {
    await _prefs.setString(_kShopJson, jsonEncode(info.toJson()));
    await _prefs.setInt(_kShopAt, DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> clearCachedShop() async {
    await _prefs.remove(_kShopJson);
    await _prefs.remove(_kShopAt);
  }

  /// Raw JSON string of the last successful `help.public` response.
  /// HelpGuideScreen falls back to this on a cold launch with no
  /// network so the FAQ stays usable offline. Null when nothing has
  /// ever been fetched (fresh install before first connection).
  String? get cachedHelpJson => _prefs.getString(_kHelpJson);

  Future<void> saveCachedHelpJson(String raw) async {
    await _prefs.setString(_kHelpJson, raw);
    await _prefs.setInt(_kHelpAt, DateTime.now().millisecondsSinceEpoch);
  }

  /// Persisted reference to the most recently filed ticket that has
  /// not yet been accepted (or has been resolved). Drives the
  /// "resume waiting screen" behavior on app restart: if the user
  /// accidentally closes the employee app while sitting on the
  /// waiting card, the next launch jumps straight back into the
  /// scoped chat for that ticket instead of dumping them on the
  /// Help Guide. Cleared as soon as the chat screen detects the
  /// matching `accepted` event OR a `resolved` event for the same
  /// ticket id.
  int? get pendingTicketAnchorMessageId => _prefs.getInt(_kPendingAnchor);
  int? get pendingTicketId => _prefs.getInt(_kPendingTicketId);

  bool get hasPendingTicket =>
      pendingTicketAnchorMessageId != null && pendingTicketId != null;

  Future<void> savePendingTicket({
    required int anchorMessageId,
    required int ticketId,
  }) async {
    await _prefs.setInt(_kPendingAnchor, anchorMessageId);
    await _prefs.setInt(_kPendingTicketId, ticketId);
  }

  Future<void> clearPendingTicket() async {
    await _prefs.remove(_kPendingAnchor);
    await _prefs.remove(_kPendingTicketId);
  }

  /// Runtime override for the tinker-chat tenant API key. Takes
  /// precedence over the `--dart-define=TINKER_CHAT_API_KEY` baked
  /// into the binary, so a cashier (or roving tech) can paste in a
  /// freshly-issued `pk_live_…` key without rebuilding. Cleared by
  /// passing an empty string.
  String? get tinkerChatApiKey => _prefs.getString(_kTinkerChatApiKey);

  Future<void> setTinkerChatApiKey(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      await _prefs.remove(_kTinkerChatApiKey);
    } else {
      await _prefs.setString(_kTinkerChatApiKey, trimmed);
    }
  }

  /// Wipe everything — used by the "reset store" path if you ever want to
  /// rebind the desktop client to a different store. Not exposed in the
  /// MVP UI but kept for parity with debug paths.
  Future<void> reset() async {
    await _prefs.remove(_kStoreName);
    await _prefs.remove(_kFullName);
    await _prefs.remove(_kUserId);
    await _prefs.remove(_kConvId);
    await _prefs.remove(_kPosManualHost);
    await _prefs.remove(_kPosManualPort);
    await _prefs.remove(_kPosStandalone);
    await _prefs.remove(_kShopJson);
    await _prefs.remove(_kShopAt);
    await _prefs.remove(_kServerBaseUrl);
    await _prefs.remove(_kHelpBaseUrl);
    await _prefs.remove(_kWsHost);
    await _prefs.remove(_kWsPort);
    await _prefs.remove(_kWsKey);
    await _prefs.remove(_kWsTls);
    await _prefs.remove(_kWsPath);
    await _prefs.remove(_kLastActiveAt);
  }
}
