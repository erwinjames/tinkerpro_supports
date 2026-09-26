import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../services/live_sync.dart';
import '../services/ops_data_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'ops_widgets.dart';
import '../widgets/tp_loader.dart';

const _tkText = Color(0xFF0F172A);
const _tkMuted = Color(0xFF475569);
const _tkFaint = Color(0xFF94A3B8);
const _tkBorder = Color(0xFFE2E8F0);
const _tkBorderStrong = Color(0xFFCBD5E1);
const _tkSurface2 = Color(0xFFF1F5F9);
const _tkSurface3 = Color(0xFFF8FAFC);
const _overdueBg = Color(0xFFFEF2F2);
const _overdueFg = Color(0xFFB91C1C);
const _todayBg = Color(0xFFFEF3C7);
const _todayFg = Color(0xFF92400E);
const _soonBg = Color(0xFFFFF7ED);
const _soonFg = Color(0xFFC2410C);
const _prioHigh = Color(0xFFEF4444);
const _prioMedium = Color(0xFFF59E0B);
const _prioLow = Color(0xFF3B82F6);

class OpsTaskRoster extends StatefulWidget {
  const OpsTaskRoster({super.key, required this.svc, required this.data, required this.onReload});
  final OpsDataService svc;
  final Json data;
  final Future<void> Function() onReload;

  @override
  State<OpsTaskRoster> createState() => _OpsTaskRosterState();
}

class _OpsTaskRosterState extends State<OpsTaskRoster> {
  final _search = TextEditingController();
  String _filter = 'all';
  String _sort = 'name';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Json> get _rows {
    final raw = widget.data['rows'];
    return raw is List
        ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Json>[];
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final totals = widget.data['totals'] is Map
        ? Map<String, dynamic>.from(widget.data['totals'] as Map)
        : <String, dynamic>{};
    int t(String k) => opsInt(totals[k]);
    final all = _rows;
    final q = _search.text.trim().toLowerCase();
    final rows = all.where((r) {
      final hay = '${opsStr(r['name'])} ${opsStr(r['username'])}'.toLowerCase();
      if (q.isNotEmpty && !hay.contains(q)) return false;
      if (_filter == 'overdue') return opsInt(r['overdue']) > 0;
      if (_filter == 'active') return opsInt(r['open']) > 0;
      if (_filter == 'idle') return opsInt(r['open']) == 0;
      return true;
    }).toList();
    rows.sort((a, b) {
      switch (_sort) {
        case 'overdue':
          return opsInt(b['overdue']) - opsInt(a['overdue']);
        case 'open':
          return opsInt(b['open']) - opsInt(a['open']);
        case 'done':
          return opsInt(b['done']) - opsInt(a['done']);
        case 'due':
          return opsInt(a['due_sort']).compareTo(opsInt(b['due_sort']));
        default:
          return opsStr(a['name']).toLowerCase().compareTo(opsStr(b['name']).toLowerCase());
      }
    });
    final err = opsStr(widget.data['error']);
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 18),
      children: [
        if (err.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: _overdueBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: Text('Could not load the team roster: $err',
                style: const TextStyle(color: _overdueFg, fontSize: 14, fontWeight: FontWeight.w500)),
          ),
        LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 900;
          return Flex(
            direction: wide ? Axis.horizontal : Axis.vertical,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: wide ? CrossAxisAlignment.center : CrossAxisAlignment.stretch,
            children: [
          Text('Team workload',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: b.paper, letterSpacing: -0.3)),
          const SizedBox(width: 16, height: 10),
          _MaybeExpanded(
            expand: wide,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: _tkBorder,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _tkBorder),
              ),
              child: IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _stat(context, '${t('people')}', 'People', '${t('idle')} with nothing open'),
                  _stat(context, '${t('open')}', 'Open tasks', '${t('all')} logged all time'),
                  _stat(context, '${t('overdue')}', 'Overdue',
                      t('overdue') > 0 ? 'Needs attention now' : 'Nothing past due',
                      valueColor: t('overdue') > 0 ? _overdueFg : null),
                  _stat(context, '${t('today')}', 'Due today', opsStr(widget.data['today_label']),
                      valueColor: t('today') > 0 ? _todayFg : null),
                  _stat(context, '${opsInt(widget.data['rate'])}', 'Completion', '${t('done')} tasks closed',
                      suffix: '%', last: true),
                ]),
              ),
            ),
          ),
            ],
          );
        }),
        const SizedBox(height: 8),
        Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 8,
            children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
          OpsPill(label: 'All', count: '${t('people')}', dark: true, active: _filter == 'all',
              onTap: () => setState(() => _filter = 'all')),
          OpsPill(label: 'Overdue', dark: true, active: _filter == 'overdue',
              onTap: () => setState(() => _filter = 'overdue')),
          OpsPill(label: 'Has open work', dark: true, active: _filter == 'active',
              onTap: () => setState(() => _filter = 'active')),
          OpsPill(label: 'Clear', count: '${t('idle')}', dark: true, active: _filter == 'idle',
              onTap: () => setState(() => _filter = 'idle')),
          ]),
          Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: SizedBox(
            width: 240,
            height: 36,
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'Search teammates',
                prefixIcon: Icon(Icons.search, size: 16),
                prefixIconConstraints: BoxConstraints(minWidth: 34),
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              ),
            ),
          ),
          ),
          const SizedBox(width: 10),
          const Text('SORT',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: _tkFaint)),
          const SizedBox(width: 6),
          OpsSelect<String>(
            value: _sort,
            width: 170,
            height: 36,
            items: const [
              ('name', 'Name (A–Z)'),
              ('overdue', 'Most overdue'),
              ('open', 'Most open tasks'),
              ('due', 'Earliest due date'),
              ('done', 'Most completed'),
            ],
            onChanged: (v) => setState(() => _sort = v),
          ),
          ]),
        ]),
        const SizedBox(height: 8),
        if (all.isEmpty && err.isEmpty)
          _blank(Icons.person_outline, 'No teammates yet',
              'Once staff accounts exist they show up here with their task load.')
        else if (rows.isEmpty)
          _blank(Icons.search, 'No one matches', 'Try a different name, or clear the filter.')
        else
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: b.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _tkBorder),
            ),
            child: ColumnResizeScope(tableId: 'ops:roster', child: Column(children: [
              Container(
                height: 26,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: const BoxDecoration(
                  color: _tkSurface3,
                  border: Border(bottom: BorderSide(color: _tkBorder)),
                ),
                child: const _RosterCols(
                  header: true,
                  person: _Head('Person'),
                  open: _Head('Open', right: true),
                  overdue: _Head('Overdue', right: true),
                  done: _Head('Done', right: true),
                  prog: _Head('Progress'),
                  next: _Head('Next up'),
                ),
              ),
              for (var i = 0; i < rows.length; i++)
                _PersonRow(
                  row: rows[i],
                  svc: widget.svc,
                  first: i == 0,
                  onOpen: () async {
                    await showDialog<void>(
                      context: context,
                      builder: (_) => OpsUserTasksModal(svc: widget.svc, userId: opsInt(rows[i]['id'])),
                    );
                    widget.onReload();
                  },
                ),
            ])),
          ),
      ],
    );
  }

  Widget _blank(IconData i, String h, String p) => Container(
        padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
        decoration: BoxDecoration(
          color: context.brand.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _tkBorderStrong),
        ),
        child: Column(children: [
          Icon(i, size: 28, color: _tkFaint),
          const SizedBox(height: 8),
          Text(h, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _tkText)),
          const SizedBox(height: 4),
          Text(p, style: const TextStyle(fontSize: 14, color: _tkMuted)),
        ]),
      );

  Widget _stat(BuildContext context, String value, String label, String note,
      {Color? valueColor, String? suffix, bool last = false}) {
    return Expanded(
      child: Container(
        margin: EdgeInsets.only(right: last ? 0 : 1),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        color: context.brand.surface,
        child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text(value,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: valueColor ?? _tkText)),
          if (suffix != null)
            Text(suffix, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: _tkMuted)),
          const SizedBox(width: 6),
          Flexible(
            flex: 4,
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _tkMuted)),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(note,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: _tkFaint)),
          ),
        ]),
      ),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.t, {this.right = false});
  final String t;
  final bool right;

  @override
  Widget build(BuildContext context) => Text(
        t.toUpperCase(),
        textAlign: right ? TextAlign.right : TextAlign.left,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.7, color: _tkFaint),
      );
}

class _RosterCols extends StatelessWidget {
  const _RosterCols({
    required this.person,
    required this.open,
    required this.overdue,
    required this.done,
    required this.prog,
    required this.next,
    this.header = false,
  });
  final Widget person, open, overdue, done, prog, next;
  final bool header;

  @override
  Widget build(BuildContext context) {
    return Row(children: resizableRowCells(context, header: header, extra: 24, [
      Expanded(flex: 22, child: person),
      const SizedBox(width: 10),
      Expanded(flex: 4, child: open),
      const SizedBox(width: 10),
      Expanded(flex: 4, child: overdue),
      const SizedBox(width: 10),
      Expanded(flex: 4, child: done),
      const SizedBox(width: 10),
      Expanded(flex: 9, child: prog),
      const SizedBox(width: 10),
      Expanded(flex: 20, child: next),
    ]));
  }
}

class _PersonRow extends StatefulWidget {
  const _PersonRow({required this.row, required this.svc, required this.first, required this.onOpen});
  final Json row;
  final OpsDataService svc;
  final bool first;
  final VoidCallback onOpen;

  @override
  State<_PersonRow> createState() => _PersonRowState();
}

class _PersonRowState extends State<_PersonRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final flag = opsStr(r['flag']);
    final stripe = switch (flag) {
      'overdue' => _prioHigh,
      'today' => _prioMedium,
      'active' => _tkBorderStrong,
      _ => Colors.transparent,
    };
    final hue = opsInt(r['hue']).toDouble();
    final avBg = HSLColor.fromAHSL(1, hue, 0.62, 0.94).toColor();
    final avFg = HSLColor.fromAHSL(1, hue, 0.52, 0.32).toColor();
    final pic = opsStr(r['profile_picture']);
    final open = opsInt(r['open']);
    final overdue = opsInt(r['overdue']);
    final done = opsInt(r['done']);
    final pct = opsInt(r['pct']);
    final role = opsStr(r['role']);
    final nextTitle = opsStr(r['next_title']);
    final state = opsStr(r['next_state']);
    final (dueBg, dueFg) = switch (state) {
      'overdue' => (_overdueBg, _overdueFg),
      'today' => (_todayBg, _todayFg),
      'soon' => (_soonBg, _soonFg),
      _ => (_tkSurface2, _tkMuted),
    };
    TextStyle num(bool zero, {bool alert = false}) => TextStyle(
          fontSize: 14,
          fontWeight: zero ? FontWeight.w500 : FontWeight.w700,
          color: alert ? _overdueFg : (zero ? _tkFaint : _tkText),
        );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onOpen,
        child: Container(
          constraints: const BoxConstraints(minHeight: 38),
          decoration: BoxDecoration(
            color: _hover ? _tkSurface3 : null,
            border: widget.first ? null : const Border(top: BorderSide(color: _tkBorder)),
          ),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(width: 3, color: stripe),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(9, 5, 12, 5),
                  child: _RosterCols(
                    person: Row(children: [
                      Container(
                        width: 24,
                        height: 24,
                        clipBehavior: Clip.antiAlias,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: avBg, shape: BoxShape.circle),
                        child: pic.isEmpty
                            ? Text(opsStr(r['initials']),
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: avFg))
                            : Image.network(
                                widget.svc.url(pic),
                                headers: widget.svc.authHeaders,
                                width: 24,
                                height: 24,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Text(opsStr(r['initials']),
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: avFg)),
                              ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(opsStr(r['name']),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: _tkText, height: 1.25)),
                            Text('@${opsStr(r['username'])}${role.isNotEmpty ? ' · $role' : ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11, color: _tkMuted, height: 1.25)),
                          ],
                        ),
                      ),
                    ]),
                    open: Align(alignment: Alignment.centerRight, child: Text('$open', style: num(false))),
                    overdue: Align(
                        alignment: Alignment.centerRight,
                        child: Text('$overdue', style: num(overdue == 0, alert: overdue > 0))),
                    done: Align(alignment: Alignment.centerRight, child: Text('$done', style: num(done == 0))),
                    prog: Row(children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: Stack(children: [
                            Container(height: 4, color: _tkSurface2),
                            FractionallySizedBox(
                              widthFactor: (pct / 100).clamp(0.0, 1.0),
                              child: Container(height: 4, color: Brand.signal),
                            ),
                          ]),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 32,
                        child: Text('$pct%',
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: _tkMuted)),
                      ),
                    ]),
                    next: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      if (nextTitle.isNotEmpty) ...[
                        Flexible(
                          child: Text(nextTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5, color: _tkMuted)),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: dueBg, borderRadius: BorderRadius.circular(99)),
                          child: Text(opsStr(r['next_label']),
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: dueFg)),
                        ),
                      ] else
                        Flexible(
                          child: Text(open > 0 ? '$open open, none scheduled' : 'Nothing on the list',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5, color: _tkFaint)),
                        ),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class OpsUserTasksModal extends StatefulWidget {
  const OpsUserTasksModal({super.key, required this.svc, required this.userId});
  final OpsDataService svc;
  final int userId;

  @override
  State<OpsUserTasksModal> createState() => _OpsUserTasksModalState();
}

class _OpsUserTasksModalState extends State<OpsUserTasksModal>
    with LiveRefresh<OpsUserTasksModal> {
  @override
  List<String> get liveKeys => const ['task'];

  @override
  void onLiveChange() => _liveLoad();

  Future<void> _liveLoad() async {
    final d = await widget.svc.userTasks(widget.userId);
    if (!mounted || d['success'] == false) return;
    setState(() => _data = d);
  }

  Json? _data;
  String _tab = 'pending';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await widget.svc.userTasks(widget.userId);
    if (mounted) setState(() => _data = d);
  }

  Future<void> _add() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _AddForUser(svc: widget.svc, userId: widget.userId),
    );
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final user = d?['user'] is Map ? Map<String, dynamic>.from(d!['user'] as Map) : <String, dynamic>{};
    final name = opsStr(user['full_name']).isNotEmpty ? opsStr(user['full_name']) : opsStr(user['username']);
    final tasks = d?['tasks'] is List
        ? (d!['tasks'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Json>[];
    final today = DateTime.now();
    final day0 = DateTime(today.year, today.month, today.day);
    bool isOverdue(Json t) {
      final due = opsParseDate(opsStr(t['due_date']));
      return opsStr(t['status']) != 'completed' && due != null && due.isBefore(day0);
    }

    final pending = tasks.where((t) => opsStr(t['status']) != 'completed').toList();
    final done = tasks.where((t) => opsStr(t['status']) == 'completed').toList();
    final overdue = pending.where(isOverdue).toList();
    final shown = switch (_tab) {
      'completed' => done,
      'overdue' => overdue,
      'all' => tasks,
      _ => pending,
    };
    return WebModal(
      title: d == null ? 'Loading…' : (name.isEmpty ? 'Tasks' : name),
      subtitle: d == null
          ? null
          : '@${opsStr(user['username'])} · ${pending.length} open · ${done.length} completed',
      icon: Icons.checklist,
      width: 1040,
      actions: [
        GhostButton(label: 'Close', onPressed: () => Navigator.of(context).pop()),
        SignalButton(label: 'Add task', icon: Icons.add, onPressed: d == null ? null : _add),
      ],
      child: d == null
          ? const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: TpLoader(strokeWidth: 2, color: Brand.signal)),
            )
          : d['success'] != true
              ? Text(opsStr(d['error']).isEmpty ? 'Could not load tasks.' : opsStr(d['error']))
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                  Wrap(spacing: 6, children: [
                    OpsPill(label: 'Open', count: '${pending.length}', dark: true, active: _tab == 'pending',
                        onTap: () => setState(() => _tab = 'pending')),
                    OpsPill(label: 'Overdue', count: '${overdue.length}', dark: true, active: _tab == 'overdue',
                        onTap: () => setState(() => _tab = 'overdue')),
                    OpsPill(label: 'Completed', count: '${done.length}', dark: true, active: _tab == 'completed',
                        onTap: () => setState(() => _tab = 'completed')),
                    OpsPill(label: 'All', count: '${tasks.length}', dark: true, active: _tab == 'all',
                        onTap: () => setState(() => _tab = 'all')),
                  ]),
                  const SizedBox(height: 14),
                  if (shown.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border.all(color: _tkBorderStrong),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('No tasks in this view.', style: TextStyle(color: _tkMuted)),
                    )
                  else
                    Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        border: Border.all(color: _tkBorder),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(children: [
                        for (var i = 0; i < shown.length; i++)
                          _UserTaskRow(task: shown[i], first: i == 0, overdue: isOverdue(shown[i])),
                      ]),
                    ),
                ]),
    );
  }
}

class _UserTaskRow extends StatelessWidget {
  const _UserTaskRow({required this.task, required this.first, required this.overdue});
  final Json task;
  final bool first;
  final bool overdue;

  @override
  Widget build(BuildContext context) {
    final t = task;
    final doneT = opsStr(t['status']) == 'completed';
    final pr = opsStr(t['priority']);
    final prColor = switch (pr) { 'high' => _prioHigh, 'low' => _prioLow, _ => _prioMedium };
    final due = opsParseDate(opsStr(t['due_date']));
    final project = opsStr(t['project_name']);
    final desc = opsStr(t['description']).replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: _tkBorder))),
      child: Row(children: [
        Icon(doneT ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 20, color: doneT ? const Color(0xFF059669) : _tkFaint),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(opsStr(t['title']),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: doneT ? _tkFaint : _tkText,
                      decoration: doneT ? TextDecoration.lineThrough : null,
                    )),
              ),
              if (project.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(
                    border: Border.all(color: _tkBorder),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.folder_outlined, size: 11, color: _tkMuted),
                    const SizedBox(width: 4),
                    Text(project, style: const TextStyle(fontSize: 11.5, color: _tkMuted)),
                  ]),
                ),
              ],
            ]),
            if (desc.isNotEmpty)
              Text(desc, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: _tkMuted)),
          ]),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: overdue ? _overdueBg : _tkSurface2,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            due == null ? 'No due date' : opsShortDate(due),
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: overdue ? _overdueFg : _tkMuted),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(width: 80, child: Align(alignment: Alignment.centerRight, child: OpsBadge.tone(pr.isEmpty ? 'medium' : pr, prColor))),
      ]),
    );
  }
}

class _AddForUser extends StatefulWidget {
  const _AddForUser({required this.svc, required this.userId});
  final OpsDataService svc;
  final int userId;

  @override
  State<_AddForUser> createState() => _AddForUserState();
}

class _AddForUserState extends State<_AddForUser> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  String _priority = 'medium';
  DateTime? _due;
  bool _busy = false;

  String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    if (_title.text.isEmpty) {
      opsToast(context, 'Please fill out the Task title field.', error: true);
      return;
    }
    if (_due == null) {
      opsToast(context, 'Please fill out the Due date field.', error: true);
      return;
    }
    setState(() => _busy = true);
    final r = await widget.svc.addTaskForUser(
      userId: widget.userId,
      title: _title.text,
      description: _desc.text,
      priority: _priority,
      dueDate: _ymd(_due!),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      opsToast(context, 'Task added successfully!');
      Navigator.of(context).pop(true);
    } else {
      opsToast(context, r.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WebModal(
      title: 'New task',
      icon: Icons.add_task,
      width: 540,
      actions: [
        GhostButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop(false)),
        SignalButton(label: 'Add task', busy: _busy, onPressed: _save),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        OpsField(
            label: 'Task title',
            required: true,
            child: TextField(
                controller: _title,
                autofocus: true,
                maxLength: 255,
                decoration: const InputDecoration(counterText: '', hintText: 'What needs doing?'))),
        OpsField(
            label: 'Description',
            child: TextField(
                controller: _desc,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(hintText: 'Add any detail that helps…'))),
        Row(children: [
          Expanded(
            child: OpsField(
              label: 'Priority',
              required: true,
              child: DropdownButtonFormField<String>(
                initialValue: _priority,
                items: const [
                  DropdownMenuItem(value: 'low', child: Text('Low')),
                  DropdownMenuItem(value: 'medium', child: Text('Medium')),
                  DropdownMenuItem(value: 'high', child: Text('High')),
                ],
                onChanged: (v) => setState(() => _priority = v ?? 'medium'),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OpsField(
              label: 'Due date',
              required: true,
              child: InkWell(
                onTap: () async {
                  final today = DateUtils.dateOnly(DateTime.now());
                  final p = await showDatePicker(
                    context: context,
                    initialDate: _due ?? today,
                    firstDate: today,
                    lastDate: DateTime(2100),
                  );
                  if (p != null) setState(() => _due = p);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(suffixIcon: Icon(Icons.calendar_today, size: 16)),
                  child: Text(_due == null ? 'mm/dd/yyyy' : _ymd(_due!)),
                ),
              ),
            ),
          ),
        ]),
      ]),
    );
  }
}

Future<void> opsOpenTaskExport(BuildContext context, OpsDataService svc) async {
  final now = DateTime.now();
  var from = DateTime(now.year, now.month, 1);
  var to = DateTime(now.year, now.month + 1, 0);
  var field = 'due';
  var status = 'all';
  var busy = false;
  String ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      Widget date(String label, DateTime v, ValueChanged<DateTime> on) => Expanded(
            child: OpsField(
              label: label,
              child: InkWell(
                onTap: () async {
                  final p = await showDatePicker(
                      context: ctx, initialDate: v, firstDate: DateTime(2020), lastDate: DateTime(2100));
                  if (p != null) set(() => on(p));
                },
                child: InputDecorator(
                  decoration: const InputDecoration(suffixIcon: Icon(Icons.calendar_today, size: 16)),
                  child: Text(ymd(v)),
                ),
              ),
            ),
          );
      Future<void> go() async {
        set(() => busy = true);
        try {
          final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
          final path = await svc.exportTasksCsv(
              from: ymd(from), to: ymd(to), dateField: field, status: status, saveDir: dir.path);
          if (ctx.mounted) {
            Navigator.of(ctx).pop();
            opsToast(context, 'Saved $path');
          }
        } catch (e) {
          set(() => busy = false);
          if (ctx.mounted) opsToast(ctx, 'Export failed: $e', error: true);
        }
      }

      return WebModal(
        title: 'Export Tasks to CSV',
        icon: Icons.description_outlined,
        width: 520,
        actions: [
          GhostButton(label: 'Cancel', onPressed: () => Navigator.of(ctx).pop()),
          SignalButton(label: 'Download CSV', icon: Icons.download, busy: busy, onPressed: go),
        ],
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            date('From', from, (v) => from = v),
            const SizedBox(width: 12),
            date('To', to, (v) => to = v),
          ]),
          Row(children: [
            Expanded(
              child: OpsField(
                label: 'Date field',
                child: DropdownButtonFormField<String>(
                  initialValue: field,
                  items: const [
                    DropdownMenuItem(value: 'due', child: Text('Due date')),
                    DropdownMenuItem(value: 'updated', child: Text('Last updated')),
                  ],
                  onChanged: (v) => set(() => field = v ?? 'due'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OpsField(
                label: 'Status',
                child: DropdownButtonFormField<String>(
                  initialValue: status,
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All')),
                    DropdownMenuItem(value: 'pending', child: Text('Pending')),
                    DropdownMenuItem(value: 'completed', child: Text('Completed')),
                    DropdownMenuItem(value: 'overdue', child: Text('Overdue')),
                  ],
                  onChanged: (v) => set(() => status = v ?? 'all'),
                ),
              ),
            ),
          ]),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline, size: 15, color: ctx.brand.paperDim),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Exports tasks where the chosen date field falls inside the range. The file is saved to your Downloads folder.',
                style: TextStyle(fontSize: 12.5, color: ctx.brand.paperDim),
              ),
            ),
          ]),
        ]),
      );
    }),
  );
}

class _MaybeExpanded extends StatelessWidget {
  const _MaybeExpanded({required this.expand, required this.child});
  final bool expand;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      expand ? Expanded(child: child) : child;
}
