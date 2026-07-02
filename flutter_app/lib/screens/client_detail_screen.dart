import 'package:flutter/material.dart';

import '../models/client_models.dart';
import '../services/client_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'client_form_screen.dart';

/// Read-only Client & Data Sheet detail with Edit + Delete.
class ClientDetailScreen extends StatefulWidget {
  const ClientDetailScreen({
    super.key,
    required this.service,
    required this.brief,
  });

  final ClientService service;
  final ClientBrief brief;

  @override
  State<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends State<ClientDetailScreen> {
  ClientDetail? _detail;
  bool _loading = true;
  bool _deleting = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await widget.service.detail(widget.brief.id);
    if (!mounted) return;
    setState(() {
      _detail = data;
      _loading = false;
    });
  }

  Future<void> _edit() async {
    final d = _detail;
    if (d == null) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ClientFormScreen(service: widget.service, existing: d),
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
          'This permanently deletes "${widget.brief.name}". This cannot be undone.',
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
    return StationScaffold(
      stationNumber: widget.brief.id.toString().padLeft(2, '0'),
      stationLabel: 'CLIENT DETAIL',
      title: widget.brief.name.isEmpty ? 'Client.' : widget.brief.name,
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
          StationAction(icon: Icons.refresh, tooltip: 'Refresh', onPressed: _load),
        ],
      ),
      child: _loading
          ? const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Brand.signal),
              ),
            )
          : d == null
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 64),
                    EmptyState(
                      label: 'Not found',
                      hint: 'Could not load this client. Pull to refresh.',
                    ),
                  ],
                )
              : ListView(
                  physics: const BouncingScrollPhysics(),
                  children: [
                    _section('Customer'),
                    _row('INVOICE', d.invoiceNumber),
                    _row('DATE PREPARED', d.datePrepared),
                    _row('VAT STATUS', d.isVat ? 'VAT' : 'NON-VAT'),
                    const SizedBox(height: 32),
                    _section('System'),
                    _row('SYSTEM UNIT', d.systemUnit),
                    _row('SYSTEM UNIT SERIAL', d.systemUnitSerial),
                    _row('RAM', d.ramConfig),
                    _row('STORAGE', d.storageConfig),
                    _row('STORAGE SERIAL', d.storageSerial),
                    _row('MONITOR',
                        [d.monitorSize, d.monitorBrand, d.monitorType]
                            .where((e) => e.isNotEmpty)
                            .join(' · ')),
                    _row('MONITOR SERIAL', d.monitorSerial),
                    const SizedBox(height: 32),
                    _section('Serial numbers'),
                    _row('MOTHERBOARD', d.motherboardSerial),
                    _row('KEYBOARD', d.keyboardSerial),
                    _row('MOUSE', d.mouseSerial),
                    _row('BARCODE SCANNER', d.barcodeScannerSerial),
                    _row('THERMAL PRINTER', d.thermalPrinterSerial),
                    _row('CASH DRAWER', d.cashDrawerSerial),
                    _row('BARCODE PRINTER', d.barcodePrinterSerial),
                    _row('CUSTOMER DISPLAY', d.cusDisplaySerial),
                    const SizedBox(height: 32),
                    _section('BIR compliant system'),
                    _row('SYSTEM SERIAL', d.systemSerial),
                    _row('MAC ADDRESS', d.macAddress),
                    _row('MIN', d.min),
                    _row('PTU', d.ptu),
                    _row('DATE APPROVED', d.dateApproved),
                    _row('TIN', d.tin),
                    _row('REGISTERED ADDRESS', d.registeredAddress),
                    if (d.invoiceItems.isNotEmpty) ...[
                      const SizedBox(height: 32),
                      _section('Invoice items'),
                      for (final it in d.invoiceItems) _itemTile(it),
                    ],
                    const SizedBox(height: 40),
                  ],
                ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            const Hairline(),
          ],
        ),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: StationDataRow(label: label, value: value.isEmpty ? '—' : value),
      );

  Widget _itemTile(ClientInvoiceItem it) {
    final text = Theme.of(context).textTheme;
    final spec = [it.component, it.optionValue, it.brandName]
        .where((e) => e.isNotEmpty)
        .join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (it.itemName.isNotEmpty)
            Text(it.itemName.toUpperCase(), style: text.labelMedium),
          const SizedBox(height: 4),
          Text(spec.isEmpty ? '—' : spec, style: text.bodyMedium),
          if (it.serialNumber.isNotEmpty)
            Text('SN: ${it.serialNumber}', style: text.bodySmall),
        ],
      ),
    );
  }
}
