import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/bir_v1_service.dart';
import 'bir_v1_ui.dart';
import 'bir_widgets.dart';

class BirV1Step3Result {
  const BirV1Step3Result({required this.ptu});
  final String ptu;
}

class BirV1Step3Dialog extends StatefulWidget {
  const BirV1Step3Dialog({super.key, required this.svc, required this.record});
  final BirV1Service svc;
  final Map<String, dynamic> record;

  @override
  State<BirV1Step3Dialog> createState() => _BirV1Step3DialogState();
}

class _BirV1Step3DialogState extends State<BirV1Step3Dialog> {
  List<PlatformFile> _files = const [];
  String _noticeKind = '';
  String _notice = '';
  bool _busy = false;
  String _busyLabel = '';

  int get _id => int.tryParse('${widget.record['id']}') ?? 0;

  void _setNotice(String kind, String msg) => setState(() {
    _noticeKind = kind;
    _notice = msg;
  });

  void _fail(String msg) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _noticeKind = 'error';
      _notice = msg;
    });
  }

  Future<void> _pick() async {
    if (_busy) return;
    FilePickerResult? res;
    try {
      res = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
    } catch (_) {
      res = null;
    }
    if (res == null || !mounted) return;
    final pdfs = res.files
        .where(
          (f) =>
              f.path != null &&
              RegExp(r'\.pdf$', caseSensitive: false).hasMatch(f.name),
        )
        .toList();
    if (pdfs.isEmpty) {
      _setNotice('warn', 'Only PDF files can be extracted.');
      return;
    }
    setState(() {
      _files = pdfs;
      _noticeKind = '';
      _notice = '';
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_files.isEmpty) {
      _setNotice('warn', 'Choose at least one Permit to Use PDF.');
      return;
    }
    setState(() {
      _noticeKind = '';
      _notice = '';
      _busy = true;
      _busyLabel = 'Reading PDF…';
    });
    Map<String, String> values;
    try {
      final extract = await widget.svc.step3Extract([
        for (final f in _files) f.path!,
      ]);
      values = await widget.svc.step3Check(_id, extract);
    } on BirV1Exception catch (e) {
      _fail(e.message);
      return;
    }
    if (!mounted) return;
    setState(() => _busyLabel = 'Completing…');
    try {
      await widget.svc.step3Update(_id, values);
    } on BirV1Exception catch (e) {
      _fail(e.message);
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.of(context).pop(BirV1Step3Result(ptu: values['ptu'] ?? ''));
  }

  @override
  Widget build(BuildContext context) {
    final company = '${widget.record['company_name'] ?? ''}'.trim();
    final serial = '${widget.record['serial_number'] ?? ''}'.trim();
    final noticeColors = switch (_noticeKind) {
      'error' => (
        const Color(0xFFFEF2F2),
        const Color(0xFFB91C1C),
        const Color(0xFFFECACA),
      ),
      'warn' => (
        const Color(0xFFFFFBEB),
        const Color(0xFF92400E),
        const Color(0xFFFDE68A),
      ),
      _ => (
        const Color(0xFFEFF6FF),
        const Color(0xFF1E40AF),
        const Color(0xFFBFDBFE),
      ),
    };
    return BirV1Shell(
      title: 'Step 3 — Upload Permit to Use',
      width: 620,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'STEP 3',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Upload the Permit to use Sales Machine Pdf',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  company.isEmpty
                      ? 'V1 record #${widget.record['id']}'
                      : company,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 8),
                birV1Label('Registered Serial Number(s)'),
                SelectableText(
                  serial.isEmpty ? '—' : serial,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13.5,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: _busy ? null : _pick,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 26),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFAF5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFDBA74), width: 2),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.picture_as_pdf,
                    size: 40,
                    color: Color(0xFFDC2626),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'DRAG & DROP',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'OR',
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: birV1Orange,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'UPLOAD',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_files.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final f in _files)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    const Icon(
                      Icons.picture_as_pdf,
                      size: 16,
                      color: Color(0xFFDC2626),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(f.name, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
          ],
          if (_notice.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: noticeColors.$1,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: noticeColors.$3),
              ),
              child: SelectableText(
                _notice,
                style: TextStyle(fontSize: 13.5, color: noticeColors.$2),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              BirOutlineButton(
                label: 'Cancel',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 180),
                child: BirSolidButton(
                  label: _busy ? _busyLabel : 'Continue',
                  icon: _busy ? null : Icons.arrow_forward,
                  busy: _busy,
                  color: const Color(0xFF007BFF),
                  height: 40,
                  fontWeight: FontWeight.w600,
                  onPressed: _submit,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
