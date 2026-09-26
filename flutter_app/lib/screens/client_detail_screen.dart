import 'package:flutter/material.dart';

import '../models/client_models.dart';
import '../models/models.dart';
import '../services/client_service.dart';
import '../services/services.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'client_form_screen.dart';
import 'customer_detail_screen.dart';

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
  bool _importing = false;
  ScaffoldMessengerState? _messenger;
  bool _imported = false;
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
        icon: const IconTile(
          icon: Icons.delete_outline_rounded,
          color: Brand.danger,
          size: 44,
          iconSize: 22,
        ),
        title: const Text('Delete client?'),
        content: Text(
          'This permanently deletes "${widget.brief.name}". This cannot be undone.',
        ),
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
          const SnackBar(content: Text('Delete failed. Please try again.')),
        );
    }
  }

  Future<void> _importToBir() async {
    setState(() => _importing = true);
    final res = await widget.service.importToBir(widget.brief.id);
    if (!mounted) return;
    setState(() {
      _importing = false;
      if (res.ok) _imported = true;
    });
    final messenger = ScaffoldMessenger.of(context);
    _messenger = messenger;
    messenger.hideCurrentSnackBar();
    if (!res.ok) {
      messenger.showSnackBar(
        SnackBar(content: Text(res.message ?? 'Could not import client.')),
      );
      return;
    }
    _changed = true;
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Imported to BIR Registration.'),
        duration: const Duration(seconds: 4),
        persist: false,
        action: res.customerId > 0
            ? SnackBarAction(
                label: 'View',
                onPressed: () {
                  messenger.hideCurrentSnackBar();
                  _openBirRecord(res.customerId);
                },
              )
            : null,
      ),
    );
  }

  @override
  void dispose() {
    _messenger?.hideCurrentSnackBar();
    super.dispose();
  }

  void _openBirRecord(int customerId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CustomerDetailScreen(
          service: CustomerService(widget.service.api),
          brief: CustomerBrief(
            id: customerId,
            companyName: widget.brief.name,
            tin: '',
            branchCode: '',
            ownerName: '',
            address: '',
            cStatus: 0,
            step2: 0,
            finalStep: 0,
            registrationSource: '',
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    final imported = _imported || widget.brief.birImported;
    return StationScaffold(
      stationNumber: widget.brief.id.toString().padLeft(2, '0'),
      stationLabel: 'Client',
      title: widget.brief.name.isEmpty ? 'Untitled client' : widget.brief.name,
      subtitle: 'Data sheet #${widget.brief.id}',
      showBottomBrand: false,
      belowRule: _identity(d),
      onBack: () => Navigator.of(context).pop(_changed),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StationAction(
            icon: Icons.edit_rounded,
            tooltip: 'Edit',
            onPressed: _loading ? () {} : _edit,
          ),
          const SizedBox(width: 8),
          StationAction(
            icon: Icons.delete_outline_rounded,
            tooltip: 'Delete',
            onPressed: _deleting ? () {} : _delete,
          ),
          const SizedBox(width: 8),
          StationAction(
            icon: imported
                ? Icons.check_circle_rounded
                : Icons.file_upload_rounded,
            tooltip: imported
                ? 'Already imported to BIR Registration'
                : 'Import to BIR Registration',
            onPressed: imported || _importing ? () {} : _importToBir,
          ),
          const SizedBox(width: 8),
          StationAction(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      child: _loading
          ? const _DetailSkeleton()
          : d == null
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 48),
                EmptyState(
                  icon: Icons.person_search_rounded,
                  label: 'Not found',
                  hint: 'Could not load this client.',
                  action: GhostButton(
                    label: 'Retry',
                    icon: Icons.refresh_rounded,
                    onPressed: _load,
                  ),
                ),
              ],
            )
          : ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                _section(0, 'Customer', Icons.person_rounded, [
                  _row('Invoice', d.invoiceNumber),
                  _row('Branch', d.branch),
                  _row('Date prepared', d.datePrepared),
                  _row('VAT status', d.isVat ? 'VAT' : 'Non-VAT'),
                ]),
                _section(1, 'System', Icons.computer_rounded, [
                  _row('System unit', d.systemUnit),
                  _row('System unit serial', d.systemUnitSerial),
                  _row('RAM', d.ramConfig),
                  _row('Storage', d.storageConfig),
                  _row('Storage serial', d.storageSerial),
                  _row(
                    'Monitor',
                    [
                      d.monitorSize,
                      d.monitorBrand,
                      d.monitorType,
                    ].where((e) => e.isNotEmpty).join(' · '),
                  ),
                  _row('Monitor serial', d.monitorSerial),
                ]),
                _section(2, 'Serial numbers', Icons.qr_code_2_rounded, [
                  _row('Motherboard', d.motherboardSerial),
                  _row('Keyboard', d.keyboardSerial),
                  _row('Mouse', d.mouseSerial),
                  _row('Barcode scanner', d.barcodeScannerSerial),
                  _row('Thermal printer', d.thermalPrinterSerial),
                  _row('Cash drawer', d.cashDrawerSerial),
                  _row('Barcode printer', d.barcodePrinterSerial),
                  _row('Customer display', d.cusDisplaySerial),
                ]),
                _section(3, 'BIR compliant system', Icons.verified_rounded, [
                  _row('System serial', d.systemSerial),
                  _row('MAC address', d.macAddress),
                  _row('MIN', d.min),
                  _row('PTU', d.ptu),
                  _row('Date approved', d.dateApproved),
                  _row('TIN', d.tin),
                  _row('Registered address', d.registeredAddress),
                ]),
                if (d.invoiceItems.isNotEmpty)
                  _section(4, 'Invoice items', Icons.receipt_long_rounded, [
                    for (var i = 0; i < d.invoiceItems.length; i++) ...[
                      if (i > 0) const Hairline(),
                      _itemTile(d.invoiceItems[i]),
                    ],
                  ]),
              ],
            ),
    );
  }

  Widget _identity(ClientDetail? d) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final name = widget.brief.name.isEmpty
        ? 'Untitled client'
        : widget.brief.name;
    final invoice = d?.invoiceNumber ?? widget.brief.invoiceNumber;
    final hasInvoice = invoice.trim().isNotEmpty;
    final pills = <Widget>[
      if (d != null)
        GlowBadge(
          label: d.isVat ? 'VAT' : 'Non-VAT',
          icon: Icons.account_balance_rounded,
          color: d.isVat ? Brand.success : b.paperDim,
        ),
      GlowBadge(
        label: hasInvoice ? 'Invoice $invoice' : 'No invoice',
        icon: Icons.receipt_long_rounded,
        color: hasInvoice ? b.signal : b.paperDim,
      ),
    ];
    return SizedBox(
      width: double.infinity,
      child: GlassPanel(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            AppAvatar(name: name, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Identity',
                    style: text.labelSmall?.copyWith(
                      color: b.signalInk,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 8, children: pills),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(
    int index,
    String title,
    IconData icon,
    List<Widget> children,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _Entry(
        index: index,
        child: AppCard(
          radius: Brand.radiusLg,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _SectionGlyph(icon: icon),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) =>
      StationDataRow(label: label, value: value.isEmpty ? '—' : value);

  Widget _itemTile(ClientInvoiceItem it) {
    final text = Theme.of(context).textTheme;
    final spec = [
      it.component,
      it.optionValue,
      it.brandName,
    ].where((e) => e.isNotEmpty).join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (it.itemName.isNotEmpty) ...[
            Text(it.itemName, style: text.titleSmall),
            const SizedBox(height: 4),
          ],
          Text(spec.isEmpty ? '—' : spec, style: text.bodyMedium),
          if (it.serialNumber.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text('SN: ${it.serialNumber}', style: text.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _SectionGlyph extends StatelessWidget {
  const _SectionGlyph({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: b.signal.withValues(alpha: b.isDark ? 0.18 : 0.12),
        border: Border.all(color: b.signal.withValues(alpha: 0.4)),
      ),
      child: Icon(icon, size: 16, color: b.signalInk),
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

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (final rows in const [3, 7, 5])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AppCard(
                radius: Brand.radiusLg,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Skeleton(width: 30, height: 30, radius: 9),
                        SizedBox(width: 10),
                        Skeleton(width: 140, height: 16),
                      ],
                    ),
                    for (var i = 0; i < rows; i++) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Skeleton(width: 96, height: 12),
                          const SizedBox(width: 24),
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Skeleton(
                                width: i.isEven ? 150 : 110,
                                height: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
