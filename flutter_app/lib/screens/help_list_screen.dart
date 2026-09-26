import 'package:flutter/material.dart';

import '../models/help_models.dart';
import '../services/help_service.dart';
import '../theme.dart';
import '../widgets/help_editor.dart';
import '../widgets/help_html.dart';
import '../widgets/html_editor.dart';
import '../widgets/premium.dart';

class HelpListScreen extends StatefulWidget {
  const HelpListScreen({super.key, required this.service});
  final HelpService service;

  @override
  State<HelpListScreen> createState() => _HelpListScreenState();
}

class _HelpListScreenState extends State<HelpListScreen> {
  List<HelpTopic> _rows = const [];
  HelpCategoryTree _tree = const HelpCategoryTree.fallback();
  bool _loading = true;
  String _system = 'all';
  String _category = '';
  String _subcategory = '';
  final TextEditingController _search = TextEditingController();

  List<HelpTopic> get _visible {
    final q = _search.text.trim().toLowerCase();
    var rows = _rows;
    if (_system != 'all') {
      rows = rows
          .where((r) => _tree.normalizeSystem(r.category) == _system)
          .toList();
      if (_category.isNotEmpty) {
        rows = rows
            .where(
              (r) =>
                  _tree.normalizeCategory(r.category, r.subcategory) ==
                  _category,
            )
            .toList();
        if (_subcategory.isNotEmpty) {
          rows = rows
              .where(
                (r) =>
                    _tree.normalizeSubcategory(
                      r.category,
                      r.subcategory,
                      r.subsubcategory,
                    ) ==
                    _subcategory,
              )
              .toList();
        }
      }
    }
    if (q.isEmpty) return rows;
    return rows
        .where(
          (r) => [
            r.title,
            r.subtitle,
            _stripHtml(r.description),
            r.icon.replaceFirst('fa-', '').replaceAll('-', ' '),
          ].any((f) => f.toLowerCase().contains(q)),
        )
        .toList();
  }

  void _clearSearch() {
    _search.clear();
    setState(() {
      _system = 'all';
      _category = '';
      _subcategory = '';
    });
  }

  bool get _filtered => _system != 'all' || _search.text.trim().isNotEmpty;

  void _syncFilters() {
    if (_system != 'all' && _tree.system(_system) == null) {
      _system = 'all';
    }
    final sys = _tree.system(_system);
    final cat = sys?.child(_category);
    if (cat == null) _category = '';
    if (cat?.child(_subcategory) == null) _subcategory = '';
  }

  Widget _filters() {
    final sys = _tree.system(_system);
    final cat = sys?.child(_category);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        ChoicePills<String>(
          options: ['all', ..._tree.systems.map((s) => s.slug)],
          value: _system,
          labelOf: (v) => v == 'all' ? 'All' : (_tree.system(v)?.name ?? v),
          onChanged: (v) => setState(() {
            _system = v;
            _category = '';
            _subcategory = '';
          }),
        ),
        if (sys != null && sys.children.isNotEmpty) ...[
          const SizedBox(height: 8),
          ChoicePills<String>(
            options: ['', ...sys.children.map((c) => c.slug)],
            value: _category,
            labelOf: (v) =>
                v.isEmpty ? 'All ${sys.name}' : (sys.child(v)?.name ?? v),
            onChanged: (v) => setState(() {
              _category = v;
              _subcategory = '';
            }),
          ),
        ],
        if (cat != null && cat.children.isNotEmpty) ...[
          const SizedBox(height: 8),
          ChoicePills<String>(
            options: ['', ...cat.children.map((c) => c.slug)],
            value: _subcategory,
            labelOf: (v) =>
                v.isEmpty ? 'All ${cat.name}' : (cat.child(v)?.name ?? v),
            onChanged: (v) => setState(() => _subcategory = v),
          ),
        ],
      ],
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      widget.service.list(),
      widget.service.categories(),
    ]);
    if (!mounted) return;
    setState(() {
      _rows = results[0] as List<HelpTopic>;
      _tree = results[1] as HelpCategoryTree;
      _syncFilters();
      _loading = false;
    });
  }

  Future<void> _openForm([HelpTopic? existing]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => _HelpFormScreen(
          service: widget.service,
          existing: existing,
          tree: _tree,
        ),
      ),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return StationScaffold(
      stationNumber: '··',
      stationLabel: 'Help',
      title: 'Help topics',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      trailing: StationAction(
        icon: Icons.add_rounded,
        tooltip: 'New help topic',
        onPressed: _openForm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSearchField(
            controller: _search,
            hint: 'Search help topics',
            onChanged: (_) => setState(() {}),
          ),
          _filters(),
          const SizedBox(height: 12),
          Expanded(
            child: RefreshIndicator(
              color: b.signal,
              backgroundColor: b.surface,
              onRefresh: _load,
              child: _loading
                  ? const SkeletonList(count: 6)
                  : _rows.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 64),
                        EmptyState(
                          icon: Icons.help_center_rounded,
                          label: 'No help topics',
                          hint:
                              'Tap + to add the first topic. Pull to refresh.',
                        ),
                      ],
                    )
                  : _visible.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 64),
                        EmptyState(
                          icon: Icons.search_off_rounded,
                          label: 'No matches',
                          hint: _filtered
                              ? 'Try a different search or filter.'
                              : 'Try a different search.',
                          action: GhostButton(
                            label: 'Clear filters',
                            onPressed: _clearSearch,
                          ),
                        ),
                      ],
                    )
                  : Builder(
                      builder: (context) {
                        final rows = _visible;
                        return ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: 16),
                          itemCount: rows.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) => _Stagger(
                            index: i,
                            child: _HelpRow(
                              row: rows[i],
                              trail: _tree.labels(
                                rows[i].category,
                                rows[i].subcategory,
                                rows[i].subsubcategory,
                              ),
                              onTap: () => _openForm(rows[i]),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

Color _visibleColor(BuildContext context, Color? color) {
  final b = context.brand;
  final c = color ?? b.signal;
  if (b.isDark && c.computeLuminance() < 0.03) return b.paper;
  return c;
}

class _HelpRow extends StatelessWidget {
  const _HelpRow({required this.row, required this.trail, required this.onTap});
  final HelpTopic row;
  final List<String> trail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final preview = row.subtitle.trim().isNotEmpty
        ? row.subtitle.trim()
        : _stripHtml(row.description);
    final accent = _visibleColor(context, parseHelpColor(row.iconColor));
    return AppCard(
      onTap: onTap,
      radius: Brand.radiusLg,
      borderColor: accent.withValues(alpha: b.isDark ? 0.34 : 0.26),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TypeTile(
            icon: helpIconData(row.icon),
            color: accent,
            size: 44,
            iconSize: 21,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.title.isEmpty ? 'Untitled topic' : row.title,
                  style: text.titleSmall,
                ),
                const SizedBox(height: 6),
                _PathPill(trail: trail),
                const SizedBox(height: 6),
                Text(
                  preview.isEmpty ? 'No description' : preview,
                  style: text.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded, size: 20, color: b.paperDim),
        ],
      ),
    );
  }
}

class _HelpFormScreen extends StatefulWidget {
  const _HelpFormScreen({
    required this.service,
    required this.tree,
    this.existing,
  });
  final HelpService service;
  final HelpCategoryTree tree;
  final HelpTopic? existing;

  @override
  State<_HelpFormScreen> createState() => _HelpFormScreenState();
}

class _HelpFormScreenState extends State<_HelpFormScreen> {
  late final TextEditingController _title;
  late final TextEditingController _subtitle;
  late final TextEditingController _content;
  final TextEditingController _iconSearch = TextEditingController();
  late String _icon;
  late String _iconColor;
  late String _system;
  late String _category;
  late String _subcategory;
  late HelpCategoryTree _tree;
  bool _saving = false;
  bool _categoryBusy = false;
  bool _treeChanged = false;
  bool _contentLoading = false;
  bool _contentReady = false;
  String _contentError = '';
  String _contentLoaded = '';

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _tree = widget.tree;
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _subtitle = TextEditingController(text: e?.subtitle ?? '');
    _content = TextEditingController();
    _icon = (e?.icon.isNotEmpty ?? false) ? e!.icon : kDefaultHelpIcon;
    _iconColor = (e?.iconColor.isNotEmpty ?? false)
        ? e!.iconColor
        : kDefaultHelpColor;
    if (e == null) {
      _system = '';
      _category = '';
      _subcategory = '';
    } else {
      _system = _tree.normalizeSystem(e.category);
      _category = _tree.normalizeCategory(_system, e.subcategory);
      _subcategory = _tree.normalizeSubcategory(
        _system,
        _category,
        e.subsubcategory,
      );
    }
    if (e == null) {
      _contentReady = true;
    } else {
      _loadContent();
    }
  }

  Future<void> _loadContent() async {
    setState(() {
      _contentLoading = true;
      _contentError = '';
    });
    final res = await widget.service.content(widget.existing!.id);
    if (!mounted) return;
    setState(() {
      _contentLoading = false;
      if (res.ok) {
        _contentReady = true;
        _contentLoaded = res.html;
        _content.text = res.html;
      } else {
        _contentError =
            res.message ??
            'Could not load the document content. Saving now would wipe it.';
      }
    });
  }

  String get _effectiveSystem => _system.isEmpty ? kDefaultHelpSystem : _system;

  List<HelpCategoryNode> get _categoryOptions =>
      _tree.system(_effectiveSystem)?.children ?? const [];

  List<HelpCategoryNode> get _subcategoryOptions =>
      _tree.system(_effectiveSystem)?.child(_category)?.children ?? const [];

  @override
  void dispose() {
    _title.dispose();
    _subtitle.dispose();
    _content.dispose();
    _iconSearch.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      _toast('Title is required.');
      return;
    }
    final html = _content.text.trim();
    setState(() => _saving = true);
    final HelpResult res;
    if (_isEdit) {
      res = await widget.service.update(
        id: widget.existing!.id,
        title: title,
        subtitle: _subtitle.text,
        icon: _icon,
        iconColor: _iconColor,
        category: _tree.loaded ? _effectiveSystem : null,
        subcategory: _tree.loaded ? _category : null,
        subsubcategory: _tree.loaded ? _subcategory : null,
      );
      if (res.ok && _contentReady && html != _contentLoaded.trim()) {
        final saved = await widget.service.saveContent(
          topicId: widget.existing!.id,
          html: html,
        );
        if (!saved.ok) {
          if (!mounted) return;
          setState(() => _saving = false);
          _toast(saved.message ?? 'Could not save the document content.');
          return;
        }
        _contentLoaded = html;
      }
    } else {
      res = await widget.service.add(
        title: title,
        subtitle: _subtitle.text,
        description: helpHtmlSummary(html),
        contentHtml: html,
        icon: _icon,
        iconColor: _iconColor,
        category: _effectiveSystem,
        subcategory: _category,
        subsubcategory: _subcategory,
      );
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.ok) {
      Navigator.of(context).pop(true);
    } else {
      _toast(res.message ?? 'Could not save the topic.');
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete help topic?'),
        content: const Text(
          'This permanently removes the topic and its content.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Brand.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    final res = await widget.service.delete(widget.existing!.id);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.ok) {
      Navigator.of(context).pop(true);
    } else {
      _toast(res.message ?? 'Could not delete the topic.');
    }
  }

  Future<String?> _promptName({
    required String title,
    required String hint,
    required String helper,
  }) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) {
          final typed = controller.text.trim();
          return AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLength: 100,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(hintText: hint, counterText: ''),
                  onChanged: (_) => setInner(() {}),
                  onSubmitted: (v) {
                    if (v.trim().isNotEmpty) Navigator.of(ctx).pop(v.trim());
                  },
                ),
                const SizedBox(height: 8),
                Text(helper, style: Theme.of(ctx).textTheme.bodySmall),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: typed.isEmpty
                    ? null
                    : () => Navigator.of(ctx).pop(typed),
                child: const Text('Save Category'),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    return value;
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Brand.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<bool> _reloadTree() async {
    final tree = await widget.service.categories();
    if (!mounted) return false;
    if (!tree.loaded) return false;
    setState(() {
      _tree = tree;
      _treeChanged = true;
    });
    return true;
  }

  Future<void> _addSystem() async {
    final name = await _promptName(
      title: 'Add system',
      hint: 'Type a new system',
      helper: 'Top level, such as V1, V2, Invoice or CRM.',
    );
    if (name == null || !mounted) return;
    setState(() => _categoryBusy = true);
    final res = await widget.service.addCategory(category: name);
    if (!mounted) return;
    setState(() => _categoryBusy = false);
    if (!res.ok) {
      _toast(res.message ?? 'Could not save the category');
      return;
    }
    _treeChanged = true;
    await _reloadTree();
    if (!mounted) return;
    final slug = res.category?.slug ?? '';
    setState(() {
      if (slug.isNotEmpty &&
          slug != _effectiveSystem &&
          _tree.system(slug) != null) {
        _system = slug;
      }
      _category = '';
      _subcategory = '';
    });
    _toast('System saved!');
  }

  Future<void> _addCategory() async {
    final sys = _tree.system(_effectiveSystem);
    if (sys == null) return;
    final name = await _promptName(
      title: 'Add category',
      hint: 'Type a new category',
      helper: 'Sits under ${sys.name}.',
    );
    if (name == null || !mounted) return;
    setState(() => _categoryBusy = true);
    final res = await widget.service.addCategory(
      category: sys.name,
      subcategory: name,
    );
    if (!mounted) return;
    setState(() => _categoryBusy = false);
    if (!res.ok) {
      _toast(res.message ?? 'Could not save the category');
      return;
    }
    _treeChanged = true;
    await _reloadTree();
    if (!mounted) return;
    final system = res.category?.slug ?? sys.slug;
    final slug = res.subcategory?.slug ?? '';
    setState(() {
      if (system != _effectiveSystem && _tree.system(system) != null) {
        _system = system;
      }
      _category = _tree.normalizeCategory(_effectiveSystem, slug);
      _subcategory = '';
    });
    _toast('System and category saved!');
  }

  Future<void> _addSubcategory() async {
    final sys = _tree.system(_effectiveSystem);
    final cat = sys?.child(_category);
    if (sys == null || cat == null) {
      _toast('Pick or type a category before adding a subcategory');
      return;
    }
    final name = await _promptName(
      title: 'Add subcategory',
      hint: 'Type a new subcategory',
      helper: 'Sits under ${cat.name}.',
    );
    if (name == null || !mounted) return;
    setState(() => _categoryBusy = true);
    final res = await widget.service.addCategory(
      category: sys.name,
      subcategory: cat.name,
      subsubcategory: name,
    );
    if (!mounted) return;
    setState(() => _categoryBusy = false);
    if (!res.ok) {
      _toast(res.message ?? 'Could not save the category');
      return;
    }
    _treeChanged = true;
    await _reloadTree();
    if (!mounted) return;
    final slug = res.subsubcategory?.slug ?? '';
    setState(() {
      _subcategory = _tree.normalizeSubcategory(
        _effectiveSystem,
        _category,
        slug,
      );
    });
    _toast('System, category and subcategory saved!');
  }

  Future<void> _deleteCategory() async {
    final sys = _tree.system(_effectiveSystem);
    final cat = sys?.child(_category);
    if (sys == null || cat == null) return;
    final ok = await _confirm(
      title: 'Delete this category?',
      message:
          '"${cat.name}" and its subcategories will be removed. Topics under it stay, but lose the category.',
      confirmLabel: 'Delete category',
    );
    if (!ok || !mounted) return;
    setState(() => _categoryBusy = true);
    final res = await widget.service.deleteSubcategory(
      category: sys.slug,
      subcategory: cat.slug,
    );
    if (!mounted) return;
    setState(() => _categoryBusy = false);
    if (!res.ok) {
      _toast(res.message ?? 'Could not delete the category');
      return;
    }
    _treeChanged = true;
    await _reloadTree();
    if (!mounted) return;
    setState(() {
      _category = '';
      _subcategory = '';
    });
    _toast('Category "${cat.name}" deleted');
  }

  Future<void> _deleteSubcategory() async {
    final sys = _tree.system(_effectiveSystem);
    final cat = sys?.child(_category);
    final sub = cat?.child(_subcategory);
    if (sys == null || cat == null || sub == null) return;
    final ok = await _confirm(
      title: 'Delete this subcategory?',
      message:
          '"${sub.name}" will be removed. Topics under it stay, but lose the subcategory.',
      confirmLabel: 'Delete subcategory',
    );
    if (!ok || !mounted) return;
    setState(() => _categoryBusy = true);
    final res = await widget.service.deleteSubcategory(
      category: sys.slug,
      subcategory: cat.slug,
      subsubcategory: sub.slug,
    );
    if (!mounted) return;
    setState(() => _categoryBusy = false);
    if (!res.ok) {
      _toast(res.message ?? 'Could not delete the subcategory');
      return;
    }
    _treeChanged = true;
    await _reloadTree();
    if (!mounted) return;
    setState(() => _subcategory = '');
    _toast('Subcategory "${sub.name}" deleted');
  }

  Future<void> _pickIconColor() async {
    final picked = await showAppColorPicker(
      context,
      _iconColor,
      presets: kHelpColors,
    );
    if (picked == null || !mounted) return;
    setState(() => _iconColor = picked);
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final color = _visibleColor(context, parseHelpColor(_iconColor));
    return PopScope<bool>(
      canPop: !_treeChanged,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || !mounted) return;
        Navigator.of(context).pop(true);
      },
      child: StationScaffold(
        stationNumber: '··',
        stationLabel: 'Help',
        title: _isEdit ? 'Edit topic' : 'Add topic',
        showBottomBrand: false,
        onBack: () => Navigator.of(context).pop(_treeChanged ? true : null),
        child: ListView(
          children: [
            GlassPanel(
              accent: color,
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  _TypeTile(
                    icon: helpIconData(_icon),
                    color: color,
                    size: 52,
                    iconSize: 26,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Preview',
                          style: text.labelMedium?.copyWith(color: b.paperDim),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _title.text.trim().isEmpty
                              ? 'Topic preview'
                              : _title.text.trim(),
                          style: text.titleMedium?.copyWith(color: b.paper),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_subtitle.text.trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            _subtitle.text.trim(),
                            style: text.bodySmall?.copyWith(color: b.paperDim),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 8),
                        _PathPill(
                          trail: _tree.labels(
                            _effectiveSystem,
                            _category,
                            _subcategory,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AppCard(
              radius: Brand.radiusLg,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _label(text, 'Title'),
                  TextField(
                    controller: _title,
                    decoration: const InputDecoration(hintText: 'Topic title'),
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                  _label(text, 'Subtitle'),
                  TextField(
                    controller: _subtitle,
                    maxLength: 255,
                    decoration: const InputDecoration(
                      hintText: 'Enter topic subtitle',
                      counterText: '',
                    ),
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => setState(() {}),
                  ),
                  _hint(text, 'Optional short line shown under the title.'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AppCard(
              radius: Brand.radiusLg,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _label(text, 'Content'),
                  if (_contentLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Skeleton(height: 44, radius: 12),
                          SizedBox(height: 10),
                          Skeleton(height: 220, radius: 12),
                        ],
                      ),
                    )
                  else if (_contentError.isNotEmpty) ...[
                    Text(
                      _contentError,
                      style: text.bodySmall?.copyWith(color: Brand.danger),
                    ),
                    const SizedBox(height: 10),
                    GhostButton(
                      label: 'Retry loading content',
                      icon: Icons.refresh_rounded,
                      onPressed: _loadContent,
                    ),
                  ] else
                    HelpContentEditor(
                      controller: _content,
                      service: widget.service,
                      colorPresets: kHelpColors,
                      enabled: !_saving,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AppCard(
              radius: Brand.radiusLg,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _levelHeader(
                    text,
                    'System',
                    addTooltip: 'Add system',
                    onAdd: _categoryBusy ? null : _addSystem,
                  ),
                  _dropdown(
                    key: ValueKey('help-system-$_system'),
                    value: _system,
                    items: [
                      if (!_isEdit) const MapEntry('', 'No system (V1)'),
                      for (final s in _tree.systems)
                        if (_isEdit || s.slug != kDefaultHelpSystem)
                          MapEntry(s.slug, s.name),
                    ],
                    onChanged: (v) => setState(() {
                      _system = v;
                      _category = '';
                      _subcategory = '';
                    }),
                  ),
                  _hint(
                    text,
                    'Leave as "No system" to file this document under V1.',
                  ),
                  const SizedBox(height: 16),
                  _levelHeader(
                    text,
                    'Category',
                    addTooltip: 'Add category',
                    onAdd: _categoryBusy ? null : _addCategory,
                    deleteTooltip: 'Delete category',
                    onDelete: _categoryBusy || _category.isEmpty
                        ? null
                        : _deleteCategory,
                  ),
                  _dropdown(
                    key: ValueKey('help-category-$_effectiveSystem-$_category'),
                    value: _category,
                    items: [
                      const MapEntry('', 'None'),
                      for (final c in _categoryOptions)
                        MapEntry(c.slug, c.name),
                    ],
                    onChanged: _categoryOptions.isEmpty
                        ? null
                        : (v) => setState(() {
                            _category = v;
                            _subcategory = '';
                          }),
                  ),
                  _hint(text, 'Optional. Add new ones with the New button.'),
                  const SizedBox(height: 16),
                  _levelHeader(
                    text,
                    'Subcategory',
                    addTooltip: 'Add subcategory',
                    onAdd: _categoryBusy ? null : _addSubcategory,
                    deleteTooltip: 'Delete subcategory',
                    onDelete: _categoryBusy || _subcategory.isEmpty
                        ? null
                        : _deleteSubcategory,
                  ),
                  _dropdown(
                    key: ValueKey(
                      'help-subcategory-$_effectiveSystem/$_category-$_subcategory',
                    ),
                    value: _subcategory,
                    items: [
                      const MapEntry('', 'None'),
                      for (final c in _subcategoryOptions)
                        MapEntry(c.slug, c.name),
                    ],
                    onChanged: _subcategoryOptions.isEmpty
                        ? null
                        : (v) => setState(() => _subcategory = v),
                  ),
                  _hint(text, 'Optional. Sits under the category.'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AppCard(
              radius: Brand.radiusLg,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _label(text, 'Search Icon'),
                  AppSearchField(
                    controller: _iconSearch,
                    hint: 'Search icons…',
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 264),
                    child: SingleChildScrollView(
                      child: _IconGrid(
                        selected: _icon,
                        color: color,
                        query: _iconSearch.text,
                        onSelected: (v) => setState(() => _icon = v),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _label(text, 'Icon Colour'),
                  const SizedBox(height: 6),
                  _ColorPalette(
                    selected: _iconColor,
                    onSelected: (v) => setState(() => _iconColor = v),
                    onCustom: _pickIconColor,
                  ),
                  const SizedBox(height: 20),
                  _label(text, 'Preview'),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    decoration: BoxDecoration(
                      color: b.surfaceHi,
                      borderRadius: BorderRadius.circular(Brand.radiusSm),
                      border: Border.all(color: b.rule),
                    ),
                    child: Column(
                      children: [
                        _TypeTile(
                          icon: helpIconData(_icon),
                          color: color,
                          size: 64,
                          iconSize: 32,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _iconColor.toUpperCase(),
                          style: text.bodySmall?.copyWith(color: b.paperDim),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SignalButton(
              label: _isEdit ? 'Save changes' : 'Create topic',
              busy: _saving,
              onPressed: _saving ? null : _save,
            ),
            if (_isEdit) ...[
              const SizedBox(height: 12),
              GhostButton(
                label: 'Delete topic',
                icon: Icons.delete_outline_rounded,
                onPressed: _delete,
              ),
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _dropdown({
    required Key key,
    required String value,
    required List<MapEntry<String, String>> items,
    required ValueChanged<String>? onChanged,
  }) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final selected = items.any((e) => e.key == value)
        ? value
        : (items.isEmpty ? null : items.first.key);
    return DropdownButtonFormField<String>(
      key: key,
      initialValue: selected,
      isExpanded: true,
      dropdownColor: b.surface,
      borderRadius: BorderRadius.circular(Brand.radius),
      icon: Icon(Icons.expand_more_rounded, color: b.paperDim),
      style: text.bodyLarge?.copyWith(color: b.paper),
      items: [
        for (final e in items)
          DropdownMenuItem<String>(
            value: e.key,
            child: Text(e.value, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged == null
          ? null
          : (v) {
              if (v != null) onChanged(v);
            },
    );
  }

  Widget _hint(TextTheme text, String hint) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(hint, style: text.bodySmall),
    );
  }

  Widget _label(TextTheme text, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(label, style: text.labelLarge),
    );
  }

  Widget _levelHeader(
    TextTheme text,
    String label, {
    required String addTooltip,
    required VoidCallback? onAdd,
    String? deleteTooltip,
    VoidCallback? onDelete,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: text.labelLarge)),
          if (deleteTooltip != null) ...[
            _MiniAction(
              icon: Icons.delete_outline_rounded,
              label: 'Delete',
              tooltip: deleteTooltip,
              color: Brand.danger,
              onPressed: onDelete,
            ),
            const SizedBox(width: 8),
          ],
          _MiniAction(
            icon: Icons.add_rounded,
            label: 'New',
            tooltip: addTooltip,
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final enabled = onPressed != null;
    final tone = color ?? b.signal;
    final ink = enabled ? _tileInk(context, tone) : b.paperDim;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        child: Material(
          color: enabled ? b.tint(tone, 0.14) : b.surfaceHi,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Brand.radiusSm),
            side: BorderSide(
              color: enabled ? tone.withValues(alpha: 0.4) : b.rule,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              height: 44,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 16, color: ink),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(
                        color: ink,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IconGrid extends StatelessWidget {
  const _IconGrid({
    required this.selected,
    required this.color,
    required this.onSelected,
    this.query = '',
  });
  final String selected;
  final Color color;
  final String query;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final needle = query.trim().toLowerCase();
    final icons = kHelpIconMap.keys
        .where((fa) => needle.isEmpty || fa.contains(needle))
        .toList();
    if (icons.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'No icons match.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: icons.map((fa) {
        final active = fa == selected;
        return Tooltip(
          message: fa.replaceFirst('fa-', '').replaceAll('-', ' '),
          child: InkWell(
            onTap: () => onSelected(fa),
            borderRadius: BorderRadius.circular(Brand.radiusSm),
            child: AnimatedContainer(
              duration: MediaQuery.of(context).disableAnimations
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: active ? b.tint(color, 0.18) : b.surfaceHi,
                borderRadius: BorderRadius.circular(Brand.radiusSm),
                border: Border.all(
                  color: active ? color : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Icon(
                kHelpIconMap[fa],
                size: 20,
                color: active ? color : b.paperDim,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ColorPalette extends StatelessWidget {
  const _ColorPalette({
    required this.selected,
    required this.onSelected,
    this.onCustom,
  });
  final String selected;
  final ValueChanged<String> onSelected;
  final VoidCallback? onCustom;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final custom = !kHelpColors.any(
      (hex) => hex.toUpperCase() == selected.toUpperCase(),
    );
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        ...[...kHelpColors, if (custom) selected].map((hex) {
          final active = hex.toUpperCase() == selected.toUpperCase();
          final color = parseHelpColor(hex)!;
          return Semantics(
            button: true,
            selected: active,
            label: 'Color $hex',
            child: InkWell(
              onTap: () => onSelected(hex),
              customBorder: const CircleBorder(),
              child: AnimatedContainer(
                duration: MediaQuery.of(context).disableAnimations
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                width: 44,
                height: 44,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: active ? b.paper : b.rule,
                    width: active ? 2 : 1,
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                  child: active
                      ? const Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: Colors.white,
                        )
                      : null,
                ),
              ),
            ),
          );
        }),
        if (onCustom != null)
          Tooltip(
            message: 'Custom colour',
            child: Semantics(
              button: true,
              label: 'Custom colour',
              child: InkWell(
                onTap: onCustom,
                customBorder: const CircleBorder(),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: b.surfaceHi,
                    border: Border.all(color: b.rule),
                  ),
                  child: Icon(
                    Icons.colorize_rounded,
                    size: 18,
                    color: b.paperDim,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

const String kDefaultHelpIcon = 'fa-question-circle';
const String kDefaultHelpColor = '#FF7D00';

const Map<String, IconData> kHelpIconMap = {
  'fa-question-circle': Icons.help_outline_rounded,
  'fa-lightbulb': Icons.lightbulb_outline_rounded,
  'fa-info-circle': Icons.info_outline_rounded,
  'fa-cogs': Icons.settings_suggest_rounded,
  'fa-book': Icons.menu_book_rounded,
  'fa-comments': Icons.forum_rounded,
  'fa-envelope': Icons.mail_outline_rounded,
  'fa-headset': Icons.headset_mic_rounded,
  'fa-globe': Icons.public_rounded,
  'fa-bell': Icons.notifications_none_rounded,
  'fa-wrench': Icons.build_rounded,
  'fa-user': Icons.person_outline_rounded,
  'fa-shield-alt': Icons.shield_rounded,
  'fa-lock': Icons.lock_outline_rounded,
  'fa-paper-plane': Icons.send_rounded,
  'fa-star': Icons.star_border_rounded,
  'fa-thumbs-up': Icons.thumb_up_off_alt_rounded,
  'fa-heart': Icons.favorite_border_rounded,
  'fa-exclamation-triangle': Icons.warning_amber_rounded,
  'fa-bug': Icons.bug_report_rounded,
  'fa-calendar': Icons.calendar_today_rounded,
  'fa-camera': Icons.photo_camera_rounded,
  'fa-chart-bar': Icons.bar_chart_rounded,
  'fa-check-circle': Icons.check_circle_outline_rounded,
  'fa-cloud': Icons.cloud_rounded,
  'fa-database': Icons.storage_rounded,
  'fa-edit': Icons.edit_rounded,
  'fa-flag': Icons.flag_rounded,
  'fa-gift': Icons.card_giftcard_rounded,
  'fa-home': Icons.home_rounded,
  'fa-key': Icons.vpn_key_rounded,
  'fa-magic': Icons.auto_fix_high_rounded,
  'fa-map-marker': Icons.location_on_rounded,
  'fa-microphone': Icons.mic_none_rounded,
  'fa-phone': Icons.phone_rounded,
  'fa-rocket': Icons.rocket_launch_rounded,
  'fa-search': Icons.search_rounded,
  'fa-shopping-cart': Icons.shopping_cart_rounded,
  'fa-signal': Icons.signal_cellular_alt_rounded,
  'fa-sitemap': Icons.account_tree_rounded,
  'fa-tag': Icons.sell_rounded,
  'fa-th-large': Icons.grid_view_rounded,
  'fa-tools': Icons.handyman_rounded,
  'fa-truck': Icons.local_shipping_rounded,
  'fa-tv': Icons.tv_rounded,
  'fa-video': Icons.videocam_rounded,
  'fa-wifi': Icons.wifi_rounded,
  'fa-barcode': Icons.qr_code_2_rounded,
  'fa-receipt': Icons.receipt_long_rounded,
  'fa-computer': Icons.desktop_windows_rounded,
  'fa-laptop-code': Icons.laptop_mac_rounded,
  'fa-print': Icons.print_rounded,
  'fa-keyboard': Icons.keyboard_rounded,
  'fa-coffee': Icons.local_cafe_rounded,
  'fa-copy': Icons.copy_rounded,
  'fa-moon': Icons.dark_mode_rounded,
  'fa-paint-brush': Icons.brush_rounded,
  'fa-sliders-h': Icons.tune_rounded,
  'fa-smile': Icons.sentiment_satisfied_rounded,
  'fa-snowflake': Icons.ac_unit_rounded,
  'fa-sun': Icons.light_mode_rounded,
  'fa-umbrella': Icons.umbrella_rounded,
  'fa-arrow-right-to-bracket': Icons.login_rounded,
  'fa-arrow-rotate-left': Icons.undo_rounded,
  'fa-mouse': Icons.mouse_rounded,
};

const List<String> kHelpColors = [
  '#FF7D00',
  '#000000',
  '#0066CC',
  '#198754',
  '#DC3545',
  '#6F42C1',
  '#FD7E14',
  '#20C997',
  '#6C757D',
];

IconData helpIconData(String fa) =>
    kHelpIconMap[fa] ?? Icons.help_outline_rounded;

Color? parseHelpColor(String hex) {
  var value = hex.trim();
  if (value.startsWith('#')) value = value.substring(1);
  if (value.length == 6) value = 'FF$value';
  if (value.length != 8) return null;
  final parsed = int.tryParse(value, radix: 16);
  return parsed == null ? null : Color(parsed);
}

String _stripHtml(String html) => helpHtmlToPlain(html);

class _Stagger extends StatelessWidget {
  const _Stagger({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce || index > 7) return child;
    final delay = index * 45;
    final total = 280 + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: Curves.easeOutCubic),
      builder: (context, t, inner) => Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 14),
          child: inner,
        ),
      ),
      child: child,
    );
  }
}

Color _tileInk(BuildContext context, Color color) {
  final b = context.brand;
  if (b.isDark) {
    return color.computeLuminance() < 0.22
        ? Color.lerp(color, Colors.white, 0.6)!
        : color;
  }
  return color.computeLuminance() > 0.3
      ? Color.lerp(color, Brand.navy, 0.45)!
      : color;
}

class _TypeTile extends StatelessWidget {
  const _TypeTile({
    required this.icon,
    required this.color,
    this.size = 44,
    this.iconSize = 21,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        color: color.withValues(alpha: b.isDark ? 0.18 : 0.12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Icon(icon, size: iconSize, color: _tileInk(context, color)),
    );
  }
}

class _PathPill extends StatelessWidget {
  const _PathPill({required this.trail});

  final List<String> trail;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final label = trail.where((t) => t.trim().isNotEmpty).join(' › ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: b.signal.withValues(alpha: b.isDark ? 0.18 : 0.12),
        border: Border.all(color: b.signal.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.account_tree_rounded, size: 13, color: b.signalInk),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label.isEmpty ? 'Uncategorised' : label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: b.signalInk,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
