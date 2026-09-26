import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../api_client.dart';
import '../models/vendor_models.dart';
import '../services/vendor_admin_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

class VendorsEntryButton extends StatelessWidget {
  const VendorsEntryButton({super.key, required this.api});

  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    return StationAction(
      icon: Icons.storefront_rounded,
      tooltip: 'Vendors management',
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => VendorAdminScreen(service: VendorAdminService(api)),
        ),
      ),
    );
  }
}

class VendorAdminScreen extends StatefulWidget {
  const VendorAdminScreen({super.key, required this.service});

  final VendorAdminService service;

  @override
  State<VendorAdminScreen> createState() => _VendorAdminScreenState();
}

class _VendorAdminScreenState extends State<VendorAdminScreen> {
  static const _pageSize = 25;

  final _searchController = TextEditingController();
  final _scroll = ScrollController();
  Timer? _searchTimer;

  List<VendorRow> _rows = const [];
  int _total = 0;
  int _page = 1;
  String _search = '';
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _requestSeq = 0;
  int _newFilings = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
    _loadNewFilings();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loading || _loadingMore) return;
    if (_rows.length >= _total) return;
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 320) {
      _loadMore();
    }
  }

  Future<void> _loadNewFilings() async {
    final res = await widget.service.newRegistrations();
    if (!mounted) return;
    setState(() => _newFilings = res.count);
  }

  Future<void> _load() async {
    final seq = ++_requestSeq;
    setState(() {
      _loading = _rows.isEmpty;
      _error = null;
    });
    try {
      final page = await widget.service.list(
        search: _search,
        page: 1,
        limit: _pageSize,
      );
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _rows = page.vendors;
        _total = page.total;
        _page = 1;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _loading = false;
        _error = e is HttpException ? e.message : 'Could not load the vendors.';
      });
    }
  }

  Future<void> _refresh() async {
    await Future.wait([_load(), _loadNewFilings()]);
  }

  Future<void> _loadMore() async {
    final seq = _requestSeq;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.service.list(
        search: _search,
        page: _page + 1,
        limit: _pageSize,
      );
      if (!mounted || seq != _requestSeq) return;
      final seen = _rows.map((r) => r.id).toSet();
      setState(() {
        _rows = [..._rows, ...page.vendors.where((r) => !seen.contains(r.id))];
        _total = page.total;
        _page += 1;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _onSearch(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _search = value;
      _load();
    });
  }

  Future<void> _openDetail(VendorRow row) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => VendorDetailScreen(
          service: widget.service,
          vendorId: row.id,
          initial: row,
        ),
      ),
    );
    if (changed == true) _load();
  }

  Future<void> _openLogs(VendorRow row) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => VendorLogsScreen(
          service: widget.service,
          vendorId: row.id,
          title: row.name,
        ),
      ),
    );
  }

  Future<void> _setPrice(VendorRow row) async {
    final changed = await showVendorPriceDialog(
      context,
      service: widget.service,
      vendorId: row.id,
      vendorName: row.name,
      currentCentavos: row.licensePriceCentavos,
    );
    if (changed == true) _load();
  }

  Future<void> _toggleStatus(VendorRow row) async {
    final changed = await showVendorStatusDialog(
      context,
      service: widget.service,
      vendorId: row.id,
      suspended: row.suspended,
    );
    if (changed == true) _load();
  }

  Future<void> _openInvites() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => VendorInvitesScreen(service: widget.service),
      ),
    );
  }

  Future<void> _createInvite() async {
    await createVendorInvite(context, widget.service);
  }

  @override
  Widget build(BuildContext context) {
    return StationScaffold(
      stationNumber: '11',
      stationLabel: 'Admin',
      title: 'Vendors',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StationAction(
            icon: Icons.list_alt_rounded,
            tooltip: 'Generated invites',
            onPressed: _openInvites,
          ),
          const SizedBox(width: 8),
          StationAction(
            icon: Icons.link_rounded,
            tooltip: 'Invite a vendor',
            onPressed: _createInvite,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSearchField(
            controller: _searchController,
            hint: 'Search Vendor ID, company, contact or email',
            onChanged: _onSearch,
            onSubmitted: (v) {
              _searchTimer?.cancel();
              _search = v;
              _load();
            },
          ),
          const SizedBox(height: 14),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: _loading
                  ? const SkeletonList(count: 6)
                  : _error != null
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 48),
                        EmptyState(
                          label: 'Could not load vendors',
                          hint: _error!,
                          icon: Icons.cloud_off_rounded,
                          action: FilledButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('Try again'),
                          ),
                        ),
                      ],
                    )
                  : _rows.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 48),
                        EmptyState(
                          label: _search.trim().isEmpty
                              ? 'No vendor accounts yet'
                              : 'No matching vendors',
                          hint: _search.trim().isEmpty
                              ? 'Invite a vendor to open the first account.'
                              : 'Try a different Vendor ID, company or email.',
                          icon: Icons.storefront_outlined,
                          action: _search.trim().isEmpty
                              ? FilledButton.icon(
                                  onPressed: _createInvite,
                                  icon: const Icon(
                                    Icons.link_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('Invite a vendor'),
                                )
                              : null,
                        ),
                      ],
                    )
                  : ListView.separated(
                      controller: _scroll,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: _rows.length + 2,
                      separatorBuilder: (_, i) =>
                          SizedBox(height: i == 0 ? 12 : 10),
                      itemBuilder: (_, i) {
                        if (i == 0) {
                          return _VendorSummary(
                            total: _total,
                            showing: _rows.length,
                            newFilings: _newFilings,
                          );
                        }
                        if (i == _rows.length + 1) {
                          if (_rows.length >= _total) {
                            return const SizedBox(height: 8);
                          }
                          return const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: SkeletonList(count: 1),
                          );
                        }
                        final row = _rows[i - 1];
                        return _EntryFade(
                          index: i - 1,
                          child: _VendorCard(
                            row: row,
                            onTap: () => _openDetail(row),
                            onAction: (action) {
                              switch (action) {
                                case 'detail':
                                  _openDetail(row);
                                  break;
                                case 'price':
                                  _setPrice(row);
                                  break;
                                case 'logs':
                                  _openLogs(row);
                                  break;
                                case 'status':
                                  _toggleStatus(row);
                                  break;
                              }
                            },
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VendorCard extends StatelessWidget {
  const _VendorCard({
    required this.row,
    required this.onTap,
    required this.onAction,
  });

  final VendorRow row;
  final VoidCallback onTap;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final suspended = row.suspended;
    final subtitle = [
      row.vendorCode,
      if (row.contactPerson.trim().isNotEmpty) row.contactPerson,
    ].where((e) => e.trim().isNotEmpty).join(' · ');

    final tone = suspended ? Brand.danger : Brand.success;
    return AppCard(
      onTap: onTap,
      radius: Brand.radiusLg,
      borderColor: suspended ? tone.withValues(alpha: 0.4) : b.rule,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AppAvatar(name: row.name, size: 42),
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: tone,
                        border: Border.all(color: b.surface, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.name,
                      style: text.titleSmall?.copyWith(
                        color: suspended ? b.paperDim : b.paper,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle.isEmpty ? '—' : subtitle,
                      style: text.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (row.email.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        row.email,
                        style: text.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _GlowPill(
                    label: row.statusLabel,
                    color: tone,
                    icon: suspended ? Icons.block_rounded : Icons.check_rounded,
                  ),
                  const SizedBox(height: 2),
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: PopupMenuButton<String>(
                      tooltip: 'Actions',
                      icon: Icon(Icons.more_vert_rounded, color: b.paperDim),
                      onSelected: onAction,
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'detail',
                          child: _MenuRow(Icons.badge_outlined, 'View details'),
                        ),
                        const PopupMenuItem(
                          value: 'price',
                          child: _MenuRow(
                            Icons.sell_outlined,
                            'Set license key price',
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'logs',
                          child: _MenuRow(
                            Icons.history_rounded,
                            'View activity log',
                          ),
                        ),
                        PopupMenuItem(
                          value: 'status',
                          child: _MenuRow(
                            suspended
                                ? Icons.check_circle_outline_rounded
                                : Icons.block_rounded,
                            suspended ? 'Reactivate vendor' : 'Suspend vendor',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _StatChip(label: 'Filed', value: '${row.submissions}'),
              _StatChip(label: 'Key price', value: row.priceLabel),
              _StatChip(
                label: 'License revenue',
                value: row.keysPaid > 0
                    ? '${vendorMoneyCentavos(row.revenueCentavos)} · ${row.keysPaid}'
                    : '—',
              ),
              _StatChip(
                label: 'Last sign-in',
                value: vendorStamp(row.lastLoginAt, 'Never'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: b.surfaceHi,
        borderRadius: BorderRadius.circular(Brand.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: text.labelMedium?.copyWith(color: b.paperDim)),
          const SizedBox(width: 6),
          Text(
            value,
            style: text.labelMedium?.copyWith(
              color: b.paper,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Row(
      children: [
        Icon(icon, size: 18, color: b.paperDim),
        const SizedBox(width: 10),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

class VendorDetailScreen extends StatefulWidget {
  const VendorDetailScreen({
    super.key,
    required this.service,
    required this.vendorId,
    this.initial,
  });

  final VendorAdminService service;
  final int vendorId;
  final VendorRow? initial;

  @override
  State<VendorDetailScreen> createState() => _VendorDetailScreenState();
}

class _VendorDetailScreenState extends State<VendorDetailScreen> {
  VendorDetail? _detail;
  bool _loading = true;
  String? _error;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _detail == null;
      _error = null;
    });
    try {
      final detail = await widget.service.detail(widget.vendorId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is HttpException ? e.message : 'Could not load the vendor.';
      });
    }
  }

  Future<void> _setPrice() async {
    final vendor = _detail?.vendor ?? widget.initial;
    if (vendor == null) return;
    final changed = await showVendorPriceDialog(
      context,
      service: widget.service,
      vendorId: widget.vendorId,
      vendorName: vendor.name,
      currentCentavos: vendor.licensePriceCentavos,
    );
    if (changed == true) {
      _changed = true;
      await _load();
    }
  }

  Future<void> _toggleStatus() async {
    final vendor = _detail?.vendor ?? widget.initial;
    if (vendor == null) return;
    final changed = await showVendorStatusDialog(
      context,
      service: widget.service,
      vendorId: widget.vendorId,
      suspended: vendor.suspended,
    );
    if (changed == true) {
      _changed = true;
      await _load();
    }
  }

  void _openLogs(VendorRow vendor) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => VendorLogsScreen(
          service: widget.service,
          vendorId: widget.vendorId,
          title: vendor.name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final vendor = _detail?.vendor ?? widget.initial ?? const VendorRow();
    final totals = _detail?.totals ?? const VendorTotals();
    final requests = _detail?.requests ?? const <VendorLicenseRequest>[];
    final suspended = vendor.suspended;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: StationScaffold(
        stationNumber: '11',
        stationLabel: 'Vendor',
        title: vendor.name,
        subtitle: vendor.vendorCode,
        showBottomBrand: false,
        onBack: () => Navigator.of(context).pop(_changed),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StationAction(
              icon: Icons.sell_outlined,
              tooltip: 'Set license key price',
              onPressed: _setPrice,
            ),
            const SizedBox(width: 8),
            StationAction(
              icon: suspended
                  ? Icons.check_circle_outline_rounded
                  : Icons.block_rounded,
              tooltip: suspended ? 'Reactivate vendor' : 'Suspend vendor',
              onPressed: _toggleStatus,
            ),
          ],
        ),
        child: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const SkeletonList(count: 6)
              : _error != null
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    const SizedBox(height: 48),
                    EmptyState(
                      label: 'Could not load the vendor',
                      hint: _error!,
                      icon: Icons.cloud_off_rounded,
                      action: FilledButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Try again'),
                      ),
                    ),
                  ],
                )
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    GlassPanel(
                      accent: suspended ? Brand.danger : Brand.success,
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              AppAvatar(name: vendor.name, size: 38),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      vendor.name.trim().isEmpty
                                          ? 'Vendor'
                                          : vendor.name,
                                      style: text.titleSmall?.copyWith(
                                        color: context.brand.paper,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      vendor.vendorCode.isEmpty
                                          ? '—'
                                          : vendor.vendorCode,
                                      style: text.bodySmall,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                child: _GlowPill(
                                  key: ValueKey(suspended),
                                  label: vendor.statusLabel,
                                  color: suspended
                                      ? Brand.danger
                                      : Brand.success,
                                  icon: suspended
                                      ? Icons.block_rounded
                                      : Icons.check_rounded,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              _GlassMetric(
                                label: 'License revenue',
                                target: totals.revenue,
                                format: vendorMoney,
                                icon: Icons.payments_rounded,
                                color: Brand.success,
                              ),
                              const _GlassDivider(),
                              _GlassMetric(
                                label: 'Keys paid',
                                target: totals.keysPaid.toDouble(),
                                format: (v) => '${v.round()}',
                                icon: Icons.vpn_key_rounded,
                                color: Brand.info,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              _GlassMetric(
                                label:
                                    'Unpaid · ${vendorMoney(totals.pendingValue)}',
                                target: totals.pending.toDouble(),
                                format: (v) => '${v.round()}',
                                icon: Icons.hourglass_bottom_rounded,
                                color: Brand.warning,
                              ),
                              const _GlassDivider(),
                              _GlassMetric(
                                label: 'Registrations filed',
                                target: totals.submissions.toDouble(),
                                format: (v) => '${v.round()}',
                                icon: Icons.assignment_turned_in_rounded,
                                color: Brand.orange,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    const SectionHeader(title: 'Profile'),
                    AppCard(
                      radius: Brand.radiusLg,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          StationDataRow(
                            label: 'Vendor ID',
                            value: vendor.vendorCode.isEmpty
                                ? '—'
                                : vendor.vendorCode,
                          ),
                          StationDataRow(
                            label: 'License key price',
                            value: vendorMoneyCentavos(
                              vendor.licensePriceCentavos,
                            ),
                            onTap: _setPrice,
                            trailingIcon: Icons.edit_rounded,
                          ),
                          StationDataRow(
                            label: 'Contact person',
                            value: vendor.contactPerson.isEmpty
                                ? '—'
                                : vendor.contactPerson,
                          ),
                          StationDataRow(
                            label: 'Email',
                            value: vendor.email.isEmpty ? '—' : vendor.email,
                          ),
                          StationDataRow(
                            label: 'Mobile',
                            value: vendor.mobile.isEmpty ? '—' : vendor.mobile,
                          ),
                          StationDataRow(
                            label: 'Address',
                            value: vendor.address.isEmpty
                                ? '—'
                                : vendor.address,
                          ),
                          StationDataRow(
                            label: 'Status',
                            value: vendor.statusLabel,
                          ),
                          StationDataRow(
                            label: 'Email verified',
                            value: vendor.emailVerified ? 'Yes' : 'No',
                          ),
                          StationDataRow(
                            label: 'Vendor since',
                            value: vendorStamp(vendor.createdAt),
                          ),
                          StationDataRow(
                            label: 'Last sign-in',
                            value: vendorStamp(vendor.lastLoginAt, 'Never'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    SectionHeader(
                      title: 'License key requests',
                      trailing: Text(
                        '${requests.length}',
                        style: text.labelMedium,
                      ),
                    ),
                    if (requests.isEmpty)
                      AppCard(
                        radius: Brand.radiusLg,
                        child: Text(
                          'No license key requests yet.',
                          style: text.bodySmall,
                        ),
                      )
                    else
                      for (var i = 0; i < requests.length; i++) ...[
                        _EntryFade(
                          index: i,
                          child: _RequestCard(request: requests[i]),
                        ),
                        const SizedBox(height: 10),
                      ],
                    const SizedBox(height: 8),
                    const SectionHeader(title: 'Activity'),
                    AppCard(
                      radius: Brand.radiusLg,
                      onTap: () => _openLogs(vendor),
                      child: Row(
                        children: [
                          const IconTile(
                            icon: Icons.history_rounded,
                            size: 38,
                            iconSize: 19,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Vendor activity', style: text.titleSmall),
                                const SizedBox(height: 2),
                                Text(
                                  'Sign-ins, filings and account changes',
                                  style: text.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: context.brand.paperDim,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request});

  final VendorLicenseRequest request;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final mono = text.bodySmall?.copyWith(
      fontFamily: 'monospace',
      color: b.paper,
    );
    return AppCard(
      radius: Brand.radiusLg,
      borderColor: request.paid
          ? Brand.success.withValues(alpha: 0.3)
          : Brand.warning.withValues(alpha: 0.35),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            request.businessName.isEmpty
                                ? '—'
                                : request.businessName,
                            style: text.titleSmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (request.quantity > 1) ...[
                          const SizedBox(width: 8),
                          _GlowPill(
                            label: '×${request.quantity}',
                            color: Brand.orange,
                          ),
                        ],
                      ],
                    ),
                    if (request.tin.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(request.tin, style: text.bodySmall),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    request.paid ? vendorMoney(request.amount) : 'unpaid',
                    style: text.titleSmall?.copyWith(
                      color: request.paid ? Brand.success : Brand.warning,
                    ),
                  ),
                  if (request.quantity > 1 && request.unitAmount > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${request.quantity} × ${vendorMoney(request.unitAmount)}',
                      style: text.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    vendorStamp(
                      request.paidAt.isNotEmpty
                          ? request.paidAt
                          : request.createdAt,
                    ),
                    style: text.bodySmall,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (request.keys.isEmpty)
            Text('not issued', style: text.bodySmall)
          else
            for (final k in request.keys)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(child: SelectableText(k.key, style: mono)),
                    const SizedBox(width: 8),
                    Text(
                      k.isUsed ? 'IN USE' : 'not used',
                      style: text.labelMedium?.copyWith(
                        color: k.isUsed ? Brand.success : b.paperDim,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
          if (request.keys.isNotEmpty && request.pendingKeys > 0)
            Text(
              '${request.pendingKeys} of ${request.quantity} still to issue',
              style: text.bodySmall?.copyWith(color: Brand.warning),
            ),
        ],
      ),
    );
  }
}

class VendorLogsScreen extends StatefulWidget {
  const VendorLogsScreen({
    super.key,
    required this.service,
    required this.vendorId,
    this.title = 'Vendor activity',
  });

  final VendorAdminService service;
  final int vendorId;
  final String title;

  @override
  State<VendorLogsScreen> createState() => _VendorLogsScreenState();
}

class _VendorLogsScreenState extends State<VendorLogsScreen> {
  static const _pageSize = 30;

  final _searchController = TextEditingController();
  final _scroll = ScrollController();
  Timer? _searchTimer;

  List<VendorLogEntry> _logs = const [];
  int _total = 0;
  String _search = '';
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _requestSeq = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loading || _loadingMore) return;
    if (_logs.length >= _total) return;
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 320) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    final seq = ++_requestSeq;
    setState(() {
      _loading = _logs.isEmpty;
      _error = null;
    });
    try {
      final page = await widget.service.logs(
        widget.vendorId,
        limit: _pageSize,
        offset: 0,
        search: _search,
      );
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _logs = page.logs;
        _total = page.total;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _loading = false;
        _error = e is HttpException
            ? e.message
            : 'Could not load the activity log.';
      });
    }
  }

  Future<void> _loadMore() async {
    final seq = _requestSeq;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.service.logs(
        widget.vendorId,
        limit: _pageSize,
        offset: _logs.length,
        search: _search,
      );
      if (!mounted || seq != _requestSeq) return;
      final seen = _logs.map((l) => l.id).toSet();
      setState(() {
        _logs = [..._logs, ...page.logs.where((l) => !seen.contains(l.id))];
        _total = page.total;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _onSearch(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _search = value;
      _logs = const [];
      _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return StationScaffold(
      stationNumber: '11',
      stationLabel: 'Vendor',
      title: 'Activity',
      subtitle: widget.title,
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSearchField(
            controller: _searchController,
            hint: 'Search action or details',
            onChanged: _onSearch,
          ),
          const SizedBox(height: 14),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const SkeletonList(count: 7, avatar: false)
                  : _error != null
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 48),
                        EmptyState(
                          label: 'Could not load the activity log',
                          hint: _error!,
                          icon: Icons.cloud_off_rounded,
                          action: FilledButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('Try again'),
                          ),
                        ),
                      ],
                    )
                  : _logs.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 48),
                        EmptyState(
                          label: 'No activity recorded yet',
                          hint: 'Vendor sign-ins and filings will show here.',
                          icon: Icons.history_rounded,
                        ),
                      ],
                    )
                  : ListView.separated(
                      controller: _scroll,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: _logs.length + 1,
                      separatorBuilder: (_, i) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        if (i == _logs.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              'Showing the latest ${_logs.length} of $_total '
                              '${_total == 1 ? 'entry' : 'entries'}.',
                              style: text.bodySmall,
                            ),
                          );
                        }
                        final log = _logs[i];
                        return ActivityRow(
                          title: log.actionLabel.isEmpty
                              ? 'activity'
                              : log.actionLabel,
                          subtitle: log.details.isEmpty ? '—' : log.details,
                          meta: vendorStamp(log.createdAt),
                          icon: Icons.bolt_rounded,
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class VendorInvitesScreen extends StatefulWidget {
  const VendorInvitesScreen({super.key, required this.service});

  final VendorAdminService service;

  @override
  State<VendorInvitesScreen> createState() => _VendorInvitesScreenState();
}

class _VendorInvitesScreenState extends State<VendorInvitesScreen> {
  List<VendorInvite> _invites = const [];
  bool _loading = true;
  String? _error;
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _invites.isEmpty;
      _error = null;
    });
    try {
      final page = await widget.service.invites(limit: 30);
      if (!mounted) return;
      setState(() {
        _invites = page.invites;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is HttpException ? e.message : 'Could not load invites.';
      });
    }
  }

  Future<void> _revoke(VendorInvite invite) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const IconTile(
          icon: Icons.link_off_rounded,
          color: Brand.danger,
          size: 44,
          iconSize: 22,
        ),
        title: const Text('Revoke this invite?'),
        content: const Text(
          'The link stops working right away. Nobody can use it to create a '
          'vendor account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Brand.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy.add(invite.id));
    final res = await widget.service.revokeInvite(invite.id);
    if (!mounted) return;
    setState(() {
      _busy.remove(invite.id);
      if (res.ok) {
        _invites = _invites
            .map((i) => i.id == invite.id ? i.asRevoked() : i)
            .toList();
      }
    });
    _toast(context, res.message ?? 'Invite revoked.');
  }

  Future<void> _create() async {
    final created = await createVendorInvite(context, widget.service);
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return StationScaffold(
      stationNumber: '11',
      stationLabel: 'Vendor',
      title: 'Invites',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      trailing: StationAction(
        icon: Icons.link_rounded,
        tooltip: 'Invite a vendor',
        onPressed: _create,
      ),
      child: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const SkeletonList(count: 6, avatar: false)
            : _error != null
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 48),
                  EmptyState(
                    label: 'Could not load invites',
                    hint: _error!,
                    icon: Icons.cloud_off_rounded,
                    action: FilledButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Try again'),
                    ),
                  ),
                ],
              )
            : _invites.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 48),
                  EmptyState(
                    label: 'No invites issued yet',
                    hint: 'Vendor registration is invite-only.',
                    icon: Icons.link_off_rounded,
                    action: FilledButton.icon(
                      onPressed: _create,
                      icon: const Icon(Icons.link_rounded, size: 18),
                      label: const Text('Invite a vendor'),
                    ),
                  ),
                ],
              )
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: _invites.length + 1,
                separatorBuilder: (_, i) => SizedBox(height: i == 0 ? 12 : 10),
                itemBuilder: (_, i) {
                  if (i == 0) {
                    return Text(
                      '${_invites.length} '
                      '${_invites.length == 1 ? 'invite' : 'invites'}',
                      style: text.titleMedium,
                    );
                  }
                  final invite = _invites[i - 1];
                  return _InviteCard(
                    invite: invite,
                    busy: _busy.contains(invite.id),
                    onRevoke: () => _revoke(invite),
                  );
                },
              ),
      ),
    );
  }
}

Color _inviteColor(VendorInviteState state) {
  switch (state) {
    case VendorInviteState.used:
      return Brand.info;
    case VendorInviteState.revoked:
      return Brand.warning;
    case VendorInviteState.active:
      return Brand.success;
    case VendorInviteState.expired:
      return Brand.danger;
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({
    required this.invite,
    required this.busy,
    required this.onRevoke,
  });

  final VendorInvite invite;
  final bool busy;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AppCard(
      radius: Brand.radiusLg,
      borderColor: _inviteColor(invite.state).withValues(alpha: 0.3),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  invite.note.trim().isEmpty ? '—' : invite.note,
                  style: text.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _GlowPill(
                label: invite.stateLabel,
                color: _inviteColor(invite.state),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _StatChip(label: 'Key price', value: invite.priceLabel),
              _StatChip(label: 'Expires', value: vendorStamp(invite.expiresAt)),
              _StatChip(
                label: 'Issued by',
                value: invite.createdByName.trim().isEmpty
                    ? '—'
                    : invite.createdByName,
              ),
            ],
          ),
          if (invite.canRevoke) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: busy
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : GhostButton(
                      label: 'Revoke',
                      icon: Icons.link_off_rounded,
                      onPressed: onRevoke,
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InviteDraft {
  const _InviteDraft(this.note, this.hours, this.price);

  final String note;
  final int hours;
  final String price;
}

Future<bool?> createVendorInvite(
  BuildContext context,
  VendorAdminService service,
) async {
  final draft = await showDialog<_InviteDraft>(
    context: context,
    builder: (_) => const _InviteDialog(),
  );
  if (draft == null || !context.mounted) return null;

  VendorInviteLink? link;
  String? error;
  try {
    link = await service.createInvite(
      note: draft.note,
      hours: draft.hours,
      licensePrice: draft.price,
    );
  } catch (e) {
    error = e is HttpException ? e.message : 'Failed to generate the token.';
  }
  if (!context.mounted) return null;
  if (link == null) {
    _toast(context, error ?? 'Failed to generate the token.');
    return null;
  }

  final created = link;
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      final text = Theme.of(ctx).textTheme;
      final b = ctx.brand;
      return AlertDialog(
        icon: const IconTile(icon: Icons.link_rounded, size: 44, iconSize: 22),
        title: const Text('Vendor invitation link'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Single use. Expires in ${created.expiresInHours} hours. '
                'Anyone with this link can create one vendor account, priced '
                'at ${created.licensePriceLabel} per license key.',
                style: text.bodySmall,
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: b.surfaceHi,
                  borderRadius: BorderRadius.circular(Brand.radiusSm),
                ),
                child: SelectableText(created.url, style: text.bodySmall),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Done'),
          ),
          FilledButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: created.url));
              final messenger = ScaffoldMessenger.of(ctx);
              Navigator.of(ctx).pop();
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(const SnackBar(content: Text('Link copied')));
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copy'),
          ),
        ],
      );
    },
  );
  return true;
}

class _InviteDialog extends StatefulWidget {
  const _InviteDialog();

  @override
  State<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<_InviteDialog> {
  final _noteController = TextEditingController();
  final _priceController = TextEditingController();
  int _hours = 48;
  String? _priceError;

  @override
  void dispose() {
    _noteController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  void _submit() {
    final error = vendorPriceError(_priceController.text);
    if (error != null) {
      setState(
        () => _priceError =
            'Set a license key price of at least ₱1.00 for this vendor.',
      );
      return;
    }
    Navigator.of(context).pop(
      _InviteDraft(_noteController.text.trim(), _hours, _priceController.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      icon: const IconTile(icon: Icons.link_rounded, size: 44, iconSize: 22),
      title: const Text('Invite a vendor'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Vendor registration is invite-only. This mints a single-use '
              'token that opens the vendor sign-up form.',
              style: text.bodySmall,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _noteController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Who is this for? (optional)',
                hintText: 'Juan Trading Corp.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _priceController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) {
                if (_priceError != null) setState(() => _priceError = null);
              },
              decoration: InputDecoration(
                labelText: 'License key price',
                hintText: '3500.00',
                prefixText: '₱ ',
                errorText: _priceError,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'What this vendor pays per license key request. Locked in on '
              'their account at sign-up; you can change it later from the '
              'vendor row.',
              style: text.bodySmall,
            ),
            const SizedBox(height: 14),
            Text('Valid for', style: text.bodySmall),
            const SizedBox(height: 6),
            ChoicePills<int>(
              options: kVendorInviteHours,
              value: _hours,
              onChanged: (v) => setState(() => _hours = v),
              labelOf: vendorInviteHoursLabel,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.link_rounded, size: 18),
          label: const Text('Generate'),
        ),
      ],
    );
  }
}

Future<bool?> showVendorPriceDialog(
  BuildContext context, {
  required VendorAdminService service,
  required int vendorId,
  required String vendorName,
  required int currentCentavos,
}) async {
  final price = await showDialog<String>(
    context: context,
    builder: (_) =>
        _PriceDialog(vendorName: vendorName, currentCentavos: currentCentavos),
  );
  if (price == null || !context.mounted) return null;
  final res = await service.setLicensePrice(vendorId, price);
  if (!context.mounted) return null;
  _toast(context, res.message ?? 'Could not update the price.');
  return res.ok;
}

class _PriceDialog extends StatefulWidget {
  const _PriceDialog({required this.vendorName, required this.currentCentavos});

  final String vendorName;
  final int currentCentavos;

  @override
  State<_PriceDialog> createState() => _PriceDialogState();
}

class _PriceDialogState extends State<_PriceDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.currentCentavos > 0
        ? (widget.currentCentavos / 100).toStringAsFixed(2)
        : '',
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final error = vendorPriceError(_controller.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      icon: const IconTile(icon: Icons.sell_outlined, size: 44, iconSize: 22),
      title: const Text('License key price'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'What ${widget.vendorName} pays per license key request. New '
            'requests use the new price; already-paid ones are untouched.',
            style: text.bodySmall,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Price',
              hintText: '3500.00',
              prefixText: '₱ ',
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save price')),
      ],
    );
  }
}

Future<bool?> showVendorStatusDialog(
  BuildContext context, {
  required VendorAdminService service,
  required int vendorId,
  required bool suspended,
}) async {
  final suspending = !suspended;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: IconTile(
        icon: suspending
            ? Icons.block_rounded
            : Icons.check_circle_outline_rounded,
        color: suspending ? Brand.danger : Brand.success,
        size: 44,
        iconSize: 22,
      ),
      title: Text(
        suspending ? 'Suspend this vendor?' : 'Reactivate this vendor?',
      ),
      content: Text(
        suspending
            ? 'They will be signed out of new sessions and blocked from '
                  'filing registrations. Existing submissions are untouched.'
            : 'They will be able to sign in and file registrations again.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: suspending ? Brand.danger : Brand.signal,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(suspending ? 'Suspend' : 'Reactivate'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return null;
  final res = await service.setStatus(
    vendorId,
    suspending ? 'suspended' : 'active',
  );
  if (!context.mounted) return null;
  _toast(context, res.message ?? 'Could not update the vendor.');
  return res.ok;
}

class _GlassDivider extends StatelessWidget {
  const _GlassDivider();

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Container(
      width: 1,
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: b.isDark
          ? Colors.white.withValues(alpha: 0.12)
          : Brand.navy.withValues(alpha: 0.1),
    );
  }
}

class _GlassMetric extends StatelessWidget {
  const _GlassMetric({
    required this.label,
    required this.target,
    required this.format,
    required this.icon,
    required this.color,
  });

  final String label;
  final double target;
  final String Function(double) format;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final value = reduce
        ? Text(
            format(target),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.titleLarge?.copyWith(color: b.paper, fontSize: 21),
          )
        : TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: target),
            duration: const Duration(milliseconds: 560),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => Text(
              format(v),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.titleLarge?.copyWith(color: b.paper, fontSize: 21),
            ),
          );
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelSmall?.copyWith(color: b.paperDim),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          value,
        ],
      ),
    );
  }
}

class _VendorSummary extends StatelessWidget {
  const _VendorSummary({
    required this.total,
    required this.showing,
    required this.newFilings,
  });

  final int total;
  final int showing;
  final int newFilings;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Vendor network',
                  style: text.titleSmall?.copyWith(color: b.paper),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: newFilings > 0
                    ? _GlowPill(
                        key: const ValueKey('filings'),
                        label: '$newFilings new filed',
                        color: Brand.orange,
                        dot: true,
                      )
                    : const GlowBadge(
                        key: ValueKey('live'),
                        label: 'Live',
                        icon: Icons.bolt_rounded,
                      ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _GlassMetric(
                label: 'Vendors',
                target: total.toDouble(),
                format: (v) => '${v.round()}',
                icon: Icons.storefront_rounded,
                color: b.signal,
              ),
              const _GlassDivider(),
              _GlassMetric(
                label: 'Showing',
                target: showing.toDouble(),
                format: (v) => '${v.round()}',
                icon: Icons.visibility_rounded,
                color: Brand.info,
              ),
              const _GlassDivider(),
              _GlassMetric(
                label: 'New filed',
                target: newFilings.toDouble(),
                format: (v) => '${v.round()}',
                icon: Icons.fiber_new_rounded,
                color: Brand.success,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GlowPill extends StatelessWidget {
  const _GlowPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.dot = false,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final ink = b.isDark
        ? color
        : Color.lerp(color, const Color(0xFF0B1B2E), 0.3)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: b.isDark ? 0.18 : 0.12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: ink, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ] else if (icon != null) ...[
            Icon(icon, size: 13, color: ink),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: ink,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryFade extends StatelessWidget {
  const _EntryFade({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) return child;
    final delay = (index.clamp(0, 7)) * 55;
    final total = 300 + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: Curves.easeOutCubic),
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 14),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
