import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../theme.dart';
import 'help_html.dart';
import 'html_delta.dart';
import 'html_editor.dart';
import 'premium.dart';

abstract class RichEditorHandle {
  void insertImage(String src, {int? width, int? height});
  void insertHtmlBlock(String html);
}

class RichHtmlEditor extends StatefulWidget {
  const RichHtmlEditor({
    super.key,
    required this.controller,
    required this.colorPresets,
    this.tools = kRichTextTools,
    this.extraTools,
    this.enabled = true,
    this.busy = false,
    this.onChanged,
    this.height = 320,
    this.hintText = 'Write here…',
    this.footnote,
    this.mediaHeaders = const {},
  });

  final TextEditingController controller;
  final List<String> colorPresets;
  final List<HtmlTool> tools;
  final List<Widget> Function(RichEditorHandle handle, bool enabled)?
  extraTools;
  final bool enabled;
  final bool busy;
  final VoidCallback? onChanged;
  final double height;
  final String hintText;
  final String? footnote;
  final Map<String, String> mediaHeaders;

  @override
  State<RichHtmlEditor> createState() => _RichHtmlEditorState();
}

class _RichHtmlEditorState extends State<RichHtmlEditor>
    implements RichEditorHandle {
  final FocusNode _focus = FocusNode();
  final ScrollController _scroll = ScrollController();

  HtmlDeltaDocument? _doc;
  QuillController? _quill;
  StreamSubscription<DocChange>? _changes;
  bool _source = false;
  bool _visualAvailable = true;
  String? _issue;
  bool _writing = false;
  String _lastHtml = '';

  @override
  void initState() {
    super.initState();
    _loadVisual(widget.controller.text);
    widget.controller.addListener(_onExternalChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onExternalChange);
    _changes?.cancel();
    _quill?.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _loadVisual(String html) {
    _changes?.cancel();
    _quill?.dispose();
    _quill = null;
    _doc = null;
    _lastHtml = html;
    _visualAvailable = htmlSurvivesRoundTrip(html);
    if (!_visualAvailable) {
      _issue = htmlRoundTripIssue(html);
      _source = true;
      return;
    }
    _issue = null;
    final doc = htmlToDeltaDocument(html);
    final quill = QuillController(
      document: Document.fromDelta(doc.delta),
      selection: const TextSelection.collapsed(offset: 0),
      readOnly: !widget.enabled,
    );
    _doc = doc;
    _quill = quill;
    _changes = quill.document.changes.listen((_) => _sync());
  }

  void _onExternalChange() {
    if (_writing) return;
    final text = widget.controller.text;
    if (text == _lastHtml) return;
    if (_source) {
      _lastHtml = text;
      return;
    }
    setState(() => _loadVisual(text));
  }

  void _sync() {
    final doc = _doc;
    final quill = _quill;
    if (doc == null || quill == null) return;
    final html = doc.toHtml(quill.document.toDelta());
    if (html == _lastHtml) return;
    _writing = true;
    widget.controller.text = html;
    _writing = false;
    _lastHtml = html;
    widget.onChanged?.call();
  }

  void _setSource(bool source) {
    if (source == _source) return;
    if (source) {
      _sync();
      setState(() => _source = true);
      return;
    }
    final html = widget.controller.text;
    if (!htmlSurvivesRoundTrip(html)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This HTML has formatting the visual editor can\'t keep, '
            'so it stays in HTML view.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _source = false;
      _loadVisual(html);
    });
  }

  @override
  void didUpdateWidget(RichHtmlEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) {
      _quill?.readOnly = !widget.enabled;
    }
  }

  int _insertIndex() {
    final quill = _quill!;
    final selection = quill.selection;
    final length = quill.document.length - 1;
    if (!selection.isValid) return length;
    return selection.baseOffset.clamp(0, length);
  }

  void _insertEmbed(Embeddable embed) {
    final quill = _quill;
    if (quill == null) return;
    final index = _insertIndex();
    final length = (quill.selection.extentOffset - quill.selection.baseOffset)
        .abs();
    quill.replaceText(
      index,
      quill.selection.isValid ? length : 0,
      embed,
      TextSelection.collapsed(offset: index + 1),
    );
  }

  @override
  void insertImage(String src, {int? width, int? height}) {
    if (_source || _quill == null) {
      final size = width == null
          ? ''
          : ' width="$width"${height == null ? '' : ' height="$height"'}';
      HtmlEditOps(
        widget.controller,
        widget.onChanged,
      ).insertBlock('<p><img src="$src" alt=""$size></p>');
      return;
    }
    _doc!.setImageSize(src, width, height);
    _insertEmbed(BlockEmbed.image(src));
  }

  @override
  void insertHtmlBlock(String html) {
    if (_source || _quill == null) {
      HtmlEditOps(widget.controller, widget.onChanged).insertBlock(html);
      return;
    }
    final unwrapped = RegExp(
      r'^\s*<p[^>]*>\s*(<(?:video|iframe|table|hr)\b[\s\S]*)</p>\s*$',
      caseSensitive: false,
    ).firstMatch(html);
    final key = _doc!.addOpaque((unwrapped?.group(1) ?? html).trim());
    _insertEmbed(BlockEmbed(kOpaqueEmbed, key));
  }

  QuillSimpleToolbarConfig _toolbarConfig(bool enabled) {
    final t = widget.tools.toSet();
    return QuillSimpleToolbarConfig(
      multiRowsDisplay: true,
      showDividers: false,
      showFontFamily: false,
      showFontSize: t.contains(HtmlTool.fontSize),
      showBoldButton: t.contains(HtmlTool.bold),
      showItalicButton: t.contains(HtmlTool.italic),
      showUnderLineButton: t.contains(HtmlTool.underline),
      showStrikeThrough: t.contains(HtmlTool.strikethrough),
      showSmallButton: false,
      showInlineCode: false,
      showColorButton: t.contains(HtmlTool.textColor),
      showBackgroundColorButton: t.contains(HtmlTool.highlight),
      showClearFormat: t.contains(HtmlTool.clear),
      showAlignmentButtons: t.contains(HtmlTool.align),
      showHeaderStyle: t.contains(HtmlTool.heading),
      showListNumbers: t.contains(HtmlTool.numberList),
      showListBullets: t.contains(HtmlTool.bulletList),
      showListCheck: false,
      showCodeBlock: false,
      showQuote: false,
      showIndent: t.contains(HtmlTool.indent) || t.contains(HtmlTool.outdent),
      showLink: t.contains(HtmlTool.link),
      showUndo: true,
      showRedo: true,
      showDirection: false,
      showSearchButton: false,
      showSubscript: false,
      showSuperscript: false,
      buttonOptions: QuillSimpleToolbarButtonOptions(
        fontSize: QuillToolbarFontSizeButtonOptions(
          items: {
            for (final size in kHtmlFontSizes)
              size.replaceAll('px', ''): size.replaceAll('px', ''),
            'Clear': '0',
          },
        ),
      ),
      customButtons: [
        if (t.contains(HtmlTool.horizontalRule))
          QuillToolbarCustomButtonOptions(
            icon: const Icon(Icons.horizontal_rule_rounded),
            tooltip: 'Divider',
            onPressed: enabled ? () => insertHtmlBlock('<hr>') : null,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final enabled = widget.enabled && !widget.busy;
    final extras = widget.extraTools?.call(this, enabled) ?? const <Widget>[];

    return Localizations.override(
      context: context,
      delegates: const [FlutterQuillLocalizations.delegate],
      child: _body(context, b, text, enabled, extras),
    );
  }

  Widget _body(
    BuildContext context,
    BrandColors b,
    TextTheme text,
    bool enabled,
    List<Widget> extras,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_visualAvailable)
          ChoicePills<bool>(
            options: const [false, true],
            value: _source,
            labelOf: (v) => v ? 'HTML' : 'Edit',
            onChanged: _setSource,
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Brand.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(Brand.radiusSm),
              border: Border.all(color: Brand.warning.withValues(alpha: 0.4)),
            ),
            child: Text(
              'This document has formatting the visual editor can\'t keep, '
              'so it opens as HTML to avoid losing anything.'
              '${(_issue ?? '').isEmpty ? '' : ' The problem starts near “$_issue”.'}',
              style: text.bodySmall,
            ),
          ),
        const SizedBox(height: 10),
        if (_source || _quill == null)
          HtmlSourceEditor(
            controller: widget.controller,
            colorPresets: widget.colorPresets,
            tools: widget.tools,
            enabled: widget.enabled,
            busy: widget.busy,
            onChanged: widget.onChanged,
            height: widget.height,
            hintText: '<p>${widget.hintText}</p>',
            footnote: widget.footnote,
            mediaHeaders: widget.mediaHeaders,
            extraTools: widget.extraTools == null
                ? null
                : (ops, on) => widget.extraTools!(this, on),
          )
        else ...[
          Theme(
            data: Theme.of(
              context,
            ).copyWith(iconTheme: IconThemeData(color: b.paper, size: 20)),
            child: Container(
              decoration: BoxDecoration(
                color: b.surfaceHi,
                borderRadius: BorderRadius.circular(Brand.radiusSm),
                border: Border.all(color: b.rule),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  IgnorePointer(
                    ignoring: !enabled,
                    child: QuillSimpleToolbar(
                      controller: _quill!,
                      config: _toolbarConfig(enabled),
                    ),
                  ),
                  if (extras.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
                      child: Wrap(spacing: 6, runSpacing: 6, children: extras),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            height: widget.height,
            decoration: BoxDecoration(
              color: b.surfaceHi,
              borderRadius: BorderRadius.circular(Brand.radiusSm),
              border: Border.all(color: b.rule),
            ),
            clipBehavior: Clip.antiAlias,
            child: QuillEditor(
              controller: _quill!,
              focusNode: _focus,
              scrollController: _scroll,
              config: QuillEditorConfig(
                placeholder: widget.hintText,
                padding: const EdgeInsets.all(14),
                expands: true,
                scrollable: true,
                embedBuilders: [
                  _ImageEmbedBuilder(widget.mediaHeaders),
                  _OpaqueEmbedBuilder(
                    () => _doc?.opaque ?? const {},
                    widget.mediaHeaders,
                  ),
                ],
                unknownEmbedBuilder: const _UnknownEmbedBuilder(),
              ),
            ),
          ),
          if (widget.footnote != null) ...[
            const SizedBox(height: 8),
            Text(
              widget.footnote!,
              style: text.bodySmall?.copyWith(color: b.paperDim),
            ),
          ],
        ],
      ],
    );
  }
}

class _ImageEmbedBuilder extends EmbedBuilder {
  const _ImageEmbedBuilder(this.headers);

  final Map<String, String> headers;

  @override
  String get key => BlockEmbed.imageType;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final b = context.brand;
    final src = embedContext.node.value.data.toString();
    final fallback = Container(
      height: 90,
      alignment: Alignment.center,
      color: b.surface,
      child: Icon(Icons.image_not_supported_rounded, color: b.paperDim),
    );
    Widget image;
    if (src.startsWith('data:image/')) {
      final index = src.indexOf('base64,');
      try {
        image = index < 0
            ? fallback
            : Image.memory(
                base64Decode(src.substring(index + 7)),
                fit: BoxFit.contain,
              );
      } catch (_) {
        image = fallback;
      }
    } else if (src.startsWith('http')) {
      image = CachedNetworkImage(
        imageUrl: src,
        httpHeaders: headers,
        fit: BoxFit.contain,
        placeholder: (_, _) => const Skeleton(height: 120),
        errorWidget: (_, _, _) => fallback,
      );
    } else {
      image = fallback;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 260),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Brand.radiusSm),
          child: image,
        ),
      ),
    );
  }
}

class _OpaqueEmbedBuilder extends EmbedBuilder {
  const _OpaqueEmbedBuilder(this.opaque, this.headers);

  final Map<String, String> Function() opaque;
  final Map<String, String> headers;

  @override
  String get key => kOpaqueEmbed;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final html = opaque()[embedContext.node.value.data.toString()] ?? '';
    final lower = html.trimLeft().toLowerCase();
    if (lower.startsWith('<hr') || lower.startsWith('<p><hr')) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Divider(color: b.rule, thickness: 1.5, height: 1.5),
      );
    }
    final isTable = lower.contains('<table');
    final isVideo = lower.contains('<video') || lower.contains('<iframe');
    final label = isTable
        ? 'Table'
        : isVideo
        ? 'Video'
        : 'Embedded content';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: b.surface,
          borderRadius: BorderRadius.circular(Brand.radiusSm),
          border: Border.all(color: b.rule),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  isTable
                      ? Icons.table_chart_outlined
                      : isVideo
                      ? Icons.movie_outlined
                      : Icons.code_rounded,
                  size: 16,
                  color: b.signal,
                ),
                const SizedBox(width: 6),
                Text(label, style: text.labelMedium),
                const Spacer(),
                Text(
                  'Kept as is',
                  style: text.labelSmall?.copyWith(color: b.paperDim),
                ),
              ],
            ),
            const SizedBox(height: 8),
            IgnorePointer(
              ignoring: isTable,
              child: HelpHtmlView(html: html, headers: headers),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnknownEmbedBuilder extends EmbedBuilder {
  const _UnknownEmbedBuilder();

  @override
  String get key => 'unknown';

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final b = context.brand;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: b.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: b.rule),
      ),
      child: Text(
        'Unsupported content',
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}
