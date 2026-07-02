import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../theme.dart';
import '../widgets/premium.dart';

/// Create / edit a BIR (customer) record. All processing happens on the web
/// server — this screen only collects the fields the web intake/edit form
/// collects and POSTs them to `addcustomer` / `updateCustomer` via
/// [CustomerService.save].
///
/// Pass [existing] to edit; leave it null to create. On a successful save the
/// screen pops with `true` so the caller can refresh.
class CustomerFormScreen extends StatefulWidget {
  const CustomerFormScreen({
    super.key,
    required this.service,
    this.existing,
    this.initialInvoiceNumber,
  });

  final CustomerService service;
  final CustomerDetail? existing;

  /// Invoice number chosen in the "Find Your Invoice" step (create flow).
  final String? initialInvoiceNumber;

  bool get isEdit => existing != null;

  @override
  State<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends State<CustomerFormScreen> {
  // Web form's <select> option sets (see modal/modal.php + customer.php).
  static const _softwareOptions = <String>[
    'TinkerPro POS - Wholesale/Retail V1.0',
    'TinkerPro POS - QuickServe',
  ];
  // Version options per software (mirrors customer.js).
  static const _softwareVersions = <String, List<String>>{
    'TinkerPro POS - Wholesale/Retail V1.0': ['V1.0'],
    'TinkerPro POS - QuickServe': ['1'],
  };
  static const _serialTypeOptions = <String>['Server', 'Terminal', 'Standalone'];
  static const _serverTypeOptions = <String>['Consolidator', 'Global'];

  // Valid-ID types (value, label) — mirrors the web registration form.
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

  // ── Text controllers ──────────────────────────────────────────────────────
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
  final _username = TextEditingController();
  final _password = TextEditingController();

  // Username/password aren't part of the BIR extraction preview — hidden for
  // now. Flip to true to collect login credentials again.
  final bool _showLogin = false;

  // ── Selections / state ────────────────────────────────────────────────────
  String? _softwareName;
  String? _softwareVersion;
  bool _isVat = true;

  // Location (province/city) is hidden for now — the BIR extraction add-customer
  // doesn't collect it. Flip to true to bring the section back.
  final bool _showLocation = false;
  List<Province> _provinces = const [];
  List<City> _cities = const [];
  Province? _province;
  City? _city;
  bool _loadingCities = false;

  final List<_SerialRow> _serialRows = [];

  // Newly uploaded documents (create only — updateCustomer ignores documents).
  final List<UploadedDoc> _extractionDocs = [];
  final List<UploadedDoc> _requirementDocs = [];
  bool _uploading = false;

  // Document extraction (AI/OCR) — create only, mirrors the web scan flow.
  // Documents are uploaded first (held here), then extracted on demand.
  bool _extracting = false;
  final String _extractMode = 'accurate'; // default; MODE toggle hidden
  final List<({String path, String name})> _pendingDocs = [];

  // Valid ID — read together with the BIR docs during "Attach & extract" (the
  // reliable keep-alive endpoint). Its extracted details (type/number/birthdate/
  // holder name) are reviewable + editable below.
  String? _validIdType;
  String? _pendingValidIdPath; // selected, not yet read
  String? _pendingValidIdName;
  UploadedDoc? _validIdFile; // stored on the server (after scan or plain upload)
  final _idNumber = TextEditingController();

  Timer? _tinDebounce;
  String _tinWarning = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _prefillFromExisting();
    _loadAddressData();
  }

  void _prefillFromExisting() {
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
    _username.text = e.username;
    _password.text = e.password;
    _isVat = e.isVat;
    if (_softwareOptions.contains(e.softwareName)) {
      _softwareName = e.softwareName;
      final versions = _softwareVersions[_softwareName] ?? const <String>[];
      if (versions.length == 1) _softwareVersion = versions.first;
    }
    if (e.serialEntries.isNotEmpty) {
      for (final s in e.serialEntries) {
        _serialRows.add(_SerialRow(
          type: _serialTypeOptions.contains(s.serialNumberType)
              ? s.serialNumberType
              : null,
          serverType: _serverTypeOptions.contains(s.serverType)
              ? s.serverType
              : null,
          sn: s.serialNumber,
          brand: s.brand,
          model: s.model,
        ));
      }
    } else {
      _serialRows.add(_SerialRow());
    }
  }

  Future<void> _loadAddressData() async {
    final provinces = await widget.service.provinces();
    if (!mounted) return;
    Province? selected;
    final code = widget.existing?.provinceCode ?? '';
    if (code.isNotEmpty) {
      for (final p in provinces) {
        if (p.code == code) {
          selected = p;
          break;
        }
      }
    }
    setState(() {
      _provinces = provinces;
      _province = selected;
    });
    if (selected != null) {
      await _loadCities(selected, preselectCode: widget.existing?.cityCode);
    }
  }

  Future<void> _loadCities(Province province, {String? preselectCode}) async {
    setState(() {
      _loadingCities = true;
      _cities = const [];
      _city = null;
    });
    final cities = await widget.service.citiesFor(province.code);
    if (!mounted) return;
    City? selected;
    if (preselectCode != null && preselectCode.isNotEmpty) {
      for (final c in cities) {
        if (c.code == preselectCode) {
          selected = c;
          break;
        }
      }
    }
    setState(() {
      _cities = cities;
      _city = selected;
      _loadingCities = false;
    });
  }

  @override
  void dispose() {
    _tinDebounce?.cancel();
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
      _username,
      _password,
      _idNumber,
    ]) {
      c.dispose();
    }
    for (final r in _serialRows) {
      r.dispose();
    }
    super.dispose();
  }

  // ── TIN duplicate check (advisory) ─────────────────────────────────────────
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
    // Editing the same record's own TIN shouldn't warn.
    if (widget.isEdit && tin == widget.existing!.tin) {
      if (mounted && _tinWarning.isNotEmpty) setState(() => _tinWarning = '');
      return;
    }
    final res =
        await widget.service.checkTinDuplicate(tin, _branchCode.text.trim());
    if (!mounted) return;
    setState(() {
      _tinWarning = res.duplicate
          ? 'A record with this TIN already exists'
              '${res.company.isEmpty ? '' : ' — ${res.company}'}.'
          : '';
    });
  }

  // ── Document extraction (AI/OCR) ────────────────────────────────────────────
  /// Step 1 — pick BIR document files. They're held locally until you tap
  /// Extract; nothing is sent yet.
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

  /// Step 3 — run OCR/AI over the uploaded documents (and the valid ID, if any)
  /// and fill the form.
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

  /// Pick a valid ID. It is read (OCR'd) together with the BIR documents when
  /// you tap "Attach & extract" — the combined endpoint is the only one that
  /// survives the production proxy. The ID detail fields stay editable.
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
      _validIdFile = null; // replaced; will be (re)read on next scan
    });
  }

  /// View the attached valid ID — the uploaded copy on the server, or the
  /// locally-picked file if it hasn't been sent yet.
  Future<void> _viewValidId() async {
    try {
      final f = _validIdFile;
      if (f != null && f.stored.isNotEmpty) {
        final url = '${widget.service.api.baseUrl}/uploads/${f.stored}';
        final ok = await launchUrl(Uri.parse(url),
            mode: LaunchMode.externalApplication);
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
      _pendingDocs.clear(); // now stored server-side, tracked by _extractionDocs
      if (r.validIdDoc != null) {
        _validIdFile = r.validIdDoc;
        _pendingValidIdPath = null;
        _pendingValidIdName = null;
        if (r.idNumber.isNotEmpty) _idNumber.text = r.idNumber;
        if (r.idBirthdate.isNotEmpty) _birthdate.text = r.idBirthdate;
      }
    });
    _checkTin();
    _toast(r.storedFiles.isEmpty
        ? 'Extraction complete — review the fields below.'
        : 'Auto-filled from ${r.storedFiles.length} document(s). Review below.');
  }

  // ── Documents ──────────────────────────────────────────────────────────────
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

  // ── Save ────────────────────────────────────────────────────────────────────
  List<SerialEntry> _collectSerials() {
    return _serialRows
        .where((r) => !r.isEmpty)
        .map((r) => r.toEntry())
        .toList();
  }

  String? _validate(List<SerialEntry> serials) {
    final missing = <String>[];
    void req(String label, bool ok) {
      if (!ok) missing.add(label);
    }

    req('Company name', _companyName.text.trim().isNotEmpty);
    req('TIN', _tin.text.trim().isNotEmpty);
    req('First name', _firstName.text.trim().isNotEmpty);
    req('Last name', _lastName.text.trim().isNotEmpty);
    if (_showLogin) {
      req('Username', _username.text.trim().isNotEmpty);
      req('Password', _password.text.isNotEmpty);
    }
    req('RDO', _rdo.text.trim().isNotEmpty);
    req('Address', _address.text.trim().isNotEmpty);
    if (_showLocation) {
      req('Province', _province != null);
      req('City', _city != null);
    }
    req('Business line', _businessLine.text.trim().isNotEmpty);
    req('Software name', (_softwareName ?? '').isNotEmpty);
    req('Accreditation no.', _accNumber.text.trim().isNotEmpty);
    req('At least one serial number',
        serials.any((s) => s.serialNumber.isNotEmpty));
    req('Valid ID', _pendingValidIdPath != null || _validIdFile != null);

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
      'username': _username.text.trim(),
      'password': _password.text,
      'is_vat': _isVat ? '1' : '0',
      'province': _province?.code ?? '',
      'province_text': _province?.name ?? '',
      'city': _city?.code ?? '',
      'city_text': _city?.name ?? '',
      // Without province/city the server's normal validation would reject the
      // save; extraction_mode switches it to the lenient rule set (company/TIN/
      // address/VAT), matching the web's BIR extraction add-customer.
      if (!_showLocation) 'extraction_mode': '1',
      'step2': '1',
      'serial_entries':
          jsonEncode(serials.map((e) => e.toJson()).toList()),
      // Documents are only processed by addcustomer (create). Harmless on edit.
      'document_files':
          jsonEncode(_extractionDocs.map((e) => e.toJson()).toList()),
      'valid_id_files': jsonEncode(_validIdFile == null
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
              }
            ]),
      'requirement_files':
          jsonEncode(_requirementDocs.map((e) => e.toJson()).toList()),
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
    // A valid ID picked but never run through a scan is uploaded plainly so it's
    // still saved; its details come from the (editable) fields.
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
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 6),
      ));
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final now = DateTime.now();
    DateTime initial = now;
    final existing = DateTime.tryParse(controller.text.trim());
    if (existing != null) initial = existing;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1990),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null) return;
    final iso = picked.toIso8601String().split('T').first;
    setState(() => controller.text = iso);
  }

  @override
  Widget build(BuildContext context) {
    return StationScaffold(
      stationNumber: widget.isEdit
          ? widget.existing!.id.toString().padLeft(2, '0')
          : '＋',
      stationLabel: 'BIR REGISTRATION',
      title: widget.isEdit ? 'Edit client.' : 'New client.',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      child: ListView(
        physics: const BouncingScrollPhysics(),
        children: [
          if (!widget.isEdit) ...[
            _extractionSection(context),
            const SizedBox(height: 36),
          ],
          _sectionHeader(context, 'Business'),
          _field('COMPANY NAME', _companyName,
              textCapitalization: TextCapitalization.characters),
          _field('TIN', _tin,
              keyboardType: TextInputType.number, onChanged: _onTinChanged),
          if (_tinWarning.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: Text(_tinWarning,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Brand.signal)),
            ),
          _field('BRANCH CODE', _branchCode),
          _dateField('TIN ISSUANCE DATE', _tinIssuance),
          _field('RDO', _rdo),
          _field('BUSINESS LINE', _businessLine),
          _field('BUSINESS ADDRESS', _address, maxLines: 2),
          const SizedBox(height: 12),
          _vatSelector(context),

          if (_showLocation) ...[
            const SizedBox(height: 36),
            _sectionHeader(context, 'Location'),
            _provinceDropdown(context),
            _cityDropdown(context),
          ],

          const SizedBox(height: 36),
          _sectionHeader(context, 'Point-of-sale'),
          _softwareDropdown(context),
          _softwareVersionDropdown(context),
          _field('ACCREDITATION NO.', _accNumber),
          const SizedBox(height: 24),
          _serialSection(context),

          const SizedBox(height: 36),
          _sectionHeader(context, 'Owner / contact'),
          _field('FIRST NAME', _firstName,
              textCapitalization: TextCapitalization.words),
          _field('MIDDLE NAME', _middleName,
              textCapitalization: TextCapitalization.words),
          _field('LAST NAME', _lastName,
              textCapitalization: TextCapitalization.words),
          _dateField('BIRTHDATE', _birthdate),
          _field('PHONE NUMBER', _phone, keyboardType: TextInputType.phone),
          _field('EMAIL', _email, keyboardType: TextInputType.emailAddress),
          if (_showLogin) ...[
            _field('USERNAME', _username),
            _field('PASSWORD', _password),
          ],

          const SizedBox(height: 36),
          _sectionHeader(context, 'Documents'),
          _documentsSection(context),

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
  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
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
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    TextInputType? keyboardType,
    int maxLines = 1,
    TextCapitalization textCapitalization = TextCapitalization.none,
    ValueChanged<String>? onChanged,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        textCapitalization: textCapitalization,
        onChanged: onChanged,
        inputFormatters: inputFormatters,
        style: Theme.of(context).textTheme.titleMedium,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  Widget _dateField(String label, TextEditingController controller) {
    return Padding(
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
                  icon: Icon(Icons.close, size: 16, color: context.brand.paperDim),
                  onPressed: () => setState(() => controller.clear()),
                ),
        ),
      ),
    );
  }

  Widget _vatSelector(BuildContext context) {
    return Row(
      children: [
        Text('VAT STATUS',
            style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(width: 16),
        _choiceChip('VAT', _isVat, () => setState(() => _isVat = true)),
        const SizedBox(width: 8),
        _choiceChip('NON-VAT', !_isVat, () => setState(() => _isVat = false)),
      ],
    );
  }

  Widget _choiceChip(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Brand.signal : Colors.transparent,
          border: Border.all(
              color: selected ? Brand.signal : context.brand.rule, width: 1),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: selected ? Brand.canvas : context.brand.paperDim,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }

  Widget _provinceDropdown(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DropdownButtonFormField<Province>(
        initialValue: _province,
        isExpanded: true,
        dropdownColor: context.brand.surface,
        style: Theme.of(context).textTheme.titleMedium,
        decoration: const InputDecoration(labelText: 'PROVINCE'),
        hint: Text(_provinces.isEmpty ? 'Loading…' : 'Select province',
            style: Theme.of(context).textTheme.bodyMedium),
        items: [
          for (final p in _provinces)
            DropdownMenuItem(value: p, child: Text(p.name)),
        ],
        onChanged: (p) {
          if (p == null) return;
          setState(() => _province = p);
          _loadCities(p);
        },
      ),
    );
  }

  Widget _cityDropdown(BuildContext context) {
    final disabled = _province == null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DropdownButtonFormField<City>(
        initialValue: _city,
        isExpanded: true,
        dropdownColor: context.brand.surface,
        style: Theme.of(context).textTheme.titleMedium,
        decoration: const InputDecoration(labelText: 'CITY / MUNICIPALITY'),
        hint: Text(
          disabled
              ? 'Select a province first'
              : (_loadingCities ? 'Loading…' : 'Select city'),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        items: [
          for (final c in _cities)
            DropdownMenuItem(value: c, child: Text(c.name)),
        ],
        onChanged: disabled ? null : (c) => setState(() => _city = c),
      ),
    );
  }

  Widget _softwareDropdown(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DropdownButtonFormField<String>(
        initialValue: _softwareName,
        isExpanded: true,
        dropdownColor: context.brand.surface,
        style: Theme.of(context).textTheme.titleMedium,
        decoration: const InputDecoration(labelText: 'SOFTWARE NAME'),
        hint: Text('Select software',
            style: Theme.of(context).textTheme.bodyMedium),
        items: [
          for (final s in _softwareOptions)
            DropdownMenuItem(value: s, child: Text(s)),
        ],
        onChanged: (s) => setState(() {
          _softwareName = s;
          final versions = _softwareVersions[s] ?? const <String>[];
          _softwareVersion = versions.length == 1 ? versions.first : null;
        }),
      ),
    );
  }

  Widget _softwareVersionDropdown(BuildContext context) {
    final versions = _softwareVersions[_softwareName] ?? const <String>[];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DropdownButtonFormField<String>(
        initialValue: _softwareVersion,
        isExpanded: true,
        dropdownColor: context.brand.surface,
        style: Theme.of(context).textTheme.titleMedium,
        decoration: const InputDecoration(labelText: 'SOFTWARE VERSION'),
        hint: Text(
            versions.isEmpty ? 'Select a software first' : 'Select version',
            style: Theme.of(context).textTheme.bodyMedium),
        items: [
          for (final v in versions) DropdownMenuItem(value: v, child: Text(v)),
        ],
        onChanged: versions.isEmpty
            ? null
            : (v) => setState(() => _softwareVersion = v),
      ),
    );
  }

  /// Valid Type choices for a serial row given what the OTHER rows already use.
  /// Rules (POS setup): Standalone is mutually exclusive with Server/Terminal,
  /// and only one Server is allowed (the rest must be Terminals).
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
      // A standalone setup — no Server/Terminal alongside it.
      opts = {'Standalone'};
    } else if (others.contains('Server') || others.contains('Terminal')) {
      // A server/terminal setup — no Standalone; only one Server.
      opts = {'Server', 'Terminal'};
      if (others.contains('Server')) opts.remove('Server');
    } else {
      opts = {'Server', 'Terminal', 'Standalone'};
    }
    // Always keep this row's own current value selectable.
    if (current != null && current.isNotEmpty) opts.add(current);
    return _serialTypeOptions.where((t) => opts.contains(t)).toList();
  }

  // ── Serial entries ──────────────────────────────────────────────────────────
  Widget _serialSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('SERIAL NUMBERS',
                style: Theme.of(context).textTheme.labelMedium),
            InkWell(
              onTap: () => setState(() => _serialRows.add(_SerialRow())),
              child: Row(
                children: [
                  const Icon(Icons.add, size: 14, color: Brand.signal),
                  const SizedBox(width: 4),
                  Text('ADD',
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: Brand.signal)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (int i = 0; i < _serialRows.length; i++)
          _serialRowWidget(context, i),
      ],
    );
  }

  Widget _serialRowWidget(BuildContext context, int index) {
    final row = _serialRows[index];
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
                child: DropdownButtonFormField<String>(
                  initialValue: row.type,
                  isExpanded: true,
                  dropdownColor: context.brand.surface,
                  style: Theme.of(context).textTheme.titleMedium,
                  decoration: const InputDecoration(labelText: 'TYPE'),
                  hint: Text('Type',
                      style: Theme.of(context).textTheme.bodyMedium),
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
              if (_serialRows.length > 1) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Remove',
                  icon: Icon(Icons.delete_outline,
                      size: 18, color: context.brand.paperDim),
                  onPressed: () => setState(() {
                    _serialRows.removeAt(index).dispose();
                  }),
                ),
              ],
            ],
          ),
          if (row.type == 'Server')
            DropdownButtonFormField<String>(
              initialValue: row.serverType,
              isExpanded: true,
              dropdownColor: context.brand.surface,
              style: Theme.of(context).textTheme.titleMedium,
              decoration: const InputDecoration(labelText: 'SERVER TYPE'),
              hint: Text('Server type',
                  style: Theme.of(context).textTheme.bodyMedium),
              items: [
                for (final t in _serverTypeOptions)
                  DropdownMenuItem(value: t, child: Text(t)),
              ],
              onChanged: (t) => setState(() => row.serverType = t),
            ),
          TextField(
            controller: row.sn,
            style: Theme.of(context).textTheme.titleMedium,
            decoration: const InputDecoration(labelText: 'SERIAL NUMBER'),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: row.brand,
                  style: Theme.of(context).textTheme.titleMedium,
                  decoration: const InputDecoration(labelText: 'BRAND'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: row.model,
                  style: Theme.of(context).textTheme.titleMedium,
                  decoration: const InputDecoration(labelText: 'MODEL'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Extraction (scan) section ────────────────────────────────────────────────
  Widget _extractionSection(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Scan documents', style: text.headlineMedium),
        const SizedBox(height: 8),
        const Hairline(),
        const SizedBox(height: 12),
        Text(
          'Upload the BIR 2303 / registration documents and (optionally) a valid '
          'ID, then tap Extract to auto-fill this form with AI. Review and '
          'correct everything below before saving.',
          style: text.bodySmall,
        ),

        // ── Step 1: documents ────────────────────────────────────────────────
        const SizedBox(height: 20),
        Text('DOCUMENTS', style: text.labelMedium),
        const SizedBox(height: 8),
        _uploadBox(
          context,
          _pendingDocs.isEmpty && _extractionDocs.isEmpty
              ? 'UPLOAD DOCUMENTS'
              : 'ADD MORE DOCUMENTS',
          Icons.upload_file,
          _extracting ? null : _pickBirDocs,
        ),
        const SizedBox(height: 8),
        for (int i = 0; i < _pendingDocs.length; i++)
          _fileRow(context, _pendingDocs[i].name,
              () => setState(() => _pendingDocs.removeAt(i))),
        for (int i = 0; i < _extractionDocs.length; i++)
          _fileRow(context, _extractionDocs[i].original,
              () => setState(() => _extractionDocs.removeAt(i))),

        // ── Step 2: valid ID ─────────────────────────────────────────────────
        const SizedBox(height: 24),
        _validIdBlock(context),

        // ── Step 3: extract ──────────────────────────────────────────────────
        const SizedBox(height: 24),
        if (_extracting)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.brand.surface,
              border: Border.all(color: context.brand.rule, width: 1),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Brand.signal),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Extracting… this can take up to a minute.',
                      style: text.bodySmall),
                ),
              ],
            ),
          )
        else
          SignalButton(
            label: 'Extract',
            icon: Icons.document_scanner_outlined,
            onPressed: _pendingDocs.isEmpty ? null : _extractNow,
          ),
      ],
    );
  }

  Widget _validIdBlock(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('VALID ID', style: text.labelMedium),
        const SizedBox(height: 8),
        Text(
          'Pick the ID type and attach a photo/scan — it is read together with '
          "your BIR documents to fill the owner's name and ID details.",
          style: text.bodySmall,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _validIdType,
          isExpanded: true,
          dropdownColor: context.brand.surface,
          style: text.titleMedium,
          decoration: const InputDecoration(labelText: 'ID TYPE'),
          hint: Text('Select ID type', style: text.bodyMedium),
          items: [
            for (final t in _validIdTypes)
              DropdownMenuItem(value: t.$1, child: Text(t.$2)),
          ],
          onChanged: (v) => setState(() => _validIdType = v),
        ),
        const SizedBox(height: 12),
        _uploadBox(
          context,
          (_pendingValidIdPath != null || _validIdFile != null)
              ? 'REPLACE VALID ID'
              : 'ATTACH VALID ID',
          Icons.badge_outlined,
          _extracting ? null : _pickValidId,
        ),
        if (_pendingValidIdPath != null) ...[
          const SizedBox(height: 8),
          _fileRow(context, _pendingValidIdName ?? 'Valid ID', () {
            setState(() {
              _pendingValidIdPath = null;
              _pendingValidIdName = null;
            });
          }, onView: _viewValidId),
          Padding(
            padding: const EdgeInsets.only(left: 24, bottom: 4),
            child: Text('Will be read when you tap Extract.',
                style: text.labelMedium),
          ),
        ],
        if (_validIdFile != null) ...[
          const SizedBox(height: 8),
          _fileRow(context, _validIdFile!.original, () {
            setState(() {
              _validIdFile = null;
              _idNumber.clear();
            });
          }, onView: _viewValidId),
        ],
        // ID number — editable, saved with the valid ID. (Birthdate lives in the
        // Owner / contact section, matching the web extraction preview.)
        if (_pendingValidIdPath != null || _validIdFile != null) ...[
          const SizedBox(height: 4),
          _field('ID NUMBER', _idNumber),
        ],
      ],
    );
  }

  /// Big, clearly-visible upload affordance — a full-width bordered box, used
  /// for both the documents and valid-ID pickers so they read as real inputs.
  Widget _uploadBox(
      BuildContext context, String label, IconData icon, VoidCallback? onTap) {
    final text = Theme.of(context).textTheme;
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
        decoration: BoxDecoration(
          color: context.brand.surface,
          border: Border.all(
            color: enabled ? Brand.signal : context.brand.rule,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 18, color: enabled ? Brand.signal : context.brand.paperDim),
            const SizedBox(width: 10),
            Text(
              label,
              style: text.labelLarge?.copyWith(
                color: enabled ? Brand.signal : context.brand.paperDim,
                fontSize: 12,
                letterSpacing: 2.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fileRow(BuildContext context, String name, VoidCallback onRemove,
      {VoidCallback? onView}) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(Icons.insert_drive_file_outlined,
              size: 16, color: context.brand.paperDim),
          const SizedBox(width: 8),
          Expanded(
            child: Text(name,
                style: text.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          if (onView != null) ...[
            InkWell(
              onTap: onView,
              child: Row(
                children: [
                  const Icon(Icons.visibility_outlined,
                      size: 15, color: Brand.signal),
                  const SizedBox(width: 4),
                  Text('VIEW',
                      style: text.labelMedium?.copyWith(color: Brand.signal)),
                ],
              ),
            ),
            const SizedBox(width: 14),
          ],
          InkWell(
            onTap: onRemove,
            child: Icon(Icons.close, size: 16, color: context.brand.paperDim),
          ),
        ],
      ),
    );
  }

  // ── Documents ──────────────────────────────────────────────────────────────
  Widget _documentsSection(BuildContext context) {
    final existing = widget.existing?.documents ?? const <CustomerDocument>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.isEdit) ...[
          // Existing docs are read-only (no per-document API), and new uploads
          // aren't processed by updateCustomer — so on edit we only display.
          if (existing.isEmpty)
            Text('No documents on file.',
                style: Theme.of(context).textTheme.bodySmall)
          else ...[
            _existingDocGroup(context, 'Extraction docs',
                existing.where((d) => d.docType == 'extraction_doc')),
            _existingDocGroup(context, 'Valid IDs',
                existing.where((d) => d.docType == 'valid_id')),
            _existingDocGroup(context, 'Requirements',
                existing.where((d) => d.docType == 'requirement')),
          ],
          const SizedBox(height: 8),
          Text(
            'Add or remove documents from the web portal — mobile edits keep '
            'the existing files.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ] else ...[
          // Extraction docs + valid IDs are attached at the top (scan flow).
          // Here we only collect the supporting requirement files.
          _uploadGroup(context, 'REQUIREMENTS', _requirementDocs),
        ],
      ],
    );
  }

  Widget _existingDocGroup(
      BuildContext context, String label, Iterable<CustomerDocument> docs) {
    final list = docs.toList();
    if (list.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          for (final d in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(Icons.insert_drive_file_outlined,
                      size: 16, color: context.brand.paperDim),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      d.originalFilename.isEmpty
                          ? d.storedFilename
                          : d.originalFilename,
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _uploadGroup(
      BuildContext context, String label, List<UploadedDoc> target) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            InkWell(
              onTap: _uploading ? null : () => _pickAndUpload(target),
              child: Row(
                children: [
                  Icon(Icons.upload_file, size: 14, color: Brand.signal),
                  const SizedBox(width: 4),
                  Text('ATTACH',
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: Brand.signal)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (target.isEmpty)
          Text('No files attached.',
              style: Theme.of(context).textTheme.bodySmall)
        else
          for (int i = 0; i < target.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(Icons.insert_drive_file_outlined,
                      size: 16, color: context.brand.paperDim),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(target[i].original,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  InkWell(
                    onTap: () => setState(() => target.removeAt(i)),
                    child: Icon(Icons.close,
                        size: 16, color: context.brand.paperDim),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

/// Mutable holder for one serial-entry row in the form.
class _SerialRow {
  _SerialRow({
    this.type,
    this.serverType,
    String sn = '',
    String brand = '',
    String model = '',
  })  : sn = TextEditingController(text: sn),
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
