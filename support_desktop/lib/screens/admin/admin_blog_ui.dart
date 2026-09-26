import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/admin_blog_service.dart';
import '../../theme.dart';
import '../../widgets/premium.dart';

enum BlogToastKind { success, error, info, warning }

final List<OverlayEntry> _toastEntries = [];

void blogToast(
  BuildContext context,
  String message, {
  BlogToastKind kind = BlogToastKind.success,
  String? title,
  Duration duration = const Duration(seconds: 5),
}) {
  if (message.isEmpty) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  final color = switch (kind) {
    BlogToastKind.success => const Color(0xFF51A351),
    BlogToastKind.error => const Color(0xFFBD362F),
    BlogToastKind.info => const Color(0xFF2F96B4),
    BlogToastKind.warning => const Color(0xFFF89406),
  };
  final icon = switch (kind) {
    BlogToastKind.success => Icons.check_circle,
    BlogToastKind.error => Icons.error,
    BlogToastKind.info => Icons.info,
    BlogToastKind.warning => Icons.warning_amber_rounded,
  };
  late OverlayEntry entry;
  void remove() {
    if (!_toastEntries.contains(entry)) return;
    _toastEntries.remove(entry);
    entry.remove();
    for (final e in _toastEntries) {
      e.markNeedsBuild();
    }
  }

  entry = OverlayEntry(
    builder: (ctx) {
      final index = _toastEntries.indexOf(entry);
      return Positioned(
        top: 16.0 + (index < 0 ? 0 : index) * 76,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: remove,
            child: Container(
              width: 320,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
                boxShadow: const [
                  BoxShadow(color: Color(0x55000000), blurRadius: 12),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (title != null)
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        Text(
                          message,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
  _toastEntries.add(entry);
  overlay.insert(entry);
  if (duration > Duration.zero) Timer(duration, remove);
}

void blogToastClear() {
  for (final e in List.of(_toastEntries)) {
    e.remove();
  }
  _toastEntries.clear();
}

Future<bool> blogUndoWindow(
  BuildContext context,
  String message, {
  Duration delay = const Duration(seconds: 5),
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  final done = Completer<bool>();
  late OverlayEntry entry;
  final seconds = ValueNotifier<int>(delay.inSeconds);
  Timer? ticker;
  void finish(bool commit) {
    if (done.isCompleted) return;
    ticker?.cancel();
    entry.remove();
    done.complete(commit);
  }

  ticker = Timer.periodic(const Duration(seconds: 1), (t) {
    seconds.value = seconds.value - 1;
    if (seconds.value <= 0) finish(true);
  });
  entry = OverlayEntry(
    builder: (ctx) => Positioned(
      left: 0,
      right: 0,
      bottom: 24,
      child: Center(
        child: Material(
          color: const Color(0xFF1F2937),
          borderRadius: BorderRadius.circular(8),
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(message, style: const TextStyle(color: Colors.white)),
                const SizedBox(width: 16),
                ValueListenableBuilder<int>(
                  valueListenable: seconds,
                  builder: (_, s, _) => TextButton(
                    onPressed: () => finish(false),
                    child: Text(
                      'Undo ${s > 0 ? s : ''}',
                      style: const TextStyle(
                        color: Brand.signal,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  return done.future;
}

Future<bool> blogConfirm(
  BuildContext context, {
  required String title,
  required Widget body,
  required String confirmLabel,
  IconData icon = Icons.warning_amber_rounded,
  bool danger = true,
  String cancelLabel = 'Cancel',
}) async {
  final ok = await showWebModal<bool>(
    context,
    title: title,
    icon: icon,
    width: 480,
    builder: (_) => body,
    actions: (ctx) => [
      GhostButton(
        label: cancelLabel,
        onPressed: () => Navigator.pop(ctx, false),
      ),
      danger
          ? DangerButton(
              label: confirmLabel,
              icon: Icons.delete_outline,
              onPressed: () => Navigator.pop(ctx, true),
            )
          : SignalButton(
              label: confirmLabel,
              onPressed: () => Navigator.pop(ctx, true),
            ),
    ],
  );
  return ok ?? false;
}

Widget blogCenterText(List<String> lines, {String? small}) => Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    const Icon(Icons.delete_outline, size: 44, color: Brand.danger),
    const SizedBox(height: 12),
    for (final l in lines)
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          l,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16),
        ),
      ),
    if (small != null)
      Text(
        small,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
      ),
  ],
);

String _p2(int n) => n.toString().padLeft(2, '0');

String blogLocalInput(DateTime d) =>
    '${d.year}-${_p2(d.month)}-${_p2(d.day)}T${_p2(d.hour)}:${_p2(d.minute)}';

String blogLocaleDate(DateTime d) => '${d.month}/${d.day}/${d.year}';

String blogLocaleTime(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '${_p2(h)}:${_p2(d.minute)} ${d.hour < 12 ? 'AM' : 'PM'}';
}

DateTime? blogParse(String s) {
  if (s.trim().isEmpty) return null;
  return DateTime.tryParse(s.trim().replaceFirst(' ', 'T'));
}

class BlogDateTimeField extends StatelessWidget {
  const BlogDateTimeField({
    super.key,
    required this.value,
    required this.onChanged,
    this.min,
  });
  final DateTime? value;
  final DateTime? min;
  final ValueChanged<DateTime?> onChanged;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final first = min ?? now;
    final init = value ?? now;
    final d = await showDatePicker(
      context: context,
      initialDate: init.isBefore(first) ? first : init,
      firstDate: DateTime(first.year, first.month, first.day),
      lastDate: DateTime(now.year + 10),
    );
    if (d == null || !context.mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(init),
    );
    if (t == null) return;
    onChanged(DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  @override
  Widget build(BuildContext context) {
    final v = value;
    return InkWell(
      onTap: () => _pick(context),
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: const InputDecoration(
          suffixIcon: Icon(Icons.calendar_month_outlined),
        ),
        child: Text(
          v == null
              ? 'mm/dd/yyyy --:-- --'
              : '${_p2(v.month)}/${_p2(v.day)}/${v.year} ${blogLocaleTime(v)}',
          style: const TextStyle(fontSize: 15),
        ),
      ),
    );
  }
}

Future<DateTime?> blogScheduleModal(BuildContext context) {
  final now = DateTime.now();
  var value = DateTime(
    now.year,
    now.month,
    now.day,
    now.hour,
    now.minute,
  ).add(const Duration(hours: 1));
  if (value.day != now.day) {
    value = DateTime(now.year, now.month, now.day, value.hour, value.minute);
  }
  return showDialog<DateTime>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => WebModal(
        title: 'Schedule Post',
        icon: Icons.calendar_month_outlined,
        width: 500,
        actions: [
          GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx)),
          SignalButton(
            label: 'Schedule',
            icon: Icons.check,
            onPressed: () {
              if (!value.isAfter(DateTime.now())) {
                blogToast(
                  ctx,
                  'Scheduled time must be in the future',
                  kind: BlogToastKind.error,
                );
                return;
              }
              Navigator.pop(ctx, value);
            },
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.access_time, size: 16),
                SizedBox(width: 6),
                Text(
                  'Select Date & Time',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            BlogDateTimeField(
              value: value,
              min: now,
              onChanged: (v) {
                if (v != null) setS(() => value = v);
              },
            ),
            const SizedBox(height: 6),
            const Text(
              'Post will be automatically published at this time',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<bool?> blogEmailModal(
  BuildContext context,
  AdminBlogService service, {
  required bool scheduled,
}) async {
  int? count;
  try {
    count = await service.subscriberCount();
  } catch (_) {
    if (context.mounted) {
      blogToast(
        context,
        'Failed to load subscriber count',
        kind: BlogToastKind.error,
      );
    }
    return null;
  }
  if (count == null || !context.mounted) return null;
  return showWebModal<bool>(
    context,
    title: 'Send Email Notification?',
    icon: Icons.email_outlined,
    width: 500,
    builder: (_) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.groups, size: 48, color: Brand.info),
        const SizedBox(height: 12),
        const Text('Send this post to all subscribers?'),
        const SizedBox(height: 6),
        Text('$count subscribers will receive an email notification.'),
        if (scheduled) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFCFF4FC),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Row(
              children: [
                Icon(Icons.access_time, size: 16, color: Color(0xFF055160)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Email will be sent automatically when the post is published.',
                    style: TextStyle(color: Color(0xFF055160)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    ),
    actions: (ctx) => [
      GhostButton(
        label: 'No, Skip',
        icon: Icons.close,
        onPressed: () => Navigator.pop(ctx, false),
      ),
      SignalButton(
        label: 'Yes, Send Email',
        icon: Icons.send,
        onPressed: () => Navigator.pop(ctx, true),
      ),
    ],
  );
}

Future<void> blogSendPostEmail(
  BuildContext context,
  AdminBlogService service, {
  required int postId,
  required String title,
  required String content,
}) async {
  blogToast(
    context,
    'Sending email notifications...',
    kind: BlogToastKind.info,
    duration: const Duration(minutes: 5),
  );
  try {
    final r = await service.sendPostNotification(
      postId: postId,
      title: title,
      content: content,
    );
    blogToastClear();
    if (!context.mounted) return;
    if (r.ok) {
      blogToast(
        context,
        'Email sent to ${r.data['sent_count'] ?? 0} subscribers!',
        title: 'Success!',
      );
    } else {
      blogToast(context, r.message, kind: BlogToastKind.warning);
    }
  } catch (_) {
    blogToastClear();
    if (context.mounted) {
      blogToast(
        context,
        'Failed to send email notifications',
        kind: BlogToastKind.error,
      );
    }
  }
}

Future<bool> blogAddCategoryModal(
  BuildContext context,
  AdminBlogService service,
) async {
  final name = TextEditingController();
  final desc = TextEditingController();
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      var busy = false;
      return StatefulBuilder(
        builder: (ctx, setS) {
          Future<void> submit() async {
            if (name.text.trim().isEmpty) {
              blogToast(
                ctx,
                'Please fill out the Category Name field.',
                kind: BlogToastKind.warning,
              );
              return;
            }
            setS(() => busy = true);
            try {
              final r = await service.addCategory(
                name.text.trim(),
                desc.text.trim(),
              );
              if (!ctx.mounted) return;
              if (r.ok) {
                blogToast(ctx, r.message);
                Navigator.pop(ctx, true);
                return;
              }
              blogToast(ctx, r.message, kind: BlogToastKind.error);
            } catch (_) {
              if (ctx.mounted) {
                blogToast(
                  ctx,
                  'Failed to add category',
                  kind: BlogToastKind.error,
                );
              }
            }
            if (ctx.mounted) setS(() => busy = false);
          }

          return WebModal(
            title: 'Add New Category',
            icon: Icons.add_circle_outline,
            width: 520,
            actions: [
              GhostButton(
                label: 'Cancel',
                onPressed: () => Navigator.pop(ctx, false),
              ),
              SignalButton(
                label: 'Add Category',
                icon: Icons.check,
                busy: busy,
                onPressed: busy ? null : submit,
              ),
            ],
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text.rich(
                  TextSpan(
                    text: 'Category Name ',
                    style: TextStyle(fontWeight: FontWeight.w600),
                    children: [
                      TextSpan(
                        text: '*',
                        style: TextStyle(color: Brand.danger),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: name,
                  autofocus: true,
                  onSubmitted: (_) => submit(),
                  decoration: const InputDecoration(
                    hintText: 'e.g., Updates, News, Tutorials',
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Description (Optional)',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: desc,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Brief description of this category',
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
  return saved == true;
}

class BlogCategoryPanel extends StatefulWidget {
  const BlogCategoryPanel({
    super.key,
    required this.service,
    required this.label,
    required this.selected,
    required this.onChanged,
    required this.onCategoryDeleted,
    this.allowCreate = false,
  });
  final AdminBlogService service;
  final String label;
  final List<int> selected;
  final ValueChanged<List<int>> onChanged;
  final VoidCallback onCategoryDeleted;
  final bool allowCreate;

  @override
  State<BlogCategoryPanel> createState() => _BlogCategoryPanelState();
}

class _BlogCategoryPanelState extends State<BlogCategoryPanel> {
  List<BlogCategory> _all = const [];
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await widget.service.categories();
      if (mounted) setState(() => _all = c);
    } catch (_) {}
  }

  void _toggle(int id, bool on) {
    final s = List<int>.from(widget.selected);
    if (on) {
      if (!s.contains(id)) s.add(id);
    } else {
      s.remove(id);
    }
    widget.onChanged(s);
  }

  Future<void> _delete(BlogCategory c) async {
    final ok = await blogConfirm(
      context,
      title: 'Delete Category',
      confirmLabel: 'Delete Category',
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Are you sure you want to delete the category:',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            c.name,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Brand.info,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3CD),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text.rich(
              TextSpan(
                style: TextStyle(color: Color(0xFF664D03)),
                children: [
                  TextSpan(
                    text: 'Warning: ',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text:
                        'This category will be removed from all posts that currently use it. This action cannot be undone.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    if (!ok || !mounted) return;
    if (!await blogUndoWindow(context, 'Category deleted')) return;
    try {
      final r = await widget.service.deleteCategory(c.id);
      if (!mounted) return;
      if (!r.ok) {
        blogToast(context, r.message, kind: BlogToastKind.error);
        return;
      }
      await _load();
      widget.onChanged(widget.selected.where((i) => i != c.id).toList());
      widget.onCategoryDeleted();
    } catch (_) {
      if (mounted) {
        blogToast(
          context,
          'Failed to delete category',
          kind: BlogToastKind.error,
        );
      }
    }
  }

  Widget _small(String label, IconData icon, VoidCallback onTap) =>
      OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 14),
        label: Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF0C233E),
          side: const BorderSide(color: Color(0xFFE2E2DE)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final byId = {for (final c in _all) c.id: c};
    final chosen = widget.selected
        .map((id) => byId[id])
        .whereType<BlogCategory>()
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        BlogLabel(widget.label),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _small(
              'SELECT CATEGORIES',
              Icons.sell_outlined,
              () => setState(() => _open = !_open),
            ),
            if (widget.allowCreate)
              _small('NEW CATEGORY', Icons.add, () async {
                if (await blogAddCategoryModal(context, widget.service)) {
                  await _load();
                }
              }),
          ],
        ),
        if (_open) ...[
          const SizedBox(height: 10),
          Container(
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              border: Border.all(color: const Color(0xFFE2E2DE)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(8),
              children: [
                for (final c in _all)
                  Container(
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Color(0xFFE2E2DE)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Checkbox(
                          value: widget.selected.contains(c.id),
                          onChanged: (v) => _toggle(c.id, v == true),
                          visualDensity: VisualDensity.compact,
                        ),
                        Expanded(child: Text(c.name)),
                        IconButton(
                          tooltip: 'Delete category',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(
                            Icons.close,
                            size: 14,
                            color: Brand.danger,
                          ),
                          onPressed: () => _delete(c),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE2E2DE)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: chosen.isEmpty
              ? const Text(
                  'No categories selected',
                  style: TextStyle(fontSize: 12),
                )
              : Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final c in chosen)
                      Chip(
                        label: Text(c.name),
                        backgroundColor: Brand.info,
                        labelStyle: const TextStyle(color: Colors.white),
                        deleteIconColor: Colors.white,
                        onDeleted: () => _toggle(c.id, false),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class BlogLabel extends StatelessWidget {
  const BlogLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: Color(0xFF888888),
      ),
    ),
  );
}

String blogFileCount(int n, String empty) =>
    n == 0 ? empty : (n == 1 ? '1 file selected' : '$n files selected');

Future<void> blogMediaPreview(
  BuildContext context,
  AdminBlogService service,
  List<BlogMedia> media,
  int start,
) {
  var index = start;
  return showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        final m = media[index];
        final url = service.mediaUrl(m.filePath);
        return Dialog(
          backgroundColor: const Color(0xFF212529),
          insetPadding: const EdgeInsets.all(40),
          child: SizedBox(
            width: 1100,
            height: 720,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                  child: Row(
                    children: [
                      const Text(
                        'Media Preview',
                        style: TextStyle(color: Colors.white, fontSize: 18),
                      ),
                      const Spacer(),
                      Text(
                        '${index + 1} / ${media.length}',
                        style: const TextStyle(color: Colors.white),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      if (media.length > 1)
                        IconButton(
                          icon: const Icon(
                            Icons.chevron_left,
                            color: Colors.white,
                            size: 36,
                          ),
                          onPressed: () => setS(
                            () => index =
                                (index - 1 + media.length) % media.length,
                          ),
                        ),
                      Expanded(
                        child: Center(
                          child: m.isPhoto
                              ? Image.network(
                                  url,
                                  headers: service.api.authHeaders(),
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) => const Text(
                                    'Failed to load image',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                )
                              : Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.play_circle_outline,
                                      color: Colors.white,
                                      size: 72,
                                    ),
                                    const SizedBox(height: 8),
                                    SelectableText(
                                      m.filePath,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      if (media.length > 1)
                        IconButton(
                          icon: const Icon(
                            Icons.chevron_right,
                            color: Colors.white,
                            size: 36,
                          ),
                          onPressed: () =>
                              setS(() => index = (index + 1) % media.length),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
