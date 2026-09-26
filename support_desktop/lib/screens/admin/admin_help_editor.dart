import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/admin_help_service.dart';
import '../../theme.dart';
import '../../widgets/premium.dart';
import 'help_clipboard.dart';
import 'help_html_codec.dart';
import 'help_rich_editor.dart';

enum HelpEditorMode { rich, html }

const kHelpImageMaxBytes = 8 * 1024 * 1024;
const kHelpSaveMaxBytes = 95 * 1024 * 1024;

class HelpEditorController extends ChangeNotifier {
  HelpEditorController([String html = '']) {
    _load(html);
  }

  final TextEditingController source = TextEditingController();
  final UndoHistoryController undo = UndoHistoryController();
  final Map<String, String> _inline = {};
  final Map<String, MemoryImage> _images = {};
  int _seq = 0;

  HelpEditorMode mode = HelpEditorMode.rich;
  EditorState? editorState;
  List<String> htmlReasons = const [];
  int generation = 0;
  String _original = '';
  bool _richDirty = false;
  String _sourceBaseline = '';
  StreamSubscription<EditorTransactionValue>? _sub;
  final List<EditorState> _states = [];

  static final _dataSrc = RegExp(
    r'''src=(["'])(data:image/[^"']+)\1''',
    caseSensitive: false,
  );
  static final _tokenSrc = RegExp(r'tp-inline-image-\d+');

  void _load(String html) {
    _inline.clear();
    _images.clear();
    _original = html.replaceAllMapped(_dataSrc, (m) {
      return 'src="${registerInline(m.group(2)!)}"';
    });
    _richDirty = false;
    final issues = HelpHtmlCodec.roundTripIssues(_original);
    if (issues.isEmpty) {
      _startRich(_original);
    } else {
      htmlReasons = issues;
      _enterHtml(_original);
    }
  }

  void setHtml(String html) {
    _load(html);
    notifyListeners();
  }

  void _startRich(String html) {
    _sub?.cancel();
    final decoded = HelpHtmlCodec.decode(html);
    final state = EditorState(document: HelpHtmlCodec.decodeDocument(decoded.nodes));
    _states.add(state);
    editorState = state;
    generation++;
    mode = HelpEditorMode.rich;
    _sub = state.transactionStream.listen((_) => _richDirty = true);
  }

  void _enterHtml(String text) {
    mode = HelpEditorMode.html;
    source.value = TextEditingValue(
      text: text,
      selection: const TextSelection.collapsed(offset: 0),
    );
    _sourceBaseline = text;
  }

  String get collapsedHtml {
    if (mode == HelpEditorMode.rich) {
      final state = editorState;
      if (!_richDirty || state == null) return _original;
      return HelpHtmlCodec.encode(state.document.root.children);
    }
    if (!_richDirty && source.text == _sourceBaseline) return _original;
    return source.text;
  }

  String get html => collapsedHtml.replaceAllMapped(
    _tokenSrc,
    (m) => _inline[m.group(0)] ?? m.group(0)!,
  );

  String? get saveProblem {
    final size = utf8.encode(html).length;
    if (size <= kHelpSaveMaxBytes) return null;
    return 'This document is ${AdminHelpApi.formatBytes(size)} with its images, over the ${AdminHelpApi.formatBytes(kHelpSaveMaxBytes)} upload limit. Remove or shrink some images and save again.';
  }

  void switchToHtml({String? insertAfterSelection}) {
    if (mode == HelpEditorMode.html) return;
    var text = collapsedHtml;
    final state = editorState;
    if (insertAfterSelection != null && state != null) {
      final nodes = state.document.root.children.toList();
      final sel = state.selection;
      final at = sel == null ? nodes.length : math.min(nodes.length, sel.end.path.first + 1);
      text = HelpHtmlCodec.encode(nodes.sublist(0, at)) +
          insertAfterSelection +
          HelpHtmlCodec.encode(nodes.sublist(at));
      _richDirty = true;
    }
    htmlReasons = const [];
    _enterHtml(text);
    notifyListeners();
  }

  List<String> switchToRich() {
    if (mode == HelpEditorMode.rich) return const [];
    final text = source.text;
    final issues = HelpHtmlCodec.roundTripIssues(text);
    if (issues.isNotEmpty) return issues;
    if (text != _sourceBaseline) _richDirty = true;
    if (_richDirty) {
      _original = text;
      _richDirty = false;
    }
    htmlReasons = const [];
    _startRich(text);
    notifyListeners();
    return const [];
  }

  String registerInline(String dataUrl) {
    final key = 'tp-inline-image-${++_seq}';
    _inline[key] = dataUrl;
    return key;
  }

  String registerInlineBytes(Uint8List bytes, String mime) {
    final key = registerInline('data:$mime;base64,${base64Encode(bytes)}');
    _images[key] = MemoryImage(bytes);
    return key;
  }

  String? inlineData(String key) => _inline[key];

  MemoryImage? inlineImage(String key) {
    final cached = _images[key];
    if (cached != null) return cached;
    final data = _inline[key];
    if (data == null) return null;
    try {
      final img = MemoryImage(base64Decode(data.substring(data.indexOf(',') + 1)));
      _images[key] = img;
      return img;
    } catch (_) {
      return null;
    }
  }

  TextSelection get _sel {
    final v = source.value;
    if (v.selection.isValid) return v.selection;
    return TextSelection.collapsed(offset: v.text.length);
  }

  String get selectedText => _sel.textInside(source.text);

  void _replace(String snippet, {int? selectFrom, int? selectTo}) {
    final sel = _sel;
    final text = source.text.replaceRange(sel.start, sel.end, snippet);
    source.value = TextEditingValue(
      text: text,
      selection: selectFrom == null
          ? TextSelection.collapsed(offset: sel.start + snippet.length)
          : TextSelection(
              baseOffset: sel.start + selectFrom,
              extentOffset: sel.start + (selectTo ?? selectFrom),
            ),
    );
  }

  void insert(String snippet) => _replace(snippet);

  void wrap(String open, String close) {
    final inner = selectedText;
    _replace(
      '$open$inner$close',
      selectFrom: open.length,
      selectTo: open.length + inner.length,
    );
  }

  static final _outerBlock = RegExp(
    r'^\s*<(p|div|h[1-6]|pre|blockquote)(\s[^>]*)?>([\s\S]*)</\1>\s*$',
    caseSensitive: false,
  );

  String _unwrapBlock(String s) {
    final m = _outerBlock.firstMatch(s);
    return m == null ? s : m.group(3)!;
  }

  String? _outerStyle(String s) {
    final m = _outerBlock.firstMatch(s);
    if (m == null) return null;
    final st = RegExp(
      r'''style=(["'])(.*?)\1''',
      caseSensitive: false,
    ).firstMatch(m.group(2) ?? '');
    return st?.group(2);
  }

  void block(String tag) {
    final inner = _unwrapBlock(selectedText);
    final open = '<$tag>';
    _replace(
      '$open$inner</$tag>',
      selectFrom: open.length,
      selectTo: open.length + inner.length,
    );
  }

  void blockStyle(String property, String? value) {
    final sel = selectedText;
    final inner = _unwrapBlock(sel);
    final styles = <String, String>{};
    for (final part in (_outerStyle(sel) ?? '').split(';')) {
      final i = part.indexOf(':');
      if (i <= 0) continue;
      styles[part.substring(0, i).trim()] = part.substring(i + 1).trim();
    }
    if (value == null) {
      styles.remove(property);
    } else {
      styles[property] = value;
    }
    final attr = styles.isEmpty
        ? ''
        : ' style="${styles.entries.map((e) => '${e.key}: ${e.value};').join(' ')}"';
    final open = '<p$attr>';
    _replace(
      '$open$inner</p>',
      selectFrom: open.length,
      selectTo: open.length + inner.length,
    );
  }

  void indent(bool increase) {
    final current = RegExp(
      r'padding-left:\s*(\d+)px',
    ).firstMatch(_outerStyle(selectedText) ?? '');
    final now = int.tryParse(current?.group(1) ?? '') ?? 0;
    final next = increase ? now + 40 : math.max(0, now - 40);
    blockStyle('padding-left', next == 0 ? null : '${next}px');
  }

  void list(bool ordered) {
    final tag = ordered ? 'ol' : 'ul';
    final lines = selectedText
        .split('\n')
        .map((l) => _unwrapBlock(l).trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      const open = '<li>';
      _replace('<$tag>\n$open</li>\n</$tag>', selectFrom: tag.length + 3 + open.length);
      return;
    }
    _replace('<$tag>\n${lines.map((l) => '<li>$l</li>').join('\n')}\n</$tag>');
  }

  void removeFormat() {
    final cleaned = selectedText.replaceAll(
      RegExp(
        r'</?(span|strong|b|em|i|u|font|s|strike|sub|sup|mark|code)\b[^>]*>',
        caseSensitive: false,
      ),
      '',
    );
    _replace(cleaned, selectFrom: 0, selectTo: cleaned.length);
  }

  @override
  void dispose() {
    _sub?.cancel();
    for (final s in _states) {
      s.dispose();
    }
    source.dispose();
    undo.dispose();
    super.dispose();
  }
}

String helpAttr(String v) =>
    v.replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;');

const _kColorMap = [
  '#BFEDD2', '#FBEEB8', '#F8CAC6', '#ECCAFA', '#C2E0F4',
  '#2DC26B', '#F1C40F', '#E03E2D', '#B96AD9', '#3598DB',
  '#169179', '#E67E23', '#BA372A', '#843FA1', '#236FA1',
  '#ECF0F1', '#CED4D9', '#95A5A6', '#7E8C8D', '#34495E',
  '#000000', '#FFFFFF',
];

const _kImageMaxHeight = 720;
const _kEditorBodyWidth = 960;
const _kVideoWidth = 720;

class _PreparedImage {
  _PreparedImage(this.bytes, this.mime, this.width, this.height);
  final Uint8List bytes;
  final String mime;
  final int width;
  final int height;
}

String? _sniffMime(Uint8List b) {
  if (b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'image/png';
  if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return 'image/jpeg';
  if (b.length > 6 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return 'image/gif';
  if (b.length > 12 &&
      b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 &&
      b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) {
    return 'image/webp';
  }
  return null;
}

Future<_PreparedImage> _prepareImage(Uint8List raw) async {
  ui.Codec codec;
  try {
    codec = await ui.instantiateImageCodec(raw);
  } catch (_) {
    throw HelpApiError('That file is not an image this editor can read.');
  }
  final frame = await codec.getNextFrame();
  final image = frame.image;
  var bytes = raw;
  var mime = _sniffMime(raw);
  if (mime == null) {
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) {
      image.dispose();
      throw HelpApiError('Could not convert the image to PNG.');
    }
    bytes = png.buffer.asUint8List();
    mime = 'image/png';
  }
  final w = image.width;
  final h = image.height;
  image.dispose();
  codec.dispose();
  if (bytes.length > kHelpImageMaxBytes) {
    throw HelpApiError(
      'This image is ${AdminHelpApi.formatBytes(bytes.length)}. Images must be ${AdminHelpApi.formatBytes(kHelpImageMaxBytes)} or smaller.',
    );
  }
  final maxW = math.max(280, _kEditorBodyWidth - 32);
  final scale = [1.0, maxW / w, _kImageMaxHeight / h].reduce(math.min);
  return _PreparedImage(
    bytes,
    mime,
    math.max(1, (w * scale).round()),
    math.max(1, (h * scale).round()),
  );
}

class HelpContentEditor extends StatefulWidget {
  const HelpContentEditor({
    super.key,
    required this.controller,
    required this.helpApi,
    this.autofocus = false,
  });

  final HelpEditorController controller;
  final AdminHelpApi helpApi;
  final bool autofocus;

  @override
  State<HelpContentEditor> createState() => _HelpContentEditorState();
}

class _HelpContentEditorState extends State<HelpContentEditor> {
  HelpEditorController get c => widget.controller;
  EditorState? get es => c.editorState;
  bool get _rich => c.mode == HelpEditorMode.rich;
  final _focus = FocusNode();
  bool _preview = false;
  bool _dragging = false;
  String? _status;
  bool _statusError = false;
  double? _progress;
  Timer? _statusTimer;
  Selection? _lastSelection;
  EditorState? _listening;
  static ({String text, String html})? _lastCopy;

  late final HelpRichScope _scope = HelpRichScope(
    imageProvider: _imageProvider,
    onEditImage: _editImage,
  );

  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
    _attach();
    if (kDebugMode) _debugHooks();
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    _listening?.selectionNotifier.removeListener(_trackSelection);
    _focus.dispose();
    _statusTimer?.cancel();
    super.dispose();
  }

  void _changed() {
    _attach();
    if (mounted) setState(() {});
  }

  void _attach() {
    final state = es;
    if (identical(state, _listening)) return;
    _listening?.selectionNotifier.removeListener(_trackSelection);
    _listening = state;
    state?.selectionNotifier.addListener(_trackSelection);
  }

  void _trackSelection() {
    final s = _listening?.selection;
    if (s != null) _lastSelection = s;
  }

  void _ensureSelection() {
    final state = es;
    if (state == null || state.selection != null) return;
    final last = _lastSelection;
    if (last != null && state.getNodeAtPath(last.end.path) != null) {
      state.updateSelectionWithReason(last, reason: SelectionUpdateReason.uiEvent);
    }
  }

  void _debugHooks() {
    final paste = Platform.environment['TP_HELP_PASTE_PNG'];
    if (paste != null && paste.isNotEmpty) {
      Timer(Duration(milliseconds: int.tryParse(Platform.environment['TP_HELP_PASTE_DELAY'] ?? '') ?? 2500), () async {
        final state = es;
        if (!mounted || state == null) return;
        final at = int.tryParse(Platform.environment['TP_HELP_PASTE_AT'] ?? '') ?? 0;
        final nodes = state.document.root.children.toList();
        if (nodes.isNotEmpty) {
          final node = nodes[at.clamp(0, nodes.length - 1)];
          state.updateSelectionWithReason(
            Selection.collapsed(Position(path: node.path, offset: node.delta?.length ?? 1)),
            reason: SelectionUpdateReason.uiEvent,
          );
        }
        await _handleClipboard(HelpClipboardData(image: File(paste).readAsBytesSync()));
      });
    }
    final caret = int.tryParse(Platform.environment['TP_HELP_CARET'] ?? '');
    if (caret != null) {
      Timer(const Duration(milliseconds: 2000), () {
        final state = es;
        if (!mounted || state == null) return;
        final nodes = state.document.root.children.toList();
        if (nodes.isEmpty) return;
        final node = nodes[caret.clamp(0, nodes.length - 1)];
        state.updateSelectionWithReason(
          Selection.collapsed(Position(path: node.path, offset: node.delta?.length ?? 1)),
          reason: SelectionUpdateReason.uiEvent,
        );
      });
    }
    final realPaste = int.tryParse(Platform.environment['TP_HELP_REAL_PASTE'] ?? '');
    if (realPaste != null) {
      Timer(Duration(milliseconds: realPaste), () {
        final state = es;
        if (!mounted || state == null) return;
        final first = state.document.root.children.first;
        state.updateSelectionWithReason(
          Selection.collapsed(Position(path: first.path, offset: first.delta?.length ?? 1)),
          reason: SelectionUpdateReason.uiEvent,
        );
        _onPaste(state);
      });
    }
    final jump = int.tryParse(Platform.environment['TP_HELP_JUMP'] ?? '');
    if (jump != null) {
      Timer(const Duration(milliseconds: 2500), () {
        if (mounted) es?.scrollService?.jumpTo(jump);
      });
    }
    final mode = Platform.environment['TP_HELP_MODE'];
    if (mode == 'html') {
      Timer(const Duration(milliseconds: 1500), () {
        if (mounted) c.switchToHtml();
      });
    }
    if (Platform.environment['TP_HELP_PREVIEW'] == '1') {
      Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _preview = true);
      });
    }
  }

  ImageProvider? _imageProvider(String src) {
    if (src.isEmpty) return null;
    if (src.startsWith('tp-inline-image-')) return c.inlineImage(src);
    if (src.startsWith('data:')) {
      try {
        return MemoryImage(base64Decode(src.substring(src.indexOf(',') + 1)));
      } catch (_) {
        return null;
      }
    }
    final api = widget.helpApi.api;
    var url = src;
    if (url.startsWith('//')) {
      url = 'https:$url';
    } else if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(url)) {
      url = '${api.baseUrl}/${url.replaceFirst(RegExp(r'^/+'), '')}';
    }
    return NetworkImage(url, headers: api.authHeaders());
  }

  void _notify(String text, {bool error = false}) {
    _statusTimer?.cancel();
    setState(() {
      _status = text;
      _statusError = error;
      _progress = null;
    });
    _statusTimer = Timer(Duration(seconds: error ? 9 : 6), () {
      if (mounted) setState(() => _status = null);
    });
  }

  void _act(void Function() fn) {
    fn();
    if (!_rich) _focus.requestFocus();
  }

  Future<void> _rich1(Future<void> Function(EditorState s) fn) async {
    final state = es;
    if (state == null) return;
    _ensureSelection();
    await fn(state);
  }

  Future<void> _link() async {
    final url = TextEditingController();
    String initialLabel;
    if (_rich) {
      _ensureSelection();
      initialLabel = es?.helpSelectedText() ?? '';
      final href = es?.getDeltaAttributeValueInSelection<String>('href');
      if (href != null) url.text = href;
    } else {
      initialLabel = c.selectedText;
    }
    final label = TextEditingController(text: initialLabel);
    var newWindow = true;
    final ok = await showWebModal<bool>(
      context,
      title: 'Insert/Edit Link',
      icon: Icons.link,
      width: 520,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FormRow(
              label: 'URL',
              labelWidth: 130,
              child: TextField(controller: url, autofocus: true),
            ),
            FormRow(
              label: 'Text to display',
              labelWidth: 130,
              child: TextField(controller: label),
            ),
            CheckboxListTile(
              value: newWindow,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Open link in a new window'),
              onChanged: (v) => set(() => newWindow = v ?? true),
            ),
          ],
        ),
      ),
      actions: (ctx) => [
        GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx, false)),
        SignalButton(label: 'Save', onPressed: () => Navigator.pop(ctx, true)),
      ],
    );
    if (ok != true) return;
    var href = url.text.trim();
    if (href.isEmpty) return;
    if (!RegExp(r'^([a-z][a-z0-9+.-]*:|/|#)', caseSensitive: false).hasMatch(href)) {
      href = 'https://$href';
    }
    final text = label.text.trim().isEmpty ? href : label.text.trim();
    if (_rich) {
      await _rich1((s) => s.helpApplyLink(href, label.text.trim(), newWindow));
      return;
    }
    final target = newWindow ? ' target="_blank" rel="noopener"' : '';
    _act(() => c.insert('<a href="${helpAttr(href)}"$target>$text</a>'));
  }

  Future<void> _insertImageBytes(Uint8List raw, {String? name}) async {
    if (!_rich) {
      try {
        final p = await _prepareImage(raw);
        final token = c.registerInlineBytes(p.bytes, p.mime);
        final alt = name == null ? '' : ' alt="${helpAttr(name)}"';
        _act(() => c.insert(
          '<img style="width: ${p.width}px; height: auto;" src="$token"$alt width="${p.width}" height="${p.height}">',
        ));
      } catch (e) {
        if (mounted) _notify(e is HelpApiError ? e.message : 'Could not add the image.', error: true);
      }
      return;
    }
    final state = es;
    if (state == null) return;
    _ensureSelection();
    final marker = 'img-${DateTime.now().microsecondsSinceEpoch}';
    await state.helpInsertBlocks([
      Node(type: HelpNodes.image, attributes: {HelpNodes.loading: marker}),
    ]);
    Node? find(Node n) {
      if (n.attributes[HelpNodes.loading] == marker) return n;
      for (final ch in n.children) {
        final f = find(ch);
        if (f != null) return f;
      }
      return null;
    }

    try {
      final p = await _prepareImage(raw);
      if (kDebugMode) {
        final slow = int.tryParse(Platform.environment['TP_HELP_PASTE_SLOW'] ?? '');
        if (slow != null) await Future<void>.delayed(Duration(milliseconds: slow));
      }
      final token = c.registerInlineBytes(p.bytes, p.mime);
      final node = find(state.document.root);
      if (node == null) return;
      final tr = state.transaction
        ..updateNode(node, {
          HelpNodes.loading: null,
          HelpNodes.imgStyle: 'width: ${p.width}px; height: auto;',
          HelpNodes.src: token,
          HelpNodes.alt: ?name,
          HelpNodes.width: '${p.width}',
          HelpNodes.height: '${p.height}',
        });
      await state.apply(tr);
    } catch (e) {
      final node = find(state.document.root);
      if (node != null) await state.apply(state.transaction..deleteNode(node));
      if (mounted) _notify(e is HelpApiError ? e.message : 'Could not add the image.', error: true);
    }
  }

  Future<void> _uploadImage() async {
    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: helpImageExtensions.toList(),
        withData: true,
      );
    } catch (_) {
      return;
    }
    final file = picked?.files.single;
    if (file == null) return;
    final bytes = file.bytes ??
        (file.path != null ? await File(file.path!).readAsBytes() : null);
    if (bytes == null) return;
    await _insertImageBytes(bytes, name: file.name);
  }

  Future<void> _imageFromUrl() async {
    final url = TextEditingController();
    final alt = TextEditingController();
    final ok = await showWebModal<bool>(
      context,
      title: 'Insert/Edit Image',
      icon: Icons.image_outlined,
      width: 520,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FormRow(
            label: 'Source',
            labelWidth: 150,
            child: TextField(controller: url, autofocus: true),
          ),
          FormRow(
            label: 'Alternative description',
            labelWidth: 150,
            child: TextField(controller: alt),
          ),
        ],
      ),
      actions: (ctx) => [
        GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx, false)),
        SignalButton(label: 'Save', onPressed: () => Navigator.pop(ctx, true)),
      ],
    );
    if (ok != true || url.text.trim().isEmpty) return;
    if (_rich) {
      await _rich1((s) => s.helpInsertBlocks([
        Node(type: HelpNodes.image, attributes: {
          HelpNodes.src: url.text.trim(),
          HelpNodes.alt: alt.text.trim(),
        }),
      ]));
      return;
    }
    _act(() => c.insert(
      '<img src="${helpAttr(url.text.trim())}" alt="${helpAttr(alt.text.trim())}">',
    ));
  }

  Future<void> _editImage(EditorState state, Node node) async {
    final width = TextEditingController(
      text: helpImageDisplayWidth(node)?.round().toString() ?? '',
    );
    final alt = TextEditingController(text: '${node.attributes[HelpNodes.alt] ?? ''}');
    var align = '${node.attributes[HelpNodes.align] ?? 'left'}';
    final ok = await showWebModal<bool>(
      context,
      title: 'Image options',
      icon: Icons.image_outlined,
      width: 480,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FormRow(
              label: 'Width (px)',
              labelWidth: 150,
              child: TextField(
                controller: width,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ),
            FormRow(
              label: 'Alternative description',
              labelWidth: 150,
              child: TextField(controller: alt),
            ),
            FormRow(
              label: 'Alignment',
              labelWidth: 150,
              child: DropdownButtonFormField<String>(
                initialValue: const ['left', 'center', 'right'].contains(align) ? align : 'left',
                items: const [
                  DropdownMenuItem(value: 'left', child: Text('Left')),
                  DropdownMenuItem(value: 'center', child: Text('Center')),
                  DropdownMenuItem(value: 'right', child: Text('Right')),
                ],
                onChanged: (v) => set(() => align = v ?? 'left'),
              ),
            ),
          ],
        ),
      ),
      actions: (ctx) => [
        GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx, false)),
        SignalButton(label: 'Save', onPressed: () => Navigator.pop(ctx, true)),
      ],
    );
    if (ok != true) return;
    final attrs = <String, dynamic>{
      HelpNodes.align: align,
      HelpNodes.alt: alt.text.trim().isEmpty ? null : alt.text.trim(),
    };
    final w = int.tryParse(width.text.trim());
    if (w != null && w > 0) {
      final aspect = helpImageAspect(node);
      var style = (node.attributes[HelpNodes.imgStyle] as String?) ?? '';
      style = setCssDecl(style, 'width', '${w}px');
      style = setCssDecl(style, 'height', 'auto');
      attrs[HelpNodes.imgStyle] = style;
      attrs[HelpNodes.width] = '$w';
      if (aspect != null) attrs[HelpNodes.height] = '${(w * aspect).round()}';
    }
    await state.apply(state.transaction..updateNode(node, attrs));
  }

  Future<void> _insertHtmlSnippet(String html) async {
    if (!_rich) {
      _act(() => c.insert(html));
      return;
    }
    final decoded = HelpHtmlCodec.decode(html);
    if (decoded.issues.isNotEmpty || decoded.nodes.isEmpty) {
      _notify('This embed can only be added in HTML mode.', error: true);
      return;
    }
    await _rich1((s) => s.helpInsertBlocks(decoded.nodes));
  }

  Future<void> _uploadVideo() async {
    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: AdminHelpApi.videoExtensions,
      );
    } catch (_) {
      return;
    }
    final file = picked?.files.single;
    if (file == null || file.path == null) return;
    _statusTimer?.cancel();
    setState(() {
      _status = 'Uploading ${file.name}…';
      _statusError = false;
      _progress = 0;
    });
    try {
      final res = await widget.helpApi.uploadVideo(
        File(file.path!),
        file.name,
        (pct) {
          if (mounted) setState(() => _progress = pct / 100);
        },
      );
      if (!mounted) return;
      await _insertHtmlSnippet(
        '<p><video src="${helpAttr('${res['url'] ?? ''}')}" width="$_kVideoWidth" controls="controls" preload="metadata" title="${helpAttr(file.name)}"></video></p>',
      );
      _notify('Video added. Remember to save the document.');
    } catch (e) {
      if (mounted) {
        _notify(
          e is HelpApiError ? e.message : 'Video upload failed.',
          error: true,
        );
      }
    }
  }

  Future<void> _videoFromLink() async {
    final url = TextEditingController();
    String? error;
    var busy = false;
    final html = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          Future<void> submit() async {
            set(() {
              busy = true;
              error = null;
            });
            try {
              final res = await widget.helpApi.videoLink(url.text.trim());
              if (res['success'] == true) {
                if (ctx.mounted) Navigator.pop(ctx, '${res['html']}');
                return;
              }
              set(() => error = '${res['message'] ?? ''}');
            } catch (e) {
              set(() => error = '$e');
            }
            set(() => busy = false);
          }

          return WebModal(
            title: 'Video from link',
            icon: Icons.link,
            width: 560,
            actions: [
              GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx)),
              SignalButton(label: 'Insert', busy: busy, onPressed: busy ? null : submit),
            ],
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'YouTube, Vimeo, Loom, Google Drive or direct video (.mp4) link',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: url,
                  autofocus: true,
                  onSubmitted: (_) => busy ? null : submit(),
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!, style: const TextStyle(color: Brand.danger)),
                ],
              ],
            ),
          );
        },
      ),
    );
    if (html == null || html.isEmpty) return;
    await _insertHtmlSnippet(html);
  }

  Future<void> _table() async {
    final rows = TextEditingController(text: '2');
    final cols = TextEditingController(text: '2');
    final ok = await showWebModal<bool>(
      context,
      title: 'Insert table',
      icon: Icons.table_chart_outlined,
      width: 420,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_rich)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Tables are edited in HTML mode. The editor switches to HTML mode and adds the table after the current paragraph.',
                style: TextStyle(fontSize: 13, color: Color(0xFF6C757D)),
              ),
            ),
          FormRow(label: 'Rows', labelWidth: 100, child: TextField(controller: rows)),
          FormRow(label: 'Columns', labelWidth: 100, child: TextField(controller: cols)),
        ],
      ),
      actions: (ctx) => [
        GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx, false)),
        SignalButton(label: 'Insert', onPressed: () => Navigator.pop(ctx, true)),
      ],
    );
    if (ok != true) return;
    final r = (int.tryParse(rows.text) ?? 2).clamp(1, 50);
    final k = (int.tryParse(cols.text) ?? 2).clamp(1, 20);
    final cell = '<td style="width: ${(100 / k).toStringAsFixed(4)}%;">&nbsp;</td>';
    final body = List.generate(r, (_) => '<tr>\n${List.filled(k, cell).join('\n')}\n</tr>').join('\n');
    final table = '<table style="border-collapse: collapse; width: 100%;" border="1">\n<tbody>\n$body\n</tbody>\n</table>\n';
    if (_rich) {
      _ensureSelection();
      c.switchToHtml(insertAfterSelection: table);
      _notify('Table added in HTML mode.');
      return;
    }
    _act(() => c.insert(table));
  }

  void _toggleMode() {
    if (_rich) {
      c.switchToHtml();
      return;
    }
    final issues = c.switchToRich();
    if (issues.isNotEmpty) {
      _notify(
        'The visual editor can\'t keep this content intact (${issues.join('; ')}). It stays in HTML mode so nothing is lost.',
        error: true,
      );
    }
  }

  Future<void> _handleClipboard(HelpClipboardData data) async {
    final state = es;
    if (state == null) return;
    if (data.files.isNotEmpty) {
      for (final f in data.files) {
        try {
          final bytes = await File(f).readAsBytes();
          await _insertImageBytes(bytes, name: f.split(Platform.pathSeparator).last);
        } catch (_) {
          if (mounted) _notify('Could not read ${f.split(Platform.pathSeparator).last}.', error: true);
        }
      }
      return;
    }
    final text = data.text ?? '';
    final last = _lastCopy;
    if (last != null && text.isNotEmpty && _normNl(text) == _normNl(last.text)) {
      if (await _pasteHtml(state, last.html)) return;
    }
    if (text.trim().isNotEmpty) {
      final html = data.html;
      if (html != null && html.trim().isNotEmpty && await _pasteHtml(state, html)) return;
      await _pastePlain(state, text);
      return;
    }
    if (data.image != null) {
      await _insertImageBytes(data.image!);
      return;
    }
    final html = data.html;
    if (html != null && html.trim().isNotEmpty) await _pasteHtml(state, html);
  }

  String _normNl(String s) => s.replaceAll('\r\n', '\n').trim();

  Future<bool> _pasteHtml(EditorState state, String html) async {
    final collapsed = html.replaceAllMapped(HelpEditorController._dataSrc, (m) {
      return 'src="${c.registerInline(m.group(2)!)}"';
    });
    final decoded = HelpHtmlCodec.decode(collapsed);
    if (decoded.issues.isNotEmpty) return false;
    final nodes = decoded.nodes;
    while (nodes.isNotEmpty && (nodes.first.delta?.toPlainText().trim().isEmpty ?? false) && nodes.first.children.isEmpty) {
      nodes.removeAt(0);
    }
    while (nodes.isNotEmpty && (nodes.last.delta?.toPlainText().trim().isEmpty ?? false) && nodes.last.children.isEmpty) {
      nodes.removeLast();
    }
    if (nodes.isEmpty) return false;
    if (nodes.length == 1 && nodes.first.delta != null && nodes.first.type == HelpNodes.paragraph) {
      await state.pasteSingleLineNode(nodes.first);
    } else if (nodes.first.delta == null) {
      await state.helpInsertBlocks(nodes);
    } else if (nodes.length == 1) {
      await state.helpInsertBlocks(nodes);
    } else {
      await state.pasteMultiLineNodes(nodes);
    }
    return true;
  }

  Future<void> _pastePlain(EditorState state, String text) async {
    final lines = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    if (lines.length == 1) {
      final sel = await state.deleteSelectionIfNeeded();
      if (sel == null) return;
      final node = state.getNodeAtPath(sel.start.path);
      if (node == null || node.delta == null) return;
      final tr = state.transaction..insertText(node, sel.startIndex, lines.first);
      await state.apply(tr);
      return;
    }
    final nodes = [for (final l in lines) paragraphNode(text: l)];
    await state.pasteMultiLineNodes(nodes);
  }

  KeyEventResult _onPaste(EditorState state) {
    () async {
      final data = await HelpClipboard.read();
      await _handleClipboard(data);
    }();
    return KeyEventResult.handled;
  }

  KeyEventResult _onPastePlain(EditorState state) {
    () async {
      final data = await HelpClipboard.read();
      final text = data.text ?? '';
      if (text.isNotEmpty) await _pastePlain(state, text);
    }();
    return KeyEventResult.handled;
  }

  KeyEventResult _onCopy(EditorState state, {bool cut = false}) {
    final sel = state.selection?.normalized;
    if (sel == null || sel.isCollapsed) return KeyEventResult.ignored;
    final text = state.getTextInSelection(sel).join('\n');
    final html = HelpHtmlCodec.encode(state.getSelectedNodes(selection: sel));
    _lastCopy = (text: text, html: html);
    Clipboard.setData(ClipboardData(text: text));
    if (cut) state.deleteSelection(sel);
    return KeyEventResult.handled;
  }

  List<CommandShortcutEvent> get _commands => [
    undoCommand,
    redoCommand,
    convertToParagraphCommand,
    backspaceCommand,
    deleteLeftWordCommand,
    deleteLeftSentenceCommand,
    deleteCommand,
    deleteRightWordCommand,
    ...arrowLeftKeys,
    ...arrowRightKeys,
    ...arrowUpKeys,
    ...arrowDownKeys,
    homeCommand,
    endCommand,
    ...toggleMarkdownCommands,
    pageUpCommand,
    pageDownCommand,
    selectAllCommand,
    CommandShortcutEvent(
      key: 'help paste',
      getDescription: () => 'Paste',
      command: 'ctrl+v',
      macOSCommand: 'cmd+v',
      handler: _onPaste,
    ),
    CommandShortcutEvent(
      key: 'help paste plain',
      getDescription: () => 'Paste as plain text',
      command: 'ctrl+shift+v',
      macOSCommand: 'cmd+shift+v',
      handler: _onPastePlain,
    ),
    CommandShortcutEvent(
      key: 'help copy',
      getDescription: () => 'Copy',
      command: 'ctrl+c',
      macOSCommand: 'cmd+c',
      handler: (s) => _onCopy(s),
    ),
    CommandShortcutEvent(
      key: 'help cut',
      getDescription: () => 'Cut',
      command: 'ctrl+x',
      macOSCommand: 'cmd+x',
      handler: (s) => _onCopy(s, cut: true),
    ),
    CommandShortcutEvent(
      key: 'help indent',
      getDescription: () => 'Indent',
      command: 'tab',
      handler: (s) {
        s.helpIndent(true);
        return KeyEventResult.handled;
      },
    ),
    CommandShortcutEvent(
      key: 'help outdent',
      getDescription: () => 'Outdent',
      command: 'shift+tab',
      handler: (s) {
        s.helpIndent(false);
        return KeyEventResult.handled;
      },
    ),
    CommandShortcutEvent(
      key: 'help link',
      getDescription: () => 'Insert link',
      command: 'ctrl+k',
      macOSCommand: 'cmd+k',
      handler: (s) {
        _link();
        return KeyEventResult.handled;
      },
    ),
  ];

  static Map<String, dynamic> _carry(Node node) {
    final out = <String, dynamic>{};
    for (final k in [HelpNodes.style, HelpNodes.align, HelpNodes.indent, HelpNodes.pWrapped, HelpNodes.pStyle]) {
      final v = node.attributes[k];
      if (v != null) out[k] = v;
    }
    final tag = node.attributes[HelpNodes.tag];
    if (tag == 'p' || tag == 'div' || tag == '') out[HelpNodes.tag] = tag == '' ? 'p' : tag;
    return out;
  }

  static final CharacterShortcutEvent _newline = CharacterShortcutEvent(
    key: 'help newline',
    character: '\n',
    handler: (state) async {
      if (HardwareKeyboard.instance.isShiftPressed) return false;
      final sel = state.selection;
      if (sel == null) return false;
      if (!sel.isCollapsed) await state.deleteSelection(sel);
      final s = state.selection;
      if (s == null) return false;
      final node = state.getNodeAtPath(s.end.path);
      if (node == null || node.delta == null) return false;
      if (HelpNodes.isList(node.type)) {
        return insertNewLineInType(state, node.type, attributes: {
          if (node.attributes[HelpNodes.pWrapped] == true) HelpNodes.pWrapped: true,
          if (node.attributes[HelpNodes.style] != null) HelpNodes.style: node.attributes[HelpNodes.style],
          if (node.attributes[HelpNodes.pStyle] != null) HelpNodes.pStyle: node.attributes[HelpNodes.pStyle],
        });
      }
      if (node.type == HelpNodes.heading) {
        await state.insertNewLine(position: s.start);
        return true;
      }
      final carry = _carry(node);
      await state.insertNewLine(
        position: s.start,
        nodeBuilder: (n) => n.copyWith(attributes: {...n.attributes, ...carry}),
      );
      return true;
    },
  );

  Widget _btn(IconData icon, String tip, VoidCallback onTap, {bool active = false}) {
    return Tooltip(
      message: tip,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        canRequestFocus: false,
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: active ? const Color(0xFFFFF4EA) : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(icon, size: 18, color: active ? Brand.signal : const Color(0xFF222F3E)),
        ),
      ),
    );
  }

  Widget _menu<T>(
    Widget child,
    String tip,
    List<PopupMenuEntry<T>> items,
    void Function(T) onSelected,
  ) {
    return PopupMenuButton<T>(
      tooltip: tip,
      onSelected: onSelected,
      itemBuilder: (_) => items,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: child,
      ),
    );
  }

  Widget _label(String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(text, style: const TextStyle(fontSize: 13.5, color: Color(0xFF222F3E))),
      const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFF222F3E)),
    ],
  );

  void _applyColor(String property, String value) {
    if (_rich) {
      final key = property == 'color' ? 'font_color' : 'bg_color';
      _rich1((s) => s.helpFormatInline({key: value.isEmpty ? null : value.toLowerCase()}));
      return;
    }
    _act(() {
      if (value.isEmpty) {
        c.removeFormat();
      } else {
        c.wrap('<span style="$property: ${value.toLowerCase()};">', '</span>');
      }
    });
  }

  Widget _colorMenu(IconData icon, String tip, String property) {
    return PopupMenuButton<String>(
      tooltip: tip,
      onSelected: (v) => _applyColor(property, v),
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          enabled: false,
          child: SizedBox(
            width: 170,
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final hex in _kColorMap)
                  InkWell(
                    onTap: () => Navigator.pop(context, hex),
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: Color(int.parse('FF${hex.substring(1)}', radix: 16)),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: const Color(0xFFCCCCCC)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const PopupMenuItem<String>(value: '', child: Text('Remove color')),
      ],
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 18, color: const Color(0xFF222F3E)),
      ),
    );
  }

  bool _inlineActive(String key) {
    final state = es;
    final sel = state?.selection;
    if (state == null || sel == null) return false;
    if (sel.isCollapsed) {
      final toggled = state.toggledStyle[key];
      if (toggled is bool) return toggled;
      if (sel.startIndex == 0) return false;
      final node = state.getNodeAtPath(sel.start.path);
      final delta = node?.delta;
      if (delta == null) return false;
      return delta.sliceAttributes(sel.startIndex)?[key] == true;
    }
    final nodes = state.getNodesInSelection(sel);
    return nodes.allSatisfyInSelection(sel, (delta) {
      return delta.everyAttributes((a) => a[key] == true);
    });
  }

  void _bold() => _rich ? _rich1((s) => s.toggleAttribute('bold')) : _act(() => c.wrap('<strong>', '</strong>'));
  void _italic() => _rich ? _rich1((s) => s.toggleAttribute('italic')) : _act(() => c.wrap('<em>', '</em>'));
  void _underline() => _rich
      ? _rich1((s) => s.toggleAttribute('underline'))
      : _act(() => c.wrap('<span style="text-decoration: underline;">', '</span>'));

  void _align(String v) => _rich ? _rich1((s) => s.helpSetAlign(v)) : _act(() => c.blockStyle('text-align', v));

  Widget _toolbar() {
    const sep = SizedBox(
      height: 22,
      child: VerticalDivider(width: 12, color: Color(0xFFE3E3E3)),
    );
    final toolbar = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _btn(Icons.undo, 'Undo', () => _rich ? es?.undoManager.undo() : _act(c.undo.undo)),
        _btn(Icons.redo, 'Redo', () => _rich ? es?.undoManager.redo() : _act(c.undo.redo)),
        sep,
        _menu<String>(
          _label('Blocks'),
          'Blocks',
          const [
            PopupMenuItem(value: 'p', child: Text('Paragraph')),
            PopupMenuItem(value: 'h1', child: Text('Heading 1', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700))),
            PopupMenuItem(value: 'h2', child: Text('Heading 2', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700))),
            PopupMenuItem(value: 'h3', child: Text('Heading 3', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
            PopupMenuItem(value: 'h4', child: Text('Heading 4', style: TextStyle(fontWeight: FontWeight.w700))),
            PopupMenuItem(value: 'h5', child: Text('Heading 5', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
            PopupMenuItem(value: 'h6', child: Text('Heading 6', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
            PopupMenuItem(value: 'pre', child: Text('Preformatted', style: TextStyle(fontFamily: 'monospace'))),
          ],
          (v) => _rich ? _rich1((s) => s.helpSetBlock(v)) : _act(() => c.block(v)),
        ),
        _menu<String>(
          _label('Font Size'),
          'Font Size',
          [
            for (final s in const ['12', '14', '16', '18', '20', '24', '30', '36', '48'])
              PopupMenuItem(value: s, child: Text(s)),
          ],
          (v) => _rich
              ? _rich1((s) => s.helpFormatInline({'font_size': double.parse(v)}))
              : _act(() => c.wrap('<span style="font-size: ${v}px;">', '</span>')),
        ),
        sep,
        _btn(Icons.format_bold, 'Bold', _bold, active: _rich && _inlineActive('bold')),
        _btn(Icons.format_italic, 'Italic', _italic, active: _rich && _inlineActive('italic')),
        _btn(Icons.format_underline, 'Underline', _underline, active: _rich && _inlineActive('underline')),
        _colorMenu(Icons.format_color_text, 'Text color', 'color'),
        _colorMenu(Icons.format_color_fill, 'Background color', 'background-color'),
        sep,
        _btn(Icons.format_align_left, 'Align left', () => _align('left')),
        _btn(Icons.format_align_center, 'Align center', () => _align('center')),
        _btn(Icons.format_align_right, 'Align right', () => _align('right')),
        _btn(Icons.format_align_justify, 'Justify', () => _align('justify')),
        sep,
        _btn(Icons.format_list_bulleted, 'Bullet list', () => _rich ? _rich1((s) => s.helpToggleList(false)) : _act(() => c.list(false))),
        _btn(Icons.format_list_numbered, 'Numbered list', () => _rich ? _rich1((s) => s.helpToggleList(true)) : _act(() => c.list(true))),
        _btn(Icons.format_indent_decrease, 'Decrease indent', () => _rich ? _rich1((s) => s.helpIndent(false)) : _act(() => c.indent(false))),
        _btn(Icons.format_indent_increase, 'Increase indent', () => _rich ? _rich1((s) => s.helpIndent(true)) : _act(() => c.indent(true))),
        sep,
        _btn(Icons.link, 'Insert/edit link', _link),
        _menu<String>(
          const Icon(Icons.image_outlined, size: 18, color: Color(0xFF222F3E)),
          'Insert/edit image',
          const [
            PopupMenuItem(value: 'upload', child: Text('Upload image…')),
            PopupMenuItem(value: 'url', child: Text('Image from URL…')),
          ],
          (v) => v == 'upload' ? _uploadImage() : _imageFromUrl(),
        ),
        _menu<String>(
          const Icon(Icons.smart_display_outlined, size: 18, color: Color(0xFF222F3E)),
          'Insert video',
          const [
            PopupMenuItem(value: 'upload', child: ListTile(dense: true, leading: Icon(Icons.upload), title: Text('Upload video file…'))),
            PopupMenuItem(value: 'link', child: ListTile(dense: true, leading: Icon(Icons.link), title: Text('Video from link…'))),
          ],
          (v) => v == 'upload' ? _uploadVideo() : _videoFromLink(),
        ),
        _btn(Icons.table_chart_outlined, 'Table', _table),
        sep,
        _btn(Icons.format_clear, 'Clear formatting', () => _rich ? _rich1((s) => s.helpClearFormatting()) : _act(c.removeFormat)),
        _btn(Icons.visibility_outlined, 'Preview', () => setState(() => _preview = !_preview), active: _preview),
        _btn(Icons.code, _rich ? 'Source code (HTML)' : 'Back to the visual editor', _toggleMode, active: !_rich),
      ],
    );
    final state = es;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE3E3E3))),
      ),
      child: _rich && state != null
          ? ValueListenableBuilder<Selection?>(
              valueListenable: state.selectionNotifier,
              builder: (_, _, _) => ValueListenableBuilder<Attributes>(
                valueListenable: state.toggledStyleNotifier,
                builder: (_, _, _) => toolbar,
              ),
            )
          : toolbar,
    );
  }

  Future<void> _onSourcePaste() async {
    final data = await HelpClipboard.read();
    final text = data.text ?? '';
    if (text.isNotEmpty) {
      _act(() => c.insert(text.replaceAll('\r\n', '\n')));
      return;
    }
    if (data.files.isNotEmpty) {
      for (final f in data.files) {
        try {
          await _insertImageBytes(await File(f).readAsBytes(), name: f.split(Platform.pathSeparator).last);
        } catch (_) {}
      }
      return;
    }
    if (data.image != null) await _insertImageBytes(data.image!);
  }

  Widget _sourceField() {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyV, control: true): _SourcePasteIntent(),
        SingleActivator(LogicalKeyboardKey.keyV, meta: true): _SourcePasteIntent(),
      },
      child: Actions(
        actions: {
          _SourcePasteIntent: CallbackAction<_SourcePasteIntent>(
            onInvoke: (_) {
              _onSourcePaste();
              return null;
            },
          ),
        },
        child: _sourceTextField(),
      ),
    );
  }

  Widget _sourceTextField() {
    return TextField(
      controller: c.source,
      undoController: c.undo,
      focusNode: _focus,
      autofocus: widget.autofocus,
      expands: true,
      maxLines: null,
      minLines: null,
      keyboardType: TextInputType.multiline,
      textAlignVertical: TextAlignVertical.top,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.5),
      decoration: const InputDecoration(
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        contentPadding: EdgeInsets.all(12),
        hintText: 'Write the document here…',
      ),
    );
  }

  Widget _richEditor(EditorState state) {
    final editor = AppFlowyEditor(
      key: ValueKey('help-editor-${c.generation}'),
      editorState: state,
      blockComponentBuilders: helpBlockBuilders(_scope),
      commandShortcutEvents: _commands,
      characterShortcutEvents: [_newline],
      editorStyle: helpEditorStyle(),
      autoFocus: widget.autofocus,
      header: const SizedBox(height: 14),
      footer: const SizedBox(height: 48),
    );
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (details) async {
        setState(() => _dragging = false);
        final paths = [
          for (final f in details.files)
            if (helpIsImagePath(f.path) || helpIsImagePath(f.name)) f,
        ];
        if (paths.isEmpty) {
          if (details.files.isNotEmpty) _notify('Only image files can be dropped here.', error: true);
          return;
        }
        for (final f in paths) {
          try {
            await _insertImageBytes(await f.readAsBytes(), name: f.name);
          } catch (_) {
            if (mounted) _notify('Could not read ${f.name}.', error: true);
          }
        }
      },
      child: Stack(
        children: [
          Positioned.fill(child: editor),
          if (_dragging)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0x14FF7D00),
                    border: Border.all(color: Brand.signal, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'Drop images to add them here',
                    style: TextStyle(fontWeight: FontWeight.w600, color: Brand.signal),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _banner({required String text, required bool error, double? progress, Widget? action}) {
    return Container(
      color: error ? const Color(0xFFFDECEC) : const Color(0xFFEFF6FF),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 13,
                    color: error ? Brand.danger : const Color(0xFF1E3A8A),
                  ),
                ),
              ),
              ?action,
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(value: progress, color: Brand.signal),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, box) {
        const minHeight = 320.0;
        final body = _body();
        if (!box.maxHeight.isFinite || box.maxHeight >= minHeight) return body;
        return SingleChildScrollView(
          child: SizedBox(height: minHeight, child: body),
        );
      },
    );
  }

  Widget _body() {
    final state = es;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFDEE2E6)),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _toolbar(),
          if (!_rich && c.htmlReasons.isNotEmpty)
            Container(
              color: const Color(0xFFFFF8E1),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                'Opened in HTML mode: this document contains content the visual editor can\'t keep intact (${c.htmlReasons.join('; ')}). Edit the HTML directly — it is saved exactly as written.',
                style: const TextStyle(fontSize: 13, color: Color(0xFF7A5B00)),
              ),
            ),
          if (_status != null) _banner(text: _status!, error: _statusError, progress: _progress),
          Expanded(
            child: LayoutBuilder(
              builder: (ctx, box) {
                if (_preview) {
                  return HelpHtmlPreview(controller: c, helpApi: widget.helpApi);
                }
                if (_rich && state != null) return _richEditor(state);
                final split = box.maxWidth >= 900;
                if (!split) return _sourceField();
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _sourceField()),
                    const VerticalDivider(width: 1, color: Color(0xFFE3E3E3)),
                    Expanded(
                      child: HelpHtmlPreview(controller: c, helpApi: widget.helpApi),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SourcePasteIntent extends Intent {
  const _SourcePasteIntent();
}

class _HNode {
  _HNode(this.tag, this.attrs);
  final String tag;
  final Map<String, String> attrs;
  final List<Object> children = [];
}

const _kVoid = {'img', 'br', 'hr', 'source', 'input', 'meta', 'link', 'col', 'wbr'};
const _kBlocks = {
  'p', 'div', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'ul', 'ol', 'li', 'table',
  'thead', 'tbody', 'tfoot', 'tr', 'td', 'th', 'blockquote', 'pre', 'figure',
  'figcaption', 'hr', 'video', 'iframe', 'section', 'article', 'header',
  'footer', 'center', 'caption',
};

final _kTagRe = RegExp(
  r'''<!--[\s\S]*?-->|<(/?)([a-zA-Z][a-zA-Z0-9]*)((?:[^>"']|"[^"]*"|'[^']*')*)>|[^<]+|<''',
);
final _kAttrRe = RegExp(
  r'''([a-zA-Z_:][-a-zA-Z0-9_:.]*)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+)))?''',
);

String _decodeEntities(String s) => s.replaceAllMapped(
  RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);'),
  (m) {
    final e = m.group(1)!;
    if (e.startsWith('#x') || e.startsWith('#X')) {
      final v = int.tryParse(e.substring(2), radix: 16);
      return v == null ? m.group(0)! : String.fromCharCode(v);
    }
    if (e.startsWith('#')) {
      final v = int.tryParse(e.substring(1));
      return v == null ? m.group(0)! : String.fromCharCode(v);
    }
    const named = {
      'nbsp': ' ', 'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"',
      'apos': "'", 'hellip': '…', 'mdash': '—', 'ndash': '–', 'copy': '©',
      'reg': '®', 'rsquo': '’', 'lsquo': '‘', 'rdquo': '”', 'ldquo': '“',
      'bull': '•', 'middot': '·', 'trade': '™', 'rarr': '→', 'larr': '←',
    };
    return named[e.toLowerCase()] ?? m.group(0)!;
  },
);

_HNode _parseHtml(String html) {
  final root = _HNode('#root', const {});
  final stack = <_HNode>[root];
  for (final m in _kTagRe.allMatches(html)) {
    final s = m.group(0)!;
    if (s.startsWith('<!--')) continue;
    final tag = m.group(2)?.toLowerCase();
    if (tag == null) {
      stack.last.children.add(_decodeEntities(s));
      continue;
    }
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
    for (final a in _kAttrRe.allMatches(m.group(3) ?? '')) {
      attrs[a.group(1)!.toLowerCase()] = _decodeEntities(
        a.group(2) ?? a.group(3) ?? a.group(4) ?? '',
      );
    }
    final node = _HNode(tag, attrs);
    stack.last.children.add(node);
    if (!_kVoid.contains(tag) && !(m.group(3) ?? '').trim().endsWith('/')) {
      stack.add(node);
    }
  }
  return root;
}

Map<String, String> _styleOf(_HNode n) => parseCss(n.attrs['style']);

double? _cssPx(String? v) {
  if (v == null) return null;
  final m = RegExp(r'([\d.]+)\s*(px|pt|em|rem)?').firstMatch(v);
  if (m == null) return null;
  final n = double.tryParse(m.group(1)!);
  if (n == null) return null;
  switch (m.group(2)) {
    case 'pt':
      return n * 4 / 3;
    case 'em':
    case 'rem':
      return n * 16;
    default:
      return n;
  }
}

class HelpHtmlPreview extends StatefulWidget {
  const HelpHtmlPreview({super.key, required this.controller, required this.helpApi});
  final HelpEditorController controller;
  final AdminHelpApi helpApi;

  @override
  State<HelpHtmlPreview> createState() => _HelpHtmlPreviewState();
}

class _HelpHtmlPreviewState extends State<HelpHtmlPreview> {
  Timer? _debounce;
  late _HNode _root;

  @override
  void initState() {
    super.initState();
    _root = _parseHtml(widget.controller.collapsedHtml);
    widget.controller.source.addListener(_changed);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.source.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _root = _parseHtml(widget.controller.collapsedHtml));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: LayoutBuilder(
        builder: (ctx, box) => SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: _HtmlRenderer(
            controller: widget.controller,
            baseUrl: widget.helpApi.api.baseUrl,
            headers: widget.helpApi.api.authHeaders(),
            width: box.maxWidth - 24,
          ).render(_root),
        ),
      ),
    );
  }
}

class _InlineStyle {
  const _InlineStyle({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.color,
    this.bg,
    this.size = 16,
    this.href,
    this.mono = false,
    this.align = TextAlign.start,
  });

  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;
  final Color? color;
  final Color? bg;
  final double size;
  final String? href;
  final bool mono;
  final TextAlign align;

  _InlineStyle copy({
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strike,
    Color? color,
    Color? bg,
    double? size,
    String? href,
    bool? mono,
    TextAlign? align,
  }) => _InlineStyle(
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    underline: underline ?? this.underline,
    strike: strike ?? this.strike,
    color: color ?? this.color,
    bg: bg ?? this.bg,
    size: size ?? this.size,
    href: href ?? this.href,
    mono: mono ?? this.mono,
    align: align ?? this.align,
  );

  TextStyle get text => TextStyle(
    fontSize: size,
    height: 1.6,
    fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
    fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    fontFamily: mono ? 'monospace' : null,
    color: href != null ? kHelpLinkColor : (color ?? kHelpTextColor),
    backgroundColor: bg,
    decoration: TextDecoration.combine([
      if (underline || href != null) TextDecoration.underline,
      if (strike) TextDecoration.lineThrough,
    ]),
  );
}

class _HtmlRenderer {
  _HtmlRenderer({
    required this.controller,
    required this.baseUrl,
    required this.headers,
    required this.width,
  });

  final HelpEditorController controller;
  final String baseUrl;
  final Map<String, String> headers;
  final double width;

  Widget render(_HNode root) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: _blocks(root, const _InlineStyle(), width),
  );

  _InlineStyle _apply(_HNode n, _InlineStyle st) {
    final css = _styleOf(n);
    var s = st;
    switch (n.tag) {
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
      case 'a':
        s = s.copy(href: n.attrs['href'] ?? '');
      case 'code':
      case 'pre':
        s = s.copy(mono: true);
      case 'h1':
        s = s.copy(size: 32, bold: true);
      case 'h2':
        s = s.copy(size: 24, bold: true);
      case 'h3':
        s = s.copy(size: 18.7, bold: true);
      case 'h4':
        s = s.copy(size: 16, bold: true);
      case 'h5':
        s = s.copy(size: 13.3, bold: true);
      case 'h6':
        s = s.copy(size: 10.7, bold: true);
      case 'font':
        s = s.copy(color: helpCssColor(n.attrs['color']));
    }
    if (css['font-weight'] != null) {
      final fw = css['font-weight']!;
      s = s.copy(bold: fw == 'bold' || (int.tryParse(fw) ?? 400) >= 600);
    }
    if (css['font-style'] == 'italic') s = s.copy(italic: true);
    final deco = css['text-decoration'] ?? css['text-decoration-line'] ?? '';
    if (deco.contains('underline')) s = s.copy(underline: true);
    if (deco.contains('line-through')) s = s.copy(strike: true);
    final color = helpCssColor(css['color']);
    if (color != null) s = s.copy(color: color);
    final bg = helpCssColor(css['background-color'] ?? css['background']);
    if (bg != null) s = s.copy(bg: bg);
    final size = _cssPx(css['font-size']);
    if (size != null && size > 4 && size < 120) s = s.copy(size: size);
    switch (css['text-align'] ?? n.attrs['align']) {
      case 'center':
        s = s.copy(align: TextAlign.center);
      case 'right':
        s = s.copy(align: TextAlign.right);
      case 'justify':
        s = s.copy(align: TextAlign.justify);
      case 'left':
        s = s.copy(align: TextAlign.left);
    }
    return s;
  }

  String? _resolve(String src) {
    if (src.isEmpty) return null;
    if (src.startsWith('tp-inline-image-')) return controller.inlineData(src);
    if (src.startsWith('data:') || RegExp(r'^https?://').hasMatch(src)) return src;
    if (src.startsWith('//')) return 'https:$src';
    return '$baseUrl/${src.replaceFirst(RegExp(r'^/+'), '')}';
  }

  Widget _image(_HNode n, double maxW) {
    final raw = n.attrs['src'] ?? '';
    final src = _resolve(raw);
    final css = _styleOf(n);
    final w = _cssPx(css['width']) ?? double.tryParse(n.attrs['width'] ?? '');
    final h = double.tryParse(n.attrs['height'] ?? '');
    final boxW = w == null ? null : math.min(w, maxW);
    final boxH = (w != null && h != null && w > 0) ? boxW! * h / w : null;
    Widget broken() => Container(
      width: boxW ?? 240,
      height: boxH ?? 120,
      color: const Color(0xFFF8F9FA),
      alignment: Alignment.center,
      child: const Text('Image not found', style: TextStyle(color: Color(0xFF777777), fontSize: 13)),
    );
    if (src == null) return broken();
    Widget img;
    if (raw.startsWith('tp-inline-image-')) {
      final mem = controller.inlineImage(raw);
      if (mem == null) return broken();
      img = Image(image: mem, width: boxW, height: boxH, fit: BoxFit.contain, errorBuilder: (_, _, _) => broken());
    } else if (src.startsWith('data:')) {
      final comma = src.indexOf(',');
      Uint8List? bytes;
      try {
        bytes = base64Decode(src.substring(comma + 1));
      } catch (_) {}
      if (bytes == null) return broken();
      img = Image.memory(bytes, width: boxW, height: boxH, fit: BoxFit.contain, errorBuilder: (_, _, _) => broken());
    } else {
      img = Image.network(src, headers: headers, width: boxW, height: boxH, fit: BoxFit.contain, errorBuilder: (_, _, _) => broken());
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxW),
      child: ClipRRect(borderRadius: BorderRadius.circular(8), child: img),
    );
  }

  Widget _media(_HNode n, double maxW) {
    var src = n.attrs['src'] ?? '';
    if (src.isEmpty) {
      for (final c in n.children) {
        if (c is _HNode && c.tag == 'source') {
          src = c.attrs['src'] ?? '';
          break;
        }
      }
    }
    final w = math.min(double.tryParse(n.attrs['width'] ?? '') ?? maxW, maxW);
    final hAttr = double.tryParse(n.attrs['height'] ?? '');
    final wAttr = double.tryParse(n.attrs['width'] ?? '');
    final h = (hAttr != null && wAttr != null && wAttr > 0) ? w * hAttr / wAttr : w * 9 / 16;
    final url = _resolve(src) ?? src;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: InkWell(
          onTap: url.isEmpty ? null : () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          child: Container(
            width: w,
            height: math.max(90, h),
            decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)),
            alignment: Alignment.center,
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(n.tag == 'video' ? Icons.play_circle_outline : Icons.smart_display_outlined, color: Colors.white, size: 42),
                const SizedBox(height: 8),
                Text(
                  url,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _inline(_HNode n, _InlineStyle st, List<InlineSpan> out, double maxW) {
    for (final c in n.children) {
      if (c is String) {
        final t = st.mono ? c : c.replaceAll(RegExp(r'[ \t\r\n\f]+'), ' ');
        if (t.isNotEmpty) out.add(TextSpan(text: t, style: st.text));
        continue;
      }
      final e = c as _HNode;
      if (e.tag == 'br') {
        out.add(TextSpan(text: '\n', style: st.text));
      } else if (e.tag == 'img') {
        out.add(WidgetSpan(alignment: PlaceholderAlignment.bottom, child: _image(e, maxW)));
      } else if (e.tag == 'script' || e.tag == 'style') {
        continue;
      } else {
        final s = _apply(e, st);
        if (e.tag == 'a' && (e.attrs['href'] ?? '').isNotEmpty) {
          final inner = <InlineSpan>[];
          _inline(e, s, inner, maxW);
          final href = e.attrs['href']!;
          out.add(WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication),
                child: Text.rich(TextSpan(children: inner)),
              ),
            ),
          ));
        } else {
          _inline(e, s, out, maxW);
        }
      }
    }
  }

  List<Widget> _blocks(_HNode n, _InlineStyle st, double maxW) {
    final out = <Widget>[];
    final pending = <InlineSpan>[];

    void flush() {
      if (pending.isEmpty) return;
      final spans = List<InlineSpan>.from(pending);
      pending.clear();
      final plain = spans.every((s) => s is TextSpan && (s.text ?? '').trim().isEmpty);
      if (plain) return;
      out.add(Text.rich(TextSpan(children: spans), textAlign: st.align));
    }

    for (final c in n.children) {
      if (c is String || !_kBlocks.contains((c as _HNode).tag)) {
        final holder = _HNode('#span', const {})..children.add(c);
        _inline(holder, st, pending, maxW);
        continue;
      }
      flush();
      final e = c;
      final s = _apply(e, st);
      final css = _styleOf(e);
      final pad = _cssPx(css['padding-left']) ?? _cssPx(css['margin-left']) ?? 0;
      switch (e.tag) {
        case 'hr':
          out.add(const Divider(height: 24));
        case 'video':
        case 'iframe':
          out.add(_media(e, maxW));
        case 'ul':
        case 'ol':
          var i = 0;
          final items = <Widget>[];
          for (final li in e.children.whereType<_HNode>()) {
            if (li.tag != 'li') continue;
            i++;
            final marker = e.tag == 'ol' ? '$i.' : '•';
            items.add(Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 26, child: Text(marker, style: s.text)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _blocks(li, _apply(li, s), maxW - 26 - pad),
                  ),
                ),
              ],
            ));
          }
          out.add(Padding(
            padding: EdgeInsets.only(left: 14 + pad, bottom: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: items),
          ));
        case 'table':
          final rows = <_HNode>[];
          void collect(_HNode x) {
            for (final k in x.children.whereType<_HNode>()) {
              if (k.tag == 'tr') {
                rows.add(k);
              } else if (k.tag == 'tbody' || k.tag == 'thead' || k.tag == 'tfoot') {
                collect(k);
              }
            }
          }
          collect(e);
          final cols = rows.fold<int>(0, (m, r) => math.max(m, r.children.whereType<_HNode>().where((x) => x.tag == 'td' || x.tag == 'th').length));
          if (cols == 0) break;
          final cellW = (maxW - pad) / cols;
          out.add(Padding(
            padding: EdgeInsets.only(left: pad, bottom: 12),
            child: Table(
              border: TableBorder.all(color: const Color(0xFFBFBFBF)),
              children: [
                for (final r in rows)
                  TableRow(children: [
                    for (var k = 0; k < cols; k++)
                      Builder(builder: (_) {
                        final cells = r.children.whereType<_HNode>().where((x) => x.tag == 'td' || x.tag == 'th').toList();
                        if (k >= cells.length) return const SizedBox();
                        return Padding(
                          padding: const EdgeInsets.all(6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: _blocks(cells[k], _apply(cells[k], s), cellW - 12),
                          ),
                        );
                      }),
                  ]),
              ],
            ),
          ));
        case 'blockquote':
          out.add(Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.only(left: 12),
            decoration: const BoxDecoration(border: Border(left: BorderSide(color: Color(0xFFCCCCCC), width: 3))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _blocks(e, s, maxW - 15)),
          ));
        default:
          final inner = _blocks(e, s, maxW - pad);
          final isP = e.tag == 'p' || e.tag.startsWith('h') || e.tag == 'pre';
          out.add(Padding(
            padding: EdgeInsets.only(left: pad, bottom: isP ? 12 : 0),
            child: inner.isEmpty
                ? SizedBox(height: isP ? s.size * 0.6 : 0)
                : Column(
                    crossAxisAlignment: s.align == TextAlign.center
                        ? CrossAxisAlignment.center
                        : s.align == TextAlign.right
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.stretch,
                    children: inner,
                  ),
          ));
      }
    }
    flush();
    return out;
  }
}
