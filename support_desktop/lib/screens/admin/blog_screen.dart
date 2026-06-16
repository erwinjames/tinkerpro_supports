import 'package:flutter/material.dart';

import '../../models/admin_models.dart';
import '../../services/admin_services.dart';
import '../../theme.dart';
import 'admin_list.dart';

class BlogScreen extends StatelessWidget {
  const BlogScreen({super.key, required this.service});
  final BlogService service;

  @override
  Widget build(BuildContext context) {
    return AdminListPage<BlogPost>(
      stationNumber: '09',
      stationLabel: 'BLOG POSTS',
      title: 'Posts.',
      addLabel: 'New post',
      searchHint: 'Search posts…',
      fetch: (search) => service.list(search: search),
      onAdd: (ctx, refresh) => _compose(ctx, refresh),
      itemBuilder: (ctx, p, refresh) => _PostRow(
        post: p,
        onView: () => _view(ctx, p),
        onDelete: () async {
          if (!await confirmDialog(ctx,
              title: 'Delete post',
              message: 'Remove "${p.title}"?')) return;
          final ok = await service.delete(p.id);
          if (!ctx.mounted) return;
          toast(ctx, ok ? 'Deleted' : 'Delete failed');
          if (ok) refresh();
        },
      ),
    );
  }

  /// Compose + publish (or save as draft) a new text post.
  Future<void> _compose(BuildContext context, VoidCallback refresh) async {
    final titleCtrl = TextEditingController();
    final contentCtrl = TextEditingController();

    // result: 'publish' | 'draft' | null
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New post'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Title'),
                  autofocus: true,
                  // Enter on the title publishes; the content field below is
                  // multi-line, so Enter there inserts a newline as expected.
                  onSubmitted: (_) => Navigator.pop(ctx, 'publish'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: contentCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Content',
                    alignLabelWithHint: true,
                  ),
                  minLines: 6,
                  maxLines: 12,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'draft'),
              child: const Text('Save as draft')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'publish'),
              child: const Text('Publish')),
        ],
      ),
    );

    if (action == null) return;
    final title = titleCtrl.text.trim();
    final content = contentCtrl.text.trim();
    if (title.isEmpty || content.isEmpty) {
      if (context.mounted) toast(context, 'Title and content are required.');
      return;
    }
    final ok = await service.add(
      title: title,
      content: content,
      isDraft: action == 'draft',
    );
    if (!context.mounted) return;
    toast(context, ok ? (action == 'draft' ? 'Draft saved' : 'Published') : 'Save failed');
    if (ok) refresh();
  }

  Future<void> _view(BuildContext context, BlogPost p) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(p.title),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(child: Text(p.preview)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }
}

class _PostRow extends StatelessWidget {
  const _PostRow(
      {required this.post, required this.onView, required this.onDelete});
  final BlogPost post;
  final VoidCallback onView;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final tag = post.isDraft ? 'DRAFT' : post.status.toUpperCase();
    return InkWell(
      onTap: onView,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                            child: Text(post.title,
                                style: text.titleSmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 8),
                        if (tag.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: (post.isDraft
                                          ? Brand.paperDim
                                          : Brand.signal)
                                      .withValues(alpha: 0.5)),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(tag,
                                style: TextStyle(
                                    color: post.isDraft
                                        ? Brand.paperDim
                                        : Brand.signal,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(post.preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(color: Brand.paperDim)),
                  ],
                ),
              ),
              IconButton(
                  tooltip: 'Delete',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, size: 18)),
            ],
          ),
          const SizedBox(height: 10),
          Container(height: 1, color: Brand.rule),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
