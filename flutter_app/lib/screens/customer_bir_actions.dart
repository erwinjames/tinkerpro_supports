import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../services/bir_register_logic.dart';
import '../services/services.dart';
import '../theme.dart';
import '../widgets/pick_source.dart';
import '../widgets/premium.dart';
import 'bir_register_widgets.dart';

const List<String> _kMonths = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String _wordedDate(DateTime? date) {
  if (date == null) return '';
  return '${_kMonths[date.month - 1]} ${date.day}, ${date.year}';
}

DateTime? _parsePastedDate(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(s);
  if (iso != null) {
    final y = int.parse(iso.group(1)!);
    final mo = int.parse(iso.group(2)!);
    final da = int.parse(iso.group(3)!);
    if (mo >= 1 && mo <= 12 && da >= 1 && da <= 31) return DateTime(y, mo, da);
  }
  final mdy = RegExp(
    r'^(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{2,4})$',
  ).firstMatch(s);
  if (mdy != null) {
    final mm = int.parse(mdy.group(1)!);
    final dd = int.parse(mdy.group(2)!);
    var yy = int.parse(mdy.group(3)!);
    if (yy < 100) yy += 2000;
    if (mm >= 1 && mm <= 12 && dd >= 1 && dd <= 31) return DateTime(yy, mm, dd);
  }
  final worded = RegExp(r'^([A-Za-z]+)\s+(\d{1,2}),?\s+(\d{4})$').firstMatch(s);
  if (worded != null) {
    final name = worded.group(1)!.toLowerCase();
    final index = _kMonths.indexWhere((m) => m.toLowerCase() == name);
    if (index >= 0) {
      return DateTime(
        int.parse(worded.group(3)!),
        index + 1,
        int.parse(worded.group(2)!),
      );
    }
  }
  return DateTime.tryParse(s);
}

List<String> _collectSerials(Object? raw) {
  final out = <String>[];
  for (final part in BirLogic.s(raw).split(RegExp(r'[/,]'))) {
    final t = part.replaceAll(RegExp(r'\s+'), '');
    if (t.isNotEmpty && !out.contains(t)) out.add(t);
  }
  return out;
}

enum _PdfStage { upload, review }

class BirRegistrationPdfScreen extends StatefulWidget {
  const BirRegistrationPdfScreen({
    super.key,
    required this.service,
    required this.customer,
  });

  final CustomerService service;
  final CustomerDetail customer;

  @override
  State<BirRegistrationPdfScreen> createState() =>
      _BirRegistrationPdfScreenState();
}

class _BirRegistrationPdfScreenState extends State<BirRegistrationPdfScreen> {
  _PdfStage _stage = _PdfStage.upload;
  final _scroll = ScrollController();

  String? _pdfPath;
  String? _pdfName;
  bool _processing = false;
  bool _saving = false;
  String _mismatch = '';

  Map<String, dynamic> _data = const {};
  Map<String, dynamic> _sw = const {};
  String? _vatStatus;
  bool _vatError = false;

  bool get _hasPdf => widget.customer.pdfFile.trim().isNotEmpty;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (mounted) birToast(context, message);
  }

  void _scrollTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  Future<void> _pick() async {
    final picked = await pickWithSource(
      context,
      allowCamera: false,
      allowedExtensions: const ['pdf'],
      cameraLabel: 'Scan with camera',
      fileLabel: 'Select PDF file',
      onError: _toast,
    );
    if (picked.isEmpty || !mounted) return;
    setState(() {
      _pdfPath = picked.first.path;
      _pdfName = picked.first.name;
      _mismatch = '';
    });
  }

  Future<void> _extract() async {
    final path = _pdfPath;
    if (path == null || _processing) return;
    setState(() {
      _processing = true;
      _mismatch = '';
    });
    final r = await widget.service.extractBirPdf(path);
    if (!mounted) return;
    final data = r.data;
    if (data == null) {
      setState(() => _processing = false);
      _toast(r.error ?? 'Failed to process PDF file. Please try again.');
      return;
    }

    final swList = data['SoftwareInfo'];
    final sw = (swList is List && swList.isNotEmpty && swList.first is Map)
        ? Map<String, dynamic>.from(swList.first as Map)
        : <String, dynamic>{};

    final extracted = <String>[];
    if (swList is List) {
      for (final item in swList.whereType<Map>()) {
        for (final s in _collectSerials(item['SerialNumber'])) {
          if (!extracted.contains(s)) extracted.add(s);
        }
      }
    }
    extracted.sort();
    final expected = _collectSerials(widget.customer.serialNumber)..sort();

    if (expected.isNotEmpty) {
      final match = extracted.isNotEmpty && extracted.every(expected.contains);
      if (!match) {
        final message =
            'The serial number in this document '
            '(${extracted.isEmpty ? 'none' : extracted.join('/')}) does not '
            'match the registered serial number (${expected.join('/')}).';
        setState(() {
          _processing = false;
          _mismatch = message;
        });
        _toast(message);
        return;
      }
    }

    final normalized = BirLogic.normalizeRegistrationType(
      BirLogic.s(data['RegistrationType']),
    );
    setState(() {
      _processing = false;
      _data = data;
      _sw = sw;
      _vatError = false;
      _vatStatus = normalized == 'VAT'
          ? '1'
          : (normalized == 'NON-VAT'
                ? '0'
                : (widget.customer.isVat ? '1' : '0'));
      _stage = _PdfStage.review;
    });
    _scrollTop();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_vatStatus == null) {
      setState(() => _vatError = true);
      return;
    }
    setState(() {
      _vatError = false;
      _saving = true;
    });
    final owner = BirLogic.splitOwnerNameParts(BirLogic.s(_data['OwnerName']));
    final res = await widget.service.saveExtractedRegistration(
      existing: widget.customer,
      companyName: BirLogic.s(_data['BusinessName']),
      tin: BirLogic.s(_data['TIN_BranchCode']),
      rdo: BirLogic.s(_data['RDOCode']),
      address: BirLogic.s(_data['BusinessAddress']),
      accNumber: BirLogic.s(_sw['AccreditationNumber']),
      softwareName: BirLogic.s(_sw['SoftwareName']),
      serialNumber: BirLogic.s(_sw['SerialNumber']),
      firstName: owner.first,
      middleName: owner.middle,
      lastName: owner.last,
      pdfFile: BirLogic.s(_data['filename']),
      isVat: _vatStatus!,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    _toast(res.message);
    if (res.ok) Navigator.of(context).pop(true);
  }

  Future<void> _handleBack() async {
    if (_processing || _saving) return;
    if (_stage == _PdfStage.review) {
      setState(() => _stage = _PdfStage.upload);
      _scrollTop();
      return;
    }
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _stage == _PdfStage.upload && !_processing && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: StationScaffold(
        stationLabel: 'BIR Registration',
        title: _stage == _PdfStage.upload
            ? (_hasPdf
                  ? 'Re-upload BIR Registration PDF'
                  : 'Upload Registration PDF')
            : 'Review Extracted Data',
        compact: true,
        showBottomBrand: false,
        onBack: _handleBack,
        bottomBar: BirBottomBar(
          children: [
            Expanded(
              child: _stage == _PdfStage.upload
                  ? SignalButton(
                      label: _processing ? 'Processing...' : 'Continue',
                      busy: _processing,
                      onPressed: _pdfPath == null || _processing
                          ? null
                          : _extract,
                    )
                  : SignalButton(
                      label: _saving ? 'Saving...' : 'Confirm & Save',
                      icon: Icons.check_circle_rounded,
                      busy: _saving,
                      onPressed: _saving ? null : _save,
                    ),
            ),
          ],
        ),
        child: ListView(
          controller: _scroll,
          children: _stage == _PdfStage.upload
              ? _uploadView(context)
              : _reviewView(context),
        ),
      ),
    );
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
          if (_mismatch.isNotEmpty)
            BirNotice(
              color: Brand.danger,
              icon: Icons.error_outline_rounded,
              title: 'Serial Mismatch',
              message: _mismatch,
            ),
          if (_processing)
            const BirNotice(
              color: Brand.info,
              icon: Icons.hourglass_top_rounded,
              title: 'Processing your document...',
              message:
                  "This may take a moment. Please don't close this window.",
            ),
          if (_pdfPath == null)
            BirUploadTile(
              label: 'Select PDF File',
              icon: Icons.cloud_upload_rounded,
              onTap: _processing ? null : _pick,
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
          if (widget.customer.serialNumber.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Registered serial number: ${widget.customer.serialNumber}',
              style: text.bodySmall,
            ),
          ],
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
            onChanged: _saving
                ? null
                : (v) => setState(() {
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
                    Icons.error_outline_rounded,
                    size: 15,
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
}

enum _PtuStage { upload, manual }

class PtuUploadScreen extends StatefulWidget {
  const PtuUploadScreen({
    super.key,
    required this.service,
    required this.customer,
  });

  final CustomerService service;
  final CustomerDetail customer;

  @override
  State<PtuUploadScreen> createState() => _PtuUploadScreenState();
}

class _PtuUploadScreenState extends State<PtuUploadScreen> {
  _PtuStage _stage = _PtuStage.upload;
  final _scroll = ScrollController();
  final _files = <PickedFile>[];
  bool _processing = false;
  bool _saving = false;
  String _mismatch = '';

  late final TextEditingController _ptu = TextEditingController(
    text: widget.customer.ptu,
  );
  late final TextEditingController _min = TextEditingController(
    text: widget.customer.min,
  );
  late DateTime? _permitDate = _parsePastedDate(widget.customer.posDateIssued);
  bool _ptuError = false;
  bool _minError = false;

  @override
  void dispose() {
    _ptu.dispose();
    _min.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (mounted) birToast(context, message);
  }

  Future<void> _pick() async {
    final picked = await pickWithSource(
      context,
      allowCamera: false,
      multiple: true,
      allowedExtensions: const ['pdf'],
      cameraLabel: 'Scan with camera',
      fileLabel: 'Select PDF file',
      onError: _toast,
    );
    if (picked.isEmpty || !mounted) return;
    setState(() {
      for (final f in picked) {
        if (!_files.any((e) => e.path == f.path)) _files.add(f);
      }
      _mismatch = '';
    });
  }

  Future<void> _submit() async {
    if (_files.isEmpty || _processing) return;
    setState(() {
      _processing = true;
      _mismatch = '';
    });

    final r = await widget.service.extractPtuDocuments(
      customerId: widget.customer.id,
      serialNumber: widget.customer.serialNumber,
      paths: _files.map((e) => e.path).toList(),
    );
    if (!mounted) return;
    final items = r.items;
    if (items == null || items.isEmpty) {
      setState(() => _processing = false);
      _toast(r.error ?? 'Failed to process PDF file. Please try again.');
      return;
    }

    final merged = <String>[];
    final filenames = <String>[];
    void addSerials(Object? raw) {
      for (final s in _collectSerials(raw)) {
        if (!merged.contains(s)) merged.add(s);
      }
    }

    for (final item in items) {
      final filename = BirLogic.s(item['filename']);
      if (filename.isNotEmpty) filenames.add(filename);
      if (item['MergedMachineSerials'] != null) {
        addSerials(item['MergedMachineSerials']);
      } else if (item['SoftwareInfo'] is List) {
        for (final sw in (item['SoftwareInfo'] as List).whereType<Map>()) {
          addSerials(sw['MachineDetails']);
        }
      }
    }
    merged.sort();
    final expected = _collectSerials(widget.customer.serialNumber)..sort();
    final match = merged.isNotEmpty && merged.every(expected.contains);

    if (!match) {
      final message =
          'Serial Mismatch! Account: [${expected.join('/')}], '
          'Uploaded PTU: [${merged.join('/')}]';
      setState(() {
        _processing = false;
        _mismatch = message;
      });
      _toast(message);
      return;
    }

    final first = items.first;
    final swList = first['SoftwareInfo'];
    final sw = (swList is List && swList.isNotEmpty && swList.first is Map)
        ? Map<String, dynamic>.from(swList.first as Map)
        : <String, dynamic>{};

    final res = await widget.service.step3UpdateCustomerData(
      customerId: widget.customer.id,
      posDateIssued: BirLogic.s(first['PosDateIssued']),
      ptu: BirLogic.s(sw['PTU']),
      min: BirLogic.s(sw['MIN']),
      filename: filenames.join(','),
      machineDetails: merged.join('/'),
    );
    if (!mounted) return;
    setState(() => _processing = false);
    _toast(res.message);
    if (res.ok) Navigator.of(context).pop(true);
  }

  Future<void> _pickPermitDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _permitDate ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 10),
    );
    if (picked == null || !mounted) return;
    setState(() => _permitDate = picked);
  }

  Future<void> _saveManual() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    final ptu = _ptu.text.trim();
    final min = _min.text.trim();
    setState(() {
      _ptuError = ptu.isEmpty;
      _minError = min.isEmpty;
    });
    if (ptu.isEmpty || min.isEmpty) {
      _toast('PTU and MIN are required.');
      return;
    }
    setState(() => _saving = true);
    final res = await widget.service.advancePtuManual(
      customerId: widget.customer.id,
      ptu: ptu,
      min: min,
      posDateIssued: _wordedDate(_permitDate),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    _toast(res.message);
    if (res.ok) Navigator.of(context).pop(true);
  }

  Future<void> _handleBack() async {
    if (_processing || _saving) return;
    if (_stage == _PtuStage.manual) {
      setState(() => _stage = _PtuStage.upload);
      return;
    }
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _stage == _PtuStage.upload && !_processing && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: StationScaffold(
        stationLabel: 'BIR Registration',
        title: _stage == _PtuStage.upload
            ? 'Upload PTU Document'
            : 'Advanced — Enter PTU Manually',
        compact: true,
        showBottomBrand: false,
        onBack: _handleBack,
        bottomBar: BirBottomBar(
          children: _stage == _PtuStage.upload
              ? [
                  Expanded(
                    child: SignalButton(
                      label: _processing ? 'Processing...' : 'Continue',
                      busy: _processing,
                      onPressed: _files.isEmpty || _processing ? null : _submit,
                    ),
                  ),
                ]
              : [
                  Expanded(
                    child: SignalButton(
                      label: _saving ? 'Saving...' : 'Save & Complete',
                      icon: Icons.check_circle_rounded,
                      busy: _saving,
                      onPressed: _saving ? null : _saveManual,
                    ),
                  ),
                ],
        ),
        child: ListView(
          controller: _scroll,
          children: _stage == _PtuStage.upload
              ? _uploadView(context)
              : _manualView(context),
        ),
      ),
    );
  }

  List<Widget> _uploadView(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return [
      BirSection(
        title: 'Upload PTU Document',
        subtitle: 'Upload the Permit to Use Sales Machine PDF file.',
        icon: Icons.description_rounded,
        iconColor: Brand.danger,
        children: [
          if (_mismatch.isNotEmpty)
            BirNotice(
              color: Brand.danger,
              icon: Icons.error_outline_rounded,
              title: 'Serial Mismatch',
              message: _mismatch,
            ),
          if (_processing)
            const BirNotice(
              color: Brand.info,
              icon: Icons.hourglass_top_rounded,
              title: 'Processing your document...',
              message:
                  "This may take a moment. Please don't close this window.",
            ),
          for (var i = 0; i < _files.length; i++)
            BirFileRow(
              name: _files[i].name,
              caption: 'Ready to extract',
              icon: Icons.picture_as_pdf_rounded,
              iconColor: Brand.danger,
              onRemove: _processing
                  ? null
                  : () => setState(() => _files.removeAt(i)),
            ),
          BirUploadTile(
            label: _files.isEmpty ? 'Select PDF File' : 'Add another PDF',
            icon: Icons.cloud_upload_rounded,
            onTap: _processing ? null : _pick,
            hint: 'PDF files only',
          ),
          if (widget.customer.serialNumber.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Registered serial number: ${widget.customer.serialNumber}',
              style: text.bodySmall,
            ),
          ],
          const SizedBox(height: 14),
          GhostButton(
            label: 'Advanced — Enter PTU Manually',
            icon: Icons.keyboard_rounded,
            onPressed: () {
              if (_processing) return;
              setState(() => _stage = _PtuStage.manual);
            },
          ),
        ],
      ),
    ];
  }

  List<Widget> _manualView(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    return [
      BirSection(
        title: 'Advanced — Enter PTU Manually',
        subtitle:
            'Type in the permit details to complete the registration without uploading a PDF.',
        icon: Icons.keyboard_rounded,
        children: [
          BirField(
            label: 'PTU No.',
            controller: _ptu,
            required: true,
            hint: 'Permit to Use number',
            prefixIcon: Icons.badge_rounded,
            highlight: _ptuError,
            onChanged: (_) {
              if (_ptuError) setState(() => _ptuError = false);
            },
          ),
          BirField(
            label: 'MIN',
            controller: _min,
            required: true,
            hint: 'Machine Identification Number',
            prefixIcon: Icons.memory_rounded,
            highlight: _minError,
            onChanged: (_) {
              if (_minError) setState(() => _minError = false);
            },
          ),
          BirLabeled(
            label: 'Effective Date of Permit',
            child: InkWell(
              borderRadius: BorderRadius.circular(Brand.radius),
              onTap: _saving ? null : _pickPermitDate,
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Brand.radiusSm + 2),
                  color: b.surfaceHi,
                  border: Border.all(color: b.rule),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.event_available_rounded,
                      size: 18,
                      color: b.signal,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _permitDate == null
                            ? 'Select a date'
                            : _wordedDate(_permitDate),
                        style: text.bodyMedium?.copyWith(
                          color: _permitDate == null ? b.paperDim : b.paper,
                        ),
                      ),
                    ),
                    if (_permitDate != null)
                      IconButton(
                        tooltip: 'Clear',
                        onPressed: _saving
                            ? null
                            : () => setState(() => _permitDate = null),
                        icon: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: b.paperDim,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ];
  }
}
