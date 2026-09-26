import 'package:flutter/material.dart';

import '../services/live_sync.dart';
import '../services/notification_center.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import '../widgets/tp_loader.dart';

class NotificationPanel extends StatefulWidget {
  const NotificationPanel({super.key, required this.center});

  final NotificationCenter center;

  static Future<void> show(BuildContext context, NotificationCenter center) {
    return showWebModal<void>(
      context,
      title: 'Notifications',
      icon: Icons.notifications_none,
      width: 520,
      height: 560,
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      builder: (_) => NotificationPanel(center: center),
    );
  }

  @override
  State<NotificationPanel> createState() => _NotificationPanelState();
}

class _NotificationPanelState extends State<NotificationPanel>
    with LiveRefresh<NotificationPanel> {
  @override
  List<String> get liveKeys => const ['clientOffer', 'customer', 'notifications'];

  @override
  void onLiveChange() => widget.center.refresh();

  @override
  void initState() {
    super.initState();
    widget.center.addListener(_onChange);
    widget.center.refresh();
  }

  @override
  void dispose() {
    widget.center.removeListener(_onChange);
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: context.brand.surfaceHi,
            border: Border(bottom: BorderSide(color: context.brand.rule)),
          ),
          child: Row(
            children: [
              Text(
                'New leads & customers',
                style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (loading)
                const Padding(
                  padding: EdgeInsets.only(right: 10),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: TpLoader(
                      strokeWidth: 2,
                      color: Brand.signal,
                    ),
                  ),
                ),
              StatusPill(
                label: total == 0
                    ? 'All clear'
                    : '$total ${total == 1 ? 'item' : 'items'}',
                color: total == 0 ? context.brand.paperDim : Brand.signal,
              ),
            ],
          ),
        ),
        Expanded(
          child: total == 0
              ? (loading
                    ? const Center(child: TpLoader())
                    : const EmptyState(
                        icon: Icons.notifications_off_outlined,
                        label: 'You are all caught up',
                        hint:
                            'No new leads or customers since your last visit.',
                      ))
              : ListView(
                  padding: const EdgeInsets.only(bottom: 12),
                  children: [
                    if (leads.isNotEmpty) ...[
                      _SectionHeader(label: 'New leads', count: leads.length),
                      ...leads.map(
                        (l) => _NotificationRow(
                          icon: Icons.person_add_alt_1_outlined,
                          title: l.name.isEmpty ? 'No name' : l.name,
                          subtitle: [
                            l.businessType,
                            l.email,
                            l.phone,
                          ].where((e) => e.isNotEmpty).join(' · '),
                          meta: l.createdAt,
                          tag: 'Lead',
                          tagColor: Brand.signal,
                        ),
                      ),
                    ],
                    if (customers.isNotEmpty) ...[
                      _SectionHeader(
                        label: 'New customers',
                        count: customers.length,
                      ),
                      ...customers.map(
                        (c) => _NotificationRow(
                          icon: Icons.storefront_outlined,
                          title: c.companyName,
                          subtitle: [
                            c.ownerName,
                            c.tin,
                          ].where((e) => e.isNotEmpty).join(' · '),
                          meta: '',
                          tag: c.status.isEmpty ? 'Customer' : c.status,
                          tagColor: Brand.info,
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ],
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
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Row(
        children: [
          Text(label.toUpperCase(), style: text.labelLarge),
          const SizedBox(width: 8),
          CountBadge(count: count),
        ],
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.meta,
    required this.tag,
    required this.tagColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String meta;
  final String tag;
  final Color tagColor;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.brand.rule)),
      ),
      child: Row(
        children: [
          IconTile(icon: icon, size: 32, color: tagColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              StatusPill(label: tag, color: tagColor),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(meta, style: text.bodySmall),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
