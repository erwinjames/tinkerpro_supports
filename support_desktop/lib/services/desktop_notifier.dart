import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

class DesktopNotifier {
  DesktopNotifier._();
  static final DesktopNotifier instance = DesktopNotifier._();

  static const String _prefKey = 'desktop_notifications_enabled';
  static const String _appName = 'TinkerPro Support';
  static const String _iconAsset = 'assets/brand/tinkerpro-icon-192.png';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);

  SharedPreferences? _prefs;
  bool _ready = false;
  Future<void>? _initFuture;
  String? _windowsIcon;
  String? _pendingPayload;
  void Function(String payload)? _onOpen;

  bool get supported => Platform.isLinux || Platform.isWindows;

  Future<void> init(SharedPreferences prefs) {
    _prefs = prefs;
    enabled.value = prefs.getBool(_prefKey) ?? true;
    return _initFuture ??= _init();
  }

  Future<void> _init() async {
    if (!supported) return;
    try {
      if (Platform.isWindows) _windowsIcon = await _resolveWindowsIcon();
      final ok = await _plugin.initialize(
        settings: InitializationSettings(
          linux: LinuxInitializationSettings(
            defaultActionName: 'Open',
            defaultIcon: AssetsLinuxIcon(_iconAsset),
          ),
          windows: WindowsInitializationSettings(
            appName: _appName,
            appUserModelId: 'TinkerPro.SupportDesktop',
            guid: '594bd8e7-b39a-406c-8909-1b8617f833e9',
            iconPath: _windowsIcon,
          ),
        ),
        onDidReceiveNotificationResponse: _onResponse,
      );
      _ready = ok ?? false;
      if (Platform.isWindows) {
        final launch = await _plugin.getNotificationAppLaunchDetails();
        final p = launch?.notificationResponse?.payload;
        if (launch?.didNotificationLaunchApp == true && p != null) {
          _pendingPayload = p;
        }
      }
    } catch (e) {
      debugPrint('DesktopNotifier init failed: $e');
      _ready = false;
    }
  }

  Future<String?> _resolveWindowsIcon() async {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final bundled = File('$exeDir\\data\\flutter_assets\\'
          '${_iconAsset.replaceAll('/', '\\')}');
      return await bundled.exists() ? bundled.path : null;
    } catch (_) {
      return null;
    }
  }

  set onOpen(void Function(String payload)? handler) {
    _onOpen = handler;
    final pending = _pendingPayload;
    if (handler != null && pending != null) {
      _pendingPayload = null;
      scheduleMicrotask(() => handler(pending));
    }
  }

  Future<void> setEnabled(bool value) async {
    enabled.value = value;
    await _prefs?.setBool(_prefKey, value);
  }

  Future<bool> appInForeground() async {
    try {
      final visible = await windowManager.isVisible();
      final minimized = await windowManager.isMinimized();
      final focused = await windowManager.isFocused();
      return visible && !minimized && focused;
    } catch (_) {
      return false;
    }
  }

  String _escapeLinux(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
    bool chat = false,
  }) async {
    if (!enabled.value || !supported) return;
    await (_initFuture ?? Future<void>.value());
    if (!_ready) return;
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: Platform.isLinux ? _escapeLinux(body) : body,
        payload: payload,
        notificationDetails: NotificationDetails(
          linux: LinuxNotificationDetails(
            category: chat
                ? LinuxNotificationCategory.imReceived
                : null,
            urgency: LinuxNotificationUrgency.normal,
            defaultActionName: 'Open',
          ),
          windows: const WindowsNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('DesktopNotifier show failed: $e');
    }
  }

  Future<void> cancel(int id) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: id);
    } catch (_) {}
  }

  Future<void> bringToFront() async {
    try {
      if (!await windowManager.isVisible()) await windowManager.show();
      if (await windowManager.isMinimized()) await windowManager.restore();
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {}
  }

  Future<void> _onResponse(NotificationResponse r) async {
    await bringToFront();
    final p = r.payload;
    if (p == null || p.isEmpty) return;
    final handler = _onOpen;
    if (handler == null) {
      _pendingPayload = p;
      return;
    }
    handler(p);
  }
}
