import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'help_html.dart';
import 'premium.dart';

enum HtmlTool {
  heading,
  bold,
  italic,
  underline,
  strikethrough,
  fontSize,
  textColor,
  highlight,
  align,
  bulletList,
  numberList,
  indent,
  outdent,
  link,
  horizontalRule,
  clear,
}

const List<HtmlTool> kRichTextTools = [
  HtmlTool.heading,
  HtmlTool.bold,
  HtmlTool.italic,
  HtmlTool.underline,
  HtmlTool.fontSize,
  HtmlTool.textColor,
  HtmlTool.highlight,
  HtmlTool.align,
  HtmlTool.bulletList,
  HtmlTool.numberList,
  HtmlTool.indent,
  HtmlTool.outdent,
  HtmlTool.link,
  HtmlTool.clear,
];

const List<String> kHtmlFontSizes = [
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

class HtmlEditOps {
  HtmlEditOps(this.controller, this.onChanged);

  final TextEditingController controller;
  final VoidCallback? onChanged;

  ({int start, int end}) range() {
    final selection = controller.selection;
    final length = controller.text.length;
    if (!selection.isValid) return (start: length, end: length);
    return (
      start: selection.start.clamp(0, length),
      end: selection.end.clamp(0, length),
    );
  }

  String selectedText() {
    final r = range();
    return controller.text.substring(r.start, r.end);
  }

  void replace(int start, int end, String value, {int? caret}) {
    final text = controller.text;
    final next = text.replaceRange(start, end, value);
    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: caret ?? start + value.length),
    );
    onChanged?.call();
  }

  void wrapSelection(String open, String close, String placeholder) {
    final r = range();
    final selected = controller.text.substring(r.start, r.end);
    final body = selected.isEmpty ? placeholder : selected;
    replace(
      r.start,
      r.end,
      '$open$body$close',
      caret: selected.isEmpty
          ? r.start + open.length + body.length
          : r.start + open.length + body.length + close.length,
    );
  }

  void insertBlock(String html) {
    final r = range();
    final before = controller.text.substring(0, r.start);
    final needsLead = before.isNotEmpty && !before.endsWith('\n');
    replace(r.start, r.end, '${needsLead ? '\n' : ''}$html\n');
  }

  void applyBlock(String tag, {String style = '', String placeholder = ''}) {
    final r = range();
    final selected = controller.text.substring(r.start, r.end).trim();
    final body = selected.isEmpty ? placeholder : selected;
    final attrs = style.isEmpty ? '' : ' style="$style"';
    insertBlockAt(r, '<$tag$attrs>$body</$tag>');
  }

  void applyList(String tag) {
    final r = range();
    final selected = controller.text.substring(r.start, r.end);
    final lines = selected
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final items = lines.isEmpty ? ['First item'] : lines;
    final body = items.map((line) => '  <li>$line</li>').join('\n');
    insertBlockAt(r, '<$tag>\n$body\n</$tag>');
  }

  void insertBlockAt(({int start, int end}) r, String html) {
    final before = controller.text.substring(0, r.start);
    final needsLead = before.isNotEmpty && !before.endsWith('\n');
    replace(r.start, r.end, '${needsLead ? '\n' : ''}$html\n');
  }

  bool clearFormatting() {
    final r = range();
    if (r.start == r.end) return false;
    final selected = controller.text.substring(r.start, r.end);
    replace(r.start, r.end, helpHtmlToPlain(selected));
    return true;
  }
}

class HtmlSourceEditor extends StatefulWidget {
  const HtmlSourceEditor({
    super.key,
    required this.controller,
    required this.colorPresets,
    this.tools = kRichTextTools,
    this.extraTools,
    this.enabled = true,
    this.busy = false,
    this.onChanged,
    this.height = 280,
    this.hintText = '<p>Write here…</p>',
    this.footnote,
    this.mediaHeaders = const {},
  });

  final TextEditingController controller;
  final List<String> colorPresets;
  final List<HtmlTool> tools;
  final List<Widget> Function(HtmlEditOps ops, bool enabled)? extraTools;
  final bool enabled;
  final bool busy;
  final VoidCallback? onChanged;
  final double height;
  final String hintText;
  final String? footnote;
  final Map<String, String> mediaHeaders;

  @override
  State<HtmlSourceEditor> createState() => _HtmlSourceEditorState();
}

class _HtmlSourceEditorState extends State<HtmlSourceEditor> {
  bool _preview = false;
  late final HtmlEditOps _ops;

  @override
  void initState() {
    super.initState();
    _ops = HtmlEditOps(widget.controller, widget.onChanged);
    widget.controller.addListener(_onText);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  void _onText() {
    if (mounted) setState(() {});
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<String?> _sheet(String title, List<(String, String)> options) {
    return showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(title, style: Theme.of(ctx).textTheme.titleSmall),
              ),
              for (final option in options)
                ListTile(
                  title: Text(option.$2),
                  onTap: () => Navigator.of(ctx).pop(option.$1),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _headingMenu() async {
    final choice = await _sheet('Text style', const [
      ('h1', 'Heading 1'),
      ('h2', 'Heading 2'),
      ('h3', 'Heading 3'),
      ('p', 'Paragraph'),
    ]);
    if (choice == null || !mounted) return;
    _ops.applyBlock(
      choice,
      placeholder: choice == 'p' ? 'Paragraph text' : 'Heading',
    );
  }

  Future<void> _alignMenu() async {
    final choice = await _sheet('Alignment', const [
      ('left', 'Align left'),
      ('center', 'Align centre'),
      ('right', 'Align right'),
      ('justify', 'Justify'),
    ]);
    if (choice == null || !mounted) return;
    _ops.applyBlock(
      'p',
      style: 'text-align:$choice',
      placeholder: 'Paragraph text',
    );
  }

  Future<void> _fontSizeMenu() async {
    final choice = await _sheet('Font size', [
      for (final size in kHtmlFontSizes) (size, size),
    ]);
    if (choice == null || !mounted) return;
    _ops.wrapSelection(
      '<span style="font-size:$choice">',
      '</span>',
      'sized text',
    );
  }

  Future<void> _insertColor(bool highlight) async {
    final picked = await showAppColorPicker(
      context,
      highlight ? '#FFF3C4' : '#0C233E',
      presets: widget.colorPresets,
      title: highlight ? 'Highlight colour' : 'Text colour',
    );
    if (picked == null || !mounted) return;
    final property = highlight ? 'background-color' : 'color';
    _ops.wrapSelection(
      '<span style="$property:$picked">',
      '</span>',
      highlight ? 'highlighted text' : 'coloured text',
    );
  }

  Future<void> _insertLink() async {
    final r = _ops.range();
    final selected = widget.controller.text.substring(r.start, r.end);
    final label = TextEditingController(text: helpHtmlToPlain(selected));
    final url = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Insert link'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: label,
              decoration: const InputDecoration(labelText: 'Text to show'),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: url,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Link address',
                hintText: 'https://',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Insert'),
          ),
        ],
      ),
    );
    final href = url.text.trim();
    final shown = label.text.trim();
    label.dispose();
    url.dispose();
    if (saved != true || !mounted) return;
    if (href.isEmpty) {
      _toast('A link needs an address.');
      return;
    }
    final safeHref = helpEscapeHtml(href);
    final safeText = helpEscapeHtml(shown.isEmpty ? href : shown);
    _ops.replace(
      r.start,
      r.end,
      '<a href="$safeHref" target="_blank" rel="noopener noreferrer">$safeText</a>',
    );
  }

  void _indent(bool deeper) {
    _ops.applyBlock(
      'p',
      style: deeper ? 'padding-left:40px' : 'padding-left:0',
      placeholder: 'Paragraph text',
    );
  }

  Widget? _toolFor(HtmlTool tool, bool enabled) {
    switch (tool) {
      case HtmlTool.heading:
        return HtmlToolButton(
          icon: Icons.title_rounded,
          tooltip: 'Headings and paragraph',
          onPressed: enabled ? _headingMenu : null,
        );
      case HtmlTool.bold:
        return HtmlToolButton(
          icon: Icons.format_bold_rounded,
          tooltip: 'Bold',
          onPressed: enabled
              ? () => _ops.wrapSelection('<strong>', '</strong>', 'bold text')
              : null,
        );
      case HtmlTool.italic:
        return HtmlToolButton(
          icon: Icons.format_italic_rounded,
          tooltip: 'Italic',
          onPressed: enabled
              ? () => _ops.wrapSelection('<em>', '</em>', 'italic text')
              : null,
        );
      case HtmlTool.underline:
        return HtmlToolButton(
          icon: Icons.format_underlined_rounded,
          tooltip: 'Underline',
          onPressed: enabled
              ? () => _ops.wrapSelection('<u>', '</u>', 'underlined text')
              : null,
        );
      case HtmlTool.strikethrough:
        return HtmlToolButton(
          icon: Icons.format_strikethrough_rounded,
          tooltip: 'Strikethrough',
          onPressed: enabled
              ? () => _ops.wrapSelection('<s>', '</s>', 'struck text')
              : null,
        );
      case HtmlTool.fontSize:
        return HtmlToolButton(
          icon: Icons.format_size_rounded,
          tooltip: 'Font size',
          onPressed: enabled ? _fontSizeMenu : null,
        );
      case HtmlTool.textColor:
        return HtmlToolButton(
          icon: Icons.format_color_text_rounded,
          tooltip: 'Text colour',
          onPressed: enabled ? () => _insertColor(false) : null,
        );
      case HtmlTool.highlight:
        return HtmlToolButton(
          icon: Icons.format_color_fill_rounded,
          tooltip: 'Highlight colour',
          onPressed: enabled ? () => _insertColor(true) : null,
        );
      case HtmlTool.align:
        return HtmlToolButton(
          icon: Icons.format_align_left_rounded,
          tooltip: 'Alignment',
          onPressed: enabled ? _alignMenu : null,
        );
      case HtmlTool.bulletList:
        return HtmlToolButton(
          icon: Icons.format_list_bulleted_rounded,
          tooltip: 'Bulleted list',
          onPressed: enabled ? () => _ops.applyList('ul') : null,
        );
      case HtmlTool.numberList:
        return HtmlToolButton(
          icon: Icons.format_list_numbered_rounded,
          tooltip: 'Numbered list',
          onPressed: enabled ? () => _ops.applyList('ol') : null,
        );
      case HtmlTool.indent:
        return HtmlToolButton(
          icon: Icons.format_indent_increase_rounded,
          tooltip: 'Indent',
          onPressed: enabled ? () => _indent(true) : null,
        );
      case HtmlTool.outdent:
        return HtmlToolButton(
          icon: Icons.format_indent_decrease_rounded,
          tooltip: 'Outdent',
          onPressed: enabled ? () => _indent(false) : null,
        );
      case HtmlTool.link:
        return HtmlToolButton(
          icon: Icons.link_rounded,
          tooltip: 'Insert link',
          onPressed: enabled ? _insertLink : null,
        );
      case HtmlTool.horizontalRule:
        return HtmlToolButton(
          icon: Icons.horizontal_rule_rounded,
          tooltip: 'Divider',
          onPressed: enabled ? () => _ops.insertBlock('<hr>') : null,
        );
      case HtmlTool.clear:
        return HtmlToolButton(
          icon: Icons.format_clear_rounded,
          tooltip: 'Clear formatting',
          onPressed: enabled
              ? () {
                  if (!_ops.clearFormatting()) {
                    _toast('Select the text you want to clear first.');
                  }
                }
              : null,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final enabled = widget.enabled && !widget.busy;
    final extras = widget.extraTools?.call(_ops, enabled) ?? const <Widget>[];
    final buttons = <Widget>[];
    for (final tool in widget.tools) {
      if (tool == HtmlTool.clear) continue;
      final built = _toolFor(tool, enabled);
      if (built != null) buttons.add(built);
    }
    buttons.addAll(extras);
    if (widget.tools.contains(HtmlTool.clear)) {
      final clear = _toolFor(HtmlTool.clear, enabled);
      if (clear != null) buttons.add(clear);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChoicePills<bool>(
          options: const [false, true],
          value: _preview,
          labelOf: (v) => v ? 'Preview' : 'Write',
          onChanged: (v) => setState(() => _preview = v),
        ),
        const SizedBox(height: 10),
        if (!_preview) ...[
          Wrap(spacing: 6, runSpacing: 6, children: buttons),
          const SizedBox(height: 10),
          SizedBox(
            height: widget.height,
            child: TextField(
              controller: widget.controller,
              enabled: widget.enabled,
              expands: true,
              minLines: null,
              maxLines: null,
              textAlignVertical: TextAlignVertical.top,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              scrollPadding: EdgeInsets.zero,
              style: text.bodySmall?.copyWith(
                fontFamily: 'monospace',
                height: 1.45,
              ),
              decoration: InputDecoration(
                hintText: widget.hintText,
                alignLabelWithHint: true,
              ),
              onChanged: (_) => widget.onChanged?.call(),
            ),
          ),
          if (widget.footnote != null) ...[
            const SizedBox(height: 8),
            Text(
              widget.footnote!,
              style: text.bodySmall?.copyWith(color: b.paperDim),
            ),
          ],
        ] else
          Container(
            width: double.infinity,
            height: widget.height,
            decoration: BoxDecoration(
              color: b.surfaceHi,
              borderRadius: BorderRadius.circular(Brand.radiusSm),
              border: Border.all(color: b.rule),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: HelpHtmlView(
                html: widget.controller.text,
                headers: widget.mediaHeaders,
              ),
            ),
          ),
      ],
    );
  }
}

class HtmlToolButton extends StatelessWidget {
  const HtmlToolButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final on = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(Brand.radiusSm),
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: b.surfaceHi,
              borderRadius: BorderRadius.circular(Brand.radiusSm),
              border: Border.all(color: b.rule),
            ),
            child: Icon(
              icon,
              size: 19,
              color: on ? b.paper : b.paperDim.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}

Future<String?> showAppColorPicker(
  BuildContext context,
  String initial, {
  required List<String> presets,
  String title = 'Pick a colour',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) =>
        _ColorPickerDialog(initial: initial, presets: presets, title: title),
  );
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({
    required this.initial,
    required this.presets,
    required this.title,
  });

  final String initial;
  final List<String> presets;
  final String title;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late Color _color;
  late final TextEditingController _hex;

  @override
  void initState() {
    super.initState();
    _color = helpParseCssColor(widget.initial) ?? Brand.navy;
    _hex = TextEditingController(text: _asHex(_color));
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  String _asHex(Color color) {
    final r = (color.r * 255).round();
    final g = (color.g * 255).round();
    final bl = (color.b * 255).round();
    final value = (r << 16) | (g << 8) | bl;
    return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  void _setColor(Color color, {bool syncField = true}) {
    setState(() => _color = color);
    if (syncField) _hex.text = _asHex(color);
  }

  Widget _channel(String label, double value, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(
          width: 18,
          child: Text(label, style: Theme.of(context).textTheme.labelMedium),
        ),
        Expanded(
          child: Slider(
            value: value,
            max: 255,
            divisions: 255,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            value.round().toString(),
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _color,
                    borderRadius: BorderRadius.circular(Brand.radiusSm),
                    border: Border.all(color: b.rule),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _hex,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[#0-9a-fA-F]'),
                      ),
                      LengthLimitingTextInputFormatter(7),
                    ],
                    decoration: const InputDecoration(labelText: 'Hex'),
                    onChanged: (value) {
                      final parsed = helpParseCssColor(value);
                      if (parsed != null) _setColor(parsed, syncField: false);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _channel(
              'R',
              (_color.r * 255),
              (v) => _setColor(
                Color.fromARGB(
                  255,
                  v.round(),
                  (_color.g * 255).round(),
                  (_color.b * 255).round(),
                ),
              ),
            ),
            _channel(
              'G',
              (_color.g * 255),
              (v) => _setColor(
                Color.fromARGB(
                  255,
                  (_color.r * 255).round(),
                  v.round(),
                  (_color.b * 255).round(),
                ),
              ),
            ),
            _channel(
              'B',
              (_color.b * 255),
              (v) => _setColor(
                Color.fromARGB(
                  255,
                  (_color.r * 255).round(),
                  (_color.g * 255).round(),
                  v.round(),
                ),
              ),
            ),
            if (widget.presets.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in widget.presets)
                    _PresetSwatch(
                      hex: preset,
                      selected:
                          _asHex(_color).toUpperCase() == preset.toUpperCase(),
                      onTap: () {
                        final parsed = helpParseCssColor(preset);
                        if (parsed != null) _setColor(parsed);
                      },
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_asHex(_color)),
          child: const Text('Use colour'),
        ),
      ],
    );
  }
}

class _PresetSwatch extends StatelessWidget {
  const _PresetSwatch({
    required this.hex,
    required this.selected,
    required this.onTap,
  });

  final String hex;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final color = helpParseCssColor(hex) ?? b.rule;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? b.signal : b.rule,
            width: selected ? 3 : 1,
          ),
        ),
      ),
    );
  }
}
