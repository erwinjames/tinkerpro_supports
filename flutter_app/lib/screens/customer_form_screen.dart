import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../theme.dart';
import '../widgets/pick_source.dart';
import '../widgets/premium.dart';
import 'bir_register_widgets.dart';

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
  final _username = TextEditingController();
  final _password = TextEditingController();

  final bool _showLogin = false;

  String? _softwareName;
  String? _softwareVersion;
  bool _isVat = true;

  final bool _showLocation = false;
  List<Province> _provinces = const [];
  List<City> _cities = const [];
  Province? _province;
  City? _city;
  bool _loadingCities = false;

  final List<_SerialRow> _serialRows = [];

  final List<UploadedDoc> _extractionDocs = [];
  final List<UploadedDoc> _requirementDocs = [];
  bool _uploading = false;

  bool _extracting = false;
  final String _extractMode = 'accurate';
  final List<({String path, String name})> _pendingDocs = [];

  String? _validIdType;
  String? _pendingValidIdPath;
  String? _pendingValidIdName;
  UploadedDoc? _validIdFile;
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
    final picked = await pickWithSource(
      context,
      multiple: true,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'gif', 'webp'],
      cameraLabel: 'Take a photo of the document',
      fileLabel: 'Choose documents from files',
      onError: _toast,
    );
    if (picked.isEmpty || !mounted) return;
    setState(() => _pendingDocs.addAll(picked));
  }

  Future<void> _extractNow() async {
    if (_pendingDocs.isEmpty) {
      _toast('Upload at least one document first.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _extracting = true);
    final outcome = await widget.service.extractDocuments(
      paths: _pendingDocs.map((d) => d.path).toList(),
      mode: _extractMode,
      validIdPath: _pendingValidIdPath,
    );
    if (!mounted) return;
    final data = outcome.data;
    final r = data == null
        ? ExtractionResult.error(outcome.failure ?? 'Extraction failed.')
        : (data['error'] != null
              ? ExtractionResult.error(data['error'].toString())
              : widget.service.toExtractionResult(data));
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
    final picked = await pickWithSource(
      context,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'gif', 'webp'],
      cameraLabel: 'Take a photo of the ID',
      fileLabel: 'Choose image or PDF',
      onError: _toast,
    );
    if (picked.isEmpty || !mounted) return;
    final file = picked.first;
    setState(() {
      _pendingValidIdPath = file.path;
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
    final picked = await pickWithSource(
      context,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'gif', 'webp'],
      cameraLabel: 'Take a photo',
      fileLabel: 'Choose image or PDF',
      onError: _toast,
    );
    if (picked.isEmpty || !mounted) return;
    final path = picked.first.path;

    setState(() => _uploading = true);
    final doc = await widget.service.uploadDocument(path);
    if (!mounted) return;
    setState(() {
      _uploading = false;
      if (doc != null) target.add(doc);
    });
    if (doc == null) _toast('Upload failed. Please try again.');
  }

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
    req(
      'At least one serial number',
      serials.any((s) => s.serialNumber.isNotEmpty),
    );
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
      if (!_showLocation) 'extraction_mode': '1',
      'step2': '1',
      'serial_entries': jsonEncode(serials.map((e) => e.toJson()).toList()),
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
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 6)),
      );
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
      stationLabel: 'BIR Registration',
      title: widget.isEdit ? 'Edit client' : 'New client',
      subtitle: widget.isEdit
          ? widget.existing!.companyName
          : 'Scan documents or fill in manually',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      bottomBar: _saveBar(context),
      child: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 8),
        children: [
          if (!widget.isEdit) ...[
            _extractionSection(context),
            const SizedBox(height: 16),
          ],
          _sectionCard(
            context,
            title: 'Business information',
            subtitle: 'Registered details from the BIR 2303.',
            icon: Icons.business_rounded,
            children: [
              _field(
                'Company name',
                _companyName,
                required: true,
                textCapitalization: TextCapitalization.characters,
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: _field(
                      'TIN',
                      _tin,
                      required: true,
                      keyboardType: TextInputType.number,
                      onChanged: _onTinChanged,
                      bottom: _tinWarning.isEmpty ? 14 : 8,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: _field(
                      'Branch code',
                      _branchCode,
                      bottom: _tinWarning.isEmpty ? 14 : 8,
                    ),
                  ),
                ],
              ),
              if (_tinWarning.isNotEmpty) _tinWarningBanner(context),
              _dateField('TIN issuance date', _tinIssuance),
              _field('RDO', _rdo, required: true),
              _field('Business line', _businessLine, required: true),
              _field('Business address', _address, required: true, maxLines: 2),
              _vatSelector(context),
            ],
          ),
          if (_showLocation) ...[
            const SizedBox(height: 16),
            _sectionCard(
              context,
              title: 'Location',
              icon: Icons.location_on_rounded,
              children: [_provinceDropdown(context), _cityDropdown(context)],
            ),
          ],
          const SizedBox(height: 16),
          _sectionCard(
            context,
            title: 'Point-of-sale',
            subtitle: 'Accredited software installed for this client.',
            icon: Icons.point_of_sale_rounded,
            children: [
              _softwareDropdown(context),
              _softwareVersionDropdown(context),
              _field(
                'Accreditation no.',
                _accNumber,
                required: true,
                bottom: 0,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _serialSection(context),
          const SizedBox(height: 16),
          _sectionCard(
            context,
            title: 'Owner / contact',
            subtitle: 'The registered owner of the business.',
            icon: Icons.person_rounded,
            children: [
              _field(
                'First name',
                _firstName,
                required: true,
                textCapitalization: TextCapitalization.words,
              ),
              _field(
                'Middle name',
                _middleName,
                textCapitalization: TextCapitalization.words,
              ),
              _field(
                'Last name',
                _lastName,
                required: true,
                textCapitalization: TextCapitalization.words,
              ),
              _dateField('Birthdate', _birthdate),
              _field(
                'Phone number',
                _phone,
                keyboardType: TextInputType.phone,
                prefixIcon: Icons.phone_rounded,
              ),
              _field(
                'Email',
                _email,
                keyboardType: TextInputType.emailAddress,
                prefixIcon: Icons.mail_outline_rounded,
                bottom: _showLogin ? 14 : 0,
              ),
              if (_showLogin) ...[
                _field('Username', _username, required: true),
                _field('Password', _password, required: true, bottom: 0),
              ],
            ],
          ),
          const SizedBox(height: 16),
          _sectionCard(
            context,
            title: 'Documents',
            subtitle: widget.isEdit
                ? 'Files on record for this client.'
                : 'Supporting requirement files.',
            icon: Icons.folder_rounded,
            children: [_documentsSection(context)],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _saveBar(BuildContext context) {
    final b = context.brand;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: b.surface,
        border: Border(top: BorderSide(color: b.rule)),
        boxShadow: b.isDark
            ? const []
            : [
                BoxShadow(
                  color: Brand.navy.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, -4),
                ),
              ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(
            children: [
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
    );
  }

  Widget _sectionCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
    String? subtitle,
    Widget? trailing,
  }) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return AppCard(
      padding: const EdgeInsets.all(16),
      radius: Brand.radiusLg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: b.tint(b.signal, 0.12),
                  border: Border.all(color: b.signal.withValues(alpha: 0.4)),
                ),
                child: Icon(icon, size: 20, color: b.signal),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: text.titleMedium),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle, style: text.bodySmall),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing],
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String label, {bool required = false}) {
    final b = context.brand;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text.rich(
        TextSpan(
          text: label,
          children: [
            if (required)
              const TextSpan(
                text: ' *',
                style: TextStyle(color: Brand.danger),
              ),
          ],
        ),
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: b.paper,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _labeled(
    BuildContext context,
    String label,
    Widget child, {
    bool required = false,
    double bottom = 14,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label(context, label, required: required),
          child,
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
    bool required = false,
    IconData? prefixIcon,
    double bottom = 14,
  }) {
    return _labeled(
      context,
      label,
      TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        textCapitalization: textCapitalization,
        onChanged: onChanged,
        inputFormatters: inputFormatters,
        decoration: InputDecoration(
          hintText: 'Enter ${_hintLabel(label)}',
          prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: 20),
        ),
      ),
      required: required,
      bottom: bottom,
    );
  }

  static String _hintLabel(String label) {
    if (label.length > 1 && label[1] == label[1].toUpperCase()) return label;
    return label[0].toLowerCase() + label.substring(1);
  }

  Widget _dateField(String label, TextEditingController controller) {
    final b = context.brand;
    return _labeled(
      context,
      label,
      TextField(
        controller: controller,
        readOnly: true,
        onTap: () => _pickDate(controller),
        decoration: InputDecoration(
          hintText: 'YYYY-MM-DD',
          prefixIcon: const Icon(Icons.event_rounded, size: 20),
          suffixIcon: controller.text.isEmpty
              ? Icon(Icons.expand_more_rounded, size: 20, color: b.paperDim)
              : IconButton(
                  tooltip: 'Clear',
                  icon: Icon(Icons.close_rounded, size: 18, color: b.paperDim),
                  onPressed: () => setState(() => controller.clear()),
                ),
        ),
      ),
    );
  }

  Widget _tinWarningBanner(BuildContext context) {
    final b = context.brand;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Brand.radius),
        color: b.tint(Brand.warning, 0.12),
        border: Border.all(color: Brand.warning.withValues(alpha: 0.42)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: Brand.warning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _tinWarning,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: b.paper),
            ),
          ),
        ],
      ),
    );
  }

  Widget _vatSelector(BuildContext context) {
    return _labeled(
      context,
      'VAT status',
      ChoicePills<bool>(
        options: const [true, false],
        value: _isVat,
        labelOf: (v) => v ? 'VAT' : 'Non-VAT',
        onChanged: (v) => setState(() => _isVat = v),
      ),
      bottom: 0,
    );
  }

  InputDecoration _dropdownDecoration(IconData? icon) {
    return InputDecoration(
      prefixIcon: icon == null ? null : Icon(icon, size: 20),
    );
  }

  Widget _dropdownHint(BuildContext context, String hint) {
    return Text(
      hint,
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: context.brand.paperDim),
    );
  }

  Widget _provinceDropdown(BuildContext context) {
    return _labeled(
      context,
      'Province',
      DropdownButtonFormField<Province>(
        initialValue: _province,
        isExpanded: true,
        dropdownColor: context.brand.surface,
        borderRadius: BorderRadius.circular(Brand.radius),
        icon: const Icon(Icons.expand_more_rounded),
        decoration: _dropdownDecoration(Icons.map_rounded),
        hint: _dropdownHint(
          context,
          _provinces.isEmpty ? 'Loading…' : 'Select province',
        ),
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
      required: true,
    );
  }

  Widget _cityDropdown(BuildContext context) {
    final disabled = _province == null;
    return _labeled(
      context,
      'City / municipality',
      DropdownButtonFormField<City>(
        initialValue: _city,
        isExpanded: true,
        dropdownColor: context.brand.surface,
        borderRadius: BorderRadius.circular(Brand.radius),
        icon: const Icon(Icons.expand_more_rounded),
        decoration: _dropdownDecoration(Icons.location_city_rounded),
        hint: _dropdownHint(
          context,
          disabled
              ? 'Select a province first'
              : (_loadingCities ? 'Loading…' : 'Select city'),
        ),
        items: [
          for (final c in _cities)
            DropdownMenuItem(value: c, child: Text(c.name)),
        ],
        onChanged: disabled ? null : (c) => setState(() => _city = c),
      ),
      required: true,
      bottom: 0,
    );
  }

  Widget _softwareDropdown(BuildContext context) {
    return _labeled(
      context,
      'Software name',
      DropdownButtonFormField<String>(
        initialValue: _softwareName,
        isExpanded: true,
        dropdownColor: context.brand.surface,
        borderRadius: BorderRadius.circular(Brand.radius),
        icon: const Icon(Icons.expand_more_rounded),
        decoration: _dropdownDecoration(Icons.apps_rounded),
        hint: _dropdownHint(context, 'Select software'),
        items: [
          for (final s in _softwareOptions)
            DropdownMenuItem(
              value: s,
              child: Text(s, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (s) => setState(() {
          _softwareName = s;
          final versions = _softwareVersions[s] ?? const <String>[];
          _softwareVersion = versions.length == 1 ? versions.first : null;
        }),
      ),
      required: true,
    );
  }

  Widget _softwareVersionDropdown(BuildContext context) {
    final versions = _softwareVersions[_softwareName] ?? const <String>[];
    return _labeled(
      context,
      'Software version',
      DropdownButtonFormField<String>(
        initialValue: _softwareVersion,
        isExpanded: true,
        dropdownColor: context.brand.surface,
        borderRadius: BorderRadius.circular(Brand.radius),
        icon: const Icon(Icons.expand_more_rounded),
        decoration: _dropdownDecoration(Icons.new_releases_rounded),
        hint: _dropdownHint(
          context,
          versions.isEmpty ? 'Select a software first' : 'Select version',
        ),
        items: [
          for (final v in versions) DropdownMenuItem(value: v, child: Text(v)),
        ],
        onChanged: versions.isEmpty
            ? null
            : (v) => setState(() => _softwareVersion = v),
      ),
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

  Widget _serialSection(BuildContext context) {
    return _sectionCard(
      context,
      title: 'Serial numbers',
      subtitle: 'At least one serial number is required.',
      icon: Icons.memory_rounded,
      trailing: TextButton.icon(
        onPressed: () => setState(() => _serialRows.add(_SerialRow())),
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text('Add'),
      ),
      children: [
        for (int i = 0; i < _serialRows.length; i++)
          _serialRowWidget(context, i),
      ],
    );
  }

  Widget _serialRowWidget(BuildContext context, int index) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final row = _serialRows[index];
    final last = index == _serialRows.length - 1;
    return Container(
      margin: EdgeInsets.only(bottom: last ? 0 : 12),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: BoxDecoration(
        color: b.canvas,
        borderRadius: BorderRadius.circular(Brand.radiusLg),
        border: Border.all(color: b.signal.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: b.tint(b.signal, 0.14),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${index + 1}',
                  style: text.labelMedium?.copyWith(
                    color: b.signal,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Serial entry ${index + 1}',
                  style: text.titleSmall,
                ),
              ),
              if (_serialRows.length > 1)
                IconButton(
                  tooltip: 'Remove serial entry ${index + 1}',
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: Brand.danger,
                  ),
                  onPressed: () => setState(() {
                    _serialRows.removeAt(index).dispose();
                  }),
                )
              else
                const SizedBox(height: 44),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _labeled(
                  context,
                  'Type',
                  DropdownButtonFormField<String>(
                    initialValue: row.type,
                    isExpanded: true,
                    dropdownColor: b.surface,
                    borderRadius: BorderRadius.circular(Brand.radius),
                    icon: const Icon(Icons.expand_more_rounded),
                    decoration: _dropdownDecoration(null),
                    hint: _dropdownHint(context, 'Type'),
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
              ),
              if (row.type == 'Server') ...[
                const SizedBox(width: 12),
                Expanded(
                  child: _labeled(
                    context,
                    'Server type',
                    DropdownButtonFormField<String>(
                      initialValue: row.serverType,
                      isExpanded: true,
                      dropdownColor: b.surface,
                      borderRadius: BorderRadius.circular(Brand.radius),
                      icon: const Icon(Icons.expand_more_rounded),
                      decoration: _dropdownDecoration(null),
                      hint: _dropdownHint(context, 'Server type'),
                      items: [
                        for (final t in _serverTypeOptions)
                          DropdownMenuItem(value: t, child: Text(t)),
                      ],
                      onChanged: (t) => setState(() => row.serverType = t),
                    ),
                  ),
                ),
              ],
            ],
          ),
          _field('Serial number', row.sn, prefixIcon: Icons.qr_code_rounded),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _field('Brand', row.brand, bottom: 0)),
              const SizedBox(width: 12),
              Expanded(child: _field('Model', row.model, bottom: 0)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _extractionSection(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return _sectionCard(
      context,
      title: 'Scan documents',
      subtitle: 'Auto-fill this form from the BIR documents.',
      icon: Icons.document_scanner_rounded,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Brand.radius),
            color: b.tint(Brand.info, 0.12),
            border: Border.all(color: Brand.info.withValues(alpha: 0.4)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: Brand.info,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Upload the BIR 2303 / registration documents and (optionally) a valid '
                  'ID, then tap Extract to auto-fill this form with AI. Review and '
                  'correct everything below before saving.',
                  style: text.bodySmall?.copyWith(color: b.paper),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _stepLabel(context, 1, 'BIR documents'),
        const SizedBox(height: 8),
        _uploadBox(
          context,
          _pendingDocs.isEmpty && _extractionDocs.isEmpty
              ? 'Upload documents'
              : 'Add more documents',
          Icons.upload_file_rounded,
          _extracting ? null : _pickBirDocs,
          hint: 'PDF, JPG, PNG, GIF or WEBP · multiple allowed',
        ),
        if (_pendingDocs.isNotEmpty || _extractionDocs.isNotEmpty)
          const SizedBox(height: 8),
        for (int i = 0; i < _pendingDocs.length; i++)
          _fileRow(
            context,
            _pendingDocs[i].name,
            () => setState(() => _pendingDocs.removeAt(i)),
            caption: 'Ready to extract',
          ),
        for (int i = 0; i < _extractionDocs.length; i++)
          _fileRow(
            context,
            _extractionDocs[i].original,
            () => setState(() => _extractionDocs.removeAt(i)),
            caption: 'Uploaded',
            done: true,
          ),
        const SizedBox(height: 16),
        const Hairline(),
        const SizedBox(height: 16),
        _validIdBlock(context),
        const SizedBox(height: 16),
        if (_extracting)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Brand.radiusLg),
              color: b.tint(b.signal, 0.12),
              border: Border.all(color: b.signal.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: b.signal,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Extracting… this can take up to a minute.',
                    style: text.bodySmall?.copyWith(color: b.paper),
                  ),
                ),
              ],
            ),
          )
        else
          SignalButton(
            label: 'Extract',
            icon: Icons.auto_awesome_rounded,
            onPressed: _pendingDocs.isEmpty ? null : _extractNow,
          ),
      ],
    );
  }

  Widget _stepLabel(BuildContext context, int step, String label) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Brand.orange,
          ),
          child: Text(
            '$step',
            style: const TextStyle(
              color: Brand.onSignal,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(label, style: text.titleSmall),
      ],
    );
  }

  Widget _validIdBlock(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final hasId = _pendingValidIdPath != null || _validIdFile != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepLabel(context, 2, 'Valid ID'),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 28),
          child: Text(
            'Pick the ID type and attach a photo/scan — it is read together with '
            "your BIR documents to fill the owner's name and ID details.",
            style: text.bodySmall,
          ),
        ),
        const SizedBox(height: 12),
        _labeled(
          context,
          'ID type',
          DropdownButtonFormField<String>(
            initialValue: _validIdType,
            isExpanded: true,
            dropdownColor: context.brand.surface,
            borderRadius: BorderRadius.circular(Brand.radius),
            icon: const Icon(Icons.expand_more_rounded),
            decoration: _dropdownDecoration(Icons.badge_rounded),
            hint: _dropdownHint(context, 'Select ID type'),
            items: [
              for (final t in _validIdTypes)
                DropdownMenuItem(value: t.$1, child: Text(t.$2)),
            ],
            onChanged: (v) => setState(() => _validIdType = v),
          ),
          required: true,
          bottom: 12,
        ),
        _uploadBox(
          context,
          hasId ? 'Replace valid ID' : 'Attach valid ID',
          Icons.add_photo_alternate_rounded,
          _extracting ? null : _pickValidId,
          hint: (_validIdType ?? '').isEmpty
              ? 'Select the ID type first'
              : 'Photo or scan · PDF, JPG, PNG, GIF or WEBP',
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
            caption: 'Will be read when you tap Extract.',
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
            caption: 'Uploaded',
            done: true,
          ),
        ],
        if (hasId) ...[
          const SizedBox(height: 8),
          _field(
            'ID number',
            _idNumber,
            prefixIcon: Icons.numbers_rounded,
            bottom: 0,
          ),
        ],
      ],
    );
  }

  Widget _uploadBox(
    BuildContext context,
    String label,
    IconData icon,
    VoidCallback? onTap, {
    String? hint,
    bool busy = false,
  }) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final enabled = onTap != null;
    final accent = enabled ? b.signal : b.paperDim;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(Brand.radiusLg),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Brand.radiusLg),
          color: enabled ? b.tint(b.signal, 0.08) : b.surfaceHi,
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Brand.radiusLg),
          child: CustomPaint(
            painter: BirDashedBorderPainter(
              color: enabled ? b.tint(b.signal, 0.6) : b.rule,
              radius: Brand.radiusLg,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
              child: Column(
                children: [
                  if (busy)
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: b.signal,
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: b.tint(accent, 0.14),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Icon(icon, size: 20, color: accent),
                    ),
                  const SizedBox(height: 10),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: text.titleSmall?.copyWith(
                      color: enabled ? b.signalInk : b.paperDim,
                    ),
                  ),
                  if (hint != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      hint,
                      textAlign: TextAlign.center,
                      style: text.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static IconData _fileIcon(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.pdf')) return Icons.picture_as_pdf_rounded;
    if (RegExp(r'\.(png|jpe?g|gif|webp|heic|bmp)$').hasMatch(n)) {
      return Icons.image_rounded;
    }
    return Icons.insert_drive_file_rounded;
  }

  Widget _fileRow(
    BuildContext context,
    String name,
    VoidCallback? onRemove, {
    VoidCallback? onView,
    String? caption,
    bool done = false,
  }) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final accent = done ? Brand.success : b.signal;
    return FadeSlideIn(
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Brand.radius),
          color: b.tint(accent, 0.1),
          border: Border.all(color: accent.withValues(alpha: 0.28)),
        ),
        child: Row(
          children: [
            IconTile(
              icon: _fileIcon(name),
              color: accent,
              size: 34,
              iconSize: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (caption != null)
                    Text(
                      caption,
                      style: text.bodySmall?.copyWith(
                        color: done ? Brand.success : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (onView != null)
              TextButton.icon(
                onPressed: onView,
                style: TextButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                icon: const Icon(Icons.visibility_rounded, size: 16),
                label: const Text('View'),
              ),
            if (onRemove != null)
              IconButton(
                tooltip: 'Remove $name',
                onPressed: onRemove,
                icon: Icon(Icons.close_rounded, size: 18, color: b.paperDim),
              ),
          ],
        ),
      ),
    );
  }

  Widget _documentsSection(BuildContext context) {
    final existing = widget.existing?.documents ?? const <CustomerDocument>[];
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.isEdit) ...[
          if (existing.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: b.surfaceHi,
                borderRadius: BorderRadius.circular(Brand.radius),
              ),
              child: Column(
                children: [
                  Icon(Icons.folder_off_rounded, size: 24, color: b.paperDim),
                  const SizedBox(height: 6),
                  Text('No documents on file.', style: text.bodySmall),
                ],
              ),
            )
          else ...[
            _existingDocGroup(
              context,
              'Extraction docs',
              existing.where((d) => d.docType == 'extraction_doc'),
            ),
            _existingDocGroup(
              context,
              'Valid IDs',
              existing.where((d) => d.docType == 'valid_id'),
            ),
            _existingDocGroup(
              context,
              'Requirements',
              existing.where((d) => d.docType == 'requirement'),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 16, color: b.paperDim),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Add or remove documents from the web portal — mobile edits keep '
                  'the existing files.',
                  style: text.bodySmall,
                ),
              ),
            ],
          ),
        ] else ...[
          _uploadGroup(context, 'Requirements', _requirementDocs),
        ],
      ],
    );
  }

  Widget _existingDocGroup(
    BuildContext context,
    String label,
    Iterable<CustomerDocument> docs,
  ) {
    final list = docs.toList();
    if (list.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _label(context, label)),
              StatusPill(
                label: '${list.length}',
                color: context.brand.paperDim,
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final d in list)
            _fileRow(
              context,
              d.originalFilename.isEmpty
                  ? d.storedFilename
                  : d.originalFilename,
              null,
            ),
        ],
      ),
    );
  }

  Widget _uploadGroup(
    BuildContext context,
    String label,
    List<UploadedDoc> target,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label(context, label),
        _uploadBox(
          context,
          _uploading ? 'Uploading…' : 'Attach file',
          Icons.upload_file_rounded,
          _uploading ? null : () => _pickAndUpload(target),
          hint: target.isEmpty
              ? 'No files attached · PDF, JPG, PNG, GIF or WEBP'
              : '${target.length} file(s) attached',
          busy: _uploading,
        ),
        if (target.isNotEmpty) const SizedBox(height: 8),
        for (int i = 0; i < target.length; i++)
          _fileRow(
            context,
            target[i].original,
            () => setState(() => target.removeAt(i)),
            caption: 'Uploaded',
            done: true,
          ),
      ],
    );
  }
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
