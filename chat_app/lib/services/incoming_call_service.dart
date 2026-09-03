import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

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
    _sub = FlutterCallkitIncoming.onEvent.listen((event) {
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

      _controller.add(IncomingCallEvent(
        action: action,
        callId: callId,
        callerId: int.tryParse((extra['caller_id'] ?? '').toString()) ?? 0,
        callerName: (extra['caller_name'] ?? '').toString(),
        media: (extra['media'] ?? 'voice').toString(),
      ));
    }, onError: (Object e) {

      debugPrint('[incoming_call] CallKit event stream error: $e');
    });
  }

  /// A call accepted from the CallKit sheet while the app was not running
  /// fires its event before [start] can subscribe, so it is lost. The plugin
  /// keeps accepted calls in its active list — read that on launch and
  /// replay the accept, otherwise the user lands in the app with no call.
  Future<IncomingCallEvent?> pendingAcceptedCall() async {
    if (!Platform.isAndroid && !Platform.isIOS) return null;
    try {
      final calls = await FlutterCallkitIncoming.activeCalls();
      if (calls is! List) return null;
      for (final entry in calls) {
        if (entry is! Map) continue;
        final extra = entry['extra'];
        if (extra is! Map) continue;
        final callId = (extra['call_id'] ?? '').toString();
        if (callId.isEmpty) continue;
        return IncomingCallEvent(
          action: IncomingCallAction.accept,
          callId: callId,
          callerId: int.tryParse((extra['caller_id'] ?? '').toString()) ?? 0,
          callerName: (extra['caller_name'] ?? '').toString(),
          media: (extra['media'] ?? 'voice').toString(),
        );
      }
    } catch (e) {
      debugPrint('[incoming_call] activeCalls lookup failed: $e');
    }
    return null;
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    await _controller.close();
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

  await FlutterCallkitIncoming.showCallkitIncoming(CallKitParams(
    id: callId,
    nameCaller: callerName.isEmpty ? 'Unknown' : callerName,
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
  ));
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
