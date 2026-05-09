import 'package:shared_preferences/shared_preferences.dart';

/// Tiny key/value layer for the customer app. The actual auth token (PHP
/// session id) lives in the cookie jar managed by [ApiClient]; this is for
/// non-secret UX state — last entered TIN, last picked branch, the active
/// customer id we hydrate on launch.
class SessionStore {
  SessionStore._(this._prefs);
  final SharedPreferences _prefs;

  static const _kLastTin = 'last_tin';
  static const _kLastBranch = 'last_branch_code';
  static const _kCustomerId = 'active_customer_id';
  static const _kHiddenMsgIds = 'hidden_message_ids';
  static const _kRememberMe = 'remember_me';

  static Future<SessionStore> create() async {
    final prefs = await SharedPreferences.getInstance();
    return SessionStore._(prefs);
  }

  String? get lastTin => _prefs.getString(_kLastTin);
  Future<void> setLastTin(String? v) async {
    if (v == null || v.isEmpty) {
      await _prefs.remove(_kLastTin);
    } else {
      await _prefs.setString(_kLastTin, v);
    }
  }

  String? get lastBranch => _prefs.getString(_kLastBranch);
  Future<void> setLastBranch(String? v) async {
    if (v == null || v.isEmpty) {
      await _prefs.remove(_kLastBranch);
    } else {
      await _prefs.setString(_kLastBranch, v);
    }
  }

  int? get activeCustomerId => _prefs.getInt(_kCustomerId);
  Future<void> setActiveCustomerId(int? v) async {
    if (v == null || v <= 0) {
      await _prefs.remove(_kCustomerId);
    } else {
      await _prefs.setInt(_kCustomerId, v);
    }
  }

  /// Whether to auto-restore the portal session on next app launch.
  /// Default is true — most customers want one-tap access. Toggling it
  /// off at login means the next launch wipes the cookie jar and lands
  /// back on the TIN form.
  bool get rememberMe {
    // Default to true so existing installs (no key set yet) keep their
    // current "stay signed in" behavior.
    return _prefs.getBool(_kRememberMe) ?? true;
  }

  Future<void> setRememberMe(bool v) async {
    await _prefs.setBool(_kRememberMe, v);
  }

  Future<void> clearAll() async {
    await _prefs.remove(_kCustomerId);
    // Keep last TIN/branch — convenience for next login.
  }

  /// Per-device "Delete for me" set. Server-side messages stay intact;
  /// the customer just doesn't see these in their chat thread on this
  /// device. Stored as a comma-separated string so we don't need to
  /// pull in JSON encoding for two ints.
  Set<int> get hiddenMessageIds {
    final raw = _prefs.getString(_kHiddenMsgIds) ?? '';
    if (raw.isEmpty) return <int>{};
    return raw
        .split(',')
        .map((s) => int.tryParse(s.trim()) ?? 0)
        .where((n) => n > 0)
        .toSet();
  }

  Future<void> hideMessageId(int id) async {
    if (id <= 0) return;
    final cur = hiddenMessageIds..add(id);
    await _prefs.setString(_kHiddenMsgIds, cur.join(','));
  }

  Future<void> unhideMessageId(int id) async {
    if (id <= 0) return;
    final cur = hiddenMessageIds..remove(id);
    if (cur.isEmpty) {
      await _prefs.remove(_kHiddenMsgIds);
    } else {
      await _prefs.setString(_kHiddenMsgIds, cur.join(','));
    }
  }
}
