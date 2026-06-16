import 'package:flutter/material.dart';

import '../../models/admin_models.dart';
import '../../services/admin_services.dart';
import '../../theme.dart';
import 'admin_list.dart';

class UsersScreen extends StatelessWidget {
  const UsersScreen({super.key, required this.service});
  final UserService service;

  @override
  Widget build(BuildContext context) {
    return AdminListPage<AdminUser>(
      stationNumber: '12',
      stationLabel: 'USER',
      title: 'Team.',
      searchHint: 'Search name / email…',
      fetch: (search) => service.list(search: search),
      itemBuilder: (ctx, u, refresh) => _UserRow(
        user: u,
        onToggle: () async {
          final next = u.isActive ? 'inactive' : 'active';
          final ok = await service.toggleStatus(id: u.id, status: next);
          if (!ctx.mounted) return;
          toast(ctx, ok ? 'Status updated' : 'Update failed');
          if (ok) refresh();
        },
        onDelete: () async {
          if (!await confirmDialog(ctx,
              title: 'Delete user',
              message: 'Remove ${u.fullName.isEmpty ? u.username : u.fullName}?')) {
            return;
          }
          final ok = await service.delete(u.id);
          if (!ctx.mounted) return;
          toast(ctx, ok ? 'Deleted' : 'Delete failed');
          if (ok) refresh();
        },
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow(
      {required this.user, required this.onToggle, required this.onDelete});
  final AdminUser user;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final online = user.onlineStatus.toLowerCase() == 'online';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: online ? Brand.signal : Brand.paperDim,
                shape: BoxShape.circle,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.fullName.isEmpty ? user.username : user.fullName,
                      style: text.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (user.email.isNotEmpty) user.email,
                      user.role,
                    ].join(' · '),
                    style: text.bodySmall?.copyWith(color: Brand.paperDim),
                  ),
                ],
              ),
            ),
            _statusChip(user.isActive),
            IconButton(
                tooltip: user.isActive ? 'Deactivate' : 'Activate',
                onPressed: onToggle,
                icon: Icon(
                    user.isActive ? Icons.toggle_on : Icons.toggle_off_outlined,
                    size: 22,
                    color: user.isActive ? Brand.signal : Brand.paperDim)),
            IconButton(
                tooltip: 'Delete',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 18)),
          ],
        ),
        const SizedBox(height: 10),
        Container(height: 1, color: Brand.rule),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _statusChip(bool active) => Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(
              color: (active ? Brand.signal : Brand.paperDim)
                  .withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(active ? 'ACTIVE' : 'INACTIVE',
            style: TextStyle(
                color: active ? Brand.signal : Brand.paperDim,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1)),
      );
}
