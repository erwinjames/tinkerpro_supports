import 'dart:io' as io;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api_client.dart';
import '../services/bir_register_service.dart';
import '../theme.dart';
import 'bir_widgets.dart';
import '../widgets/tp_loader.dart';

class BirRegisterUploadResult {
  const BirRegisterUploadResult({
    this.prefill,
    this.birRegistrationPdf = false,
  });
  final Map<String, dynamic>? prefill;
  final bool birRegistrationPdf;
}

class BirRegisterUploadDialog extends StatefulWidget {
  const BirRegisterUploadDialog({
    super.key,
    required this.api,
    this.customerId,
    this.allowBirPdfChoice = true,
  });

  final ApiClient api;
  final int? customerId;
  final bool allowBirPdfChoice;

  static Future<BirRegisterUploadResult?> show(
    BuildContext context, {
    required ApiClient api,
    int? customerId,
    bool allowBirPdfChoice = true,
  }) {
    return showDialog<BirRegisterUploadResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BirRegisterUploadDialog(
        api: api,
        customerId: customerId,
        allowBirPdfChoice: allowBirPdfChoice,
      ),
    );
  }

  @override
  State<BirRegisterUploadDialog> createState() =>
      _BirRegisterUploadDialogState();
}

class _BirRegisterUploadDialogState extends State<BirRegisterUploadDialog> {
  static const _docExts = [
    'pdf',
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'bmp',
    'doc',
    'docx',
  ];
  static const _hints = {
    'no':
        'We\'ll read the business details from BIR Form 2303 and the ID holder from the valid ID.',
    'yes':
        'We\'ll open the BIR Registration upload so the Application for Registration PDF can be extracted directly.',
  };

  late final BirRegisterService _svc = BirRegisterService(widget.api);
  String _choice = 'no';
  final List<({String path, String name})> _files = [];
  String _vidMode = 'upload';
  ({String path, String name})? _vid;
  final _manualName = TextEditingController();
  DateTime? _manualBirth;
  bool _busy = false;
  int _percent = 0;
  String _stage = '';
  String _dupMsg = '';
  String _error = '';
  bool _nameError = false;
  bool _birthError = false;
  bool _vidPulse = false;

  @override
  void dispose() {
    _manualName.dispose();
    super.dispose();
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Future<List<PlatformFile>> _pick({bool multiple = false}) async {
    try {
      final r = await FilePicker.platform.pickFiles(
        allowMultiple: multiple,
        type: FileType.custom,
        allowedExtensions: _docExts,
      );
      return (r?.files ?? const []).where((f) => f.path != null).toList();
    } catch (_) {
      _toast('Could not open the file picker.');
      return const [];
    }
  }

  Future<void> _pickDocs() async {
    final picked = await _pick(multiple: true);
    if (picked.isEmpty) return;
    setState(() {
      for (final f in picked) {
        _files.add((path: f.path!, name: f.name));
      }
    });
  }

  Future<void> _pickVid() async {
    final picked = await _pick();
    if (picked.isEmpty) return;
    setState(() => _vid = (path: picked.first.path!, name: picked.first.name));
  }

  Future<void> _pickBirth() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _manualBirth ?? DateTime(now.year - 30),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (d != null) {
      setState(() {
        _manualBirth = d;
        _birthError = false;
      });
    }
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _mdy(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year.toString().padLeft(4, '0')}';

  void _focusVid(String message) {
    _toast(message);
    setState(() => _vidPulse = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _vidPulse = false);
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_files.isEmpty) {
      _toast('Please upload at least one document.');
      return;
    }
    String? manualName;
    String? manualBirth;
    if (_vidMode == 'manual') {
      if (_manualName.text.trim().isEmpty) {
        setState(() => _nameError = true);
        _focusVid('Enter the ID holder\'s full name.');
        return;
      }
      if (_manualBirth == null) {
        setState(() => _birthError = true);
        _focusVid('Enter the ID holder\'s birthdate.');
        return;
      }
      manualName = _manualName.text.trim();
      manualBirth = _iso(_manualBirth!);
    } else if (_vid == null) {
      _focusVid('Please upload a Valid ID before proceeding.');
      return;
    }
    setState(() {
      _busy = true;
      _percent = 0;
      _stage = 'Uploading your documents...';
      _error = '';
    });
    try {
      final job = await _svc.startExtraction(
        files: _files.map((f) => f.path).toList(),
        validIdPath: _vid?.path,
        manualName: manualName,
        manualBirthdate: manualBirth,
      );
      if (!mounted) return;
      setState(() {
        _percent = 30;
        _stage = 'Starting document analysis...';
      });
      await _svc.pollExtraction(
        job,
        onProgress: (p) {
          if (!mounted) return;
          final pct = int.tryParse('${p['percent'] ?? ''}');
          final label = (p['label'] ?? '').toString();
          final provider = (p['provider'] ?? '').toString();
          setState(() {
            if (pct != null && pct > _percent) _percent = pct;
            if (label.isNotEmpty) {
              _stage = provider.isNotEmpty ? '$label · $provider' : label;
            }
          });
        },
      );
      final prefill = await _svc.prefill(
        job,
        customerId: widget.customerId,
        manualName: manualName,
        manualBirthdate: manualBirth,
      );
      if (!mounted) return;
      setState(() {
        _percent = 100;
        _stage = 'Ready for review';
      });
      final check = prefill['tin_check'] is Map
          ? Map<String, dynamic>.from(prefill['tin_check'])
          : const <String, dynamic>{};
      final tin = (check['tin'] ?? '').toString();
      if (tin.length >= 9) {
        final dup = await _svc.checkTin(
          tin,
          (check['branch_code'] ?? '').toString(),
          upload: true,
        );
        if (!mounted) return;
        if (dup.duplicate) {
          setState(() {
            _busy = false;
            _dupMsg = dup.message;
          });
          _toast(
            'Duplicate TIN detected. This client may already be registered.',
          );
          return;
        }
      }
      setState(() {
        _busy = false;
        _dupMsg = '';
      });
      final cmp = prefill['doc_comparison'];
      if (cmp is List && cmp.length > 1) {
        final go = await _DocComparisonDialog.show(
          context,
          cmp
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList(),
          ((prefill['fields'] as Map?)?['companyname'] ?? '').toString(),
        );
        if (go != true || !mounted) return;
      }
      prefill['manual_valid_id'] = manualName != null;
      Navigator.of(context).pop(BirRegisterUploadResult(prefill: prefill));
    } on BirRegisterException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast('Extraction failed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        BirDialogShell(
          title: 'Register New Client',
          icon: Icons.receipt_long,
          width: 820,
          onClose: _busy ? () {} : () => Navigator.of(context).pop(),
          child: AbsorbPointer(absorbing: _busy, child: _body()),
        ),
        if (_busy) Positioned.fill(child: _overlay()),
      ],
    );
  }

  Widget _body() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Upload your',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, color: Color(0xFF6C757D)),
        ),
        const Text(
          'BIR Form 2303 and Valid ID',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: Brand.signal,
          ),
        ),
        const SizedBox(height: 22),
        _choiceBox(),
        const SizedBox(height: 18),
        _dropArea(),
        if (_dupMsg.isNotEmpty) ...[const SizedBox(height: 16), _dupAlert()],
        const SizedBox(height: 26),
        _validIdCard(),
        if (_error.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(_error, style: const TextStyle(color: Brand.danger)),
        ],
        const SizedBox(height: 30),
        Center(
          child: BirSolidButton(
            label: 'Start Data Extraction',
            icon: Icons.auto_fix_high,
            height: 52,
            fontSize: 16,
            busy: _busy,
            onPressed: _submit,
          ),
        ),
        const SizedBox(height: 10),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, size: 14, color: Color(0xFF6C757D)),
            SizedBox(width: 4),
            Text(
              'Our AI will parse information from your documents automatically.',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF6C757D)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _choiceBox() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8F1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFE0B2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.fact_check_outlined, size: 18, color: Brand.signal),
              SizedBox(width: 8),
              Text(
                'Does this client already have a BIR Registration?',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Brand.navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _choice,
            isExpanded: true,
            isDense: true,
            items: [
              const DropdownMenuItem(
                value: 'no',
                child: Text('No — register from BIR Form 2303 & Valid ID'),
              ),
              if (widget.allowBirPdfChoice)
                const DropdownMenuItem(
                  value: 'yes',
                  child: Text('Yes — upload the BIR Registration PDF instead'),
                ),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _choice = v);
              if (v == 'yes') {
                Navigator.of(
                  context,
                ).pop(const BirRegisterUploadResult(birRegistrationPdf: true));
              }
            },
          ),
          const SizedBox(height: 8),
          Text(
            _hints[_choice] ?? _hints['no']!,
            style: const TextStyle(fontSize: 12.5, color: Color(0xFF6C757D)),
          ),
        ],
      ),
    );
  }

  Widget _dropArea() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: _pickDocs,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFCF9),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFD9DEE5), width: 2),
            ),
            child: Column(
              children: [
                const Icon(Icons.cloud_upload, size: 64, color: Brand.signal),
                const SizedBox(height: 12),
                const Text(
                  'DRAG & DROP FILES',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Brand.navy,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'or click to browse from your computer',
                  style: TextStyle(color: Color(0xFF6C757D)),
                ),
                const SizedBox(height: 16),
                BirSolidButton(
                  label: 'Select Documents',
                  icon: Icons.folder_open,
                  onPressed: _pickDocs,
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final p in const [
                      (Icons.picture_as_pdf, 'PDF'),
                      (Icons.description, 'Word'),
                      (Icons.image, 'Images'),
                      (Icons.shield, 'Secure'),
                    ])
                      Chip(
                        avatar: Icon(p.$1, size: 14),
                        label: Text(p.$2),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        for (var i = 0; i < _files.length; i++)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(
              children: [
                Icon(
                  _files[i].name.toLowerCase().endsWith('.pdf')
                      ? Icons.picture_as_pdf
                      : Icons.insert_drive_file_outlined,
                  size: 18,
                  color: Brand.signal,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_files[i].name, overflow: TextOverflow.ellipsis),
                ),
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => _files.removeAt(i)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _dupAlert() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8D7DA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF5C6CB)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFF721C24)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Duplicate TIN Found',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF721C24),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _dupMsg,
                  style: const TextStyle(
                    color: Color(0xFF721C24),
                    fontSize: 13.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeBtn(String mode, IconData icon, String label) {
    final active = _vidMode == mode;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _vidMode = mode),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: active ? Brand.signal : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? Brand.signal : const Color(0xFFE2E6EB),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: active ? Colors.white : Brand.navy),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.white : Brand.navy,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _validIdCard() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _vidPulse ? Brand.signal : const Color(0xFFE5E7EB),
          width: _vidPulse ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.badge_outlined, color: Brand.signal),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Valid ID',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Brand.navy,
                      ),
                    ),
                    Text(
                      'Upload an ID photo, PDF, or Word document',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF6C757D),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: Text(
                  '— we\'ll extract holder details with the BIR data in one pass.',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 12, color: Color(0xFF6C757D)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _modeBtn('upload', Icons.badge, 'Upload Valid ID'),
              const SizedBox(width: 10),
              _modeBtn('manual', Icons.keyboard, 'No ID — Type Manually'),
            ],
          ),
          const SizedBox(height: 14),
          if (_vidMode == 'manual') _manualBlock() else _uploadBlock(),
        ],
      ),
    );
  }

  Widget _manualBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: Color(0xFF1D4ED8)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'No ID document will be attached. Enter the ID holder\'s full name and birthdate exactly as they should appear on the client record.',
                  style: TextStyle(fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text.rich(
                    TextSpan(
                      text: 'Full Name ',
                      style: TextStyle(fontWeight: FontWeight.w700),
                      children: [
                        TextSpan(
                          text: '*',
                          style: TextStyle(color: Brand.danger),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _manualName,
                    onChanged: (_) {
                      if (_nameError) setState(() => _nameError = false);
                    },
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'e.g. DELA CRUZ, JUAN P.',
                      errorText: _nameError ? '' : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '"Last, First Middle" or "First Middle Last" — we\'ll split it for you.',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFF6C757D)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text.rich(
                    TextSpan(
                      text: 'Birthdate ',
                      style: TextStyle(fontWeight: FontWeight.w700),
                      children: [
                        TextSpan(
                          text: '*',
                          style: TextStyle(color: Brand.danger),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    readOnly: true,
                    onTap: _pickBirth,
                    controller: TextEditingController(
                      text: _manualBirth == null ? '' : _mdy(_manualBirth!),
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'mm/dd/yyyy',
                      errorText: _birthError ? '' : null,
                      suffixIcon: const Icon(
                        Icons.calendar_today_outlined,
                        size: 16,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Saved as YYYY-MM-DD.',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFF6C757D)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  bool _isImage(String name) => RegExp(
    r'\.(png|jpe?g|gif|webp|bmp)$',
    caseSensitive: false,
  ).hasMatch(name);

  Widget _uploadBlock() {
    final v = _vid;
    if (v == null) {
      return InkWell(
        onTap: _pickVid,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 28),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFCF9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFD9DEE5), width: 2),
          ),
          child: const Column(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: Color(0xFFFFF4EA),
                child: Icon(Icons.photo_camera, color: Brand.signal),
              ),
              SizedBox(height: 10),
              Text(
                'Drop ID photo or document here',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Brand.navy,
                ),
              ),
              Text(
                'image, PDF, or Word — click to browse',
                style: TextStyle(fontSize: 12.5, color: Color(0xFF6C757D)),
              ),
            ],
          ),
        ),
      );
    }
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 120,
            height: 76,
            child: _isImage(v.name)
                ? Image.file(io.File(v.path), fit: BoxFit.cover)
                : Container(
                    color: const Color(0xFFF1F5F9),
                    child: const Icon(Icons.description, color: Brand.navy),
                  ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(v.name, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _pickVid,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Change'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _overlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.45),
      alignment: Alignment.center,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bolt, size: 16, color: Brand.signal),
                    SizedBox(width: 4),
                    Text(
                      'Extracting documents',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Brand.signal,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: 120,
                  height: 120,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.expand(
                        child: TpLoader(
                          value: _percent / 100,
                          strokeWidth: 10,
                          color: Brand.signal,
                          backgroundColor: const Color(0x14FF7D00),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$_percent%',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: Brand.navy,
                            ),
                          ),
                          const Text(
                            'Complete',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF6C757D),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Processing Documents',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Brand.navy,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Analyzing layout, matching key fields, and structuring your data for review.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF6C757D)),
                ),
                const SizedBox(height: 6),
                Text(
                  _stage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Brand.signal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DocComparisonDialog extends StatelessWidget {
  const _DocComparisonDialog({required this.items, required this.finalName});
  final List<Map<String, dynamic>> items;
  final String finalName;

  static Future<bool?> show(
    BuildContext context,
    List<Map<String, dynamic>> items,
    String finalName,
  ) => showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DocComparisonDialog(items: items, finalName: finalName),
  );

  @override
  Widget build(BuildContext context) {
    return BirDialogShell(
      title: 'Document Validation',
      icon: Icons.warning_amber_rounded,
      width: 760,
      onClose: () => Navigator.of(context).pop(false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text.rich(
            TextSpan(
              text: 'We found ',
              children: [
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
          ),
          const SizedBox(height: 16),
          for (final e in items) ...[_card(e), const SizedBox(height: 10)],
          if (finalName.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0x14FF7D00),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0x33FF7D00)),
              ),
              child: Text.rich(
                TextSpan(
                  text: 'Resolved Business Name: ',
                  style: const TextStyle(color: Color(0xFF6C757D)),
                  children: [
                    TextSpan(
                      text: finalName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Brand.signal,
                      ),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(false),
                icon: const Icon(Icons.redo, size: 16),
                label: const Text('Re-upload Documents'),
              ),
              const SizedBox(width: 12),
              BirSolidButton(
                label: 'Continue Anyway',
                icon: Icons.arrow_forward,
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _card(Map<String, dynamic> e) {
    final match = e['match'] == true;
    final c = match ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
    final name = (e['name'] ?? '').toString();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c, width: 1.5),
      ),
      child: Row(
        children: [
          Icon(match ? Icons.check_circle : Icons.cancel, color: c),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (e['file'] ?? '').toString(),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  name.isEmpty ? 'No business name found' : name,
                  style: TextStyle(
                    fontSize: 15,
                    fontStyle: name.isEmpty ? FontStyle.italic : null,
                  ),
                ),
              ],
            ),
          ),
          Text(
            match ? 'MATCH' : 'MISMATCH',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: c,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
