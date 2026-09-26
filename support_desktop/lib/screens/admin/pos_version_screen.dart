import 'package:flutter/material.dart';

import '../../models/admin_models.dart';
import '../../services/admin_services.dart';
import '../../widgets/admin_table_page.dart';
import '../../widgets/premium.dart';
import 'admin_list.dart';

class PosVersionScreen extends StatelessWidget {
  const PosVersionScreen({super.key, required this.service});
  final PosVersionService service;

  @override
  Widget build(BuildContext context) {
    return AdminTablePage<PosVersion>(
      stationNumber: '06',
      stationLabel: 'POS VERSION',
      title: 'POS Version',
      addLabel: 'New version node',
      searchHint: 'Search version codes…',
      searchInToolbar: false,
      liveKeys: const ['posversion'],
      fetch: (search) => service.list(search: search),
      onAdd: (ctx, refresh) => _edit(ctx, refresh),
      onRowTap: (ctx, v, refresh) => _edit(ctx, refresh, existing: v),
      stats: _stats,
      columns: [
        AdminColumn(
          'Version Code',
          flex: 5,
          sortValue: (v) => (v as PosVersion).version,
        ),
        AdminColumn(
          'Release Date',
          flex: 5,
          sortValue: (v) => (v as PosVersion).date,
        ),
        AdminColumn('Action', width: 140, center: true, sortable: false),
      ],
      cells: (ctx, v, refresh) => [
        AdminCellText('v${v.version}', bold: true),
        Row(
          children: [
            Flexible(
              child: AdminCellText(
                adminFormatDate(v.date),
                bold: true,
                size: 14,
              ),
            ),
            if (adminWeekday(v.date).isNotEmpty)
              Text(
                '  ·  ${adminWeekday(v.date)}',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AdminTableColors.muted,
                ),
              ),
          ],
        ),
        AdminRowMenu(
          actions: [
            AdminMenuAction(
              'Edit',
              Icons.edit_outlined,
              () => _edit(ctx, refresh, existing: v),
            ),
            AdminMenuAction(
              'Delete',
              Icons.delete_outline,
              () => _delete(ctx, refresh, v),
              danger: true,
            ),
          ],
        ),
      ],
    );
  }

  List<StatItem> _stats(List<PosVersion> items, int total) {
    PosVersion? latest;
    DateTime? latestDate;
    for (final v in items) {
      final d = DateTime.tryParse(v.date);
      if (d == null) continue;
      if (latestDate == null || d.isAfter(latestDate)) {
        latestDate = d;
        latest = v;
      }
    }
    latest ??= items.isNotEmpty ? items.first : null;
    return [
      StatItem(
        'Total versions',
        total.toString().padLeft(2, '0'),
        icon: Icons.account_tree_outlined,
      ),
      StatItem(
        'Latest release',
        latest == null ? '—' : 'v${latest.version}',
        icon: Icons.event_available_outlined,
      ),
      StatItem(
        'Last updated',
        latest == null ? '—' : adminFormatDate(latest.date),
        icon: Icons.schedule,
      ),
    ];
  }

  Future<void> _delete(
    BuildContext context,
    VoidCallback refresh,
    PosVersion v,
  ) async {
    if (!await confirmDialog(
      context,
      title: 'Delete this POS version?',
      message:
          'The version node and its release notes will be permanently purged.',
      confirmLabel: 'Delete version',
    )) {
      return;
    }
    if (!context.mounted) return;
    adminUndoDelete(
      context,
      message: 'Version Node Purged',
      commit: () async {
        try {
          await service.delete(v.id);
        } catch (_) {
          if (context.mounted) toast(context, 'Purge Failed');
        }
        refresh();
      },
    );
  }

  Future<void> _edit(
    BuildContext context,
    VoidCallback refresh, {
    PosVersion? existing,
  }) async {
    final versionCtrl = TextEditingController(text: existing?.version ?? '');
    final dateCtrl = TextEditingController(text: existing?.date ?? '');
    var busy = false;

    Future<void> submit(BuildContext ctx, StateSetter setLocal) async {
      if (busy) return;
      final version = versionCtrl.text;
      final date = dateCtrl.text;
      if (version.isEmpty || date.isEmpty) {
        toast(ctx, 'Please fill out this field.');
        return;
      }
      setLocal(() => busy = true);
      try {
        if (existing == null) {
          final ok = await service.add(version: version, releaseDate: date);
          if (!ctx.mounted) return;
          if (ok) {
            toast(ctx, 'Version Node Registered');
            Navigator.pop(ctx, true);
          } else {
            toast(ctx, 'Registration Failed');
          }
        } else {
          await service.update(id: existing.id, version: version, date: date);
          if (!ctx.mounted) return;
          toast(ctx, 'Version Node Updated');
          Navigator.pop(ctx, true);
        }
      } catch (_) {
        if (ctx.mounted) {
          toast(ctx, existing == null ? 'Network Error' : 'Update Failed');
        }
      } finally {
        if (ctx.mounted) setLocal(() => busy = false);
      }
    }

    final saved = await showWebModal<bool>(
      context,
      title: existing == null ? 'Register Version Node' : 'Modify Version Node',
      icon: Icons.account_tree_outlined,
      width: 520,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FormRow(
            label: 'Version Number',
            icon: Icons.tag,
            required: true,
            labelWidth: 150,
            child: TextField(
              controller: versionCtrl,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'e.g. 1.0.0'),
            ),
          ),
          FormRow(
            label: 'Release Date',
            icon: Icons.calendar_today_outlined,
            required: true,
            labelWidth: 150,
            child: AdminDateField(controller: dateCtrl),
          ),
        ],
      ),
      actions: (ctx) => [
        GhostButton(
          label: 'CANCEL',
          onPressed: () => Navigator.pop(ctx, false),
        ),
        StatefulBuilder(
          builder: (bctx, setLocal) => SignalButton(
            label: existing == null ? 'REGISTER NODE' : 'UPDATE NODE',
            icon: Icons.check,
            busy: busy,
            onPressed: busy ? null : () => submit(ctx, setLocal),
          ),
        ),
      ],
    );

    if (saved == true) refresh();
  }
}
