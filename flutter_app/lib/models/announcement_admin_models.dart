import 'announcement_models.dart';

int _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? 0;
}

String _asText(Object? v) => (v ?? '').toString();

List<String> _asStringList(Object? v) {
  if (v is List) {
    return v
        .map((e) => e.toString().trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toList();
  }
  return const <String>[];
}

List<int> _asIntList(Object? v) {
  if (v is List) {
    return v.map(_asInt).where((e) => e > 0).toList();
  }
  return const <int>[];
}

DateTime? announcementFromDb(String raw, int dbOffsetSeconds) {
  final value = raw.trim();
  if (value.isEmpty) return null;
  final parsed = DateTime.tryParse('${value.replaceFirst(' ', 'T')}Z');
  if (parsed == null) return null;
  return parsed.subtract(Duration(seconds: dbOffsetSeconds)).toLocal();
}

String announcementToDb(DateTime? local, int dbOffsetSeconds) {
  if (local == null) return '';
  final shifted = local.toUtc().add(Duration(seconds: dbOffsetSeconds));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${shifted.year}-${two(shifted.month)}-${two(shifted.day)} '
      '${two(shifted.hour)}:${two(shifted.minute)}:00';
}

const Map<String, String> kAnnouncementLifecycles = <String, String>{
  'active': 'Active',
  'draft': 'Draft',
  'scheduled': 'Scheduled',
  'expired': 'Expired',
};

class AdminAnnouncement {
  const AdminAnnouncement({
    required this.id,
    required this.title,
    required this.body,
    required this.icon,
    required this.tone,
    required this.linkUrl,
    required this.linkLabel,
    required this.audienceType,
    required this.audienceRoles,
    required this.audienceUsers,
    required this.status,
    required this.requireAck,
    required this.startsAt,
    required this.expiresAt,
    required this.lifecycle,
    required this.createdByName,
    required this.createdAt,
    required this.reach,
    required this.readCount,
    required this.audienceLabel,
  });

  factory AdminAnnouncement.fromJson(Map<String, dynamic> json) {
    return AdminAnnouncement(
      id: _asInt(json['id']),
      title: _asText(json['title']),
      body: _asText(json['body']),
      icon: _asText(json['icon']).isEmpty
          ? 'fa-bullhorn'
          : _asText(json['icon']),
      tone: _asText(json['tone']).isEmpty ? 'info' : _asText(json['tone']),
      linkUrl: _asText(json['link_url']),
      linkLabel: _asText(json['link_label']),
      audienceType: _asText(json['audience_type']).isEmpty
          ? 'all'
          : _asText(json['audience_type']),
      audienceRoles: _asStringList(json['audience_roles']),
      audienceUsers: _asIntList(json['audience_users']),
      status: _asText(json['status']).isEmpty
          ? 'draft'
          : _asText(json['status']),
      requireAck: _asInt(json['require_ack']) == 1,
      startsAt: _asText(json['starts_at']),
      expiresAt: _asText(json['expires_at']),
      lifecycle: _asText(json['lifecycle']).isEmpty
          ? 'draft'
          : _asText(json['lifecycle']),
      createdByName: _asText(json['created_by_name']),
      createdAt: _asText(json['created_at']),
      reach: _asInt(json['reach']),
      readCount: _asInt(json['read_count']),
      audienceLabel: _asText(json['audience_label']),
    );
  }

  final int id;
  final String title;
  final String body;
  final String icon;
  final String tone;
  final String linkUrl;
  final String linkLabel;
  final String audienceType;
  final List<String> audienceRoles;
  final List<int> audienceUsers;
  final String status;
  final bool requireAck;
  final String startsAt;
  final String expiresAt;
  final String lifecycle;
  final String createdByName;
  final String createdAt;
  final int reach;
  final int readCount;
  final String audienceLabel;

  bool get isPublished => status == 'published';

  String get lifecycleLabel => kAnnouncementLifecycles[lifecycle] ?? lifecycle;

  String get toneLabel => kAnnouncementTones[tone] ?? 'Information';

  AnnouncementTone get toneColors => AnnouncementTone.of(tone);

  String windowLabel(int dbOffsetSeconds) {
    String day(String raw) {
      final parsed = announcementFromDb(raw, dbOffsetSeconds);
      if (parsed == null) return '';
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return '${months[parsed.month - 1]} ${parsed.day}, ${parsed.year}';
    }

    final from = day(startsAt);
    final to = day(expiresAt);
    if (from.isNotEmpty && to.isNotEmpty) return '$from → $to';
    if (from.isNotEmpty) return 'From $from';
    if (to.isNotEmpty) return 'Until $to';
    return 'No end date';
  }
}

class AdminAnnouncementPage {
  const AdminAnnouncementPage({
    required this.items,
    required this.counts,
    required this.dbOffsetSeconds,
  });

  final List<AdminAnnouncement> items;
  final Map<String, int> counts;
  final int dbOffsetSeconds;
}

class AnnouncementReader {
  const AnnouncementReader({
    required this.userId,
    required this.fullName,
    required this.role,
    required this.readAt,
    required this.acknowledged,
  });

  factory AnnouncementReader.fromJson(Map<String, dynamic> json) =>
      AnnouncementReader(
        userId: _asInt(json['user_id']),
        fullName: _asText(json['full_name']),
        role: _asText(json['role']),
        readAt: _asText(json['read_at']),
        acknowledged: _asInt(json['acknowledged']) == 1,
      );

  final int userId;
  final String fullName;
  final String role;
  final String readAt;
  final bool acknowledged;

  String get displayName =>
      fullName.trim().isEmpty ? 'User #$userId' : fullName.trim();
}

class AnnouncementReaders {
  const AnnouncementReaders({required this.readers, required this.reach});

  final List<AnnouncementReader> readers;
  final int reach;
}

class AnnouncementStaffPick {
  const AnnouncementStaffPick({
    required this.id,
    required this.name,
    required this.role,
  });

  final int id;
  final String name;
  final String role;

  String get roleLabel => announcementRoleLabel(role);

  String get searchKey => '$name $role'.toLowerCase();
}

class AnnouncementDraft {
  AnnouncementDraft({
    this.id = 0,
    this.title = '',
    this.body = '',
    this.icon = 'fa-bullhorn',
    this.tone = 'info',
    this.linkUrl = '',
    this.linkLabel = '',
    this.audienceType = 'all',
    Set<String>? roles,
    Set<int>? users,
    this.requireAck = false,
    this.startsAt,
    this.expiresAt,
    this.published = false,
  }) : roles = roles ?? <String>{},
       users = users ?? <int>{};

  factory AnnouncementDraft.from(AdminAnnouncement item, int dbOffsetSeconds) =>
      AnnouncementDraft(
        id: item.id,
        title: item.title,
        body: item.body,
        icon: item.icon,
        tone: item.tone,
        linkUrl: item.linkUrl,
        linkLabel: item.linkLabel,
        audienceType: item.audienceType,
        roles: item.audienceRoles.toSet(),
        users: item.audienceUsers.toSet(),
        requireAck: item.requireAck,
        startsAt: announcementFromDb(item.startsAt, dbOffsetSeconds),
        expiresAt: announcementFromDb(item.expiresAt, dbOffsetSeconds),
        published: item.isPublished,
      );

  int id;
  String title;
  String body;
  String icon;
  String tone;
  String linkUrl;
  String linkLabel;
  String audienceType;
  final Set<String> roles;
  final Set<int> users;
  bool requireAck;
  DateTime? startsAt;
  DateTime? expiresAt;
  bool published;

  bool get isNew => id <= 0;
}
