import '../api_client.dart';

int _int(dynamic v) => int.tryParse('$v') ?? 0;
String _str(dynamic v) => v == null ? '' : v.toString();

class FeedbackAttachment {
  const FeedbackAttachment({required this.id, required this.name});
  final int id;
  final String name;
}

class FeedbackEntry {
  const FeedbackEntry({
    required this.id,
    required this.userName,
    required this.userRole,
    required this.category,
    required this.categoryLabel,
    required this.status,
    required this.rating,
    required this.subject,
    required this.message,
    required this.pageUrl,
    required this.createdAt,
    required this.adminNote,
    required this.handledByName,
    required this.attachments,
  });

  final int id;
  final String userName;
  final String userRole;
  final String category;
  final String categoryLabel;
  final String status;
  final int rating;
  final String subject;
  final String message;
  final String pageUrl;
  final String createdAt;
  final String adminNote;
  final String handledByName;
  final List<FeedbackAttachment> attachments;

  factory FeedbackEntry.fromJson(Map<String, dynamic> j) => FeedbackEntry(
        id: _int(j['id']),
        userName: _str(j['user_name']),
        userRole: _str(j['user_role']),
        category: _str(j['category']),
        categoryLabel: _str(j['category_label']),
        status: _str(j['status']),
        rating: _int(j['rating']),
        subject: _str(j['subject']),
        message: _str(j['message']),
        pageUrl: _str(j['page_url']),
        createdAt: _str(j['created_at']),
        adminNote: _str(j['admin_note']),
        handledByName: _str(j['handled_by_name']),
        attachments: (j['attachments'] is List ? j['attachments'] as List : const [])
            .whereType<Map>()
            .map((m) => FeedbackAttachment(
                id: _int(m['id']), name: _str(m['original_name'])))
            .toList(),
      );
}

class FeedbackStats {
  const FeedbackStats({
    required this.total,
    required this.fresh,
    required this.inProgress,
    required this.resolved,
    required this.avgRating,
  });
  final int total;
  final int fresh;
  final int inProgress;
  final int resolved;
  final String avgRating;
}

class FeedbackPage {
  const FeedbackPage({required this.items, required this.stats});
  final List<FeedbackEntry> items;
  final FeedbackStats stats;
}

class FeedbackResult {
  const FeedbackResult(this.ok, this.message);
  final bool ok;
  final String message;
}

class FeedbackService {
  FeedbackService(this.api);
  final ApiClient api;

  static const statuses = <String, String>{
    'new': 'New',
    'reviewed': 'Reviewed',
    'in_progress': 'In progress',
    'resolved': 'Resolved',
    'archived': 'Archived',
  };

  static const categories = <String, String>{
    'general': 'General',
    'bug': 'Bug report',
    'feature': 'Feature request',
    'ui': 'Design / UI',
    'performance': 'Performance',
    'other': 'Other',
  };

  Future<FeedbackPage> list(
      {String status = '', String category = '', String search = ''}) async {
    final res = await api.get('getFeedbackList', {
      'status': status,
      'category': category,
      'search': search,
    });
    if (res['success'] != true) {
      throw Exception(_str(res['message']).isEmpty
          ? 'Could not load feedback.'
          : _str(res['message']));
    }
    final s = res['stats'] is Map
        ? Map<String, dynamic>.from(res['stats'] as Map)
        : <String, dynamic>{};
    final avg = s['avg_rating'];
    final avgNum = num.tryParse('$avg') ?? 0;
    return FeedbackPage(
      items: (res['feedback'] is List ? res['feedback'] as List : const [])
          .whereType<Map>()
          .map((m) => FeedbackEntry.fromJson(Map<String, dynamic>.from(m)))
          .toList(),
      stats: FeedbackStats(
        total: _int(s['total']),
        fresh: _int(s['new']),
        inProgress: _int(s['in_progress']),
        resolved: _int(s['resolved']),
        avgRating: avgNum == 0 ? '—' : '$avg / 5',
      ),
    );
  }

  Future<FeedbackResult> setStatus(
      {required int id, required String status, required String note}) async {
    try {
      final res = await api.post('updateFeedbackStatus',
          body: {'id': '$id', 'status': status, 'note': note});
      return FeedbackResult(
          res['success'] == true, _str(res['message']).isEmpty ? 'Done' : _str(res['message']));
    } catch (e) {
      return FeedbackResult(false, e.toString());
    }
  }

  Future<FeedbackResult> delete(int id) async {
    try {
      final res = await api.post('deleteFeedback', body: {'id': '$id'});
      return FeedbackResult(
          res['success'] == true, _str(res['message']).isEmpty ? 'Done' : _str(res['message']));
    } catch (e) {
      return FeedbackResult(false, e.toString());
    }
  }

  String attachmentUrl(int id) =>
      api.actionUrl('feedbackAttachment', {'id': '$id'});

  Map<String, String> get authHeaders => api.authHeaders();
}
