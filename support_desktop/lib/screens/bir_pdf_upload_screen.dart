import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api_client.dart';
import '../services/bir_step2_service.dart';
import 'bir_step2_form_screen.dart';
import 'bir_step2_widgets.dart';

class BirPdfUploadScreen extends StatefulWidget {
  const BirPdfUploadScreen({
    super.key,
    required this.service,
    required this.customerId,
  });

  final BirStep2Service service;
  final String customerId;

  static Future<bool?> show(
    BuildContext context, {
    required ApiClient api,
    int? customerId,
    String invoiceNumber = '',
    bool pendingRegistration = false,
    int originalStep2 = 0,
  }) async {
    final service = BirStep2Service(api);
    final cid = (customerId ?? 0) > 0 ? '$customerId' : '';
    final prefill = await showDialog<BirStep2Result>(
      context: context,
      barrierDismissible: true,
      builder: (_) => BirPdfUploadScreen(service: service, customerId: cid),
    );
    if (prefill == null || !context.mounted) return null;
    final vat = await BirPdfReviewDialog.show(context, prefill: prefill);
    if (vat == null || !context.mounted) return null;
    final form = Map<String, dynamic>.from(prefill.data['form'] as Map? ?? {});
    final entries = (prefill.data['serial_entries'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => BirSerialEntry.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final data = BirStep2FormData(
      fields: {
        'customer_id': cid,
        'invoice_number': cid.isEmpty ? invoiceNumber : '',
        for (final e in form.entries) e.key: '${e.value ?? ''}',
        'is_vat': vat,
      },
      serialEntries: entries,
      isPendingRegistration: pendingRegistration && cid.isNotEmpty,
      originalStep2: originalStep2,
    );
    return BirStep2FormScreen.open(context, api: api, data: data);
  }

  @override
  State<BirPdfUploadScreen> createState() => _BirPdfUploadScreenState();
}

class _BirPdfUploadScreenState extends State<BirPdfUploadScreen> {
  String? _path;
  String? _name;
  bool _busy = false;

  Future<void> _pick() async {
    if (_busy) return;
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
    } catch (_) {
      if (mounted) {
        birToast(context, 'Could not open the file picker.', error: true);
      }
      return;
    }
    final f = result?.files.singleOrNull;
    if (f?.path == null) return;
    setState(() {
      _path = f!.path;
      _name = f.name.length > 50 ? '${f.name.substring(0, 48)}...' : f.name;
    });
  }

  Future<void> _continue() async {
    if (_busy) return;
    if (_path == null) {
      birToast(context, 'Please select a PDF file.', error: true);
      return;
    }
    setState(() => _busy = true);
    final extraction = await widget.service.extractRegistrationPdf(_path!);
    if (!mounted) return;
    if (extraction.isEmpty || extraction['error'] != null) {
      setState(() => _busy = false);
      birToast(
        context,
        (extraction['error'] ?? '').toString().isNotEmpty
            ? extraction['error'].toString()
            : 'Failed to process PDF file. Please try again.',
        error: true,
      );
      return;
    }
    final prefill = await widget.service.registrationPrefill(
      customerId: widget.customerId,
      extraction: extraction,
    );
    if (!mounted) return;
    if (!prefill.ok) {
      setState(() => _busy = false);
      birToast(
        context,
        prefill.title.isEmpty
            ? prefill.message
            : '${prefill.title}: ${prefill.message}',
        error: true,
      );
      return;
    }
    Navigator.of(context).pop(prefill);
  }

  @override
  Widget build(BuildContext context) {
    return BirNavyModal(
      title: 'Upload BIR Registration',
      icon: Icons.picture_as_pdf,
      width: 520,
      closeEnabled: !_busy,
      onClose: _busy ? null : () => Navigator.of(context).pop(),
      subtitleWidget: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Upload the BIR Application of Registration (.PDF) from ',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          InkWell(
            onTap: () => launchUrl(
              Uri.parse('https://eaccreg.bir.gov.ph'),
              mode: LaunchMode.externalApplication,
            ),
            child: const Text(
              'eaccreg.bir.gov.ph',
              style: TextStyle(
                color: birOrange,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            BirPdfDropZone(onTap: _busy ? null : _pick),
            if (_name != null)
              BirFileChip(
                name: _name!,
                onRemove: _busy
                    ? null
                    : () => setState(() {
                        _path = null;
                        _name = null;
                      }),
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
    );
  }
}

class BirPdfReviewDialog extends StatefulWidget {
  const BirPdfReviewDialog({super.key, required this.prefill});

  final BirStep2Result prefill;

  static Future<String?> show(
    BuildContext context, {
    required BirStep2Result prefill,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (_) => BirPdfReviewDialog(prefill: prefill),
    );
  }

  @override
  State<BirPdfReviewDialog> createState() => _BirPdfReviewDialogState();
}

class _BirPdfReviewDialogState extends State<BirPdfReviewDialog> {
  String? _vat;
  bool _vatError = false;

  @override
  void initState() {
    super.initState();
    final v = '${widget.prefill.data['vat'] ?? ''}';
    _vat = v == '0' || v == '1' ? v : null;
  }

  Map<String, dynamic> get _r =>
      Map<String, dynamic>.from(widget.prefill.data['review'] as Map? ?? {});

  Widget _item(String label, IconData icon, String key) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8ECF1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: birOrange),
              const SizedBox(width: 6),
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            '${_r[key] ?? ''}',
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: birNavy,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pair(Widget a, Widget b) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: a),
        const SizedBox(width: 12),
        Expanded(child: b),
      ],
    ),
  );

  void _confirm() {
    if (_vat == null) {
      setState(() => _vatError = true);
      return;
    }
    Navigator.of(context).pop(_vat);
  }

  @override
  Widget build(BuildContext context) {
    return BirNavyModal(
      kicker: 'Extraction Checkpoint',
      title: 'Review Extracted Data',
      icon: Icons.fact_check_outlined,
      subtitle:
          'Scan the captured details, confirm the VAT setup, and continue once everything matches the uploaded BIR registration.',
      width: 760,
      footer: Container(
        padding: const EdgeInsets.fromLTRB(28, 14, 28, 18),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            ElevatedButton.icon(
              onPressed: _confirm,
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: const Text('Confirm & Save'),
              style: ElevatedButton.styleFrom(
                backgroundColor: birOrange,
                foregroundColor: Colors.white,
                minimumSize: const Size(210, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _item('Company Name', Icons.business, 'companyname'),
            const SizedBox(height: 12),
            _pair(
              _item('TIN', Icons.tag, 'tin'),
              _item('RDO', Icons.place_outlined, 'rdo'),
            ),
            const SizedBox(height: 12),
            _item('Business Address', Icons.location_on_outlined, 'address'),
            const SizedBox(height: 12),
            _pair(
              _item(
                'Accreditation No.',
                Icons.workspace_premium_outlined,
                'acc_number',
              ),
              _item(
                'Software Name',
                Icons.desktop_windows_outlined,
                'softwarename',
              ),
            ),
            const SizedBox(height: 12),
            _pair(
              _item('Serial Number', Icons.qr_code_2, 'sn'),
              _item('Owner Name', Icons.person_outline, 'owner_name'),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFAF3),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: birOrange.withValues(alpha: 0.18)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'VAT Registration',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: birNavy,
                            fontSize: 14.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Pick the registration type before saving the extracted record into the client form.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        if (_vatError)
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  size: 14,
                                  color: Colors.red,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'VAT selection is required.',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<String>(
                      initialValue: _vat,
                      isExpanded: true,
                      hint: const Text('Choose status'),
                      items: const [
                        DropdownMenuItem(
                          value: '1',
                          child: Text('VAT Registered'),
                        ),
                        DropdownMenuItem(
                          value: '0',
                          child: Text('Non-VAT Registered'),
                        ),
                      ],
                      onChanged: (v) => setState(() {
                        _vat = v;
                        _vatError = false;
                      }),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
