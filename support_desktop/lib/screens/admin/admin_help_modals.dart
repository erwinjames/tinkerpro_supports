import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/admin_help_service.dart';
import '../../theme.dart';
import '../../widgets/admin_fa.dart';
import '../../widgets/premium.dart';
import 'admin_help_editor.dart';
import 'admin_list.dart';

const kHelpIconList = [
  'fa-question-circle', 'fa-lightbulb', 'fa-info-circle', 'fa-cogs', 'fa-book', 'fa-comments',
  'fa-envelope', 'fa-headset', 'fa-globe', 'fa-bell', 'fa-wrench', 'fa-user', 'fa-shield-alt',
  'fa-lock', 'fa-paper-plane', 'fa-star', 'fa-thumbs-up', 'fa-heart', 'fa-exclamation-triangle',
  'fa-bug', 'fa-calendar', 'fa-camera', 'fa-chart-bar', 'fa-check-circle', 'fa-cloud',
  'fa-coffee', 'fa-copy', 'fa-database', 'fa-edit', 'fa-flag', 'fa-gift', 'fa-home', 'fa-key',
  'fa-magic', 'fa-map-marker', 'fa-microphone', 'fa-moon', 'fa-paint-brush', 'fa-phone',
  'fa-rocket', 'fa-search', 'fa-shopping-cart', 'fa-signal', 'fa-sitemap', 'fa-sliders-h',
  'fa-smile', 'fa-snowflake', 'fa-sun', 'fa-tag', 'fa-th-large', 'fa-tools', 'fa-truck',
  'fa-tv', 'fa-umbrella', 'fa-video', 'fa-wifi', 'fa-barcode', 'fa-arrow-right-to-bracket', 'fa-receipt',
  'fa-arrow-rotate-left', 'fa-computer', 'fa-laptop-code', 'fa-print', 'fa-keyboard', 'fa-mouse',
];

const kHelpDefaultIcon = 'fa-question-circle';
const kHelpDefaultIconColor = '#0c233e';

IconData helpFaIcon(String name) => adminFaIcon('fas $name');

Color helpHexColor(String hex, [Color fallback = Brand.signal]) {
  var h = hex.replaceAll('#', '').trim();
  if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
  if (h.length != 6) return fallback;
  final v = int.tryParse(h, radix: 16);
  return v == null ? fallback : Color(0xFF000000 | v);
}

class HelpTaxonomy {
  const HelpTaxonomy(this.cats);
  final List<HelpCategoryNode> cats;

  HelpCategoryNode? cat(String slug) {
    for (final c in cats) {
      if (c.slug == slug) return c;
    }
    return null;
  }

  String normCat(String? v) {
    final k = (v ?? '').trim().toLowerCase();
    return cat(k) != null ? k : 'v1';
  }

  HelpCategoryNode? sub(String catSlug, String subSlug) {
    final c = cat(catSlug);
    if (c == null || subSlug.isEmpty) return null;
    for (final s in c.subs) {
      if (s.slug == subSlug) return s;
    }
    return null;
  }

  String normSub(String? catSlug, String? v) {
    final k = (v ?? '').trim().toLowerCase();
    if (k.isEmpty) return '';
    final c = cat(normCat(catSlug));
    return c != null && c.subs.any((s) => s.slug == k) ? k : '';
  }

  String normSubSub(String? catSlug, String? subSlug, String? v) {
    final k = (v ?? '').trim().toLowerCase();
    if (k.isEmpty) return '';
    final c = normCat(catSlug);
    final s = sub(c, normSub(c, subSlug));
    return s != null && s.subs.any((d) => d.slug == k) ? k : '';
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child, this.hint, this.optional = false});
  final String label;
  final Widget child;
  final String? hint;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
            if (optional) ...[
              const SizedBox(width: 6),
              const Text('optional', style: TextStyle(fontSize: 11.5, color: Color(0xFF888888))),
            ],
          ],
        ),
        const SizedBox(height: 6),
        child,
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(hint!, style: const TextStyle(fontSize: 12, color: Color(0xFF6C757D))),
        ],
      ],
    );
  }
}

Widget _select({
  required String value,
  required List<(String, String)> options,
  required ValueChanged<String> onChanged,
  bool enabled = true,
}) {
  final safe = options.any((o) => o.$1 == value) ? value : (options.isEmpty ? null : options.first.$1);
  return DropdownButtonFormField<String>(
    key: ValueKey('${options.map((o) => o.$1).join('|')}#$safe#$enabled'),
    initialValue: safe,
    isExpanded: true,
    items: [
      for (final o in options)
        DropdownMenuItem(value: o.$1, child: Text(o.$2, overflow: TextOverflow.ellipsis)),
    ],
    onChanged: enabled ? (v) => onChanged(v ?? '') : null,
  );
}

List<(String, String)> _subOptions(HelpTaxonomy tx, String catSlug) {
  final c = tx.cat(tx.normCat(catSlug));
  return [
    ('', 'None'),
    for (final s in c?.subs ?? const <HelpCategoryNode>[]) (s.slug, s.name),
  ];
}

List<(String, String)> _subSubOptions(HelpTaxonomy tx, String catSlug, String subSlug) {
  final c = tx.normCat(catSlug);
  final s = tx.sub(c, tx.normSub(c, subSlug));
  return [
    ('', 'None'),
    for (final d in s?.subs ?? const <HelpCategoryNode>[]) (d.slug, d.name),
  ];
}

Widget _metaGrid(List<Widget> fields) {
  return LayoutBuilder(
    builder: (ctx, box) {
      const gap = 16.0;
      final per = ((box.maxWidth + gap) / (240 + gap)).floor().clamp(1, fields.length);
      final w = (box.maxWidth - gap * (per - 1)) / per;
      return Wrap(
        spacing: gap,
        runSpacing: 14,
        children: [for (final f in fields) SizedBox(width: w, child: f)],
      );
    },
  );
}

Widget _editorArea(List<Widget> header, Widget editor, {double minEditorHeight = 360}) {
  return CustomScrollView(
    slivers: [
      SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: header,
        ),
      ),
      SliverLayoutBuilder(
        builder: (ctx, c) => SliverToBoxAdapter(
          child: SizedBox(
            height: math.max(minEditorHeight, c.viewportMainAxisExtent - c.precedingScrollExtent),
            child: editor,
          ),
        ),
      ),
    ],
  );
}

class _ColorField extends StatelessWidget {
  const _ColorField({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final VoidCallback onChanged;

  static const _swatches = [
    '#0c233e', '#000000', '#ff7d00', '#fd7e14', '#dc3545', '#e03e2d', '#198754',
    '#2dc26b', '#0d6efd', '#3598db', '#6f42c1', '#b96ad9', '#20c997', '#6c757d',
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (_, v, _) => Row(
        children: [
          PopupMenuButton<String>(
            tooltip: 'Choose icon color',
            onSelected: (hex) {
              controller.text = hex;
              onChanged();
            },
            itemBuilder: (_) => [
              PopupMenuItem<String>(
                enabled: false,
                child: SizedBox(
                  width: 196,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final hex in _swatches)
                        InkWell(
                          onTap: () => Navigator.pop(context, hex),
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: helpHexColor(hex),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0xFFDDDDDD)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            child: Container(
              width: 44,
              height: 38,
              decoration: BoxDecoration(
                color: helpHexColor(v.text, Colors.black),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFDEE2E6)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: (_) => onChanged(),
              decoration: const InputDecoration(hintText: '#000000'),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconGrid extends StatelessWidget {
  const _IconGrid({
    required this.icons,
    required this.selected,
    required this.color,
    required this.onPick,
  });
  final List<String> icons;
  final String selected;
  final Color color;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    if (icons.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(6),
        child: Text('No icons match.', style: TextStyle(fontSize: 12.5, color: Color(0xFF888888))),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final name in icons)
          Tooltip(
            message: name,
            child: InkWell(
              onTap: () => onPick(name),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: 40,
                height: 36,
                decoration: BoxDecoration(
                  color: name == selected ? const Color(0xFFFFF4EA) : Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: name == selected ? Brand.signal : const Color(0xFF6C757D),
                  ),
                ),
                child: Icon(
                  helpFaIcon(name),
                  size: 16,
                  color: name == selected ? color : const Color(0xFF6C757D),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

Future<bool> showHelpAddTopicModal(
  BuildContext context, {
  required AdminHelpApi api,
  required HelpTaxonomy taxonomy,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AddTopicDialog(api: api, taxonomy: taxonomy),
  );
  return ok == true;
}

class _AddTopicDialog extends StatefulWidget {
  const _AddTopicDialog({required this.api, required this.taxonomy});
  final AdminHelpApi api;
  final HelpTaxonomy taxonomy;

  @override
  State<_AddTopicDialog> createState() => _AddTopicDialogState();
}

class _AddTopicDialogState extends State<_AddTopicDialog> {
  HelpTaxonomy get tx => widget.taxonomy;
  final _title = TextEditingController();
  final _subtitle = TextEditingController();
  final _search = TextEditingController();
  final _color = TextEditingController(text: '#000000');
  final _editor = HelpEditorController();
  String _cat = '';
  String _sub = '';
  String _subSub = '';
  String _icon = '';
  int _loaded = 12;
  bool _busy = false;
  String? _titleError;

  @override
  void dispose() {
    _title.dispose();
    _subtitle.dispose();
    _search.dispose();
    _color.dispose();
    _editor.dispose();
    super.dispose();
  }

  List<String> get _filtered => kHelpIconList
      .where((i) => i.toLowerCase().contains(_search.text.toLowerCase()))
      .toList();

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _titleError = 'Please fill out this field.');
      return;
    }
    final problem = _editor.saveProblem;
    if (problem != null) {
      toast(context, problem);
      return;
    }
    setState(() {
      _busy = true;
      _titleError = null;
    });
    try {
      final html = _editor.html;
      final description = await widget.api.summary(html);
      final res = await widget.api.addTopic({
        'title': _title.text.trim(),
        'subtitle': _subtitle.text.trim(),
        'description': description,
        'icon': _icon.isEmpty ? kHelpDefaultIcon : _icon,
        'iconColor': _color.text.trim(),
        'category': _cat.isEmpty ? 'v1' : _cat,
        'subcategory': _sub,
        'subsubcategory': _subSub,
        'ordered': html.trim().isNotEmpty
            ? [
                {'type': 'text', 'content': html},
              ]
            : [],
      });
      if (!mounted) return;
      if (res['success'] == true) {
        toast(context, 'Help topic added successfully!');
        Navigator.pop(context, true);
        return;
      }
      toast(context, 'Error: ${res['message']}');
    } catch (e) {
      if (mounted) {
        toast(context, e is HelpApiError ? e.message : 'Error adding help topic');
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final catOptions = [
      ('', 'No system (V1)'),
      for (final c in tx.cats)
        if (c.slug != 'v1') (c.slug, c.name),
    ];
    final subOpts = _subOptions(tx, _cat);
    final subSubOpts = _subSubOptions(tx, _cat, _sub);
    final icons = _filtered;
    final color = helpHexColor(_color.text, Colors.black);
    return WebModal(
      title: 'New Help Document',
      icon: Icons.note_add_outlined,
      width: 1480,
      height: screen.height * 0.92,
      scrollable: false,
      onClose: _busy ? () {} : null,
      actions: [
        GhostButton(label: 'Cancel', onPressed: _busy ? null : () => Navigator.pop(context, false)),
        SignalButton(label: 'Save Topic', busy: _busy, onPressed: _busy ? null : _submit),
      ],
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _editorArea(
              [
                _metaGrid([
                  _Field(
                    label: 'Title',
                    child: TextField(
                      controller: _title,
                      autofocus: true,
                      onChanged: (_) {
                        if (_titleError != null) setState(() => _titleError = null);
                      },
                      decoration: InputDecoration(
                        hintText: 'Enter topic title',
                        errorText: _titleError,
                      ),
                    ),
                  ),
                  _Field(
                    label: 'Subtitle',
                    hint: 'Optional short line shown under the title.',
                    child: TextField(
                      controller: _subtitle,
                      maxLength: 255,
                      decoration: const InputDecoration(
                        hintText: 'Enter topic subtitle',
                        counterText: '',
                      ),
                    ),
                  ),
                  _Field(
                    label: 'System',
                    hint: 'Leave as "No system" to file this document under V1.',
                    child: _select(
                      value: _cat,
                      options: catOptions,
                      onChanged: (v) => setState(() {
                        _cat = v;
                        _sub = '';
                        _subSub = '';
                      }),
                    ),
                  ),
                  _Field(
                    label: 'Category',
                    hint: 'Optional. Add new ones with the Add Category button.',
                    child: _select(
                      value: _sub,
                      options: subOpts,
                      enabled: subOpts.length > 1,
                      onChanged: (v) => setState(() {
                        _sub = v;
                        _subSub = '';
                      }),
                    ),
                  ),
                  _Field(
                    label: 'Subcategory',
                    hint: 'Optional. Sits under the category.',
                    child: _select(
                      value: _subSub,
                      options: subSubOpts,
                      enabled: subSubOpts.length > 1,
                      onChanged: (v) => setState(() => _subSub = v),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                const Text('Content', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                const SizedBox(height: 6),
              ],
              HelpContentEditor(controller: _editor, helpApi: widget.api),
            ),
          ),
          const SizedBox(width: 24),
          Container(
            width: 320,
            padding: const EdgeInsets.only(left: 24),
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: Color(0xFFE8E8E4))),
            ),
            child: ListView(
              children: [
                _Field(
                  label: 'Search Icon',
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() => _loaded = 12),
                    decoration: const InputDecoration(hintText: 'Search icons...'),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFDDDDDD)),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _IconGrid(
                          icons: icons.take(_loaded).toList(),
                          selected: _icon,
                          color: color,
                          onPick: (n) => setState(() => _icon = n),
                        ),
                        if (_loaded < icons.length)
                          TextButton(
                            onPressed: () => setState(() => _loaded += 12),
                            child: const Text('Load More Icons'),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _Field(
                  label: 'Icon Color',
                  child: _ColorField(controller: _color, onChanged: () => setState(() {})),
                ),
                const SizedBox(height: 16),
                _Field(
                  label: 'Preview',
                  child: Container(
                    height: 72,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFDEE2E6)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      helpFaIcon(_icon.isEmpty ? kHelpDefaultIcon : _icon),
                      size: 32,
                      color: _icon.isEmpty ? Colors.black : color,
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
}

enum HelpEditResult { saved, delete }

Future<HelpEditResult?> showHelpEditTopicModal(
  BuildContext context, {
  required AdminHelpApi api,
  required HelpTaxonomy taxonomy,
  required Map<String, dynamic> topic,
  required String html,
}) {
  return showDialog<HelpEditResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _EditTopicDialog(api: api, taxonomy: taxonomy, topic: topic, html: html),
  );
}

class _EditTopicDialog extends StatefulWidget {
  const _EditTopicDialog({
    required this.api,
    required this.taxonomy,
    required this.topic,
    required this.html,
  });
  final AdminHelpApi api;
  final HelpTaxonomy taxonomy;
  final Map<String, dynamic> topic;
  final String html;

  @override
  State<_EditTopicDialog> createState() => _EditTopicDialogState();
}

class _EditTopicDialogState extends State<_EditTopicDialog> {
  HelpTaxonomy get tx => widget.taxonomy;
  late final int _id = int.tryParse('${widget.topic['id']}') ?? 0;
  late final _title = TextEditingController(text: '${widget.topic['title'] ?? ''}');
  late final _subtitle = TextEditingController(text: '${widget.topic['subtitle'] ?? ''}');
  late final _color = TextEditingController(
    text: RegExp(r'^#[0-9a-f]{6}$', caseSensitive: false)
            .hasMatch('${widget.topic['icon_color'] ?? ''}'.trim())
        ? '${widget.topic['icon_color']}'.trim()
        : kHelpDefaultIconColor,
  );
  late final _editor = HelpEditorController(widget.html);
  final _iconSearch = TextEditingController();
  final _titleFocus = FocusNode();
  late String _cat = tx.normCat('${widget.topic['category'] ?? ''}');
  late String _sub = tx.normSub(_cat, '${widget.topic['subcategory'] ?? ''}');
  late String _subSub = tx.normSubSub(_cat, _sub, '${widget.topic['subsubcategory'] ?? ''}');
  late String _icon = '${widget.topic['icon'] ?? ''}'.isEmpty
      ? kHelpDefaultIcon
      : '${widget.topic['icon']}';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      final after = int.tryParse(Platform.environment['TP_HELP_SAVE_AFTER'] ?? '');
      if (after != null) {
        Timer(Duration(milliseconds: after), () {
          if (mounted && !_busy) _save();
        });
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _subtitle.dispose();
    _color.dispose();
    _editor.dispose();
    _iconSearch.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  Future<void> _pickIcon() async {
    _iconSearch.clear();
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => WebModal(
          title: 'Choose topic icon',
          icon: Icons.emoji_symbols_outlined,
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _iconSearch,
                autofocus: true,
                onChanged: (_) => set(() {}),
                decoration: const InputDecoration(hintText: 'Search icons...'),
              ),
              const SizedBox(height: 10),
              _IconGrid(
                icons: kHelpIconList
                    .where((n) => _iconSearch.text.trim().isEmpty || n.contains(_iconSearch.text.trim().toLowerCase()))
                    .toList(),
                selected: _icon,
                color: helpHexColor(_color.text, Colors.black),
                onPick: (n) => Navigator.pop(ctx, n),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) setState(() => _icon = picked);
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      toast(context, 'Title is required');
      _titleFocus.requestFocus();
      return;
    }
    final problem = _editor.saveProblem;
    if (problem != null) {
      toast(context, problem);
      return;
    }
    setState(() => _busy = true);
    try {
      final cat = _cat.isEmpty ? 'v1' : _cat;
      final sub = tx.normSub(cat, _sub);
      final details = await widget.api.updateTopic({
        'id': '$_id',
        'title': _title.text.trim(),
        'subtitle': _subtitle.text.trim(),
        'icon': _icon.isEmpty ? kHelpDefaultIcon : _icon,
        'iconColor': _color.text.trim().isEmpty ? kHelpDefaultIconColor : _color.text.trim(),
        'category': cat,
        'subcategory': sub,
        'subsubcategory': tx.normSubSub(cat, sub, _subSub),
      });
      if (details['success'] != true) {
        throw HelpApiError('${details['message'] ?? 'Could not save the topic details'}');
      }
      final res = await widget.api.saveContent(_id, _editor.html);
      if (!mounted) return;
      if (res['success'] == true) {
        toast(context, 'Changes saved successfully!');
        Navigator.pop(context, HelpEditResult.saved);
        return;
      }
      toast(context, 'Error saving content: ${res['message']}');
    } catch (e) {
      if (mounted) toast(context, e is HelpApiError ? e.message : 'Error saving changes');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: 'Delete this help topic?',
      message: 'The topic and all of its content blocks will be permanently removed.',
      confirmLabel: 'Delete topic',
    );
    if (ok && mounted) Navigator.pop(context, HelpEditResult.delete);
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final color = helpHexColor(_color.text, Colors.black);
    final catOptions = [for (final c in tx.cats) (c.slug, c.name)];
    final subOpts = _subOptions(tx, _cat);
    final subSubOpts = _subSubOptions(tx, _cat, _sub);
    final title = _title.text.trim().isEmpty ? 'Untitled topic' : _title.text.trim();
    return WebModal(
      title: title,
      subtitle: _subtitle.text.trim().isEmpty ? 'Help Editor' : 'Help Editor · ${_subtitle.text.trim()}',
      icon: helpFaIcon(_icon),
      width: 1480,
      height: screen.height * 0.92,
      scrollable: false,
      onClose: _busy ? () {} : null,
      actions: [
        DangerButton(label: 'Delete Topic', icon: Icons.delete_outline, onPressed: _busy ? null : _delete),
        const Spacer(),
        GhostButton(label: 'Cancel', onPressed: _busy ? null : () => Navigator.pop(context)),
        SignalButton(label: 'Save Changes', icon: Icons.save_outlined, busy: _busy, onPressed: _busy ? null : _save),
      ],
      child: _editorArea(
        [
          _metaGrid([
            _Field(
              label: 'Title',
              child: TextField(
                controller: _title,
                focusNode: _titleFocus,
                maxLength: 255,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(hintText: 'Topic title', counterText: ''),
              ),
            ),
            _Field(
              label: 'Subtitle',
              child: TextField(
                controller: _subtitle,
                maxLength: 255,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(hintText: 'Short line shown under the title', counterText: ''),
              ),
            ),
            _Field(
              label: 'System',
              child: _select(
                value: _cat,
                options: catOptions,
                onChanged: (v) => setState(() {
                  _cat = v;
                  _sub = '';
                  _subSub = '';
                }),
              ),
            ),
            _Field(
              label: 'Category',
              child: _select(
                value: _sub,
                options: subOpts,
                enabled: subOpts.length > 1,
                onChanged: (v) => setState(() {
                  _sub = v;
                  _subSub = '';
                }),
              ),
            ),
            _Field(
              label: 'Subcategory',
              child: _select(
                value: _subSub,
                options: subSubOpts,
                enabled: subSubOpts.length > 1,
                onChanged: (v) => setState(() => _subSub = v),
              ),
            ),
            _Field(
              label: 'Icon',
              child: Row(
                children: [
                  OutlinedButton(
                    onPressed: _pickIcon,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(64, 42),
                      side: const BorderSide(color: Color(0xFFDEE2E6)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(helpFaIcon(_icon), size: 18, color: color),
                        const Icon(Icons.expand_more, size: 16, color: Color(0xFF888888)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ColorField(controller: _color, onChanged: () => setState(() {})),
                  ),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 16),
        ],
        HelpContentEditor(controller: _editor, helpApi: widget.api),
      ),
    );
  }
}

Future<Map<String, dynamic>?> showHelpCategoryModal(
  BuildContext context, {
  required AdminHelpApi api,
  required HelpTaxonomy taxonomy,
}) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => _CategoryDialog(api: api, taxonomy: taxonomy),
  );
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({required this.api, required this.taxonomy});
  final AdminHelpApi api;
  final HelpTaxonomy taxonomy;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  final _cat = TextEditingController();
  final _sub = TextEditingController();
  final _subSub = TextEditingController();
  final _catFocus = FocusNode();
  final _subFocus = FocusNode();
  final _subSubFocus = FocusNode();
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_cat, _sub, _subSub]) {
      c.dispose();
    }
    for (final f in [_catFocus, _subFocus, _subSubFocus]) {
      f.dispose();
    }
    super.dispose();
  }

  HelpCategoryNode? _match(List<HelpCategoryNode> list, String value) {
    final typed = value.trim().toLowerCase();
    if (typed.isEmpty) return null;
    for (final c in list) {
      if (c.name.toLowerCase() == typed || c.slug == typed) return c;
    }
    return null;
  }

  List<String> _options(int level) {
    final cats = widget.taxonomy.cats;
    if (level == 1) return cats.map((c) => c.name).toList();
    final cat = _match(cats, _cat.text);
    if (level == 2) return cat == null ? const [] : cat.subs.map((s) => s.name).toList();
    final sub = cat == null ? null : _match(cat.subs, _sub.text);
    return sub == null ? const [] : sub.subs.map((s) => s.name).toList();
  }

  Iterable<String> _matches(int level, String typedRaw) {
    final typed = typedRaw.trim().toLowerCase();
    final options = _options(level);
    final exact = options.any((n) => n.toLowerCase() == typed);
    return typed.isNotEmpty && !exact
        ? options.where((n) => n.toLowerCase().contains(typed))
        : options;
  }

  Widget _combo({
    required int level,
    required TextEditingController controller,
    required FocusNode focus,
    required String placeholder,
    required String emptyText,
    VoidCallback? onChange,
    bool autofocus = false,
  }) {
    return RawAutocomplete<String>(
      textEditingController: controller,
      focusNode: focus,
      optionsBuilder: (v) => _matches(level, v.text),
      onSelected: (v) {
        controller.text = v;
        onChange?.call();
      },
      fieldViewBuilder: (ctx, ctrl, node, submit) => TextField(
        controller: ctrl,
        focusNode: node,
        autofocus: autofocus,
        maxLength: 100,
        onChanged: (_) => onChange?.call(),
        decoration: InputDecoration(
          hintText: placeholder,
          counterText: '',
          suffixIcon: const Icon(Icons.expand_more, size: 18),
        ),
      ),
      optionsViewBuilder: (ctx, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220, maxWidth: 452),
            child: options.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(emptyText, style: const TextStyle(color: Color(0xFF888888))),
                  )
                : ListView(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    children: [
                      for (final o in options)
                        InkWell(
                          onTap: () => onSelected(o),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            child: Text(o),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final category = _cat.text.trim();
    final subcategory = _sub.text.trim();
    final subsubcategory = _subSub.text.trim();
    if (category.isEmpty) {
      toast(context, 'System name is required');
      _catFocus.requestFocus();
      return;
    }
    if (subsubcategory.isNotEmpty && subcategory.isEmpty) {
      toast(context, 'Pick or type a category before adding a subcategory');
      _subFocus.requestFocus();
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await widget.api.addCategory(category, subcategory, subsubcategory);
      if (!mounted) return;
      if (res['success'] != true) {
        toast(context, '${res['message'] ?? 'Could not save the category'}');
        setState(() => _busy = false);
        return;
      }
      toast(
        context,
        subsubcategory.isNotEmpty
            ? 'System, category and subcategory saved!'
            : subcategory.isNotEmpty
                ? 'System and category saved!'
                : 'System saved!',
      );
      Navigator.pop(context, res);
    } catch (_) {
      if (!mounted) return;
      toast(context, 'Error saving category');
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WebModal(
      title: 'Add Category',
      subtitle: 'Help Center',
      icon: Icons.create_new_folder_outlined,
      width: 500,
      actions: [
        GhostButton(label: 'Cancel', onPressed: _busy ? null : () => Navigator.pop(context)),
        SignalButton(label: 'Save Category', icon: Icons.save_outlined, busy: _busy, onPressed: _busy ? null : _submit),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Field(
            label: 'System',
            hint: 'Top level, such as V1, V2, Invoice or CRM.',
            child: _combo(
              level: 1,
              controller: _cat,
              focus: _catFocus,
              autofocus: true,
              placeholder: 'Select an existing system or type a new one',
              emptyText: 'Type to add a new system',
              onChange: () {
                _sub.clear();
                _subSub.clear();
              },
            ),
          ),
          const SizedBox(height: 16),
          _Field(
            label: 'Category',
            optional: true,
            child: _combo(
              level: 2,
              controller: _sub,
              focus: _subFocus,
              placeholder: 'Select an existing category or type a new one',
              emptyText: 'Type to add a new category',
              onChange: _subSub.clear,
            ),
          ),
          const SizedBox(height: 16),
          _Field(
            label: 'Subcategory',
            optional: true,
            child: _combo(
              level: 3,
              controller: _subSub,
              focus: _subSubFocus,
              placeholder: 'Select an existing subcategory or type a new one',
              emptyText: 'Type to add a new subcategory',
            ),
          ),
        ],
      ),
    );
  }
}
