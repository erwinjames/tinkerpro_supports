import 'dart:async';

import 'package:flutter/material.dart';

import '../models/client_models.dart';
import '../services/client_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import '../widgets/serial_scanner.dart';

const String _snDefault = 'N/A';
const String _specNa = 'Not Applicable';
const String _specOther = 'Others';
const String _otherOption = 'Other';

const List<String> _systemUnitOptions = <String>[
  'Generic CPU',
  'Branded CPU',
  'ALL IN ONE SYSTEM',
];

const Map<String, String> _systemUnitLabels = <String, String>{
  'Generic CPU': 'Generic CPU',
  'Branded CPU': 'Branded CPU',
  'ALL IN ONE SYSTEM': 'All-in-One System',
};

const List<String> _ramOptions = <String>[
  '2GB',
  '4GB',
  '6GB',
  '8GB',
  '16GB',
  '32GB',
];

const List<String> _monitorSizeOptions = <String>[
  '14 Inches',
  '15.6 Inches',
  '17 Inches',
  '19 Inches',
  '20 Inches',
];

const Map<String, String> _monitorSizeLabels = <String, String>{
  '14 Inches': '14"',
  '15.6 Inches': '15.6"',
  '17 Inches': '17"',
  '19 Inches': '19"',
  '20 Inches': '20"',
};

const List<String> _monitorBrandOptions = <String>[
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

const List<String> _monitorTypeOptions = <String>[
  'Touch Screen',
  'Non Touch',
  'Projection Type',
];

const List<String> _storageTypeOptions = <String>[
  'Solid State Drive',
  'Hard Disk Drive',
  'MMC',
];

const Map<String, String> _storageTypeLabels = <String, String>{
  'Solid State Drive': 'SSD (Solid State Drive)',
  'Hard Disk Drive': 'HDD (Hard Disk Drive)',
  'MMC': 'MMC',
};

const List<String> _storageSizeOptions = <String>[
  '16GB',
  '32GB',
  '60GB',
  '120GB',
  '128GB',
  '130GB',
  '256GB',
  '500GB',
  '1TB',
];

const Map<String, List<String>> _specOptions = <String, List<String>>{
  'monitor': <String>[
    '14 Inches',
    '15.6 Inches',
    '17 Inches',
    '19 Inches',
    '20 Inches',
  ],
  'ram': <String>['2GB', '4GB', '6GB', '8GB', '16GB', '32GB'],
  'storage': <String>[
    '16GB',
    '32GB',
    '60GB',
    '120GB',
    '128GB',
    '256GB',
    '500GB',
    '1TB',
  ],
  'storagetype': <String>['HDD', 'SSD', 'M.2', 'eMMC', 'NVMe'],
  'cashdrawer': <String>['3 Bills', '4 Bills', '5 Bills', '6 Bills', '8 Bills'],
  'printer': <String>['58mm', '80mm'],
  'processor': <String>[
    '1.8 GHz',
    '2.0 GHz',
    '2.4 GHz',
    '2.6 GHz',
    '3.0 GHz',
    '3.2 GHz',
    '3.6 GHz',
  ],
  'barcode': <String>['1D', '2D'],
};

const Map<String, List<String>> _specBrands = <String, List<String>>{
  'monitor': <String>[
    'N-Vision',
    'Supervision',
    'Dell',
    'LG',
    'HP',
    'Acer',
    'AOC',
    'ASUS',
    'Samsung',
    'GreatWall',
    'Gamdas',
    'Orion',
    'TinkerPro',
  ],
  'processor': <String>['AMD', 'Intel'],
};

const List<String> _monthNames = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

class _SerialFieldSpec {
  const _SerialFieldSpec(this.label, this.icon, this.formKey, this.column);

  final String label;
  final IconData icon;
  final String formKey;
  final String column;
}

const List<_SerialFieldSpec> _serialFields = <_SerialFieldSpec>[
  _SerialFieldSpec(
    'Motherboard',
    Icons.memory_rounded,
    'clientMotherboardSerialNumber',
    'motherboard_serialnum',
  ),
  _SerialFieldSpec(
    'Keyboard',
    Icons.keyboard_rounded,
    'clientKeyboardSerialNumber',
    'keyboard_serialnum',
  ),
  _SerialFieldSpec(
    'Mouse',
    Icons.mouse_rounded,
    'clientMouseSerialNumber',
    'mouse_serialnum',
  ),
  _SerialFieldSpec(
    'Barcode Scanner',
    Icons.qr_code_scanner_rounded,
    'clientbarcodescannerSerialNumber',
    'barcodeScanner_serialnum',
  ),
  _SerialFieldSpec(
    'Thermal Printer',
    Icons.print_rounded,
    'clientthermalprinterSerialNumber',
    'thermalPrinter_serialnum',
  ),
  _SerialFieldSpec(
    'Cash Drawer',
    Icons.point_of_sale_rounded,
    'clientCashDrawerSerialNumber',
    'cashDrawer_serialnum',
  ),
  _SerialFieldSpec(
    'Barcode Printer',
    Icons.local_printshop_rounded,
    'clientBarcodePrinterSerialNumber',
    'barcodePrinter_serialnum',
  ),
  _SerialFieldSpec(
    'Customer Display (Pole / Monitor)',
    Icons.desktop_windows_rounded,
    'clientcusdisplaySerialNumber',
    'cusdisplay_serialnum',
  ),
];

class ClientFormScreen extends StatefulWidget {
  const ClientFormScreen({super.key, required this.service, this.existing});

  final ClientService service;
  final ClientDetail? existing;

  bool get isEdit => existing != null;

  @override
  State<ClientFormScreen> createState() => _ClientFormScreenState();
}

class _ClientFormScreenState extends State<ClientFormScreen> {
  final _name = TextEditingController();
  final _invoice = TextEditingController();
  final _branch = TextEditingController();
  final _datePrepared = TextEditingController();
  final _dateApproved = TextEditingController();
  final _storageConfig = TextEditingController();
  final _systemSerial = TextEditingController();
  final _mac = TextEditingController();
  final _min = TextEditingController();
  final _ptu = TextEditingController();
  final _tin = TextEditingController();
  final _registeredAddress = TextEditingController();

  final Map<String, TextEditingController> _serials =
      <String, TextEditingController>{
        for (final f in _serialFields) f.formKey: TextEditingController(),
      };

  final List<_UnitGroup> _units = <_UnitGroup>[];
  final List<_RamGroup> _rams = <_RamGroup>[];
  final List<_StorageRow> _storage = <_StorageRow>[];
  final List<_MonitorGroup> _monitors = <_MonitorGroup>[];
  final List<_SpecRow> _specRows = <_SpecRow>[];

  final Map<String, String> _syncedSerials = <String, String>{};
  final Set<TextEditingController> _revealed = <TextEditingController>{};
  final Set<String> _invalid = <String>{};
  List<ClientSpecReplacement> _replacements = <ClientSpecReplacement>[];

  bool _isVat = false;
  bool _invoiceMode = false;
  bool _customerLocked = false;
  bool _specLocked = true;
  bool _saving = false;
  bool _aiBusy = false;
  bool _reloading = false;
  int? _clientId;

  @override
  void initState() {
    super.initState();
    _units.add(_UnitGroup());
    _rams.add(_RamGroup());
    _monitors.add(_MonitorGroup());
    final e = widget.existing;
    if (e == null) {
      _setStorageConfigValue('');
      _applySerialDefaults();
    } else {
      _clientId = e.id;
      _loadFrom(e);
    }
  }

  void _loadFrom(ClientDetail e) {
    _revealed.clear();
    _invalid.clear();
    _syncedSerials.clear();
    _invoiceMode = false;
    _customerLocked = false;
    _specLocked = true;
    _name.text = e.name;
    _invoice.text = e.invoiceNumber;
    _branch.text = e.branch;
    _datePrepared.text = e.datePrepared;
    _dateApproved.text = e.dateApproved;
    _mac.text = e.macAddress;
    _min.text = e.min;
    _ptu.text = e.ptu;
    _tin.text = e.tin;
    _registeredAddress.text = e.registeredAddress;
    _systemSerial.text = e.systemSerial;
    _isVat = e.isVat;
    _replacements = e.specReplacements;

    final serialValues = <String, String>{
      'clientMotherboardSerialNumber': e.motherboardSerial,
      'clientKeyboardSerialNumber': e.keyboardSerial,
      'clientMouseSerialNumber': e.mouseSerial,
      'clientbarcodescannerSerialNumber': e.barcodeScannerSerial,
      'clientthermalprinterSerialNumber': e.thermalPrinterSerial,
      'clientCashDrawerSerialNumber': e.cashDrawerSerial,
      'clientBarcodePrinterSerialNumber': e.barcodePrinterSerial,
      'clientcusdisplaySerialNumber': e.cusDisplaySerial,
    };
    serialValues.forEach((k, v) => _serials[k]!.text = v);

    _populateUnitGroups(e.systemUnit, e.systemUnitSerial);
    _populateRamGroups(e.ramConfig);
    _setStorageConfigValue(e.storageConfig);
    _setStorageSerialValue(e.storageSerial);
    _populateMonitorGroups(
      e.monitorSize,
      e.monitorBrand,
      e.monitorType,
      e.monitorSerial,
    );

    if (e.invoiceItems.isNotEmpty) {
      _buildStoredSpecRows(e.invoiceItems);
      _invoiceMode = true;
      _customerLocked = true;
      _specLocked = true;
      _syncInvoiceSerials();
    }
  }

  @override
  void dispose() {
    for (final c in <TextEditingController>[
      _name,
      _invoice,
      _branch,
      _datePrepared,
      _dateApproved,
      _storageConfig,
      _systemSerial,
      _mac,
      _min,
      _ptu,
      _tin,
      _registeredAddress,
      ..._serials.values,
    ]) {
      c.dispose();
    }
    for (final g in _units) {
      g.dispose();
    }
    for (final g in _rams) {
      g.dispose();
    }
    for (final g in _storage) {
      g.dispose();
    }
    for (final g in _monitors) {
      g.dispose();
    }
    for (final r in _specRows) {
      r.dispose();
    }
    super.dispose();
  }

  void _applySerialDefaults() {
    for (final c in _serials.values) {
      if (c.text.trim().isEmpty) c.text = _snDefault;
    }
  }

  void _populateUnitGroups(String brands, String serials) {
    for (final g in _units) {
      g.dispose();
    }
    _units.clear();
    final names = _splitCsv(brands);
    final sns = _splitCsvKeepEmpty(serials);
    final count = <int>[
      names.length,
      sns.length,
      1,
    ].reduce((a, b) => a > b ? a : b);
    for (var i = 0; i < count; i++) {
      final g = _UnitGroup();
      g.setValue(i < names.length ? names[i] : '');
      g.serial.text = i < sns.length ? sns[i] : '';
      _units.add(g);
    }
  }

  void _populateRamGroups(String value) {
    for (final g in _rams) {
      g.dispose();
    }
    _rams.clear();
    final list = _splitCsv(value);
    if (list.isEmpty) {
      _rams.add(_RamGroup());
      return;
    }
    for (final v in list) {
      _rams.add(_RamGroup()..choice.init(v));
    }
  }

  void _populateMonitorGroups(
    String sizes,
    String brands,
    String types,
    String serials,
  ) {
    for (final g in _monitors) {
      g.dispose();
    }
    _monitors.clear();
    final s = _splitCsv(sizes);
    final b = _splitCsv(brands);
    final t = _splitCsv(types);
    final sn = _splitCsvKeepEmpty(serials);
    final count = <int>[
      s.length,
      b.length,
      t.length,
      sn.length,
      1,
    ].reduce((a, b) => a > b ? a : b);
    for (var i = 0; i < count; i++) {
      final g = _MonitorGroup();
      g.size.init(i < s.length ? s[i] : '');
      g.brand.init(i < b.length ? b[i] : '');
      g.type.init(i < t.length ? t[i] : '');
      g.serial.text = i < sn.length ? sn[i] : '';
      _monitors.add(g);
    }
  }

  void _setStorageConfigValue(String value) {
    for (final r in _storage) {
      r.dispose();
    }
    _storage.clear();
    final parts = _splitCsv(value);
    _StorageRow? current;
    for (final p in parts) {
      if (_storageTypeOptions.contains(p)) {
        current = _StorageRow()..setType(p);
        _storage.add(current);
      } else if (current != null && current.sizeValue.isEmpty) {
        current.setSize(p);
      } else {
        current = _StorageRow()..setSize(p);
        _storage.add(current);
      }
    }
    if (_storage.isEmpty) _storage.add(_StorageRow());
    _rebuildStorageConfig();
  }

  void _setStorageSerialValue(String value) {
    final vals = _splitCsvKeepEmpty(value);
    for (var i = 0; i < _storage.length; i++) {
      _storage[i].serial.text = i < vals.length ? vals[i] : '';
    }
  }

  void _rebuildStorageConfig() {
    final out = <String>[];
    for (final r in _storage) {
      final t = r.typeValue;
      final s = r.sizeValue;
      if (t.isNotEmpty) out.add(t);
      if (s.isNotEmpty) out.add(s);
    }
    _storageConfig.text = out.join(', ');
  }

  String _storageSerialValue() {
    final out = _storage.map((r) => r.serial.text.trim()).toList();
    while (out.isNotEmpty && out.last.isEmpty) {
      out.removeLast();
    }
    return out.join(', ');
  }

  void _buildStoredSpecRows(List<ClientInvoiceItem> items) {
    for (final r in _specRows) {
      r.dispose();
    }
    _specRows.clear();
    final byGroup = <String, Map<String, _SpecRow>>{};
    for (var i = 0; i < items.length; i++) {
      final row = items[i];
      final groupName = row.itemName.trim().isEmpty
          ? 'Item'
          : row.itemName.trim();
      final component = row.component.trim();
      final meta = _normalizeSpec(component);
      var optionVal = row.optionValue.trim();
      var sizeVal = '';
      if (meta.optionsKey == 'storagetype') {
        final m = RegExp(
          r'(\d+(?:\.\d+)?)\s*(GB|TB)',
          caseSensitive: false,
        ).firstMatch(optionVal);
        if (m != null) {
          sizeVal = '${m.group(1)}${m.group(2)!.toUpperCase()}';
          optionVal = optionVal.replaceFirst(m.group(0)!, '').trim();
        }
      }
      final serial = row.serialNumber.trim();
      final entry = _SpecEntry(
        optionsKey: meta.optionsKey,
        freeSpec: meta.optionsKey.isEmpty,
        option: optionVal,
        size: sizeVal,
        brand: row.brandName.trim(),
        serial: (serial.isEmpty || serial == _snDefault) ? '' : serial,
        target: meta.target,
        raw: component,
        serverIndex: i,
      );
      final key = component.toLowerCase();
      final group = byGroup.putIfAbsent(groupName, () => <String, _SpecRow>{});
      final existing = group[key];
      if (existing != null) {
        existing.entries.add(entry);
      } else {
        final specRow = _SpecRow(
          itemName: groupName,
          component: component,
          icon: meta.icon,
          optionsKey: meta.optionsKey,
          freeSpec: meta.optionsKey.isEmpty,
        )..entries.add(entry);
        group[key] = specRow;
        _specRows.add(specRow);
      }
    }
    _initSystemSerialToggle();
  }

  void _buildInvoiceSpecRows(Map<String, dynamic> invoice) {
    for (final r in _specRows) {
      r.dispose();
    }
    _specRows.clear();
    final rawItems = invoice['items'];
    if (rawItems is! List) return;
    for (final li in rawItems.whereType<Map>()) {
      final m = Map<String, dynamic>.from(li);
      final product = m['product'] is Map
          ? _pick(Map<String, dynamic>.from(m['product']), <String>['name'])
          : _pick(m, <String>['name']);
      final pname = product.isEmpty ? 'Item' : product;
      final qtyRaw = m['qty'];
      final qty = qtyRaw == null ? '' : ' ×${_trimNumber(qtyRaw.toString())}';
      var comps = _parseComponentLines(_pick(m, <String>['description']));
      if (comps.isEmpty) comps = <String>[pname];
      final groupName = '$pname$qty';
      final byComp = <String, _SpecRow>{};
      for (final c in comps) {
        final meta = _normalizeSpec(c);
        final entry = _SpecEntry(
          optionsKey: meta.optionsKey,
          freeSpec: meta.optionsKey.isEmpty,
          option: meta.defaultOption,
          size: meta.defaultSize,
          brand: meta.defaultBrand,
          serial: '',
          target: meta.target,
          raw: c,
        );
        final key = meta.name.toLowerCase();
        final existing = byComp[key];
        if (existing != null) {
          existing.entries.add(entry);
        } else {
          final row = _SpecRow(
            itemName: groupName,
            component: meta.name,
            icon: meta.icon,
            optionsKey: meta.optionsKey,
            freeSpec: meta.optionsKey.isEmpty,
          )..entries.add(entry);
          byComp[key] = row;
          _specRows.add(row);
        }
      }
    }
    _initSystemSerialToggle();
  }

  void _initSystemSerialToggle() {
    final storageEntries = <_SpecEntry>[];
    for (final row in _specRows) {
      if (row.optionsKey != 'storagetype') continue;
      storageEntries.addAll(row.entries);
    }
    if (storageEntries.isEmpty) return;
    if (!storageEntries.any((e) => e.sysSerial)) {
      storageEntries.first.sysSerial = true;
    }
  }

  bool get _systemSerialEnabled {
    if (!_invoiceMode) return true;
    final toggles = <_SpecEntry>[];
    for (final row in _specRows) {
      if (row.optionsKey != 'storagetype') continue;
      toggles.addAll(row.entries);
    }
    if (toggles.isEmpty) return true;
    return toggles.any((e) => e.sysSerial);
  }

  void _syncInvoiceSerials() {
    final groups = <String, List<String>>{};
    for (final row in _specRows) {
      for (final e in row.entries) {
        if (e.target.isEmpty) continue;
        groups
            .putIfAbsent(e.target, () => <String>[])
            .add(e.serial.text.trim());
      }
    }
    _syncedSerials.clear();
    groups.forEach((target, values) {
      final joined = values.where((v) => v.isNotEmpty).join(', ');
      _syncedSerials[target] = joined.isEmpty ? _snDefault : joined;
    });
  }

  Future<void> _openInvoiceSearch() async {
    final picked = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _InvoicePickDialog(service: widget.service),
    );
    if (picked == null || !mounted) return;
    await _selectInvoice(picked);
  }

  Future<void> _selectInvoice(Map<String, dynamic> invoice) async {
    final invNo = _invoiceNumberOf(invoice);
    final invBranch = _invoiceBranchOf(invoice);
    final invLabel = invBranch.isEmpty ? invNo : '$invNo ($invBranch)';

    final check = await widget.service.checkInvoice(invNo, branch: invBranch);
    if (!mounted) return;
    if (check.exists) {
      final takenBy = check.clientName.trim().isEmpty
          ? ''
          : ' (${check.clientName.trim()})';
      if (!check.branchMatched) {
        final proceed = await _confirm(
          title: 'Invoice already recorded',
          message:
              'Invoice $invNo is already recorded$takenBy without a branch. '
              'Continue with branch $invBranch?',
          confirmLabel: 'Continue anyway',
        );
        if (proceed != true || !mounted) return;
      } else {
        await _alert(
          title: 'Invoice already recorded',
          message: 'Invoice $invLabel already has a client record$takenBy.',
        );
        return;
      }
    }

    _fillFromInvoice(invoice);
    _toast('Form auto-filled from invoice $invLabel');
    unawaited(_runSpecAutoFill(silent: true));
  }

  void _fillFromInvoice(Map<String, dynamic> invoice) {
    final customer = invoice['customer'] is Map
        ? Map<String, dynamic>.from(invoice['customer'])
        : <String, dynamic>{};
    final components = <String>[];
    final rawItems = invoice['items'];
    if (rawItems is List) {
      for (final li in rawItems.whereType<Map>()) {
        components.addAll(
          _parseComponentLines(
            _pick(Map<String, dynamic>.from(li), <String>['description']),
          ),
        );
      }
    }

    setState(() {
      final name = _pick(customer, <String>[
        'display_name',
        'name',
        'company_name',
        'customerName',
        'email',
      ]);
      _name.text = name.isNotEmpty
          ? name
          : _pick(invoice, <String>['name', 'customer_name']);
      _invoice.text = _invoiceNumberOf(invoice);
      _branch.text = _invoiceBranchOf(invoice);
      final date = _pick(invoice, <String>[
        'date_prepared',
        'date',
        'invoice_date',
        'issued_at',
        'created_at',
      ]);
      _datePrepared.text = date.isEmpty
          ? ''
          : date.split(' ').first.split('T').first;
      _registeredAddress.text = _pick(customer, <String>[
        'address',
        'registered_address',
        'billing_address',
        'shipping_address',
      ]);
      _tin.text = _pick(customer, <String>['tin', 'tax_id']);

      _populateUnitGroups(_matchSystemUnit(components), '');
      _populateRamGroups(_matchRam(components));
      _setStorageConfigValue(_matchStorage(components));
      _populateMonitorGroups(
        _matchMonitorSize(components),
        _matchMonitorBrand(components),
        _matchMonitorType(components),
        '',
      );

      _buildInvoiceSpecRows(invoice);
      _syncInvoiceSerials();
      _invoiceMode = true;
      _customerLocked = true;
      _specLocked = true;
      _invalid.clear();
    });
  }

  void _clearInvoiceMode() {
    setState(() {
      for (final r in _specRows) {
        r.dispose();
      }
      _specRows.clear();
      _syncedSerials.clear();
      _invoiceMode = false;
      _customerLocked = false;
      _specLocked = true;
      _applySerialDefaults();
    });
  }

  Future<void> _runSpecAutoFill({bool silent = false}) async {
    final components = _specRows
        .map((r) => r.raw.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (components.isEmpty) {
      if (!silent) _toast('Look up an invoice first.');
      return;
    }
    if (!silent) setState(() => _aiBusy = true);
    final parsed = await widget.service.parseInvoiceSpecs(components);
    if (!mounted) return;
    if (parsed.isEmpty) {
      if (!silent) {
        setState(() => _aiBusy = false);
        _toast('Could not read the invoice specifications.');
      }
      return;
    }
    setState(() {
      _aiBusy = false;
      for (var i = 0; i < _specRows.length && i < parsed.length; i++) {
        final d = parsed[i];
        final row = _specRows[i];
        final comp = (d['component'] ?? '').toString().trim();
        final spec = (d['specification'] ?? '').toString().trim();
        final brand = (d['brand'] ?? '').toString().trim();
        if (comp.isNotEmpty) row.component.text = comp;
        for (final e in row.entries) {
          if (spec.isNotEmpty && e.option.value.isEmpty) e.option.set(spec);
          if (brand.isNotEmpty && e.brand.text.trim().isEmpty) {
            e.brand.text = brand;
          }
        }
      }
    });
    if (!silent) _toast('System details filled from items.');
  }

  Map<String, String> _buildFields() {
    final fields = <String, String>{
      'clientName': _name.text.trim(),
      'clientInvoiceNumber': _invoice.text.trim(),
      'clientBranch': _branch.text.trim(),
      'clientDatePrepared': _datePrepared.text.trim(),
      'clientSystemsUnit': _units
          .map((g) => g.value)
          .where((v) => v.isNotEmpty)
          .join(', '),
      'clientSystemUnitSerialNumber': _units
          .map((g) => g.serial.text.trim())
          .where((v) => v.isNotEmpty)
          .join(', '),
      'clientRamConfig': _rams
          .map((g) => g.choice.value)
          .where((v) => v.isNotEmpty)
          .join(', '),
      'clientstorageConfig': _storageConfig.text.trim(),
      'clientStorageSerialNumber': _storageSerialValue(),
      'clientmonitorsizeConfig': _monitors
          .map((g) => g.size.value)
          .where((v) => v.isNotEmpty)
          .join(', '),
      'clientmonitorbrandConfig': _monitors
          .map((g) => g.brand.value)
          .where((v) => v.isNotEmpty)
          .join(', '),
      'clientmonitortypeConfig': _monitors
          .map((g) => g.type.value)
          .where((v) => v.isNotEmpty)
          .join(', '),
      'clientMonitorSerialNumber': _monitors
          .map((g) => g.serial.text.trim())
          .where((v) => v.isNotEmpty)
          .join(', '),
      for (final f in _serialFields)
        f.formKey: _serials[f.formKey]!.text.trim(),
      'clientSystemSerialNumber': _systemSerial.text.trim(),
      'clientMacAddress': _mac.text.trim(),
      'clientMIN': _min.text.trim(),
      'clientPTU': _ptu.text.trim(),
      'clientDateApproved': _dateApproved.text.trim(),
      'clientTIN': _tin.text.trim(),
      'clientRegisteredAddress': _registeredAddress.text.trim(),
      'is_vat': _isVat ? '1' : '0',
    };
    if (_invoiceMode) {
      _syncInvoiceSerials();
      _syncedSerials.forEach((key, value) => fields[key] = value);
    }
    return fields;
  }

  List<ClientInvoiceItem> _buildInvoiceItems() {
    if (!_invoiceMode) return const <ClientInvoiceItem>[];
    final out = <ClientInvoiceItem>[];
    for (final row in _specRows) {
      for (final e in row.entries) {
        final optionValue = row.freeSpec
            ? e.freeValue.text.trim()
            : row.optionsKey == 'storagetype'
            ? <String>[
                e.option.value,
                e.size.value,
              ].where((v) => v.isNotEmpty).join(' ')
            : e.option.value;
        final brand = e.brand.text.trim();
        final serial = e.serial.text.trim();
        if (optionValue.isEmpty && brand.isEmpty && serial.isEmpty) continue;
        out.add(
          ClientInvoiceItem(
            itemName: row.itemName,
            component: row.component.text.trim(),
            optionValue: optionValue,
            brandName: brand,
            serialNumber: serial,
          ),
        );
      }
    }
    return out;
  }

  bool _validate() {
    final missing = <String>{};
    if (_name.text.trim().isEmpty) missing.add('clientName');
    if (_invoice.text.trim().isEmpty) missing.add('clientInvoiceNumber');
    if (_datePrepared.text.trim().isEmpty) missing.add('clientDatePrepared');
    if (!_invoiceMode) {
      if (_units.isEmpty || _units.first.value.isEmpty) {
        missing.add('clientSystemsUnit');
      }
      if (_rams.isEmpty || _rams.first.choice.value.isEmpty) {
        missing.add('clientRamConfig');
      }
      if (_monitors.isEmpty || _monitors.first.size.value.isEmpty) {
        missing.add('clientmonitorsizeConfig');
      }
      if (_monitors.isEmpty || _monitors.first.brand.value.isEmpty) {
        missing.add('clientmonitorbrandConfig');
      }
    }
    setState(() {
      _invalid
        ..clear()
        ..addAll(missing);
    });
    return missing.isEmpty;
  }

  Future<void> _save() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    if (!_validate()) {
      _toast('Please fill in the required fields.');
      return;
    }
    setState(() => _saving = true);
    final result = await widget.service.save(
      id: _clientId,
      fields: _buildFields(),
      items: _buildInvoiceItems(),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (result.ok) {
      _toast(
        widget.isEdit
            ? 'Client Updated Successfully'
            : 'Client Added Successfully',
      );
      Navigator.of(context).pop(true);
    } else {
      _toast(
        widget.isEdit
            ? 'Client Not Updated: ${result.message}'
            : 'Client Not Added: ${result.message}',
      );
    }
  }

  Future<void> _reload() async {
    final id = _clientId;
    if (id == null || _reloading) return;
    setState(() => _reloading = true);
    final fresh = await widget.service.detail(id);
    if (!mounted) return;
    setState(() {
      _reloading = false;
      if (fresh != null) _loadFrom(fresh);
    });
  }

  Future<void> _recordReplacement(_ReplacementTarget target) async {
    final id = _clientId;
    if (id == null) return;
    final result = await showDialog<({String component, String serial})>(
      context: context,
      builder: (_) => _ReplacementDialog(componentName: target.componentName),
    );
    if (result == null || !mounted) return;
    if (result.component.trim().isEmpty && result.serial.trim().isEmpty) {
      _toast('Enter the replacement component or serial number.');
      return;
    }
    final res = await widget.service.addSpecReplacement(
      clientId: id,
      src: target.src,
      index: target.index,
      serialField: target.serialField,
      oldComponent: target.componentName,
      newComponent: result.component.trim(),
      newSerial: result.serial.trim(),
    );
    if (!mounted) return;
    _toast(res.message);
    if (res.ok) await _reload();
  }

  String _fieldDisplayName(_SerialFieldSpec f) {
    final list = _historyFor('${f.column}:0');
    if (list.isEmpty) return f.label;
    final latest = list.last.newComponent.trim();
    return latest.isEmpty ? f.label : latest;
  }

  List<ClientSpecReplacement> _historyFor(String rowKey) {
    if (rowKey.isEmpty) return const <ClientSpecReplacement>[];
    return _replacements.where((r) => r.rowKey == rowKey).toList();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
      );
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const IconTile(
          icon: Icons.warning_amber_rounded,
          color: Brand.warning,
          size: 44,
          iconSize: 22,
        ),
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _alert({required String title, required String message}) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const IconTile(
          icon: Icons.error_outline_rounded,
          color: Brand.danger,
          size: 44,
          iconSize: 22,
        ),
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
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
    setState(() => controller.text = picked.toIso8601String().split('T').first);
  }

  @override
  Widget build(BuildContext context) {
    return StationScaffold(
      stationNumber: widget.isEdit
          ? widget.existing!.id.toString().padLeft(2, '0')
          : '＋',
      stationLabel: 'Clients',
      title: widget.isEdit ? 'Edit client' : 'New client',
      subtitle: widget.isEdit ? widget.existing!.name : 'Client data sheet',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      bottomBar: _bottomBar(),
      child: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(top: 4, bottom: 16),
        children: <Widget>[
          if (!widget.isEdit) _invoiceSearchSection(),
          _customerSection(),
          _systemSection(),
          if (!_invoiceMode) _serialSection(),
          _birSection(),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    final b = context.brand;
    return Material(
      color: b.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: b.rule)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Row(
              children: <Widget>[
                Expanded(
                  flex: 2,
                  child: GhostButton(
                    label: 'Cancel',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: SignalButton(
                    label: widget.isEdit ? 'Save changes' : 'Create client',
                    busy: _saving,
                    icon: Icons.check_rounded,
                    onPressed: _saving ? null : _save,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _invoiceSearchSection() {
    return _section(
      index: 0,
      title: 'Invoice',
      icon: Icons.receipt_long_rounded,
      subtitle:
          'Search invoice number to auto-fill the customer details and the '
          'system specifications. You can edit everything below.',
      action: _invoiceMode
          ? _sectionAction('Clear', Icons.close_rounded, _clearInvoiceMode)
          : null,
      children: <Widget>[
        _uploadBox('Find invoice', Icons.search_rounded, _openInvoiceSearch),
      ],
    );
  }

  Widget _customerSection() {
    return _section(
      index: 1,
      title: 'Customer Information',
      icon: Icons.person_rounded,
      action: _invoiceMode
          ? _sectionAction(
              _customerLocked ? 'Edit' : 'Done',
              _customerLocked ? Icons.edit_rounded : Icons.check_rounded,
              () => setState(() => _customerLocked = !_customerLocked),
            )
          : null,
      children: _customerLocked
          ? <Widget>[
              _staticRow('Customer Name', _name.text),
              _staticRow('Agreement / Invoice Number', _invoice.text),
              _staticRow('Branch', _branch.text),
              _staticRow('Date Prepared', _datePrepared.text),
            ]
          : <Widget>[
              _field(
                'Customer Name',
                _name,
                fieldKey: 'clientName',
                required: true,
                textCapitalization: TextCapitalization.words,
                hint: 'Enter customer name',
              ),
              _field(
                'Agreement / Invoice Number',
                _invoice,
                fieldKey: 'clientInvoiceNumber',
                required: true,
                hint: 'Invoice number',
              ),
              _field('Branch', _branch, hint: 'Branch'),
              _dateField(
                'Date Prepared',
                _datePrepared,
                fieldKey: 'clientDatePrepared',
                required: true,
              ),
            ],
    );
  }

  Widget _systemSection() {
    return _section(
      index: 2,
      title: 'System Specifications',
      icon: Icons.computer_rounded,
      subtitle: _invoiceMode ? null : 'Hardware and system setup',
      action: _invoiceMode
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _sectionAction(
                  _aiBusy ? 'Filling…' : 'AI fill',
                  Icons.auto_awesome_rounded,
                  _aiBusy ? null : _runSpecAutoFill,
                ),
                _sectionAction(
                  _specLocked ? 'Edit' : 'Done',
                  _specLocked ? Icons.edit_rounded : Icons.check_rounded,
                  () => setState(() => _specLocked = !_specLocked),
                ),
              ],
            )
          : null,
      children: _invoiceMode ? _invoiceSpecChildren() : _manualSpecChildren(),
    );
  }

  List<Widget> _manualSpecChildren() {
    return <Widget>[
      _groupLabel('Systems Unit Brand', Icons.dns_rounded, required: true),
      for (var i = 0; i < _units.length; i++) _unitGroupCard(i),
      _addMoreButton(
        'Add More',
        () => setState(() => _units.add(_UnitGroup())),
      ),
      const SizedBox(height: 18),
      _groupLabel('RAM Configuration', Icons.memory_rounded, required: true),
      for (var i = 0; i < _rams.length; i++) _ramGroupCard(i),
      _addMoreButton('Add More', () => setState(() => _rams.add(_RamGroup()))),
      const SizedBox(height: 18),
      _groupLabel('HDD / SSD Type and Size', Icons.storage_rounded),
      for (var i = 0; i < _storage.length; i++) _storageRowCard(i),
      _addMoreButton(
        'Add More',
        () => setState(() {
          _storage.add(_StorageRow());
          _rebuildStorageConfig();
        }),
      ),
      const SizedBox(height: 18),
      _groupLabel('Monitor', Icons.tv_rounded, required: true),
      for (var i = 0; i < _monitors.length; i++) _monitorGroupCard(i),
      _addMoreButton(
        'Add Monitor',
        () => setState(() => _monitors.add(_MonitorGroup())),
      ),
    ];
  }

  Widget _unitGroupCard(int index) {
    final g = _units[index];
    final branded = RegExp(
      r'^branded cpu',
      caseSensitive: false,
    ).hasMatch(g.selected ?? '');
    return _rowShell(
      onRemove: index == 0
          ? null
          : () => setState(() => _units.removeAt(index).dispose()),
      replacement: _replacementFor(
        _ReplacementTarget(
          src: 'field',
          index: index,
          serialField: 'system_unit_serialnum',
          componentName: g.value.isEmpty ? 'System Unit' : g.value,
        ),
      ),
      children: <Widget>[
        _dropdown(
          value: g.selected,
          hint: 'Select an option',
          invalid: index == 0 && _invalid.contains('clientSystemsUnit'),
          options: _systemUnitOptions,
          labelOf: (v) => _systemUnitLabels[v] ?? v,
          onChanged: (v) => setState(() {
            g.selected = v;
            if (!RegExp(
              r'^branded cpu',
              caseSensitive: false,
            ).hasMatch(v ?? '')) {
              g.brand.clear();
            }
          }),
        ),
        if (branded) ...<Widget>[
          const SizedBox(height: 8),
          TextField(
            controller: g.brand,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Brand name (e.g. HP, Dell)',
              isDense: true,
            ),
          ),
        ],
        const SizedBox(height: 8),
        _optionalSerial(g.serial),
      ],
    );
  }

  Widget _ramGroupCard(int index) {
    final g = _rams[index];
    return _rowShell(
      onRemove: index == 0
          ? null
          : () => setState(() => _rams.removeAt(index).dispose()),
      children: <Widget>[
        _choiceControl(
          g.choice,
          hint: 'Select an option',
          otherHint: 'Specify other RAM size',
          invalid: index == 0 && _invalid.contains('clientRamConfig'),
        ),
      ],
    );
  }

  Widget _storageRowCard(int index) {
    final r = _storage[index];
    return _rowShell(
      onRemove: index == 0 && _storage.length == 1
          ? null
          : () => setState(() {
              _storage.removeAt(index).dispose();
              if (_storage.isEmpty) _storage.add(_StorageRow());
              _rebuildStorageConfig();
            }),
      replacement: _replacementFor(
        _ReplacementTarget(
          src: 'field',
          index: index,
          serialField: 'storage_serialnum',
          componentName: <String>[
            r.typeValue,
            r.sizeValue,
          ].where((v) => v.isNotEmpty).join(' '),
        ),
      ),
      children: <Widget>[
        _dropdown(
          value: r.type,
          hint: 'Select type',
          options: _storageTypeOptions,
          labelOf: (v) => _storageTypeLabels[v] ?? v,
          onChanged: (v) => setState(() {
            r.type = v;
            _rebuildStorageConfig();
          }),
        ),
        const SizedBox(height: 8),
        _dropdown(
          value: r.size,
          hint: 'Size',
          options: <String>[..._storageSizeOptions, _otherOption],
          onChanged: (v) => setState(() {
            r.size = v;
            if (v != _otherOption) r.sizeOther.clear();
            _rebuildStorageConfig();
          }),
        ),
        if (r.size == _otherOption) ...<Widget>[
          const SizedBox(height: 8),
          TextField(
            controller: r.sizeOther,
            onChanged: (_) => setState(_rebuildStorageConfig),
            decoration: const InputDecoration(
              hintText: 'Custom size',
              isDense: true,
            ),
          ),
        ],
        const SizedBox(height: 8),
        _optionalSerial(r.serial),
      ],
    );
  }

  Widget _monitorGroupCard(int index) {
    final g = _monitors[index];
    return _rowShell(
      onRemove: index == 0
          ? null
          : () => setState(() => _monitors.removeAt(index).dispose()),
      replacement: _replacementFor(
        _ReplacementTarget(
          src: 'field',
          index: index,
          serialField: 'monitor_serialnum',
          componentName:
              <String>[
                g.size.value,
                g.brand.value,
              ].where((v) => v.isNotEmpty).join(' ').trim().isEmpty
              ? 'Monitor'
              : <String>[
                  g.size.value,
                  g.brand.value,
                ].where((v) => v.isNotEmpty).join(' '),
        ),
      ),
      children: <Widget>[
        _subLabel('Size'),
        _choiceControl(
          g.size,
          hint: 'Select a size',
          otherHint: 'Specify other size',
          labelOf: (v) => _monitorSizeLabels[v] ?? v,
          invalid: index == 0 && _invalid.contains('clientmonitorsizeConfig'),
        ),
        const SizedBox(height: 10),
        _subLabel('Brand'),
        _choiceControl(
          g.brand,
          hint: 'Select a brand',
          otherHint: 'Specify other brand',
          invalid: index == 0 && _invalid.contains('clientmonitorbrandConfig'),
        ),
        const SizedBox(height: 10),
        _subLabel('Type'),
        _choiceControl(
          g.type,
          hint: 'Select a type',
          otherHint: 'Specify other type',
        ),
        const SizedBox(height: 10),
        _subLabel('Serial Number'),
        _optionalSerial(g.serial),
      ],
    );
  }

  List<Widget> _invoiceSpecChildren() {
    if (_specRows.isEmpty) {
      return <Widget>[
        Text(
          'This invoice has no line items.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ];
    }
    final out = <Widget>[];
    String lastGroup = '';
    final groupCount = _specRows.map((r) => r.itemName).toSet().length;
    for (var i = 0; i < _specRows.length; i++) {
      final row = _specRows[i];
      if (groupCount > 1 && row.itemName != lastGroup) {
        lastGroup = row.itemName;
        out.add(
          Padding(
            padding: EdgeInsets.only(top: out.isEmpty ? 0 : 8, bottom: 8),
            child: Text(
              row.itemName,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: context.brand.signalInk),
            ),
          ),
        );
      }
      out.add(_specRowCard(i));
    }
    if (!_specLocked) {
      out.add(
        _addMoreButton('Add component', () {
          setState(() {
            final row = _SpecRow(
              itemName: _specRows.isEmpty ? 'Item' : _specRows.last.itemName,
              component: '',
              icon: Icons.category_rounded,
              optionsKey: '',
              freeSpec: true,
            )..entries.add(_SpecEntry(optionsKey: '', freeSpec: true));
            _specRows.add(row);
          });
        }),
      );
    }
    return out;
  }

  Widget _specRowCard(int index) {
    final row = _specRows[index];
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final isStorage = row.optionsKey == 'storagetype';
    final rowKeys = row.entries
        .map((e) => e.serverIndex == null ? '' : 'item:${e.serverIndex}')
        .toList();
    final hasHistory = rowKeys.any((k) => _historyFor(k).isNotEmpty);
    final displayName = row.component.text.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: b.canvas,
        borderRadius: BorderRadius.circular(Brand.radiusLg),
        border: Border.all(color: b.signal.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(row.icon, size: 18, color: b.signalInk),
              const SizedBox(width: 8),
              Expanded(
                child: _specLocked
                    ? Text(
                        displayName.isEmpty ? '—' : displayName,
                        style: text.titleSmall,
                      )
                    : TextField(
                        controller: row.component,
                        decoration: const InputDecoration(
                          hintText: 'Component name',
                          isDense: true,
                        ),
                      ),
              ),
              if (hasHistory) ...<Widget>[
                const SizedBox(width: 8),
                StatusPill(
                  label: 'Replacement',
                  icon: Icons.swap_horiz_rounded,
                  color: Brand.warning,
                ),
              ],
              if (!_specLocked)
                IconButton(
                  tooltip: 'Remove item',
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: Brand.danger,
                  ),
                  onPressed: () =>
                      setState(() => _specRows.removeAt(index).dispose()),
                ),
            ],
          ),
          for (var i = 0; i < row.entries.length; i++) ...<Widget>[
            const SizedBox(height: 10),
            _specEntry(row, i, isStorage),
            for (final r in _historyFor(rowKeys[i]))
              _historyRow(r, row.component.text.trim()),
          ],
          if (!_specLocked) ...<Widget>[
            const SizedBox(height: 8),
            _addMoreButton('Add specification', () {
              setState(() {
                row.entries.add(
                  _SpecEntry(
                    optionsKey: row.optionsKey,
                    freeSpec: row.freeSpec,
                    target: row.entries.isEmpty ? '' : row.entries.first.target,
                    raw: row.raw,
                  ),
                );
                _initSystemSerialToggle();
              });
            }),
          ],
        ],
      ),
    );
  }

  Widget _specEntry(_SpecRow row, int i, bool isStorage) {
    final e = row.entries[i];
    final removable = !_specLocked && row.entries.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _subLabel('Specification'),
        if (row.freeSpec)
          TextField(
            controller: e.freeValue,
            enabled: !_specLocked,
            decoration: const InputDecoration(
              hintText: 'Specification',
              isDense: true,
            ),
          )
        else ...<Widget>[
          _specSelect(e.option, enabled: !_specLocked),
          if (isStorage) ...<Widget>[
            const SizedBox(height: 8),
            _specSelect(e.size, enabled: !_specLocked),
          ],
        ],
        const SizedBox(height: 8),
        _subLabel('Brand Name'),
        TextField(
          controller: e.brand,
          enabled: !_specLocked,
          decoration: const InputDecoration(
            hintText: 'Brand name',
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        _subLabel('Serial Number'),
        Row(
          children: <Widget>[
            Expanded(
              child: _optionalSerial(
                e.serial,
                onChanged: () => setState(_syncInvoiceSerials),
              ),
            ),
            ?_replacementFor(
              _ReplacementTarget(
                src: 'item',
                index: e.serverIndex ?? -1,
                serialField: '',
                componentName: row.component.text.trim(),
              ),
            ),
            if (removable)
              IconButton(
                tooltip: 'Remove',
                icon: const Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: Brand.danger,
                ),
                onPressed: () => setState(() {
                  row.entries.removeAt(i).dispose();
                  _syncInvoiceSerials();
                  _initSystemSerialToggle();
                }),
              ),
          ],
        ),
        if (isStorage) ...<Widget>[
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Switch(
                value: e.sysSerial,
                onChanged: (v) => setState(() {
                  for (final r in _specRows) {
                    if (r.optionsKey != 'storagetype') continue;
                    for (final other in r.entries) {
                      other.sysSerial = false;
                    }
                  }
                  e.sysSerial = v;
                }),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Use this drive as the System Serial Number',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _historyRow(ClientSpecReplacement r, String fallbackName) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final name = r.oldComponent.trim().isEmpty
        ? fallbackName
        : r.oldComponent.trim();
    final when = _formatReplacedAt(r.replacedAt);
    final who = r.replacedByName.trim();
    final tag = <String>[
      when.isEmpty ? 'Replaced' : 'Replaced $when',
      if (who.isNotEmpty) 'by $who',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('└─', style: text.bodySmall?.copyWith(color: b.paperDim)),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(name, style: text.bodyMedium),
                Text(tag, style: text.labelSmall?.copyWith(color: b.paperDim)),
                Text(
                  r.oldSerial.trim().isEmpty
                      ? 'SN: N/A'
                      : 'SN: ${r.oldSerial.trim()}',
                  style: text.bodySmall?.copyWith(color: b.paperDim),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget? _replacementFor(_ReplacementTarget target) {
    if (_clientId == null) return null;
    if (target.src == 'item' && target.index < 0) return null;
    return IconButton(
      tooltip: 'Record a replacement',
      icon: Icon(
        Icons.swap_horiz_rounded,
        size: 18,
        color: context.brand.signalInk,
      ),
      onPressed: () => _recordReplacement(target),
    );
  }

  Widget _serialSection() {
    return _section(
      index: 3,
      title: 'Serial Numbers',
      icon: Icons.qr_code_2_rounded,
      subtitle: 'Collect SN for records',
      children: <Widget>[
        for (final f in _serialFields) ...<Widget>[
          _groupLabel(_fieldDisplayName(f), f.icon),
          Row(
            children: <Widget>[
              Expanded(child: _optionalSerial(_serials[f.formKey]!)),
              ?_replacementFor(
                _ReplacementTarget(
                  src: 'field',
                  index: 0,
                  serialField: f.column,
                  componentName: _fieldDisplayName(f),
                ),
              ),
            ],
          ),
          for (final r in _historyFor('${f.column}:0')) _historyRow(r, f.label),
          const SizedBox(height: 14),
        ],
      ],
    );
  }

  Widget _birSection() {
    return _section(
      index: 4,
      title: 'BIR Compliant System',
      icon: Icons.verified_rounded,
      subtitle: 'Fill in details for BIR compliant system',
      children: <Widget>[
        _groupLabel('System Serial Number', Icons.tag_rounded),
        _optionalSerial(
          _systemSerial,
          hint: 'System Serial Number',
          enabled: _systemSerialEnabled,
        ),
        const SizedBox(height: 14),
        _field('MAC Address (Physical Address)', _mac, hint: 'MAC Address'),
        _field(
          'Machine Identification Number (MIN)',
          _min,
          hint: 'Machine Identification Number (MIN)',
        ),
        _field('PTU', _ptu, hint: 'PTU'),
        _dateField('Date Approved', _dateApproved),
        _field('TIN', _tin, hint: 'TIN'),
        _field(
          'Registered Address (As per 2303)',
          _registeredAddress,
          hint: 'Registered Address',
          maxLines: 2,
        ),
        _vatSelector(),
      ],
    );
  }

  Widget _section({
    required int index,
    required String title,
    required IconData icon,
    required List<Widget> children,
    String? subtitle,
    Widget? action,
  }) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _Entry(
        index: index,
        child: AppCard(
          radius: Brand.radiusLg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  _SectionGlyph(icon: icon),
                  const SizedBox(width: 10),
                  Expanded(child: Text(title, style: text.titleMedium)),
                  ?action,
                ],
              ),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: 10),
                Text(subtitle, style: text.bodySmall),
              ],
              const SizedBox(height: 16),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionAction(String label, IconData icon, VoidCallback? onTap) {
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
  }

  Widget _label(String label, {bool required = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text.rich(
      TextSpan(
        text: label,
        children: <InlineSpan>[
          if (required)
            const TextSpan(
              text: ' *',
              style: TextStyle(color: Brand.danger),
            ),
        ],
      ),
      style: Theme.of(context).textTheme.labelLarge,
    ),
  );

  Widget _subLabel(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.labelSmall?.copyWith(color: context.brand.paperDim),
    ),
  );

  Widget _groupLabel(String label, IconData icon, {bool required = false}) {
    final b = context.brand;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 16, color: b.signalInk),
          const SizedBox(width: 8),
          Flexible(child: _label(label, required: required)),
        ],
      ),
    );
  }

  Widget _staticRow(String label, String value) =>
      StationDataRow(label: label, value: value.trim().isEmpty ? '—' : value);

  Widget _field(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
    String? hint,
    String? fieldKey,
    bool required = false,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    final invalid = fieldKey != null && _invalid.contains(fieldKey);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _label(label, required: required),
          TextField(
            controller: controller,
            maxLines: maxLines,
            textCapitalization: textCapitalization,
            onChanged: fieldKey == null || !invalid
                ? null
                : (_) => setState(() => _invalid.remove(fieldKey)),
            decoration: InputDecoration(
              hintText: hint,
              enabledBorder: invalid ? _invalidBorder() : null,
            ),
          ),
        ],
      ),
    );
  }

  OutlineInputBorder _invalidBorder() => OutlineInputBorder(
    borderRadius: BorderRadius.circular(Brand.radius),
    borderSide: const BorderSide(color: Brand.danger),
  );

  Widget _dateField(
    String label,
    TextEditingController controller, {
    String? fieldKey,
    bool required = false,
  }) {
    final invalid = fieldKey != null && _invalid.contains(fieldKey);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _label(label, required: required),
          TextField(
            controller: controller,
            readOnly: true,
            onTap: () async {
              await _pickDate(controller);
              if (fieldKey != null && mounted) {
                setState(() => _invalid.remove(fieldKey));
              }
            },
            decoration: InputDecoration(
              hintText: 'YYYY-MM-DD',
              enabledBorder: invalid ? _invalidBorder() : null,
              prefixIcon: Icon(
                Icons.calendar_today_rounded,
                size: 18,
                color: context.brand.paperDim,
              ),
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear date',
                      icon: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: context.brand.paperDim,
                      ),
                      onPressed: () => setState(() => controller.clear()),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdown({
    required String? value,
    required String hint,
    required List<String> options,
    required ValueChanged<String?> onChanged,
    String Function(String)? labelOf,
    bool enabled = true,
    bool invalid = false,
  }) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    return InputDecorator(
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        enabledBorder: invalid ? _invalidBorder() : null,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: options.contains(value) ? value : null,
          isExpanded: true,
          isDense: true,
          dropdownColor: b.surface,
          borderRadius: BorderRadius.circular(Brand.radius),
          icon: Icon(Icons.expand_more_rounded, color: b.paperDim),
          hint: Text(hint, style: text.bodyMedium?.copyWith(color: b.paperDim)),
          items: <DropdownMenuItem<String>>[
            for (final o in options)
              DropdownMenuItem<String>(
                value: o,
                child: Text(
                  labelOf == null ? o : labelOf(o),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: enabled ? onChanged : null,
        ),
      ),
    );
  }

  Widget _choiceControl(
    _Choice choice, {
    required String hint,
    required String otherHint,
    String Function(String)? labelOf,
    bool invalid = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _dropdown(
          value: choice.selected,
          hint: hint,
          invalid: invalid,
          options: <String>[...choice.options, _otherOption],
          labelOf: labelOf,
          onChanged: (v) => setState(() {
            choice.selected = v;
            if (v != _otherOption) choice.other.clear();
          }),
        ),
        if (choice.selected == _otherOption) ...<Widget>[
          const SizedBox(height: 8),
          TextField(
            controller: choice.other,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(hintText: otherHint, isDense: true),
          ),
        ],
      ],
    );
  }

  Widget _specSelect(_SpecSelect select, {bool enabled = true}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _dropdown(
          value: select.selected,
          hint: 'Select…',
          enabled: enabled,
          options: select.options,
          onChanged: (v) => setState(() {
            select.selected = v;
            if (v != _specOther) select.other.clear();
          }),
        ),
        if (select.selected == _specOther) ...<Widget>[
          const SizedBox(height: 8),
          TextField(
            controller: select.other,
            enabled: enabled,
            decoration: const InputDecoration(
              hintText: 'Enter value',
              isDense: true,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _scanInto(
    TextEditingController controller, {
    VoidCallback? onChanged,
  }) async {
    final code = await scanSerialCode(context);
    if (code == null || !mounted) return;
    setState(() {
      controller.text = code;
      _revealed.add(controller);
      onChanged?.call();
    });
  }

  Widget _scanButton(
    TextEditingController controller, {
    VoidCallback? onChanged,
    bool enabled = true,
  }) {
    return IconButton(
      tooltip: 'Scan serial number',
      onPressed: enabled
          ? () => _scanInto(controller, onChanged: onChanged)
          : null,
      icon: Icon(
        Icons.qr_code_scanner_rounded,
        size: 20,
        color: enabled ? context.brand.signal : context.brand.paperDim,
      ),
    );
  }

  Widget _optionalSerial(
    TextEditingController controller, {
    String hint = 'Serial number',
    bool enabled = true,
    VoidCallback? onChanged,
  }) {
    final value = controller.text.trim();
    final hasValue = value.isNotEmpty && value != _snDefault;
    if (!hasValue && !_revealed.contains(controller)) {
      return Row(
        children: <Widget>[
          TextButton.icon(
            onPressed: enabled
                ? () => setState(() {
                    controller.text = '';
                    _revealed.add(controller);
                    onChanged?.call();
                  })
                : null,
            style: TextButton.styleFrom(
              minimumSize: const Size(44, 44),
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Add serial number'),
          ),
          _scanButton(controller, onChanged: onChanged, enabled: enabled),
        ],
      );
    }
    return TextField(
      controller: controller,
      enabled: enabled,
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        suffixIcon: _scanButton(
          controller,
          onChanged: onChanged,
          enabled: enabled,
        ),
      ),
      onChanged: (_) {
        onChanged?.call();
      },
    );
  }

  Widget _rowShell({
    required List<Widget> children,
    VoidCallback? onRemove,
    Widget? replacement,
  }) {
    final b = context.brand;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: b.canvas,
        borderRadius: BorderRadius.circular(Brand.radiusLg),
        border: Border.all(color: b.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (onRemove != null || replacement != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                ?replacement,
                if (onRemove != null)
                  IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: Brand.danger,
                    ),
                    onPressed: onRemove,
                  ),
              ],
            ),
          ...children,
        ],
      ),
    );
  }

  Widget _addMoreButton(String label, VoidCallback onTap) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      icon: const Icon(Icons.add_rounded, size: 16),
      label: Text(label),
    ),
  );

  Widget _vatSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _label('VAT status'),
        ChoicePills<bool>(
          options: const <bool>[true, false],
          value: _isVat,
          onChanged: (v) => setState(() => _isVat = v),
          labelOf: (v) => v ? 'VAT' : 'Non-VAT',
        ),
      ],
    );
  }

  Widget _uploadBox(String label, IconData icon, VoidCallback? onTap) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final enabled = onTap != null;
    final c = enabled ? b.signalInk : b.paperDim;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Brand.radiusLg),
        color: enabled
            ? b.signal.withValues(alpha: b.isDark ? 0.18 : 0.12)
            : b.surfaceHi,
        border: Border.all(
          color: enabled ? b.signal.withValues(alpha: 0.4) : b.rule,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(Brand.radiusLg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(icon, size: 20, color: c),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: text.labelLarge?.copyWith(
                    color: c,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _pick(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && v.toString().trim().isNotEmpty) {
        return v.toString().trim();
      }
    }
    return '';
  }
}

String _trimNumber(String raw) {
  final v = double.tryParse(raw);
  if (v == null) return raw;
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toString();
}

String _formatReplacedAt(String raw) {
  final normalized = raw.trim().replaceFirst(' ', 'T');
  if (normalized.isEmpty) return '';
  final parsed = DateTime.tryParse(normalized);
  if (parsed == null) return '';
  return '${_monthNames[parsed.month - 1]} ${parsed.day}, ${parsed.year}';
}

List<String> _splitCsv(String value) =>
    value.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

List<String> _splitCsvKeepEmpty(String value) {
  if (value.trim().isEmpty) return const <String>[];
  return value.split(',').map((s) => s.trim()).toList();
}

List<String> _parseComponentLines(String text) {
  if (text.isEmpty) return const <String>[];
  return text
      .split(RegExp(r'\r?\n|•|;'))
      .map(
        (l) => l
            .replaceFirst(RegExp(r'^[\s\-*▪◦·]+'), '')
            .replaceFirst(RegExp(r'\s*[×xX]\s*\d+(\.\d+)?\s*$'), '')
            .trim(),
      )
      .where((l) => l.isNotEmpty)
      .toList();
}

String _pickField(Map<String, dynamic> m, List<String> keys) {
  for (final k in keys) {
    final v = m[k];
    if (v != null && v.toString().trim().isNotEmpty) {
      return v.toString().trim();
    }
  }
  return '';
}

String _invoiceNumberOf(Map<String, dynamic> item) => _pickField(item, <String>[
  'invoice_number',
  'invoiceNumber',
  'invoice_no',
  'invoiceNo',
  'number',
  'invoice',
]);

String _invoiceBranchOf(Map<String, dynamic> item) {
  for (final k in <String>[
    'branch_name',
    'branch_code',
    'branchName',
    'branch',
  ]) {
    final v = item[k];
    if (v == null) continue;
    if (v is Map) {
      final nested = _pickField(Map<String, dynamic>.from(v), <String>[
        'name',
        'branch_name',
        'code',
      ]);
      if (nested.isNotEmpty) return nested;
      continue;
    }
    if (v.toString().trim().isNotEmpty) return v.toString().trim();
  }
  return '';
}

String _invoiceNameOf(Map<String, dynamic> item) {
  final customer = item['customer'] is Map
      ? Map<String, dynamic>.from(item['customer'])
      : item;
  final name = _pickField(customer, <String>[
    'display_name',
    'name',
    'company_name',
    'customerName',
    'email',
  ]);
  if (name.isNotEmpty) return name;
  return _pickField(item, <String>['name', 'customer_name']);
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
    } else if (RegExp(
      r'\bhdd\b|hard\s*disk',
      caseSensitive: false,
    ).hasMatch(s)) {
      type = 'Hard Disk Drive';
    } else if (RegExp(r'\be?mmc\b', caseSensitive: false).hasMatch(s)) {
      type = 'MMC';
    }
    if (type.isEmpty) continue;
    pairs.add(type);
    final m = RegExp(
      r'(\d+(?:\.\d+)?)\s*(GB|TB)',
      caseSensitive: false,
    ).firstMatch(s);
    if (m != null) pairs.add('${m.group(1)}${m.group(2)!.toUpperCase()}');
  }
  return pairs.join(', ');
}

String _matchMonitorSize(List<String> c) {
  for (final s in c) {
    final m = RegExp(
      r'(\d+(?:\.\d+)?)\s*(?:inch|inches|")',
      caseSensitive: false,
    ).firstMatch(s);
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

String _matchMonitorBrand(List<String> c) {
  for (final s in c) {
    if (!RegExp(r'monitor|display|screen', caseSensitive: false).hasMatch(s)) {
      continue;
    }
    for (final b in _monitorBrandOptions) {
      if (RegExp(
        b.replaceAll('-', '[- ]?'),
        caseSensitive: false,
      ).hasMatch(s)) {
        return b;
      }
    }
  }
  return '';
}

String _detectBrand(String text, String brandsKey) {
  for (final b in _specBrands[brandsKey] ?? const <String>[]) {
    if (RegExp(
      '\\b${b.replaceAll('-', '[-\\s]?')}',
      caseSensitive: false,
    ).hasMatch(text)) {
      return b;
    }
  }
  return '';
}

class _SpecMeta {
  _SpecMeta({
    required this.name,
    required this.icon,
    required this.target,
    required this.optionsKey,
    required this.defaultOption,
    required this.defaultSize,
    required this.defaultBrand,
  });

  final String name;
  final IconData icon;
  final String target;
  final String optionsKey;
  final String defaultOption;
  final String defaultSize;
  final String defaultBrand;
}

({String formKey, IconData icon})? _componentSerialField(String label) {
  bool m(String p) => RegExp(p, caseSensitive: false).hasMatch(label);
  if (m(r'thermal\s*printer')) {
    return (
      formKey: 'clientthermalprinterSerialNumber',
      icon: Icons.print_rounded,
    );
  }
  if (m(r'barcode\s*printer')) {
    return (
      formKey: 'clientBarcodePrinterSerialNumber',
      icon: Icons.local_printshop_rounded,
    );
  }
  if (m(r'barcode\s*scanner|\bscanner\b')) {
    return (
      formKey: 'clientbarcodescannerSerialNumber',
      icon: Icons.qr_code_scanner_rounded,
    );
  }
  if (m(r'cash\s*drawer')) {
    return (
      formKey: 'clientCashDrawerSerialNumber',
      icon: Icons.point_of_sale_rounded,
    );
  }
  if (m(r'customer\s*display|pole')) {
    return (
      formKey: 'clientcusdisplaySerialNumber',
      icon: Icons.desktop_windows_rounded,
    );
  }
  if (m(r'motherboard|mainboard')) {
    return (
      formKey: 'clientMotherboardSerialNumber',
      icon: Icons.memory_rounded,
    );
  }
  if (m(r'keyboard')) {
    return (
      formKey: 'clientKeyboardSerialNumber',
      icon: Icons.keyboard_rounded,
    );
  }
  if (m(r'mouse')) {
    return (formKey: 'clientMouseSerialNumber', icon: Icons.mouse_rounded);
  }
  if (m(r'monitor|display|screen')) {
    return (formKey: 'clientMonitorSerialNumber', icon: Icons.tv_rounded);
  }
  if (m(r'\bssd\b|solid\s*state|\bhdd\b|hard\s*disk|\be?mmc\b|storage')) {
    return (formKey: 'clientStorageSerialNumber', icon: Icons.storage_rounded);
  }
  if (m(
    r'all\s*-?\s*in\s*-?\s*one|branded\s*cpu|generic\s*cpu|\bcpu\b|system\s*unit',
  )) {
    return (formKey: 'clientSystemUnitSerialNumber', icon: Icons.dns_rounded);
  }
  return null;
}

_SpecMeta _normalizeSpec(String label) {
  final c = label;
  final field = _componentSerialField(c);
  String name = c;
  IconData icon = field?.icon ?? Icons.category_rounded;
  final target = field?.formKey ?? '';
  String optionsKey = '';
  String defaultOption = '';
  String defaultSize = '';
  String defaultBrand = '';
  bool m(String p) => RegExp(p, caseSensitive: false).hasMatch(c);
  RegExpMatch? match(String p) => RegExp(p, caseSensitive: false).firstMatch(c);

  if (m(r'monitor|display|screen')) {
    name = 'Monitor';
    optionsKey = 'monitor';
    final s = match(r'(\d+(?:\.\d+)?)\s*(?:in\b|inch|inches|")');
    if (s != null) defaultOption = '${s.group(1)} Inches';
    defaultBrand = _detectBrand(c, 'monitor');
  } else if (m(r'\bram\b|memory')) {
    name = 'RAM';
    optionsKey = 'ram';
    final s = match(r'(\d+)\s*GB');
    if (s != null) defaultOption = '${s.group(1)}GB';
  } else if (m(
    r'\bssd\b|solid\s*state|\bhdd\b|hard\s*disk|\bnvme\b|\bm\.?2\b|\be?mmc\b|storage',
  )) {
    name = 'Storage';
    icon = Icons.storage_rounded;
    optionsKey = 'storagetype';
    if (m(r'\bnvme\b')) {
      defaultOption = 'NVMe';
    } else if (m(r'\bm\.?2\b')) {
      defaultOption = 'M.2';
    } else if (m(r'\bssd\b|solid\s*state')) {
      defaultOption = 'SSD';
    } else if (m(r'\be?mmc\b')) {
      defaultOption = 'eMMC';
    } else if (m(r'\bhdd\b|hard\s*disk')) {
      defaultOption = 'HDD';
    }
    final s = match(r'(\d+(?:\.\d+)?)\s*(GB|TB)');
    if (s != null) defaultSize = '${s.group(1)}${s.group(2)!.toUpperCase()}';
  } else if (m(r'receipt\s*printer')) {
    name = 'Receipt Printer';
    icon = Icons.print_rounded;
    optionsKey = 'printer';
    final s = match(r'(\d+)\s*mm');
    if (s != null) defaultOption = '${s.group(1)}mm';
  } else if (m(r'thermal\s*printer')) {
    name = 'Thermal Printer';
    optionsKey = 'printer';
    final s = match(r'(\d+)\s*mm');
    if (s != null) defaultOption = '${s.group(1)}mm';
  } else if (m(r'processor|\bcpu\b|system\s*unit|all\s*-?\s*in\s*-?\s*one')) {
    name = 'Processor';
    icon = Icons.memory_rounded;
    optionsKey = 'processor';
    final s = match(r'(\d+(?:\.\d+)?)\s*(MHz|GHz)');
    if (s != null) {
      final unit = RegExp(r'ghz', caseSensitive: false).hasMatch(s.group(2)!)
          ? 'GHz'
          : 'MHz';
      defaultOption = '${s.group(1)} $unit';
    }
    defaultBrand = _detectBrand(c, 'processor');
  } else if (m(r'cash\s*drawer')) {
    name = 'Cash Drawer';
    optionsKey = 'cashdrawer';
    final s = match(r'(\d+(?:\s*/\s*\d+)?)\s*bills?');
    if (s != null) {
      defaultOption = '${s.group(1)!.replaceAll(RegExp(r'\s+'), '')} Bills';
    }
  } else if (m(r'barcode\s*scanner|\bscanner\b')) {
    name = 'Barcode Scanner';
    optionsKey = 'barcode';
    final s = match(r'\b(1d(?:\s*[/&]\s*2d)?|2d)\b');
    if (s != null) {
      defaultOption = s.group(1)!.toUpperCase().replaceAll(RegExp(r'\s+'), '');
    }
  } else if (m(r'barcode\s*printer')) {
    name = 'Barcode Printer';
  } else if (m(r'motherboard|mainboard')) {
    name = 'Motherboard';
  } else if (m(r'keyboard')) {
    name = 'Keyboard';
  } else if (m(r'mouse\s*pad|mousepad')) {
    name = 'Mouse Pad';
  } else if (m(r'mouse')) {
    name = 'Mouse';
  } else if (m(r'customer\s*display|pole')) {
    name = 'Customer Display';
  }
  if (optionsKey.isEmpty && defaultOption.isEmpty) defaultOption = _specNa;
  return _SpecMeta(
    name: name,
    icon: icon,
    target: target,
    optionsKey: optionsKey,
    defaultOption: defaultOption,
    defaultSize: defaultSize,
    defaultBrand: defaultBrand,
  );
}

class _ReplacementTarget {
  const _ReplacementTarget({
    required this.src,
    required this.index,
    required this.serialField,
    required this.componentName,
  });

  final String src;
  final int index;
  final String serialField;
  final String componentName;
}

class _Choice {
  _Choice(this.options);

  final List<String> options;
  String? selected;
  final TextEditingController other = TextEditingController();

  void init(String value) {
    if (value.isEmpty) {
      selected = null;
      other.clear();
    } else if (options.contains(value)) {
      selected = value;
      other.clear();
    } else {
      selected = _otherOption;
      other.text = value;
    }
  }

  String get value =>
      selected == _otherOption ? other.text.trim() : (selected ?? '');

  void dispose() => other.dispose();
}

class _SpecSelect {
  _SpecSelect(this.optionsKey, String initial) {
    set(initial);
  }

  final String optionsKey;
  String? selected;
  String custom = '';
  final TextEditingController other = TextEditingController();

  List<String> get options => <String>[
    if (custom.isNotEmpty) custom,
    ...(_specOptions[optionsKey] ?? const <String>[]),
    _specNa,
    _specOther,
  ];

  void set(String value) {
    final v = value.trim();
    if (v.isEmpty) {
      selected = null;
      custom = '';
      other.clear();
      return;
    }
    if (v == _specOther) {
      selected = _specOther;
      return;
    }
    final list = _specOptions[optionsKey] ?? const <String>[];
    if (list.contains(v) || v == _specNa) {
      selected = v;
      custom = '';
      return;
    }
    custom = v;
    selected = v;
  }

  String get value =>
      selected == _specOther ? other.text.trim() : (selected ?? '');

  void dispose() => other.dispose();
}

class _UnitGroup {
  String? selected;
  final TextEditingController brand = TextEditingController();
  final TextEditingController serial = TextEditingController();

  void setValue(String value) {
    final v = value.trim();
    if (RegExp(r'^branded cpu', caseSensitive: false).hasMatch(v)) {
      selected = 'Branded CPU';
      brand.text = v.replaceFirst(
        RegExp(r'^branded cpu\s*-?\s*', caseSensitive: false),
        '',
      );
      return;
    }
    selected = v.isEmpty ? null : v;
    brand.clear();
  }

  String get value {
    final v = selected ?? '';
    if (RegExp(r'^branded cpu', caseSensitive: false).hasMatch(v)) {
      final b = brand.text.trim();
      return b.isEmpty ? 'Branded CPU' : 'Branded CPU - $b';
    }
    return v;
  }

  void dispose() {
    brand.dispose();
    serial.dispose();
  }
}

class _RamGroup {
  final _Choice choice = _Choice(_ramOptions);

  void dispose() => choice.dispose();
}

class _StorageRow {
  String? type;
  String? size;
  final TextEditingController sizeOther = TextEditingController();
  final TextEditingController serial = TextEditingController();

  void setType(String value) => type = value.isEmpty ? null : value;

  void setSize(String value) {
    final v = value.trim();
    if (v.isEmpty) {
      size = null;
      sizeOther.clear();
      return;
    }
    if (_storageSizeOptions.contains(v)) {
      size = v;
      sizeOther.clear();
      return;
    }
    size = _otherOption;
    sizeOther.text = v;
  }

  String get typeValue => type ?? '';

  String get sizeValue =>
      size == _otherOption ? sizeOther.text.trim() : (size ?? '');

  void dispose() {
    sizeOther.dispose();
    serial.dispose();
  }
}

class _MonitorGroup {
  final _Choice size = _Choice(_monitorSizeOptions);
  final _Choice brand = _Choice(_monitorBrandOptions);
  final _Choice type = _Choice(_monitorTypeOptions);
  final TextEditingController serial = TextEditingController();

  void dispose() {
    size.dispose();
    brand.dispose();
    type.dispose();
    serial.dispose();
  }
}

class _SpecEntry {
  _SpecEntry({
    required this.optionsKey,
    required this.freeSpec,
    String option = '',
    String size = '',
    String brand = '',
    String serial = '',
    this.target = '',
    this.raw = '',
    this.serverIndex,
  }) : option = _SpecSelect(optionsKey, freeSpec ? '' : option),
       size = _SpecSelect('storage', size),
       freeValue = TextEditingController(text: freeSpec ? option : ''),
       brand = TextEditingController(text: brand),
       serial = TextEditingController(text: serial);

  final String optionsKey;
  final bool freeSpec;
  final _SpecSelect option;
  final _SpecSelect size;
  final TextEditingController freeValue;
  final TextEditingController brand;
  final TextEditingController serial;
  final String target;
  final String raw;
  final int? serverIndex;
  bool sysSerial = false;

  void dispose() {
    option.dispose();
    size.dispose();
    freeValue.dispose();
    brand.dispose();
    serial.dispose();
  }
}

class _SpecRow {
  _SpecRow({
    required this.itemName,
    required String component,
    required this.icon,
    required this.optionsKey,
    required this.freeSpec,
  }) : component = TextEditingController(text: component);

  final String itemName;
  final TextEditingController component;
  final IconData icon;
  final String optionsKey;
  final bool freeSpec;
  final List<_SpecEntry> entries = <_SpecEntry>[];

  String get raw => entries.isEmpty || entries.first.raw.isEmpty
      ? component.text.trim()
      : entries.first.raw;

  void dispose() {
    component.dispose();
    for (final e in entries) {
      e.dispose();
    }
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
      child: Icon(icon, size: 17, color: b.signalInk),
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

class _ReplacementDialog extends StatefulWidget {
  const _ReplacementDialog({required this.componentName});

  final String componentName;

  @override
  State<_ReplacementDialog> createState() => _ReplacementDialogState();
}

class _ReplacementDialogState extends State<_ReplacementDialog> {
  late final TextEditingController _component = TextEditingController(
    text: widget.componentName,
  );
  final TextEditingController _serial = TextEditingController();

  @override
  void dispose() {
    _component.dispose();
    _serial.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      icon: const IconTile(
        icon: Icons.swap_horiz_rounded,
        size: 44,
        iconSize: 22,
      ),
      title: Text(
        'Replacement for ${widget.componentName.isEmpty ? 'component' : widget.componentName}',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('Component', style: text.labelLarge),
          const SizedBox(height: 6),
          TextField(
            controller: _component,
            decoration: const InputDecoration(hintText: 'New component'),
          ),
          const SizedBox(height: 14),
          Text('Serial Number', style: text.labelLarge),
          const SizedBox(height: 6),
          TextField(
            controller: _serial,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'New serial number',
              suffixIcon: IconButton(
                tooltip: 'Scan serial number',
                icon: Icon(
                  Icons.qr_code_scanner_rounded,
                  size: 20,
                  color: context.brand.signal,
                ),
                onPressed: () async {
                  final code = await scanSerialCode(context);
                  if (code == null || !mounted) return;
                  setState(() => _serial.text = code);
                },
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'The current entry is kept as history under this component.',
            style: text.bodySmall,
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(
            context,
          ).pop((component: _component.text, serial: _serial.text)),
          icon: const Icon(Icons.check_rounded, size: 18),
          label: const Text('Save replacement'),
        ),
      ],
    );
  }
}

class _InvoicePickDialog extends StatefulWidget {
  const _InvoicePickDialog({required this.service});

  final ClientService service;

  @override
  State<_InvoicePickDialog> createState() => _InvoicePickDialogState();
}

class _InvoicePickDialogState extends State<_InvoicePickDialog> {
  final _controller = TextEditingController();
  Timer? _debounce;
  bool _searching = false;
  String _message = '';
  List<Map<String, dynamic>> _results = const <Map<String, dynamic>>[];
  final Map<String, List<Map<String, dynamic>>> _cache =
      <String, List<Map<String, dynamic>>>{};

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    final term = value.trim();
    _debounce?.cancel();
    if (term.isEmpty) {
      setState(() {
        _results = const <Map<String, dynamic>>[];
        _message = '';
      });
      return;
    }
    final cached = _cache[term];
    if (cached != null) {
      setState(() {
        _results = cached;
        _message = cached.isEmpty ? 'No matching invoice found.' : '';
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () => _search(term));
  }

  Future<void> _search(String term) async {
    if (term.isEmpty) return;
    setState(() {
      _searching = true;
      _message = '';
    });
    final res = await widget.service.searchInvoice(term);
    if (!mounted) return;
    setState(() {
      _searching = false;
      _results = res.rows;
      if (res.error.isNotEmpty) {
        _message = res.error;
      } else {
        _cache[term] = res.rows;
        _message = res.rows.isEmpty ? 'No matching invoice found.' : '';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const IconTile(icon: Icons.receipt_long_rounded, size: 40),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Find invoice', style: text.titleLarge)),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: b.paperDim,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Search invoice number to auto-fill',
                style: text.labelLarge,
              ),
              const SizedBox(height: 6),
              AppSearchField(
                controller: _controller,
                hint: 'Type an invoice number, e.g. INV-00123…',
                onChanged: _onChanged,
                onSubmitted: (v) => _search(v.trim()),
              ),
              if (_searching) ...<Widget>[
                const SizedBox(height: 16),
                const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ],
              if (_message.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  _message,
                  style: text.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
              if (_results.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _results.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final item = _results[i];
                      final no = _invoiceNumberOf(item);
                      final branch = _invoiceBranchOf(item);
                      final name = _invoiceNameOf(item);
                      return AppCard(
                        radius: Brand.radiusLg,
                        onTap: () => Navigator.of(context).pop(item),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: <Widget>[
                            const IconTile(
                              icon: Icons.description_rounded,
                              size: 34,
                              iconSize: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Row(
                                    children: <Widget>[
                                      Flexible(
                                        child: Text(
                                          no.isEmpty ? '—' : no,
                                          style: text.titleSmall,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (branch.isNotEmpty) ...<Widget>[
                                        const SizedBox(width: 8),
                                        StatusPill(
                                          label: branch,
                                          icon: Icons.account_tree_rounded,
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (name.isNotEmpty) ...<Widget>[
                                    const SizedBox(height: 2),
                                    Text(
                                      name,
                                      style: text.bodySmall,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 20,
                              color: b.paperDim,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
