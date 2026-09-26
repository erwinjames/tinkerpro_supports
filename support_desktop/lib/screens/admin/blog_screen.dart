import 'dart:async';
import 'dart:io' as tmpio;

import 'package:flutter/material.dart';

import '../../services/admin_blog_service.dart';
import '../../services/admin_services.dart';
import '../../theme.dart';
import '../../widgets/admin_table_page.dart';
import '../../widgets/premium.dart';
import 'admin_blog_compose.dart';
import 'admin_blog_editor.dart';
import 'admin_blog_ui.dart';
import '../../models/admin_models.dart';

typedef _Post = Map<String, dynamic>;

String _ps(_Post p, String k) => (p[k] ?? '').toString();

int _pid(_Post p) => int.tryParse(_ps(p, 'id')) ?? 0;

class BlogScreen extends StatefulWidget {
  const BlogScreen({super.key, required this.service});
  final BlogService service;

  @override
  State<BlogScreen> createState() => _BlogScreenState();
}

class _BlogScreenState extends State<BlogScreen> {
  late final AdminBlogService _blog = AdminBlogService(widget.service.api);
  final _table = AdminTableController();
  final Set<int> _hidden = {};
  String _filter = 'all';
  int _published = 0;
  int _scheduled = 0;
  int _pending = 0;
  int _drafts = 0;
  Timer? _scheduledPoll;
  Timer? _draftsPoll;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    _loadCounts();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkScheduled());
    _scheduledPoll = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _checkScheduled(),
    );
    _draftsPoll = Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        if (_onScreen) _loadDrafts();
      },
    );
    final tmpOpen = tmpio.Platform.environment['TP_BLOG_OPEN'] ?? '';
    if (tmpOpen.isNotEmpty) {
      Future.delayed(const Duration(seconds: 3), () async {
        if (!mounted) return;
        if (tmpOpen == 'compose') {
          _compose(draft: BlogPostDetail(id: 0, title: 'ZZ FLOW TEST UI', content: '<p style="font-size: 16px;">Hello <strong>bold</strong> <em>it</em> <span style="color: #E03E2D;">red</span></p>\n<h2>Heading</h2>\n<ul>\n<li>one</li>\n<li>two</li>\n</ul>\n<p style="text-align: center;">centered</p>', status: 'draft', scheduledAt: '', createdAt: '', categories: const [], media: const []));
        } else if (tmpOpen.startsWith('edit:')) {
          _edit({'id': tmpOpen.substring(5)});
        } else if (tmpOpen.startsWith('view:')) {
          _view({'id': tmpOpen.substring(5)});
        } else if (tmpOpen.startsWith('resched:')) {
          _reschedule({'id': tmpOpen.substring(8)});
        } else if (tmpOpen == 'drafts') {
          _showDrafts();
        }
      });
    }
  }

  @override
  void dispose() {
    _scheduledPoll?.cancel();
    _draftsPoll?.cancel();
    super.dispose();
  }

  bool get _onScreen => mounted && Visibility.of(context);

  Future<void> _checkScheduled() async {
    if (_polling || !_onScreen) return;
    _polling = true;
    try {
      if (await _blog.publishDueScheduled() > 0 && mounted) _refreshAll();
    } catch (_) {
    } finally {
      _polling = false;
    }
  }

  List<Map<String, dynamic>> _list(dynamic raw) => raw is List
      ? raw.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
      : <Map<String, dynamic>>[];

  Future<void> _loadDrafts() async {
    try {
      final d = await _blog.drafts();
      if (mounted) setState(() => _drafts = d.length);
    } catch (_) {}
  }

  Future<void> _loadCounts() async {
    try {
      final api = widget.service.api;
      final all = await api.getPath(kBlogFacade, {
        'action': 'getposts-admin',
        'page': '1',
        'pageSize': '999999',
        'filter': '',
      });
      final fb = await api.getPath(kBlogFacade, {'action': 'getfeedbacks'});
      final posts = _list(all['posts']);
      final feedbacks = _list(fb['data']);
      final postIds = posts.map((p) => _ps(p, 'id')).toSet();
      if (!mounted) return;
      setState(() {
        _published = posts
            .where(
              (p) =>
                  _ps(p, 'status') == 'published' && _ps(p, 'is_draft') != '1',
            )
            .length;
        _scheduled = posts.where((p) => _ps(p, 'status') == 'scheduled').length;
        _pending = feedbacks
            .where(
              (f) =>
                  postIds.contains(_ps(f, 'post_id')) &&
                  _ps(f, 'approved') != '1',
            )
            .length;
      });
    } catch (_) {}
    await _loadDrafts();
  }

  Future<Paged<_Post>> _fetch(String _) async {
    final res = await widget.service.api.getPath(kBlogFacade, {
      'action': 'getposts-admin',
      'page': '1',
      'pageSize': '999999',
      'filter': _filter == 'all' ? '' : _filter,
    });
    final posts = _list(
      res['posts'],
    ).where((p) => !_hidden.contains(_pid(p))).toList();
    return Paged(items: posts, total: posts.length);
  }

  void _refreshAll() {
    _table.reload();
    _loadCounts();
  }

  Future<void> _compose({BlogPostDetail? draft}) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BlogComposeDialog(
        service: _blog,
        draft: draft,
        onPostsChanged: _refreshAll,
        onDraftsChanged: _loadDrafts,
      ),
    );
  }

  Future<void> _edit(_Post p) async {
    BlogPostDetail? post;
    try {
      post = await _blog.post(_pid(p));
    } catch (_) {}
    if (!mounted) return;
    if (post == null) {
      blogToast(context, 'Failed to load post data', kind: BlogToastKind.error);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => BlogEditDialog(
        service: _blog,
        post: post!,
        onPostsChanged: _refreshAll,
      ),
    );
  }

  Future<void> _delete(_Post p) async {
    final id = _pid(p);
    final ok = await blogConfirm(
      context,
      title: 'Delete this post?',
      confirmLabel: 'Delete post',
      body: const Text(
        'The post and its associated media references will be permanently removed.',
      ),
    );
    if (!ok || !mounted) return;
    setState(() => _hidden.add(id));
    _table.silentReload();
    final commit = await blogUndoWindow(context, 'Post deleted');
    if (!mounted) return;
    if (!commit) {
      setState(() => _hidden.remove(id));
      _table.silentReload();
      return;
    }
    try {
      final r = await _blog.deletePost(id);
      if (mounted && !r.ok) {
        blogToast(context, r.message, kind: BlogToastKind.error);
      }
    } catch (_) {
      if (mounted) {
        blogToast(context, 'Failed to delete post', kind: BlogToastKind.error);
      }
    }
    _hidden.remove(id);
    if (mounted) _refreshAll();
  }

  Future<void> _reschedule(_Post p) async {
    final id = _pid(p);
    BlogPostDetail? post;
    try {
      post = await _blog.post(id);
    } catch (_) {}
    if (!mounted) return;
    if (post == null) {
      blogToast(context, 'Failed to load post data', kind: BlogToastKind.error);
      return;
    }
    DateTime? value = blogParse(post.scheduledAt);
    final opened = DateTime.now();
    var busy = '';
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          Future<void> confirm() async {
            final v = value;
            if (v == null) {
              blogToast(
                ctx,
                'Please select a date and time',
                kind: BlogToastKind.error,
              );
              return;
            }
            if (!v.isAfter(DateTime.now())) {
              blogToast(
                ctx,
                'Scheduled time must be in the future',
                kind: BlogToastKind.error,
              );
              return;
            }
            setS(() => busy = 'reschedule');
            try {
              final r = await _blog.reschedule(id, blogLocalInput(v));
              blogToastClear();
              if (!ctx.mounted) return;
              if (r.ok) {
                blogToast(
                  ctx,
                  'Post rescheduled for ${blogLocaleDate(v)} at ${blogLocaleTime(v)}',
                  title: 'Success!',
                );
                Navigator.pop(ctx);
                Future.delayed(const Duration(milliseconds: 500), _refreshAll);
                return;
              }
              blogToast(
                ctx,
                r.message.isEmpty ? 'Failed to reschedule post' : r.message,
                kind: BlogToastKind.error,
              );
            } catch (_) {
              blogToastClear();
              if (ctx.mounted) {
                blogToast(
                  ctx,
                  'Failed to reschedule post',
                  kind: BlogToastKind.error,
                );
              }
            }
            if (ctx.mounted) setS(() => busy = '');
          }

          Future<void> publishNow() async {
            setS(() => busy = 'publish');
            try {
              final r = await _blog.publishScheduledNow(id);
              if (!ctx.mounted) return;
              if (r.ok) {
                blogToast(ctx, 'Post published succesfully!');
                await Future<void>.delayed(const Duration(milliseconds: 600));
                if (ctx.mounted) Navigator.pop(ctx);
                _refreshAll();
                return;
              }
              blogToast(
                ctx,
                r.message.isEmpty ? 'Failed to publish post' : r.message,
                kind: BlogToastKind.error,
              );
            } catch (_) {
              if (ctx.mounted) {
                blogToast(
                  ctx,
                  'Failed to publish post',
                  kind: BlogToastKind.error,
                );
              }
            }
            if (ctx.mounted) setS(() => busy = '');
          }

          return WebModal(
            title: 'Reschedule Post',
            icon: Icons.calendar_month_outlined,
            width: 560,
            actions: [
              GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx)),
              SignalButton(
                label: busy == 'publish' ? 'Publishing...' : 'Publish Now',
                icon: Icons.send,
                busy: busy == 'publish',
                onPressed: busy.isEmpty ? publishNow : null,
              ),
              SignalButton(
                label: busy == 'reschedule' ? 'Rescheduling' : 'Reschedule',
                icon: Icons.access_time,
                busy: busy == 'reschedule',
                onPressed: busy.isEmpty ? confirm : null,
              ),
            ],
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFCFF4FC),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 18,
                        color: Color(0xFF055160),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            style: TextStyle(color: Color(0xFF055160)),
                            children: [
                              TextSpan(
                                text: 'Reschedule your post\n',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              TextSpan(
                                text:
                                    'Change the date and time when this post will be automatically published, or publish it immediately.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF494646),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    Icon(Icons.access_time, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'New Date & Time',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                BlogDateTimeField(
                  value: value,
                  min: opened,
                  onChanged: (v) => setS(() => value = v),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showDrafts() async {
    List<Map<String, dynamic>> drafts;
    try {
      drafts = await _blog.drafts();
    } catch (_) {
      if (mounted) {
        blogToast(
          context,
          'Failed to save draft. You may lose changes if you close.',
          kind: BlogToastKind.error,
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() => _drafts = drafts.length);
    final pick = await showWebModal<(String, int)>(
      context,
      title: 'Drafts (${drafts.length})',
      icon: Icons.folder_open_outlined,
      width: 760,
      builder: (ctx) => drafts.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Column(
                children: [
                  Icon(
                    Icons.folder_open_outlined,
                    size: 48,
                    color: Color(0xFF94A3B8),
                  ),
                  SizedBox(height: 12),
                  Text('No drafts yet'),
                ],
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final d in drafts)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: AdminTableColors.border),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => Navigator.pop(ctx, ('open', _pid(d))),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _ps(d, 'title').isEmpty
                                        ? 'Untitled Draft'
                                        : _ps(d, 'title'),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      const Icon(Icons.access_time, size: 13),
                                      const SizedBox(width: 6),
                                      Text(
                                        adminFormatDate(
                                          _ps(d, 'created_at'),
                                          withTime: true,
                                        ),
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            DangerButton(
                              label: 'Delete',
                              icon: Icons.delete_outline,
                              onPressed: () =>
                                  Navigator.pop(ctx, ('delete', _pid(d))),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
    if (pick == null || !mounted) return;
    if (pick.$1 == 'delete') {
      await _deleteDraft(pick.$2);
    } else {
      await _openDraft(pick.$2);
    }
  }

  Future<void> _openDraft(int id) async {
    BlogPostDetail? draft;
    try {
      draft = await _blog.post(id);
    } catch (_) {}
    if (!mounted) return;
    if (draft == null) {
      blogToast(context, 'Failed to load draft', kind: BlogToastKind.error);
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (mounted) await _compose(draft: draft);
  }

  Future<void> _deleteDraft(int id) async {
    final ok = await blogConfirm(
      context,
      title: 'Delete Draft?',
      confirmLabel: 'Delete',
      body: blogCenterText([
        'Are you sure you want to delete this draft?',
      ], small: 'This action cannot be undone.'),
    );
    if (!ok || !mounted) return;
    if (!await blogUndoWindow(context, 'Draft deleted')) return;
    try {
      final r = await _blog.deletePost(id);
      if (!mounted) return;
      if (!r.ok) {
        blogToast(
          context,
          r.message.isEmpty ? 'Failed to delete draft' : r.message,
          kind: BlogToastKind.error,
        );
      }
      await _loadDrafts();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (mounted) await _showDrafts();
    } catch (_) {
      if (mounted) {
        blogToast(
          context,
          'An error occurred while deleting the draft',
          kind: BlogToastKind.error,
        );
      }
    }
  }

  Future<void> _view(_Post p) async {
    BlogPostDetail? post;
    try {
      post = await _blog.post(_pid(p));
    } catch (_) {}
    if (!mounted) return;
    if (post == null) {
      blogToast(context, 'Failed to load post data', kind: BlogToastKind.error);
      return;
    }
    final detail = post;
    final scheduled = detail.status == 'scheduled';
    await showWebModal<void>(
      context,
      title: detail.title,
      subtitle: scheduled
          ? 'Scheduled on ${adminFormatDate(detail.scheduledAt, withTime: true)}'
          : 'Published on ${adminFormatDate(detail.createdAt, withTime: true)}',
      icon: Icons.article_outlined,
      width: 900,
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          BlogHtmlView(html: detail.content),
          if (detail.media.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < detail.media.length; i++)
                  InkWell(
                    onTap: () => blogMediaPreview(ctx, _blog, detail.media, i),
                    child: Container(
                      width: 160,
                      height: 120,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: const Color(0xFF212529),
                      ),
                      child: detail.media[i].isPhoto
                          ? Image.network(
                              _blog.mediaUrl(detail.media[i].filePath),
                              headers: widget.service.api.authHeaders(),
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const Icon(Icons.broken_image_outlined),
                            )
                          : const Icon(
                              Icons.play_circle_outline,
                              color: Colors.white,
                              size: 40,
                            ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
      actions: (ctx) => [
        SignalButton(label: 'Close', onPressed: () => Navigator.pop(ctx)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    String pad(int n) => n.toString().padLeft(2, '0');
    return AdminTablePage<_Post>(
      stationNumber: '09',
      stationLabel: 'BLOG POSTS',
      title: 'Blog Posts',
      addLabel: 'New publication',
      searchHint: 'Search publication registry...',
      controller: _table,
      liveKeys: const ['blogposts'],
      onLiveChange: _loadCounts,
      filterKey: _filter,
      fetch: _fetch,
      localFilter: (p, q) =>
          _ps(p, 'title').toLowerCase().contains(q) ||
          _ps(p, 'content').toLowerCase().contains(q),
      onAdd: (ctx, refresh) => _compose(),
      onRowTap: (ctx, p, refresh) => _view(p),
      extraActions: [_DraftsButton(count: _drafts, onPressed: _showDrafts)],
      summary: (ctx, items, total, search) => AdminTicker(
        items: [
          AdminTickerItem(
            'Live archive',
            pad(_published),
            Icons.check_circle,
            Brand.success,
          ),
          AdminTickerItem(
            'Scheduled',
            pad(_scheduled),
            Icons.watch_later,
            Brand.info,
          ),
          AdminTickerItem(
            'Moderation queue',
            pad(_pending),
            Icons.error,
            Brand.warning,
          ),
        ],
        trailing: [
          PopupMenuButton<String>(
            tooltip: 'Filter registry',
            position: PopupMenuPosition.under,
            onSelected: (v) {
              setState(() => _filter = v);
              _table.reload();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'all', child: Text('ALL ENTRIES')),
              PopupMenuItem(value: 'published', child: Text('PUBLISHED')),
              PopupMenuItem(value: 'scheduled', child: Text('SCHEDULED')),
            ],
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AdminTableColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.filter_alt,
                    size: 15,
                    color: AdminTableColors.text,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _filter == 'all'
                        ? 'FILTER REGISTRY'
                        : _filter.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AdminTableColors.text,
                    ),
                  ),
                  const Icon(
                    Icons.arrow_drop_down,
                    size: 18,
                    color: AdminTableColors.text,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      columns: [
        AdminColumn(
          'Publication Details',
          flex: 1,
          sortValue: (p) => _ps(p as _Post, 'title'),
        ),
        AdminColumn(
          'Registry Timestamp',
          width: 265,
          sortValue: (p) => _ps(p as _Post, 'status') == 'scheduled'
              ? _ps(p, 'scheduled_at')
              : _ps(p, 'created_at'),
        ),
        AdminColumn(
          'Status',
          width: 135,
          center: true,
          sortValue: (p) => _ps(p as _Post, 'status'),
        ),
        const AdminColumn('Action', width: 135, center: true, sortable: false),
      ],
      cells: (ctx, p, refresh) {
        final scheduled = _ps(p, 'status') == 'scheduled';
        final draft = _ps(p, 'status') == 'draft' || _ps(p, 'is_draft') == '1';
        final cats = p['categories'] is List
            ? p['categories'] as List
            : const [];
        return [
          Row(
            children: [
              Flexible(child: AdminCellText(_ps(p, 'title'))),
              for (final c in cats.whereType<Map>()) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F9FA),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AdminTableColors.border),
                  ),
                  child: Text(
                    '${c['name'] ?? ''}'.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: AdminTableColors.text,
                    ),
                  ),
                ),
              ],
            ],
          ),
          AdminDateTimeCell(
            scheduled ? _ps(p, 'scheduled_at') : _ps(p, 'created_at'),
            prefix: scheduled ? 'Scheduled' : 'Published',
          ),
          scheduled
              ? const AdminBadge(
                  'Pending',
                  color: Brand.warning,
                  icon: Icons.watch_later,
                )
              : draft
              ? const AdminBadge(
                  'Draft',
                  color: AdminTableColors.headerText,
                  icon: Icons.description,
                )
              : const AdminBadge(
                  'Published',
                  color: Brand.success,
                  icon: Icons.check_circle,
                ),
          AdminRowMenu(
            actions: [
              AdminMenuAction(
                'Edit Publication',
                Icons.edit_outlined,
                () => _edit(p),
              ),
              AdminMenuAction(
                'Purge Record',
                Icons.delete_outline,
                () => _delete(p),
                danger: true,
              ),
              if (scheduled)
                AdminMenuAction(
                  'Modify Schedule',
                  Icons.calendar_month_outlined,
                  () => _reschedule(p),
                ),
            ],
          ),
        ];
      },
    );
  }
}

class _DraftsButton extends StatelessWidget {
  const _DraftsButton({required this.count, required this.onPressed});
  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AdminTableColors.text,
        side: const BorderSide(color: AdminTableColors.border),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.folder_open_outlined, size: 16),
          const SizedBox(width: 8),
          const Text(
            'DRAFTS',
            style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5),
          ),
          if (count > 0) ...[
            const SizedBox(width: 8),
            CountBadge(count: count),
          ],
        ],
      ),
    );
  }
}
