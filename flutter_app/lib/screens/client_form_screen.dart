import 'package:flutter/material.dart';

import '../models/client_models.dart';
import '../services/client_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';

/// Create / edit a Client & Data Sheet record. All processing is server-side
/// (`addClient` / `updateClient`). Pass [existing] to edit. Pops `true` on save.
class ClientFormScreen extends StatefulWidget {
  const ClientFormScreen({super.key, required this.service, this.existing});

  final ClientService service;
  final ClientDetail? existing;

  bool get isEdit => existing != null;

  @override
  State<ClientFormScreen> createState() => _ClientFormScreenState();
}

class _ClientFormScreenState extends State<ClientFormScreen> {
  // Enumerated option sets (from the web modal).
  static const _systemUnitOptions = <String>[
    'Generic CPU',
    'Branded CPU',
    'ALL IN ONE SYSTEM',
  ];
  static const _ramOptions = <String>['2GB', '4GB', '6GB', '8GB', '16GB', '32GB'];
  static const _monitorSizeOptions = <String>[
    '14 Inches',
    '15.6 Inches',
    '17 Inches',
    '19 Inches',
    '20 Inches',
  ];
  static const _monitorBrandOptions = <String>[
    'N-Vision',
    'Supervision',
    'LG',
    'HP',
    'Acer',
    'AOC',
    'ASUS',
    'GreatWall',
    'Gamdas',
    'Orion',
    'TinkerPro',
  ];
  static const _monitorTypeOptions = <String>[
    'Touch Screen',
    'Non Touch',
    'Projection Type',
  ];

  // Text controllers.
  final _name = TextEditingController();
  final _invoice = TextEditingController();
  final _datePrepared = TextEditingController();
  final _dateApproved = TextEditingController();
  final _systemUnitSerial = TextEditingController();
  final _motherboardSerial = TextEditingController();
  final _storageConfig = TextEditingController();
  final _storageSerial = TextEditingController();
  final _monitorSerial = TextEditingController();
  final _keyboardSerial = TextEditingController();
  final _mouseSerial = TextEditingController();
  final _barcodeScannerSerial = TextEditingController();
  final _thermalPrinterSerial = TextEditingController();
  final _cashDrawerSerial = TextEditingController();
  final _barcodePrinterSerial = TextEditingController();
  final _cusDisplaySerial = TextEditingController();
  final _systemSerial = TextEditingController();
  final _mac = TextEditingController();
  final _min = TextEditingController();
  final _ptu = TextEditingController();
  final _tin = TextEditingController();
  final _registeredAddress = TextEditingController();

  // Dropdown-with-"Other" choices.
  late final _Choice _systemUnit = _Choice(_systemUnitOptions);
  late final _Choice _ram = _Choice(_ramOptions);
  late final _Choice _monitorSize = _Choice(_monitorSizeOptions);
  late final _Choice _monitorBrand = _Choice(_monitorBrandOptions);
  late final _Choice _monitorType = _Choice(_monitorTypeOptions);

  bool _isVat = false;
  final List<_ItemRow> _items = [];

  bool _saving = false;
  bool _aiBusy = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _name.text = e.name;
      _invoice.text = e.invoiceNumber;
      _datePrepared.text = e.datePrepared;
      _dateApproved.text = e.dateApproved;
      _systemUnitSerial.text = e.systemUnitSerial;
      _motherboardSerial.text = e.motherboardSerial;
      _storageConfig.text = e.storageConfig;
      _storageSerial.text = e.storageSerial;
      _monitorSerial.text = e.monitorSerial;
      _keyboardSerial.text = e.keyboardSerial;
      _mouseSerial.text = e.mouseSerial;
      _barcodeScannerSerial.text = e.barcodeScannerSerial;
      _thermalPrinterSerial.text = e.thermalPrinterSerial;
      _cashDrawerSerial.text = e.cashDrawerSerial;
      _barcodePrinterSerial.text = e.barcodePrinterSerial;
      _cusDisplaySerial.text = e.cusDisplaySerial;
      _systemSerial.text = e.systemSerial;
      _mac.text = e.macAddress;
      _min.text = e.min;
      _ptu.text = e.ptu;
      _tin.text = e.tin;
      _registeredAddress.text = e.registeredAddress;
      _isVat = e.isVat;
      _systemUnit.init(e.systemUnit);
      _ram.init(e.ramConfig);
      _monitorSize.init(e.monitorSize);
      _monitorBrand.init(e.monitorBrand);
      _monitorType.init(e.monitorType);
      for (final it in e.invoiceItems) {
        _items.add(_ItemRow(
          itemName: it.itemName,
          component: it.component,
          optionValue: it.optionValue,
          brandName: it.brandName,
          serialNumber: it.serialNumber,
        ));
      }
    }
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _invoice,
      _datePrepared,
      _dateApproved,
      _systemUnitSerial,
      _motherboardSerial,
      _storageConfig,
      _storageSerial,
      _monitorSerial,
      _keyboardSerial,
      _mouseSerial,
      _barcodeScannerSerial,
      _thermalPrinterSerial,
      _cashDrawerSerial,
      _barcodePrinterSerial,
      _cusDisplaySerial,
      _systemSerial,
      _mac,
      _min,
      _ptu,
      _tin,
      _registeredAddress,
    ]) {
      c.dispose();
    }
    for (final c in [_systemUnit, _ram, _monitorSize, _monitorBrand, _monitorType]) {
      c.dispose();
    }
    for (final r in _items) {
      r.dispose();
    }
    super.dispose();
  }

  // ── Invoice lookup / auto-fill ──────────────────────────────────────────────
  Future<void> _findInvoice() async {
    final picked = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _InvoicePickDialog(service: widget.service),
    );
    if (picked == null || !mounted) return;

    final invoiceNo = _pick(picked,
        ['invoice_number', 'invoiceNumber', 'invoice_no', 'invoiceNo', 'number', 'invoice']);
    if (invoiceNo.isNotEmpty) {
      final exists = await widget.service.checkInvoice(invoiceNo);
      if (!mounted) return;
      if (exists) {
        _toast('Invoice "$invoiceNo" is already recorded for a client.');
        return;
      }
    }

    final customer =
        picked['customer'] is Map ? Map<String, dynamic>.from(picked['customer']) : picked;

    // Parse each invoice line's description into components (keeping the parent
    // product name), mirroring the web's collectComponents/parseComponentLines.
    final compPairs = <({String product, String raw})>[];
    final rawItems = picked['items'];
    if (rawItems is List) {
      for (final li in rawItems.whereType<Map>()) {
        final m = Map<String, dynamic>.from(li);
        final product = m['product'] is Map
            ? _pick(Map<String, dynamic>.from(m['product']), ['name'])
            : _pick(m, ['name']);
        final lines = _parseComponentLines(_pick(m, ['description']));
        if (lines.isEmpty) {
          if (product.isNotEmpty) {
            compPairs.add((product: product, raw: product));
          }
        } else {
          for (final l in lines) {
            compPairs.add((product: product, raw: l));
          }
        }
      }
    }
    final rawComponents = compPairs.map((e) => e.raw).toList();

    setState(() {
      // Customer fields.
      final name = _pick(customer,
          ['display_name', 'name', 'company_name', 'customerName', 'email']);
      if (name.isNotEmpty) _name.text = name;
      if (invoiceNo.isNotEmpty) _invoice.text = invoiceNo;
      final date = _pick(picked,
          ['date_prepared', 'date', 'invoice_date', 'issued_at', 'created_at']);
      if (date.isNotEmpty) _datePrepared.text = date.split(' ').first.split('T').first;
      final addr = _pick(customer,
          ['address', 'registered_address', 'billing_address', 'shipping_address']);
      if (addr.isNotEmpty) _registeredAddress.text = addr;
      final tin = _pick(customer, ['tin', 'tax_id']);
      if (tin.isNotEmpty) _tin.text = tin;

      // System specs derived from the bundle components (web matchers).
      _fillSystemFrom(rawComponents);

      // Rebuild invoice items = one row per parsed component.
      for (final r in _items) {
        r.dispose();
      }
      _items
        ..clear()
        ..addAll(compPairs.map((p) => _ItemRow(itemName: p.product, component: p.raw)));
    });
    _toast('Auto-filled from invoice. Review below.');

    // Refine component/specification/brand via the server parser (best-effort),
    // aligned by index with the rows we just built.
    if (rawComponents.isNotEmpty) {
      final refined = await widget.service.parseInvoiceSpecs(rawComponents);
      if (!mounted || refined.isEmpty) return;
      setState(() {
        final enriched = <String>[];
        for (var i = 0; i < _items.length && i < refined.length; i++) {
          final d = refined[i];
          final comp = (d['component'] ?? '').toString();
          final spec = (d['specification'] ?? '').toString();
          final brand = (d['brand'] ?? '').toString();
          if (comp.isNotEmpty) _items[i].component.text = comp;
          if (spec.isNotEmpty) _items[i].optionValue.text = spec;
          if (brand.isNotEmpty) _items[i].brandName.text = brand;
          enriched.add('$comp $spec $brand');
        }
        // The AI-cleaned items usually name components clearly (e.g. "RAM 8GB",
        // "21.5 inch Monitor"), so re-run the matchers over them to fill any
        // System field the raw description missed.
        _fillSystemFrom(enriched, onlyIfEmpty: true);
      });
    }
  }

  /// Fill the System dropdowns/storage from a list of component strings using
  /// the web matchers. With [onlyIfEmpty], keeps values already set.
  void _fillSystemFrom(List<String> comps, {bool onlyIfEmpty = false}) {
    void setChoice(_Choice c, String v) {
      if (v.isEmpty) return;
      if (onlyIfEmpty && c.value.isNotEmpty) return;
      c.init(v);
    }

    setChoice(_systemUnit, _matchSystemUnit(comps));
    setChoice(_ram, _matchRam(comps));
    final storage = _matchStorage(comps);
    if (storage.isNotEmpty &&
        !(onlyIfEmpty && _storageConfig.text.trim().isNotEmpty)) {
      _storageConfig.text = storage;
    }
    setChoice(_monitorSize, _matchMonitorSize(comps));
    setChoice(_monitorBrand, _matchMonitorBrand(comps));
    setChoice(_monitorType, _matchMonitorType(comps));
  }

  /// Manual "AI fill" for the System section — refines the current invoice-item
  /// components with the server AI parser, then maps them into the System
  /// fields. Same idea as the web add-client auto-fill.
  Future<void> _aiFillSystem() async {
    final comps = _items
        .map((r) => r.component.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (comps.isEmpty) {
      _toast('Add or import invoice items first.');
      return;
    }
    setState(() => _aiBusy = true);
    final refined = await widget.service.parseInvoiceSpecs(comps);
    if (!mounted) return;
    final enriched = <String>[];
    for (var i = 0; i < comps.length; i++) {
      if (i < refined.length) {
        final d = refined[i];
        enriched.add(
            '${d['component'] ?? ''} ${d['specification'] ?? ''} ${d['brand'] ?? ''}');
      } else {
        enriched.add(comps[i]);
      }
    }
    setState(() {
      _aiBusy = false;
      _fillSystemFrom(enriched);
    });
    _toast('System details filled from items.');
  }

  String _pick(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
    }
    return '';
  }

  // ── Save ─────────────────────────────────────────────────────────────────────
  Map<String, String> _buildFields() => {
        'clientName': _name.text.trim(),
        'clientInvoiceNumber': _invoice.text.trim(),
        'clientDatePrepared': _datePrepared.text.trim(),
        'clientSystemsUnit': _systemUnit.value,
        'clientSystemUnitSerialNumber': _systemUnitSerial.text.trim(),
        'clientRamConfig': _ram.value,
        'clientMotherboardSerialNumber': _motherboardSerial.text.trim(),
        'clientstorageConfig': _storageConfig.text.trim(),
        'clientStorageSerialNumber': _storageSerial.text.trim(),
        'clientmonitorsizeConfig': _monitorSize.value,
        'clientmonitorbrandConfig': _monitorBrand.value,
        'clientmonitortypeConfig': _monitorType.value,
        'clientMonitorSerialNumber': _monitorSerial.text.trim(),
        'clientKeyboardSerialNumber': _keyboardSerial.text.trim(),
        'clientMouseSerialNumber': _mouseSerial.text.trim(),
        'clientbarcodescannerSerialNumber': _barcodeScannerSerial.text.trim(),
        'clientthermalprinterSerialNumber': _thermalPrinterSerial.text.trim(),
        'clientCashDrawerSerialNumber': _cashDrawerSerial.text.trim(),
        'clientBarcodePrinterSerialNumber': _barcodePrinterSerial.text.trim(),
        'clientcusdisplaySerialNumber': _cusDisplaySerial.text.trim(),
        'clientSystemSerialNumber': _systemSerial.text.trim(),
        'clientMacAddress': _mac.text.trim(),
        'clientMIN': _min.text.trim(),
        'clientPTU': _ptu.text.trim(),
        'clientDateApproved': _dateApproved.text.trim(),
        'clientTIN': _tin.text.trim(),
        'clientRegisteredAddress': _registeredAddress.text.trim(),
        'is_vat': _isVat ? '1' : '0',
      };

  Future<void> _save() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    if (_name.text.trim().isEmpty) {
      _toast('Customer name is required.');
      return;
    }
    setState(() => _saving = true);
    final result = await widget.service.save(
      id: widget.existing?.id,
      fields: _buildFields(),
      items: _items.map((r) => r.toItem()).toList(),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (result.ok) {
      _toast(widget.isEdit ? 'Client updated.' : 'Client created.');
      Navigator.of(context).pop(true);
    } else {
      _toast(result.message);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 4),
      ));
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final now = DateTime.now();
    final initial = DateTime.tryParse(controller.text.trim()) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1990),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null) return;
    setState(() =>
        controller.text = picked.toIso8601String().split('T').first);
  }

  @override
  Widget build(BuildContext context) {
    return StationScaffold(
      stationNumber: widget.isEdit
          ? widget.existing!.id.toString().padLeft(2, '0')
          : '＋',
      stationLabel: 'CLIENT DATA SHEET',
      title: widget.isEdit ? 'Edit client.' : 'New client.',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      child: ListView(
        physics: const BouncingScrollPhysics(),
        children: [
          if (!widget.isEdit) ...[
            _sectionHeader('Invoice'),
            Text(
              'Look up an invoice to auto-fill the customer details and bundle '
              'items. You can edit everything below.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            _uploadBox('FIND INVOICE', Icons.receipt_long_outlined, _findInvoice),
            const SizedBox(height: 36),
          ],

          _sectionHeader('Customer'),
          _field('CUSTOMER NAME', _name,
              textCapitalization: TextCapitalization.words),
          _field('AGREEMENT / INVOICE NUMBER', _invoice),
          _dateField('DATE PREPARED', _datePrepared),

          const SizedBox(height: 36),
          _sectionHeaderAction(
            'System',
            _aiBusy ? 'FILLING…' : 'AI FILL',
            Icons.auto_awesome,
            _aiBusy ? null : _aiFillSystem,
          ),
          _choiceField('SYSTEM UNIT', _systemUnit),
          _field('SYSTEM UNIT SERIAL', _systemUnitSerial),
          _choiceField('RAM', _ram),
          _field('STORAGE CONFIG', _storageConfig),
          _field('STORAGE SERIAL', _storageSerial),
          _choiceField('MONITOR SIZE', _monitorSize),
          _choiceField('MONITOR BRAND', _monitorBrand),
          _choiceField('MONITOR TYPE', _monitorType),
          _field('MONITOR SERIAL', _monitorSerial),
          const SizedBox(height: 24),
          _itemsSection(),

          const SizedBox(height: 36),
          _sectionHeader('Serial numbers'),
          _field('MOTHERBOARD', _motherboardSerial),
          _field('KEYBOARD', _keyboardSerial),
          _field('MOUSE', _mouseSerial),
          _field('BARCODE SCANNER', _barcodeScannerSerial),
          _field('THERMAL PRINTER', _thermalPrinterSerial),
          _field('CASH DRAWER', _cashDrawerSerial),
          _field('BARCODE PRINTER', _barcodePrinterSerial),
          _field('CUSTOMER DISPLAY', _cusDisplaySerial),

          const SizedBox(height: 36),
          _sectionHeader('BIR compliant system'),
          _field('SYSTEM SERIAL NUMBER', _systemSerial),
          _field('MAC ADDRESS', _mac),
          _field('MIN', _min),
          _field('PTU', _ptu),
          _dateField('DATE APPROVED', _dateApproved),
          _field('TIN', _tin),
          _field('REGISTERED ADDRESS', _registeredAddress, maxLines: 2),
          const SizedBox(height: 12),
          _vatSelector(),

          const SizedBox(height: 40),
          SignalButton(
            label: widget.isEdit ? 'Save changes' : 'Create client',
            busy: _saving,
            icon: Icons.check,
            onPressed: _saving ? null : _save,
          ),
          const SizedBox(height: 12),
          GhostButton(
            label: 'Cancel',
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Building blocks ─────────────────────────────────────────────────────────
  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            const Hairline(),
            const SizedBox(height: 8),
          ],
        ),
      );

  Widget _sectionHeaderAction(
      String title, String action, IconData icon, VoidCallback? onTap) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(title, style: text.headlineMedium),
              InkWell(
                onTap: onTap,
                child: Row(
                  children: [
                    Icon(icon,
                        size: 14,
                        color: onTap == null ? context.brand.paperDim : Brand.signal),
                    const SizedBox(width: 4),
                    Text(action,
                        style: text.labelMedium?.copyWith(
                            color:
                                onTap == null ? context.brand.paperDim : Brand.signal)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Hairline(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: controller,
          maxLines: maxLines,
          textCapitalization: textCapitalization,
          style: Theme.of(context).textTheme.titleMedium,
          decoration: InputDecoration(labelText: label),
        ),
      );

  Widget _dateField(String label, TextEditingController controller) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: controller,
          readOnly: true,
          onTap: () => _pickDate(controller),
          style: Theme.of(context).textTheme.titleMedium,
          decoration: InputDecoration(
            labelText: label,
            hintText: 'YYYY-MM-DD',
            suffixIcon: controller.text.isEmpty
                ? Icon(Icons.calendar_today_outlined,
                    size: 16, color: context.brand.paperDim)
                : IconButton(
                    icon: Icon(Icons.close,
                        size: 16, color: context.brand.paperDim),
                    onPressed: () => setState(() => controller.clear()),
                  ),
          ),
        ),
      );

  Widget _choiceField(String label, _Choice choice) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: choice.selected,
            isExpanded: true,
            dropdownColor: context.brand.surface,
            style: text.titleMedium,
            decoration: InputDecoration(labelText: label),
            hint: Text('Select', style: text.bodyMedium),
            items: [
              for (final o in choice.options)
                DropdownMenuItem(value: o, child: Text(o)),
              const DropdownMenuItem(value: 'Other', child: Text('Other')),
            ],
            onChanged: (v) => setState(() => choice.selected = v),
          ),
          if (choice.selected == 'Other')
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: TextField(
                controller: choice.other,
                style: text.titleMedium,
                decoration: const InputDecoration(labelText: 'OTHER'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _vatSelector() {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Text('VAT STATUS', style: text.labelMedium),
        const SizedBox(width: 16),
        _chip('VAT', _isVat, () => setState(() => _isVat = true)),
        const SizedBox(width: 8),
        _chip('NON-VAT', !_isVat, () => setState(() => _isVat = false)),
      ],
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Brand.signal : Colors.transparent,
          border:
              Border.all(color: selected ? Brand.signal : context.brand.rule, width: 1),
        ),
        child: Text(label,
            style: text.labelMedium?.copyWith(
              color: selected ? Brand.canvas : context.brand.paperDim,
              fontWeight: FontWeight.w700,
            )),
      ),
    );
  }

  Widget _uploadBox(String label, IconData icon, VoidCallback? onTap) {
    final text = Theme.of(context).textTheme;
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
        decoration: BoxDecoration(
          color: context.brand.surface,
          border:
              Border.all(color: enabled ? Brand.signal : context.brand.rule, width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: enabled ? Brand.signal : context.brand.paperDim),
            const SizedBox(width: 10),
            Text(label,
                style: text.labelLarge?.copyWith(
                  color: enabled ? Brand.signal : context.brand.paperDim,
                  fontSize: 12,
                  letterSpacing: 2.5,
                  fontWeight: FontWeight.w700,
                )),
          ],
        ),
      ),
    );
  }

  // ── Invoice items editor ──────────────────────────────────────────────────────
  Widget _itemsSection() {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Invoice items', style: text.headlineMedium),
            InkWell(
              onTap: () => setState(() => _items.add(_ItemRow())),
              child: Row(
                children: [
                  const Icon(Icons.add, size: 14, color: Brand.signal),
                  const SizedBox(width: 4),
                  Text('ADD',
                      style: text.labelMedium?.copyWith(color: Brand.signal)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Hairline(),
        const SizedBox(height: 12),
        if (_items.isEmpty)
          Text('No items. Tap ADD or look up an invoice.',
              style: text.bodySmall),
        for (int i = 0; i < _items.length; i++) _itemRow(i),
      ],
    );
  }

  Widget _itemRow(int index) {
    final row = _items[index];
    final text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.brand.surface,
        border: Border.all(color: context.brand.rule, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: row.itemName,
                  style: text.titleMedium,
                  decoration: const InputDecoration(labelText: 'ITEM / BUNDLE'),
                ),
              ),
              IconButton(
                tooltip: 'Remove',
                icon: Icon(Icons.delete_outline,
                    size: 18, color: context.brand.paperDim),
                onPressed: () =>
                    setState(() => _items.removeAt(index).dispose()),
              ),
            ],
          ),
          TextField(
            controller: row.component,
            style: text.titleMedium,
            decoration: const InputDecoration(labelText: 'COMPONENT'),
          ),
          TextField(
            controller: row.optionValue,
            style: text.titleMedium,
            decoration: const InputDecoration(labelText: 'SPECIFICATION'),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: row.brandName,
                  style: text.titleMedium,
                  decoration: const InputDecoration(labelText: 'BRAND'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: row.serialNumber,
                  style: text.titleMedium,
                  decoration: const InputDecoration(labelText: 'SERIAL'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Invoice → form matchers (Dart ports of the web client.php logic) ──────────

/// Split a line-item description into individual component strings.
List<String> _parseComponentLines(String text) {
  if (text.isEmpty) return const [];
  return text
      .split(RegExp(r'\r?\n|•|;'))
      .map((l) => l
          .replaceFirst(RegExp(r'^[\s\-*▪◦·]+'), '')
          .replaceFirst(RegExp(r'\s*[×xX]\s*\d+(\.\d+)?\s*$'), '')
          .trim())
      .where((l) => l.isNotEmpty)
      .toList();
}

bool _any(List<String> c, String pattern) =>
    c.any((s) => RegExp(pattern, caseSensitive: false).hasMatch(s));

String _matchSystemUnit(List<String> c) {
  if (_any(c, r'all\s*-?\s*in\s*-?\s*one')) return 'ALL IN ONE SYSTEM';
  if (_any(c, r'branded\s*cpu')) return 'Branded CPU';
  if (_any(c, r'generic\s*cpu')) return 'Generic CPU';
  return '';
}

String _matchRam(List<String> c) {
  for (final s in c) {
    if (RegExp(r'ram|memory', caseSensitive: false).hasMatch(s)) {
      final m = RegExp(r'(\d+)\s*GB', caseSensitive: false).firstMatch(s);
      if (m != null) return '${m.group(1)}GB';
    }
  }
  return '';
}

String _matchStorage(List<String> c) {
  final pairs = <String>[];
  for (final s in c) {
    String type = '';
    if (RegExp(r'\bssd\b|solid\s*state', caseSensitive: false).hasMatch(s)) {
      type = 'Solid State Drive';
    } else if (RegExp(r'\bhdd\b|hard\s*disk', caseSensitive: false).hasMatch(s)) {
      type = 'Hard Disk Drive';
    } else if (RegExp(r'\be?mmc\b', caseSensitive: false).hasMatch(s)) {
      type = 'MMC';
    }
    if (type.isEmpty) continue;
    pairs.add(type);
    final m =
        RegExp(r'(\d+(?:\.\d+)?)\s*(GB|TB)', caseSensitive: false).firstMatch(s);
    if (m != null) pairs.add('${m.group(1)}${m.group(2)!.toUpperCase()}');
  }
  return pairs.join(', ');
}

String _matchMonitorSize(List<String> c) {
  for (final s in c) {
    final m = RegExp(r'(\d+(?:\.\d+)?)\s*(?:inch|inches|")', caseSensitive: false)
        .firstMatch(s);
    if (m != null) return '${m.group(1)} Inches';
  }
  return '';
}

String _matchMonitorType(List<String> c) {
  for (final s in c) {
    if (RegExp(r'touch\s*screen', caseSensitive: false).hasMatch(s)) {
      return 'Touch Screen';
    }
    if (RegExp(r'non[\s-]*touch', caseSensitive: false).hasMatch(s)) {
      return 'Non Touch';
    }
    if (RegExp(r'projection', caseSensitive: false).hasMatch(s)) {
      return 'Projection Type';
    }
  }
  return '';
}

const _invoiceMonitorBrands = <String>[
  'N-Vision',
  'Supervision',
  'LG',
  'HP',
  'Acer',
  'AOC',
  'ASUS',
  'GreatWall',
  'Gamdas',
  'Orion',
  'TinkerPro',
];

String _matchMonitorBrand(List<String> c) {
  for (final s in c) {
    if (!RegExp(r'monitor|display|screen', caseSensitive: false).hasMatch(s)) {
      continue;
    }
    for (final b in _invoiceMonitorBrands) {
      if (RegExp(b.replaceAll('-', '[- ]?'), caseSensitive: false).hasMatch(s)) {
        return b;
      }
    }
  }
  return '';
}

/// Mutable holder for a dropdown that supports a free-text "Other" value.
class _Choice {
  _Choice(this.options);
  final List<String> options;
  String? selected;
  final TextEditingController other = TextEditingController();

  void init(String value) {
    if (value.isEmpty) {
      selected = null;
    } else if (options.contains(value)) {
      selected = value;
    } else {
      selected = 'Other';
      other.text = value;
    }
  }

  String get value => selected == 'Other' ? other.text.trim() : (selected ?? '');

  void dispose() => other.dispose();
}

/// Mutable holder for one invoice-item row.
class _ItemRow {
  _ItemRow({
    String itemName = '',
    String component = '',
    String optionValue = '',
    String brandName = '',
    String serialNumber = '',
  })  : itemName = TextEditingController(text: itemName),
        component = TextEditingController(text: component),
        optionValue = TextEditingController(text: optionValue),
        brandName = TextEditingController(text: brandName),
        serialNumber = TextEditingController(text: serialNumber);

  final TextEditingController itemName;
  final TextEditingController component;
  final TextEditingController optionValue;
  final TextEditingController brandName;
  final TextEditingController serialNumber;

  ClientInvoiceItem toItem() => ClientInvoiceItem(
        itemName: itemName.text.trim(),
        component: component.text.trim(),
        optionValue: optionValue.text.trim(),
        brandName: brandName.text.trim(),
        serialNumber: serialNumber.text.trim(),
      );

  void dispose() {
    itemName.dispose();
    component.dispose();
    optionValue.dispose();
    brandName.dispose();
    serialNumber.dispose();
  }
}

/// Search + pick an invoice from the external Invoice service. Returns the
/// chosen raw invoice map, or null if cancelled.
class _InvoicePickDialog extends StatefulWidget {
  const _InvoicePickDialog({required this.service});
  final ClientService service;

  @override
  State<_InvoicePickDialog> createState() => _InvoicePickDialogState();
}

class _InvoicePickDialogState extends State<_InvoicePickDialog> {
  final _controller = TextEditingController();
  bool _searching = false;
  String _message = '';
  List<Map<String, dynamic>> _results = const [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final term = _controller.text.trim();
    if (term.isEmpty || _searching) return;
    setState(() {
      _searching = true;
      _message = '';
      _results = const [];
    });
    final res = await widget.service.searchInvoice(term);
    if (!mounted) return;
    setState(() {
      _searching = false;
      _results = res;
      if (res.isEmpty) _message = 'No invoices matched “$term”.';
    });
  }

  String _pick(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Dialog(
      backgroundColor: context.brand.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: context.brand.rule, width: 1),
        borderRadius: BorderRadius.zero,
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long_outlined,
                    size: 18, color: Brand.signal),
                const SizedBox(width: 8),
                Expanded(child: Text('Find invoice', style: text.headlineMedium)),
                InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  child:
                      Icon(Icons.close, size: 18, color: context.brand.paperDim),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Hairline(),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              style: text.titleMedium,
              decoration: const InputDecoration(
                labelText: 'INVOICE NUMBER',
                hintText: 'e.g. INV-00123',
              ),
            ),
            const SizedBox(height: 12),
            SignalButton(
              label: 'Search',
              busy: _searching,
              icon: Icons.search,
              onPressed: _searching ? null : _search,
            ),
            if (_message.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(_message, style: text.bodySmall),
            ],
            if (_results.isNotEmpty) ...[
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _results.length,
                  separatorBuilder: (_, _) => const Hairline(),
                  itemBuilder: (_, i) {
                    final item = _results[i];
                    final no = _pick(item, [
                      'invoice_number',
                      'invoiceNumber',
                      'invoice_no',
                      'invoiceNo',
                      'number',
                      'invoice'
                    ]);
                    final cust = item['customer'] is Map
                        ? Map<String, dynamic>.from(item['customer'])
                        : item;
                    final name = _pick(cust, [
                      'display_name',
                      'name',
                      'company_name',
                      'customerName',
                      'email'
                    ]);
                    return InkWell(
                      onTap: () => Navigator.of(context).pop(item),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(no.isEmpty ? '—' : no,
                                style: text.titleSmall
                                    ?.copyWith(color: Brand.signal)),
                            if (name.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(name,
                                  style: text.bodySmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
