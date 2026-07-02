// API layer for the Blog Posts feature. All endpoints live on `api.php`:
//   * getBlogPosts   GET   page,limit,search        → {data:[...], totalRecords}
//   * addBlogPost    POST  title, content, is_draft  → {success, post_id}
//   * deleteBlogPost POST  id                         → {success, deleted}
// There is NO update endpoint — list / view / create / delete only.

import '../api_client.dart';
import '../models/blog_models.dart';

class BlogResult {
  BlogResult({required this.ok, this.message});
  final bool ok;
  final String? message;
}

class BlogService {
  BlogService(this._api);
  final ApiClient _api;

  /// Fetch a page of blog posts. The backend paginates; we pull a large page
  /// so the mobile list is simple (pull-to-refresh, no infinite scroll yet).
  /// Returns an empty list on any failure so the UI still renders.
  Future<List<BlogPost>> list({
    int page = 1,
    int limit = 100,
    String search = '',
  }) async {
    try {
      final res = await _api.get('getBlogPosts', {
        'page': '$page',
        'limit': '$limit',
        if (search.isNotEmpty) 'search': search,
      });
      final raw = res['data'];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => BlogPost.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  /// Create a post. [isDraft] true → saved as a draft, otherwise published.
  Future<BlogResult> add({
    required String title,
    required String content,
    required bool isDraft,
  }) async {
    return _mutate('addBlogPost', {
      'title': title.trim(),
      'content': content.trim(),
      'is_draft': isDraft ? '1' : '0',
    });
  }

  Future<BlogResult> delete(int id) =>
      _mutate('deleteBlogPost', {'id': '$id'});

  Future<BlogResult> _mutate(
      String action, Map<String, String> body) async {
    try {
      final res = await _api.post(action, body: body);
      final ok = res['success'] == true || res['status'] == 'success';
      return BlogResult(ok: ok, message: res['message']?.toString());
    } catch (e) {
      return BlogResult(ok: false, message: 'Network error');
    }
  }
}
