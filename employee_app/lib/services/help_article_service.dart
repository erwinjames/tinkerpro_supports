import 'dart:convert';

import '../api_client.dart';
import 'session_store.dart';

/// One row of the FAQ list rendered in HelpGuideScreen. Built from
/// the admin Help Center (`help` + `help_content` tables) via the
/// `help.public` API action; we flatten the topic + blocks into a
/// title, a plain-text body (HTML → text), and an ordered list of
/// raw image filenames (resolved by the screen against
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
      final composed = _compose(Map<String, dynamic>.from(t));
      if (composed.body.isEmpty && composed.imagePaths.isEmpty) continue;
      out.add(HelpArticle(
        title: title,
        body: composed.body,
        imagePaths: composed.imagePaths,
      ));
    }
    return out;
  }

  /// Walk the topic's description + each help_content block, peel
  /// the HTML down to plain text, and collect any attached image
  /// filenames as a separate list (so the renderer can show them
  /// inline beneath the text instead of leaking [image: …]
  /// placeholders into the body).
  static ({String body, List<String> imagePaths}) _compose(
    Map<String, dynamic> topic,
  ) {
    final textPieces = <String>[];
    final images = <String>[];
    final desc = (topic['description'] ?? '').toString().trim();
    if (desc.isNotEmpty) textPieces.add(_stripHtml(desc));
    final blocks = topic['blocks'];
    if (blocks is List) {
      for (final b in blocks) {
        if (b is! Map) continue;
        final raw = (b['text_content'] ?? '').toString();
        final cleaned = _stripHtml(raw);
        if (cleaned.isNotEmpty) textPieces.add(cleaned);
        final img = (b['image_path'] ?? '').toString().trim();
        if (img.isNotEmpty) images.add(img);
      }
    }
    return (body: textPieces.join('\n\n').trim(), imagePaths: images);
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
