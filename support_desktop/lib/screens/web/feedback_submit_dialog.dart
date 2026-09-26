import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../api_client.dart';
import '../../theme.dart';
import '../../widgets/premium.dart';
import '../../widgets/tp_loader.dart';

Future<void> showFeedbackSubmitDialog(BuildContext context, ApiClient api) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _FeedbackSubmitDialog(api: api),
  );
}

class _Attachment {
  _Attachment(this.key, this.name, this.path);
  final String key;
  final String name;
  final String path;
  String status = 'uploading';
  int? id;
  String error = '';
}

class _FeedbackSubmitDialog extends StatefulWidget {
  const _FeedbackSubmitDialog({required this.api});
  final ApiClient api;

  @override
  State<_FeedbackSubmitDialog> createState() => _FeedbackSubmitDialogState();
}

class _FeedbackSubmitDialogState extends State<_FeedbackSubmitDialog> {
  static const _categories = [
    ('general', 'General'),
    ('bug', 'Bug report'),
    ('feature', 'Feature request'),
    ('ui', 'Design / UI'),
    ('performance', 'Performance'),
    ('other', 'Other'),
  ];
  static const _hints = ['Optional', 'Very poor', 'Poor', 'Okay', 'Good', 'Excellent'];
  static const _maxFiles = 6;
  static const _maxBytes = 10 * 1024 * 1024;

  final _subject = TextEditingController();
  final _message = TextEditingController();
  String _category = 'general';
  int _rating = 0;
  bool _sending = false;
  bool _done = false;
  int _seq = 0;
  final List<_Attachment> _files = [];
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  int get _busy => _files.where((f) => f.status == 'uploading').length;
  int get _uploaded => _files.where((f) => f.status == 'done').length;

  Future<Map<String, dynamic>> _post(Map<String, String> body) =>
      widget.api.post(body['action']!, body: body);

  Future<void> _close() async {
    if (!_done) {
      _post({'action': 'feedbackDiscardPending'}).catchError((_) => <String, dynamic>{});
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _toast(String text) {
    setState(() => _error = text);
  }

  Future<void> _pick() async {
    final res = await FilePicker.platform
        .pickFiles(type: FileType.image, allowMultiple: true);
    if (res == null) return;
    for (final f in res.files) {
      final path = f.path;
      if (path == null) continue;
      if (_files.length >= _maxFiles) {
        _toast('You can attach up to $_maxFiles images.');
        break;
      }
      final size = f.size;
      if (size > _maxBytes) {
        _toast('"${f.name}" is larger than 10 MB.');
        continue;
      }
      _seq += 1;
      final item = _Attachment('f$_seq', f.name, path);
      setState(() => _files.add(item));
      _upload(item);
    }
  }

  Future<void> _upload(_Attachment item) async {
    try {
      final bytes = await File(item.path).readAsBytes();
      final uri = Uri.parse(
          '${widget.api.baseUrl}/api.php?action=feedbackAttach&name=${Uri.encodeQueryComponent(item.name)}');
      final r = await http.post(uri,
          headers: {
            ...widget.api.authHeaders(),
            'Content-Type': 'application/octet-stream',
            'X-Requested-With': 'XMLHttpRequest',
          },
          body: bytes);
      final res = jsonDecode(r.body);
      if (res is Map && res['success'] == true && res['attachment'] is Map) {
        item.status = 'done';
        item.id = int.tryParse('${(res['attachment'] as Map)['id']}');
      } else {
        item.status = 'error';
        item.error = (res is Map ? res['message']?.toString() : null) ??
            'Upload failed.';
        _toast(item.error);
      }
    } catch (_) {
      item.status = 'error';
      item.error = 'Upload failed.';
      _toast('Could not upload "${item.name}".');
    }
    if (mounted) setState(() {});
  }

  void _remove(_Attachment item) {
    setState(() => _files.remove(item));
    if (item.id != null) {
      _post({'action': 'feedbackDetach', 'id': '${item.id}'})
          .catchError((_) => <String, dynamic>{});
    }
  }

  Future<void> _send() async {
    if (_sending || _busy > 0) return;
    var body = _message.text.trim();
    if (body.isEmpty && _uploaded == 0) {
      _toast('Please write your feedback first.');
      return;
    }
    if (body.isEmpty) body = '(screenshot only)';
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final res = await _post({
        'action': 'submitFeedback',
        'category': _category,
        'rating': '$_rating',
        'subject': _subject.text.trim(),
        'message': body,
        'page_url': 'desktop-app',
      });
      if (!mounted) return;
      if (res['success'] == true) {
        setState(() {
          _sending = false;
          _done = true;
        });
      } else {
        setState(() {
          _sending = false;
          _error = res['message']?.toString() ?? 'Could not send your feedback.';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = 'Network error. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (_done) {
      return WebModal(
        title: 'Send Feedback',
        icon: Icons.chat_bubble_outline,
        width: 560,
        onClose: _close,
        actions: [SignalButton(label: 'Close', onPressed: _close)],
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(children: [
            const IconTile(icon: Icons.check, size: 56, color: Brand.success),
            const SizedBox(height: 14),
            Text('Thanks for the feedback', style: text.titleLarge),
            const SizedBox(height: 6),
            Text('The super admin team has been notified. We read every message.',
                textAlign: TextAlign.center, style: text.bodySmall),
          ]),
        ),
      );
    }
    final busy = _busy > 0;
    return WebModal(
      title: 'Send Feedback',
      subtitle:
          'Tell us what is working, what is broken, or what you wish this app could do.',
      icon: Icons.chat_bubble_outline,
      width: 600,
      onClose: _close,
      actions: [
        Expanded(
          child: Text('Sent to the TinkerPro Support Team.',
              style: text.bodySmall),
        ),
        GhostButton(label: 'Cancel', onPressed: _close),
        SignalButton(
          label: busy ? 'Uploading…' : (_sending ? 'Sending…' : 'Send feedback'),
          icon: Icons.send,
          busy: _sending || busy,
          onPressed: _send,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What is this about?',
              style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in _categories)
              ChoiceChip(
                label: Text(c.$2),
                selected: _category == c.$1,
                selectedColor: Brand.signalGlow(0.16),
                labelStyle: TextStyle(
                    color: _category == c.$1 ? Brand.signal : null,
                    fontWeight: FontWeight.w600),
                onSelected: (_) => setState(() => _category = c.$1),
              ),
          ]),
          const SizedBox(height: 18),
          Text('How would you rate the experience?',
              style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Row(children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                tooltip: _hints[i],
                onPressed: () => setState(() => _rating = _rating == i ? 0 : i),
                icon: Icon(Icons.star,
                    color: i <= _rating
                        ? const Color(0xFFF59E0B)
                        : context.brand.rule),
              ),
            const SizedBox(width: 8),
            Text(_hints[_rating], style: text.bodySmall),
          ]),
          const SizedBox(height: 14),
          TextField(
            controller: _subject,
            maxLength: 120,
            decoration: const InputDecoration(
              labelText: 'Subject',
              hintText: 'Short summary (optional)',
              counterText: '',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _message,
            autofocus: true,
            maxLength: 5000,
            minLines: 5,
            maxLines: 10,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Your feedback',
              hintText: 'Describe it in as much detail as you like…',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 6),
          Row(children: [
            GhostButton(
                label: 'Attach images',
                icon: Icons.attach_file,
                onPressed: _files.length >= _maxFiles ? null : _pick),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Pick up to $_maxFiles images (10 MB each)',
                  style: text.bodySmall),
            ),
          ]),
          if (_files.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final f in _files)
                Stack(clipBehavior: Clip.none, children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: f.status == 'error'
                              ? Brand.danger
                              : context.brand.rule),
                      image: DecorationImage(
                          image: FileImage(File(f.path)), fit: BoxFit.cover),
                    ),
                    child: f.status == 'uploading'
                        ? Container(
                            color: Colors.white.withValues(alpha: 0.6),
                            alignment: Alignment.center,
                            child: const SizedBox(
                                width: 18,
                                height: 18,
                                child: TpLoader(strokeWidth: 2)),
                          )
                        : null,
                  ),
                  Positioned(
                    top: -8,
                    right: -8,
                    child: IconButton.filledTonal(
                      iconSize: 14,
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Remove',
                      onPressed: () => _remove(f),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ]),
            ]),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: text.bodySmall?.copyWith(
                    color: Brand.danger, fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }
}
