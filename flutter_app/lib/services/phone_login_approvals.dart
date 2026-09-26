import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../api_client.dart';
import '../screens/phone_login_approval_screen.dart';
import 'biometric_auth.dart';

class PhoneLoginApprovals {
  PhoneLoginApprovals._();

  static final PhoneLoginApprovals instance = PhoneLoginApprovals._();

  static const String pushType = 'desktop_login';

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  ApiClient? _api;
  RemoteMessage? _stashedInitial;
  bool _started = false;
  final Set<String> _open = <String>{};

  static bool isApprovalPush(Map<String, dynamic> data) =>
      (data['type'] ?? '').toString() == pushType;

  RemoteMessage? takeStashedInitial() {
    final m = _stashedInitial;
    _stashedInitial = null;
    return m;
  }

  Future<void> bootstrap(ApiClient api) async {
    _api = api;
    if (_started || !Platform.isAndroid) return;
    _started = true;
    try {
      await Firebase.initializeApp();
    } catch (_) {
      return;
    }

    FirebaseMessaging.onMessage.listen(_handle);
    FirebaseMessaging.onMessageOpenedApp.listen(_handle);
    FirebaseMessaging.instance.onTokenRefresh.listen(
      (token) => BiometricAuth(api).syncPushToken(token),
    );

    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        if (isApprovalPush(initial.data)) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _handle(initial));
        } else {
          _stashedInitial = initial;
        }
      }
    } catch (_) {}

    BiometricAuth(api).syncPushToken();
  }

  void _handle(RemoteMessage message) {
    if (!isApprovalPush(message.data)) return;
    final requestId = (message.data['request_id'] ?? '').toString();
    if (requestId.isEmpty) return;
    open(requestId);
  }

  void open(String requestId, {Map<String, dynamic>? preview}) {
    final api = _api;
    final nav = navigatorKey.currentState;
    if (api == null || nav == null) return;
    if (!_open.add(requestId)) return;
    nav
        .push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => PhoneLoginApprovalScreen(
              biometrics: BiometricAuth(api),
              requestId: requestId,
              preview: preview,
            ),
          ),
        )
        .whenComplete(() => _open.remove(requestId));
  }
}
