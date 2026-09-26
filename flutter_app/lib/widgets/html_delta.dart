import 'package:flutter_quill/quill_delta.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';

const String kOpaqueEmbed = 'tpblock';
const String kSoftBreak = ' ';

const Set<String> _opaqueTags = {'table', 'iframe', 'video', 'hr'};

final InlineStyles _inlineStyles = InlineStyles({
  ...defaultInlineStyles.attrs,
  'size': InlineStyleType(
    fn: (value, _) {
      const named = {
        'small': 'font-size: 0.75em',
        'large': 'font-size: 1.5em',
        'huge': 'font-size: 2.5em',
      };
      if (named.containsKey(value)) return named[value];
      final n = double.tryParse(value.replaceAll('px', ''));
      return n == null ? null : 'font-size:${n.round()}px';
    },
  ),
  'indent': InlineStyleType(
    fn: (value, _) {
      final level = int.tryParse(value) ?? 0;
      return level <= 0 ? null : 'padding-left:${level * 40}px';
    },
  ),
});

class HtmlDeltaDocument {
  HtmlDeltaDocument._(this.delta, this.opaque, this.images);

  final Delta delta;
  final Map<String, String> opaque;
  final Map<String, String> images;

  String addOpaque(String html) {
    var index = opaque.length;
    while (opaque.containsKey('$index')) {
      index++;
    }
    final key = '$index';
    opaque[key] = html;
    return key;
  }

  void setImageSize(String src, int? width, int? height) {
    if (width == null) return;
    images[src] = '$width|${height ?? ''}|';
  }

  String toHtml([Delta? edited]) =>
      deltaToHtml(edited ?? delta, opaque: opaque, images: images);
}

HtmlDeltaDocument htmlToDeltaDocument(String html) {
  final opaque = <String, String>{};
  final images = <String, String>{};
  final delta = _HtmlImporter(opaque, images).convert(_rgbToHex(html));
  return HtmlDeltaDocument._(delta, opaque, images);
}

String deltaToHtml(
  Delta delta, {
  Map<String, String> opaque = const {},
  Map<String, String> images = const {},
}) {
  final ops = <Map<String, dynamic>>[];
  for (final raw in delta.toJson()) {
    final op = Map<String, dynamic>.from(raw);
    final insert = op['insert'];
    if (insert is Map && insert.containsKey(kOpaqueEmbed)) {
      op['attributes'] = {
        ...?(op['attributes'] as Map?)?.cast<String, dynamic>(),
        'renderAsBlock': true,
      };
    }
    ops.add(op);
  }
  final converter = QuillDeltaToHtmlConverter(
    ops,
    ConverterOptions(
      multiLineParagraph: false,
      multiLineHeader: false,
      converterOptions: OpConverterOptions(
        inlineStylesFlag: true,
        inlineStyles: _inlineStyles,
      ),
    ),
  );
  converter.renderCustomWith = (op, _) {
    final data = op.insert;
    if (data is InsertDataCustom && data.type == kOpaqueEmbed) {
      return opaque[data.value.toString()] ?? '';
    }
    return '';
  };
  var html = converter.convert().replaceAll(kSoftBreak, '<br>');
  for (final snippet in opaque.values) {
    for (final blank in const ['<p><br/></p>', '<p><br></p>']) {
      html = html.replaceFirst('$snippet$blank', snippet);
    }
  }
  html = _restoreImageSizes(html, images);
  return _tidy(html);
}

String? htmlRoundTripIssue(String html) {
  final source = html.trim();
  if (source.isEmpty) return null;
  try {
    final a = htmlFingerprint(source).split('\n');
    final b = htmlFingerprint(htmlToDeltaDocument(source).toHtml()).split('\n');
    for (var i = 0; i < a.length || i < b.length; i++) {
      final x = i < a.length ? a[i] : '';
      final y = i < b.length ? b[i] : '';
      if (x == y) continue;
      var line = x.isNotEmpty && x != 'LI' ? x : y;
      if (line == 'LI' && i + 1 < a.length) line = a[i + 1];
      final text = line
          .replaceFirst(RegExp(r'^.*?::'), '')
          .replaceAll(RegExp(r'\{[^}]*\}'), '')
          .replaceAll('|BR|', ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (text.isEmpty) return '';
      return text.length > 70 ? '${text.substring(0, 70)}…' : text;
    }
    return null;
  } catch (_) {
    return '';
  }
}

bool htmlSurvivesRoundTrip(String html) {
  final source = html.trim();
  if (source.isEmpty) return true;
  try {
    final rebuilt = htmlToDeltaDocument(source).toHtml();
    return htmlFingerprint(rebuilt) == htmlFingerprint(source);
  } catch (_) {
    return false;
  }
}

class _HtmlImporter {
  _HtmlImporter(this._opaque, this._images);

  final Map<String, String> _opaque;
  final Map<String, String> _images;
  final Delta _delta = Delta();
  bool _lineHasContent = false;
  int _pendingBreaks = 0;

  static const _blockTags = {
    'p',
    'div',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'blockquote',
    'pre',
    'li',
    'ul',
    'ol',
  };

  Delta convert(String html) {
    final body = html_parser.parse(html).body;
    if (body != null) {
      _walkChildren(body, const {}, const {}, 0, false);
    }
    if (_lineHasContent || _delta.isEmpty) _endLine(const {});
    return _delta;
  }

  void _walkChildren(
    dom.Element element,
    Map<String, dynamic> inline,
    Map<String, dynamic> block,
    int listDepth,
    bool pre,
  ) {
    for (final node in element.nodes) {
      _walk(node, inline, block, listDepth, pre);
    }
  }

  void _walk(
    dom.Node node,
    Map<String, dynamic> inline,
    Map<String, dynamic> block,
    int listDepth,
    bool pre,
  ) {
    if (node is dom.Text) {
      _text(node.text, inline, pre);
      return;
    }
    if (node is! dom.Element) return;
    final tag = node.localName ?? '';

    if (tag == 'br') {
      if (_lineHasContent) _pendingBreaks++;
      return;
    }
    if (tag == 'img') {
      final src = node.attributes['src'] ?? '';
      if (src.isEmpty) return;
      final width = node.attributes['width'] ?? '';
      final style = node.attributes['style'] ?? '';
      if (width.isNotEmpty || style.isNotEmpty) {
        _images[src] = '$width|${node.attributes['height'] ?? ''}|$style';
      }
      _embed({'image': src}, inline);
      return;
    }
    if (_opaqueTags.contains(tag)) {
      if (_lineHasContent) _endLine(block);
      final key = '${_opaque.length}';
      _opaque[key] = node.outerHtml;
      _delta.insert({kOpaqueEmbed: key});
      _lineHasContent = true;
      _endLine(const {});
      return;
    }
    if (tag == 'ul' || tag == 'ol') {
      if (_lineHasContent) _endLine(block);
      final nextDepth = listDepth + 1;
      for (final child in node.nodes) {
        if (child is dom.Element && child.localName == 'li') {
          final itemBlock = <String, dynamic>{
            'list': tag == 'ol' ? 'ordered' : 'bullet',
            if (nextDepth > 1) 'indent': nextDepth - 1,
            ..._alignOf(child),
          };
          _block(child, _inlineFrom(child, inline), itemBlock, nextDepth, pre);
        } else if (child is dom.Element) {
          _walk(child, inline, block, listDepth, pre);
        }
      }
      return;
    }
    if (_blockTags.contains(tag)) {
      final own = <String, dynamic>{..._alignOf(node), ..._indentOf(node)};
      if (tag.length == 2 && tag.startsWith('h')) {
        final level = int.tryParse(tag.substring(1));
        if (level != null) own['header'] = level;
      }
      if (tag == 'blockquote') own['blockquote'] = true;
      if (tag == 'pre') own['code-block'] = true;
      final merged = {...block, ...own};
      _block(
        node,
        _inlineFrom(node, inline),
        merged,
        listDepth,
        pre || tag == 'pre',
      );
      return;
    }
    _walkChildren(node, _inlineFrom(node, inline), block, listDepth, pre);
  }

  void _block(
    dom.Element element,
    Map<String, dynamic> inline,
    Map<String, dynamic> block,
    int listDepth,
    bool pre,
  ) {
    if (_lineHasContent) _endLine(block);
    final hasBlockChild = element.children.any(
      (c) =>
          _blockTags.contains(c.localName) || _opaqueTags.contains(c.localName),
    );
    _walkChildren(element, inline, block, listDepth, pre);
    if (_lineHasContent || !hasBlockChild) _endLine(block);
  }

  Map<String, dynamic> _inlineFrom(
    dom.Element element,
    Map<String, dynamic> base,
  ) {
    final out = Map<String, dynamic>.from(base);
    switch (element.localName) {
      case 'strong':
      case 'b':
        out['bold'] = true;
      case 'em':
      case 'i':
        out['italic'] = true;
      case 'u':
        out['underline'] = true;
      case 's':
      case 'strike':
      case 'del':
        out['strike'] = true;
      case 'code':
        out['code'] = true;
      case 'sub':
        out['script'] = 'sub';
      case 'sup':
        out['script'] = 'super';
      case 'a':
        final href = element.attributes['href'];
        if (href != null && href.isNotEmpty) out['link'] = href;
    }
    final style = element.attributes['style'];
    final color = _styleValue(style, 'color');
    if (color != null && color.isNotEmpty) out['color'] = color;
    final background = _styleValue(style, 'background-color');
    if (background != null && background.isNotEmpty) {
      out['background'] = background;
    }
    final size = _pxOf(_styleValue(style, 'font-size'));
    if (size != null) out['size'] = size.round().toString();
    final weight = _styleValue(style, 'font-weight');
    if (weight == 'bold' || weight == '700' || weight == '600') {
      out['bold'] = true;
    }
    if (_styleValue(style, 'font-style') == 'italic') out['italic'] = true;
    final decoration = _styleValue(style, 'text-decoration') ?? '';
    if (decoration.contains('underline')) out['underline'] = true;
    if (decoration.contains('line-through')) out['strike'] = true;
    return out;
  }

  Map<String, dynamic> _alignOf(dom.Element element) {
    final align = _styleValue(element.attributes['style'], 'text-align');
    if (align == 'center' || align == 'right' || align == 'justify') {
      return {'align': align};
    }
    return const {};
  }

  Map<String, dynamic> _indentOf(dom.Element element) {
    final level = _indentLevel(element.attributes['style']);
    return level > 0 ? {'indent': level} : const {};
  }

  void _text(String raw, Map<String, dynamic> inline, bool pre) {
    if (pre) {
      final parts = raw.split('\n');
      for (var i = 0; i < parts.length; i++) {
        if (parts[i].isNotEmpty) _insertText(parts[i], inline);
        if (i < parts.length - 1) _endLine(const {'code-block': true});
      }
      return;
    }
    var value = raw.replaceAll(RegExp(r'[ \t\r\n\f]+'), ' ');
    if (!_lineHasContent || _pendingBreaks > 0) {
      value = value.replaceFirst(RegExp(r'^ +'), '');
    }
    if (value.isEmpty) return;
    _insertText(value, inline);
  }

  void _flushBreaks(Map<String, dynamic> inline) {
    if (_pendingBreaks <= 0) return;
    _delta.insert(
      kSoftBreak * _pendingBreaks,
      inline.isEmpty ? null : Map.of(inline),
    );
    _pendingBreaks = 0;
  }

  void _insertText(String value, Map<String, dynamic> inline) {
    _flushBreaks(inline);
    _delta.insert(value, inline.isEmpty ? null : Map.of(inline));
    _lineHasContent = true;
  }

  void _embed(Map<String, dynamic> data, Map<String, dynamic> inline) {
    _flushBreaks(inline);
    _delta.insert(data);
    _lineHasContent = true;
  }

  void _endLine(Map<String, dynamic> block) {
    if (_pendingBreaks >= 2) _flushBreaks(const {});
    _pendingBreaks = 0;
    _delta.insert('\n', block.isEmpty ? null : Map.of(block));
    _lineHasContent = false;
  }
}

String? _styleValue(String? style, String property) {
  if (style == null || style.isEmpty) return null;
  for (final part in style.split(';')) {
    final bits = part.split(':');
    if (bits.length < 2) continue;
    if (bits.first.trim().toLowerCase() == property) {
      return bits.sublist(1).join(':').trim().toLowerCase();
    }
  }
  return null;
}

double? _pxOf(String? value) {
  if (value == null) return null;
  final v = value.trim();
  if (v.endsWith('px')) return double.tryParse(v.substring(0, v.length - 2));
  if (v.endsWith('pt')) {
    final n = double.tryParse(v.substring(0, v.length - 2));
    return n == null ? null : n * 4 / 3;
  }
  if (v.endsWith('rem') || v.endsWith('em')) {
    final n = double.tryParse(v.replaceAll(RegExp(r'r?em$'), ''));
    return n == null ? null : n * 16;
  }
  return double.tryParse(v);
}

int _indentLevel(String? style) {
  final pad =
      _styleValue(style, 'padding-left') ?? _styleValue(style, 'margin-left');
  final px = _pxOf(pad);
  if (px == null || px < 20) return 0;
  return (px / 40).round().clamp(1, 8);
}

String _rgbToHex(String html) {
  return html.replaceAllMapped(
    RegExp(r'rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,[^)]*)?\)'),
    (match) {
      int channel(int group) =>
          (int.tryParse(match.group(group) ?? '0') ?? 0).clamp(0, 255);
      final value = (channel(1) << 16) | (channel(2) << 8) | channel(3);
      return '#${value.toRadixString(16).padLeft(6, '0')}';
    },
  );
}

String _restoreImageSizes(String html, Map<String, String> images) {
  if (images.isEmpty) return html;
  final body = html_parser.parse(html).body;
  if (body == null) return html;
  var touched = false;
  for (final image in body.querySelectorAll('img')) {
    final src = image.attributes['src'] ?? '';
    final dims = images[src];
    if (dims == null) continue;
    final parts = dims.split('|');
    final style = parts.length > 2 ? parts.sublist(2).join('|') : '';
    if (style.isNotEmpty && (image.attributes['style'] ?? '').isEmpty) {
      image.attributes['style'] = style;
      touched = true;
    }
    if ((image.attributes['width'] ?? '').isNotEmpty) continue;
    if (parts.first.isNotEmpty) image.attributes['width'] = parts.first;
    if (parts.length > 1 && parts[1].isNotEmpty) {
      image.attributes['height'] = parts[1];
    }
    touched = true;
  }
  return touched ? body.innerHtml : html;
}

String _tidy(String html) {
  var out = html.trim();
  const blanks = ['<p><br/></p>', '<p><br></p>'];
  var changed = true;
  while (changed) {
    changed = false;
    for (final blank in blanks) {
      if (out.endsWith(blank)) {
        out = out.substring(0, out.length - blank.length).trimRight();
        changed = true;
      }
    }
  }
  return out;
}

const Set<String> _fpBlockTags = {
  'p',
  'div',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'blockquote',
  'pre',
  'li',
};

String htmlFingerprint(String html) {
  final body = html_parser.parse(_rgbToHex(html)).body;
  if (body == null) return '';
  final lines = <String>[];
  final current = StringBuffer();
  var currentBlock = '';
  var lastKey = '';

  void flush() {
    final text = current.toString().trim();
    if (text.isNotEmpty) lines.add('$currentBlock::$text');
    current.clear();
    lastKey = '';
  }

  String inlineKey(Map<String, String> attrs) {
    final keys = attrs.keys.toList()..sort();
    return keys.map((k) => '$k=${attrs[k]}').join(',');
  }

  void walk(dom.Node node, Map<String, String> inline, String block) {
    if (node is dom.Text) {
      final text = node.text.replaceAll(RegExp(r'[\s ]+'), ' ');
      if (text.trim().isEmpty && current.isEmpty) return;
      final key = inlineKey(inline);
      if (key != lastKey) {
        current.write('{$key}');
        lastKey = key;
      }
      current.write(text);
      return;
    }
    if (node is! dom.Element) return;
    final tag = node.localName ?? '';
    if (tag == 'br') {
      if (current.toString().trim().isNotEmpty) {
        final trimmed = current.toString().trimRight();
        current
          ..clear()
          ..write('$trimmed|BR|');
        lastKey = '';
      }
      return;
    }
    if (tag == 'img') {
      current.write(
        '[IMG ${node.attributes['src'] ?? ''} ${node.attributes['width'] ?? ''}]',
      );
      lastKey = '';
      return;
    }
    if (_opaqueTags.contains(tag)) {
      flush();
      lines.add('OPAQUE::${node.outerHtml}');
      return;
    }

    final style = node.attributes['style'];
    final next = Map<String, String>.from(inline);
    switch (tag) {
      case 'strong':
      case 'b':
        next['bold'] = '1';
      case 'em':
      case 'i':
        next['italic'] = '1';
      case 'u':
        next['underline'] = '1';
      case 's':
      case 'strike':
      case 'del':
        next['strike'] = '1';
      case 'code':
        next['code'] = '1';
      case 'a':
        final href = node.attributes['href'];
        if (href != null && href.isNotEmpty) next['link'] = href;
    }
    final color = _styleValue(style, 'color');
    if (color != null) next['color'] = color;
    final bg = _styleValue(style, 'background-color');
    if (bg != null) next['bg'] = bg;
    final size = _pxOf(_styleValue(style, 'font-size'));
    if (size != null) next['size'] = size.round().toString();
    final weight = _styleValue(style, 'font-weight');
    if (weight == 'bold' || weight == '700' || weight == '600') {
      next['bold'] = '1';
    }
    if (_styleValue(style, 'font-style') == 'italic') next['italic'] = '1';
    final decoration = _styleValue(style, 'text-decoration') ?? '';
    if (decoration.contains('underline')) next['underline'] = '1';
    if (decoration.contains('line-through')) next['strike'] = '1';

    if (_fpBlockTags.contains(tag)) {
      final hasBlockChild = node.children.any(
        (c) =>
            _fpBlockTags.contains(c.localName) ||
            c.localName == 'ul' ||
            c.localName == 'ol' ||
            _opaqueTags.contains(c.localName),
      );
      var kind = tag == 'div' ? 'p' : tag;
      if (tag == 'li') {
        var depth = 0;
        dom.Element? cursor = node.parent;
        while (cursor != null) {
          if (cursor.localName == 'ul' || cursor.localName == 'ol') depth++;
          cursor = cursor.parent;
        }
        kind = 'li:${node.parent?.localName ?? 'ul'}:$depth';
      }
      final align = _styleValue(style, 'text-align');
      if (align != null && align != 'left' && align != 'start') {
        kind = '$kind:a=$align';
      }
      final indent = _indentLevel(style);
      if (indent > 0) kind = '$kind:i=$indent';
      if (block.startsWith('blockquote')) kind = 'blockquote>$kind';
      if (tag == 'div' && hasBlockChild) kind = block;
      final insideItem =
          (tag == 'p' || tag == 'div') && block.startsWith('li:');
      if (insideItem) kind = block;
      flush();
      if (tag == 'li') lines.add('LI');
      final saved = currentBlock;
      currentBlock = kind;
      for (final child in node.nodes) {
        walk(child, next, kind);
      }
      flush();
      currentBlock = saved;
      return;
    }
    for (final child in node.nodes) {
      walk(child, next, block);
    }
  }

  currentBlock = 'p';
  for (final child in body.nodes) {
    walk(child, const {}, 'p');
  }
  flush();
  return lines
      .map(
        (l) => l.replaceAll(RegExp(r'\|BR\|$'), '').replaceAll(' |BR|', '|BR|'),
      )
      .join('\n');
}
