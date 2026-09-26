import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SavedLogin {
  const SavedLogin(this.email);
  final String email;
}

class SavedLogins {
  SavedLogins._();
  static final SavedLogins instance = SavedLogins._();

  static const _storage = FlutterSecureStorage();

  String _norm(String server) =>
      server.trim().replaceAll(RegExp(r'/+$'), '').toLowerCase();

  String _listKey(String server) => 'tp_saved_logins::${_norm(server)}';
  String _pwKey(String server, String email) =>
      'tp_saved_pw::${_norm(server)}::${email.trim().toLowerCase()}';
  String _promptKey(String server) => 'tp_login_save_prompted::${_norm(server)}';

  Future<List<SavedLogin>> list(String server) async {
    try {
      final raw = await _storage.read(key: _listKey(server));
      if (raw == null || raw.isEmpty) return const [];
      final data = jsonDecode(raw);
      if (data is! List) return const [];
      return [for (final e in data) SavedLogin(e.toString())];
    } catch (_) {
      return const [];
    }
  }

  Future<bool> isSaved(String server, String email) async {
    final all = await list(server);
    final e = email.trim().toLowerCase();
    return all.any((s) => s.email.toLowerCase() == e);
  }

  Future<String?> password(String server, String email) async {
    try {
      return await _storage.read(key: _pwKey(server, email));
    } catch (_) {
      return null;
    }
  }

  Future<bool> save(String server, String email, String password) async {
    try {
      final all = (await list(server)).map((s) => s.email).toList();
      final e = email.trim();
      all.removeWhere((x) => x.toLowerCase() == e.toLowerCase());
      all.insert(0, e);
      await _storage.write(key: _pwKey(server, e), value: password);
      await _storage.write(key: _listKey(server), value: jsonEncode(all));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> remove(String server, String email) async {
    try {
      final e = email.trim().toLowerCase();
      final all = (await list(server))
          .map((s) => s.email)
          .where((x) => x.toLowerCase() != e)
          .toList();
      await _storage.delete(key: _pwKey(server, email));
      await _storage.write(key: _listKey(server), value: jsonEncode(all));
    } catch (_) {}
  }

  Future<bool> wasPrompted(String server, String email) async {
    final prefs = await SharedPreferences.getInstance();
    final asked = prefs.getStringList(_promptKey(server)) ?? const [];
    return asked.contains(email.trim().toLowerCase());
  }

  Future<void> markPrompted(String server, String email) async {
    final prefs = await SharedPreferences.getInstance();
    final asked = List<String>.from(prefs.getStringList(_promptKey(server)) ?? const []);
    final e = email.trim().toLowerCase();
    if (!asked.contains(e)) asked.add(e);
    await prefs.setStringList(_promptKey(server), asked);
  }
}
