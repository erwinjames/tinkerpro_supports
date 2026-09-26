import 'package:flutter/material.dart';

import '../services/bir_data_service.dart';
import '../services/bir_misc_service.dart';
import '../theme.dart';
import 'bir_misc_ui.dart';
import 'bir_widgets.dart';

class BirPrintDialog extends StatefulWidget {
  const BirPrintDialog({
    super.key,
    required this.bir,
    required this.customer,
    this.printOnly = false,
  });

  final BirDataService bir;
  final Map<String, dynamic> customer;
  final bool printOnly;

  static Future<void> show(
    BuildContext context, {
    required BirDataService bir,
    required Map<String, dynamic> customer,
    bool printOnly = false,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) =>
          BirPrintDialog(bir: bir, customer: customer, printOnly: printOnly),
    );
  }

  @override
  State<BirPrintDialog> createState() => _BirPrintDialogState();
}

class _Doc {
  const _Doc(this.title, this.file);
  final String title;
  final BirSavedFile file;
}

class _BirPrintDialogState extends State<BirPrintDialog> {
  late final BirMiscService _svc = BirMiscService(widget.bir.api);
  bool _application = false;
  bool _declaration = false;
  bool _statement = false;
  bool _ptu = false;
  bool _receipt = false;
  bool _busy = false;

  String _s(String k) => (widget.customer[k] ?? '').toString().trim();
  int get _id => int.tryParse(_s('id')) ?? 0;
  bool get _finalDone => _s('final_step') == '1';
  bool get _hasPtu => _s('ptu_file').isNotEmpty;
  List<String> get _ptuFiles => _s(
    'ptu_file',
  ).split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  String? get _docType {
    if (_declaration && _statement) return 'sworn_declaration_and_statement';
    if (_declaration) return 'sworn_declaration';
    if (_statement) return 'sworn_statement';
    return null;
  }

  Future<void> _run({required bool download}) async {
    final selected = <_Doc>[];
    final missing = <String>[];
    final calls = <Future<void>>[];
    var anyChecked = false;

    if (_application) {
      anyChecked = true;
      final f = _s('pdf_file');
      if (f.isNotEmpty) {
        calls.add(
          _svc.fetchPdfUpload(f).then((file) {
            if (file != null) {
              selected.add(_Doc('Application for Registration', file));
            } else {
              missing.add('Application for Registration of Sales Machines');
            }
          }),
        );
      } else {
        missing.add('Application for Registration of Sales Machines');
      }
    }

    if (_ptu && _hasPtu) {
      anyChecked = true;
      final files = _ptuFiles;
      if (files.isNotEmpty) {
        for (var i = 0; i < files.length; i++) {
          final label = 'Permit to Use${files.length > 1 ? ' (${i + 1})' : ''}';
          calls.add(
            _svc.fetchPdfUpload(files[i]).then((file) {
              if (file != null) {
                selected.add(_Doc(label, file));
              } else {
                missing.add(label);
              }
            }),
          );
        }
      } else {
        missing.add('Permit to Use Sales Machines');
      }
    }

    if (_receipt && _finalDone) {
      anyChecked = true;
      calls.add(() async {
        await _svc.prepareAskReceipt(_id);
        final file = await _svc.fetchToFile(
          'print/ask-for-receipt.pdf?t=${DateTime.now().millisecondsSinceEpoch}',
          'ask-for-receipt.pdf',
          temp: true,
        );
        selected.add(_Doc('Ask for Receipt', file));
      }());
    }

    final docType = _docType;
    if (docType != null) {
      anyChecked = true;
      final label = docType == 'sworn_declaration_and_statement'
          ? 'Sworn Declaration & Statement'
          : (docType == 'sworn_declaration'
                ? 'Sworn Declaration'
                : 'Sworn Statement');
      calls.add(() async {
        final path = await _svc.swornPdfPath(_id, docType);
        final name = path.split('/').last.split('?').first;
        final file = await _svc.fetchToFile(
          '$path?t=${DateTime.now().millisecondsSinceEpoch}',
          name.isEmpty ? 'document.pdf' : name,
          temp: true,
        );
        selected.add(_Doc(label, file));
      }());
    }

    if (!anyChecked) {
      birToast(context, 'Please select at least one document.');
      return;
    }

    void reportMissing(BuildContext ctx) {
      if (missing.isEmpty) return;
      final msg = missing.length == 1
          ? 'The file for "${missing.first}" is missing on the server.'
          : 'The following files are missing on the server: ${missing.join(', ')}.';
      birToast(
        ctx,
        msg,
        kind: BirToastKind.error,
        duration: const Duration(seconds: 4),
      );
    }

    if (calls.isEmpty) {
      reportMissing(context);
      return;
    }

    final rootCtx = Navigator.of(context, rootNavigator: true).context;
    setState(() => _busy = true);
    final loader = BirLoading.show(
      context,
      title: 'Preparing Documents...',
      text: 'Please wait while the documents are being prepared.',
    );
    var failed = false;
    try {
      await Future.wait(calls);
    } catch (_) {
      failed = true;
    }
    loader.close();
    if (!rootCtx.mounted) return;
    if (mounted) setState(() => _busy = false);
    if (failed) {
      birToast(
        rootCtx,
        'Failed to prepare one or more documents. Please try again.',
        kind: BirToastKind.error,
      );
      return;
    }
    reportMissing(rootCtx);
    if (selected.isEmpty) return;
    if (mounted) Navigator.of(context).pop();
    if (download) {
      final saved = <String>[];
      for (final d in selected) {
        final out = await _svc.saveBytes(
          await _svc.bytesFromFile(d.file.path),
          d.file.name,
        );
        saved.add(out.path);
      }
      if (rootCtx.mounted) {
        birToast(
          rootCtx,
          saved.length == 1
              ? 'Saved to ${saved.first}'
              : 'Saved ${saved.length} documents to ${saved.first.substring(0, saved.first.lastIndexOf(RegExp(r'[\\/]')))}',
          kind: BirToastKind.success,
        );
      }
    } else {
      for (final d in selected) {
        await _svc.open(d.file.path);
      }
    }
  }

  Future<void> _sendEmail() async {
    final emailCtl = TextEditingController(text: _s('email'));
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => BirDialogShell(
        title: 'Email Confirmation',
        width: 600,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Email',
              style: TextStyle(fontWeight: FontWeight.w600, color: Brand.navy),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: emailCtl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(hintText: 'Email Address'),
            ),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerRight,
              child: BirSolidButton(
                label: 'Send',
                icon: Icons.email,
                color: const Color(0xFF007BFF),
                onPressed: () => Navigator.of(ctx).pop(true),
              ),
            ),
          ],
        ),
      ),
    );
    final receiver = emailCtl.text;
    emailCtl.dispose();
    if (go != true || !mounted) return;

    final rootCtx = Navigator.of(context, rootNavigator: true).context;
    Navigator.of(context).pop();
    if (!rootCtx.mounted) return;
    final loader = BirLoading.show(
      rootCtx,
      title: 'Sending Emails...',
      text: 'Please wait while emails are being sent.',
    );

    final calls = <Future<bool>>[];
    if (_application) {
      final raw = widget.customer['pdf_file'];
      calls.add(
        raw == null
            ? Future.value(false)
            : _svc.postEmail('email/sendApplication.php', {
                'pdfFile': raw.toString(),
                'receiverEmail': receiver,
              }),
      );
    }
    if (_ptu && _hasPtu) {
      calls.add(
        _svc.postEmail('email/sendPTU-pdf.php', {
          'ptuFile': (widget.customer['ptu_file'] ?? '').toString(),
          'receiverEmail': receiver,
        }),
      );
    }
    if (_receipt && _finalDone) {
      calls.add(
        _svc.postEmail('email/sendAskforReceipt.php', {
          'id': '$_id',
          'receiverEmail': receiver,
        }),
      );
    }
    final docType = _docType;
    if (docType != null) {
      calls.add(
        _svc.postEmail('email/sendStatementDeclaration.php', {
          'id': '$_id',
          'docType': docType,
          'receiverEmail': receiver,
        }),
      );
    }
    if (calls.isEmpty) {
      loader.close();
      return;
    }
    final results = await Future.wait(calls);
    loader.close();
    if (!rootCtx.mounted) return;
    if (results.every((e) => e)) {
      await birAlert(
        rootCtx,
        icon: BirAlertIcon.success,
        title: 'Emails Sent!',
        text: 'All selected emails were sent successfully.',
      );
    } else {
      await birAlert(
        rootCtx,
        icon: BirAlertIcon.error,
        title: 'Email Sending Failed!',
        text:
            'There was an error sending one or more emails. Please try again.',
      );
    }
  }

  Widget _check(String label, bool value, ValueChanged<bool> onChanged) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: value,
                activeColor: Brand.signal,
                onChanged: (v) => onChanged(v ?? false),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Brand.navy,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BirDialogShell(
      title: 'Print Application',
      subtitle: 'SELECT DOCUMENTS',
      icon: Icons.print,
      width: 550,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _check(
            'APPLICATION FOR REGISTRATION OF SALES MACHINES',
            _application,
            (v) => setState(() => _application = v),
          ),
          _check(
            'SWORN DECLARATION',
            _declaration,
            (v) => setState(() => _declaration = v),
          ),
          _check(
            'SWORN STATEMENT',
            _statement,
            (v) => setState(() => _statement = v),
          ),
          if (_hasPtu)
            _check(
              'PERMIT TO USE SALES MACHINE',
              _ptu,
              (v) => setState(() => _ptu = v),
            ),
          if (_finalDone)
            _check(
              'ASK FOR RECEIPT',
              _receipt,
              (v) => setState(() => _receipt = v),
            ),
          const SizedBox(height: 18),
          const Divider(height: 1, color: Color(0xFFF0F0F0)),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 10,
            runSpacing: 10,
            children: [
              BirOutlineButton(
                label: 'Send to Email',
                icon: Icons.email_outlined,
                height: 45,
                onPressed: _busy ? null : _sendEmail,
              ),
              if (!widget.printOnly)
                BirSolidButton(
                  label: 'Download',
                  icon: Icons.download,
                  color: Brand.navy,
                  busy: _busy,
                  onPressed: () => _run(download: true),
                ),
              BirSolidButton(
                label: 'Print',
                icon: Icons.print,
                busy: _busy,
                onPressed: () => _run(download: false),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
