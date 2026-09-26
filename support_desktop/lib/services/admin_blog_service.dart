import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api_client.dart';

const String kBlogFacade = 'utils/models/blog-facade.php';
const String kEmailNotification = 'utils/models/email-notification.php';

class BlogCategory {
  const BlogCategory({
    required this.id,
    required this.name,
    this.description = '',
  });
  final int id;
  final String name;
  final String description;

  factory BlogCategory.fromJson(Map<String, dynamic> j) => BlogCategory(
    id: int.tryParse('${j['id']}') ?? 0,
    name: '${j['name'] ?? ''}',
    description: '${j['description'] ?? ''}',
  );
}

class BlogMedia {
  const BlogMedia({
    required this.id,
    required this.type,
    required this.filePath,
  });
  final int id;
  final String type;
  final String filePath;
  bool get isPhoto => type == 'photo';

  factory BlogMedia.fromJson(Map<String, dynamic> j) => BlogMedia(
    id: int.tryParse('${j['id']}') ?? 0,
    type: '${j['media_type'] ?? ''}',
    filePath: '${j['file_path'] ?? ''}',
  );
}

class BlogPostDetail {
  const BlogPostDetail({
    required this.id,
    required this.title,
    required this.content,
    required this.status,
    required this.scheduledAt,
    required this.createdAt,
    required this.categories,
    required this.media,
  });
  final int id;
  final String title;
  final String content;
  final String status;
  final String scheduledAt;
  final String createdAt;
  final List<BlogCategory> categories;
  final List<BlogMedia> media;

  factory BlogPostDetail.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> rows(dynamic v) => v is List
        ? v.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
        : const [];
    return BlogPostDetail(
      id: int.tryParse('${j['id']}') ?? 0,
      title: '${j['title'] ?? ''}',
      content: '${j['content'] ?? ''}',
      status: '${j['status'] ?? ''}',
      scheduledAt: '${j['scheduled_at'] ?? ''}',
      createdAt: '${j['created_at'] ?? ''}',
      categories: rows(j['categories']).map(BlogCategory.fromJson).toList(),
      media: rows(j['media']).map(BlogMedia.fromJson).toList(),
    );
  }
}

class BlogResult {
  const BlogResult(this.ok, this.message, [this.data = const {}]);
  final bool ok;
  final String message;
  final Map<String, dynamic> data;
}

class AdminBlogService {
  AdminBlogService(this.api);
  final ApiClient api;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('${api.baseUrl}/$path').replace(queryParameters: query);

  Map<String, String> get _headers => {
    ...api.authHeaders(),
    'Accept': 'application/json',
  };

  dynamic _json(http.Response r) {
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('HTTP ${r.statusCode}');
    }
    final t = r.body.trim();
    if (t.isEmpty) return <String, dynamic>{};
    return jsonDecode(t);
  }

  Map<String, dynamic> _map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  BlogResult _result(dynamic v) {
    final m = _map(v);
    return BlogResult(m['success'] == true, '${m['message'] ?? ''}', m);
  }

  String _form(List<MapEntry<String, String>> fields) => fields
      .map(
        (e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
      )
      .join('&');

  Future<dynamic> _get(String path, Map<String, String> query) async {
    final r = await http.get(_uri(path, query), headers: _headers);
    return _json(r);
  }

  Future<dynamic> _post(
    String path,
    List<MapEntry<String, String>> fields, {
    Map<String, String>? query,
  }) async {
    final r = await http.post(
      _uri(path, query),
      headers: {
        ..._headers,
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
      },
      body: _form(fields),
    );
    return _json(r);
  }

  Future<dynamic> _multipart(
    String path,
    Map<String, String> query,
    List<MapEntry<String, String>> before,
    List<String> mediaPaths,
    List<MapEntry<String, String>> after,
  ) async {
    final req = http.MultipartRequest('POST', _uri(path, query));
    req.headers.addAll(_headers);
    for (final e in before) {
      req.fields[e.key] = e.value;
    }
    for (final p in mediaPaths) {
      req.files.add(await http.MultipartFile.fromPath('media[]', p));
    }
    for (final e in after) {
      req.fields[e.key] = e.value;
    }
    final r = await http.Response.fromStream(await req.send());
    return _json(r);
  }

  String _ts() => '${DateTime.now().millisecondsSinceEpoch}';

  Future<List<BlogCategory>> categories() async {
    final v = await _get(kBlogFacade, {'action': 'getcategories'});
    if (v is! List) return const [];
    return v
        .whereType<Map>()
        .map((m) => BlogCategory.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<List<Map<String, dynamic>>> drafts() async {
    final v = await _get(kBlogFacade, {'action': 'getdrafts'});
    if (v is! List) return const [];
    return v.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  }

  Future<BlogPostDetail?> post(int id) async {
    final v = _map(await _get(kBlogFacade, {'action': 'getpost', 'id': '$id'}));
    if (v.isEmpty || v['success'] == false) return null;
    return BlogPostDetail.fromJson(v);
  }

  Future<BlogResult> addPost({
    required String title,
    required String content,
    required List<int> categoryIds,
    List<String> mediaPaths = const [],
    bool isDraft = false,
    bool sendEmail = false,
    String? scheduledAt,
    int? draftId,
  }) async {
    final v = await _multipart(
      kBlogFacade,
      {'action': 'addpost'},
      [MapEntry('title', title), MapEntry('content', content)],
      mediaPaths,
      [
        if (isDraft) const MapEntry('is_draft', '1'),
        MapEntry('categories', jsonEncode(categoryIds)),
        if (!isDraft) MapEntry('send_email', sendEmail ? '1' : '0'),
        if (!isDraft && scheduledAt != null)
          MapEntry('scheduled_at', scheduledAt),
        if (draftId != null) MapEntry('draft_id', '$draftId'),
      ],
    );
    return _result(v);
  }

  Future<BlogResult> updatePost({
    required int id,
    required String title,
    required String content,
    required List<int> categoryIds,
    List<String> mediaPaths = const [],
  }) async {
    final v = await _multipart(
      kBlogFacade,
      {'action': 'updatepost'},
      [
        MapEntry('id', '$id'),
        MapEntry('title', title),
        MapEntry('content', content),
      ],
      mediaPaths,
      [MapEntry('categories', jsonEncode(categoryIds))],
    );
    return _result(v);
  }

  Future<BlogResult> deletePost(int id) async => _result(
    await _post(
      kBlogFacade,
      [MapEntry('id', '$id')],
      query: {'action': 'deletepost'},
    ),
  );

  Future<BlogResult> deleteMedia(int id) async => _result(
    await _post(
      kBlogFacade,
      [MapEntry('id', '$id')],
      query: {'action': 'delete-media'},
    ),
  );

  Future<BlogResult> deleteMultipleMedia(List<int> ids) async => _result(
    await _post(
      kBlogFacade,
      [for (final i in ids) MapEntry('ids[]', '$i')],
      query: {'action': 'delete-multiple-media'},
    ),
  );

  Future<BlogResult> addCategory(String name, String description) async =>
      _result(
        await _post(
          kBlogFacade,
          [MapEntry('name', name), MapEntry('description', description)],
          query: {'action': 'addcategory'},
        ),
      );

  Future<BlogResult> deleteCategory(int id) async => _result(
    await _post(
      kBlogFacade,
      [MapEntry('id', '$id'), const MapEntry('cascade', 'true')],
      query: {'action': 'deletecategory'},
    ),
  );

  Future<BlogResult> reschedule(int id, String scheduledAt) async => _result(
    await _post(
      kBlogFacade,
      [MapEntry('id', '$id'), MapEntry('scheduled_at', scheduledAt)],
      query: {'action': 'reschedulepost', '_t': _ts()},
    ),
  );

  Future<BlogResult> publishScheduledNow(int id) async => _result(
    await _post(
      kBlogFacade,
      [MapEntry('id', '$id')],
      query: {'action': 'publishschedulednow', '_t': _ts()},
    ),
  );

  Future<int> publishDueScheduled() async {
    final m = _map(
      await _post(
        kBlogFacade,
        const [],
        query: {'action': 'publish-scheduled', '_t': _ts()},
      ),
    );
    return m['success'] == true ? (int.tryParse('${m['count']}') ?? 0) : 0;
  }

  Future<int?> subscriberCount() async {
    final m = _map(
      await _post(kEmailNotification, const [
        MapEntry('action', 'get-subscriber-count'),
      ]),
    );
    if (m['success'] != true) return null;
    return int.tryParse('${m['count']}') ?? 0;
  }

  Future<BlogResult> sendPostNotification({
    required int postId,
    required String title,
    required String content,
  }) async {
    final m = _map(
      await _post(kEmailNotification, [
        const MapEntry('action', 'send-post-notification'),
        MapEntry('post_id', '$postId'),
        MapEntry('post_title', title),
        MapEntry('post_content', content),
        MapEntry('post_url', 'https://tinkerpro.io/blog/$postId'),
      ]),
    );
    return BlogResult(m['success'] == true, '${m['message'] ?? ''}', m);
  }

  String mediaUrl(String filePath) => '${api.baseUrl}/uploads/$filePath';
}
