import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../api_client.dart';
import '../../services/live_sync.dart';
import '../../services/pricing_service.dart';
import '../../theme.dart';
import '../../widgets/premium.dart';
import '../admin/admin_list.dart';
import 'op_page_header.dart';
import '../../widgets/tp_loader.dart';

const List<(String, IconData)> _kIcons = [
  ('fas fa-gas-pump', Icons.local_gas_station),
  ('fas fa-cut', Icons.content_cut),
  ('images/barber-pole.svg', Icons.face_retouching_natural),
  ('fas fa-briefcase', Icons.work_outline),
  ('fas fa-building', Icons.business),
  ('fas fa-store', Icons.store),
  ('fas fa-shopping-cart', Icons.shopping_cart),
  ('fas fa-utensils', Icons.restaurant),
  ('fas fa-coffee', Icons.coffee),
  ('fas fa-hospital', Icons.local_hospital),
  ('fas fa-hotel', Icons.hotel),
  ('fas fa-car', Icons.directions_car),
  ('fas fa-graduation-cap', Icons.school),
  ('fas fa-laptop', Icons.laptop),
  ('fas fa-tools', Icons.handyman),
  ('fas fa-chart-line', Icons.show_chart),
  ('fas fa-users', Icons.groups),
  ('fas fa-globe', Icons.public),
  ('fas fa-heart', Icons.favorite),
  ('fas fa-lightbulb', Icons.lightbulb_outline),
  ('fas fa-rocket', Icons.rocket_launch),
  ('fas fa-shield-alt', Icons.shield),
  ('fas fa-star', Icons.star),
  ('bi bi-pc-display', Icons.desktop_windows),
  ('bi bi-shop', Icons.storefront),
  ('bi bi-cart', Icons.shopping_cart_outlined),
  ('bi bi-building', Icons.apartment),
  ('fas fa-wrench', Icons.build),
  ('fas fa-hammer', Icons.hardware),
  ('fas fa-plug', Icons.power),
  ('fas fa-paint-roller', Icons.format_paint),
  ('fas fa-truck', Icons.local_shipping),
  ('fas fa-shipping-fast', Icons.delivery_dining),
  ('fas fa-box', Icons.inventory_2),
  ('fas fa-barcode', Icons.qr_code_2),
  ('fas fa-receipt', Icons.receipt_long),
  ('fas fa-wallet', Icons.account_balance_wallet),
  ('fas fa-credit-card', Icons.credit_card),
  ('fas fa-money-bill-wave', Icons.payments),
  ('fas fa-university', Icons.account_balance),
  ('fas fa-calculator', Icons.calculate),
  ('fas fa-file-invoice-dollar', Icons.request_quote),
  ('fas fa-balance-scale', Icons.balance),
  ('fas fa-stethoscope', Icons.medical_services),
  ('fas fa-pills', Icons.medication),
  ('fas fa-ambulance', Icons.emergency),
  ('fas fa-first-aid', Icons.healing),
  ('fas fa-school', Icons.school_outlined),
  ('fas fa-book', Icons.menu_book),
  ('fas fa-pencil-alt', Icons.edit),
  ('fas fa-laptop-code', Icons.code),
  ('fas fa-server', Icons.dns),
  ('fas fa-database', Icons.storage),
  ('fas fa-cloud', Icons.cloud),
  ('fas fa-wifi', Icons.wifi),
  ('fas fa-mobile-alt', Icons.smartphone),
  ('fas fa-tablet-alt', Icons.tablet),
  ('fas fa-camera', Icons.photo_camera),
  ('fas fa-video', Icons.videocam),
  ('fas fa-music', Icons.music_note),
  ('fas fa-gamepad', Icons.sports_esports),
  ('fas fa-dumbbell', Icons.fitness_center),
  ('fas fa-bicycle', Icons.pedal_bike),
  ('fas fa-plane', Icons.flight),
  ('fas fa-train', Icons.train),
  ('fas fa-bus', Icons.directions_bus),
  ('fas fa-taxi', Icons.local_taxi),
  ('fas fa-home', Icons.home),
  ('fas fa-key', Icons.key),
  ('fas fa-bed', Icons.bed),
  ('fas fa-bath', Icons.bathtub),
  ('fas fa-tree', Icons.park),
  ('fas fa-leaf', Icons.eco),
  ('fas fa-seedling', Icons.grass),
  ('fas fa-cannabis', Icons.spa),
  ('fas fa-sun', Icons.wb_sunny),
  ('fas fa-moon', Icons.dark_mode),
  ('fas fa-cloud-sun', Icons.wb_cloudy),
  ('fas fa-snowflake', Icons.ac_unit),
  ('fas fa-anchor', Icons.anchor),
  ('fas fa-ship', Icons.directions_boat),
  ('fas fa-fish', Icons.set_meal),
  ('fas fa-swimmer', Icons.pool),
  ('fas fa-cog', Icons.settings),
  ('fas fa-cogs', Icons.settings_suggest),
  ('fas fa-sync', Icons.sync),
  ('fas fa-redo', Icons.redo),
  ('fas fa-plus', Icons.add),
  ('fas fa-minus', Icons.remove),
  ('fas fa-check', Icons.check),
  ('fas fa-times', Icons.close),
  ('fas fa-info-circle', Icons.info_outline),
  ('fas fa-question-circle', Icons.help_outline),
  ('fas fa-exclamation-circle', Icons.error_outline),
  ('fas fa-bell', Icons.notifications),
  ('fas fa-envelope', Icons.email),
  ('fas fa-phone', Icons.phone),
  ('fas fa-comment', Icons.chat_bubble),
  ('fas fa-share-alt', Icons.share),
  ('fas fa-thumbs-up', Icons.thumb_up),
  ('fas fa-eye', Icons.visibility),
  ('fas fa-lock', Icons.lock),
  ('fas fa-unlock', Icons.lock_open),
  ('fas fa-user-tie', Icons.person),
  ('fas fa-user-cog', Icons.manage_accounts),
  ('fas fa-user-graduate', Icons.badge),
  ('fas fa-handshake', Icons.handshake),
  ('fas fa-gift', Icons.card_giftcard),
  ('fas fa-crown', Icons.workspace_premium),
  ('fas fa-gem', Icons.diamond),
  ('fas fa-medal', Icons.military_tech),
  ('fas fa-fire', Icons.local_fire_department),
  ('fas fa-bolt', Icons.bolt),
  ('fas fa-water', Icons.water),
  ('fas fa-atom', Icons.science),
];

IconData? _iconFor(String icon) {
  if (icon.isEmpty) return null;
  for (final e in _kIcons) {
    if (e.$1 == icon) return e.$2;
  }
  return Icons.category_outlined;
}

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

Future<String?> _pickImage() async {
  final picked = await FilePicker.platform.pickFiles(type: FileType.image);
  if (picked == null || picked.files.isEmpty) return null;
  return picked.files.single.path;
}

String _fileName(String path) => path.split(RegExp(r'[\\/]')).last;

class PricingScreen extends StatefulWidget {
  const PricingScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<PricingScreen> createState() => _PricingScreenState();
}

class _PricingScreenState extends State<PricingScreen>
    with LiveRefresh<PricingScreen> {
  late final PricingService _service = PricingService(widget.api);

  List<BusinessType> _businessTypes = const [];
  List<FeatureCategory> _categories = const [];
  int? _currentBT;
  List<PricingPlan> _plans = const [];
  bool _loading = true;
  String? _error;
  final Set<int> _pendingDelete = {};

  bool get _canManage =>
      widget.api.permissions.isEmpty || widget.api.hasPermission('user');

  @override
  void initState() {
    super.initState();
    _loadBusinessTypes();
    _loadCategories();
  }

  @override
  List<String> get liveKeys => const ['pricing'];

  @override
  void onLiveChange() => _liveReload();

  Future<void> _liveReload() async {
    final wanted = _currentBT;
    try {
      final types = await _service.businessTypes();
      final cats = await _service.categories();
      final bt = wanted != null && types.any((b) => b.id == wanted)
          ? wanted
          : null;
      final plans = await _service.pricings(businessTypeId: bt);
      if (!mounted || _currentBT != wanted) return;
      setState(() {
        _businessTypes = types;
        _categories = cats;
        _currentBT = bt;
        _plans = plans;
        _loading = false;
        _error = null;
      });
    } catch (_) {}
  }

  Future<void> _loadBusinessTypes() async {
    try {
      final list = await _service.businessTypes();
      if (!mounted) return;
      setState(() {
        _businessTypes = list;
        if (_currentBT != null && !list.any((b) => b.id == _currentBT)) {
          _currentBT = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
    _loadPlans();
  }

  Future<void> _loadCategories() async {
    try {
      final list = await _service.categories();
      if (!mounted) return;
      setState(() => _categories = list);
    } catch (_) {}
  }

  Future<void> _loadPlans() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _service.pricings(businessTypeId: _currentBT);
      if (!mounted) return;
      setState(() {
        _plans = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _switchBT(int? id) {
    setState(() => _currentBT = id);
    _loadPlans();
  }

  Future<void> _openBusinessTypes() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _BusinessTypesDialog(
        service: _service,
        onChanged: (deleted) {
          if (deleted) _currentBT = null;
          _loadBusinessTypes();
        },
      ),
    );
  }

  Future<void> _openCategories() async {
    await showDialog<void>(
      context: context,
      builder: (_) =>
          _CategoriesDialog(service: _service, onChanged: _loadCategories),
    );
  }

  Future<void> _openPlanForm({PricingPlan? existing}) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PlanFormDialog(
        service: _service,
        businessTypes: _businessTypes,
        categories: _categories,
        existing: existing,
        defaultBusinessType: _currentBT,
      ),
    );
    if (saved == true) _loadPlans();
  }

  Future<void> _deletePlan(PricingPlan p) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete this pricing plan?',
      message: 'The plan will be permanently removed from this business type.',
      confirmLabel: 'Delete plan',
    );
    if (!ok || !mounted) return;
    setState(() => _pendingDelete.add(p.id));
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final reason = await messenger
        .showSnackBar(
          SnackBar(
            content: const Text('Pricing plan deleted'),
            duration: const Duration(seconds: 5),
            persist: false,
            action: SnackBarAction(label: 'Undo', onPressed: () {}),
          ),
        )
        .closed;
    if (reason == SnackBarClosedReason.action) {
      if (mounted) setState(() => _pendingDelete.remove(p.id));
      return;
    }
    final res = await _service.deletePricing(p.id);
    if (!mounted) return;
    _pendingDelete.remove(p.id);
    if (!res.ok) toast(context, res.message);
    _loadPlans();
  }

  @override
  Widget build(BuildContext context) {
    return OpPage(
      padding: const EdgeInsets.fromLTRB(17, 0, 17, 20),
      header: OpPageHeader(
        eyebrow: 'Inventory Management',
        title: 'Pricing & Plans',
        actions: [
          if (_canManage) ...[
            OpPillButton(
              label: 'Business Types',
              icon: Icons.work,
              onPressed: _openBusinessTypes,
            ),
            OpPillButton(
              label: 'Categories',
              icon: Icons.list,
              onPressed: _openCategories,
            ),
            OpPillButton(
              label: 'Add Plan',
              icon: Icons.add,
              primary: true,
              onPressed: () => _openPlanForm(),
            ),
          ],
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          _tabs(),
          const SizedBox(height: 16),
          Expanded(child: _table()),
        ],
      ),
    );
  }

  Widget _tabs() {
    Widget tab(int? id, String label, Widget? icon) {
      final active = _currentBT == id;
      return Padding(
        padding: const EdgeInsets.only(right: 16),
        child: InkWell(
          mouseCursor: SystemMouseCursors.click,
          onTap: () => _switchBT(id),
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: BoxDecoration(
              color: active ? Brand.signal : context.brand.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: active ? Brand.signal : context.brand.rule,
              ),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: Brand.signal.withValues(alpha: 0.2),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: IconTheme(
              data: IconThemeData(
                size: 22,
                color: active ? Colors.white : context.brand.paper,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[icon, const SizedBox(width: 14)],
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: active ? Colors.white : context.brand.paper,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          tab(null, 'All', const Icon(Icons.grid_view)),
          for (final bt in _businessTypes)
            tab(
              bt.id,
              bt.name,
              _iconFor(bt.icon) == null ? null : Icon(_iconFor(bt.icon)),
            ),
        ],
      ),
    );
  }

  Widget _table() {
    final text = Theme.of(context).textTheme;
    final visible = _plans
        .where((p) => !_pendingDelete.contains(p.id))
        .toList();
    Widget body;
    if (_loading) {
      body = const Center(child: TpLoader());
    } else if (_error != null) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Could not load pricing plans', style: text.titleMedium),
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center, style: text.bodySmall),
            const SizedBox(height: 12),
            GhostButton(
              label: 'Retry',
              icon: Icons.refresh,
              onPressed: _loadBusinessTypes,
            ),
          ],
        ),
      );
    } else if (visible.isEmpty) {
      body = const EmptyState(
        label: 'No pricing plans available',
        hint: 'Add a plan or pick another business type.',
      );
    } else {
      body = ListView.builder(
        itemCount: visible.length,
        itemBuilder: (_, i) => _planRow(visible[i]),
      );
    }
    return OpPanel(
      child: ColumnResizeScope(
        tableId: 'pricing:plans',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WebTableHeader(
              cells: [
                const SizedBox(width: 250, child: Text('PLAN')),
                const SizedBox(width: 140, child: Text('PRICE')),
                const Expanded(child: Text('FEATURES')),
                if (_canManage)
                  const SizedBox(
                    width: 110,
                    child: Text('ACTIONS', textAlign: TextAlign.right),
                  ),
              ],
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  Widget _planRow(PricingPlan p) {
    final text = Theme.of(context).textTheme;
    final grouped = <String, List<String>>{};
    for (final f in p.features) {
      grouped.putIfAbsent(f.categoryName, () => []).add(f.name);
    }
    return _HoverRow(
      onTap: _canManage ? () => _openPlanForm(existing: p) : null,
      child: Builder(
        builder: (context) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: resizableRowCells(context, [
            SizedBox(
              width: 250,
              child: Padding(
                padding: const EdgeInsets.only(right: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (p.image.isNotEmpty) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          _service.uploadUrl(p.image),
                          headers: widget.api.authHeaders(),
                          height: 140,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            height: 140,
                            alignment: Alignment.center,
                            color: context.brand.surfaceHi,
                            child: Text(
                              'No Preview',
                              style: text.titleMedium?.copyWith(
                                color: context.brand.paperDim,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text(
                      p.title,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: 140,
              child: Text(
                p.price,
                style: text.headlineSmall?.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Brand.signal,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final e in grouped.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (e.key.isEmpty ? 'General features' : e.key)
                                .toUpperCase(),
                            style: text.labelSmall?.copyWith(
                              color: context.brand.paperDim,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final name in e.value)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: context.brand.canvas,
                                    borderRadius: BorderRadius.circular(99),
                                    border: Border.all(
                                      color: context.brand.rule,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.check,
                                        size: 13,
                                        color: Brand.signal,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          name,
                                          style: text.bodyMedium?.copyWith(
                                            fontSize: 13.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (_canManage)
              SizedBox(
                width: 110,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedIconButton(
                      icon: Icons.edit_outlined,
                      tooltip: 'Edit',
                      onPressed: () => _openPlanForm(existing: p),
                    ),
                    const SizedBox(width: 6),
                    OutlinedIconButton(
                      icon: Icons.delete_outline,
                      tooltip: 'Delete',
                      color: Brand.danger,
                      onPressed: () => _deletePlan(p),
                    ),
                  ],
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _HoverRow extends StatefulWidget {
  const _HoverRow({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<_HoverRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: _hover ? context.brand.surfaceHi : context.brand.surface,
            border: Border(bottom: BorderSide(color: context.brand.rule)),
          ),
          child: widget.child,
        ),
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

class _BusinessTypesDialog extends StatefulWidget {
  const _BusinessTypesDialog({required this.service, required this.onChanged});
  final PricingService service;
  final void Function(bool deleted) onChanged;

  @override
  State<_BusinessTypesDialog> createState() => _BusinessTypesDialogState();
}

class _BusinessTypesDialogState extends State<_BusinessTypesDialog>
    with LiveRefresh<_BusinessTypesDialog> {
  static const int _step = 24;
  List<BusinessType> _items = [];
  bool _loading = true;
  bool _saving = false;
  int _iconsLimit = _step;
  int? _editingId;
  String _icon = '';
  final _name = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  List<String> get liveKeys => const ['pricing'];

  @override
  void onLiveChange() {
    if (_saving || _editingId != null) return;
    _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final list = await widget.service.businessTypes();
      if (!mounted) return;
      if (silent && (_saving || _editingId != null)) return;
      setState(() {
        _items = List.of(list);
        _loading = false;
      });
    } catch (e) {
      if (!mounted || silent) return;
      setState(() => _loading = false);
      toast(context, e.toString());
    }
  }

  void _reset() {
    setState(() {
      _editingId = null;
      _icon = '';
      _name.clear();
    });
  }

  void _edit(BusinessType bt) {
    final index = _kIcons.indexWhere((e) => e.$1 == bt.icon);
    setState(() {
      _editingId = bt.id;
      _name.text = bt.name;
      _icon = bt.icon;
      if (index >= _iconsLimit) {
        _iconsLimit = ((index + 1) / _step).ceil() * _step;
      }
    });
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      toast(context, 'Business type name is required.');
      return;
    }
    setState(() => _saving = true);
    final res = await widget.service.saveBusinessType(
      id: _editingId,
      name: _name.text,
      icon: _icon,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!res.ok) {
      toast(context, res.message);
      return;
    }
    _reset();
    widget.onChanged(false);
    _load();
  }

  Future<void> _delete(BusinessType bt) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete this business type?',
      message:
          'All pricing plans associated with this business type will be permanently removed.',
      confirmLabel: 'Delete business type',
    );
    if (!ok || !mounted) return;
    setState(() => _items = _items.where((b) => b.id != bt.id).toList());
    if (!await _undoWindow(context, 'Business type deleted')) {
      if (mounted) _load();
      return;
    }
    if (!mounted) return;
    final res = await widget.service.deleteBusinessType(bt.id);
    if (!mounted) return;
    if (!res.ok) toast(context, res.message);
    if (_editingId == bt.id) _reset();
    widget.onChanged(true);
    _load();
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    setState(() {
      final item = _items.removeAt(oldIndex);
      _items.insert(newIndex, item);
    });
    final res = await widget.service.reorderBusinessTypes(
      _items.map((b) => b.id).toList(),
    );
    if (!mounted) return;
    if (!res.ok) toast(context, res.message);
    widget.onChanged(false);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final shownIcons = _kIcons.take(_iconsLimit).toList();
    return _DialogShell(
      title: 'Business Types',
      subtitle: 'Drag to reorder how the tabs appear',
      icon: Icons.work_outline,
      width: 720,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              color: context.brand.surfaceHi,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _FieldLabel('Business type name'),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _name,
                          autofocus: true,
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: 'e.g. Barber, Gas Station',
                          ),
                          onSubmitted: (_) => _save(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SignalButton(
                        label: _editingId == null ? 'Save' : 'Update',
                        busy: _saving,
                        onPressed: _saving ? null : _save,
                      ),
                      if (_editingId != null) ...[
                        const SizedBox(width: 8),
                        GhostButton(label: 'Cancel', onPressed: _reset),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  _FieldLabel(
                    'Select icon',
                    trailing: _iconsLimit < _kIcons.length
                        ? TextButton(
                            onPressed: () =>
                                setState(() => _iconsLimit += _step),
                            child: const Text('Load more'),
                          )
                        : null,
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final e in shownIcons)
                        Tooltip(
                          message: e.$1,
                          child: InkWell(
                            mouseCursor: SystemMouseCursors.click,
                            onTap: () => setState(() => _icon = e.$1),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: _icon == e.$1
                                    ? Brand.signalGlow(0.15)
                                    : context.brand.surface,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _icon == e.$1
                                      ? Brand.signal
                                      : context.brand.rule,
                                  width: _icon == e.$1 ? 2 : 1,
                                ),
                              ),
                              child: Icon(
                                e.$2,
                                size: 20,
                                color: _icon == e.$1
                                    ? Brand.signal
                                    : context.brand.paper,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(30),
                child: Center(
                  child: TpLoader(
                    strokeWidth: 2,
                    color: Brand.signal,
                  ),
                ),
              )
            else if (_items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(30),
                child: Center(
                  child: Text(
                    'No business types found',
                    style: text.bodyMedium?.copyWith(
                      color: context.brand.paperDim,
                    ),
                  ),
                ),
              )
            else
              ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                onReorderItem: _reorder,
                children: [
                  for (var i = 0; i < _items.length; i++)
                    Container(
                      key: ValueKey(_items[i].id),
                      decoration: BoxDecoration(
                        color: _editingId == _items[i].id
                            ? Brand.signalGlow(0.08)
                            : context.brand.surface,
                        border: Border(
                          bottom: BorderSide(color: context.brand.rule),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          ReorderableDragStartListener(
                            index: i,
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Icon(
                                Icons.drag_indicator,
                                size: 18,
                                color: context.brand.paperDim,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 32,
                            child: _iconFor(_items[i].icon) == null
                                ? null
                                : Icon(
                                    _iconFor(_items[i].icon),
                                    size: 20,
                                    color: Brand.signal,
                                  ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _items[i].name,
                              style: text.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Edit',
                            onPressed: () => _edit(_items[i]),
                            icon: const Icon(Icons.edit_outlined, size: 18),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            onPressed: () => _delete(_items[i]),
                            icon: const Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: Colors.redAccent,
                            ),
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

class _CategoriesDialog extends StatefulWidget {
  const _CategoriesDialog({required this.service, required this.onChanged});
  final PricingService service;
  final VoidCallback onChanged;

  @override
  State<_CategoriesDialog> createState() => _CategoriesDialogState();
}

class _CategoriesDialogState extends State<_CategoriesDialog>
    with LiveRefresh<_CategoriesDialog> {
  List<FeatureCategory> _items = const [];
  bool _loading = true;
  bool _saving = false;
  int? _editingId;
  final _name = TextEditingController();
  final _subtitle = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _subtitle.dispose();
    super.dispose();
  }

  @override
  List<String> get liveKeys => const ['pricing'];

  @override
  void onLiveChange() {
    if (_saving || _editingId != null) return;
    _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final list = await widget.service.categories();
      if (!mounted) return;
      if (silent && (_saving || _editingId != null)) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || silent) return;
      setState(() => _loading = false);
      toast(context, e.toString());
    }
  }

  void _reset() {
    setState(() {
      _editingId = null;
      _name.clear();
      _subtitle.clear();
    });
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      toast(context, 'Category name is required.');
      return;
    }
    setState(() => _saving = true);
    final res = await widget.service.saveCategory(
      id: _editingId,
      name: _name.text,
      subtitle: _subtitle.text,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!res.ok) {
      toast(context, res.message);
      return;
    }
    _reset();
    widget.onChanged();
    _load();
  }

  Future<void> _delete(FeatureCategory c) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete this category?',
      message: 'The category will be permanently removed from the catalog.',
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
    if (_editingId == c.id) _reset();
    widget.onChanged();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return _DialogShell(
      title: 'Feature Categories',
      icon: Icons.list,
      width: 720,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              color: context.brand.surfaceHi,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                                hintText: 'e.g. Core Features, Analytics',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const _FieldLabel('Subtitle (optional)'),
                            TextField(
                              controller: _subtitle,
                              decoration: const InputDecoration(
                                isDense: true,
                                hintText: 'e.g. Basic management tools',
                              ),
                              onSubmitted: (_) => _save(),
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
                      if (_editingId != null) ...[
                        GhostButton(label: 'Cancel', onPressed: _reset),
                        const SizedBox(width: 8),
                      ],
                      SignalButton(
                        label: _editingId == null ? 'Add' : 'Update',
                        icon: _editingId == null ? Icons.add : null,
                        busy: _saving,
                        onPressed: _saving ? null : _save,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(30),
                child: Center(
                  child: TpLoader(
                    strokeWidth: 2,
                    color: Brand.signal,
                  ),
                ),
              )
            else if (_items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(30),
                child: Center(
                  child: Text(
                    'No categories found',
                    style: text.bodyMedium?.copyWith(
                      color: context.brand.paperDim,
                    ),
                  ),
                ),
              )
            else
              for (final c in _items)
                Container(
                  decoration: BoxDecoration(
                    color: _editingId == c.id
                        ? Brand.signalGlow(0.08)
                        : context.brand.surface,
                    border: Border(
                      bottom: BorderSide(color: context.brand.rule),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.name,
                              style: text.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (c.subtitle.isNotEmpty)
                              Text(
                                c.subtitle,
                                style: text.bodySmall?.copyWith(
                                  color: context.brand.paperDim,
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Edit',
                        onPressed: () => setState(() {
                          _editingId = c.id;
                          _name.text = c.name;
                          _subtitle.text = c.subtitle;
                        }),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        onPressed: () => _delete(c),
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _FeatureDraft {
  _FeatureDraft({this.categoryId, String name = '', this.showCategory = true})
    : ctrl = TextEditingController(text: name),
      focus = FocusNode();

  int? categoryId;
  final TextEditingController ctrl;
  final FocusNode focus;
  final bool showCategory;

  void dispose() {
    ctrl.dispose();
    focus.dispose();
  }
}

class _PlanFormDialog extends StatefulWidget {
  const _PlanFormDialog({
    required this.service,
    required this.businessTypes,
    required this.categories,
    this.existing,
    this.defaultBusinessType,
  });

  final PricingService service;
  final List<BusinessType> businessTypes;
  final List<FeatureCategory> categories;
  final PricingPlan? existing;
  final int? defaultBusinessType;

  @override
  State<_PlanFormDialog> createState() => _PlanFormDialogState();
}

class _PlanFormDialogState extends State<_PlanFormDialog> {
  int? _businessTypeId;
  final _title = TextEditingController();
  final _price = TextEditingController();
  String? _imagePath;
  final List<_FeatureDraft> _features = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    final validIds = widget.businessTypes.map((b) => b.id).toSet();
    if (p == null) {
      _businessTypeId = validIds.contains(widget.defaultBusinessType)
          ? widget.defaultBusinessType
          : null;
      _features.add(_FeatureDraft());
      return;
    }
    _businessTypeId = validIds.contains(p.businessTypeId)
        ? p.businessTypeId
        : null;
    _title.text = p.title;
    _price.text = p.price;
    final seen = <int?>{};
    for (final f in p.features) {
      _features.add(
        _FeatureDraft(
          categoryId: f.categoryId,
          name: f.name,
          showCategory: !seen.contains(f.categoryId),
        ),
      );
      seen.add(f.categoryId);
    }
    if (_features.isEmpty) _features.add(_FeatureDraft());
  }

  @override
  void dispose() {
    _title.dispose();
    _price.dispose();
    for (final f in _features) {
      f.dispose();
    }
    super.dispose();
  }

  void _insertAfter(int index, List<String> names, {required bool focus}) {
    final ref = _features[index];
    final drafts = [
      for (final n in names)
        _FeatureDraft(categoryId: ref.categoryId, name: n, showCategory: false),
    ];
    setState(() => _features.insertAll(index + 1, drafts));
    if (focus && drafts.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => drafts.first.focus.requestFocus(),
      );
    }
  }

  void _onFeatureChanged(int index, String value) {
    if (!value.contains('\n')) return;
    final parts = value.split(RegExp(r'\r?\n'));
    final rest = parts
        .skip(1)
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final first = parts.first;
    final draft = _features[index];
    draft.ctrl.value = TextEditingValue(
      text: rest.isEmpty ? first : first.trim(),
      selection: TextSelection.collapsed(
        offset: (rest.isEmpty ? first : first.trim()).length,
      ),
    );
    if (rest.isEmpty) {
      _insertAfter(index, const [''], focus: true);
    } else {
      _insertAfter(index, rest, focus: false);
    }
  }

  void _addMore() {
    final last = _features.isEmpty ? null : _features.last;
    final draft = _FeatureDraft(categoryId: last?.categoryId);
    setState(() => _features.add(draft));
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => draft.focus.requestFocus(),
    );
  }

  Future<void> _save() async {
    if (_businessTypeId == null ||
        _title.text.trim().isEmpty ||
        _price.text.trim().isEmpty) {
      toast(context, 'Business type, plan title and price are required.');
      return;
    }
    setState(() => _saving = true);
    final res = await widget.service.savePricing(
      id: widget.existing?.id,
      businessTypeId: _businessTypeId!,
      title: _title.text,
      price: _price.text.trim(),
      features: [
        for (final f in _features)
          if (f.ctrl.text.trim().isNotEmpty)
            (categoryId: f.categoryId, name: f.ctrl.text.trim()),
      ],
      imagePath: _imagePath,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!res.ok) {
      toast(context, res.message);
      return;
    }
    toast(context, res.message);
    Navigator.of(context).pop(true);
  }

  String _categoryName(int? id) {
    if (id == null) return 'No category';
    for (final c in widget.categories) {
      if (c.id == id) return c.name;
    }
    return 'No category';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final editing = widget.existing != null;
    return _DialogShell(
      title: editing ? 'Edit Pricing Plan' : 'Add Pricing Plan',
      icon: Icons.sell_outlined,
      width: 1040,
      actions: [
        GhostButton(
          label: 'Cancel',
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
        ),
        SignalButton(
          label: 'Save Pricing Plan',
          icon: Icons.save_outlined,
          busy: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _FieldLabel('Business type'),
                  DropdownButtonFormField<int?>(
                    initialValue: _businessTypeId,
                    isExpanded: true,
                    decoration: const InputDecoration(isDense: true),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Select business type'),
                      ),
                      for (final b in widget.businessTypes)
                        DropdownMenuItem<int?>(
                          value: b.id,
                          child: Text(b.name),
                        ),
                    ],
                    onChanged: (v) => setState(() => _businessTypeId = v),
                  ),
                  const SizedBox(height: 14),
                  const _FieldLabel('Plan title'),
                  TextField(
                    controller: _title,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'e.g. Starter, Premium',
                    ),
                  ),
                  const SizedBox(height: 14),
                  const _FieldLabel('Monthly price'),
                  TextField(
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: '0.00',
                    ),
                  ),
                  const SizedBox(height: 14),
                  const _FieldLabel('Plan banner image'),
                  Row(
                    children: [
                      GhostButton(
                        label: 'Choose image',
                        icon: Icons.image_outlined,
                        onPressed: () async {
                          final p = await _pickImage();
                          if (p != null) setState(() => _imagePath = p);
                        },
                      ),
                      const SizedBox(width: 12),
                      if (_imagePath != null)
                        Flexible(
                          child: Text(
                            _fileName(_imagePath!),
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall,
                          ),
                        )
                      else if ((widget.existing?.image ?? '').isEmpty)
                        Text(
                          'No file chosen',
                          style: text.bodySmall?.copyWith(
                            color: context.brand.paperDim,
                          ),
                        ),
                    ],
                  ),
                  if (_imagePath == null &&
                      (widget.existing?.image ?? '').isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          widget.service.uploadUrl(widget.existing!.image),
                          headers: widget.service.api.authHeaders(),
                          width: 160,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 28),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _FieldLabel('Included features'),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 420),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.brand.surfaceHi,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: context.brand.rule),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _features.length,
                      itemBuilder: (_, i) => _featureRow(i),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: GhostButton(
                      label: 'Add feature',
                      icon: Icons.add,
                      onPressed: _addMore,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Enter adds a row below; pasting several lines creates one feature per line.',
                    style: text.bodySmall?.copyWith(
                      color: context.brand.paperDim,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _featureRow(int i) {
    final f = _features[i];
    final text = Theme.of(context).textTheme;
    final validCat = widget.categories.any((c) => c.id == f.categoryId)
        ? f.categoryId
        : null;
    return Padding(
      key: ObjectKey(f),
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 170,
            child: f.showCategory
                ? DropdownButtonFormField<int?>(
                    initialValue: validCat,
                    isExpanded: true,
                    isDense: true,
                    style: text.bodySmall,
                    decoration: const InputDecoration(isDense: true),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('No category'),
                      ),
                      for (final c in widget.categories)
                        DropdownMenuItem<int?>(
                          value: c.id,
                          child: Text(c.name, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setState(() => f.categoryId = v),
                  )
                : Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Text(
                      '↳ ${_categoryName(validCat)}',
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        color: context.brand.paperDim,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: f.ctrl,
              focusNode: f.focus,
              minLines: 1,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              style: text.bodyMedium,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Feature name...',
              ),
              onChanged: (v) => _onFeatureChanged(i, v),
            ),
          ),
          IconButton(
            tooltip: 'Add below',
            visualDensity: VisualDensity.compact,
            onPressed: () => _insertAfter(i, const [''], focus: true),
            icon: const Icon(Icons.add, size: 16, color: Brand.signal),
          ),
          IconButton(
            tooltip: 'Remove',
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _features.removeAt(i).dispose()),
            icon: const Icon(Icons.close, size: 16, color: Colors.redAccent),
          ),
        ],
      ),
    );
  }
}
