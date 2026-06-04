import 'dart:convert';

import 'package:dio/dio.dart';

import '../api_client.dart';
import 'session_store.dart';

/// One row of the FAQ list rendered in HelpGuideScreen. Built from
/// the admin Help Center (`help` + `help_content` tables) via the
/// public `getPublicHelpTopics` / `getPublicHelpContent` API actions;
/// we flatten the topic description + content blocks into a title, a
/// plain-text body (HTML → text), and an ordered list of raw image
/// filenames (resolved by the screen against
/// `${baseUrl}/uploads/help/{path}`).
class HelpArticle {
  const HelpArticle({
    required this.title,
    required this.body,
    this.imagePaths = const [],
  });
  final String title;
  final String body;
  final List<String> imagePaths;
}

/// Fetches the admin-managed help topics from the public Help Center
/// API, caches the last good payload to SessionStore for offline use,
/// and exposes a flat list of [HelpArticle] for the FAQ render.
///
/// The Help Center is the same one that powers the public marketing
/// site's `/help` page (tinkerpro.io). It exposes two public actions on
/// the support server's `api.php`:
///
///   • `getPublicHelpTopics`               → { success, data: [topic…] }
///   • `getPublicHelpContent&topic_id=N`   → { success, topic, content: [block…] }
///
/// We fetch the topic list, then pull each topic's content blocks in
/// parallel and compose them into one [HelpArticle] per topic. Falls
/// back to the cached JSON when the network call fails; the screen
/// layers its own baked-in defaults below this when nothing is cached
/// either (fresh install with no first-launch connection).
class HelpArticleService {
  HelpArticleService({required this.api, required this.store, String? helpBaseUrl})
      : baseUrl = helpBaseUrl ?? kHelpBaseUrl;
  final ApiClient api;
  final SessionStore store;

  /// Origin the Help Center is served from. The Help Guide fetches the
  /// public help actions and resolves `/uploads/help/*` images against
  /// this — see [kHelpBaseUrl]. Kept independent of [ApiClient.baseUrl]
  /// (the logged-in app server) on purpose.
  final String baseUrl;

  /// Lazily-built Dio bound to [baseUrl]. The help actions are public
  /// endpoints, so no cookie jar / session is needed here.
  Dio? _dio;
  Dio get _client => _dio ??= Dio(BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 30),
        followRedirects: true,
        validateStatus: (s) => s != null && s < 500,
      ));

  /// One-shot fetch of the public Help Center. Returns a non-empty list
  /// when either the network or the cache had something usable; an empty
  /// list means "show the baked-in fallback".
  Future<List<HelpArticle>> load() async {
    final fresh = await _loadFromNetwork();
    if (fresh != null && fresh.isNotEmpty) {
      try {
        await store.saveCachedHelpJson(_encode(fresh));
      } catch (_) {/* non-fatal */}
      return fresh;
    }
    // Network failed or returned nothing usable — try the last
    // successful response.
    return _loadFromCache();
  }

  /// Fetch the topic list + each topic's content blocks. Returns null on
  /// a hard failure (list call failed / unusable shape) so the caller
  /// falls back to cache; an empty list means the server has no topics.
  Future<List<HelpArticle>?> _loadFromNetwork() async {
    List<dynamic> topics;
    try {
      final res = await _client.get<dynamic>(
        '/api.php',
        queryParameters: const {'action': 'getPublicHelpTopics'},
      );
      final map = _asMap(res.data);
      if (map == null || map['success'] != true || map['data'] is! List) {
        return null;
      }
      topics = map['data'] as List;
    } catch (_) {
      return null;
    }

    // Pull every topic's content blocks concurrently. Topics number in
    // the low dozens, so a fan-out of small GETs is cheaper (and far
    // simpler) than a paginated bulk endpoint we'd have to add server-side.
    final futures = <Future<HelpArticle?>>[];
    for (final t in topics) {
      if (t is! Map) continue;
      final id = (t['id'] as num?)?.toInt();
      final title = (t['title'] ?? '').toString().trim();
      if (id == null || title.isEmpty) continue;
      final description = (t['description'] ?? '').toString();
      futures.add(_fetchTopicArticle(id, title, description));
    }
    final results = await Future.wait(futures);
    return results
        .whereType<HelpArticle>()
        .where((a) => a.body.isNotEmpty || a.imagePaths.isNotEmpty)
        .toList(growable: false);
  }

  /// Fetch one topic's content blocks and compose them into a single
  /// article. If the content call fails, we still surface the topic with
  /// its description so the FAQ row isn't lost entirely.
  Future<HelpArticle?> _fetchTopicArticle(
    int id,
    String title,
    String description,
  ) async {
    try {
      final res = await _client.get<dynamic>(
        '/api.php',
        queryParameters: {'action': 'getPublicHelpContent', 'topic_id': id},
      );
      final map = _asMap(res.data);
      final blocks =
          (map != null && map['content'] is List) ? map['content'] as List : const [];
      final composed = _composeBlocks(description, blocks);
      return HelpArticle(
        title: title,
        body: composed.body,
        imagePaths: composed.imagePaths,
      );
    } catch (_) {
      // List loaded but this topic's content didn't — degrade to the
      // description rather than dropping the topic.
      return HelpArticle(title: title, body: _stripHtml(description).trim());
    }
  }

  /// Walk the topic's content blocks, peel each block's HTML down to
  /// plain text, and collect any attached image filenames as a separate
  /// list (so the renderer can show them inline beneath the text instead
  /// of leaking placeholders into the body). When no block carries text,
  /// fall back to the topic description so the body isn't blank.
  static ({String body, List<String> imagePaths}) _composeBlocks(
    String description,
    List<dynamic> blocks,
  ) {
    final textPieces = <String>[];
    final images = <String>[];
    for (final b in blocks) {
      if (b is! Map) continue;
      final cleaned = _stripHtml((b['text_content'] ?? '').toString()).trim();
      if (cleaned.isNotEmpty) textPieces.add(cleaned);
      final img = (b['image_path'] ?? '').toString().trim();
      if (img.isNotEmpty) images.add(img);
    }
    if (textPieces.isEmpty) {
      final desc = _stripHtml(description).trim();
      if (desc.isNotEmpty) textPieces.add(desc);
    }
    return (body: textPieces.join('\n\n').trim(), imagePaths: images);
  }

  // ── Cache (de)serialization ────────────────────────────────────────
  // We persist the composed article list (not the raw API payload) so a
  // cold launch can render instantly without re-running the fan-out.

  static String _encode(List<HelpArticle> articles) {
    return jsonEncode([
      for (final a in articles)
        {'title': a.title, 'body': a.body, 'images': a.imagePaths},
    ]);
  }

  List<HelpArticle> _loadFromCache() {
    final cached = store.cachedHelpJson;
    if (cached == null || cached.isEmpty) return const [];
    try {
      final decoded = jsonDecode(cached);
      if (decoded is! List) return const []; // old payload shape → fallback
      return decoded
          .whereType<Map>()
          .map((m) => HelpArticle(
                title: (m['title'] ?? '').toString(),
                body: (m['body'] ?? '').toString(),
                imagePaths: m['images'] is List
                    ? List<String>.from(
                        (m['images'] as List).map((e) => e.toString()))
                    : const [],
              ))
          .where((a) => a.title.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static Map<String, dynamic>? _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String && data.isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {/* not JSON */}
    }
    return null;
  }

  /// Cheap HTML → plain-text converter:
  /// * `<br>` and `</p>`/`</div>`/`</li>` become newlines.
  /// * Bullet `<li>` openers get a leading "• ".
  /// * Every remaining tag is dropped.
  /// * Named entities TinyMCE emits (`&bull;`, smart-quotes, dashes,
  ///   ellipsis, etc.) are decoded; numeric refs (`&#160;`, `&#x2019;`)
  ///   handled via a single regex sweep.
  /// * Multiple blank lines collapse to one to keep the FAQ tidy.
  static String _stripHtml(String s) {
    if (s.isEmpty) return s;
    var out = s
        // Normalise line-breaking tags to newlines BEFORE stripping.
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'</div\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</li\s*>', caseSensitive: false), '\n')
        .replaceAllMapped(RegExp(r'<li[^>]*>', caseSensitive: false),
            (_) => '• ')
        // Now drop every remaining tag.
        .replaceAll(RegExp(r'<[^>]+>'), '');
    // Numeric entity sweep first (so we don't accidentally pre-decode
    // an `&amp;#39;` into `&#39;` and miss it). Handles both decimal
    // (`&#39;`) and hex (`&#x27;`) forms.
    out = out.replaceAllMapped(
      RegExp(r'&#(x?[0-9a-fA-F]+);'),
      (m) {
        final raw = m.group(1) ?? '';
        try {
          final n = raw.startsWith('x') || raw.startsWith('X')
              ? int.parse(raw.substring(1), radix: 16)
              : int.parse(raw);
          if (n > 0 && n < 0x110000) return String.fromCharCode(n);
        } catch (_) {/* fall through */}
        return m.group(0)!;
      },
    );
    // Named entities. Includes everything TinyMCE actually emits on
    // this admin's content (bullet, smart quotes, dashes, ellipsis,
    // trademark, etc.). Order matters: keep `&amp;` last so we don't
    // re-decode entities we just unescaped.
    const named = <String, String>{
      '&nbsp;': ' ',
      '&quot;': '"',
      '&apos;': "'",
      '&lt;': '<',
      '&gt;': '>',
      '&bull;': '•', // •
      '&middot;': '·', // ·
      '&rsquo;': '’', // ’
      '&lsquo;': '‘', // ‘
      '&rdquo;': '”', // ”
      '&ldquo;': '“', // “
      '&laquo;': '«', // «
      '&raquo;': '»', // »
      '&ndash;': '–', // –
      '&mdash;': '—', // —
      '&hellip;': '…', // …
      '&trade;': '™', // ™
      '&reg;': '®', // ®
      '&copy;': '©', // ©
      '&deg;': '°', // °
    };
    named.forEach((k, v) => out = out.replaceAll(k, v));
    out = out.replaceAll('&amp;', '&');
    // Collapse 3+ newlines and trim trailing whitespace per line.
    out = out.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    out = out.split('\n').map((l) => l.trimRight()).join('\n').trim();
    return out;
  }
}
