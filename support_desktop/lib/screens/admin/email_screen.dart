import 'package:flutter/material.dart';

import '../../models/admin_models.dart';
import '../../services/admin_services.dart';
import '../../theme.dart';
import 'admin_list.dart';

class EmailScreen extends StatelessWidget {
  const EmailScreen({super.key, required this.service});
  final EmailService service;

  @override
  Widget build(BuildContext context) {
    return AdminListPage<EmailRecipient>(
      stationNumber: '13',
      stationLabel: 'EMAIL',
      title: 'Recipients.',
      addLabel: 'Compose',
      searchHint: 'Search email…',
      fetch: (search) => service.list(search: search),
      onAdd: (ctx, refresh) => _compose(ctx),
      itemBuilder: (ctx, r, refresh) => _RecipientRow(
        recipient: r,
        onSend: () => _compose(ctx, to: r.email),
        onDelete: () async {
          if (!await confirmDialog(ctx,
              title: 'Delete recipient',
              message: 'Remove ${r.email}?')) return;
          final ok = await service.delete(id: r.id, source: r.source);
          if (!ctx.mounted) return;
          toast(ctx, ok ? 'Deleted' : 'Delete failed');
          if (ok) refresh();
        },
      ),
    );
  }

  Future<void> _compose(BuildContext context, {String? to}) async {
    final toCtrl = TextEditingController(text: to ?? '');
    final subjectCtrl = TextEditingController();
    final messageCtrl = TextEditingController();
    var sendAll = to == null;

    final sent = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Compose email'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Send to all subscribers'),
                    value: sendAll,
                    onChanged: (v) => setLocal(() => sendAll = v),
                  ),
                  if (!sendAll)
                    TextField(
                      controller: toCtrl,
                      decoration: const InputDecoration(labelText: 'To'),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: subjectCtrl,
                    decoration: const InputDecoration(labelText: 'Subject'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: messageCtrl,
                    minLines: 4,
                    maxLines: 10,
                    decoration: const InputDecoration(
                        labelText: 'Message', alignLabelWithHint: true),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton.icon(
                icon: const Icon(Icons.send, size: 16),
                onPressed: () => Navigator.pop(ctx, true),
                label: const Text('Send')),
          ],
        ),
      ),
    );

    if (sent != true) return;
    final subject = subjectCtrl.text.trim();
    final message = messageCtrl.text.trim();
    if (subject.isEmpty || message.isEmpty) {
      if (context.mounted) toast(context, 'Subject and message are required.');
      return;
    }
    final ok = sendAll
        ? await service.sendAll(subject: subject, message: message)
        : await service.sendSingle(
            email: toCtrl.text.trim(), subject: subject, message: message);
    if (!context.mounted) return;
    toast(context, ok ? 'Email sent' : 'Send failed');
  }
}

class _RecipientRow extends StatelessWidget {
  const _RecipientRow(
      {required this.recipient, required this.onSend, required this.onDelete});
  final EmailRecipient recipient;
  final VoidCallback onSend;
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
                  Text(recipient.email, style: text.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    [
                      recipient.source.toUpperCase(),
                      if (recipient.businessType.isNotEmpty)
                        recipient.businessType,
                    ].join(' · '),
                    style: text.bodySmall?.copyWith(color: Brand.paperDim),
                  ),
                ],
              ),
            ),
            IconButton(
                tooltip: 'Send email',
                onPressed: onSend,
                icon: const Icon(Icons.send_outlined, size: 18)),
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
