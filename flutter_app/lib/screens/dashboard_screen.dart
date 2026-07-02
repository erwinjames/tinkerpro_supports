import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models/models.dart';
import '../services/notification_center.dart';
import '../services/services.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'notification_panel.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.api,
    required this.dashboard,
    required this.notifications,
    required this.onOpenLeads,
    required this.onOpenChat,
  });

  /// Source of the signed-in user's feature permissions — drives which
  /// metric tiles and quick actions are shown (mirrors the web sidebar).
  final ApiClient api;
  final DashboardService dashboard;
  final NotificationCenter notifications;

  /// Jump to the Leads tab. The bottom nav is permission-driven and its tab
  /// order is dynamic, so quick actions navigate by intent — HomeShell
  /// resolves this to the Leads tab's current position (or no-ops if the
  /// user can't reach it).
  final VoidCallback onOpenLeads;

  /// Jump to the Chat tab (resolved the same way as [onOpenLeads]).
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
              // Each tile is shown only when the user holds the matching
              // permission (mirrors the web sidebar gates). The surviving
              // tiles reflow into two-up rows so there are never gaps.
              ..._metricRows([
                if (widget.api.hasPermission('customer'))
                  MetricTile(
                    label: 'CUSTOMERS',
                    value: s.byLabel('Customers').toString().padLeft(2, '0'),
                  ),
                if (widget.api.hasPermission('ticket'))
                  MetricTile(
                    label: 'TICKETS',
                    value: s.byLabel('Tickets').toString().padLeft(2, '0'),
                  ),
                if (widget.api.hasPermission('clientOffer'))
                  MetricTile(
                    label: 'LEADS',
                    value: s.byLabel('Leads').toString().padLeft(2, '0'),
                  ),
                if (widget.api.hasPermission('client'))
                  MetricTile(
                    label: 'CLIENTS',
                    value: s.byLabel('Clients').toString().padLeft(2, '0'),
                  ),
                if (widget.api.hasPermission('blogposts'))
                  MetricTile(
                    label: 'POSTS',
                    value: s.byLabel('Posts').toString().padLeft(2, '0'),
                  ),
                if (widget.api.hasPermission('licensekey'))
                  MetricTile(
                    label: 'LICENSE KEYS',
                    value:
                        s.byLabel('License Keys').toString().padLeft(2, '0'),
                  ),
              ]),
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
              // Quick actions, each gated by the same permission as its
              // destination so we never offer a jump the user can't take.
              Builder(builder: (context) {
                final actions = <Widget>[
                  if (widget.api.hasPermission('clientOffer'))
                    Expanded(
                      child: GhostButton(
                        label: 'View all leads',
                        onPressed: widget.onOpenLeads,
                      ),
                    ),
                  if (widget.api.hasPermission('chat'))
                    Expanded(
                      child: SignalButton(
                        label: 'Open chat',
                        onPressed: widget.onOpenChat,
                      ),
                    ),
                ];
                if (actions.isEmpty) return const SizedBox.shrink();
                return Row(
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 12),
                      actions[i],
                    ],
                  ],
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

/// Lay out the permitted metric tiles two-per-row. A trailing odd tile is
/// padded with an empty Expanded so it keeps its half-width instead of
/// stretching across the whole row.
List<Widget> _metricRows(List<Widget> tiles) {
  final rows = <Widget>[];
  for (var i = 0; i < tiles.length; i += 2) {
    if (i > 0) rows.add(const SizedBox(height: 12));
    rows.add(Row(
      children: [
        Expanded(child: tiles[i]),
        const SizedBox(width: 12),
        Expanded(
          child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox(),
        ),
      ],
    ));
  }
  return rows;
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
