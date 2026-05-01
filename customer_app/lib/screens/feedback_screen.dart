import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models/customer_models.dart';
import '../theme.dart';

/// Mirrors the web portal's "Share Your Feedback" form. Posts to the same
/// `submitClientFeedback` (or equivalent) endpoint. We accept a couple
/// of likely server action names because backend naming evolved during
/// iteration; whichever returns success ends the flow.
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key, required this.api, required this.customer});
  final ApiClient api;
  final Customer customer;

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  String _category = '';
  int _rating = 0;
  final _messageController = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _submitted = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_category.isEmpty) {
      setState(() => _error = 'Pick a category first.');
      return;
    }
    if (_rating <= 0) {
      setState(() => _error = 'Tap a star to rate your experience.');
      return;
    }
    if (_messageController.text.trim().isEmpty) {
      setState(() => _error = 'Tell us a bit more in the message.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final body = {
      'customer_id': widget.customer.id.toString(),
      'category': _category,
      'rating': _rating.toString(),
      'message': _messageController.text.trim(),
    };
    Map<String, dynamic>? res;
    for (final action in const [
      'submitClientFeedback',
      'submitCustomerFeedback',
      'addClientFeedback',
    ]) {
      try {
        final r = await widget.api.post(action, body: body);
        if (r['success'] == true || r['status'] == 'success') {
          res = r;
          break;
        }
      } catch (_) {}
    }
    if (!mounted) return;
    if (res == null) {
      setState(() {
        _busy = false;
        _error = 'Could not submit feedback. Try again later.';
      });
      return;
    }
    setState(() {
      _busy = false;
      _submitted = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Share Your Feedback'),
        backgroundColor: Brand.canvas,
        scrolledUnderElevation: 0,
        shape: const Border(bottom: BorderSide(color: Brand.stroke)),
      ),
      body: _submitted ? _ThankYou(onClose: () => Navigator.pop(context)) : _form(),
    );
  }

  Widget _form() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Brand.canvas,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Brand.stroke),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      gradient: Brand.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.chat_bubble,
                        color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'How are we doing?',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Help us improve your experience.',
                          style: TextStyle(
                              fontSize: 12.5, color: Brand.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const _Label('Category'),
              DropdownButtonFormField<String>(
                value: _category.isEmpty ? null : _category,
                items: const [
                  DropdownMenuItem(
                      value: 'experience',
                      child: Text('Overall experience')),
                  DropdownMenuItem(
                      value: 'improvement',
                      child: Text('Suggestion / Improvement')),
                  DropdownMenuItem(
                      value: 'bug', child: Text('Bug Report')),
                ],
                onChanged: (v) => setState(() => _category = v ?? ''),
                decoration: const InputDecoration(hintText: '-- Select --'),
              ),
              const SizedBox(height: 16),
              const _Label('Rating'),
              Row(
                children: List.generate(5, (i) {
                  final filled = i < _rating;
                  return IconButton(
                    icon: Icon(
                      filled ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: filled ? Brand.signal : Brand.stroke,
                      size: 32,
                    ),
                    onPressed: () => setState(() => _rating = i + 1),
                  );
                }),
              ),
              const SizedBox(height: 16),
              const _Label('Your message'),
              TextField(
                controller: _messageController,
                minLines: 4,
                maxLines: 8,
                maxLength: 1000,
                decoration: const InputDecoration(
                  hintText: 'Write your feedback here…',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                _Banner.error(_error!),
              ],
              const SizedBox(height: 14),
              ElevatedButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: Colors.white),
                      )
                    : const Text('SUBMIT FEEDBACK'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 11,
          color: Brand.textMuted,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner._(this.text, this.color);
  final String text;
  final Color color;
  factory _Banner.error(String msg) => _Banner._(msg, Brand.danger);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12.5,
        ),
      ),
    );
  }
}

class _ThankYou extends StatelessWidget {
  const _ThankYou({required this.onClose});
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: Brand.primary,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Brand.signalGlow(0.34),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(Icons.check_rounded,
                  color: Colors.white, size: 40),
            ),
            const SizedBox(height: 18),
            const Text(
              'Thank you!',
              style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 22, height: 1.2),
            ),
            const SizedBox(height: 6),
            const Text(
              'Your feedback helps us make TinkerPro better.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Brand.textMuted, fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: onClose, child: const Text('CLOSE')),
          ],
        ),
      ),
    );
  }
}
