class BlogCategory {
  const BlogCategory({
    required this.id,
    required this.name,
    required this.slug,
    this.description = '',
  });

  final int id;
  final String name;
  final String slug;
  final String description;

  factory BlogCategory.fromJson(Map<String, dynamic> json) => BlogCategory(
    id: _asInt(json['id']),
    name: (json['name'] ?? '').toString(),
    slug: (json['slug'] ?? '').toString(),
    description: (json['description'] ?? '').toString(),
  );
}

class BlogMedia {
  const BlogMedia({
    required this.id,
    required this.mediaType,
    required this.filePath,
    required this.url,
  });

  final int id;
  final String mediaType;
  final String filePath;
  final String url;

  bool get isVideo => mediaType.toLowerCase() == 'video';

  factory BlogMedia.fromJson(Map<String, dynamic> json, String baseUrl) {
    final path = (json['file_path'] ?? '').toString();
    var url = (json['url'] ?? '').toString();
    if (url.isEmpty || !url.startsWith('http')) {
      final name = path.split('/').last;
      url = name.isEmpty ? '' : '$baseUrl/uploads/$name';
    }
    return BlogMedia(
      id: _asInt(json['id']),
      mediaType: (json['media_type'] ?? '').toString(),
      filePath: path,
      url: url,
    );
  }
}

class BlogPost {
  BlogPost({
    required this.id,
    required this.title,
    required this.content,
    required this.isDraft,
    required this.status,
    required this.scheduledAt,
    required this.createdAt,
    required this.updatedAt,
    this.categories = const [],
    this.media = const [],
  });

  final int id;
  final String title;
  final String content;
  final int isDraft;
  final String status;
  final String? scheduledAt;
  final String createdAt;
  final String updatedAt;
  final List<BlogCategory> categories;
  final List<BlogMedia> media;

  bool get isDraftPost => isDraft == 1 || status == 'draft';

  bool get isScheduled => status == 'scheduled';

  String get statusLabel => isScheduled
      ? 'Pending'
      : isDraftPost
      ? 'Draft'
      : 'Published';

  String get stamp =>
      (isScheduled ? (scheduledAt ?? createdAt) : createdAt).trim();

  String get stampLabel => isScheduled ? 'Scheduled' : 'Published';

  String get plainContent => blogStripHtml(content);

  factory BlogPost.fromJson(Map<String, dynamic> json, {String baseUrl = ''}) {
    final rawCategories = json['categories'];
    final rawMedia = json['media'];
    return BlogPost(
      id: _asInt(json['id']),
      title: (json['title'] ?? '').toString(),
      content: (json['content'] ?? '').toString(),
      isDraft: _asInt(json['is_draft']),
      status: (json['status'] ?? '').toString(),
      scheduledAt: json['scheduled_at']?.toString(),
      createdAt: (json['created_at'] ?? '').toString(),
      updatedAt: (json['updated_at'] ?? '').toString(),
      categories: rawCategories is List
          ? rawCategories
                .whereType<Map>()
                .map((e) => BlogCategory.fromJson(Map<String, dynamic>.from(e)))
                .toList()
          : const [],
      media: rawMedia is List
          ? rawMedia
                .whereType<Map>()
                .map(
                  (e) =>
                      BlogMedia.fromJson(Map<String, dynamic>.from(e), baseUrl),
                )
                .toList()
          : const [],
    );
  }
}

class BlogFeedback {
  const BlogFeedback({
    required this.id,
    required this.postId,
    required this.userName,
    required this.userEmail,
    required this.message,
    required this.approved,
    required this.createdAt,
    required this.postTitle,
  });

  final int id;
  final int postId;
  final String userName;
  final String userEmail;
  final String message;
  final int approved;
  final String createdAt;
  final String postTitle;

  bool get isApproved => approved == 1;

  String get reference => 'FT-${id.toString().padLeft(5, '0')}';

  factory BlogFeedback.fromJson(Map<String, dynamic> json) => BlogFeedback(
    id: _asInt(json['id']),
    postId: _asInt(json['post_id']),
    userName: (json['user_name'] ?? '').toString(),
    userEmail: (json['user_email'] ?? '').toString(),
    message: (json['message'] ?? '').toString(),
    approved: _asInt(json['approved']),
    createdAt: (json['created_at'] ?? '').toString(),
    postTitle: (json['post_title'] ?? '').toString(),
  );
}

class BlogPage {
  const BlogPage({
    required this.posts,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  final List<BlogPost> posts;
  final int total;
  final int page;
  final int pageSize;

  static const BlogPage empty = BlogPage(
    posts: [],
    total: 0,
    page: 1,
    pageSize: 10,
  );

  bool get hasMore => page * pageSize < total;
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

String blogStripHtml(String html) {
  if (html.isEmpty) return '';
  var s = html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'</(p|div|h[1-6]|li|tr)>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<[^>]+>'), ' ');
  const named = {
    '&nbsp;': ' ',
    '&amp;': '&',
    '&lt;': '<',
    '&gt;': '>',
    '&quot;': '"',
    '&#39;': "'",
    '&apos;': "'",
    '&rsquo;': '’',
    '&lsquo;': '‘',
    '&ldquo;': '“',
    '&rdquo;': '”',
    '&mdash;': '—',
    '&ndash;': '–',
    '&hellip;': '…',
  };
  named.forEach((k, v) => s = s.replaceAll(k, v));
  s = s.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
    final code = int.tryParse(m.group(1)!);
    return code != null ? String.fromCharCode(code) : m.group(0)!;
  });
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}
