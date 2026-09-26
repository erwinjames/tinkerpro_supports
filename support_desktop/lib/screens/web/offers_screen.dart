import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../api_client.dart';
import '../../services/live_sync.dart';
import '../../services/offers_service.dart';
import '../../theme.dart';
import '../../widgets/premium.dart';
import '../admin/admin_list.dart';
import 'op_page_header.dart';
import '../../widgets/tp_loader.dart';

Future<bool> _undoWindow(BuildContext context, String message) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  final reason = await messenger
      .showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 5),
          persist: false,
          action: SnackBarAction(label: 'Undo', onPressed: () {}),
        ),
      )
      .closed;
  return reason != SnackBarClosedReason.action;
}

class _ServerSlug {
  _ServerSlug(this.service, this.target);
  final OffersService service;
  final TextEditingController target;
  Timer? _timer;
  int _seq = 0;

  void update(String text) {
    _timer?.cancel();
    final seq = ++_seq;
    _timer = Timer(const Duration(milliseconds: 180), () async {
      final slug = await service.slugify(text);
      if (slug != null && seq == _seq) target.text = slug;
    });
  }

  void dispose() {
    _timer?.cancel();
    _seq++;
  }
}

String _plainText(String html) => html
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .trim();

Future<String?> _pickImage() async {
  final picked = await FilePicker.platform.pickFiles(type: FileType.image);
  if (picked == null || picked.files.isEmpty) return null;
  return picked.files.single.path;
}

String _fileName(String path) => path.split(RegExp(r'[\\/]')).last;

class OffersScreen extends StatefulWidget {
  const OffersScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends State<OffersScreen>
    with LiveRefresh<OffersScreen> {
  late final OffersService _service = OffersService(widget.api);
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  List<OfferCategory> _categories = const [];
  int? _categoryId;
  bool _withPackagesOnly = false;
  int _page = 1;
  int _pageSize = 15;
  List<Offer> _items = const [];
  int _total = 0;
  bool _loading = true;
  String? _error;
  final Set<int> _expanded = {};
  final Set<int> _pendingDelete = {};

  int get _lastPage =>
      _total == 0 ? 1 : ((_total + _pageSize - 1) ~/ _pageSize);

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final cats = await _service.categories();
      if (!mounted) return;
      setState(() {
        _categories = cats;
        if (_categoryId != null && !cats.any((c) => c.id == _categoryId)) {
          _categoryId = null;
        }
      });
    } catch (_) {}
  }

  @override
  List<String> get liveKeys => const ['offers'];

  @override
  void onLiveChange() {
    _loadCategories();
    _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final key = (
      _page,
      _pageSize,
      _searchCtrl.text.trim(),
      _categoryId,
      _withPackagesOnly,
    );
    try {
      final page = await _service.list(
        page: key.$1,
        limit: key.$2,
        search: key.$3,
        categoryId: key.$4,
        withPackagesOnly: key.$5,
      );
      if (!mounted) return;
      if (silent &&
          key !=
              (
                _page,
                _pageSize,
                _searchCtrl.text.trim(),
                _categoryId,
                _withPackagesOnly,
              )) {
        return;
      }
      setState(() {
        _items = page.items;
        _total = page.total;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || silent) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _resetAndLoad() {
    _page = 1;
    _load();
  }

  void _onSearchChanged(String _) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _resetAndLoad);
  }

  Future<void> _openOfferForm({Offer? existing}) async {
    Offer? full;
    if (existing != null) {
      try {
        full = await _service.getById(existing.id);
      } catch (_) {}
      if (!mounted) return;
      if (full == null) {
        toast(context, 'Could not load offer');
        return;
      }
    }
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _OfferFormDialog(
        service: _service,
        categories: _categories,
        existing: full,
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _openPackages(Offer offer) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _PackagesDialog(service: _service, offer: offer),
    );
    if (changed == true) _load();
  }

  Future<void> _openCategories() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CategoriesDialog(
        service: _service,
        onChanged: () {
          _loadCategories();
          _load();
        },
      ),
    );
  }

  Future<void> _deleteOffer(Offer offer) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete this offer?',
      message:
          'The offer and any attached package references will be permanently removed.',
      confirmLabel: 'Delete offer',
    );
    if (!ok || !mounted) return;
    setState(() => _pendingDelete.add(offer.id));
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final reason = await messenger
        .showSnackBar(
          SnackBar(
            content: const Text('Offer deleted'),
            duration: const Duration(seconds: 5),
            persist: false,
            action: SnackBarAction(label: 'Undo', onPressed: () {}),
          ),
        )
        .closed;
    if (reason == SnackBarClosedReason.action) {
      if (mounted) setState(() => _pendingDelete.remove(offer.id));
      return;
    }
    final res = await _service.deleteOffer(offer.id);
    if (!mounted) return;
    _pendingDelete.remove(offer.id);
    if (!res.ok) toast(context, res.message);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return OpPage(
      header: OpPageHeader(
        eyebrow: 'Marketing & Growth',
        title: 'Offers Management',
        actions: [
          OpPillButton(
            label: 'Manage Categories',
            icon: Icons.view_list,
            onPressed: _openCategories,
          ),
          OpPillButton(
            label: 'Add New Offer',
            icon: Icons.add,
            primary: true,
            onPressed: () => _openOfferForm(),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _filterBar(),
          const SizedBox(height: 24),
          Expanded(child: _table()),
        ],
      ),
    );
  }

  InputDecoration _pillDecoration({
    String? hint,
    Widget? prefix,
    Widget? suffix,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(99),
      borderSide: BorderSide(color: context.brand.rule),
    );
    return InputDecoration(
      isDense: true,
      hintText: hint,
      prefixIcon: prefix,
      suffixIcon: suffix,
      filled: true,
      fillColor: context.brand.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: Brand.signal),
      ),
    );
  }

  Widget _filterBar() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.brand.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.brand.rule),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<int?>(
              initialValue: _categoryId,
              isDense: true,
              isExpanded: true,
              icon: const Icon(
                Icons.keyboard_arrow_down,
                size: 18,
                color: Brand.signal,
              ),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.brand.paper,
              ),
              decoration: _pillDecoration(),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('All categories'),
                ),
                for (final c in _categories)
                  DropdownMenuItem<int?>(value: c.id, child: Text(c.name)),
              ],
              onChanged: (v) {
                setState(() => _categoryId = v);
                _resetAndLoad();
              },
            ),
          ),
          const SizedBox(width: 16),
          Transform.scale(
            scale: 0.8,
            child: Switch(
              value: _withPackagesOnly,
              activeTrackColor: Brand.signal,
              onChanged: (v) {
                setState(() => _withPackagesOnly = v);
                _resetAndLoad();
              },
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'With Packages Only',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: context.brand.paper,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: 320,
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              onSubmitted: (_) => _resetAndLoad(),
              style: const TextStyle(fontSize: 14),
              decoration: _pillDecoration(
                hint: 'Search title, description or slug...',
                prefix: Icon(
                  Icons.search,
                  size: 17,
                  color: context.brand.paperDim,
                ),
                suffix: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {});
                          _resetAndLoad();
                        },
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _table() {
    final visible = _items
        .where((o) => !_pendingDelete.contains(o.id))
        .toList();
    return OpPanel(
      child: ColumnResizeScope(
        tableId: 'offers:offers',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const WebTableHeader(
              cells: [
                SizedBox(width: 60, child: Text('ID')),
                SizedBox(width: 100, child: Text('IMAGE')),
                Expanded(flex: 3, child: Text('OFFER TITLE')),
                Expanded(flex: 4, child: Text('DESCRIPTION')),
                SizedBox(
                  width: 150,
                  child: Text('ACTIONS', textAlign: TextAlign.right),
                ),
              ],
            ),
            Expanded(child: _tableBody(visible)),
            _pager(),
          ],
        ),
      ),
    );
  }

  Widget _tableBody(List<Offer> visible) {
    if (_loading) {
      return const Center(child: TpLoader());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Could not load offers',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            GhostButton(label: 'Retry', icon: Icons.refresh, onPressed: _load),
          ],
        ),
      );
    }
    if (visible.isEmpty) {
      return const EmptyState(
        label: 'No offers found',
        hint: 'Adjust the filters or add one.',
      );
    }
    return ListView.builder(
      itemCount: visible.length,
      itemBuilder: (context, i) => _row(visible[i]),
    );
  }

  Widget _row(Offer o) {
    final text = Theme.of(context).textTheme;
    final expanded = _expanded.contains(o.id);
    final plain = _plainText(o.description);
    final short = plain.length > 80 ? '${plain.substring(0, 80)}...' : plain;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WebTableRow(
          onTap: () => _openOfferForm(existing: o),
          cells: [
            SizedBox(
              width: 60,
              child: Text(
                '${o.id}',
                style: text.bodySmall?.copyWith(fontFamily: 'monospace'),
              ),
            ),
            SizedBox(
              width: 100,
              child: Align(
                alignment: Alignment.center,
                child: _Thumb(
                  url: _service.mediaUrl(o.image),
                  headers: widget.api.authHeaders(),
                  width: 60,
                  height: 40,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  IconButton(
                    tooltip: expanded ? 'Hide details' : 'Show details',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      expanded
                          ? Icons.remove_circle_outline
                          : Icons.add_circle_outline,
                      size: 18,
                      color: context.brand.paperDim,
                    ),
                    onPressed: () => setState(() {
                      expanded ? _expanded.remove(o.id) : _expanded.add(o.id);
                    }),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          o.title,
                          style: text.titleSmall?.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (o.categoryName.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            o.categoryName.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: Brand.signal,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text(
                  short,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(
                    color: context.brand.paperDim,
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 150,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedIconButton(
                    icon: Icons.edit_outlined,
                    tooltip: 'Edit',
                    color: const Color(0xFF17A2B8),
                    onPressed: () => _openOfferForm(existing: o),
                  ),
                  const SizedBox(width: 6),
                  OutlinedIconButton(
                    icon: Icons.inventory_2_outlined,
                    tooltip: 'Packages',
                    color: const Color(0xFFFFC107),
                    onPressed: () => _openPackages(o),
                  ),
                  const SizedBox(width: 6),
                  OutlinedIconButton(
                    icon: Icons.delete_outline,
                    tooltip: 'Delete',
                    color: Brand.danger,
                    onPressed: () => _deleteOffer(o),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (expanded)
          Container(
            padding: const EdgeInsets.fromLTRB(172, 12, 20, 16),
            decoration: BoxDecoration(
              color: context.brand.surfaceHi,
              border: Border(bottom: BorderSide(color: context.brand.rule)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                plain.isEmpty
                    ? Text(
                        'No description',
                        style: text.bodySmall?.copyWith(
                          fontStyle: FontStyle.italic,
                          color: context.brand.paperDim,
                        ),
                      )
                    : SelectableText(
                        plain,
                        style: text.bodyMedium?.copyWith(height: 1.6),
                      ),
                const SizedBox(height: 10),
                GhostButton(
                  label: 'Manage packages',
                  icon: Icons.inventory_2_outlined,
                  onPressed: () => _openPackages(o),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _pager() {
    final text = Theme.of(context).textTheme;
    final from = _total == 0 ? 0 : (_page - 1) * _pageSize + 1;
    final to = (_page * _pageSize).clamp(0, _total);
    void go(int p) {
      _page = p;
      _load();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: context.brand.surfaceHi,
        border: Border(top: BorderSide(color: context.brand.rule)),
      ),
      child: Row(
        children: [
          Text(
            'Page Size',
            style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 84,
            child: DropdownButtonFormField<int>(
              initialValue: _pageSize,
              isDense: true,
              decoration: const InputDecoration(isDense: true),
              items: const [15, 20, 25, 30]
                  .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _pageSize = v);
                _resetAndLoad();
              },
            ),
          ),
          const SizedBox(width: 16),
          Text('Showing $from–$to of $_total', style: text.bodySmall),
          const Spacer(),
          _PagerButton(
            label: 'First',
            onPressed: _page > 1 ? () => go(1) : null,
          ),
          _PagerButton(
            label: 'Prev',
            onPressed: _page > 1 ? () => go(_page - 1) : null,
          ),
          _PagerButton(label: '$_page', active: true, onPressed: () {}),
          _PagerButton(
            label: 'Next',
            onPressed: _page < _lastPage ? () => go(_page + 1) : null,
          ),
          _PagerButton(
            label: 'Last',
            onPressed: _page < _lastPage ? () => go(_lastPage) : null,
          ),
        ],
      ),
    );
  }
}

class _PagerButton extends StatelessWidget {
  const _PagerButton({
    required this.label,
    required this.onPressed,
    this.active = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: InkWell(
        mouseCursor: enabled && !active
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onTap: active ? null : onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          constraints: const BoxConstraints(minWidth: 34),
          height: 34,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: active ? Brand.signal : context.brand.surface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: active ? Brand.signal : context.brand.rule,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: active ? FontWeight.w700 : FontWeight.w400,
              color: active
                  ? Colors.white
                  : enabled
                  ? context.brand.paper
                  : context.brand.paperDim,
            ),
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.url,
    required this.headers,
    this.width = 64,
    this.height = 42,
  });

  final String url;
  final Map<String, String> headers;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.brand.surfaceHi,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.brand.rule),
      ),
      child: Text(
        'NO IMG',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: context.brand.paperDim,
        ),
      ),
    );
    if (url.isEmpty) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        url,
        headers: headers,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder,
      ),
    );
  }
}

class _DialogShell extends StatelessWidget {
  const _DialogShell({
    required this.title,
    required this.icon,
    required this.child,
    this.subtitle,
    this.actions = const [],
    this.width = 900,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;
  final List<Widget> actions;
  final double width;

  @override
  Widget build(BuildContext context) {
    return WebModal(
      title: title,
      subtitle: subtitle,
      icon: icon,
      width: width,
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      actions: actions,
      child: child,
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label, {this.trailing});
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _ImagePickerField extends StatelessWidget {
  const _ImagePickerField({
    required this.existingUrl,
    required this.localPath,
    required this.headers,
    required this.onPick,
    this.onClear,
  });

  final String existingUrl;
  final String? localPath;
  final Map<String, String> headers;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GhostButton(
          label: 'Choose image',
          icon: Icons.image_outlined,
          onPressed: onPick,
        ),
        const SizedBox(width: 12),
        if (localPath != null) ...[
          Flexible(
            child: Text(
              _fileName(localPath!),
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall,
            ),
          ),
          if (onClear != null)
            IconButton(
              tooltip: 'Remove selection',
              visualDensity: VisualDensity.compact,
              onPressed: onClear,
              icon: const Icon(Icons.close, size: 16),
            ),
        ] else if (existingUrl.isNotEmpty)
          _Thumb(url: existingUrl, headers: headers, width: 110, height: 70)
        else
          Text(
            'No file chosen',
            style: text.bodySmall?.copyWith(color: context.brand.paperDim),
          ),
      ],
    );
  }
}

class _EditableList extends StatelessWidget {
  const _EditableList({
    required this.controllers,
    required this.hint,
    required this.onRemove,
  });

  final List<TextEditingController> controllers;
  final String hint;
  final void Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < controllers.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controllers[i],
                    decoration: InputDecoration(isDense: true, hintText: hint),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  onPressed: () => onRemove(i),
                  icon: const Icon(Icons.close, size: 16, color: Brand.danger),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SectionDraft {
  _SectionDraft({this.id, String content = '', this.existingImage = ''})
    : ctrl = TextEditingController(text: content);

  final int? id;
  final TextEditingController ctrl;
  final String existingImage;
  String? localImage;
}

class _OfferFormDialog extends StatefulWidget {
  const _OfferFormDialog({
    required this.service,
    required this.categories,
    this.existing,
  });

  final OffersService service;
  final List<OfferCategory> categories;
  final Offer? existing;

  @override
  State<_OfferFormDialog> createState() => _OfferFormDialogState();
}

class _OfferFormDialogState extends State<_OfferFormDialog> {
  final _title = TextEditingController();
  final _slug = TextEditingController();
  late final _slugger = _ServerSlug(widget.service, _slug);
  int? _categoryId;
  String? _imagePath;
  final List<TextEditingController> _forYou = [];
  final List<TextEditingController> _notForYou = [];
  final List<_SectionDraft> _sections = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final o = widget.existing;
    if (o == null) {
      _sections.add(_SectionDraft());
      _forYou.add(TextEditingController());
      _notForYou.add(TextEditingController());
      return;
    }
    _title.text = o.title;
    _slug.text = o.slug;
    _categoryId = widget.categories.any((c) => c.id == o.categoryId)
        ? o.categoryId
        : null;
    if (o.sections.isNotEmpty) {
      for (final s in o.sections) {
        _sections.add(
          _SectionDraft(id: s.id, content: s.content, existingImage: s.image),
        );
      }
    } else {
      _sections.add(_SectionDraft(content: o.description));
    }
    _forYou.addAll(o.forYou.map((e) => TextEditingController(text: e)));
    if (_forYou.isEmpty) _forYou.add(TextEditingController());
    _notForYou.addAll(o.notForYou.map((e) => TextEditingController(text: e)));
    if (_notForYou.isEmpty) _notForYou.add(TextEditingController());
  }

  @override
  void dispose() {
    _slugger.dispose();
    _title.dispose();
    _slug.dispose();
    for (final c in [..._forYou, ..._notForYou]) {
      c.dispose();
    }
    for (final s in _sections) {
      s.ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final slug = _slug.text.trim();
    if (title.isEmpty || slug.isEmpty) {
      toast(context, 'Title and slug are required.');
      return;
    }
    setState(() => _saving = true);
    final res = await widget.service.saveOffer(
      id: widget.existing?.id,
      title: title,
      slug: slug,
      categoryId: _categoryId,
      forYou: _forYou
          .map((c) => c.text.trim())
          .where((v) => v.isNotEmpty)
          .toList(),
      notForYou: _notForYou
          .map((c) => c.text.trim())
          .where((v) => v.isNotEmpty)
          .toList(),
      sections: [
        for (final s in _sections)
          OfferSectionInput(
            id: s.id,
            content: s.ctrl.text,
            existingImage: s.existingImage,
            localImagePath: s.localImage,
          ),
      ],
      imagePath: _imagePath,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    toast(context, res.message);
    if (res.ok) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    final headers = widget.service.api.authHeaders();
    return _DialogShell(
      title: editing ? 'Edit Offer' : 'Add New Offer',
      subtitle: 'Inventory catalog',
      icon: editing ? Icons.edit_outlined : Icons.add_circle_outline,
      width: 1000,
      actions: [
        GhostButton(
          label: 'Cancel',
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
        ),
        SignalButton(
          label: 'Save Offer',
          icon: Icons.save_outlined,
          busy: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _FieldLabel('Title'),
                      TextField(
                        controller: _title,
                        autofocus: !editing,
                        decoration: const InputDecoration(isDense: true),
                        onChanged: _slugger.update,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _FieldLabel('Slug (URL friendly)'),
                      TextField(
                        controller: _slug,
                        decoration: const InputDecoration(
                          isDense: true,
                          helperText: 'Auto-generated from title.',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _FieldLabel('Category'),
                      DropdownButtonFormField<int?>(
                        initialValue: _categoryId,
                        isExpanded: true,
                        decoration: const InputDecoration(isDense: true),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('Select category'),
                          ),
                          for (final c in widget.categories)
                            DropdownMenuItem<int?>(
                              value: c.id,
                              child: Text(c.name),
                            ),
                        ],
                        onChanged: (v) => setState(() => _categoryId = v),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const _FieldLabel('Main offer image (thumbnail)'),
            _ImagePickerField(
              existingUrl: widget.service.mediaUrl(
                widget.existing?.image ?? '',
              ),
              localPath: _imagePath,
              headers: headers,
              onPick: () async {
                final p = await _pickImage();
                if (p != null) setState(() => _imagePath = p);
              },
              onClear: () => setState(() => _imagePath = null),
            ),
            const SizedBox(height: 22),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _FieldLabel(
                        'This is for you if...',
                        trailing: TextButton.icon(
                          onPressed: () => setState(
                            () => _forYou.add(TextEditingController()),
                          ),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add'),
                        ),
                      ),
                      _EditableList(
                        controllers: _forYou,
                        hint: 'Enter specific detail...',
                        onRemove: (i) =>
                            setState(() => _forYou.removeAt(i).dispose()),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _FieldLabel(
                        'This is NOT for you if...',
                        trailing: TextButton.icon(
                          onPressed: () => setState(
                            () => _notForYou.add(TextEditingController()),
                          ),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add'),
                        ),
                      ),
                      _EditableList(
                        controllers: _notForYou,
                        hint: 'Enter specific detail...',
                        onRemove: (i) =>
                            setState(() => _notForYou.removeAt(i).dispose()),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < _sections.length; i++) _sectionCard(i, headers),
            Align(
              alignment: Alignment.centerLeft,
              child: GhostButton(
                label: 'Add description section',
                icon: Icons.add,
                onPressed: () => setState(() => _sections.add(_SectionDraft())),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard(int i, Map<String, String> headers) {
    final s = _sections[i];
    final text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.brand.surfaceHi,
        border: Border.all(color: context.brand.rule),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Description block #${i + 1}',
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Brand.danger),
                onPressed: () => setState(() {
                  _sections.removeAt(i).ctrl.dispose();
                }),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Remove'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const _FieldLabel('Content (HTML)'),
          TextField(
            controller: s.ctrl,
            minLines: 6,
            maxLines: 16,
            keyboardType: TextInputType.multiline,
            style: text.bodySmall?.copyWith(fontFamily: 'monospace'),
            decoration: const InputDecoration(
              isDense: true,
              hintText: '<p>Section content…</p>',
            ),
          ),
          const SizedBox(height: 12),
          const _FieldLabel('Section image (optional)'),
          _ImagePickerField(
            existingUrl: widget.service.mediaUrl(s.existingImage),
            localPath: s.localImage,
            headers: headers,
            onPick: () async {
              final p = await _pickImage();
              if (p != null) setState(() => s.localImage = p);
            },
            onClear: () => setState(() => s.localImage = null),
          ),
        ],
      ),
    );
  }
}

class _PackagesDialog extends StatefulWidget {
  const _PackagesDialog({required this.service, required this.offer});
  final OffersService service;
  final Offer offer;

  @override
  State<_PackagesDialog> createState() => _PackagesDialogState();
}

class _PackagesDialogState extends State<_PackagesDialog>
    with LiveRefresh<_PackagesDialog> {
  List<OfferPackage> _packages = const [];
  bool _loading = true;
  String? _error;
  bool _changed = false;
  bool _formOpen = false;
  bool _saving = false;

  OfferPackage? _editing;
  final _title = TextEditingController();
  final _price = TextEditingController();
  final _originalPrice = TextEditingController();
  final _savings = TextEditingController();
  final _description = TextEditingController();
  final _footer = TextEditingController();
  final List<TextEditingController> _inclusions = [];
  final List<TextEditingController> _payments = [];
  bool _popular = false;
  String? _imagePath;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _title,
      _price,
      _originalPrice,
      _savings,
      _description,
      _footer,
      ..._inclusions,
      ..._payments,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  List<String> get liveKeys => const ['offers'];

  @override
  void onLiveChange() {
    if (_formOpen || _saving || _loading) return;
    _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final list = await widget.service.packages(widget.offer.id);
      if (!mounted) return;
      if (silent && (_formOpen || _saving)) return;
      setState(() {
        _packages = list;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || silent) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _resetList(List<TextEditingController> list, List<String> values) {
    for (final c in list) {
      c.dispose();
    }
    list
      ..clear()
      ..addAll(values.map((v) => TextEditingController(text: v)));
    if (list.isEmpty) list.add(TextEditingController());
  }

  void _openForm([OfferPackage? p]) {
    setState(() {
      _editing = p;
      _title.text = p?.title ?? '';
      _price.text = p?.price ?? '';
      _originalPrice.text = p?.originalPrice ?? '';
      _savings.text = p?.savingsLabel ?? '';
      _description.text = p?.description ?? '';
      _footer.text = p?.footerText ?? '';
      _popular = p?.isPopular ?? false;
      _imagePath = null;
      _resetList(_inclusions, p?.inclusions ?? const []);
      _resetList(_payments, p?.paymentOptions ?? const []);
      _formOpen = true;
    });
  }

  Future<void> _edit(OfferPackage p) async {
    OfferPackage? fresh;
    try {
      fresh = await widget.service.packageById(p.id);
    } catch (_) {}
    if (!mounted) return;
    _openForm(fresh ?? p);
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty || _price.text.trim().isEmpty) {
      toast(context, 'Title and price are required.');
      return;
    }
    setState(() => _saving = true);
    final res = await widget.service.savePackage(
      id: _editing?.id,
      offerId: widget.offer.id,
      title: _title.text,
      price: _price.text.trim(),
      originalPrice: _originalPrice.text.trim(),
      savingsLabel: _savings.text,
      description: _description.text,
      inclusions: _inclusions
          .map((c) => c.text.trim())
          .where((v) => v.isNotEmpty)
          .toList(),
      paymentOptions: _payments
          .map((c) => c.text.trim())
          .where((v) => v.isNotEmpty)
          .toList(),
      footerText: _footer.text,
      isPopular: _popular,
      imagePath: _imagePath,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    toast(context, res.message);
    if (res.ok) {
      _changed = true;
      setState(() => _formOpen = false);
      _load();
    }
  }

  Future<void> _delete(OfferPackage p) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete this package?',
      message: 'The package will be permanently removed from this offer.',
      confirmLabel: 'Delete package',
    );
    if (!ok || !mounted) return;
    setState(() => _packages = _packages.where((x) => x.id != p.id).toList());
    if (!await _undoWindow(context, 'Package deleted')) {
      if (mounted) _load();
      return;
    }
    if (!mounted) return;
    final res = await widget.service.deletePackage(p.id);
    if (!mounted) return;
    if (!res.ok) toast(context, res.message);
    _changed = true;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_formOpen) {
          setState(() => _formOpen = false);
        } else {
          Navigator.of(context).pop(_changed);
        }
      },
      child: _DialogShell(
        title: 'Manage Packages',
        subtitle: widget.offer.title,
        icon: Icons.inventory_2_outlined,
        width: 1000,
        child: _formOpen ? _form() : _list(),
      ),
    );
  }

  Widget _list() {
    final text = Theme.of(context).textTheme;
    Widget body;
    if (_loading) {
      body = const Padding(
        padding: EdgeInsets.all(40),
        child: Center(
          child: TpLoader(strokeWidth: 2, color: Brand.signal),
        ),
      );
    } else if (_error != null) {
      body = Padding(
        padding: const EdgeInsets.all(40),
        child: Center(child: Text(_error!, style: text.bodySmall)),
      );
    } else if (_packages.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.all(40),
        child: Center(
          child: Text(
            'No packages found',
            style: text.bodyMedium?.copyWith(color: context.brand.paperDim),
          ),
        ),
      );
    } else {
      body = ColumnResizeScope(
        tableId: 'offers:packages',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const WebTableHeader(
              cells: [
                Expanded(flex: 3, child: Text('PACKAGE TITLE')),
                Expanded(flex: 1, child: Text('PRICE')),
                Expanded(flex: 3, child: Text('INCLUSIONS')),
                SizedBox(
                  width: 100,
                  child: Text('ACTIONS', textAlign: TextAlign.right),
                ),
              ],
            ),
            for (final p in _packages) _packageRow(p),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SignalButton(
              label: 'Add Package',
              icon: Icons.add,
              onPressed: () => _openForm(),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: context.brand.rule),
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: body,
          ),
        ],
      ),
    );
  }

  Widget _packageRow(OfferPackage p) {
    final text = Theme.of(context).textTheme;
    return WebTableRow(
      onTap: () => _edit(p),
      crossAxisAlignment: CrossAxisAlignment.start,
      cells: [
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    Text(
                      p.title,
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (p.isPopular)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Brand.signalGlow(0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Brand.signalGlow(0.3)),
                        ),
                        child: Text(
                          'Popular',
                          style: text.labelSmall?.copyWith(
                            color: Brand.signal,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ),
                if (p.description.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    p.description,
                    style: text.bodySmall?.copyWith(
                      color: context.brand.paperDim,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Expanded(
          flex: 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                p.price,
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (p.savingsLabel.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    p.savingsLabel,
                    style: text.labelSmall?.copyWith(
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final inc in p.inclusions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '- $inc',
                    style: text.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          width: 100,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedIconButton(
                icon: Icons.edit_outlined,
                tooltip: 'Edit',
                onPressed: () => _edit(p),
              ),
              const SizedBox(width: 6),
              OutlinedIconButton(
                icon: Icons.delete_outline,
                tooltip: 'Delete',
                color: Brand.danger,
                onPressed: () => _delete(p),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _form() {
    final text = Theme.of(context).textTheme;
    Widget field(
      String label,
      TextEditingController c, {
      int lines = 1,
      TextInputType? type,
      String? hint,
    }) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FieldLabel(label),
            TextField(
              controller: c,
              minLines: lines,
              maxLines: lines == 1 ? 1 : lines + 2,
              keyboardType: type,
              decoration: InputDecoration(isDense: true, hintText: hint),
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _editing == null ? 'Add Package' : 'Edit Package',
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          field('Title', _title),
                          Row(
                            children: [
                              Expanded(
                                child: field(
                                  'Price',
                                  _price,
                                  type: const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: field(
                                  'Original price (optional)',
                                  _originalPrice,
                                  type: const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          field('Savings label (optional)', _savings),
                          field('Description', _description, lines: 2),
                          field(
                            'Footer text (e.g. guarantee)',
                            _footer,
                            lines: 2,
                          ),
                          const _FieldLabel('Image (optional)'),
                          _ImagePickerField(
                            existingUrl: widget.service.mediaUrl(
                              _editing?.image ?? '',
                            ),
                            localPath: _imagePath,
                            headers: widget.service.api.authHeaders(),
                            onPick: () async {
                              final p = await _pickImage();
                              if (p != null) setState(() => _imagePath = p);
                            },
                            onClear: () => setState(() => _imagePath = null),
                          ),
                          const SizedBox(height: 10),
                          CheckboxListTile(
                            value: _popular,
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: const Text('Mark as popular'),
                            onChanged: (v) =>
                                setState(() => _popular = v ?? false),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _FieldLabel(
                            'Inclusions',
                            trailing: TextButton.icon(
                              onPressed: () => setState(
                                () => _inclusions.add(TextEditingController()),
                              ),
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Add inclusion'),
                            ),
                          ),
                          _EditableList(
                            controllers: _inclusions,
                            hint: 'Enter inclusion detail...',
                            onRemove: (i) => setState(
                              () => _inclusions.removeAt(i).dispose(),
                            ),
                          ),
                          const SizedBox(height: 14),
                          _FieldLabel(
                            'Payment options',
                            trailing: TextButton.icon(
                              onPressed: () => setState(
                                () => _payments.add(TextEditingController()),
                              ),
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Add option'),
                            ),
                          ),
                          _EditableList(
                            controllers: _payments,
                            hint: 'Enter payment option...',
                            onRemove: (i) =>
                                setState(() => _payments.removeAt(i).dispose()),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          decoration: BoxDecoration(
            color: context.brand.surfaceHi,
            border: Border(top: BorderSide(color: context.brand.rule)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              GhostButton(
                label: 'Cancel',
                onPressed: _saving
                    ? null
                    : () => setState(() => _formOpen = false),
              ),
              const SizedBox(width: 10),
              SignalButton(
                label: 'Save Package',
                icon: Icons.save_outlined,
                busy: _saving,
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CategoriesDialog extends StatefulWidget {
  const _CategoriesDialog({required this.service, required this.onChanged});
  final OffersService service;
  final VoidCallback onChanged;

  @override
  State<_CategoriesDialog> createState() => _CategoriesDialogState();
}

class _CategoriesDialogState extends State<_CategoriesDialog>
    with LiveRefresh<_CategoriesDialog> {
  List<OfferCategory> _items = [];
  bool _loading = true;
  String? _error;
  String _filter = '';
  bool _formOpen = false;
  bool _saving = false;
  int? _editingId;
  final _name = TextEditingController();
  final _slug = TextEditingController();
  late final _slugger = _ServerSlug(widget.service, _slug);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _slugger.dispose();
    _name.dispose();
    _slug.dispose();
    super.dispose();
  }

  @override
  List<String> get liveKeys => const ['offers'];

  @override
  void onLiveChange() {
    if (_formOpen || _saving || _loading) return;
    _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final list = await widget.service.categories();
      if (!mounted) return;
      if (silent && (_formOpen || _saving)) return;
      setState(() {
        _items = List.of(list);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || silent) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _openForm() {
    setState(() {
      _editingId = null;
      _name.clear();
      _slug.clear();
      _formOpen = true;
    });
  }

  Future<void> _edit(OfferCategory c) async {
    OfferCategory? fresh;
    try {
      fresh = await widget.service.categoryById(c.id);
    } catch (_) {}
    if (!mounted) return;
    final cat = fresh ?? c;
    setState(() {
      _editingId = cat.id;
      _name.text = cat.name;
      _slug.text = cat.slug;
      _formOpen = true;
    });
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _slug.text.trim().isEmpty) {
      toast(context, 'Name and slug are required.');
      return;
    }
    setState(() => _saving = true);
    final res = await widget.service.saveCategory(
      id: _editingId,
      name: _name.text,
      slug: _slug.text,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    toast(context, res.message);
    if (res.ok) {
      setState(() => _formOpen = false);
      widget.onChanged();
      _load();
    }
  }

  Future<void> _delete(OfferCategory c) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete this category?',
      message: 'Offers attached to this category may be affected.',
      confirmLabel: 'Delete category',
    );
    if (!ok || !mounted) return;
    setState(() => _items = _items.where((x) => x.id != c.id).toList());
    if (!await _undoWindow(context, 'Category deleted')) {
      if (mounted) _load();
      return;
    }
    if (!mounted) return;
    final res = await widget.service.deleteCategory(c.id);
    if (!mounted) return;
    if (!res.ok) toast(context, res.message);
    widget.onChanged();
    _load();
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    setState(() {
      final item = _items.removeAt(oldIndex);
      _items.insert(newIndex, item);
    });
    final res = await widget.service.updateCategoryOrder(
      _items.map((c) => c.id).toList(),
    );
    if (!mounted) return;
    toast(context, res.message);
    if (res.ok) widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final filtering = _filter.isNotEmpty;
    final shown = filtering
        ? _items
              .where(
                (c) => c.name.toLowerCase().contains(_filter.toLowerCase()),
              )
              .toList()
        : _items;

    Widget rowFor(OfferCategory c, int index) {
      return Container(
        key: ValueKey(c.id),
        decoration: BoxDecoration(
          color: context.brand.surface,
          border: Border(bottom: BorderSide(color: context.brand.rule)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            if (!filtering)
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    Icons.drag_indicator,
                    size: 18,
                    color: context.brand.paperDim,
                  ),
                ),
              )
            else
              const SizedBox(width: 34),
            Expanded(child: Text(c.name, style: text.bodyMedium)),
            OutlinedIconButton(
              icon: Icons.edit_outlined,
              tooltip: 'Edit',
              onPressed: () => _edit(c),
            ),
            const SizedBox(width: 6),
            OutlinedIconButton(
              icon: Icons.delete_outline,
              tooltip: 'Delete',
              color: Brand.danger,
              onPressed: () => _delete(c),
            ),
            const SizedBox(width: 4),
          ],
        ),
      );
    }

    Widget list;
    if (_loading) {
      list = const Padding(
        padding: EdgeInsets.all(30),
        child: Center(
          child: TpLoader(strokeWidth: 2, color: Brand.signal),
        ),
      );
    } else if (_error != null) {
      list = Padding(
        padding: const EdgeInsets.all(30),
        child: Text(_error!, style: text.bodySmall),
      );
    } else if (shown.isEmpty) {
      list = Padding(
        padding: const EdgeInsets.all(30),
        child: Center(
          child: Text(
            'No categories found',
            style: text.bodyMedium?.copyWith(color: context.brand.paperDim),
          ),
        ),
      );
    } else if (filtering) {
      list = Column(
        children: [for (var i = 0; i < shown.length; i++) rowFor(shown[i], i)],
      );
    } else {
      list = ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        onReorderItem: _reorder,
        children: [for (var i = 0; i < shown.length; i++) rowFor(shown[i], i)],
      );
    }

    return _DialogShell(
      title: 'Manage Categories',
      subtitle: 'Drag to reorder',
      icon: Icons.folder_open_outlined,
      width: 760,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: SearchField(
                    hint: 'Search categories...',
                    width: null,
                    onChanged: (v) => setState(() => _filter = v.trim()),
                  ),
                ),
                const SizedBox(width: 10),
                SignalButton(
                  label: 'Add Category',
                  icon: Icons.add,
                  onPressed: _openForm,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: context.brand.rule),
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: list,
            ),
            if (_formOpen) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: context.brand.surfaceHi,
                  border: Border.all(color: context.brand.rule),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _editingId == null ? 'Add Category' : 'Edit Category',
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const _FieldLabel('Category name'),
                              TextField(
                                controller: _name,
                                autofocus: true,
                                decoration: const InputDecoration(
                                  isDense: true,
                                ),
                                onChanged: _slugger.update,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const _FieldLabel('Slug'),
                              TextField(
                                controller: _slug,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  helperText: 'Auto-generated from name.',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        GhostButton(
                          label: 'Cancel',
                          onPressed: _saving
                              ? null
                              : () => setState(() => _formOpen = false),
                        ),
                        const SizedBox(width: 10),
                        SignalButton(
                          label: 'Save Category',
                          busy: _saving,
                          onPressed: _saving ? null : _save,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
