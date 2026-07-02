import 'package:flutter/material.dart';

import '../models/releasenotes_models.dart';
import '../services/releasenotes_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';

/// Release Notes — native CRUD. List of notes with create / edit / delete,
/// backed by the `*ReleaseNotes` actions on api.php. Each note pairs a POS
/// version (from getposversion) with an action type (from getActionTypes)
/// and a free-form notes body.
class ReleaseNotesListScreen extends StatefulWidget {
  const ReleaseNotesListScreen({super.key, required this.service});
  final ReleaseNotesService service;

  @override
  State<ReleaseNotesListScreen> createState() => _ReleaseNotesListScreenState();
}

class _ReleaseNotesListScreenState extends State<ReleaseNotesListScreen> {
  List<ReleaseNote> _rows = const [];
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
    return StationScaffold(
      stationNumber: '13',
      stationLabel: 'RELEASE NOTES',
      title: 'Release notes.',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      trailing: StationAction(
        icon: Icons.add,
        tooltip: 'New release note',
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
                        label: 'No release notes',
                        hint: 'Tap + to add the first note. Pull to refresh.',
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _rows.length,
                    separatorBuilder: (_, _) => const Hairline(),
                    itemBuilder: (_, i) => _ReleaseNoteRow(
                      row: _rows[i],
                      onTap: () => _openForm(_rows[i]),
                    ),
                  ),
      ),
    );
  }
}

class _ReleaseNoteRow extends StatelessWidget {
  const _ReleaseNoteRow({required this.row, required this.onTap});
  final ReleaseNote row;
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
                  Row(
                    children: [
                      Text(
                        row.version.isEmpty ? 'No version' : row.version,
                        style: text.titleSmall,
                      ),
                      if (row.type.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        Text(
                          row.type.toUpperCase(),
                          style: text.labelMedium?.copyWith(
                            color: Brand.paperDim,
                            letterSpacing: 2.2,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    row.notes.isEmpty ? 'No notes' : row.notes,
                    style: text.bodySmall,
                    maxLines: 2,
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

/// Add / edit form. Version + action type are dropdowns sourced from
/// getposversion / getActionTypes; notes is a multiline field.
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
      // Drop stale selections that aren't in the picker lists.
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
        backgroundColor: Brand.surface,
        title: const Text('Delete release note?'),
        content: const Text('This permanently removes the note.'),
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
      _toast(res.message ?? 'Could not delete the release note.');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg.toUpperCase())));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return StationScaffold(
      stationNumber: '13',
      stationLabel: _isEdit ? 'EDIT NOTE' : 'NEW NOTE',
      title: _isEdit ? 'Edit note.' : 'Add note.',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      child: _loadingPickers
          ? const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Brand.signal),
              ),
            )
          : ListView(
              children: [
                _PickerField<int>(
                  label: 'VERSION',
                  value: _versionId,
                  hint: 'Select a version',
                  items: _versions
                      .map((v) => DropdownMenuItem<int>(
                            value: v.id,
                            child: Text(
                              v.version.isEmpty ? '#${v.id}' : v.version,
                              style: text.titleMedium,
                            ),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _versionId = v),
                ),
                const SizedBox(height: 20),
                _PickerField<int>(
                  label: 'ACTION TYPE',
                  value: _actionTypeId,
                  hint: 'Select an action type',
                  items: _actionTypes
                      .map((a) => DropdownMenuItem<int>(
                            value: a.id,
                            child: Text(
                              a.type.isEmpty ? '#${a.id}' : a.type,
                              style: text.titleMedium,
                            ),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _actionTypeId = v),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _notes,
                  decoration: const InputDecoration(labelText: 'NOTES'),
                  style: text.titleMedium,
                  minLines: 4,
                  maxLines: 8,
                  keyboardType: TextInputType.multiline,
                ),
                const SizedBox(height: 32),
                SignalButton(
                  label: _isEdit ? 'Save changes' : 'Create note',
                  busy: _saving,
                  onPressed: _saving ? null : _save,
                ),
                if (_isEdit) ...[
                  const SizedBox(height: 12),
                  GhostButton(label: 'Delete note', onPressed: _delete),
                ],
                const SizedBox(height: 40),
              ],
            ),
    );
  }
}

/// A labelled Material dropdown matching the app's input styling.
class _PickerField<T> extends StatelessWidget {
  const _PickerField({
    required this.label,
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
  });
  final String label;
  final T? value;
  final String hint;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      dropdownColor: Brand.surface,
      iconEnabledColor: Brand.paperDim,
      style: Theme.of(context).textTheme.titleMedium,
      hint: Text(hint, style: Theme.of(context).textTheme.bodySmall),
      items: items,
      onChanged: onChanged,
    );
  }
}
