class ActivityLog {
  ActivityLog({
    required this.id,
    required this.userId,
    required this.action,
    required this.details,
    required this.ipAddress,
    required this.createdAt,
    required this.username,
    this.location = '',
    this.locationCity = '',
    this.locationStatus = '',
    this.locationZip = '',
    this.isp = '',
    this.locationLat,
    this.locationLon,
    this.ipV4 = '',
    this.ipLan = '',
    this.gpsLat,
    this.gpsLon,
    this.gpsAccuracyM,
  });

  final int id;
  final int userId;
  final String action;
  final String details;
  final String ipAddress;
  final String createdAt;
  final String username;

  final String location;
  final String locationCity;
  final String locationStatus;
  final String locationZip;
  final String isp;
  final double? locationLat;
  final double? locationLon;

  final String ipV4;
  final String ipLan;
  final double? gpsLat;
  final double? gpsLon;
  final int? gpsAccuracyM;

  bool get hasDeviceFix => gpsLat != null && gpsLon != null;

  bool get hasIpFix =>
      locationStatus == 'success' && locationLat != null && locationLon != null;

  bool get hasCoords => hasDeviceFix || hasIpFix;

  double? get lat => hasDeviceFix ? gpsLat : (hasIpFix ? locationLat : null);

  double? get lon => hasDeviceFix ? gpsLon : (hasIpFix ? locationLon : null);

  String get coordSource =>
      hasDeviceFix ? 'device' : (hasIpFix ? 'ip' : 'none');

  String get locationLabel {
    final v = location.trim();
    if (v.isEmpty || v == '—') return '';
    return v;
  }

  DateTime? get when => _parseStamp(createdAt);

  factory ActivityLog.fromJson(Map<String, dynamic> json) => ActivityLog(
    id: _asInt(json['id']),
    userId: _asInt(json['user_id']),
    action: _asText(json['action']),
    details: _asText(json['details']),
    ipAddress: _asText(json['ip_address']),
    createdAt: _asText(json['created_at']),
    username: _asText(json['username']),
    location: _asText(json['location']),
    locationCity: _asText(json['location_city']),
    locationStatus: _asText(json['location_status']),
    locationZip: _asText(json['location_zip']),
    isp: _asText(json['isp']),
    locationLat: _asDouble(json['location_lat']),
    locationLon: _asDouble(json['location_lon']),
    ipV4: _asText(json['ip_v4']),
    ipLan: _asText(json['ip_lan']),
    gpsLat: _asDouble(json['gps_lat']),
    gpsLon: _asDouble(json['gps_lon']),
    gpsAccuracyM: _asNullableInt(json['gps_accuracy_m']),
  );
}

class ActivityLogPage {
  const ActivityLogPage({required this.rows, required this.total});

  final List<ActivityLog> rows;
  final int total;

  static const ActivityLogPage empty = ActivityLogPage(
    rows: <ActivityLog>[],
    total: 0,
  );
}

class TraceField {
  const TraceField({
    required this.label,
    required this.value,
    this.mono = false,
    this.tag = '',
  });

  final String label;
  final String value;
  final bool mono;
  final String tag;

  bool get isEmpty => value.isEmpty || value == '—';

  factory TraceField.fromJson(Map<String, dynamic> json) => TraceField(
    label: _asText(json['k']),
    value: _asText(json['v']),
    mono: json['mono'] == true,
    tag: _asText(json['tag']),
  );
}

class TraceSection {
  const TraceSection({required this.title, required this.fields});

  final String title;
  final List<TraceField> fields;

  factory TraceSection.fromJson(Map<String, dynamic> json) => TraceSection(
    title: _asText(json['title']),
    fields: _asList(json['fields'])
        .map((e) => TraceField.fromJson(e))
        .where((f) => !f.isEmpty || f.tag.isNotEmpty)
        .toList(growable: false),
  );
}

class TracePoint {
  const TracePoint({
    required this.id,
    required this.ids,
    required this.action,
    required this.createdAt,
    required this.firstAt,
    required this.lat,
    required this.lon,
    required this.source,
    required this.events,
    this.accuracyM,
    this.location = '',
    this.address = '',
    this.addressPrecision = '',
    this.addressProvider = '',
  });

  final int id;
  final List<int> ids;
  final String action;
  final String createdAt;
  final String firstAt;
  final double lat;
  final double lon;
  final String source;
  final int events;
  final int? accuracyM;
  final String location;
  final String address;
  final String addressPrecision;
  final String addressProvider;

  bool get isDeviceFix => source == 'device';

  DateTime? get when => _parseStamp(createdAt);

  static TracePoint? fromJson(Map<String, dynamic> json) {
    final lat = _asDouble(json['lat']);
    final lon = _asDouble(json['lon']);
    if (lat == null || lon == null) return null;
    return TracePoint(
      id: _asInt(json['id']),
      ids: _asList(json['ids']).isEmpty
          ? <int>[_asInt(json['id'])]
          : _asIntList(json['ids']),
      action: _asText(json['action']),
      createdAt: _asText(json['created_at']),
      firstAt: _asText(json['first_at']),
      lat: lat,
      lon: lon,
      source: _asText(json['source']),
      events: _asInt(json['events']) == 0 ? 1 : _asInt(json['events']),
      accuracyM: _asNullableInt(json['accuracy_m']),
      location: _asText(json['location']),
      address: _asText(json['address']),
      addressPrecision: _asText(json['address_precision']),
      addressProvider: _asText(json['address_provider']),
    );
  }
}

class TracePresence {
  const TracePresence({
    required this.userId,
    required this.username,
    required this.fullName,
    required this.role,
    required this.email,
    required this.isOnline,
    required this.lastSeen,
  });

  final int userId;
  final String username;
  final String fullName;
  final String role;
  final String email;
  final bool isOnline;
  final String lastSeen;

  String get displayName {
    if (fullName.isNotEmpty) return fullName;
    if (username.isNotEmpty) return username;
    return 'User #$userId';
  }

  factory TracePresence.fromJson(Map<String, dynamic> json) => TracePresence(
    userId: _asInt(json['id']),
    username: _asText(json['username']),
    fullName: _asText(json['full_name']),
    role: _asText(json['role']),
    email: _asText(json['email']),
    isOnline: json['is_online'] == true || json['is_online'] == 1,
    lastSeen: _asText(json['last_seen']),
  );
}

class ActivityTrace {
  const ActivityTrace({
    required this.title,
    required this.subtitle,
    required this.eyebrow,
    required this.note,
    required this.noteLabel,
    required this.sections,
    required this.track,
    required this.selectedIds,
    required this.trackNote,
    required this.emptyNote,
    required this.latestId,
    required this.live,
    required this.liveKind,
    required this.liveUserId,
    required this.liveCollectionId,
    this.user,
  });

  final String title;
  final String subtitle;
  final String eyebrow;
  final String note;
  final String noteLabel;
  final List<TraceSection> sections;
  final List<TracePoint> track;
  final List<int> selectedIds;
  final String trackNote;
  final String emptyNote;
  final int latestId;
  final bool live;
  final String liveKind;
  final int liveUserId;
  final String liveCollectionId;
  final TracePresence? user;

  Map<String, String>? get heartbeatQuery {
    if (!live) return null;
    if (liveKind == 'download') {
      if (liveCollectionId.isEmpty) return null;
      return {
        'live': '1',
        'live_kind': 'download',
        'collection_id': liveCollectionId,
      };
    }
    if (liveUserId <= 0) return null;
    return {'live': '1', 'live_kind': 'user', 'user_id': '$liveUserId'};
  }

  int get deviceFixes => track.where((p) => p.isDeviceFix).length;

  TracePoint? get selected {
    for (final p in track) {
      if (p.ids.any(selectedIds.contains)) return p;
    }
    return track.isEmpty ? null : track.last;
  }

  factory ActivityTrace.fromJson(Map<String, dynamic> json) {
    final liveBlock = json['live'];
    final userBlock = json['user'];
    return ActivityTrace(
      title: _asText(json['title']),
      subtitle: _asText(json['subtitle']),
      eyebrow: _asText(json['eyebrow']),
      note: _asText(json['note']),
      noteLabel: _asText(json['note_label']),
      sections: _asList(json['sections'])
          .map((e) => TraceSection.fromJson(e))
          .where((s) => s.fields.isNotEmpty)
          .toList(growable: false),
      track: _asList(json['track'])
          .map(TracePoint.fromJson)
          .whereType<TracePoint>()
          .toList(growable: false),
      selectedIds: _asIntList(json['selected_ids']),
      trackNote: _asText(json['track_note']),
      emptyNote: _asText(json['empty_note']),
      latestId: liveBlock is Map ? _asInt(liveBlock['latest_id']) : 0,
      live: liveBlock is Map,
      liveKind: liveBlock is Map ? _asText(liveBlock['kind']) : '',
      liveUserId: liveBlock is Map ? _asInt(liveBlock['user_id']) : 0,
      liveCollectionId: liveBlock is Map
          ? _asText(liveBlock['collection_id'])
          : '',
      user: userBlock is Map
          ? TracePresence.fromJson(Map<String, dynamic>.from(userBlock))
          : null,
    );
  }
}

class TraceHeartbeat {
  const TraceHeartbeat({required this.latestId, this.user});

  final int latestId;
  final TracePresence? user;
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? 0;
  return 0;
}

int? _asNullableInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    final t = value.trim();
    if (t.isEmpty) return null;
    return int.tryParse(t) ?? double.tryParse(t)?.toInt();
  }
  return null;
}

double? _asDouble(Object? value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) {
    final t = value.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }
  return null;
}

String _asText(Object? value) {
  if (value == null) return '';
  final t = value.toString().trim();
  return t == 'null' ? '' : t;
}

List<Map<String, dynamic>> _asList(Object? value) {
  if (value is! List) return const <Map<String, dynamic>>[];
  return value
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList(growable: false);
}

List<int> _asIntList(Object? value) {
  if (value is! List) return const <int>[];
  return value.map(_asInt).where((v) => v > 0).toList(growable: false);
}

DateTime? _parseStamp(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return null;
  return DateTime.tryParse(t.replaceFirst(' ', 'T'));
}

class GeoFields {
  const GeoFields({
    this.location = '',
    this.locationCity = '',
    this.locationStatus = '',
    this.locationZip = '',
    this.isp = '',
    this.locationLat,
    this.locationLon,
    this.gpsLat,
    this.gpsLon,
    this.gpsAccuracyM,
  });

  final String location;
  final String locationCity;
  final String locationStatus;
  final String locationZip;
  final String isp;
  final double? locationLat;
  final double? locationLon;
  final double? gpsLat;
  final double? gpsLon;
  final int? gpsAccuracyM;

  bool get hasDeviceFix => gpsLat != null && gpsLon != null;

  bool get hasIpFix =>
      locationStatus == 'success' && locationLat != null && locationLon != null;

  bool get hasCoords => hasDeviceFix || hasIpFix;

  double? get lat => hasDeviceFix ? gpsLat : (hasIpFix ? locationLat : null);

  double? get lon => hasDeviceFix ? gpsLon : (hasIpFix ? locationLon : null);

  String get source => hasDeviceFix ? 'device' : (hasIpFix ? 'ip' : 'none');

  String get label {
    final v = location.trim();
    if (v.isEmpty || v == '—') return '';
    return v;
  }

  factory GeoFields.fromJson(Map<String, dynamic> json) => GeoFields(
    location: _asText(json['location']),
    locationCity: _asText(json['location_city']),
    locationStatus: _asText(json['location_status']),
    locationZip: _asText(json['location_zip']),
    isp: _asText(json['isp']),
    locationLat: _asDouble(json['location_lat']),
    locationLon: _asDouble(json['location_lon']),
    gpsLat: _asDouble(json['gps_lat']),
    gpsLon: _asDouble(json['gps_lon']),
    gpsAccuracyM: _asNullableInt(json['gps_accuracy_m']),
  );
}

class OnlineUser {
  const OnlineUser({
    required this.id,
    required this.fullName,
    required this.username,
    required this.role,
    required this.ipAddress,
    required this.ipV4,
    required this.ipLan,
    required this.lastActivity,
    required this.lastAction,
    required this.lastSeen,
    required this.geo,
  });

  final int id;
  final String fullName;
  final String username;
  final String role;
  final String ipAddress;
  final String ipV4;
  final String ipLan;
  final String lastActivity;
  final String lastAction;
  final String lastSeen;
  final GeoFields geo;

  String get displayName {
    if (fullName.isNotEmpty) return fullName;
    if (username.isNotEmpty) return username;
    return 'Unknown';
  }

  String get roleLabel {
    final r = role.replaceAll('_', ' ').trim();
    if (r.isEmpty) return '—';
    return r
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  DateTime? get when => _parseStamp(lastActivity);

  String get haystack => [
    fullName,
    username,
    role,
    ipAddress,
    geo.location,
    geo.isp,
    lastAction,
  ].join(' ').toLowerCase();

  factory OnlineUser.fromJson(Map<String, dynamic> json) => OnlineUser(
    id: _asInt(json['id']),
    fullName: _asText(json['full_name']),
    username: _asText(json['username']),
    role: _asText(json['role']),
    ipAddress: _asText(json['ip_address']),
    ipV4: _asText(json['ip_v4']),
    ipLan: _asText(json['ip_lan']),
    lastActivity: _asText(json['last_activity']),
    lastAction: _asText(json['last_action']),
    lastSeen: _asText(json['last_seen']),
    geo: GeoFields.fromJson(json),
  );
}

class TicketLog {
  const TicketLog({
    required this.id,
    required this.subject,
    required this.description,
    required this.status,
    required this.priority,
    required this.customerName,
    required this.businessName,
    required this.vatReg,
    required this.conversationId,
    required this.createdAt,
    required this.updatedAt,
    required this.agentFullName,
    required this.agentUsername,
  });

  final int id;
  final String subject;
  final String description;
  final String status;
  final String priority;
  final String customerName;
  final String businessName;
  final bool vatReg;
  final int conversationId;
  final String createdAt;
  final String updatedAt;
  final String agentFullName;
  final String agentUsername;

  bool get assigned => agentFullName.isNotEmpty || agentUsername.isNotEmpty;

  String get agentLabel {
    if (agentFullName.isNotEmpty) return agentFullName;
    if (agentUsername.isNotEmpty) return agentUsername;
    return 'unassigned';
  }

  String get statusLabel {
    final s = status.isEmpty ? 'new' : status;
    if (s == 'in_progress') return 'In progress';
    return '${s[0].toUpperCase()}${s.substring(1)}';
  }

  String get priorityLabel => priority.isEmpty ? 'medium' : priority;

  String get subjectLabel => subject.isEmpty ? '(no subject)' : subject;

  DateTime? get when => _parseStamp(createdAt);

  String get haystack => [
    '$id',
    subject,
    description,
    customerName,
    businessName,
    agentFullName,
    agentUsername,
  ].join(' ').toLowerCase();

  factory TicketLog.fromJson(Map<String, dynamic> json) => TicketLog(
    id: _asInt(json['id']),
    subject: _asText(json['subject']),
    description: _asText(json['description']),
    status: _asText(json['status']).toLowerCase(),
    priority: _asText(json['priority']).toLowerCase(),
    customerName: _asText(json['customer_name']),
    businessName: _asText(json['business_name']),
    vatReg:
        json['vat_reg'] == 1 ||
        json['vat_reg'] == true ||
        _asText(json['vat_reg']) == '1',
    conversationId: _asInt(json['conversation_id']),
    createdAt: _asText(json['created_at']),
    updatedAt: _asText(json['updated_at']),
    agentFullName: _asText(json['agent_full_name']),
    agentUsername: _asText(json['agent_username']),
  );
}

class ConversationLog {
  const ConversationLog({
    required this.id,
    required this.type,
    required this.visibility,
    required this.name,
    required this.topic,
    required this.guestStatus,
    required this.createdAt,
    required this.lastActivityAt,
    required this.memberCount,
    required this.messageCount,
    required this.fileCount,
    required this.ticketCount,
  });

  final int id;
  final String type;
  final String visibility;
  final String name;
  final String topic;
  final String guestStatus;
  final String createdAt;
  final String lastActivityAt;
  final int memberCount;
  final int messageCount;
  final int fileCount;
  final int ticketCount;

  String get title {
    if (name.isNotEmpty) return name;
    if (topic.isNotEmpty) return topic;
    return 'Conversation #$id';
  }

  String get subtitle => topic.isNotEmpty && topic != name ? topic : '';

  String get typeLabel => type == 'dm' ? 'Direct' : 'Group';

  DateTime? get when => _parseStamp(lastActivityAt);

  String get haystack => ['$id', name, topic, type].join(' ').toLowerCase();

  factory ConversationLog.fromJson(Map<String, dynamic> json) =>
      ConversationLog(
        id: _asInt(json['id']),
        type: _asText(json['type']).toLowerCase(),
        visibility: _asText(json['visibility']),
        name: _asText(json['name']),
        topic: _asText(json['topic']),
        guestStatus: _asText(json['guest_status']),
        createdAt: _asText(json['created_at']),
        lastActivityAt: _asText(json['last_activity_at']),
        memberCount: _asInt(json['member_count']),
        messageCount: _asInt(json['message_count']),
        fileCount: _asInt(json['file_count']),
        ticketCount: _asInt(json['ticket_count']),
      );
}

class ConversationTicket {
  const ConversationTicket({
    required this.id,
    required this.subject,
    required this.status,
    required this.priority,
    required this.agent,
    required this.createdAt,
  });

  final int id;
  final String subject;
  final String status;
  final String priority;
  final String agent;
  final String createdAt;

  String get statusLabel {
    if (status.isEmpty) return '';
    if (status == 'in_progress') return 'In progress';
    return '${status[0].toUpperCase()}${status.substring(1)}';
  }

  factory ConversationTicket.fromJson(Map<String, dynamic> json) =>
      ConversationTicket(
        id: _asInt(json['id']),
        subject: _asText(json['subject']),
        status: _asText(json['status']).toLowerCase(),
        priority: _asText(json['priority']).toLowerCase(),
        agent: _asText(json['agent']),
        createdAt: _asText(json['created_at']),
      );
}

class ConversationMember {
  const ConversationMember({
    required this.userId,
    required this.name,
    required this.username,
    required this.role,
    required this.joinedAt,
  });

  final int userId;
  final String name;
  final String username;
  final String role;
  final String joinedAt;

  bool get isStaff =>
      const ['admin', 'staff', 'support', 'agent'].contains(role);

  factory ConversationMember.fromJson(Map<String, dynamic> json) =>
      ConversationMember(
        userId: _asInt(json['user_id']),
        name: _asText(json['name']),
        username: _asText(json['username']),
        role: _asText(json['role']),
        joinedAt: _asText(json['joined_at']),
      );
}

class ConversationFile {
  const ConversationFile({
    required this.id,
    required this.name,
    required this.mime,
    required this.size,
    required this.createdAt,
    required this.uploader,
  });

  final int id;
  final String name;
  final String mime;
  final int size;
  final String createdAt;
  final String uploader;

  String get sizeLabel {
    if (size <= 0) return '';
    final kb = (size / 1024).round();
    return '${kb < 1 ? 1 : kb} KB';
  }

  factory ConversationFile.fromJson(Map<String, dynamic> json) =>
      ConversationFile(
        id: _asInt(json['id']),
        name: _asText(json['name']),
        mime: _asText(json['mime']),
        size: _asInt(json['size']),
        createdAt: _asText(json['created_at']),
        uploader: _asText(json['uploader']),
      );
}

class ConversationMessage {
  const ConversationMessage({
    required this.id,
    required this.senderId,
    required this.sender,
    required this.role,
    required this.body,
    required this.createdAt,
    required this.attachments,
  });

  final int id;
  final int senderId;
  final String sender;
  final String role;
  final String body;
  final String createdAt;
  final List<String> attachments;

  bool get isStaff =>
      const ['admin', 'staff', 'support', 'agent'].contains(role);

  factory ConversationMessage.fromJson(Map<String, dynamic> json) {
    final raw = json['attachments'];
    return ConversationMessage(
      id: _asInt(json['id']),
      senderId: _asInt(json['sender_id']),
      sender: _asText(json['sender']),
      role: _asText(json['role']),
      body: _asText(json['body']),
      createdAt: _asText(json['created_at']),
      attachments: raw is List
          ? raw.map(_asText).where((e) => e.isNotEmpty).toList(growable: false)
          : const <String>[],
    );
  }
}

class ConversationActivity {
  const ConversationActivity({
    required this.tickets,
    required this.participants,
    required this.files,
    required this.messages,
    required this.totalMessages,
    required this.totalFiles,
    required this.firstAt,
    required this.lastAt,
  });

  final List<ConversationTicket> tickets;
  final List<ConversationMember> participants;
  final List<ConversationFile> files;
  final List<ConversationMessage> messages;
  final int totalMessages;
  final int totalFiles;
  final String firstAt;
  final String lastAt;

  factory ConversationActivity.fromJson(Map<String, dynamic> json) {
    final stats = json['stats'];
    final statsMap = stats is Map
        ? Map<String, dynamic>.from(stats)
        : <String, dynamic>{};
    return ConversationActivity(
      tickets: _asList(
        json['tickets'],
      ).map(ConversationTicket.fromJson).toList(growable: false),
      participants: _asList(
        json['participants'],
      ).map(ConversationMember.fromJson).toList(growable: false),
      files: _asList(
        json['files'],
      ).map(ConversationFile.fromJson).toList(growable: false),
      messages: _asList(
        json['messages'],
      ).map(ConversationMessage.fromJson).toList(growable: false),
      totalMessages: _asInt(statsMap['total_messages']),
      totalFiles: _asInt(statsMap['total_files']),
      firstAt: _asText(statsMap['first_at']),
      lastAt: _asText(statsMap['last_at']),
    );
  }
}

class PortalActivityLog {
  const PortalActivityLog({
    required this.id,
    required this.source,
    required this.actorType,
    required this.actor,
    required this.business,
    required this.reference,
    required this.action,
    required this.actionCode,
    required this.details,
    required this.ipAddress,
    required this.userAgent,
    required this.device,
    required this.createdAt,
    required this.geo,
  });

  final String id;
  final String source;
  final String actorType;
  final String actor;
  final String business;
  final String reference;
  final String action;
  final String actionCode;
  final String details;
  final String ipAddress;
  final String userAgent;
  final String device;
  final String createdAt;
  final GeoFields geo;

  bool get isVendor => source == 'vendor';

  String get sourceLabel => isVendor ? 'Vendor' : 'Taxpayer';

  String get actorTypeLabel =>
      actorType == 'anonymous' ? 'not signed in' : actorType;

  bool get failed => RegExp(
    r'fail|throttl|denied',
    caseSensitive: false,
  ).hasMatch(actionCode.isEmpty ? action : actionCode);

  bool get isSignIn => RegExp(
    r'login|logout|signed in|sign-in|signed out',
    caseSensitive: false,
  ).hasMatch(actionCode.isEmpty ? action : actionCode);

  String get actionLabel => action.isEmpty ? '—' : action;

  DateTime? get when => _parseStamp(createdAt);

  String get haystack => [
    actor,
    business,
    reference,
    action,
    actionCode,
    details,
    ipAddress,
    geo.location,
    device,
    createdAt,
  ].join(' ').toLowerCase();

  factory PortalActivityLog.fromJson(Map<String, dynamic> json) =>
      PortalActivityLog(
        id: _asText(json['id']),
        source: _asText(json['source']).toLowerCase(),
        actorType: _asText(json['actor_type']).toLowerCase(),
        actor: _asText(json['actor']),
        business: _asText(json['business']),
        reference: _asText(json['reference']),
        action: _asText(json['action']),
        actionCode: _asText(json['action_code']),
        details: _asText(json['details']),
        ipAddress: _asText(json['ip_address']),
        userAgent: _asText(json['user_agent']),
        device: _asText(json['device']),
        createdAt: _asText(json['created_at']),
        geo: GeoFields.fromJson(json),
      );
}

class PublicDownloadLog {
  const PublicDownloadLog({
    required this.id,
    required this.collectionId,
    required this.collectionName,
    required this.collectionType,
    required this.tokenType,
    required this.ipAddress,
    required this.userAgent,
    required this.device,
    required this.accessedAt,
    required this.geo,
  });

  final int id;
  final String collectionId;
  final String collectionName;
  final String collectionType;
  final String tokenType;
  final String ipAddress;
  final String userAgent;
  final String device;
  final String accessedAt;
  final GeoFields geo;

  bool get permanent => tokenType == 'permanent';

  String get shortCollectionId {
    if (collectionId.length <= 13) return collectionId;
    return '${collectionId.substring(0, 13)}…';
  }

  DateTime? get when => _parseStamp(accessedAt);

  String get haystack => [
    collectionName,
    collectionId,
    ipAddress,
    userAgent,
    device,
    geo.location,
    geo.isp,
    accessedAt,
  ].join(' ').toLowerCase();

  factory PublicDownloadLog.fromJson(Map<String, dynamic> json) =>
      PublicDownloadLog(
        id: _asInt(json['id']),
        collectionId: _asText(json['collection_id']),
        collectionName: _asText(json['collection_name']),
        collectionType: _asText(json['collection_type']),
        tokenType: _asText(json['token_type']).toLowerCase(),
        ipAddress: _asText(json['ip_address']),
        userAgent: _asText(json['user_agent']),
        device: _asText(json['device']),
        accessedAt: _asText(json['accessed_at']),
        geo: GeoFields.fromJson(json),
      );
}
