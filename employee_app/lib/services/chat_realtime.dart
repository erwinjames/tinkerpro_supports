import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../api_client.dart';
import '../models/chat_models.dart';

/// Soketi connection config. By default the host is derived from the API
/// base URL so a single `--dart-define=TPS_BASE_URL=http://192.168.1.5/…`
/// configures both HTTP and WebSocket. Override only the bits that
/// genuinely differ from the API host:
///
///   --dart-define=CHAT_SOKETI_PORT=6001       # default 6001
///   --dart-define=CHAT_SOKETI_KEY=…           # default tinkerpro-chat-key
///   --dart-define=CHAT_SOKETI_TLS=true        # default: matches API scheme
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

  /// Build a config given the API base URL the rest of the app already
  /// uses. If [hostOverride] is set (via `--dart-define=CHAT_SOKETI_HOST`),
  /// that wins — useful when Soketi runs on a different host than PHP.
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
    if (host.isEmpty) host = '10.0.2.2';
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

  Uri wsUri() {
    final scheme = useTls ? 'wss' : 'ws';
    // Normalise the optional proxy prefix: '' → none; 'soketi' or '/soketi/'
    // → '/soketi'. The '/app/...' Pusher path is appended after it.
    final prefix =
        path.isEmpty ? '' : '/${path.replaceAll(RegExp(r'^/+|/+$'), '')}';
    return Uri.parse(
      '$scheme://$host:$port$prefix/app/$apiKey?protocol=7&client=tinkerpro-customer&version=1.0&flash=false',
    );
  }
}

/// Hand-rolled minimal Pusher-protocol client. Carbon copy of the staff
/// app's structure — implements only what the customer needs:
///   • subscribe to `private-user-{shadowId}`  (call.signal events)
///   • subscribe to `private-conv-{convId}`    (message.new / read / typing)
///   • re-subscribe on reconnect
class ChatRealtimeService {
  ChatRealtimeService(this.api, {ChatRealtimeConfig? config})
      : _config = config ?? ChatRealtimeConfig.fromBaseUrl(api.baseUrl);

  final ApiClient api;
  final ChatRealtimeConfig _config;

  WebSocketChannel? _socket;
  StreamSubscription<dynamic>? _socketSub;
  String? _socketId;
  bool _connected = false;
  bool _wantConnected = false;
  bool _disposed = false;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;

  final _subscribed = <String>{};
  final _pendingSubscribes = <String>{};

  final _messageEvents = StreamController<ChatMessage>.broadcast();
  final _typingEvents = StreamController<TypingEvent>.broadcast();
  final _readEvents = StreamController<MessageRead>.broadcast();
  final _deletedEvents = StreamController<int>.broadcast(); // message_id
  final _pinnedEvents = StreamController<PinnedEvent>.broadcast();
  final _callSignalEvents = StreamController<CallSignal>.broadcast();
  // Conversation-wide call presence — fires when a colleague in the
  // same support thread starts/ends a call so this terminal can grey
  // out its own call buttons and show a banner. Distinct from
  // _callSignalEvents (which is the per-user WebRTC offer/answer/ICE
  // relay).
  final _callPresenceEvents = StreamController<CallPresence>.broadcast();

  /// `conversation.created` — fired by the server when this user is
  /// added to a new conversation (e.g., another employee invited them
  /// via Add Participant). The chat screen listens here and prompts
  /// the user to switch their primary thread.
  final _conversationCreatedEvents =
      StreamController<ConversationInvite>.broadcast();

  Stream<ChatMessage> get messageEvents => _messageEvents.stream;
  Stream<TypingEvent> get typingEvents => _typingEvents.stream;
  Stream<MessageRead> get readEvents => _readEvents.stream;
  Stream<int> get messageDeletedEvents => _deletedEvents.stream;
  Stream<PinnedEvent> get pinnedEvents => _pinnedEvents.stream;
  Stream<CallSignal> get callSignalEvents => _callSignalEvents.stream;
  Stream<CallPresence> get callPresenceEvents => _callPresenceEvents.stream;
  Stream<ConversationInvite> get conversationCreatedEvents =>
      _conversationCreatedEvents.stream;

  bool get isConnected => _connected;

  Future<void> connect({required int shadowUserId, required int conversationId}) async {
    _wantConnected = true;
    _pendingSubscribes
      ..clear()
      ..add('private-user-$shadowUserId')
      ..add('private-conv-$conversationId');
    await _openSocket();
  }

  Future<void> pause() async {
    _wantConnected = false;
    await _closeSocket();
  }

  Future<void> resume({required int shadowUserId, required int conversationId}) async {
    _wantConnected = true;
    if (!_connected) {
      _pendingSubscribes
        ..clear()
        ..add('private-user-$shadowUserId')
        ..add('private-conv-$conversationId');
      await _openSocket();
    }
  }

  /// Subscribe to an additional `private-conv-{id}` channel at runtime.
  /// Used by the "Add participant → switch primary conv" flow: B's app
  /// subscribes to A's conv before unsubscribing from B's old one.
  Future<void> subscribeConversation(int conversationId) async {
    final ch = 'private-conv-$conversationId';
    _pendingSubscribes.add(ch);
    if (_connected) {
      await _sendSubscribe(ch);
    }
  }

  /// Unsubscribe and forget a `private-conv-{id}` channel. Counterpart
  /// to [subscribeConversation] for the conversation-switch flow.
  void unsubscribeConversation(int conversationId) {
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
    await _messageEvents.close();
    await _typingEvents.close();
    await _readEvents.close();
    await _deletedEvents.close();
    await _pinnedEvents.close();
    await _callSignalEvents.close();
    await _callPresenceEvents.close();
    await _conversationCreatedEvents.close();
  }

  // ── socket lifecycle ──────────────────────────────────────────────────

  Future<void> _openSocket() async {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    WebSocketChannel? channel;
    final uri = _config.wsUri();
    debugPrint('[chat-realtime] connecting to $uri');
    try {
      channel = WebSocketChannel.connect(uri);
      await channel.ready;
      if (_disposed) {
        await channel.sink.close();
        return;
      }
      _socket = channel;
      _socketSub = channel.stream.listen(
        _onMessage,
        onDone: _onSocketClosed,
        onError: (e, _) {
          debugPrint('[chat-realtime] socket error: $e');
          _onSocketClosed();
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('[chat-realtime] connect failed: $e');
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
    if (_wantConnected && !_disposed) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || !_wantConnected) return;
    _reconnectAttempts = (_reconnectAttempts + 1).clamp(1, 6);
    final delayMs = 500 * (1 << (_reconnectAttempts - 1));
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), _openSocket);
  }

  void _sendRaw(Map<String, dynamic> frame) {
    try {
      _socket?.sink.add(jsonEncode(frame));
    } catch (_) {}
  }

  // ── inbound dispatch ──────────────────────────────────────────────────

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

    switch (event) {
      case 'pusher:connection_established':
        _handleConnectionEstablished(data);
        break;
      case 'pusher:ping':
        _sendRaw({'event': 'pusher:pong', 'data': {}});
        break;
      case 'pusher_internal:subscription_succeeded':
      case 'pusher:subscription_succeeded':
        debugPrint(
            '[chat-realtime] subscribed to ${frame['channel']}');
        break;
      case 'pusher:subscription_error':
        debugPrint('[chat-realtime] subscription_error frame=$frame');
        break;
      case 'message.new':
        debugPrint(
            '[chat-realtime] message.new from sender=${data?['sender_id']} '
            'on ${frame['channel']}');
        if (data != null && !_messageEvents.isClosed) {
          _messageEvents.add(ChatMessage.fromJson(data));
        }
        break;
      case 'message.read':
        if (data != null && !_readEvents.isClosed) {
          _readEvents.add(MessageRead.fromJson(data));
        }
        break;
      case 'message.deleted':
        if (data != null && !_deletedEvents.isClosed) {
          final id = int.tryParse((data['message_id'] ?? 0).toString()) ?? 0;
          if (id > 0) {
            debugPrint('[chat-realtime] message.deleted id=$id');
            _deletedEvents.add(id);
          }
        }
        break;
      case 'message.pinned':
        if (data != null && !_pinnedEvents.isClosed) {
          _pinnedEvents.add(PinnedEvent(
            conversationId:
                int.tryParse((data['conversation_id'] ?? 0).toString()) ?? 0,
            messageId: int.tryParse((data['message_id'] ?? 0).toString()) ?? 0,
            pinned: true,
            entry: PinnedMessage.fromJson(data),
          ));
        }
        break;
      case 'message.unpinned':
        if (data != null && !_pinnedEvents.isClosed) {
          _pinnedEvents.add(PinnedEvent(
            conversationId:
                int.tryParse((data['conversation_id'] ?? 0).toString()) ?? 0,
            messageId: int.tryParse((data['message_id'] ?? 0).toString()) ?? 0,
            pinned: false,
          ));
        }
        break;
      case 'typing':
        final ch = (frame['channel'] ?? '').toString();
        const prefix = 'private-conv-';
        if (data != null && ch.startsWith(prefix) && !_typingEvents.isClosed) {
          final convId = int.tryParse(ch.substring(prefix.length)) ?? 0;
          final uid = int.tryParse((data['user_id'] ?? '').toString()) ?? 0;
          if (convId > 0 && uid > 0) {
            _typingEvents.add(TypingEvent(
              conversationId: convId,
              userId: uid,
              username: (data['username'] ?? '').toString(),
            ));
          }
        }
        break;
      case 'call.signal':
        if (data != null && !_callSignalEvents.isClosed) {
          _callSignalEvents.add(CallSignal.fromJson(data));
        }
        break;
      case 'call.presence':
        if (data != null && !_callPresenceEvents.isClosed) {
          _callPresenceEvents.add(CallPresence.fromJson(data));
        }
        break;
      case 'conversation.created':
        if (data != null && !_conversationCreatedEvents.isClosed) {
          final convId =
              int.tryParse((data['conversation_id'] ?? '').toString()) ?? 0;
          if (convId > 0) {
            _conversationCreatedEvents.add(ConversationInvite(
              conversationId: convId,
              inviterUserId: int.tryParse(
                      (data['inviter_user_id'] ?? '').toString()) ??
                  0,
              inviterName: (data['inviter_name'] ?? '').toString(),
            ));
          }
        }
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
    debugPrint(
        '[chat-realtime] connected, socket_id=$_socketId; subscribing to ${_pendingSubscribes.toList()}');
    for (final ch in _pendingSubscribes.toList()) {
      await _sendSubscribe(ch);
    }
  }

  Future<void> _sendSubscribe(String channelName) async {
    if (!_connected || _socketId == null) return;
    if (_subscribed.contains(channelName)) return;

    // Server's chat.pusherAuth uses chatResolveActor() → because we go
    // through `postChat` (which adds as_portal=1), the server resolves
    // the customer's shadow user even if the device cookie also has a
    // staff session. Without that flag, private-user-{shadowId} would
    // 403.
    final res = await api.postChat('chat.pusherAuth', body: {
      'socket_id': _socketId!,
      'channel_name': channelName,
    });
    final auth = res['auth'];
    if (auth is! String || auth.isEmpty) {
      debugPrint('[chat-realtime] auth failed for $channelName: $res');
      return;
    }
    final payload = <String, dynamic>{
      'channel': channelName,
      'auth': auth,
    };
    if (res['channel_data'] is String) {
      payload['channel_data'] = res['channel_data'];
    }
    _sendRaw({'event': 'pusher:subscribe', 'data': payload});
    _subscribed.add(channelName);
  }
}

/// Payload of a `conversation.created` Soketi event — the server fired
/// it because someone added us to a new chat conversation. The chat
/// screen surfaces a Join? prompt with the inviter's display name.
class ConversationInvite {
  ConversationInvite({
    required this.conversationId,
    required this.inviterUserId,
    required this.inviterName,
  });

  final int conversationId;
  final int inviterUserId;
  final String inviterName;
}
