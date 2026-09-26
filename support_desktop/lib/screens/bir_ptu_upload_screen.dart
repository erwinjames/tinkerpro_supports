import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api_client.dart';
import '../services/bir_step2_service.dart';
import 'bir_step2_widgets.dart';
import '../widgets/tp_loader.dart';

class BirPtuUploadScreen extends StatefulWidget {
  const BirPtuUploadScreen({
    super.key,
    required this.service,
    required this.customerId,
    required this.serialNumber,
  });

  final BirStep2Service service;
  final int customerId;
  final String serialNumber;

  static Future<bool?> show(
    BuildContext context, {
    required ApiClient api,
    required int customerId,
    required String serialNumber,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BirPtuUploadScreen(
        service: BirStep2Service(api),
        customerId: customerId,
        serialNumber: serialNumber,
      ),
    );
  }

  @override
  State<BirPtuUploadScreen> createState() => _BirPtuUploadScreenState();
}

class _BirPtuUploadScreenState extends State<BirPtuUploadScreen> {
  final List<({String path, String name})> _files = [];
  bool _busy = false;

  Future<void> _pick() async {
    if (_busy) return;
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
    } catch (_) {
      if (mounted) {
        birToast(context, 'Could not open the file picker.', error: true);
      }
      return;
    }
    final picked = (result?.files ?? const <PlatformFile>[])
        .where((f) => f.path != null)
        .map((f) => (path: f.path!, name: f.name))
        .toList();
    if (picked.isEmpty) return;
    setState(() => _files.addAll(picked));
  }

  void _reset() {
    setState(() {
      _busy = false;
      _files.clear();
    });
  }

  Future<void> _continue() async {
    if (_busy) return;
    if (_files.isEmpty) {
      birToast(context, 'Please select a PDF file.', error: true);
      return;
    }
    setState(() => _busy = true);
    final cid = '${widget.customerId}';
    final raw = await widget.service.extractPtu(
      customerId: cid,
      serialNumber: widget.serialNumber,
      paths: _files.map((f) => f.path).toList(),
    );
    if (!mounted) return;
    if (raw['__failed'] == true) {
      birToast(
        context,
        'Failed to process PDF file. Please try again.',
        error: true,
      );
      _reset();
      return;
    }
    final extraction = raw['data'] is List ? raw['data'] : raw;
    final resolved = await widget.service.ptuResolve(
      customerId: cid,
      serialNumber: widget.serialNumber,
      extraction: extraction,
    );
    if (!mounted) return;
    if (!resolved.ok) {
      birToast(context, resolved.message, error: true);
      if (resolved.data['status'] == 'mismatch') {
        _reset();
      } else {
        setState(() => _busy = false);
      }
      return;
    }
    final payload = Map<String, dynamic>.from(
      resolved.data['payload'] as Map? ?? {},
    ).map((k, v) => MapEntry(k, '${v ?? ''}'));
    final saved = await widget.service.step3Update(payload);
    if (!mounted) return;
    if (saved.ok) {
      birToast(context, 'Successfully Added');
      Navigator.of(context).pop(true);
      return;
    }
    birToast(
      context,
      saved.data.isEmpty
          ? saved.message
          : 'Failed to update customer: ${saved.message}',
      error: true,
    );
    _reset();
  }

  @override
  Widget build(BuildContext context) {
    return BirNavyModal(
      title: 'Upload PTU Document',
      icon: Icons.upload_file,
      subtitle: 'Upload the Permit to Use Sales Machine PDF file.',
      width: 520,
      closeEnabled: !_busy,
      onClose: _busy ? null : () => Navigator.of(context).pop(),
      child: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(32, 24, 32, 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BirPdfDropZone(onTap: _busy ? null : _pick, multiple: true),
                for (var i = 0; i < _files.length; i++)
                  BirFileChip(
                    name: _files[i].name,
                    onRemove: _busy
                        ? null
                        : () => setState(() => _files.removeAt(i)),
                  ),
                const SizedBox(height: 20),
                BirPrimaryButton(
                  label: 'Continue',
                  busy: _busy,
                  onPressed: _continue,
                ),
              ],
            ),
          ),
          if (_busy)
            Positioned.fill(
              child: Container(
                color: Colors.white.withValues(alpha: 0.92),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 56,
                      height: 56,
                      child: TpLoader(
                        strokeWidth: 4,
                        color: birOrange,
                      ),
                    ),
                    SizedBox(height: 18),
                    Text(
                      'Processing your document...',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: birNavy,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      "This may take a moment. Please don't close this window.",
                      style: TextStyle(color: Color(0xFF888888), fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class BirPtuAdvanceScreen extends StatefulWidget {
  const BirPtuAdvanceScreen({
    super.key,
    required this.service,
    required this.customerId,
  });

  final BirStep2Service service;
  final int customerId;

  static Future<bool?> show(
    BuildContext context, {
    required ApiClient api,
    required int customerId,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BirPtuAdvanceScreen(
        service: BirStep2Service(api),
        customerId: customerId,
      ),
    );
  }

  @override
  State<BirPtuAdvanceScreen> createState() => _BirPtuAdvanceScreenState();
}

class _BirPtuAdvanceScreenState extends State<BirPtuAdvanceScreen> {
  final _ptu = TextEditingController();
  final _min = TextEditingController();
  final _date = TextEditingController();
  bool _busy = false;
  final Set<String> _missing = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await widget.service.advanceForm(widget.customerId);
    if (!mounted || !r.ok) return;
    setState(() {
      _ptu.text = '${r.data['ptu'] ?? ''}';
      _min.text = '${r.data['min'] ?? ''}';
      _date.text = '${r.data['permit_effective_date'] ?? ''}';
    });
  }

  @override
  void dispose() {
    _ptu.dispose();
    _min.dispose();
    _date.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_date.text.trim()) ?? now,
      firstDate: DateTime(1990),
      lastDate: DateTime(now.year + 10),
    );
    if (picked == null) return;
    setState(() {
      _date.text =
          '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    _missing
      ..clear()
      ..addAll([
        if (_ptu.text.trim().isEmpty) 'ptu',
        if (_min.text.trim().isEmpty) 'min',
      ]);
    if (_missing.isNotEmpty) {
      setState(() {});
      return;
    }
    setState(() => _busy = true);
    final prep = await widget.service.advancePayload({
      'customerId': '${widget.customerId}',
      'ptu': _ptu.text,
      'min': _min.text,
      'acc_num': '',
      'permit_effective_date': _date.text,
    });
    if (!mounted) return;
    if (!prep.ok) {
      setState(() => _busy = false);
      birToast(context, prep.message, error: true);
      return;
    }
    final payload = Map<String, dynamic>.from(
      prep.data['payload'] as Map? ?? {},
    ).map((k, v) => MapEntry(k, '${v ?? ''}'));
    final r = await widget.service.advancePtuManual(payload);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      birToast(context, 'Registration completed successfully.');
      Navigator.of(context).pop(true);
      return;
    }
    birToast(
      context,
      r.data.isEmpty
          ? r.message
          : (r.message.isNotEmpty
                ? r.message
                : 'Failed to complete registration.'),
      error: true,
    );
  }

  Widget _label(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Icon(icon, size: 14, color: birOrange),
        const SizedBox(width: 6),
        Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: birNavy,
            fontSize: 12,
            letterSpacing: 0.5,
          ),
        ),
      ],
    ),
  );

  Widget _input(TextEditingController c, String hint, String key) => TextField(
    controller: c,
    onChanged: _missing.contains(key)
        ? (_) => setState(() => _missing.remove(key))
        : null,
    decoration: InputDecoration(
      hintText: hint,
      isDense: true,
      errorText: _missing.contains(key) ? 'Please fill out this field.' : null,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return BirNavyModal(
      title: 'Advanced — Enter PTU Manually',
      icon: Icons.keyboard_outlined,
      subtitle:
          'Type in the permit details to complete the registration without uploading a PDF.',
      width: 520,
      closeEnabled: !_busy,
      onClose: _busy ? null : () => Navigator.of(context).pop(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _label(Icons.badge_outlined, 'PTU No.'),
            _input(_ptu, 'Permit to Use number', 'ptu'),
            const SizedBox(height: 16),
            _label(Icons.memory, 'MIN'),
            _input(_min, 'Machine Identification Number', 'min'),
            const SizedBox(height: 16),
            _label(Icons.event_available_outlined, 'Effective Date of Permit'),
            TextField(
              controller: _date,
              decoration: InputDecoration(
                hintText: 'YYYY-MM-DD',
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                suffixIcon: IconButton(
                  tooltip: 'Pick a date',
                  icon: const Icon(Icons.calendar_today_outlined, size: 16),
                  onPressed: _busy ? null : _pickDate,
                ),
              ),
            ),
            const SizedBox(height: 20),
            BirPrimaryButton(
              label: 'Save & Complete',
              icon: Icons.check_circle_outline,
              busy: _busy,
              busyLabel: 'Saving...',
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
