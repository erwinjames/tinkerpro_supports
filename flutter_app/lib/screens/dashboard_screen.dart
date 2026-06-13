import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/notification_center.dart';
import '../services/services.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'notification_panel.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.dashboard,
    required this.notifications,
    required this.onNavigate,
    required this.onOpenChat,
  });

  final DashboardService dashboard;
  final NotificationCenter notifications;

  /// Callback for quick-action tiles that want to switch to a different
  /// bottom-nav tab (e.g. "view all tickets" jumps to tab 2).
  final ValueChanged<int> onNavigate;

  /// Open the chat inbox. Chat is no longer a bottom-nav tab (its slot is
  /// taken by Tasks), so it's pushed as its own screen — see HomeShell.
  final VoidCallback onOpenChat;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DashboardSummary? _summary;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    widget.notifications.addListener(_onNotificationsChanged);
  }

  @override
  void dispose() {
    widget.notifications.removeListener(_onNotificationsChanged);
    super.dispose();
  }

  void _onNotificationsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final summary = await widget.dashboard.fetch();
    if (!mounted) return;
    setState(() {
      _summary = summary;
      _loading = false;
    });
    widget.notifications.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    final today = DateTime.now();
    final dateLabel = '${_weekday(today)} · ${today.day.toString().padLeft(2, '0')}.${today.month.toString().padLeft(2, '0')}.${today.year}';

    return StationScaffold(
      stationNumber: '00',
      stationLabel: dateLabel.toUpperCase(),
      title: 'Good to see you.',
      trailing: StationAction(
        icon: Icons.refresh,
        tooltip: 'Refresh',
        onPressed: _load,
      ),
      belowRule: NotificationBell(
        count: widget.notifications.unseenCount,
        onPressed: () =>
            NotificationPanel.show(context, widget.notifications),
        tooltip: 'New leads & customers',
      ),
      child: RefreshIndicator(
        color: Brand.signal,
        backgroundColor: Brand.surface,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (_loading && s == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Brand.signal,
                    ),
                  ),
                ),
              ),
            if (s != null) ...[
              Row(
                children: [
                  Expanded(
                    child: MetricTile(
                      label: 'CUSTOMERS',
                      value:
                          s.byLabel('Customers').toString().padLeft(2, '0'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: MetricTile(
                      label: 'TICKETS',
                      value: s.byLabel('Tickets').toString().padLeft(2, '0'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: MetricTile(
                      label: 'LEADS',
                      value: s.byLabel('Leads').toString().padLeft(2, '0'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: MetricTile(
                      label: 'CLIENTS',
                      value: s.byLabel('Clients').toString().padLeft(2, '0'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: MetricTile(
                      label: 'POSTS',
                      value: s.byLabel('Posts').toString().padLeft(2, '0'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: MetricTile(
                      label: 'LICENSE KEYS',
                      value: s
                          .byLabel('License Keys')
                          .toString()
                          .padLeft(2, '0'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),
              Row(
                children: [
                  Text('Recent activity',
                      style: Theme.of(context).textTheme.headlineMedium),
                  const Spacer(),
                  Text(
                    '${s.recentActivity.length} ITEMS'.toUpperCase(),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Hairline(),
              if (s.recentActivity.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text(
                      'No activity yet.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                )
              else
                ...s.recentActivity.map(
                  (a) => Column(
                    children: [
                      ActivityRow(
                        title: a.title,
                        subtitle: a.subtitle.isEmpty
                            ? a.type.toUpperCase()
                            : a.subtitle,
                        meta: a.type.toUpperCase(),
                        showSignalDot: a.type == 'lead',
                      ),
                      const Hairline(),
                    ],
                  ),
                ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: GhostButton(
                      label: 'View all leads',
                      onPressed: () => widget.onNavigate(3),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    // Chat is parked off the bottom nav (Tasks took its slot),
                    // so open the inbox as a pushed screen rather than a tab.
                    child: SignalButton(
                      label: 'Open chat',
                      onPressed: widget.onOpenChat,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _weekday(DateTime d) {
  const names = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  return names[d.weekday - 1];
}
