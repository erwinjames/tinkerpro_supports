/// Persistent theme-mode toggle. Backed by SharedPreferences so the
/// user's choice survives app restarts. The single instance is exposed
/// as a [ValueNotifier] so MaterialApp can rebuild on change.
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemePrefs extends ValueNotifier<ThemeMode> {
  ThemePrefs._(this._prefs, ThemeMode initial) : super(initial);

  static const _kKey = 'theme_mode';
  final SharedPreferences _prefs;

  /// Load the persisted mode; defaults to system (which honors the OS
  /// dark/light setting). Falls back to dark if anything unparseable.
  static Future<ThemePrefs> load(SharedPreferences prefs) async {
    final raw = prefs.getString(_kKey) ?? 'system';
    return ThemePrefs._(prefs, _parse(raw));
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode == value) return;
    value = mode;
    await _prefs.setString(_kKey, _serialize(mode));
  }

  static ThemeMode _parse(String s) {
    switch (s) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String _serialize(ThemeMode m) {
    switch (m) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}
