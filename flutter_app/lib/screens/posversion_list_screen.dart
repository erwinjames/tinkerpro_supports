import 'package:flutter/material.dart';

import '../models/posversion_models.dart';
import '../services/posversion_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';

/// POS Versions — native CRUD. List of released POS versions with create /
/// edit / delete, backed by the `*posversion` actions on api.php.
class PosVersionListScreen extends StatefulWidget {
  const PosVersionListScreen({super.key, required this.service});
  final PosVersionService service;

  @override
  State<PosVersionListScreen> createState() => _PosVersionListScreenState();
}

class _PosVersionListScreenState extends State<PosVersionListScreen> {
  List<PosVersion> _rows = const [];
  bool _loading = true;

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
    return StationScaffold(
      stationNumber: '13',
      stationLabel: 'POS VERSIONS',
      title: 'Versions.',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      trailing: StationAction(
        icon: Icons.add,
        tooltip: 'New version',
        onPressed: _openForm,
      ),
      child: RefreshIndicator(
        color: Brand.signal,
        backgroundColor: Brand.surface,
        onRefresh: _load,
        child: _loading
            ? const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Brand.signal),
                ),
              )
            : _rows.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 64),
                      EmptyState(
                        label: 'No POS versions',
                        hint: 'Tap + to publish the first version. '
                            'Pull to refresh.',
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _rows.length,
                    separatorBuilder: (_, _) => const Hairline(),
                    itemBuilder: (_, i) => _PosVersionRow(
                      row: _rows[i],
                      onTap: () => _openForm(_rows[i]),
                    ),
                  ),
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
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 7, right: 12),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Brand.signal,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('v${row.version}',
                      style: text.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Text(
                    row.date.isEmpty ? 'No release date' : 'Released ${row.date}',
                    style: text.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Add / edit form. Version string + a release date picker (YYYY-MM-DD).
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
      res = await widget.service.add(
        version: version,
        date: _dateStr!,
      );
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
      builder: (_) => AlertDialog(
        backgroundColor: Brand.surface,
        title: const Text('Delete version?'),
        content: const Text('This permanently removes the POS version.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('DELETE'),
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg.toUpperCase())));
  }

  @override
  Widget build(BuildContext context) {
    return StationScaffold(
      stationNumber: '13',
      stationLabel: _isEdit ? 'EDIT VERSION' : 'NEW VERSION',
      title: _isEdit ? 'Edit version.' : 'Publish version.',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      child: ListView(
        children: [
          _Field(label: 'VERSION', controller: _version),
          const SizedBox(height: 16),
          StationDataRow(
            label: 'RELEASE DATE',
            value: _dateStr ?? 'Tap to pick a date',
            onTap: _pickDate,
            trailingIcon: Icons.calendar_today,
          ),
          const SizedBox(height: 32),
          SignalButton(
            label: _isEdit ? 'Save changes' : 'Create version',
            busy: _saving,
            onPressed: _saving ? null : _save,
          ),
          if (_isEdit) ...[
            const SizedBox(height: 12),
            GhostButton(label: 'Delete version', onPressed: _delete),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

/// Standard labelled text field matching the app's input styling.
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.controller});
  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      style: Theme.of(context).textTheme.titleMedium,
    );
  }
}
