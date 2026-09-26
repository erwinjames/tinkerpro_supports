import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/bir_register_logic.dart';
import '../services/services.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'bir_pdf_register_screen.dart';
import 'bir_register_widgets.dart';

enum _Step { invoice, upload, extracting, review }

class BirRegisterFlowScreen extends StatefulWidget {
  const BirRegisterFlowScreen({super.key, required this.service});

  final CustomerService service;

  @override
  State<BirRegisterFlowScreen> createState() => _BirRegisterFlowScreenState();
}

class _BirRegisterFlowScreenState extends State<BirRegisterFlowScreen> {
  static const _docExtensions = <String>[
    'pdf',
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'bmp',
    'heic',
    'heif',
    'tif',
    'tiff',
    'doc',
    'docx',
  ];
  static const _guideDismissKey = 'tp_bir_guide_dismissed';
  static const _birHints = <String, String>{
    'no':
        'We\'ll read the business details from BIR Form 2303 and the ID holder from the valid ID.',
    'yes':
        'We\'ll open the BIR Registration upload so the Application for Registration PDF can be extracted directly.',
  };

  CustomerService get _svc => widget.service;

  _Step _step = _Step.invoice;
  final _scroll = ScrollController();

  final _invoiceCtrl = TextEditingController();
  bool _invoiceChecking = false;
  String _invoiceMessage = '';
  String _invoiceNumber = '';

  String _birChoice = 'no';
  final List<({String path, String name})> _docs = [];
  String _vidMode = 'upload';
  String? _vidPath;
  String? _vidName;
  final _manualName = TextEditingController();
  final _manualBirthdate = TextEditingController();
  bool _manualNameError = false;
  bool _manualBirthError = false;
  String _dupTinMessage = '';
  ({String name, String birthdate})? _manualEntry;
  bool _guideShown = false;

  double _percent = 0;
  bool _uploadDone = false;
  double _serverPercent = 0;
  String _serverLabel = '';
  String _serverProvider = '';
  bool _progressComplete = false;
  DateTime? _progressStarted;
  DateTime? _procStarted;
  int _elapsed = 0;
  Timer? _progressTimer;
  Timer? _clockTimer;

  late final Future<Map<String, List<SoftwareVersionInfo>>> _catalogFuture;
  late final Future<List<PsicItem>> _psicFuture;
  Map<String, List<SoftwareVersionInfo>> _catalog = const {};
  List<PsicItem> _psic = const [];

  Map<String, dynamic> _response = const {};
  final _company = TextEditingController();
  final _tin = TextEditingController();
  final _branch = TextEditingController();
  final _rdo = TextEditingController();
  final _tinIssuance = TextEditingController();
  final _lob = TextEditingController();
  final _lobFocus = FocusNode();
  String _lobDesc = '';
  String _lobSource = '';
  String _lobBadgeValue = '';
  List<LobCandidate> _lobCandidates = const [];
  final _address = TextEditingController();
  final _lastName = TextEditingController();
  final _firstName = TextEditingController();
  final _middleName = TextEditingController();
  final _birthdate = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _acc = TextEditingController();
  String _regType = '';
  String _vatSource = '';
  bool _vatBadgeVisible = false;
  String? _software;
  String _version = '';
  String _ownerName = '';
  String _authorizedPerson = '';
  String _validIdType = '';
  String _validIdNumber = '';
  String _rawText = '';
  String _pdfFile = '';
  final List<BirSnRow> _rows = [BirSnRow()];
  final Map<BirSnRow, Timer> _snTimers = {};
  Timer? _tinTimer;
  String _tinDupMessage = '';
  bool _tinBlocked = false;
  List<Map<String, dynamic>> _extractionStored = [];
  final List<Map<String, dynamic>> _requirementStored = [];
  bool _addingDocs = false;
  String _addDocStatus = 'Update extraction with more files.';
  bool _attaching = false;
  bool _saving = false;

  final _ocrQuery = TextEditingController();
  final _ocrScroll = ScrollController();
  List<int> _ocrMatches = const [];
  int _ocrIndex = -1;
  String _ocrTerm = '';
  bool _ocrOpen = false;

  @override
  void initState() {
    super.initState();
    _catalogFuture = _svc.softwareCatalog(refresh: true);
    _psicFuture = _svc.psicList();
    _catalogFuture.then((v) {
      if (mounted) setState(() => _catalog = v);
    });
    _psicFuture.then((v) {
      if (mounted) setState(() => _psic = v);
    });
    _lobFocus.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _clockTimer?.cancel();
    _tinTimer?.cancel();
    for (final t in _snTimers.values) {
      t.cancel();
    }
    for (final c in [
      _invoiceCtrl,
      _manualName,
      _manualBirthdate,
      _company,
      _tin,
      _branch,
      _rdo,
      _tinIssuance,
      _lob,
      _address,
      _lastName,
      _firstName,
      _middleName,
      _birthdate,
      _phone,
      _email,
      _acc,
      _ocrQuery,
    ]) {
      c.dispose();
    }
    for (final r in _rows) {
      r.dispose();
    }
    _lobFocus.dispose();
    _scroll.dispose();
    _ocrScroll.dispose();
    super.dispose();
  }

  void _toast(String message, {SnackBarAction? action}) {
    if (!mounted) return;
    birToast(context, message, action: action);
  }

  void _scrollTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  static bool _truthy(Object? v) =>
      v == true || v == 1 || v == '1' || v == 'true';

  Future<void> _invoiceContinue() async {
    final term = _invoiceCtrl.text.trim();
    if (term.isEmpty || _invoiceChecking) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _invoiceChecking = true;
      _invoiceMessage = 'Checking invoice…';
    });
    final r = await _svc.searchInvoice(term);
    if (!mounted) return;
    if (r.ok) {
      setState(() {
        _invoiceChecking = false;
        _invoiceMessage = '';
        _invoiceNumber = r.invoice ?? term;
      });
      _goUpload();
      return;
    }
    setState(() {
      _invoiceChecking = false;
      if (r.error == 'not_found') {
        _invoiceMessage =
            'Invoice “$term” was not found on TinkerPro Invoice. Please check the number, or Skip if you don\'t have one.';
      } else if (r.error == 'unreachable') {
        _invoiceMessage =
            'Could not reach the invoice service. Please try again.';
      } else {
        _invoiceMessage = r.error ?? 'Invoice not found.';
      }
    });
  }

  void _invoiceSkip() {
    setState(() {
      _invoiceNumber = '';
      _invoiceMessage = '';
    });
    _goUpload();
  }

  void _goUpload() {
    setState(() {
      _step = _Step.upload;
      _birChoice = 'no';
    });
    _scrollTop();
    if (!_guideShown) {
      _guideShown = true;
      Future<void>.delayed(const Duration(milliseconds: 260), () async {
        if (!mounted || _step != _Step.upload) return;
        var dismissed = false;
        try {
          final prefs = await SharedPreferences.getInstance();
          dismissed = prefs.getString(_guideDismissKey) == '1';
        } catch (_) {}
        if (!dismissed && mounted && _step == _Step.upload) _showGuide();
      });
    }
  }

  Future<void> _onBirChoice(String? v) async {
    if (v == null) return;
    setState(() => _birChoice = v);
    if (v != 'yes') return;
    setState(() => _birChoice = 'no');
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            BirPdfRegisterScreen(service: _svc, invoiceNumber: _invoiceNumber),
      ),
    );
    if (saved == true && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _showGuide() async {
    final base = _svc.api.baseUrl;
    final headers = _svc.api.authHeaders();
    var lane = _birChoice;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        final text = Theme.of(ctx).textTheme;
        final b = ctx.brand;
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final no = lane == 'no';
            final fields = no
                ? const <(String, String, String?)>[
                    ('RDO', 'Revenue District Office and region', null),
                    (
                      'TIN & branch code',
                      'Identifies head office vs branch',
                      null,
                    ),
                    (
                      'Name of taxpayer',
                      'The registered entity name',
                      'If this is a person’s name (sole proprietor), the business name is taken from the DTI certificate and business permit instead.',
                    ),
                    ('TIN issuance date', 'When the TIN was issued', null),
                    (
                      'Registering address',
                      'Split into region, province, city, barangay',
                      null,
                    ),
                    (
                      'Tax types & taxpayer type',
                      'Tells us whether the client is VAT or non-VAT',
                      null,
                    ),
                    (
                      'Trade name, PSIC & line of business',
                      'Business details for the filing',
                      null,
                    ),
                  ]
                : const <(String, String, String?)>[
                    (
                      'Date submitted & transaction number',
                      'Ties the client to the BIR application',
                      null,
                    ),
                    (
                      'Permit type & machine setup',
                      'Final or provisional, and how the POS is deployed',
                      null,
                    ),
                    ('RDO code', 'Revenue District Office of the client', null),
                    (
                      'TIN & branch code',
                      'Identifies head office vs branch',
                      null,
                    ),
                    ('Owner name', 'The registered taxpayer', null),
                    ('Business name', 'Trading name on the permit', null),
                    (
                      'Business address',
                      'Split into region, province, city, barangay',
                      null,
                    ),
                    (
                      'Registered machines',
                      'Accreditation number, serial number, brand and model',
                      null,
                    ),
                  ];
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.9,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              builder: (ctx, controller) => ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  Row(
                    children: [
                      Icon(Icons.route_rounded, color: b.signal, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'What happens after you choose',
                          style: text.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'no',
                        label: Text('No — from the 2303'),
                      ),
                      ButtonSegment(
                        value: 'yes',
                        label: Text('Yes — registered'),
                      ),
                    ],
                    selected: {lane},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setSheet(() => lane = s.first),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    no
                        ? 'We read the Certificate of Registration, then the valid ID'
                        : 'Upload the Application for Registration PDF instead',
                    style: text.bodySmall,
                  ),
                  if (!no) ...[
                    const SizedBox(height: 12),
                    for (final s in const [
                      (
                        Icons.picture_as_pdf_rounded,
                        'Upload the BIR Registration PDF',
                      ),
                      (Icons.search_rounded, 'We extract the details from it'),
                      (Icons.check_circle_rounded, 'Skip straight to review'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Icon(s.$1, size: 16, color: b.signal),
                            const SizedBox(width: 8),
                            Expanded(child: Text(s.$2, style: text.bodyMedium)),
                          ],
                        ),
                      ),
                  ],
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Brand.radius),
                    child: Container(
                      color: b.surfaceHi,
                      child: Image.network(
                        no
                            ? '$base/upload/bir2303_guide/1.webp'
                            : '$base/upload/birregistration_guide/registration.png',
                        headers: headers,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => SizedBox(
                          height: 120,
                          child: Center(
                            child: Icon(
                              Icons.image_not_supported_rounded,
                              color: b.paperDim,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    no ? 'Sample BIR Form 2303' : 'Sample BIR Registration PDF',
                    textAlign: TextAlign.center,
                    style: text.labelMedium,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    no
                        ? 'What we pull off the 2303'
                        : 'What we pull off the registration',
                    style: text.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < fields.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: b.tint(b.signal, 0.14),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${i + 1}',
                              style: TextStyle(
                                color: b.signal,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(fields[i].$1, style: text.titleSmall),
                                Text(fields[i].$2, style: text.bodySmall),
                                if (fields[i].$3 != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      fields[i].$3!,
                                      style: text.bodySmall?.copyWith(
                                        color: b.signalInk,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 6),
                  BirNotice(
                    color: no ? Brand.info : b.signal,
                    icon: no ? Icons.badge_rounded : Icons.bolt_rounded,
                    message: no
                        ? 'Then the valid ID gives us the authorised person — everything is read in one pass and the form comes back prefilled for you to check. For a sole proprietor, add the DTI certificate and business permit so we can pick up the trading name.'
                        : 'Everything above is read in one pass, so you land straight on the review step with the form already filled in — just check it and save.',
                  ),
                  if (no)
                    const BirNotice(
                      color: Brand.warning,
                      icon: Icons.info_outline_rounded,
                      title: 'No 2303 yet?',
                      message:
                          'To get BIR Form 2303 (Certificate of Registration) in the Philippines, you must register your business or professional practice with the Bureau of Internal Revenue (BIR).',
                    ),
                  Text(
                    'Reopen this any time with the ? beside the question.',
                    style: text.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  SignalButton(
                    label: 'Got it',
                    icon: Icons.check_rounded,
                    onPressed: () async {
                      try {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString(_guideDismissKey, '1');
                      } catch (_) {}
                      if (ctx.mounted) Navigator.of(ctx).pop();
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<List<({String path, String name})>> _chooseFiles({
    required bool multiple,
    String cameraLabel = 'Take a photo',
    String fileLabel = 'Choose from files',
  }) async {
    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: Text(cameraLabel),
              onTap: () => Navigator.of(ctx).pop('camera'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open_rounded),
              title: Text(fileLabel),
              onTap: () => Navigator.of(ctx).pop('file'),
            ),
          ],
        ),
      ),
    );
    if (source == null) return const [];
    if (source == 'camera') {
      try {
        final shot = await ImagePicker().pickImage(
          source: ImageSource.camera,
          imageQuality: 92,
        );
        if (shot == null) return const [];
        return [(path: shot.path, name: shot.name)];
      } catch (_) {
        _toast('Could not open the camera.');
        return const [];
      }
    }
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        allowMultiple: multiple,
        type: FileType.custom,
        allowedExtensions: _docExtensions,
      );
    } catch (_) {
      _toast('Could not open the file picker.');
      return const [];
    }
    return (result?.files ?? const <PlatformFile>[])
        .where((f) => f.path != null)
        .map((f) => (path: f.path!, name: f.name))
        .toList();
  }

  Future<void> _pickDocs() async {
    final picked = await _chooseFiles(
      multiple: true,
      cameraLabel: 'Take a photo of the document',
      fileLabel: 'Choose documents from files',
    );
    if (picked.isEmpty || !mounted) return;
    setState(() => _docs.addAll(picked));
  }

  Future<void> _pickValidId() async {
    final picked = await _chooseFiles(
      multiple: false,
      cameraLabel: 'Take a photo of the ID',
      fileLabel: 'Choose image, PDF, or Word file',
    );
    if (picked.isEmpty || !mounted) return;
    setState(() {
      _vidPath = picked.first.path;
      _vidName = picked.first.name;
    });
  }

  Future<void> _pickManualBirthdate() async {
    final now = DateTime.now();
    final existing = _parseDate(_manualBirthdate.text);
    final picked = await showDatePicker(
      context: context,
      initialDate: existing ?? DateTime(now.year - 30),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked == null) return;
    setState(() {
      _manualBirthdate.text = _mdy(picked);
      _manualBirthError = false;
    });
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _mdy(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year.toString().padLeft(4, '0')}';

  static DateTime? _parseDate(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return null;
    final iso = RegExp(r'^(\d{4})[/-](\d{1,2})[/-](\d{1,2})$').firstMatch(raw);
    if (iso != null) {
      return _buildDate(
        int.parse(iso.group(1)!),
        int.parse(iso.group(2)!),
        int.parse(iso.group(3)!),
      );
    }
    final slashed = RegExp(
      r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$',
    ).firstMatch(raw);
    if (slashed != null) {
      return _buildDate(
        int.parse(slashed.group(3)!),
        int.parse(slashed.group(1)!),
        int.parse(slashed.group(2)!),
      );
    }
    return DateTime.tryParse(raw);
  }

  static DateTime? _buildDate(int year, int month, int day) {
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final parsed = DateTime(year, month, day);
    return parsed.month == month && parsed.day == day ? parsed : null;
  }

  static String _displayDate(String value) {
    final parsed = _parseDate(value);
    return parsed == null ? value.trim() : _mdy(parsed);
  }

  static String _isoDate(String value) {
    final parsed = _parseDate(value);
    return parsed == null ? value.trim() : _ymd(parsed);
  }

  void _setVidMode(String mode) {
    setState(() {
      _vidMode = mode;
      if (mode == 'manual') {
        _vidPath = null;
        _vidName = null;
      } else {
        _manualName.clear();
        _manualBirthdate.clear();
        _manualNameError = false;
        _manualBirthError = false;
      }
    });
  }

  Future<void> _startExtraction() async {
    FocusScope.of(context).unfocus();
    if (_docs.isEmpty) {
      _toast('Please upload at least one document.');
      return;
    }
    final manual = _vidMode == 'manual';
    if (manual) {
      if (_manualName.text.trim().isEmpty) {
        setState(() => _manualNameError = true);
        _toast('Enter the ID holder\'s full name.');
        return;
      }
      if (_manualBirthdate.text.trim().isEmpty) {
        setState(() => _manualBirthError = true);
        _toast('Enter the ID holder\'s birthdate.');
        return;
      }
    } else if (_vidPath == null) {
      _toast('Please upload a Valid ID before proceeding.');
      return;
    }
    _manualEntry = manual
        ? (
            name: _manualName.text.trim(),
            birthdate: _isoDate(_manualBirthdate.text),
          )
        : null;

    setState(() => _step = _Step.extracting);
    _startProgress();
    final outcome = await _svc.extractDocuments(
      paths: _docs.map((d) => d.path).toList(),
      validIdPath: manual ? null : _vidPath,
      manualName: manual ? _manualEntry!.name : null,
      manualBirthdate: manual ? _manualEntry!.birthdate : null,
      onUploaded: () => _uploadDone = true,
      onProgress: _applyServerProgress,
      isCancelled: () => !mounted,
    );
    if (!mounted) return;
    if (outcome.failure != null) {
      _stopProgress(false);
      setState(() => _step = _Step.upload);
      _toast(outcome.failure!);
      return;
    }
    _stopProgress(true);
    await Future<void>.delayed(const Duration(milliseconds: 260));
    if (!mounted) return;
    final response = outcome.data!;
    final err = response['error'];
    if (err != null) {
      setState(() => _step = _Step.upload);
      final msg = err.toString();
      _toast(msg.isEmpty ? 'Extraction failed.' : msg);
      return;
    }
    await _validateTinThenProceed(response);
  }

  void _startProgress() {
    _progressTimer?.cancel();
    _clockTimer?.cancel();
    _progressStarted = DateTime.now();
    _procStarted = null;
    _uploadDone = false;
    _serverPercent = 0;
    _serverLabel = '';
    _serverProvider = '';
    _progressComplete = false;
    _percent = 0;
    _elapsed = 0;
    _progressTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      final elapsed = DateTime.now()
          .difference(_progressStarted!)
          .inMilliseconds;
      double p;
      if (!_uploadDone) {
        p = math.min(30, (elapsed / 6000) * 30);
      } else {
        _procStarted ??= DateTime.now();
        final proc = DateTime.now().difference(_procStarted!).inMilliseconds;
        final drift = 30 + 8 * (1 - math.exp(-proc / 12000));
        p = math.max(drift, _serverPercent);
      }
      if (p < _percent) p = _percent;
      setState(() => _percent = p);
    });
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed++);
    });
  }

  void _applyServerProgress(Map<String, dynamic> res) {
    _serverLabel = (res['label'] ?? '').toString();
    _serverProvider = (res['provider'] ?? '').toString();
    final p = res['percent'];
    if (p is num) _serverPercent = math.max(_serverPercent, p.toDouble());
  }

  void _stopProgress(bool complete) {
    _progressTimer?.cancel();
    _clockTimer?.cancel();
    _progressTimer = null;
    _clockTimer = null;
    if (!mounted) return;
    setState(() {
      _progressComplete = complete;
      _percent = complete ? 100 : 0;
    });
  }

  Future<void> _validateTinThenProceed(Map<String, dynamic> response) async {
    final normalized = BirLogic.digits(BirLogic.s(response['TIN_BranchCode']));
    final branch = BirLogic.digits(BirLogic.s(response['BranchCode']));
    if (normalized.length >= 9) {
      final res = await _svc.checkTinDuplicate(normalized, branch);
      if (!mounted) return;
      if (res.duplicate) {
        final existingTin = res.tin.isNotEmpty ? res.tin : normalized;
        setState(() {
          _step = _Step.upload;
          _dupTinMessage = res.company.isNotEmpty
              ? 'The extracted TIN ($existingTin) is already registered to "${res.company}". Please upload documents for a different client or verify the documents are correct.'
              : 'The extracted TIN ($existingTin) is already registered. Please upload documents for a different client or verify the documents are correct.';
        });
        _scrollTop();
        _toast(
          'Duplicate TIN detected. This client may already be registered.',
        );
        return;
      }
    }
    await _proceedToPreview(response);
  }

  Future<void> _proceedToPreview(Map<String, dynamic> response) async {
    setState(() {
      _dupTinMessage = '';
      _tinBlocked = false;
      for (final r in _rows) {
        r.dupMessage = '';
        r.dupFromDb = false;
      }
    });
    final comparison = response['DocComparison'];
    if (_truthy(response['DocComparisonMismatch']) &&
        comparison is List &&
        comparison.length > 1) {
      final cont = await _showDocComparison(response);
      if (!mounted) return;
      if (!cont) {
        setState(() => _step = _Step.upload);
        _scrollTop();
        return;
      }
    }
    await _populateAndReview(response);
  }

  Future<bool> _showDocComparison(Map<String, dynamic> response) async {
    final comparison = (response['DocComparison'] as List)
        .whereType<Map>()
        .toList();
    final filenames = (response['filenames'] is List)
        ? (response['filenames'] as List).map((e) => e.toString()).toList()
        : const <String>[];
    final finalName = BirLogic.s(response['BusinessName']);
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final b = ctx.brand;
        final text = Theme.of(ctx).textTheme;
        return AlertDialog(
          icon: const Icon(
            Icons.warning_amber_rounded,
            color: Brand.warning,
            size: 32,
          ),
          title: const Text('Document Validation'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text.rich(
                    const TextSpan(
                      children: [
                        TextSpan(text: 'We found '),
                        TextSpan(
                          text: 'mismatched business names',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(
                          text:
                              ' across your uploaded documents. Please review and re-upload any incorrect documents.',
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: 14),
                  for (var idx = 0; idx < comparison.length; idx++)
                    Builder(
                      builder: (_) {
                        final entry = comparison[idx];
                        final match = _truthy(entry['match']);
                        final file = BirLogic.s(entry['file']);
                        var display = file;
                        for (final f in filenames) {
                          final stem = f
                              .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
                              .split('.')
                              .first;
                          if (file.contains(stem)) {
                            display = f;
                            break;
                          }
                        }
                        if (display == file && idx < filenames.length) {
                          display = filenames[idx];
                        }
                        final c = match ? Brand.success : Brand.danger;
                        final name = BirLogic.s(entry['name']);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: b.tint(c, 0.06),
                            borderRadius: BorderRadius.circular(Brand.radius),
                            border: Border.all(color: c, width: 1.4),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                match
                                    ? Icons.check_circle_rounded
                                    : Icons.cancel_rounded,
                                color: c,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      display,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: text.titleSmall,
                                    ),
                                    Text(
                                      name.isEmpty
                                          ? 'No business name found'
                                          : name,
                                      style: text.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: name.isEmpty ? b.paperDim : null,
                                        fontStyle: name.isEmpty
                                            ? FontStyle.italic
                                            : null,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                match ? 'MATCH' : 'MISMATCH',
                                style: TextStyle(
                                  color: c,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  if (finalName.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: b.tint(b.signal, 0.08),
                        borderRadius: BorderRadius.circular(Brand.radiusSm),
                        border: Border.all(color: b.tint(b.signal, 0.25)),
                      ),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: 'Resolved Business Name: ',
                              style: text.bodySmall,
                            ),
                            TextSpan(
                              text: finalName,
                              style: text.titleSmall?.copyWith(
                                color: b.signalInk,
                              ),
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            OutlinedButton.icon(
              onPressed: () => Navigator.of(ctx).pop(false),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Re-upload Documents'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(ctx).pop(true),
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text('Continue Anyway'),
            ),
          ],
        );
      },
    );
    return result == true;
  }

  Future<void> _populateAndReview(Map<String, dynamic> response) async {
    final catalog = await _catalogFuture;
    final psic = await _psicFuture;
    if (!mounted) return;
    final s = BirLogic.s;
    setState(() {
      _catalog = catalog;
      _psic = psic;
      _response = response;
      final stored = response['storedFiles'];
      if (stored is List) {
        _extractionStored = stored
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      final swList = response['SoftwareInfo'];
      final software = (swList is List && swList.isNotEmpty && swList[0] is Map)
          ? Map<String, dynamic>.from(swList[0] as Map)
          : <String, dynamic>{};

      var ownerParsed = BirLogic.parseOwnerName(s(response['OwnerName']));
      var businessName = s(response['BusinessName']);
      if (ownerParsed.isCorporate && businessName.trim().isEmpty) {
        businessName = ownerParsed.full;
      }
      final rawText = s(response['RawExtractedText']);
      if (ownerParsed.full.isEmpty) {
        final fb = BirLogic.tinLineOwnerFallback(rawText);
        if (fb.isNotEmpty) ownerParsed = BirLogic.parseOwnerName(fb);
      }
      var ownerNameStr = ownerParsed.full;

      final hasRealValidId = s(response['ValidIDSourceFile']).trim().isNotEmpty;
      final validIdName = hasRealValidId
          ? s(response['ValidIDName']).trim()
          : '';
      final idHolderName = hasRealValidId
          ? s(response['IDHolderName']).trim()
          : '';
      final holderFromParts = hasRealValidId
          ? [
              s(response['IDHolderFirstName']),
              s(response['IDHolderMiddleName']),
              s(response['IDHolderLastName']),
            ].where((e) => e.isNotEmpty).join(' ')
          : '';
      String firstNonEmpty(List<String> xs) =>
          xs.firstWhere((e) => e.isNotEmpty, orElse: () => '');
      if (ownerNameStr.isEmpty) {
        if (hasRealValidId) {
          final fallbackIdName = firstNonEmpty([
            idHolderName,
            validIdName,
            s(response['AuthorizedPersonName']),
            holderFromParts,
          ]);
          if (fallbackIdName.isNotEmpty) {
            ownerParsed = BirLogic.parseOwnerName(fallbackIdName);
            ownerNameStr = ownerParsed.full;
          }
        }
        if (ownerNameStr.isEmpty && businessName.trim().isNotEmpty) {
          ownerNameStr = businessName.trim();
        }
      }
      final idNameStr = hasRealValidId
          ? firstNonEmpty([
              idHolderName,
              validIdName,
              s(response['AuthorizedPersonName']),
              holderFromParts,
            ])
          : '';

      _rawText = rawText;
      _ocrMatches = const [];
      _ocrIndex = -1;
      _ocrTerm = '';
      _ocrQuery.clear();
      _company.text = businessName;

      final tinParts = BirLogic.formatTin(
        s(response['TIN_BranchCode']),
        s(response['BranchCode']),
      );
      _tin.text = tinParts.tin;
      _branch.text = tinParts.branch;
      _tinIssuance.text = s(response['TINIssuanceDate']);
      _address.text = s(response['BusinessAddress']);
      _rdo.text = s(response['RDOCode']);

      var lobValue = s(response['LineOfBusiness']);
      var lobSource = s(response['LineOfBusinessSource']);
      if (lobSource.isEmpty && lobValue.isNotEmpty) lobSource = 'document';
      if (lobValue.isEmpty && businessName.isNotEmpty) {
        lobValue = BirLogic.inferLobFromBusinessName(businessName);
        if (lobValue.isNotEmpty) lobSource = 'inferred_business_name';
      }
      final lobMatch = BirLogic.findPsicMatch(psic, lobValue);
      if (lobMatch != null) {
        _lob.text = lobMatch.label;
        _lobDesc = lobMatch.description;
      } else {
        _lob.text = lobValue;
        _lobDesc = '';
      }
      _lobBadgeValue = lobValue;
      _lobSource = lobSource;
      _lobCandidates = BirLogic.resolveLobCandidates(
        psic,
        response['LineOfBusinessCandidates'],
      );

      final vat = BirLogic.detectRegistrationType(response);
      _regType = vat.type;
      _vatSource = vat.source;
      _vatBadgeVisible = true;

      _birthdate.text = hasRealValidId
          ? _displayDate(
              firstNonEmpty([
                s(response['ValidIDBirthdate']),
                s(response['Birthdate']),
              ]),
            )
          : '';
      _ownerName = ownerNameStr;

      if (hasRealValidId) {
        var idFirst = s(response['IDHolderFirstName']).trim();
        var idMiddle = s(response['IDHolderMiddleName']).trim();
        var idLast = s(response['IDHolderLastName']).trim();
        if (idFirst.isEmpty &&
            idMiddle.isEmpty &&
            idLast.isEmpty &&
            idNameStr.isNotEmpty) {
          final p = BirLogic.parseOwnerName(idNameStr);
          idFirst = p.first;
          idMiddle = p.middle;
          idLast = p.last;
        }
        _firstName.text = idFirst;
        _middleName.text = idMiddle;
        _lastName.text = idLast;
        _validIdType = s(response['ValidIDType']);
        _validIdNumber = s(response['ValidIDNumber']);
      } else {
        _firstName.clear();
        _middleName.clear();
        _lastName.clear();
        _validIdType = '';
        _validIdNumber = '';
      }
      _authorizedPerson = idNameStr;

      final manual = _manualEntry;
      if (manual != null) {
        final parsed = BirLogic.splitManualHolderName(manual.name);
        _firstName.text = parsed.first;
        _middleName.text = parsed.middle;
        _lastName.text = parsed.last;
        _authorizedPerson = parsed.full;
        _birthdate.text = _displayDate(manual.birthdate);
        _validIdType = 'MANUAL ENTRY (NO ID)';
        _validIdNumber = '';
        if (_ownerName.trim().isEmpty) _ownerName = parsed.full;
      }

      final names = catalog.keys;
      final normalized = BirLogic.normalizeSoftwareName(
        s(software['SoftwareName']),
        names,
      );
      if (normalized.isNotEmpty) {
        _software = catalog.containsKey(normalized) ? normalized : null;
        final versions = _versionsFor(_software);
        _version = versions.isNotEmpty
            ? versions.first.version
            : (BirLogic.softwareVersionByName[_software ?? ''] ?? '');
      } else {
        final fallback = BirLogic.normalizeSoftwareName(
          'Wholesale/Retail',
          names,
        );
        _software = catalog.containsKey(fallback) ? fallback : null;
        final versions = _versionsFor(_software);
        _version = versions.isNotEmpty ? versions.first.version : '';
        final fv = s(software['SoftwareVersion']);
        if (fv.isNotEmpty && versions.any((v) => v.version == fv)) {
          _version = fv;
        }
      }
      _acc.text = s(software['AccreditationNumber']);
      _applyCatalogAccreditation();

      final filenames = response['filenames'];
      _pdfFile = (filenames is List && filenames.isNotEmpty)
          ? filenames.first.toString()
          : '';

      _rows.first.brand.text = s(response['Brand']);
      _rows.first.model.text = s(response['Model']);

      _step = _Step.review;
    });
    _checkTinInline(branchOverride: _branch.text);
    setState(() {
      _branch.text = BirLogic.branchFromTin(_branch.text, _tin.text);
    });
    _scrollTop();
  }

  List<SoftwareVersionInfo> _versionsFor(String? name) =>
      name == null ? const [] : (_catalog[name] ?? const []);

  void _applyCatalogAccreditation() {
    final match = _versionsFor(
      _software,
    ).where((v) => v.version == _version).firstOrNull;
    final acc = match?.accNumber ?? '';
    if (acc.isNotEmpty) _acc.text = acc;
  }

  void _onTinChanged(String _) {
    _tinTimer?.cancel();
    _tinTimer = Timer(
      const Duration(milliseconds: 400),
      () => _checkTinInline(),
    );
  }

  Future<void> _checkTinInline({String? branchOverride}) async {
    final normalized = BirLogic.digits(_tin.text);
    final branch = BirLogic.digits(branchOverride ?? _branch.text);
    if (normalized.length < 9) {
      setState(() {
        _tinDupMessage = '';
        _tinBlocked = false;
      });
      return;
    }
    final res = await _svc.checkTinDuplicate(normalized, branch);
    if (!mounted) return;
    setState(() {
      if (res.duplicate) {
        final existingTin = res.tin.isNotEmpty ? res.tin : normalized;
        _tinDupMessage = res.company.isNotEmpty
            ? 'This TIN ($existingTin) is already registered to "${res.company}". Please verify before saving.'
            : 'This TIN ($existingTin) is already registered. Please verify before saving.';
        _tinBlocked = true;
      } else {
        _tinDupMessage = '';
        _tinBlocked = false;
      }
    });
  }

  void _syncOwnerFromParts() {
    _ownerName = [
      _firstName.text,
      _middleName.text,
      _lastName.text,
    ].map((e) => e.trim()).where((e) => e.isNotEmpty).join(' ');
  }

  bool get _snBlocked => _rows.any((r) => r.isDuplicate);

  void _onSnChanged(BirSnRow row) {
    _snTimers.remove(row)?.cancel();
    final sn = row.sn.text.trim();
    setState(() {
      row.dupMessage = '';
      row.dupFromDb = false;
    });
    if (sn.isEmpty) return;
    final dupe = _rows.any((r) => !identical(r, row) && r.sn.text.trim() == sn);
    if (dupe) {
      setState(
        () => row.dupMessage = 'This serial number is entered more than once.',
      );
      _toast(
        'Duplicate serial number "$sn" — each serial number must be unique.',
      );
      return;
    }
    _snTimers[row] = Timer(
      const Duration(milliseconds: 500),
      () => _checkSnDb(row, sn),
    );
  }

  Future<void> _checkSnDb(BirSnRow row, String sn) async {
    final res = await _svc.checkSnDuplicate(sn);
    if (!mounted || !_rows.contains(row)) return;
    if (row.sn.text.trim() != sn) return;
    setState(() {
      if (res.duplicate) {
        row.dupMessage = 'This serial number is already in use.';
        row.dupFromDb = true;
      } else if (row.dupFromDb) {
        row.dupMessage = '';
        row.dupFromDb = false;
      }
    });
    if (res.duplicate) _toast('Serial number "$sn" is already in use.');
  }

  void _onSnPicked(BirSnRow row, LicenseSerialSuggestion hit) {
    final index = _rows.indexOf(row);
    if (index >= 0 && hit.machineType.isNotEmpty && row.type.isEmpty) {
      final allowed = BirLogic.serialTypeOptions(
        _rows.map((r) => r.type).toList(),
        index,
      );
      if (allowed.contains(hit.machineType)) {
        setState(() => row.type = hit.machineType);
      }
    }
    _onSnChanged(row);
    if (hit.taken) {
      _toast(
        'Serial number "${hit.serial}" is already in use by ${hit.assignedTo}.',
      );
    }
  }

  void _addSnRow() => setState(() => _rows.add(BirSnRow()));

  void _removeSnRow(BirSnRow row) {
    setState(() {
      _rows.remove(row);
      _snTimers.remove(row)?.cancel();
    });
    row.dispose();
  }

  void _openStored(Map<String, dynamic> f) async {
    final stored = BirLogic.s(f['stored']);
    if (stored.isEmpty) return;
    final url = '${_svc.api.baseUrl}/uploads/${Uri.encodeComponent(stored)}';
    try {
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) _toast('Could not open the file.');
    } catch (_) {
      _toast('Could not open the file.');
    }
  }

  Future<void> _addMoreDocs() async {
    final files = await _chooseFiles(
      multiple: true,
      cameraLabel: 'Take a photo of the document',
      fileLabel: 'Choose documents from files',
    );
    if (files.isEmpty || !mounted) return;
    setState(() {
      _addingDocs = true;
      _addDocStatus = 'Identifying and extracting document...';
    });
    for (final file in files) {
      final r = await _svc.addDocument(file.path);
      if (!mounted) return;
      if (r.failed || r.res == null) {
        _toast('Failed to process document.');
        continue;
      }
      final response = r.res!;
      if (response['error'] != null) {
        _toast('Error: ${response['error']}');
        continue;
      }
      final docType = BirLogic.s(response['document_type']);
      final fields = response['fields'] is Map
          ? Map<String, dynamic>.from(response['fields'] as Map)
          : <String, dynamic>{};
      String f(String k) => BirLogic.s(fields[k]);
      setState(() {
        if (docType == 'ID') {
          if (f('IDHolderName').isNotEmpty) {
            _authorizedPerson = f('IDHolderName');
          }
          if (f('IDHolderFirstName').isNotEmpty) {
            _firstName.text = f('IDHolderFirstName');
          }
          if (f('IDHolderMiddleName').isNotEmpty) {
            _middleName.text = f('IDHolderMiddleName');
          }
          if (f('IDHolderLastName').isNotEmpty) {
            _lastName.text = f('IDHolderLastName');
          }
          if (f('ValidIDType').isNotEmpty) _validIdType = f('ValidIDType');
          if (f('ValidIDNumber').isNotEmpty) {
            _validIdNumber = f('ValidIDNumber');
          }
          if (f('ValidIDBirthdate').isNotEmpty) {
            _birthdate.text = _displayDate(f('ValidIDBirthdate'));
          }
        } else if (docType == 'BIR_2303') {
          if (f('TIN_BranchCode').isNotEmpty || f('BranchCode').isNotEmpty) {
            final t = BirLogic.formatTin(f('TIN_BranchCode'), f('BranchCode'));
            _tin.text = t.tin;
            _branch.text = t.branch;
          }
          if (f('BusinessName').isNotEmpty) _company.text = f('BusinessName');
          if (f('BusinessAddress').isNotEmpty) {
            _address.text = f('BusinessAddress');
          }
          if (f('RDOCode').isNotEmpty) _rdo.text = f('RDOCode');
          if (f('LineOfBusiness').isNotEmpty) {
            final m = BirLogic.findPsicMatch(_psic, f('LineOfBusiness'));
            if (m != null) {
              _lob.text = m.label;
              _lobDesc = m.description;
            } else {
              _lob.text = f('LineOfBusiness');
              _lobDesc = '';
            }
          }
          if (f('TINIssuanceDate').isNotEmpty) {
            _tinIssuance.text = f('TINIssuanceDate');
          }
          if (f('RegistrationType').isNotEmpty) {
            _regType = BirLogic.normalizeRegistrationType(
              f('RegistrationType'),
            );
          }
        }
        final stored = response['stored_file'];
        if (stored is Map) {
          final m = Map<String, dynamic>.from(stored);
          m['_docType'] = docType;
          _extractionStored.add(m);
        }
        _docs.add((path: file.path, name: file.name));
      });
      if (docType == 'ID') {
        _syncOwnerFromParts();
        _toast('Valid ID detected — holder details updated.');
      } else if (docType == 'BIR_2303') {
        _toast('BIR 2303 detected — business details updated.');
      } else {
        _toast('Document type not recognized.');
      }
    }
    if (!mounted) return;
    setState(() {
      _addingDocs = false;
      _addDocStatus = 'Document analysis complete.';
    });
  }

  Future<void> _attachRequirement() async {
    final files = await _chooseFiles(
      multiple: true,
      cameraLabel: 'Take a photo of the requirement',
      fileLabel: 'Choose files',
    );
    if (files.isEmpty || !mounted) return;
    setState(() => _attaching = true);
    for (final file in files) {
      final r = await _svc.uploadAttachment(file.path);
      if (!mounted) return;
      if (r.error != null) {
        _toast('Error: ${r.error}');
      } else if (r.stored != null) {
        setState(() => _requirementStored.add(r.stored!));
        _toast(
          'Requirement attached: ${BirLogic.s(r.stored!['original']).isEmpty ? 'file' : r.stored!['original']}',
        );
      } else {
        _toast('Failed to upload file.');
      }
    }
    if (mounted) setState(() => _attaching = false);
  }

  List<Map<String, dynamic>> get _validIdFiles => _extractionStored
      .where((f) => f['_docType'] == 'ID' || f['is_valid_id'] == true)
      .toList();

  List<Map<String, dynamic>> get _entityDocFiles => _extractionStored
      .where((f) => !(f['_docType'] == 'ID' || f['is_valid_id'] == true))
      .toList();

  String _joined(String Function(BirSnRow r) pick) =>
      _rows.map(pick).where((v) => v.isNotEmpty).join('/');

  Future<void> _save() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    if (_tinBlocked) {
      _toast(
        'This TIN is already registered. Please verify the TIN before saving.',
      );
      return;
    }
    if (_snBlocked) {
      _toast(
        'A serial number is already in use. Please check the highlighted serial number fields.',
      );
      return;
    }
    final seen = <String>{};
    String? repeated;
    for (final r in _rows) {
      final v = r.sn.text.trim();
      if (v.isEmpty) continue;
      if (!seen.add(v)) {
        repeated = v;
        break;
      }
    }
    if (repeated != null) {
      setState(() {
        for (final r in _rows) {
          if (r.sn.text.trim() == repeated) {
            r.dupMessage = 'This serial number is entered more than once.';
          }
        }
      });
      _toast(
        'Duplicate serial number "$repeated" found. Each serial number must be unique.',
      );
      return;
    }

    final required = <(String, String)>[
      ('Business Name', _company.text),
      ('TIN (Taxpayer Identification No.)', _tin.text),
      ('Branch Code', _branch.text),
      ('RDO Code', _rdo.text),
      ('Line of Business (PSIC)', _lob.text),
      ('Registration Type', _regType),
      ('Business Address', _address.text),
      ('Last Name', _lastName.text),
      ('Birthdate', _birthdate.text),
      ('Software Name', _software ?? ''),
      ('Accreditation Number', _acc.text),
      for (final r in _rows) ...[
        ('Serial Number Type', r.type),
        if (r.type == 'Server') ('Server Type', r.serverType),
        ('Serial Number', r.sn.text),
        ('Brand', r.brand.text),
        ('Model', r.model.text),
      ],
    ];
    for (final f in required) {
      if (f.$2.trim().isEmpty) {
        _toast('"${f.$1}" is required. Please fill in all visible fields.');
        return;
      }
    }

    final reviewGroups = <(String, IconData, List<(String, String)>)>[
      (
        'Business',
        Icons.storefront_rounded,
        [
          ('Company / Business Name', _company.text),
          ('TIN', _tin.text),
          ('Branch Code', _branch.text),
          ('RDO Code', _rdo.text),
          ('Line of Business', _lob.text),
          ('Registration Type', _regType),
          ('Address', _address.text),
        ],
      ),
      (
        'ID Holder',
        Icons.badge_rounded,
        [
          ('Last Name', _lastName.text),
          ('First Name', _firstName.text),
          ('Middle Name', _middleName.text),
          ('Birthdate', _birthdate.text),
          ('ID Holder', _authorizedPerson),
          ('Valid ID Type', _validIdType),
          ('Valid ID Number', _validIdNumber),
        ],
      ),
      (
        'Contact',
        Icons.contact_phone_rounded,
        [('Phone Number', _phone.text), ('Email Address', _email.text)],
      ),
      (
        'Software & Hardware',
        Icons.memory_rounded,
        [
          ('Software', _software ?? ''),
          ('Serial Number Type', _joined((r) => r.type)),
          ('Serial Number', _joined((r) => r.sn.text)),
          ('Brand', _joined((r) => r.brand.text)),
          ('Model', _joined((r) => r.model.text)),
        ],
      ),
    ];
    final confirmed = await _showReviewSummary(reviewGroups);
    if (!confirmed || !mounted) return;
    await _submit();
  }

  Future<bool> _showReviewSummary(
    List<(String, IconData, List<(String, String)>)> groups,
  ) async {
    final fields = [for (final group in groups) ...group.$3];
    final missing = [
      for (final field in fields)
        if (field.$2.trim().isEmpty) field.$1,
    ];
    final captured = fields.length - missing.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final b = ctx.brand;
        final text = Theme.of(ctx).textTheme;
        final warnInk = b.isDark ? Brand.warning : const Color(0xFFB45309);
        const okInk = Color(0xFF15803D);
        return Dialog(
          backgroundColor: b.surface,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Brand.radiusLg),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 560,
              maxHeight: MediaQuery.of(ctx).size.height * 0.86,
            ),
            child: Semantics(
              scopesRoute: true,
              namesRoute: true,
              explicitChildNodes: true,
              label: 'Review extracted data',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: b.tint(b.signal, 0.16),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.fact_check_rounded,
                            color: b.signalInk,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Semantics(
                                header: true,
                                child: Text(
                                  'Review Extracted Data',
                                  style: text.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(999),
                                      child: LinearProgressIndicator(
                                        value: fields.isEmpty
                                            ? 1
                                            : captured / fields.length,
                                        semanticsLabel: 'Fields captured',
                                        semanticsValue:
                                            '$captured of ${fields.length}',
                                        minHeight: 5,
                                        backgroundColor: b.rule,
                                        color: missing.isEmpty
                                            ? okInk
                                            : warnInk,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '$captured/${fields.length}',
                                    style: text.labelSmall?.copyWith(
                                      color: b.paperDim,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (missing.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: b.tint(Brand.warning, 0.12),
                          borderRadius: BorderRadius.circular(Brand.radius),
                          border: Border.all(
                            color: warnInk.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              size: 18,
                              color: warnInk,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                missing.length == 1
                                    ? '${missing.first} is empty. Go back and fill it in, or save without it.'
                                    : '${missing.length} fields are empty: ${missing.join(', ')}.',
                                style: text.bodySmall?.copyWith(color: b.paper),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Flexible(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
                      shrinkWrap: true,
                      children: [
                        for (final group in groups) ...[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Icon(group.$2, size: 15, color: b.signalInk),
                                const SizedBox(width: 8),
                                Semantics(
                                  header: true,
                                  child: Text(
                                    group.$1.toUpperCase(),
                                    style: text.labelSmall?.copyWith(
                                      color: b.signalInk,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Divider(color: b.rule, height: 1),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              color: b.canvas,
                              borderRadius: BorderRadius.circular(Brand.radius),
                              border: Border.all(color: b.rule),
                            ),
                            child: Column(
                              children: [
                                for (var i = 0; i < group.$3.length; i++)
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      border: i == group.$3.length - 1
                                          ? null
                                          : Border(
                                              bottom: BorderSide(color: b.rule),
                                            ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          group.$3[i].$1,
                                          style: text.labelSmall?.copyWith(
                                            color: b.paperDim,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        if (group.$3[i].$2.trim().isEmpty)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: b.tint(
                                                Brand.warning,
                                                0.14,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                              border: Border.all(
                                                color: warnInk.withValues(
                                                  alpha: 0.45,
                                                ),
                                              ),
                                            ),
                                            child: Text(
                                              'Not detected',
                                              style: text.labelSmall?.copyWith(
                                                color: warnInk,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          )
                                        else
                                          Text(
                                            group.$3[i].$2.trim(),
                                            style: text.bodyMedium?.copyWith(
                                              color: b.paper,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: b.rule)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: b.paper,
                              side: BorderSide(color: b.rule),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('Go Back & Edit'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: okInk,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: () => Navigator.of(ctx).pop(true),
                            icon: const Icon(Icons.check_rounded, size: 18),
                            label: const Text('Confirm & Save'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    return ok == true;
  }

  Map<String, String> _buildFields() {
    final s = BirLogic.s;
    final serialEntries = <Map<String, String>>[
      for (final r in _rows)
        if (r.sn.text.trim().isNotEmpty || r.type.trim().isNotEmpty)
          r.toEntry(),
    ];
    final businessLine = _lobDesc.trim().isNotEmpty
        ? _lobDesc.trim()
        : _lob.text.trim();
    return <String, String>{
      'invoice_number': _invoiceNumber,
      'raw_extracted_text': _rawText,
      'companyname': _company.text,
      'tin': _tin.text,
      'branch_code': _branch.text,
      'rdo': _rdo.text,
      'tin_issuance_date': _tinIssuance.text,
      'line_of_business': _lob.text,
      'registration_type': _regType,
      'address': _address.text,
      'lastname': _lastName.text,
      'firstname': _firstName.text,
      'middlename': _middleName.text,
      'ownerName': _ownerName,
      'birthdate': _isoDate(_birthdate.text),
      'phone_number': _phone.text,
      'email_address': _email.text,
      'acc_number': _acc.text,
      'present_reading': s(_response['PresentReading']),
      'date_of_reading': s(_response['DateOfReading']),
      'last_or_number': s(_response['LastORNumber']),
      'last_cash_invoice_number': s(_response['LastCashInvoiceNumber']),
      'last_charge_invoice_number': s(_response['LastChargeInvoiceNumber']),
      'last_transaction_number': s(_response['LastTransactionNumber']),
      'pdf_file': _pdfFile,
      'extraction_mode': '1',
      'is_vat': _regType == 'VAT' ? '1' : '0',
      'softwarename': _software ?? '',
      'software_version': _version,
      'sn': _joined((r) => r.sn.text),
      'serial_number_type': _joined((r) => r.type),
      'server_type': _joined((r) => r.serverType),
      'brand': _joined((r) => r.brand.text),
      'model': _joined((r) => r.model.text),
      'serial_entries': jsonEncode(serialEntries),
      'businessline': businessLine,
      if (_extractionStored.isNotEmpty)
        'document_files': jsonEncode(_extractionStored),
      if (_requirementStored.isNotEmpty)
        'requirement_files': jsonEncode(_requirementStored),
    };
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    final fields = _buildFields();
    final res = await _svc.addCustomer(fields);
    if (!mounted) return;
    if (res.networkError != null) {
      setState(() => _saving = false);
      _toast('An error occurred: ${res.networkError}');
      return;
    }
    if (!res.ok) {
      setState(() => _saving = false);
      _toast('Client Not Added: ${res.message}');
      return;
    }
    if (res.customerId > 0) fields['customer_id'] = '${res.customerId}';
    final csv = await _svc.exportClientCsv(fields);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    if (csv.path != null) {
      final path = csv.path!;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Client added and CSV downloaded as ${csv.filename}.'),
          duration: const Duration(seconds: 8),
          persist: false,
          action: SnackBarAction(
            label: 'Open',
            onPressed: () => OpenFilex.open(path),
          ),
        ),
      );
    } else {
      messenger.showSnackBar(
        const SnackBar(content: Text('Client saved, but CSV download failed.')),
      );
    }
    setState(() => _saving = false);
    Navigator.of(context).pop(true);
  }

  Future<void> _handleBack() async {
    switch (_step) {
      case _Step.invoice:
        Navigator.of(context).pop();
      case _Step.upload:
        setState(() => _step = _Step.invoice);
        _scrollTop();
      case _Step.extracting:
        return;
      case _Step.review:
        final ok = await birConfirm(
          context,
          title: 'Discard this registration?',
          message: 'The extracted data and your edits will be lost.',
        );
        if (ok && mounted) Navigator.of(context).pop();
    }
  }

  void _runOcrSearch() {
    final term = _ocrQuery.text.trim();
    final matches = <int>[];
    if (term.isNotEmpty) {
      final hay = _rawText.toLowerCase();
      final needle = term.toLowerCase();
      var i = hay.indexOf(needle);
      while (i >= 0) {
        matches.add(i);
        i = hay.indexOf(needle, i + needle.length);
      }
    }
    setState(() {
      _ocrTerm = term;
      _ocrMatches = matches;
      _ocrIndex = matches.isEmpty ? -1 : 0;
    });
    _scrollOcrToMatch();
  }

  void _stepOcr(int delta) {
    if (_ocrMatches.isEmpty) {
      _runOcrSearch();
      return;
    }
    setState(() {
      _ocrIndex = (_ocrIndex + delta) % _ocrMatches.length;
      if (_ocrIndex < 0) _ocrIndex += _ocrMatches.length;
    });
    _scrollOcrToMatch();
  }

  void _scrollOcrToMatch() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_ocrScroll.hasClients || _ocrIndex < 0 || _rawText.isEmpty) return;
      final ratio = _ocrMatches[_ocrIndex] / _rawText.length;
      final target = (_ocrScroll.position.maxScrollExtent * ratio).clamp(
        0.0,
        _ocrScroll.position.maxScrollExtent,
      );
      _ocrScroll.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  int get _stepIndex => switch (_step) {
    _Step.invoice => 0,
    _Step.upload => 1,
    _Step.extracting => 2,
    _Step.review => 3,
  };

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return PopScope(
      canPop: _step == _Step.invoice,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: StationScaffold(
        stationLabel: 'BIR Registration',
        title: 'Register New Client',
        compact: true,
        showBottomBrand: false,
        onBack: _step == _Step.extracting ? null : _handleBack,
        belowRule: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: BirStepper(
            steps: const ['Invoice', 'Documents', 'Extract', 'Review'],
            current: _stepIndex,
          ),
        ),
        bottomBar: _bottomBar(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                child: KeyedSubtree(
                  key: ValueKey(_step),
                  child: switch (_step) {
                    _Step.invoice => _invoiceView(context),
                    _Step.upload => _uploadView(context),
                    _Step.extracting => _extractingView(context),
                    _Step.review => _reviewView(context),
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _bottomBar(BuildContext context) {
    switch (_step) {
      case _Step.invoice:
        final enabled =
            _invoiceCtrl.text.trim().isNotEmpty && !_invoiceChecking;
        return BirBottomBar(
          children: [
            Expanded(
              flex: 2,
              child: GhostButton(
                label: 'Skip — No Invoice',
                icon: Icons.fast_forward_rounded,
                onPressed: _invoiceChecking ? () {} : _invoiceSkip,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: SignalButton(
                label: 'Continue',
                busy: _invoiceChecking,
                onPressed: enabled ? _invoiceContinue : null,
              ),
            ),
          ],
        );
      case _Step.upload:
        return BirBottomBar(
          children: [
            Expanded(
              child: SignalButton(
                label: 'Start Data Extraction',
                icon: Icons.auto_awesome_rounded,
                onPressed: _startExtraction,
              ),
            ),
          ],
        );
      case _Step.extracting:
        return null;
      case _Step.review:
        return BirBottomBar(
          children: [
            Expanded(
              child: SignalButton(
                label: _saving ? 'Saving & Exporting...' : 'Save',
                icon: Icons.file_download_done_rounded,
                busy: _saving,
                onPressed: _saving ? null : _save,
              ),
            ),
          ],
        );
    }
  }

  Widget _invoiceView(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final selected = _invoiceNumber.isNotEmpty;
    return ListView(
      controller: _scroll,
      children: [
        FadeSlideIn(
          child: BirSection(
            title: 'Find Your Invoice',
            icon: Icons.receipt_long_rounded,
            children: [
              Text(
                'Enter the invoice number tied to your purchase. We\'ll verify it with TinkerPro Invoice before attaching it to this registration. Don\'t have one yet? Just skip this step.',
                style: text.bodySmall,
              ),
              const SizedBox(height: 16),
              BirLabeled(
                label: 'Invoice number',
                bottom: 8,
                child: TextField(
                  controller: _invoiceCtrl,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onChanged: (_) => setState(() {
                    _invoiceMessage = '';
                    _invoiceNumber = '';
                  }),
                  onSubmitted: (_) => _invoiceContinue(),
                  decoration: InputDecoration(
                    hintText: 'Type an invoice number, e.g. INV-00123…',
                    prefixIcon: const Icon(Icons.receipt_rounded, size: 20),
                    suffixIcon: _invoiceCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: b.paperDim,
                            ),
                            onPressed: () => setState(() {
                              _invoiceCtrl.clear();
                              _invoiceMessage = '';
                            }),
                          ),
                  ),
                ),
              ),
              if (_invoiceMessage.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Brand.radiusLg),
                    color: b.tint(b.signal, 0.1),
                    border: Border.all(color: b.signal.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      if (_invoiceChecking) ...[
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: b.signal,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Text(_invoiceMessage, style: text.bodySmall),
                      ),
                    ],
                  ),
                ),
              if (selected)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: GlowStatusPill(
                      label: 'Selected invoice: $_invoiceNumber',
                      color: Brand.success,
                      icon: Icons.check_circle_rounded,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _uploadView(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return ListView(
      controller: _scroll,
      children: [
        FadeSlideIn(
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Brand.radiusLg),
              color: b.isDark ? const Color(0xFF12304F) : Brand.navy,
              border: Border.all(color: Brand.orange.withValues(alpha: 0.32)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: Brand.orange.withValues(alpha: 0.16),
                    border: Border.all(
                      color: Brand.orange.withValues(alpha: 0.45),
                    ),
                  ),
                  child: const Icon(
                    Icons.document_scanner_rounded,
                    size: 22,
                    color: Brand.orange,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Upload your',
                        style: text.labelMedium?.copyWith(
                          color: Brand.orange,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Semantics(
                        header: true,
                        child: Text(
                          'BIR Form 2303 and Valid ID',
                          style: text.titleLarge?.copyWith(color: Colors.white),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Both documents are read in a single pass, then the form comes back prefilled for you to check.',
                        style: text.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.78),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FadeSlideIn(
          index: 1,
          child: AppCard(
            radius: Brand.radiusLg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.fact_check_rounded, size: 18, color: b.signal),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Does this client already have a BIR Registration?',
                        style: text.titleSmall,
                      ),
                    ),
                    const SizedBox(width: 8),
                    AppIconButton(
                      icon: Icons.question_mark_rounded,
                      tooltip: 'What we read off the 2303',
                      onPressed: _showGuide,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                BirDropdown<String>(
                  value: _birChoice,
                  hint: 'Select',
                  items: const [
                    DropdownMenuItem(
                      value: 'no',
                      child: Text(
                        'No — register from BIR Form 2303 & Valid ID',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'yes',
                      child: Text(
                        'Yes — upload the BIR Registration PDF instead',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  onChanged: _onBirChoice,
                ),
                const SizedBox(height: 8),
                Text(
                  _birHints[_birChoice] ?? _birHints['no']!,
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FadeSlideIn(
          index: 2,
          child: BirSection(
            title: 'Business documents',
            subtitle: 'BIR Form 2303, DTI certificate, business permit…',
            icon: Icons.upload_file_rounded,
            children: [
              BirUploadTile(
                label: 'Select Documents',
                icon: Icons.cloud_upload_rounded,
                onTap: _pickDocs,
                hint: 'PDF · Word · Images — multiple allowed',
              ),
              if (_docs.isNotEmpty) const SizedBox(height: 10),
              for (var i = 0; i < _docs.length; i++)
                BirFileRow(
                  name: _docs[i].name,
                  caption: 'Ready to extract',
                  onRemove: () => setState(() => _docs.removeAt(i)),
                ),
            ],
          ),
        ),
        if (_dupTinMessage.isNotEmpty) ...[
          const SizedBox(height: 16),
          BirNotice(
            color: Brand.danger,
            icon: Icons.warning_amber_rounded,
            title: 'Duplicate TIN Found',
            message: _dupTinMessage,
            bottom: 0,
          ),
        ],
        const SizedBox(height: 16),
        FadeSlideIn(index: 3, child: _validIdCard(context)),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline_rounded, size: 16, color: b.paperDim),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Our AI will parse information from your documents automatically.',
                style: text.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _validIdCard(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final manual = _vidMode == 'manual';
    return BirSection(
      title: 'Valid ID',
      subtitle: manual
          ? 'Type the ID holder details — no ID document required'
          : 'Upload an ID photo, PDF, or Word document',
      icon: Icons.badge_rounded,
      children: [
        Text(
          '— we\'ll extract holder details with the BIR data in one pass.',
          style: text.bodySmall,
        ),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'upload',
              icon: Icon(Icons.badge_rounded, size: 16),
              label: Text('Upload Valid ID'),
            ),
            ButtonSegment(
              value: 'manual',
              icon: Icon(Icons.keyboard_rounded, size: 16),
              label: Text('No ID — Type Manually'),
            ),
          ],
          selected: {_vidMode},
          showSelectedIcon: false,
          onSelectionChanged: (s) => _setVidMode(s.first),
        ),
        const SizedBox(height: 14),
        if (manual) ...[
          const BirNotice(
            color: Brand.info,
            icon: Icons.info_outline_rounded,
            message:
                'No ID document will be attached. Enter the ID holder\'s full name and birthdate exactly as they should appear on the client record.',
          ),
          BirField(
            label: 'Full Name',
            controller: _manualName,
            required: true,
            hint: 'e.g. DELA CRUZ, JUAN P.',
            textCapitalization: TextCapitalization.characters,
            highlight: _manualNameError,
            onChanged: (_) {
              if (_manualNameError) setState(() => _manualNameError = false);
            },
            bottom: 4,
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              '"Last, First Middle" or "First Middle Last" — we\'ll split it for you.',
              style: text.bodySmall,
            ),
          ),
          BirField(
            label: 'Birthdate',
            controller: _manualBirthdate,
            required: true,
            hint: 'MM/DD/YYYY',
            readOnly: true,
            onTap: _pickManualBirthdate,
            prefixIcon: Icons.event_rounded,
            highlight: _manualBirthError,
            bottom: 4,
          ),
          Text('Entered as MM/DD/YYYY.', style: text.bodySmall),
        ] else if (_vidPath == null)
          BirUploadTile(
            label: 'Drop ID photo or document here',
            icon: Icons.photo_camera_rounded,
            onTap: _pickValidId,
            hint: 'image, PDF, or Word — tap to browse',
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Brand.radiusLg),
              color: b.tint(Brand.success, 0.14),
              border: Border.all(color: Brand.success.withValues(alpha: 0.45)),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(Brand.radiusSm),
                  child: SizedBox(
                    width: 84,
                    height: 56,
                    child: birIsImage(_vidName ?? _vidPath!)
                        ? Image.file(
                            File(_vidPath!),
                            fit: BoxFit.cover,
                            excludeFromSemantics: true,
                            errorBuilder: (_, _, _) =>
                                Icon(Icons.image_rounded, color: b.paperDim),
                          )
                        : Container(
                            color: b.tint(b.signal, 0.1),
                            child: Icon(
                              birFileIcon(_vidName ?? ''),
                              color: b.signal,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 14,
                            color: Brand.success,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'Valid ID ready',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.labelMedium?.copyWith(
                                color: Brand.success,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _vidName ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: _pickValidId,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 44),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Change'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _extractingView(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final pct = _percent.round().clamp(0, 100);
    String eta;
    if (_progressComplete) {
      eta = 'Ready for review';
    } else if (_serverLabel.isNotEmpty) {
      eta = _serverProvider.isNotEmpty
          ? '$_serverLabel · $_serverProvider'
          : _serverLabel;
    } else if (!_uploadDone) {
      eta = 'Uploading your documents...';
    } else {
      eta = 'Starting document analysis...';
    }
    final clock = _progressTimer == null && _progressComplete
        ? ''
        : ' (${_elapsed ~/ 60}:${(_elapsed % 60).toString().padLeft(2, '0')})';
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final switchDuration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 240);
    final accent = _progressComplete ? Brand.success : b.signal;
    final stages = <(String, bool, bool)>[
      (
        'Uploading your documents',
        _uploadDone || _progressComplete,
        !_uploadDone && !_progressComplete,
      ),
      (
        _serverLabel.isEmpty
            ? 'Analyzing layout & matching fields'
            : _serverLabel,
        _progressComplete,
        _uploadDone && !_progressComplete,
      ),
      ('Structuring data for review', _progressComplete, false),
    ];
    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: GlassPanel(
            accent: accent,
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GlowStatusPill(
                  label: _progressComplete
                      ? 'Extraction complete'
                      : 'Scanning documents',
                  color: accent,
                  icon: _progressComplete
                      ? Icons.check_circle_rounded
                      : Icons.bolt_rounded,
                ),
                const SizedBox(height: 22),
                Semantics(
                  label: 'Extraction progress',
                  value: '$pct percent',
                  excludeSemantics: true,
                  child: BirScanRing(
                    progress: pct / 100,
                    complete: _progressComplete,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedSwitcher(
                          duration: switchDuration,
                          child: Text(
                            '$pct%',
                            key: ValueKey<int>(pct),
                            style: text.displaySmall?.copyWith(
                              color: b.paper,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          'Complete',
                          style: text.labelMedium?.copyWith(
                            color: b.paperDim,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'Processing Documents$clock',
                  textAlign: TextAlign.center,
                  style: text.titleLarge?.copyWith(color: b.paper),
                ),
                const SizedBox(height: 6),
                Text(
                  'Analyzing layout, matching key fields, and structuring your data for review.',
                  textAlign: TextAlign.center,
                  style: text.bodySmall?.copyWith(color: b.paperDim),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < stages.length; i++)
                        BirScanLine(
                          index: i,
                          label: stages[i].$1,
                          done: stages[i].$2,
                          active: stages[i].$3,
                        ),
                    ],
                  ),
                ),
                if (_serverProvider.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  GlowStatusPill(
                    label: _serverProvider,
                    color: Brand.info,
                    icon: Icons.memory_rounded,
                  ),
                ],
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Brand.radiusLg),
                    color: b.tint(accent, 0.08),
                    border: Border.all(color: accent.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_progressComplete)
                        const Icon(
                          Icons.check_circle_rounded,
                          size: 16,
                          color: Brand.success,
                        )
                      else
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: b.signal,
                          ),
                        ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: AnimatedSwitcher(
                          duration: switchDuration,
                          child: Text(
                            eta,
                            key: ValueKey<String>(eta),
                            textAlign: TextAlign.center,
                            style: text.labelLarge?.copyWith(
                              color: _progressComplete
                                  ? GlowStatusPill.inkFor(
                                      context,
                                      Brand.success,
                                    )
                                  : b.signalInk,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _reviewView(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return ListView(
      controller: _scroll,
      children: [
        Row(
          children: [
            FilledButton.icon(
              onPressed: _addingDocs ? null : _addMoreDocs,
              icon: _addingDocs
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Brand.onSignal,
                      ),
                    )
                  : const Icon(Icons.add_circle_rounded, size: 18),
              label: Text(_addingDocs ? 'Analyzing...' : 'Add Documents'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _addDocStatus,
                style: text.bodySmall?.copyWith(color: b.paperDim),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        FadeSlideIn(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Brand.radiusLg),
              color: b.tint(Brand.danger, 0.16),
              border: Border.all(color: Brand.danger.withValues(alpha: 0.45)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: b.tint(Brand.danger, 0.18),
                    border: Border.all(
                      color: Brand.danger.withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: Brand.danger,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MANDATORY: YOU MUST REVIEW & EDIT ALL DATA BELOW',
                        style: text.titleSmall?.copyWith(color: Brand.danger),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Our Artificial Intelligence has successfully digitized your identification documents; however, automated extraction is a technical interpretation and is not absolute. It is YOUR LEGAL RESPONSIBILITY as the authorized representative to REVIEW AND EDIT every single character before final submission. Meticulously verify the extracted Business Name, TIN, and Registration Address against your physical BIR Form 2303. Absolute precision is mandatory to guarantee total data integrity for your compliance records.',
                        style: text.bodySmall?.copyWith(color: b.paper),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FadeSlideIn(index: 1, child: _ocrCard(context)),
        const SizedBox(height: 16),
        FadeSlideIn(index: 2, child: _entityCard(context)),
        const SizedBox(height: 16),
        FadeSlideIn(index: 3, child: _ownershipCard(context)),
        const SizedBox(height: 16),
        FadeSlideIn(index: 4, child: _softwareCard(context)),
        const SizedBox(height: 16),
        FadeSlideIn(index: 5, child: _attachmentsCard(context)),
        const SizedBox(height: 16),
        Text(
          'By confirming, all extracted data will be saved to the database and a formatted CSV will be generated for BIR submission.',
          textAlign: TextAlign.center,
          style: text.bodySmall,
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _ocrCard(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final spans = <TextSpan>[];
    if (_ocrTerm.isEmpty || _ocrMatches.isEmpty) {
      spans.add(TextSpan(text: _rawText.isEmpty ? '(no text)' : _rawText));
    } else {
      var cursor = 0;
      for (var i = 0; i < _ocrMatches.length; i++) {
        final start = _ocrMatches[i];
        final end = start + _ocrTerm.length;
        if (start > cursor) {
          spans.add(TextSpan(text: _rawText.substring(cursor, start)));
        }
        spans.add(
          TextSpan(
            text: _rawText.substring(start, end),
            style: TextStyle(
              backgroundColor: i == _ocrIndex
                  ? b.signal
                  : b.tint(Brand.warning, 0.45),
              color: i == _ocrIndex ? Brand.onSignal : b.paper,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
        cursor = end;
      }
      if (cursor < _rawText.length) {
        spans.add(TextSpan(text: _rawText.substring(cursor)));
      }
    }
    return AppCard(
      padding: EdgeInsets.zero,
      radius: Brand.radiusLg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _ocrOpen = !_ocrOpen),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const IconTile(
                    icon: Icons.text_snippet_rounded,
                    size: 36,
                    iconSize: 18,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('OCR Extraction Log', style: text.titleMedium),
                        Text(
                          'Raw text read from your documents',
                          style: text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _ocrOpen
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: b.paperDim,
                  ),
                ],
              ),
            ),
          ),
          if (_ocrOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ocrQuery,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _runOcrSearch(),
                          decoration: const InputDecoration(
                            hintText: 'Search word in OCR Extraction Log...',
                            prefixIcon: Icon(Icons.search_rounded, size: 20),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Previous match',
                        onPressed: () => _stepOcr(-1),
                        icon: const Icon(Icons.keyboard_arrow_up_rounded),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Next match',
                        onPressed: () => _stepOcr(1),
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      '${_ocrMatches.isEmpty ? 0 : _ocrIndex + 1} / ${_ocrMatches.length}',
                      textAlign: TextAlign.right,
                      style: text.labelMedium,
                    ),
                  ),
                  Container(
                    height: 260,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: b.surfaceHi,
                      borderRadius: BorderRadius.circular(Brand.radiusSm),
                      border: Border.all(color: b.rule),
                    ),
                    child: SingleChildScrollView(
                      controller: _ocrScroll,
                      child: SelectableText.rich(
                        TextSpan(
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            height: 1.45,
                            color: b.paper,
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
      ),
    );
  }

  Widget _entityCard(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final lobBadge = BirLogic.lobBadge(_lobBadgeValue, _lobSource);
    final vatBadge = _vatBadgeVisible
        ? BirLogic.vatBadge(_regType, _vatSource)
        : null;
    final lobQuery = _lob.text.trim();
    final suggestions = lobQuery.isEmpty || _lobDesc.isNotEmpty
        ? const <PsicItem>[]
        : BirLogic.searchPsic(_psic, lobQuery).take(30).toList();
    final showDetected =
        _lobFocus.hasFocus && lobQuery.isEmpty && _lobCandidates.isNotEmpty;
    final currentCode = BirLogic.lobCodeFromValue(_lob.text);
    var recommended = _lobCandidates.indexWhere((c) => c.code == currentCode);
    if (recommended < 0) recommended = 0;
    final entityDocs = _entityDocFiles;

    return BirSection(
      title: 'Entity Information',
      icon: Icons.business_rounded,
      children: [
        BirField(
          label: 'Business Name',
          controller: _company,
          textCapitalization: TextCapitalization.characters,
        ),
        BirField(
          label: 'TIN (Taxpayer Identification No.)',
          controller: _tin,
          keyboardType: TextInputType.number,
          onChanged: _onTinChanged,
          errorText: _tinDupMessage.isEmpty ? null : _tinDupMessage,
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: BirField(
                label: 'Branch Code',
                controller: _branch,
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: BirField(label: 'RDO Code', controller: _rdo),
            ),
          ],
        ),
        BirLabeled(
          label: 'Line of Business (PSIC)',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _lob,
                focusNode: _lobFocus,
                maxLines: null,
                onChanged: (_) => setState(() => _lobDesc = ''),
                decoration: InputDecoration(
                  hintText: 'Search PSIC code or description',
                  suffixIcon: _lob.text.isEmpty
                      ? const Icon(Icons.search_rounded, size: 20)
                      : IconButton(
                          tooltip: 'Clear',
                          icon: Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: b.paperDim,
                          ),
                          onPressed: () => setState(() {
                            _lob.clear();
                            _lobDesc = '';
                          }),
                        ),
                ),
              ),
              if (suggestions.isNotEmpty || showDetected)
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
                      if (showDetected) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                          child: Text(
                            'Detected on document',
                            style: text.labelSmall,
                          ),
                        ),
                        for (final c in _lobCandidates)
                          _suggestionTile(context, c.label, () {
                            setState(() {
                              _lob.text = c.label;
                              _lobDesc = c.description;
                            });
                            _lobFocus.unfocus();
                          }),
                      ],
                      for (final p in suggestions)
                        _suggestionTile(context, p.label, () {
                          setState(() {
                            _lob.text = p.label;
                            _lobDesc = p.description;
                          });
                          _lobFocus.unfocus();
                        }),
                    ],
                  ),
                ),
              if (lobBadge != null)
                BirBadge(
                  text: lobBadge.text,
                  color: lobBadge.guess ? Brand.warning : Brand.success,
                  icon: lobBadge.guess
                      ? Icons.warning_amber_rounded
                      : Icons.description_rounded,
                ),
              if (_lobCandidates.length >= 2)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: b.tint(b.signal, 0.06),
                    borderRadius: BorderRadius.circular(Brand.radiusSm),
                    border: Border.all(color: b.tint(b.signal, 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 14,
                            color: b.signalInk,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Multiple PSIC detected — confirm the correct line of business',
                              style: text.labelSmall?.copyWith(
                                color: b.signalInk,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (var i = 0; i < _lobCandidates.length; i++)
                            ChoiceChip(
                              selected: i == recommended,
                              label: Text(
                                i == recommended
                                    ? '${_lobCandidates[i].label} (Recommended)'
                                    : _lobCandidates[i].label,
                              ),
                              onSelected: (_) => setState(() {
                                _lob.text = _lobCandidates[i].label;
                                _lobDesc = _lobCandidates[i].description;
                              }),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        BirLabeled(
          label: 'Registration Type',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BirDropdown<String>(
                value: _regType,
                hint: 'Select registration type',
                items: const [
                  DropdownMenuItem(
                    value: '',
                    child: Text('Select registration type'),
                  ),
                  DropdownMenuItem(value: 'VAT', child: Text('VAT')),
                  DropdownMenuItem(value: 'NON-VAT', child: Text('NON-VAT')),
                ],
                onChanged: (v) => setState(() {
                  _regType = BirLogic.normalizeRegistrationType(v ?? '');
                  _vatSource = '';
                  _vatBadgeVisible = true;
                }),
              ),
              if (vatBadge != null)
                BirBadge(
                  text: vatBadge.text,
                  color: vatBadge.uncertain
                      ? Brand.warning
                      : (_regType == 'VAT' ? Brand.info : Brand.success),
                  icon: vatBadge.uncertain
                      ? Icons.warning_amber_rounded
                      : (_regType == 'VAT'
                            ? Icons.request_quote_rounded
                            : Icons.description_rounded),
                ),
            ],
          ),
        ),
        BirField(
          label: 'Business Address',
          controller: _address,
          maxLines: 3,
          bottom: entityDocs.isEmpty ? 0 : 14,
        ),
        if (entityDocs.isNotEmpty) ...[
          Text('Uploaded Documents', style: text.labelLarge),
          const SizedBox(height: 6),
          for (final f in entityDocs)
            BirFileRow(
              name: BirLogic.s(f['original']).isNotEmpty
                  ? BirLogic.s(f['original'])
                  : BirLogic.s(f['stored']),
              caption: 'Business Document',
              done: true,
              onView: () => _openStored(f),
            ),
        ],
      ],
    );
  }

  Widget _suggestionTile(
    BuildContext context,
    String label,
    VoidCallback onTap,
  ) {
    final b = context.brand;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: b.rule)),
        ),
        child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ),
    );
  }

  Widget _ownershipCard(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final vids = _validIdFiles;
    return BirSection(
      title: 'Registration & Ownership',
      icon: Icons.badge_rounded,
      children: [
        BirLabeled(
          label: 'VALID ID Holder Name',
          child: vids.isEmpty
              ? Text(
                  _authorizedPerson.isEmpty
                      ? (_validIdType.isEmpty ? '—' : _validIdType)
                      : '$_authorizedPerson${_validIdType.isEmpty ? '' : ' · $_validIdType'}',
                  style: text.bodyMedium,
                )
              : Column(
                  children: [
                    for (final f in vids)
                      BirFileRow(
                        name: BirLogic.s(f['original']).isNotEmpty
                            ? BirLogic.s(f['original'])
                            : BirLogic.s(f['stored']),
                        caption: _authorizedPerson.isEmpty
                            ? 'Uploaded Valid ID'
                            : 'Uploaded Valid ID · $_authorizedPerson',
                        icon: Icons.badge_rounded,
                        done: true,
                        onView: () => _openStored(f),
                      ),
                  ],
                ),
        ),
        BirField(
          label: 'Last Name',
          controller: _lastName,
          textCapitalization: TextCapitalization.characters,
          onChanged: (_) => _syncOwnerFromParts(),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: BirField(
                label: 'First Name',
                controller: _firstName,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => _syncOwnerFromParts(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: BirField(
                label: 'Middle Name',
                controller: _middleName,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => _syncOwnerFromParts(),
              ),
            ),
          ],
        ),
        BirField(
          label: 'Birthdate',
          controller: _birthdate,
          hint: 'MM/DD/YYYY',
          keyboardType: TextInputType.datetime,
          prefixIcon: Icons.event_rounded,
          suffix: IconButton(
            tooltip: 'Pick date',
            icon: const Icon(Icons.calendar_month_rounded, size: 18),
            onPressed: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate:
                    _parseDate(_birthdate.text) ?? DateTime(now.year - 30),
                firstDate: DateTime(1900),
                lastDate: now,
              );
              if (picked != null) {
                setState(() => _birthdate.text = _mdy(picked));
              }
            },
          ),
        ),
        BirField(
          label: 'Phone Number',
          controller: _phone,
          keyboardType: TextInputType.phone,
          prefixIcon: Icons.phone_rounded,
        ),
        BirField(
          label: 'Email Address',
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          prefixIcon: Icons.mail_outline_rounded,
          bottom: 0,
        ),
      ],
    );
  }

  Widget _softwareCard(BuildContext context) {
    final versions = _versionsFor(_software);
    final names = _catalog.keys.toList();
    return BirSection(
      title: 'Software & Hardware',
      icon: Icons.memory_rounded,
      children: [
        BirLabeled(
          label: 'Software Name',
          child: BirDropdown<String>(
            value: _software,
            hint: '-- Select Software --',
            icon: Icons.apps_rounded,
            items: [
              for (final n in names)
                DropdownMenuItem(
                  value: n,
                  child: Text(n, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() {
              _software = v;
              final vs = _versionsFor(v);
              _version = vs.isNotEmpty
                  ? vs.first.version
                  : (BirLogic.softwareVersionByName[v ?? ''] ?? '');
              _applyCatalogAccreditation();
            }),
          ),
        ),
        BirLabeled(
          label: 'Software Version',
          child: BirDropdown<String>(
            value: _version,
            hint: _software == null
                ? '-- Select Version --'
                : (versions.isEmpty
                      ? '-- No version configured --'
                      : '-- Select Version --'),
            icon: Icons.new_releases_rounded,
            items: [
              for (final v in versions)
                DropdownMenuItem(value: v.version, child: Text(v.version)),
            ],
            onChanged: versions.isEmpty
                ? null
                : (v) => setState(() {
                    _version = v ?? '';
                    _applyCatalogAccreditation();
                  }),
          ),
        ),
        BirField(label: 'Accreditation Number', controller: _acc),
        const BirLabeled(
          label: 'Serial Number Entries',
          bottom: 8,
          child: SizedBox.shrink(),
        ),
        for (var i = 0; i < _rows.length; i++) _snRowCard(context, i),
      ],
    );
  }

  Widget _snRowCard(BuildContext context, int index) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final row = _rows[index];
    final types = _rows.map((r) => r.type).toList();
    final typeOptions = BirLogic.serialTypeOptions(types, index);
    return Container(
      margin: EdgeInsets.only(bottom: index == _rows.length - 1 ? 0 : 12),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 14),
      decoration: BoxDecoration(
        color: b.canvas,
        borderRadius: BorderRadius.circular(Brand.radius),
        border: Border.all(color: row.isDuplicate ? Brand.danger : b.rule),
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
              if (index == 0)
                IconButton(
                  tooltip: 'Add Serial Number',
                  onPressed: _addSnRow,
                  icon: const Icon(
                    Icons.add_circle_rounded,
                    color: Brand.success,
                  ),
                )
              else
                IconButton(
                  tooltip: 'Remove',
                  onPressed: () => _removeSnRow(row),
                  icon: const Icon(
                    Icons.remove_circle_rounded,
                    color: Brand.danger,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: BirLabeled(
                        label: 'Type',
                        child: Row(
                          children: [
                            Expanded(
                              child: BirDropdown<String>(
                                value: row.type.isEmpty ? null : row.type,
                                hint: '-- Select Type --',
                                items: [
                                  for (final t in typeOptions)
                                    DropdownMenuItem(value: t, child: Text(t)),
                                ],
                                onChanged: (t) => setState(() {
                                  row.type = t ?? '';
                                  if (row.type != 'Server') {
                                    row.serverType = '';
                                  }
                                }),
                              ),
                            ),
                            if (row.type.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: 'Clear type',
                                onPressed: () => setState(() {
                                  row.type = '';
                                  row.serverType = '';
                                }),
                                icon: const Icon(
                                  Icons.remove_circle_rounded,
                                  color: Brand.danger,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (row.type == 'Server') ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: BirLabeled(
                          label: 'Server Type',
                          child: BirDropdown<String>(
                            value: row.serverType.isEmpty
                                ? null
                                : row.serverType,
                            hint: '-- Select Server Type --',
                            items: [
                              for (final t in BirLogic.serverTypeOptions)
                                DropdownMenuItem(value: t, child: Text(t)),
                            ],
                            onChanged: (t) =>
                                setState(() => row.serverType = t ?? ''),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                BirSerialField(
                  controller: row.sn,
                  search: _svc.searchLicenseSerials,
                  onChanged: (_) => _onSnChanged(row),
                  onSelected: (hit) => _onSnPicked(row, hit),
                  errorText: row.dupMessage.isEmpty ? null : row.dupMessage,
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: BirLabeled(
                        label: 'Brand',
                        bottom: 0,
                        child: BirCombo(
                          controller: row.brand,
                          options: BirLogic.brandOptions,
                          hint: 'Brand',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: BirLabeled(
                        label: 'Model',
                        bottom: 0,
                        child: BirCombo(
                          controller: row.model,
                          options: BirLogic.modelOptions,
                          hint: 'Model',
                        ),
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

  Widget _attachmentsCard(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return BirSection(
      title: 'Uploaded Attachments',
      icon: Icons.attach_file_rounded,
      children: [
        if (_requirementStored.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 18),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: b.surfaceHi,
              borderRadius: BorderRadius.circular(Brand.radius),
            ),
            child: Column(
              children: [
                Icon(Icons.cloud_upload_rounded, color: b.paperDim),
                const SizedBox(height: 6),
                Text('No requirement attachments yet', style: text.bodySmall),
              ],
            ),
          )
        else
          for (var i = 0; i < _requirementStored.length; i++)
            BirFileRow(
              name: BirLogic.s(_requirementStored[i]['original']).isNotEmpty
                  ? BirLogic.s(_requirementStored[i]['original'])
                  : BirLogic.s(_requirementStored[i]['stored']),
              caption: 'Requirement',
              done: true,
              onView: () => _openStored(_requirementStored[i]),
              onRemove: () => setState(() => _requirementStored.removeAt(i)),
            ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _attaching ? null : _attachRequirement,
          icon: _attaching
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: b.signal,
                  ),
                )
              : const Icon(Icons.add_rounded, size: 18),
          label: Text(_attaching ? 'Uploading...' : 'Attach Requirement'),
        ),
      ],
    );
  }
}
