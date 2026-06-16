import 'package:flutter/material.dart';

import '../services/notification_center.dart';
import '../theme.dart';
import '../widgets/premium.dart';

/// Bottom sheet that lists new leads and customers since the user last
/// dismissed the panel. On close we mark everything as seen so the badge
/// resets.
class NotificationPanel extends StatefulWidget {
  const NotificationPanel({super.key, required this.center});

  final NotificationCenter center;

  static Future<void> show(BuildContext context, NotificationCenter center) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Brand.surface,
      isScrollControlled: true,
      builder: (_) => NotificationPanel(center: center),
    );
  }

  @override
  State<NotificationPanel> createState() => _NotificationPanelState();
}

class _NotificationPanelState extends State<NotificationPanel> {
  @override
  void initState() {
    super.initState();
    widget.center.addListener(_onChange);
    // Pull fresh data the moment the sheet opens.
    widget.center.refresh();
  }

  @override
  void dispose() {
    widget.center.removeListener(_onChange);
    // Clear the badge — anything visible here counts as seen.
    widget.center.markAllSeen();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final leads = widget.center.unseenLeads;
    final customers = widget.center.unseenCustomers;
    final total = leads.length + customers.length;
    final loading = widget.center.loading;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Brand.surface,
            border: Border(top: BorderSide(color: Brand.signal, width: 2)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text('NOTIFICATIONS · NEW',
                      style: text.labelLarge),
                  const Spacer(),
                  Text(
                    total == 0
                        ? 'ALL CLEAR'
                        : '$total ${total == 1 ? 'ITEM' : 'ITEMS'}',
                    style: text.labelMedium?.copyWith(
                      color: total == 0 ? Brand.paperDim : Brand.signal,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Hairline(),
              Expanded(
                child: total == 0 && !loading
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'No new leads or customers since your last visit.',
                            style: text.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.only(top: 12),
                        children: [
                          if (loading && total == 0)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 32),
                              child: Center(
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Brand.signal,
                                  ),
                                ),
                              ),
                            ),
                          if (leads.isNotEmpty) ...[
                            _SectionHeader(
                                label: 'NEW LEADS', count: leads.length),
                            ...leads.map((l) => _NotificationRow(
                                  title: l.name.isEmpty ? 'No name' : l.name,
                                  subtitle: [l.businessType, l.email, l.phone]
                                      .where((e) => e.isNotEmpty)
                                      .join(' · '),
                                  meta: 'LEAD',
                                )),
                            const SizedBox(height: 18),
                          ],
                          if (customers.isNotEmpty) ...[
                            _SectionHeader(
                                label: 'NEW CUSTOMERS',
                                count: customers.length),
                            ...customers.map((c) => _NotificationRow(
                                  title: c.companyName,
                                  subtitle: [c.ownerName, c.tin]
                                      .where((e) => e.isNotEmpty)
                                      .join(' · '),
                                  meta: c.status.toUpperCase(),
                                )),
                          ],
                        ],
                      ),
              ),
              const SizedBox(height: 16),
              GhostButton(
                label: 'Close',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(label, style: text.labelMedium),
          const SizedBox(width: 8),
          Text('· $count',
              style: text.labelMedium?.copyWith(color: Brand.signal)),
        ],
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({
    required this.title,
    required this.subtitle,
    required this.meta,
  });

  final String title;
  final String subtitle;
  final String meta;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ActivityRow(
          title: title,
          subtitle: subtitle.isEmpty ? meta : subtitle,
          meta: meta,
          showSignalDot: true,
        ),
        const Hairline(),
      ],
    );
  }
}
