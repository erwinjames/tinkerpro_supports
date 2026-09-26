import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api_client.dart';
import '../services/bir_data_service.dart';
import '../services/bir_register_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import '../widgets/tp_loader.dart';
import 'bir_widgets.dart';

enum BirReviewMode { add, continueUpload, complete }

class BirRegisterReviewDialog extends StatefulWidget {
  const BirRegisterReviewDialog({
    super.key,
    required this.api,
    required this.data,
    required this.mode,
    this.customerId,
    this.invoiceNumber = '',
    this.onViewDetails,
  });

  final ApiClient api;
  final Map<String, dynamic> data;
  final BirReviewMode mode;
  final int? customerId;
  final String invoiceNumber;
  final Future<void> Function()? onViewDetails;

  static Future<bool?> show(
    BuildContext context, {
    required ApiClient api,
    required Map<String, dynamic> data,
    required BirReviewMode mode,
    int? customerId,
    String invoiceNumber = '',
    Future<void> Function()? onViewDetails,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BirRegisterReviewDialog(
        api: api,
        data: data,
        mode: mode,
        customerId: customerId,
        invoiceNumber: invoiceNumber,
        onViewDetails: onViewDetails,
      ),
    );
  }

  @override
  State<BirRegisterReviewDialog> createState() =>
      _BirRegisterReviewDialogState();
}

class _SnRow {
  _SnRow(Map<String, dynamic> m)
    : type = (m['serial_number_type'] ?? '').toString(),
      serverType = (m['server_type'] ?? '').toString(),
      sn = TextEditingController(text: (m['serial_number'] ?? '').toString()),
      brand = TextEditingController(text: (m['brand'] ?? '').toString()),
      model = TextEditingController(text: (m['model'] ?? '').toString());

  String type;
  String serverType;
  final TextEditingController sn;
  final TextEditingController brand;
  final TextEditingController model;
  final GlobalKey key = GlobalKey();
  final FocusNode snFocus = FocusNode();
  String dupMsg = '';
  bool dbDup = false;
  List<Map<String, dynamic>> suggestions = const [];
  bool suggestOpen = false;
  String suggestQuery = '';
  Timer? snTimer;
  Timer? suggestTimer;

  int get id => identityHashCode(this);

  Map<String, dynamic> toJson() => {
    'serial_number_type': type,
    'server_type': serverType,
    'serial_number': sn.text,
    'brand': brand.text,
    'model': model.text,
  };

  void dispose() {
    snTimer?.cancel();
    suggestTimer?.cancel();
    sn.dispose();
    brand.dispose();
    model.dispose();
    snFocus.dispose();
  }
}

class _BirthdateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue o, TextEditingValue n) {
    final d = n.text.replaceAll(RegExp(r'[^0-9]'), '');
    final digits = d.length > 8 ? d.substring(0, 8) : d;
    var out = digits.length > 2 ? digits.substring(0, 2) : digits;
    if (digits.length > 2) {
      out += '/${digits.substring(2, digits.length > 4 ? 4 : digits.length)}';
    }
    if (digits.length > 4) out += '/${digits.substring(4)}';
    return TextEditingValue(
      text: out,
      selection: TextSelection.collapsed(offset: out.length),
    );
  }
}

class _Section {
  const _Section(this.id, this.title, this.icon, this.hint);
  final String id;
  final String title;
  final IconData icon;
  final String hint;
}

class _Req {
  _Req(
    this.section,
    this.target,
    this.label,
    this.filled, {
    this.focus,
    this.rowKey,
    this.error = false,
  });
  final String section;
  final String target;
  final String label;
  final bool filled;
  final FocusNode? focus;
  final GlobalKey? rowKey;
  final bool error;
}

class _BirRegisterReviewDialogState extends State<BirRegisterReviewDialog> {
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
  static const _textKeys = [
    'raw_extracted_text',
    'companyname',
    'tin',
    'branch_code',
    'rdo',
    'tin_issuance_date',
    'line_of_business',
    'address',
    'lastname',
    'firstname',
    'middlename',
    'birthdate',
    'phone_number',
    'email_address',
    'acc_number',
    'valid_id_type',
    'valid_id_source_file',
  ];
  static const _hiddenKeys = [
    'ownerName',
    'line_of_business_desc',
    'pdf_file',
    'is_vat',
    'authorized_person',
    'valid_id_number',
    'roving',
    'present_reading',
    'date_of_reading',
    'last_or_number',
    'last_cash_invoice_number',
    'last_charge_invoice_number',
    'last_transaction_number',
  ];
  static const _businessKeys = [
    'companyname',
    'tin',
    'branch_code',
    'rdo',
    'tin_issuance_date',
    'line_of_business',
    'registration_type',
    'address',
  ];
  static const _choiceKeys = [
    'registration_type',
    'softwarename',
    'software_version',
  ];
  static const _imageExt = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'];

  late final BirRegisterService _svc = BirRegisterService(widget.api);
  final Map<String, TextEditingController> _c = {};
  final Map<String, String> _hidden = {};
  final Map<String, String> _auto = {};
  String _registrationType = '';
  String _software = '';
  String _version = '';
  Map<String, List<Map<String, dynamic>>> _catalog = {};
  List<String> _visible = const [];
  final List<_SnRow> _rows = [];
  List<Map<String, dynamic>> _lobCandidates = const [];
  List<Map<String, dynamic>> _lobSuggest = const [];
  bool _lobFocused = false;
  final _lobFocus = FocusNode();
  Timer? _lobTimer;
  final List<Map<String, dynamic>> _stored = [];
  final List<Map<String, dynamic>> _requirements = [];
  bool _namesEdited = false;
  String _tinDupMsg = '';
  Timer? _tinTimer;
  bool _addingDocs = false;
  bool _attaching = false;
  String _previewStatus = 'Update extraction with more files.';
  bool _saving = false;
  final _ocrSearch = TextEditingController();
  List<int> _ocrMatches = const [];
  int _ocrIndex = -1;
  bool _ocrOpen = false;

  final _scroll = ScrollController();
  final _viewportKey = GlobalKey();
  final Map<String, GlobalKey> _sectionKeys = {};
  final Map<String, GlobalKey> _fieldKeys = {};
  final Map<String, FocusNode> _focus = {};
  String _active = '';
  bool _attempted = false;
  bool _navLock = false;
  Set<String> _missing = const {};

  bool get _complete => widget.mode == BirReviewMode.complete;

  @override
  void initState() {
    super.initState();
    if (kDebugMode && Platform.environment['TP_BIR_SN'] != null) {
      Timer(const Duration(seconds: 2), () {
        if (!mounted || _rows.isEmpty) return;
        final r = _rows.last;
        r.type = Platform.environment['TP_BIR_SN_TYPE'] ?? r.type;
        r.sn.text = Platform.environment['TP_BIR_SN']!;
        _onSnChanged(r);
      });
    }
    final d = widget.data;
    final f = d['fields'] is Map
        ? Map<String, dynamic>.from(d['fields'])
        : <String, dynamic>{};
    for (final k in _textKeys) {
      _c[k] = TextEditingController(text: (f[k] ?? '').toString());
    }
    for (final k in _hiddenKeys) {
      _hidden[k] = (f[k] ?? '').toString();
    }
    _registrationType = (f['registration_type'] ?? '').toString();
    _software = (f['softwarename'] ?? '').toString();
    _version = (f['software_version'] ?? '').toString();
    if (!_complete) {
      for (final k in [..._textKeys, ..._choiceKeys]) {
        if (k == 'raw_extracted_text') continue;
        final v = (f[k] ?? '').toString();
        if (v.trim().isNotEmpty) _auto[k] = v;
      }
    }
    final cat = d['catalog'];
    if (cat is Map) {
      _catalog = {
        for (final e in cat.entries)
          e.key.toString(): (e.value is List ? e.value as List : const [])
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList(),
      };
    }
    final vis = d['visible_fields'];
    _visible = vis is List ? vis.map((e) => e.toString()).toList() : const [];
    final rows = d['serial_rows'];
    if (rows is List && rows.isNotEmpty) {
      for (final r in rows.whereType<Map>()) {
        _rows.add(_SnRow(Map<String, dynamic>.from(r)));
      }
    } else {
      _rows.add(_SnRow(const {}));
    }
    final lc = d['lob_candidates'];
    _lobCandidates = lc is List
        ? lc.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : const [];
    final sf = d['stored_files'];
    if (sf is List) {
      _stored.addAll(
        sf.whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
      );
    }
    _focus['line_of_business'] = _lobFocus;
    _lobFocus.addListener(() {
      setState(() => _lobFocused = _lobFocus.hasFocus);
      if (!_lobFocus.hasFocus) {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted && !_lobFocus.hasFocus) {
            setState(() => _lobSuggest = const []);
          }
        });
      }
    });
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkTin());
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    for (final r in _rows) {
      r.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    _lobTimer?.cancel();
    _tinTimer?.cancel();
    _ocrSearch.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool _show(String key) {
    if (_complete) {
      return const [
            'software_name',
            'software_version',
            'acc_number',
            'serial_number',
            'serial_number_type',
            'server_type',
            'brand',
            'model',
          ].contains(key) &&
          _visible.contains(key);
    }
    return _visible.contains(key);
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  String _digits(String v) => v.replaceAll(RegExp(r'[^0-9]'), '');

  GlobalKey _fk(String k) => _fieldKeys.putIfAbsent(k, GlobalKey.new);
  GlobalKey _sk(String k) => _sectionKeys.putIfAbsent(k, GlobalKey.new);
  FocusNode _fn(String k) => _focus.putIfAbsent(k, FocusNode.new);

  void _onTinChanged(String v) {
    if (_c['branch_code']!.text.trim().isEmpty) {
      final d = _digits(v);
      if (d.length > 9) {
        _c['branch_code']!.text = d.substring(9);
      } else if (d.length == 9) {
        _c['branch_code']!.text = '00000';
      }
    }
    _tinTimer?.cancel();
    _tinTimer = Timer(const Duration(milliseconds: 400), _checkTin);
  }

  Future<void> _checkTin() async {
    if (widget.mode != BirReviewMode.add) {
      if (_tinDupMsg.isNotEmpty) setState(() => _tinDupMsg = '');
      return;
    }
    final d = _digits(_c['tin']!.text);
    if (d.length < 9) {
      if (_tinDupMsg.isNotEmpty) setState(() => _tinDupMsg = '');
      return;
    }
    final r = await _svc.checkTin(d, _digits(_c['branch_code']!.text));
    if (!mounted) return;
    setState(() => _tinDupMsg = r.duplicate ? r.message : '');
  }

  List<Map<String, dynamic>> get _versions => _catalog[_software] ?? const [];

  void _applyAcc() {
    for (final v in _versions) {
      if ((v['version'] ?? '').toString() == _version) {
        final acc = (v['acc_number'] ?? '').toString();
        if (acc.isNotEmpty) _c['acc_number']!.text = acc;
      }
    }
  }

  void _onLobTyped(String v) {
    _lobTimer?.cancel();
    if (v.trim().isEmpty) {
      setState(() => _lobSuggest = const []);
      return;
    }
    _lobTimer = Timer(const Duration(milliseconds: 250), () async {
      final list = await _svc.psic(v.trim());
      if (mounted && _c['line_of_business']!.text.trim() == v.trim()) {
        setState(() => _lobSuggest = list);
      }
    });
  }

  void _pickLob(Map<String, dynamic> item) {
    setState(() {
      _c['line_of_business']!.text =
          (item['label'] ?? '${item['code']} - ${item['description']}')
              .toString();
      _hidden['line_of_business_desc'] = (item['description'] ?? '').toString();
      _lobSuggest = const [];
    });
  }

  List<String> _typeOptions(int index) {
    var serverTaken = false, hasSrvTerm = false, hasStandalone = false;
    for (final r in _rows) {
      if (r.type == 'Server') {
        serverTaken = true;
        hasSrvTerm = true;
      } else if (r.type == 'Terminal') {
        hasSrvTerm = true;
      } else if (r.type == 'Standalone') {
        hasStandalone = true;
      }
    }
    final cur = _rows[index].type;
    return [
      if (cur == 'Server' || (!serverTaken && !hasStandalone)) 'Server',
      if (cur == 'Terminal' || !hasStandalone) 'Terminal',
      if (cur == 'Standalone' || !hasSrvTerm) 'Standalone',
    ];
  }

  void _addRow() {
    final row = _SnRow(const {});
    setState(() => _rows.add(row));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = row.key.currentContext;
      if (ctx == null || !mounted) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: const Duration(milliseconds: 250),
      );
    });
  }

  void _onSnChanged(_SnRow row) {
    row.snTimer?.cancel();
    row.suggestTimer?.cancel();
    final sn = row.sn.text.trim();
    row.dbDup = false;
    if (sn.length < 2) _closeSuggest(row);
    if (sn.isEmpty) {
      setState(() => row.dupMsg = '');
      return;
    }
    final inForm = _rows.any(
      (r) => !identical(r, row) && r.sn.text.trim() == sn,
    );
    setState(() {
      row.dupMsg = inForm
          ? 'This serial number is entered more than once.'
          : '';
    });
    if (inForm) {
      _closeSuggest(row);
      _toast(
        'Duplicate serial number "$sn" — each serial number must be unique.',
      );
      return;
    }
    row.snTimer = Timer(const Duration(milliseconds: 500), () async {
      final taken = await _svc.snTaken(sn);
      if (!mounted || row.sn.text.trim() != sn) return;
      setState(() {
        row.dbDup = taken;
        row.dupMsg = taken ? 'This serial number is already in use.' : '';
      });
      if (taken) _toast('Serial number "$sn" is already in use.');
    });
    _fetchSuggest(row);
  }

  void _fetchSuggest(_SnRow row) {
    row.suggestTimer?.cancel();
    final sn = row.sn.text.trim();
    if (sn.length < 2) return;
    row.suggestTimer = Timer(const Duration(milliseconds: 250), () async {
      final type = row.type;
      final list = await _svc.snSuggest(sn, type);
      if (!mounted || row.sn.text.trim() != sn || row.type != type) return;
      setState(() {
        row.suggestions = list;
        row.suggestQuery = sn;
        row.suggestOpen = true;
      });
    });
  }

  void _closeSuggest(_SnRow row) {
    row.suggestTimer?.cancel();
    if (!row.suggestOpen && row.suggestions.isEmpty) return;
    setState(() {
      row.suggestOpen = false;
      row.suggestions = const [];
    });
  }

  void _pickSn(_SnRow row, Map<String, dynamic> item) {
    row.sn.text = (item['serial'] ?? '').toString();
    final t = (item['machine_type'] ?? '').toString();
    final idx = _rows.indexOf(row);
    if (row.type.isEmpty && t.isNotEmpty) {
      final opt = _typeOptions(
        idx,
      ).where((o) => o.toLowerCase() == t.toLowerCase());
      if (opt.isNotEmpty) row.type = opt.first;
    }
    _onSnChanged(row);
    row.suggestTimer?.cancel();
    setState(() {
      row.suggestOpen = false;
      row.suggestions = const [];
    });
  }

  Future<List<PlatformFile>> _pickMany() async {
    try {
      final r = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: const [
          'pdf',
          'jpg',
          'jpeg',
          'png',
          'gif',
          'webp',
          'bmp',
          'doc',
          'docx',
        ],
      );
      return (r?.files ?? const []).where((f) => f.path != null).toList();
    } catch (_) {
      _toast('Could not open the file picker.');
      return const [];
    }
  }

  Future<void> _addDocuments() async {
    final files = await _pickMany();
    if (files.isEmpty) return;
    setState(() {
      _addingDocs = true;
      _previewStatus = 'Identifying and extracting document...';
    });
    for (final f in files) {
      try {
        final r = await _svc.addDocument(f.path!);
        if (!mounted) return;
        final set = r['set'] is Map ? Map<String, dynamic>.from(r['set']) : {};
        setState(() {
          set.forEach((k, v) {
            final s = v.toString();
            if (k == 'registration_type') {
              _registrationType = s;
            } else if (_c.containsKey(k)) {
              _c[k]!.text = s;
            } else {
              _hidden[k] = s;
            }
            if (k != 'raw_extracted_text' &&
                s.trim().isNotEmpty &&
                (_c.containsKey(k) || _choiceKeys.contains(k))) {
              _auto[k] = s;
            }
          });
          final sf = r['stored_file'];
          if (sf is Map) _stored.add(Map<String, dynamic>.from(sf));
        });
        _toast((r['message'] ?? '').toString());
      } on BirRegisterException catch (e) {
        _toast(e.message);
      }
    }
    if (!mounted) return;
    setState(() {
      _addingDocs = false;
      _previewStatus = 'Document analysis complete.';
    });
  }

  Future<void> _attachRequirement() async {
    final files = await _pickMany();
    if (files.isEmpty) return;
    setState(() => _attaching = true);
    for (final f in files) {
      try {
        final s = await _svc.uploadRequirement(f.path!);
        if (!mounted) return;
        setState(() => _requirements.add(s));
        _toast('Requirement attached: ${s['original'] ?? 'file'}');
      } on BirRegisterException catch (e) {
        _toast(e.message);
      }
    }
    if (mounted) setState(() => _attaching = false);
  }

  Future<void> _openFile(Map<String, dynamic> f) async {
    final stored = (f['stored'] ?? '').toString();
    if (stored.isEmpty) return;
    final ok = await launchUrl(
      Uri.parse(_svc.uploadUrl(stored)),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) _toast('Could not open the document.');
  }

  Map<String, dynamic> _formData() {
    return {
      'mode': switch (widget.mode) {
        BirReviewMode.add => 'add',
        BirReviewMode.continueUpload => 'continue',
        BirReviewMode.complete => 'complete',
      },
      if (widget.customerId != null) 'customer_id': widget.customerId,
      'invoice_number': widget.invoiceNumber,
      for (final e in _c.entries) e.key: e.value.text,
      ..._hidden,
      'registration_type': _registrationType,
      'softwarename': _software,
      'software_version': _version,
      'names_edited': _namesEdited,
      'serial_rows': _rows.map((r) => r.toJson()).toList(),
      'document_files': _stored,
      'requirement_files': _requirements,
    };
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _attempted = true);
    if (widget.mode == BirReviewMode.add && _tinDupMsg.isNotEmpty) {
      _toast(
        'This TIN is already registered. Please verify the TIN before saving.',
      );
      if (_show('tin')) _jumpToField('tin');
      return;
    }
    final dupRow = _rows.indexWhere((r) => r.dupMsg.isNotEmpty);
    if (dupRow >= 0) {
      _toast(
        'A serial number is already in use. Please check the highlighted serial number fields.',
      );
      _jumpToRow(dupRow, focusSn: true);
      return;
    }
    setState(() => _saving = true);
    final res = await _svc.review(_formData());
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['status'] != 'success') {
      _toast((res['message'] ?? 'Could not validate the form.').toString());
      final field = (res['field'] ?? '').toString();
      final row = int.tryParse('${res['row'] ?? ''}');
      if (row != null && row >= 0 && row < _rows.length) {
        _jumpToRow(row, focusSn: field == 'sn');
      } else if (field.isNotEmpty) {
        _jumpToField(field);
      }
      return;
    }
    final summary = (res['summary'] is List ? res['summary'] as List : const [])
        .whereType<Map>()
        .toList();
    final empty = int.tryParse('${res['empty_count'] ?? 0}') ?? 0;
    final ok = await _confirmSummary(summary, empty);
    if (ok != true || !mounted) return;
    final payload = (res['payload'] as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    setState(() => _saving = true);
    final update = widget.mode != BirReviewMode.add;
    final r = await _svc.submit(
      update ? 'updateCustomer' : 'addcustomer',
      payload,
    );
    if (!mounted) return;
    if (r['status'] != 'success') {
      setState(() => _saving = false);
      final msg = (r['message'] ?? 'Unknown error').toString();
      _toast(update ? 'Failed to update: $msg' : 'Client Not Added: $msg');
      return;
    }
    var csvPayload = payload;
    final newId = int.tryParse('${r['customer_id'] ?? 0}') ?? 0;
    if (!update && newId > 0) {
      csvPayload = [
        ...payload.where((p) => p['name'] != 'customer_id'),
        {'name': 'customer_id', 'value': '$newId'},
      ];
    }
    try {
      final csv = await _svc.exportCsv(csvPayload);
      final bir = BirDataService(widget.api);
      final local = await bir.downloadPath(csv.url, csv.filename);
      await bir.open(local);
      if (!mounted) return;
      _toast(
        update
            ? 'Registration completed and CSV downloaded.'
            : 'Client added and CSV downloaded as ACCREG_POS_STANDALONE.csv.',
      );
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      if (update) {
        _toast('Registration saved, but CSV download failed.');
        Navigator.of(context).pop(true);
      } else {
        _toast('Client saved, but CSV download failed.');
      }
    }
  }

  Future<bool?> _confirmSummary(List<Map> rows, int empty) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => BirDialogShell(
        title: 'Review Extracted Data',
        icon: Icons.info_outline,
        width: 560,
        onClose: () => Navigator.of(ctx).pop(false),
        footer: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            GhostButton(
              label: 'Go Back & Edit',
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
            const SizedBox(width: 10),
            SignalButton(
              label: 'Confirm & Save',
              icon: Icons.check,
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (empty > 0)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3CD),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFFC107)),
                ),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '$empty field(s) are empty.',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const TextSpan(
                        text:
                            ' You may go back and fill them in before saving.',
                      ),
                    ],
                  ),
                ),
              ),
            Table(
              columnWidths: const {
                0: IntrinsicColumnWidth(),
                1: FlexColumnWidth(),
              },
              children: [
                for (final r in rows)
                  TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 4, 12, 4),
                        child: Text(
                          (r['label'] ?? '').toString(),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: (r['value'] ?? '').toString().isEmpty
                            ? const Text(
                                '(empty)',
                                style: TextStyle(
                                  color: Color(0xFFDC3545),
                                  fontStyle: FontStyle.italic,
                                ),
                              )
                            : Text((r['value'] ?? '').toString()),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _runOcrSearch() {
    final q = _ocrSearch.text.trim().toLowerCase();
    final text = _c['raw_extracted_text']!.text.toLowerCase();
    final out = <int>[];
    if (q.isNotEmpty) {
      var i = text.indexOf(q);
      while (i >= 0) {
        out.add(i);
        i = text.indexOf(q, i + q.length);
      }
    }
    setState(() {
      _ocrMatches = out;
      _ocrIndex = out.isEmpty ? -1 : 0;
    });
    if (q.isNotEmpty) {
      _toast(
        out.isEmpty ? 'No matches found.' : 'Found ${out.length} match(es).',
      );
    }
  }

  List<_Section> get _sections {
    final owner =
        _show('authorized_person') ||
        _show('birthdate') ||
        _show('valid_id_type') ||
        _show('valid_id_source_file');
    return [
      if (!_complete)
        const _Section(
          'docs',
          'Documents',
          Icons.description_outlined,
          'Source files the data was read from',
        ),
      if (!_complete && _businessKeys.any(_show))
        const _Section(
          'business',
          'Business',
          Icons.storefront_outlined,
          'Registration details as printed on BIR Form 2303',
        ),
      if (!_complete && owner)
        const _Section(
          'owner',
          'Owner',
          Icons.badge_outlined,
          'Valid ID holder and personal details',
        ),
      if (!_complete)
        const _Section(
          'contact',
          'Contact',
          Icons.contact_phone_outlined,
          'How we can reach the client',
        ),
      const _Section(
        'software',
        'Software & Hardware',
        Icons.memory,
        'Accredited software and the machines it runs on',
      ),
      if (!_complete)
        const _Section(
          'attachments',
          'Attachments',
          Icons.attach_file,
          'Supporting requirement files',
        ),
    ];
  }

  String _valueOf(String k) => switch (k) {
    'registration_type' => _registrationType,
    'softwarename' => _software,
    'software_version' => _version,
    _ => _c[k]?.text ?? '',
  };

  bool _isAuto(String k) {
    final v = _auto[k];
    if (v == null || v.trim().isEmpty) return false;
    return _valueOf(k) == v;
  }

  List<_Req> _checks() {
    final out = <_Req>[];
    void need(String container, String field, String section, String label) {
      if (!_show(container)) return;
      out.add(
        _Req(
          section,
          field,
          label,
          _valueOf(field).trim().isNotEmpty,
          focus: _focus[field],
        ),
      );
    }

    if (_tinDupMsg.isNotEmpty && _show('tin')) {
      out.add(
        _Req(
          'business',
          'tin',
          'TIN already registered',
          false,
          focus: _fn('tin'),
          error: true,
        ),
      );
    }
    need('companyname', 'companyname', 'business', 'Business Name');
    need('tin', 'tin', 'business', 'TIN');
    need('branch_code', 'branch_code', 'business', 'Branch Code');
    need('rdo', 'rdo', 'business', 'RDO Code');
    need(
      'line_of_business',
      'line_of_business',
      'business',
      'Line of Business',
    );
    need(
      'registration_type',
      'registration_type',
      'business',
      'Registration Type',
    );
    need('address', 'address', 'business', 'Business Address');
    need('authorized_person', 'lastname', 'owner', 'Last Name');
    need('birthdate', 'birthdate', 'owner', 'Birthdate');
    need('software_name', 'softwarename', 'software', 'Software Name');
    if (_versions.isNotEmpty) {
      need(
        'software_version',
        'software_version',
        'software',
        'Software Version',
      );
    }
    need('acc_number', 'acc_number', 'software', 'Accreditation Number');
    if (_show('serial_number')) {
      for (var i = 0; i < _rows.length; i++) {
        final r = _rows[i];
        final n = 'Serial entry ${i + 1}';
        void cell(String part, String label, bool filled, {FocusNode? f}) {
          out.add(
            _Req(
              'software',
              'row:${r.id}:$part',
              '$n: $label',
              filled,
              rowKey: r.key,
              focus: f,
            ),
          );
        }

        if (r.dupMsg.isNotEmpty) {
          out.add(
            _Req(
              'software',
              'row:${r.id}:dup',
              '$n: duplicate serial',
              false,
              rowKey: r.key,
              focus: r.snFocus,
              error: true,
            ),
          );
        }
        if (_show('serial_number_type')) {
          cell('type', 'Type', r.type.trim().isNotEmpty);
        }
        if (r.type == 'Server' && _show('server_type')) {
          cell('server', 'Server Type', r.serverType.trim().isNotEmpty);
        }
        cell('sn', 'Serial Number', r.sn.text.trim().isNotEmpty, f: r.snFocus);
        if (_show('brand')) {
          cell('brand', 'Brand', r.brand.text.trim().isNotEmpty);
        }
        if (_show('model')) {
          cell('model', 'Model', r.model.text.trim().isNotEmpty);
        }
      }
    }
    return out;
  }

  bool _isMissing(String target) => _attempted && _missing.contains(target);

  void _jumpToField(String field) {
    final ctx = _fieldKeys[field]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.2,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    ).then((_) {
      if (mounted) _focus[field]?.requestFocus();
    });
  }

  void _jumpToRow(int i, {bool focusSn = false}) {
    final row = _rows[i];
    final ctx = row.key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.3,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    ).then((_) {
      if (mounted && focusSn) row.snFocus.requestFocus();
    });
  }

  void _jumpTo(_Req r) {
    setState(() => _attempted = true);
    final ctx = (r.rowKey ?? _fieldKeys[r.target])?.currentContext;
    if (ctx == null) {
      _goSection(r.section);
      return;
    }
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.25,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    ).then((_) {
      if (mounted) r.focus?.requestFocus();
    });
  }

  void _goSection(String id) {
    final ctx = _sectionKeys[id]?.currentContext;
    if (ctx == null) return;
    setState(() {
      _active = id;
      _navLock = true;
    });
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    ).whenComplete(() => _navLock = false);
  }

  void _onScroll() {
    final vp = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (_navLock || vp == null || !vp.attached || !_scroll.hasClients) {
      return;
    }
    final secs = _sections;
    if (secs.isEmpty) return;
    String? active;
    for (final s in secs) {
      final box =
          _sectionKeys[s.id]?.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final dy = box.localToGlobal(Offset.zero, ancestor: vp).dy;
      if (dy <= 140) active = s.id;
    }
    final p = _scroll.position;
    if (p.pixels >= p.maxScrollExtent - 4) active = secs.last.id;
    active ??= secs.first.id;
    if (active != _active) setState(() => _active = active!);
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final screen = MediaQuery.sizeOf(context);
    final inset = screen.width < 900 || screen.height < 640 ? 12.0 : 28.0;
    final w = math.min(_complete ? 980.0 : 1200.0, screen.width - inset * 2);
    final h = math.min(1040.0, screen.height - inset * 2);
    final checks = _checks();
    _missing = {
      for (final c in checks)
        if (!c.filled && !c.error) c.target,
    };
    final issues = checks.where((c) => !c.filled).toList();
    final secs = _sections;
    if (_active.isEmpty && secs.isNotEmpty) _active = secs.first.id;
    final showNav = w >= 1000 && secs.length > 2;
    return PopScope(
      canPop: !_saving,
      child: Dialog(
        insetPadding: EdgeInsets.all(inset),
        backgroundColor: b.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: w,
          height: h,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(w),
              Divider(height: 1, color: b.rule),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showNav) _nav(secs, checks),
                    Expanded(child: _form(secs, w < 700)),
                  ],
                ),
              ),
              _footer(issues, w < 700),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(double w) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final pill = switch (widget.mode) {
      BirReviewMode.add => 'New customer',
      BirReviewMode.continueUpload => 'Continue registration',
      BirReviewMode.complete => 'Complete registration',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
      child: Row(
        children: [
          IconTile(
            icon: _complete ? Icons.memory : Icons.fact_check_outlined,
            size: 40,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _complete
                      ? 'Complete Registration'
                      : 'Extracted Data Preview',
                  style: text.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _complete
                      ? 'Add the software and hardware details to finish this registration'
                      : 'Review what was read from the documents before saving',
                  style: text.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (w >= 640) ...[
            const SizedBox(width: 12),
            StatusPill(label: pill, color: Brand.signal),
          ],
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Close',
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            icon: Icon(Icons.close, size: 20, color: b.paperDim),
          ),
        ],
      ),
    );
  }

  Widget _nav(List<_Section> secs, List<_Req> checks) {
    final b = context.brand;
    final req = checks.where((c) => !c.error).toList();
    final done = req.where((c) => c.filled).length;
    final total = req.length;
    return Container(
      width: 236,
      decoration: BoxDecoration(
        color: b.surfaceHi,
        border: Border(right: BorderSide(color: b.rule)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 16, 8),
            child: Text(
              'SECTIONS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.9,
                color: b.paperDim,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: [for (final s in secs) _navItem(s, checks)],
            ),
          ),
          if (total > 0)
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: b.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: b.rule),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Required fields',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: b.paper,
                          ),
                        ),
                      ),
                      Text(
                        '$done / $total',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: done == total ? Brand.success : Brand.signal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: total == 0 ? 1 : done / total,
                      minHeight: 6,
                      backgroundColor: b.rule,
                      color: done == total ? Brand.success : Brand.signal,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _navItem(_Section s, List<_Req> checks) {
    final b = context.brand;
    final active = _active == s.id;
    final mine = checks.where((c) => c.section == s.id).toList();
    final bad = mine.where((c) => !c.filled).length;
    Widget? trail;
    if (bad > 0) {
      trail = _countPill('$bad', Brand.danger);
    } else if (mine.isNotEmpty) {
      trail = const Icon(Icons.check_circle, size: 17, color: Brand.success);
    } else if (s.id == 'docs' && _stored.isNotEmpty) {
      trail = _countPill('${_stored.length}', b.paperDim);
    } else if (s.id == 'attachments' && _requirements.isNotEmpty) {
      trail = _countPill('${_requirements.length}', b.paperDim);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: active
            ? Brand.signal.withValues(alpha: 0.10)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _goSection(s.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 18,
                  decoration: BoxDecoration(
                    color: active ? Brand.signal : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  s.icon,
                  size: 17,
                  color: active ? Brand.signal : b.paperDim,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    s.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                      color: active ? b.paper : b.paper.withValues(alpha: 0.82),
                    ),
                  ),
                ),
                ?trail,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _countPill(String t, Color c) => Container(
    constraints: const BoxConstraints(minWidth: 22),
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.13),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      t,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: c),
    ),
  );

  Widget _form(List<_Section> secs, bool narrow) {
    final b = context.brand;
    final pad = narrow ? 14.0 : 24.0;
    final has = {for (final s in secs) s.id: s};
    Widget sec(String id, Widget body, {Widget? trailing}) =>
        _sectionCard(has[id]!, body, trailing: trailing);
    return Container(
      key: _viewportKey,
      color: b.canvas,
      child: Scrollbar(
        controller: _scroll,
        child: SingleChildScrollView(
          controller: _scroll,
          padding: EdgeInsets.fromLTRB(pad, 20, pad, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_complete) ...[_summaryCard(), const SizedBox(height: 16)],
              if (!_complete) ...[_notice(), const SizedBox(height: 16)],
              if (has.containsKey('docs')) sec('docs', _documents()),
              if (has.containsKey('business')) sec('business', _entity()),
              if (has.containsKey('owner')) sec('owner', _ownership()),
              if (has.containsKey('contact')) sec('contact', _contact()),
              sec('software', _software_()),
              if (has.containsKey('attachments'))
                sec('attachments', _attachments()),
              if (!_complete)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'By confirming, all extracted data will be saved to the database and a formatted CSV will be generated for BIR submission.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionCard(_Section s, Widget body, {Widget? trailing}) {
    final b = context.brand;
    return Container(
      key: _sk(s.id),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: b.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: b.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
            child: Row(
              children: [
                IconTile(icon: s.icon, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        s.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: b.paper,
                        ),
                      ),
                      Text(
                        s.hint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 10), trailing],
              ],
            ),
          ),
          Divider(height: 1, color: b.rule),
          Padding(padding: const EdgeInsets.all(18), child: body),
        ],
      ),
    );
  }

  Widget _footer(List<_Req> issues, bool narrow) {
    final b = context.brand;
    final missing = issues.where((i) => !i.error).length;
    final errors = issues.where((i) => i.error).length;
    Widget status;
    if (issues.isEmpty) {
      status = Row(
        children: [
          const Icon(Icons.check_circle, size: 18, color: Brand.success),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'All required fields are filled',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: b.paper,
              ),
            ),
          ),
        ],
      );
    } else {
      final parts = [
        if (missing > 0)
          '$missing required field${missing == 1 ? '' : 's'} missing',
        if (errors > 0) '$errors error${errors == 1 ? '' : 's'}',
      ];
      status = Tooltip(
        message: issues.map((i) => i.label).take(12).join('\n'),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => _jumpTo(issues.first),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Row(
              children: [
                const Icon(Icons.error_outline, size: 18, color: Brand.danger),
                const SizedBox(width: 8),
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: parts.join(' · '),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Brand.danger,
                          ),
                        ),
                        const TextSpan(text: '   '),
                        const TextSpan(
                          text: 'Review',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Brand.signal,
                            decoration: TextDecoration.underline,
                            decorationColor: Brand.signal,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: b.surfaceHi,
        border: Border(top: BorderSide(color: b.rule)),
      ),
      padding: EdgeInsets.fromLTRB(narrow ? 14 : 20, 12, narrow ? 14 : 20, 12),
      child: Row(
        children: [
          Expanded(child: status),
          const SizedBox(width: 12),
          GhostButton(
            label: 'Cancel',
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 10),
          SignalButton(
            label: _complete
                ? (narrow ? 'Complete' : 'Complete & export CSV')
                : (narrow ? 'Save' : 'Save customer'),
            icon: _complete ? Icons.check : Icons.save_outlined,
            busy: _saving,
            onPressed: _save,
          ),
        ],
      ),
    );
  }

  Widget _notice() {
    final b = context.brand;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Brand.danger.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Brand.danger.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const IconTile(
            icon: Icons.warning_amber_rounded,
            size: 32,
            color: Brand.danger,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'MANDATORY: YOU MUST REVIEW & EDIT ALL DATA BELOW',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 0.3,
                    color: Color(0xFFB91C1C),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Our Artificial Intelligence has successfully digitized your identification documents; however, automated extraction is a technical interpretation and is not absolute. It is YOUR LEGAL RESPONSIBILITY as the authorized representative to REVIEW AND EDIT every single character before final submission. Meticulously verify the extracted Business Name, TIN, and Registration Address against your physical BIR Form 2303. Absolute precision is mandatory to guarantee total data integrity for your compliance records.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: b.paper.withValues(alpha: 0.82),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard() {
    final b = context.brand;
    final s = widget.data['summary'] is Map
        ? Map<String, dynamic>.from(widget.data['summary'])
        : const <String, dynamic>{};
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Brand.signal.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Brand.signal.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const IconTile(icon: Icons.storefront_outlined, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'COMPLETING REGISTRATION FOR',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: Brand.signal,
                  ),
                ),
                Text(
                  (s['name'] ?? '—').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: b.paper,
                  ),
                ),
                Text.rich(
                  TextSpan(
                    style: TextStyle(fontSize: 13, color: b.paperDim),
                    children: [
                      const TextSpan(
                        text: 'TIN: ',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(text: (s['tin'] ?? '—').toString()),
                      const TextSpan(
                        text: '    Branch: ',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(text: (s['branch'] ?? '—').toString()),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (widget.onViewDetails != null) ...[
            const SizedBox(width: 12),
            GhostButton(
              label: 'View details',
              icon: Icons.visibility_outlined,
              onPressed: widget.onViewDetails,
            ),
          ],
        ],
      ),
    );
  }

  Widget _documents() {
    final b = context.brand;
    final docs = [
      for (final f in _filesOfType(false)) (f, 'Business document'),
      if (_show('authorized_person'))
        for (final f in _filesOfType(true)) (f, 'Valid ID'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _addingDocs ? null : _addDocuments,
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
              icon: _addingDocs
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: TpLoader(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_circle_outline, size: 16),
              label: Text(_addingDocs ? 'Analyzing...' : 'Add documents'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _previewStatus,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (docs.isEmpty)
          Text(
            'No source documents attached.',
            style: TextStyle(fontSize: 13, color: b.paperDim),
          )
        else
          _tiles([
            for (final d in docs)
              _fileTile(
                d.$1,
                d.$2,
                d.$2 == 'Valid ID' ? Icons.badge_outlined : Icons.description,
              ),
          ]),
        if (_show('raw_text')) ...[const SizedBox(height: 16), _ocrLog()],
      ],
    );
  }

  Widget _tiles(List<Widget> tiles) => LayoutBuilder(
    builder: (ctx, c) {
      const gap = 12.0;
      final per = c.maxWidth >= 860
          ? 3
          : c.maxWidth >= 520
          ? 2
          : 1;
      final tw = ((c.maxWidth - gap * (per - 1)) / per).floorToDouble();
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final t in tiles) SizedBox(width: tw, child: t)],
      );
    },
  );

  Widget _ocrLog() {
    final b = context.brand;
    final text = _c['raw_extracted_text']!.text;
    final q = _ocrSearch.text.trim();
    final spans = <TextSpan>[];
    if (_ocrMatches.isEmpty || q.isEmpty) {
      spans.add(TextSpan(text: text));
    } else {
      var pos = 0;
      for (var i = 0; i < _ocrMatches.length; i++) {
        final m = _ocrMatches[i];
        spans.add(TextSpan(text: text.substring(pos, m)));
        spans.add(
          TextSpan(
            text: text.substring(m, m + q.length),
            style: TextStyle(
              backgroundColor: i == _ocrIndex
                  ? Brand.signal
                  : const Color(0xFFFFE08A),
              color: i == _ocrIndex ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
        );
        pos = m + q.length;
      }
      spans.add(TextSpan(text: text.substring(pos)));
    }
    final lines = text.trim().isEmpty
        ? 0
        : '\n'.allMatches(text.trim()).length + 1;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: b.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _ocrOpen = !_ocrOpen),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.text_snippet_outlined,
                    size: 17,
                    color: b.paperDim,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'OCR extraction log',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: b.paper,
                      ),
                    ),
                  ),
                  Text(
                    lines == 0 ? 'Empty' : '$lines lines',
                    style: TextStyle(fontSize: 12, color: b.paperDim),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    _ocrOpen ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: b.paperDim,
                  ),
                ],
              ),
            ),
          ),
          if (_ocrOpen) ...[
            Divider(height: 1, color: b.rule),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ocrSearch,
                          onSubmitted: (_) => _runOcrSearch(),
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: 'Search word in OCR Extraction Log...',
                            prefixIcon: Icon(Icons.search, size: 18),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      TextButton(
                        onPressed: _runOcrSearch,
                        child: const Text('Search'),
                      ),
                      IconButton(
                        tooltip: 'Previous',
                        onPressed: _ocrMatches.isEmpty
                            ? null
                            : () => setState(
                                () => _ocrIndex =
                                    (_ocrIndex - 1 + _ocrMatches.length) %
                                    _ocrMatches.length,
                              ),
                        icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                      ),
                      IconButton(
                        tooltip: 'Next',
                        onPressed: _ocrMatches.isEmpty
                            ? null
                            : () => setState(
                                () => _ocrIndex =
                                    (_ocrIndex + 1) % _ocrMatches.length,
                              ),
                        icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                      ),
                      Text(
                        '${_ocrMatches.isEmpty ? 0 : _ocrIndex + 1} / ${_ocrMatches.length}',
                        style: TextStyle(fontSize: 12.5, color: b.paperDim),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    height: 220,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText.rich(
                        TextSpan(
                          style: const TextStyle(
                            color: Color(0xFFE2E8F0),
                            fontFamily: 'monospace',
                            fontSize: 12,
                            height: 1.45,
                          ),
                          children: spans,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _label(String t, {bool required = false, String? autoKey}) {
    final b = context.brand;
    final auto = autoKey != null && _isAuto(autoKey);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SizedBox(
        height: 18,
        child: Row(
          children: [
            Flexible(
              child: Text.rich(
                TextSpan(
                  text: t,
                  children: [
                    if (required)
                      const TextSpan(
                        text: ' *',
                        style: TextStyle(color: Brand.danger),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: b.paper.withValues(alpha: 0.78),
                ),
              ),
            ),
            if (auto) ...[const SizedBox(width: 8), _autoTag()],
          ],
        ),
      ),
    );
  }

  Widget _autoTag() {
    final label = widget.mode == BirReviewMode.add ? 'Extracted' : 'Prefilled';
    return Tooltip(
      message: 'Filled in automatically. Verify it against the documents.',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: Brand.signal.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, size: 10, color: Brand.signal),
            const SizedBox(width: 3),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Brand.signal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _deco({
    String? hint,
    bool readOnly = false,
    bool auto = false,
    bool error = false,
    Widget? suffix,
    Widget? prefix,
  }) {
    final b = context.brand;
    OutlineInputBorder ob(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: BorderSide(color: c, width: w),
    );
    return InputDecoration(
      isDense: true,
      hintText: hint,
      filled: true,
      fillColor: readOnly
          ? b.surfaceHi
          : auto
          ? Brand.signal.withValues(alpha: 0.035)
          : b.surface,
      enabledBorder: error
          ? ob(Brand.danger)
          : auto
          ? ob(Brand.signal.withValues(alpha: 0.28))
          : null,
      focusedBorder: error ? ob(Brand.danger, 1.5) : null,
      suffixIcon: suffix,
      prefixIcon: prefix,
    );
  }

  Widget _errText(String t) => Padding(
    padding: const EdgeInsets.only(top: 5),
    child: Text(
      t,
      style: const TextStyle(
        color: Brand.danger,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _field(
    String label,
    String key, {
    String? hint,
    int maxLines = 1,
    bool readOnly = false,
    bool required = false,
    ValueChanged<String>? onChanged,
    List<TextInputFormatter>? formatters,
    String? error,
    IconData? icon,
  }) {
    final missing = _isMissing(key);
    final err = error != null && error.isNotEmpty
        ? error
        : missing
        ? 'Required'
        : null;
    final auto = !readOnly && _isAuto(key);
    return KeyedSubtree(
      key: _fk(key),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _label(label, required: required, autoKey: readOnly ? null : key),
          TextField(
            controller: _c[key],
            focusNode: _fn(key),
            readOnly: readOnly,
            maxLines: maxLines,
            minLines: 1,
            onChanged: (v) {
              onChanged?.call(v);
              setState(() {});
            },
            inputFormatters: formatters,
            decoration: _deco(
              hint: hint,
              readOnly: readOnly,
              auto: auto,
              error: err != null,
              prefix: icon == null ? null : Icon(icon, size: 17),
            ),
          ),
          if (err != null) _errText(err),
        ],
      ),
    );
  }

  Widget _dropdown({
    required String label,
    required String target,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?>? onChanged,
    Key? key,
    bool required = false,
  }) {
    final missing = _isMissing(target);
    return KeyedSubtree(
      key: _fk(target),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _label(label, required: required, autoKey: target),
          DropdownButtonFormField<String>(
            key: key,
            initialValue: value,
            isDense: true,
            isExpanded: true,
            decoration: _deco(auto: _isAuto(target), error: missing),
            items: items,
            onChanged: onChanged,
          ),
          if (missing) _errText('Required'),
        ],
      ),
    );
  }

  Widget _grid(List<(int, Widget)> cells) {
    return LayoutBuilder(
      builder: (ctx, c) {
        const gap = 16.0;
        final w = c.maxWidth;
        int span(int s) => w < 520
            ? 12
            : w < 760
            ? (s <= 6 ? 6 : 12)
            : s;
        final unit = (w - 11 * gap) / 12;
        return Wrap(
          spacing: gap,
          runSpacing: 18,
          children: [
            for (final cell in cells)
              SizedBox(
                width: (unit * span(cell.$1) + gap * (span(cell.$1) - 1))
                    .floorToDouble(),
                child: cell.$2,
              ),
          ],
        );
      },
    );
  }

  List<Map<String, dynamic>> _filesOfType(bool validId) => _stored
      .where(
        (f) => (f['is_valid_id'] == true || f['_docType'] == 'ID') == validId,
      )
      .toList();

  Widget _fileTile(
    Map<String, dynamic> f,
    String title,
    IconData icon, {
    VoidCallback? onRemove,
  }) {
    final b = context.brand;
    final name = (f['original'] ?? f['stored'] ?? '').toString();
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    final stored = (f['stored'] ?? '').toString();
    final isPdf = ext == 'pdf';
    final isDoc = ext == 'doc' || ext == 'docx';
    final tint = isPdf
        ? const Color(0xFFEF4444)
        : isDoc
        ? Brand.info
        : Brand.signal;
    final fallback = Container(
      color: tint.withValues(alpha: 0.12),
      alignment: Alignment.center,
      child: Icon(
        isPdf
            ? Icons.picture_as_pdf
            : isDoc
            ? Icons.article_outlined
            : icon,
        color: tint,
        size: 22,
      ),
    );
    return Material(
      color: b.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => _openFile(f),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: b.rule),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: _imageExt.contains(ext) && stored.isNotEmpty
                      ? Image.network(
                          _svc.uploadUrl(stored),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => fallback,
                        )
                      : fallback,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: b.paperDim,
                      ),
                    ),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: b.paper,
                      ),
                    ),
                    Text(
                      ext.isEmpty ? 'File' : ext.toUpperCase(),
                      style: TextStyle(fontSize: 11, color: b.paperDim),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'View',
                visualDensity: VisualDensity.compact,
                onPressed: () => _openFile(f),
                icon: const Icon(
                  Icons.open_in_new,
                  size: 17,
                  color: Brand.signal,
                ),
              ),
              if (onRemove != null)
                IconButton(
                  tooltip: 'Remove',
                  visualDensity: VisualDensity.compact,
                  onPressed: onRemove,
                  icon: Icon(Icons.close, size: 17, color: b.paperDim),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _lobField() {
    final b = context.brand;
    final showDetected =
        _lobFocused &&
        _c['line_of_business']!.text.trim().isEmpty &&
        _lobCandidates.isNotEmpty;
    final list = showDetected ? _lobCandidates : _lobSuggest;
    final currentCode =
        RegExp(
          r'\b(\d{4,5})\b',
        ).firstMatch(_c['line_of_business']!.text)?.group(1) ??
        '';
    var rec = _lobCandidates.indexWhere(
      (e) => (e['code'] ?? '').toString() == currentCode,
    );
    if (rec < 0) rec = 0;
    final missing = _isMissing('line_of_business');
    return KeyedSubtree(
      key: _fk('line_of_business'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _label(
            'Line of Business (PSIC)',
            required: true,
            autoKey: 'line_of_business',
          ),
          TextField(
            controller: _c['line_of_business'],
            focusNode: _lobFocus,
            onChanged: (v) {
              _onLobTyped(v);
              setState(() {});
            },
            decoration: _deco(
              hint: 'Search PSIC code or description',
              auto: _isAuto('line_of_business'),
              error: missing,
              prefix: const Icon(Icons.search, size: 17),
            ),
          ),
          if (missing) _errText('Required'),
          if (list.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(
                color: b.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: b.rule),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: [
                  if (showDetected)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: Text(
                        'DETECTED ON DOCUMENT',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: b.paperDim,
                        ),
                      ),
                    ),
                  for (final item in list)
                    InkWell(
                      onTap: () => _pickLob(item),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Text((item['label'] ?? '').toString()),
                      ),
                    ),
                ],
              ),
            ),
          if (_lobCandidates.length >= 2)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Brand.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Brand.warning.withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'MULTIPLE PSIC DETECTED — CONFIRM THE CORRECT LINE OF BUSINESS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFB45309),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (var i = 0; i < _lobCandidates.length; i++)
                        ChoiceChip(
                          selected: i == rec,
                          showCheckmark: false,
                          visualDensity: VisualDensity.compact,
                          selectedColor: const Color(0xFFF97316),
                          label: Text(
                            '${_lobCandidates[i]['label']}${i == rec ? ' (Recommended)' : ''}',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: i == rec
                                  ? Colors.white
                                  : const Color(0xFF9A3412),
                            ),
                          ),
                          onSelected: (_) => _pickLob(_lobCandidates[i]),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _entity() {
    return _grid([
      if (_show('companyname'))
        (8, _field('Business Name', 'companyname', required: true)),
      if (_show('registration_type'))
        (
          4,
          _dropdown(
            label: 'Registration Type',
            target: 'registration_type',
            required: true,
            value: ['VAT', 'NON-VAT'].contains(_registrationType)
                ? _registrationType
                : '',
            items: const [
              DropdownMenuItem(
                value: '',
                child: Text('Select registration type'),
              ),
              DropdownMenuItem(value: 'VAT', child: Text('VAT')),
              DropdownMenuItem(value: 'NON-VAT', child: Text('NON-VAT')),
            ],
            onChanged: (v) => setState(() => _registrationType = v ?? ''),
          ),
        ),
      if (_show('tin'))
        (
          4,
          _field(
            'TIN (Taxpayer Identification No.)',
            'tin',
            required: true,
            onChanged: _onTinChanged,
            error: _tinDupMsg,
          ),
        ),
      if (_show('branch_code'))
        (
          4,
          _field(
            'Branch Code',
            'branch_code',
            required: true,
            onChanged: (_) {
              _tinTimer?.cancel();
              _tinTimer = Timer(const Duration(milliseconds: 400), _checkTin);
            },
          ),
        ),
      if (_show('rdo')) (4, _field('RDO Code', 'rdo', required: true)),
      if (_show('tin_issuance_date'))
        (
          4,
          _field(
            'TIN Issuance Date',
            'tin_issuance_date',
            hint: 'e.g. November 25, 2021',
          ),
        ),
      if (_show('line_of_business'))
        (_show('tin_issuance_date') ? 8 : 12, _lobField()),
      if (_show('address'))
        (
          12,
          _field('Business Address', 'address', maxLines: 3, required: true),
        ),
    ]);
  }

  Widget _ownership() {
    void nameEdited(String _) => _namesEdited = true;
    return _grid([
      if (_show('authorized_person')) ...[
        (
          4,
          _field(
            'Last Name',
            'lastname',
            required: true,
            onChanged: nameEdited,
          ),
        ),
        (4, _field('First Name', 'firstname', onChanged: nameEdited)),
        (4, _field('Middle Name', 'middlename', onChanged: nameEdited)),
      ],
      if (_show('birthdate'))
        (
          4,
          _field(
            'Birthdate (MM/DD/YYYY)',
            'birthdate',
            hint: 'MM/DD/YYYY',
            required: true,
            icon: Icons.cake_outlined,
            formatters: [_BirthdateFormatter()],
          ),
        ),
      if (_show('valid_id_type'))
        (4, _field('Detected Valid ID Type', 'valid_id_type', readOnly: true)),
      if (_show('valid_id_source_file'))
        (
          4,
          _field(
            'Detected Valid ID Source File',
            'valid_id_source_file',
            readOnly: true,
          ),
        ),
    ]);
  }

  Widget _contact() => _grid([
    (
      6,
      _field(
        'Phone Number',
        'phone_number',
        hint: '09XX XXX XXXX',
        icon: Icons.phone_outlined,
      ),
    ),
    (
      6,
      _field(
        'Email Address',
        'email_address',
        hint: 'name@example.com',
        icon: Icons.mail_outline,
      ),
    ),
  ]);

  Widget _software_() {
    final b = context.brand;
    final versions = _versions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _grid([
          if (_show('software_name'))
            (
              4,
              _dropdown(
                label: 'Software Name',
                target: 'softwarename',
                required: true,
                key: ValueKey('sw-$_software'),
                value: _catalog.containsKey(_software) ? _software : '',
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('-- Select Software --'),
                  ),
                  for (final n in _catalog.keys)
                    DropdownMenuItem(value: n, child: Text(n)),
                ],
                onChanged: (v) => setState(() {
                  _software = v ?? '';
                  final vs = _versions;
                  _version = vs.isEmpty
                      ? ''
                      : (vs.first['version'] ?? '').toString();
                  _applyAcc();
                }),
              ),
            ),
          if (_show('software_version'))
            (
              4,
              _dropdown(
                label: 'Software Version',
                target: 'software_version',
                required: versions.isNotEmpty,
                key: ValueKey('ver-$_software-$_version'),
                value: versions.any((v) => v['version'].toString() == _version)
                    ? _version
                    : '',
                items: [
                  if (versions.isEmpty)
                    DropdownMenuItem(
                      value: '',
                      child: Text(
                        _software.isEmpty
                            ? '-- Select Version --'
                            : '-- No version configured --',
                      ),
                    ),
                  for (final v in versions)
                    DropdownMenuItem(
                      value: v['version'].toString(),
                      child: Text(v['version'].toString()),
                    ),
                ],
                onChanged: versions.isEmpty
                    ? null
                    : (v) => setState(() {
                        _version = v ?? '';
                        _applyAcc();
                      }),
              ),
            ),
          (
            _show('software_name') && _show('software_version')
                ? 4
                : _show('software_name') || _show('software_version')
                ? 8
                : 12,
            _field(
              'Accreditation Number',
              'acc_number',
              required: _show('acc_number'),
            ),
          ),
        ]),
        if (_show('serial_number')) ...[
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: 'Serial Number Entries',
                    children: [
                      TextSpan(
                        text: '   ${_rows.length}',
                        style: TextStyle(
                          color: b.paperDim,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: b.paper,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _addRow,
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36)),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add serial'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _serialTable(),
        ],
      ],
    );
  }

  Widget _combo(
    TextEditingController c,
    String hint,
    List<String> options, {
    Key? key,
    bool error = false,
  }) {
    return Autocomplete<String>(
      key: key,
      initialValue: TextEditingValue(text: c.text),
      optionsBuilder: (v) {
        final q = v.text.toLowerCase();
        return options.where((o) => q.isEmpty || o.toLowerCase().contains(q));
      },
      onSelected: (v) => setState(() => c.text = v),
      fieldViewBuilder: (ctx, ctrl, focus, submit) {
        return TextField(
          controller: ctrl,
          focusNode: focus,
          onChanged: (v) {
            c.text = v;
            setState(() {});
          },
          decoration: _deco(
            hint: hint,
            error: error,
            suffix: const Icon(Icons.expand_more, size: 18),
          ),
        );
      },
    );
  }

  Widget _typeDrop(_SnRow row, List<String> opts) =>
      DropdownButtonFormField<String>(
        key: ValueKey('t-${row.id}-${row.type}-${opts.join()}'),
        initialValue: opts.contains(row.type) ? row.type : '',
        isDense: true,
        isExpanded: true,
        decoration: _deco(error: _isMissing('row:${row.id}:type')),
        items: [
          const DropdownMenuItem(
            value: '',
            child: Text(
              'Select type',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          for (final o in opts)
            DropdownMenuItem(
              value: o,
              child: Text(o, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) {
          setState(() {
            row.type = v ?? '';
            if (row.type != 'Server') row.serverType = '';
          });
          if (row.suggestOpen) _fetchSuggest(row);
        },
      );

  Widget _serverDrop(_SnRow row) => DropdownButtonFormField<String>(
    key: ValueKey('s-${row.id}'),
    initialValue: ['Consolidator', 'Global'].contains(row.serverType)
        ? row.serverType
        : '',
    isDense: true,
    isExpanded: true,
    decoration: _deco(error: _isMissing('row:${row.id}:server')),
    items: const [
      DropdownMenuItem(
        value: '',
        child: Text(
          'Select server type',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      DropdownMenuItem(
        value: 'Consolidator',
        child: Text(
          'Consolidator',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      DropdownMenuItem(value: 'Global', child: Text('Global')),
    ],
    onChanged: (v) => setState(() => row.serverType = v ?? ''),
  );

  Widget _snInput(_SnRow row) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          _closeSuggest(row),
    },
    child: TextField(
      controller: row.sn,
      focusNode: row.snFocus,
      groupId: row.key,
      onTapOutside: (_) => _closeSuggest(row),
      onChanged: (_) => _onSnChanged(row),
      decoration: _deco(
        hint: row.type.isEmpty
            ? 'Serial Number'
            : 'Search ${row.type == 'Standalone' ? 'Server / Terminal' : row.type} serial',
        error: row.dupMsg.isNotEmpty || _isMissing('row:${row.id}:sn'),
      ),
    ),
  );

  Widget _brandInput(_SnRow row) => _combo(
    row.brand,
    'Brand',
    _brands,
    key: ValueKey('b-${row.id}'),
    error: _isMissing('row:${row.id}:brand'),
  );

  Widget _modelInput(_SnRow row) => _combo(
    row.model,
    'Model',
    _models,
    key: ValueKey('m-${row.id}'),
    error: _isMissing('row:${row.id}:model'),
  );

  Widget _removeBtn(int i) => IconButton(
    tooltip: i == 0 ? 'The first entry cannot be removed' : 'Remove',
    onPressed: i == 0
        ? null
        : () {
            final r = _rows[i];
            setState(() => _rows.removeAt(i));
            WidgetsBinding.instance.addPostFrameCallback((_) => r.dispose());
          },
    icon: Icon(
      Icons.delete_outline,
      size: 19,
      color: i == 0 ? context.brand.rule : Brand.danger,
    ),
  );

  Widget _serialTable() {
    final b = context.brand;
    final showType = _show('serial_number_type');
    final showServer =
        _show('server_type') && _rows.any((r) => r.type == 'Server');
    final showBrand = _show('brand');
    final showModel = _show('model');
    return LayoutBuilder(
      builder: (ctx, c) {
        if (c.maxWidth < 700) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < _rows.length; i++)
                _snCard(i, showType, showBrand, showModel),
            ],
          );
        }
        Widget head(String t, {bool req = false}) => Text.rich(
          TextSpan(
            text: t,
            children: [
              if (req)
                const TextSpan(
                  text: ' *',
                  style: TextStyle(color: Brand.danger),
                ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: b.paperDim,
          ),
        );
        List<Widget> cells(List<(String, int, Widget)> xs) => [
          for (var k = 0; k < xs.length; k++) ...[
            if (k > 0) const SizedBox(width: 10),
            Expanded(key: ValueKey(xs[k].$1), flex: xs[k].$2, child: xs[k].$3),
          ],
        ];
        return Container(
          decoration: BoxDecoration(
            color: b.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: b.rule),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: b.surfaceHi,
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Row(
                  children: [
                    SizedBox(width: 30, child: head('#')),
                    ...cells([
                      if (showType) ('type', 3, head('TYPE', req: true)),
                      if (showServer)
                        ('server', 4, head('SERVER TYPE', req: true)),
                      ('sn', 4, head('SERIAL NUMBER', req: true)),
                      if (showBrand) ('brand', 3, head('BRAND', req: true)),
                      if (showModel) ('model', 3, head('MODEL', req: true)),
                    ]),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              for (var i = 0; i < _rows.length; i++) ...[
                Divider(height: 1, color: b.rule),
                KeyedSubtree(
                  key: _rows[i].key,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            SizedBox(
                              width: 30,
                              child: Text(
                                '${i + 1}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: b.paperDim,
                                ),
                              ),
                            ),
                            ...cells([
                              if (showType)
                                (
                                  'type',
                                  3,
                                  _typeDrop(_rows[i], _typeOptions(i)),
                                ),
                              if (showServer)
                                (
                                  'server',
                                  4,
                                  _rows[i].type == 'Server'
                                      ? _serverDrop(_rows[i])
                                      : Text(
                                          '—',
                                          style: TextStyle(color: b.paperDim),
                                        ),
                                ),
                              ('sn', 4, _snInput(_rows[i])),
                              if (showBrand)
                                ('brand', 3, _brandInput(_rows[i])),
                              if (showModel)
                                ('model', 3, _modelInput(_rows[i])),
                            ]),
                            const SizedBox(width: 6),
                            SizedBox(width: 42, child: _removeBtn(i)),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 30, right: 48),
                          child: _snExtras(_rows[i]),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _snCard(int i, bool showType, bool showBrand, bool showModel) {
    final b = context.brand;
    final row = _rows[i];
    Widget labeled(String l, Widget w, {bool req = true}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _label(l, required: req),
        w,
      ],
    );
    return Container(
      key: row.key,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 12),
      decoration: BoxDecoration(
        color: b.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: b.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Entry ${i + 1}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: b.paper,
                  ),
                ),
              ),
              _removeBtn(i),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: _grid([
              if (showType)
                (6, labeled('Type', _typeDrop(row, _typeOptions(i)))),
              if (row.type == 'Server' && _show('server_type'))
                (6, labeled('Server Type', _serverDrop(row))),
              (12, labeled('Serial Number', _snInput(row))),
              if (showBrand) (6, labeled('Brand', _brandInput(row))),
              if (showModel) (6, labeled('Model', _modelInput(row))),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: _snExtras(row),
          ),
        ],
      ),
    );
  }

  Widget _snExtras(_SnRow row) {
    final b = context.brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (row.dupMsg.isNotEmpty) _errText(row.dupMsg),
        if (row.suggestOpen && row.suggestions.isEmpty)
          TapRegion(
            groupId: row.key,
            child: Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: b.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: b.rule),
              ),
              child: Text(
                'No ${row.type == 'Standalone' ? 'Server or Terminal ' : (row.type.isEmpty ? '' : '${row.type} ')}license serial matches "${row.suggestQuery}"',
                style: TextStyle(fontSize: 12.5, color: b.paperDim),
              ),
            ),
          ),
        if (row.suggestOpen && row.suggestions.isNotEmpty)
          TapRegion(
            groupId: row.key,
            child: Container(
              margin: const EdgeInsets.only(top: 6),
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: b.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: b.rule),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: [
                  for (final s in row.suggestions)
                    InkWell(
                      onTap: () => _pickSn(row, s),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  (s['serial'] ?? '').toString(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if ((s['assigned_to'] ?? '')
                                    .toString()
                                    .isNotEmpty)
                                  _badge(
                                    'Assigned to ${s['assigned_to']}',
                                    const Color(0xFFDC3545),
                                  ),
                                if (s['expired'] == true)
                                  _badge('Expired', const Color(0xFF6C757D))
                                else if (s['trial'] == true)
                                  _badge('Trial', const Color(0xFFF59E0B)),
                              ],
                            ),
                            Text(
                              [
                                    s['store_name'],
                                    s['machine_type'],
                                    s['license_key'],
                                  ]
                                  .where((e) => (e ?? '').toString().isNotEmpty)
                                  .join(' · '),
                              style: TextStyle(fontSize: 12, color: b.paperDim),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _badge(String t, Color c) => Container(
    margin: const EdgeInsets.only(left: 6),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      t,
      style: TextStyle(fontSize: 10.5, color: c, fontWeight: FontWeight.w700),
    ),
  );

  Widget _attachments() {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: _attaching
              ? Brand.signal.withValues(alpha: 0.05)
              : b.surfaceHi,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _attaching ? null : _attachRequirement,
            child: CustomPaint(
              painter: _DashedBorder(
                color: _attaching
                    ? Brand.signal
                    : b.paperDim.withValues(alpha: 0.45),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
                child: Column(
                  children: [
                    if (_attaching)
                      const TpLoader(size: 40)
                    else
                      const IconTile(
                        icon: Icons.cloud_upload_outlined,
                        size: 44,
                      ),
                    const SizedBox(height: 10),
                    Text(
                      _attaching
                          ? 'Uploading...'
                          : _requirements.isEmpty
                          ? 'No requirement attachments yet'
                          : 'Attach more requirement files',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: b.paper,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'PDF, images (JPG, PNG, GIF, WEBP, BMP) or Word documents',
                      textAlign: TextAlign.center,
                      style: text.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    IgnorePointer(
                      child: OutlinedButton.icon(
                        onPressed: _attaching ? null : () {},
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 36),
                        ),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Attach Requirement'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_requirements.isNotEmpty) ...[
          const SizedBox(height: 14),
          _tiles([
            for (final f in _requirements)
              _fileTile(
                f,
                'Requirement',
                Icons.insert_drive_file_outlined,
                onRemove: () => setState(() => _requirements.remove(f)),
              ),
          ]),
        ],
      ],
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(10),
        ).deflate(0.7),
      );
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + 7, m.length)), paint);
        d += 12;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}
