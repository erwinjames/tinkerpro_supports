import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/blog_models.dart';
import '../services/blog_service.dart';
import '../theme.dart';
import '../widgets/html_editor.dart';
import '../widgets/pick_source.dart';
import '../widgets/premium.dart';
import '../widgets/rich_html_editor.dart';

const List<HtmlTool> kBlogTools = [
  HtmlTool.bold,
  HtmlTool.italic,
  HtmlTool.underline,
  HtmlTool.strikethrough,
  HtmlTool.fontSize,
  HtmlTool.textColor,
  HtmlTool.highlight,
  HtmlTool.align,
  HtmlTool.bulletList,
  HtmlTool.numberList,
  HtmlTool.indent,
  HtmlTool.outdent,
  HtmlTool.link,
  HtmlTool.horizontalRule,
  HtmlTool.clear,
];

const List<String> kBlogColorPresets = [
  '#0C233E',
  '#FF7D00',
  '#1F2937',
  '#64748B',
  '#0EA5E9',
  '#16A34A',
  '#DC2626',
  '#7C3AED',
  '#FFFFFF',
];

String blogStampNow(DateTime value) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}:00';
}

String blogPrettyStamp(String raw) {
  final parsed = DateTime.tryParse(raw.trim().replaceFirst(' ', 'T'));
  if (parsed == null) return raw.trim();
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final hour12 = parsed.hour % 12 == 0 ? 12 : parsed.hour % 12;
  final suffix = parsed.hour < 12 ? 'AM' : 'PM';
  final minute = parsed.minute.toString().padLeft(2, '0');
  return '${months[parsed.month - 1]} ${parsed.day}, ${parsed.year} · '
      '$hour12:$minute $suffix';
}

class BlogFormScreen extends StatefulWidget {
  const BlogFormScreen({super.key, required this.service, this.existing});

  final BlogService service;
  final BlogPost? existing;

  @override
  State<BlogFormScreen> createState() => _BlogFormScreenState();
}

class _BlogFormScreenState extends State<BlogFormScreen> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _content = TextEditingController();

  List<BlogCategory> _categories = const [];
  final Set<int> _selected = <int>{};
  final List<PickedFile> _pending = [];
  List<BlogMedia> _media = const [];
  final Set<int> _markedMedia = <int>{};

  bool _loading = true;
  bool _saving = false;
  bool _showCategories = false;

  BlogPost? get _existing => widget.existing;

  bool get _isDraft => _existing?.isDraftPost ?? false;

  bool get _isEdit => _existing != null && !_isDraft;

  @override
  void initState() {
    super.initState();
    final post = _existing;
    if (post != null) {
      _title.text = post.title;
      _content.text = post.content;
      _selected.addAll(post.categories.map((c) => c.id));
      _media = post.media;
    }
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final categories = await widget.service.categories();
    BlogPost? fresh;
    final post = _existing;
    if (post != null) fresh = await widget.service.post(post.id);
    if (!mounted) return;
    setState(() {
      _categories = categories;
      _loading = false;
      if (fresh != null) {
        if (_content.text.trim().isEmpty) _content.text = fresh.content;
        _media = fresh.media;
        if (_selected.isEmpty) {
          _selected.addAll(fresh.categories.map((c) => c.id));
        }
      }
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickMedia() async {
    final picked = await pickWithSource(
      context,
      multiple: true,
      cameraLabel: 'Take a photo',
      fileLabel: 'Choose files',
      onError: _toast,
    );
    if (picked.isEmpty || !mounted) return;
    setState(() => _pending.addAll(picked));
  }

  Future<void> _newCategory() async {
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
    if (!res.ok) {
      _toast(res.message ?? 'Could not add the category.');
      return;
    }
    final categories = await widget.service.categories();
    if (!mounted) return;
    setState(() {
      _categories = categories;
      _showCategories = true;
      final match = categories.where(
        (c) => c.name.toLowerCase() == label.toLowerCase(),
      );
      if (match.isNotEmpty) _selected.add(match.first.id);
    });
  }

  Future<void> _removeMedia(BlogMedia media) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete media?'),
        content: const Text('This removes the file from the post.'),
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
    final res = await widget.service.deleteMedia(media.id);
    if (!mounted) return;
    if (!res.ok) {
      _toast(res.message ?? 'Could not delete the media.');
      return;
    }
    setState(() {
      _media = _media.where((m) => m.id != media.id).toList();
      _markedMedia.remove(media.id);
    });
  }

  Future<void> _removeMarkedMedia() async {
    if (_markedMedia.isEmpty) return;
    final ids = _markedMedia.toList();
    final res = await widget.service.deleteMediaMany(ids);
    if (!mounted) return;
    if (!res.ok) {
      _toast(res.message ?? 'Could not delete the selected media.');
      return;
    }
    setState(() {
      _media = _media.where((m) => !ids.contains(m.id)).toList();
      _markedMedia.clear();
    });
  }

  Future<DateTime?> _pickSchedule() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(hours: 1)),
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _schedule() async {
    if (!_validate()) return;
    final when = await _pickSchedule();
    if (when == null || !mounted) return;
    if (!when.isAfter(DateTime.now())) {
      _toast('Scheduled time must be in the future.');
      return;
    }
    final sendEmail = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Schedule release'),
        content: Text(
          'This post goes live on ${blogPrettyStamp(blogStampNow(when))}.\n\n'
          'Email subscribers when it publishes?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No email'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Send email'),
          ),
        ],
      ),
    );
    if (!mounted || sendEmail == null) return;
    await _submit(
      isDraft: false,
      scheduledAt: blogStampNow(when),
      sendEmail: sendEmail,
    );
  }

  bool _validate() {
    if (_title.text.trim().isEmpty) {
      _toast('Title is required.');
      return false;
    }
    if (_content.text.trim().isEmpty) {
      _toast('Content is required.');
      return false;
    }
    return true;
  }

  Future<void> _submit({
    required bool isDraft,
    String scheduledAt = '',
    bool sendEmail = false,
  }) async {
    if (!_validate()) return;
    setState(() => _saving = true);
    final paths = _pending.map((f) => f.path).toList();
    final BlogResult res;
    if (_isEdit) {
      res = await widget.service.update(
        id: _existing!.id,
        title: _title.text,
        content: _content.text,
        categoryIds: _selected.toList(),
        mediaPaths: paths,
      );
    } else {
      res = await widget.service.save(
        draftId: _isDraft ? _existing!.id : null,
        title: _title.text,
        content: _content.text,
        isDraft: isDraft,
        categoryIds: _selected.toList(),
        scheduledAt: scheduledAt,
        sendEmail: sendEmail,
        mediaPaths: paths,
      );
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.ok) {
      Navigator.of(context).pop(true);
    } else {
      _toast(res.message ?? 'Could not save the post.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final selectedNames = _categories
        .where((c) => _selected.contains(c.id))
        .map((c) => c.name)
        .toList();

    return StationScaffold(
      stationNumber: '13',
      stationLabel: 'Blog',
      title: _isEdit
          ? 'Edit article'
          : _isDraft
          ? 'Continue draft'
          : 'New publication',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      child: ListView(
        children: [
          AppCard(
            radius: Brand.radiusLg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('Headline', style: text.labelLarge),
                ),
                TextField(
                  controller: _title,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Enter publication title…',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            radius: Brand.radiusLg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('Article content', style: text.labelLarge),
                ),
                RichHtmlEditor(
                  controller: _content,
                  colorPresets: kBlogColorPresets,
                  tools: kBlogTools,
                  enabled: !_saving,
                  hintText: 'Write the article here…',
                  footnote:
                      'Photos and videos are attached below, not inside '
                      'the text.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            radius: Brand.radiusLg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(
                  title: 'Categories',
                  trailing: GhostButton(
                    label: 'New category',
                    icon: Icons.add_rounded,
                    onPressed: _newCategory,
                  ),
                ),
                if (_loading)
                  const Skeleton(height: 40)
                else ...[
                  GhostButton(
                    label: _showCategories
                        ? 'Close categories'
                        : 'Select categories',
                    icon: _showCategories
                        ? Icons.close_rounded
                        : Icons.sell_outlined,
                    onPressed: () =>
                        setState(() => _showCategories = !_showCategories),
                  ),
                  if (_showCategories) ...[
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 220),
                      decoration: BoxDecoration(
                        color: b.surfaceHi,
                        borderRadius: BorderRadius.circular(Brand.radiusSm),
                        border: Border.all(color: b.rule),
                      ),
                      child: _categories.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(14),
                              child: Text(
                                'No categories yet.',
                                style: text.bodySmall?.copyWith(
                                  color: b.paperDim,
                                ),
                              ),
                            )
                          : ListView(
                              shrinkWrap: true,
                              children: [
                                for (final category in _categories)
                                  CheckboxListTile(
                                    dense: true,
                                    value: _selected.contains(category.id),
                                    title: Text(category.name),
                                    subtitle: category.description.isEmpty
                                        ? null
                                        : Text(
                                            category.description,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                    onChanged: (on) => setState(() {
                                      if (on == true) {
                                        _selected.add(category.id);
                                      } else {
                                        _selected.remove(category.id);
                                      }
                                    }),
                                  ),
                              ],
                            ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    selectedNames.isEmpty
                        ? 'No categories selected'
                        : selectedNames.join(' · '),
                    style: text.bodySmall?.copyWith(color: b.paperDim),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            radius: Brand.radiusLg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(
                  title: 'Media',
                  trailing: GhostButton(
                    label: 'Attach',
                    icon: Icons.attach_file_rounded,
                    onPressed: _pickMedia,
                  ),
                ),
                if (_pending.isEmpty && _media.isEmpty)
                  Text(
                    'No photos or videos attached.',
                    style: text.bodySmall?.copyWith(color: b.paperDim),
                  ),
                for (final file in _pending)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.upload_file_rounded,
                      color: b.signal,
                      size: 20,
                    ),
                    title: Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: const Text('Uploads when you save'),
                    trailing: IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => setState(() => _pending.remove(file)),
                    ),
                  ),
                if (_media.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${_media.length} attached',
                          style: text.labelMedium,
                        ),
                      ),
                      if (_markedMedia.isNotEmpty)
                        TextButton.icon(
                          onPressed: _removeMarkedMedia,
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: Text('Delete ${_markedMedia.length}'),
                          style: TextButton.styleFrom(
                            foregroundColor: Brand.danger,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final media in _media)
                        BlogMediaThumb(
                          media: media,
                          headers: widget.service.mediaHeaders,
                          selected: _markedMedia.contains(media.id),
                          onTap: () => setState(() {
                            if (!_markedMedia.remove(media.id)) {
                              _markedMedia.add(media.id);
                            }
                          }),
                          onDelete: () => _removeMedia(media),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (_isEdit)
            SignalButton(
              label: 'Commit changes',
              icon: Icons.save_rounded,
              busy: _saving,
              onPressed: _saving ? null : () => _submit(isDraft: false),
            )
          else ...[
            SignalButton(
              label: 'Publish now',
              icon: Icons.send_rounded,
              busy: _saving,
              onPressed: _saving ? null : () => _submit(isDraft: false),
            ),
            const SizedBox(height: 10),
            GhostButton(
              label: _isDraft ? 'Update draft' : 'Save as draft',
              icon: Icons.drafts_outlined,
              onPressed: () {
                if (!_saving) _submit(isDraft: true);
              },
            ),
            const SizedBox(height: 10),
            GhostButton(
              label: 'Schedule release',
              icon: Icons.schedule_rounded,
              onPressed: () {
                if (!_saving) _schedule();
              },
            ),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class BlogMediaThumb extends StatelessWidget {
  const BlogMediaThumb({
    super.key,
    required this.media,
    required this.headers,
    this.selected = false,
    this.onTap,
    this.onDelete,
  });

  final BlogMedia media;
  final Map<String, String> headers;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Brand.radiusSm),
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          color: b.surfaceHi,
          borderRadius: BorderRadius.circular(Brand.radiusSm),
          border: Border.all(
            color: selected ? b.signal : b.rule,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (media.isVideo || media.url.isEmpty)
              Center(
                child: Icon(
                  media.isVideo
                      ? Icons.movie_outlined
                      : Icons.image_not_supported_outlined,
                  color: b.paperDim,
                ),
              )
            else
              CachedNetworkImage(
                imageUrl: media.url,
                httpHeaders: headers,
                fit: BoxFit.cover,
                placeholder: (_, _) => const Skeleton(height: 96),
                errorWidget: (_, _, _) =>
                    Icon(Icons.broken_image_outlined, color: b.paperDim),
              ),
            if (onDelete != null)
              Positioned(
                right: 2,
                top: 2,
                child: InkWell(
                  onTap: onDelete,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Brand.danger.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 13,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            if (selected)
              Positioned(
                left: 2,
                bottom: 2,
                child: Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: b.signal,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
