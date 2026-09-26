import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api_client.dart';
import '../models/offer_models.dart';
import '../services/offer_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';

class OfferListScreen extends StatefulWidget {
  const OfferListScreen({super.key, required this.service, required this.api});
  final OfferService service;
  final ApiClient api;

  @override
  State<OfferListScreen> createState() => _OfferListScreenState();
}

class _OfferListScreenState extends State<OfferListScreen> {
  final _searchCtrl = TextEditingController();
  List<Offer> _rows = const [];
  List<OfferCategory> _categories = const [];
  bool _loading = true;
  int? _category;

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<int?> get _categoryOptions => [
    null,
    ..._categories
        .map((c) => c.id)
        .where((id) => _rows.any((r) => r.categoryId == id)),
  ];

  String _categoryLabel(int? id) {
    if (id == null) return 'All';
    for (final c in _categories) {
      if (c.id == id) return c.name;
    }
    return 'Category';
  }

  int _categoryCount(int? id) =>
      id == null ? _rows.length : _rows.where((r) => r.categoryId == id).length;

  List<Offer> get _visible => _category == null
      ? _rows
      : _rows.where((r) => r.categoryId == _category).toList();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await widget.service.list(search: _searchCtrl.text.trim());
    final cats = _categories.isEmpty
        ? await widget.service.listCategories()
        : _categories;
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _categories = cats;
      _loading = false;
    });
  }

  Future<void> _openForm([Offer? existing]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => _OfferFormScreen(
          service: widget.service,
          categories: _categories,
          existing: existing,
        ),
      ),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return StationScaffold(
      stationNumber: '14',
      stationLabel: 'Offers',
      title: 'Offers',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      trailing: StationAction(
        icon: Icons.add_rounded,
        tooltip: 'New offer',
        onPressed: _openForm,
      ),
      subtitle: _loading ? '' : '${_rows.length} offers',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSearchField(
            controller: _searchCtrl,
            hint: 'Search offers',
            onSubmitted: (_) => _load(),
            onChanged: (v) {
              if (v.isEmpty) _load();
            },
          ),
          if (!_loading && _categoryOptions.length > 2) ...[
            const SizedBox(height: 12),
            ChoicePills<int?>(
              options: _categoryOptions,
              value: _categoryOptions.contains(_category) ? _category : null,
              onChanged: (v) => setState(() => _category = v),
              labelOf: _categoryLabel,
              countOf: _categoryCount,
            ),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: RefreshIndicator(
              color: b.signal,
              backgroundColor: b.surface,
              onRefresh: _load,
              child: _buildList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const SkeletonList(count: 6);
    }
    final rows = _visible;
    if (rows.isEmpty) {
      final searching = _searchCtrl.text.trim().isNotEmpty;
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 48),
          EmptyState(
            icon: Icons.local_offer_rounded,
            label: searching ? 'No matching offers' : 'No offers',
            hint: searching
                ? 'Try a different search.'
                : 'Tap + to create the first offer. Pull to refresh.',
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _Entry(
        index: i,
        child: _OfferRow(
          row: rows[i],
          service: widget.service,
          onTap: () => _openForm(rows[i]),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.url,
    required this.headers,
    required this.fallbackIcon,
    this.size = 64,
  });
  final String url;
  final Map<String, String> headers;
  final IconData fallbackIcon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    Widget box(IconData icon) => Container(
      color: b.surfaceHi,
      alignment: Alignment.center,
      child: Icon(icon, color: b.paperDim, size: size * 0.36),
    );
    return _ThumbFrame(
      radius: size >= 64 ? Brand.radiusLg : Brand.radius,
      child: SizedBox(
        width: size,
        height: size,
        child: url.isEmpty
            ? box(fallbackIcon)
            : CachedNetworkImage(
                imageUrl: url,
                httpHeaders: headers,
                fit: BoxFit.cover,
                fadeInDuration: MediaQuery.of(context).disableAnimations
                    ? Duration.zero
                    : const Duration(milliseconds: 200),
                placeholder: (_, _) =>
                    Skeleton(width: size, height: size, radius: 0),
                errorWidget: (_, _, _) => box(Icons.broken_image_rounded),
              ),
      ),
    );
  }
}

class _OfferRow extends StatelessWidget {
  const _OfferRow({
    required this.row,
    required this.service,
    required this.onTap,
  });
  final Offer row;
  final OfferService service;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final url = service.imageUrl(row.image);
    final desc = row.description.trim().isNotEmpty
        ? row.description.trim().replaceAll(RegExp(r'\s+'), ' ')
        : (row.slug.isEmpty ? 'No description' : '/${row.slug}');
    return AppCard(
      onTap: onTap,
      radius: Brand.radiusLg,
      borderColor: b.signal.withValues(alpha: 0.25),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          ExcludeSemantics(
            child: _Thumb(
              url: url,
              headers: service.api.authHeaders(),
              fallbackIcon: Icons.local_offer_rounded,
              size: 72,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.title.isEmpty ? '(untitled)' : row.title,
                  style: text.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: text.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (row.categoryName.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  GlowBadge(
                    label: row.categoryName,
                    color: b.signal,
                    icon: Icons.sell_rounded,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded, color: b.paperDim, size: 20),
        ],
      ),
    );
  }
}

class _ThumbFrame extends StatelessWidget {
  const _ThumbFrame({required this.child, this.radius = Brand.radiusLg});

  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        color: b.surfaceHi,
        border: Border.all(color: b.rule),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return child;
    final start = (index.clamp(0, 5)) * 0.12;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 400),
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class _OfferFormScreen extends StatefulWidget {
  const _OfferFormScreen({
    required this.service,
    required this.categories,
    this.existing,
  });
  final OfferService service;
  final List<OfferCategory> categories;
  final Offer? existing;

  @override
  State<_OfferFormScreen> createState() => _OfferFormScreenState();
}

class _SectionField {
  _SectionField({this.id, String content = '', this.existingImage = ''})
    : controller = TextEditingController(text: content);
  final int? id;
  final TextEditingController controller;
  final String existingImage;
  String? localImagePath;
}

class _OfferFormScreenState extends State<_OfferFormScreen> {
  final _picker = ImagePicker();
  late final TextEditingController _title;
  late final TextEditingController _slug;
  late final TextEditingController _description;
  int? _categoryId;
  String? _imagePath;
  String _existingImage = '';
  final List<_SectionField> _sections = [];
  bool _saving = false;
  bool _loadingDetail = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _slug = TextEditingController(text: e?.slug ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _categoryId = e?.categoryId;
    _existingImage = e?.image ?? '';
    if (_isEdit) {
      _loadDetail();
    } else {
      _sections.add(_SectionField());
    }
  }

  Future<void> _loadDetail() async {
    setState(() => _loadingDetail = true);
    final full = await widget.service.detail(widget.existing!.id);
    if (!mounted) return;
    setState(() {
      if (full != null) {
        _description.text = full.description.isNotEmpty
            ? full.description
            : _description.text;
        _existingImage = full.image;
        _sections
          ..clear()
          ..addAll(
            full.sections.map(
              (s) => _SectionField(
                id: s.id,
                content: s.content,
                existingImage: s.image,
              ),
            ),
          );
      }
      if (_sections.isEmpty) _sections.add(_SectionField());
      _loadingDetail = false;
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _slug.dispose();
    _description.dispose();
    for (final s in _sections) {
      s.controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickCover() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    if (!mounted) return;
    setState(() => _imagePath = picked.path);
  }

  Future<void> _pickSectionImage(_SectionField s) async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    if (!mounted) return;
    setState(() => s.localImagePath = picked.path);
  }

  void _addSection() {
    setState(() => _sections.add(_SectionField()));
  }

  void _removeSection(int index) {
    setState(() {
      _sections[index].controller.dispose();
      _sections.removeAt(index);
    });
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      _toast('Title is required.');
      return;
    }
    if (_slug.text.trim().isEmpty) {
      _toast('Slug is required.');
      return;
    }
    final sections = _sections
        .where(
          (s) =>
              s.controller.text.trim().isNotEmpty ||
              s.existingImage.isNotEmpty ||
              s.localImagePath != null,
        )
        .map(
          (s) => OfferSectionInput(
            id: s.id,
            content: s.controller.text.trim(),
            existingImage: s.existingImage,
            localImagePath: s.localImagePath,
          ),
        )
        .toList();

    setState(() => _saving = true);
    final OfferResult res;
    if (_isEdit) {
      res = await widget.service.update(
        id: widget.existing!.id,
        title: title,
        slug: _slug.text.trim(),
        description: _description.text.trim(),
        categoryId: _categoryId,
        sections: sections,
        imagePath: _imagePath,
      );
    } else {
      res = await widget.service.add(
        title: title,
        slug: _slug.text.trim(),
        description: _description.text.trim(),
        categoryId: _categoryId,
        sections: sections,
        imagePath: _imagePath,
      );
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.ok) {
      Navigator.of(context).pop(true);
    } else {
      _toast(res.message ?? 'Could not save the offer.');
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete offer?'),
        content: const Text('This permanently removes the offer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Brand.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    final res = await widget.service.delete(
      widget.existing!.id,
      title: widget.existing!.title,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.ok) {
      Navigator.of(context).pop(true);
    } else {
      _toast(res.message ?? 'Could not delete the offer.');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return StationScaffold(
      stationNumber: '14',
      stationLabel: 'Offers',
      title: _isEdit ? 'Edit offer' : 'New offer',
      subtitle: _isEdit ? widget.existing!.title : 'Create a new offer',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      bottomBar: Material(
        color: b.surface,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: b.rule)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: SignalButton(
                label: _isEdit ? 'Save changes' : 'Create offer',
                icon: Icons.check_rounded,
                busy: _saving,
                onPressed: _saving || _loadingDetail ? null : _save,
              ),
            ),
          ),
        ),
      ),
      child: _loadingDetail
          ? const _FormSkeleton()
          : ListView(
              padding: const EdgeInsets.only(top: 4, bottom: 16),
              children: [
                _coverPicker(text),
                const SizedBox(height: 12),
                AppCard(
                  radius: Brand.radiusLg,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _cardTitle(text, 'Details', Icons.article_rounded),
                      const SizedBox(height: 16),
                      _Field(label: 'Title', controller: _title),
                      const SizedBox(height: 16),
                      _Field(label: 'Slug', controller: _slug),
                      const SizedBox(height: 16),
                      _Field(
                        label: 'Description',
                        controller: _description,
                        maxLines: 4,
                      ),
                      if (widget.categories.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _categoryDropdown(text),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SectionHeader(
                  title: 'Content sections',
                  trailing: StationAction(
                    icon: Icons.add_rounded,
                    tooltip: 'Add section',
                    onPressed: _addSection,
                  ),
                ),
                for (var i = 0; i < _sections.length; i++)
                  _sectionCard(i, text),
                if (_isEdit) ...[
                  const SizedBox(height: 4),
                  GhostButton(
                    label: 'Delete offer',
                    icon: Icons.delete_outline_rounded,
                    onPressed: _delete,
                  ),
                ],
              ],
            ),
    );
  }

  Widget _cardTitle(TextTheme text, String title, IconData icon) {
    return Row(
      children: [
        IconTile(icon: icon, size: 30, iconSize: 16),
        const SizedBox(width: 10),
        Expanded(child: Text(title, style: text.titleMedium)),
      ],
    );
  }

  Widget _coverPicker(TextTheme text) {
    final b = context.brand;
    Widget preview;
    if (_imagePath != null) {
      preview = Image.file(File(_imagePath!), fit: BoxFit.cover);
    } else if (_existingImage.isNotEmpty) {
      preview = CachedNetworkImage(
        imageUrl: widget.service.imageUrl(_existingImage),
        httpHeaders: widget.service.api.authHeaders(),
        fit: BoxFit.cover,
        placeholder: (_, _) => Container(color: b.surfaceHi),
        errorWidget: (_, _, _) =>
            Icon(Icons.broken_image_rounded, color: b.paperDim),
      );
    } else {
      preview = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconTile(icon: Icons.add_photo_alternate_rounded, color: b.signal),
          const SizedBox(height: 8),
          Text('Add a cover image', style: text.labelLarge),
        ],
      );
    }
    return AppCard(
      radius: Brand.radiusLg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(text, 'Cover image', Icons.image_rounded),
          const SizedBox(height: 12),
          Semantics(
            button: true,
            label: 'Pick cover image',
            child: _ThumbFrame(
              child: Material(
                color: b.surfaceHi,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _pickCover,
                  child: SizedBox(
                    height: 170,
                    width: double.infinity,
                    child: ExcludeSemantics(child: preview),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _imagePath != null
                ? 'New image selected. Tap to change.'
                : 'Tap to pick an image.',
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _categoryDropdown(TextTheme text) {
    final b = context.brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text('Category', style: text.labelLarge),
        ),
        DropdownButtonFormField<int?>(
          initialValue: _categoryId,
          isExpanded: true,
          dropdownColor: b.surface,
          borderRadius: BorderRadius.circular(Brand.radius),
          icon: Icon(Icons.expand_more_rounded, color: b.paperDim),
          decoration: const InputDecoration(
            hintText: 'Select category',
            prefixIcon: Icon(Icons.category_rounded),
          ),
          style: text.bodyLarge?.copyWith(color: b.paper),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('None')),
            ...widget.categories.map(
              (c) => DropdownMenuItem<int?>(
                value: c.id,
                child: Text(c.name, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
          onChanged: (v) => setState(() => _categoryId = v),
        ),
      ],
    );
  }

  Widget _sectionCard(int index, TextTheme text) {
    final b = context.brand;
    final s = _sections[index];
    final hasImage = s.localImagePath != null || s.existingImage.isNotEmpty;
    Widget? thumb;
    if (s.localImagePath != null) {
      thumb = _ThumbFrame(
        radius: Brand.radius,
        child: Image.file(
          File(s.localImagePath!),
          width: 44,
          height: 44,
          fit: BoxFit.cover,
        ),
      );
    } else if (s.existingImage.isNotEmpty) {
      thumb = _Thumb(
        url: widget.service.imageUrl(s.existingImage),
        headers: widget.service.api.authHeaders(),
        fallbackIcon: Icons.image_rounded,
        size: 44,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        radius: Brand.radiusLg,
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                StatusPill(label: 'Block ${index + 1}', color: b.signal),
                const Spacer(),
                if (_sections.length > 1)
                  IconButton(
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      color: Brand.danger,
                      size: 20,
                    ),
                    tooltip: 'Remove section',
                    onPressed: () => _removeSection(index),
                  )
                else
                  const SizedBox(height: 48),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: TextField(
                controller: s.controller,
                maxLines: 4,
                decoration: const InputDecoration(hintText: 'Content'),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (thumb != null) ...[thumb, const SizedBox(width: 12)],
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(44, 44),
                  ),
                  onPressed: () => _pickSectionImage(s),
                  icon: Icon(
                    hasImage
                        ? Icons.swap_horiz_rounded
                        : Icons.add_photo_alternate_rounded,
                    size: 18,
                  ),
                  label: Text(hasImage ? 'Change image' : 'Add image'),
                ),
                const SizedBox(width: 12),
                if (s.localImagePath != null)
                  const StatusPill(label: 'Selected', color: Brand.success)
                else if (s.existingImage.isNotEmpty)
                  Text('Has image', style: text.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.maxLines = 1,
  });
  final String label;
  final TextEditingController controller;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(label, style: Theme.of(context).textTheme.labelLarge),
        ),
        TextField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(hintText: label),
        ),
      ],
    );
  }
}

class _FormSkeleton extends StatelessWidget {
  const _FormSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        children: [
          const AppCard(
            radius: Brand.radiusLg,
            child: Skeleton(height: 190, radius: Brand.radius),
          ),
          const SizedBox(height: 12),
          AppCard(
            radius: Brand.radiusLg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(height: 18),
                  const Skeleton(width: 90, height: 12),
                  const SizedBox(height: 8),
                  Skeleton(height: i == 2 ? 96 : 48, radius: Brand.radius),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
