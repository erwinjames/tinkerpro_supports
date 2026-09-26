import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api_client.dart';
import '../models/delivery_models.dart';
import '../services/client_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'delivery_detail_screen.dart';

const String kDeliveryStatusPrefKey = 'tp.delivery.statusFilter';

Color deliveryStatusColor(BuildContext context, String status) {
  switch (status) {
    case 'Delivered':
      return Brand.success;
    case 'Ready for Delivery':
      return Brand.info;
    case 'Out for Delivery':
      return Brand.warning;
    case 'Cancelled':
      return Brand.danger;
    default:
      return context.brand.paperDim;
  }
}

IconData deliveryStatusIcon(String status) {
  switch (status) {
    case 'Delivered':
      return Icons.task_alt_rounded;
    case 'Ready for Delivery':
      return Icons.inventory_2_rounded;
    case 'Out for Delivery':
      return Icons.local_shipping_rounded;
    case 'Cancelled':
      return Icons.block_rounded;
    default:
      return Icons.local_shipping_rounded;
  }
}

void deliveryToast(BuildContext context, String message) {
  if (message.trim().isEmpty) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

String deliveryErrorText(Object error, String fallback) {
  if (error is DeliveryException) {
    return error.message.trim().isEmpty ? fallback : error.message;
  }
  if (error is HttpException) {
    return error.message.trim().isEmpty ? fallback : error.message;
  }
  return fallback;
}

String deliveryDateLine(String raw) {
  final value = raw.trim();
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(value);
  if (match == null) return value;
  const months = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  const days = <String>[
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final date = DateTime(year, month, day);
  final dd = day.toString().padLeft(2, '0');
  return '${months[month - 1]} $dd, $year · ${days[date.weekday - 1]}';
}

class DeliveryPane extends StatefulWidget {
  const DeliveryPane({super.key, required this.service, this.onReadyCount});

  final ClientService service;
  final ValueChanged<int>? onReadyCount;

  @override
  State<DeliveryPane> createState() => DeliveryPaneState();
}

class DeliveryPaneState extends State<DeliveryPane>
    with AutomaticKeepAliveClientMixin {
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<DeliveryBrief> _rows = const [];
  Set<String> _statuses = <String>{'Ready for Delivery', 'Out for Delivery'};
  String _term = '';
  bool _loading = true;
  bool _refreshing = false;
  String _error = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _restoreStatuses();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _restoreStatuses() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(kDeliveryStatusPrefKey);
      if (saved == null || !mounted) return;
      setState(() {
        _statuses = saved.where(kDeliveryStatuses.contains).toSet();
      });
    } catch (_) {}
  }

  Future<void> _saveStatuses() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(kDeliveryStatusPrefKey, _statuses.toList());
    } catch (_) {}
  }

  Future<void> refresh() => _load(force: true);

  Future<void> _load({bool force = false}) async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      if (_rows.isEmpty) _loading = true;
    });
    try {
      final res = await widget.service.deliveries(force: force);
      if (!mounted) return;
      setState(() {
        _rows = res.rows;
        _loading = false;
        _refreshing = false;
        _error = '';
      });
      widget.onReadyCount?.call(res.readyCount);
      if (res.stale && res.message.isNotEmpty) {
        deliveryToast(context, res.message);
      }
    } catch (e) {
      if (!mounted) return;
      final message = deliveryErrorText(
        e,
        force ? 'Failed to refresh deliveries.' : 'Failed to load delivery.',
      );
      setState(() {
        _loading = false;
        _refreshing = false;
        if (_rows.isEmpty) _error = message;
      });
      if (_rows.isNotEmpty) deliveryToast(context, message);
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _term = value.trim().toLowerCase());
    });
  }

  void _toggleStatus(String status) {
    setState(() {
      if (_statuses.contains(status)) {
        _statuses.remove(status);
      } else {
        _statuses.add(status);
      }
      _statuses = _statuses.toSet();
    });
    _saveStatuses();
  }

  bool get _statusActive =>
      _statuses.isNotEmpty && _statuses.length < kDeliveryStatuses.length;

  List<DeliveryBrief> get _visible {
    return _rows.where((r) {
      final matchTerm = r.matches(_term);
      final matchStatus = !_statusActive || _statuses.contains(r.status);
      return matchTerm && matchStatus;
    }).toList();
  }

  int _countFor(String status) => _rows.where((r) => r.status == status).length;

  Future<void> _open(DeliveryBrief row) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            DeliveryDetailScreen(service: widget.service, brief: row),
      ),
    );
    if (changed == true) await _load(force: true);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final b = context.brand;
    final rows = _visible;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSearchField(
          controller: _searchController,
          hint: 'Search by delivery, invoice, or customer',
          onChanged: _onSearchChanged,
        ),
        const SizedBox(height: 12),
        _StatusFilterChips(
          selected: _statuses,
          countOf: _loading ? null : _countFor,
          onToggle: _toggleStatus,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: RefreshIndicator(
            color: b.signal,
            backgroundColor: b.surface,
            onRefresh: () => _load(force: true),
            child: _loading
                ? const SkeletonList(count: 7)
                : rows.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 48),
                      EmptyState(
                        icon: _error.isEmpty
                            ? Icons.local_shipping_rounded
                            : Icons.error_outline_rounded,
                        label: _error.isEmpty
                            ? 'No deliveries found'
                            : 'Deliveries unavailable',
                        hint: _error.isEmpty
                            ? 'Nothing matched this search or status filter. Pull to refresh.'
                            : _error,
                        action: _error.isEmpty
                            ? null
                            : GhostButton(
                                label: 'Try again',
                                icon: Icons.refresh_rounded,
                                onPressed: () => _load(force: true),
                              ),
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _DeliveryRow(
                      delivery: rows[i],
                      onTap: () => _open(rows[i]),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _StatusFilterChips extends StatelessWidget {
  const _StatusFilterChips({
    required this.selected,
    required this.onToggle,
    this.countOf,
  });

  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final int Function(String)? countOf;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: kDeliveryStatuses.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final status = kDeliveryStatuses[i];
          final on = selected.contains(status);
          final count = countOf?.call(status);
          return Semantics(
            button: true,
            selected: on,
            child: Material(
              color: on ? Brand.navy : b.surface,
              shape: StadiumBorder(
                side: BorderSide(color: on ? Brand.navy : b.rule),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onToggle(status),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: deliveryStatusColor(context, status),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        status,
                        style: text.labelLarge?.copyWith(
                          color: on ? Colors.white : b.paper,
                          fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      if (count != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: on ? Brand.orange : b.surfaceHi,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '$count',
                            style: text.labelSmall?.copyWith(
                              color: on ? Colors.white : b.paperDim,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DeliveryRow extends StatelessWidget {
  const _DeliveryRow({required this.delivery, required this.onTap});

  final DeliveryBrief delivery;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final color = deliveryStatusColor(context, delivery.status);
    final name = delivery.clientName.isEmpty
        ? 'Unnamed customer'
        : delivery.clientName;
    final deliveryDate = deliveryDateLine(delivery.deliveryDate);
    final meta = <String>[
      if (delivery.deliveryNo.isNotEmpty) delivery.deliveryNo,
      if (delivery.invoiceNo.isNotEmpty) 'Invoice ${delivery.invoiceNo}',
      if (delivery.items.isNotEmpty) '${delivery.items} items',
    ].join(' · ');
    return AppCard(
      onTap: onTap,
      radius: Brand.radiusLg,
      borderColor: color.withValues(alpha: 0.3),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconTile(icon: deliveryStatusIcon(delivery.status), color: color),
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
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        meta,
                        style: text.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, size: 20, color: b.paperDim),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusPill(label: delivery.status, color: color, dot: true),
              if (delivery.branch.isNotEmpty)
                GlowBadge(
                  label: delivery.branch,
                  color: Brand.pageVoice,
                  icon: Icons.storefront_rounded,
                ),
              if (deliveryDate.isNotEmpty)
                GlowBadge(
                  label: deliveryDate,
                  color: b.paperDim,
                  icon: Icons.event_rounded,
                  maxLabelWidth: 240,
                ),
              if (delivery.date.isNotEmpty)
                GlowBadge(
                  label: delivery.date,
                  color: b.paperDim,
                  icon: Icons.schedule_rounded,
                ),
            ],
          ),
          if (delivery.internalNote.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.sticky_note_2_rounded,
                  size: 15,
                  color: Brand.warning,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    delivery.internalNote,
                    style: text.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
