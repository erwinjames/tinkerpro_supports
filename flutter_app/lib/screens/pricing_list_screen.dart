import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api_client.dart';
import '../models/pricing_models.dart';
import '../services/pricing_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';

/// Pricing — native CRUD over the STANDALONE `pricing-facade.php` dispatcher.
/// A list of plans (title + price + business type + thumbnail) with create /
/// edit / delete. Each plan carries an image and a list of features, every
/// feature optionally tagged with a category.
class PricingListScreen extends StatefulWidget {
  const PricingListScreen({super.key, required this.service, required this.api});
  final PricingService service;
  final ApiClient api;

  @override
  State<PricingListScreen> createState() => _PricingListScreenState();
}

class _PricingListScreenState extends State<PricingListScreen> {
  List<Pricing> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await widget.service.listPricings();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _openForm([Pricing? existing]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => _PricingFormScreen(
          service: widget.service,
          api: widget.api,
          existing: existing,
        ),
      ),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return StationScaffold(
      stationNumber: '13',
      stationLabel: 'PRICING',
      title: 'Pricing.',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      trailing: StationAction(
        icon: Icons.add,
        tooltip: 'New plan',
        onPressed: _openForm,
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
                        label: 'No pricing plans',
                        hint: 'Tap + to add the first plan. Pull to refresh.',
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _rows.length,
                    separatorBuilder: (_, _) => const Hairline(),
                    itemBuilder: (_, i) => _PricingRow(
                      row: _rows[i],
                      api: widget.api,
                      onTap: () => _openForm(_rows[i]),
                    ),
                  ),
      ),
    );
  }
}

class _PricingRow extends StatelessWidget {
  const _PricingRow({required this.row, required this.api, required this.onTap});
  final Pricing row;
  final ApiClient api;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Thumb(image: row.image, api: api),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.title,
                      style: text.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Text(
                    row.businessTypeName.isEmpty
                        ? 'No business type'
                        : row.businessTypeName,
                    style: text.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              row.price.isEmpty ? '—' : row.price,
              style: text.labelLarge?.copyWith(color: Brand.signal),
            ),
          ],
        ),
      ),
    );
  }
}

/// 48x48 thumbnail. Falls back to a neutral placeholder when the plan has no
/// image or the fetch fails.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.image, required this.api});
  final String image;
  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Brand.surfaceHi,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.local_offer, size: 20, color: Brand.paperDim),
    );
    if (image.isEmpty) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: '${api.baseUrl}/uploads/$image',
        httpHeaders: api.authHeaders(),
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        placeholder: (_, _) => placeholder,
        errorWidget: (_, _, _) => placeholder,
      ),
    );
  }
}

/// Add / edit form: business type dropdown, title, price (numeric), image
/// picker, and a features editor (add/remove rows; each feature has a name +
/// optional category dropdown). Delete is available on edit.
class _PricingFormScreen extends StatefulWidget {
  const _PricingFormScreen({
    required this.service,
    required this.api,
    this.existing,
  });
  final PricingService service;
  final ApiClient api;
  final Pricing? existing;

  @override
  State<_PricingFormScreen> createState() => _PricingFormScreenState();
}

class _FeatureDraft {
  _FeatureDraft({String name = '', this.categoryId})
      : controller = TextEditingController(text: name);
  final TextEditingController controller;
  int? categoryId;
}

class _PricingFormScreenState extends State<_PricingFormScreen> {
  final _picker = ImagePicker();
  late final TextEditingController _title;
  late final TextEditingController _price;

  int? _businessTypeId;
  final List<_FeatureDraft> _features = [];

  List<BusinessType> _businessTypes = const [];
  List<PricingCategory> _categories = const [];
  bool _loadingMeta = true;

  /// Newly picked local image (null until the user picks one).
  XFile? _pickedImage;

  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _price = TextEditingController(text: e?.price ?? '');
    _businessTypeId = e?.businessTypeId == 0 ? null : e?.businessTypeId;
    if (e != null) {
      for (final f in e.features) {
        _features.add(_FeatureDraft(name: f.name, categoryId: f.categoryId));
      }
    }
    _loadMeta();
  }

  Future<void> _loadMeta() async {
    final types = await widget.service.listBusinessTypes();
    final cats = await widget.service.listCategories();
    if (!mounted) return;
    setState(() {
      _businessTypes = types;
      _categories = cats;
      // Drop a stale selection that isn't in the fetched list.
      if (_businessTypeId != null &&
          !types.any((t) => t.id == _businessTypeId)) {
        _businessTypeId = null;
      }
      _loadingMeta = false;
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _price.dispose();
    for (final f in _features) {
      f.controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage() async {
    final x = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 92);
    if (x == null || !mounted) return;
    setState(() => _pickedImage = x);
  }

  void _addFeature() {
    setState(() => _features.add(_FeatureDraft()));
  }

  void _removeFeature(int index) {
    final draft = _features.removeAt(index);
    draft.controller.dispose();
    setState(() {});
  }

  Future<void> _save() async {
    if (_businessTypeId == null) {
      _toast('Pick a business type.');
      return;
    }
    final title = _title.text.trim();
    if (title.isEmpty) {
      _toast('Title is required.');
      return;
    }
    final price = _price.text.trim();
    if (price.isEmpty) {
      _toast('Price is required.');
      return;
    }
    final features = <Map<String, dynamic>>[];
    for (final f in _features) {
      final name = f.controller.text.trim();
      if (name.isEmpty) continue;
      features.add({'name': name, 'category_id': f.categoryId});
    }

    setState(() => _saving = true);
    final PricingResult res;
    if (_isEdit) {
      res = await widget.service.update(
        id: widget.existing!.id,
        businessTypeId: _businessTypeId!,
        title: title,
        price: price,
        features: features,
        imagePath: _pickedImage?.path,
      );
    } else {
      res = await widget.service.add(
        businessTypeId: _businessTypeId!,
        title: title,
        price: price,
        features: features,
        imagePath: _pickedImage?.path,
      );
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.ok) {
      Navigator.of(context).pop(true);
    } else {
      _toast(res.message ?? 'Could not save the plan.');
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Brand.surface,
        title: const Text('Delete plan?'),
        content: const Text('This permanently removes the pricing plan.'),
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
    final res = await widget.service.delete(widget.existing!.id);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.ok) {
      Navigator.of(context).pop(true);
    } else {
      _toast(res.message ?? 'Could not delete the plan.');
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
      stationNumber: '13',
      stationLabel: _isEdit ? 'EDIT PLAN' : 'NEW PLAN',
      title: _isEdit ? 'Edit plan.' : 'Add plan.',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      child: _loadingMeta
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
                _BusinessTypeDropdown(
                  types: _businessTypes,
                  value: _businessTypeId,
                  onChanged: (v) => setState(() => _businessTypeId = v),
                ),
                const SizedBox(height: 20),
                _Field(label: 'TITLE', controller: _title),
                const SizedBox(height: 16),
                _Field(
                  label: 'PRICE',
                  controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                ),
                const SizedBox(height: 28),
                Text('IMAGE', style: text.labelLarge),
                const SizedBox(height: 12),
                _ImagePickerTile(
                  picked: _pickedImage,
                  existingImage: widget.existing?.image ?? '',
                  api: widget.api,
                  onPick: _pickImage,
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: Text('FEATURES', style: text.labelLarge),
                    ),
                    StationAction(
                      icon: Icons.add,
                      tooltip: 'Add feature',
                      onPressed: _addFeature,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_features.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No features yet. Tap + to add one.',
                      style: text.bodySmall,
                    ),
                  ),
                for (int i = 0; i < _features.length; i++) ...[
                  _FeatureEditor(
                    draft: _features[i],
                    categories: _categories,
                    onRemove: () => _removeFeature(i),
                    onCategoryChanged: (v) =>
                        setState(() => _features[i].categoryId = v),
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 24),
                SignalButton(
                  label: _isEdit ? 'Save changes' : 'Create plan',
                  busy: _saving,
                  onPressed: _saving ? null : _save,
                ),
                if (_isEdit) ...[
                  const SizedBox(height: 12),
                  GhostButton(label: 'Delete plan', onPressed: _delete),
                ],
                const SizedBox(height: 40),
              ],
            ),
    );
  }
}

class _BusinessTypeDropdown extends StatelessWidget {
  const _BusinessTypeDropdown({
    required this.types,
    required this.value,
    required this.onChanged,
  });
  final List<BusinessType> types;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'BUSINESS TYPE'),
      dropdownColor: Brand.surface,
      style: Theme.of(context).textTheme.titleMedium,
      items: types
          .map((t) => DropdownMenuItem<int>(
                value: t.id,
                child: Text(t.name, overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      onChanged: onChanged,
    );
  }
}

class _ImagePickerTile extends StatelessWidget {
  const _ImagePickerTile({
    required this.picked,
    required this.existingImage,
    required this.api,
    required this.onPick,
  });
  final XFile? picked;
  final String existingImage;
  final ApiClient api;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    Widget preview;
    if (picked != null) {
      preview = Image.file(File(picked!.path),
          width: 56, height: 56, fit: BoxFit.cover);
    } else if (existingImage.isNotEmpty) {
      preview = CachedNetworkImage(
        imageUrl: '${api.baseUrl}/uploads/$existingImage',
        httpHeaders: api.authHeaders(),
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        errorWidget: (_, _, _) => const _ImageFallback(),
      );
    } else {
      preview = const _ImageFallback();
    }

    return InkWell(
      onTap: onPick,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(width: 56, height: 56, child: preview),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              picked != null
                  ? 'New image selected. Tap to change.'
                  : (existingImage.isNotEmpty
                      ? 'Tap to replace image.'
                      : 'Tap to choose an image.'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const Icon(Icons.photo_library, color: Brand.paperDim, size: 20),
        ],
      ),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      color: Brand.surfaceHi,
      child: const Icon(Icons.image, color: Brand.paperDim, size: 22),
    );
  }
}

class _FeatureEditor extends StatelessWidget {
  const _FeatureEditor({
    required this.draft,
    required this.categories,
    required this.onRemove,
    required this.onCategoryChanged,
  });
  final _FeatureDraft draft;
  final List<PricingCategory> categories;
  final VoidCallback onRemove;
  final ValueChanged<int?> onCategoryChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final hasCategory =
        draft.categoryId != null && categories.any((c) => c.id == draft.categoryId);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
      decoration: BoxDecoration(
        border: Border.all(color: Brand.rule),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: draft.controller,
                  decoration: const InputDecoration(labelText: 'FEATURE'),
                  style: text.titleMedium,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Brand.paperDim, size: 20),
                tooltip: 'Remove feature',
                onPressed: onRemove,
              ),
            ],
          ),
          DropdownButtonFormField<int?>(
            initialValue: hasCategory ? draft.categoryId : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'CATEGORY (OPTIONAL)'),
            dropdownColor: Brand.surface,
            style: text.bodySmall,
            items: [
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('None'),
              ),
              ...categories.map((c) => DropdownMenuItem<int?>(
                    value: c.id,
                    child: Text(c.name, overflow: TextOverflow.ellipsis),
                  )),
            ],
            onChanged: onCategoryChanged,
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
    this.keyboardType,
  });
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(labelText: label),
      style: Theme.of(context).textTheme.titleMedium,
    );
  }
}
