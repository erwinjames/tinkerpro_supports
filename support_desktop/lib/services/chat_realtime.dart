import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../api_client.dart';
import '../models/chat_models.dart';

/// Soketi connection config. By default the host is derived from the API
/// base URL so a single `--dart-define=TPS_BASE_URL=https://support.tinkerpro.io`
/// configures both HTTP and WebSocket. Override only the bits that genuinely
/// differ from the API host:
///
///   --dart-define=CHAT_SOKETI_PORT=6001       # default 6001 (use 443 on live)
///   --dart-define=CHAT_SOKETI_KEY=…           # default tinkerpro-chat-key
///   --dart-define=CHAT_SOKETI_TLS=true        # default: matches API scheme
///   --dart-define=CHAT_SOKETI_PATH=/soketi    # nginx proxy prefix on live
///   --dart-define=CHAT_SOKETI_HOST=…          # only if Soketi runs on a
///                                             # different host than the API
class ChatRealtimeConfig {
  const ChatRealtimeConfig({
    required this.apiKey,
    required this.host,
    required this.port,
    required this.useTls,
    this.path = '',
  });

  final String apiKey;
  final String host;
  final int port;
  final bool useTls;

  /// Optional URL path prefix Soketi is proxied under (e.g. `/soketi` when
  /// nginx fronts it on the main 443 vhost). Empty when Soketi is reached
  /// at the host root (direct port, or a dedicated subdomain).
  final String path;

  /// Build a config given the API base URL the rest of the app already uses.
  /// If [CHAT_SOKETI_HOST] is set, that wins — useful when Soketi runs on a
  /// different host than PHP.
  factory ChatRealtimeConfig.fromBaseUrl(String baseUrl) {
    const apiKey = String.fromEnvironment(
      'CHAT_SOKETI_KEY',
      defaultValue: 'tinkerpro-chat-key',
    );
    const port = int.fromEnvironment('CHAT_SOKETI_PORT', defaultValue: 6001);
    const path = String.fromEnvironment('CHAT_SOKETI_PATH', defaultValue: '');
    const hostOverride =
        String.fromEnvironment('CHAT_SOKETI_HOST', defaultValue: '');
    const tlsOverride =
        String.fromEnvironment('CHAT_SOKETI_TLS', defaultValue: '');

    String host = hostOverride;
    bool useTls = false;
    try {
      final u = Uri.parse(baseUrl);
      if (u.host.isNotEmpty) {
        if (host.isEmpty) host = u.host;
        useTls = u.scheme == 'https';
      }
    } catch (_) {}
    if (host.isEmpty) host = '127.0.0.1';
    if (tlsOverride.isNotEmpty) {
      useTls = tlsOverride.toLowerCase() == 'true';
    }

    return ChatRealtimeConfig(
      apiKey: apiKey,
      host: host,
      port: port,
      useTls: useTls,
      path: path,
    );
  }

  /// Wire URL per the Pusher protocol v7:
  ///   ws(s)://host:port[/prefix]/app/{key}?protocol=7&client=tinkerpro&version=1.0
  Uri wsUri() {
    final scheme = useTls ? 'wss' : 'ws';
    // Normalise the optional proxy prefix: '' → none; 'soketi' or '/soketi/'
    // → '/soketi'. The '/app/...' Pusher path is appended after it.
    final prefix =
        path.isEmpty ? '' : '/${path.replaceAll(RegExp(r'^/+|/+$'), '')}';
    return Uri.parse(
      '$scheme://$host:$port$prefix/app/$apiKey?protocol=7&client=tinkerpro&version=1.0&flash=false',
    );
  }
}

/// Hand-rolled minimal Pusher-protocol client. Intentionally implements
/// only what Phase 1 needs:
///
///   * subscribe to `private-user-{me}` and `private-conv-{id}`
///   * subscribe to `presence-global-staff` with presence payload
///   * receive `message.new` / `conversation.activity` events
///   * maintain `onlineUsers` from presence events
///   * pause/resume/disconnect over the app lifecycle
///   * auto-reconnect on drop with exponential backoff
///
/// Delivery is best-effort. Any drop is recovered by the REST hydrate
/// that runs on [resume] — see ChatInbox.reload and ChatThread.loadInitial.
class ChatRealtimeService {
  ChatRealtimeService(this.api, {ChatRealtimeConfig? config})
      : _config = config ?? ChatRealtimeConfig.fromBaseUrl(api.baseUrl);

  final ApiClient api;
  final ChatRealtimeConfig _config;

  int? _myUserId;
  WebSocketChannel? _socket;
  StreamSubscription<dynamic>? _socketSub;
  String? _socketId;
  bool _connected = false;
  bool _disposed = false;
  bool _wantConnected = false;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;

  final _subscribed = <String>{};
  final _pendingSubscribes = <String>{};

  final _inboxEvents = StreamController<ConversationActivity>.broadcast();
  final _messageEvents = StreamController<Message>.broadcast();
  final _lifecycleEvents = StreamController<ConversationLifecycle>.broadcast();
  final _readEvents = StreamController<MessageRead>.broadcast();
  final _typingEvents = StreamController<TypingEvent>.broadcast();
  final _callSignalEvents = StreamController<CallSignal>.broadcast();
  final _pinEvents = StreamController<PinUpdate>.broadcast();

  Stream<ConversationActivity> get inboxEvents => _inboxEvents.stream;
  Stream<Message> get messageEvents => _messageEvents.stream;

  /// Inbound WebRTC signaling: offer/answer/ICE/control frames forwarded by
  /// the server on the per-user channel. CallService is the sole consumer.
  Stream<CallSignal> get callSignalEvents => _callSignalEvents.stream;

  /// Fires on every `typing` event from any subscribed conversation. Carries
  /// the conversation id so a single listener (the open thread) can filter.
  Stream<TypingEvent> get typingEvents => _typingEvents.stream;

  /// Fires when the current user is added to a conversation
  /// (`conversation.created`) or removed from one (`conversation.removed`).
  /// Drives ChatInbox to re-hydrate from REST.
  Stream<ConversationLifecycle> get lifecycleEvents => _lifecycleEvents.stream;

  /// Fires whenever a participant's read cursor advances. Drives the
  /// "Seen by N" UI re-render in open threads.
  Stream<MessageRead> get readEvents => _readEvents.stream;

  /// Fires when a message is pinned (`pinned` non-null) or unpinned
  /// (`pinned` null) in a subscribed conversation. The open thread filters
  /// by conversation id.
  Stream<PinUpdate> get pinEvents => _pinEvents.stream;

  /// Conversation id the user currently has on screen. PushService consults
  /// this to decide whether to suppress an FCM notification for a chat
  /// message that just arrived for the same conversation. Set/cleared by
  /// ChatThreadScreen on init/dispose.
  final ValueNotifier<int?> currentlyViewedConv = ValueNotifier<int?>(null);

  /// Live set of user ids currently on `presence-global-staff`. Widgets
  /// that care about presence listen to this notifier.
  final ValueNotifier<Set<int>> onlineUsers = ValueNotifier<Set<int>>(<int>{});

  bool get isConnected => _connected;

  Future<void> connect(int myUserId) async {
    _myUserId = myUserId;
    _wantConnected = true;
    _subscribed.clear();
    _pendingSubscribes
      ..clear()
      ..add('private-user-$myUserId')
      ..add('presence-global-staff');
    await _openSocket();
  }

  Future<void> pause() async {
    _wantConnected = false;
    await _closeSocket();
  }

  Future<void> resume() async {
    if (_myUserId == null) return;
    _wantConnected = true;
    if (!_connected) {
      await _openSocket();
    }
  }

  Future<void> disconnect() async {
    _wantConnected = false;
    _subscribed.clear();
    _pendingSubscribes.clear();
    await _closeSocket();
  }

  Future<void> subscribeConversation(int conversationId) async {
    final ch = 'private-conv-$conversationId';
    _pendingSubscribes.add(ch);
    if (_connected && _socketId != null) {
      await _sendSubscribe(ch);
    }
  }

  Future<void> unsubscribeConversation(int conversationId) async {
    final ch = 'private-conv-$conversationId';
    _pendingSubscribes.remove(ch);
    if (_subscribed.remove(ch)) {
      _sendRaw({
        'event': 'pusher:unsubscribe',
        'data': {'channel': ch},
      });
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _wantConnected = false;
    _reconnectTimer?.cancel();
    await _closeSocket();
    await _inboxEvents.close();
    await _messageEvents.close();
    await _lifecycleEvents.close();
    await _readEvents.close();
    await _typingEvents.close();
    await _callSignalEvents.close();
    await _pinEvents.close();
    currentlyViewedConv.dispose();
  }

  // ─────────────────────────────────── internals ─────────────────────────────

  Future<void> _openSocket() async {
    if (_disposed) return;
    _reconnectTimer?.cancel();

    WebSocketChannel? channel;
    try {
      channel = WebSocketChannel.connect(_config.wsUri());
      // Awaiting the handshake here is important — without it, a failed
      // connection (e.g. Soketi not running) surfaces as an UNHANDLED
      // future error from `channel.ready`, which the stream's onError
      // doesn't catch. The try/catch below would also miss it. So we
      // await explicitly so the error funnels into _scheduleReconnect.
      await channel.ready;
      if (_disposed) {
        await channel.sink.close();
        return;
      }
      _socket = channel;
      _socketSub = channel.stream.listen(
        _onMessage,
        onDone: _onSocketClosed,
        onError: (Object err, StackTrace st) => _onSocketClosed(),
        cancelOnError: true,
      );
    } catch (_) {
      // Soketi unreachable / handshake failed / TLS mismatch / etc.
      // All of these reduce to "try again later".
      try {
        await channel?.sink.close();
      } catch (_) {}
      _socket = null;
      _scheduleReconnect();
    }
  }

  Future<void> _closeSocket() async {
    _reconnectTimer?.cancel();
    await _socketSub?.cancel();
    _socketSub = null;
    try {
      await _socket?.sink.close();
    } catch (_) {}
    _socket = null;
    _socketId = null;
    _connected = false;
    _subscribed.clear();
  }

  void _onSocketClosed() {
    _connected = false;
    _socketId = null;
    _subscribed.clear();
    _socket = null;
    if (_wantConnected && !_disposed) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed || !_wantConnected) return;
    _reconnectAttempts = (_reconnectAttempts + 1).clamp(1, 6);
    final delayMs = 500 * (1 << (_reconnectAttempts - 1)); // 500, 1s, 2s, 4s, 8s, 16s
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), _openSocket);
  }

  void _sendRaw(Map<String, dynamic> frame) {
    try {
      _socket?.sink.add(jsonEncode(frame));
    } catch (_) {}
  }

  void _onMessage(dynamic raw) {
    if (raw is! String || raw.isEmpty) return;
    Map<String, dynamic>? frame;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) frame = Map<String, dynamic>.from(decoded);
    } catch (_) {}
    if (frame == null) return;

    final event = (frame['event'] ?? '').toString();
    final data = _decodeData(frame['data']);
    final channel = (frame['channel'] ?? '').toString();

    switch (event) {
      case 'pusher:connection_established':
        _handleConnectionEstablished(data);
        break;
      case 'pusher:ping':
        _sendRaw({'event': 'pusher:pong', 'data': {}});
        break;
      case 'pusher_internal:subscription_succeeded':
      case 'pusher:subscription_succeeded':
        _handleSubscriptionSucceeded(channel, data);
        break;
      case 'pusher:subscription_error':
        _subscribed.remove(channel);
        break;
      case 'pusher_internal:member_added':
      case 'pusher:member_added':
        _handleMemberDelta(channel, data, joined: true);
        break;
      case 'pusher_internal:member_removed':
      case 'pusher:member_removed':
        _handleMemberDelta(channel, data, joined: false);
        break;
      case 'message.new':
        _forwardMessage(data);
        break;
      case 'conversation.activity':
        _forwardActivity(data);
        break;
      case 'conversation.created':
        _forwardLifecycle(data, added: true);
        break;
      case 'conversation.removed':
        _forwardLifecycle(data, added: false);
        break;
      case 'message.read':
        _forwardRead(data);
        break;
      case 'message.pinned':
        _forwardPin(data, pinned: true);
        break;
      case 'message.unpinned':
        _forwardPin(data, pinned: false);
        break;
      case 'typing':
        _forwardTyping(channel, data);
        break;
      case 'call.signal':
        _forwardCallSignal(data);
        break;
    }
  }

  Map<String, dynamic>? _decodeData(dynamic raw) {
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    } else if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return null;
  }

  Future<void> _handleConnectionEstablished(Map<String, dynamic>? data) async {
    _socketId = (data?['socket_id'] ?? '').toString();
    if (_socketId == null || _socketId!.isEmpty) return;
    _connected = true;
    _reconnectAttempts = 0;

    // Re-subscribe to every channel we want.
    for (final ch in _pendingSubscribes.toList()) {
      await _sendSubscribe(ch);
    }
  }

  Future<void> _sendSubscribe(String channelName) async {
    if (!_connected || _socketId == null) return;
    if (_subscribed.contains(channelName)) return;

    final authRes = await api.post('chat.pusherAuth', body: {
      'socket_id': _socketId!,
      'channel_name': channelName,
    });

    final auth = authRes['auth'];
    if (auth is! String || auth.isEmpty) return;

    final data = <String, dynamic>{
      'channel': channelName,
      'auth': auth,
    };
    if (authRes['channel_data'] is String) {
      data['channel_data'] = authRes['channel_data'];
    }
    _sendRaw({'event': 'pusher:subscribe', 'data': data});
    _subscribed.add(channelName);
  }

  void _handleSubscriptionSucceeded(String channel, Map<String, dynamic>? data) {
    if (channel != 'presence-global-staff') return;
    final presence = data?['presence'];
    if (presence is Map) {
      final ids = presence['ids'];
      if (ids is List) {
        final next = ids
            .map((e) => int.tryParse(e.toString()) ?? 0)
            .where((e) => e > 0)
            .toSet();
        onlineUsers.value = next;
      }
    }
  }

  void _handleMemberDelta(String channel, Map<String, dynamic>? data,
      {required bool joined}) {
    if (channel != 'presence-global-staff') return;
    final uid = int.tryParse((data?['user_id'] ?? '').toString()) ?? 0;
    if (uid <= 0) return;
    final next = Set<int>.from(onlineUsers.value);
    if (joined) {
      next.add(uid);
    } else {
      next.remove(uid);
    }
    onlineUsers.value = next;
  }

  void _forwardMessage(Map<String, dynamic>? data) {
    if (data == null || _messageEvents.isClosed) return;
    _messageEvents.add(Message.fromJson(data));
  }

  void _forwardActivity(Map<String, dynamic>? data) {
    if (data == null || _inboxEvents.isClosed) return;
    _inboxEvents.add(ConversationActivity.fromJson(data));
  }

  void _forwardLifecycle(Map<String, dynamic>? data, {required bool added}) {
    if (data == null || _lifecycleEvents.isClosed) return;
    final cid = int.tryParse((data['conversation_id'] ?? '').toString()) ?? 0;
    if (cid <= 0) return;
    _lifecycleEvents.add(ConversationLifecycle(
      conversationId: cid,
      added: added,
    ));
  }

  void _forwardRead(Map<String, dynamic>? data) {
    if (data == null || _readEvents.isClosed) return;
    _readEvents.add(MessageRead.fromJson(data));
  }

  void _forwardCallSignal(Map<String, dynamic>? data) {
    if (data == null || _callSignalEvents.isClosed) return;
    _callSignalEvents.add(CallSignal.fromJson(data));
  }

  void _forwardPin(Map<String, dynamic>? data, {required bool pinned}) {
    if (data == null || _pinEvents.isClosed) return;
    final convId =
        int.tryParse((data['conversation_id'] ?? '').toString()) ?? 0;
    final msgId = int.tryParse((data['message_id'] ?? '').toString()) ?? 0;
    if (convId <= 0 || msgId <= 0) return;
    _pinEvents.add(PinUpdate(
      conversationId: convId,
      messageId: msgId,
      pinned: pinned ? PinnedMessage.fromJson(data) : null,
    ));
  }

  void _forwardTyping(String channelName, Map<String, dynamic>? data) {
    if (data == null || _typingEvents.isClosed) return;
    const prefix = 'private-conv-';
    if (!channelName.startsWith(prefix)) return;
    final convId = int.tryParse(channelName.substring(prefix.length)) ?? 0;
    if (convId <= 0) return;
    final userId = int.tryParse((data['user_id'] ?? '').toString()) ?? 0;
    if (userId <= 0) return;
    _typingEvents.add(TypingEvent(
      conversationId: convId,
      userId: userId,
      username: (data['username'] ?? '').toString(),
    ));
  }
}
