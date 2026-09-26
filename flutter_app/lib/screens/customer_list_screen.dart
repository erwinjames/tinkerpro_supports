import 'dart:async';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/bir_v1_service.dart';
import '../services/notification_center.dart';
import '../services/services.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'bir_register_flow.dart';
import 'bir_register_widgets.dart';
import 'bir_v1_screen.dart';
import 'customer_detail_screen.dart';
import 'notification_panel.dart';

class CustomerListScreen extends StatefulWidget {
  const CustomerListScreen({
    super.key,
    required this.service,
    required this.notifications,
    this.onBack,
  });
  final CustomerService service;
  final NotificationCenter notifications;
  final VoidCallback? onBack;

  @override
  State<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends State<CustomerListScreen> {
  final _searchController = TextEditingController();
  final GlobalKey<BirV1PaneState> _v1Key = GlobalKey<BirV1PaneState>();
  Timer? _debounce;
  List<CustomerBrief> _rows = const [];
  bool _loading = true;
  String _status = 'all';
  late final BirV1Service _v1Service;
  bool _v1Enabled = false;
  bool _showV1 = false;
  int? _v1Total;

  @override
  void initState() {
    super.initState();
    _v1Service = BirV1Service(widget.service.api);
    _v1Enabled = _v1Service.canAccess;
    _load();
    if (_v1Enabled) _loadV1Total();
    widget.notifications.addListener(_onNotificationsChanged);
  }

  Future<void> _loadV1Total() async {
    try {
      final total = await _v1Service.total();
      if (!mounted) return;
      setState(() => _v1Total = total);
    } catch (_) {}
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    widget.notifications.removeListener(_onNotificationsChanged);
    super.dispose();
  }

  void _onNotificationsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load({String? search}) async {
    setState(() => _loading = true);
    final rows = await widget.service.list(search: search);
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
    widget.notifications.refresh();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _load(search: value);
    });
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => BirRegisterFlowScreen(service: widget.service),
      ),
    );
    if (created == true) _load(search: _searchController.text);
  }

  List<CustomerBrief> get _visible {
    if (_status == 'all') return _rows;
    return _rows.where((c) => c.status == _status).toList();
  }

  Future<void> _openDetail(CustomerBrief c) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => CustomerDetailScreen(service: widget.service, brief: c),
      ),
    );
    if (changed == true) {
      _load(search: _searchController.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final rows = _visible;
    const filters = <(String, String)>[
      ('all', 'All'),
      (kCustomerStatusCompleted, kCustomerStatusCompleted),
      (kCustomerStatusUploadPtu, kCustomerStatusUploadPtu),
      (kCustomerStatusContinue, kCustomerStatusContinue),
      (kCustomerStatusPending, kCustomerStatusPending),
    ];
    const versions = <(String, String)>[
      ('v2', 'Version 2'),
      ('v1', 'Version 1'),
    ];
    return StationScaffold(
      stationNumber: '04',
      stationLabel: 'BIR Registration',
      title: 'Clients',
      showBottomBrand: false,
      onBack: widget.onBack,
      backAlways: widget.onBack != null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          NotificationBell(
            count: widget.notifications.unseenCount,
            onPressed: () =>
                NotificationPanel.show(context, widget.notifications),
            tooltip: 'Notifications',
          ),
          const SizedBox(width: 8),
          StationAction(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh',
            onPressed: () {
              if (_showV1) {
                _v1Key.currentState?.reload();
                _loadV1Total();
              } else {
                _load(search: _searchController.text);
              }
            },
          ),
          if (!_showV1) ...[
            const SizedBox(width: 8),
            AppIconButton(
              icon: Icons.add_rounded,
              tooltip: 'New client',
              color: b.signal,
              onPressed: _openCreate,
            ),
          ],
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_v1Enabled) ...[
            ChoicePills<(String, String)>(
              options: versions,
              value: versions.firstWhere(
                (v) => v.$1 == (_showV1 ? 'v1' : 'v2'),
                orElse: () => versions.first,
              ),
              labelOf: (v) => v.$2,
              countOf: (v) => v.$1 == 'v1' ? _v1Total : null,
              onChanged: (v) {
                final next = v.$1 == 'v1';
                if (next == _showV1) return;
                setState(() => _showV1 = next);
              },
            ),
            const SizedBox(height: 12),
          ],
          if (_showV1)
            Expanded(
              child: BirV1Pane(
                key: _v1Key,
                service: _v1Service,
                onTotal: (total) {
                  if (!mounted || _v1Total == total) return;
                  setState(() => _v1Total = total);
                },
              ),
            )
          else ...[
            AppSearchField(
              controller: _searchController,
              hint: 'Search TIN, company or owner',
              onChanged: _onSearchChanged,
            ),
            const SizedBox(height: 12),
            ChoicePills<(String, String)>(
              options: filters,
              value: filters.firstWhere(
                (f) => f.$1 == _status,
                orElse: () => filters.first,
              ),
              labelOf: (f) => f.$2,
              countOf: _loading
                  ? null
                  : (f) => f.$1 == 'all'
                        ? _rows.length
                        : _rows.where((c) => c.status == f.$1).length,
              onChanged: (f) => setState(() => _status = f.$1),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: RefreshIndicator(
                color: b.signal,
                backgroundColor: b.surface,
                onRefresh: () => _load(search: _searchController.text),
                child: _loading
                    ? const SkeletonList()
                    : rows.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 48),
                          EmptyState(
                            icon: Icons.business_rounded,
                            label: 'No clients',
                            hint:
                                'Nothing matched your search. Pull down to refresh.',
                          ),
                        ],
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final c = rows[i];
                          return FadeSlideIn(
                            key: ValueKey<int>(c.id),
                            index: i,
                            child: _CustomerRow(
                              customer: c,
                              onTap: () => _openDetail(c),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({required this.customer, required this.onTap});
  final CustomerBrief customer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = customer;
    final accentColor = customerStatusColor(c.status);
    final tin = c.tin.isEmpty
        ? ''
        : (c.branchCode.isEmpty ? c.tin : '${c.tin}-${c.branchCode}');
    final accent = accentColor;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      radius: Brand.radiusLg,
      borderColor: context.brand.isDark ? accent.withValues(alpha: 0.22) : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppAvatar(name: c.companyName),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.companyName,
                  style: text.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  c.ownerName.isEmpty ? '—' : c.ownerName,
                  style: text.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (tin.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.badge_rounded,
                        size: 14,
                        color: context.brand.paperDim,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          tin,
                          style: text.labelMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GlowStatusPill(label: c.status, color: accent, dot: true),
              if (c.fromClientPortal) ...[
                const SizedBox(height: 6),
                GlowStatusPill(
                  label: 'Client',
                  color: Brand.navy,
                  icon: Icons.public_rounded,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
