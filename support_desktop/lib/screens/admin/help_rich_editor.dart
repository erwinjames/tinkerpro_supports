import 'dart:convert';
import 'dart:math' as math;

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../widgets/tp_loader.dart';
import 'help_html_codec.dart';

Color? helpCssColor(Object? v) {
  if (v is! String) return null;
  final s = v.trim().toLowerCase();
  if (s.startsWith('#')) {
    var h = s.substring(1);
    if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
    if (h.length == 6) {
      final n = int.tryParse(h, radix: 16);
      return n == null ? null : Color(0xFF000000 | n);
    }
    return null;
  }
  final rgb = RegExp(r'rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)(?:\s*,\s*([\d.]+))?').firstMatch(s);
  if (rgb != null) {
    final a = double.tryParse(rgb.group(4) ?? '1') ?? 1;
    return Color.fromARGB(
      (a * 255).round().clamp(0, 255),
      int.parse(rgb.group(1)!).clamp(0, 255),
      int.parse(rgb.group(2)!).clamp(0, 255),
      int.parse(rgb.group(3)!).clamp(0, 255),
    );
  }
  const named = {
    'black': Color(0xFF000000), 'white': Color(0xFFFFFFFF), 'red': Color(0xFFFF0000),
    'green': Color(0xFF008000), 'blue': Color(0xFF0000FF), 'orange': Color(0xFFFFA500),
    'gray': Color(0xFF808080), 'grey': Color(0xFF808080), 'yellow': Color(0xFFFFFF00),
    'purple': Color(0xFF800080), 'navy': Color(0xFF000080), 'teal': Color(0xFF008080),
    'maroon': Color(0xFF800000), 'silver': Color(0xFFC0C0C0),
  };
  return named[s];
}

const kHelpLinkColor = Color(0xFF0066CC);
const kHelpTextColor = Color(0xFF1A1A1A);

const _headingSizes = [32.0, 24.0, 18.72, 16.0, 13.28, 10.72];

double helpHeadingSize(int level) => _headingSizes[(level - 1).clamp(0, 5)];

TextStyle _cssTextStyle(Map<String, String> css) {
  var st = const TextStyle();
  final size = cssPxValue(css['font-size']);
  if (size != null && size > 4 && size < 120) st = st.copyWith(fontSize: size);
  final color = helpCssColor(css['color']);
  if (color != null) st = st.copyWith(color: color);
  final bg = helpCssColor(css['background-color']);
  if (bg != null) st = st.copyWith(backgroundColor: bg);
  final fam = css['font-family'];
  if (fam != null && fam.isNotEmpty) {
    final list = fam.split(',').map((f) => f.trim().replaceAll(RegExp(r'''^["']|["']$'''), '')).toList();
    st = st.copyWith(fontFamily: list.first, fontFamilyFallback: list.skip(1).toList());
  }
  final w = (css['font-weight'] ?? '').toLowerCase();
  if (w == 'bold' || (int.tryParse(w) ?? 0) >= 600) st = st.copyWith(fontWeight: FontWeight.w700);
  return st;
}

TextStyle helpBlockTextStyle(Node node) {
  final css = {
    ...parseCss(node.attributes[HelpNodes.style] as String?),
    ...parseCss(node.attributes[HelpNodes.pStyle] as String?),
  };
  var st = _cssTextStyle(css);
  if (node.attributes[HelpNodes.tag] == 'pre') {
    st = st.copyWith(fontFamily: 'monospace', fontFamilyFallback: const ['JetBrainsMono']);
  }
  return st;
}

TextSpan helpTextSpanDecorator(
  BuildContext context,
  Node node,
  int index,
  TextInsert text,
  TextSpan before,
  TextSpan after,
) {
  final a = text.attributes;
  var style = after.style ?? before.style ?? const TextStyle();
  if (a != null) {
    if (a['href'] is String) {
      style = style.copyWith(color: kHelpLinkColor, decoration: TextDecoration.underline);
    }
    final extra = _cssTextStyle(parseCss(a[HelpNodes.extraCss] as String?));
    style = style.merge(extra);
    final color = helpCssColor(a['font_color']);
    if (color != null) style = style.copyWith(color: color);
    final bg = helpCssColor(a['bg_color']);
    if (bg != null) style = style.copyWith(backgroundColor: bg);
    final size = a['font_size'];
    if (size is num && size > 4 && size < 120) style = style.copyWith(fontSize: size.toDouble());
    final fam = a['font_family'];
    if (fam is String && fam.isNotEmpty) {
      final list = fam.split(',').map((f) => f.trim().replaceAll(RegExp(r'''^["']|["']$'''), '')).toList();
      style = style.copyWith(fontFamily: list.first, fontFamilyFallback: list.skip(1).toList());
    }
    final deco = <TextDecoration>[
      if (a['underline'] == true || a['href'] is String) TextDecoration.underline,
      if (a['strikethrough'] == true) TextDecoration.lineThrough,
    ];
    if (deco.isNotEmpty) style = style.copyWith(decoration: TextDecoration.combine(deco));
  }
  return TextSpan(
    text: text.text,
    style: style,
    mouseCursor: a?['href'] is String ? SystemMouseCursors.text : null,
  );
}

EditorStyle helpEditorStyle() => EditorStyle.desktop(
  padding: const EdgeInsets.symmetric(horizontal: 20),
  cursorColor: const Color(0xFF222F3E),
  selectionColor: const Color(0x552F80ED),
  textStyleConfiguration: const TextStyleConfiguration(
    text: TextStyle(fontSize: 16, color: kHelpTextColor),
    href: TextStyle(color: kHelpLinkColor, decoration: TextDecoration.underline),
    code: TextStyle(fontFamily: 'monospace', backgroundColor: Color(0xFFF1F3F5)),
    lineHeight: 1.6,
  ),
  textSpanDecorator: helpTextSpanDecorator,
);

class HelpRichScope {
  HelpRichScope({
    required this.imageProvider,
    required this.onEditImage,
  });

  final ImageProvider? Function(String src) imageProvider;
  final void Function(EditorState editorState, Node node) onEditImage;
}

EdgeInsets _padding(Node node) {
  switch (node.type) {
    case HelpNodes.image:
    case HelpNodes.media:
      return const EdgeInsets.symmetric(vertical: 6);
    case HelpNodes.bulleted:
    case HelpNodes.numbered:
      return const EdgeInsets.symmetric(vertical: 1);
    default:
      final indent = node.attributes[HelpNodes.indent];
      final left = indent is num ? indent.toDouble() : 0.0;
      final bare = node.attributes[HelpNodes.tag] == '';
      return EdgeInsets.only(left: left, top: 2, bottom: bare ? 2 : 8);
  }
}

BlockComponentConfiguration _config() => BlockComponentConfiguration(
  padding: _padding,
  placeholderText: (_) => ' ',
  textStyle: (node, {textSpan}) => helpBlockTextStyle(node),
  textAlign: (node) => node.attributes[HelpNodes.align] == 'justify' ? TextAlign.justify : TextAlign.start,
  indentPadding: (node, dir) => dir == TextDirection.rtl
      ? const EdgeInsets.only(right: 28)
      : const EdgeInsets.only(left: 28),
);

Map<String, BlockComponentBuilder> helpBlockBuilders(HelpRichScope scope) {
  final cfg = _config();
  return {
    PageBlockKeys.type: PageBlockComponentBuilder(),
    ParagraphBlockKeys.type: ParagraphBlockComponentBuilder(
      configuration: cfg.copyWith(placeholderText: (_) => 'Write the document here…'),
      showPlaceholder: (editorState, node) =>
          editorState.document.root.children.length == 1 &&
          (node.delta?.isEmpty ?? false) &&
          node.path.length == 1,
    ),
    HeadingBlockKeys.type: HeadingBlockComponentBuilder(
      configuration: cfg,
      textStyleBuilder: (level) => TextStyle(
        fontSize: helpHeadingSize(level),
        fontWeight: FontWeight.w700,
      ),
    ),
    BulletedListBlockKeys.type: BulletedListBlockComponentBuilder(
      configuration: cfg,
      iconBuilder: (context, node) => _ListMarker(node: node),
    ),
    NumberedListBlockKeys.type: NumberedListBlockComponentBuilder(
      configuration: cfg,
      iconBuilder: (context, node, direction) => _ListMarker(node: node),
    ),
    HelpNodes.image: _HelpImageBlockBuilder(scope, cfg),
    HelpNodes.media: _HelpMediaBlockBuilder(cfg),
  };
}

int helpListIndex(Node node) {
  var index = 1;
  if (node.attributes[HelpNodes.listStart] == true) return index;
  var prev = node.previous;
  while (prev != null && prev.type == node.type) {
    index++;
    if (prev.attributes[HelpNodes.listStart] == true) break;
    prev = prev.previous;
  }
  return index;
}

class _ListMarker extends StatelessWidget {
  const _ListMarker({required this.node});
  final Node node;

  int get _depth {
    var d = 0;
    var p = node.parent;
    while (p != null) {
      if (p.type == node.type) d++;
      p = p.parent;
    }
    return d;
  }

  @override
  Widget build(BuildContext context) {
    final ordered = node.type == HelpNodes.numbered;
    final base = helpBlockTextStyle(node);
    final delta = node.delta;
    double? size;
    if (delta != null) {
      for (final op in delta) {
        if (op is TextInsert && op.attributes?['font_size'] is num) {
          size = (op.attributes!['font_size'] as num).toDouble();
          break;
        }
      }
    }
    final fontSize = size ?? base.fontSize ?? 16;
    final lineH = fontSize * 1.6;
    if (!ordered) {
      final depth = _depth % 3;
      final dot = math.max(5.0, fontSize * 0.36);
      return SizedBox(
        width: 28,
        height: lineH,
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 9),
            child: Container(
              width: dot,
              height: dot,
              decoration: BoxDecoration(
                color: depth == 1 ? null : (base.color ?? kHelpTextColor),
                shape: depth == 2 ? BoxShape.rectangle : BoxShape.circle,
                border: depth == 1 ? Border.all(color: base.color ?? kHelpTextColor, width: 1.2) : null,
              ),
            ),
          ),
        ),
      );
    }
    return Container(
      constraints: BoxConstraints(minWidth: 28, minHeight: lineH),
      padding: const EdgeInsets.only(right: 6),
      alignment: Alignment.topRight,
      child: Text(
        '${helpListIndex(node)}.',
        style: TextStyle(fontSize: fontSize, height: 1.6, color: base.color ?? kHelpTextColor),
        textAlign: TextAlign.right,
      ),
    );
  }
}

double? helpImageDisplayWidth(Node node) {
  final css = parseCss(node.attributes[HelpNodes.imgStyle] as String?);
  return cssPxValue(css['width']) ?? double.tryParse('${node.attributes[HelpNodes.width] ?? ''}');
}

double? helpImageAspect(Node node) {
  final w = double.tryParse('${node.attributes[HelpNodes.width] ?? ''}');
  final h = double.tryParse('${node.attributes[HelpNodes.height] ?? ''}');
  if (w == null || h == null || w <= 0 || h <= 0) return null;
  return h / w;
}

Alignment _alignOf(Node node) {
  switch (node.attributes[HelpNodes.align]) {
    case 'center':
      return Alignment.center;
    case 'right':
      return Alignment.centerRight;
    default:
      return Alignment.centerLeft;
  }
}

class _HelpImageBlockBuilder extends BlockComponentBuilder {
  _HelpImageBlockBuilder(this.scope, BlockComponentConfiguration cfg) {
    configuration = cfg;
  }

  final HelpRichScope scope;

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return _HelpImageBlock(
      key: node.key,
      node: node,
      scope: scope,
      configuration: configuration,
    );
  }

  @override
  BlockComponentValidate get validate => (node) => node.delta == null && node.children.isEmpty;

  @override
  Position end(Node node) => Position(path: node.path, offset: 1);
}

class _HelpImageBlock extends BlockComponentStatefulWidget {
  const _HelpImageBlock({
    super.key,
    required super.node,
    required this.scope,
    super.configuration = const BlockComponentConfiguration(),
  });

  final HelpRichScope scope;

  @override
  State<_HelpImageBlock> createState() => _HelpImageBlockState();
}

mixin _BlockSelectable<T extends BlockComponentStatefulWidget> on SelectableMixin<T> {
  GlobalKey get boxKey;
  Node get blockNode => widget.node;
  RenderBox? get _renderBox => context.findRenderObject() as RenderBox?;

  @override
  Position start() => Position(path: blockNode.path, offset: 0);

  @override
  Position end() => Position(path: blockNode.path, offset: 1);

  @override
  Position getPositionInOffset(Offset start) => end();

  @override
  bool get shouldCursorBlink => false;

  @override
  CursorStyle get cursorStyle => CursorStyle.cover;

  @override
  Rect getBlockRect({bool shiftWithBaseOffset = false}) {
    final box = boxKey.currentContext?.findRenderObject();
    if (box is RenderBox) return Offset.zero & box.size;
    return Rect.zero;
  }

  @override
  Rect? getCursorRectInPosition(Position position, {bool shiftWithBaseOffset = false}) {
    final rb = _renderBox;
    if (rb == null) return null;
    final size = rb.size;
    return Rect.fromLTWH(-size.width / 2.0, 0, size.width, size.height);
  }

  @override
  List<Rect> getRectsInSelection(Selection selection, {bool shiftWithBaseOffset = false}) {
    final rb = _renderBox;
    if (rb == null) return [];
    final box = boxKey.currentContext?.findRenderObject();
    if (box is RenderBox) return [box.localToGlobal(Offset.zero, ancestor: rb) & box.size];
    return [Offset.zero & rb.size];
  }

  @override
  Selection getSelectionInRange(Offset start, Offset end) =>
      Selection.single(path: blockNode.path, startOffset: 0, endOffset: 1);

  @override
  Offset localToGlobal(Offset offset, {bool shiftWithBaseOffset = false}) =>
      _renderBox!.localToGlobal(offset);
}

class _HelpImageBlockState extends State<_HelpImageBlock>
    with SelectableMixin, BlockComponentConfigurable, _BlockSelectable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  @override
  final GlobalKey boxKey = GlobalKey();

  late final EditorState editorState = Provider.of<EditorState>(context, listen: false);

  bool _hover = false;
  double? _dragWidth;

  void _commitWidth(double w) {
    final width = w.round();
    final aspect = helpImageAspect(node);
    var style = (node.attributes[HelpNodes.imgStyle] as String?) ?? '';
    style = setCssDecl(style, 'width', '${width}px');
    style = setCssDecl(style, 'height', 'auto');
    final tr = editorState.transaction
      ..updateNode(node, {
        HelpNodes.imgStyle: style,
        HelpNodes.width: '$width',
        if (aspect != null) HelpNodes.height: '${(width * aspect).round()}',
      });
    editorState.apply(tr);
  }

  void _delete() {
    final tr = editorState.transaction..deleteNode(node);
    editorState.apply(tr);
  }

  Widget _broken(double w) => Container(
    width: w,
    height: 120,
    decoration: BoxDecoration(
      color: const Color(0xFFF8F9FA),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFFE3E3E3)),
    ),
    alignment: Alignment.center,
    child: const Text('Image not found', style: TextStyle(color: Color(0xFF777777), fontSize: 13)),
  );

  @override
  Widget build(BuildContext context) {
    final loading = node.attributes[HelpNodes.loading] != null;
    Widget child = LayoutBuilder(
      builder: (ctx, box) {
        final maxW = box.maxWidth.isFinite ? box.maxWidth : 900.0;
        if (loading) {
          return Align(
            alignment: _alignOf(node),
            child: Container(
              width: math.min(320, maxW),
              height: 150,
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE3E3E3)),
              ),
              alignment: Alignment.center,
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TpLoader(size: 40),
                  SizedBox(height: 10),
                  Text('Adding image…', style: TextStyle(fontSize: 12.5, color: Color(0xFF6C757D))),
                ],
              ),
            ),
          );
        }
        final src = '${node.attributes[HelpNodes.src] ?? ''}';
        final provider = widget.scope.imageProvider(src);
        final natural = helpImageDisplayWidth(node);
        final w = math.min(_dragWidth ?? natural ?? maxW, maxW).clamp(24.0, maxW);
        final aspect = helpImageAspect(node);
        final h = aspect == null ? null : w * aspect;
        final img = provider == null
            ? _broken(w)
            : Image(
                image: provider,
                width: w,
                height: h,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => _broken(w),
              );
        final editable = editorState.editable;
        return Align(
          alignment: _alignOf(node),
          child: MouseRegion(
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            child: Stack(
              key: boxKey,
              clipBehavior: Clip.none,
              children: [
                ClipRRect(borderRadius: BorderRadius.circular(8), child: img),
                if (_hover && editable) ...[
                  Positioned(
                    top: 6,
                    right: 6,
                    child: _ImageActions(
                      onEdit: () => widget.scope.onEditImage(editorState, node),
                      onDelete: _delete,
                    ),
                  ),
                  Positioned(
                    right: -5,
                    bottom: -5,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeDownRight,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (_) => setState(() => _dragWidth = w),
                        onPanUpdate: (d) => setState(() {
                          final factor = node.attributes[HelpNodes.align] == 'center' ? 2.0 : 1.0;
                          _dragWidth = ((_dragWidth ?? w) + d.delta.dx * factor).clamp(40.0, maxW);
                        }),
                        onPanEnd: (_) {
                          final v = _dragWidth;
                          setState(() => _dragWidth = null);
                          if (v != null) _commitWidth(v);
                        },
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: const Color(0xFF222F3E), width: 1.5),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
    child = Padding(padding: padding, child: child);
    return BlockSelectionContainer(
      node: node,
      delegate: this,
      listenable: editorState.selectionNotifier,
      remoteSelection: editorState.remoteSelections,
      blockColor: editorState.editorStyle.selectionColor,
      supportTypes: const [BlockSelectionType.block],
      child: child,
    );
  }
}

class _ImageActions extends StatelessWidget {
  const _ImageActions({this.onEdit, required this.onDelete});
  final VoidCallback? onEdit;
  final VoidCallback onDelete;

  Widget _b(IconData icon, String tip, VoidCallback onTap) => Tooltip(
    message: tip,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Icon(icon, size: 16, color: const Color(0xFF222F3E)),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 2,
      borderRadius: BorderRadius.circular(6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onEdit != null) _b(Icons.tune, 'Image options', onEdit!),
          _b(Icons.delete_outline, 'Remove', onDelete),
        ],
      ),
    );
  }
}

class HelpMediaInfo {
  HelpMediaInfo(this.tag, this.src, this.width, this.height);
  final String tag;
  final String src;
  final double? width;
  final double? height;

  static HelpMediaInfo parse(String html) {
    final tag = RegExp(r'^\s*<\s*(\w+)').firstMatch(html)?.group(1)?.toLowerCase() ?? 'video';
    String attr(String name) =>
        RegExp('\\b$name\\s*=\\s*"([^"]*)"', caseSensitive: false).firstMatch(html)?.group(1) ?? '';
    var src = attr('src');
    if (src.isEmpty) {
      src = RegExp(r'<source[^>]*\bsrc\s*=\s*"([^"]*)"', caseSensitive: false).firstMatch(html)?.group(1) ?? '';
    }
    final style = parseCss(attr('style'));
    return HelpMediaInfo(
      tag,
      src.replaceAll('&amp;', '&'),
      cssPxValue(style['width']) ?? double.tryParse(attr('width')),
      cssPxValue(style['height']) ?? double.tryParse(attr('height')),
    );
  }
}

class _HelpMediaBlockBuilder extends BlockComponentBuilder {
  _HelpMediaBlockBuilder(BlockComponentConfiguration cfg) {
    configuration = cfg;
  }

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return _HelpMediaBlock(key: node.key, node: node, configuration: configuration);
  }

  @override
  BlockComponentValidate get validate => (node) => node.delta == null && node.children.isEmpty;

  @override
  Position end(Node node) => Position(path: node.path, offset: 1);
}

class _HelpMediaBlock extends BlockComponentStatefulWidget {
  const _HelpMediaBlock({
    super.key,
    required super.node,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<_HelpMediaBlock> createState() => _HelpMediaBlockState();
}

class _HelpMediaBlockState extends State<_HelpMediaBlock>
    with SelectableMixin, BlockComponentConfigurable, _BlockSelectable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  @override
  final GlobalKey boxKey = GlobalKey();

  late final EditorState editorState = Provider.of<EditorState>(context, listen: false);
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final info = HelpMediaInfo.parse('${node.attributes[HelpNodes.html] ?? ''}');
    Widget child = LayoutBuilder(
      builder: (ctx, box) {
        final maxW = box.maxWidth.isFinite ? box.maxWidth : 720.0;
        final w = math.min(info.width ?? 720, maxW);
        final h = (info.width != null && info.height != null && info.width! > 0)
            ? w * info.height! / info.width!
            : w * 9 / 16;
        return Align(
          alignment: _alignOf(node),
          child: MouseRegion(
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            child: Stack(
              key: boxKey,
              children: [
                Container(
                  width: w,
                  height: math.max(90, h),
                  decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        info.tag == 'video' ? Icons.play_circle_outline : Icons.smart_display_outlined,
                        color: Colors.white,
                        size: 42,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        info.src,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (_hover && editorState.editable)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: _ImageActions(
                      onDelete: () => editorState.apply(editorState.transaction..deleteNode(node)),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
    child = Padding(padding: padding, child: child);
    return BlockSelectionContainer(
      node: node,
      delegate: this,
      listenable: editorState.selectionNotifier,
      remoteSelection: editorState.remoteSelections,
      blockColor: editorState.editorStyle.selectionColor,
      supportTypes: const [BlockSelectionType.block],
      child: child,
    );
  }
}

extension HelpRichOps on EditorState {
  List<Node> _selectedNodes() {
    final sel = selection;
    if (sel == null) return const [];
    return getNodesInSelection(sel.normalized);
  }

  List<Node> _selectedTextNodes() => _selectedNodes().where((n) => n.delta != null).toList();

  Future<void> helpSetBlock(String tag) async {
    final nodes = _selectedTextNodes();
    if (nodes.isEmpty) return;
    final tr = transaction;
    for (final n in nodes) {
      final attrs = Map<String, dynamic>.from(n.attributes)..remove(HelpNodes.level);
      if (tag == 'p' || tag == 'pre') {
        attrs[HelpNodes.tag] = tag;
        tr.updateNodeType(n, HelpNodes.paragraph, attrs);
      } else {
        attrs[HelpNodes.tag] = tag;
        attrs[HelpNodes.level] = int.parse(tag.substring(1));
        tr.updateNodeType(n, HelpNodes.heading, attrs);
      }
    }
    tr.afterSelection = selection;
    await apply(tr);
  }

  Future<void> helpFormatInline(Map<String, dynamic> attrs) async {
    final sel = selection;
    if (sel == null) return;
    if (sel.isCollapsed) {
      attrs.forEach(updateToggledStyle);
      return;
    }
    await formatDelta(sel, attrs);
  }

  Future<void> helpClearFormatting() => helpFormatInline({
    'bold': null,
    'italic': null,
    'underline': null,
    'strikethrough': null,
    'code': null,
    'font_color': null,
    'bg_color': null,
    'font_size': null,
    'font_family': null,
    HelpNodes.extraCss: null,
  });

  Future<void> helpSetAlign(String align) async {
    final nodes = _selectedNodes();
    if (nodes.isEmpty) return;
    final tr = transaction;
    for (final n in nodes) {
      if (n.type == PageBlockKeys.type) continue;
      tr.updateNode(n, {HelpNodes.align: align});
    }
    tr.afterSelection = selection;
    await apply(tr);
  }

  Future<void> helpToggleList(bool ordered) async {
    final type = ordered ? HelpNodes.numbered : HelpNodes.bulleted;
    final nodes = _selectedTextNodes();
    if (nodes.isEmpty) return;
    final all = nodes.every((n) => n.type == type);
    final tr = transaction;
    for (var i = 0; i < nodes.length; i++) {
      final n = nodes[i];
      final attrs = Map<String, dynamic>.from(n.attributes)..remove(HelpNodes.level);
      if (all) {
        attrs[HelpNodes.tag] = 'p';
        attrs.remove(HelpNodes.listStart);
        tr.updateNodeType(n, HelpNodes.paragraph, attrs);
      } else {
        attrs.remove(HelpNodes.tag);
        attrs.remove(HelpNodes.indent);
        final prev = n.previous;
        final continues = prev != null && prev.type == type && (i > 0 || !nodes.contains(prev));
        if (!continues && i == 0) {
          attrs[HelpNodes.listStart] = true;
        } else {
          attrs.remove(HelpNodes.listStart);
        }
        tr.updateNodeType(n, type, attrs);
      }
    }
    tr.afterSelection = selection;
    await apply(tr);
  }

  Future<void> helpIndent(bool increase) async {
    final nodes = _selectedNodes().where((n) => n.type != PageBlockKeys.type).toList();
    if (nodes.isEmpty) return;
    if (nodes.every((n) => HelpNodes.isList(n.type))) {
      (increase ? indentCommand : outdentCommand).handler(this);
      return;
    }
    final tr = transaction;
    for (final n in nodes) {
      if (n.delta == null || HelpNodes.isList(n.type)) continue;
      final cur = n.attributes[HelpNodes.indent];
      final now = cur is num ? cur.toInt() : 0;
      final next = increase ? now + 40 : math.max(0, now - 40);
      tr.updateNode(n, {HelpNodes.indent: next == 0 ? null : next});
    }
    tr.afterSelection = selection;
    await apply(tr);
  }

  String helpSelectedText() => getTextInSelection(selection).join('\n');

  Future<void> helpApplyLink(String href, String label, bool newWindow) async {
    final sel = selection?.normalized;
    if (sel == null) return;
    final meta = newWindow ? jsonEncode({'target': '_blank', 'rel': 'noopener'}) : null;
    final attrs = <String, dynamic>{'href': href, HelpNodes.anchor: meta};
    final node = getNodeAtPath(sel.start.path);
    if (node == null || node.delta == null) return;
    final current = helpSelectedText();
    if (sel.isCollapsed || (sel.isSingle && label.isNotEmpty && label != current)) {
      final text = label.isEmpty ? href : label;
      final tr = transaction;
      if (sel.isCollapsed) {
        tr.insertText(node, sel.startIndex, text, attributes: {
          'href': href,
          HelpNodes.anchor: ?meta,
        });
      } else {
        tr.replaceText(node, sel.startIndex, sel.endIndex - sel.startIndex, text, attributes: {
          'href': href,
          HelpNodes.anchor: ?meta,
        });
      }
      await apply(tr);
      return;
    }
    await formatDelta(sel, attrs);
  }

  Future<Path> helpInsertBlocks(List<Node> blocks) async {
    final sel = selection?.normalized;
    final root = document.root;
    final tr = transaction;
    var target = <int>[root.children.length];
    Node? replace;
    var extra = <Node>[];
    final node = sel == null ? null : getNodeAtPath(sel.end.path);
    if (sel != null && node != null) {
      final delta = node.delta;
      final idx = sel.endIndex;
      if (delta == null) {
        target = node.path.next;
      } else if (HelpNodes.isList(node.type)) {
        target = node.path + [0];
        if (idx < delta.length) {
          final tail = delta.slice(idx);
          tr.deleteText(node, idx, delta.length - idx);
          extra = [
            Node(type: HelpNodes.paragraph, attributes: {HelpNodes.tag: '', 'delta': tail.toJson()}),
          ];
        }
      } else if (delta.isEmpty && node.type == HelpNodes.paragraph && node.children.isEmpty) {
        target = node.path;
        replace = node;
      } else if (idx == 0) {
        target = node.path;
      } else if (idx >= delta.length) {
        target = node.path.next;
      } else {
        final tail = delta.slice(idx);
        tr.deleteText(node, idx, delta.length - idx);
        final attrs = Map<String, dynamic>.from(node.attributes)
          ..remove(HelpNodes.bareEmpty)
          ..remove(HelpNodes.listStart)
          ..['delta'] = tail.toJson();
        extra = [Node(type: node.type, attributes: attrs)];
        target = node.path.next;
      }
    }
    final all = [...blocks, ...extra];
    tr.insertNodes(target, all);
    if (replace != null) tr.deleteNode(replace);
    final base = target.sublist(0, target.length - 1);
    final lastPath = base + [target.last + blocks.length - 1];
    if (extra.isNotEmpty) {
      tr.afterSelection = Selection.collapsed(Position(path: base + [target.last + blocks.length]));
    } else {
      final parent = getNodeAtPath(base) ?? root;
      final remaining = parent.children.length - (replace != null ? 1 : 0);
      final atEnd = target.last >= remaining;
      if (atEnd && base.isEmpty) {
        final after = [target.last + blocks.length];
        tr.insertNode(after, paragraphNode());
        tr.afterSelection = Selection.collapsed(Position(path: after));
      } else {
        tr.afterSelection = Selection.collapsed(Position(path: lastPath, offset: 1));
      }
    }
    await apply(tr);
    return lastPath;
  }
}
