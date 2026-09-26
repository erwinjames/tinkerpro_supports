import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'chat_head.dart';

class BubbleStatus {
  const BubbleStatus({
    required this.supported,
    required this.notifications,
    required this.overlay,
  });

  static const unsupported = BubbleStatus(
    supported: false,
    notifications: false,
    overlay: false,
  );

  final bool supported;
  final bool notifications;
  final bool overlay;

  bool get ready => supported && notifications && overlay;
}

class BubblePermission {
  static const MethodChannel _channel =
      MethodChannel('com.tinkerpro.support/chat_bubble');

  static bool get platformSupported => Platform.isAndroid;

  static Future<BubbleStatus> status() async {
    if (!platformSupported) return BubbleStatus.unsupported;
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('bubbleStatus');
      if (raw == null) return BubbleStatus.unsupported;
      return BubbleStatus(
        supported: raw['supported'] == true,
        notifications: raw['notifications'] == true,
        overlay: raw['overlay'] == true,
      );
    } catch (_) {
      return BubbleStatus.unsupported;
    }
  }

  static Future<bool> requestNotifications() async {
    if (!platformSupported) return false;
    try {
      final result = await Permission.notification.request();
      return result.isGranted;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> requestOverlay() => ChatHead.requestPermission();

  static Future<bool> openNotificationSettings() async {
    if (!platformSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('openNotificationSettings') ??
          false;
    } catch (_) {
      return false;
    }
  }
}
