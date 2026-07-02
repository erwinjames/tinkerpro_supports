import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'customer_form_screen.dart';

class CustomerDetailScreen extends StatefulWidget {
  const CustomerDetailScreen({
    super.key,
    required this.service,
    required this.brief,
  });

  final CustomerService service;
  final CustomerBrief brief;

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  CustomerDetail? _detail;
  bool _loading = true;
  bool _deleting = false;
  bool _changed = false; // pop this back so the list refreshes.

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await widget.service.detailFull(widget.brief.id);
    if (!mounted) return;
    setState(() {
      _detail = data;
      _loading = false;
    });
  }

  Future<void> _edit() async {
    final detail = _detail;
    if (detail == null) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            CustomerFormScreen(service: widget.service, existing: detail),
      ),
    );
    if (saved == true) {
      _changed = true;
      _load();
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.brand.surface,
        title: Text('Delete client?',
            style: Theme.of(ctx).textTheme.headlineMedium),
        content: Text(
          'This permanently deletes "${widget.brief.companyName}" and its '
          'documents on the server. This cannot be undone.',
          style: Theme.of(ctx).textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('CANCEL',
                style: Theme.of(ctx)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: context.brand.paperDim)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('DELETE',
                style: Theme.of(ctx)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: Brand.signal)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _deleting = true);
    final ok = await widget.service.delete(widget.brief.id);
    if (!mounted) return;
    setState(() => _deleting = false);
    if (ok) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Client deleted.')));
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
            const SnackBar(content: Text('Delete failed. Please try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    final branch = d?.branchCode ?? widget.brief.branchCode;
    final address = (d?.address.isNotEmpty ?? false)
        ? d!.address
        : widget.brief.address;
    final rdo = d?.rdo ?? '';
    final software = d?.softwareName ?? '';
    final accNumber = d?.accNumber ?? '';
    final vat = d == null ? '' : (d.isVat ? 'VAT' : 'NON-VAT');
    final owner =
        (d?.ownerName.isNotEmpty ?? false) ? d!.ownerName : widget.brief.ownerName;
    final tin = (d?.tin.isNotEmpty ?? false) ? d!.tin : widget.brief.tin;
    final status = d?.status ?? widget.brief.status;

    return StationScaffold(
      stationNumber: widget.brief.id.toString().padLeft(2, '0'),
      stationLabel: 'CLIENT DETAIL',
      title: widget.brief.companyName,
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(_changed),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StationAction(
            icon: Icons.edit_outlined,
            tooltip: 'Edit',
            onPressed: _loading ? () {} : _edit,
          ),
          const SizedBox(width: 4),
          StationAction(
            icon: Icons.delete_outline,
            tooltip: 'Delete',
            onPressed: _deleting ? () {} : _delete,
          ),
          const SizedBox(width: 4),
          StationAction(
            icon: Icons.refresh,
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      child: _loading
          ? const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Brand.signal,
                ),
              ),
            )
          : ListView(
              physics: const BouncingScrollPhysics(),
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: status == 'Processed' ? Brand.signal : context.brand.rule,
                      ),
                    ),
                    Text(
                      status.toUpperCase(),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: status == 'Processed'
                                ? Brand.signal
                                : context.brand.paperDim,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                StationDataRow(
                  label: 'TIN · BRANCH',
                  value:
                      '${tin.isEmpty ? '—' : tin}${branch.isEmpty ? '' : '  ·  $branch'}',
                ),
                const SizedBox(height: 20),
                StationDataRow(
                    label: 'OWNER', value: owner.isEmpty ? '—' : owner),
                const SizedBox(height: 20),
                StationDataRow(
                    label: 'ADDRESS', value: address.isEmpty ? '—' : address),
                const SizedBox(height: 20),
                StationDataRow(label: 'RDO', value: rdo.isEmpty ? '—' : rdo),
                const SizedBox(height: 20),
                StationDataRow(
                    label: 'VAT STATUS', value: vat.isEmpty ? '—' : vat),
                const SizedBox(height: 40),
                Text('Point-of-sale',
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 8),
                const Hairline(),
                const SizedBox(height: 20),
                StationDataRow(
                    label: 'SOFTWARE', value: software.isEmpty ? '—' : software),
                const SizedBox(height: 20),
                StationDataRow(
                    label: 'ACC. NUMBER',
                    value: accNumber.isEmpty ? '—' : accNumber),
                const SizedBox(height: 20),
                StationDataRow(
                  label: 'SERIAL NUMBER',
                  value: (d?.serialNumber.isNotEmpty ?? false)
                      ? d!.serialNumber
                      : '—',
                ),
                if (d != null && d.serialEntries.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  _serialEntries(context, d.serialEntries),
                ],
                if (d != null && d.documents.isNotEmpty) ...[
                  const SizedBox(height: 40),
                  _documents(context, d.documents),
                ],
                const SizedBox(height: 40),
              ],
            ),
    );
  }

  Widget _serialEntries(BuildContext context, List<SerialEntry> entries) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Serial entries',
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        const Hairline(),
        const SizedBox(height: 16),
        for (final s in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    s.serialNumberType,
                    if (s.serverType.isNotEmpty) s.serverType,
                  ].where((e) => e.isNotEmpty).join(' · ').toUpperCase(),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 4),
                Text(s.serialNumber.isEmpty ? '—' : s.serialNumber,
                    style: Theme.of(context).textTheme.bodyMedium),
                if (s.brand.isNotEmpty || s.model.isNotEmpty)
                  Text(
                    [s.brand, s.model].where((e) => e.isNotEmpty).join(' '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _documents(BuildContext context, List<CustomerDocument> docs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Documents', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        const Hairline(),
        const SizedBox(height: 16),
        for (final doc in docs)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Icon(Icons.insert_drive_file_outlined,
                    size: 16, color: context.brand.paperDim),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    doc.originalFilename.isEmpty
                        ? doc.storedFilename
                        : doc.originalFilename,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(doc.docType.replaceAll('_', ' ').toUpperCase(),
                    style: Theme.of(context).textTheme.labelMedium),
              ],
            ),
          ),
      ],
    );
  }
}
