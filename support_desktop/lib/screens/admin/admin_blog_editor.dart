import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const List<String> kBlogFontSizes = [
  '10px',
  '11px',
  '12px',
  '14px',
  '16px',
  '18px',
  '20px',
  '21px',
  '24px',
  '30px',
  '36px',
  '48px',
  '60px',
  '72px',
];

const List<Color> kBlogColors = [
  Color(0xFF000000),
  Color(0xFF434343),
  Color(0xFF666666),
  Color(0xFFB91C1C),
  Color(0xFFE03E2D),
  Color(0xFFFF7D00),
  Color(0xFFF1C40F),
  Color(0xFF2DC26B),
  Color(0xFF169179),
  Color(0xFF3598DB),
  Color(0xFF236FA1),
  Color(0xFF843FA1),
  Color(0xFFFFFFFF),
];

String blogColorHex(Color c) {
  String h(double v) =>
      (v * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return '#${h(c.r)}${h(c.g)}${h(c.b)}'.toUpperCase();
}

bool blogHasMarkup(String s) =>
    RegExp(r'<\s*[a-zA-Z][^>]*>').hasMatch(s) ||
    RegExp(r'&[a-zA-Z#0-9]+;').hasMatch(s);

String blogEscape(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

String blogEditorHtml(String source) {
  final s = source.trim();
  if (s.isEmpty || blogHasMarkup(s)) return s;
  return s
      .split(RegExp(r'\n\s*\n'))
      .map((b) => b.trim())
      .where((b) => b.isNotEmpty)
      .map(
        (b) =>
            '<p style="font-size: 16px;">${blogEscape(b).replaceAll('\n', '<br>')}</p>',
      )
      .join('\n');
}

class BlogHtmlEditor extends StatefulWidget {
  const BlogHtmlEditor({
    super.key,
    required this.controller,
    this.onChanged,
    this.minHeight = 320,
  });
  final TextEditingController controller;
  final VoidCallback? onChanged;
  final double minHeight;

  @override
  State<BlogHtmlEditor> createState() => _BlogHtmlEditorState();
}

class _BlogHtmlEditorState extends State<BlogHtmlEditor> {
  final _focus = FocusNode();
  bool _preview = false;

  TextEditingController get _c => widget.controller;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _changed() {
    widget.onChanged?.call();
    setState(() {});
  }

  TextSelection get _sel {
    final s = _c.selection;
    if (!s.isValid) {
      return TextSelection.collapsed(offset: _c.text.length);
    }
    return s;
  }

  void _replace(int start, int end, String text, {int? caret, int? selEnd}) {
    final t = _c.text;
    _c.value = TextEditingValue(
      text: t.replaceRange(start, end, text),
      selection: selEnd != null
          ? TextSelection(baseOffset: caret ?? start, extentOffset: selEnd)
          : TextSelection.collapsed(offset: caret ?? start + text.length),
    );
    _focus.requestFocus();
    _changed();
  }

  void _wrap(String open, String close, {String placeholder = 'text'}) {
    final s = _sel;
    final inner = s.isCollapsed
        ? placeholder
        : _c.text.substring(s.start, s.end);
    final start = s.start;
    _replace(
      s.start,
      s.end,
      '$open$inner$close',
      caret: start + open.length,
      selEnd: start + open.length + inner.length,
    );
  }

  (int, int) _lineRange() {
    final s = _sel;
    final t = _c.text;
    var a = s.start;
    while (a > 0 && t[a - 1] != '\n') {
      a--;
    }
    var b = s.end;
    while (b < t.length && t[b] != '\n') {
      b++;
    }
    return (a, b);
  }

  String _stripBlock(String line) => line
      .replaceAll(
        RegExp(
          r'</?(p|h[1-6]|blockquote|pre|div)(\s[^>]*)?>',
          caseSensitive: false,
        ),
        '',
      )
      .trim();

  void _block(String tag, {String style = ''}) {
    final (a, b) = _lineRange();
    final lines = _c.text
        .substring(a, b)
        .split('\n')
        .map(_stripBlock)
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) lines.add('text');
    final attr = style.isEmpty ? '' : ' style="$style"';
    final out = lines.map((l) => '<$tag$attr>$l</$tag>').join('\n');
    _replace(a, b, out);
  }

  void _align(String align) {
    final (a, b) = _lineRange();
    final lines = _c.text.substring(a, b).split('\n');
    final out = <String>[];
    for (final raw in lines) {
      if (raw.trim().isEmpty) continue;
      final m = RegExp(
        r'^\s*<(p|h[1-6]|div|li)(\s[^>]*)?>(.*)</\1>\s*$',
        caseSensitive: false,
        dotAll: true,
      ).firstMatch(raw);
      if (m != null) {
        final tag = m.group(1)!;
        var attrs = m.group(2) ?? '';
        final body = m.group(3) ?? '';
        final styleM = RegExp(r'style="([^"]*)"').firstMatch(attrs);
        var style = styleM?.group(1) ?? '';
        style = style
            .replaceAll(RegExp(r'text-align:\s*[a-z]+;?\s*'), '')
            .trim();
        if (align != 'left') {
          style = '${style.isEmpty ? '' : '$style '}text-align: $align;';
        }
        attrs = attrs.replaceAll(RegExp(r'\s*style="[^"]*"'), '');
        final st = style.isEmpty ? '' : ' style="$style"';
        out.add('<$tag$attrs$st>$body</$tag>');
      } else {
        final st = align == 'left'
            ? ' style="font-size: 16px;"'
            : ' style="text-align: $align; font-size: 16px;"';
        out.add('<p$st>${raw.trim()}</p>');
      }
    }
    if (out.isEmpty) return;
    _replace(a, b, out.join('\n'));
  }

  void _list(String tag) {
    final (a, b) = _lineRange();
    final lines = _c.text
        .substring(a, b)
        .split('\n')
        .map((l) => _stripBlock(l.replaceAll(RegExp(r'</?li[^>]*>'), '')))
        .where((l) => l.isNotEmpty && !RegExp(r'^</?(ul|ol)').hasMatch(l))
        .toList();
    if (lines.isEmpty) lines.add('item');
    final out =
        '<$tag>\n${lines.map((l) => '<li>$l</li>').join('\n')}\n</$tag>';
    _replace(a, b, out);
  }

  void _insert(String snippet) {
    final s = _sel;
    _replace(s.start, s.end, snippet);
  }

  void _removeFormat() {
    final s = _sel;
    if (s.isCollapsed) return;
    final inner = _c.text
        .substring(s.start, s.end)
        .replaceAll(RegExp(r'<[^>]*>'), '');
    _replace(s.start, s.end, inner);
  }

  Future<void> _link() async {
    final s = _sel;
    final url = TextEditingController(text: 'https://');
    final text = TextEditingController(
      text: s.isCollapsed ? '' : _c.text.substring(s.start, s.end),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Insert/Edit Link'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: url,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'URL'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: text,
                decoration: const InputDecoration(labelText: 'Text to display'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final u = url.text.trim();
    if (ok != true || u.isEmpty || u == 'https://') return;
    final label = text.text.trim().isEmpty ? u : text.text.trim();
    _replace(s.start, s.end, '<a href="$u">$label</a>');
  }

  Future<void> _pickColor(bool background) async {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    final c = await showMenu<Color>(
      context: context,
      position: RelativeRect.fromLTRB(origin.dx + 360, origin.dy + 40, 0, 0),
      items: [
        PopupMenuItem<Color>(
          enabled: false,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final k in kBlogColors)
                InkWell(
                  onTap: () => Navigator.pop(context, k),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: k,
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
    if (c == null) return;
    final prop = background ? 'background-color' : 'color';
    _wrap('<span style="$prop: ${blogColorHex(c)};">', '</span>');
  }

  Widget _btn(IconData icon, String tip, VoidCallback onTap) => IconButton(
    tooltip: tip,
    icon: Icon(icon, size: 18),
    visualDensity: VisualDensity.compact,
    splashRadius: 16,
    onPressed: _preview ? null : onTap,
  );

  Widget _sep() => Container(
    width: 1,
    height: 20,
    margin: const EdgeInsets.symmetric(horizontal: 4),
    color: const Color(0xFFE2E2DE),
  );

  @override
  Widget build(BuildContext context) {
    final border = const Color(0xFFE2E2DE);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: border)),
              color: const Color(0xFFFAFAF9),
            ),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                PopupMenuButton<String>(
                  tooltip: 'Blocks',
                  enabled: !_preview,
                  onSelected: (v) => v == 'p'
                      ? _block('p', style: 'font-size: 16px;')
                      : _block(v),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'p', child: Text('Paragraph')),
                    PopupMenuItem(value: 'h1', child: Text('Heading 1')),
                    PopupMenuItem(value: 'h2', child: Text('Heading 2')),
                    PopupMenuItem(value: 'h3', child: Text('Heading 3')),
                    PopupMenuItem(value: 'h4', child: Text('Heading 4')),
                    PopupMenuItem(
                      value: 'blockquote',
                      child: Text('Blockquote'),
                    ),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Paragraph', style: TextStyle(fontSize: 13)),
                        Icon(Icons.arrow_drop_down, size: 18),
                      ],
                    ),
                  ),
                ),
                _sep(),
                _btn(
                  Icons.format_bold,
                  'Bold',
                  () => _wrap('<strong>', '</strong>'),
                ),
                _btn(
                  Icons.format_italic,
                  'Italic',
                  () => _wrap('<em>', '</em>'),
                ),
                _btn(
                  Icons.format_underline,
                  'Underline',
                  () => _wrap(
                    '<span style="text-decoration: underline;">',
                    '</span>',
                  ),
                ),
                _btn(
                  Icons.format_strikethrough,
                  'Strikethrough',
                  () => _wrap('<s>', '</s>'),
                ),
                _sep(),
                _btn(
                  Icons.format_align_left,
                  'Align left',
                  () => _align('left'),
                ),
                _btn(
                  Icons.format_align_center,
                  'Align center',
                  () => _align('center'),
                ),
                _btn(
                  Icons.format_align_right,
                  'Align right',
                  () => _align('right'),
                ),
                _btn(
                  Icons.format_align_justify,
                  'Justify',
                  () => _align('justify'),
                ),
                _sep(),
                _btn(
                  Icons.format_list_bulleted,
                  'Bullet list',
                  () => _list('ul'),
                ),
                _btn(
                  Icons.format_list_numbered,
                  'Numbered list',
                  () => _list('ol'),
                ),
                _btn(
                  Icons.format_indent_increase,
                  'Increase indent',
                  () => _wrap('<p style="padding-left: 40px;">', '</p>'),
                ),
                _sep(),
                _btn(Icons.format_clear, 'Clear formatting', _removeFormat),
                _btn(
                  Icons.format_color_text,
                  'Text color',
                  () => _pickColor(false),
                ),
                _btn(
                  Icons.format_color_fill,
                  'Background color',
                  () => _pickColor(true),
                ),
                _btn(
                  Icons.horizontal_rule,
                  'Horizontal line',
                  () => _insert('\n<hr>\n'),
                ),
                _btn(Icons.link, 'Link', _link),
                PopupMenuButton<String>(
                  tooltip: 'Font Size',
                  enabled: !_preview,
                  onSelected: (v) =>
                      _wrap('<span style="font-size: $v;">', '</span>'),
                  itemBuilder: (_) => [
                    for (final s in kBlogFontSizes)
                      PopupMenuItem(value: s, child: Text(s)),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('16px', style: TextStyle(fontSize: 13)),
                        Icon(Icons.arrow_drop_down, size: 18),
                      ],
                    ),
                  ),
                ),
                _sep(),
                TextButton.icon(
                  onPressed: () => setState(() => _preview = !_preview),
                  icon: Icon(
                    _preview ? Icons.code : Icons.visibility_outlined,
                    size: 16,
                  ),
                  label: Text(_preview ? 'Edit' : 'Preview'),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: widget.minHeight),
            child: _preview
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: BlogHtmlView(html: blogEditorHtml(_c.text)),
                  )
                : Shortcuts(
                    shortcuts: const {
                      SingleActivator(LogicalKeyboardKey.tab): _EmspIntent(),
                    },
                    child: Actions(
                      actions: {
                        _EmspIntent: CallbackAction<_EmspIntent>(
                          onInvoke: (_) {
                            _insert('&emsp;');
                            return null;
                          },
                        ),
                      },
                      child: TextField(
                        controller: _c,
                        focusNode: _focus,
                        minLines: 14,
                        maxLines: 24,
                        onChanged: (_) => _changed(),
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.6,
                          color: Color(0xFF2D3748),
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          contentPadding: EdgeInsets.all(16),
                          hintText:
                              'Write the article. Blank lines separate paragraphs; use the toolbar for formatting.',
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _EmspIntent extends Intent {
  const _EmspIntent();
}

class _Node {
  _Node(this.tag, [this.attrs = const {}]);
  final String tag;
  final Map<String, String> attrs;
  final List<Object> children = [];
}

const _voidTags = {'br', 'hr', 'img', 'input', 'meta', 'link', 'wbr', 'col'};
const _blockTags = {
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
  'li',
  'blockquote',
  'pre',
  'hr',
  'table',
  'tbody',
  'thead',
  'tr',
  'td',
  'th',
  'figure',
  'section',
  'article',
};

String _decodeEntities(String s) => s
    .replaceAllMapped(
      RegExp(r'&#(\d+);'),
      (m) => String.fromCharCode(int.tryParse(m.group(1)!) ?? 32),
    )
    .replaceAllMapped(
      RegExp(r'&#x([0-9a-fA-F]+);'),
      (m) => String.fromCharCode(int.tryParse(m.group(1)!, radix: 16) ?? 32),
    )
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&emsp;', ' ')
    .replaceAll('&ensp;', ' ')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&apos;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&mdash;', '—')
    .replaceAll('&ndash;', '–')
    .replaceAll('&hellip;', '…')
    .replaceAll('&rsquo;', '’')
    .replaceAll('&lsquo;', '‘')
    .replaceAll('&rdquo;', '”')
    .replaceAll('&ldquo;', '“')
    .replaceAll('&amp;', '&');

_Node _parse(String html) {
  final root = _Node('root');
  final stack = <_Node>[root];
  final re = RegExp(r'<!--.*?-->|<(/?)([a-zA-Z0-9]+)([^>]*)>', dotAll: true);
  var pos = 0;
  for (final m in re.allMatches(html)) {
    if (m.start > pos) {
      stack.last.children.add(html.substring(pos, m.start));
    }
    pos = m.end;
    final name = m.group(2);
    if (name == null) continue;
    final tag = name.toLowerCase();
    if (m.group(1) == '/') {
      for (var i = stack.length - 1; i > 0; i--) {
        if (stack[i].tag == tag) {
          stack.removeRange(i, stack.length);
          break;
        }
      }
      continue;
    }
    final attrs = <String, String>{};
    for (final a in RegExp(
      r'''([a-zA-Z-]+)\s*=\s*("([^"]*)"|'([^']*)'|([^\s>]+))''',
    ).allMatches(m.group(3) ?? '')) {
      attrs[a.group(1)!.toLowerCase()] =
          a.group(3) ?? a.group(4) ?? a.group(5) ?? '';
    }
    final node = _Node(tag, attrs);
    stack.last.children.add(node);
    final selfClosing = (m.group(3) ?? '').trim().endsWith('/');
    if (!_voidTags.contains(tag) && !selfClosing) stack.add(node);
  }
  if (pos < html.length) stack.last.children.add(html.substring(pos));
  return root;
}

Map<String, String> _styles(String? s) {
  final out = <String, String>{};
  if (s == null) return out;
  for (final part in s.split(';')) {
    final i = part.indexOf(':');
    if (i <= 0) continue;
    out[part.substring(0, i).trim().toLowerCase()] = part
        .substring(i + 1)
        .trim();
  }
  return out;
}

Color? _cssColor(String? v) {
  if (v == null) return null;
  final s = v.trim().toLowerCase();
  final hex = RegExp(r'^#([0-9a-f]{3,8})$').firstMatch(s);
  if (hex != null) {
    var h = hex.group(1)!;
    if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
    if (h.length == 6) h = 'ff$h';
    if (h.length == 8 && hex.group(1)!.length == 8) {
      h = h.substring(6) + h.substring(0, 6);
    }
    return Color(int.parse(h, radix: 16));
  }
  final rgb = RegExp(r'^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)').firstMatch(s);
  if (rgb != null) {
    return Color.fromARGB(
      255,
      int.parse(rgb.group(1)!),
      int.parse(rgb.group(2)!),
      int.parse(rgb.group(3)!),
    );
  }
  const named = {
    'black': Color(0xFF000000),
    'white': Color(0xFFFFFFFF),
    'red': Color(0xFFFF0000),
    'blue': Color(0xFF0000FF),
    'green': Color(0xFF008000),
    'orange': Color(0xFFFFA500),
    'gray': Color(0xFF808080),
    'grey': Color(0xFF808080),
  };
  return named[s];
}

double? _cssSize(String? v, double base) {
  if (v == null) return null;
  final m = RegExp(r'([\d.]+)\s*(px|pt|em|rem)?').firstMatch(v);
  if (m == null) return null;
  final n = double.tryParse(m.group(1)!) ?? base;
  switch (m.group(2)) {
    case 'pt':
      return n * 1.333;
    case 'em':
    case 'rem':
      return n * 16;
    default:
      return n;
  }
}

class BlogHtmlView extends StatelessWidget {
  const BlogHtmlView({super.key, required this.html, this.baseStyle});
  final String html;
  final TextStyle? baseStyle;

  @override
  Widget build(BuildContext context) {
    final base =
        baseStyle ??
        const TextStyle(fontSize: 16, height: 1.8, color: Color(0xFF2D3748));
    final root = _parse(html);
    final blocks = <Widget>[];
    _Renderer(context, base, blocks).block(root, base, 0, null);
    if (blocks.isEmpty) {
      return Text(
        'Nothing to preview yet.',
        style: base.copyWith(color: const Color(0xFF888888)),
      );
    }
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: blocks,
      ),
    );
  }
}

class _Renderer {
  _Renderer(this.context, this.base, this.out);
  final BuildContext context;
  final TextStyle base;
  final List<Widget> out;

  List<InlineSpan> _pending = [];
  TextAlign _pendingAlign = TextAlign.start;
  double _pendingIndent = 0;

  void _flush() {
    if (_pending.isEmpty) return;
    final spans = _pending;
    _pending = [];
    final hasText = spans.any(
      (s) => s is! TextSpan || (s.toPlainText().trim().isNotEmpty),
    );
    if (!hasText) return;
    out.add(
      Padding(
        padding: EdgeInsets.only(left: _pendingIndent, bottom: 12),
        child: Text.rich(TextSpan(children: spans), textAlign: _pendingAlign),
      ),
    );
  }

  TextAlign _align(Map<String, String> st, TextAlign fallback) {
    switch (st['text-align']) {
      case 'center':
        return TextAlign.center;
      case 'right':
        return TextAlign.right;
      case 'justify':
        return TextAlign.justify;
      case 'left':
        return TextAlign.left;
    }
    return fallback;
  }

  TextStyle _inlineStyle(_Node n, TextStyle s) {
    final st = _styles(n.attrs['style']);
    var r = s;
    switch (n.tag) {
      case 'strong':
      case 'b':
        r = r.copyWith(fontWeight: FontWeight.w700);
      case 'em':
      case 'i':
        r = r.copyWith(fontStyle: FontStyle.italic);
      case 'u':
        r = r.copyWith(decoration: TextDecoration.underline);
      case 's':
      case 'strike':
      case 'del':
        r = r.copyWith(decoration: TextDecoration.lineThrough);
      case 'a':
        r = r.copyWith(
          color: const Color(0xFF2563EB),
          decoration: TextDecoration.underline,
        );
      case 'code':
        r = r.copyWith(fontFamily: 'monospace');
    }
    final color = _cssColor(st['color']);
    if (color != null) r = r.copyWith(color: color);
    final bg = _cssColor(st['background-color'] ?? st['background']);
    if (bg != null) r = r.copyWith(backgroundColor: bg);
    final size = _cssSize(st['font-size'], r.fontSize ?? 16);
    if (size != null) r = r.copyWith(fontSize: size);
    final deco = st['text-decoration'] ?? st['text-decoration-line'];
    if (deco != null) {
      if (deco.contains('underline')) {
        r = r.copyWith(decoration: TextDecoration.underline);
      } else if (deco.contains('line-through')) {
        r = r.copyWith(decoration: TextDecoration.lineThrough);
      }
    }
    final fw = st['font-weight'];
    if (fw != null && (fw == 'bold' || (int.tryParse(fw) ?? 400) >= 600)) {
      r = r.copyWith(fontWeight: FontWeight.w700);
    }
    if (st['font-style'] == 'italic') {
      r = r.copyWith(fontStyle: FontStyle.italic);
    }
    return r;
  }

  void _inline(Object child, TextStyle s) {
    if (child is String) {
      final text = _decodeEntities(child.replaceAll(RegExp(r'\s+'), ' '));
      if (text.isEmpty) return;
      if (_pending.isEmpty && text.trim().isEmpty) return;
      _pending.add(TextSpan(text: text, style: s));
      return;
    }
    final n = child as _Node;
    if (n.tag == 'br') {
      _pending.add(TextSpan(text: '\n', style: s));
      return;
    }
    if (n.tag == 'img') {
      _pending.add(TextSpan(text: '[image]', style: s));
      return;
    }
    final ns = _inlineStyle(n, s);
    for (final c in n.children) {
      if (c is _Node && _blockTags.contains(c.tag)) {
        block(c, ns, _pendingIndent, null);
      } else {
        _inline(c, ns);
      }
    }
  }

  void block(_Node n, TextStyle s, double indent, String? bullet) {
    for (var i = 0; i < n.children.length; i++) {
      final c = n.children[i];
      if (c is _Node && _blockTags.contains(c.tag)) {
        _flush();
        _renderBlock(c, s, indent);
      } else {
        if (_pending.isEmpty) {
          _pendingIndent = indent;
          _pendingAlign = TextAlign.start;
        }
        _inline(c, s);
      }
    }
    _flush();
  }

  void _renderBlock(_Node n, TextStyle s, double indent) {
    final st = _styles(n.attrs['style']);
    var ns = _inlineStyle(n, s);
    final pad = _cssSize(st['padding-left'] ?? st['margin-left'], 0) ?? 0;
    switch (n.tag) {
      case 'hr':
        out.add(const Divider(height: 28, color: Color(0xFFCBD5E1)));
        return;
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        const sizes = {
          'h1': 32.0,
          'h2': 26.0,
          'h3': 22.0,
          'h4': 19.0,
          'h5': 17.0,
          'h6': 15.0,
        };
        ns = ns.copyWith(
          fontSize: _cssSize(st['font-size'], 16) ?? sizes[n.tag],
          fontWeight: FontWeight.w700,
          color: _cssColor(st['color']) ?? const Color(0xFF1A1A1A),
          height: 1.3,
        );
      case 'ul':
      case 'ol':
        var k = 0;
        for (final c in n.children) {
          if (c is _Node && c.tag == 'li') {
            k++;
            final marker = n.tag == 'ol' ? '$k. ' : '• ';
            _pendingIndent = indent + 20 + pad;
            _pendingAlign = _align(_styles(c.attrs['style']), TextAlign.start);
            _pending.add(TextSpan(text: marker, style: ns));
            for (final cc in c.children) {
              if (cc is _Node && (cc.tag == 'ul' || cc.tag == 'ol')) {
                _flush();
                _renderBlock(cc, ns, indent + 20);
              } else if (cc is _Node && _blockTags.contains(cc.tag)) {
                for (final ccc in cc.children) {
                  _inline(ccc, _inlineStyle(cc, ns));
                }
              } else {
                _inline(cc, ns);
              }
            }
            _flush();
          }
        }
        return;
      case 'blockquote':
        final inner = <Widget>[];
        _Renderer(context, base, inner).block(n, ns, 0, null);
        out.add(
          Container(
            margin: EdgeInsets.only(left: indent, bottom: 12),
            padding: const EdgeInsets.only(left: 14),
            decoration: const BoxDecoration(
              border: Border(
                left: BorderSide(color: Color(0xFFFF7D00), width: 3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: inner,
            ),
          ),
        );
        return;
      case 'tr':
        final cells = <Widget>[];
        for (final c in n.children) {
          if (c is _Node && (c.tag == 'td' || c.tag == 'th')) {
            final inner = <Widget>[];
            _Renderer(context, base, inner).block(
              c,
              c.tag == 'th' ? ns.copyWith(fontWeight: FontWeight.w700) : ns,
              0,
              null,
            );
            cells.add(
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFE2E2DE)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: inner,
                  ),
                ),
              ),
            );
          }
        }
        out.add(
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: cells),
        );
        return;
    }
    _flush();
    _pendingIndent = indent + pad;
    _pendingAlign = _align(st, TextAlign.start);
    final align = _pendingAlign;
    final ind = _pendingIndent;
    for (final c in n.children) {
      if (c is _Node && _blockTags.contains(c.tag)) {
        _flush();
        _renderBlock(c, ns, indent + pad);
        _pendingAlign = align;
        _pendingIndent = ind;
      } else {
        _inline(c, ns);
      }
    }
    _flush();
  }
}
