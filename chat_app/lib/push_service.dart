import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_client.dart';
import 'services/chat_head.dart';
import 'services/incoming_call_service.dart';
import 'services/tone_prefs.dart';

const MethodChannel _chatBubbleChannel =
    MethodChannel('com.tinkerpro.support/chat_bubble');

const String _kChatChannelId = 'tinkerpro_chat_default';
const String _kChatChannelName = 'TinkerPro Chat';
const String _kAlertsChannelId = 'tinkerpro_alerts';
const String _kAlertsChannelName = 'TinkerPro Alerts';

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

  if (type == 'incoming_call') {
    await showIncomingCall(data.map((k, v) => MapEntry(k, v)));
    return;
  }

  if (type == 'chat.read') {
    final convId =
        int.tryParse((data['conversation_id'] ?? '').toString()) ?? 0;
    if (convId > 0 && Platform.isAndroid) {
      final handled = await _cancelBubble(convId);
      await ChatHead.markConversationRead(convId);
      await _ensureBgLocalInit();
      if (!handled) await _bgLocalPlugin.cancel(convId);
      await _bgLocalPlugin.cancel(-convId);
    }
    return;
  }

  if (Platform.isAndroid) {
    if ((data['event'] ?? '').toString() == 'fb_moved') {
      await _ensureBgLocalInit();
      await _showMovedBanner(_bgLocalPlugin, Map<String, dynamic>.from(data));
      return;
    }
    if (type == 'chat.message') {
      final shown = await _tryShowBubble(data);
      if (!shown) {
        await _ensureBgLocalInit();
        await _showChatBanner(_bgLocalPlugin, data);
      }
      await ChatHead.showForMessage(Map<String, dynamic>.from(data));
    }
  }
}

String _soundEventFor(Map<String, dynamic> data) =>
    (data['source'] ?? '').toString() == 'facebook' ? 'fb' : 'notify';

Future<bool> _tryShowBubble(Map<String, dynamic> data) async {
  try {
    final channelId = await TonePrefs.channelFor(_soundEventFor(data));
    await _chatBubbleChannel.invokeMethod('show', <String, dynamic>{
      'channelId': channelId ?? '',
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

Future<bool> _cancelBubble(int conversationId) async {
  try {
    await _chatBubbleChannel.invokeMethod('cancel', <String, dynamic>{
      'conversationId': conversationId,
    });
    return true;
  } catch (_) {
    return false;
  }
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
  final channelId =
      await TonePrefs.channelFor(_soundEventFor(data)) ?? _kChatChannelId;
  await plugin.show(
    convId == 0 ? 0 : convId,
    senderName,
    preview.isEmpty ? 'You have a new message' : preview,
    NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        _kChatChannelName,
        channelDescription: 'New chat messages.',
        importance: Importance.high,
        priority: Priority.high,
      ),
    ),
    payload: 'chat:$convId',
  );
}

Future<void> _showMovedBanner(
    FlutterLocalNotificationsPlugin plugin, Map<String, dynamic> data) async {
  final title =
      (data['thread_name'] ?? data['sender_name'] ?? 'Facebook chat moved')
          .toString();
  final body = (data['preview'] ?? '').toString();
  final convId =
      int.tryParse((data['conversation_id'] ?? '').toString()) ?? 0;
  final channelId = await TonePrefs.channelFor('fbmove') ?? _kChatChannelId;
  await plugin.show(
    convId == 0 ? 0 : -convId,
    title,
    body.isEmpty ? 'A Facebook chat was moved to agents' : body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        _kChatChannelName,
        channelDescription: 'New chat messages.',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.message,
      ),
    ),
    payload: 'chat:$convId',
  );
}

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

  ValueNotifier<int?>? _currentlyViewedConv;
  void bindCurrentlyViewedConv(ValueNotifier<int?> notifier) {
    _currentlyViewedConv = notifier;
  }

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
    await androidPlugin?.deleteNotificationChannel('tinkerpro_chat');
    await androidPlugin?.deleteNotificationChannel('tinkerpro_chat_messages');
    await TonePrefs.applyToRingtoneService();
    await TonePrefs.syncChannels();

    await FirebaseMessaging.instance
        .requestPermission(alert: true, badge: true, sound: true);

    FirebaseMessaging.onMessage.listen(_handleForegroundFcm);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      _handleNotificationTap(initial);
    }

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

  Future<void> dismissBubble(int conversationId) async {
    if (!_initialized) return;
    await _cancelBubble(conversationId);
    await ChatHead.dismissConversation(conversationId);
  }

  Future<void> _handleForegroundFcm(RemoteMessage message) async {
    final type = (message.data['type'] ?? '').toString();

    if (type == 'incoming_call') {
      await showIncomingCall(
          message.data.map((k, v) => MapEntry(k, v)));
      return;
    }

    if (type == 'chat.read') {
      final convId =
          int.tryParse((message.data['conversation_id'] ?? '').toString()) ?? 0;
      if (convId > 0) {
        final handled = await _cancelBubble(convId);
        await ChatHead.markConversationRead(convId);
        if (!handled) await _local.cancel(convId);
        await _local.cancel(-convId);
      }
      return;
    }

    if ((message.data['event'] ?? '').toString() == 'fb_moved') {
      await _showMovedBanner(_local, message.data);
      return;
    }

    final isChat = type == 'chat.message';

    if (isChat) {
      final convId =
          int.tryParse((message.data['conversation_id'] ?? '').toString()) ?? 0;
      final viewing = _currentlyViewedConv?.value;
      if (convId > 0 && viewing == convId) {
        await _cancelBubble(convId);
        return;
      }

      final shown = await _tryShowBubble(message.data);
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

  void _handleNotificationTap(RemoteMessage message) {
    if ((message.data['type'] ?? '') == 'chat.message') {
      final convId =
          int.tryParse((message.data['conversation_id'] ?? '').toString()) ?? 0;
      if (convId > 0) {
        pendingChatNavigation.setTarget(convId);
      }
    }
  }

  void _onLocalNotificationTap(NotificationResponse response) {
    final payload = response.payload ?? '';
    if (payload.startsWith('chat:')) {
      final convId = int.tryParse(payload.substring('chat:'.length)) ?? 0;
      if (convId > 0) {
        pendingChatNavigation.setTarget(convId);
      }
    }
  }

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

    }
  }

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

    }
  }
}
