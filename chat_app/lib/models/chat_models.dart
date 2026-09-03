class ChatUser {
  ChatUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    required this.presence,
    this.avatar,
    this.lastSeenAt,
  });

  final int id;
  final String username;
  final String fullName;
  final String role;
  final String presence;

  final String? avatar;
  final String? lastSeenAt;

  String get displayName => fullName.isNotEmpty ? fullName : username;
  bool get isOnline => presence == 'online';

  factory ChatUser.fromJson(Map<String, dynamic> j) => ChatUser(
        id: _asInt(j['id']),
        username: (j['username'] ?? '').toString(),
        fullName: (j['full_name'] ?? '').toString(),
        role: (j['role'] ?? 'user').toString(),
        presence: (j['presence'] ?? 'offline').toString(),
        avatar: j['avatar']?.toString(),
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
    this.source = 'internal',
    this.guestStatus = 'none',
    this.priority = 0,
    this.archived = 0,
    this.fbRequest = 0,
    this.fbMoved = 0,
    this.fbAssignedTo,
    this.fbAiOwned = 0,
    this.fbPsid = '',
    this.fbPageId = '',
  });

  final int id;
  final String type;
  final String visibility;
  final String name;
  final String? topic;
  final ChatUser? peer;
  final Message? lastMessage;
  final int unreadCount;
  final String lastActivityAt;
  final int participantCount;
  final String source;
  final String guestStatus;
  final int priority;
  final int archived;
  final int fbRequest;
  final int fbMoved;
  final int? fbAssignedTo;
  final int fbAiOwned;
  final String fbPsid;
  final String fbPageId;

  bool get isFacebook => source == 'facebook';

  bool get isGuest =>
      source == 'guest' || (guestStatus.isNotEmpty && guestStatus != 'none');

  /// Anything that isn't an internal staff thread: Facebook page chats,
  /// customer and vendor portal threads, and guest sessions.
  bool get isExternal => source != 'internal' || isGuest;

  bool get isAiOwned => fbAiOwned == 1;

  bool get isPriority => priority != 0;

  bool get isArchived => archived != 0;

  /// Mirrors the web inbox: an unclaimed Facebook thread sitting in the
  /// queue, i.e. not yet moved into the main inbox and not flagged priority.
  bool get isFacebookRequest => isFacebook && fbMoved == 0 && priority == 0;

  Conversation copyWith({
    Message? lastMessage,
    int? unreadCount,
    String? lastActivityAt,
    int? archived,
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
      source: source,
      guestStatus: guestStatus,
      priority: priority,
      archived: archived ?? this.archived,
      fbRequest: fbRequest,
      fbMoved: fbMoved,
      fbAssignedTo: fbAssignedTo,
      fbAiOwned: fbAiOwned,
      fbPsid: fbPsid,
      fbPageId: fbPageId,
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
        source: (j['source'] ?? _sourceFromTopic(j['topic'])).toString(),
        guestStatus: (j['guest_status'] ?? 'none').toString(),
        priority: _asInt(j['priority']),
        archived: _asInt(j['archived']),
        fbRequest: _asInt(j['fb_request']),
        fbMoved: _asInt(j['fb_moved']),
        fbAssignedTo:
            j['fb_assigned_to'] == null ? null : _asInt(j['fb_assigned_to']),
        fbAiOwned: _asInt(j['fb_ai_owned']),
        fbPsid: (j['fb_psid'] ?? '').toString(),
        fbPageId: (j['fb_page_id'] ?? '').toString(),
      );
}

/// Fallback for payloads that predate the `source` field (and for
/// `chat.conversation`, which doesn't always send it). Mirrors the server's
/// ChatFacade::conversationSource topic-prefix rules.
String _sourceFromTopic(dynamic topic) {
  final t = (topic ?? '').toString();
  if (t.startsWith('fb:')) return 'facebook';
  if (t.startsWith('customer:')) return 'customer';
  if (t.startsWith('vendor:')) return 'vendor';
  return 'internal';
}

class Message {
  Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.body,
    required this.clientNonce,
    required this.createdAt,
    this.senderAlias = '',
    this.fbDelivery,
    this.attachments = const [],
    this.status = MessageStatus.sent,
  });

  final int? id;
  final int conversationId;
  final int senderId;
  final String body;
  final String clientNonce;
  final String createdAt;

  /// Name the recipient sees for the sender: a per-conversation alias, the
  /// agent's saved alias, or the Facebook visitor's own name.
  final String senderAlias;

  /// Messenger delivery state for a Facebook thread: `sent`, `failed`, or
  /// `blocked` (the Page AI still owns the thread). Null off Facebook.
  final String? fbDelivery;

  bool get fbUndelivered => fbDelivery == 'failed' || fbDelivery == 'blocked';
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
      senderAlias: senderAlias,
      fbDelivery: fbDelivery,
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
      senderAlias: (j['sender_alias'] ?? '').toString(),
      fbDelivery: j['fb_delivery']?.toString(),
      attachments: attachments,
      status: MessageStatus.sent,
    );
  }
}

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

enum TicketKind { submitted, accepted, resolved }

class TicketRef {
  const TicketRef(this.kind, this.id);
  final TicketKind kind;
  final int id;
}

final RegExp _ticketReSubmitted =
    RegExp(r'🎫\s*Ticket\s*#(\d+)\s+submitted', caseSensitive: false, unicode: true);
final RegExp _ticketReResolved =
    RegExp(r'✅[^\n]*ticket\s*#(\d+)', caseSensitive: false, unicode: true);
final RegExp _ticketReAccepted =
    RegExp(r'👋[^\n]*ticket\s*#(\d+)', caseSensitive: false, unicode: true);

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

class TicketStatusInfo {
  const TicketStatusInfo({
    required this.status,
    this.assignedAgentId,
    this.agentName,
    this.conversationId,
  });

  final String status;
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

class ConversationReadSync {
  ConversationReadSync({
    required this.conversationId,
    required this.lastReadMessageId,
    required this.unreadCount,
  });

  final int conversationId;
  final int lastReadMessageId;
  final int unreadCount;

  factory ConversationReadSync.fromJson(Map<String, dynamic> j) {
    return ConversationReadSync(
      conversationId: _asInt(j['conversation_id']),
      lastReadMessageId: _asInt(j['last_read_message_id']),
      unreadCount: _asInt(j['unread_count']),
    );
  }
}

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

class ConversationLifecycle {
  ConversationLifecycle({
    required this.conversationId,
    required this.added,
  });
  final int conversationId;
  final bool added;
}

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
  final String visibility;
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

class ConversationMember {
  ConversationMember({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    required this.presence,
    required this.joinedAt,
    this.avatar,
    this.lastSeenAt,
  });

  final int id;
  final String username;
  final String fullName;
  final String role;
  final String presence;
  final String joinedAt;
  final String? avatar;
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
        avatar: j['avatar']?.toString(),
        lastSeenAt: j['last_seen_at']?.toString(),
      );
}

class ConversationDetail {
  ConversationDetail({
    required this.conversation,
    required this.participants,
  });

  final Map<String, dynamic> conversation;
  final List<ConversationMember> participants;

  int get id => _asInt(conversation['id']);
  String get type => (conversation['type'] ?? '').toString();
  String get visibility => (conversation['visibility'] ?? 'public').toString();
  String get name => (conversation['name'] ?? '').toString();
  String? get topic => conversation['topic']?.toString();
  int get createdBy => _asInt(conversation['created_by']);

  String get source =>
      (conversation['source'] ?? _sourceFromTopic(conversation['topic']))
          .toString();

  String get guestStatus =>
      (conversation['guest_status'] ?? 'none').toString();

  bool get isGuest =>
      source == 'guest' || (guestStatus.isNotEmpty && guestStatus != 'none');

  bool get isExternal => source != 'internal' || isGuest;
}

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
      fromId: int.tryParse((j['from_id'] ?? '').toString()) ?? 0,
      fromName: (j['from_name'] ?? '').toString(),
      payload: payload,
    );
  }
}

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

/// Mirrors the web app's QUOTE_RE: `> @Sender [#id]: preview`, a blank
/// line, then the reply body.
final RegExp _kQuoteRe = RegExp(
  r'^>\s*@([^\[:\n]+?)(?:\s*\[#(\d+)\])?\s*:[ \t]*([^\n]*?)(?:\r?\n\r?\n([\s\S]+))?$',
);

class QuotedBody {
  const QuotedBody({
    required this.sender,
    required this.targetId,
    required this.preview,
    required this.reply,
  });

  final String sender;
  final int? targetId;
  final String preview;
  final String reply;
}

QuotedBody? parseQuotedBody(String body) {
  final m = _kQuoteRe.firstMatch(body.trim());
  if (m == null) return null;
  final preview = (m.group(3) ?? '').trim();
  return QuotedBody(
    sender: (m.group(1) ?? '').trim(),
    targetId: int.tryParse(m.group(2) ?? ''),
    preview: preview.isEmpty ? '[attachment]' : preview,
    reply: (m.group(4) ?? '').trim(),
  );
}
