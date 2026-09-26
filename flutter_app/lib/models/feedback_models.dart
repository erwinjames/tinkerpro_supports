import 'dart:typed_data';

int _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? 0;
}

String _asText(Object? v) => (v ?? '').toString();

const Map<String, String> kFeedbackCategories = <String, String>{
  'general': 'General',
  'bug': 'Bug report',
  'feature': 'Feature request',
  'ui': 'Design / UI',
  'performance': 'Performance',
  'other': 'Other',
};

const Map<String, String> kFeedbackStatuses = <String, String>{
  'new': 'New',
  'reviewed': 'Reviewed',
  'in_progress': 'In progress',
  'resolved': 'Resolved',
  'archived': 'Archived',
};

const List<String> kFeedbackRatingHints = <String>[
  'Optional',
  'Very poor',
  'Poor',
  'Okay',
  'Good',
  'Excellent',
];

const int kFeedbackMaxAttachments = 6;

const int kFeedbackMaxAttachmentBytes = 10485760;

const int kFeedbackMaxMessage = 5000;

const int kFeedbackMaxSubject = 120;

String feedbackCategoryLabel(String category) =>
    kFeedbackCategories[category.trim().toLowerCase()] ?? category;

String feedbackStatusLabel(String status) =>
    kFeedbackStatuses[status.trim().toLowerCase()] ?? status;

class FeedbackAttachment {
  const FeedbackAttachment({
    required this.id,
    required this.originalName,
    required this.mimeType,
    required this.byteSize,
    required this.width,
    required this.height,
  });

  factory FeedbackAttachment.fromJson(Map<String, dynamic> json) =>
      FeedbackAttachment(
        id: _asInt(json['id']),
        originalName: _asText(json['original_name']),
        mimeType: _asText(json['mime_type']),
        byteSize: _asInt(json['byte_size']),
        width: json['width'] == null ? null : _asInt(json['width']),
        height: json['height'] == null ? null : _asInt(json['height']),
      );

  final int id;
  final String originalName;
  final String mimeType;
  final int byteSize;
  final int? width;
  final int? height;
}

class FeedbackItem {
  const FeedbackItem({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.userRole,
    required this.category,
    required this.categoryLabel,
    required this.rating,
    required this.subject,
    required this.message,
    required this.pageUrl,
    required this.status,
    required this.adminNote,
    required this.handledByName,
    required this.createdAt,
    required this.attachments,
  });

  factory FeedbackItem.fromJson(Map<String, dynamic> json) {
    final raw = json['attachments'];
    return FeedbackItem(
      id: _asInt(json['id']),
      userId: _asInt(json['user_id']),
      userName: _asText(json['user_name']),
      userEmail: _asText(json['user_email']),
      userRole: _asText(json['user_role']),
      category: _asText(json['category']),
      categoryLabel: _asText(json['category_label']).isEmpty
          ? feedbackCategoryLabel(_asText(json['category']))
          : _asText(json['category_label']),
      rating: _asInt(json['rating']),
      subject: _asText(json['subject']),
      message: _asText(json['message']),
      pageUrl: _asText(json['page_url']),
      status: _asText(json['status']).isEmpty ? 'new' : _asText(json['status']),
      adminNote: _asText(json['admin_note']),
      handledByName: _asText(json['handled_by_name']),
      createdAt: _asText(json['created_at']),
      attachments: raw is List
          ? raw
                .whereType<Map>()
                .map(
                  (e) =>
                      FeedbackAttachment.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList()
          : const <FeedbackAttachment>[],
    );
  }

  final int id;
  final int userId;
  final String userName;
  final String userEmail;
  final String userRole;
  final String category;
  final String categoryLabel;
  final int rating;
  final String subject;
  final String message;
  final String pageUrl;
  final String status;
  final String adminNote;
  final String handledByName;
  final String createdAt;
  final List<FeedbackAttachment> attachments;

  bool get isNew => status == 'new';

  String get statusLabel => feedbackStatusLabel(status);

  String get displayName =>
      userName.trim().isEmpty ? 'Unknown user' : userName.trim();

  String get roleLabel => userRole.replaceAll('_', ' ').trim();

  String get ago {
    final value = createdAt.trim();
    if (value.isEmpty) return '';
    final parsed = DateTime.tryParse(value.replaceFirst(' ', 'T'));
    if (parsed == null) return value;
    final diff = DateTime.now().difference(parsed);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-'
        '${parsed.day.toString().padLeft(2, '0')}';
  }
}

class FeedbackStats {
  const FeedbackStats({
    required this.total,
    required this.newCount,
    required this.inProgress,
    required this.resolved,
    required this.avgRating,
  });

  factory FeedbackStats.fromJson(Map<String, dynamic> json) => FeedbackStats(
    total: _asInt(json['total']),
    newCount: _asInt(json['new']),
    inProgress: _asInt(json['in_progress']),
    resolved: _asInt(json['resolved']),
    avgRating: double.tryParse('${json['avg_rating'] ?? 0}') ?? 0,
  );

  static const FeedbackStats empty = FeedbackStats(
    total: 0,
    newCount: 0,
    inProgress: 0,
    resolved: 0,
    avgRating: 0,
  );

  final int total;
  final int newCount;
  final int inProgress;
  final int resolved;
  final double avgRating;

  String get avgRatingLabel {
    if (avgRating <= 0) return '—';
    final trimmed = avgRating.toStringAsFixed(1);
    return '$trimmed / 5';
  }
}

class FeedbackPage {
  const FeedbackPage({required this.items, required this.stats});

  final List<FeedbackItem> items;
  final FeedbackStats stats;
}

class PendingAttachment {
  PendingAttachment({
    required this.key,
    required this.name,
    required this.bytes,
    this.id = 0,
    this.uploading = true,
    this.error = '',
  });

  final String key;
  final String name;
  final Uint8List bytes;
  int id;
  bool uploading;
  String error;

  bool get failed => error.isNotEmpty;
}
