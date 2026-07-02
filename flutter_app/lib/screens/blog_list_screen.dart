import 'package:flutter/material.dart';

import '../models/blog_models.dart';
import '../services/blog_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';

/// Blog Posts — native list / view / create / delete, backed by the
/// `*BlogPost(s)` actions on api.php. There is no update endpoint, so the
/// detail screen is read-only (full content + delete).
class BlogListScreen extends StatefulWidget {
  const BlogListScreen({super.key, required this.service});
  final BlogService service;

  @override
  State<BlogListScreen> createState() => _BlogListScreenState();
}

class _BlogListScreenState extends State<BlogListScreen> {
  List<BlogPost> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await widget.service.list();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _openNew() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => _BlogFormScreen(service: widget.service),
      ),
    );
    if (changed == true) _load();
  }

  Future<void> _openDetail(BlogPost post) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            _BlogDetailScreen(service: widget.service, post: post),
      ),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return StationScaffold(
      stationNumber: '13',
      stationLabel: 'BLOG POSTS',
      title: 'Posts.',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      trailing: StationAction(
        icon: Icons.add,
        tooltip: 'New post',
        onPressed: _openNew,
      ),
      child: RefreshIndicator(
        color: Brand.signal,
        backgroundColor: Brand.surface,
        onRefresh: _load,
        child: _loading
            ? const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Brand.signal),
                ),
              )
            : _rows.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 64),
                      EmptyState(
                        label: 'No blog posts',
                        hint: 'Tap + to write the first post. Pull to refresh.',
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _rows.length,
                    separatorBuilder: (_, _) => const Hairline(),
                    itemBuilder: (_, i) => _BlogRow(
                      row: _rows[i],
                      onTap: () => _openDetail(_rows[i]),
                    ),
                  ),
      ),
    );
  }
}

class _BlogRow extends StatelessWidget {
  const _BlogRow({required this.row, required this.onTap});
  final BlogPost row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final status = row.isDraftPost ? 'DRAFT' : 'PUBLISHED';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 7, right: 12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: row.isDraftPost ? Brand.rule : Brand.signal,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.title.isEmpty ? 'Untitled' : row.title,
                    style: text.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    row.plainContent,
                    style: text.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              status,
              style: text.labelMedium?.copyWith(
                color: row.isDraftPost ? Brand.paperDim : Brand.signal,
                letterSpacing: 2.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Read-only detail. Shows the full post content and a delete action.
class _BlogDetailScreen extends StatefulWidget {
  const _BlogDetailScreen({required this.service, required this.post});
  final BlogService service;
  final BlogPost post;

  @override
  State<_BlogDetailScreen> createState() => _BlogDetailScreenState();
}

class _BlogDetailScreenState extends State<_BlogDetailScreen> {
  bool _busy = false;

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Brand.surface,
        title: const Text('Delete post?'),
        content: const Text('This permanently removes the post.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final res = await widget.service.delete(widget.post.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.ok) {
      Navigator.of(context).pop(true);
    } else {
      _toast(res.message ?? 'Could not delete the post.');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg.toUpperCase())));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final post = widget.post;
    return StationScaffold(
      stationNumber: '13',
      stationLabel: post.isDraftPost ? 'DRAFT POST' : 'PUBLISHED POST',
      title: 'Post.',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      child: ListView(
        children: [
          Text(
            post.title.isEmpty ? 'Untitled' : post.title,
            style: text.headlineLarge,
          ),
          const SizedBox(height: 8),
          Text(
            (post.isDraftPost ? 'DRAFT' : 'PUBLISHED') +
                (post.createdAt.isEmpty ? '' : '  ·  ${post.createdAt}'),
            style: text.labelMedium?.copyWith(
              color: post.isDraftPost ? Brand.paperDim : Brand.signal,
              letterSpacing: 2.2,
            ),
          ),
          const SizedBox(height: 24),
          const Hairline(),
          const SizedBox(height: 24),
          Text(
            post.plainContent.isEmpty ? 'No content.' : post.plainContent,
            style: text.titleMedium,
          ),
          const SizedBox(height: 32),
          GhostButton(
            label: _busy ? 'Deleting…' : 'Delete post',
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

/// Create form. Title + multiline content + draft toggle.
class _BlogFormScreen extends StatefulWidget {
  const _BlogFormScreen({required this.service});
  final BlogService service;

  @override
  State<_BlogFormScreen> createState() => _BlogFormScreenState();
}

class _BlogFormScreenState extends State<_BlogFormScreen> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _content = TextEditingController();
  bool _draft = false;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final content = _content.text.trim();
    if (title.isEmpty) {
      _toast('Title is required.');
      return;
    }
    if (content.isEmpty) {
      _toast('Content is required.');
      return;
    }
    setState(() => _saving = true);
    final res = await widget.service.add(
      title: title,
      content: content,
      isDraft: _draft,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.ok) {
      Navigator.of(context).pop(true);
    } else {
      _toast(res.message ?? 'Could not save the post.');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg.toUpperCase())));
  }

  @override
  Widget build(BuildContext context) {
    return StationScaffold(
      stationNumber: '13',
      stationLabel: 'NEW POST',
      title: 'Write post.',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      child: ListView(
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'TITLE'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _content,
            decoration: const InputDecoration(labelText: 'CONTENT'),
            style: Theme.of(context).textTheme.titleMedium,
            minLines: 6,
            maxLines: 14,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
          ),
          const SizedBox(height: 20),
          _ToggleRow(
            label: 'SAVE AS DRAFT',
            value: _draft,
            onChanged: (v) => setState(() => _draft = v),
          ),
          const SizedBox(height: 32),
          SignalButton(
            label: _draft ? 'Save draft' : 'Publish post',
            busy: _saving,
            onPressed: _saving ? null : _save,
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.labelLarge),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: Brand.signal,
        ),
      ],
    );
  }
}
