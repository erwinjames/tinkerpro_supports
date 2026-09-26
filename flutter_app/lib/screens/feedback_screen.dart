import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api_client.dart';
import '../models/feedback_models.dart';
import '../services/feedback_service.dart';
import '../theme.dart';
import '../widgets/pick_source.dart';
import '../widgets/premium.dart';

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<void> openFeedbackComposer(BuildContext context, ApiClient api) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => FeedbackComposerSheet(service: FeedbackService(api)),
  );
}

class FeedbackComposerSheet extends StatefulWidget {
  const FeedbackComposerSheet({super.key, required this.service});

  final FeedbackService service;

  @override
  State<FeedbackComposerSheet> createState() => _FeedbackComposerSheetState();
}

class _FeedbackComposerSheetState extends State<FeedbackComposerSheet> {
  final _subject = TextEditingController();
  final _message = TextEditingController();
  final List<PendingAttachment> _files = <PendingAttachment>[];

  String _category = 'general';
  int _rating = 0;
  int _seq = 0;
  bool _sending = false;
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    _message.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  int get _busyCount => _files.where((f) => f.uploading).length;

  int get _uploadedCount => _files.where((f) => !f.failed).length;

  Future<void> _pickImages() async {
    if (_files.length >= kFeedbackMaxAttachments) return;
    final chosen = await pickWithSource(
      context,
      multiple: true,
      cameraLabel: 'Take a photo',
      fileLabel: 'Choose an image file',
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'gif', 'webp'],
      onError: (m) => _toast(context, m),
    );
    if (chosen.isEmpty || !mounted) return;
    final picked = [for (final f in chosen) XFile(f.path)];
    for (final x in picked) {
      if (_files.length >= kFeedbackMaxAttachments) {
        _toast(
          context,
          'You can attach up to $kFeedbackMaxAttachments images.',
        );
        break;
      }
      await _addOne(x);
      if (!mounted) return;
    }
  }

  Future<void> _addOne(XFile x) async {
    final bytes = await x.readAsBytes();
    if (!mounted) return;
    if (bytes.length > kFeedbackMaxAttachmentBytes) {
      _toast(context, '"${x.name}" is larger than 10 MB.');
      return;
    }
    _seq += 1;
    final item = PendingAttachment(
      key: 'f$_seq',
      name: x.name.isEmpty ? 'image-$_seq.png' : x.name,
      bytes: bytes,
    );
    setState(() => _files.add(item));

    final result = await widget.service.attach(bytes: bytes, name: item.name);
    if (!mounted) return;
    setState(() {
      item.uploading = false;
      if (result.ok) {
        item.id = result.id;
      } else {
        item.error = result.message;
      }
    });
    if (!result.ok) _toast(context, result.message);
  }

  void _remove(PendingAttachment item) {
    setState(() => _files.remove(item));
    widget.service.detach(item.id);
  }

  Future<void> _send() async {
    if (_sending) return;
    if (_busyCount > 0) {
      _toast(context, 'Hold on — an image is still uploading.');
      return;
    }
    var body = _message.text.trim();
    if (body.isEmpty && _uploadedCount == 0) {
      _toast(context, 'Please write your feedback first.');
      return;
    }
    if (body.isEmpty) body = '(screenshot only)';

    setState(() => _sending = true);
    final result = await widget.service.submit(
      category: _category,
      rating: _rating,
      subject: _subject.text,
      message: body,
    );
    if (!mounted) return;
    if (!result.ok) {
      setState(() => _sending = false);
      _toast(context, result.message);
      return;
    }
    setState(() {
      _sending = false;
      _sent = true;
      _files.clear();
    });
  }

  void _close() {
    if (!_sent) widget.service.discardPending();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: b.canvas,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(Brand.radiusLg),
            ),
          ),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.92,
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: _sent ? _buildDone(context) : _buildForm(context, text),
        ),
      ),
    );
  }

  Widget _buildDone(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Brand.success.withValues(alpha: 0.18),
            border: Border.all(color: Brand.success.withValues(alpha: 0.5)),
          ),
          child: Icon(
            Icons.check_rounded,
            size: 28,
            color: context.brand.isDark
                ? Brand.success
                : Color.lerp(Brand.success, const Color(0xFF0B1B2E), 0.25),
          ),
        ),
        const SizedBox(height: 14),
        Text('Thanks for the feedback', style: text.titleMedium),
        const SizedBox(height: 6),
        Text(
          'The super admin team has been notified. We read every message.',
          style: text.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 18),
        SignalButton(label: 'Close', icon: null, onPressed: _close),
      ],
    );
  }

  Widget _buildForm(BuildContext context, TextTheme text) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const IconTile(
              icon: Icons.chat_bubble_outline_rounded,
              color: Brand.orange,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Send Feedback', style: text.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    'Tell us what is working, what is broken, or what you '
                    'wish this app could do.',
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
            AppIconButton(
              icon: Icons.close_rounded,
              tooltip: 'Close',
              onPressed: _close,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              _Label('What is this about?'),
              ChoicePills<String>(
                options: kFeedbackCategories.keys.toList(),
                value: _category,
                labelOf: (k) => kFeedbackCategories[k] ?? k,
                onChanged: (k) => setState(() => _category = k),
              ),
              const SizedBox(height: 14),
              _Label('How would you rate the experience?'),
              Row(
                children: [
                  for (var i = 1; i <= 5; i++)
                    _StarButton(
                      index: i,
                      rating: _rating,
                      onTap: () =>
                          setState(() => _rating = _rating == i ? 0 : i),
                    ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Text(
                        kFeedbackRatingHints[_rating],
                        key: ValueKey(_rating),
                        style: text.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _Label('Subject'),
              TextField(
                controller: _subject,
                maxLength: kFeedbackMaxSubject,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  hintText: 'Short summary (optional)',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 14),
              _Label('Your feedback'),
              TextField(
                controller: _message,
                minLines: 4,
                maxLines: 8,
                maxLength: kFeedbackMaxMessage,
                decoration: const InputDecoration(
                  hintText:
                      'Describe it in as much detail as you like… attach a '
                      'screenshot if it helps.',
                  counterText: '',
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${_message.text.length}/$kFeedbackMaxMessage',
                  style: text.bodySmall,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  GhostButton(
                    label: 'Attach images',
                    icon: Icons.attach_file_rounded,
                    onPressed: _files.length >= kFeedbackMaxAttachments
                        ? () {}
                        : _pickImages,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _files.isEmpty
                          ? 'Pick up to $kFeedbackMaxAttachments images '
                                '(10 MB each)'
                          : '${_files.length} of $kFeedbackMaxAttachments '
                                'attached',
                      style: text.bodySmall,
                    ),
                  ),
                ],
              ),
              if (_files.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final item in _files)
                      _Thumb(item: item, onRemove: () => _remove(item)),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Text(
                'Sent to the TinkerPro Support Team.',
                style: text.bodySmall,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: GhostButton(label: 'Cancel', onPressed: _close),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SignalButton(
                      label: _busyCount > 0 ? 'Uploading…' : 'Send feedback',
                      icon: Icons.send_rounded,
                      busy: _sending,
                      onPressed: _busyCount > 0 || _sending ? null : _send,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: b.paperDim,
          letterSpacing: 0.9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.item, required this.onRemove});

  final PendingAttachment item;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(Brand.radiusSm + 2),
            child: Image.memory(
              item.bytes,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
          ),
          if (item.uploading)
            DecoratedBox(
              decoration: BoxDecoration(
                color: b.canvas.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(Brand.radiusSm + 2),
              ),
              child: const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (item.failed)
            DecoratedBox(
              decoration: BoxDecoration(
                color: Brand.danger.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(Brand.radiusSm + 2),
              ),
              child: const Center(
                child: Icon(
                  Icons.error_outline_rounded,
                  size: 20,
                  color: Colors.white,
                ),
              ),
            ),
          Positioned(
            top: -6,
            right: -6,
            child: IconButton(
              tooltip: 'Remove ${item.name}',
              onPressed: onRemove,
              icon: const Icon(Icons.cancel_rounded, size: 20),
              color: b.paperDim,
            ),
          ),
        ],
      ),
    );
  }
}

class FeedbackInboxScreen extends StatefulWidget {
  const FeedbackInboxScreen({super.key, required this.service});

  final FeedbackService service;

  @override
  State<FeedbackInboxScreen> createState() => _FeedbackInboxScreenState();
}

class _FeedbackInboxScreenState extends State<FeedbackInboxScreen> {
  final _searchController = TextEditingController();
  Timer? _searchTimer;

  List<FeedbackItem> _items = const [];
  FeedbackStats _stats = FeedbackStats.empty;
  String _status = '';
  String _category = '';
  String _search = '';
  bool _loading = true;
  String? _error;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      _loading = _items.isEmpty;
      _error = null;
    });
    try {
      final page = await widget.service.list(
        status: _status,
        category: _category,
        search: _search,
      );
      if (!mounted || seq != _seq) return;
      setState(() {
        _items = page.items;
        _stats = page.stats;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _error = e is HttpException ? e.message : 'Could not load feedback.';
      });
    }
  }

  void _onSearch(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _search = value.trim();
      _load();
    });
  }

  Future<void> _setStatus(FeedbackItem item, String status) async {
    final result = await widget.service.setStatus(
      id: item.id,
      status: status,
      note: item.adminNote,
    );
    if (!mounted) return;
    _toast(context, result.message);
    if (result.ok) _load();
  }

  Future<void> _editNote(FeedbackItem item) async {
    final controller = TextEditingController(text: item.adminNote);
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          item.adminNote.isEmpty
              ? 'Add an internal note'
              : 'Edit internal note',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Only super admins see this. It stays on the feedback from '
              '${item.displayName}.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              minLines: 3,
              maxLines: 6,
              maxLength: 4000,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'What did you find, or what happens next?',
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text(item.adminNote.isEmpty ? 'Add note' : 'Save note'),
          ),
        ],
      ),
    );
    if (saved == null || !mounted) return;
    final result = await widget.service.setStatus(
      id: item.id,
      status: item.status == 'new' ? 'reviewed' : item.status,
      note: saved,
    );
    if (!mounted) return;
    _toast(context, result.message);
    if (result.ok) _load();
  }

  Future<void> _delete(FeedbackItem item) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this feedback?'),
        content: Text(
          'The message from ${item.displayName} and any attached images will '
          'be removed for good.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Brand.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    final result = await widget.service.delete(item.id);
    if (!mounted) return;
    _toast(context, result.message);
    if (result.ok) _load();
  }

  void _openShot(FeedbackAttachment shot) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ShotViewer(
          uri: widget.service.attachmentUri(shot.id),
          headers: widget.service.imageHeaders,
          name: shot.originalName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StationScaffold(
      stationNumber: '13',
      stationLabel: 'Super Admin',
      title: 'Feedback',
      subtitle: 'Everything users have sent through the Feedback button',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      trailing: StationAction(
        icon: Icons.refresh_rounded,
        tooltip: 'Refresh',
        onPressed: _load,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChoicePills<String>(
            options: const [
              '',
              'new',
              'reviewed',
              'in_progress',
              'resolved',
              'archived',
            ],
            value: _status,
            labelOf: (s) => s.isEmpty ? 'All statuses' : feedbackStatusLabel(s),
            onChanged: (s) {
              if (s == _status) return;
              setState(() => _status = s);
              _load();
            },
          ),
          const SizedBox(height: 10),
          ChoicePills<String>(
            options: ['', ...kFeedbackCategories.keys],
            value: _category,
            labelOf: (c) =>
                c.isEmpty ? 'All categories' : feedbackCategoryLabel(c),
            onChanged: (c) {
              if (c == _category) return;
              setState(() => _category = c);
              _load();
            },
          ),
          const SizedBox(height: 12),
          AppSearchField(
            controller: _searchController,
            hint: 'Search name, subject or message',
            onChanged: _onSearch,
            onSubmitted: (v) {
              _searchTimer?.cancel();
              _search = v.trim();
              _load();
            },
          ),
          const SizedBox(height: 14),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const SkeletonList(count: 5)
                  : _error != null
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 48),
                        EmptyState(
                          label: 'Could not load feedback',
                          hint: _error!,
                          icon: Icons.cloud_off_rounded,
                          action: FilledButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('Try again'),
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 20),
                      itemCount: _items.isEmpty ? 2 : _items.length + 1,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        if (i == 0) return _StatsStrip(stats: _stats);
                        if (_items.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.only(top: 36),
                            child: EmptyState(
                              label: 'No feedback matches these filters yet',
                              hint:
                                  'Change the status, category or search word.',
                              icon: Icons.inbox_rounded,
                            ),
                          );
                        }
                        final item = _items[i - 1];
                        return _EntryFade(
                          index: i - 1,
                          child: _FeedbackCard(
                            item: item,
                            headers: widget.service.imageHeaders,
                            uriOf: widget.service.attachmentUri,
                            onShot: _openShot,
                            onStatus: (s) => _setStatus(item, s),
                            onNote: () => _editNote(item),
                            onDelete: () => _delete(item),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsStrip extends StatelessWidget {
  const _StatsStrip({required this.stats});

  final FeedbackStats stats;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return SizedBox(
      height: 104,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _StatTile(
            label: 'Total',
            value: stats.total,
            icon: Icons.inbox_rounded,
            color: b.signal,
          ),
          const SizedBox(width: 10),
          _StatTile(
            label: 'New',
            value: stats.newCount,
            icon: Icons.fiber_new_rounded,
            color: Brand.orange,
            alert: stats.newCount > 0,
          ),
          const SizedBox(width: 10),
          _StatTile(
            label: 'In progress',
            value: stats.inProgress,
            icon: Icons.sync_rounded,
            color: Brand.warning,
          ),
          const SizedBox(width: 10),
          _StatTile(
            label: 'Resolved',
            value: stats.resolved,
            icon: Icons.check_circle_rounded,
            color: Brand.success,
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 168,
            child: GlassPanel(
              accent: Brand.info,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        size: 13,
                        color: Brand.info,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          'Avg rating',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.labelSmall?.copyWith(color: b.paperDim),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    stats.avgRatingLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleLarge?.copyWith(
                      color: b.paper,
                      fontSize: 20,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _StarMeter(value: stats.avgRating, size: 15),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.alert = false,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final style = text.headlineSmall?.copyWith(color: b.paper, height: 1.1);
    return SizedBox(
      width: 142,
      child: GlassPanel(
        accent: color,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: color.withValues(alpha: alert ? 0.5 : 0.3),
                    ),
                  ),
                  child: Icon(
                    icon,
                    size: 13,
                    color: b.isDark
                        ? color
                        : Color.lerp(color, const Color(0xFF0B1B2E), 0.25),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: reduce
                      ? Text('$value', style: style)
                      : TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0, end: value.toDouble()),
                          duration: const Duration(milliseconds: 520),
                          curve: Curves.easeOutCubic,
                          builder: (context, v, _) =>
                              Text('${v.round()}', style: style),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.labelSmall?.copyWith(color: b.paperDim),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({
    required this.item,
    required this.headers,
    required this.uriOf,
    required this.onShot,
    required this.onStatus,
    required this.onNote,
    required this.onDelete,
  });

  final FeedbackItem item;
  final Map<String, String> headers;
  final Uri Function(int) uriOf;
  final ValueChanged<FeedbackAttachment> onShot;
  final ValueChanged<String> onStatus;
  final VoidCallback onNote;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    return AppCard(
      radius: Brand.radiusLg,
      padding: const EdgeInsets.all(14),
      borderColor: item.isNew ? Brand.orange.withValues(alpha: 0.5) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppAvatar(name: item.displayName, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.displayName,
                      style: text.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _GlowPill(label: item.categoryLabel, color: Brand.info),
                        _GlowPill(
                          label: item.statusLabel,
                          color: StatusPill.colorFor(item.statusLabel),
                          dot: true,
                        ),
                        if (item.rating > 0)
                          _StarMeter(value: item.rating.toDouble(), size: 14),
                        Text(item.ago, style: text.bodySmall),
                        if (item.roleLabel.isNotEmpty)
                          Text('· ${item.roleLabel}', style: text.bodySmall),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (item.subject.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(item.subject, style: text.titleSmall),
          ],
          const SizedBox(height: 6),
          Text(item.message, style: text.bodySmall),
          if (item.pageUrl.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(item.pageUrl, style: text.bodySmall?.copyWith(fontSize: 11)),
          ],
          if (item.attachments.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 78,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: item.attachments.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final shot = item.attachments[i];
                  return Semantics(
                    button: true,
                    label: shot.originalName,
                    child: InkWell(
                      onTap: () => onShot(shot),
                      borderRadius: BorderRadius.circular(Brand.radiusSm + 2),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(Brand.radiusSm + 2),
                        child: Image.network(
                          uriOf(shot.id).toString(),
                          headers: headers,
                          width: 78,
                          height: 78,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 78,
                            height: 78,
                            color: b.surfaceHi,
                            child: Icon(
                              Icons.broken_image_rounded,
                              color: b.paperDim,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          if (item.adminNote.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: b.surfaceHi,
                borderRadius: BorderRadius.circular(Brand.radiusSm),
              ),
              child: Text(
                '${item.handledByName.isEmpty ? 'Admin' : item.handledByName}: '
                '${item.adminNote}',
                style: text.bodySmall,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _ActChip(
                icon: Icons.visibility_rounded,
                label: 'Reviewed',
                onTap: () => onStatus('reviewed'),
              ),
              _ActChip(
                icon: Icons.sync_rounded,
                label: 'In progress',
                onTap: () => onStatus('in_progress'),
              ),
              _ActChip(
                icon: Icons.check_rounded,
                label: 'Resolved',
                onTap: () => onStatus('resolved'),
              ),
              _ActChip(
                icon: Icons.archive_rounded,
                label: 'Archive',
                onTap: () => onStatus('archived'),
              ),
              _ActChip(
                icon: Icons.edit_note_rounded,
                label: item.adminNote.isEmpty ? 'Add note' : 'Edit note',
                onTap: onNote,
              ),
              _ActChip(
                icon: Icons.delete_outline_rounded,
                label: 'Delete',
                danger: true,
                onTap: onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActChip extends StatelessWidget {
  const _ActChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final color = danger ? Brand.danger : b.paper;
    return Semantics(
      button: true,
      child: Material(
        color: b.surface,
        shape: StadiumBorder(
          side: BorderSide(color: danger ? Brand.danger : b.rule),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShotViewer extends StatelessWidget {
  const _ShotViewer({
    required this.uri,
    required this.headers,
    required this.name,
  });

  final Uri uri;
  final Map<String, String> headers;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.navy,
      appBar: AppBar(
        backgroundColor: Brand.navy,
        foregroundColor: Colors.white,
        title: Text(name.isEmpty ? 'Attachment' : name),
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 5,
          child: Image.network(
            uri.toString(),
            headers: headers,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const EmptyState(
              label: 'Could not load that image',
              hint: 'It may have been removed from the server.',
              icon: Icons.broken_image_rounded,
            ),
          ),
        ),
      ),
    );
  }
}

class _GlowPill extends StatelessWidget {
  const _GlowPill({required this.label, required this.color, this.dot = false});

  final String label;
  final Color color;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final ink = b.isDark
        ? color
        : Color.lerp(color, const Color(0xFF0B1B2E), 0.3)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: b.isDark ? 0.18 : 0.12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: ink, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: ink,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StarMeter extends StatelessWidget {
  const _StarMeter({required this.value, this.size = 15});

  final double value;
  final double size;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final ratio = (value / 5).clamp(0.0, 1.0);
    final width = size * 5 + 8;
    Widget row(Color color, IconData icon) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++)
          Padding(
            padding: EdgeInsets.only(right: i == 4 ? 0 : 2),
            child: Icon(icon, size: size, color: color),
          ),
      ],
    );
    return Semantics(
      label: '${value.toStringAsFixed(1)} out of 5 stars',
      child: SizedBox(
        width: width,
        height: size,
        child: Stack(
          children: [
            row(b.paperDim.withValues(alpha: 0.5), Icons.star_rounded),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: reduce ? ratio : 0, end: ratio),
              duration: Duration(milliseconds: reduce ? 0 : 520),
              curve: Curves.easeOutCubic,
              builder: (context, t, child) =>
                  ClipRect(clipper: _StarClipper(t), child: child),
              child: row(Brand.orange, Icons.star_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _StarClipper extends CustomClipper<Rect> {
  const _StarClipper(this.ratio);

  final double ratio;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * ratio, size.height);

  @override
  bool shouldReclip(_StarClipper oldClipper) => oldClipper.ratio != ratio;
}

class _StarButton extends StatelessWidget {
  const _StarButton({
    required this.index,
    required this.rating,
    required this.onTap,
  });

  final int index;
  final int rating;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final on = index <= rating;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Semantics(
      button: true,
      selected: on,
      label: '$index star',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: AnimatedScale(
              scale: on ? 1.15 : 1,
              duration: Duration(milliseconds: reduce ? 0 : 220),
              curve: Curves.easeOutBack,
              child: Icon(
                on ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 26,
                color: on ? Brand.orange : b.paperDim,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EntryFade extends StatelessWidget {
  const _EntryFade({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) return child;
    final delay = (index.clamp(0, 7)) * 55;
    final total = 300 + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: Curves.easeOutCubic),
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 14),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
