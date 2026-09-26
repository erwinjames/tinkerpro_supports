import 'package:flutter/material.dart';

import '../services/services.dart';
import '../theme.dart';
import 'bir_widgets.dart';

class InvoiceLookupDialog extends StatefulWidget {
  const InvoiceLookupDialog({super.key, required this.service});

  final CustomerService service;

  static Future<String?> show(BuildContext context, CustomerService service) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => InvoiceLookupDialog(service: service),
    );
  }

  @override
  State<InvoiceLookupDialog> createState() => _InvoiceLookupDialogState();
}

class _InvoiceLookupDialogState extends State<InvoiceLookupDialog> {
  final _controller = TextEditingController();
  bool _checking = false;
  String _message = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final term = _controller.text.trim();
    if (term.isEmpty || _checking) return;
    setState(() {
      _checking = true;
      _message = '';
    });
    final r = await widget.service.searchInvoice(term);
    if (!mounted) return;
    if (r.ok) {
      Navigator.of(context).pop(r.invoice);
      return;
    }
    setState(() {
      _checking = false;
      _message = r.error == 'not_found'
          ? 'Invoice “$term” was not found on TinkerPro Invoice. '
                'Check the number, or skip if you don’t have one.'
          : (r.error == 'unreachable'
                ? 'Could not reach the invoice service. Please try again.'
                : (r.error ?? 'Invoice not found.'));
    });
  }

  @override
  Widget build(BuildContext context) {
    return BirDialogShell(
      title: 'Find Your Invoice',
      icon: Icons.receipt_long,
      width: 500,
      onClose: () => Navigator.of(context).pop(),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          SizedBox(
            height: 60,
            child: OutlinedButton(
              onPressed: _checking ? null : () => Navigator.of(context).pop(''),
              style: OutlinedButton.styleFrom(
                foregroundColor: Brand.navy,
                side: const BorderSide(color: Color(0xFFD7DDE5)),
                padding: const EdgeInsets.symmetric(horizontal: 30),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fast_forward, size: 22),
                  SizedBox(width: 10),
                  Text('Skip — No Invoice'),
                ],
              ),
            ),
          ),
          const SizedBox(width: 20),
          BirSolidButton(
            label: 'Continue',
            icon: Icons.arrow_forward,
            height: 60,
            fontSize: 17,
            busy: _checking,
            onPressed: _controller.text.trim().isEmpty ? null : _continue,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enter the invoice number tied to your purchase. We\'ll verify it '
            'with TinkerPro Invoice before attaching it to this registration. '
            'Don\'t have one yet? Just skip this step.',
            style: TextStyle(
              fontSize: 15,
              height: 1.6,
              color: Color(0xFF212529),
            ),
          ),
          const SizedBox(height: 18),
          const Row(
            children: [
              Icon(Icons.description, size: 15, color: Brand.navy),
              SizedBox(width: 4),
              Text(
                'Invoice number',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Brand.navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.go,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _continue(),
            decoration: const InputDecoration(
              hintText: 'Type an invoice number, e.g. INV-00123…',
            ),
          ),
          if (_message.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Brand.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Brand.danger.withValues(alpha: 0.3)),
              ),
              child: Text(
                _message,
                style: const TextStyle(fontSize: 13, color: Brand.danger),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
