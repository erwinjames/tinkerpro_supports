import 'package:flutter/material.dart';

import '../api_client.dart';
import '../services/bir_step2_service.dart';
import 'bir_ptu_upload_screen.dart';
import 'bir_step2_widgets.dart';
import '../widgets/tp_loader.dart';

class BirStep2FormScreen extends StatefulWidget {
  const BirStep2FormScreen({
    super.key,
    required this.service,
    required this.data,
  });

  final BirStep2Service service;
  final BirStep2FormData data;

  static const _advancedResult = 'advanced';

  static Future<bool?> showEdit(
    BuildContext context, {
    required ApiClient api,
    required int customerId,
    bool fromView = false,
  }) async {
    final service = BirStep2Service(api);
    final data = await service.editForm(customerId, fromView: fromView);
    if (!context.mounted) return null;
    if (data == null) {
      birToast(
        context,
        'An error occurred while fetching customer details.',
        error: true,
      );
      return null;
    }
    return open(context, api: api, data: data);
  }

  static Future<bool?> open(
    BuildContext context, {
    required ApiClient api,
    required BirStep2FormData data,
  }) async {
    final service = BirStep2Service(api);
    final result = await showDialog<Object>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BirStep2FormScreen(service: service, data: data),
    );
    if (result == _advancedResult && context.mounted) {
      return BirPtuAdvanceScreen.show(
        context,
        api: api,
        customerId: int.tryParse(data.fields['customer_id'] ?? '') ?? 0,
      );
    }
    return result == true ? true : null;
  }

  @override
  State<BirStep2FormScreen> createState() => _BirStep2FormScreenState();
}

class _SnCard {
  _SnCard(BirSerialEntry e)
    : type = e.type,
      serverType = e.serverType,
      sn = TextEditingController(text: e.serialNumber),
      brand = TextEditingController(text: e.brand),
      model = TextEditingController(text: e.model);

  String type;
  String serverType;
  final TextEditingController sn;
  final TextEditingController brand;
  final TextEditingController model;

  BirSerialEntry toEntry() => BirSerialEntry(
    type: type,
    serverType: type == 'Server' ? serverType : '',
    serialNumber: sn.text.trim(),
    brand: brand.text.trim(),
    model: model.text.trim(),
  );

  void dispose() {
    sn.dispose();
    brand.dispose();
    model.dispose();
  }
}

class _BirStep2FormScreenState extends State<BirStep2FormScreen> {
  static const _brands = [
    'TinkerPro',
    'Cloned',
    'HP',
    'Dell',
    'Lenovo',
    'Acer',
    'Asus',
    'Apple',
    'Samsung',
    'MSI',
    'Toshiba',
    'Fujitsu',
    'Gigabyte',
    'Intel',
    'NEC',
    'Epson',
  ];
  static const _models = [
    'Generic',
    'Desktop',
    'Laptop',
    'Mini PC',
    'All-in-One',
    'Tower',
    'Workstation',
    'Tablet',
    'POS Terminal',
  ];

  final Map<String, TextEditingController> _c = {};
  final List<_SnCard> _cards = [];
  bool _editing = false;
  bool _saving = false;
  String _isVat = '';
  final Set<String> _missing = {};

  String? _province;
  String? _city;
  List<Map<String, dynamic>> _provinces = [];
  List<Map<String, dynamic>> _allCities = [];
  List<Map<String, dynamic>> _businessLines = [];
  List<Map<String, dynamic>> _lobMatches = [];

  BirStep2FormData get _d => widget.data;

  TextEditingController _ctl(String key) => _c.putIfAbsent(
    key,
    () => TextEditingController(text: _d.fields[key] ?? ''),
  );

  @override
  void initState() {
    super.initState();
    for (final k in const [
      'softwarename',
      'acc_number',
      'companyname',
      'tin',
      'rdo',
      'address',
      'min',
      'ptu',
      'pos_date_issued',
      'businesslinecode',
      'firstname',
      'middlename',
      'lastname',
      'email',
      'username',
      'password',
    ]) {
      _ctl(k);
    }
    _c['businessline'] = TextEditingController(
      text: _d.fields['businessline'] ?? '',
    );
    _c['province_text'] = TextEditingController(
      text: _d.fields['province_text'] ?? '',
    );
    _c['city_text'] = TextEditingController(text: _d.fields['city_text'] ?? '');
    _province = (_d.fields['province'] ?? '').isEmpty
        ? null
        : _d.fields['province'];
    _city = (_d.fields['city'] ?? '').isEmpty ? null : _d.fields['city'];
    _isVat = _d.fields['is_vat'] ?? '';
    final entries = _d.serialEntries.isEmpty
        ? [BirSerialEntry()]
        : _d.serialEntries;
    for (final e in entries) {
      _cards.add(_SnCard(e));
    }
    _loadLookups();
  }

  Future<void> _loadLookups() async {
    final results = await Future.wait([
      widget.service.provinces(),
      widget.service.cities(),
      widget.service.businessLines(),
    ]);
    if (!mounted) return;
    setState(() {
      _provinces = results[0]
        ..sort(
          (a, b) => '${a['province_name']}'.compareTo('${b['province_name']}'),
        );
      _allCities = results[1];
      _businessLines = results[2];
    });
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    for (final c in _cards) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _noValidate => _editing || _d.isPendingRegistration;
  bool get _locked => !_editing;
  bool get _ptuLocked => !_editing || _d.isUploadPtu;

  List<String> _typeOptions(_SnCard card) {
    var serverTaken = false;
    var hasServerOrTerminal = false;
    var hasStandalone = false;
    for (final c in _cards) {
      if (c.type == 'Server') {
        serverTaken = true;
        hasServerOrTerminal = true;
      } else if (c.type == 'Terminal') {
        hasServerOrTerminal = true;
      } else if (c.type == 'Standalone') {
        hasStandalone = true;
      }
    }
    final current = card.type;
    return [
      if (current == 'Server' || (!serverTaken && !hasStandalone)) 'Server',
      if (current == 'Terminal' || !hasStandalone) 'Terminal',
      if (current == 'Standalone' || !hasServerOrTerminal) 'Standalone',
    ];
  }

  List<Map<String, dynamic>> get _cities {
    if (_province == null) return const [];
    final list =
        _allCities.where((c) => '${c['province_code']}' == _province).toList()
          ..sort((a, b) => '${a['city_name']}'.compareTo('${b['city_name']}'));
    return list;
  }

  void _onLobChanged(String value) {
    final q = value.trim();
    setState(() {
      _lobMatches = q.isEmpty
          ? []
          : _businessLines
                .where(
                  (i) =>
                      '${i['code']}'.contains(q) ||
                      '${i['description']}'.toLowerCase().contains(
                        q.toLowerCase(),
                      ),
                )
                .toList();
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    _missing.clear();
    if (!_noValidate) {
      for (final k in const [
        'firstname',
        'lastname',
        'email',
        'username',
        'password',
      ]) {
        if (_c[k]!.text.trim().isEmpty) _missing.add(k);
      }
      if (_missing.isNotEmpty) {
        setState(() {});
        birToast(
          context,
          'Please fill out the highlighted fields.',
          error: true,
        );
        return;
      }
    }
    setState(() => _saving = true);
    final entries = _cards.map((c) => c.toEntry()).toList();
    final prep = await widget.service.prepareSave(
      isVat: _isVat,
      entries: entries,
      isPendingRegistration: _d.isPendingRegistration,
      originalStep2: _d.originalStep2,
    );
    if (!mounted) return;
    if (!prep.ok) {
      setState(() => _saving = false);
      birToast(context, prep.message, error: true);
      return;
    }
    final canon = Map<String, dynamic>.from(prep.data['fields'] as Map? ?? {});
    String t(String k) => _c[k]!.text;
    final fields = <String, String>{
      'customer_id': _d.fields['customer_id'] ?? '',
      'invoice_number': _d.fields['invoice_number'] ?? '',
      'pdf_file': _d.fields['pdf_file'] ?? '',
      'bir_registration_extracted': '1',
      'softwarename': t('softwarename'),
      'acc_number': t('acc_number'),
      'sn': '${canon['sn'] ?? ''}',
      'serial_entries': '${canon['serial_entries'] ?? ''}',
      'companyname': t('companyname'),
      'tin': t('tin'),
      'rdo': t('rdo'),
      'address': t('address'),
      'min': t('min'),
      'ptu': t('ptu'),
      'pos_date_issued': t('pos_date_issued'),
      'province': ?_province,
      'province_text': t('province_text'),
      'city': ?_city,
      'city_text': t('city_text'),
      'businessline': t('businessline'),
      'businesslinecode': t('businesslinecode'),
      'firstname': t('firstname'),
      'middlename': t('middlename'),
      'lastname': t('lastname'),
      'email': t('email'),
      'username': t('username'),
      'password': t('password'),
      'is_vat': _isVat,
      if (canon.containsKey('step2')) 'step2': '${canon['step2']}',
    };
    final update = _d.isUpdate;
    final r = await widget.service.saveCustomer(update: update, fields: fields);
    if (!mounted) return;
    setState(() => _saving = false);
    if (r.ok) {
      birToast(
        context,
        update
            ? 'Customer Updated Successfully'
            : 'Customer Added Successfully',
      );
      Navigator.of(context).pop(true);
      return;
    }
    if (r.data.isEmpty) {
      birToast(context, 'An error occurred: ${r.message}', error: true);
      return;
    }
    birToast(
      context,
      '${update ? 'Customer Not Updated' : 'Customer Not Added'}: ${r.message}',
      error: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BirNavyModal(
      kicker: 'Step 2',
      icon: Icons.description_outlined,
      title: 'Application for Registration',
      subtitle:
          'Complete the registration details for sales machines and sworn statement declaration.',
      width: 680,
      onClose: _saving ? null : () => Navigator.of(context).pop(),
      closeEnabled: !_saving,
      headerTrailing: _intakeBadge(),
      footer: _footer(),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Color(0xFFFFFAF5)],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(32, 20, 32, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(alignment: Alignment.centerRight, child: _editToggle()),
              const SizedBox(height: 14),
              _grid([
                _box(
                  'Software Name',
                  Icons.desktop_windows_outlined,
                  _text('softwarename', readOnly: _locked),
                ),
                _box(
                  'Accreditation No.',
                  Icons.workspace_premium_outlined,
                  _text('acc_number', readOnly: _locked),
                ),
                _snGroup(),
              ]),
              const SizedBox(height: 14),
              _grid([
                _box(
                  'Company Name',
                  Icons.business,
                  _text('companyname', readOnly: _locked),
                  wide: true,
                ),
                _box('TIN', Icons.tag, _text('tin', readOnly: _locked)),
                _box(
                  'RDO',
                  Icons.place_outlined,
                  _text('rdo', readOnly: _locked),
                ),
                _box(
                  'Business Address',
                  Icons.location_on_outlined,
                  _text('address', readOnly: _locked),
                  wide: true,
                ),
              ]),
              if (_d.showMin || _d.showPtu || _d.showPosDateIssued) ...[
                const SizedBox(height: 14),
                _grid([
                  if (_d.showMin)
                    _box(
                      'MIN',
                      Icons.memory,
                      _text('min', readOnly: _ptuLocked),
                    ),
                  if (_d.showPtu)
                    _box(
                      'PTU',
                      Icons.badge_outlined,
                      _text('ptu', readOnly: _ptuLocked),
                    ),
                  if (_d.showPosDateIssued)
                    _box(
                      'Date Issued',
                      Icons.event_available_outlined,
                      _text('pos_date_issued', readOnly: _ptuLocked),
                    ),
                ]),
              ],
              const SizedBox(height: 20),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.gavel, size: 13, color: birOrange),
                  SizedBox(width: 6),
                  Text(
                    'SWORN STATEMENT & DECLARATION',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.6,
                      color: birOrange,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _grid([
                _box('Province', Icons.map_outlined, _provinceSelect()),
                _box(
                  'City / Municipality',
                  Icons.location_city_outlined,
                  _citySelect(),
                ),
                _box(
                  'Business Line (Sub Code)',
                  Icons.work_outline,
                  _lobField(),
                  wide: true,
                ),
              ]),
              const SizedBox(height: 14),
              _grid([
                _box(
                  'First Name',
                  Icons.person_outline,
                  _text('firstname', hint: 'First Name'),
                ),
                _box(
                  'Middle Name',
                  Icons.person_outline,
                  _text('middlename', hint: 'Middle Name'),
                ),
                _box(
                  'Last Name',
                  Icons.person_outline,
                  _text('lastname', hint: 'Last Name'),
                ),
                _box(
                  'Email',
                  Icons.mail_outline,
                  _text('email', hint: 'Email'),
                ),
                _box(
                  'Username',
                  Icons.account_circle_outlined,
                  _text('username', hint: 'Username'),
                ),
                _box(
                  'Password',
                  Icons.key_outlined,
                  _text('password', hint: 'Password'),
                ),
              ]),
              const SizedBox(height: 10),
              _vatBox(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _intakeBadge() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: birOrange,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.fact_check_outlined,
            color: Colors.white,
            size: 16,
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'BRAND REVIEW',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: Colors.white.withValues(alpha: 0.45),
              ),
            ),
            const Text(
              'TinkerPro Intake',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _editToggle() {
    return InkWell(
      onTap: _saving ? null : () => setState(() => _editing = !_editing),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
        decoration: BoxDecoration(
          color: _editing
              ? birOrange.withValues(alpha: 0.1)
              : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: _editing ? birOrange : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _editing ? Icons.lock_open : Icons.lock_outline,
              size: 15,
              color: _editing ? birOrange : const Color(0xFF64748B),
            ),
            const SizedBox(width: 6),
            Text(
              _editing ? 'Editing Active' : 'Enable Edit',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: _editing ? birOrange : const Color(0xFF475569),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 22,
              child: FittedBox(
                child: Switch(
                  value: _editing,
                  activeThumbColor: Colors.white,
                  activeTrackColor: birOrange,
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _editing = v),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _grid(List<_Cell> cells) {
    final rows = <Widget>[];
    var i = 0;
    while (i < cells.length) {
      final a = cells[i];
      if (a.wide || i + 1 >= cells.length || cells[i + 1].wide) {
        rows.add(a.child);
        i++;
      } else {
        rows.add(
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: a.child),
                const SizedBox(width: 14),
                Expanded(child: cells[i + 1].child),
              ],
            ),
          ),
        );
        i += 2;
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var k = 0; k < rows.length; k++) ...[
          if (k > 0) const SizedBox(height: 14),
          rows[k],
        ],
      ],
    );
  }

  _Cell _box(String label, IconData icon, Widget child, {bool wide = false}) {
    return _Cell(
      wide,
      Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE8E8E8)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, size: 12, color: const Color(0xFF94A3B8)),
                const SizedBox(width: 6),
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.9,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            child,
          ],
        ),
      ),
    );
  }

  Widget _text(String key, {bool readOnly = false, String? hint}) {
    final missing = _missing.contains(key);
    return TextField(
      controller: _c[key],
      readOnly: readOnly,
      onChanged: missing ? (_) => setState(() => _missing.remove(key)) : null,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: readOnly ? const Color(0xFF64748B) : birNavy,
      ),
      decoration: InputDecoration(
        isDense: true,
        filled: false,
        hintText: hint,
        hintStyle: const TextStyle(
          color: Color(0xFFCBD5E1),
          fontWeight: FontWeight.w500,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 4),
        border: InputBorder.none,
        enabledBorder: missing
            ? const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.red),
              )
            : InputBorder.none,
        focusedBorder: InputBorder.none,
        errorText: missing ? 'Please fill out this field.' : null,
      ),
    );
  }

  Widget _mini(
    TextEditingController c,
    String hint, {
    bool readOnly = false,
    List<String>? options,
  }) {
    final field = TextField(
      controller: c,
      readOnly: readOnly,
      style: const TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        color: birNavy,
      ),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        suffixIcon: options == null || readOnly
            ? null
            : PopupMenuButton<String>(
                tooltip: hint,
                icon: const Icon(Icons.expand_more, size: 16),
                onSelected: (v) => setState(() => c.text = v),
                itemBuilder: (_) {
                  final q = c.text.trim().toLowerCase();
                  final list = options
                      .where((o) => q.isEmpty || o.toLowerCase().contains(q))
                      .toList();
                  return [
                    for (final o in list.isEmpty ? options : list)
                      PopupMenuItem(value: o, height: 34, child: Text(o)),
                  ];
                },
              ),
      ),
    );
    return field;
  }

  _Cell _snGroup() {
    return _Cell(
      true,
      Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _editing
                ? birOrange.withValues(alpha: 0.5)
                : const Color(0xFFE8E8E8),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.qr_code_2, size: 12, color: Color(0xFF94A3B8)),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'SERIAL NUMBER ENTRIES',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.9,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _saving
                      ? null
                      : () => setState(
                          () => _cards.add(_SnCard(BirSerialEntry())),
                        ),
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text('Add'),
                  style: TextButton.styleFrom(foregroundColor: birOrange),
                ),
              ],
            ),
            for (var i = 0; i < _cards.length; i++) _snCard(i),
          ],
        ),
      ),
    );
  }

  Widget _snCard(int i) {
    final card = _cards[i];
    final ro = _locked;
    final opts = _typeOptions(card);
    return Container(
      key: ObjectKey(card),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8ECF1)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 140,
                child: DropdownButtonFormField<String>(
                  key: ValueKey(
                    't-${identityHashCode(card)}-${card.type}-${opts.join()}',
                  ),
                  initialValue: card.type.isEmpty || !opts.contains(card.type)
                      ? ''
                      : card.type,
                  isDense: true,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                  ),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('Type')),
                    for (final o in opts)
                      DropdownMenuItem(value: o, child: Text(o)),
                  ],
                  onChanged: ro
                      ? null
                      : (v) => setState(() {
                          card.type = v ?? '';
                          if (card.type != 'Server') card.serverType = '';
                        }),
                ),
              ),
              if (card.type == 'Server') ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 150,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(
                      's-${identityHashCode(card)}-${card.serverType}',
                    ),
                    initialValue:
                        const [
                          'Consolidator',
                          'Global',
                        ].contains(card.serverType)
                        ? card.serverType
                        : '',
                    isDense: true,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(value: '', child: Text('Server Type')),
                      DropdownMenuItem(
                        value: 'Consolidator',
                        child: Text('Consolidator'),
                      ),
                      DropdownMenuItem(value: 'Global', child: Text('Global')),
                    ],
                    onChanged: ro
                        ? null
                        : (v) => setState(() => card.serverType = v ?? ''),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Expanded(child: _mini(card.sn, 'Serial Number', readOnly: ro)),
              SizedBox(
                width: 36,
                child: i == 0
                    ? null
                    : IconButton(
                        tooltip: 'Remove serial number',
                        onPressed: () =>
                            setState(() => _cards.removeAt(i).dispose()),
                        icon: const Icon(Icons.close, size: 16),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _mini(
                  card.brand,
                  'Brand',
                  readOnly: ro,
                  options: _brands,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _mini(
                  card.model,
                  'Model',
                  readOnly: ro,
                  options: _models,
                ),
              ),
              const SizedBox(width: 36),
            ],
          ),
        ],
      ),
    );
  }

  Widget _provinceSelect() {
    final items = <DropdownMenuItem<String>>[
      for (final p in _provinces)
        DropdownMenuItem(
          value: '${p['province_code']}',
          child: Text('${p['province_name']}', overflow: TextOverflow.ellipsis),
        ),
    ];
    if (_province != null && !items.any((i) => i.value == _province)) {
      items.insert(
        0,
        DropdownMenuItem(
          value: _province,
          child: Text(_c['province_text']!.text),
        ),
      );
    }
    return DropdownButtonFormField<String>(
      key: ValueKey('prov-${_provinces.length}-$_province'),
      initialValue: _province,
      isExpanded: true,
      isDense: true,
      hint: const Text('Choose State/Province'),
      decoration: const InputDecoration(
        isDense: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        filled: false,
        contentPadding: EdgeInsets.symmetric(vertical: 4),
      ),
      items: items,
      onChanged: (v) => setState(() {
        _province = v;
        final match = _provinces.where((p) => '${p['province_code']}' == v);
        _c['province_text']!.text = match.isEmpty
            ? ''
            : '${match.first['province_name']}';
        _city = null;
        _c['city_text']!.text = '';
      }),
    );
  }

  Widget _citySelect() {
    final list = _cities;
    final items = <DropdownMenuItem<String>>[
      for (final c in list)
        DropdownMenuItem(
          value: '${c['city_code']}',
          child: Text('${c['city_name']}', overflow: TextOverflow.ellipsis),
        ),
    ];
    if (_city != null && !items.any((i) => i.value == _city)) {
      items.insert(
        0,
        DropdownMenuItem(value: _city, child: Text(_c['city_text']!.text)),
      );
    }
    return DropdownButtonFormField<String>(
      key: ValueKey('city-$_province-${list.length}-$_city'),
      initialValue: _city,
      isExpanded: true,
      isDense: true,
      hint: const Text('Choose City/Municipality'),
      decoration: const InputDecoration(
        isDense: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        filled: false,
        contentPadding: EdgeInsets.symmetric(vertical: 4),
      ),
      items: items,
      onChanged: (v) => setState(() {
        _city = v;
        final match = list.where((c) => '${c['city_code']}' == v);
        _c['city_text']!.text = match.isEmpty
            ? ''
            : '${match.first['city_name']}';
      }),
    );
  }

  Widget _lobField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _c['businesslinecode'],
          onChanged: _onLobChanged,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: birNavy,
          ),
          decoration: const InputDecoration(
            isDense: true,
            filled: false,
            hintText: 'Enter Sub Code',
            hintStyle: TextStyle(
              color: Color(0xFFCBD5E1),
              fontWeight: FontWeight.w500,
            ),
            contentPadding: EdgeInsets.symmetric(vertical: 4),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
        ),
        if (_lobMatches.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE5E7EB)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _lobMatches.length,
              itemBuilder: (_, i) {
                final item = _lobMatches[i];
                return InkWell(
                  onTap: () => setState(() {
                    _c['businesslinecode']!.text =
                        '${item['code']} - ${item['description']}';
                    _c['businessline']!.text = '${item['description']}';
                    _lobMatches = [];
                  }),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Color(0xFFEEF0F3)),
                      ),
                    ),
                    child: Text(
                      '${item['code']} - ${item['description']}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _vatBox() {
    Widget radio(String value, String label) => InkWell(
      onTap: () => setState(() => _isVat = value),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Radio<String>(value: value, activeColor: birOrange),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600, color: birNavy),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFFBF5), Color(0xFFFFF8EF)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: birOrange.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'VAT Registration',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                    color: birNavy,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Select the registration type for this client.',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                ),
              ],
            ),
          ),
          RadioGroup<String>(
            groupValue: _isVat,
            onChanged: (v) => setState(() => _isVat = v ?? ''),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                radio('1', 'VAT'),
                const SizedBox(width: 6),
                radio('0', 'Non-VAT'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(32, 14, 32, 14),
      decoration: const BoxDecoration(
        color: Color(0xFFFFFAF5),
        border: Border(top: BorderSide(color: Color(0x0F000000))),
      ),
      child: Row(
        children: [
          if (_d.showAdvanced)
            OutlinedButton.icon(
              onPressed: _saving
                  ? null
                  : () => Navigator.of(
                      context,
                    ).pop(BirStep2FormScreen._advancedResult),
              icon: const Icon(Icons.keyboard_outlined, size: 16),
              label: const Text('Advanced'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFC26200),
                side: const BorderSide(color: birOrange),
                minimumSize: const Size(0, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          const Spacer(),
          if (_d.fromView) ...[
            TextButton.icon(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('Go Back'),
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFFF1F5F9),
                foregroundColor: const Color(0xFF475569),
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          ElevatedButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: TpLoader(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_circle_outline, size: 16),
            label: Text(_saving ? 'Saving...' : 'Confirm & Save'),
            style: ElevatedButton.styleFrom(
              backgroundColor: birOrange,
              foregroundColor: Colors.white,
              disabledBackgroundColor: birOrange.withValues(alpha: 0.7),
              disabledForegroundColor: Colors.white,
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 22),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _Cell {
  const _Cell(this.wide, this.child);
  final bool wide;
  final Widget child;
}
