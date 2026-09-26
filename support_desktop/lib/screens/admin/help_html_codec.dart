import 'dart:convert';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as hp;

class HelpNodes {
  static const paragraph = 'paragraph';
  static const heading = 'heading';
  static const bulleted = 'bulleted_list';
  static const numbered = 'numbered_list';
  static const image = 'tp_image';
  static const media = 'tp_media';

  static const tag = 'tp_tag';
  static const style = 'tp_style';
  static const indent = 'tp_indent';
  static const align = 'align';
  static const level = 'level';
  static const listStart = 'tp_start';
  static const listStyle = 'tp_list_style';
  static const pWrapped = 'tp_p';
  static const pStyle = 'tp_p_style';
  static const lead = 'tp_lead';
  static const bareEmpty = 'tp_empty';

  static const src = 'src';
  static const alt = 'alt';
  static const title = 'title';
  static const width = 'width';
  static const height = 'height';
  static const imgStyle = 'style';
  static const wrapStyle = 'tp_wrap_style';
  static const link = 'tp_link';
  static const loading = 'tp_loading';
  static const html = 'tp_html';

  static const extraCss = 'tp_css';
  static const anchor = 'tp_a';

  static bool isList(String type) => type == bulleted || type == numbered;
  static bool isText(String type) =>
      type == paragraph || type == heading || isList(type);
}

class HelpDecodeResult {
  HelpDecodeResult(this.nodes, this.issues);
  final List<Node> nodes;
  final List<String> issues;
}

const _inlineTags = {
  'span', 'strong', 'b', 'em', 'i', 'u', 's', 'strike', 'del', 'code', 'a',
  'font', 'br', 'img', 'video', 'iframe',
};

const _blockTags = {
  'p', 'div', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'pre', 'ul', 'ol', 'li',
  'blockquote', 'table', 'thead', 'tbody', 'tfoot', 'tr', 'td', 'th',
  'caption', 'colgroup', 'col', 'hr', 'section', 'article', 'header', 'footer',
  'figure', 'figcaption', 'center', 'dl', 'dt', 'dd', 'address', 'form',
};

const _supportedStyleForInline = {
  'color', 'background-color', 'background', 'font-size', 'font-family',
  'font-weight', 'font-style', 'text-decoration', 'text-decoration-line',
};

Map<String, String> parseCss(String? style) {
  final out = <String, String>{};
  for (final part in (style ?? '').split(';')) {
    final i = part.indexOf(':');
    if (i <= 0) continue;
    final k = part.substring(0, i).trim().toLowerCase();
    final v = part.substring(i + 1).trim();
    if (k.isEmpty || v.isEmpty) continue;
    out[k] = v;
  }
  return out;
}

String cssString(Map<String, String> css) =>
    css.entries.map((e) => '${e.key}: ${e.value};').join(' ');

String setCssDecl(String? style, String prop, String? value) {
  final css = parseCss(style);
  if (value == null || value.isEmpty) {
    css.remove(prop);
  } else {
    css[prop] = value;
  }
  return cssString(css);
}

double? cssPxValue(String? v) {
  if (v == null) return null;
  final m = RegExp(r'^\s*(\d+(?:\.\d+)?)\s*(px)?\s*$', caseSensitive: false).firstMatch(v);
  return m == null ? null : double.tryParse(m.group(1)!);
}

String _fmtNum(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

String escapeHtmlText(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll(' ', '&nbsp;');

String escapeHtmlAttr(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('"', '&quot;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

class _Piece {
  _Piece(this.text, this.attrs, {this.hard = false});
  final String text;
  final Map<String, dynamic> attrs;
  final bool hard;
}

class _Embed {
  _Embed(this.node);
  final Node node;
}

class HelpHtmlCodec {
  HelpHtmlCodec._();

  static HelpDecodeResult decode(String html) {
    final d = _Decoder();
    final frag = hp.parseFragment(html);
    final nodes = d.blocks(frag.nodes, pre: false);
    return HelpDecodeResult(nodes, d.issues.toList());
  }

  static Document decodeDocument(List<Node> nodes) {
    final children = nodes.isEmpty ? [paragraphNode()] : nodes;
    return Document(root: pageNode(children: children));
  }

  static String encode(Iterable<Node> nodes, {String Function(String src)? resolveSrc}) {
    final e = _Encoder(resolveSrc ?? (s) => s);
    return e.blocks(nodes.toList());
  }

  static List<String> roundTripIssues(String html) {
    final decoded = decode(html);
    if (decoded.issues.isNotEmpty) return decoded.issues;
    final again = encode(decoded.nodes);
    final a = helpHtmlSignature(html);
    final b = helpHtmlSignature(again);
    if (_listEq(a, b)) return const [];
    var i = 0;
    while (i < a.length && i < b.length && a[i] == b[i]) {
      i++;
    }
    final near = i < a.length ? _describeToken(a[i]) : 'the end of the document';
    return ['Content near $near would change after conversion'];
  }

  static bool _listEq(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static String _describeToken(String t) {
    final parts = t.split('\u0001');
    switch (parts.first) {
      case 'W':
        return '"${parts.last}"';
      case 'I':
        return 'an image';
      case 'M':
        return 'a video';
      default:
        return 'the document';
    }
  }
}

class _Decoder {
  final Set<String> issues = {};

  void _issue(String s) => issues.add(s);

  List<Node> blocks(List<dom.Node> nodes, {required bool pre}) {
    final out = <Node>[];
    final run = <dom.Node>[];

    void flush() {
      if (run.isEmpty) return;
      final onlySpace = run.every((n) => n is dom.Text && n.data.trim().isEmpty && !n.data.contains(' '));
      if (!onlySpace) {
        out.addAll(_textBlock(HelpNodes.paragraph, {HelpNodes.tag: ''}, List.of(run), pre: pre, wrapStyle: ''));
      }
      run.clear();
    }

    for (final n in nodes) {
      if (n is dom.Comment) continue;
      if (n is dom.Text) {
        run.add(n);
        continue;
      }
      if (n is! dom.Element) continue;
      final tag = n.localName ?? '';
      if (_inlineTags.contains(tag)) {
        run.add(n);
        continue;
      }
      flush();
      switch (tag) {
        case 'p':
        case 'pre':
          out.addAll(_styledTextBlock(n, HelpNodes.paragraph, tag));
        case 'h1':
        case 'h2':
        case 'h3':
        case 'h4':
        case 'h5':
        case 'h6':
          out.addAll(_styledTextBlock(n, HelpNodes.heading, tag));
        case 'div':
          final hasBlock = n.nodes.any((c) => c is dom.Element && _blockTags.contains(c.localName));
          if (!hasBlock) {
            out.addAll(_styledTextBlock(n, HelpNodes.paragraph, 'div'));
          } else if (n.attributes.isEmpty) {
            out.addAll(blocks(n.nodes, pre: pre));
          } else {
            _issue('A styled <div> container');
          }
        case 'ul':
        case 'ol':
          out.addAll(_list(n));
        case 'table':
        case 'thead':
        case 'tbody':
        case 'tfoot':
        case 'tr':
        case 'td':
        case 'th':
        case 'caption':
        case 'colgroup':
        case 'col':
          _issue('Tables');
        case 'blockquote':
          _issue('Block quotes');
        case 'li':
          _issue('A list item outside of a list');
        default:
          _issue('The <$tag> element');
      }
    }
    flush();
    return out;
  }

  List<Node> _styledTextBlock(dom.Element el, String type, String tag) {
    final extra = el.attributes.keys.map((k) => '$k'.toLowerCase()).where((k) => k != 'style').toList();
    if (extra.isNotEmpty) _issue('Extra attributes (${extra.join(', ')}) on <$tag>');
    final css = parseCss(el.attributes['style']);
    final attrs = <String, dynamic>{HelpNodes.tag: tag};
    final align = css.remove('text-align')?.toLowerCase();
    if (align != null) {
      if (const {'left', 'center', 'right', 'justify'}.contains(align)) {
        attrs[HelpNodes.align] = align;
      } else {
        css['text-align'] = align;
      }
    }
    final pad = css['padding-left'];
    final padPx = cssPxValue(pad);
    if (padPx != null) {
      css.remove('padding-left');
      attrs[HelpNodes.indent] = padPx.round();
    }
    if (css.isNotEmpty) attrs[HelpNodes.style] = cssString(css);
    if (type == HelpNodes.heading) attrs[HelpNodes.level] = int.parse(tag.substring(1));
    final hasBlock = el.nodes.any((c) => c is dom.Element && _blockTags.contains(c.localName));
    if (hasBlock) {
      _issue('Block content nested inside <$tag>');
      return const [];
    }
    return _textBlock(type, attrs, el.nodes, pre: tag == 'pre', wrapStyle: el.attributes['style'] ?? '');
  }

  List<Node> _textBlock(
    String type,
    Map<String, dynamic> attrs,
    List<dom.Node> content, {
    required bool pre,
    required String wrapStyle,
  }) {
    final items = <Object>[];
    for (final c in content) {
      _inline(c, const {}, items, pre: pre, link: null);
    }
    final segments = <Object>[];
    var buf = <_Piece>[];
    for (final it in items) {
      if (it is _Embed) {
        segments.add(buf);
        buf = <_Piece>[];
        final node = it.node;
        final a = Map<String, dynamic>.from(node.attributes);
        if (attrs[HelpNodes.align] != null) a[HelpNodes.align] = attrs[HelpNodes.align];
        a[HelpNodes.wrapStyle] = wrapStyle;
        a['tp_wrap_tag'] = attrs[HelpNodes.tag] ?? '';
        segments.add(Node(type: node.type, attributes: a));
      } else {
        buf.add(it as _Piece);
      }
    }
    segments.add(buf);
    final hasEmbed = segments.any((s) => s is Node);
    final out = <Node>[];
    for (var i = 0; i < segments.length; i++) {
      final s = segments[i];
      if (s is Node) {
        out.add(s);
        continue;
      }
      var pieces = _whitespace(s as List<_Piece>, pre: pre);
      if (hasEmbed) {
        if (i > 0 && segments[i - 1] is Node) pieces = _dropEdgeBreak(pieces, leading: true);
        if (i < segments.length - 1 && segments[i + 1] is Node) pieces = _dropEdgeBreak(pieces, leading: false);
        final text = pieces.map((p) => p.text).join();
        if (text.replaceAll(RegExp(r'[\s ]'), '').isEmpty && !text.contains('\n')) continue;
        if (text.isEmpty) continue;
      }
      final delta = Delta();
      for (final p in _mergePieces(pieces)) {
        delta.insert(p.text, attributes: p.attrs.isEmpty ? null : p.attrs);
      }
      final a = Map<String, dynamic>.from(attrs);
      if (!hasEmbed && delta.isEmpty && content.isEmpty) a[HelpNodes.bareEmpty] = true;
      a['delta'] = delta.toJson();
      out.add(Node(type: type, attributes: a));
    }
    return out;
  }

  List<_Piece> _dropEdgeBreak(List<_Piece> pieces, {required bool leading}) {
    if (pieces.isEmpty) return pieces;
    final list = List.of(pieces);
    final idx = leading ? 0 : list.length - 1;
    final p = list[idx];
    if (p.text == '\n' && p.hard) list.removeAt(idx);
    return list;
  }

  List<_Piece> _mergePieces(List<_Piece> pieces) {
    final out = <_Piece>[];
    for (final p in pieces) {
      if (p.text.isEmpty) continue;
      if (out.isNotEmpty && _attrKey(out.last.attrs) == _attrKey(p.attrs)) {
        out[out.length - 1] = _Piece(out.last.text + p.text, p.attrs);
      } else {
        out.add(_Piece(p.text, p.attrs));
      }
    }
    return out;
  }

  List<_Piece> _whitespace(List<_Piece> pieces, {required bool pre}) {
    if (pre) {
      final out = <_Piece>[];
      for (var i = 0; i < pieces.length; i++) {
        var t = pieces[i].text.replaceAll('\r\n', '\n');
        if (i == 0 && !pieces[i].hard && t.startsWith('\n')) t = t.substring(1);
        out.add(_Piece(t, pieces[i].attrs, hard: pieces[i].hard));
      }
      return out;
    }
    final chars = <(String, Map<String, dynamic>, bool)>[];
    for (final p in pieces) {
      if (p.hard) {
        chars.add(('\n', p.attrs, true));
        continue;
      }
      final t = p.text.replaceAll(RegExp(r'[ \t\n\r\f]+'), ' ');
      for (final ch in t.split('')) {
        chars.add((ch, p.attrs, false));
      }
    }
    final kept = <(String, Map<String, dynamic>, bool)>[];
    for (var i = 0; i < chars.length; i++) {
      final c = chars[i];
      if (c.$1 == ' ' && !c.$3) {
        final prev = kept.isEmpty ? null : kept.last;
        if (prev == null || (prev.$1 == '\n' && prev.$3) || (prev.$1 == ' ' && !prev.$3)) continue;
        var j = i + 1;
        while (j < chars.length && chars[j].$1 == ' ' && !chars[j].$3) {
          j++;
        }
        if (j >= chars.length || (chars[j].$1 == '\n' && chars[j].$3)) continue;
      }
      kept.add(c);
    }
    return [for (final c in kept) _Piece(c.$1, c.$2, hard: c.$3)];
  }

  void _inline(
    dom.Node n,
    Map<String, dynamic> attrs,
    List<Object> out, {
    required bool pre,
    required String? link,
  }) {
    if (n is dom.Text) {
      out.add(_Piece(n.data, attrs));
      return;
    }
    if (n is! dom.Element) return;
    final tag = n.localName ?? '';
    switch (tag) {
      case 'br':
        out.add(_Piece('\n', attrs, hard: true));
        return;
      case 'img':
        out.add(_Embed(_imageNode(n, link)));
        return;
      case 'video':
      case 'iframe':
        if (link != null) _issue('A video inside a link');
        out.add(_Embed(_mediaNode(n)));
        return;
    }
    if (!_inlineTags.contains(tag)) {
      if (_blockTags.contains(tag)) {
        _issue('Block content nested inside inline formatting');
      } else {
        _issue('The <$tag> element');
      }
      return;
    }
    final a = Map<String, dynamic>.from(attrs);
    String? nextLink = link;
    switch (tag) {
      case 'strong':
      case 'b':
        a['bold'] = true;
      case 'em':
      case 'i':
        a['italic'] = true;
      case 'u':
        a['underline'] = true;
      case 's':
      case 'strike':
      case 'del':
        a['strikethrough'] = true;
      case 'code':
        a['code'] = true;
      case 'font':
        final color = n.attributes['color'];
        if (color != null && color.isNotEmpty) a['font_color'] = color;
        final size = int.tryParse(n.attributes['size'] ?? '');
        const map = {1: 10.0, 2: 13.0, 3: 16.0, 4: 18.0, 5: 24.0, 6: 32.0, 7: 48.0};
        if (size != null && map[size] != null) a['font_size'] = map[size];
      case 'a':
        final href = n.attributes['href'] ?? '';
        final meta = <String, String>{};
        for (final e in n.attributes.entries) {
          final k = '${e.key}'.toLowerCase();
          if (k == 'href') continue;
          meta[k] = e.value;
        }
        a['href'] = href;
        if (meta.isNotEmpty) {
          a[HelpNodes.anchor] = jsonEncode(meta);
        } else {
          a.remove(HelpNodes.anchor);
        }
        nextLink = jsonEncode({'href': href, ...meta});
    }
    if (tag != 'a') {
      final extraAttrs = n.attributes.keys
          .map((k) => '$k'.toLowerCase())
          .where((k) => k != 'style' && !(tag == 'font' && (k == 'color' || k == 'size' || k == 'face')))
          .toList();
      if (extraAttrs.isNotEmpty) _issue('Extra attributes (${extraAttrs.join(', ')}) on <$tag>');
      if (tag == 'font' && (n.attributes['face'] ?? '').isNotEmpty) a['font_family'] = n.attributes['face'];
      _applyCss(parseCss(n.attributes['style']), a);
    }
    for (final c in n.nodes) {
      _inline(c, a, out, pre: pre, link: nextLink);
    }
  }

  void _applyCss(Map<String, String> css, Map<String, dynamic> a) {
    final extra = parseCss(a[HelpNodes.extraCss] as String?);
    css.forEach((k, v) {
      final lv = v.toLowerCase();
      switch (k) {
        case 'color':
          a['font_color'] = v;
        case 'background-color':
          a['bg_color'] = v;
        case 'font-family':
          a['font_family'] = v;
        case 'font-size':
          final px = cssPxValue(v);
          if (px != null) {
            a['font_size'] = px;
            extra.remove('font-size');
          } else {
            a.remove('font_size');
            extra[k] = v;
          }
        case 'font-weight':
          if (lv == 'bold' || lv == 'bolder' || (int.tryParse(lv) ?? 0) >= 600) {
            a['bold'] = true;
          } else {
            extra[k] = v;
          }
        case 'font-style':
          if (lv == 'italic' || lv == 'oblique') {
            a['italic'] = true;
          } else {
            extra[k] = v;
          }
        case 'text-decoration':
        case 'text-decoration-line':
          final parts = lv.split(RegExp(r'\s+'));
          var handled = false;
          if (parts.contains('underline')) {
            a['underline'] = true;
            handled = true;
          }
          if (parts.contains('line-through')) {
            a['strikethrough'] = true;
            handled = true;
          }
          if (!handled || parts.any((p) => p != 'underline' && p != 'line-through')) extra[k] = v;
        default:
          extra[k] = v;
      }
    });
    if (extra.isEmpty) {
      a.remove(HelpNodes.extraCss);
    } else {
      a[HelpNodes.extraCss] = cssString(extra);
    }
  }

  Node _imageNode(dom.Element el, String? link) {
    final attrs = <String, dynamic>{};
    for (final e in el.attributes.entries) {
      final k = '${e.key}'.toLowerCase();
      switch (k) {
        case 'src':
        case 'alt':
        case 'title':
        case 'width':
        case 'height':
        case 'style':
          attrs[k] = e.value;
        default:
          _issue('Extra image attributes ($k)');
      }
    }
    if (link != null) attrs[HelpNodes.link] = link;
    return Node(type: HelpNodes.image, attributes: attrs);
  }

  Node _mediaNode(dom.Element el) {
    for (final c in el.nodes) {
      if (c is dom.Element && c.localName != 'source') _issue('Unexpected content inside a video');
    }
    return Node(type: HelpNodes.media, attributes: {HelpNodes.html: el.outerHtml});
  }

  List<Node> _list(dom.Element el) {
    final type = el.localName == 'ol' ? HelpNodes.numbered : HelpNodes.bulleted;
    final extra = el.attributes.keys.map((k) => '$k'.toLowerCase()).where((k) => k != 'style').toList();
    if (extra.isNotEmpty) _issue('Extra attributes (${extra.join(', ')}) on a list');
    final out = <Node>[];
    for (final c in el.nodes) {
      if (c is dom.Comment) continue;
      if (c is dom.Text) {
        if (c.data.trim().isNotEmpty) _issue('Text directly inside a list');
        continue;
      }
      if (c is! dom.Element) continue;
      if (c.localName != 'li') {
        _issue('A <${c.localName}> directly inside a list');
        continue;
      }
      out.add(_listItem(c, type, first: out.isEmpty, listStyle: el.attributes['style']));
    }
    if (out.isEmpty) _issue('An empty list');
    return out;
  }

  Node _listItem(dom.Element li, String type, {required bool first, String? listStyle}) {
    final extra = li.attributes.keys.map((k) => '$k'.toLowerCase()).where((k) => k != 'style').toList();
    if (extra.isNotEmpty) _issue('Extra attributes (${extra.join(', ')}) on a list item');
    final attrs = <String, dynamic>{};
    final css = parseCss(li.attributes['style']);
    final align = css.remove('text-align')?.toLowerCase();
    if (align != null) attrs[HelpNodes.align] = align;
    if (css.isNotEmpty) attrs[HelpNodes.style] = cssString(css);
    if (first) {
      attrs[HelpNodes.listStart] = true;
      if ((listStyle ?? '').trim().isNotEmpty) attrs[HelpNodes.listStyle] = listStyle;
    }
    final kids = blocks(li.nodes, pre: false);
    var delta = Delta();
    var rest = kids;
    final head = kids.isEmpty ? null : kids.first;
    if (head != null &&
        head.type == HelpNodes.paragraph &&
        (head.attributes[HelpNodes.tag] == '' || head.attributes[HelpNodes.tag] == 'p') &&
        head.attributes[HelpNodes.indent] == null) {
      delta = Delta.fromJson(head.attributes['delta'] as List);
      rest = kids.sublist(1);
      if (head.attributes[HelpNodes.tag] == 'p') {
        attrs[HelpNodes.pWrapped] = true;
        final pAlign = head.attributes[HelpNodes.align];
        if (pAlign != null) {
          if (attrs[HelpNodes.align] != null && attrs[HelpNodes.align] != pAlign) {
            _issue('Conflicting alignment in a list item');
          }
          attrs[HelpNodes.align] = pAlign;
        }
        final ps = head.attributes[HelpNodes.style];
        if (ps != null) attrs[HelpNodes.pStyle] = ps;
      }
    } else {
      attrs[HelpNodes.lead] = true;
    }
    attrs['delta'] = delta.toJson();
    return Node(type: type, attributes: attrs, children: rest);
  }
}

String _attrKey(Map<String, dynamic>? a) {
  if (a == null || a.isEmpty) return '';
  final keys = a.keys.toList()..sort();
  return keys.map((k) => '$k=${a[k]}').join('|');
}

class _Encoder {
  _Encoder(this.resolveSrc);
  final String Function(String src) resolveSrc;

  String blocks(List<Node> nodes) {
    final sb = StringBuffer();
    var i = 0;
    var prevBare = false;
    while (i < nodes.length) {
      final n = nodes[i];
      if (HelpNodes.isList(n.type)) {
        var j = i + 1;
        while (j < nodes.length && nodes[j].type == n.type && nodes[j].attributes[HelpNodes.listStart] != true) {
          j++;
        }
        final tag = n.type == HelpNodes.numbered ? 'ol' : 'ul';
        final ls = (n.attributes[HelpNodes.listStyle] as String?) ?? '';
        sb.write('<$tag${ls.trim().isEmpty ? '' : ' style="${escapeHtmlAttr(ls)}"'}>\n');
        for (var k = i; k < j; k++) {
          sb.write(_item(nodes[k]));
        }
        sb.write('</$tag>\n');
        i = j;
        prevBare = false;
        continue;
      }
      final bare = n.type == HelpNodes.paragraph && n.attributes[HelpNodes.tag] == '' &&
          n.attributes[HelpNodes.align] == null && n.attributes[HelpNodes.indent] == null;
      if (bare && prevBare) sb.write('<br>');
      sb.write(_block(n));
      if (n.children.isNotEmpty) sb.write(blocks(n.children.toList()));
      prevBare = bare;
      i++;
    }
    return sb.toString();
  }

  String _item(Node n) {
    final sb = StringBuffer();
    var style = (n.attributes[HelpNodes.style] as String?) ?? '';
    final align = n.attributes[HelpNodes.align] as String?;
    final pWrapped = n.attributes[HelpNodes.pWrapped] == true;
    final delta = n.delta ?? Delta();
    final lead = n.attributes[HelpNodes.lead] == true && delta.isEmpty;
    var pStyle = (n.attributes[HelpNodes.pStyle] as String?) ?? '';
    if (align != null) {
      if (pWrapped && !lead) {
        pStyle = setCssDecl(pStyle, 'text-align', align);
      } else {
        style = setCssDecl(style, 'text-align', align);
      }
    }
    sb.write('<li${_styleAttr(style)}>');
    if (!lead) {
      final inline = _inline(delta);
      if (pWrapped) {
        sb.write('<p${_styleAttr(pStyle)}>${inline.isEmpty ? '&nbsp;' : inline}</p>');
      } else {
        sb.write(inline);
      }
    }
    if (n.children.isNotEmpty) {
      sb.write('\n');
      sb.write(blocks(n.children.toList()));
    }
    sb.write('</li>\n');
    return sb.toString();
  }

  String _styleAttr(String style) =>
      style.trim().isEmpty ? '' : ' style="${escapeHtmlAttr(style.trim())}"';

  String _blockStyle(Node n) {
    var style = (n.attributes[HelpNodes.style] as String?) ?? '';
    final align = n.attributes[HelpNodes.align] as String?;
    if (align != null) style = setCssDecl(style, 'text-align', align);
    final indent = n.attributes[HelpNodes.indent];
    if (indent is num && indent > 0) style = setCssDecl(style, 'padding-left', '${indent.round()}px');
    return style;
  }

  String _block(Node n) {
    switch (n.type) {
      case HelpNodes.image:
        return _wrapEmbed(n, _image(n));
      case HelpNodes.media:
        return _wrapEmbed(n, (n.attributes[HelpNodes.html] as String?) ?? '');
      case HelpNodes.heading:
        final level = ((n.attributes[HelpNodes.level] as num?)?.toInt() ?? 1).clamp(1, 6);
        return '<h$level${_styleAttr(_blockStyle(n))}>${_inline(n.delta ?? Delta())}</h$level>\n';
      default:
        final tag = (n.attributes[HelpNodes.tag] as String?) ?? 'p';
        final delta = n.delta ?? Delta();
        if (tag == '' && n.attributes[HelpNodes.align] == null && n.attributes[HelpNodes.indent] == null) {
          return _inline(delta);
        }
        final t = tag == '' ? 'p' : tag;
        if (t == 'pre') {
          return '<pre${_styleAttr(_blockStyle(n))}>${_inline(delta, pre: true)}</pre>\n';
        }
        final inline = _inline(delta);
        final empty = inline.isEmpty && n.attributes[HelpNodes.bareEmpty] != true ? '&nbsp;' : inline;
        return '<$t${_styleAttr(_blockStyle(n))}>$empty</$t>\n';
    }
  }

  String _wrapEmbed(Node n, String inner) {
    var style = (n.attributes[HelpNodes.wrapStyle] as String?) ?? '';
    final align = n.attributes[HelpNodes.align] as String?;
    style = setCssDecl(style, 'text-align', align);
    final wrapTag = n.attributes['tp_wrap_tag'] as String?;
    if (wrapTag == '' && style.trim().isEmpty) return inner;
    final tag = wrapTag == null || wrapTag.isEmpty ? 'p' : wrapTag;
    return '<$tag${_styleAttr(style)}>$inner</$tag>\n';
  }

  String _image(Node n) {
    final a = n.attributes;
    final parts = <String>[];
    final style = (a[HelpNodes.imgStyle] as String?) ?? '';
    if (style.trim().isNotEmpty) parts.add('style="${escapeHtmlAttr(style.trim())}"');
    parts.add('src="${escapeHtmlAttr(resolveSrc('${a[HelpNodes.src] ?? ''}'))}"');
    for (final k in [HelpNodes.alt, HelpNodes.title, HelpNodes.width, HelpNodes.height]) {
      final v = a[k];
      if (v == null) continue;
      parts.add('$k="${escapeHtmlAttr('$v')}"');
    }
    final img = '<img ${parts.join(' ')}>';
    final link = a[HelpNodes.link] as String?;
    if (link == null) return img;
    final m = Map<String, dynamic>.from(jsonDecode(link) as Map);
    final href = '${m.remove('href') ?? ''}';
    return '<a href="${escapeHtmlAttr(href)}"${_anchorAttrs(m)}>$img</a>';
  }

  String _anchorAttrs(Map<String, dynamic> m) =>
      m.entries.map((e) => ' ${e.key}="${escapeHtmlAttr('${e.value}')}"').join();

  String _inline(Delta delta, {bool pre = false}) {
    final ops = <TextInsert>[for (final op in delta) if (op is TextInsert) op];
    final sb = StringBuffer();
    var i = 0;
    while (i < ops.length) {
      final href = ops[i].attributes?['href'] as String?;
      if (href == null || href.isEmpty) {
        sb.write(_run(ops[i], pre: pre, atStart: i == 0, atEnd: i == ops.length - 1));
        i++;
        continue;
      }
      final anchor = ops[i].attributes?[HelpNodes.anchor] as String?;
      var j = i;
      final inner = StringBuffer();
      while (j < ops.length &&
          ops[j].attributes?['href'] == href &&
          ops[j].attributes?[HelpNodes.anchor] == anchor) {
        inner.write(_run(ops[j], pre: pre, atStart: j == 0, atEnd: j == ops.length - 1));
        j++;
      }
      final meta = anchor == null ? <String, dynamic>{} : Map<String, dynamic>.from(jsonDecode(anchor) as Map);
      sb.write('<a href="${escapeHtmlAttr(href)}"${_anchorAttrs(meta)}>$inner</a>');
      i = j;
    }
    return sb.toString();
  }

  String _text(String t, {required bool pre, required bool atStart, required bool atEnd}) {
    if (pre) return escapeHtmlText(t);
    final sb = StringBuffer();
    final chars = t.split('');
    for (var k = 0; k < chars.length; k++) {
      final ch = chars[k];
      if (ch == '\n') {
        sb.write('<br>');
        continue;
      }
      if (ch == ' ') {
        final prev = k == 0 ? (atStart ? '\n' : null) : chars[k - 1];
        final next = k == chars.length - 1 ? (atEnd ? '\n' : null) : chars[k + 1];
        if (prev == '\n' || prev == ' ' || prev == ' ' || next == '\n') {
          sb.write('&nbsp;');
          continue;
        }
        sb.write(' ');
        continue;
      }
      sb.write(escapeHtmlText(ch));
    }
    return sb.toString();
  }

  String _run(TextInsert op, {required bool pre, required bool atStart, required bool atEnd}) {
    final a = op.attributes ?? const <String, dynamic>{};
    var html = _text(op.text, pre: pre, atStart: atStart, atEnd: atEnd);
    final css = <String, String>{};
    final extra = parseCss(a[HelpNodes.extraCss] as String?);
    css.addAll(extra);
    if (a['underline'] == true) css['text-decoration'] = 'underline';
    final color = a['font_color'];
    if (color is String && color.isNotEmpty) css['color'] = color;
    final bg = a['bg_color'];
    if (bg is String && bg.isNotEmpty) css['background-color'] = bg;
    final size = a['font_size'];
    if (size is num) css['font-size'] = '${_fmtNum(size.toDouble())}px';
    final family = a['font_family'];
    if (family is String && family.isNotEmpty) css['font-family'] = family;
    if (css.isNotEmpty) html = '<span style="${escapeHtmlAttr(cssString(css))}">$html</span>';
    if (a['code'] == true) html = '<code>$html</code>';
    if (a['strikethrough'] == true) html = '<s>$html</s>';
    if (a['italic'] == true) html = '<em>$html</em>';
    if (a['bold'] == true) html = '<strong>$html</strong>';
    return html;
  }
}

List<String> helpHtmlSignature(String html) {
  final frag = hp.parseFragment(html);
  final sig = _Signature();
  sig.walk(frag.nodes, const _SigState());
  sig.flushWord();
  return sig.tokens;
}

class _SigState {
  const _SigState({
    this.list = '',
    this.block = '',
    this.heading = 0,
    this.pre = false,
    this.align = '',
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.code = false,
    this.color = '',
    this.bg = '',
    this.size = '',
    this.family = '',
    this.href = '',
    this.extra = '',
  });

  final String list;
  final String block;
  final int heading;
  final bool pre;
  final String align;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;
  final bool code;
  final String color;
  final String bg;
  final String size;
  final String family;
  final String href;
  final String extra;

  _SigState copy({
    String? list,
    String? block,
    int? heading,
    bool? pre,
    String? align,
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strike,
    bool? code,
    String? color,
    String? bg,
    String? size,
    String? family,
    String? href,
    String? extra,
  }) => _SigState(
    list: list ?? this.list,
    block: block ?? this.block,
    heading: heading ?? this.heading,
    pre: pre ?? this.pre,
    align: align ?? this.align,
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    underline: underline ?? this.underline,
    strike: strike ?? this.strike,
    code: code ?? this.code,
    color: color ?? this.color,
    bg: bg ?? this.bg,
    size: size ?? this.size,
    family: family ?? this.family,
    href: href ?? this.href,
    extra: extra ?? this.extra,
  );

  String get ctx => '$list\u0002$block\u0002$heading\u0002$pre\u0002$align';
  String get fmt =>
      '$bold$italic$underline$strike$code\u0002$color\u0002$bg\u0002$size\u0002$family\u0002$href\u0002$extra';
}

class _Signature {
  final tokens = <String>[];
  final _word = StringBuffer();
  String _wordKey = '';
  int _lists = 0;

  void flushWord() {
    if (_word.isEmpty) return;
    tokens.add('W\u0001$_wordKey\u0001$_word');
    _word.clear();
  }

  void _char(String ch, _SigState st) {
    if (RegExp(r'[\s ]').hasMatch(ch)) {
      flushWord();
      return;
    }
    final key = '${st.ctx}\u0003${st.fmt}';
    if (_word.isNotEmpty && key != _wordKey) flushWord();
    _wordKey = key;
    _word.write(ch);
  }

  String _norm(String v) => v.toLowerCase().replaceAll(RegExp(r'\s+'), '');

  String _px(String v) {
    final p = cssPxValue(v);
    if (p != null) return _fmtNum(p);
    final pt = RegExp(r'^\s*(\d+(?:\.\d+)?)\s*pt\s*$').firstMatch(v);
    if (pt != null) return _fmtNum((double.parse(pt.group(1)!) * 1.333).roundToDouble());
    return _norm(v);
  }

  _SigState _applyCss(Map<String, String> css, _SigState st, {required bool block}) {
    var s = st;
    final extra = parseCss(st.extra.replaceAll('\u0004', ';'));
    css.forEach((k, v) {
      final lv = v.toLowerCase().trim();
      switch (k) {
        case 'color':
          s = s.copy(color: _norm(v));
        case 'background-color':
        case 'background':
          s = s.copy(bg: _norm(v));
        case 'font-size':
          s = s.copy(size: _px(v));
        case 'font-family':
          s = s.copy(family: _norm(v));
        case 'font-weight':
          s = s.copy(bold: lv == 'bold' || lv == 'bolder' || (int.tryParse(lv) ?? 400) >= 600);
        case 'font-style':
          s = s.copy(italic: lv == 'italic' || lv == 'oblique');
        case 'text-decoration':
        case 'text-decoration-line':
          if (lv.contains('underline')) s = s.copy(underline: true);
          if (lv.contains('line-through')) s = s.copy(strike: true);
        case 'text-align':
          s = s.copy(align: lv);
        default:
          if (!block) extra[k] = _norm(v);
      }
    });
    if (!block) {
      final keys = extra.keys.toList()..sort();
      s = s.copy(extra: keys.map((k) => '$k:${extra[k]}').join('\u0004'));
    }
    return s;
  }

  String _blockDecls(Map<String, String> css) {
    final keep = <String>[];
    final keys = css.keys.toList()..sort();
    for (final k in keys) {
      if (_supportedStyleForInline.contains(k) || k == 'text-align') continue;
      keep.add('$k:${k == 'padding-left' ? _px(css[k]!) : _norm(css[k]!)}');
    }
    return keep.join(',');
  }

  void walk(List<dom.Node> nodes, _SigState st) {
    for (final n in nodes) {
      if (n is dom.Text) {
        final data = n.data;
        for (final ch in data.split('')) {
          _char(ch, st);
        }
        continue;
      }
      if (n is! dom.Element) continue;
      final tag = n.localName ?? '';
      final css = parseCss(n.attributes['style']);
      switch (tag) {
        case 'br':
          flushWord();
          continue;
        case 'img':
          flushWord();
          final a = n.attributes;
          final sc = parseCss(a['style']);
          tokens.add([
            'I',
            st.ctx,
            st.href,
            a['src'] ?? '',
            a['alt'] ?? '',
            a['width'] ?? '',
            a['height'] ?? '',
            _px(sc['width'] ?? ''),
            _px(sc['height'] ?? ''),
          ].join('\u0001'));
          continue;
        case 'video':
        case 'iframe':
          flushWord();
          final srcs = <String>[n.attributes['src'] ?? ''];
          for (final c in n.nodes) {
            if (c is dom.Element && c.localName == 'source') srcs.add(c.attributes['src'] ?? '');
          }
          final keys = n.attributes.keys.map((k) => '$k').toList()..sort();
          tokens.add([
            'M',
            st.ctx,
            tag,
            srcs.join(','),
            keys.map((k) => '$k=${n.attributes[k]}').join(','),
          ].join('\u0001'));
          continue;
      }
      var s = st;
      final isBlock = const {
        'p', 'div', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'pre', 'li', 'ul', 'ol', 'blockquote',
        'table', 'tr', 'td', 'th', 'tbody', 'thead', 'tfoot', 'caption',
      }.contains(tag);
      switch (tag) {
        case 'strong':
        case 'b':
        case 'th':
          s = s.copy(bold: true);
        case 'em':
        case 'i':
          s = s.copy(italic: true);
        case 'u':
          s = s.copy(underline: true);
        case 's':
        case 'strike':
        case 'del':
          s = s.copy(strike: true);
        case 'code':
          s = s.copy(code: true);
        case 'pre':
          s = s.copy(pre: true);
        case 'a':
          final meta = n.attributes.keys.map((k) => '$k').where((k) => k != 'style').toList()..sort();
          s = s.copy(href: meta.map((k) => '$k=${n.attributes[k]}').join(','));
        case 'font':
          if ((n.attributes['color'] ?? '').isNotEmpty) s = s.copy(color: _norm(n.attributes['color']!));
          if ((n.attributes['face'] ?? '').isNotEmpty) s = s.copy(family: _norm(n.attributes['face']!));
          const map = {1: '10', 2: '13', 3: '16', 4: '18', 5: '24', 6: '32', 7: '48'};
          final sz = map[int.tryParse(n.attributes['size'] ?? '')];
          if (sz != null) s = s.copy(size: sz);
        case 'ul':
        case 'ol':
          _lists++;
          s = s.copy(list: '${s.list}>$tag#$_lists${_blockDecls(css)}');
        case 'li':
          var idx = 0;
          for (final sib in n.parent?.nodes ?? const <dom.Node>[]) {
            if (sib is dom.Element && sib.localName == 'li') idx++;
            if (identical(sib, n)) break;
          }
          s = s.copy(list: '${s.list}.$idx');
        case 'h1':
        case 'h2':
        case 'h3':
        case 'h4':
        case 'h5':
        case 'h6':
          s = s.copy(heading: int.parse(tag.substring(1)));
      }
      if (tag == 'p' || tag == 'div' || tag == 'pre' || tag.startsWith('h') && tag.length == 2) {
        final d = _blockDecls(css);
        if (d.isNotEmpty) s = s.copy(block: '${s.block}/$d');
      }
      if (tag == 'li') {
        final d = _blockDecls(css);
        if (d.isNotEmpty) s = s.copy(block: '${s.block}/$d');
      }
      if (tag != 'ul' && tag != 'ol') s = _applyCss(css, s, block: isBlock);
      if (isBlock) flushWord();
      walk(n.nodes, s);
      if (isBlock) flushWord();
    }
  }
}
