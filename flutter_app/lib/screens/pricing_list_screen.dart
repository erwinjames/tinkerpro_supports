import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api_client.dart';
import '../models/pricing_models.dart';
import '../services/pricing_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';

class PricingListScreen extends StatefulWidget {
  const PricingListScreen({
    super.key,
    required this.service,
    required this.api,
  });
  final PricingService service;
  final ApiClient api;

  @override
  State<PricingListScreen> createState() => _PricingListScreenState();
}

class _PricingListScreenState extends State<PricingListScreen> {
  final _searchController = TextEditingController();
  List<Pricing> _rows = const [];
  bool _loading = true;
  String _type = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _typeOptions {
    final seen = <String>{};
    for (final r in _rows) {
      final n = r.businessTypeName.trim();
      if (n.isNotEmpty) seen.add(n);
    }
    return ['', ...seen];
  }

  int _typeCount(String t) => t.isEmpty
      ? _rows.length
      : _rows.where((r) => r.businessTypeName.trim() == t).length;

  List<Pricing> get _visible {
    final q = _searchController.text.trim().toLowerCase();
    return _rows.where((r) {
      if (_type.isNotEmpty && r.businessTypeName.trim() != _type) {
        return false;
      }
      if (q.isEmpty) return true;
      return r.title.toLowerCase().contains(q) ||
          r.price.toLowerCase().contains(q) ||
          r.businessTypeName.toLowerCase().contains(q);
    }).toList();
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
    final b = context.brand;
    final rows = _visible;
    final types = _typeOptions;
    return StationScaffold(
      stationNumber: '13',
      stationLabel: 'Pricing',
      title: 'Pricing',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      trailing: StationAction(
        icon: Icons.add_rounded,
        tooltip: 'New plan',
        onPressed: _openForm,
      ),
      subtitle: _loading ? '' : '${_rows.length} plans',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSearchField(
            controller: _searchController,
            hint: 'Search plan, price or business type',
            onChanged: (_) => setState(() {}),
          ),
          if (!_loading && types.length > 2) ...[
            const SizedBox(height: 12),
            ChoicePills<String>(
              options: types,
              value: types.contains(_type) ? _type : '',
              onChanged: (v) => setState(() => _type = v),
              labelOf: (t) => t.isEmpty ? 'All' : t,
              countOf: _typeCount,
            ),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: RefreshIndicator(
              color: b.signal,
              backgroundColor: b.surface,
              onRefresh: _load,
              child: _loading
                  ? const SkeletonList(count: 5)
                  : rows.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 48),
                        EmptyState(
                          icon: Icons.sell_rounded,
                          label: _rows.isEmpty
                              ? 'No pricing plans'
                              : 'No matching plans',
                          hint: _rows.isEmpty
                              ? 'Tap + to add the first plan. Pull to refresh.'
                              : 'Try a different search or filter.',
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _Entry(
                        index: i,
                        child: _PricingRow(
                          row: rows[i],
                          api: widget.api,
                          onTap: () => _openForm(rows[i]),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PricingRow extends StatelessWidget {
  const _PricingRow({
    required this.row,
    required this.api,
    required this.onTap,
  });
  final Pricing row;
  final ApiClient api;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final featureCount = row.features.length;
    return AppCard(
      onTap: onTap,
      radius: Brand.radiusLg,
      borderColor: b.signal.withValues(alpha: 0.25),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          ExcludeSemantics(
            child: _ThumbFrame(
              child: _Thumb(image: row.image, api: api),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.title,
                  style: text.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                _PriceTag(value: row.price),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    StatusPill(
                      label: row.businessTypeName.isEmpty
                          ? 'No business type'
                          : row.businessTypeName,
                      color: row.businessTypeName.isEmpty
                          ? b.paperDim
                          : Brand.info,
                      icon: Icons.storefront_rounded,
                    ),
                    if (featureCount > 0)
                      StatusPill(
                        label: featureCount == 1
                            ? '1 feature'
                            : '$featureCount features',
                        color: Brand.success,
                        icon: Icons.check_rounded,
                      ),
                  ],
                ),
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

class _PriceTag extends StatelessWidget {
  const _PriceTag({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Brand.radius),
        color: b.signal.withValues(alpha: b.isDark ? 0.18 : 0.12),
        border: Border.all(color: b.signal.withValues(alpha: 0.4)),
      ),
      child: Text(
        value.isEmpty ? '—' : value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: text.titleLarge?.copyWith(
          color: b.signalInk,
          fontWeight: FontWeight.w800,
          height: 1.2,
        ),
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

class _Thumb extends StatelessWidget {
  const _Thumb({required this.image, required this.api});
  final String image;
  final ApiClient api;

  static const double _size = 72;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final placeholder = Container(
      width: _size,
      height: _size,
      color: b.tint(b.signal, 0.10),
      child: Icon(Icons.sell_rounded, size: 26, color: b.signal),
    );
    if (image.isEmpty) return placeholder;
    return CachedNetworkImage(
      imageUrl: '${api.baseUrl}/uploads/$image',
      httpHeaders: api.authHeaders(),
      width: _size,
      height: _size,
      fit: BoxFit.cover,
      fadeInDuration: MediaQuery.of(context).disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 200),
      placeholder: (_, _) =>
          const Skeleton(width: _size, height: _size, radius: 0),
      errorWidget: (_, _, _) => placeholder,
    );
  }
}

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
    final x = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 92,
    );
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
        title: const Text('Delete plan?'),
        content: const Text('This permanently removes the pricing plan.'),
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return StationScaffold(
      stationNumber: '13',
      stationLabel: 'Pricing',
      title: _isEdit ? 'Edit plan' : 'Add plan',
      subtitle: _isEdit ? widget.existing!.title : 'New pricing plan',
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
                label: _isEdit ? 'Save changes' : 'Create plan',
                icon: Icons.check_rounded,
                busy: _saving,
                onPressed: _saving || _loadingMeta ? null : _save,
              ),
            ),
          ),
        ),
      ),
      child: _loadingMeta
          ? const _FormSkeleton()
          : ListView(
              padding: const EdgeInsets.only(top: 4, bottom: 16),
              children: [
                AppCard(
                  radius: Brand.radiusLg,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _cardTitle(text, 'Plan', Icons.sell_rounded),
                      const SizedBox(height: 16),
                      _BusinessTypeDropdown(
                        types: _businessTypes,
                        value: _businessTypeId,
                        onChanged: (v) => setState(() => _businessTypeId = v),
                      ),
                      const SizedBox(height: 16),
                      _Field(label: 'Title', controller: _title),
                      const SizedBox(height: 16),
                      _Field(
                        label: 'Price',
                        controller: _price,
                        icon: Icons.payments_rounded,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
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
                      _cardTitle(text, 'Image', Icons.image_rounded),
                      const SizedBox(height: 12),
                      _ImagePickerTile(
                        picked: _pickedImage,
                        existingImage: widget.existing?.image ?? '',
                        api: widget.api,
                        onPick: _pickImage,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SectionHeader(
                  title: 'Features',
                  trailing: StationAction(
                    icon: Icons.add_rounded,
                    tooltip: 'Add feature',
                    onPressed: _addFeature,
                  ),
                ),
                if (_features.isEmpty)
                  AppCard(
                    radius: Brand.radiusLg,
                    child: Row(
                      children: [
                        const IconTile(
                          icon: Icons.checklist_rounded,
                          size: 36,
                          iconSize: 18,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'No features yet. Tap + to add one.',
                            style: text.bodySmall,
                          ),
                        ),
                      ],
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
                  const SizedBox(height: 10),
                ],
                if (_isEdit) ...[
                  const SizedBox(height: 12),
                  GhostButton(
                    label: 'Delete plan',
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
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(height: 18),
                  const Skeleton(width: 100, height: 12),
                  const SizedBox(height: 8),
                  const Skeleton(height: 48, radius: Brand.radius),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          const AppCard(
            child: Row(
              children: [
                Skeleton(width: 72, height: 72, radius: Brand.radius),
                SizedBox(width: 12),
                Expanded(child: Skeleton(height: 12)),
              ],
            ),
          ),
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
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text('Business type', style: text.labelLarge),
        ),
        DropdownButtonFormField<int>(
          initialValue: value,
          isExpanded: true,
          decoration: const InputDecoration(
            hintText: 'Select business type',
            prefixIcon: Icon(Icons.storefront_rounded),
          ),
          dropdownColor: b.surface,
          borderRadius: BorderRadius.circular(Brand.radius),
          icon: Icon(Icons.expand_more_rounded, color: b.paperDim),
          style: text.bodyLarge?.copyWith(color: b.paper),
          items: types
              .map(
                (t) => DropdownMenuItem<int>(
                  value: t.id,
                  child: Text(t.name, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ],
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
    final b = context.brand;
    Widget preview;
    if (picked != null) {
      preview = Image.file(
        File(picked!.path),
        width: 72,
        height: 72,
        fit: BoxFit.cover,
      );
    } else if (existingImage.isNotEmpty) {
      preview = CachedNetworkImage(
        imageUrl: '${api.baseUrl}/uploads/$existingImage',
        httpHeaders: api.authHeaders(),
        width: 72,
        height: 72,
        fit: BoxFit.cover,
        errorWidget: (_, _, _) => const _ImageFallback(),
      );
    } else {
      preview = const _ImageFallback();
    }

    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(Brand.radiusLg),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            _ThumbFrame(
              radius: Brand.radius,
              child: SizedBox(
                width: 72,
                height: 72,
                child: ExcludeSemantics(child: preview),
              ),
            ),
            const SizedBox(width: 12),
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
            Icon(Icons.photo_library_rounded, color: b.signal, size: 20),
          ],
        ),
      ),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback();

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Container(
      width: 72,
      height: 72,
      color: b.surfaceHi,
      child: Icon(
        Icons.add_photo_alternate_rounded,
        color: b.paperDim,
        size: 24,
      ),
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
    final b = context.brand;
    final hasCategory =
        draft.categoryId != null &&
        categories.any((c) => c.id == draft.categoryId);
    return AppCard(
      radius: Brand.radiusLg,
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: IconTile(
              icon: Icons.check_rounded,
              color: Brand.success,
              size: 32,
              iconSize: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: draft.controller,
                  decoration: const InputDecoration(hintText: 'Feature'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int?>(
                  initialValue: hasCategory ? draft.categoryId : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    hintText: 'Category (optional)',
                    isDense: true,
                  ),
                  dropdownColor: b.surface,
                  borderRadius: BorderRadius.circular(Brand.radius),
                  icon: Icon(Icons.expand_more_rounded, color: b.paperDim),
                  style: text.bodyMedium?.copyWith(color: b.paper),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('None'),
                    ),
                    ...categories.map(
                      (c) => DropdownMenuItem<int?>(
                        value: c.id,
                        child: Text(c.name, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: onCategoryChanged,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: Brand.danger,
              size: 20,
            ),
            tooltip: 'Remove feature',
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.keyboardType,
    this.icon,
  });
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final IconData? icon;

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
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: label,
            prefixIcon: icon == null ? null : Icon(icon),
          ),
        ),
      ],
    );
  }
}
