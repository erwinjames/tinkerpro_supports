import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:shared_preferences/shared_preferences.dart';

/// User-tunable chat preferences. Persisted in SharedPreferences and
/// surfaced to anyone listening (Settings UI for toggles, ChatThreadScreen
/// for theme application, PushService for whether to use the native
/// bubble path on incoming chat messages).
///
/// Any change calls [notifyListeners] so dependent UI rebuilds without
/// a manual reload.
class ChatPrefs extends ChangeNotifier {
  ChatPrefs(this._prefs);
  final SharedPreferences _prefs;

  static const _kBubbleEnabledKey = 'chat_bubble_enabled';
  static const _kThemeKey = 'chat_theme_key';

  /// Top-level switch for the Android Bubbles-API path. Some users prefer
  /// a normal banner notification — not everyone likes a chat head
  /// hovering over their other apps. Default ON to keep parity with
  /// pre-toggle behaviour.
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

  /// Helper used by the FCM background isolate, which can't share an
  /// in-memory ChatPrefs instance with the running app. Reads the value
  /// directly from SharedPreferences in a fire-and-forget manner.
  static Future<bool> bubbleEnabledFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_kBubbleEnabledKey) ?? true;
    } catch (_) {
      return true;
    }
  }
}

/// A Messenger-style colour theme for chat bubbles. The "mine" colours
/// apply to my own messages (right-aligned, accent-tinted); the "their"
/// colours apply to incoming messages (left-aligned, neutral surface).
///
/// Themes deliberately keep peer messages dark + grey so the orange/blue/etc.
/// is just a per-user accent — it stays readable, doesn't scream, and
/// matches the editorial-dark canvas.
class ChatTheme {
  const ChatTheme({
    required this.key,
    required this.displayName,
    required this.mineBg,
    required this.mineBorder,
    required this.theirBg,
    required this.theirBorder,
    required this.accent,
  });

  /// Stable identifier — what we persist. Never localise.
  final String key;

  /// Human-readable label for the picker UI.
  final String displayName;

  /// Background tint for messages I send.
  final Color mineBg;

  /// Border colour for messages I send.
  final Color mineBorder;

  /// Background for messages from the peer/group.
  final Color theirBg;

  /// Border for peer messages.
  final Color theirBorder;

  /// Accent used for "Seen", typing indicators, header presence dots,
  /// etc. Picks up the theme's character at a glance.
  final Color accent;

  // Editorial-dark palette: peer rows stay #141311 / #2A2824 across all
  // themes — the per-theme hue lives only on "my" bubbles. Keeps the
  // chat readable and on-brand.
  static const _peerBg = Color(0xFF141311);
  static const _peerBorder = Color(0xFF2A2824);

  static const ChatTheme signal = ChatTheme(
    key: 'signal',
    displayName: 'Signal',
    mineBg: Color(0x33FF7D00),
    mineBorder: Color(0xFFFF7D00),
    theirBg: _peerBg,
    theirBorder: _peerBorder,
    accent: Color(0xFFFF7D00),
  );

  static const ChatTheme ocean = ChatTheme(
    key: 'ocean',
    displayName: 'Ocean',
    mineBg: Color(0x332196F3),
    mineBorder: Color(0xFF2196F3),
    theirBg: _peerBg,
    theirBorder: _peerBorder,
    accent: Color(0xFF2196F3),
  );

  static const ChatTheme forest = ChatTheme(
    key: 'forest',
    displayName: 'Forest',
    mineBg: Color(0x3343A047),
    mineBorder: Color(0xFF43A047),
    theirBg: _peerBg,
    theirBorder: _peerBorder,
    accent: Color(0xFF43A047),
  );

  static const ChatTheme sunset = ChatTheme(
    key: 'sunset',
    displayName: 'Sunset',
    mineBg: Color(0x33E91E63),
    mineBorder: Color(0xFFE91E63),
    theirBg: _peerBg,
    theirBorder: _peerBorder,
    accent: Color(0xFFE91E63),
  );

  static const ChatTheme lavender = ChatTheme(
    key: 'lavender',
    displayName: 'Lavender',
    mineBg: Color(0x339C27B0),
    mineBorder: Color(0xFF9C27B0),
    theirBg: _peerBg,
    theirBorder: _peerBorder,
    accent: Color(0xFF9C27B0),
  );

  static const ChatTheme amber = ChatTheme(
    key: 'amber',
    displayName: 'Amber',
    mineBg: Color(0x33FFB300),
    mineBorder: Color(0xFFFFB300),
    theirBg: _peerBg,
    theirBorder: _peerBorder,
    accent: Color(0xFFFFB300),
  );

  static const ChatTheme mono = ChatTheme(
    key: 'mono',
    displayName: 'Mono',
    mineBg: Color(0xFF1C1B18),
    mineBorder: Color(0xFFA8A59D),
    theirBg: _peerBg,
    theirBorder: _peerBorder,
    accent: Color(0xFFA8A59D),
  );

  static const ChatTheme defaultTheme = signal;

  /// All themes, in the order they appear in the picker.
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
