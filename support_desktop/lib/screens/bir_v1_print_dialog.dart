import 'package:flutter/material.dart';

import 'bir_v1_ui.dart';
import 'bir_widgets.dart';

class BirV1PrintChoice {
  const BirV1PrintChoice({
    required this.email,
    required this.application,
    required this.ptu,
    required this.askReceipt,
    required this.swornDocType,
    this.receiverEmail = '',
  });

  final bool email;
  final bool application;
  final bool ptu;
  final bool askReceipt;
  final String? swornDocType;
  final String receiverEmail;
}

List<String> birV1PtuFiles(Map<String, dynamic> record) =>
    (record['ptu_file'] ?? '')
        .toString()
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

class BirV1PrintDialog extends StatefulWidget {
  const BirV1PrintDialog({super.key, required this.record});
  final Map<String, dynamic> record;

  @override
  State<BirV1PrintDialog> createState() => _BirV1PrintDialogState();
}

class _BirV1PrintDialogState extends State<BirV1PrintDialog> {
  final _checked = <String, bool>{};

  Map<String, dynamic> get _r => widget.record;
  bool get _completed => '${_r['status']}' == 'completed';

  ({bool available, String hint}) _availability(String doc) {
    switch (doc) {
      case 'application':
        final has = '${_r['pdf_file'] ?? ''}'.isNotEmpty;
        return (
          available: has,
          hint: has ? '' : 'No registration PDF stored on this record.',
        );
      case 'ptu':
        final has = birV1PtuFiles(_r).isNotEmpty;
        return (
          available: has,
          hint: has ? '' : 'No PTU file stored on this record.',
        );
      case 'ask_receipt':
        final ready = _r['bir_card_ready'] == true;
        final missing = _r['bir_card_missing_fields'];
        final list = missing is List ? missing.join(', ') : '';
        return (
          available: ready,
          hint: ready
              ? ''
              : 'Missing: ${list.isEmpty ? 'required fields' : list}',
        );
    }
    return (available: true, hint: '');
  }

  bool _isChecked(String doc) =>
      (_checked[doc] ?? false) && _availability(doc).available;

  String? get _swornDocType {
    final declaration = _isChecked('sworn_declaration');
    final statement = _isChecked('sworn_statement');
    if (declaration && statement) return 'sworn_declaration_and_statement';
    if (declaration) return 'sworn_declaration';
    if (statement) return 'sworn_statement';
    return null;
  }

  bool get _anySelected =>
      _isChecked('application') ||
      _isChecked('ptu') ||
      _isChecked('ask_receipt') ||
      _swornDocType != null;

  BirV1PrintChoice _choice({required bool email, String to = ''}) =>
      BirV1PrintChoice(
        email: email,
        application: _isChecked('application'),
        ptu: _isChecked('ptu'),
        askReceipt: _isChecked('ask_receipt'),
        swornDocType: _swornDocType,
        receiverEmail: to,
      );

  Future<void> _print() async {
    if (!_anySelected) {
      await birV1Toast(
        context,
        'warning',
        'Nothing selected',
        'Tick at least one document to print.',
      );
      return;
    }
    if (mounted) Navigator.of(context).pop(_choice(email: false));
  }

  Future<void> _email() async {
    if (!_anySelected) {
      await birV1Toast(
        context,
        'warning',
        'Nothing selected',
        'Tick at least one document to send.',
      );
      return;
    }
    final to = await birV1EmailPrompt(context, '${_r['email'] ?? ''}');
    if (to == null || to.isEmpty || !mounted) return;
    Navigator.of(context).pop(_choice(email: true, to: to));
  }

  Widget _check(String doc, String label) {
    final a = _availability(doc);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: a.available
                ? () =>
                      setState(() => _checked[doc] = !(_checked[doc] ?? false))
                : null,
            child: Row(
              children: [
                Checkbox(
                  value: a.available && (_checked[doc] ?? false),
                  activeColor: const Color(0xFF007BFF),
                  onChanged: a.available
                      ? (v) => setState(() => _checked[doc] = v ?? false)
                      : null,
                ),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: a.available
                          ? const Color(0xFF212529)
                          : const Color(0xFF94A3B8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (a.hint.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 48),
              child: Text(
                a.hint,
                style: const TextStyle(fontSize: 12, color: Color(0xFFB45309)),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final company = '${_r['company_name'] ?? ''}'.trim();
    return BirV1Shell(
      title: 'Print Application',
      width: 560,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Text(
              company.isEmpty ? 'V1 record #${_r['id']}' : company,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
          _check(
            'application',
            'APPLICATION FOR REGISTRATION OF SALES MACHINES',
          ),
          _check('sworn_declaration', 'SWORN DECLARATION'),
          _check('sworn_statement', 'SWORN STATEMENT'),
          if (_completed) _check('ptu', 'PERMIT TO USE SALES MACHINE'),
          if (_completed) _check('ask_receipt', 'ASK FOR RECEIPT'),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              BirOutlineButton(
                label: 'Send to Email',
                icon: Icons.email_outlined,
                onPressed: _email,
              ),
              const SizedBox(width: 8),
              BirSolidButton(
                label: 'Print',
                icon: Icons.print,
                color: const Color(0xFF007BFF),
                height: 40,
                fontWeight: FontWeight.w600,
                onPressed: _print,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
