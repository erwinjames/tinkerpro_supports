class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.isRead,
    required this.createdAt,
    this.refId,
    this.meta = const {},
  });

  final int id;
  final String type;
  final String title;
  final String body;
  final bool isRead;
  final DateTime? createdAt;
  final int? refId;
  final Map<String, dynamic> meta;

  bool get isBirStatus => type == 'customer_status';

  String get statusCode => (meta['to_status'] ?? '').toString();

  bool get isPtuRequest =>
      statusCode == 'awaiting_ptu' || statusCode == 'for_ptu';

  bool get isCompleted => statusCode == 'completed';

  String get companyName => (meta['company_name'] ?? '').toString();

  String get tin => (meta['tin'] ?? '').toString();

  AppNotification copyWith({bool? isRead}) => AppNotification(
        id: id,
        type: type,
        title: title,
        body: body,
        isRead: isRead ?? this.isRead,
        createdAt: createdAt,
        refId: refId,
        meta: meta,
      );

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: _asInt(json['id']),
      type: (json['type'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      body: (json['body'] ?? '').toString(),
      isRead: _asInt(json['is_read']) == 1,
      createdAt: _asDate(json['created_at']),
      refId: json['ref_id'] == null ? null : _asInt(json['ref_id']),
      meta: json['meta'] is Map
          ? Map<String, dynamic>.from(json['meta'] as Map)
          : const {},
    );
  }
}

int _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is bool) return v ? 1 : 0;
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

DateTime? _asDate(dynamic v) {
  if (v == null) return null;
  final raw = v.toString().trim();
  if (raw.isEmpty) return null;
  return DateTime.tryParse(raw.replaceFirst(' ', 'T'));
}
