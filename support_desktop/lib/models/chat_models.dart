/// Data classes for the chat MVP. Thin wrappers over the JSON shapes
/// returned by `api.php?action=chat.*`. Field names match the backend
/// `docs/chat-mvp-design.md` Part V contract.

class ChatUser {
  ChatUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    required this.presence,
    this.lastSeenAt,
  });

  final int id;
  final String username;
  final String fullName;
  final String role;
  final String presence; // 'online' | 'offline'

  /// `null` if we've never seen this user online before. Server-supplied
  /// "YYYY-MM-DD HH:MM:SS" string; formatters parse it lazily.
  final String? lastSeenAt;

  String get displayName => fullName.isNotEmpty ? fullName : username;
  bool get isOnline => presence == 'online';

  factory ChatUser.fromJson(Map<String, dynamic> j) => ChatUser(
        id: _asInt(j['id']),
        username: (j['username'] ?? '').toString(),
        fullName: (j['full_name'] ?? '').toString(),
        role: (j['role'] ?? 'user').toString(),
        presence: (j['presence'] ?? 'offline').toString(),
        lastSeenAt: j['last_seen_at']?.toString(),
      );
}

class Conversation {
  Conversation({
    required this.id,
    required this.type,
    required this.visibility,
    required this.name,
    required this.topic,
    required this.peer,
    required this.lastMessage,
    required this.unreadCount,
    required this.lastActivityAt,
    required this.participantCount,
  });

  final int id;
  final String type;        // 'dm' | 'group' | 'channel'
  final String visibility;  // 'public' | 'private'
  final String name;
  final String? topic;
  final ChatUser? peer;     // DMs only
  final Message? lastMessage;
  final int unreadCount;
  final String lastActivityAt;
  final int participantCount;

  Conversation copyWith({
    Message? lastMessage,
    int? unreadCount,
    String? lastActivityAt,
  }) {
    return Conversation(
      id: id,
      type: type,
      visibility: visibility,
      name: name,
      topic: topic,
      peer: peer,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
      lastActivityAt: lastActivityAt ?? this.lastActivityAt,
      participantCount: participantCount,
    );
  }

  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
        id: _asInt(j['id']),
        type: (j['type'] ?? 'dm').toString(),
        visibility: (j['visibility'] ?? 'public').toString(),
        name: (j['name'] ?? '').toString(),
        topic: j['topic']?.toString(),
        peer: j['peer'] is Map
            ? ChatUser.fromJson(Map<String, dynamic>.from(j['peer'] as Map))
            : null,
        lastMessage: j['last_message'] is Map
            ? Message.fromJson(Map<String, dynamic>.from(j['last_message'] as Map))
            : null,
        unreadCount: _asInt(j['unread_count']),
        lastActivityAt: (j['last_activity_at'] ?? '').toString(),
        participantCount: _asInt(j['participant_count']),
      );
}

class Message {
  Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.body,
    required this.clientNonce,
    required this.createdAt,
    this.attachments = const [],
    this.status = MessageStatus.sent,
  });

  /// `null` for an optimistic row that hasn't yet been assigned an id by
  /// the server. Reconciled by `clientNonce` once the server responds.
  final int? id;
  final int conversationId;
  final int senderId;
  final String body;
  final String clientNonce;
  final String createdAt;
  final List<Attachment> attachments;
  final MessageStatus status;

  bool get hasAttachments => attachments.isNotEmpty;

  Message copyWith({
    int? id,
    String? createdAt,
    List<Attachment>? attachments,
    MessageStatus? status,
  }) {
    return Message(
      id: id ?? this.id,
      conversationId: conversationId,
      senderId: senderId,
      body: body,
      clientNonce: clientNonce,
      createdAt: createdAt ?? this.createdAt,
      attachments: attachments ?? this.attachments,
      status: status ?? this.status,
    );
  }

  factory Message.fromJson(Map<String, dynamic> j) {
    final rawAtt = j['attachments'];
    final attachments = <Attachment>[];
    if (rawAtt is List) {
      for (final a in rawAtt) {
        if (a is Map) {
          attachments.add(Attachment.fromJson(Map<String, dynamic>.from(a)));
        }
      }
    }
    return Message(
      id: j['id'] == null ? null : _asInt(j['id']),
      conversationId: _asInt(j['conversation_id']),
      senderId: _asInt(j['sender_id']),
      body: (j['body'] ?? '').toString(),
      clientNonce: (j['client_nonce'] ?? '').toString(),
      createdAt: (j['created_at'] ?? '').toString(),
      attachments: attachments,
      status: MessageStatus.sent,
    );
  }
}

/// Wire shape for `chat.uploadAttachment` / messages' `attachments[]`.
/// Points to a server-streamed file at `api.php?action=chat.downloadAttachment&id=X`.
class Attachment {
  Attachment({
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

  /// Human-readable size: "12 KB", "2.4 MB", etc.
  String formattedSize() {
    if (byteSize < 1024) return '$byteSize B';
    final kb = byteSize / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  }

  factory Attachment.fromJson(Map<String, dynamic> j) => Attachment(
        id: _asInt(j['id']),
        mimeType: (j['mime_type'] ?? 'application/octet-stream').toString(),
        byteSize: _asInt(j['byte_size']),
        originalName: (j['original_name'] ?? 'attachment').toString(),
        width: j['width'] == null ? null : _asInt(j['width']),
        height: j['height'] == null ? null : _asInt(j['height']),
      );
}

enum MessageStatus { sending, sent, failed }

// ─────────────────────────────────────────────── tickets in chat ──────────
// Mirrors the web chat (chat.php): system messages announce a ticket's
// lifecycle, and staff can Accept (claim) / Resolve them inline. We detect
// the ticket from the message body using the same emoji + "#<number>"
// conventions the server writes, then fetch live status via getTicketsByIds.

enum TicketKind { submitted, accepted, resolved }

/// A ticket reference detected inside a chat message body. [id] is the public
/// ticket number the server embeds (e.g. "Ticket #456789").
class TicketRef {
  const TicketRef(this.kind, this.id);
  final TicketKind kind;
  final int id;
}

// Same patterns as chat.php (TICKET_RE_SUBMITTED / _ACCEPTED / _RESOLVED).
final RegExp _ticketReSubmitted =
    RegExp(r'🎫\s*Ticket\s*#(\d+)\s+submitted', caseSensitive: false, unicode: true);
final RegExp _ticketReResolved =
    RegExp(r'✅[^\n]*ticket\s*#(\d+)', caseSensitive: false, unicode: true);
final RegExp _ticketReAccepted =
    RegExp(r'👋[^\n]*ticket\s*#(\d+)', caseSensitive: false, unicode: true);

/// Detect a ticket reference in a message body, or null if none. Resolution
/// order matches the web client: submitted → resolved → accepted.
TicketRef? detectTicketRef(String? body) {
  if (body == null || body.isEmpty) return null;
  var m = _ticketReSubmitted.firstMatch(body);
  if (m != null) return TicketRef(TicketKind.submitted, int.parse(m.group(1)!));
  m = _ticketReResolved.firstMatch(body);
  if (m != null) return TicketRef(TicketKind.resolved, int.parse(m.group(1)!));
  m = _ticketReAccepted.firstMatch(body);
  if (m != null) return TicketRef(TicketKind.accepted, int.parse(m.group(1)!));
  return null;
}

/// Live status for a ticket, from `getTicketsByIds`. Keyed in the caller by
/// the same public ticket number [detectTicketRef] returns.
class TicketStatusInfo {
  const TicketStatusInfo({
    required this.status,
    this.assignedAgentId,
    this.agentName,
    this.conversationId,
  });

  final String status; // new | in_progress | assigned | resolved | closed
  final int? assignedAgentId;
  final String? agentName;
  final int? conversationId;

  bool get isNew => status == 'new';
  bool get isInProgress => status == 'in_progress' || status == 'assigned';
  bool get isResolved => status == 'resolved';
  bool get isClosed => status == 'closed';

  factory TicketStatusInfo.fromJson(Map<String, dynamic> j) => TicketStatusInfo(
        status: (j['status'] ?? 'new').toString(),
        assignedAgentId:
            j['assigned_agent_id'] == null ? null : _asInt(j['assigned_agent_id']),
        agentName: (j['agent_name'] == null || j['agent_name'].toString().isEmpty)
            ? null
            : j['agent_name'].toString(),
        conversationId:
            j['conversation_id'] == null ? null : _asInt(j['conversation_id']),
      );
}

/// Full ticket row from `chat.getTicketDetail`, shown in the detail sheet.
class TicketDetail {
  const TicketDetail({
    required this.id,
    required this.ticketNumber,
    required this.subject,
    required this.description,
    required this.status,
    required this.priority,
    this.customerName,
    this.businessName,
    this.agentName,
    this.createdAt,
  });

  final int id;
  final int? ticketNumber;
  final String subject;
  final String description;
  final String status;
  final String priority;
  final String? customerName;
  final String? businessName;
  final String? agentName;
  final String? createdAt;

  factory TicketDetail.fromJson(Map<String, dynamic> j) => TicketDetail(
        id: _asInt(j['id']),
        ticketNumber:
            j['ticket_number'] == null ? null : _asInt(j['ticket_number']),
        subject: (j['subject'] ?? '').toString(),
        description: (j['description'] ?? '').toString(),
        status: (j['status'] ?? 'new').toString(),
        priority: (j['priority'] ?? 'medium').toString(),
        customerName: (j['customer_name'] ?? '').toString().isEmpty
            ? null
            : j['customer_name'].toString(),
        businessName: (j['business_name'] ?? '').toString().isEmpty
            ? null
            : j['business_name'].toString(),
        agentName: (j['agent_name'] ?? '').toString().isEmpty
            ? null
            : j['agent_name'].toString(),
        createdAt: (j['created_at'] ?? '').toString().isEmpty
            ? null
            : j['created_at'].toString(),
      );
}

class MessagePage {
  MessagePage({required this.messages, required this.hasMore});
  final List<Message> messages;
  final bool hasMore;
}

/// Wire payload for `conversation.activity` events on `private-user-{id}`.
class ConversationActivity {
  ConversationActivity({
    required this.conversationId,
    required this.lastMessageId,
    required this.lastSenderId,
    required this.preview,
    required this.createdAt,
    required this.unreadCount,
  });

  final int conversationId;
  final int lastMessageId;
  final int lastSenderId;
  final String preview;
  final String createdAt;
  final int unreadCount;

  factory ConversationActivity.fromJson(Map<String, dynamic> j) {
    final last = j['last_message'] is Map
        ? Map<String, dynamic>.from(j['last_message'] as Map)
        : const <String, dynamic>{};
    return ConversationActivity(
      conversationId: _asInt(j['conversation_id']),
      lastMessageId: _asInt(last['id']),
      lastSenderId: _asInt(last['sender_id']),
      preview: (last['preview'] ?? '').toString(),
      createdAt: (last['created_at'] ?? '').toString(),
      unreadCount: _asInt(j['unread_count']),
    );
  }
}

/// Wire payload for `message.read` events on `private-conv-{id}`. Tells the
/// thread that participant `userId`'s read cursor has advanced to
/// `messageId`. Drives the "Seen by N" indicator.
class MessageRead {
  MessageRead({
    required this.messageId,
    required this.userId,
    required this.readAt,
  });
  final int messageId;
  final int userId;
  final String readAt;

  factory MessageRead.fromJson(Map<String, dynamic> j) => MessageRead(
        messageId: _asInt(j['message_id']),
        userId: _asInt(j['user_id']),
        readAt: (j['read_at'] ?? '').toString(),
      );
}

/// Wire payload for `conversation.created` / `conversation.removed` events.
/// Compact by design — the receiver rehydrates the full conversation via
/// REST so we don't have to pay the cost of shipping full metadata on the
/// Pusher channel.
class ConversationLifecycle {
  ConversationLifecycle({
    required this.conversationId,
    required this.added,
  });
  final int conversationId;
  final bool added; // true = added; false = removed
}

/// Row shape returned by `chat.channels`. Used by the channel browser to
/// render "Joined" vs a "Join" affordance.
class ChannelBrief {
  ChannelBrief({
    required this.id,
    required this.name,
    required this.topic,
    required this.visibility,
    required this.memberCount,
    required this.joined,
  });

  final int id;
  final String name;
  final String? topic;
  final String visibility; // 'public' | 'private'
  final int memberCount;
  final bool joined;

  bool get isPrivate => visibility == 'private';

  factory ChannelBrief.fromJson(Map<String, dynamic> j) => ChannelBrief(
        id: _asInt(j['id']),
        name: (j['name'] ?? '').toString(),
        topic: j['topic']?.toString(),
        visibility: (j['visibility'] ?? 'public').toString(),
        memberCount: _asInt(j['member_count']),
        joined: j['joined'] == true,
      );
}

/// Row shape returned by `chat.conversation` → `participants[]`.
class ConversationMember {
  ConversationMember({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    required this.presence,
    required this.joinedAt,
    this.lastSeenAt,
  });

  final int id;
  final String username;
  final String fullName;
  final String role;
  final String presence;
  final String joinedAt;
  final String? lastSeenAt;

  String get displayName => fullName.isNotEmpty ? fullName : username;
  bool get isOnline => presence == 'online';

  factory ConversationMember.fromJson(Map<String, dynamic> j) =>
      ConversationMember(
        id: _asInt(j['id']),
        username: (j['username'] ?? '').toString(),
        fullName: (j['full_name'] ?? '').toString(),
        role: (j['role'] ?? 'user').toString(),
        presence: (j['presence'] ?? 'offline').toString(),
        joinedAt: (j['joined_at'] ?? '').toString(),
        lastSeenAt: j['last_seen_at']?.toString(),
      );
}

/// Response from `chat.conversation`: metadata + full participant list.
class ConversationDetail {
  ConversationDetail({
    required this.conversation,
    required this.participants,
  });

  /// Minimal metadata (id/type/visibility/name/topic/participant_count).
  /// Full Conversation object would require the peer + last_message joins
  /// which this endpoint doesn't compute — that's what the inbox is for.
  final Map<String, dynamic> conversation;
  final List<ConversationMember> participants;

  int get id => _asInt(conversation['id']);
  String get type => (conversation['type'] ?? '').toString();
  String get visibility => (conversation['visibility'] ?? 'public').toString();
  String get name => (conversation['name'] ?? '').toString();
  String? get topic => conversation['topic']?.toString();
  int get createdBy => _asInt(conversation['created_by']);
}

/// Ephemeral `typing` event on `private-conv-{id}`. No persistence — drives
/// a short-lived "X is typing…" indicator in the open thread.
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

/// A message pinned to a conversation. Support agents pin messages so the
/// next agent sees standing instructions at the top. Mirrors the server
/// `chat.listPinned` / `chat.pinMessage` entry shape.
class PinnedMessage {
  PinnedMessage({
    required this.conversationId,
    required this.messageId,
    required this.senderId,
    required this.senderName,
    required this.body,
    required this.createdAt,
    required this.pinnedBy,
    required this.pinnedAt,
  });

  final int conversationId;
  final int messageId;
  final int senderId;
  final String senderName;
  final String body;
  final String createdAt;
  final int pinnedBy;
  final String pinnedAt;

  factory PinnedMessage.fromJson(Map<String, dynamic> j) => PinnedMessage(
        conversationId: _asInt(j['conversation_id']),
        messageId: _asInt(j['message_id']),
        senderId: _asInt(j['sender_id']),
        senderName: (j['sender_name'] ?? '').toString(),
        body: (j['body'] ?? '').toString(),
        createdAt: (j['created_at'] ?? '').toString(),
        pinnedBy: _asInt(j['pinned_by']),
        pinnedAt: (j['pinned_at'] ?? '').toString(),
      );
}

/// Realtime pin/unpin delta forwarded from `message.pinned` /
/// `message.unpinned`. [pinned] is the entry when a message was pinned, and
/// null when it was unpinned.
class PinUpdate {
  PinUpdate({
    required this.conversationId,
    required this.messageId,
    required this.pinned,
  });
  final int conversationId;
  final int messageId;
  final PinnedMessage? pinned;
  bool get isPinned => pinned != null;
}

/// One frame of WebRTC signaling forwarded by the server. Wraps the raw
/// `call.signal` event from `private-user-{me}`. Payload is opaque to the
/// transport layer — caller/callee state machines decode it as SDP, ICE,
/// or null depending on [kind].
class CallSignal {
  CallSignal({
    required this.kind,
    required this.callId,
    required this.media,
    required this.fromId,
    required this.fromName,
    required this.payload,
  });

  /// 'offer' | 'answer' | 'ice' | 'ringing' | 'accept' | 'decline' | 'end' | 'busy'
  final String kind;
  final String callId;

  /// 'voice' | 'video'
  final String media;
  final int fromId;
  final String fromName;

  /// SDP map (`{sdp, type}`), ICE candidate map, or null for control kinds.
  final Map<String, dynamic>? payload;

  factory CallSignal.fromJson(Map<String, dynamic> j) {
    Map<String, dynamic>? payload;
    final raw = j['payload'];
    if (raw is Map) payload = Map<String, dynamic>.from(raw);
    return CallSignal(
      kind: (j['kind'] ?? '').toString(),
      callId: (j['call_id'] ?? '').toString(),
      media: (j['media'] ?? 'voice').toString(),
      fromId: int.tryParse((j['from_id'] ?? '').toString()) ?? 0,
      fromName: (j['from_name'] ?? '').toString(),
      payload: payload,
    );
  }
}

/// Compact "last seen" formatter shared by the DM header, participants list,
/// and anywhere else that wants to display a presence timestamp. Returns:
///   online     → 'ONLINE'
///   < 60s      → 'NOW'
///   < 60m      → '{n}M AGO'
///   same day   → 'TODAY HH:MM'
///   < 7 days   → 'Mon HH:MM' (abbreviated weekday)
///   older      → '05 APR'
///   no data    → null (caller decides whether to render anything)
String? formatLastSeen({required bool online, String? lastSeenAt}) {
  if (online) return 'ONLINE';
  if (lastSeenAt == null || lastSeenAt.isEmpty) return null;
  DateTime? dt;
  try {
    dt = DateTime.parse(lastSeenAt.replaceAll(' ', 'T'));
  } catch (_) {
    return null;
  }
  final now = DateTime.now();
  final diff = now.difference(dt);

  if (diff.inSeconds < 60) return 'NOW';
  if (diff.inMinutes < 60) return '${diff.inMinutes}M AGO';

  final sameDay =
      dt.year == now.year && dt.month == now.month && dt.day == now.day;
  String hhmm() =>
      '${dt!.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  if (sameDay) return 'TODAY ${hhmm()}';
  if (diff.inDays < 7) {
    const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    return '${days[dt.weekday - 1]} ${hhmm()}';
  }
  const months = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];
  return '${dt.day.toString().padLeft(2, '0')} ${months[dt.month - 1]}';
}

int _asInt(Object? value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}
