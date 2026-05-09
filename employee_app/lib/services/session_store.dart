import 'package:shared_preferences/shared_preferences.dart';

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
  static const _kPosHost   = 'pos_db_host';
  static const _kPosPort   = 'pos_db_port';

  static Future<SessionStore> open() async {
    final prefs = await SharedPreferences.getInstance();
    return SessionStore._(prefs);
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

  /// Wipe everything — used by the "reset store" path if you ever want to
  /// rebind the desktop client to a different store. Not exposed in the
  /// MVP UI but kept for parity with debug paths.
  Future<void> reset() async {
    await _prefs.remove(_kStoreName);
    await _prefs.remove(_kUserId);
    await _prefs.remove(_kConvId);
  }
}
