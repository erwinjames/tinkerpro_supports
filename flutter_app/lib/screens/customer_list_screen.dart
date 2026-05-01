import 'dart:async';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/notification_center.dart';
import '../services/services.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'customer_detail_screen.dart';
import 'notification_panel.dart';

class CustomerListScreen extends StatefulWidget {
  const CustomerListScreen({
    super.key,
    required this.service,
    required this.notifications,
  });
  final CustomerService service;
  final NotificationCenter notifications;

  @override
  State<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends State<CustomerListScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<CustomerBrief> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    widget.notifications.addListener(_onNotificationsChanged);
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

  @override
  Widget build(BuildContext context) {
    return StationScaffold(
      stationNumber: '04',
      stationLabel: 'BIR REGISTRATION',
      title: 'Clients.',
      showBottomBrand: false,
      trailing: StationAction(
        icon: Icons.refresh,
        tooltip: 'Refresh',
        onPressed: () => _load(search: _searchController.text),
      ),
      belowRule: NotificationBell(
        count: widget.notifications.unseenCount,
        onPressed: () =>
            NotificationPanel.show(context, widget.notifications),
        tooltip: 'New leads & customers',
      ),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              labelText: 'SEARCH · TIN · COMPANY · OWNER',
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close,
                          size: 18, color: Brand.paperDim),
                      onPressed: () {
                        _searchController.clear();
                        _load();
                      },
                    ),
            ),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 20),
          Expanded(
            child: RefreshIndicator(
              color: Brand.signal,
              backgroundColor: Brand.surface,
              onRefresh: () => _load(search: _searchController.text),
              child: _loading
                  ? const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Brand.signal,
                        ),
                      ),
                    )
                  : _rows.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 64),
                            EmptyState(
                              label: 'No clients',
                              hint:
                                  'Nothing matched your search. Pull down to refresh.',
                            ),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: _rows.length,
                          separatorBuilder: (_, __) => const Hairline(),
                          itemBuilder: (_, i) {
                            final c = _rows[i];
                            return _CustomerRow(
                              customer: c,
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => CustomerDetailScreen(
                                      service: widget.service,
                                      brief: c,
                                    ),
                                  ),
                                );
                              },
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

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({required this.customer, required this.onTap});
  final CustomerBrief customer;
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
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 7, right: 12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: customer.status == 'Processed'
                    ? Brand.signal
                    : Brand.rule,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(customer.companyName,
                      style: text.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Text(
                    customer.ownerName.isEmpty ? '—' : customer.ownerName,
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
                Text(customer.tin.isEmpty ? '—' : customer.tin,
                    style: text.labelMedium),
                const SizedBox(height: 4),
                Text(customer.status.toUpperCase(),
                    style: text.labelMedium?.copyWith(
                      color: customer.status == 'Processed'
                          ? Brand.signal
                          : Brand.paperDim,
                      letterSpacing: 2.2,
                    )),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
