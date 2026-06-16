import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/admin_models.dart';
import '../../services/admin_services.dart';
import '../../theme.dart';
import 'admin_list.dart';

/// Builds a secure license key in the same `TP-XXXX-XXXX-XXXX-XXXX` shape the
/// web console generates (4 groups of 4 alphanumeric characters).
String _generateLicenseKey() {
  const chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  final rnd = Random.secure();
  String group() => List.generate(
      4, (_) => chars[rnd.nextInt(chars.length)]).join();
  return 'TP-${group()}-${group()}-${group()}-${group()}';
}

class LicenseKeyScreen extends StatelessWidget {
  const LicenseKeyScreen({super.key, required this.service});
  final LicenseService service;

  @override
  Widget build(BuildContext context) {
    return AdminListPage<LicenseKey>(
      stationNumber: '08',
      stationLabel: 'LICENSE KEY',
      title: 'Keys.',
      addLabel: 'New key',
      searchable: false,
      fetch: (_) => service.list(),
      onAdd: (ctx, refresh) => _edit(ctx, refresh),
      itemBuilder: (ctx, k, refresh) => _LicenseRow(
        license: k,
        onEdit: () => _edit(ctx, refresh, existing: k),
        onDelete: () async {
          if (!await confirmDialog(ctx,
              title: 'Delete license',
              message: 'Remove key ${k.licenseKey}?')) return;
          final ok = await service.delete(k.id);
          if (!ctx.mounted) return;
          toast(ctx, ok ? 'Deleted' : 'Delete failed');
          if (ok) refresh();
        },
      ),
    );
  }

  Future<void> _edit(BuildContext context, VoidCallback refresh,
      {LicenseKey? existing}) async {
    final keyCtrl = TextEditingController(text: existing?.licenseKey ?? '');
    final expCtrl = TextEditingController(text: existing?.dateExpired ?? '');
    final storeName = TextEditingController(text: existing?.storeName ?? '');
    final storeAddr = TextEditingController(text: existing?.storeAddress ?? '');
    final storeEmail = TextEditingController(text: existing?.storeEmail ?? '');
    // '0' permanent, '1' trial.
    var type = (existing?.isPermanent ?? true) ? '0' : '1';

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(existing == null ? 'New license key' : 'Edit license key'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: keyCtrl,
                    decoration: InputDecoration(
                      labelText: 'License key',
                      suffixIcon: IconButton(
                        tooltip: 'Generate key',
                        icon: const Icon(Icons.autorenew, size: 18),
                        onPressed: () =>
                            setLocal(() => keyCtrl.text = _generateLicenseKey()),
                      ),
                    ),
                    autofocus: true,
                    // Enter submits the dialog (Save).
                    onSubmitted: (_) => Navigator.pop(ctx, true),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: const [
                      DropdownMenuItem(value: '0', child: Text('Permanent')),
                      DropdownMenuItem(value: '1', child: Text('Trial')),
                    ],
                    onChanged: (v) => setLocal(() => type = v ?? '0'),
                  ),
                  if (type != '0') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: expCtrl,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Expiration date',
                        hintText: 'YYYY-MM-DD',
                        suffixIcon: Icon(Icons.calendar_today, size: 16),
                      ),
                      onTap: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: now,
                          firstDate: DateTime(2015),
                          lastDate: DateTime(now.year + 10),
                        );
                        if (picked != null) {
                          expCtrl.text =
                              '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                        }
                      },
                    ),
                  ],
                  if (existing != null) ...[
                    const SizedBox(height: 18),
                    const Divider(),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Assigned store',
                          style: Theme.of(ctx).textTheme.labelMedium),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                        controller: storeName,
                        decoration:
                            const InputDecoration(labelText: 'Store name')),
                    const SizedBox(height: 12),
                    TextField(
                        controller: storeAddr,
                        decoration:
                            const InputDecoration(labelText: 'Store address')),
                    const SizedBox(height: 12),
                    TextField(
                        controller: storeEmail,
                        decoration:
                            const InputDecoration(labelText: 'Store email')),
                  ],
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
    final key = keyCtrl.text.trim();
    if (key.isEmpty) {
      if (context.mounted) toast(context, 'License key is required.');
      return;
    }
    final ok = existing == null
        ? await service.add(
            licenseKey: key, licenseType: type, expirationDate: expCtrl.text)
        : await service.update(
            id: existing.id,
            licenseKey: key,
            licenseType: type,
            expirationDate: expCtrl.text,
            storeName: storeName.text.trim(),
            storeAddress: storeAddr.text.trim(),
            storeEmail: storeEmail.text.trim(),
          );
    if (!context.mounted) return;
    toast(context, ok ? 'Saved' : 'Save failed');
    if (ok) refresh();
  }
}

class _LicenseRow extends StatelessWidget {
  const _LicenseRow(
      {required this.license, required this.onEdit, required this.onDelete});
  final LicenseKey license;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final tag = license.isPermanent ? 'PERMANENT' : 'TRIAL';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(license.licenseKey,
                      style: text.titleMedium, maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Wrap(
                    spacing: 10,
                    children: [
                      _chip(tag, license.isPermanent ? Brand.signal : Brand.paperDim),
                      _chip(license.isUsed ? 'IN USE' : 'AVAILABLE',
                          license.isUsed ? Brand.paperDim : Brand.signal),
                      if (!license.isPermanent && license.dateExpired.isNotEmpty)
                        Text('exp ${license.dateExpired}',
                            style: text.bodySmall
                                ?.copyWith(color: Brand.paperDim)),
                      if (license.storeName.isNotEmpty)
                        Text(license.storeName,
                            style: text.bodySmall
                                ?.copyWith(color: Brand.paperDim)),
                    ],
                  ),
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

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label,
            style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1)),
      );
}
