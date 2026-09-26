import '../api_client.dart';
import '../models/blog_models.dart';

const String kBlogFacade = 'utils/models/blog-facade.php';

class BlogResult {
  BlogResult({required this.ok, this.message, this.postId});
  final bool ok;
  final String? message;
  final int? postId;
}

class BlogService {
  BlogService(this._api);
  final ApiClient _api;

  String get baseUrl => _api.baseUrl;

  Map<String, String> get mediaHeaders => _api.authHeaders();

  Future<BlogPage> posts({
    int page = 1,
    int pageSize = 20,
    String filter = '',
    String search = '',
  }) async {
    final query = search.trim();
    try {
      final res = await _api.getPath(kBlogFacade, {
        'action': query.isEmpty ? 'getposts-admin' : 'searchposts',
        'page': '$page',
        'pageSize': '$pageSize',
        'filter': filter,
        if (query.isNotEmpty) 'q': query,
      });
      final raw = res['posts'];
      if (raw is List) {
        return BlogPage(
          posts: raw
              .whereType<Map>()
              .map(
                (e) => BlogPost.fromJson(
                  Map<String, dynamic>.from(e),
                  baseUrl: baseUrl,
                ),
              )
              .toList(),
          total: _asInt(res['total']),
          page: _asInt(res['page']) == 0 ? page : _asInt(res['page']),
          pageSize: _asInt(res['pageSize']) == 0
              ? pageSize
              : _asInt(res['pageSize']),
        );
      }
    } catch (_) {}
    return BlogPage.empty;
  }

  Future<List<BlogPost>> drafts() async {
    try {
      final res = await _api.getPath(kBlogFacade, {'action': 'getdrafts'});
      final raw = res['data'];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map(
              (e) => BlogPost.fromJson(
                Map<String, dynamic>.from(e),
                baseUrl: baseUrl,
              ),
            )
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<BlogPost?> post(int id) async {
    try {
      final res = await _api.getPath(kBlogFacade, {
        'action': 'getpost',
        'id': '$id',
      });
      if (res['success'] == false) return null;
      if (_asInt(res['id']) <= 0) return null;
      return BlogPost.fromJson(res, baseUrl: baseUrl);
    } catch (_) {}
    return null;
  }

  Future<List<BlogCategory>> categories() async {
    try {
      final res = await _api.getPath(kBlogFacade, {'action': 'getcategories'});
      final raw = res['data'];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => BlogCategory.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<List<BlogFeedback>> feedbacks() async {
    try {
      final res = await _api.getPath(kBlogFacade, {'action': 'getfeedbacks'});
      final raw = res['data'];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => BlogFeedback.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<BlogResult> save({
    int? draftId,
    required String title,
    required String content,
    required bool isDraft,
    List<int> categoryIds = const [],
    String scheduledAt = '',
    bool sendEmail = false,
    List<String> mediaPaths = const [],
  }) async {
    final fields = <String, String>{
      'action': 'addpost',
      'title': title.trim(),
      'content': content.trim(),
      if (isDraft) 'is_draft': '1',
      if (draftId != null && draftId > 0) 'draft_id': '$draftId',
      if (categoryIds.isNotEmpty) 'categories': _jsonIds(categoryIds),
      if (scheduledAt.isNotEmpty) 'scheduled_at': scheduledAt,
      if (sendEmail) 'send_email': '1',
    };
    return _multipart(fields, mediaPaths);
  }

  Future<BlogResult> update({
    required int id,
    required String title,
    required String content,
    List<int> categoryIds = const [],
    List<String> mediaPaths = const [],
  }) async {
    final fields = <String, String>{
      'action': 'updatepost',
      'id': '$id',
      'title': title.trim(),
      'content': content.trim(),
      if (categoryIds.isNotEmpty) 'categories': _jsonIds(categoryIds),
    };
    return _multipart(fields, mediaPaths);
  }

  Future<BlogResult> delete(int id) =>
      _form({'action': 'deletepost', 'id': '$id'});

  Future<BlogResult> deleteMedia(int id) =>
      _form({'action': 'delete-media', 'id': '$id'});

  Future<BlogResult> deleteMediaMany(List<int> ids) =>
      _form({'action': 'delete-multiple-media', ..._indexed('ids', ids)});

  Future<BlogResult> reschedule({
    required int id,
    required String scheduledAt,
  }) => _form({
    'action': 'reschedulepost',
    'id': '$id',
    'scheduled_at': scheduledAt,
  });

  Future<BlogResult> publishNow(int id) =>
      _form({'action': 'publishschedulednow', 'id': '$id'});

  Future<BlogResult> addCategory({
    required String name,
    String description = '',
  }) => _form({
    'action': 'addcategory',
    'name': name.trim(),
    'description': description.trim(),
  });

  Future<BlogResult> deleteCategory(int id, {bool cascade = true}) => _form({
    'action': 'deletecategory',
    'id': '$id',
    if (cascade) 'cascade': '1',
  });

  Future<BlogResult> approveFeedback(int id) =>
      _form({'action': 'approvefeedback', 'id': '$id'});

  Future<BlogResult> deleteFeedback(int id) =>
      _form({'action': 'deletefeedback', 'id': '$id'});

  Future<BlogResult> approveFeedbacks(List<int> ids) =>
      _form({'action': 'approveMultipleFeedbacks', ..._indexed('ids', ids)});

  Future<BlogResult> deleteFeedbacks(List<int> ids) =>
      _form({'action': 'deleteMultipleFeedbacks', ..._indexed('ids', ids)});

  Future<BlogResult> _form(Map<String, String> body) async {
    try {
      final res = await _api.postPath(kBlogFacade, body: body);
      return _resultOf(res);
    } catch (_) {
      return BlogResult(ok: false, message: 'Network error');
    }
  }

  Future<BlogResult> _multipart(
    Map<String, String> fields,
    List<String> mediaPaths,
  ) async {
    try {
      final res = await _api.postPathMultipartFiles(
        kBlogFacade,
        fields: fields,
        files: [
          for (final path in mediaPaths)
            if (path.isNotEmpty) (field: 'media[]', path: path),
        ],
      );
      return _resultOf(res);
    } catch (_) {
      return BlogResult(ok: false, message: 'Network error');
    }
  }

  BlogResult _resultOf(Map<String, dynamic> res) => BlogResult(
    ok: res['success'] == true,
    message: res['message']?.toString(),
    postId: res['post_id'] == null ? null : _asInt(res['post_id']),
  );

  Map<String, String> _indexed(String field, List<int> ids) {
    final out = <String, String>{};
    for (var i = 0; i < ids.length; i++) {
      out['$field[$i]'] = '${ids[i]}';
    }
    return out;
  }

  String _jsonIds(List<int> ids) => '[${ids.join(',')}]';
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
