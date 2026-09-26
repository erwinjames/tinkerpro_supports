import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/blog_models.dart';
import '../services/blog_service.dart';
import '../theme.dart';
import '../widgets/help_html.dart';
import '../widgets/premium.dart';
import 'blog_form_screen.dart';

const List<({String label, String value})> kBlogFilters = [
  (label: 'All', value: ''),
  (label: 'Published', value: 'published'),
  (label: 'Scheduled', value: 'scheduled'),
  (label: 'Pending', value: 'pending'),
];

class BlogListScreen extends StatefulWidget {
  const BlogListScreen({super.key, required this.service});
  final BlogService service;

  @override
  State<BlogListScreen> createState() => _BlogListScreenState();
}

class _BlogListScreenState extends State<BlogListScreen> {
  final TextEditingController _search = TextEditingController();
  final List<BlogPost> _posts = [];
  List<BlogFeedback> _feedbacks = const [];

  Timer? _debounce;
  String _filter = '';
  int _page = 1;
  int _total = 0;
  int _published = 0;
  int _scheduled = 0;
  int _drafts = 0;
  bool _loading = true;
  bool _loadingMore = false;

  static const int _pageSize = 20;

  int get _pendingFeedback => _feedbacks.where((f) => !f.isApproved).length;

  bool get _hasMore => _posts.length < _total;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await Future.wait([_loadPosts(), _loadMeta()]);
  }

  Future<void> _loadPosts() async {
    setState(() => _loading = true);
    final page = await widget.service.posts(
      page: 1,
      pageSize: _pageSize,
      filter: _filter,
      search: _search.text,
    );
    if (!mounted) return;
    setState(() {
      _posts
        ..clear()
        ..addAll(page.posts);
      _page = 1;
      _total = page.total;
      _loading = false;
    });
  }

  Future<void> _loadMeta() async {
    final results = await Future.wait([
      widget.service.feedbacks(),
      widget.service.drafts(),
      widget.service.posts(page: 1, pageSize: 1, filter: 'published'),
      widget.service.posts(page: 1, pageSize: 1, filter: 'scheduled'),
    ]);
    if (!mounted) return;
    setState(() {
      _feedbacks = results[0] as List<BlogFeedback>;
      _drafts = (results[1] as List<BlogPost>).length;
      _published = (results[2] as BlogPage).total;
      _scheduled = (results[3] as BlogPage).total;
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final page = await widget.service.posts(
      page: _page + 1,
      pageSize: _pageSize,
      filter: _filter,
      search: _search.text,
    );
    if (!mounted) return;
    setState(() {
      _posts.addAll(page.posts);
      _page += 1;
      _total = page.total;
      _loadingMore = false;
    });
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _loadPosts);
  }

  void _setFilter(String value) {
    if (_filter == value) return;
    setState(() => _filter = value);
    _loadPosts();
  }

  List<BlogFeedback> _feedbackFor(int postId) =>
      _feedbacks.where((f) => f.postId == postId).toList();

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openForm({BlogPost? existing}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            BlogFormScreen(service: widget.service, existing: existing),
      ),
    );
    if (changed == true) _load();
  }

  Future<void> _openDetail(BlogPost post) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => BlogDetailScreen(
          service: widget.service,
          post: post,
          feedbacks: _feedbackFor(post.id),
        ),
      ),
    );
    if (changed == true) _load();
  }

  Future<void> _openDrafts() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => BlogDraftsScreen(service: widget.service),
      ),
    );
    if (changed == true) _load();
  }

  Future<void> _openCategories() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => BlogCategoriesScreen(service: widget.service),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _openFeedback(BlogPost post) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => BlogFeedbackScreen(
          service: widget.service,
          post: post,
          feedbacks: _feedbackFor(post.id),
        ),
      ),
    );
    if (changed == true) _load();
  }

  Future<void> _delete(BlogPost post) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Purge record?'),
        content: Text(
          'This permanently removes "${post.title}" and its media.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Brand.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final res = await widget.service.delete(post.id);
    if (!mounted) return;
    if (res.ok) {
      _load();
    } else {
      _toast(res.message ?? 'Could not delete the post.');
    }
  }

  Future<void> _reschedule(BlogPost post) async {
    final when = await pickBlogSchedule(context);
    if (when == null || !mounted) return;
    final res = await widget.service.reschedule(
      id: post.id,
      scheduledAt: blogStampNow(when),
    );
    if (!mounted) return;
    if (res.ok) {
      _toast(res.message ?? 'Schedule updated.');
      _load();
    } else {
      _toast(res.message ?? 'Could not reschedule the post.');
    }
  }

  Future<void> _publishNow(BlogPost post) async {
    final res = await widget.service.publishNow(post.id);
    if (!mounted) return;
    if (res.ok) {
      _toast(res.message ?? 'Post published.');
      _load();
    } else {
      _toast(res.message ?? 'Could not publish the post.');
    }
  }

  Future<void> _actions(BlogPost post) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_note_rounded),
              title: const Text('Edit publication'),
              onTap: () => Navigator.of(ctx).pop('edit'),
            ),
            ListTile(
              leading: const Icon(Icons.forum_outlined),
              title: const Text('Reader feedback'),
              subtitle: Text('${_feedbackFor(post.id).length} recorded'),
              onTap: () => Navigator.of(ctx).pop('feedback'),
            ),
            if (post.isScheduled) ...[
              ListTile(
                leading: const Icon(Icons.event_repeat_rounded),
                title: const Text('Modify schedule'),
                onTap: () => Navigator.of(ctx).pop('reschedule'),
              ),
              ListTile(
                leading: const Icon(Icons.publish_rounded),
                title: const Text('Publish now'),
                onTap: () => Navigator.of(ctx).pop('publish'),
              ),
            ],
            ListTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: Brand.danger,
              ),
              title: const Text('Purge record'),
              onTap: () => Navigator.of(ctx).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'edit':
        await _openForm(existing: post);
      case 'feedback':
        await _openFeedback(post);
      case 'reschedule':
        await _reschedule(post);
      case 'publish':
        await _publishNow(post);
      case 'delete':
        await _delete(post);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return StationScaffold(
      stationNumber: '13',
      stationLabel: 'Blog',
      title: 'Publications',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DraftsAction(count: _drafts, onPressed: _openDrafts),
          const SizedBox(width: 8),
          AppIconButton(
            icon: Icons.sell_outlined,
            tooltip: 'Categories',
            onPressed: _openCategories,
          ),
          const SizedBox(width: 8),
          StationAction(
            icon: Icons.add_rounded,
            tooltip: 'New publication',
            onPressed: _openForm,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Wrap(
              spacing: 18,
              runSpacing: 10,
              children: [
                _TickerItem(
                  icon: Icons.check_circle_rounded,
                  color: Brand.success,
                  label: 'Live archive',
                  value: _loading ? '—' : _pad(_published),
                ),
                _TickerItem(
                  icon: Icons.schedule_rounded,
                  color: b.signal,
                  label: 'Scheduled',
                  value: _loading ? '—' : _pad(_scheduled),
                ),
                _TickerItem(
                  icon: Icons.mark_chat_unread_outlined,
                  color: Brand.warning,
                  label: 'Moderation',
                  value: _loading ? '—' : _pad(_pendingFeedback),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          AppSearchField(
            controller: _search,
            hint: 'Search publications',
            onChanged: _onSearch,
            onSubmitted: (_) => _load(),
          ),
          const SizedBox(height: 12),
          ChoicePills<String>(
            options: [for (final f in kBlogFilters) f.value],
            value: _filter,
            labelOf: (v) => kBlogFilters.firstWhere((f) => f.value == v).label,
            onChanged: _setFilter,
          ),
          const SizedBox(height: 14),
          Expanded(
            child: RefreshIndicator(
              color: b.signal,
              backgroundColor: b.surface,
              onRefresh: _load,
              child: _loading
                  ? const SkeletonList(count: 6)
                  : _posts.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 64),
                        EmptyState(
                          icon: _search.text.trim().isEmpty
                              ? Icons.article_rounded
                              : Icons.search_off_rounded,
                          label: _search.text.trim().isEmpty
                              ? 'No publications'
                              : 'No matches',
                          hint: _search.text.trim().isEmpty
                              ? 'Tap + to write the first one. Pull to refresh.'
                              : 'Try a different search.',
                          action: _search.text.trim().isEmpty
                              ? null
                              : GhostButton(
                                  label: 'Clear search',
                                  onPressed: () {
                                    _search.clear();
                                    _load();
                                  },
                                ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: _posts.length + (_hasMore ? 1 : 0),
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        if (i >= _posts.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: GhostButton(
                              label: _loadingMore
                                  ? 'Loading…'
                                  : 'Load more (${_posts.length} of $_total)',
                              icon: Icons.expand_more_rounded,
                              onPressed: _loadMore,
                            ),
                          );
                        }
                        final post = _posts[i];
                        return _Stagger(
                          index: i,
                          child: _BlogRow(
                            row: post,
                            pending: _feedbackFor(
                              post.id,
                            ).where((f) => !f.isApproved).length,
                            onTap: () => _openDetail(post),
                            onActions: () => _actions(post),
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

String _pad(int value) => value.toString().padLeft(2, '0');

Future<DateTime?> pickBlogSchedule(BuildContext context) async {
  final now = DateTime.now();
  final date = await showDatePicker(
    context: context,
    initialDate: now.add(const Duration(hours: 1)),
    firstDate: now,
    lastDate: DateTime(now.year + 5),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
  );
  if (time == null) return null;
  final picked = DateTime(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  );
  return picked;
}

class _DraftsAction extends StatelessWidget {
  const _DraftsAction({required this.count, required this.onPressed});

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AppIconButton(
          icon: Icons.folder_open_outlined,
          tooltip: 'Drafts',
          onPressed: onPressed,
        ),
        if (count > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Brand.danger,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _BlogRow extends StatelessWidget {
  const _BlogRow({
    required this.row,
    required this.pending,
    required this.onTap,
    required this.onActions,
  });

  final BlogPost row;
  final int pending;
  final VoidCallback onTap;
  final VoidCallback onActions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final accent = blogStatusColor(context, row);
    return AppCard(
      onTap: onTap,
      radius: Brand.radiusLg,
      borderColor: accent.withValues(alpha: b.isDark ? 0.34 : 0.26),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TypeTile(icon: blogStatusIcon(row), color: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.title.isEmpty ? 'Untitled' : row.title,
                  style: text.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (row.categories.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final category in row.categories)
                        _CategoryChip(label: category.name),
                    ],
                  ),
                ],
                if (row.plainContent.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    row.plainContent,
                    style: text.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _GlowChip(
                      label: row.statusLabel.toUpperCase(),
                      color: accent,
                      icon: blogStatusIcon(row),
                    ),
                    if (row.stamp.isNotEmpty)
                      Text(
                        '${row.stampLabel} ${blogPrettyStamp(row.stamp)}',
                        style: text.labelMedium,
                      ),
                    if (row.media.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.perm_media_outlined,
                            size: 13,
                            color: b.paperDim,
                          ),
                          const SizedBox(width: 4),
                          Text('${row.media.length}', style: text.labelMedium),
                        ],
                      ),
                    if (pending > 0)
                      _GlowChip(
                        label: '$pending PENDING',
                        color: Brand.warning,
                        icon: Icons.mark_chat_unread_outlined,
                      ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Actions',
            icon: Icon(Icons.more_vert_rounded, color: b.paperDim),
            onPressed: onActions,
          ),
        ],
      ),
    );
  }
}

Color blogStatusColor(BuildContext context, BlogPost post) {
  if (post.isScheduled) return context.brand.signal;
  if (post.isDraftPost) return Brand.warning;
  return Brand.success;
}

IconData blogStatusIcon(BlogPost post) {
  if (post.isScheduled) return Icons.schedule_rounded;
  if (post.isDraftPost) return Icons.edit_note_rounded;
  return Icons.check_circle_rounded;
}

class BlogDetailScreen extends StatefulWidget {
  const BlogDetailScreen({
    super.key,
    required this.service,
    required this.post,
    this.feedbacks = const [],
  });

  final BlogService service;
  final BlogPost post;
  final List<BlogFeedback> feedbacks;

  @override
  State<BlogDetailScreen> createState() => _BlogDetailScreenState();
}

class _BlogDetailScreenState extends State<BlogDetailScreen> {
  late BlogPost _post;
  bool _dirty = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _refresh();
  }

  Future<void> _refresh() async {
    final fresh = await widget.service.post(widget.post.id);
    if (!mounted || fresh == null) return;
    setState(() => _post = fresh);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _edit() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            BlogFormScreen(service: widget.service, existing: _post),
      ),
    );
    if (changed == true) {
      _dirty = true;
      await _refresh();
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Purge record?'),
        content: const Text('This permanently removes the post and its media.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Brand.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final res = await widget.service.delete(_post.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.ok) {
      Navigator.of(context).pop(true);
    } else {
      _toast(res.message ?? 'Could not delete the post.');
    }
  }

  Future<void> _publishNow() async {
    setState(() => _busy = true);
    final res = await widget.service.publishNow(_post.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.ok) {
      _dirty = true;
      _toast(res.message ?? 'Post published.');
      await _refresh();
    } else {
      _toast(res.message ?? 'Could not publish the post.');
    }
  }

  Future<void> _reschedule() async {
    final when = await pickBlogSchedule(context);
    if (when == null || !mounted) return;
    setState(() => _busy = true);
    final res = await widget.service.reschedule(
      id: _post.id,
      scheduledAt: blogStampNow(when),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.ok) {
      _dirty = true;
      _toast(res.message ?? 'Schedule updated.');
      await _refresh();
    } else {
      _toast(res.message ?? 'Could not reschedule the post.');
    }
  }

  Future<void> _openFeedback() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => BlogFeedbackScreen(
          service: widget.service,
          post: _post,
          feedbacks: widget.feedbacks,
        ),
      ),
    );
    if (changed == true) _dirty = true;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final accent = blogStatusColor(context, _post);
    return StationScaffold(
      stationNumber: '13',
      stationLabel: 'Blog',
      title: 'Publication',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(_dirty),
      trailing: StationAction(
        icon: Icons.edit_rounded,
        tooltip: 'Edit publication',
        onPressed: _edit,
      ),
      child: ListView(
        children: [
          GlassPanel(
            accent: accent,
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _TypeTile(icon: blogStatusIcon(_post), color: accent),
                    const SizedBox(width: 12),
                    _GlowChip(
                      label: _post.statusLabel.toUpperCase(),
                      color: accent,
                      icon: blogStatusIcon(_post),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  _post.title.isEmpty ? 'Untitled' : _post.title,
                  style: text.headlineMedium?.copyWith(color: b.paper),
                ),
                if (_post.stamp.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${_post.stampLabel} ${blogPrettyStamp(_post.stamp)}',
                    style: text.bodySmall?.copyWith(color: b.paperDim),
                  ),
                ],
                if (_post.categories.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final category in _post.categories)
                        _CategoryChip(label: category.name),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            radius: Brand.radiusLg,
            child: _post.content.trim().isEmpty
                ? Text(
                    'No content.',
                    style: text.bodyLarge?.copyWith(color: b.paperDim),
                  )
                : HelpHtmlView(
                    html: _post.content,
                    headers: widget.service.mediaHeaders,
                  ),
          ),
          if (_post.media.isNotEmpty) ...[
            const SizedBox(height: 12),
            AppCard(
              radius: Brand.radiusLg,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionHeader(title: 'Media (${_post.media.length})'),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final media in _post.media)
                        _MediaTile(
                          media: media,
                          headers: widget.service.mediaHeaders,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          AppCard(
            radius: Brand.radiusLg,
            onTap: _openFeedback,
            child: Row(
              children: [
                Icon(Icons.forum_outlined, color: b.signal),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Reader feedback', style: text.titleSmall),
                ),
                Text(
                  '${widget.feedbacks.length}',
                  style: text.titleSmall?.copyWith(color: b.paperDim),
                ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right_rounded, color: b.paperDim),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (_post.isScheduled) ...[
            SignalButton(
              label: 'Publish now',
              icon: Icons.publish_rounded,
              busy: _busy,
              onPressed: _busy ? null : _publishNow,
            ),
            const SizedBox(height: 10),
            GhostButton(
              label: 'Modify schedule',
              icon: Icons.event_repeat_rounded,
              onPressed: () {
                if (!_busy) _reschedule();
              },
            ),
            const SizedBox(height: 10),
          ],
          GhostButton(
            label: _busy ? 'Working…' : 'Purge record',
            icon: Icons.delete_outline_rounded,
            onPressed: () {
              if (!_busy) _delete();
            },
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({required this.media, required this.headers});

  final BlogMedia media;
  final Map<String, String> headers;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return InkWell(
      onTap: media.url.isEmpty
          ? null
          : () => launchUrl(
              Uri.parse(media.url),
              mode: LaunchMode.externalApplication,
            ),
      borderRadius: BorderRadius.circular(Brand.radiusSm),
      child: Container(
        width: 104,
        height: 104,
        decoration: BoxDecoration(
          color: b.surfaceHi,
          borderRadius: BorderRadius.circular(Brand.radiusSm),
          border: Border.all(color: b.rule),
        ),
        clipBehavior: Clip.antiAlias,
        child: media.isVideo || media.url.isEmpty
            ? Center(
                child: Icon(
                  media.isVideo
                      ? Icons.play_circle_outline_rounded
                      : Icons.image_not_supported_outlined,
                  color: b.paperDim,
                ),
              )
            : CachedNetworkImage(
                imageUrl: media.url,
                httpHeaders: headers,
                fit: BoxFit.cover,
                placeholder: (_, _) => const Skeleton(height: 104),
                errorWidget: (_, _, _) =>
                    Icon(Icons.broken_image_outlined, color: b.paperDim),
              ),
      ),
    );
  }
}

class BlogDraftsScreen extends StatefulWidget {
  const BlogDraftsScreen({super.key, required this.service});
  final BlogService service;

  @override
  State<BlogDraftsScreen> createState() => _BlogDraftsScreenState();
}

class _BlogDraftsScreenState extends State<BlogDraftsScreen> {
  List<BlogPost> _rows = const [];
  bool _loading = true;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await widget.service.drafts();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _open(BlogPost draft) async {
    final full = await widget.service.post(draft.id) ?? draft;
    if (!mounted) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => BlogFormScreen(service: widget.service, existing: full),
      ),
    );
    if (changed == true) {
      _dirty = true;
      _load();
    }
  }

  Future<void> _delete(BlogPost draft) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard draft?'),
        content: const Text('This permanently removes the draft.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Brand.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final res = await widget.service.delete(draft.id);
    if (!mounted) return;
    if (res.ok) {
      _dirty = true;
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message ?? 'Could not discard the draft.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return StationScaffold(
      stationNumber: '13',
      stationLabel: 'Blog',
      title: 'Drafts',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(_dirty),
      child: _loading
          ? const SkeletonList(count: 5)
          : _rows.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 64),
                EmptyState(
                  icon: Icons.drafts_outlined,
                  label: 'No drafts',
                  hint: 'Drafts you save appear here.',
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: _rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final draft = _rows[i];
                return AppCard(
                  radius: Brand.radiusLg,
                  onTap: () => _open(draft),
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const _TypeTile(
                        icon: Icons.edit_note_rounded,
                        color: Brand.warning,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              draft.title.isEmpty ? 'Untitled' : draft.title,
                              style: text.titleSmall,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (draft.plainContent.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                draft.plainContent,
                                style: text.bodySmall,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            if (draft.createdAt.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                blogPrettyStamp(draft.createdAt),
                                style: text.labelMedium,
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Discard draft',
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: b.paperDim,
                        ),
                        onPressed: () => _delete(draft),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class BlogCategoriesScreen extends StatefulWidget {
  const BlogCategoriesScreen({super.key, required this.service});
  final BlogService service;

  @override
  State<BlogCategoriesScreen> createState() => _BlogCategoriesScreenState();
}

class _BlogCategoriesScreenState extends State<BlogCategoriesScreen> {
  List<BlogCategory> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await widget.service.categories();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _add() async {
    final name = TextEditingController();
    final description = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add new category'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Category name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: description,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    final label = name.text.trim();
    final note = description.text.trim();
    name.dispose();
    description.dispose();
    if (saved != true || !mounted) return;
    if (label.isEmpty) {
      _toast('Category name is required.');
      return;
    }
    final res = await widget.service.addCategory(
      name: label,
      description: note,
    );
    if (!mounted) return;
    if (res.ok) {
      _load();
    } else {
      _toast(res.message ?? 'Could not add the category.');
    }
  }

  Future<void> _delete(BlogCategory category) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete category?'),
        content: Text(
          '"${category.name}" is removed from every post that uses it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Brand.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final res = await widget.service.deleteCategory(category.id);
    if (!mounted) return;
    if (res.ok) {
      _toast(res.message ?? 'Category deleted.');
      _load();
    } else {
      _toast(res.message ?? 'Could not delete the category.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return StationScaffold(
      stationNumber: '13',
      stationLabel: 'Blog',
      title: 'Categories',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      trailing: StationAction(
        icon: Icons.add_rounded,
        tooltip: 'New category',
        onPressed: _add,
      ),
      child: _loading
          ? const SkeletonList(count: 5)
          : _rows.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 64),
                EmptyState(
                  icon: Icons.sell_outlined,
                  label: 'No categories',
                  hint: 'Tap + to add the first one.',
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: _rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final category = _rows[i];
                return AppCard(
                  radius: Brand.radiusLg,
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      _TypeTile(icon: Icons.sell_rounded, color: b.signal),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(category.name, style: text.titleSmall),
                            const SizedBox(height: 2),
                            Text(
                              category.description.isEmpty
                                  ? category.slug
                                  : category.description,
                              style: text.bodySmall?.copyWith(
                                color: b.paperDim,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Delete category',
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: b.paperDim,
                        ),
                        onPressed: () => _delete(category),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class BlogFeedbackScreen extends StatefulWidget {
  const BlogFeedbackScreen({
    super.key,
    required this.service,
    required this.post,
    required this.feedbacks,
  });

  final BlogService service;
  final BlogPost post;
  final List<BlogFeedback> feedbacks;

  @override
  State<BlogFeedbackScreen> createState() => _BlogFeedbackScreenState();
}

class _BlogFeedbackScreenState extends State<BlogFeedbackScreen> {
  late List<BlogFeedback> _rows;
  final Set<int> _selected = <int>{};
  bool _dirty = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _rows = List<BlogFeedback>.from(widget.feedbacks);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _reload() async {
    final all = await widget.service.feedbacks();
    if (!mounted) return;
    setState(() {
      _rows = all.where((f) => f.postId == widget.post.id).toList();
      _selected.removeWhere((id) => !_rows.any((f) => f.id == id));
    });
  }

  Future<void> _run(Future<BlogResult> Function() action) async {
    setState(() => _busy = true);
    final res = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.ok) {
      _toast(res.message ?? 'That did not work.');
      return;
    }
    _dirty = true;
    if (res.message != null) _toast(res.message!);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return StationScaffold(
      stationNumber: '13',
      stationLabel: 'Blog',
      title: 'Reader feedback',
      subtitle: widget.post.title,
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(_dirty),
      bottomBar: _selected.isEmpty
          ? null
          : Row(
              children: [
                Expanded(
                  child: GhostButton(
                    label: 'Approve ${_selected.length}',
                    icon: Icons.check_rounded,
                    onPressed: () {
                      if (_busy) return;
                      _run(
                        () =>
                            widget.service.approveFeedbacks(_selected.toList()),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GhostButton(
                    label: 'Delete ${_selected.length}',
                    icon: Icons.delete_outline_rounded,
                    onPressed: () {
                      if (_busy) return;
                      _run(
                        () =>
                            widget.service.deleteFeedbacks(_selected.toList()),
                      );
                    },
                  ),
                ),
              ],
            ),
      child: _rows.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 64),
                EmptyState(
                  icon: Icons.forum_outlined,
                  label: 'Registry empty',
                  hint: 'No reader interactions recorded for this post.',
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: _rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final row = _rows[i];
                final selected = _selected.contains(row.id);
                return AppCard(
                  radius: Brand.radiusLg,
                  borderColor: selected ? b.signal : null,
                  onTap: () => setState(() {
                    if (!_selected.remove(row.id)) _selected.add(row.id);
                  }),
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppAvatar(name: row.userName, size: 40),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  row.userName.isEmpty
                                      ? 'Anonymous'
                                      : row.userName,
                                  style: text.titleSmall,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  row.userEmail.isEmpty
                                      ? blogPrettyStamp(row.createdAt)
                                      : '${row.userEmail} · '
                                            '${blogPrettyStamp(row.createdAt)}',
                                  style: text.labelMedium,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          _GlowChip(
                            label: row.isApproved ? 'VERIFIED' : 'PENDING',
                            color: row.isApproved
                                ? Brand.success
                                : Brand.warning,
                            icon: row.isApproved
                                ? Icons.check_rounded
                                : Icons.schedule_rounded,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: b.surfaceHi,
                          borderRadius: BorderRadius.circular(Brand.radiusSm),
                          border: Border(
                            left: BorderSide(color: b.signal, width: 3),
                          ),
                        ),
                        child: Text(row.message, style: text.bodyMedium),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(row.reference, style: text.labelMedium),
                          const Spacer(),
                          if (!row.isApproved)
                            TextButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => _run(
                                      () => widget.service.approveFeedback(
                                        row.id,
                                      ),
                                    ),
                              icon: const Icon(Icons.check_rounded, size: 18),
                              label: const Text('Approve'),
                            ),
                          TextButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _run(
                                    () => widget.service.deleteFeedback(row.id),
                                  ),
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                            ),
                            label: const Text('Delete'),
                            style: TextButton.styleFrom(
                              foregroundColor: Brand.danger,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _TickerItem extends StatelessWidget {
  const _TickerItem({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: _chipInk(context, color)),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: text.labelMedium?.copyWith(
            color: b.paperDim,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          value,
          style: text.titleSmall?.copyWith(color: _chipInk(context, color)),
        ),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: b.surfaceHi,
        border: Border.all(color: b.rule),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: b.paperDim,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _Stagger extends StatelessWidget {
  const _Stagger({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce || index > 7) return child;
    final delay = index * 45;
    final total = 280 + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: Curves.easeOutCubic),
      builder: (context, t, inner) => Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 14),
          child: inner,
        ),
      ),
      child: child,
    );
  }
}

Color _chipInk(BuildContext context, Color color) {
  final b = context.brand;
  if (b.isDark) {
    return color.computeLuminance() < 0.22
        ? Color.lerp(color, Colors.white, 0.6)!
        : color;
  }
  return color.computeLuminance() > 0.3
      ? Color.lerp(color, Brand.navy, 0.45)!
      : color;
}

class _GlowChip extends StatelessWidget {
  const _GlowChip({required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final ink = _chipInk(context, color);
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
          if (icon != null) ...[
            Icon(icon, size: 13, color: ink),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: ink,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeTile extends StatelessWidget {
  const _TypeTile({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        color: color.withValues(alpha: b.isDark ? 0.18 : 0.12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Icon(icon, size: 21, color: _chipInk(context, color)),
    );
  }
}
