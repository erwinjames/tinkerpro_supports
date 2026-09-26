import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../services/bir_register_logic.dart';
import '../services/services.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'bir_register_widgets.dart';

enum _PdfStage { upload, review, form }

class BirPdfRegisterScreen extends StatefulWidget {
  const BirPdfRegisterScreen({
    super.key,
    required this.service,
    required this.invoiceNumber,
  });

  final CustomerService service;
  final String invoiceNumber;

  @override
  State<BirPdfRegisterScreen> createState() => _BirPdfRegisterScreenState();
}

class _BirPdfRegisterScreenState extends State<BirPdfRegisterScreen> {
  CustomerService get _svc => widget.service;

  _PdfStage _stage = _PdfStage.upload;
  final _scroll = ScrollController();

  String? _pdfPath;
  String? _pdfName;
  bool _processing = false;
  Map<String, dynamic> _data = const {};
  Map<String, dynamic> _sw = const {};

  String? _vatStatus;
  bool _vatError = false;

  bool _edit = false;
  final _softwareName = TextEditingController();
  final _acc = TextEditingController();
  final _company = TextEditingController();
  final _tin = TextEditingController();
  final _rdo = TextEditingController();
  final _address = TextEditingController();
  final _firstName = TextEditingController();
  final _middleName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _blCode = TextEditingController();
  String _businessLine = '';
  String? _isVat;
  final List<BirSnRow> _rows = [BirSnRow()];

  List<Province> _provinces = const [];
  List<City> _cities = const [];
  Province? _province;
  City? _city;
  bool _loadingCities = false;
  List<PsicItem> _psic = const [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _svc.provinces().then((p) {
      if (mounted) setState(() => _provinces = p);
    });
    _svc.psicList().then((p) {
      if (mounted) setState(() => _psic = p);
    });
  }

  @override
  void dispose() {
    for (final c in [
      _softwareName,
      _acc,
      _company,
      _tin,
      _rdo,
      _address,
      _firstName,
      _middleName,
      _lastName,
      _email,
      _username,
      _password,
      _blCode,
    ]) {
      c.dispose();
    }
    for (final r in _rows) {
      r.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  void _toast(String m) {
    if (mounted) birToast(context, m);
  }

  void _scrollTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  Future<void> _pickPdf() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
    } catch (_) {
      _toast('Could not open the file picker.');
      return;
    }
    final f = result?.files.singleOrNull;
    if (f?.path == null) return;
    setState(() {
      _pdfPath = f!.path;
      _pdfName = f.name;
    });
  }

  Future<void> _extract() async {
    if (_pdfPath == null || _processing) return;
    setState(() => _processing = true);
    final r = await _svc.extractBirPdf(_pdfPath!);
    if (!mounted) return;
    setState(() => _processing = false);
    if (r.data == null) {
      _toast(r.error ?? 'Failed to process PDF file. Please try again.');
      return;
    }
    final data = r.data!;
    final swList = data['SoftwareInfo'];
    final sw = (swList is List && swList.isNotEmpty && swList[0] is Map)
        ? Map<String, dynamic>.from(swList[0] as Map)
        : <String, dynamic>{};
    final normalized = BirLogic.normalizeRegistrationType(
      BirLogic.s(data['RegistrationType']),
    );
    final owner = BirLogic.splitOwnerNameParts(BirLogic.s(data['OwnerName']));
    setState(() {
      _data = data;
      _sw = sw;
      _vatStatus = normalized == 'VAT'
          ? '1'
          : (normalized == 'NON-VAT' ? '0' : null);
      _vatError = false;
      _company.text = BirLogic.s(data['BusinessName']);
      _tin.text = BirLogic.s(data['TIN_BranchCode']);
      _address.text = BirLogic.s(data['BusinessAddress']);
      _rdo.text = BirLogic.s(data['RDOCode']);
      _firstName.text = owner.first;
      _middleName.text = owner.middle;
      _lastName.text = owner.last;
      _acc.text = BirLogic.s(sw['AccreditationNumber']);
      _softwareName.text = BirLogic.s(sw['SoftwareName']);
      _setSnFromString(BirLogic.s(sw['SerialNumber']));
      _stage = _PdfStage.review;
    });
    _scrollTop();
    _hydrateSerialMeta();
  }

  void _setSnFromString(String raw) {
    final parts = raw
        .split('/')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    for (final r in _rows) {
      r.dispose();
    }
    _rows
      ..clear()
      ..add(BirSnRow(sn: parts.isEmpty ? '' : parts.first));
    for (var i = 1; i < parts.length; i++) {
      _rows.add(BirSnRow(sn: parts[i]));
    }
  }

  Future<void> _hydrateSerialMeta() async {
    for (final row in List<BirSnRow>.from(_rows)) {
      final sn = row.sn.text.trim();
      if (sn.isEmpty) continue;
      final meta = await _svc.serialMeta(sn);
      if (!mounted || meta == null || !_rows.contains(row)) continue;
      setState(() {
        final type = BirLogic.s(meta['serial_number_type']);
        if (type.isNotEmpty) {
          row.type = type;
          if (type == 'Server') {
            row.serverType = BirLogic.s(meta['server_type']);
          }
        }
        final brand = BirLogic.s(meta['brand']);
        final model = BirLogic.s(meta['model']);
        if (brand.isNotEmpty) row.brand.text = brand;
        if (model.isNotEmpty) row.model.text = model;
      });
    }
  }

  void _confirmReview() {
    if (_vatStatus == null) {
      setState(() => _vatError = true);
      return;
    }
    setState(() {
      _vatError = false;
      _isVat = _vatStatus;
      _stage = _PdfStage.form;
    });
    _scrollTop();
  }

  Future<void> _loadCities(Province p) async {
    setState(() {
      _province = p;
      _city = null;
      _cities = const [];
      _loadingCities = true;
    });
    final cities = await _svc.citiesFor(p.code);
    if (!mounted) return;
    setState(() {
      _cities = cities;
      _loadingCities = false;
    });
  }

  List<Map<String, String>> get _entries => _rows
      .map(
        (r) => {
          'serial_number_type': r.type.trim(),
          'server_type': r.serverType.trim(),
          'serial_number': r.sn.text.trim(),
          'brand': r.brand.text.trim(),
          'model': r.model.text.trim(),
        },
      )
      .toList();

  Future<void> _save() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    if (!_edit) {
      final required = <(String, TextEditingController)>[
        ('First Name', _firstName),
        ('Last Name', _lastName),
        ('Email', _email),
        ('Username', _username),
        ('Password', _password),
      ];
      for (final f in required) {
        if (f.$2.text.trim().isEmpty) {
          _toast('"${f.$1}" is required.');
          return;
        }
      }
      if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email.text.trim())) {
        _toast('Enter a valid email address.');
        return;
      }
    }
    if (_isVat == null) {
      _toast('Please select VAT status!');
      return;
    }
    final entries = _entries;
    final snList = <String>[];
    for (final e in entries) {
      final sn = e['serial_number']!;
      if (sn.isNotEmpty && !snList.contains(sn)) snList.add(sn);
    }
    final meaningful = entries
        .where((e) => e.values.any((v) => v.isNotEmpty))
        .toList();
    final fields = <String, String>{
      'customer_id': '',
      'invoice_number': widget.invoiceNumber,
      'pdf_file': BirLogic.s(_data['filename']),
      'bir_registration_extracted': '1',
      'softwarename': _softwareName.text,
      'acc_number': _acc.text,
      'sn': snList.join('/'),
      'serial_entries': meaningful.isEmpty ? '' : jsonEncode(meaningful),
      'companyname': _company.text,
      'tin': _tin.text,
      'rdo': _rdo.text,
      'address': _address.text,
      'min': '',
      'ptu': '',
      'pos_date_issued': '',
      'province': _province?.code ?? '',
      'province_text': _province?.name ?? '',
      'city': _city?.code ?? '',
      'city_text': _city?.name ?? '',
      'businessline': _businessLine,
      'businesslinecode': _blCode.text,
      'firstname': _firstName.text,
      'middlename': _middleName.text,
      'lastname': _lastName.text,
      'email': _email.text,
      'username': _username.text,
      'password': _password.text,
      'is_vat': _isVat!,
    };
    setState(() => _saving = true);
    final res = await _svc.addCustomer(fields);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.networkError != null) {
      _toast('An error occurred: ${res.networkError}');
      return;
    }
    if (!res.ok) {
      _toast('Customer Not Added: ${res.message}');
      return;
    }
    _toast('Customer Added Successfully');
    Navigator.of(context).pop(true);
  }

  Future<void> _handleBack() async {
    if (_processing || _saving) return;
    switch (_stage) {
      case _PdfStage.upload:
        Navigator.of(context).pop();
      case _PdfStage.review:
        setState(() => _stage = _PdfStage.upload);
      case _PdfStage.form:
        final ok = await birConfirm(
          context,
          title: 'Discard this registration?',
          message: 'The extracted data and your edits will be lost.',
        );
        if (ok && mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final idx = switch (_stage) {
      _PdfStage.upload => 1,
      _PdfStage.review => 2,
      _PdfStage.form => 3,
    };
    return PopScope(
      canPop: _stage == _PdfStage.upload && !_processing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: StationScaffold(
        stationLabel: 'BIR Registration',
        title: switch (_stage) {
          _PdfStage.upload => 'Upload BIR Registration',
          _PdfStage.review => 'Review Extracted Data',
          _PdfStage.form => 'Application for Registration',
        },
        compact: true,
        showBottomBrand: false,
        onBack: _handleBack,
        belowRule: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: BirStepper(
            steps: const ['Invoice', 'Upload PDF', 'Review', 'Application'],
            current: idx,
          ),
        ),
        bottomBar: _bottomBar(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                controller: _scroll,
                children: switch (_stage) {
                  _PdfStage.upload => _uploadView(context),
                  _PdfStage.review => _reviewView(context),
                  _PdfStage.form => _formView(context),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar() {
    switch (_stage) {
      case _PdfStage.upload:
        return BirBottomBar(
          children: [
            Expanded(
              child: SignalButton(
                label: _processing ? 'Processing...' : 'Continue',
                busy: _processing,
                onPressed: _pdfPath == null ? null : _extract,
              ),
            ),
          ],
        );
      case _PdfStage.review:
        return BirBottomBar(
          children: [
            Expanded(
              child: SignalButton(
                label: 'Confirm & Save',
                icon: Icons.check_circle_rounded,
                onPressed: _confirmReview,
              ),
            ),
          ],
        );
      case _PdfStage.form:
        return BirBottomBar(
          children: [
            Expanded(
              child: SignalButton(
                label: _saving ? 'Saving...' : 'Confirm & Save',
                icon: Icons.check_circle_rounded,
                busy: _saving,
                onPressed: _saving ? null : _save,
              ),
            ),
          ],
        );
    }
  }

  List<Widget> _uploadView(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return [
      BirSection(
        title: 'Upload BIR Registration',
        icon: Icons.picture_as_pdf_rounded,
        iconColor: Brand.danger,
        children: [
          Text.rich(
            TextSpan(
              style: text.bodySmall,
              children: [
                const TextSpan(
                  text:
                      'Upload the BIR Application of Registration (.PDF) from ',
                ),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: GestureDetector(
                    onTap: () => launchUrl(
                      Uri.parse('https://eaccreg.bir.gov.ph'),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: Text(
                      'eaccreg.bir.gov.ph',
                      style: text.bodySmall?.copyWith(
                        color: b.signalInk,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (_pdfPath == null)
            BirUploadTile(
              label: 'Select PDF File',
              icon: Icons.cloud_upload_rounded,
              onTap: _processing ? null : _pickPdf,
              hint: 'PDF files only',
            )
          else
            BirFileRow(
              name: _pdfName ?? 'BIR Registration.pdf',
              caption: 'Ready to extract',
              icon: Icons.picture_as_pdf_rounded,
              iconColor: Brand.danger,
              onRemove: _processing
                  ? null
                  : () => setState(() {
                      _pdfPath = null;
                      _pdfName = null;
                    }),
            ),
        ],
      ),
    ];
  }

  List<Widget> _reviewView(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    var itemIndex = 0;
    Widget item(IconData icon, String label, String value) {
      final index = itemIndex++;
      final filled = value.isNotEmpty;
      return FadeSlideIn(
        index: index,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Brand.radius),
            color: filled ? b.tint(b.signal, 0.10) : b.surfaceHi,
            border: Border.all(
              color: b.signal.withValues(alpha: filled ? 0.28 : 0.14),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 14, color: b.signal),
                  const SizedBox(width: 6),
                  Text(
                    label.toUpperCase(),
                    style: text.labelSmall?.copyWith(
                      color: b.paperDim,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                value.isEmpty ? '—' : value,
                style: text.titleSmall?.copyWith(
                  color: filled ? b.paper : b.paperDim,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return [
      BirSection(
        title: 'Extraction Checkpoint',
        subtitle:
            'Scan the captured details, confirm the VAT setup, and continue once everything matches the uploaded BIR registration.',
        icon: Icons.fact_check_rounded,
        children: [
          item(
            Icons.business_rounded,
            'Company Name',
            BirLogic.s(_data['BusinessName']),
          ),
          item(Icons.tag_rounded, 'TIN', BirLogic.s(_data['TIN_BranchCode'])),
          item(Icons.place_rounded, 'RDO', BirLogic.s(_data['RDOCode'])),
          item(
            Icons.location_on_rounded,
            'Business Address',
            BirLogic.s(_data['BusinessAddress']),
          ),
          item(
            Icons.verified_rounded,
            'Accreditation No.',
            BirLogic.s(_sw['AccreditationNumber']),
          ),
          item(
            Icons.desktop_windows_rounded,
            'Software Name',
            BirLogic.s(_sw['SoftwareName']),
          ),
          item(
            Icons.qr_code_rounded,
            'Serial Number',
            BirLogic.s(_sw['SerialNumber']),
          ),
          item(
            Icons.person_rounded,
            'Owner Name',
            BirLogic.s(_data['OwnerName']),
          ),
        ],
      ),
      const SizedBox(height: 16),
      BirSection(
        title: 'VAT Registration',
        subtitle:
            'Pick the registration type before saving the extracted record into the client form.',
        icon: Icons.request_quote_rounded,
        children: [
          BirDropdown<String>(
            value: _vatStatus,
            hint: 'Choose status',
            items: const [
              DropdownMenuItem(value: '1', child: Text('VAT Registered')),
              DropdownMenuItem(value: '0', child: Text('Non-VAT Registered')),
            ],
            onChanged: (v) => setState(() {
              _vatStatus = v;
              _vatError = false;
            }),
          ),
          if (_vatError)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_rounded,
                    size: 14,
                    color: Brand.danger,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'VAT selection is required.',
                    style: text.bodySmall?.copyWith(color: Brand.danger),
                  ),
                ],
              ),
            ),
        ],
      ),
    ];
  }

  List<Widget> _formView(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final ro = !_edit;
    final q = _blCode.text.trim();
    final suggestions = q.isEmpty || _businessLine.isNotEmpty
        ? const <PsicItem>[]
        : BirLogic.searchPsic(_psic, q).take(30).toList();
    return [
      Text(
        'Complete the registration details for sales machines and sworn statement declaration.',
        style: text.bodySmall,
      ),
      const SizedBox(height: 12),
      AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        radius: Brand.radiusLg,
        borderColor: _edit ? b.signal.withValues(alpha: 0.4) : null,
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _edit,
          onChanged: (v) => setState(() => _edit = v),
          secondary: Icon(
            _edit ? Icons.lock_open_rounded : Icons.lock_rounded,
            color: _edit ? b.signal : b.paperDim,
          ),
          title: Text(_edit ? 'Editing Active' : 'Enable Edit'),
        ),
      ),
      const SizedBox(height: 16),
      BirSection(
        title: 'Sales machine',
        icon: Icons.point_of_sale_rounded,
        children: [
          BirField(
            label: 'Software Name',
            controller: _softwareName,
            readOnly: ro,
            prefixIcon: Icons.desktop_windows_rounded,
          ),
          BirField(
            label: 'Accreditation No.',
            controller: _acc,
            readOnly: ro,
            prefixIcon: Icons.verified_rounded,
          ),
          Row(
            children: [
              Expanded(
                child: Text('Serial Number Entries', style: text.labelLarge),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _rows.add(BirSnRow())),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < _rows.length; i++) _snCard(context, i, ro),
        ],
      ),
      const SizedBox(height: 16),
      BirSection(
        title: 'Business',
        icon: Icons.business_rounded,
        children: [
          BirField(label: 'Company Name', controller: _company, readOnly: ro),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: BirField(label: 'TIN', controller: _tin, readOnly: ro),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: BirField(label: 'RDO', controller: _rdo, readOnly: ro),
              ),
            ],
          ),
          BirField(
            label: 'Business Address',
            controller: _address,
            readOnly: ro,
            maxLines: 2,
            bottom: 0,
          ),
        ],
      ),
      const SizedBox(height: 16),
      BirSection(
        title: 'Sworn Statement & Declaration',
        icon: Icons.gavel_rounded,
        children: [
          BirLabeled(
            label: 'Province',
            child: BirDropdown<Province>(
              value: _province,
              hint: _provinces.isEmpty ? 'Loading…' : 'Select province',
              icon: Icons.map_rounded,
              items: [
                for (final p in _provinces)
                  DropdownMenuItem(value: p, child: Text(p.name)),
              ],
              onChanged: (p) {
                if (p != null) _loadCities(p);
              },
            ),
          ),
          BirLabeled(
            label: 'City / Municipality',
            child: BirDropdown<City>(
              value: _city,
              hint: _province == null
                  ? 'Select a province first'
                  : (_loadingCities ? 'Loading…' : 'Select city'),
              icon: Icons.location_city_rounded,
              items: [
                for (final c in _cities)
                  DropdownMenuItem(value: c, child: Text(c.name)),
              ],
              onChanged: _province == null
                  ? null
                  : (c) => setState(() => _city = c),
            ),
          ),
          BirLabeled(
            label: 'Business Line (Sub Code)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _blCode,
                  maxLines: null,
                  onChanged: (_) => setState(() => _businessLine = ''),
                  decoration: const InputDecoration(
                    hintText: 'Enter Sub Code',
                    prefixIcon: Icon(Icons.work_outline_rounded, size: 20),
                  ),
                ),
                if (suggestions.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    constraints: const BoxConstraints(maxHeight: 220),
                    decoration: BoxDecoration(
                      color: b.surface,
                      borderRadius: BorderRadius.circular(Brand.radiusSm),
                      border: Border.all(color: b.rule),
                    ),
                    child: ListView(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      children: [
                        for (final p in suggestions)
                          InkWell(
                            onTap: () => setState(() {
                              _blCode.text = p.label;
                              _businessLine = p.description;
                              FocusScope.of(context).unfocus();
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: b.rule),
                                ),
                              ),
                              child: Text(p.label, style: text.bodyMedium),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: BirField(
                  label: 'First Name',
                  controller: _firstName,
                  required: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: BirField(label: 'Middle Name', controller: _middleName),
              ),
            ],
          ),
          BirField(label: 'Last Name', controller: _lastName, required: true),
          BirField(
            label: 'Email',
            controller: _email,
            required: true,
            keyboardType: TextInputType.emailAddress,
            prefixIcon: Icons.mail_outline_rounded,
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: BirField(
                  label: 'Username',
                  controller: _username,
                  required: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: BirField(
                  label: 'Password',
                  controller: _password,
                  required: true,
                  bottom: 0,
                ),
              ),
            ],
          ),
        ],
      ),
      const SizedBox(height: 16),
      BirSection(
        title: 'VAT Registration',
        subtitle: 'Select the registration type for this client.',
        icon: Icons.request_quote_rounded,
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: '1', label: Text('VAT')),
              ButtonSegment(value: '0', label: Text('Non-VAT')),
            ],
            emptySelectionAllowed: true,
            selected: {?_isVat},
            onSelectionChanged: (s) =>
                setState(() => _isVat = s.isEmpty ? null : s.first),
          ),
        ],
      ),
      const SizedBox(height: 16),
    ];
  }

  Widget _snCard(BuildContext context, int index, bool ro) {
    final b = context.brand;
    final row = _rows[index];
    final types = _rows.map((r) => r.type).toList();
    final typeOptions = BirLogic.serialTypeOptions(types, index);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
      decoration: BoxDecoration(
        color: b.canvas,
        borderRadius: BorderRadius.circular(Brand.radius),
        border: Border.all(color: b.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: BirDropdown<String>(
                  value: row.type.isEmpty ? null : row.type,
                  hint: 'Type',
                  items: [
                    for (final t in typeOptions)
                      DropdownMenuItem(value: t, child: Text(t)),
                  ],
                  onChanged: ro
                      ? null
                      : (t) => setState(() {
                          row.type = t ?? '';
                          if (row.type != 'Server') row.serverType = '';
                        }),
                ),
              ),
              if (row.type == 'Server') ...[
                const SizedBox(width: 8),
                Expanded(
                  child: BirDropdown<String>(
                    value: row.serverType.isEmpty ? null : row.serverType,
                    hint: 'Server Type',
                    items: [
                      for (final t in BirLogic.serverTypeOptions)
                        DropdownMenuItem(value: t, child: Text(t)),
                    ],
                    onChanged: ro
                        ? null
                        : (t) => setState(() => row.serverType = t ?? ''),
                  ),
                ),
              ],
              if (_rows.length > 1)
                IconButton(
                  tooltip: 'Remove serial number',
                  onPressed: () => setState(() {
                    _rows.removeAt(index);
                    row.dispose();
                  }),
                  icon: Icon(Icons.close_rounded, size: 18, color: b.paperDim),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: row.sn,
                  readOnly: ro,
                  style: ro ? TextStyle(color: b.paperDim) : null,
                  decoration: const InputDecoration(
                    hintText: 'Serial Number',
                    prefixIcon: Icon(Icons.qr_code_rounded, size: 20),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: BirCombo(
                        controller: row.brand,
                        options: BirLogic.brandOptions,
                        hint: 'Brand',
                        readOnly: ro,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: BirCombo(
                        controller: row.model,
                        options: BirLogic.modelOptions,
                        hint: 'Model',
                        readOnly: ro,
                      ),
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
}
