import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import 'premium.dart';

const int kHelpMediaMaxWidth = 720;
const int kHelpMediaMaxHeight = 720;
const int kHelpInlineImageMaxBytes = 6 * 1024 * 1024;

String helpHtmlToPlain(String html) {
  if (html.isEmpty) return '';
  return helpDecodeEntities(
    html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(
          RegExp(r'</(p|div|li|h[1-6]|tr)>', caseSensitive: false),
          '\n',
        )
        .replaceAll(RegExp(r'<[^>]+>'), ''),
  ).replaceAll(RegExp(r'[ \t]+\n'), '\n').trim();
}

String helpHtmlSummary(String html, {int limit = 220}) {
  final plain = helpHtmlToPlain(html).replaceAll(RegExp(r'\s+'), ' ').trim();
  return plain.length <= limit ? plain : plain.substring(0, limit);
}

String helpDecodeEntities(String value) {
  var out = value
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&hellip;', '…')
      .replaceAll('&mdash;', '—')
      .replaceAll('&ndash;', '–');
  out = out.replaceAllMapped(RegExp(r'&#(\d{1,6});'), (m) {
    final code = int.tryParse(m.group(1)!);
    return code == null ? m.group(0)! : String.fromCharCode(code);
  });
  return out.replaceAll('&amp;', '&');
}

String helpEscapeHtml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String? helpVideoEmbedUrl(String rawUrl) {
  final url = rawUrl.trim();
  if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(url)) return null;
  final parsed = Uri.tryParse(url);
  if (parsed == null) return null;

  final host = parsed.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
  final segments = parsed.pathSegments;
  final start =
      parsed.queryParameters['t'] ?? parsed.queryParameters['start'] ?? '';
  final startSeconds = RegExp(r'^\d+$').hasMatch(start) ? start : '';

  String youtube(String id) =>
      'https://www.youtube.com/embed/$id${startSeconds.isEmpty ? '' : '?start=$startSeconds'}';

  if (host == 'youtu.be') {
    return segments.isEmpty ? null : youtube(segments.first);
  }
  if (host == 'youtube.com' ||
      host == 'm.youtube.com' ||
      host == 'youtube-nocookie.com') {
    if (parsed.path.startsWith('/embed/')) return url;
    final id =
        parsed.queryParameters['v'] ??
        (segments.length > 1 && ['shorts', 'live', 'v'].contains(segments.first)
            ? segments[1]
            : null);
    return id == null || id.isEmpty ? null : youtube(id);
  }
  if (host == 'vimeo.com') {
    final id = RegExp(r'/(\d+)').firstMatch(parsed.path)?.group(1);
    return id == null ? null : 'https://player.vimeo.com/video/$id';
  }
  if (host == 'player.vimeo.com') return url;
  if (host == 'loom.com') {
    final id = RegExp(
      r'/(?:share|embed)/([^/?]+)',
    ).firstMatch(parsed.path)?.group(1);
    return id == null ? null : 'https://www.loom.com/embed/$id';
  }
  if (host == 'drive.google.com') {
    final id =
        RegExp(r'/file/d/([^/]+)').firstMatch(parsed.path)?.group(1) ??
        parsed.queryParameters['id'];
    return id == null || id.isEmpty
        ? null
        : 'https://drive.google.com/file/d/$id/preview';
  }
  if (host == 'dailymotion.com' || host == 'geo.dailymotion.com') {
    final id = RegExp(r'/video/([^/?]+)').firstMatch(parsed.path)?.group(1);
    return id == null ? null : 'https://www.dailymotion.com/embed/video/$id';
  }
  if (host == 'streamable.com') {
    final id = parsed.path
        .replaceFirst(RegExp(r'^/(?:e/)?'), '')
        .split('/')
        .first;
    return id.isEmpty ? null : 'https://streamable.com/e/$id';
  }
  return null;
}

({int width, int height}) helpFittedSize(int width, int height) {
  if (width <= 0 || height <= 0) {
    return (
      width: kHelpMediaMaxWidth,
      height: (kHelpMediaMaxWidth * 9 / 16).round(),
    );
  }
  final scale = [
    1.0,
    kHelpMediaMaxWidth / width,
    kHelpMediaMaxHeight / height,
  ].reduce((a, b) => a < b ? a : b);
  return (
    width: (width * scale).round().clamp(1, kHelpMediaMaxWidth),
    height: (height * scale).round().clamp(1, kHelpMediaMaxHeight),
  );
}

Future<({int width, int height})?> helpImageSize(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final size = (width: frame.image.width, height: frame.image.height);
    frame.image.dispose();
    codec.dispose();
    return size;
  } catch (_) {
    return null;
  }
}

String helpImageMimeType(String extension) {
  switch (extension.toLowerCase()) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    default:
      return 'image/png';
  }
}

class _HelpBlock {
  _HelpBlock(this.tag, this.inner, this.attrs);
  final String tag;
  final String inner;
  final String attrs;
}

const Set<String> _blockTags = {
  'p',
  'div',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'ul',
  'ol',
  'blockquote',
  'pre',
  'table',
  'figure',
};

List<_HelpBlock> _parseBlocks(String html) {
  final blocks = <_HelpBlock>[];
  final open = RegExp(
    '<(${_blockTags.join('|')})\\b([^>]*)>',
    caseSensitive: false,
  );
  var cursor = 0;
  while (cursor < html.length) {
    final match = open.firstMatch(html.substring(cursor));
    if (match == null) {
      final rest = html.substring(cursor);
      if (rest.trim().isNotEmpty) blocks.add(_HelpBlock('p', rest, ''));
      break;
    }
    final before = html.substring(cursor, cursor + match.start);
    if (before.trim().isNotEmpty) blocks.add(_HelpBlock('p', before, ''));

    final tag = match.group(1)!.toLowerCase();
    final attrs = match.group(2) ?? '';
    final contentStart = cursor + match.end;
    final end = _findClosing(html, tag, contentStart);
    final inner = html.substring(contentStart, end.content);
    blocks.add(_HelpBlock(tag, inner, attrs));
    cursor = end.next;
  }
  return blocks;
}

({int content, int next}) _findClosing(String html, String tag, int from) {
  final pattern = RegExp('</?$tag\\b[^>]*>', caseSensitive: false);
  var depth = 1;
  var cursor = from;
  while (cursor < html.length) {
    final match = pattern.firstMatch(html.substring(cursor));
    if (match == null) break;
    final absolute = cursor + match.start;
    final closing = match.group(0)!.startsWith('</');
    if (closing) {
      depth--;
      if (depth == 0) {
        return (content: absolute, next: cursor + match.end);
      }
    } else {
      depth++;
    }
    cursor = cursor + match.end;
  }
  return (content: html.length, next: html.length);
}

List<String> _parseItems(String html, String tag) {
  final items = <String>[];
  final open = RegExp('<$tag\\b[^>]*>', caseSensitive: false);
  var cursor = 0;
  while (cursor < html.length) {
    final match = open.firstMatch(html.substring(cursor));
    if (match == null) break;
    final contentStart = cursor + match.end;
    final end = _findClosing(html, tag, contentStart);
    items.add(html.substring(contentStart, end.content));
    cursor = end.next;
  }
  return items;
}

String? _styleValue(String attrs, String property) {
  final style = RegExp(
    r'''style=["']([^"']*)["']''',
    caseSensitive: false,
  ).firstMatch(attrs)?.group(1);
  if (style == null) return null;
  for (final part in style.split(';')) {
    final index = part.indexOf(':');
    if (index <= 0) continue;
    if (part.substring(0, index).trim().toLowerCase() == property) {
      return part.substring(index + 1).trim();
    }
  }
  return null;
}

String? _attrValue(String attrs, String name) => RegExp(
  '$name=["\']([^"\']*)["\']',
  caseSensitive: false,
).firstMatch(attrs)?.group(1);

Color? helpParseCssColor(String? raw) {
  if (raw == null) return null;
  var value = raw.trim().toLowerCase();
  if (value.startsWith('#')) {
    value = value.substring(1);
    if (value.length == 3) {
      value = value.split('').map((c) => '$c$c').join();
    }
    if (value.length == 6) value = 'ff$value';
    final parsed = int.tryParse(value, radix: 16);
    return parsed == null ? null : Color(parsed);
  }
  final rgb = RegExp(r'^rgba?\(([^)]*)\)$').firstMatch(value);
  if (rgb != null) {
    final parts = rgb.group(1)!.split(',').map((p) => p.trim()).toList();
    if (parts.length >= 3) {
      final r = int.tryParse(parts[0]);
      final g = int.tryParse(parts[1]);
      final b = int.tryParse(parts[2]);
      if (r != null && g != null && b != null) {
        return Color.fromARGB(255, r, g, b);
      }
    }
  }
  const named = {
    'black': Colors.black,
    'white': Colors.white,
    'red': Colors.red,
    'blue': Colors.blue,
    'green': Colors.green,
    'orange': Colors.orange,
    'yellow': Colors.yellow,
    'grey': Colors.grey,
    'gray': Colors.grey,
  };
  return named[value];
}

class HelpHtmlView extends StatefulWidget {
  const HelpHtmlView({super.key, required this.html, this.headers = const {}});

  final String html;
  final Map<String, String> headers;

  @override
  State<HelpHtmlView> createState() => _HelpHtmlViewState();
}

class _HelpHtmlViewState extends State<HelpHtmlView> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
    super.dispose();
  }

  void _retireRecognizers() {
    if (_recognizers.isEmpty) return;
    final retired = List<TapGestureRecognizer>.from(_recognizers);
    _recognizers.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final recognizer in retired) {
        recognizer.dispose();
      }
    });
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    _retireRecognizers();
    final blocks = _parseBlocks(widget.html);
    final children = <Widget>[];
    for (final block in blocks) {
      children.addAll(_buildBlock(context, block));
    }
    if (children.isEmpty) {
      final b = context.brand;
      return Text(
        'Nothing to preview yet.',
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: b.paperDim),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  List<Widget> _buildBlock(BuildContext context, _HelpBlock block) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    switch (block.tag) {
      case 'ul':
      case 'ol':
        final items = _parseItems(block.inner, 'li');
        return [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < items.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 26,
                          child: Text(
                            block.tag == 'ol' ? '${i + 1}.' : '•',
                            style: text.bodyMedium?.copyWith(
                              color: b.signalInk,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: _inlineWidgets(
                              context,
                              items[i],
                              text.bodyMedium!,
                              TextAlign.start,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ];
      case 'blockquote':
        return [
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: BoxDecoration(
              color: b.surfaceHi,
              border: Border(left: BorderSide(color: b.signal, width: 3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _inlineWidgets(
                context,
                block.inner,
                text.bodyMedium!,
                TextAlign.start,
              ),
            ),
          ),
        ];
      case 'pre':
        return [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: b.surfaceHi,
              borderRadius: BorderRadius.circular(Brand.radiusSm),
              border: Border.all(color: b.rule),
            ),
            child: Text(
              helpHtmlToPlain(block.inner),
              style: text.bodySmall?.copyWith(fontFamily: 'monospace'),
            ),
          ),
        ];
      case 'table':
        return [_buildTable(context, block)];
      default:
        final style = _blockStyle(context, block.tag);
        return [
          Padding(
            padding: EdgeInsets.only(bottom: block.tag == 'p' ? 10 : 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _inlineWidgets(
                context,
                block.inner,
                style,
                _align(block.attrs),
              ),
            ),
          ),
        ];
    }
  }

  TextAlign _align(String attrs) {
    switch (_styleValue(attrs, 'text-align')) {
      case 'center':
        return TextAlign.center;
      case 'right':
        return TextAlign.right;
      case 'justify':
        return TextAlign.justify;
      default:
        return TextAlign.start;
    }
  }

  TextStyle _blockStyle(BuildContext context, String tag) {
    final text = Theme.of(context).textTheme;
    switch (tag) {
      case 'h1':
        return text.titleLarge!;
      case 'h2':
        return text.titleMedium!;
      case 'h3':
        return text.titleSmall!;
      case 'h4':
      case 'h5':
      case 'h6':
        return text.labelLarge!;
      default:
        return text.bodyMedium!;
    }
  }

  Widget _buildTable(BuildContext context, _HelpBlock block) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final rows = _parseItems(block.inner, 'tr');
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        border: Border.all(color: b.rule),
        borderRadius: BorderRadius.circular(Brand.radiusSm),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var r = 0; r < rows.length; r++)
            Container(
              decoration: BoxDecoration(
                color: r.isEven ? b.surface : b.surfaceHi,
                border: r == 0 ? null : Border(top: BorderSide(color: b.rule)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final cell in _parseCells(rows[r]))
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          helpHtmlToPlain(cell),
                          style: text.bodySmall,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<String> _parseCells(String row) {
    final cells = [..._parseItems(row, 'th'), ..._parseItems(row, 'td')];
    return cells.isEmpty ? [row] : cells;
  }

  List<Widget> _inlineWidgets(
    BuildContext context,
    String html,
    TextStyle base,
    TextAlign align,
  ) {
    final widgets = <Widget>[];
    final media = RegExp(
      r'<(img|video|iframe)\b([^>]*)>',
      caseSensitive: false,
    );
    var cursor = 0;
    while (cursor < html.length) {
      final match = media.firstMatch(html.substring(cursor));
      if (match == null) break;
      final before = html.substring(cursor, cursor + match.start);
      final span = _span(context, before, base);
      if (span != null) {
        widgets.add(Text.rich(span, textAlign: align));
      }
      widgets.add(
        _mediaWidget(
          context,
          match.group(1)!.toLowerCase(),
          match.group(2) ?? '',
        ),
      );
      cursor = cursor + match.end;
    }
    final tail = html.substring(cursor);
    final span = _span(context, tail, base);
    if (span != null) widgets.add(Text.rich(span, textAlign: align));
    return widgets;
  }

  Widget _mediaWidget(BuildContext context, String tag, String attrs) {
    final b = context.brand;
    final src = _attrValue(attrs, 'src') ?? '';
    if (tag == 'img') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Brand.radiusSm),
          child: _image(context, helpDecodeEntities(src)),
        ),
      );
    }
    final label = tag == 'iframe' ? 'Embedded video' : 'Uploaded video';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        onTap: src.isEmpty ? null : () => _open(helpDecodeEntities(src)),
        child: Row(
          children: [
            IconTile(icon: Icons.play_circle_outline_rounded, color: b.signal),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    helpDecodeEntities(src),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Icon(Icons.open_in_new_rounded, size: 18, color: b.paperDim),
          ],
        ),
      ),
    );
  }

  Widget _image(BuildContext context, String src) {
    final b = context.brand;
    final fallback = Container(
      height: 120,
      alignment: Alignment.center,
      color: b.surfaceHi,
      child: Icon(Icons.image_not_supported_rounded, color: b.paperDim),
    );
    if (src.isEmpty) return fallback;
    if (src.startsWith('data:image/')) {
      final index = src.indexOf('base64,');
      if (index < 0) return fallback;
      try {
        final bytes = base64Decode(src.substring(index + 7));
        return Image.memory(bytes, fit: BoxFit.contain);
      } catch (_) {
        return fallback;
      }
    }
    if (!src.startsWith('http')) return fallback;
    return CachedNetworkImage(
      imageUrl: src,
      httpHeaders: widget.headers,
      fit: BoxFit.contain,
      placeholder: (_, _) =>
          const Skeleton(height: 120, width: double.infinity),
      errorWidget: (_, _, _) => fallback,
    );
  }

  InlineSpan? _span(BuildContext context, String html, TextStyle base) {
    if (html.trim().isEmpty) return null;
    final b = context.brand;
    final children = <InlineSpan>[];
    final styles = <TextStyle>[base];
    final hrefs = <String>[];
    final tagPattern = RegExp(r'</?([a-zA-Z0-9]+)([^>]*)>');
    var cursor = 0;

    void addText(String raw) {
      if (raw.isEmpty) return;
      final value = helpDecodeEntities(raw).replaceAll(RegExp(r'\s+'), ' ');
      if (value.isEmpty) return;
      final href = hrefs.isEmpty ? null : hrefs.last;
      if (href == null) {
        children.add(TextSpan(text: value, style: styles.last));
        return;
      }
      final recognizer = TapGestureRecognizer()..onTap = () => _open(href);
      _recognizers.add(recognizer);
      children.add(
        TextSpan(text: value, style: styles.last, recognizer: recognizer),
      );
    }

    while (cursor < html.length) {
      final match = tagPattern.firstMatch(html.substring(cursor));
      if (match == null) {
        addText(html.substring(cursor));
        break;
      }
      addText(html.substring(cursor, cursor + match.start));
      final tag = match.group(1)!.toLowerCase();
      final attrs = match.group(2) ?? '';
      final closing = match.group(0)!.startsWith('</');
      if (tag == 'br') {
        children.add(const TextSpan(text: '\n'));
      } else if (closing) {
        if (styles.length > 1) styles.removeLast();
        if (tag == 'a' && hrefs.isNotEmpty) hrefs.removeLast();
      } else {
        var style = styles.last;
        switch (tag) {
          case 'strong':
          case 'b':
            style = style.copyWith(fontWeight: FontWeight.w700);
          case 'em':
          case 'i':
            style = style.copyWith(fontStyle: FontStyle.italic);
          case 'u':
            style = style.copyWith(decoration: TextDecoration.underline);
          case 's':
          case 'strike':
            style = style.copyWith(decoration: TextDecoration.lineThrough);
          case 'code':
            style = style.copyWith(fontFamily: 'monospace');
          case 'a':
            hrefs.add(helpDecodeEntities(_attrValue(attrs, 'href') ?? ''));
            style = style.copyWith(
              color: b.signalInk,
              decoration: TextDecoration.underline,
            );
          case 'span':
            final color = helpParseCssColor(_styleValue(attrs, 'color'));
            final background = helpParseCssColor(
              _styleValue(attrs, 'background-color'),
            );
            final size = _styleValue(attrs, 'font-size');
            final points = size == null
                ? null
                : double.tryParse(size.replaceAll(RegExp(r'[^0-9.]'), ''));
            style = style.copyWith(
              color: color ?? style.color,
              backgroundColor: background,
              fontSize: points != null && points > 6 && points < 96
                  ? points
                  : style.fontSize,
            );
        }
        styles.add(style);
      }
      cursor = cursor + match.end;
    }

    if (children.isEmpty) return null;
    return TextSpan(children: children, style: base);
  }
}
