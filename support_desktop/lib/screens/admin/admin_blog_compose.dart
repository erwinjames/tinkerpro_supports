import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../services/admin_blog_service.dart';
import '../../theme.dart';
import '../../widgets/premium.dart';
import 'admin_blog_editor.dart';
import 'admin_blog_ui.dart';

const Duration kBlogAutoSaveDelay = Duration(seconds: 30);

InputDecoration _titleDecoration(String hint) => InputDecoration(
  hintText: hint,
  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
);

class _MediaPicker extends StatelessWidget {
  const _MediaPicker({
    required this.label,
    required this.count,
    required this.empty,
    required this.icon,
    required this.onPick,
  });
  final String label;
  final int count;
  final String empty;
  final IconData icon;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFCFCFB),
          border: Border.all(color: const Color(0xFFE2E2DE)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: Color(0xFF0C233E),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: Brand.signal),
                const SizedBox(width: 8),
                Text(
                  blogFileCount(count, empty),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<List<String>?> _pickFiles() async {
  final r = await FilePicker.platform.pickFiles(allowMultiple: true);
  if (r == null) return null;
  return r.files.map((f) => f.path).whereType<String>().toList();
}

class BlogComposeDialog extends StatefulWidget {
  const BlogComposeDialog({
    super.key,
    required this.service,
    required this.onPostsChanged,
    required this.onDraftsChanged,
    this.draft,
  });
  final AdminBlogService service;
  final BlogPostDetail? draft;
  final VoidCallback onPostsChanged;
  final VoidCallback onDraftsChanged;

  @override
  State<BlogComposeDialog> createState() => _BlogComposeDialogState();
}

class _BlogComposeDialogState extends State<BlogComposeDialog> {
  final _title = TextEditingController();
  final _content = TextEditingController();
  List<int> _categories = [];
  List<String> _files = [];
  int? _draftId;
  bool _busy = false;
  bool _allowClose = false;
  bool _unsaved = false;
  Timer? _autoSave;

  AdminBlogService get service => widget.service;

  @override
  void initState() {
    super.initState();
    final d = widget.draft;
    if (d != null) {
      _title.text = d.title;
      _content.text = d.content;
      _categories = d.categories.map((c) => c.id).toList();
      _draftId = d.id;
      if (d.media.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          blogToast(
            context,
            d.media.length == 1
                ? '1 media file attached'
                : '${d.media.length} media files attached',
            kind: BlogToastKind.info,
          );
        });
      }
    }
  }

  @override
  void dispose() {
    _autoSave?.cancel();
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  void _scheduleAutoSave() {
    _autoSave?.cancel();
    _unsaved = true;
    _autoSave = Timer(kBlogAutoSaveDelay, () {
      if (_unsaved && mounted) _autoSaveDraft();
    });
  }

  Future<void> _autoSaveDraft() async {
    final title = _title.text;
    final content = blogEditorHtml(_content.text);
    if (title.isEmpty && content.isEmpty) return;
    final draftId = _draftId;
    try {
      final r = await service.addPost(
        title: title,
        content: content,
        categoryIds: _categories,
        mediaPaths: _files,
        isDraft: true,
        draftId: draftId,
      );
      if (!mounted || !r.ok) return;
      final pid = int.tryParse('${r.data['post_id']}');
      if (pid != null && draftId == null) _draftId = pid;
      _unsaved = false;
      blogToast(
        context,
        'Draft auto-saved',
        kind: BlogToastKind.info,
        duration: const Duration(seconds: 2),
      );
      widget.onDraftsChanged();
    } catch (_) {}
  }

  void _close() {
    _autoSave?.cancel();
    setState(() => _allowClose = true);
    Navigator.of(context).pop();
  }

  Future<void> _tryClose() async {
    if (_title.text.trim().isEmpty && _content.text.trim().isEmpty) {
      _close();
      return;
    }
    final discard = await showWebModal<bool>(
      context,
      title: 'Unfinished Post',
      icon: Icons.warning_amber_rounded,
      width: 480,
      barrierDismissible: false,
      builder: (_) => const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.description_outlined, size: 48, color: Brand.danger),
          SizedBox(height: 12),
          Text(
            'You have an unfinished post with missing title or content.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17),
          ),
          SizedBox(height: 8),
          Text('Do you want to discard it?', textAlign: TextAlign.center),
        ],
      ),
      actions: (ctx) => [
        GhostButton(
          label: 'Go back',
          icon: Icons.arrow_back,
          onPressed: () => Navigator.pop(ctx, false),
        ),
        DangerButton(
          label: 'Discard',
          icon: Icons.delete_outline,
          onPressed: () => Navigator.pop(ctx, true),
        ),
      ],
    );
    if (discard == true && mounted) _close();
  }

  Future<void> _publish() async {
    final send = await blogEmailModal(context, service, scheduled: false);
    if (send == null || !mounted) return;
    await _submit(sendEmail: send);
  }

  Future<void> _schedule() async {
    final when = await blogScheduleModal(context);
    if (when == null || !mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    final send = await blogEmailModal(context, service, scheduled: true);
    if (send == null || !mounted) return;
    await _submit(sendEmail: send, scheduledAt: blogLocalInput(when));
  }

  Future<void> _submit({required bool sendEmail, String? scheduledAt}) async {
    final title = _title.text;
    final content = blogEditorHtml(_content.text);
    setState(() => _busy = true);
    try {
      final r = await service.addPost(
        title: title,
        content: content,
        categoryIds: _categories,
        mediaPaths: _files,
        sendEmail: sendEmail,
        scheduledAt: scheduledAt,
        draftId: _draftId,
      );
      if (!mounted) return;
      if (!r.ok) {
        blogToast(context, r.message, kind: BlogToastKind.error);
        setState(() => _busy = false);
        return;
      }
      final status = '${r.data['status'] ?? ''}';
      final postId = int.tryParse('${r.data['post_id']}') ?? 0;
      if (sendEmail && status == 'published') {
        unawaited(
          blogSendPostEmail(
            context,
            service,
            postId: postId,
            title: title,
            content: content,
          ),
        );
      }
      if (status == 'scheduled') {
        final d = blogParse('${r.data['scheduled_at'] ?? ''}');
        var message = d == null
            ? r.message
            : 'Post scheduled for ${blogLocaleDate(d)} at ${blogLocaleTime(d)}';
        if (sendEmail) {
          message += '\nEmail will be sent automatically when published.';
        }
        blogToast(context, message, title: 'Success!');
      } else if (status == 'published') {
        blogToast(context, 'Post published successfully!');
      } else if (status == 'draft') {
        blogToast(context, 'Draft saved successfully!');
      } else {
        blogToast(context, r.message);
      }
      widget.onPostsChanged();
      widget.onDraftsChanged();
      _close();
    } catch (_) {
      if (!mounted) return;
      blogToast(context, 'Failed to add post', kind: BlogToastKind.error);
      setState(() => _busy = false);
    }
  }

  Future<void> _saveDraft() async {
    setState(() => _busy = true);
    try {
      final r = await service.addPost(
        title: _title.text,
        content: blogEditorHtml(_content.text),
        categoryIds: _categories,
        mediaPaths: _files,
        isDraft: true,
        draftId: _draftId,
      );
      if (!mounted) return;
      if (r.ok) {
        blogToast(context, 'Draft saved successfully!');
        widget.onDraftsChanged();
        _close();
        return;
      }
      blogToast(context, r.message, kind: BlogToastKind.error);
    } catch (_) {
      if (mounted) {
        blogToast(context, 'Failed to save draft', kind: BlogToastKind.error);
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowClose,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _tryClose();
      },
      child: WebModal(
        title: 'New Publication',
        subtitle: 'Content Assembly Protocol',
        icon: Icons.article_outlined,
        width: 980,
        actions: [
          GhostButton(
            label: 'SAVE AS DRAFT',
            onPressed: _busy ? null : _saveDraft,
          ),
          SignalButton(
            label: 'INITIATE PUBLICATION',
            icon: Icons.send,
            busy: _busy,
            onPressed: _busy ? null : _publish,
          ),
          PopupMenuButton<String>(
            tooltip: 'More publish options',
            enabled: !_busy,
            onSelected: (_) => _schedule(),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'schedule',
                child: Row(
                  children: [
                    Icon(Icons.access_time, size: 18, color: Brand.info),
                    SizedBox(width: 8),
                    Text(
                      'Schedule Release',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ],
            child: Container(
              height: 40,
              width: 36,
              decoration: BoxDecoration(
                color: Brand.signal,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.arrow_drop_down, color: Colors.white),
            ),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const BlogLabel('Descriptive Headline'),
            TextField(
              controller: _title,
              autofocus: true,
              onChanged: (_) => _scheduleAutoSave(),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              decoration: _titleDecoration('Enter publication title...'),
            ),
            const SizedBox(height: 24),
            const BlogLabel('Article Payload'),
            BlogHtmlEditor(controller: _content, onChanged: _scheduleAutoSave),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 7,
                  child: BlogCategoryPanel(
                    service: service,
                    label: 'Taxonomy Selection',
                    selected: _categories,
                    allowCreate: true,
                    onChanged: (v) => setState(() => _categories = v),
                    onCategoryDeleted: widget.onPostsChanged,
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const BlogLabel('Visual Media Registry'),
                      _MediaPicker(
                        label: 'CLICK TO ATTACH ASSETS',
                        count: _files.length,
                        empty: 'Awaiting files...',
                        icon: Icons.cloud_upload_outlined,
                        onPick: () async {
                          final f = await _pickFiles();
                          if (f != null && mounted) {
                            setState(() => _files = f);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class BlogEditDialog extends StatefulWidget {
  const BlogEditDialog({
    super.key,
    required this.service,
    required this.post,
    required this.onPostsChanged,
  });
  final AdminBlogService service;
  final BlogPostDetail post;
  final VoidCallback onPostsChanged;

  @override
  State<BlogEditDialog> createState() => _BlogEditDialogState();
}

class _BlogEditDialogState extends State<BlogEditDialog> {
  late final _title = TextEditingController(text: widget.post.title);
  late final _content = TextEditingController(text: widget.post.content);
  late List<int> _categories = widget.post.categories.map((c) => c.id).toList();
  late final List<BlogMedia> _media = List.of(widget.post.media);
  final Set<int> _selected = {};
  final Set<int> _hidden = {};
  List<String> _files = [];
  bool _busy = false;

  AdminBlogService get service => widget.service;

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  List<BlogMedia> get _visible =>
      _media.where((m) => !_hidden.contains(m.id)).toList();

  Future<void> _deleteOne(BlogMedia m) async {
    setState(() => _hidden.add(m.id));
    if (!await blogUndoWindow(context, 'Media deleted')) {
      if (mounted) setState(() => _hidden.remove(m.id));
      return;
    }
    try {
      final r = await service.deleteMedia(m.id);
      if (!mounted) return;
      if (r.ok) {
        setState(() {
          _media.removeWhere((x) => x.id == m.id);
          _selected.remove(m.id);
          _hidden.remove(m.id);
        });
        widget.onPostsChanged();
        return;
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _hidden.remove(m.id));
    blogToast(context, 'Failed to delete media', kind: BlogToastKind.error);
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) {
      blogToast(context, 'No media selected', kind: BlogToastKind.warning);
      return;
    }
    final ids = _selected.toList();
    final ok = await blogConfirm(
      context,
      title: 'Confirm Media Deletion',
      confirmLabel: 'Delete Selected',
      body: blogCenterText([
        'Are you sure you want to delete ${ids.length} selected media file(s)?',
      ], small: 'This action cannot be undone.'),
    );
    if (!ok || !mounted) return;
    setState(() => _hidden.addAll(ids));
    if (!await blogUndoWindow(context, '${ids.length} media file(s) deleted')) {
      if (mounted) setState(() => _hidden.removeAll(ids));
      return;
    }
    String? error;
    try {
      final r = await service.deleteMultipleMedia(ids);
      if (!mounted) return;
      if (r.ok) {
        setState(() {
          _media.removeWhere((m) => ids.contains(m.id));
          _selected.removeAll(ids);
          _hidden.removeAll(ids);
        });
        widget.onPostsChanged();
        return;
      }
      error = r.message.isEmpty ? 'Failed to delete selected media' : r.message;
    } catch (_) {
      error = 'Failed to delete selected media';
    }
    if (!mounted) return;
    setState(() => _hidden.removeAll(ids));
    blogToast(context, error, kind: BlogToastKind.error);
  }

  void _toggleAll() {
    final vis = _visible.map((m) => m.id).toSet();
    setState(() {
      if (vis.isNotEmpty && _selected.containsAll(vis)) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(vis);
      }
    });
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty) {
      blogToast(
        context,
        'Please fill out the Publication Headline field.',
        kind: BlogToastKind.warning,
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await service.updatePost(
        id: widget.post.id,
        title: _title.text,
        content: blogEditorHtml(_content.text),
        categoryIds: _categories,
        mediaPaths: _files,
      );
      if (!mounted) return;
      if (r.ok) {
        blogToast(context, r.message);
        widget.onPostsChanged();
        Navigator.of(context).pop();
        return;
      }
      blogToast(context, r.message, kind: BlogToastKind.error);
    } catch (_) {
      if (mounted) {
        blogToast(context, 'Failed to update post', kind: BlogToastKind.error);
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Widget _thumb(BlogMedia m) {
    final url = service.mediaUrl(m.filePath);
    return SizedBox(
      width: 108,
      height: 88,
      child: Stack(
        children: [
          Positioned(
            left: 20,
            top: 0,
            child: InkWell(
              onTap: () => blogMediaPreview(context, service, [m], 0),
              child: Container(
                width: 80,
                height: 80,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFD5D6D6), width: 2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: m.isPhoto
                    ? Image.network(
                        url,
                        headers: service.api.authHeaders(),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.broken_image_outlined),
                      )
                    : const ColoredBox(
                        color: Color(0xFF212529),
                        child: Icon(
                          Icons.play_circle_outline,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ),
          Positioned(
            left: -6,
            top: -6,
            child: Checkbox(
              value: _selected.contains(m.id),
              visualDensity: VisualDensity.compact,
              onChanged: (v) => setState(() {
                if (v == true) {
                  _selected.add(m.id);
                } else {
                  _selected.remove(m.id);
                }
              }),
            ),
          ),
          Positioned(
            right: 4,
            top: 4,
            child: Material(
              color: Brand.danger,
              borderRadius: BorderRadius.circular(4),
              child: InkWell(
                onTap: () => _deleteOne(m),
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(Icons.close, size: 14, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vis = _visible;
    final allSel =
        vis.isNotEmpty && _selected.containsAll(vis.map((m) => m.id));
    final selCount = _selected.where((id) => !_hidden.contains(id)).length;
    return WebModal(
      title: 'Edit Article',
      subtitle: 'Publication Modification Protocol',
      icon: Icons.edit_note,
      width: 980,
      actions: [
        SignalButton(
          label: 'COMMIT CHANGES TO REGISTRY',
          icon: Icons.save_outlined,
          busy: _busy,
          onPressed: _busy ? null : _submit,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const BlogLabel('Publication Headline'),
          TextField(
            controller: _title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            decoration: _titleDecoration(''),
          ),
          const SizedBox(height: 24),
          const BlogLabel('Article Payload'),
          BlogHtmlEditor(controller: _content),
          const SizedBox(height: 24),
          BlogCategoryPanel(
            service: service,
            label: 'Registry Re-Classification',
            selected: _categories,
            onChanged: (v) => setState(() => _categories = v),
            onCategoryDeleted: widget.onPostsChanged,
          ),
          const SizedBox(height: 24),
          const BlogLabel('Asset Repository'),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _MediaPicker(
                label: 'APPEND NEW ASSETS',
                count: _files.length,
                empty: 'Choose files...',
                icon: Icons.add_circle_outline,
                onPick: () async {
                  final f = await _pickFiles();
                  if (f != null && mounted) setState(() => _files = f);
                },
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: _toggleAll,
                child: Text(allSel ? 'Deselect All' : 'SELECT ALL'),
              ),
              if (selCount > 0) ...[
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Brand.danger),
                  onPressed: _deleteSelected,
                  child: Text('Delete Selected ($selCount)'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              border: Border.all(color: const Color(0xFFE2E2DE)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: vis.isEmpty
                ? const Text(
                    'No media',
                    style: TextStyle(color: Color(0xFF64748B)),
                  )
                : Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [for (final m in vis) _thumb(m)],
                  ),
          ),
        ],
      ),
    );
  }
}
