part of 'client_screen.dart';

const Color _cdvText = Color(0xFF1F2937);
const Color _cdvMuted = Color(0xFF9CA3AF);
const Color _cdvSub = Color(0xFF4B5563);

class _CdvRow {
  _CdvRow({
    required this.name,
    required this.serial,
    required this.icon,
    required this.src,
    this.field = '',
    required this.idx,
  });

  String name;
  final String serial;
  final IconData icon;
  final String src;
  final String field;
  final int idx;

  String get rowKey => src == 'item' ? 'item:$idx' : '$field:$idx';
  bool get nameWritable =>
      src == 'item' || field == 'system_unit_serialnum';
}

String _cdvVal(String? v) {
  final s = (v ?? '').trim();
  return (s.isEmpty || s.toUpperCase() == 'N/A') ? '' : s;
}

List<String> _cdvCsv(String? v) =>
    (v ?? '').split(',').map((s) => s.trim()).toList();

IconData? _cdvComponentIcon(String label) {
  final c = label.toLowerCase();
  bool has(String p) => RegExp(p, caseSensitive: false).hasMatch(c);
  if (has(r'thermal\s*printer')) return Icons.print_rounded;
  if (has(r'barcode\s*printer')) return Icons.print_rounded;
  if (has(r'barcode\s*scanner|\bscanner\b')) return Icons.qr_code_scanner_rounded;
  if (has(r'cash\s*drawer')) return Icons.point_of_sale_rounded;
  if (has(r'customer\s*display|pole')) return Icons.desktop_windows_outlined;
  if (has(r'motherboard|mainboard')) return Icons.developer_board_rounded;
  if (has(r'keyboard')) return Icons.keyboard_rounded;
  if (has(r'mouse')) return Icons.mouse_rounded;
  if (has(r'monitor|display|screen')) return Icons.tv_rounded;
  if (has(r'\bssd\b|solid\s*state|\bhdd\b|hard\s*disk|\be?mmc\b|storage')) {
    return Icons.storage_rounded;
  }
  if (has(r'all\s*-?\s*in\s*-?\s*one|branded\s*cpu|generic\s*cpu|\bcpu\b|system\s*unit')) {
    return Icons.dns_rounded;
  }
  return null;
}

Map<String, String> _cdvDataOf(ClientDetail d) => <String, String>{
      'name': d.name,
      'invoice_number': d.invoiceNumber,
      'branch': d.branch,
      'date_prepared': d.datePrepared,
      'system_unit': d.systemUnit,
      'system_unit_serialnum': d.systemUnitSerial,
      'ram_config': d.ramConfig,
      'motherboard_serialnum': d.motherboardSerial,
      'storage_config': d.storageConfig,
      'storage_serialnum': d.storageSerial,
      'monitorsize_config': d.monitorSize,
      'monitorbrand_config': d.monitorBrand,
      'monitorType_config': d.monitorType,
      'monitor_serialnum': d.monitorSerial,
      'keyboard_serialnum': d.keyboardSerial,
      'mouse_serialnum': d.mouseSerial,
      'barcodeScanner_serialnum': d.barcodeScannerSerial,
      'thermalPrinter_serialnum': d.thermalPrinterSerial,
      'cashDrawer_serialnum': d.cashDrawerSerial,
      'barcodePrinter_serialnum': d.barcodePrinterSerial,
      'cusdisplay_serialnum': d.cusDisplaySerial,
      'system_serialnum': d.systemSerial,
      'mac_address': d.macAddress,
      'min': d.min,
      'ptu': d.ptu,
      'date_approved': d.dateApproved,
      'tin': d.tin,
      'registered_address': d.registeredAddress,
    };

void _cdvPushRows(
  List<_CdvRow> rows,
  List<({String? csv, String label})> parts,
  String? serialCsv,
  IconData icon,
  String field,
) {
  final serials = _cdvCsv(serialCsv);
  final lists = parts.map((p) => p.csv != null ? _cdvCsv(p.csv) : null).toList();
  var count = serials.length;
  for (final l in lists) {
    if (l != null && l.length > count) count = l.length;
  }
  if (count < 1) count = 1;
  for (var i = 0; i < count; i++) {
    final name = <String>[
      for (var j = 0; j < parts.length; j++)
        lists[j] != null
            ? _cdvVal(i < lists[j]!.length ? lists[j]![i] : '')
            : parts[j].label,
    ].where((s) => s.isNotEmpty).join(' ');
    final serial = _cdvVal(i < serials.length ? serials[i] : '');
    if (name.isEmpty && serial.isEmpty) continue;
    rows.add(_CdvRow(
        name: name, serial: serial, icon: icon, src: 'field', field: field, idx: i));
  }
}

List<_CdvRow> _cdvBuildSpec(
    Map<String, String> d, List<ClientInvoiceItem> items) {
  final rows = <_CdvRow>[];
  for (var idx = 0; idx < items.length; idx++) {
    final name = items[idx].component.trim();
    if (name.isEmpty) continue;
    rows.add(_CdvRow(
      name: name,
      serial: _cdvVal(items[idx].serialNumber),
      icon: _cdvComponentIcon(name) ?? Icons.inventory_2_rounded,
      src: 'item',
      idx: idx,
    ));
  }
  if (rows.isNotEmpty) return rows;
  ({String? csv, String label}) csv(String? v) => (csv: v ?? '', label: '');
  ({String? csv, String label}) lbl(String v) => (csv: null, label: v);
  _cdvPushRows(rows, [csv(d['monitorsize_config']), csv(d['monitorbrand_config']), lbl('Monitor')],
      d['monitor_serialnum'], Icons.tv_rounded, 'monitor_serialnum');
  _cdvPushRows(rows, [csv(d['system_unit'])], d['system_unit_serialnum'],
      Icons.dns_rounded, 'system_unit_serialnum');
  final parts = _cdvCsv(d['storage_config']);
  final sSerials = _cdvCsv(d['storage_serialnum']);
  final ram = _cdvVal(d['ram_config']).isEmpty ? '' : '${_cdvVal(d['ram_config'])} RAM';
  var count = (parts.length / 2).ceil();
  if (sSerials.length > count) count = sSerials.length;
  if (ram.isNotEmpty && count < 1) count = 1;
  for (var i = 0; i < count; i++) {
    String at(List<String> l, int k) => k < l.length ? _cdvVal(l[k]) : '';
    final drive = <String>[at(parts, i * 2), at(parts, i * 2 + 1)]
        .where((s) => s.isNotEmpty)
        .join(' ');
    final name = <String>[i == 0 ? ram : '', drive]
        .where((s) => s.isNotEmpty)
        .join(' / ');
    final serial = at(sSerials, i);
    if (name.isEmpty && serial.isEmpty) continue;
    rows.add(_CdvRow(
        name: name,
        serial: serial,
        icon: Icons.memory_rounded,
        src: 'field',
        field: 'storage_serialnum',
        idx: i));
  }
  const simple = <(String, String, IconData)>[
    ('Motherboard', 'motherboard_serialnum', Icons.developer_board_rounded),
    ('Keyboard', 'keyboard_serialnum', Icons.keyboard_rounded),
    ('Mouse', 'mouse_serialnum', Icons.mouse_rounded),
    ('Barcode Scanner', 'barcodeScanner_serialnum', Icons.qr_code_scanner_rounded),
    ('Thermal Printer', 'thermalPrinter_serialnum', Icons.print_rounded),
    ('Cash Drawer', 'cashDrawer_serialnum', Icons.point_of_sale_rounded),
    ('Barcode Printer', 'barcodePrinter_serialnum', Icons.print_rounded),
    ('Customer Display', 'cusdisplay_serialnum', Icons.desktop_windows_outlined),
  ];
  for (final s in simple) {
    _cdvPushRows(rows, [lbl(s.$1)], d[s.$2], s.$3, s.$2);
  }
  return rows;
}

const List<(String, String, bool)> _cdvBirFields = <(String, String, bool)>[
  ('System Serial Number', 'system_serialnum', false),
  ('MAC Address (Physical Address)', 'mac_address', false),
  ('Machine Identification Number (MIN)', 'min', false),
  ('PTU', 'ptu', false),
  ('Date Approved', 'date_approved', true),
  ('TIN', 'tin', false),
  ('Registered Address (As per 2303)', 'registered_address', false),
];

class _ClientDetailModal extends StatefulWidget {
  const _ClientDetailModal({
    required this.service,
    required this.brief,
  });

  final ClientService service;
  final ClientBrief brief;

  @override
  State<_ClientDetailModal> createState() => _ClientDetailModalState();
}

class _ClientDetailModalState extends State<_ClientDetailModal>
    with LiveRefresh<_ClientDetailModal> {
  ClientDetail? _detail;
  Map<String, String> _data = <String, String>{};
  List<ClientInvoiceItem> _items = <ClientInvoiceItem>[];
  List<_CdvRow> _spec = <_CdvRow>[];
  bool _loading = true;
  bool _changed = false;
  bool _removed = false;
  bool _livePending = false;
  bool _liveBusy = false;
  final Set<String> _editing = <String>{};
  final Set<String> _saving = <String>{};
  final Map<String, TextEditingController> _ctrl =
      <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  List<String> get liveKeys => const ['client'];

  @override
  void onLiveChange() => _liveRefresh();

  Future<void> _liveRefresh() async {
    if (_removed || _loading) return;
    if (_editing.isNotEmpty || _saving.isNotEmpty || _liveBusy) {
      _livePending = true;
      return;
    }
    _livePending = false;
    _liveBusy = true;
    final res = await widget.service.lookup(widget.brief.id);
    _liveBusy = false;
    if (!mounted) return;
    if (_editing.isNotEmpty || _saving.isNotEmpty) {
      _livePending = true;
      return;
    }
    if (res.missing) {
      setState(() {
        _removed = true;
        _changed = true;
      });
      return;
    }
    final d = res.detail;
    if (d != null) {
      setState(() {
        _detail = d;
        _data = _cdvDataOf(d);
        _items = List<ClientInvoiceItem>.from(d.invoiceItems);
        _rebuildSpec();
      });
    }
    if (_livePending) _liveRefresh();
  }

  void _flushLive() {
    if (_livePending && _editing.isEmpty && _saving.isEmpty) _liveRefresh();
  }

  TextEditingController _c(String key, String initial) =>
      _ctrl.putIfAbsent(key, () => TextEditingController(text: initial));

  void _dropControllers(String prefix) {
    final keys = _ctrl.keys.where((k) => k.startsWith(prefix)).toList();
    for (final k in keys) {
      _ctrl.remove(k)?.dispose();
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final d = await widget.service.detail(widget.brief.id);
    if (!mounted) return;
    setState(() {
      _detail = d;
      if (d != null) {
        _data = _cdvDataOf(d);
        _items = List<ClientInvoiceItem>.from(d.invoiceItems);
        _rebuildSpec();
      }
      _loading = false;
    });
  }

  void _rebuildSpec() {
    _spec = _cdvBuildSpec(_data, _items);
    for (final m in _spec) {
      if (m.nameWritable) continue;
      final list = _historyFor(m.rowKey);
      if (list.isEmpty) continue;
      final latest = list.last.newComponent.trim();
      if (latest.isNotEmpty) m.name = latest;
    }
  }

  List<ClientSpecReplacement> _historyFor(String key) =>
      (_detail?.specReplacements ?? const <ClientSpecReplacement>[])
          .where((r) => r.rowKey == key)
          .toList();

  void _close() => Navigator.of(context).pop(_changed);

  void _print() {
    _openPdf(context, widget.service.downloadClientPdf(widget.brief.id),
        preparing: 'Preparing client data sheet…');
  }

  void _startEdit(String sec) {
    _dropControllers('$sec:');
    setState(() => _editing.add(sec));
  }

  Map<String, dynamic> _sectionValues(String sec) {
    String v(String key, String fallback) => _ctrl[key]?.text ?? fallback;
    if (sec == 'customer') {
      return <String, dynamic>{
        for (final k in const ['name', 'invoice_number', 'branch', 'date_prepared'])
          k: v('customer:$k', _data[k] ?? ''),
      };
    }
    if (sec == 'bir') {
      return <String, dynamic>{
        for (final f in _cdvBirFields) f.$2: v('bir:${f.$2}', _data[f.$2] ?? ''),
      };
    }
    return <String, dynamic>{
      'rows': <Map<String, dynamic>>[
        for (var i = 0; i < _spec.length; i++)
          <String, dynamic>{
            'src': _spec[i].src,
            'idx': _spec[i].idx,
            'field': _spec[i].field,
            'serial': v('spec:sn:$i', _spec[i].serial),
            if (_spec[i].src == 'item') 'component': v('spec:comp:$i', ''),
          },
      ],
    };
  }

  Future<void> _save(String sec) async {
    if (_saving.contains(sec)) return;
    final values = _sectionValues(sec);
    setState(() => _saving.add(sec));
    final res = await widget.service.saveSheetSection(
      id: widget.brief.id,
      section: sec,
      values: values,
    );
    if (!mounted) return;
    setState(() {
      _saving.remove(sec);
      _editing.remove(sec);
      _dropControllers('$sec:');
      if (res.ok) _changed = true;
    });
    _snack(context, res.ok ? 'Changes saved' : res.message);
    await _load(silent: true);
    _flushLive();
  }

  Future<void> _replace(_CdvRow m) async {
    final result = await showDialog<({String component, String serial})>(
      context: context,
      builder: (_) => _ReplacementDialog(componentName: m.name),
    );
    if (result == null || !mounted) return;
    if (result.component.trim().isEmpty && result.serial.trim().isEmpty) {
      _snack(context, 'Enter the replacement component or serial number.');
      return;
    }
    final res = await widget.service.addSpecReplacement(
      clientId: widget.brief.id,
      src: m.src,
      index: m.idx,
      serialField: m.field,
      oldComponent: m.name,
      newComponent: result.component.trim(),
      newSerial: result.serial.trim(),
    );
    if (!mounted) return;
    _snack(context, res.ok ? 'Replacement recorded' : res.message);
    if (res.ok) {
      _changed = true;
      _dropControllers('spec:');
      await _load(silent: true);
    }
  }

  Future<void> _copy(String v) async {
    await Clipboard.setData(ClipboardData(text: v));
    if (mounted) _snack(context, 'Copied to clipboard');
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final w = (screen.width - 64).clamp(320.0, 900.0).toDouble();
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
      child: Center(
        child: Container(
          width: w,
          constraints: BoxConstraints(maxHeight: screen.height - 56),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x33111827), blurRadius: 60, offset: Offset(0, 24)),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: Colors.white,
            child: Stack(
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 4),
                      child: Column(
                        children: [
                          Image(image: brandAsset('assets/brand/logo-wordmark.png'),
                              height: 40, fit: BoxFit.contain),
                          const SizedBox(height: 6),
                          const Text(
                            'Client and Data Sheet',
                            style: TextStyle(
                              fontSize: 17.6,
                              fontWeight: FontWeight.w600,
                              color: _cdvText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: _loading
                          ? const SizedBox(height: 240, child: Center(
                              child: TpLoader(
                                  strokeWidth: 2, color: Brand.signal)))
                          : _removed
                              ? const SizedBox(
                                  height: 240,
                                  child: EmptyState(
                                    label: 'This record was removed',
                                    hint:
                                        'This client was deleted elsewhere. Close this sheet to return to the list.',
                                  ),
                                )
                              : _detail == null
                              ? const SizedBox(
                                  height: 240,
                                  child: EmptyState(
                                    label: 'Not found',
                                    hint: 'Could not load client details.',
                                  ),
                                )
                              : SingleChildScrollView(
                                  padding:
                                      const EdgeInsets.fromLTRB(32, 24, 32, 32),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _customerCard(),
                                      const SizedBox(height: 24),
                                      _specCard(),
                                      const SizedBox(height: 24),
                                      _birCard(),
                                    ],
                                  ),
                                ),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(24, 16, 32, 24),
                      decoration: const BoxDecoration(
                        border: Border(top: BorderSide(color: Color(0xFFF0F1F4))),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _footBtn('Close', null, false, _close),
                          if (!_removed) ...[
                            const SizedBox(width: 12),
                            _footBtn('Print', Icons.print_rounded, true, _print),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                Positioned(
                  top: 16,
                  right: 18,
                  child: _CdvCloseButton(onTap: _close),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _footBtn(String label, IconData? icon, bool primary, VoidCallback onTap) {
    return Material(
      color: primary ? Brand.signal : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: primary ? Brand.signal : const Color(0xFFD9DDE3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: primary ? Colors.white : _cdvText),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: primary ? Colors.white : _cdvText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(String sec, String title, IconData icon, List<String> head,
      List<Widget> rows) {
    final editing = _editing.contains(sec);
    final saving = _saving.contains(sec);
    return Container(
      padding: const EdgeInsets.fromLTRB(26, 24, 26, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8EBF0)),
        boxShadow: const [
          BoxShadow(color: Color(0x0D111827), blurRadius: 22, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Brand.signalGlow(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 17, color: Brand.signal),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                    color: _cdvText,
                  ),
                ),
              ),
              _CdvEditButton(
                editing: editing,
                busy: saving,
                onTap: () => editing ? _save(sec) : _startEdit(sec),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Brand.signal,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Expanded(flex: 6, child: _headText(head[0])),
                Expanded(flex: 4, child: _headText(head[1])),
              ],
            ),
          ),
          ...rows,
        ],
      ),
    );
  }

  Widget _headText(String t) => Text(
        t,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      );

  Widget _row({required Widget left, required Widget right}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 36),
          child: Row(
            children: [
              Expanded(flex: 6, child: left),
              Expanded(flex: 4, child: right),
            ],
          ),
        ),
      );

  Widget _label(String t) => Text(
        t,
        style: const TextStyle(fontSize: 13, color: _cdvText),
      );

  Widget _copyCell(String value) {
    final v = _cdvVal(value);
    if (v.isEmpty) {
      return const Text('N/A', style: TextStyle(fontSize: 13, color: _cdvMuted));
    }
    return Row(
      children: [
        Expanded(
          child: SelectableText(v,
              style: const TextStyle(fontSize: 13, color: _cdvSub)),
        ),
        _CdvCopyButton(onTap: () => _copy(v)),
      ],
    );
  }

  Widget _input(String key, String initial, {bool date = false, String? hint}) {
    final c = _c(key, initial);
    return SizedBox(
      height: 36,
      child: TextField(
        controller: c,
        readOnly: date,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          suffixIcon: date
              ? const Icon(Icons.calendar_today_rounded, size: 15)
              : null,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        ),
        onTap: date
            ? () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.tryParse(c.text) ?? now,
                  firstDate: DateTime(1990),
                  lastDate: DateTime(now.year + 10),
                );
                if (picked != null) {
                  c.text =
                      '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                }
              }
            : null,
      ),
    );
  }

  Widget _customerCard() {
    final editing = _editing.contains('customer');
    const fields = <(String, String, bool)>[
      ('Customer Name', 'name', false),
      ('Agreement / Invoice Number', 'invoice_number', false),
      ('Branch', 'branch', false),
      ('Date Prepared', 'date_prepared', true),
    ];
    return _card('customer', 'Customer Information', Icons.person_rounded,
        const ['Detail', ''], [
      for (final f in fields)
        _row(
          left: _label(f.$1),
          right: editing
              ? _input('customer:${f.$2}', _data[f.$2] ?? '', date: f.$3)
              : _copyCell(_data[f.$2] ?? ''),
        ),
    ]);
  }

  Widget _birCard() {
    final editing = _editing.contains('bir');
    return _card('bir', 'BIR Compliant System', Icons.description_rounded,
        const ['Detail', ''], [
      for (final f in _cdvBirFields)
        _row(
          left: _label(f.$1),
          right: editing
              ? _input('bir:${f.$2}', _data[f.$2] ?? '', date: f.$3)
              : _copyCell(_data[f.$2] ?? ''),
        ),
    ]);
  }

  Widget _specCard() {
    final editing = _editing.contains('spec');
    final rows = <Widget>[];
    if (_spec.isEmpty) {
      rows.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Text('No system specifications recorded.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: _cdvMuted)),
      ));
    }
    for (var i = 0; i < _spec.length; i++) {
      final m = _spec[i];
      final history = _historyFor(m.rowKey);
      final badge = history.isNotEmpty ? const _CdvReplBadge() : null;
      final nameWidget = editing && m.src == 'item'
          ? Row(children: [
              Expanded(child: _input('spec:comp:$i', m.name)),
              if (badge != null) ...[const SizedBox(width: 6), badge],
              const SizedBox(width: 24),
            ])
          : Row(children: [
              Flexible(child: _label(m.name)),
              if (badge != null) ...[const SizedBox(width: 8), badge],
            ]);
      rows.add(_row(
        left: Row(
          children: [
            SizedBox(
                width: 28,
                child: Icon(m.icon, size: 16, color: Brand.signal)),
            Expanded(child: nameWidget),
          ],
        ),
        right: editing
            ? Row(children: [
                Expanded(
                    child: _input('spec:sn:$i', m.serial, hint: 'Serial number')),
                const SizedBox(width: 6),
                Tooltip(
                  message: 'Record a replacement',
                  child: _CdvCopyButton(
                    icon: Icons.swap_horiz_rounded,
                    onTap: () => _replace(m),
                  ),
                ),
              ])
            : m.serial.isEmpty
                ? const Text('N/A',
                    style: TextStyle(fontSize: 13, color: _cdvMuted))
                : _copyCell(m.serial),
      ));
      var level = 1;
      for (var k = history.length - 1; k >= 0; k--, level++) {
        final r = history[k];
        final name = r.oldComponent.trim().isEmpty ? m.name : r.oldComponent.trim();
        final serial = r.oldSerial.trim();
        final when = _formatReplacedAt(r.replacedAt);
        final who = r.replacedByName.trim();
        final tag = <String>[
          'Replaced${when.isEmpty ? '' : ' $when'}',
          if (who.isNotEmpty) 'by $who',
        ].join(' · ');
        rows.add(_row(
          left: Padding(
            padding: EdgeInsets.only(left: 12.0 + (level - 1) * 18),
            child: Row(
              children: [
                const Text('└─', style: TextStyle(color: _cdvMuted, fontSize: 13)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: _cdvSub)),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(tag,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: _cdvMuted)),
                ),
              ],
            ),
          ),
          right: serial.isEmpty
              ? const Text('N/A', style: TextStyle(fontSize: 13, color: _cdvMuted))
              : Row(children: [
                  Expanded(
                    child: Text(serial,
                        style: const TextStyle(
                          fontSize: 13,
                          color: _cdvMuted,
                          decoration: TextDecoration.lineThrough,
                        )),
                  ),
                  _CdvCopyButton(onTap: () => _copy(serial)),
                ]),
        ));
      }
    }
    return _card('spec', 'System Specifications', Icons.desktop_windows_rounded,
        const ['Component', 'Serial Number'], rows);
  }
}

class _CdvReplBadge extends StatelessWidget {
  const _CdvReplBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: Brand.signalGlow(0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.swap_horiz_rounded, size: 11, color: Brand.signal),
          SizedBox(width: 3),
          Text('Replacement',
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: Brand.signal)),
        ],
      ),
    );
  }
}

class _CdvCopyButton extends StatefulWidget {
  const _CdvCopyButton({required this.onTap, this.icon = Icons.copy_rounded});

  final VoidCallback onTap;
  final IconData icon;

  @override
  State<_CdvCopyButton> createState() => _CdvCopyButtonState();
}

class _CdvCopyButtonState extends State<_CdvCopyButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: _hover ? Brand.signalGlow(0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(widget.icon,
              size: 14, color: _hover ? Brand.signal : _cdvMuted),
        ),
      ),
    );
  }
}

class _CdvEditButton extends StatelessWidget {
  const _CdvEditButton({
    required this.editing,
    required this.busy,
    required this.onTap,
  });

  final bool editing;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = editing ? Colors.white : Brand.signal;
    return Material(
      color: editing ? Brand.signal : Colors.white,
      shape: StadiumBorder(
        side: BorderSide(color: editing ? Brand.signal : Brand.signalGlow(0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              busy
                  ? SizedBox(
                      width: 11,
                      height: 11,
                      child: TpLoader(strokeWidth: 1.6, color: fg))
                  : Icon(editing ? Icons.check_rounded : Icons.edit_rounded,
                      size: 12, color: fg),
              const SizedBox(width: 6),
              Text(
                editing ? 'Save' : 'Edit',
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600, color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CdvCloseButton extends StatefulWidget {
  const _CdvCloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_CdvCloseButton> createState() => _CdvCloseButtonState();
}

class _CdvCloseButtonState extends State<_CdvCloseButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _hover ? const Color(0xFFFFF5F5) : Colors.white,
            borderRadius: BorderRadius.circular(9),
            boxShadow: const [
              BoxShadow(color: Color(0x1A111827), blurRadius: 8, offset: Offset(0, 2)),
            ],
          ),
          child: Icon(Icons.close_rounded,
              size: 20,
              color: _hover ? const Color(0xFFEF4444) : _cdvText),
        ),
      ),
    );
  }
}
