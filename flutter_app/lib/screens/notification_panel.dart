import 'package:flutter/material.dart';

import '../models/notification_models.dart';
import '../services/notification_center.dart';
import '../theme.dart';
import '../widgets/premium.dart';

class NotificationPanel extends StatefulWidget {
  const NotificationPanel({super.key, required this.center});

  final NotificationCenter center;

  static Future<void> show(BuildContext context, NotificationCenter center) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      showDragHandle: false,
      builder: (_) => NotificationPanel(center: center),
    );
  }

  @override
  State<NotificationPanel> createState() => _NotificationPanelState();
}

enum _PanelFilter { all, alerts, leads, customers }

class _NotificationPanelState extends State<NotificationPanel> {
  _PanelFilter _filter = _PanelFilter.all;
  final Set<int> _fresh = <int>{};

  @override
  void initState() {
    super.initState();
    widget.center.addListener(_onChange);
    widget.center.refresh();
    _autoRead();
  }

  @override
  void dispose() {
    widget.center.removeListener(_onChange);
    widget.center.markAllSeen();
    widget.center.alerts?.markAllRead();
    super.dispose();
  }

  void _onChange() {
    _autoRead();
    if (mounted) setState(() {});
  }

  void _autoRead() {
    final alerts = widget.center.alerts;
    if (alerts == null || alerts.loading) return;
    final unread = alerts.items.where((n) => !n.isRead);
    if (unread.isEmpty) return;
    _fresh.addAll(unread.map((n) => n.id));
    alerts.markAllRead();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final center = widget.center;
    final alertsCenter = center.alerts;
    final alerts = alertsCenter?.items ?? const <AppNotification>[];
    final leads = center.unseenLeads;
    final customers = center.unseenCustomers;
    final unreadAlerts = center.unreadAlerts > _fresh.length
        ? center.unreadAlerts
        : _fresh.length;
    final total = leads.length + customers.length + unreadAlerts;
    final loading =
        (center.loading || (alertsCenter?.loading ?? false)) &&
        alerts.isEmpty &&
        leads.isEmpty &&
        customers.isEmpty;

    final showAlerts =
        (_filter == _PanelFilter.all || _filter == _PanelFilter.alerts) &&
        alerts.isNotEmpty;
    final showLeads =
        (_filter == _PanelFilter.all || _filter == _PanelFilter.leads) &&
        leads.isNotEmpty;
    final showCustomers =
        (_filter == _PanelFilter.all || _filter == _PanelFilter.customers) &&
        customers.isNotEmpty;
    final empty = !showAlerts && !showLeads && !showCustomers;

    final filters = [
      _PanelFilter.all,
      if (alertsCenter != null) _PanelFilter.alerts,
      _PanelFilter.leads,
      _PanelFilter.customers,
    ];

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollController) {
        return _PanelSheet(
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.zero,
            children: [
              Row(
                children: [
                  const IconTile(
                    icon: Icons.notifications_rounded,
                    size: 38,
                    iconSize: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text('Notifications', style: text.titleLarge),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          alertsCenter != null
                              ? 'Alerts, new leads and customers'
                              : 'New leads and customers since your last visit',
                          style: text.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedSwitcher(
                    duration:
                        (MediaQuery.maybeOf(context)?.disableAnimations ??
                            false)
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: ScaleTransition(scale: anim, child: child),
                    ),
                    child: GlowBadge(
                      key: ValueKey(total),
                      label: total == 0 ? 'All clear' : '$total new',
                      color: total == 0 ? Brand.success : b.signal,
                      icon: total == 0
                          ? Icons.check_rounded
                          : Icons.bolt_rounded,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ChoicePills<_PanelFilter>(
                options: filters,
                value: _filter,
                onChanged: (v) => setState(() => _filter = v),
                labelOf: (v) => switch (v) {
                  _PanelFilter.all => 'All',
                  _PanelFilter.alerts => 'Alerts',
                  _PanelFilter.leads => 'Leads',
                  _PanelFilter.customers => 'Customers',
                },
                countOf: (v) {
                  final n = switch (v) {
                    _PanelFilter.all => total,
                    _PanelFilter.alerts => unreadAlerts,
                    _PanelFilter.leads => leads.length,
                    _PanelFilter.customers => customers.length,
                  };
                  return n > 0 ? n : null;
                },
              ),
              const SizedBox(height: 14),
              KeyedSubtree(
                child: loading
                    ? const _LoadingRows()
                    : empty
                    ? EmptyState(
                        label: 'You\'re all caught up',
                        hint: switch (_filter) {
                          _PanelFilter.alerts =>
                            'Status changes and alerts will appear here.',
                          _PanelFilter.leads =>
                            'No new leads since your last visit.',
                          _PanelFilter.customers =>
                            'No new customers since your last visit.',
                          _PanelFilter.all =>
                            'Nothing new since your last visit.',
                        },
                        icon: Icons.notifications_off_rounded,
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showAlerts) ...[
                            _SectionHeader(
                              label: 'Alerts',
                              count: unreadAlerts,
                            ),
                            _Group(
                              children: [
                                for (final n in alerts)
                                  _AlertRow(
                                    item: n,
                                    fresh: _fresh.contains(n.id),
                                    onTap: () => alertsCenter!.markRead(n),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 20),
                          ],
                          if (showLeads) ...[
                            _SectionHeader(
                              label: 'New leads',
                              count: leads.length,
                            ),
                            _Group(
                              children: [
                                for (final l in leads)
                                  _NotificationRow(
                                    title: l.name.isEmpty ? 'No name' : l.name,
                                    subtitle: [
                                      l.businessType,
                                      l.email,
                                      l.phone,
                                    ].where((e) => e.isNotEmpty).join(' · '),
                                    meta: 'Lead',
                                    icon: Icons.local_fire_department_rounded,
                                    color: b.signal,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 20),
                          ],
                          if (showCustomers) ...[
                            _SectionHeader(
                              label: 'New customers',
                              count: customers.length,
                            ),
                            _Group(
                              children: [
                                for (final c in customers)
                                  _NotificationRow(
                                    title: c.companyName,
                                    subtitle: [
                                      c.ownerName,
                                      c.tin,
                                    ].where((e) => e.isNotEmpty).join(' · '),
                                    meta: c.status,
                                    icon: Icons.storefront_rounded,
                                    color: Brand.info,
                                    statusPill: true,
                                  ),
                              ],
                            ),
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

class _AlertRow extends StatelessWidget {
  const _AlertRow({
    required this.item,
    required this.onTap,
    this.fresh = false,
  });

  final AppNotification item;
  final VoidCallback onTap;
  final bool fresh;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final read = item.isRead && !fresh;
    final (IconData icon, Color tint) = switch (item) {
      final n when n.isCompleted => (Icons.verified_rounded, Brand.success),
      final n when n.isPtuRequest => (Icons.upload_file_rounded, Brand.signal),
      final n when n.isBirStatus => (Icons.description_rounded, Brand.info),
      _ => (Icons.notifications_none_rounded, b.paperDim),
    };
    return Semantics(
      button: true,
      label: read ? null : 'New',
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                IconTile(icon: icon, color: tint, size: 40, iconSize: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: text.titleSmall?.copyWith(
                          fontWeight: read ? FontWeight.w500 : FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (item.body.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.body,
                          style: text.bodySmall,
                          maxLines: 2,
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
                    if (item.createdAt != null)
                      Text(
                        _relative(item.createdAt!),
                        style: text.labelMedium?.copyWith(
                          color: read ? b.paperDim : b.signalInk,
                        ),
                      ),
                    const SizedBox(height: 6),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: read ? Colors.transparent : b.signal,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _relative(DateTime when) {
  final diff = DateTime.now().difference(when);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${when.day}/${when.month}/${when.year}';
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return SectionHeader(
      title: label,
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      trailing: StatusPill(label: '$count', color: b.signal),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.only(left: 66),
                child: Hairline(),
              ),
            children[i],
          ],
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
    required this.icon,
    required this.color,
    this.statusPill = false,
  });

  final String title;
  final String subtitle;
  final String meta;
  final IconData icon;
  final Color color;
  final bool statusPill;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            IconTile(icon: icon, color: color, size: 40, iconSize: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: text.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle.isEmpty ? meta : subtitle,
                    style: text.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (statusPill && meta.isNotEmpty)
                  StatusPill(label: meta)
                else if (!statusPill)
                  Text(meta, style: text.labelMedium),
                const SizedBox(height: 6),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: b.signal,
                    shape: BoxShape.circle,
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

class _LoadingRows extends StatelessWidget {
  const _LoadingRows();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: Column(
        children: [
          for (var i = 0; i < 4; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            AppCard(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Skeleton(width: 40, height: 40, radius: 12),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Skeleton(width: i.isEven ? 160 : 120, height: 14),
                        const SizedBox(height: 8),
                        Skeleton(width: i.isEven ? 110 : 150, height: 11),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PanelSheet extends StatelessWidget {
  const _PanelSheet({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    const radius = BorderRadius.vertical(top: Radius.circular(26));
    return ClipRRect(
      borderRadius: radius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          color: b.surface,
          border: Border(top: BorderSide(color: b.rule)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: b.paperDim.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
