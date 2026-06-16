import 'package:flutter/material.dart';

import '../../models/admin_models.dart';
import '../../services/admin_services.dart';
import '../../theme.dart';
import 'admin_list.dart';

class ReleaseNotesScreen extends StatelessWidget {
  const ReleaseNotesScreen({super.key, required this.service});
  final ReleaseNotesService service;

  @override
  Widget build(BuildContext context) {
    return AdminListPage<ReleaseNote>(
      stationNumber: '07',
      stationLabel: 'RELEASE NOTES',
      title: 'Changelog.',
      addLabel: 'New note',
      fetch: (search) => service.list(search: search),
      onAdd: (ctx, refresh) => _edit(ctx, refresh),
      itemBuilder: (ctx, n, refresh) => _NoteRow(
        note: n,
        onEdit: () => _edit(ctx, refresh, existing: n),
        onDelete: () async {
          if (!await confirmDialog(ctx,
              title: 'Delete note',
              message: 'Remove this release note?')) return;
          final ok = await service.delete(n.id);
          if (!ctx.mounted) return;
          toast(ctx, ok ? 'Deleted' : 'Delete failed');
          if (ok) refresh();
        },
      ),
    );
  }

  Future<void> _edit(BuildContext context, VoidCallback refresh,
      {ReleaseNote? existing}) async {
    // Load the dropdown sources first.
    List<PosVersion> versions;
    List<ActionType> actions;
    try {
      versions = await service.versions();
      actions = await service.actionTypes();
    } catch (e) {
      if (context.mounted) toast(context, 'Could not load options: $e');
      return;
    }
    if (!context.mounted) return;
    if (versions.isEmpty || actions.isEmpty) {
      toast(context, 'No versions or action types available.');
      return;
    }

    int versionId = existing?.posVersionId ??
        (versions.isNotEmpty ? versions.first.id : 0);
    int actionId =
        existing?.actionId ?? (actions.isNotEmpty ? actions.first.id : 0);
    if (!versions.any((v) => v.id == versionId)) versionId = versions.first.id;
    if (!actions.any((a) => a.id == actionId)) actionId = actions.first.id;
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(existing == null ? 'New release note' : 'Edit release note'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: versionId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Version'),
                    items: [
                      for (final v in versions)
                        DropdownMenuItem(value: v.id, child: Text('v${v.version}')),
                    ],
                    onChanged: (v) => setLocal(() => versionId = v ?? versionId),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: actionId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Action type'),
                    items: [
                      for (final a in actions)
                        DropdownMenuItem(value: a.id, child: Text(a.type)),
                    ],
                    onChanged: (v) => setLocal(() => actionId = v ?? actionId),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtrl,
                    minLines: 3,
                    maxLines: 8,
                    decoration: const InputDecoration(
                        labelText: 'Notes', alignLabelWithHint: true),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save')),
          ],
        ),
      ),
    );

    if (saved != true) return;
    final notes = notesCtrl.text.trim();
    if (notes.isEmpty) {
      if (context.mounted) toast(context, 'Notes cannot be empty.');
      return;
    }
    final ok = existing == null
        ? await service.add(
            versionId: versionId, actionTypeId: actionId, notes: notes)
        : await service.update(
            id: existing.id,
            versionId: versionId,
            actionTypeId: actionId,
            notes: notes);
    if (!context.mounted) return;
    toast(context, ok ? 'Saved' : 'Save failed');
    if (ok) refresh();
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow(
      {required this.note, required this.onEdit, required this.onDelete});
  final ReleaseNote note;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('v${note.version}', style: text.titleSmall),
                      const SizedBox(width: 8),
                      if (note.actionType.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: Brand.signalGlow(0.14),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(note.actionType.toUpperCase(),
                              style: const TextStyle(
                                  color: Brand.signal,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(note.notes, style: text.bodyMedium),
                ],
              ),
            ),
            IconButton(
                tooltip: 'Edit',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18)),
            IconButton(
                tooltip: 'Delete',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 18)),
          ],
        ),
        const SizedBox(height: 10),
        Container(height: 1, color: Brand.rule),
        const SizedBox(height: 10),
      ],
    );
  }
}
