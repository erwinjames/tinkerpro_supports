import 'dart:async';

import 'package:flutter/material.dart';

import '../models/client_models.dart';
import '../services/client_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'client_detail_screen.dart';
import 'client_form_screen.dart';
import 'delivery_pane.dart';

enum _InvoiceFilter { all, withInvoice, noInvoice }

class ClientListScreen extends StatefulWidget {
  const ClientListScreen({super.key, required this.service});
  final ClientService service;

  @override
  State<ClientListScreen> createState() => _ClientListScreenState();
}

class _ClientListScreenState extends State<ClientListScreen>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  final GlobalKey<DeliveryPaneState> _deliveryKey =
      GlobalKey<DeliveryPaneState>();
  late final TabController _tabs;
  Timer? _debounce;
  List<ClientBrief> _rows = const [];
  bool _loading = true;
  int _readyCount = 0;
  _InvoiceFilter _filter = _InvoiceFilter.all;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this)..addListener(_onTabChanged);
    _load();
    _prefetchReadyCount();
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabs.indexIsChanging || !mounted) return;
    setState(() {});
  }

  Future<void> _prefetchReadyCount() async {
    final count = await widget.service.readyDeliveryCount();
    if (!mounted) return;
    setState(() => _readyCount = count);
  }

  Future<void> _load({String? search}) async {
    setState(() => _loading = true);
    final res = await widget.service.list(search: search);
    if (!mounted) return;
    setState(() {
      _rows = res.rows;
      _loading = false;
    });
  }

  void _onSearchChanged(String value) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _load(search: value);
    });
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ClientFormScreen(service: widget.service),
      ),
    );
    if (created == true) _load(search: _searchController.text);
  }

  List<ClientBrief> get _visible {
    switch (_filter) {
      case _InvoiceFilter.all:
        return _rows;
      case _InvoiceFilter.withInvoice:
        return _rows.where((c) => c.invoiceNumber.trim().isNotEmpty).toList();
      case _InvoiceFilter.noInvoice:
        return _rows.where((c) => c.invoiceNumber.trim().isEmpty).toList();
    }
  }

  int _countFor(_InvoiceFilter f) {
    switch (f) {
      case _InvoiceFilter.all:
        return _rows.length;
      case _InvoiceFilter.withInvoice:
        return _rows.where((c) => c.invoiceNumber.trim().isNotEmpty).length;
      case _InvoiceFilter.noInvoice:
        return _rows.where((c) => c.invoiceNumber.trim().isEmpty).length;
    }
  }

  String _labelFor(_InvoiceFilter f) {
    switch (f) {
      case _InvoiceFilter.all:
        return 'All';
      case _InvoiceFilter.withInvoice:
        return 'With invoice';
      case _InvoiceFilter.noInvoice:
        return 'No invoice';
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final onDelivery = _tabs.index == 1;
    return StationScaffold(
      stationNumber: '15',
      stationLabel: 'Client data sheet',
      title: 'Clients',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      trailing: onDelivery
          ? StationAction(
              icon: Icons.refresh_rounded,
              tooltip: 'Refresh',
              onPressed: () => _deliveryKey.currentState?.refresh(),
            )
          : StationAction(
              icon: Icons.add_rounded,
              tooltip: 'New client',
              onPressed: _openCreate,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: b.surfaceHi,
              borderRadius: BorderRadius.circular(Brand.radius),
            ),
            child: TabBar(
              controller: _tabs,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: b.isDark ? const Color(0xFF12304F) : Brand.navy,
                borderRadius: BorderRadius.circular(Brand.radiusSm + 1),
              ),
              labelColor: Colors.white,
              unselectedLabelColor: b.paperDim,
              labelStyle: text.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              unselectedLabelStyle: text.labelLarge,
              dividerColor: Colors.transparent,
              splashBorderRadius: BorderRadius.circular(Brand.radiusSm + 1),
              tabs: [
                const Tab(
                  height: 40,
                  child: _TabLabel(
                    icon: Icons.groups_2_rounded,
                    label: 'Clients',
                  ),
                ),
                Tab(
                  height: 40,
                  child: _TabLabel(
                    icon: Icons.local_shipping_rounded,
                    label: 'Delivery',
                    badge: _readyCount,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _clientsTab(),
                DeliveryPane(
                  key: _deliveryKey,
                  service: widget.service,
                  onReadyCount: (count) {
                    if (!mounted || count == _readyCount) return;
                    setState(() => _readyCount = count);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _clientsTab() {
    final b = context.brand;
    final rows = _visible;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSearchField(
          controller: _searchController,
          hint: 'Search by name or invoice',
          onChanged: _onSearchChanged,
        ),
        const SizedBox(height: 12),
        ChoicePills<_InvoiceFilter>(
          options: _InvoiceFilter.values,
          value: _filter,
          onChanged: (v) => setState(() => _filter = v),
          labelOf: _labelFor,
          countOf: _loading ? null : _countFor,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: RefreshIndicator(
            color: b.signal,
            backgroundColor: b.surface,
            onRefresh: () => _load(search: _searchController.text),
            child: _loading
                ? const SkeletonList(count: 7)
                : rows.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 48),
                      EmptyState(
                        icon: Icons.storefront_rounded,
                        label: 'No clients',
                        hint:
                            'Nothing matched. Tap + to add a data sheet, or pull to refresh.',
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final c = rows[i];
                      return _Entry(
                        index: i,
                        child: _ClientRow(
                          client: c,
                          onTap: () async {
                            final changed = await Navigator.of(context)
                                .push<bool>(
                                  MaterialPageRoute<bool>(
                                    builder: (_) => ClientDetailScreen(
                                      service: widget.service,
                                      brief: c,
                                    ),
                                  ),
                                );
                            if (changed == true) {
                              _load(search: _searchController.text);
                            }
                          },
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel({required this.icon, required this.label, this.badge = 0});

  final IconData icon;
  final String label;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 6),
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        if (badge > 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: Brand.orange,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$badge',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
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

class _ClientRow extends StatelessWidget {
  const _ClientRow({required this.client, required this.onTap});
  final ClientBrief client;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final hasInvoice = client.invoiceNumber.trim().isNotEmpty;
    final name = client.name.isEmpty ? 'Untitled client' : client.name;
    final b = context.brand;
    return AppCard(
      onTap: onTap,
      radius: Brand.radiusLg,
      borderColor: hasInvoice ? Brand.success.withValues(alpha: 0.3) : null,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          AppAvatar(name: name, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: text.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  hasInvoice ? 'Invoice ${client.invoiceNumber}' : 'No invoice',
                  style: text.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              hasInvoice
                  ? const GlowBadge(
                      label: 'Invoiced',
                      color: Brand.success,
                      icon: Icons.verified_rounded,
                    )
                  : StatusPill(
                      label: 'No invoice',
                      color: b.paperDim,
                      dot: true,
                    ),
              if (client.birImported) ...[
                const SizedBox(height: 6),
                const GlowBadge(
                  label: 'In BIR',
                  color: Brand.info,
                  icon: Icons.file_present_rounded,
                ),
              ],
            ],
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, size: 20, color: b.paperDim),
        ],
      ),
    );
  }
}
