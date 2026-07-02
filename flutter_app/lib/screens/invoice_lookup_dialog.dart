import 'package:flutter/material.dart';

import '../services/services.dart';
import '../theme.dart';
import '../widgets/premium.dart';

/// "Find Your Invoice" step shown before creating a new client — mirrors the
/// web registration. Returns via [Navigator.pop]:
///   * a non-empty String → the verified invoice number to attach
///   * ''  → the user skipped (no invoice)
///   * null → the user cancelled (dismissed) — creation should not proceed
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
    final text = Theme.of(context).textTheme;
    return Dialog(
      backgroundColor: context.brand.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: context.brand.rule, width: 1),
        borderRadius: BorderRadius.zero,
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long_outlined,
                    size: 18, color: Brand.signal),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Find your invoice',
                      style: text.headlineMedium),
                ),
                InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  child: Icon(Icons.close, size: 18, color: context.brand.paperDim),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Hairline(),
            const SizedBox(height: 16),
            Text(
              'Enter the invoice number tied to this purchase. We’ll verify it '
              'with TinkerPro Invoice before attaching it. No invoice yet? '
              'Just skip this step.',
              style: text.bodySmall,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _continue(),
              style: text.titleMedium,
              decoration: const InputDecoration(
                labelText: 'INVOICE NUMBER',
                hintText: 'e.g. INV-00123',
              ),
            ),
            if (_message.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(_message,
                  style: text.bodySmall?.copyWith(color: Brand.signal)),
            ],
            const SizedBox(height: 24),
            SignalButton(
              label: 'Continue',
              busy: _checking,
              icon: Icons.arrow_forward,
              onPressed: _checking ? null : _continue,
            ),
            const SizedBox(height: 12),
            GhostButton(
              label: 'Skip — no invoice',
              onPressed: () => Navigator.of(context).pop(''),
            ),
          ],
        ),
      ),
    );
  }
}
