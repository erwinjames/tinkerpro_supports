import '../api_client.dart';
import '../models/feedback_models.dart';

class FeedbackResult {
  const FeedbackResult({required this.ok, required this.message, this.id = 0});

  final bool ok;
  final String message;
  final int id;
}

class FeedbackAttachResult {
  const FeedbackAttachResult({
    required this.ok,
    required this.message,
    required this.id,
  });

  final bool ok;
  final String message;
  final int id;
}

class FeedbackService {
  FeedbackService(this.api);

  final ApiClient api;

  String _fail(Object e, String fallback) {
    final msg = e is HttpException ? e.message.trim() : '';
    if (msg.isEmpty || msg.startsWith('HTTP ') || msg.startsWith('Non-JSON')) {
      return fallback;
    }
    return msg;
  }

  Uri attachmentUri(int id) =>
      Uri.parse(api.actionUrl('feedbackAttachment', {'id': '$id'}));

  Map<String, String> get imageHeaders => api.authHeaders();

  Future<FeedbackResult> submit({
    required String category,
    required int rating,
    required String subject,
    required String message,
    String pageUrl = 'flutter-app',
  }) async {
    try {
      final res = await api.post(
        'submitFeedback',
        body: {
          'category': category,
          'rating': '$rating',
          'subject': subject.trim(),
          'message': message,
          'page_url': pageUrl,
        },
      );
      return FeedbackResult(
        ok: res['success'] == true,
        message: res['message']?.toString() ?? 'Could not send your feedback.',
        id: int.tryParse('${res['id']}') ?? 0,
      );
    } catch (e) {
      return FeedbackResult(
        ok: false,
        message: _fail(e, 'Network error. Please try again.'),
      );
    }
  }

  Future<FeedbackAttachResult> attach({
    required List<int> bytes,
    required String name,
  }) async {
    try {
      final res = await api.postBytes(
        'feedbackAttach',
        bytes: bytes,
        query: {'name': name},
      );
      final raw = res['attachment'];
      if (res['success'] == true && raw is Map) {
        return FeedbackAttachResult(
          ok: true,
          message: '',
          id: int.tryParse('${raw['id']}') ?? 0,
        );
      }
      return FeedbackAttachResult(
        ok: false,
        message: res['message']?.toString() ?? 'Upload failed.',
        id: 0,
      );
    } catch (e) {
      return FeedbackAttachResult(
        ok: false,
        message: _fail(e, 'Upload failed.'),
        id: 0,
      );
    }
  }

  Future<void> detach(int id) async {
    if (id <= 0) return;
    try {
      await api.post('feedbackDetach', body: {'id': '$id'});
    } catch (_) {}
  }

  Future<void> discardPending() async {
    try {
      await api.post('feedbackDiscardPending');
    } catch (_) {}
  }

  Future<FeedbackPage> list({
    String status = '',
    String category = '',
    String search = '',
    int limit = 200,
  }) async {
    try {
      final res = await api.get('getFeedbackList', {
        'status': status,
        'category': category,
        'search': search.trim(),
        'limit': '$limit',
      });
      final raw = res['feedback'];
      final items = raw is List
          ? raw
                .whereType<Map>()
                .map((e) => FeedbackItem.fromJson(Map<String, dynamic>.from(e)))
                .toList()
          : <FeedbackItem>[];
      final stats = res['stats'];
      final parsedStats = stats is Map
          ? FeedbackStats.fromJson(Map<String, dynamic>.from(stats))
          : FeedbackStats.empty;
      if (res['success'] != true && items.isEmpty) {
        throw HttpException(
          res['message']?.toString() ?? 'Could not load feedback.',
        );
      }
      return FeedbackPage(items: items, stats: parsedStats);
    } catch (e) {
      throw HttpException(_fail(e, 'Could not load feedback.'));
    }
  }

  Future<FeedbackResult> setStatus({
    required int id,
    required String status,
    required String note,
  }) async {
    try {
      final res = await api.post(
        'updateFeedbackStatus',
        body: {'id': '$id', 'status': status, 'note': note},
      );
      return FeedbackResult(
        ok: res['success'] == true,
        message:
            res['message']?.toString() ?? 'Could not update this feedback.',
      );
    } catch (e) {
      return FeedbackResult(
        ok: false,
        message: _fail(e, 'Could not update this feedback.'),
      );
    }
  }

  Future<FeedbackResult> delete(int id) async {
    try {
      final res = await api.post('deleteFeedback', body: {'id': '$id'});
      return FeedbackResult(
        ok: res['success'] == true,
        message:
            res['message']?.toString() ?? 'Could not delete this feedback.',
      );
    } catch (e) {
      return FeedbackResult(
        ok: false,
        message: _fail(e, 'Could not delete this feedback.'),
      );
    }
  }

  Future<int> newCount() async {
    try {
      final res = await api.get('feedbackNewCount');
      if (res['success'] != true) return 0;
      return int.tryParse('${res['new_count']}') ?? 0;
    } catch (_) {
      return 0;
    }
  }
}
