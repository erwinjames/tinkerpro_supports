import 'package:flutter/material.dart';

import '../models/posversion_models.dart';
import '../services/posversion_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';

class PosVersionListScreen extends StatefulWidget {
  const PosVersionListScreen({super.key, required this.service});
  final PosVersionService service;

  @override
  State<PosVersionListScreen> createState() => _PosVersionListScreenState();
}

class _PosVersionListScreenState extends State<PosVersionListScreen> {
  final _searchController = TextEditingController();
  List<PosVersion> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

  Future<void> _openForm([PosVersion? existing]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            _PosVersionFormScreen(service: widget.service, existing: existing),
      ),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final q = _searchController.text.trim().toLowerCase();
    final rows = q.isEmpty
        ? _rows
        : _rows
              .where(
                (r) =>
                    r.version.toLowerCase().contains(q) ||
                    r.date.toLowerCase().contains(q),
              )
              .toList();
    return StationScaffold(
      stationNumber: '13',
      stationLabel: 'POS versions',
      title: 'Versions',
      subtitle: _loading ? '' : '${_rows.length} releases',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      trailing: StationAction(
        icon: Icons.add_rounded,
        tooltip: 'New version',
        onPressed: _openForm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSearchField(
            controller: _searchController,
            hint: 'Search version or date',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: RefreshIndicator(
              color: b.signal,
              backgroundColor: b.surface,
              onRefresh: _load,
              child: _loading
                  ? const SkeletonList(count: 7)
                  : rows.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 48),
                        EmptyState(
                          icon: Icons.new_releases_rounded,
                          label: _rows.isEmpty
                              ? 'No POS versions'
                              : 'No matching versions',
                          hint: _rows.isEmpty
                              ? 'Tap + to publish the first version. Pull to refresh.'
                              : 'Try a different search.',
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _Entry(
                        index: i,
                        child: _PosVersionRow(
                          row: rows[i],
                          onTap: () => _openForm(rows[i]),
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

class _PosVersionRow extends StatelessWidget {
  const _PosVersionRow({required this.row, required this.onTap});
  final PosVersion row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return AppCard(
      onTap: onTap,
      radius: Brand.radiusLg,
      borderColor: b.signal.withValues(alpha: 0.28),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              color: b.signal.withValues(alpha: b.isDark ? 0.18 : 0.12),
              border: Border.all(color: b.signal.withValues(alpha: 0.4)),
            ),
            child: Icon(
              Icons.new_releases_rounded,
              size: 20,
              color: b.signalInk,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'v${row.version}',
                  style: text.titleSmall?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  row.date.isEmpty ? 'No release date' : 'Released ${row.date}',
                  style: text.bodySmall,
                  maxLines: 1,
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

class _Entry extends StatelessWidget {
  const _Entry({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return child;
    final start = (index.clamp(0, 5)) * 0.12;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 400),
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class _PosVersionFormScreen extends StatefulWidget {
  const _PosVersionFormScreen({required this.service, this.existing});
  final PosVersionService service;
  final PosVersion? existing;

  @override
  State<_PosVersionFormScreen> createState() => _PosVersionFormScreenState();
}

class _PosVersionFormScreenState extends State<_PosVersionFormScreen> {
  late final TextEditingController _version;
  DateTime? _date;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _version = TextEditingController(text: e?.version ?? '');
    if (e?.date != null && e!.date.isNotEmpty) {
      _date = DateTime.tryParse(e.date);
    }
  }

  @override
  void dispose() {
    _version.dispose();
    super.dispose();
  }

  String? get _dateStr => _date == null
      ? null
      : '${_date!.year.toString().padLeft(4, '0')}-'
            '${_date!.month.toString().padLeft(2, '0')}-'
            '${_date!.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final version = _version.text.trim();
    if (version.isEmpty) {
      _toast('Version is required.');
      return;
    }
    if (_dateStr == null) {
      _toast('Pick a release date.');
      return;
    }
    setState(() => _saving = true);
    final PosVersionResult res;
    if (_isEdit) {
      res = await widget.service.update(
        id: widget.existing!.id,
        version: version,
        date: _dateStr!,
      );
    } else {
      res = await widget.service.add(version: version, date: _dateStr!);
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.ok) {
      Navigator.of(context).pop(true);
    } else {
      _toast(res.message ?? 'Could not save the version.');
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const IconTile(
          icon: Icons.delete_outline_rounded,
          color: Brand.danger,
          size: 44,
          iconSize: 22,
        ),
        title: const Text('Delete version?'),
        content: const Text('This permanently removes the POS version.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Brand.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
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
      _toast(res.message ?? 'Could not delete the version.');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return StationScaffold(
      stationNumber: '13',
      stationLabel: 'POS versions',
      title: _isEdit ? 'Edit version' : 'Publish version',
      subtitle: _isEdit ? 'v${widget.existing!.version}' : 'New release',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      bottomBar: Material(
        color: b.surface,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: b.rule)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: SignalButton(
                label: _isEdit ? 'Save changes' : 'Create version',
                icon: Icons.check_rounded,
                busy: _saving,
                onPressed: _saving ? null : _save,
              ),
            ),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 4, bottom: 16),
              children: [
                AppCard(
                  radius: Brand.radiusLg,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const IconTile(
                            icon: Icons.new_releases_rounded,
                            size: 30,
                            iconSize: 16,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('Release', style: text.titleMedium),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text('Version', style: text.labelLarge),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _version,
                        decoration: const InputDecoration(
                          hintText: 'e.g. 2.4.1',
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text('Release date', style: text.labelLarge),
                      const SizedBox(height: 6),
                      Material(
                        color: b.surfaceHi,
                        borderRadius: BorderRadius.circular(Brand.radiusLg),
                        child: InkWell(
                          onTap: _pickDate,
                          borderRadius: BorderRadius.circular(Brand.radiusLg),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.calendar_today_rounded,
                                  size: 18,
                                  color: b.paperDim,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _dateStr ?? 'Tap to pick a date',
                                    style: text.bodyLarge?.copyWith(
                                      color: _dateStr == null
                                          ? b.paperDim
                                          : b.paper,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.expand_more_rounded,
                                  size: 20,
                                  color: b.paperDim,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isEdit) ...[
                  const SizedBox(height: 12),
                  GhostButton(
                    label: 'Delete version',
                    icon: Icons.delete_outline_rounded,
                    onPressed: _delete,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
