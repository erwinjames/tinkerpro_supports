import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api_client.dart';
import '../models/offer_models.dart';
import '../services/offer_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';

/// Offers — native CRUD. Searchable list of offers with thumbnails, plus a
/// create / edit form (image upload + repeatable content sections) and delete,
/// backed by the `*Offer` actions on api.php.
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await widget.service.list(search: _searchCtrl.text.trim());
    final cats =
        _categories.isEmpty ? await widget.service.listCategories() : _categories;
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
    return StationScaffold(
      stationNumber: '14',
      stationLabel: 'OFFERS',
      title: 'Offers.',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      trailing: StationAction(
        icon: Icons.add,
        tooltip: 'New offer',
        onPressed: _openForm,
      ),
      child: RefreshIndicator(
        color: Brand.signal,
        backgroundColor: Brand.surface,
        onRefresh: _load,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                controller: _searchCtrl,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _load(),
                decoration: InputDecoration(
                  labelText: 'SEARCH OFFERS',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search, color: Brand.paperDim),
                    onPressed: _load,
                  ),
                ),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Expanded(child: _buildList()),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child:
              CircularProgressIndicator(strokeWidth: 2, color: Brand.signal),
        ),
      );
    }
    if (_rows.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 64),
          EmptyState(
            label: 'No offers',
            hint: 'Tap + to create the first offer. Pull to refresh.',
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _rows.length,
      separatorBuilder: (_, _) => const Hairline(),
      itemBuilder: (_, i) => _OfferRow(
        row: _rows[i],
        service: widget.service,
        onTap: () => _openForm(_rows[i]),
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
    final url = service.imageUrl(row.image);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 52,
                height: 52,
                child: url.isEmpty
                    ? Container(
                        color: Brand.surfaceHi,
                        child: const Icon(Icons.local_offer_outlined,
                            color: Brand.paperDim, size: 20),
                      )
                    : CachedNetworkImage(
                        imageUrl: url,
                        httpHeaders: service.api.authHeaders(),
                        fit: BoxFit.cover,
                        placeholder: (_, _) =>
                            Container(color: Brand.surfaceHi),
                        errorWidget: (_, _, _) => Container(
                          color: Brand.surfaceHi,
                          child: const Icon(Icons.broken_image_outlined,
                              color: Brand.paperDim, size: 20),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.title.isEmpty ? '(untitled)' : row.title,
                    style: text.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    row.categoryName.isEmpty
                        ? (row.slug.isEmpty ? 'No category' : row.slug)
                        : row.categoryName,
                    style: text.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.chevron_right, color: Brand.paperDim, size: 20),
          ],
        ),
      ),
    );
  }
}

/// Add / edit form. Title, slug, multiline description, optional category
/// dropdown, a picked cover image, and a repeatable list of content sections.
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
  String? _imagePath; // freshly picked local file
  String _existingImage = ''; // backend path on edit
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
        _description.text =
            full.description.isNotEmpty ? full.description : _description.text;
        _existingImage = full.image;
        _sections
          ..clear()
          ..addAll(full.sections.map((s) => _SectionField(
                id: s.id,
                content: s.content,
                existingImage: s.image,
              )));
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
        .where((s) =>
            s.controller.text.trim().isNotEmpty ||
            s.existingImage.isNotEmpty ||
            s.localImagePath != null)
        .map((s) => OfferSectionInput(
              id: s.id,
              content: s.controller.text.trim(),
              existingImage: s.existingImage,
              localImagePath: s.localImagePath,
            ))
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
        backgroundColor: Brand.surface,
        title: const Text('Delete offer?'),
        content: const Text('This permanently removes the offer.'),
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
    setState(() => _saving = true);
    final res = await widget.service
        .delete(widget.existing!.id, title: widget.existing!.title);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.ok) {
      Navigator.of(context).pop(true);
    } else {
      _toast(res.message ?? 'Could not delete the offer.');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg.toUpperCase())));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return StationScaffold(
      stationNumber: '14',
      stationLabel: _isEdit ? 'EDIT OFFER' : 'NEW OFFER',
      title: _isEdit ? 'Edit offer.' : 'New offer.',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      child: _loadingDetail
          ? const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Brand.signal),
              ),
            )
          : ListView(
              children: [
                _coverPicker(text),
                const SizedBox(height: 24),
                _Field(label: 'TITLE', controller: _title),
                const SizedBox(height: 16),
                _Field(label: 'SLUG', controller: _slug),
                const SizedBox(height: 16),
                _Field(
                  label: 'DESCRIPTION',
                  controller: _description,
                  maxLines: 4,
                ),
                if (widget.categories.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _categoryDropdown(text),
                ],
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: Text('CONTENT SECTIONS', style: text.labelLarge),
                    ),
                    StationAction(
                      icon: Icons.add,
                      tooltip: 'Add section',
                      onPressed: _addSection,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < _sections.length; i++)
                  _sectionCard(i, text),
                const SizedBox(height: 32),
                SignalButton(
                  label: _isEdit ? 'Save changes' : 'Create offer',
                  busy: _saving,
                  onPressed: _saving ? null : _save,
                ),
                if (_isEdit) ...[
                  const SizedBox(height: 12),
                  GhostButton(label: 'Delete offer', onPressed: _delete),
                ],
                const SizedBox(height: 40),
              ],
            ),
    );
  }

  Widget _coverPicker(TextTheme text) {
    Widget preview;
    if (_imagePath != null) {
      preview = Image.file(File(_imagePath!), fit: BoxFit.cover);
    } else if (_existingImage.isNotEmpty) {
      preview = CachedNetworkImage(
        imageUrl: widget.service.imageUrl(_existingImage),
        httpHeaders: widget.service.api.authHeaders(),
        fit: BoxFit.cover,
        placeholder: (_, _) => Container(color: Brand.surfaceHi),
        errorWidget: (_, _, _) => const Icon(Icons.broken_image_outlined,
            color: Brand.paperDim),
      );
    } else {
      preview = const Center(
        child: Icon(Icons.add_photo_alternate_outlined,
            color: Brand.paperDim, size: 28),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('COVER IMAGE', style: text.labelLarge),
        const SizedBox(height: 8),
        InkWell(
          onTap: _pickCover,
          child: Container(
            height: 140,
            decoration: BoxDecoration(
              color: Brand.surface,
              border: Border.all(color: Brand.rule),
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            width: double.infinity,
            child: preview,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _imagePath != null
              ? 'New image selected. Tap to change.'
              : 'Tap to pick an image.',
          style: text.bodySmall,
        ),
      ],
    );
  }

  Widget _categoryDropdown(TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('CATEGORY', style: text.labelLarge),
        const SizedBox(height: 8),
        DropdownButtonFormField<int?>(
          initialValue: _categoryId,
          isExpanded: true,
          dropdownColor: Brand.surface,
          decoration: const InputDecoration(labelText: 'SELECT CATEGORY'),
          style: text.titleMedium,
          items: [
            const DropdownMenuItem<int?>(
              value: null,
              child: Text('None'),
            ),
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
    final s = _sections[index];
    final hasImage = s.localImagePath != null || s.existingImage.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Brand.surface,
        border: Border.all(color: Brand.rule),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('BLOCK #${index + 1}', style: text.labelMedium),
              ),
              if (_sections.length > 1)
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: Brand.paperDim, size: 20),
                  tooltip: 'Remove section',
                  onPressed: () => _removeSection(index),
                ),
            ],
          ),
          TextField(
            controller: s.controller,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'CONTENT'),
            style: text.titleMedium,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              GhostButton(
                label: hasImage ? 'Change image' : 'Add image',
                onPressed: () => _pickSectionImage(s),
              ),
              const SizedBox(width: 12),
              if (s.localImagePath != null)
                Text('Selected', style: text.bodySmall)
              else if (s.existingImage.isNotEmpty)
                Text('Has image', style: text.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

/// Standard labelled text field matching the app's input styling.
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
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label),
      style: Theme.of(context).textTheme.titleMedium,
    );
  }
}
