import 'package:flutter/material.dart';

import '../../models/admin_models.dart';
import '../../services/admin_services.dart';
import '../../theme.dart';
import '../../widgets/admin_table_page.dart';
import '../../widgets/premium.dart';
import 'admin_list.dart';

class ReleaseNotesScreen extends StatefulWidget {
  const ReleaseNotesScreen({super.key, required this.service});
  final ReleaseNotesService service;

  @override
  State<ReleaseNotesScreen> createState() => _ReleaseNotesScreenState();
}

class _ReleaseNotesScreenState extends State<ReleaseNotesScreen> {
  ReleaseNotesService get service => widget.service;
  final _table = AdminTableController();
  List<ActionType> _actions = const [];
  List<PosVersion> _versions = const [];
  String _actionFilter = '';
  String _versionFilter = '';

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    try {
      final a = await service.actionTypes();
      final v = await service.versions();
      if (mounted) {
        setState(() {
          _actions = a;
          _versions = v;
        });
      }
    } catch (_) {}
  }

  Future<Paged<ReleaseNote>> _fetch(String search) async {
    final res = await service.api.get('getReleaseNotes', {
      'page': '1',
      'limit': '5000',
      'search': search,
      'filterVersion': _versionFilter,
      'filterActionType': _actionFilter,
    });
    final raw = res['data'];
    final items = raw is List
        ? raw
              .whereType<Map>()
              .map((m) => ReleaseNote.fromJson(Map<String, dynamic>.from(m)))
              .toList()
        : <ReleaseNote>[];
    return Paged(
      items: items,
      total: int.tryParse('${res['total'] ?? items.length}') ?? items.length,
    );
  }

  Widget _select(
    String value,
    String hint,
    List<DropdownMenuItem<String>> items,
    ValueChanged<String> onChanged,
  ) {
    return Container(
      height: 40,
      width: 200,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AdminTableColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          style: const TextStyle(fontSize: 14, color: AdminTableColors.text),
          items: [
            DropdownMenuItem(value: '', child: Text(hint)),
            ...items,
          ],
          onChanged: (v) => onChanged(v ?? ''),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminTablePage<ReleaseNote>(
      stationNumber: '07',
      stationLabel: 'RELEASE NOTES',
      title: 'Release Notes',
      addLabel: 'New log entry',
      searchHint: 'Search version codes or log content...',
      searchInToolbar: false,
      controller: _table,
      liveKeys: const ['releasenotes', 'posversion'],
      onLiveChange: _loadOptions,
      filterKey: '$_actionFilter|$_versionFilter',
      fetch: _fetch,
      onAdd: (ctx, refresh) => _edit(ctx, refresh),
      onRowTap: (ctx, n, refresh) => _edit(ctx, refresh, existing: n),
      summary: (ctx, items, total, search) {
        final updates = items
            .where((d) => d.actionType.toLowerCase().contains('update'))
            .length;
        final patches = items.where((d) {
          final t = d.actionType.toLowerCase();
          return t.contains('fix') || t.contains('patch');
        }).length;
        String pad(int n) => n.toString().padLeft(2, '0');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdminStatBar(
              items: [
                StatItem(
                  'Total entries',
                  pad(items.length),
                  icon: Icons.inventory_2_outlined,
                ),
                StatItem(
                  'Standard updates',
                  pad(updates),
                  icon: Icons.arrow_upward,
                ),
                StatItem(
                  'Security patches',
                  pad(patches),
                  icon: Icons.shield_outlined,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 10,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: search,
                ),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                _select(
                  _actionFilter,
                  'Action Protocol',
                  [
                    for (final a in _actions)
                      DropdownMenuItem(value: '${a.id}', child: Text(a.type)),
                  ],
                  (v) {
                    setState(() => _actionFilter = v);
                    _table.reload();
                  },
                ),
                _select(
                  _versionFilter,
                  'All Versions',
                  [
                    for (final v in _versions)
                      DropdownMenuItem(
                        value: '${v.id}',
                        child: Text('v${v.version}'),
                      ),
                  ],
                  (v) {
                    setState(() => _versionFilter = v);
                    _table.reload();
                  },
                ),
                  ],
                ),
              ],
            ),
          ],
        );
      },
      columns: [
        AdminColumn(
          'Version Code',
          flex: 2,
          sortValue: (n) => (n as ReleaseNote).version,
        ),
        AdminColumn(
          'System Documentation',
          flex: 7,
          sortValue: (n) => (n as ReleaseNote).notes,
        ),
        AdminColumn(
          'Release Time',
          width: 220,
          sortValue: (n) => (n as ReleaseNote).createdAt,
        ),
        AdminColumn(
          'Classification',
          width: 160,
          center: true,
          sortValue: (n) => (n as ReleaseNote).actionType,
        ),
        const AdminColumn('Action', width: 120, center: true, sortable: false),
      ],
      cells: (ctx, n, refresh) => [
        AdminCellText('v${n.version}'),
        Row(
          children: [
            Flexible(
              child: AdminCellText(n.notes.replaceAll('\n', ' '), size: 14.5),
            ),
            const SizedBox(width: 8),
            Text(
              '#${n.id}',
              style: const TextStyle(
                fontSize: 12.5,
                color: AdminTableColors.muted,
              ),
            ),
          ],
        ),
        AdminDateTimeCell(n.createdAt),
        AdminBadge(
          n.actionType.isEmpty ? 'Unknown' : n.actionType,
          color: _actionColor(n.actionType),
        ),
        AdminRowMenu(
          actions: [
            AdminMenuAction(
              'Modify Entry',
              Icons.edit_outlined,
              () => _edit(ctx, refresh, existing: n),
            ),
            AdminMenuAction(
              'Purge Record',
              Icons.delete_outline,
              () => _delete(ctx, refresh, n),
              danger: true,
            ),
          ],
        ),
      ],
    );
  }

  Color _actionColor(String type) {
    final t = type.toUpperCase();
    if (t.contains('FIX') || t.contains('PATCH')) return Brand.danger;
    if (t.contains('UPDATE')) return Brand.success;
    if (t.contains('NEW')) return Brand.warning;
    return Brand.info;
  }

  Future<void> _delete(
    BuildContext context,
    VoidCallback refresh,
    ReleaseNote n,
  ) async {
    if (!await confirmDialog(
      context,
      title: 'Delete this release note?',
      message:
          'The record will be permanently purged from the release registry.',
      confirmLabel: 'Delete release note',
    )) {
      return;
    }
    if (!context.mounted) return;
    adminUndoDelete(
      context,
      message: 'Record purged',
      commit: () async {
        try {
          await service.delete(n.id);
        } catch (_) {
          if (context.mounted) toast(context, 'Failed to purge record');
        }
        refresh();
      },
    );
  }

  Future<void> _edit(
    BuildContext context,
    VoidCallback refresh, {
    ReleaseNote? existing,
  }) async {
    List<PosVersion> versions;
    List<ActionType> actions;
    try {
      versions = await service.versions();
      actions = await service.actionTypes();
    } catch (e) {
      if (context.mounted) toast(context, 'Could not load options: $e');
      return;
    }
    if (!context.mounted) return;

    int? versionId = existing?.posVersionId;
    int? actionId = existing?.actionId;
    if (versionId != null && !versions.any((v) => v.id == versionId)) {
      versionId = null;
    }
    if (actionId != null && !actions.any((a) => a.id == actionId)) {
      actionId = null;
    }
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    var busy = false;
    final isAdd = existing == null;

    Future<void> submit(BuildContext ctx, StateSetter setLocal) async {
      if (busy) return;
      if (versionId == null || actionId == null || notesCtrl.text.isEmpty) {
        toast(
          ctx,
          versionId == null || actionId == null
              ? 'Please select an item in the list.'
              : 'Please fill out this field.',
        );
        return;
      }
      setLocal(() => busy = true);
      try {
        final ok = isAdd
            ? await service.add(
                versionId: versionId!,
                actionTypeId: actionId!,
                notes: notesCtrl.text,
              )
            : await service.update(
                id: existing.id,
                versionId: versionId!,
                actionTypeId: actionId!,
                notes: notesCtrl.text,
              );
        if (!ctx.mounted) return;
        if (ok) {
          toast(
            ctx,
            isAdd ? 'Entry Committed to Registry' : 'Registry Updated Successfully',
          );
          Navigator.pop(ctx, true);
        } else {
          toast(ctx, isAdd ? 'Commit Failed' : 'Update Failed');
        }
      } catch (_) {
        if (ctx.mounted) {
          toast(
            ctx,
            isAdd ? 'Network Error during commit' : 'Network Error during update',
          );
        }
      } finally {
        if (ctx.mounted) setLocal(() => busy = false);
      }
    }

    final saved = await showWebModal<bool>(
      context,
      title: isAdd ? 'New Entry Protocol' : 'Modify Release Notes',
      icon: Icons.menu_book_outlined,
      width: 620,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FormRow(
              label: 'System Version',
              icon: Icons.account_tree_outlined,
              required: true,
              labelWidth: 170,
              child: DropdownButtonFormField<int>(
                initialValue: versionId,
                isExpanded: true,
                hint: const Text('Select Version Node'),
                items: [
                  for (final v in versions)
                    DropdownMenuItem(
                      value: v.id,
                      child: Text('Version: ${v.version}'),
                    ),
                ],
                onChanged: (v) => setLocal(() => versionId = v),
              ),
            ),
            FormRow(
              label: 'Action Protocol',
              icon: Icons.label_outline,
              required: true,
              labelWidth: 170,
              child: DropdownButtonFormField<int>(
                initialValue: actionId,
                isExpanded: true,
                hint: const Text('Identify Action Category'),
                items: [
                  for (final a in actions)
                    DropdownMenuItem(value: a.id, child: Text(a.type)),
                ],
                onChanged: (v) => setLocal(() => actionId = v),
              ),
            ),
            FormRow(
              label: 'Documentation Notes',
              icon: Icons.description_outlined,
              required: true,
              labelWidth: 170,
              child: TextField(
                controller: notesCtrl,
                minLines: 4,
                maxLines: 12,
                decoration: InputDecoration(
                  hintText: isAdd ? 'Describe the changes in this node...' : null,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: (ctx) => [
        GhostButton(
          label: 'CANCEL',
          onPressed: () => Navigator.pop(ctx, false),
        ),
        StatefulBuilder(
          builder: (bctx, setLocal) => SignalButton(
            label: isAdd ? 'COMMIT CHANGES' : 'UPDATE REGISTRY',
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
