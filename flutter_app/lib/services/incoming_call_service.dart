import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

/// Triggered by [FlutterCallkitIncoming] events. Coarse-grained on purpose —
/// `accept` / `decline` / `ended` is everything the rest of the app needs to
/// know. SDP fetch + WebRTC negotiation is the [CallService]'s job.
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
  final String media; // 'voice' | 'video'
}

/// App-wide bus for CallKit-originated events. The CallService subscribes to
/// this once it's constructed (after login bootstrap); the singleton lets
/// the background isolate's `showCallkitIncoming` call still surface its
/// follow-up accept / decline through a path the foreground app can pick
/// up after a cold start.
class IncomingCallEvents {
  IncomingCallEvents._();
  static final IncomingCallEvents instance = IncomingCallEvents._();

  final _controller = StreamController<IncomingCallEvent>.broadcast();
  Stream<IncomingCallEvent> get stream => _controller.stream;

  StreamSubscription<CallEvent?>? _sub;

  /// Wire `FlutterCallkitIncoming.onEvent` into [stream]. Safe to call more
  /// than once; later calls are no-ops.
  void start() {
    if (_sub != null) return;
    // flutter_callkit_incoming only has a native implementation on Android and
    // iOS. On desktop/web the `flutter_callkit_incoming_events` EventChannel
    // has no handler, so subscribing throws MissingPluginException (reported
    // by the services library, not deliverable to onError). Skip it entirely.
    if (!Platform.isAndroid && !Platform.isIOS) return;
    _sub = FlutterCallkitIncoming.onEvent.listen((event) {
      if (event == null) return;
      final body = event.body;
      if (body is! Map) return;
      final extra = body['extra'];
      if (extra is! Map) return;
      // Only events we tagged ourselves carry call_id in extra. CallKit's
      // own outgoing-call events (and iOS PushKit ones in Phase 2) won't.
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
      // The CallKit EventChannel can throw MissingPluginException while it's
      // (re)activating — most commonly right after a hot restart, when the
      // Dart side re-subscribes before the native channel is re-registered,
      // or on platforms with no native CallKit implementation. It's transient
      // and non-fatal, so swallow it instead of letting it surface uncaught.
      debugPrint('[incoming_call] CallKit event stream error: $e');
    });
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    await _controller.close();
  }
}

/// Render the native incoming-call sheet. Safe to call from either the
/// foreground or the FCM background isolate. The [data] map is the payload
/// from the FCM `data` block produced by `mobileSendCallPush()` server-side
/// (`type: incoming_call`, `call_id`, `caller_id`, `caller_name`, `media`).
///
/// On Android: full-screen heads-up notification + ConnectionService entry.
/// On iOS: this currently no-ops — Phase 2 needs PushKit + APNS direct.
Future<void> showIncomingCall(Map<String, dynamic> data) async {
  final callId = (data['call_id'] ?? '').toString();
  if (callId.isEmpty) {
    debugPrint('[incoming_call] dropped — empty call_id');
    return;
  }

  // Drop pushes that have been sitting in FCM's queue past the caller's
  // ring timeout — better to silently miss than ring a phantom call.
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

/// Tear down the CallKit sheet locally (e.g. caller hung up before we
/// answered, or our own `decline`). Idempotent.
Future<void> dismissIncomingCall(String callId) async {
  if (callId.isEmpty) return;
  try {
    await FlutterCallkitIncoming.endCall(callId);
  } catch (_) {/* not currently shown — ignore */}
}
