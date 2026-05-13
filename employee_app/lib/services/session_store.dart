import 'dart:convert';
import 'dart:io';

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
  static const _kUserId    = 'employee_user_id';
  static const _kConvId    = 'employee_conv_id';
  static const _kPosHost          = 'pos_db_host';
  static const _kPosPort          = 'pos_db_port';
  static const _kPosManualHost    = 'pos_db_manual_host';
  static const _kPosManualPort    = 'pos_db_manual_port';
  static const _kShopJson         = 'pos_shop_info_json';
  static const _kShopAt           = 'pos_shop_info_saved_at';
  static const _kHelpJson         = 'help_topics_json';
  static const _kHelpAt           = 'help_topics_saved_at';
  static const _kPendingAnchor    = 'pending_ticket_anchor_msg_id';
  static const _kPendingTicketId  = 'pending_ticket_id';

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
  /// the Inno installer when the admin picks "Terminal" mode) and
  /// copy `{host, port}` into the manual-target prefs if we don't
  /// already have one. The installer runs elevated so it can write
  /// to ProgramData; the app runs as the cashier and only needs
  /// read access. Failure here is silent — discovery still works
  /// as a fallback.
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
  int? get userId => _prefs.getInt(_kUserId);
  int? get convId => _prefs.getInt(_kConvId);

  bool get isConfigured => (storeName ?? '').trim().isNotEmpty;

  Future<void> saveStoreName(String name) =>
      _prefs.setString(_kStoreName, name.trim());

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

  /// Wipe everything — used by the "reset store" path if you ever want to
  /// rebind the desktop client to a different store. Not exposed in the
  /// MVP UI but kept for parity with debug paths.
  Future<void> reset() async {
    await _prefs.remove(_kStoreName);
    await _prefs.remove(_kUserId);
    await _prefs.remove(_kConvId);
    await _prefs.remove(_kPosManualHost);
    await _prefs.remove(_kPosManualPort);
    await _prefs.remove(_kShopJson);
    await _prefs.remove(_kShopAt);
  }
}
