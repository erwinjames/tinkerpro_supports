import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:local_notifier/local_notifier.dart';

import '../platform_info.dart';

/// Thin cross-platform wrapper over OS/system notifications.
///
/// The employee app ships to two very different targets and no single
/// plugin covers both, so we pick one per platform:
///   • Desktop (Windows/Linux/macOS) → `local_notifier`
///   • Mobile  (Android/iOS)         → `flutter_local_notifications`
///
/// Everything is best-effort and guarded: a platform without a working
/// notification backend (or a user who denied permission) just gets the
/// in-app banner + sound instead. [init] is idempotent.
class OsNotifications {
  OsNotifications._();
  static final OsNotifications instance = OsNotifications._();

  bool _ready = false;
  FlutterLocalNotificationsPlugin? _mobile;

  /// Fired when the user taps a notification. Wired by the app to bring
  /// the support chat to the foreground.
  VoidCallback? onTap;

  static const String _androidChannelId = 'support_chat';
  static const String _androidChannelName = 'Support chat';

  Future<void> init() async {
    if (_ready) return;
    try {
      if (kIsDesktopPlatform) {
        // Registers a Start-Menu shortcut carrying the AppUserModelID
        // Windows toast notifications require. No-op re-setup is cheap.
        await localNotifier.setup(appName: 'TinkerPro Support');
      } else if (kIsMobilePlatform) {
        final plugin = FlutterLocalNotificationsPlugin();
        const android = AndroidInitializationSettings('@mipmap/ic_launcher');
        const darwin = DarwinInitializationSettings();
        await plugin.initialize(
          settings: const InitializationSettings(android: android, iOS: darwin),
          onDidReceiveNotificationResponse: (_) => onTap?.call(),
        );
        // Android 13+ needs an explicit runtime grant; iOS needs the
        // permission prompt. Both are best-effort.
        final android13 = plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        await android13?.requestNotificationsPermission();
        await android13?.createNotificationChannel(
          const AndroidNotificationChannel(
            _androidChannelId,
            _androidChannelName,
            description: 'New chat messages from TinkerPro support',
            importance: Importance.high,
          ),
        );
        final ios = plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        await ios?.requestPermissions(alert: true, badge: true, sound: true);
        _mobile = plugin;
      }
    } catch (e) {
      debugPrint('[os-notif] init failed: $e');
    }
    _ready = true;
  }

  /// Show a single notification. [id] lets callers collapse repeated
  /// support pings onto one entry rather than stacking a tower of them.
  Future<void> show(String title, String body, {int id = 1}) async {
    try {
      if (kIsDesktopPlatform) {
        final n = LocalNotification(title: title, body: body);
        n.onClick = () => onTap?.call();
        await n.show();
      } else if (_mobile != null) {
        const android = AndroidNotificationDetails(
          _androidChannelId,
          _androidChannelName,
          channelDescription: 'New chat messages from TinkerPro support',
          importance: Importance.high,
          priority: Priority.high,
        );
        const details =
            NotificationDetails(android: android, iOS: DarwinNotificationDetails());
        await _mobile!.show(
          id: id,
          title: title,
          body: body,
          notificationDetails: details,
        );
      }
    } catch (e) {
      debugPrint('[os-notif] show failed: $e');
    }
  }
}
