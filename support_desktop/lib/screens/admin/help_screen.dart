import 'package:flutter/material.dart';

import '../../models/admin_models.dart';
import '../../services/admin_services.dart';
import '../../theme.dart';
import 'admin_list.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key, required this.service});
  final HelpService service;

  @override
  Widget build(BuildContext context) {
    return AdminListPage<HelpTopic>(
      stationNumber: '17',
      stationLabel: 'HELP PAGE',
      title: 'Topics.',
      addLabel: 'New topic',
      searchable: false,
      fetch: (_) => service.list(),
      onAdd: (ctx, refresh) => _edit(ctx, refresh),
      itemBuilder: (ctx, t, refresh) => _TopicRow(
        topic: t,
        onEdit: () => _edit(ctx, refresh, existing: t),
        onDelete: () async {
          if (!await confirmDialog(ctx,
              title: 'Delete topic',
              message: 'Remove "${t.title}" and its content?')) return;
          final ok = await service.delete(t.id);
          if (!ctx.mounted) return;
          toast(ctx, ok ? 'Deleted' : 'Delete failed');
          if (ok) refresh();
        },
      ),
    );
  }

  Future<void> _edit(BuildContext context, VoidCallback refresh,
      {HelpTopic? existing}) async {
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    final iconCtrl =
        TextEditingController(text: existing?.icon ?? 'fas fa-circle-info');
    final colorCtrl =
        TextEditingController(text: existing?.iconColor ?? '#FF7D00');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'New help topic' : 'Edit help topic'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Title'),
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                      labelText: 'Description', alignLabelWithHint: true),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: iconCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Icon class',
                    hintText: 'e.g. fas fa-circle-info',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: colorCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Icon color',
                    hintText: '#FF7D00',
                  ),
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
    );

    if (saved != true) return;
    final title = titleCtrl.text.trim();
    final icon = iconCtrl.text.trim();
    final color = colorCtrl.text.trim();
    if (title.isEmpty || icon.isEmpty || color.isEmpty) {
      if (context.mounted) toast(context, 'Title, icon and color are required.');
      return;
    }
    final ok = existing == null
        ? await service.add(
            title: title,
            description: descCtrl.text.trim(),
            icon: icon,
            iconColor: color)
        : await service.update(
            id: existing.id,
            title: title,
            description: descCtrl.text.trim(),
            icon: icon,
            iconColor: color);
    if (!context.mounted) return;
    toast(context, ok ? 'Saved' : 'Save failed');
    if (ok) refresh();
  }
}

class _TopicRow extends StatelessWidget {
  const _TopicRow(
      {required this.topic, required this.onEdit, required this.onDelete});
  final HelpTopic topic;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  Color _parseColor(String hex) {
    var h = hex.replaceAll('#', '').trim();
    if (h.length == 6) h = 'FF$h';
    final v = int.tryParse(h, radix: 16);
    return v == null ? Brand.signal : Color(v);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(top: 6, right: 10),
              decoration: BoxDecoration(
                color: _parseColor(topic.iconColor),
                shape: BoxShape.circle,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(topic.title, style: text.titleMedium),
                  if (topic.description.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(topic.description,
                        style:
                            text.bodySmall?.copyWith(color: Brand.paperDim)),
                  ],
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
