import 'package:flutter/material.dart';

import '../../models/admin_models.dart';
import '../../services/admin_services.dart';
import '../../theme.dart';
import 'admin_list.dart';

class PosVersionScreen extends StatelessWidget {
  const PosVersionScreen({super.key, required this.service});
  final PosVersionService service;

  @override
  Widget build(BuildContext context) {
    return AdminListPage<PosVersion>(
      stationNumber: '06',
      stationLabel: 'POS VERSION',
      title: 'Releases.',
      addLabel: 'New version',
      fetch: (search) => service.list(search: search),
      onAdd: (ctx, refresh) => _edit(ctx, refresh),
      itemBuilder: (ctx, v, refresh) => _PosRow(
        version: v,
        onEdit: () => _edit(ctx, refresh, existing: v),
        onDelete: () async {
          if (!await confirmDialog(ctx,
              title: 'Delete version',
              message: 'Remove POS version ${v.version}?')) {
            return;
          }
          final ok = await service.delete(v.id);
          if (!ctx.mounted) return;
          toast(ctx, ok ? 'Deleted' : 'Delete failed');
          if (ok) refresh();
        },
      ),
    );
  }

  Future<void> _edit(BuildContext context, VoidCallback refresh,
      {PosVersion? existing}) async {
    final versionCtrl = TextEditingController(text: existing?.version ?? '');
    final dateCtrl = TextEditingController(text: existing?.date ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'New POS version' : 'Edit POS version'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: versionCtrl,
              decoration: const InputDecoration(labelText: 'Version'),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: dateCtrl,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'Release date',
                hintText: 'YYYY-MM-DD',
                suffixIcon: Icon(Icons.calendar_today, size: 16),
              ),
              onTap: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: ctx,
                  initialDate: now,
                  firstDate: DateTime(2015),
                  lastDate: DateTime(now.year + 5),
                );
                if (picked != null) {
                  dateCtrl.text =
                      '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                }
              },
            ),
          ],
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
    );

    if (saved != true) return;
    final version = versionCtrl.text.trim();
    final date = dateCtrl.text.trim();
    if (version.isEmpty || date.isEmpty) {
      if (context.mounted) toast(context, 'Version and date are required.');
      return;
    }
    final ok = existing == null
        ? await service.add(version: version, releaseDate: date)
        : await service.update(id: existing.id, version: version, date: date);
    if (!context.mounted) return;
    toast(context, ok ? 'Saved' : 'Save failed');
    if (ok) refresh();
  }
}

class _PosRow extends StatelessWidget {
  const _PosRow(
      {required this.version, required this.onEdit, required this.onDelete});
  final PosVersion version;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('v${version.version}', style: text.titleMedium),
                  const SizedBox(height: 2),
                  Text(version.date,
                      style: text.bodySmall
                          ?.copyWith(color: Brand.paperDim)),
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
