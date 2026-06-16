import 'package:flutter/material.dart';

import '../../models/admin_models.dart';
import '../../services/admin_services.dart';
import '../../theme.dart';
import 'admin_list.dart';

class ActivityLogsScreen extends StatelessWidget {
  const ActivityLogsScreen({super.key, required this.service});
  final ActivityLogService service;

  @override
  Widget build(BuildContext context) {
    return AdminListPage<ActivityLog>(
      stationNumber: '16',
      stationLabel: 'ACTIVITY LOGS',
      title: 'Audit trail.',
      searchHint: 'Search action / user…',
      fetch: (search) => service.list(search: search),
      itemBuilder: (ctx, log, refresh) => _LogRow(log: log),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.log});
  final ActivityLog log;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
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
                      Text(log.action,
                          style: text.titleSmall?.copyWith(color: Brand.signal)),
                      const SizedBox(width: 8),
                      Text(log.username.isEmpty ? 'system' : log.username,
                          style:
                              text.bodySmall?.copyWith(color: Brand.paperDim)),
                    ],
                  ),
                  if (log.details.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(log.details, style: text.bodyMedium),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(log.createdAt,
                    style: text.bodySmall?.copyWith(color: Brand.paperDim)),
                if (log.ipAddress.isNotEmpty)
                  Text(log.ipAddress,
                      style: text.labelSmall?.copyWith(color: Brand.paperDim)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(height: 1, color: Brand.rule),
        const SizedBox(height: 10),
      ],
    );
  }
}
