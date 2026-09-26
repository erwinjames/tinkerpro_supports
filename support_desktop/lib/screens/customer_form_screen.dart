import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'bir_step2_form_screen.dart';
import '../widgets/tp_loader.dart';

class CustomerFormScreen extends StatefulWidget {
  const CustomerFormScreen({
    super.key,
    required this.service,
    this.existing,
    this.initialInvoiceNumber,
  });

  final CustomerService service;
  final CustomerDetail? existing;

  final String? initialInvoiceNumber;

  bool get isEdit => existing != null;

  static Future<bool?> show(
    BuildContext context, {
    required CustomerService service,
    CustomerDetail? existing,
    String? initialInvoiceNumber,
  }) {
    if (existing != null) {
      return BirStep2FormScreen.showEdit(
        context,
        api: service.api,
        customerId: existing.id,
      );
    }
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CustomerFormScreen(
        service: service,
        existing: existing,
        initialInvoiceNumber: initialInvoiceNumber,
      ),
    );
  }

  @override
  State<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends State<CustomerFormScreen> {
  static const _softwareOptions = <String>[
    'TinkerPro POS - Wholesale/Retail V1.0',
    'TinkerPro POS - QuickServe',
  ];
  static const _softwareVersions = <String, List<String>>{
    'TinkerPro POS - Wholesale/Retail V1.0': ['V1.0'],
    'TinkerPro POS - QuickServe': ['1'],
  };
  static const _serialTypeOptions = <String>[
    'Server',
    'Terminal',
    'Standalone',
  ];
  static const _serverTypeOptions = <String>['Consolidator', 'Global'];

  static const _validIdTypes = <(String, String)>[
    ('NATIONAL ID', 'National ID'),
    ("DRIVER'S LICENSE", "Driver's License"),
    ('PASSPORT', 'Passport'),
    ("VOTER'S ID", "Voter's ID"),
    ('SSS ID', 'SSS'),
    ('PHILHEALTH ID', 'PhilHealth'),
    ('POSTAL ID', 'Postal ID'),
    ('UMID', 'UMID'),
  ];

  final _companyName = TextEditingController();
  final _tin = TextEditingController();
  final _branchCode = TextEditingController();
  final _tinIssuance = TextEditingController();
  final _rdo = TextEditingController();
  final _businessLine = TextEditingController();
  final _address = TextEditingController();
  final _min = TextEditingController();
  final _ptu = TextEditingController();
  final _posDate = TextEditingController();
  final _invoiceNumber = TextEditingController();
  final _accNumber = TextEditingController();
  final _firstName = TextEditingController();
  final _middleName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _birthdate = TextEditingController();
  final _idNumber = TextEditingController();

  String? _softwareName;
  String? _softwareVersion;
  bool _isVat = true;
  final List<_SerialRow> _serialRows = [];

  String _username = '';
  String _password = '';

  final List<UploadedDoc> _extractionDocs = [];
  final List<UploadedDoc> _requirementDocs = [];
  bool _uploading = false;
  bool _extracting = false;
  final String _extractMode = 'accurate';

  bool _revealForm = false;
  final List<({String path, String name})> _pendingDocs = [];

  String? _validIdType;
  String? _pendingValidIdPath;
  String? _pendingValidIdName;
  UploadedDoc? _validIdFile;

  Timer? _tinDebounce;
  String _tinWarning = '';
  bool _saving = false;
  String _notice = '';
  final _scroll = ScrollController();
  final _viewportKey = GlobalKey();
  final _sectionKeys = List.generate(5, (_) => GlobalKey());
  int _activeStep = 0;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e == null) {
      _invoiceNumber.text = widget.initialInvoiceNumber ?? '';
      _serialRows.add(_SerialRow());
      return;
    }
    _companyName.text = e.companyName;
    _tin.text = e.tin;
    _branchCode.text = e.branchCode;
    _tinIssuance.text = e.tinIssuanceDate;
    _rdo.text = e.rdo;
    _businessLine.text = e.businessLine;
    _address.text = e.address;
    _min.text = e.min;
    _ptu.text = e.ptu;
    _posDate.text = e.posDateIssued;
    _invoiceNumber.text = e.invoiceNumber;
    _accNumber.text = e.accNumber;
    _firstName.text = e.firstName;
    _middleName.text = e.middleName;
    _lastName.text = e.lastName;
    _email.text = e.email;
    _username = e.username;
    _password = e.password;
    _isVat = e.isVat;
    if (_softwareOptions.contains(e.softwareName)) {
      _softwareName = e.softwareName;
      final versions = _softwareVersions[_softwareName] ?? const <String>[];
      if (versions.length == 1) _softwareVersion = versions.first;
    }
    if (e.serialEntries.isNotEmpty) {
      for (final s in e.serialEntries) {
        _serialRows.add(
          _SerialRow(
            type: _serialTypeOptions.contains(s.serialNumberType)
                ? s.serialNumberType
                : null,
            serverType: _serverTypeOptions.contains(s.serverType)
                ? s.serverType
                : null,
            sn: s.serialNumber,
            brand: s.brand,
            model: s.model,
          ),
        );
      }
    } else {
      _serialRows.add(_SerialRow());
    }
  }

  @override
  void dispose() {
    _tinDebounce?.cancel();
    _scroll.dispose();
    for (final c in [
      _companyName,
      _tin,
      _branchCode,
      _tinIssuance,
      _rdo,
      _businessLine,
      _address,
      _min,
      _ptu,
      _posDate,
      _invoiceNumber,
      _accNumber,
      _firstName,
      _middleName,
      _lastName,
      _email,
      _phone,
      _birthdate,
      _idNumber,
    ]) {
      c.dispose();
    }
    for (final r in _serialRows) {
      r.dispose();
    }
    super.dispose();
  }

  void _onTinChanged(String value) {
    _tinDebounce?.cancel();
    if (value.trim().isEmpty) {
      if (_tinWarning.isNotEmpty) setState(() => _tinWarning = '');
      return;
    }
    _tinDebounce = Timer(const Duration(milliseconds: 500), _checkTin);
  }

  Future<void> _checkTin() async {
    final tin = _tin.text.trim();
    if (widget.isEdit && tin == widget.existing!.tin) {
      if (mounted && _tinWarning.isNotEmpty) setState(() => _tinWarning = '');
      return;
    }
    final res = await widget.service.checkTinDuplicate(
      tin,
      _branchCode.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _tinWarning = res.duplicate
          ? 'A record with this TIN already exists'
                '${res.company.isEmpty ? '' : ' — ${res.company}'}.'
          : '';
    });
  }

  Future<void> _pickBirDocs() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'gif', 'webp'],
      );
    } catch (_) {
      _toast('Could not open the file picker.');
      return;
    }
    final picked = (result?.files ?? const [])
        .where((f) => f.path != null)
        .map((f) => (path: f.path!, name: f.name))
        .toList();
    if (picked.isEmpty) return;
    setState(() => _pendingDocs.addAll(picked));
  }

  Future<void> _extractNow() async {
    if (_pendingDocs.isEmpty) {
      _toast('Upload at least one document first.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _extracting = true);
    final r = await widget.service.extractDocuments(
      _pendingDocs.map((d) => d.path).toList(),
      mode: _extractMode,
      validIdPath: _pendingValidIdPath,
      validIdType: _validIdType,
    );
    if (!mounted) return;
    setState(() => _extracting = false);
    if (!r.ok) {
      _toast(r.error ?? 'Extraction failed. You can still fill the form.');
      return;
    }
    _applyExtraction(r);
  }

  Future<void> _pickValidId() async {
    if ((_validIdType ?? '').isEmpty) {
      _toast('Select the valid ID type first.');
      return;
    }
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'gif', 'webp'],
      );
    } catch (_) {
      _toast('Could not open the file picker.');
      return;
    }
    final file = result?.files.singleOrNull;
    if (file?.path == null) return;
    setState(() {
      _pendingValidIdPath = file!.path;
      _pendingValidIdName = file.name;
      _validIdFile = null;
    });
  }

  Future<void> _viewValidId() async {
    try {
      final f = _validIdFile;
      if (f != null && f.stored.isNotEmpty) {
        final url = '${widget.service.api.baseUrl}/uploads/${f.stored}';
        final ok = await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
        if (!ok && mounted) _toast('Could not open the ID.');
      } else if (_pendingValidIdPath != null) {
        await OpenFilex.open(_pendingValidIdPath!);
      }
    } catch (_) {
      if (mounted) _toast('Could not open the ID.');
    }
  }

  void _applyExtraction(ExtractionResult r) {
    setState(() {
      _revealForm = true;
      if (r.companyName.isNotEmpty) _companyName.text = r.companyName;
      if (r.tin.isNotEmpty) _tin.text = r.tin;
      if (r.branchCode.isNotEmpty) _branchCode.text = r.branchCode;
      if (r.tinIssuanceDate.isNotEmpty) _tinIssuance.text = r.tinIssuanceDate;
      if (r.address.isNotEmpty) _address.text = r.address;
      if (r.businessLine.isNotEmpty) _businessLine.text = r.businessLine;
      if (r.rdo.isNotEmpty) _rdo.text = r.rdo;
      if (r.firstName.isNotEmpty) _firstName.text = r.firstName;
      if (r.middleName.isNotEmpty) _middleName.text = r.middleName;
      if (r.lastName.isNotEmpty) _lastName.text = r.lastName;
      if (r.isVat != null) _isVat = r.isVat!;
      _extractionDocs.addAll(r.storedFiles);
      _pendingDocs.clear();
      if (r.validIdDoc != null) {
        _validIdFile = r.validIdDoc;
        _pendingValidIdPath = null;
        _pendingValidIdName = null;
        if (r.idNumber.isNotEmpty) _idNumber.text = r.idNumber;
        if (r.idBirthdate.isNotEmpty) _birthdate.text = r.idBirthdate;
      }
    });
    _checkTin();
    _toast(
      r.storedFiles.isEmpty
          ? 'Extraction complete — review the fields below.'
          : 'Auto-filled from ${r.storedFiles.length} document(s). Review below.',
    );
  }

  Future<void> _pickAndUpload(List<UploadedDoc> target) async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'gif', 'webp'],
      );
    } catch (_) {
      _toast('Could not open the file picker.');
      return;
    }
    final path = result?.files.singleOrNull?.path;
    if (path == null) return;
    setState(() => _uploading = true);
    final doc = await widget.service.uploadDocument(path);
    if (!mounted) return;
    setState(() {
      _uploading = false;
      if (doc != null) target.add(doc);
    });
    if (doc == null) _toast('Upload failed. Please try again.');
  }

  List<SerialEntry> _collectSerials() =>
      _serialRows.where((r) => !r.isEmpty).map((r) => r.toEntry()).toList();

  String? _validate(List<SerialEntry> serials) {
    final missing = <String>[];
    void req(String label, bool ok) {
      if (!ok) missing.add(label);
    }

    req('Company name', _companyName.text.trim().isNotEmpty);
    req('TIN', _tin.text.trim().isNotEmpty);
    req('Address', _address.text.trim().isNotEmpty);
    req('First name', _firstName.text.trim().isNotEmpty);
    req('Last name', _lastName.text.trim().isNotEmpty);
    req('RDO', _rdo.text.trim().isNotEmpty);
    req('Business line', _businessLine.text.trim().isNotEmpty);
    req('Software name', (_softwareName ?? '').isNotEmpty);
    req('Accreditation no.', _accNumber.text.trim().isNotEmpty);
    req(
      'At least one serial number',
      serials.any((s) => s.serialNumber.isNotEmpty),
    );
    if (!widget.isEdit) {
      req('Valid ID', _pendingValidIdPath != null || _validIdFile != null);
    }

    if (missing.isEmpty) return null;
    return 'Required: ${missing.join(', ')}.';
  }

  Map<String, String> _buildFields(List<SerialEntry> serials) {
    final snJoined = serials
        .map((e) => e.serialNumber)
        .where((s) => s.isNotEmpty)
        .join('/');
    return <String, String>{
      'companyname': _companyName.text.trim(),
      'tin': _tin.text.trim(),
      'branch_code': _branchCode.text.trim(),
      'tin_issuance_date': _tinIssuance.text.trim(),
      'rdo': _rdo.text.trim(),
      'businessline': _businessLine.text.trim(),
      'address': _address.text.trim(),
      'min': _min.text.trim(),
      'ptu': _ptu.text.trim(),
      'pos_date_issued': _posDate.text.trim(),
      'invoice_number': _invoiceNumber.text.trim(),
      'softwarename': _softwareName ?? '',
      'software_version': _softwareVersion ?? '',
      'acc_number': _accNumber.text.trim(),
      'sn': snJoined,
      'firstname': _firstName.text.trim(),
      'middlename': _middleName.text.trim(),
      'lastname': _lastName.text.trim(),
      'email': _email.text.trim(),
      'phone_number': _phone.text.trim(),
      'birthdate': _birthdate.text.trim(),
      'username': _username,
      'password': _password,
      'is_vat': _isVat ? '1' : '0',
      'extraction_mode': '1',
      'step2': '1',
      'serial_entries': CustomerService.encodeSerialEntries(serials),
      'document_files': jsonEncode(
        _extractionDocs.map((e) => e.toJson()).toList(),
      ),
      'valid_id_files': jsonEncode(
        _validIdFile == null
            ? const []
            : [
                {
                  'original': _validIdFile!.original,
                  'stored': _validIdFile!.stored,
                  'mime': _validIdFile!.mime,
                  'size': _validIdFile!.size,
                  'extracted': {
                    'id_type': _validIdType ?? '',
                    'id_name': [
                      _firstName.text.trim(),
                      _middleName.text.trim(),
                      _lastName.text.trim(),
                    ].where((e) => e.isNotEmpty).join(' '),
                    'id_number': _idNumber.text.trim(),
                    'id_birthdate': _birthdate.text.trim(),
                  },
                },
              ],
      ),
      'requirement_files': jsonEncode(
        _requirementDocs.map((e) => e.toJson()).toList(),
      ),
    };
  }

  Future<void> _save() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    final serials = _collectSerials();
    final error = _validate(serials);
    if (error != null) {
      _toast(error);
      return;
    }
    setState(() => _saving = true);
    if (_pendingValidIdPath != null && _validIdFile == null) {
      final doc = await widget.service.uploadDocument(_pendingValidIdPath!);
      if (doc != null) _validIdFile = doc;
      _pendingValidIdPath = null;
      _pendingValidIdName = null;
    }
    final result = await widget.service.save(
      id: widget.existing?.id,
      fields: _buildFields(serials),
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
    if (mounted) setState(() => _notice = message);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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

  bool get _scanGate => !widget.isEdit && !_revealForm;

  List<_Step> get _steps => widget.isEdit
      ? const [
          _Step(
            'Business Information',
            'TIN, RDO and address',
            Icons.storefront_outlined,
          ),
          _Step(
            'Point-of-Sale',
            'Software and serial numbers',
            Icons.point_of_sale_outlined,
          ),
          _Step(
            'Owner / Contact',
            'Owner name and contact details',
            Icons.person_outline,
          ),
        ]
      : const [
          _Step(
            'Documents & Valid ID',
            'Scan to auto-fill with AI',
            Icons.document_scanner_outlined,
          ),
          _Step(
            'Business Information',
            'TIN, RDO and address',
            Icons.storefront_outlined,
          ),
          _Step(
            'Point-of-Sale',
            'Software and serial numbers',
            Icons.point_of_sale_outlined,
          ),
          _Step(
            'Owner / Contact',
            'Owner name and contact details',
            Icons.person_outline,
          ),
          _Step('Requirements', 'Supporting documents', Icons.attach_file),
        ];

  void _goToStep(int index) {
    if (_scanGate && index > 0) {
      _toast('Extract the documents or choose "Enter details manually" first.');
      return;
    }
    setState(() => _activeStep = index);
    final ctx = _sectionKeys[index].currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  bool _onScroll(ScrollNotification n) {
    final viewport =
        _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (viewport == null || !viewport.attached) return false;
    final top = viewport.localToGlobal(Offset.zero).dy;
    var active = 0;
    for (var i = 0; i < _steps.length; i++) {
      final box =
          _sectionKeys[i].currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      if (box.localToGlobal(Offset.zero).dy - top <= 120) active = i;
    }
    if (_scroll.hasClients &&
        _scroll.position.pixels >= _scroll.position.maxScrollExtent - 4) {
      active = _steps.length - 1;
    }
    if (active != _activeStep) setState(() => _activeStep = active);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final modal = WebModal(
      title: widget.isEdit ? 'Update Customer' : 'Register New Client',
      subtitle: widget.isEdit
          ? widget.existing!.companyName
          : ((widget.initialInvoiceNumber ?? '').isEmpty
                ? 'No invoice attached'
                : 'Invoice ${widget.initialInvoiceNumber}'),
      icon: Icons.description_outlined,
      width: _scanGate ? 800 : 1150,
      height: 900,
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      onClose: () => Navigator.of(context).pop(),
      actions: _footerActions(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_scanGate && MediaQuery.sizeOf(context).width >= 1000)
            _rail(context),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: SingleChildScrollView(
                key: _viewportKey,
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _sections(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (ModalRoute.of(context) is PopupRoute) return modal;
    return Scaffold(backgroundColor: context.brand.canvas, body: modal);
  }

  List<Widget> _footerActions(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final steps = _steps.length;
    final current = _scanGate ? 1 : _activeStep + 1;
    final status = Expanded(
      child: Row(
        children: [
          Text(
            'Step $current of $steps',
            style: text.bodySmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 200,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: current / steps,
                minHeight: 5,
                color: Brand.signal,
                backgroundColor: context.brand.rule,
              ),
            ),
          ),
          const SizedBox(width: 16),
          if (_notice.isNotEmpty)
            Expanded(
              child: Text(
                _notice,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(color: Brand.danger),
              ),
            ),
        ],
      ),
    );
    final cancel = GhostButton(
      label: 'Cancel',
      onPressed: _saving ? null : () => Navigator.of(context).pop(),
    );
    if (_scanGate) {
      return [
        status,
        cancel,
        GhostButton(
          label: 'Enter details manually',
          icon: Icons.edit_note,
          onPressed: _extracting
              ? null
              : () => setState(() {
                  _revealForm = true;
                  _notice = '';
                }),
        ),
        SignalButton(
          label: 'Extract',
          icon: Icons.document_scanner_outlined,
          busy: _extracting,
          onPressed: _pendingDocs.isEmpty ? null : _extractNow,
        ),
      ];
    }
    return [
      status,
      cancel,
      SignalButton(
        label: widget.isEdit ? 'Save Changes' : 'Create Client',
        icon: Icons.check,
        busy: _saving,
        onPressed: _saving ? null : _save,
      ),
    ];
  }

  Widget _rail(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      width: 270,
      decoration: BoxDecoration(
        color: context.brand.surfaceHi,
        border: Border(right: BorderSide(color: context.brand.rule)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _steps.length; i++)
            _railItem(context, i, _steps[i]),
          const Spacer(),
          if (_scanGate)
            Text(
              'Upload the BIR 2303 / registration documents and a valid ID, '
              'then Extract to auto-fill the form. Prefer to type it in? '
              'Choose "Enter details manually".',
              style: text.bodySmall,
            )
          else
            Text(
              'Fields marked * are required. Review everything before saving.',
              style: text.bodySmall,
            ),
        ],
      ),
    );
  }

  Widget _railItem(BuildContext context, int index, _Step step) {
    final text = Theme.of(context).textTheme;
    final active = (_scanGate ? 0 : _activeStep) == index;
    final locked = _scanGate && index > 0;
    final fg = locked
        ? context.brand.paperDim.withValues(alpha: 0.55)
        : (active ? Brand.signal : context.brand.paper);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: () => _goToStep(index),
        mouseCursor: locked
            ? SystemMouseCursors.forbidden
            : SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: active ? context.brand.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? context.brand.rule : Colors.transparent,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? Brand.signal : context.brand.surface,
                  border: Border.all(
                    color: active ? Brand.signal : context.brand.rule,
                  ),
                ),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: active ? Colors.white : context.brand.paperDim,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(step.icon, size: 15, color: fg),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            step.title,
                            style: text.bodyMedium?.copyWith(
                              color: fg,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(step.subtitle, style: text.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _sections(BuildContext context) {
    final out = <Widget>[];
    var i = 0;
    void add(Widget body) {
      final idx = i++;
      if (out.isNotEmpty) out.add(const SizedBox(height: 26));
      out.add(_section(context, idx, _steps[idx], body));
    }

    if (!widget.isEdit) {
      if (_scanGate) return [_scanHero(context)];
      add(_extractionSection(context));
    }
    add(_businessSection(context));
    add(_posSection(context));
    add(_ownerSection(context));
    if (!widget.isEdit) add(_requirementsSection(context));
    return out;
  }

  Widget _section(BuildContext context, int index, _Step step, Widget body) {
    return Column(
      key: _sectionKeys[index],
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Brand.signal,
              ),
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Icon(step.icon, size: 19, color: Brand.signal),
            const SizedBox(width: 8),
            Text(
              step.title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Brand.signal,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: context.brand.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.brand.rule),
          ),
          child: body,
        ),
      ],
    );
  }

  Widget _businessSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormRow(
          label: 'Business Name',
          icon: Icons.storefront_outlined,
          required: true,
          child: _input(
            _companyName,
            hint: 'Registered business name',
            textCapitalization: TextCapitalization.characters,
          ),
        ),
        FormRow(
          label: 'TIN',
          icon: Icons.badge_outlined,
          required: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _input(
                _tin,
                hint: '000-000-000',
                keyboardType: TextInputType.number,
                onChanged: _onTinChanged,
              ),
              if (_tinWarning.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _tinWarning,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Brand.danger),
                  ),
                ),
            ],
          ),
        ),
        FormRow(
          label: 'Branch Code',
          icon: Icons.account_tree_outlined,
          child: _input(_branchCode, hint: '00000'),
        ),
        FormRow(
          label: 'TIN Issuance Date',
          icon: Icons.event_outlined,
          child: _dateInput(_tinIssuance),
        ),
        FormRow(
          label: 'RDO',
          icon: Icons.location_city_outlined,
          required: true,
          child: _input(_rdo, hint: 'Revenue District Office'),
        ),
        FormRow(
          label: 'Line of Business',
          icon: Icons.work_outline,
          required: true,
          child: _input(_businessLine, hint: 'e.g. Retail'),
        ),
        FormRow(
          label: 'Business Address',
          icon: Icons.place_outlined,
          required: true,
          child: _input(_address, hint: 'Full business address', maxLines: 2),
        ),
        FormRow(
          label: 'VAT Status',
          icon: Icons.percent,
          child: Row(
            children: [
              _chip('VAT', _isVat, () => setState(() => _isVat = true)),
              const SizedBox(width: 8),
              _chip('NON-VAT', !_isVat, () => setState(() => _isVat = false)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _posSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormRow(
          label: 'Software Name',
          icon: Icons.apps_outlined,
          required: true,
          child: _softwareDropdown(),
        ),
        FormRow(
          label: 'Software Version',
          icon: Icons.tag,
          child: _softwareVersionDropdown(),
        ),
        FormRow(
          label: 'Accreditation No.',
          icon: Icons.verified_outlined,
          required: true,
          child: _input(_accNumber, hint: 'BIR accreditation number'),
        ),
        const SizedBox(height: 12),
        _serialSection(),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _ownerSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormRow(
          label: 'First Name',
          icon: Icons.person_outline,
          required: true,
          child: _input(
            _firstName,
            hint: 'First name',
            textCapitalization: TextCapitalization.words,
          ),
        ),
        FormRow(
          label: 'Middle Name',
          icon: Icons.person_outline,
          child: _input(
            _middleName,
            hint: 'Middle name',
            textCapitalization: TextCapitalization.words,
          ),
        ),
        FormRow(
          label: 'Last Name',
          icon: Icons.person_outline,
          required: true,
          child: _input(
            _lastName,
            hint: 'Last name',
            textCapitalization: TextCapitalization.words,
          ),
        ),
        FormRow(
          label: 'Email',
          icon: Icons.mail_outline,
          child: _input(
            _email,
            hint: 'name@example.com',
            keyboardType: TextInputType.emailAddress,
          ),
        ),
        FormRow(
          label: 'Phone Number',
          icon: Icons.phone_outlined,
          child: _input(
            _phone,
            hint: '09XX XXX XXXX',
            keyboardType: TextInputType.phone,
          ),
        ),
        FormRow(
          label: 'Birthdate',
          icon: Icons.cake_outlined,
          child: _dateInput(_birthdate),
        ),
      ],
    );
  }

  Widget _input(
    TextEditingController controller, {
    String? hint,
    TextInputType? keyboardType,
    int maxLines = 1,
    TextCapitalization textCapitalization = TextCapitalization.none,
    ValueChanged<String>? onChanged,
  }) => TextField(
    controller: controller,
    keyboardType: keyboardType,
    maxLines: maxLines,
    textCapitalization: textCapitalization,
    onChanged: onChanged,
    decoration: InputDecoration(hintText: hint, isDense: true),
  );

  Widget _dateInput(TextEditingController controller) => TextField(
    controller: controller,
    readOnly: true,
    onTap: () => _pickDate(controller),
    mouseCursor: SystemMouseCursors.click,
    decoration: InputDecoration(
      hintText: 'YYYY-MM-DD',
      isDense: true,
      suffixIcon: controller.text.isEmpty
          ? Icon(
              Icons.calendar_today_outlined,
              size: 16,
              color: context.brand.paperDim,
            )
          : IconButton(
              tooltip: 'Clear',
              icon: Icon(Icons.close, size: 16, color: context.brand.paperDim),
              onPressed: () => setState(() => controller.clear()),
            ),
    ),
  );

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      mouseCursor: SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? Brand.signal : context.brand.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? Brand.signal : Brand.inputBorder,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : context.brand.paperDim,
          ),
        ),
      ),
    );
  }

  Widget _scanHero(BuildContext context) {
    final hasFiles = _pendingDocs.isNotEmpty || _extractionDocs.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        const Text(
          'Upload your',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, color: Color(0xFF212529)),
        ),
        const SizedBox(height: 4),
        const Text(
          'BIR Form 2303 and Valid ID',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 31,
            fontWeight: FontWeight.w800,
            color: Brand.signal,
          ),
        ),
        const SizedBox(height: 28),
        InkWell(
          onTap: _extracting ? null : _pickBirDocs,
          borderRadius: BorderRadius.circular(14),
          child: CustomPaint(
            painter: _DashedBorder(),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFCF9),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  const Icon(Icons.cloud_upload, size: 72, color: Brand.signal),
                  const SizedBox(height: 18),
                  const Text(
                    'DRAG & DROP FILES',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Brand.navy,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'or click to browse from your computer',
                    style: TextStyle(fontSize: 15, color: Color(0xFF334155)),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 58,
                    child: TextButton.icon(
                      onPressed: _extracting ? null : _pickBirDocs,
                      icon: const Icon(Icons.folder_open, size: 22),
                      label: Text(
                        hasFiles ? 'Add More Documents' : 'Select Documents',
                      ),
                      style: TextButton.styleFrom(
                        backgroundColor: Brand.signal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.picture_as_pdf, size: 16, color: Brand.navy),
                      SizedBox(width: 4),
                      Text('PDF'),
                      SizedBox(width: 12),
                      Icon(Icons.image, size: 16, color: Brand.navy),
                      SizedBox(width: 4),
                      Text('Images'),
                      SizedBox(width: 12),
                      Icon(Icons.shield, size: 16, color: Brand.navy),
                      SizedBox(width: 4),
                      Text('Secure'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (int i = 0; i < _pendingDocs.length; i++)
          _fileRow(
            context,
            _pendingDocs[i].name,
            () => setState(() => _pendingDocs.removeAt(i)),
            badge: 'Pending',
          ),
        for (int i = 0; i < _extractionDocs.length; i++)
          _fileRow(
            context,
            _extractionDocs[i].original,
            () => setState(() => _extractionDocs.removeAt(i)),
            badge: 'Uploaded',
          ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: _validIdBlock(context),
        ),
        if (_extracting) ...[
          const SizedBox(height: 14),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: TpLoader(
                  strokeWidth: 2,
                  color: Brand.signal,
                ),
              ),
              SizedBox(width: 12),
              Text('Extracting… this can take up to a minute.'),
            ],
          ),
        ],
      ],
    );
  }

  Widget _extractionSection(BuildContext context) {
    if (_scanGate) return _scanHero(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Upload the BIR 2303 / registration documents and a valid ID, then '
            'Extract to auto-fill this form with AI. Review and correct every '
            'field before saving.',
            style: text.bodyMedium?.copyWith(color: context.brand.paperDim),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _subLabel('BIR Documents', Icons.description_outlined),
                    const SizedBox(height: 8),
                    _uploadBox(
                      context,
                      _pendingDocs.isEmpty && _extractionDocs.isEmpty
                          ? 'Upload documents'
                          : 'Add more documents',
                      'PDF, JPG, PNG, GIF or WEBP',
                      Icons.upload_file,
                      _extracting ? null : _pickBirDocs,
                    ),
                    const SizedBox(height: 8),
                    for (int i = 0; i < _pendingDocs.length; i++)
                      _fileRow(
                        context,
                        _pendingDocs[i].name,
                        () => setState(() => _pendingDocs.removeAt(i)),
                        badge: 'Pending',
                      ),
                    for (int i = 0; i < _extractionDocs.length; i++)
                      _fileRow(
                        context,
                        _extractionDocs[i].original,
                        () => setState(() => _extractionDocs.removeAt(i)),
                        badge: 'Uploaded',
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(child: _validIdBlock(context)),
            ],
          ),
          const SizedBox(height: 14),
          if (_extracting)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Brand.signalGlow(0.06),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Brand.signalGlow(0.35)),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: TpLoader(
                      strokeWidth: 2,
                      color: Brand.signal,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Extracting… this can take up to a minute.',
                      style: text.bodyMedium,
                    ),
                  ),
                ],
              ),
            )
          else if (!_scanGate)
            Align(
              alignment: Alignment.centerRight,
              child: SignalButton(
                label: 'Extract',
                icon: Icons.document_scanner_outlined,
                onPressed: _pendingDocs.isEmpty ? null : _extractNow,
              ),
            ),
        ],
      ),
    );
  }

  Widget _subLabel(String label, IconData icon) => Row(
    children: [
      Icon(icon, size: 15, color: Brand.signal),
      const SizedBox(width: 6),
      Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    ],
  );

  Widget _validIdBlock(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _subLabel('Valid ID', Icons.badge_outlined)),
            if (!widget.isEdit)
              const Text(
                'Required',
                style: TextStyle(
                  color: Brand.danger,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Pick the ID type and attach a photo/scan — it is read together with '
          "the BIR documents to fill the owner's name and ID details.",
          style: text.bodySmall,
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: _validIdType,
          isExpanded: true,
          isDense: true,
          decoration: const InputDecoration(hintText: 'Select ID type'),
          items: [
            for (final t in _validIdTypes)
              DropdownMenuItem(value: t.$1, child: Text(t.$2)),
          ],
          onChanged: (v) => setState(() => _validIdType = v),
        ),
        const SizedBox(height: 10),
        _uploadBox(
          context,
          (_pendingValidIdPath != null || _validIdFile != null)
              ? 'Replace valid ID'
              : 'Attach valid ID',
          'Photo or scan of the ID',
          Icons.badge_outlined,
          _extracting ? null : _pickValidId,
        ),
        if (_pendingValidIdPath != null) ...[
          const SizedBox(height: 8),
          _fileRow(
            context,
            _pendingValidIdName ?? 'Valid ID',
            () {
              setState(() {
                _pendingValidIdPath = null;
                _pendingValidIdName = null;
              });
            },
            onView: _viewValidId,
            badge: 'Read on Extract',
          ),
        ],
        if (_validIdFile != null) ...[
          const SizedBox(height: 8),
          _fileRow(
            context,
            _validIdFile!.original,
            () {
              setState(() {
                _validIdFile = null;
                _idNumber.clear();
              });
            },
            onView: _viewValidId,
            badge: 'Uploaded',
          ),
        ],
        if (_pendingValidIdPath != null || _validIdFile != null) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _idNumber,
            decoration: const InputDecoration(
              labelText: 'ID Number',
              isDense: true,
            ),
          ),
        ],
      ],
    );
  }

  Widget _uploadBox(
    BuildContext context,
    String label,
    String hint,
    IconData icon,
    VoidCallback? onTap,
  ) {
    final text = Theme.of(context).textTheme;
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      mouseCursor: enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
        decoration: BoxDecoration(
          color: enabled ? Brand.signalGlow(0.05) : context.brand.surfaceHi,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: enabled ? Brand.signalGlow(0.55) : context.brand.rule,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: enabled ? Brand.signal : context.brand.paperDim,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: text.bodyMedium?.copyWith(
                      color: enabled ? Brand.signal : context.brand.paperDim,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(hint, style: text.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fileRow(
    BuildContext context,
    String name,
    VoidCallback onRemove, {
    VoidCallback? onView,
    String? badge,
  }) {
    final text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
      decoration: BoxDecoration(
        color: context.brand.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: context.brand.rule),
      ),
      child: Row(
        children: [
          Icon(
            Icons.insert_drive_file_outlined,
            size: 16,
            color: context.brand.paperDim,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              style: text.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (badge != null) ...[
            const SizedBox(width: 6),
            StatusPill(label: badge),
          ],
          if (onView != null)
            IconButton(
              tooltip: 'View',
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.visibility_outlined,
                size: 17,
                color: Brand.signal,
              ),
              onPressed: onView,
            ),
          IconButton(
            tooltip: 'Remove',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close, size: 17, color: context.brand.paperDim),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }

  Widget _requirementsSection(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Optional supporting documents.',
            style: text.bodyMedium?.copyWith(color: context.brand.paperDim),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 420,
              child: _uploadBox(
                context,
                _uploading ? 'Uploading…' : 'Upload requirement',
                'PDF, JPG, PNG, GIF or WEBP',
                Icons.attach_file,
                _uploading ? null : () => _pickAndUpload(_requirementDocs),
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (int i = 0; i < _requirementDocs.length; i++)
            _fileRow(
              context,
              _requirementDocs[i].original,
              () => setState(() => _requirementDocs.removeAt(i)),
              badge: 'Uploaded',
            ),
        ],
      ),
    );
  }

  Widget _softwareDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _softwareName,
      isExpanded: true,
      isDense: true,
      decoration: const InputDecoration(hintText: 'Select software'),
      items: [
        for (final s in _softwareOptions)
          DropdownMenuItem(value: s, child: Text(s)),
      ],
      onChanged: (s) => setState(() {
        _softwareName = s;
        final versions = _softwareVersions[s] ?? const <String>[];
        _softwareVersion = versions.length == 1 ? versions.first : null;
      }),
    );
  }

  Widget _softwareVersionDropdown() {
    final versions = _softwareVersions[_softwareName] ?? const <String>[];
    return DropdownButtonFormField<String>(
      key: ValueKey('ver-$_softwareName-$_softwareVersion'),
      initialValue: _softwareVersion,
      isExpanded: true,
      isDense: true,
      decoration: InputDecoration(
        hintText: versions.isEmpty
            ? 'Select a software first'
            : 'Select version',
      ),
      items: [
        for (final v in versions) DropdownMenuItem(value: v, child: Text(v)),
      ],
      onChanged: versions.isEmpty
          ? null
          : (v) => setState(() => _softwareVersion = v),
    );
  }

  List<String> _serialTypeOptionsFor(int index) {
    final current = _serialRows[index].type;
    final others = <String>{};
    for (var i = 0; i < _serialRows.length; i++) {
      if (i == index) continue;
      final t = _serialRows[i].type;
      if (t != null && t.isNotEmpty) others.add(t);
    }
    Set<String> opts;
    if (others.contains('Standalone')) {
      opts = {'Standalone'};
    } else if (others.contains('Server') || others.contains('Terminal')) {
      opts = {'Server', 'Terminal'};
      if (others.contains('Server')) opts.remove('Server');
    } else {
      opts = {'Server', 'Terminal', 'Standalone'};
    }
    if (current != null && current.isNotEmpty) opts.add(current);
    return _serialTypeOptions.where((t) => opts.contains(t)).toList();
  }

  Widget _serialSection() {
    const headerStyle = TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.w700,
      fontSize: 13,
    );
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.brand.rule),
      ),
      clipBehavior: Clip.antiAlias,
      child: ColumnResizeScope(
        tableId: 'customer:serials',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: Brand.signal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Builder(
                builder: (context) => Row(
                  children: resizableRowCells(
                    context,
                    [
                      Expanded(
                        flex: 3,
                        child: Text('Type', style: headerStyle),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: Text('Server Type', style: headerStyle),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        flex: 4,
                        child: Text('Serial Number *', style: headerStyle),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: Text('Brand', style: headerStyle),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: Text('Model', style: headerStyle),
                      ),
                      SizedBox(width: 40),
                    ],
                    header: true,
                    extra: 24,
                  ),
                ),
              ),
            ),
            for (int i = 0; i < _serialRows.length; i++) _serialRowWidget(i),
            Container(
              padding: const EdgeInsets.all(10),
              color: context.brand.surfaceHi,
              alignment: Alignment.centerLeft,
              child: GhostButton(
                label: 'Add Serial',
                icon: Icons.add,
                onPressed: () => setState(() => _serialRows.add(_SerialRow())),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _serialRowWidget(int index) {
    final row = _serialRows[index];
    final isServer = row.type == 'Server';
    return Container(
      key: ObjectKey(row),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: index.isOdd ? Brand.signalGlow(0.04) : context.brand.surface,
        border: Border(bottom: BorderSide(color: context.brand.rule)),
      ),
      child: Builder(
        builder: (context) => Row(
          children: resizableRowCells(context, [
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<String>(
                initialValue: row.type,
                isExpanded: true,
                isDense: true,
                decoration: const InputDecoration(hintText: 'Type'),
                items: [
                  for (final t in _serialTypeOptionsFor(index))
                    DropdownMenuItem(value: t, child: Text(t)),
                ],
                onChanged: (t) => setState(() {
                  row.type = t;
                  if (t != 'Server') row.serverType = null;
                }),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<String>(
                key: ValueKey('srv-${identityHashCode(row)}-$isServer'),
                initialValue: isServer ? row.serverType : null,
                isExpanded: true,
                isDense: true,
                decoration: InputDecoration(
                  hintText: isServer ? 'Server type' : 'Servers only',
                ),
                items: [
                  for (final t in _serverTypeOptions)
                    DropdownMenuItem(value: t, child: Text(t)),
                ],
                onChanged: isServer
                    ? (t) => setState(() => row.serverType = t)
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 4,
              child: TextField(
                controller: row.sn,
                decoration: const InputDecoration(
                  hintText: 'Serial number',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: TextField(
                controller: row.brand,
                decoration: const InputDecoration(
                  hintText: 'Brand',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: TextField(
                controller: row.model,
                decoration: const InputDecoration(
                  hintText: 'Model',
                  isDense: true,
                ),
              ),
            ),
            SizedBox(
              width: 40,
              child: _serialRows.length > 1
                  ? IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: Brand.danger,
                      ),
                      onPressed: () =>
                          setState(() => _serialRows.removeAt(index).dispose()),
                    )
                  : null,
            ),
          ]),
        ),
      ),
    );
  }
}

class _Step {
  const _Step(this.title, this.subtitle, this.icon);
  final String title;
  final String subtitle;
  final IconData icon;
}

class _SerialRow {
  _SerialRow({
    this.type,
    this.serverType,
    String sn = '',
    String brand = '',
    String model = '',
  }) : sn = TextEditingController(text: sn),
       brand = TextEditingController(text: brand),
       model = TextEditingController(text: model);

  String? type;
  String? serverType;
  final TextEditingController sn;
  final TextEditingController brand;
  final TextEditingController model;

  bool get isEmpty =>
      sn.text.trim().isEmpty &&
      brand.text.trim().isEmpty &&
      model.text.trim().isEmpty &&
      (type == null || type!.isEmpty);

  SerialEntry toEntry() => SerialEntry(
    serialNumberType: type ?? '',
    serverType: type == 'Server' ? (serverType ?? '') : '',
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

class _DashedBorder extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFD9DEE5)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14)),
      );
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + 8), paint);
        d += 14;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
