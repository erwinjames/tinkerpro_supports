import 'package:flutter/material.dart';

import '../models/releasenotes_models.dart';
import '../services/releasenotes_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';

class ReleaseNotesListScreen extends StatefulWidget {
  const ReleaseNotesListScreen({super.key, required this.service});
  final ReleaseNotesService service;

  @override
  State<ReleaseNotesListScreen> createState() => _ReleaseNotesListScreenState();
}

class _ReleaseNotesListScreenState extends State<ReleaseNotesListScreen> {
  List<ReleaseNote> _rows = const [];
  bool _loading = true;
  String _type = '';

  List<String> get _types {
    final seen = <String>{};
    for (final r in _rows) {
      if (r.type.isNotEmpty) seen.add(r.type);
    }
    return ['', ...seen];
  }

  final TextEditingController _search = TextEditingController();

  List<ReleaseNote> get _matched {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _rows;
    return _rows
        .where(
          (r) => [
            r.version,
            r.type,
            r.notes,
          ].any((f) => f.toLowerCase().contains(q)),
        )
        .toList();
  }

  List<ReleaseNote> get _visible {
    final rows = _matched;
    return _type.isEmpty ? rows : rows.where((r) => r.type == _type).toList();
  }

  void _clearSearch() {
    _search.clear();
    setState(() {});
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
    final rows = await widget.service.list();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _openForm([ReleaseNote? existing]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            _ReleaseNoteFormScreen(service: widget.service, existing: existing),
      ),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return StationScaffold(
      stationNumber: '13',
      stationLabel: 'Releases',
      title: 'Release notes',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      trailing: StationAction(
        icon: Icons.add_rounded,
        tooltip: 'New release note',
        onPressed: _openForm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSearchField(
            controller: _search,
            hint: 'Search release notes',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          if (!_loading && _types.length > 2) ...[
            ChoicePills<String>(
              options: _types,
              value: _types.contains(_type) ? _type : '',
              onChanged: (v) => setState(() => _type = v),
              labelOf: (t) => t.isEmpty ? 'All' : t,
              countOf: (t) => t.isEmpty
                  ? _matched.length
                  : _matched.where((r) => r.type == t).length,
            ),
            const SizedBox(height: 14),
          ],
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
                          icon: Icons.new_releases_rounded,
                          label: 'No release notes',
                          hint: 'Tap + to add the first note. Pull to refresh.',
                        ),
                      ],
                    )
                  : Builder(
                      builder: (context) {
                        final rows = _types.contains(_type)
                            ? _visible
                            : _matched;
                        if (rows.isEmpty) {
                          return ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              const SizedBox(height: 64),
                              EmptyState(
                                icon: Icons.search_off_rounded,
                                label: 'No matches',
                                hint: 'Try a different search.',
                                action: GhostButton(
                                  label: 'Clear search',
                                  onPressed: _clearSearch,
                                ),
                              ),
                            ],
                          );
                        }
                        return ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: 16),
                          itemCount: rows.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) => _Stagger(
                            index: i,
                            child: _ReleaseNoteRow(
                              row: rows[i],
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

Color _typeColor(String type) {
  final t = type.toLowerCase();
  if (t.contains('fix') || t.contains('bug') || t.contains('remove')) {
    return Brand.danger;
  }
  if (t.contains('new') || t.contains('add') || t.contains('feature')) {
    return Brand.success;
  }
  if (t.contains('improve') ||
      t.contains('enhance') ||
      t.contains('update') ||
      t.contains('change')) {
    return Brand.info;
  }
  return Brand.signal;
}

IconData _typeIcon(String type) {
  final t = type.toLowerCase();
  if (t.contains('fix') || t.contains('bug')) return Icons.bug_report_rounded;
  if (t.contains('new') || t.contains('add') || t.contains('feature')) {
    return Icons.auto_awesome_rounded;
  }
  if (t.contains('improve') || t.contains('enhance')) {
    return Icons.trending_up_rounded;
  }
  return Icons.new_releases_rounded;
}

class _ReleaseNoteRow extends StatelessWidget {
  const _ReleaseNoteRow({required this.row, required this.onTap});
  final ReleaseNote row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final color = _typeColor(row.type);
    return AppCard(
      onTap: onTap,
      radius: Brand.radiusLg,
      borderColor: color.withValues(alpha: b.isDark ? 0.34 : 0.26),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TypeTile(
            icon: _typeIcon(row.type),
            color: color,
            size: 44,
            iconSize: 21,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _VersionPill(
                      version: row.version.isEmpty ? 'No version' : row.version,
                    ),
                    if (row.type.isNotEmpty)
                      _GlowChip(label: row.type, color: color),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  row.notes.isEmpty ? 'No notes' : row.notes,
                  style: text.bodyMedium?.copyWith(color: b.paper),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, size: 20, color: b.paperDim),
        ],
      ),
    );
  }
}

class _ReleaseNoteFormScreen extends StatefulWidget {
  const _ReleaseNoteFormScreen({required this.service, this.existing});
  final ReleaseNotesService service;
  final ReleaseNote? existing;

  @override
  State<_ReleaseNoteFormScreen> createState() => _ReleaseNoteFormScreenState();
}

class _ReleaseNoteFormScreenState extends State<_ReleaseNoteFormScreen> {
  late final TextEditingController _notes;
  List<PosVersionRef> _versions = const [];
  List<ActionType> _actionTypes = const [];
  int? _versionId;
  int? _actionTypeId;
  bool _loadingPickers = true;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _notes = TextEditingController(text: e?.notes ?? '');
    _versionId = e?.posversionId;
    _actionTypeId = e?.actionId;
    _loadPickers();
  }

  Future<void> _loadPickers() async {
    final versions = await widget.service.listVersions();
    final actionTypes = await widget.service.listActionTypes();
    if (!mounted) return;
    setState(() {
      _versions = versions;
      _actionTypes = actionTypes;
      if (!versions.any((v) => v.id == _versionId)) _versionId = null;
      if (!actionTypes.any((a) => a.id == _actionTypeId)) _actionTypeId = null;
      _loadingPickers = false;
    });
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_versionId == null) {
      _toast('Pick a version.');
      return;
    }
    if (_actionTypeId == null) {
      _toast('Pick an action type.');
      return;
    }
    final notes = _notes.text.trim();
    if (notes.isEmpty) {
      _toast('Notes are required.');
      return;
    }
    setState(() => _saving = true);
    final ReleaseNotesResult res;
    if (_isEdit) {
      res = await widget.service.update(
        id: widget.existing!.id,
        versionId: _versionId!,
        actionTypeId: _actionTypeId!,
        notes: notes,
      );
    } else {
      res = await widget.service.add(
        versionId: _versionId!,
        actionTypeId: _actionTypeId!,
        notes: notes,
      );
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.ok) {
      Navigator.of(context).pop(true);
    } else {
      _toast(res.message ?? 'Could not save the release note.');
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete release note?'),
        content: const Text('This permanently removes the note.'),
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
      _toast(res.message ?? 'Could not delete the release note.');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String get _versionLabel {
    for (final v in _versions) {
      if (v.id == _versionId) return v.version.isEmpty ? '#${v.id}' : v.version;
    }
    return 'No version';
  }

  String get _typeLabel {
    for (final a in _actionTypes) {
      if (a.id == _actionTypeId) return a.type.isEmpty ? '#${a.id}' : a.type;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final typeLabel = _typeLabel;
    final accent = typeLabel.isEmpty ? b.signal : _typeColor(typeLabel);
    return StationScaffold(
      stationNumber: '13',
      stationLabel: 'Release notes',
      title: _isEdit ? 'Edit note' : 'Add note',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      child: _loadingPickers
          ? const Align(
              alignment: Alignment.topCenter,
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Skeleton(width: 70, height: 12),
                    SizedBox(height: 8),
                    Skeleton(height: 48, radius: 12),
                    SizedBox(height: 18),
                    Skeleton(width: 90, height: 12),
                    SizedBox(height: 8),
                    Skeleton(height: 48, radius: 12),
                    SizedBox(height: 18),
                    Skeleton(width: 50, height: 12),
                    SizedBox(height: 8),
                    Skeleton(height: 110, radius: 12),
                  ],
                ),
              ),
            )
          : ListView(
              children: [
                GlassPanel(
                  accent: accent,
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      _TypeTile(
                        icon: _typeIcon(typeLabel),
                        color: accent,
                        size: 48,
                        iconSize: 24,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Release',
                              style: text.labelMedium?.copyWith(
                                color: b.paperDim,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                _VersionPill(version: _versionLabel),
                                if (typeLabel.isNotEmpty)
                                  _GlowChip(label: typeLabel, color: accent),
                              ],
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
                      _PickerField<int>(
                        label: 'Version',
                        value: _versionId,
                        hint: 'Select a version',
                        icon: Icons.sell_rounded,
                        items: _versions
                            .map(
                              (v) => DropdownMenuItem<int>(
                                value: v.id,
                                child: Text(
                                  v.version.isEmpty ? '#${v.id}' : v.version,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _versionId = v),
                      ),
                      const SizedBox(height: 16),
                      _PickerField<int>(
                        label: 'Action type',
                        value: _actionTypeId,
                        hint: 'Select an action type',
                        icon: Icons.category_rounded,
                        items: _actionTypes
                            .map(
                              (a) => DropdownMenuItem<int>(
                                value: a.id,
                                child: Text(
                                  a.type.isEmpty ? '#${a.id}' : a.type,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _actionTypeId = v),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text('Notes', style: text.labelLarge),
                      ),
                      TextField(
                        controller: _notes,
                        decoration: const InputDecoration(
                          hintText: 'What changed in this release?',
                        ),
                        minLines: 4,
                        maxLines: 8,
                        keyboardType: TextInputType.multiline,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SignalButton(
                  label: _isEdit ? 'Save changes' : 'Create note',
                  busy: _saving,
                  onPressed: _saving ? null : _save,
                ),
                if (_isEdit) ...[
                  const SizedBox(height: 12),
                  GhostButton(
                    label: 'Delete note',
                    icon: Icons.delete_outline_rounded,
                    onPressed: _delete,
                  ),
                ],
                const SizedBox(height: 40),
              ],
            ),
    );
  }
}

class _PickerField<T> extends StatelessWidget {
  const _PickerField({
    required this.label,
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
    this.icon,
  });
  final String label;
  final T? value;
  final String hint;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(label, style: text.labelLarge),
        ),
        DropdownButtonFormField<T>(
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(
            prefixIcon: icon == null ? null : Icon(icon),
          ),
          dropdownColor: b.surface,
          borderRadius: BorderRadius.circular(Brand.radius),
          icon: Icon(Icons.expand_more_rounded, color: b.paperDim),
          style: text.bodyLarge?.copyWith(color: b.paper),
          hint: Text(hint, style: text.bodyMedium?.copyWith(color: b.paperDim)),
          items: items,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

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

Color _chipInk(BuildContext context, Color color) {
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

class _GlowChip extends StatelessWidget {
  const _GlowChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final ink = _chipInk(context, color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: b.isDark ? 0.18 : 0.12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: ink,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
    );
  }
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
      child: Icon(icon, size: iconSize, color: _chipInk(context, color)),
    );
  }
}

class _VersionPill extends StatelessWidget {
  const _VersionPill({required this.version});

  final String version;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: b.signal.withValues(alpha: b.isDark ? 0.18 : 0.12),
        border: Border.all(color: b.signal.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sell_rounded, size: 13, color: b.signalInk),
          const SizedBox(width: 5),
          Text(
            version,
            style: TextStyle(
              color: b.signalInk,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              height: 1.2,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
