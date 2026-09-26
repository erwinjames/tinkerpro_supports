import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kDefaultBaseUrl = String.fromEnvironment(
  'TPS_BASE_URL',
  defaultValue: 'https://support.tinkerpro.io',
);
const String _kAvatarCacheKey = 'call_avatar_cache';

enum IncomingCallAction { accept, decline, timeout, ended }

class IncomingCallEvent {
  IncomingCallEvent({
    required this.action,
    required this.callId,
    required this.callerId,
    required this.callerName,
    required this.media,
  });

  final IncomingCallAction action;
  final String callId;
  final int callerId;
  final String callerName;
  final String media;
}

class IncomingCallEvents {
  IncomingCallEvents._();
  static final IncomingCallEvents instance = IncomingCallEvents._();

  final _controller = StreamController<IncomingCallEvent>.broadcast();
  Stream<IncomingCallEvent> get stream => _controller.stream;

  StreamSubscription<CallEvent?>? _sub;

  void start() {
    if (_sub != null) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    _sub = FlutterCallkitIncoming.onEvent.listen(
      (event) {
        if (event == null) return;
        final body = event.body;
        if (body is! Map) return;
        final extra = body['extra'];
        if (extra is! Map) return;
        final callId = (extra['call_id'] ?? '').toString();
        if (callId.isEmpty) return;

        final action = switch (event.event) {
          Event.actionCallAccept => IncomingCallAction.accept,
          Event.actionCallDecline => IncomingCallAction.decline,
          Event.actionCallTimeout => IncomingCallAction.timeout,
          Event.actionCallEnded => IncomingCallAction.ended,
          _ => null,
        };
        if (action == null) return;

        _controller.add(
          IncomingCallEvent(
            action: action,
            callId: callId,
            callerId: int.tryParse((extra['caller_id'] ?? '').toString()) ?? 0,
            callerName: (extra['caller_name'] ?? '').toString(),
            media: (extra['media'] ?? 'voice').toString(),
          ),
        );
      },
      onError: (Object e) {
        debugPrint('[incoming_call] CallKit event stream error: $e');
      },
    );
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    await _controller.close();
  }
}

Future<void> rememberCallerAvatars(Map<int, String?> avatars) async {
  try {
    final map = <String, String>{};
    avatars.forEach((id, url) {
      if (url != null && url.isNotEmpty) map['$id'] = url;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAvatarCacheKey, jsonEncode(map));
  } catch (_) {}
}

Future<String?> _callerAvatar(Map<String, dynamic> data) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    var raw = (data['caller_avatar'] ?? '').toString().trim();
    if (raw.isEmpty) {
      final stored = prefs.getString(_kAvatarCacheKey) ?? '';
      if (stored.isNotEmpty) {
        final decoded = jsonDecode(stored);
        if (decoded is Map) {
          raw = (decoded['${data['caller_id'] ?? ''}'] ?? '').toString().trim();
        }
      }
    }
    if (raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    final base = (prefs.getString('server_base_url') ?? _kDefaultBaseUrl)
        .trim()
        .replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) return null;
    return '$base/${raw.replaceAll(RegExp(r'^/+'), '')}';
  } catch (_) {
    return null;
  }
}

Future<void> showIncomingCall(Map<String, dynamic> data) async {
  final callId = (data['call_id'] ?? '').toString();
  if (callId.isEmpty) {
    debugPrint('[incoming_call] dropped — empty call_id');
    return;
  }

  final sentAt = int.tryParse((data['sent_at'] ?? '').toString()) ?? 0;
  if (sentAt > 0) {
    final ageSec = (DateTime.now().millisecondsSinceEpoch ~/ 1000) - sentAt;
    if (ageSec > 45) {
      debugPrint('[incoming_call] dropped — stale push (${ageSec}s old)');
      return;
    }
  }

  final callerName = (data['caller_name'] ?? 'Unknown').toString();
  final media = (data['media'] ?? 'voice').toString();
  final isVideo = media == 'video';
  final avatar = await _callerAvatar(data);

  await FlutterCallkitIncoming.showCallkitIncoming(
    CallKitParams(
      id: callId,
      nameCaller: callerName.isEmpty ? 'Unknown' : callerName,
      avatar: avatar,
      appName: 'TinkerPro Support',
      handle: callerName,
      type: isVideo ? 1 : 0,
      duration: 45000,
      textAccept: 'Accept',
      textDecline: 'Decline',
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: false,
        subtitle: 'Missed call',
      ),
      extra: <String, dynamic>{
        'call_id': callId,
        'caller_id': (data['caller_id'] ?? '').toString(),
        'caller_name': callerName,
        'media': media,
      },
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0F172A',
        actionColor: '#4CAF50',
        incomingCallNotificationChannelName: 'Incoming Calls',
        missedCallNotificationChannelName: 'Missed Calls',
      ),
      ios: const IOSParams(
        iconName: 'CallKitLogo',
        handleType: 'generic',
        supportsVideo: true,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'default',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        supportsDTMF: false,
        supportsHolding: false,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: 'system_ringtone_default',
      ),
    ),
  );
}

Future<void> dismissIncomingCall(String callId) async {
  if (callId.isEmpty) return;
  try {
    await FlutterCallkitIncoming.endCall(callId);
  } catch (_) {}
}

Future<void> markIncomingCallConnected(String callId) async {
  if (callId.isEmpty) return;
  if (!Platform.isAndroid && !Platform.isIOS) return;
  try {
    await FlutterCallkitIncoming.setCallConnected(callId);
  } catch (_) {}
}
