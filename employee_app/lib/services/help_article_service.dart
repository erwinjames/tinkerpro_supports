import 'dart:convert';

import '../api_client.dart';
import 'session_store.dart';

/// One row of the FAQ list rendered in HelpGuideScreen. Built from
/// the admin Help Center (`help` + `help_content` tables) via the
/// `help.public` API action; the screen only needs a flat title +
/// plain-text body per entry, so we flatten the topic + blocks at
/// fetch time.
class HelpArticle {
  HelpArticle({required this.title, required this.body});
  final String title;
  final String body;
}

/// Fetches the admin-managed help topics, caches the last good
/// payload to SessionStore for offline use, and exposes a flat list
/// of [HelpArticle] for the FAQ render. Falls back to the cached
/// JSON when the network call fails; the screen layers its own
/// baked-in defaults below this when nothing is cached either
/// (fresh install with no first-launch connection).
class HelpArticleService {
  HelpArticleService({required this.api, required this.store});
  final ApiClient api;
  final SessionStore store;

  /// One-shot fetch of `help.public`. Returns a non-empty list when
  /// either the network or the cache had something usable; empty
  /// list means "show the baked-in fallback".
  Future<List<HelpArticle>> load() async {
    Map<String, dynamic>? payload;
    try {
      final res = await api.get('help.public');
      if (res['success'] == true && res['topics'] is List) {
        payload = res;
      }
    } catch (_) {
      // Network down — fall through to cache.
    }
    if (payload != null) {
      try {
        // Persist the raw payload for next cold launch.
        await store.saveCachedHelpJson(jsonEncode(payload));
      } catch (_) {/* non-fatal */}
      return _articlesFromPayload(payload);
    }
    // Network failed or returned unusable shape — try the last
    // successful response.
    final cached = store.cachedHelpJson;
    if (cached != null && cached.isNotEmpty) {
      try {
        final decoded = jsonDecode(cached);
        if (decoded is Map<String, dynamic>) {
          return _articlesFromPayload(decoded);
        }
      } catch (_) {/* fall through */}
    }
    return const [];
  }

  static List<HelpArticle> _articlesFromPayload(Map<String, dynamic> p) {
    final topics = p['topics'];
    if (topics is! List) return const [];
    final out = <HelpArticle>[];
    for (final t in topics) {
      if (t is! Map) continue;
      final title = (t['title'] ?? '').toString().trim();
      if (title.isEmpty) continue;
      final body = _composeBody(Map<String, dynamic>.from(t));
      if (body.isEmpty) continue;
      out.add(HelpArticle(title: title, body: body));
    }
    return out;
  }

  /// Compose the article body from the topic's `description` (plain
  /// intro) plus every `help_content` block's `text_content`. Blocks
  /// store HTML emitted by TinyMCE in the admin — we strip tags down
  /// to plain text and unescape the common entities the editor adds
  /// so the FAQ renders as readable paragraphs without depending on
  /// a heavyweight HTML renderer.
  static String _composeBody(Map<String, dynamic> topic) {
    final pieces = <String>[];
    final desc = (topic['description'] ?? '').toString().trim();
    if (desc.isNotEmpty) pieces.add(_stripHtml(desc));
    final blocks = topic['blocks'];
    if (blocks is List) {
      for (final b in blocks) {
        if (b is! Map) continue;
        final raw = (b['text_content'] ?? '').toString();
        final cleaned = _stripHtml(raw);
        if (cleaned.isNotEmpty) pieces.add(cleaned);
        final img = (b['image_path'] ?? '').toString().trim();
        if (img.isNotEmpty) pieces.add('[image: $img]');
      }
    }
    return pieces.join('\n\n').trim();
  }

  /// Cheap HTML → plain-text converter:
  /// * `<br>` and `</p>`/`</div>`/`</li>` become newlines.
  /// * Bullet `<li>` openers get a leading "• ".
  /// * Every remaining tag is dropped.
  /// * The handful of entities TinyMCE actually emits are unescaped.
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
        // Now drop every tag.
        .replaceAll(RegExp(r'<[^>]+>'), '')
        // Common entities. Order matters: do `&amp;` last so we don't
        // re-expand entities we just unescaped.
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&');
    // Collapse 3+ newlines and trim trailing whitespace per line.
    out = out.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    out = out.split('\n').map((l) => l.trimRight()).join('\n').trim();
    return out;
  }
}
