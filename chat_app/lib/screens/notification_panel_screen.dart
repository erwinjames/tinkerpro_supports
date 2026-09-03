import 'package:flutter/material.dart';

import '../models/notification_models.dart';
import '../services/notification_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';

class NotificationPanelScreen extends StatefulWidget {
  const NotificationPanelScreen({super.key, required this.center});

  final NotificationCenter center;

  @override
  State<NotificationPanelScreen> createState() =>
      _NotificationPanelScreenState();
}

class _NotificationPanelScreenState extends State<NotificationPanelScreen> {
  bool _birOnly = false;

  @override
  void initState() {
    super.initState();
    widget.center.addListener(_onChange);
    widget.center.load();
  }

  @override
  void dispose() {
    widget.center.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final center = widget.center;
    final items = _birOnly ? center.birItems : center.items;
    final unread = center.unread;

    return StationScaffold(
      title: 'Notifications',
      subtitle: unread == 0 ? 'All caught up' : '$unread unread',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StationAction(
            icon: Icons.refresh,
            tooltip: 'Refresh',
            onPressed: center.load,
          ),
          StationAction(
            icon: Icons.done_all,
            tooltip: 'Mark all read',
            onPressed: center.markAllRead,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _FilterChip(
                label: 'All',
                selected: !_birOnly,
                onTap: () => setState(() => _birOnly = false),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'BIR registration',
                selected: _birOnly,
                onTap: () => setState(() => _birOnly = true),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: RefreshIndicator(
              onRefresh: center.load,
              child: items.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 40),
                        EmptyState(
                          icon: Icons.notifications_none,
                          label: center.loading
                              ? 'Loading notifications'
                              : 'Nothing here yet',
                          hint: _birOnly
                              ? 'PTU uploads and completed registrations will appear here.'
                              : 'Status changes and alerts will appear here.',
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _NotificationCard(
                        item: items[i],
                        onTap: () => center.markRead(items[i]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? brand.signal : brand.surface,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: selected ? brand.signal : brand.rule),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: selected ? Brand.onSignal : brand.paperDim,
              ),
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.item, required this.onTap});

  final AppNotification item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final brand = context.brand;

    final (IconData icon, Color tint) = switch (item) {
      final n when n.isCompleted => (Icons.verified_outlined, Brand.success),
      final n when n.isPtuRequest => (Icons.upload_file_outlined, Brand.signal),
      final n when n.isBirStatus => (Icons.description_outlined, brand.paperDim),
      _ => (Icons.notifications_none, brand.paperDim),
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Brand.radiusLg),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: brand.surface,
          borderRadius: BorderRadius.circular(Brand.radiusLg),
          border: Border.all(
            color: item.isRead ? brand.rule : tint.withValues(alpha: 0.55),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(Brand.radiusSm),
              ),
              child: Icon(icon, size: 19, color: tint),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          style: text.titleSmall?.copyWith(
                            fontWeight:
                                item.isRead ? FontWeight.w500 : FontWeight.w700,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!item.isRead) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: tint,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (item.body.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.body,
                      style: text.bodySmall,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (item.createdAt != null) ...[
                    const SizedBox(height: 6),
                    Text(_relative(item.createdAt!), style: text.labelMedium),
                  ],
                ],
              ),
            ),
          ],
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
