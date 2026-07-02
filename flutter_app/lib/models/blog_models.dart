// Domain model for the Blog Posts feature. Mirrors the `getBlogPosts`
// row shape returned by `api.php` (data: [...], totalRecords: N).

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
  });

  final int id;
  final String title;
  final String content;

  /// 1 = draft (not yet published), 0 = published.
  final int isDraft;

  /// Backend status string: 'draft' or 'published'.
  final String status;
  final String? scheduledAt;
  final String createdAt;
  final String updatedAt;

  bool get isDraftPost => isDraft == 1;

  /// [content] is stored as HTML. The app has no HTML renderer, so this strips
  /// tags and decodes common entities for clean plain-text display in the
  /// list and detail views.
  String get plainContent => _stripHtml(content);

  factory BlogPost.fromJson(Map<String, dynamic> json) => BlogPost(
        id: _asInt(json['id']),
        title: (json['title'] ?? '').toString(),
        content: (json['content'] ?? '').toString(),
        isDraft: _asInt(json['is_draft']),
        status: (json['status'] ?? '').toString(),
        scheduledAt: json['scheduled_at']?.toString(),
        createdAt: (json['created_at'] ?? '').toString(),
        updatedAt: (json['updated_at'] ?? '').toString(),
      );
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

/// Strip HTML tags and decode the common entities so post content reads as
/// plain text (no `<p style=…>` etc. leaking into the UI).
String _stripHtml(String html) {
  if (html.isEmpty) return '';
  // Turn block boundaries into spaces, then drop all tags.
  var s = html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'</(p|div|h[1-6]|li|tr)>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<[^>]+>'), ' ');
  // Common named entities.
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
  // Numeric entities (&#123;).
  s = s.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
    final code = int.tryParse(m.group(1)!);
    return code != null ? String.fromCharCode(code) : m.group(0)!;
  });
  // Collapse whitespace.
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}
