/// Chat-side models for the customer app. Mirrors the JSON shapes the
/// `chat.*` PHP endpoints return — kept lean since the customer's view is
/// always one fixed group (their support thread), not a full inbox.

class ChatParticipant {
  ChatParticipant({
    required this.userId,
    required this.username,
    required this.fullName,
    required this.role,
  });

  final int userId;
  final String username;
  final String fullName;
  final String role;

  String get displayName =>
      fullName.trim().isNotEmpty ? fullName : (username.isEmpty ? 'User $userId' : username);

  factory ChatParticipant.fromJson(Map<String, dynamic> j) => ChatParticipant(
        userId: int.tryParse((j['user_id'] ?? j['id'] ?? 0).toString()) ?? 0,
        username: (j['username'] ?? '').toString(),
        fullName: (j['full_name'] ?? '').toString(),
        role: (j['role'] ?? '').toString(),
      );
}

class ChatAttachment {
  ChatAttachment({
    required this.id,
    required this.mimeType,
    required this.byteSize,
    required this.originalName,
    this.width,
    this.height,
  });

  final int id;
  final String mimeType;
  final int byteSize;
  final String originalName;
  final int? width;
  final int? height;

  bool get isImage => mimeType.startsWith('image/');

  factory ChatAttachment.fromJson(Map<String, dynamic> j) => ChatAttachment(
        id: int.tryParse((j['id'] ?? 0).toString()) ?? 0,
        mimeType: (j['mime_type'] ?? '').toString(),
        byteSize: int.tryParse((j['byte_size'] ?? 0).toString()) ?? 0,
        originalName: (j['original_name'] ?? '').toString(),
        width: j['width'] == null ? null : int.tryParse(j['width'].toString()),
        height:
            j['height'] == null ? null : int.tryParse(j['height'].toString()),
      );
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.body,
    required this.clientNonce,
    required this.createdAt,
    required this.attachments,
    this.optimistic = false,
  });

  /// Server id (>0) for persisted messages, or `'tmp-…'` for optimistic
  /// rows that haven't been confirmed yet. Stored as a string so the
  /// type lines up across both cases — cast to int when you need to
  /// compare against e.g. read cursors.
  final Object id;
  final int conversationId;
  final int senderId;
  final String body;
  final String clientNonce;
  final String createdAt;
  final List<ChatAttachment> attachments;
  final bool optimistic;

  bool get isPersisted => id is int;
  int? get persistedId => id is int ? id as int : null;

  factory ChatMessage.fromJson(Map<String, dynamic> j) {
    final atts = <ChatAttachment>[];
    final raw = j['attachments'];
    if (raw is List) {
      for (final a in raw) {
        if (a is Map) {
          atts.add(ChatAttachment.fromJson(Map<String, dynamic>.from(a)));
        }
      }
    }
    return ChatMessage(
      id: int.tryParse((j['id'] ?? 0).toString()) ?? 0,
      conversationId:
          int.tryParse((j['conversation_id'] ?? 0).toString()) ?? 0,
      senderId: int.tryParse((j['sender_id'] ?? 0).toString()) ?? 0,
      body: (j['body'] ?? '').toString(),
      clientNonce: (j['client_nonce'] ?? '').toString(),
      createdAt: (j['created_at'] ?? '').toString(),
      attachments: atts,
    );
  }

  ChatMessage copyWith({
    Object? id,
    String? body,
    String? clientNonce,
    String? createdAt,
    List<ChatAttachment>? attachments,
    bool? optimistic,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      conversationId: conversationId,
      senderId: senderId,
      body: body ?? this.body,
      clientNonce: clientNonce ?? this.clientNonce,
      createdAt: createdAt ?? this.createdAt,
      attachments: attachments ?? this.attachments,
      optimistic: optimistic ?? this.optimistic,
    );
  }
}

/// Decoded WebRTC signaling frame coming off `private-user-{me}`.
/// Identical shape to the staff app's CallSignal so the call service can
/// be ported without translation.
class CallSignal {
  CallSignal({
    required this.kind,
    required this.callId,
    required this.media,
    required this.fromId,
    required this.fromName,
    required this.payload,
  });

  final String kind;
  final String callId;
  final String media;
  final int fromId;
  final String fromName;
  final Map<String, dynamic>? payload;

  factory CallSignal.fromJson(Map<String, dynamic> j) {
    Map<String, dynamic>? payload;
    final raw = j['payload'];
    if (raw is Map) payload = Map<String, dynamic>.from(raw);
    return CallSignal(
      kind: (j['kind'] ?? '').toString(),
      callId: (j['call_id'] ?? '').toString(),
      media: (j['media'] ?? 'voice').toString(),
      fromId: int.tryParse((j['from_id'] ?? 0).toString()) ?? 0,
      fromName: (j['from_name'] ?? '').toString(),
      payload: payload,
    );
  }
}

/// Conversation-wide call-presence event broadcast on
/// `private-conv-{id}`. Lets colleagues in the same support thread
/// (multi-terminal install) see when one of them starts/ends a call so
/// the chat screen can grey out the call buttons on every *other*
/// terminal and surface a "`<name>` is on a call" banner.
///
/// Distinct from [CallSignal] — that's the per-user WebRTC relay.
class CallPresence {
  CallPresence({
    required this.fromId,
    required this.fromName,
    required this.state,
    required this.media,
    required this.callId,
    required this.sentAt,
  });

  final int fromId;
  final String fromName;
  final String state; // 'busy' | 'free'
  final String media; // 'voice' | 'video'
  final String callId;
  final DateTime sentAt;

  bool get isBusy => state == 'busy';
  bool get isFree => state == 'free';

  factory CallPresence.fromJson(Map<String, dynamic> j) {
    final epoch = int.tryParse((j['sent_at'] ?? 0).toString()) ?? 0;
    return CallPresence(
      fromId: int.tryParse((j['from_id'] ?? 0).toString()) ?? 0,
      fromName: (j['from_name'] ?? '').toString(),
      state: (j['state'] ?? '').toString(),
      media: (j['media'] ?? 'voice').toString(),
      callId: (j['call_id'] ?? '').toString(),
      sentAt: epoch > 0
          ? DateTime.fromMillisecondsSinceEpoch(epoch * 1000)
          : DateTime.now(),
    );
  }
}

/// Small typing event broadcast on `private-conv-{id}`.
class TypingEvent {
  TypingEvent({
    required this.conversationId,
    required this.userId,
    required this.username,
  });
  final int conversationId;
  final int userId;
  final String username;
}

/// Read-cursor fan-out broadcast on `private-conv-{id}`.
class MessageRead {
  MessageRead({required this.userId, required this.lastReadMessageId});
  final int userId;
  final int lastReadMessageId;
  factory MessageRead.fromJson(Map<String, dynamic> j) => MessageRead(
        userId: int.tryParse((j['user_id'] ?? 0).toString()) ?? 0,
        lastReadMessageId:
            int.tryParse((j['last_read_message_id'] ?? 0).toString()) ?? 0,
      );
}
