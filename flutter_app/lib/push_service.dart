import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_client.dart';
import 'services/chat_prefs.dart';
import 'services/incoming_call_service.dart';

/// Method channel into the native ChatBubble plugin (kotlin) for
/// Messenger-style chat-head bubble notifications. Falls back to
/// regular flutter_local_notifications if the channel call fails
/// (e.g. older Android, channel not registered yet).
const MethodChannel _chatBubbleChannel =
    MethodChannel('com.tinkerpro.support/chat_bubble');

const String _kChatChannelId = 'tinkerpro_chat';
const String _kChatChannelName = 'TinkerPro Chat';
const String _kAlertsChannelId = 'tinkerpro_alerts';
const String _kAlertsChannelName = 'TinkerPro Alerts';

/// Top-level instance shared with the background isolate. The background
/// handler can't reach the running app's PushService, so it shows banners
/// through this independent plugin instance.
final FlutterLocalNotificationsPlugin _bgLocalPlugin =
    FlutterLocalNotificationsPlugin();
bool _bgInitialised = false;

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  final data = message.data;
  final type = (data['type'] ?? '').toString();

  // Incoming call wakes the device whether the app is alive, backgrounded,
  // or killed. Hand off to flutter_callkit_incoming immediately — Apple/Google
  // both penalize apps that take more than a few seconds to display a call UI
  // after a high-priority push. SDP fetch + WebRTC negotiation happens later
  // (after the user taps Accept), via CallService.acceptIncomingFromPush.
  if (type == 'incoming_call') {
    await showIncomingCall(data.map((k, v) => MapEntry(k, v)));
    return;
  }

  if (Platform.isAndroid) {
    if (type == 'chat.message') {
      // Honour the per-user "Chat bubble notifications" toggle from
      // Settings. The background isolate can't share state with the
      // running app, so we read directly from SharedPreferences.
      final bubblesAllowed = await ChatPrefs.bubbleEnabledFromDisk();
      final shown = bubblesAllowed ? await _tryShowBubble(data) : false;
      if (!shown) {
        await _ensureBgLocalInit();
        await _showChatBanner(_bgLocalPlugin, data);
      }
    }
  }
}

Future<bool> _tryShowBubble(Map<String, dynamic> data) async {
  try {
    await _chatBubbleChannel.invokeMethod('show', <String, dynamic>{
      'conversationId':
          int.tryParse((data['conversation_id'] ?? '').toString()) ?? 0,
      'senderId':
          int.tryParse((data['sender_id'] ?? '').toString()) ?? 0,
      'senderName': (data['sender_name'] ?? 'New message').toString(),
      'body': (data['preview'] ?? '').toString(),
    });
    return true;
  } on MissingPluginException catch (_) {
    return false;
  } on PlatformException catch (_) {
    return false;
  } catch (_) {
    return false;
  }
}

Future<void> _cancelBubble(int conversationId) async {
  try {
    await _chatBubbleChannel.invokeMethod('cancel', <String, dynamic>{
      'conversationId': conversationId,
    });
  } catch (_) {}
}

Future<void> _ensureBgLocalInit() async {
  if (_bgInitialised) return;
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await _bgLocalPlugin
      .initialize(const InitializationSettings(android: androidInit));
  await _bgLocalPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(const AndroidNotificationChannel(
    _kChatChannelId,
    _kChatChannelName,
    description: 'New chat messages.',
    importance: Importance.high,
  ));
  _bgInitialised = true;
}

Future<void> _showChatBanner(
    FlutterLocalNotificationsPlugin plugin, Map<String, dynamic> data) async {
  final senderName = (data['sender_name'] ?? 'New message').toString();
  final preview = (data['preview'] ?? '').toString();
  final convId =
      int.tryParse((data['conversation_id'] ?? '').toString()) ?? 0;
  await plugin.show(
    convId == 0 ? 0 : convId,
    senderName,
    preview.isEmpty ? 'You have a new message' : preview,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        _kChatChannelId,
        _kChatChannelName,
        channelDescription: 'New chat messages.',
        importance: Importance.high,
        priority: Priority.high,
      ),
    ),
    payload: 'chat:$convId',
  );
}

/// Pushed via FCM tap → consumed by HomeShell on next build / lifecycle
/// resume to switch to the CHAT tab and open the thread.
class PendingChatNavigation extends ChangeNotifier {
  int? _conversationId;
  int? consume() {
    final v = _conversationId;
    _conversationId = null;
    return v;
  }

  void setTarget(int conversationId) {
    _conversationId = conversationId;
    notifyListeners();
  }
}

class PushService {
  PushService(this._api);

  final ApiClient _api;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Set by HomeShell after ChatRealtimeService is up. Used to suppress
  /// banners when the user is already viewing the conversation that just
  /// got a message.
  ValueNotifier<int?>? _currentlyViewedConv;
  void bindCurrentlyViewedConv(ValueNotifier<int?> notifier) {
    _currentlyViewedConv = notifier;
  }

  /// Late-bound reference to the user's chat preferences (bubble toggle,
  /// theme). Set by HomeShell after ChatPrefs is constructed.
  ChatPrefs? _chatPrefs;
  void bindChatPrefs(ChatPrefs prefs) {
    _chatPrefs = prefs;
  }

  /// One-shot navigation target — read by HomeShell when the user taps a
  /// chat banner. Pre-allocated so callers can listen before initialize().
  final PendingChatNavigation pendingChatNavigation = PendingChatNavigation();

  Future<void> initialize() async {
    if (_initialized) return;
    if (!Platform.isAndroid) return;

    await Firebase.initializeApp();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _local.initialize(
      const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: _onLocalNotificationTap,
    );

    // Two channels — one for legacy alerts, one for chat. They look the
    // same but separating them lets the user mute chat without losing
    // customer/lead alerts.
    final androidPlugin = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _kAlertsChannelId,
        _kAlertsChannelName,
        description: 'Push alerts for new customers and client offers.',
        importance: Importance.high,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _kChatChannelId,
        _kChatChannelName,
        description: 'New chat messages.',
        importance: Importance.high,
      ),
    );

    await FirebaseMessaging.instance
        .requestPermission(alert: true, badge: true, sound: true);

    FirebaseMessaging.onMessage.listen(_handleForegroundFcm);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // Cold start from a notification tap.
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      _handleNotificationTap(initial);
    }

    // Native chat bubble: when the user taps the bubble (or the
    // MessagingStyle banner), MainActivity invokes `openConversation`
    // on this channel. Route it into pendingChatNavigation just like
    // the local-notification tap path.
    _chatBubbleChannel.setMethodCallHandler((call) async {
      if (call.method == 'openConversation') {
        final convId = (call.arguments as Map?)?['conversationId'];
        final id = int.tryParse(convId?.toString() ?? '') ?? 0;
        if (id > 0) {
          pendingChatNavigation.setTarget(id);
        }
      }
      return null;
    });

    FirebaseMessaging.instance.onTokenRefresh.listen(_registerToken);

    _initialized = true;
  }

  /// Dismiss the chat-head bubble + banner for a conversation. Called
  /// when the user opens that thread in-app, so the bubble doesn't hover
  /// over the screen they're already reading.
  Future<void> dismissBubble(int conversationId) =>
      _cancelBubble(conversationId);

  /// Foreground delivery decision matrix (see docs/chat-mvp-design.md §VIII):
  ///   * legacy notification-style payload         → render banner
  ///   * data-only chat payload, viewing this conv → suppress (Pusher already delivered)
  ///   * data-only chat payload, viewing other     → render banner
  Future<void> _handleForegroundFcm(RemoteMessage message) async {
    final type = (message.data['type'] ?? '').toString();

    // Incoming call: same handoff as the background path. We deliberately
    // don't try to short-circuit via Soketi here; even if the app is in
    // foreground, going through CallKit gives the user the same Accept/
    // Decline UI as the killed-app path. CallService picks up via
    // IncomingCallEvents (started in main.dart).
    if (type == 'incoming_call') {
      await showIncomingCall(
          message.data.map((k, v) => MapEntry(k, v)));
      return;
    }

    final isChat = type == 'chat.message';

    if (isChat) {
      final convId =
          int.tryParse((message.data['conversation_id'] ?? '').toString()) ?? 0;
      final viewing = _currentlyViewedConv?.value;
      if (convId > 0 && viewing == convId) {
        // User is already reading the thread — Pusher delivered the live
        // copy. Cancel any leftover bubble for this conv so we don't hang
        // a chat head over the open thread.
        await _cancelBubble(convId);
        return;
      }
      // Native bubble first IF the user has the "Chat bubble notifications"
      // toggle on. Otherwise fall straight to a plain local notification.
      final bubblesAllowed = _chatPrefs?.bubbleEnabled ?? true;
      final shown =
          bubblesAllowed ? await _tryShowBubble(message.data) : false;
      if (!shown) {
        await _showChatBanner(_local, message.data);
      }
      return;
    }

    final notification = message.notification;
    if (notification == null) return;
    await _local.show(
      notification.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _kAlertsChannelId,
          _kAlertsChannelName,
          channelDescription:
              'Push alerts for new customers and client offers.',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
    );
  }

  /// Tap on a system-tray notification that came from FCM directly (i.e.
  /// the legacy `notification`-block alerts). Chat messages go through
  /// the local plugin, not this path.
  void _handleNotificationTap(RemoteMessage message) {
    if ((message.data['type'] ?? '') == 'chat.message') {
      final convId =
          int.tryParse((message.data['conversation_id'] ?? '').toString()) ?? 0;
      if (convId > 0) {
        pendingChatNavigation.setTarget(convId);
      }
    }
  }

  /// Tap on a banner shown via flutter_local_notifications. The payload
  /// format we set in [_showChatBanner] is `chat:<convId>`.
  void _onLocalNotificationTap(NotificationResponse response) {
    final payload = response.payload ?? '';
    if (payload.startsWith('chat:')) {
      final convId = int.tryParse(payload.substring('chat:'.length)) ?? 0;
      if (convId > 0) {
        pendingChatNavigation.setTarget(convId);
      }
    }
  }

  /// Fetches the current FCM token and posts it to `registerMobilePushToken`.
  /// Safe to call multiple times — duplicates are handled server-side via
  /// `ON DUPLICATE KEY UPDATE`.
  Future<String?> registerCurrentDevice() async {
    await initialize();
    if (!_initialized) return null;
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return null;
    await _registerToken(token);
    return token;
  }

  Future<void> _registerToken(String token) async {
    if (!_api.hasSession) return;
    try {
      await _api.post(
        'registerMobilePushToken',
        body: <String, String>{
          'token': token,
          'platform': 'android',
          'device_name': 'Android Device',
        },
      );
    } catch (_) {
      // Swallow registration errors so the rest of the app keeps working —
      // the log on the console will still show the failure.
    }
  }

  /// Best-effort unregister of the current device's FCM token, called on
  /// logout. Without this, the previous user's row in
  /// `mobile_device_tokens` keeps the token mapped to them until the next
  /// login overwrites it — which means push notifications addressed to
  /// that user can briefly land on a device that's now signed in as
  /// somebody else.
  Future<void> releaseCurrentDevice() async {
    if (!Platform.isAndroid) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;
      await _api.post(
        'unregisterMobilePushToken',
        body: <String, String>{'token': token},
      );
    } catch (_) {
      // Ignored — the server-side token table also dedupes by token, so
      // the next user's login will overwrite the row regardless.
    }
  }
}
