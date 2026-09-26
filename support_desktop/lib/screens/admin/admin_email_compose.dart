import 'dart:async';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/admin_services.dart';
import '../../theme.dart';
import '../../widgets/admin_table_page.dart';
import '../../widgets/premium.dart';
import 'admin_list.dart';
import '../../widgets/tp_loader.dart';

const _kMaxAttach = 25 * 1024 * 1024;
const _kConcurrent = 8;
const _kAttachExt = [
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'bmp',
  'svg',
  'pdf',
  'doc',
  'docx',
  'txt',
];
final _emailRe = RegExp(r'^[^\s@,;<>]+@[^\s@,;<>]+\.[^\s@,;<>]+$');

class EmailAttachment {
  EmailAttachment(this.name, this.path, this.size);
  final String name;
  final String path;
  final int size;
}

Future<List<EmailAttachment>> pickEmailAttachments() async {
  final res = await FilePicker.platform.pickFiles(
    allowMultiple: true,
    type: FileType.custom,
    allowedExtensions: _kAttachExt,
  );
  if (res == null) return const [];
  return [
    for (final f in res.files)
      if (f.path != null) EmailAttachment(f.name, f.path!, f.size),
  ];
}

String _fmtSize(int size) => size > 1024 * 1024
    ? '${(size / 1024 / 1024).toStringAsFixed(1)} MB'
    : '${(size / 1024).toStringAsFixed(0)} KB';

class EmailSendProgress extends ChangeNotifier {
  EmailSendProgress({required this.single});
  final bool single;
  final DateTime started = DateTime.now();
  String label = 'Sending...';
  String text = '';
  IconData icon = Icons.sync;
  Color tone = Brand.signal;
  int total = 0;
  int sent = 0;
  int failed = 0;
  bool done = false;
  bool cancelRequested = false;
  bool keepComposeOpen = false;
  String estimate = '';
  Duration? finalElapsed;
  final failures = <({String email, String reason})>[];

  void set(String t, {IconData? icon, Color? tone}) {
    text = t;
    if (icon != null) this.icon = icon;
    if (tone != null) this.tone = tone;
    notifyListeners();
  }

  void record(bool ok, String email, String? reason, {bool cancelled = false}) {
    if (ok) {
      sent++;
    } else if (!cancelled) {
      failed++;
      failures.add((email: email, reason: reason ?? 'Unknown error'));
    }
    final processed = sent + failed;
    text = 'Sending emails... $processed of $total';
    icon = Icons.send;
    if (processed > 0) {
      final ms = DateTime.now().difference(started).inMilliseconds;
      final remaining = (total - processed) * (ms / processed) / 1000;
      estimate = 'Est: ${remaining.toStringAsFixed(0)}s remaining';
    }
    notifyListeners();
  }

  void finish(
    String t, {
    required IconData icon,
    required Color tone,
    required bool keepOpen,
    String? label,
    String? estimate,
  }) {
    done = true;
    finalElapsed = DateTime.now().difference(started);
    text = t;
    this.icon = icon;
    this.tone = tone;
    keepComposeOpen = keepOpen;
    if (label != null) this.label = label;
    if (estimate != null) this.estimate = estimate;
    notifyListeners();
  }

  String get durationText =>
      ((finalElapsed ?? DateTime.now().difference(started)).inMilliseconds /
              1000)
          .toStringAsFixed(1);
}

Future<void> runEmailBatches<T>(
  List<T> items,
  Future<void> Function(T) send,
  EmailSendProgress p, {
  int start = 0,
}) async {
  for (var i = start; i < items.length; i += _kConcurrent) {
    if (p.cancelRequested) break;
    final chunk = items.sublist(i, math.min(i + _kConcurrent, items.length));
    await Future.wait(chunk.map(send));
    if (i + _kConcurrent < items.length && !p.cancelRequested) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }
}

Future<bool> showEmailProgress(
  BuildContext context,
  EmailSendProgress p,
  Future<void> Function() job,
) async {
  unawaited(job());
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ProgressDialog(p: p),
  );
  return p.keepComposeOpen;
}

class _ProgressDialog extends StatefulWidget {
  const _ProgressDialog({required this.p});
  final EmailSendProgress p;

  @override
  State<_ProgressDialog> createState() => _ProgressDialogState();
}

class _ProgressDialogState extends State<_ProgressDialog> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    widget.p.addListener(_changed);
    _tick = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted && !widget.p.done) setState(() {});
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tick?.cancel();
    widget.p.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final processed = p.sent + p.failed;
    final pct = p.total == 0 ? 0.0 : processed / p.total;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(height: 4, color: Brand.signal),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 12),
              child: Row(
                children: [
                  const Icon(Icons.send, color: Brand.signal, size: 18),
                  const SizedBox(width: 10),
                  Text(
                    p.single ? p.label : 'Sending Emails',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Brand.navy,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Container(
              color: const Color(0xFFF7F7F5),
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!p.single) ...[
                    Row(
                      children: [
                        const Text(
                          'Progress',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF888888),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${(pct * 100).round()}%',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF888888),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 10,
                        backgroundColor: const Color(0xFFE8E8E4),
                        color: p.done ? p.tone : Brand.signal,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      p.done
                          ? Icon(p.icon, size: 18, color: p.tone)
                          : const SizedBox(
                              width: 16,
                              height: 16,
                              child: TpLoader(strokeWidth: 2),
                            ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          p.text,
                          style: const TextStyle(fontSize: 14, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                  if (p.failures.isNotEmpty && p.done) ...[
                    const SizedBox(height: 14),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFF3CD),
                        border: Border(
                          left: BorderSide(color: Color(0xFFFFC107), width: 4),
                        ),
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.single ? 'Failed:' : 'Failed Emails:',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF850804),
                              ),
                            ),
                            const SizedBox(height: 6),
                            for (final f in p.failures)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 2,
                                ),
                                child: SelectableText(
                                  '• ${f.email}: ${f.reason}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF3A3838),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (!p.single) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _stat('Sent', '${p.sent}', Brand.success),
                        _stat('Failed', '${p.failed}', Brand.danger),
                        _stat('Total', '${p.total}', Brand.navy),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          'Time: ${p.durationText}s',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF888888),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          p.estimate,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF888888),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: p.done
                  ? SignalButton(
                      label: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                    )
                  : (p.single
                        ? const SizedBox.shrink()
                        : DangerButton(
                            label: p.cancelRequested
                                ? 'Cancelling...'
                                : 'Cancel Sending',
                            onPressed: p.cancelRequested
                                ? null
                                : () => setState(() => p.cancelRequested = true),
                          )),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value, Color color) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 11.5, color: Color(0xFF888888)),
        ),
      ],
    ),
  );
}

class EmailTemplatePicker extends StatefulWidget {
  const EmailTemplatePicker({
    super.key,
    required this.service,
    required this.message,
    required this.onPick,
  });
  final EmailService service;
  final TextEditingController message;
  final void Function(Map<String, dynamic> template) onPick;

  @override
  State<EmailTemplatePicker> createState() => _EmailTemplatePickerState();
}

class _EmailTemplatePickerState extends State<EmailTemplatePicker> {
  List<Map<String, dynamic>> _templates = const [];
  bool _open = false;

  @override
  void initState() {
    super.initState();
    widget.message.addListener(_changed);
    widget.service.templates().then((t) {
      if (mounted) setState(() => _templates = t);
    }, onError: (_) {});
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.message.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.message.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.layers_outlined, size: 15, color: Brand.signal),
                const SizedBox(width: 6),
                const Text(
                  'Templates',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(width: 4),
                Icon(
                  _open ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
        if (_open)
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _templates.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final t = _templates[i];
                final html = (t['html'] ?? '').toString();
                final selected = html.isNotEmpty && html == current;
                return InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => widget.onPick(t),
                  child: Container(
                    width: 130,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: selected
                          ? Brand.signal.withValues(alpha: 0.08)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected ? Brand.signal : AdminTableColors.border,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        (t['title'] ?? '').toString(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _AttachList extends StatelessWidget {
  const _AttachList({required this.files, required this.onRemove});
  final List<EmailAttachment> files;
  final void Function(int) onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < files.length; i++)
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Brand.info.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                const Icon(Icons.attach_file, size: 15),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${files[i].name} (${_fmtSize(files[i].size)})',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  tooltip: 'Remove',
                  icon: const Icon(Icons.close),
                  onPressed: () => onRemove(i),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

enum ComposeMode { all, single, selected }

Future<bool> showSubscriberCompose(
  BuildContext context, {
  required EmailService service,
  required ComposeMode mode,
  String? email,
  List<String> selected = const [],
}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (_) => _SubscriberCompose(
      service: service,
      mode: mode,
      email: email,
      selected: selected,
    ),
  );
  return res == true;
}

class _SubscriberCompose extends StatefulWidget {
  const _SubscriberCompose({
    required this.service,
    required this.mode,
    required this.email,
    required this.selected,
  });
  final EmailService service;
  final ComposeMode mode;
  final String? email;
  final List<String> selected;

  @override
  State<_SubscriberCompose> createState() => _SubscriberComposeState();
}

class _SubscriberComposeState extends State<_SubscriberCompose> {
  final _subject = TextEditingController();
  final _message = TextEditingController();
  final _files = <EmailAttachment>[];
  bool _sending = false;

  EmailService get service => widget.service;

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  String get _title => switch (widget.mode) {
    ComposeMode.all => 'Compose Email to All Subscribers',
    ComposeMode.single => 'Send email to ${widget.email}',
    ComposeMode.selected =>
      'Send email to ${widget.selected.length} selected recipient(s)',
  };

  String get _button => switch (widget.mode) {
    ComposeMode.all => 'Send to All',
    ComposeMode.single => 'Send to ${widget.email}',
    ComposeMode.selected => 'Send to ${widget.selected.length} Selected',
  };

  void _clear() {
    _subject.clear();
    _message.clear();
    setState(_files.clear);
  }

  Future<void> _send() async {
    if (_sending) return;
    final totalSize = _files.fold<int>(0, (s, f) => s + f.size);
    if (totalSize > _kMaxAttach) {
      await _alert('Total file size exceeds 25MB limit! Please select smaller files.');
      return;
    }
    setState(() => _sending = true);
    final subject = _subject.text;
    final paths = [for (final f in _files) f.path];
    final attachCount = _files.length;
    final ctx = context;
    bool keepOpen;
    if (widget.mode == ComposeMode.single) {
      final to = widget.email ?? '';
      final p = EmailSendProgress(single: true)
        ..set('Sending email to $to...');
      keepOpen = await showEmailProgress(ctx, p, () async {
        try {
          final message = (await service.messageHtml(_message.text)).trim();
          final r = await service.sendSingle(
            email: to,
            subject: subject,
            message: message,
            attachmentPaths: paths,
          );
          if (r['success'] == true) {
            unawaited(
              service
                  .saveRecentTemplate(html: message, subject: subject)
                  .catchError((_) {}),
            );
            if (mounted) _clear();
            p.finish(
              'Successfully sent to $to',
              icon: Icons.check_circle,
              tone: Brand.success,
              keepOpen: false,
              label: 'Email Sent!',
            );
          } else {
            p.finish(
              (r['message'] ?? 'Unknown error').toString(),
              icon: Icons.warning_amber_rounded,
              tone: Brand.danger,
              keepOpen: true,
              label: 'Email Failed!',
            );
          }
        } catch (e) {
          p.finish(
            'Failed to send to $to: $e',
            icon: Icons.warning_amber_rounded,
            tone: Brand.danger,
            keepOpen: true,
          );
        }
      });
    } else {
      final p = EmailSendProgress(single: false)..set('Preparing to send...');
      keepOpen = await showEmailProgress(ctx, p, () async {
        try {
          final message = (await service.messageHtml(_message.text)).trim();
          final emails = widget.mode == ComposeMode.all
              ? await service.allSubscriberEmails()
              : List<String>.from(widget.selected);
          p.total = emails.length;
          if (emails.isEmpty) {
            p.finish(
              'No recipients matched — nothing was sent.',
              icon: Icons.info_outline,
              tone: Brand.warning,
              keepOpen: true,
              estimate: '',
            );
            return;
          }
          Future<void> sendOne(String email) async {
            if (p.cancelRequested) return;
            try {
              final r = await service.sendSingle(
                email: email,
                subject: subject,
                message: message,
                skipLogging: true,
                attachmentPaths: paths,
              );
              p.record(
                r['success'] == true,
                email,
                (r['message'] ?? 'Unknown error').toString(),
                cancelled: r['cancelled'] == true,
              );
            } catch (e) {
              p.record(false, email, '$e');
            }
          }

          await runEmailBatches(emails, sendOne, p);
          if (p.cancelRequested) {
            p.finish(
              'Cancelled by user',
              icon: Icons.block,
              tone: Brand.danger,
              keepOpen: false,
              estimate: 'Cancelled',
            );
            return;
          }
          final duration = p.durationText;
          if (p.failed == 0) {
            if (widget.mode == ComposeMode.all) {
              unawaited(
                service
                    .logAllEmailSend(
                      emails: emails,
                      subject: subject,
                      attachmentCount: attachCount,
                    )
                    .catchError((_) {}),
              );
            } else {
              unawaited(
                service
                    .logBulkSend(
                      emails: emails,
                      subject: subject,
                      attachmentCount: attachCount,
                    )
                    .catchError((_) {}),
              );
            }
            if (mounted) _clear();
            p.finish(
              'All done! Completed in ${duration}s',
              icon: Icons.check_circle,
              tone: Brand.success,
              keepOpen: false,
              estimate: 'Completed in ${duration}s',
            );
          } else {
            p.finish(
              '${p.failed} failed to send',
              icon: Icons.error_outline,
              tone: Brand.warning,
              keepOpen: true,
              estimate: 'Completed in ${duration}s',
            );
          }
          if (widget.mode == ComposeMode.all && p.sent > 0) {
            unawaited(
              service
                  .saveRecentTemplate(html: message, subject: subject)
                  .catchError((_) {}),
            );
          }
        } catch (e) {
          p.finish(
            '$e',
            icon: Icons.warning_amber_rounded,
            tone: Brand.danger,
            keepOpen: true,
          );
        }
      });
    }
    if (!mounted) return;
    setState(() => _sending = false);
    if (!keepOpen) Navigator.of(context).pop(true);
  }

  Future<void> _alert(String msg) => showWebModal<void>(
    context,
    title: 'Attachments',
    icon: Icons.warning_amber_rounded,
    width: 420,
    builder: (_) => Text(msg),
    actions: (c) => [
      SignalButton(label: 'OK', onPressed: () => Navigator.pop(c)),
    ],
  );

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 6, top: 4),
    child: Text(
      t,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 760,
          maxHeight: MediaQuery.of(context).size.height * 0.92,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              color: Brand.navy,
              child: Row(
                children: [
                  const Icon(Icons.send, color: Colors.white, size: 18),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'EMAIL COMPOSER',
                          style: TextStyle(
                            fontSize: 10.5,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w700,
                            color: Colors.white60,
                          ),
                        ),
                        Text(
                          _title,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _label('Subject'),
                    TextField(
                      controller: _subject,
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Enter email subject…',
                      ),
                    ),
                    const SizedBox(height: 10),
                    EmailTemplatePicker(
                      service: service,
                      message: _message,
                      onPick: (t) => _message.text = t['is_blank'] == true
                          ? ''
                          : (t['html'] ?? '').toString(),
                    ),
                    const SizedBox(height: 6),
                    _label('Message'),
                    TextField(
                      controller: _message,
                      minLines: 10,
                      maxLines: 18,
                      decoration: const InputDecoration(
                        hintText: 'Write your message…',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _label('Attach File / Image'),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () async {
                        final picked = await pickEmailAttachments();
                        if (picked.isNotEmpty) {
                          setState(() => _files.addAll(picked));
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AdminTableColors.border),
                        ),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.cloud_upload_outlined,
                              color: Brand.signal,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _files.isEmpty
                                  ? 'Click or drag files here to upload'
                                  : '${_files.length} file(s) selected',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                    _AttachList(
                      files: _files,
                      onRemove: (i) => setState(() => _files.removeAt(i)),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  GhostButton(
                    label: 'Close',
                    icon: Icons.close,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: SignalButton(
                      label: _button,
                      icon: Icons.send,
                      busy: _sending,
                      onPressed: _sending ? null : _send,
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

class GmChip {
  GmChip({
    required this.kind,
    required this.value,
    required this.label,
    this.sub,
    this.count,
    this.isNew = false,
    this.invalid = false,
  });
  final String kind;
  final String value;
  final String label;
  final String? sub;
  final int? count;
  final bool isNew;
  final bool invalid;

  String get key => '$kind|${value.toLowerCase()}';
}

class GmComposerState {
  final recipients = <String, List<GmChip>>{'to': [], 'cc': [], 'bcc': []};
  bool showCc = false;
  bool showBcc = false;
  final subject = TextEditingController();
  final message = TextEditingController();
  final files = <EmailAttachment>[];
  final suggestCache = <String, Map<String, dynamic>>{};

  static const fields = ['to', 'cc', 'bcc'];

  bool hasChip(String field, GmChip c) =>
      recipients[field]!.any((e) => e.key == c.key);

  String? addChip(String field, GmChip c) {
    for (final other in fields) {
      if (other != field && hasChip(other, c)) {
        return '${c.label} is already in ${other.toUpperCase()}.';
      }
    }
    if (hasChip(field, c)) return '';
    recipients[field]!.add(c);
    return null;
  }

  int get total => fields.fold(
    0,
    (sum, f) =>
        sum +
        recipients[f]!.fold<int>(
          0,
          (n, c) => n + (c.kind == 'group' ? (c.count ?? 0) : 1),
        ),
  );

  bool get hasContent =>
      fields.any((f) => recipients[f]!.isNotEmpty) ||
      subject.text.trim().isNotEmpty ||
      message.text.trim().isNotEmpty ||
      files.isNotEmpty;

  void clear() {
    for (final f in fields) {
      recipients[f]!.clear();
    }
    showCc = false;
    showBcc = false;
    subject.clear();
    message.clear();
    files.clear();
  }

  void removeEmail(String email) {
    for (final f in fields) {
      recipients[f]!.removeWhere(
        (c) => c.kind == 'email' && c.value.toLowerCase() == email.toLowerCase(),
      );
    }
  }
}

class InternalComposer extends StatefulWidget {
  const InternalComposer({
    super.key,
    required this.service,
    required this.state,
    required this.onManage,
    required this.onRecipientsChanged,
  });
  final EmailService service;
  final GmComposerState state;
  final VoidCallback onManage;
  final VoidCallback onRecipientsChanged;

  @override
  State<InternalComposer> createState() => _InternalComposerState();
}

class _InternalComposerState extends State<InternalComposer> {
  GmComposerState get s => widget.state;
  EmailService get service => widget.service;
  final _inputs = {
    for (final f in GmComposerState.fields) f: TextEditingController(),
  };
  final _focus = {for (final f in GmComposerState.fields) f: FocusNode()};
  String? _suggestField;
  List<GmChip> _options = const [];
  int _hidden = 0;
  int _active = -1;
  int _seq = 0;
  Timer? _debounce;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    for (final f in GmComposerState.fields) {
      _focus[f]!.addListener(() => _onFocus(f));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in _inputs.values) {
      c.dispose();
    }
    for (final n in _focus.values) {
      n.dispose();
    }
    super.dispose();
  }

  void _toast(String m) => toast(context, m);

  void _onFocus(String field) {
    if (_focus[field]!.hasFocus) {
      _queueSuggest(field, _inputs[field]!.text.trim());
    } else {
      Future<void>.delayed(const Duration(milliseconds: 180), () {
        if (!mounted) return;
        if (_suggestField == field) _hideSuggest();
        _commitTyped(field);
      });
    }
  }

  void _hideSuggest() => setState(() {
    _suggestField = null;
    _options = const [];
    _active = -1;
  });

  void _queueSuggest(String field, String term) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 140),
      () => _fetchSuggest(field, term),
    );
  }

  Future<void> _fetchSuggest(String field, String term) async {
    final key = term.toLowerCase();
    final seq = ++_seq;
    void paint(Map<String, dynamic> res) {
      if (seq != _seq || !mounted) return;
      final taken = {
        for (final f in GmComposerState.fields)
          for (final c in s.recipients[f]!) c.key,
      };
      final groups = (res['groups'] is List ? res['groups'] as List : const [])
          .whereType<Map>()
          .map(
            (g) => GmChip(
              kind: 'group',
              value: '${g['id']}',
              label: '${g['label'] ?? ''}',
              sub: '${g['hint'] ?? ''}',
              count: int.tryParse('${g['count'] ?? 0}') ?? 0,
            ),
          );
      final peopleRaw = res['people'] is List
          ? res['people'] as List
          : const [];
      final people = peopleRaw.whereType<Map>().map((p) {
        final email = '${p['email'] ?? ''}';
        final name = '${p['name'] ?? ''}';
        return _PersonChip(
          kind: 'email',
          value: email,
          label: name.isEmpty ? email : name,
          sub: email,
          source: '${p['source'] ?? ''}',
          tag: '${p['tag'] ?? ''}',
        );
      });
      final options = [
        ...groups,
        ...people,
      ].where((o) => !taken.contains(o.key)).toList();
      setState(() {
        _suggestField = field;
        _options = options;
        _active = options.isEmpty ? -1 : 0;
        _hidden =
            (int.tryParse('${res['peopleTotal'] ?? 0}') ?? 0) -
            peopleRaw.length;
      });
    }

    final cached = s.suggestCache[key];
    if (cached != null) {
      paint(cached);
      return;
    }
    try {
      final res = await service.suggestions(term);
      if (res['success'] != true) return;
      s.suggestCache[key] = res;
      paint(res);
    } catch (_) {}
  }

  void _addChip(String field, GmChip c) {
    final r = s.addChip(field, c);
    if (r != null && r.isNotEmpty) _toast(r);
    setState(() {});
    widget.onRecipientsChanged();
  }

  void _commitTyped(String field) {
    final ctrl = _inputs[field]!;
    final raw = ctrl.text.trim().replaceAllMapped(
      RegExp(r'[^,;]*<([^>]+)>'),
      (m) => ' ${m[1]} ',
    );
    if (raw.trim().isEmpty) return;
    for (final token in raw.split(RegExp(r'[,;\s]+'))) {
      final address = token.trim();
      if (address.isEmpty) continue;
      final valid = _emailRe.hasMatch(address);
      if (!valid) _toast('"$address" doesn\'t look like an email address.');
      _addChip(
        field,
        GmChip(
          kind: 'email',
          value: address,
          label: address,
          isNew: true,
          invalid: !valid,
        ),
      );
    }
    ctrl.clear();
  }

  void _pick(int index) {
    final field = _suggestField;
    if (field == null || index < 0 || index >= _options.length) return;
    final o = _options[index];
    _addChip(
      field,
      o.kind == 'group'
          ? GmChip(kind: 'group', value: o.value, label: o.label, count: o.count)
          : GmChip(kind: 'email', value: o.value, label: o.label, sub: o.sub),
    );
    _inputs[field]!.clear();
    _focus[field]!.requestFocus();
    _hideSuggest();
  }

  KeyEventResult _onKey(String field, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final hasPick =
        _suggestField == field && _active >= 0 && _options.isNotEmpty;
    if (k == LogicalKeyboardKey.arrowDown && _options.isNotEmpty) {
      setState(() => _active = (_active + 1) % _options.length);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp && _options.isNotEmpty) {
      setState(
        () => _active = (_active - 1 + _options.length) % _options.length,
      );
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      _hideSuggest();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter ||
        k == LogicalKeyboardKey.tab) {
      if (hasPick) {
        _pick(_active);
        return KeyEventResult.handled;
      }
      if (_inputs[field]!.text.trim().isNotEmpty) {
        _commitTyped(field);
        _hideSuggest();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (k == LogicalKeyboardKey.backspace &&
        _inputs[field]!.text.isEmpty &&
        s.recipients[field]!.isNotEmpty) {
      setState(() => s.recipients[field]!.removeLast());
      widget.onRecipientsChanged();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _chip(String field, int i) {
    final c = s.recipients[field]![i];
    final bg = c.invalid
        ? Brand.danger.withValues(alpha: 0.12)
        : c.kind == 'group'
        ? Brand.info.withValues(alpha: 0.12)
        : c.isNew
        ? Brand.success.withValues(alpha: 0.12)
        : const Color(0xFFEEF2F7);
    return Tooltip(
      message: c.kind == 'group'
          ? c.label
          : (c.sub != null && c.sub!.isNotEmpty
                ? '${c.label} <${c.value}>'
                : c.value),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 3, 2, 3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(99),
          border: c.invalid ? Border.all(color: Brand.danger) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (c.kind == 'group') ...[
              const Icon(Icons.groups, size: 14),
              const SizedBox(width: 4),
            ],
            Text(c.label, style: const TextStyle(fontSize: 12.5)),
            if (c.kind == 'group' && c.count != null) ...[
              const SizedBox(width: 6),
              Text(
                '${c.count}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            InkWell(
              onTap: () {
                setState(() => s.recipients[field]!.removeAt(i));
                widget.onRecipientsChanged();
              },
              child: const Padding(
                padding: EdgeInsets.all(3),
                child: Icon(Icons.close, size: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _suggestMenu() {
    if (_options.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          'No match — press Enter to use what you typed as an address.',
          style: TextStyle(fontSize: 12.5, color: AdminTableColors.muted),
        ),
      );
    }
    final rows = <Widget>[];
    String? lastKind;
    for (var i = 0; i < _options.length; i++) {
      final o = _options[i];
      if (o.kind != lastKind) {
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Text(
              o.kind == 'group' ? 'GROUPS' : 'PEOPLE',
              style: const TextStyle(
                fontSize: 10.5,
                letterSpacing: 1,
                fontWeight: FontWeight.w700,
                color: AdminTableColors.muted,
              ),
            ),
          ),
        );
        lastKind = o.kind;
      }
      final meta = o.kind == 'group'
          ? '${o.count}'
          : (o is _PersonChip && o.source == 'staff'
                ? o.tag.replaceAll('_', ' ')
                : 'Added');
      rows.add(
        InkWell(
          onTap: () => _pick(i),
          child: Container(
            color: i == _active ? const Color(0xFFF1F7FE) : null,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: o.kind == 'group'
                      ? Brand.info.withValues(alpha: 0.15)
                      : Brand.signal.withValues(alpha: 0.15),
                  child: o.kind == 'group'
                      ? const Icon(Icons.groups, size: 15)
                      : Text(
                          _initials(o.label),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        o.label,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if ((o.sub ?? '').isNotEmpty)
                        Text(
                          o.sub!,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AdminTableColors.muted,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  meta,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AdminTableColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_hidden > 0) {
      rows.add(
        Padding(
          padding: const EdgeInsets.all(10),
          child: Text(
            '$_hidden more — keep typing to narrow it down',
            style: const TextStyle(
              fontSize: 12,
              color: AdminTableColors.muted,
            ),
          ),
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 260),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        ),
      ),
    );
  }

  String _initials(String text) {
    final parts = text.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  Widget _row(String field, String label, String hint, {Widget? trailing}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AdminTableColors.cellRule)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AdminTableColors.muted,
                  ),
                ),
              ),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (var i = 0; i < s.recipients[field]!.length; i++)
                      _chip(field, i),
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: 200,
                        maxWidth: 420,
                      ),
                      child: Focus(
                        onKeyEvent: (_, e) => _onKey(field, e),
                        child: TextField(
                          controller: _inputs[field],
                          focusNode: _focus[field],
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: InputDecoration(
                            hintText: hint,
                            isDense: true,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                          ),
                          onChanged: (v) {
                            if (RegExp(r'[,;]').hasMatch(v)) {
                              _commitTyped(field);
                              _hideSuggest();
                              return;
                            }
                            _queueSuggest(field, v.trim());
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
        if (_suggestField == field)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AdminTableColors.border),
              boxShadow: const [
                BoxShadow(color: Color(0x14000000), blurRadius: 12),
              ],
            ),
            child: _suggestMenu(),
          ),
      ],
    );
  }

  void _toggle(bool cc) {
    final showing = cc ? s.showCc : s.showBcc;
    if (showing && s.recipients[cc ? 'cc' : 'bcc']!.isNotEmpty) {
      _toast('Remove the recipients first to hide this field.');
      return;
    }
    setState(() {
      if (cc) {
        s.showCc = !showing;
      } else {
        s.showBcc = !showing;
      }
    });
    if (!showing) _focus[cc ? 'cc' : 'bcc']!.requestFocus();
  }

  Future<void> _discard() async {
    if (!s.hasContent) return;
    final ok = await _confirm(
      title: 'Discard this draft?',
      text: 'The recipients, subject and message will be cleared.',
      confirm: 'Discard',
      cancel: 'Keep editing',
    );
    if (ok) {
      setState(s.clear);
      widget.onRecipientsChanged();
    }
  }

  Future<bool> _confirm({
    required String title,
    required String text,
    required String confirm,
    required String cancel,
  }) async {
    final r = await showWebModal<bool>(
      context,
      title: title,
      icon: Icons.help_outline,
      width: 440,
      builder: (_) => Text(text),
      actions: (c) => [
        GhostButton(label: cancel, onPressed: () => Navigator.pop(c, false)),
        SignalButton(label: confirm, onPressed: () => Navigator.pop(c, true)),
      ],
    );
    return r == true;
  }

  Future<({List<String> to, List<String> cc, List<String> bcc})>
  _resolve() async {
    final resolved = <String, List<String>>{'to': [], 'cc': [], 'bcc': []};
    final groupCache = <String, List<String>>{};
    for (final f in GmComposerState.fields) {
      for (final c in s.recipients[f]!) {
        if (c.kind == 'email') {
          resolved[f]!.add(c.value);
          continue;
        }
        groupCache[c.value] ??= await service.groupEmails(c.value);
        resolved[f]!.addAll(groupCache[c.value]!);
      }
    }
    final seen = <String>{};
    for (final f in GmComposerState.fields) {
      resolved[f] = resolved[f]!.where((e) {
        final k = e.trim().toLowerCase();
        if (k.isEmpty || seen.contains(k)) return false;
        seen.add(k);
        return true;
      }).toList();
    }
    return (to: resolved['to']!, cc: resolved['cc']!, bcc: resolved['bcc']!);
  }

  Future<void> _send() async {
    for (final f in GmComposerState.fields) {
      _commitTyped(f);
    }
    _hideSuggest();
    if (_sending) return;
    final invalid = [
      for (final f in GmComposerState.fields)
        ...s.recipients[f]!.where((c) => c.invalid),
    ];
    if (invalid.isNotEmpty) {
      _toast('Fix or remove: ${invalid.map((c) => c.label).join(', ')}');
      return;
    }
    final chips = GmComposerState.fields.fold<int>(
      0,
      (n, f) => n + s.recipients[f]!.length,
    );
    if (chips == 0) {
      _toast('Add at least one recipient.');
      _focus['to']!.requestFocus();
      return;
    }
    final subject = s.subject.text.trim();
    if (subject.isEmpty) {
      final go = await _confirm(
        title: 'Send without a subject?',
        text: 'This email has no subject line.',
        confirm: 'Send anyway',
        cancel: 'Add a subject',
      );
      if (!go) return;
    }
    final totalSize = s.files.fold<int>(0, (n, f) => n + f.size);
    if (totalSize > _kMaxAttach) {
      _toast('Attachments total more than 25MB. Please remove some files.');
      return;
    }
    final typedByHand = [
      for (final f in GmComposerState.fields)
        for (final c in s.recipients[f]!)
          if (c.kind == 'email' && c.isNew) c.value,
    ];
    final paths = [for (final f in s.files) f.path];
    final attachCount = s.files.length;
    final rawMessage = s.message.text;
    setState(() => _sending = true);
    final p = EmailSendProgress(single: false)
      ..set('Working out who this goes to…');
    if (!mounted) return;
    await showEmailProgress(context, p, () async {
      late final ({List<String> to, List<String> cc, List<String> bcc}) r;
      try {
        r = await _resolve();
      } catch (_) {
        p.finish(
          'Could not work out the recipients. Please try again.',
          icon: Icons.warning_amber_rounded,
          tone: Brand.danger,
          keepOpen: true,
        );
        return;
      }
      final everyone = [...r.to, ...r.cc, ...r.bcc];
      if (everyone.isEmpty) {
        p.finish(
          'No addresses matched — nothing was sent.',
          icon: Icons.info_outline,
          tone: Brand.warning,
          keepOpen: true,
        );
        return;
      }
      final messages = r.to.isNotEmpty
          ? [
              for (var i = 0; i < r.to.length; i++)
                (
                  to: r.to[i],
                  cc: i == 0 ? r.cc : const <String>[],
                  bcc: i == 0 ? r.bcc : const <String>[],
                ),
            ]
          : [(to: '', cc: r.cc, bcc: r.bcc)];
      p.total = messages.length;
      final message = (await service.messageHtml(rawMessage)).trim();
      Future<void> sendOne(
        ({String to, List<String> cc, List<String> bcc}) item,
      ) async {
        if (p.cancelRequested) return;
        final label = item.to.isNotEmpty
            ? item.to
            : (item.cc.isNotEmpty ? item.cc.first : item.bcc.first);
        try {
          final res = await service.sendSingle(
            email: item.to,
            subject: subject,
            message: message,
            skipLogging: true,
            cc: item.cc,
            bcc: item.bcc,
            attachmentPaths: paths,
          );
          p.record(
            res['success'] == true,
            label,
            (res['message'] ?? 'Unknown error').toString(),
            cancelled: res['cancelled'] == true,
          );
        } catch (e) {
          p.record(false, label, '$e');
        }
      }

      await sendOne(messages.first);
      await runEmailBatches(messages, sendOne, p, start: 1);
      final duration = p.durationText;
      if (p.cancelRequested) {
        p.finish(
          'Cancelled by user',
          icon: Icons.block,
          tone: Brand.danger,
          keepOpen: true,
          estimate: 'Cancelled',
        );
        return;
      }
      if (p.failed == 0) {
        p.finish(
          'All done! Completed in ${duration}s',
          icon: Icons.check_circle,
          tone: Brand.success,
          keepOpen: false,
          estimate: 'Completed in ${duration}s',
        );
        if (mounted) {
          setState(s.clear);
          widget.onRecipientsChanged();
        }
      } else {
        p.finish(
          '${p.failed} failed to send',
          icon: Icons.error_outline,
          tone: Brand.warning,
          keepOpen: true,
          estimate: 'Completed in ${duration}s',
        );
      }
      if (p.sent > 0) {
        unawaited(
          service
              .logBulkSend(
                emails: everyone,
                subject: subject,
                attachmentCount: attachCount,
              )
              .catchError((_) {}),
        );
        unawaited(
          service
              .saveRecentTemplate(html: message, subject: subject)
              .catchError((_) {}),
        );
      }
      final bounced = {for (final f in p.failures) f.email.toLowerCase()};
      final keepers = typedByHand
          .where((e) => !bounced.contains(e.toLowerCase()))
          .toList();
      if (keepers.isNotEmpty) {
        try {
          final res = await service.rememberContacts(keepers);
          final added = res['added'] is List ? res['added'] as List : const [];
          if (res['success'] == true && added.isNotEmpty && mounted) {
            _toast(
              added.length == 1
                  ? '${added.first} was saved to your added emails.'
                  : '${added.length} new addresses were saved to your added emails.',
            );
            s.suggestCache.clear();
            widget.onRecipientsChanged();
          }
        } catch (_) {}
      }
    });
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final total = s.total;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminTableColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.edit_note, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'New Message',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: widget.onManage,
                  icon: const Icon(
                    Icons.contacts_outlined,
                    size: 16,
                    color: Colors.white,
                  ),
                  label: const Text(
                    'Manage recipients',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          _row(
            'to',
            'To',
            'Type a name, an email, or “all”…',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () => _toggle(true),
                  child: Text(
                    'Cc',
                    style: TextStyle(
                      fontWeight: s.showCc ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => _toggle(false),
                  child: Text(
                    'Bcc',
                    style: TextStyle(
                      fontWeight: s.showBcc
                          ? FontWeight.w800
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (s.showCc) _row('cc', 'Cc', 'Carbon copy…'),
          if (s.showBcc) _row('bcc', 'Bcc', 'Blind copy…'),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AdminTableColors.cellRule),
              ),
            ),
            child: TextField(
              controller: s.subject,
              decoration: const InputDecoration(
                hintText: 'Subject',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: s.message,
                expands: true,
                maxLines: null,
                minLines: null,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  hintText: 'Write your message…',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                ),
              ),
            ),
          ),
          if (s.files.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _AttachList(
                files: s.files,
                onRemove: (i) => setState(() => s.files.removeAt(i)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                SignalButton(
                  label: total > 0 ? 'Send · $total' : 'Send',
                  icon: Icons.send,
                  busy: _sending,
                  onPressed: _sending ? null : _send,
                ),
                const SizedBox(width: 10),
                IconButton(
                  tooltip: 'Attach files',
                  icon: const Icon(Icons.attach_file),
                  onPressed: () async {
                    final picked = await pickEmailAttachments();
                    if (picked.isNotEmpty) {
                      setState(() => s.files.addAll(picked));
                    }
                  },
                ),
                _TemplateDropdown(
                  service: service,
                  onPick: (t) => setState(
                    () => s.message.text = t['is_blank'] == true
                        ? ''
                        : (t['html'] ?? '').toString(),
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Discard draft',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _discard,
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'Everyone in To gets their own copy — they never see each other\'s address. Cc and Bcc are copied once. An address you type by hand is saved to your added emails once it sends, so it\'s there next time.',
              style: TextStyle(fontSize: 12, color: AdminTableColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonChip extends GmChip {
  _PersonChip({
    required super.kind,
    required super.value,
    required super.label,
    super.sub,
    required this.source,
    required this.tag,
  });
  final String source;
  final String tag;
}

class _TemplateDropdown extends StatefulWidget {
  const _TemplateDropdown({required this.service, required this.onPick});
  final EmailService service;
  final void Function(Map<String, dynamic>) onPick;

  @override
  State<_TemplateDropdown> createState() => _TemplateDropdownState();
}

class _TemplateDropdownState extends State<_TemplateDropdown> {
  List<Map<String, dynamic>> _templates = const [];

  @override
  void initState() {
    super.initState();
    widget.service.templates().then((t) {
      if (mounted) setState(() => _templates = t);
    }, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: 'Insert a template',
      onSelected: (i) => widget.onPick(_templates[i]),
      itemBuilder: (_) => [
        for (var i = 0; i < _templates.length; i++)
          PopupMenuItem(value: i, child: Text('${_templates[i]['title']}')),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AdminTableColors.border),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Template…', style: TextStyle(fontSize: 13)),
            Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }
}

Future<bool> showContactModal(
  BuildContext context, {
  required EmailService service,
  Map<String, dynamic>? contact,
  List<String> labels = const [],
}) async {
  final editing = contact != null && '${contact['id'] ?? ''}'.isNotEmpty;
  String v(String k) => (contact?[k] ?? '').toString();
  final email = TextEditingController(text: v('email'));
  final name = TextEditingController(text: v('name'));
  final company = TextEditingController(
    text: v('company').isNotEmpty ? v('company') : v('subtitle'),
  );
  final label = TextEditingController(
    text: v('label').isNotEmpty ? v('label') : v('tag'),
  );
  final notes = TextEditingController(text: v('notes'));
  var busy = false;

  Future<void> save(BuildContext ctx, StateSetter setLocal) async {
    if (busy) return;
    if (email.text.trim().isEmpty) {
      toast(ctx, 'An email address is required.');
      return;
    }
    setLocal(() => busy = true);
    try {
      final r = await service.saveContact(
        id: editing ? v('id') : '',
        name: name.text,
        email: email.text.trim(),
        company: company.text,
        label: label.text,
        notes: notes.text,
      );
      if (!ctx.mounted) return;
      if (r.ok) {
        toast(ctx, r.message.isNotEmpty ? r.message : 'Email saved.');
        Navigator.pop(ctx, true);
      } else {
        toast(ctx, r.message.isNotEmpty ? r.message : 'Could not save email.');
      }
    } catch (_) {
      if (ctx.mounted) toast(ctx, 'Could not save email.');
    } finally {
      if (ctx.mounted) setLocal(() => busy = false);
    }
  }

  Widget field(String l, TextEditingController c, String hint,
          {bool req = false, int lines = 1, String? help}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                text: l,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AdminTableColors.headerText,
                ),
                children: [
                  if (req)
                    const TextSpan(
                      text: ' *',
                      style: TextStyle(color: Brand.danger),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: c,
              minLines: lines,
              maxLines: lines,
              decoration: InputDecoration(hintText: hint),
            ),
            if (help != null) ...[
              const SizedBox(height: 4),
              Text(
                help,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AdminTableColors.muted,
                ),
              ),
            ],
          ],
        ),
      );

  final r = await showWebModal<bool>(
    context,
    title: editing ? 'Edit Email' : 'Add Email',
    subtitle: 'Internal Email',
    icon: Icons.mail_outline,
    width: 560,
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        field('Email', email, 'name@example.com', req: true),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: field('Name', name, 'Full name')),
            const SizedBox(width: 12),
            Expanded(child: field('Company', company, 'Business name')),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Label',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AdminTableColors.headerText,
                ),
              ),
              const SizedBox(height: 6),
              RawAutocomplete<String>(
                textEditingController: label,
                focusNode: FocusNode(),
                optionsBuilder: (t) => labels.where(
                  (l) => l.toLowerCase().contains(t.text.toLowerCase()),
                ),
                fieldViewBuilder: (c, ctrl, fn, _) => TextField(
                  controller: ctrl,
                  focusNode: fn,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Vendors, Partners, Resellers',
                  ),
                ),
                optionsViewBuilder: (c, onSel, opts) => Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxHeight: 200,
                        maxWidth: 480,
                      ),
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final o in opts)
                            ListTile(
                              dense: true,
                              title: Text(o),
                              onTap: () => onSel(o),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Labels group these emails so you can blast just one set.',
                style: TextStyle(fontSize: 11.5, color: AdminTableColors.muted),
              ),
            ],
          ),
        ),
        field('Notes', notes, 'Optional', lines: 2),
      ],
    ),
    actions: (ctx) => [
      GhostButton(
        label: 'Cancel',
        icon: Icons.close,
        onPressed: () => Navigator.pop(ctx, false),
      ),
      StatefulBuilder(
        builder: (bctx, setLocal) => SignalButton(
          label: editing ? 'Save Changes' : 'Save Email',
          icon: Icons.save_outlined,
          busy: busy,
          onPressed: busy ? null : () => save(ctx, setLocal),
        ),
      ),
    ],
  );
  return r == true;
}
