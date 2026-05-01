import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../theme.dart';
import '../widgets/premium.dart';

class TicketListScreen extends StatefulWidget {
  const TicketListScreen({super.key, required this.service});
  final TicketService service;

  @override
  State<TicketListScreen> createState() => _TicketListScreenState();
}

class _TicketListScreenState extends State<TicketListScreen> {
  List<TicketBrief> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await widget.service.list();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return StationScaffold(
      stationNumber: '05',
      stationLabel: 'TICKETS',
      title: 'Support queue.',
      showBottomBrand: false,
      trailing: StationAction(
        icon: Icons.refresh,
        tooltip: 'Refresh',
        onPressed: _load,
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
                        label: 'Inbox zero',
                        hint:
                            'No open tickets right now. Pull down to refresh.',
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) => const Hairline(),
                    itemBuilder: (_, i) {
                      final t = _rows[i];
                      final urgent =
                          t.priority == 'high' || t.status == 'new';
                      final statusLabel =
                          t.status.replaceAll('_', ' ').toUpperCase();
                      return ActivityRow(
                        title: t.subject,
                        subtitle:
                            '${t.customerName.isEmpty ? 'No customer' : t.customerName} · $statusLabel',
                        meta: t.createdAt,
                        trailingText: t.priority.toUpperCase(),
                        showSignalDot: urgent,
                      );
                    },
                  ),
      ),
    );
  }
}
