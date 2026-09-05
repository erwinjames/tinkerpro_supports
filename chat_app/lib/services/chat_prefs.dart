import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:shared_preferences/shared_preferences.dart';

class ChatPrefs extends ChangeNotifier {
  ChatPrefs(this._prefs);
  final SharedPreferences _prefs;

  static const _kBubbleEnabledKey = 'chat_bubble_enabled';
  static const _kThemeKey = 'chat_theme_key';

  bool get bubbleEnabled => _prefs.getBool(_kBubbleEnabledKey) ?? true;

  String get themeKey =>
      _prefs.getString(_kThemeKey) ?? ChatTheme.defaultTheme.key;

  ChatTheme get theme => ChatTheme.byKey(themeKey);

  Future<void> setBubbleEnabled(bool value) async {
    await _prefs.setBool(_kBubbleEnabledKey, value);
    notifyListeners();
  }

  Future<void> setTheme(ChatTheme theme) async {
    await _prefs.setString(_kThemeKey, theme.key);
    notifyListeners();
  }

  static Future<bool> bubbleEnabledFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_kBubbleEnabledKey) ?? true;
    } catch (_) {
      return true;
    }
  }
}

class ChatTheme {
  const ChatTheme({
    required this.key,
    required this.displayName,
    required this.mineBg,
    required this.mineBorder,
    required this.accent,
  });

  final String key;

  final String displayName;

  final Color mineBg;

  final Color mineBorder;

  final Color accent;

  static const ChatTheme signal = ChatTheme(
    key: 'signal',
    displayName: 'Signal',
    mineBg: Color(0x33FF7D00),
    mineBorder: Color(0xFFFF7D00),
    accent: Color(0xFFFF7D00),
  );

  static const ChatTheme ocean = ChatTheme(
    key: 'ocean',
    displayName: 'Ocean',
    mineBg: Color(0x332196F3),
    mineBorder: Color(0xFF2196F3),
    accent: Color(0xFF2196F3),
  );

  static const ChatTheme forest = ChatTheme(
    key: 'forest',
    displayName: 'Forest',
    mineBg: Color(0x3343A047),
    mineBorder: Color(0xFF43A047),
    accent: Color(0xFF43A047),
  );

  static const ChatTheme sunset = ChatTheme(
    key: 'sunset',
    displayName: 'Sunset',
    mineBg: Color(0x33E91E63),
    mineBorder: Color(0xFFE91E63),
    accent: Color(0xFFE91E63),
  );

  static const ChatTheme lavender = ChatTheme(
    key: 'lavender',
    displayName: 'Lavender',
    mineBg: Color(0x339C27B0),
    mineBorder: Color(0xFF9C27B0),
    accent: Color(0xFF9C27B0),
  );

  static const ChatTheme amber = ChatTheme(
    key: 'amber',
    displayName: 'Amber',
    mineBg: Color(0x33FFB300),
    mineBorder: Color(0xFFFFB300),
    accent: Color(0xFFFFB300),
  );

  static const ChatTheme mono = ChatTheme(
    key: 'mono',
    displayName: 'Mono',
    mineBg: Color(0x33A8A59D),
    mineBorder: Color(0xFFA8A59D),
    accent: Color(0xFFA8A59D),
  );

  static const ChatTheme defaultTheme = signal;

  static const List<ChatTheme> all = [
    signal,
    ocean,
    forest,
    sunset,
    lavender,
    amber,
    mono,
  ];

  static ChatTheme byKey(String key) {
    for (final theme in all) {
      if (theme.key == key) return theme;
    }
    return defaultTheme;
  }
}
