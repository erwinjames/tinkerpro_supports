import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../services/live_sync.dart';
import '../services/notification_center.dart';
import '../services/ops_data_service.dart';
import '../services/services.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'ops_widgets.dart';
import '../widgets/tp_loader.dart';

class LeadListScreen extends StatefulWidget {
  const LeadListScreen({
    super.key,
    required this.service,
    required this.notifications,
  });
  final LeadService service;
  final NotificationCenter notifications;

  @override
  State<LeadListScreen> createState() => _LeadListScreenState();
}

enum _Sort { none, nameAsc, nameDesc, dateAsc, dateDesc }

class _LeadListScreenState extends State<LeadListScreen>
    with LiveRefresh<LeadListScreen> {
  late final OpsDataService _svc = OpsDataService(widget.service.api);
  final _search = TextEditingController();
  final _locFilter = TextEditingController();
  List<Json> _rows = const [];
  bool _loading = true;
  int _page = 0;
  int _pageSize = 30;
  _Sort _sort = _Sort.none;
  final Set<int> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
    widget.notifications.addListener(_onNotificationsChanged);
  }

  @override
  void dispose() {
    widget.notifications.removeListener(_onNotificationsChanged);
    _search.dispose();
    _locFilter.dispose();
    super.dispose();
  }

  void _onNotificationsChanged() {
    if (mounted) setState(() {});
  }

  @override
  List<String> get liveKeys => const ['clientOffer'];

  @override
  void onLiveChange() => _liveLoad();

  bool _liveBusy = false;

  Future<void> _liveLoad() async {
    if (_liveBusy) return;
    _liveBusy = true;
    try {
      final rows = await _svc.leads();
      if (!mounted || (rows.isEmpty && _rows.isNotEmpty)) return;
      setState(() {
        _rows = rows;
        _loading = false;
        _selected.removeWhere((id) => !rows.any((r) => opsInt(r['id']) == id));
      });
    } finally {
      _liveBusy = false;
    }
  }

  Future<void> _load() async {
    final rows = await _svc.leads();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
      _selected.removeWhere((id) => !rows.any((r) => opsInt(r['id']) == id));
    });
    widget.notifications.refresh();
  }

  List<Json> get _filtered {
    final q = _search.text.trim().toLowerCase();
    final loc = _locFilter.text.trim().toLowerCase();
    final out = _rows.where((l) {
      if (loc.isNotEmpty && !opsStr(l['location']).toLowerCase().contains(loc)) {
        return false;
      }
      if (q.isEmpty) return true;
      return const [
        'name',
        'email',
        'phone',
        'location',
        'businessType',
        'customBusinessType',
      ].any((k) => opsStr(l[k]).toLowerCase().contains(q));
    }).toList();
    int cmp(Json a, Json b, String k) =>
        opsStr(a[k]).toLowerCase().compareTo(opsStr(b[k]).toLowerCase());
    switch (_sort) {
      case _Sort.nameAsc:
        out.sort((a, b) => cmp(a, b, 'name'));
      case _Sort.nameDesc:
        out.sort((a, b) => cmp(b, a, 'name'));
      case _Sort.dateAsc:
        out.sort((a, b) => cmp(a, b, 'created_at'));
      case _Sort.dateDesc:
        out.sort((a, b) => cmp(b, a, 'created_at'));
      case _Sort.none:
        break;
    }
    return out;
  }

  void _toggleSort(bool name) {
    setState(() {
      if (name) {
        _sort = _sort == _Sort.nameAsc ? _Sort.nameDesc : _Sort.nameAsc;
      } else {
        _sort = _sort == _Sort.dateAsc ? _Sort.dateDesc : _Sort.dateAsc;
      }
    });
  }

  Future<void> _exportCsv() async {
    try {
      final dir = await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
      final path = await _svc.exportLeadsCsv(
          _filtered.map((l) => opsInt(l['id'])).toList(), dir.path);
      if (mounted) opsToast(context, 'Exported to $path');
    } catch (e) {
      if (mounted) opsToast(context, 'Export failed: $e', error: true);
    }
  }

  Future<void> _menu(Json l, Offset pos) async {
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx - 200, pos.dy, pos.dx, pos.dy),
      items: const [
        PopupMenuItem(value: 'view', child: _MenuLabel(Icons.visibility_outlined, 'View Profile')),
        PopupMenuItem(value: 'email', child: _MenuLabel(Icons.mail_outline, 'Send Email')),
        PopupMenuItem(value: 'sms', child: _MenuLabel(Icons.sms_outlined, 'Send SMS')),
        PopupMenuItem(value: 'memo', child: _MenuLabel(Icons.sticky_note_2_outlined, 'Memo')),
        PopupMenuDivider(),
        PopupMenuItem(
            value: 'delete',
            child: _MenuLabel(Icons.delete_outline, 'Purge Record', danger: true)),
      ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'view':
        _view(l);
      case 'email':
        _email([l]);
      case 'sms':
        _sms(l);
      case 'memo':
        _memo(l);
      case 'delete':
        _delete(l);
    }
  }

  Future<void> _view(Json l) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _LeadProfile(lead: l, svc: _svc, onChanged: _load),
    );
  }

  Future<void> _memo(Json l) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _MemoModal(lead: l, svc: _svc),
    );
    if (saved == true) _load();
  }

  Future<void> _sms(Json l) async {
    if (opsStr(l['phone']).isEmpty) {
      opsToast(context, 'This lead has no phone number on file.', error: true);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => _SmsModal(lead: l, svc: _svc, onSent: _load),
    );
  }

  Future<void> _email(List<Json> leads) async {
    final sent = await showDialog<bool>(
      context: context,
      builder: (_) => _EmailModal(leads: leads, svc: _svc),
    );
    if (sent == true) _load();
  }

  Future<void> _delete(Json l) async {
    final ok = await opsConfirm(
      context,
      title: 'Delete this lead?',
      message:
          'The lead record will be permanently removed from the active registry.',
      confirm: 'Delete lead',
    );
    if (!ok || !mounted) return;
    final id = opsInt(l['id']);
    setState(() {
      _rows = _rows.where((r) => opsInt(r['id']) != id).toList();
      _selected.remove(id);
    });
    if (!await opsUndoWindow(context, 'Lead deleted')) {
      _load();
      return;
    }
    final r = await _svc.deleteLead(id);
    if (!mounted) return;
    if (!r.ok) opsToast(context, 'Failed to delete lead.', error: true);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final filtered = _filtered;
    final pages =
        filtered.isEmpty ? 1 : ((filtered.length - 1) ~/ _pageSize) + 1;
    final page = _page.clamp(0, pages - 1);
    final visible = filtered.skip(page * _pageSize).take(_pageSize).toList();
    final newIds =
        widget.notifications.unseenLeads.map((l) => l.id).toSet();
    final allSel = visible.isNotEmpty &&
        visible.every((l) => _selected.contains(opsInt(l['id'])));

    return Container(
      color: b.canvas,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PageToolbar(actions: [
          SizedBox(
            width: 300,
            height: 40,
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() => _page = 0),
              decoration: const InputDecoration(
                hintText: 'Search Lead Registry...',
                prefixIcon: Icon(Icons.search, size: 18),
                prefixIconConstraints: BoxConstraints(minWidth: 38),
              ),
            ),
          ),
          if (_selected.isNotEmpty)
            OpsButton(
              label: 'Bulk Email',
              icon: Icons.mail,
              color: Brand.signal,
              onPressed: () => _email(
                  _rows.where((r) => _selected.contains(opsInt(r['id']))).toList()),
            ),
          OpsButton(
            label: 'Export CSV',
            icon: Icons.description_outlined,
            color: b.paper,
            outlined: true,
            onPressed: _exportCsv,
          ),
        ]),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: b.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: b.rule),
              ),
              child: ColumnResizeScope(tableId: 'leads', child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _HeaderRow(
                  allSelected: allSel,
                  onSelectAll: (v) => setState(() {
                    for (final l in visible) {
                      v
                          ? _selected.add(opsInt(l['id']))
                          : _selected.remove(opsInt(l['id']));
                    }
                  }),
                  sort: _sort,
                  onSort: _toggleSort,
                  locFilter: _locFilter,
                  onLocChanged: () => setState(() => _page = 0),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: TpLoader())
                      : visible.isEmpty
                          ? Center(
                              child: Text('No records found in active registry',
                                  style: TextStyle(color: b.paperDim)))
                          : ListView.builder(
                              itemCount: visible.length,
                              itemBuilder: (_, i) {
                                final l = visible[i];
                                final id = opsInt(l['id']);
                                return _LeadRow(
                                  lead: l,
                                  isNew: newIds.contains(id),
                                  selected: _selected.contains(id),
                                  onSelect: (v) => setState(() =>
                                      v ? _selected.add(id) : _selected.remove(id)),
                                  onOpen: () => _view(l),
                                  onMenu: (p) => _menu(l, p),
                                );
                              },
                            ),
                ),
                _Pager(
                  page: page,
                  pages: pages,
                  pageSize: _pageSize,
                  onPage: (p) => setState(() => _page = p),
                  onPageSize: (s) => setState(() {
                    _pageSize = s;
                    _page = 0;
                  }),
                ),
              ])),
            ),
          ),
        ),
      ]),
    );
  }
}

class _MenuLabel extends StatelessWidget {
  const _MenuLabel(this.icon, this.label, {this.danger = false});
  final IconData icon;
  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = danger ? opsRed : context.brand.paper;
    return Row(children: [
      Icon(icon, size: 16, color: c),
      const SizedBox(width: 10),
      Text(label, style: TextStyle(color: c, fontWeight: FontWeight.w600)),
    ]);
  }
}

const _wSel = 50.0;
const _wSerial = 76.0;
const _wReceived = 165.0;
const _wBiz = 145.0;
const _wSpec = 145.0;
const _wSub = 115.0;
const _wAction = 70.0;

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.allSelected,
    required this.onSelectAll,
    required this.sort,
    required this.onSort,
    required this.locFilter,
    required this.onLocChanged,
  });

  final bool allSelected;
  final ValueChanged<bool> onSelectAll;
  final _Sort sort;
  final ValueChanged<bool> onSort;
  final TextEditingController locFilter;
  final VoidCallback onLocChanged;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final style = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
      color: b.paperDim,
    );
    Widget arrow(bool? up) => Icon(
          up == false ? Icons.arrow_drop_down : Icons.arrow_drop_up,
          size: 20,
          color: up == null ? b.rule : b.paper,
        );
    Widget cell(String t,
        {double? w, int flex = 0, Widget? trailing, Widget? below, VoidCallback? onTap}) {
      final content = Container(
        padding: const EdgeInsets.fromLTRB(10, 14, 6, 10),
        decoration: BoxDecoration(border: Border(right: BorderSide(color: b.rule))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(
                child: Text(t.toUpperCase(),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: style)),
            ?trailing,
          ]),
          if (below != null) ...[const SizedBox(height: 8), below],
        ]),
      );
      final tap = onTap == null
          ? content
          : MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(onTap: onTap, child: content));
      return w != null ? SizedBox(width: w, child: tap) : Expanded(flex: flex, child: tap);
    }

    return Container(
      height: 92,
      decoration: BoxDecoration(
        color: b.surface,
        border: Border(bottom: BorderSide(color: b.rule, width: 2)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: resizableRowCells(context, [
        SizedBox(
          width: _wSel,
          child: Container(
            alignment: Alignment.topCenter,
            padding: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(border: Border(right: BorderSide(color: b.rule))),
            child: Checkbox(
              value: allSelected,
              onChanged: (v) => onSelectAll(v ?? false),
            ),
          ),
        ),
        cell('Serial', w: _wSerial),
        cell('Identity',
            flex: 20,
            trailing: arrow(sort == _Sort.nameAsc
                ? true
                : sort == _Sort.nameDesc
                    ? false
                    : null),
            onTap: () => onSort(true)),
        cell('Received',
            w: _wReceived,
            trailing: arrow(sort == _Sort.dateAsc
                ? true
                : sort == _Sort.dateDesc
                    ? false
                    : null),
            onTap: () => onSort(false)),
        cell('Communication', flex: 23),
        cell('Location Registry',
            flex: 20,
            below: SizedBox(
              height: 32,
              child: TextField(
                controller: locFilter,
                onChanged: (_) => onLocChanged(),
                style: const TextStyle(fontSize: 13.5),
                decoration: const InputDecoration(
                  hintText: 'Filter location...',
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
              ),
            )),
        cell('Business Line', w: _wBiz),
        cell('Specific Business Line', w: _wSpec),
        cell('Subscribe', w: _wSub),
        cell('Notes', flex: 20),
        cell('Action', w: _wAction),
      ], header: true)),
    );
  }
}

class _LeadRow extends StatefulWidget {
  const _LeadRow({
    required this.lead,
    required this.isNew,
    required this.selected,
    required this.onSelect,
    required this.onOpen,
    required this.onMenu,
  });

  final Json lead;
  final bool isNew;
  final bool selected;
  final ValueChanged<bool> onSelect;
  final VoidCallback onOpen;
  final ValueChanged<Offset> onMenu;

  @override
  State<_LeadRow> createState() => _LeadRowState();
}

class _LeadRowState extends State<_LeadRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final l = widget.lead;
    final phone = opsStr(l['phone']);
    final email = opsStr(l['email']);
    final notes = opsStr(l['notes']);
    final subscribed = opsStr(l['subscribe']) == '1';
    Widget pill(String t) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F1EE),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(t.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: Color(0xFF0C233E))),
        );
    Widget cell(Widget c, {double? w, int flex = 0}) {
      final p = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10), child: c);
      return w != null ? SizedBox(width: w, child: p) : Expanded(flex: flex, child: p);
    }

    final name = opsStr(l['name']).isEmpty ? '—' : opsStr(l['name']);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onDoubleTap: widget.onOpen,
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            color: widget.selected
                ? Brand.signal.withValues(alpha: 0.08)
                : widget.isNew
                    ? Brand.signal.withValues(alpha: 0.04)
                    : (_hover ? b.surfaceHi : b.surface),
            border: Border(bottom: BorderSide(color: b.rule)),
          ),
          child: Row(children: resizableRowCells(context, [
            SizedBox(
              width: _wSel,
              child: Checkbox(
                value: widget.selected,
                onChanged: (v) => widget.onSelect(v ?? false),
              ),
            ),
            cell(
                Text('#${opsStr(l['id'])}',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        color: b.paperDim)),
                w: _wSerial),
            cell(
                Row(children: [
                  Flexible(
                    child: Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                            color: b.paper)),
                  ),
                  if (widget.isNew) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: Brand.signal,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('NEW',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6)),
                    ),
                  ],
                ]),
                flex: 20),
            cell(
                Text(opsStr(l['created_at']),
                    maxLines: 1,
                    style: TextStyle(fontSize: 12.5, color: b.paperDim)),
                w: _wReceived),
            cell(
                phone.isEmpty && email.isEmpty
                    ? const Text('—', style: TextStyle(color: Color(0xFFCCCCCC)))
                    : Row(children: [
                        if (phone.isNotEmpty)
                          Flexible(
                            child: Text(phone,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14.5,
                                    color: b.paper)),
                          ),
                        if (phone.isNotEmpty && email.isNotEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text('·',
                                style: TextStyle(color: Color(0xFFCBD5E1))),
                          ),
                        if (email.isNotEmpty)
                          Expanded(
                            child: Tooltip(
                              message: email,
                              child: Text(email,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 14.5, color: b.paperDim)),
                            ),
                          ),
                      ]),
                flex: 23),
            cell(
                Tooltip(
                  message: opsStr(l['location']),
                  child: Text(
                      opsStr(l['location']).isEmpty ? '—' : opsStr(l['location']),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13.5, color: b.paperDim)),
                ),
                flex: 20),
            cell(
                Align(
                    alignment: Alignment.centerLeft,
                    child: pill(opsStr(l['businessType']).isEmpty
                        ? 'GENERAL'
                        : opsStr(l['businessType']))),
                w: _wBiz),
            cell(
                Align(
                    alignment: Alignment.centerLeft,
                    child: pill(opsStr(l['customBusinessType']).isEmpty
                        ? 'N/A'
                        : opsStr(l['customBusinessType']))),
                w: _wSpec),
            cell(
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(subscribed ? Icons.check_circle : Icons.cancel,
                      size: 13,
                      color: subscribed
                          ? const Color(0xFF28A745)
                          : const Color(0xFF6C757D)),
                  const SizedBox(width: 4),
                  Text(subscribed ? 'Subscribed' : 'Opt-out',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: subscribed
                              ? const Color(0xFF28A745)
                              : const Color(0xFF6C757D))),
                ]),
                w: _wSub),
            cell(
                Text(notes.replaceAll(RegExp(r'\s+'), ' ').trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontStyle: FontStyle.italic,
                        color: b.paperDim)),
                flex: 20),
            SizedBox(
              width: _wAction,
              child: Center(
                child: Builder(builder: (ctx) {
                  return MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTapDown: (d) => widget.onMenu(d.globalPosition),
                      child: Container(
                        width: 34,
                        height: 28,
                        decoration: BoxDecoration(
                          color: b.surface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: b.rule),
                        ),
                        child: Icon(Icons.arrow_drop_down,
                            size: 20, color: b.paper),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ])),
        ),
      ),
    );
  }
}

class _Pager extends StatelessWidget {
  const _Pager({
    required this.page,
    required this.pages,
    required this.pageSize,
    required this.onPage,
    required this.onPageSize,
  });

  final int page;
  final int pages;
  final int pageSize;
  final ValueChanged<int> onPage;
  final ValueChanged<int> onPageSize;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    Widget btn(String label, int? target, {bool active = false}) => Padding(
          padding: const EdgeInsets.only(left: 4),
          child: MouseRegion(
            cursor: target == null
                ? SystemMouseCursors.basic
                : SystemMouseCursors.click,
            child: GestureDetector(
              onTap: target == null ? null : () => onPage(target),
              child: Container(
                height: 40,
                constraints: const BoxConstraints(minWidth: 34),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: active ? Brand.signal : b.surface,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: active ? Brand.signal : b.rule),
                ),
                child: Text(label,
                    style: TextStyle(
                        fontSize: 15,
                        color: active
                            ? Colors.white
                            : target == null
                                ? b.paperDim
                                : b.paper)),
              ),
            ),
          ),
        );
    var start = (page - 2).clamp(0, pages - 1);
    final end = (start + 4).clamp(0, pages - 1);
    start = (end - 4).clamp(0, pages - 1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: b.surfaceHi,
        border: Border(top: BorderSide(color: b.rule)),
      ),
      child: Row(children: [
        Text('Page Size',
            style: TextStyle(
                fontWeight: FontWeight.w700, fontSize: 15, color: b.paper)),
        const SizedBox(width: 10),
        OpsSelect<int>(
          value: pageSize,
          width: 64,
          height: 30,
          items: const [(15, '15'), (20, '20'), (25, '25'), (30, '30')],
          onChanged: onPageSize,
        ),
        const Spacer(),
        btn('First', page > 0 ? 0 : null),
        btn('Prev', page > 0 ? page - 1 : null),
        for (var i = start; i <= end; i++)
          btn('${i + 1}', i == page ? null : i, active: i == page),
        btn('Next', page < pages - 1 ? page + 1 : null),
        btn('Last', page < pages - 1 ? pages - 1 : null),
      ]),
    );
  }
}

class _LeadProfile extends StatefulWidget {
  const _LeadProfile({
    required this.lead,
    required this.svc,
    required this.onChanged,
  });
  final Json lead;
  final OpsDataService svc;
  final VoidCallback onChanged;

  @override
  State<_LeadProfile> createState() => _LeadProfileState();
}

class _LeadProfileState extends State<_LeadProfile>
    with LiveRefresh<_LeadProfile> {
  late final Json _l = Map<String, dynamic>.from(widget.lead);
  bool _editing = false;
  bool _saving = false;
  bool _removed = false;
  bool _liveBusy = false;

  @override
  List<String> get liveKeys => const ['clientOffer'];

  @override
  void onLiveChange() => _liveRefresh();

  Future<void> _liveRefresh() async {
    if (_liveBusy || _removed || _saving) return;
    _liveBusy = true;
    List<Json> rows;
    try {
      rows = await widget.svc.leads();
    } finally {
      _liveBusy = false;
    }
    if (!mounted || rows.isEmpty) return;
    final id = opsInt(_l['id']);
    final hit = rows.where((r) => opsInt(r['id']) == id);
    if (hit.isEmpty) {
      setState(() => _removed = true);
      return;
    }
    if (_editing || _saving) return;
    final fresh = hit.first;
    setState(() {
      _l
        ..clear()
        ..addAll(fresh);
      _phone.text = opsStr(fresh['phone']);
    });
  }
  late final TextEditingController _phone =
      TextEditingController(text: opsStr(_l['phone']));

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  List<(String, String, bool)> get _fields {
    final bt = opsStr(_l['businessType']);
    final spec = opsStr(_l['customBusinessType']);
    return [
      ('Full Name', opsStr(_l['name']), false),
      ('Phone', opsStr(_l['phone']), true),
      ('Email', opsStr(_l['email']), false),
      ('Location', opsStr(_l['location']), false),
      ('Business Line', bt == 'Other' ? 'Other (${spec.isEmpty ? 'N/A' : spec})' : bt, false),
      ('Specific Business Line', spec, false),
      ('Requirements', opsStr(_l['message']), false),
      ('Source', opsStr(_l['source']), false),
      ('Subscription', opsStr(_l['subscribe']) == '1' ? 'Subscribed' : 'Opt-out', false),
      ('Date Received', opsStr(_l['created_at']), false),
      ('Notes', opsStr(_l['notes']), false),
    ];
  }

  Future<void> _savePhone() async {
    final v = _phone.text.trim();
    if (v.isEmpty) {
      opsToast(context, 'Phone cannot be empty.', error: true);
      return;
    }
    if (v == opsStr(_l['phone'])) {
      setState(() => _editing = false);
      return;
    }
    setState(() => _saving = true);
    final r = await widget.svc.updateLeadPhone(opsInt(_l['id']), v);
    if (!mounted) return;
    setState(() => _saving = false);
    if (r.ok) {
      setState(() {
        _l['phone'] = opsStr(r.data['phone']).isEmpty ? v : opsStr(r.data['phone']);
        _editing = false;
      });
      opsToast(context, 'Phone updated.');
      widget.onChanged();
    } else {
      opsToast(context, r.message.isEmpty ? 'Failed to update phone' : r.message,
          error: true);
    }
  }

  void _copy(String text, String msg) {
    Clipboard.setData(ClipboardData(text: text));
    opsToast(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    final fields = _fields;
    final empty = fields.where((f) => f.$2.trim().isEmpty).length;
    const navy = Color(0xFF0C233E);
    Widget sq(IconData i, Color fg, VoidCallback onTap, {Color bg = const Color(0xFFFAFAFA)}) =>
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFECECEC)),
            ),
            child: Icon(i, size: 13, color: fg),
          ),
        );
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 560,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 28),
          Container(
            width: 78,
            height: 78,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Brand.signal, width: 3),
            ),
            child: const Text('i',
                style: TextStyle(
                    color: Brand.signal, fontSize: 38, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 10),
          const Text('Lead Details',
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800, color: navy)),
          const SizedBox(height: 16),
          if (_removed)
            Container(
              margin: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: const Color(0xFFFDECEC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFF2B8B5)),
              ),
              child: const Row(children: [
                Icon(Icons.info_outline, size: 17, color: navy),
                SizedBox(width: 10),
                Expanded(
                  child: Text('This record was removed',
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: navy)),
                ),
              ]),
            ),
          if (empty > 0)
            Container(
              margin: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFF5D27A)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.warning_amber_rounded, size: 17, color: navy),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(
                        text: '$empty field(s) are empty. ',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const TextSpan(
                        text: 'This lead has not provided these details yet.'),
                  ]), style: const TextStyle(fontSize: 13.5, color: navy)),
                ),
              ]),
            ),
          Flexible(
            child: Container(
              margin: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              constraints: const BoxConstraints(maxHeight: 360),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFF0F0F0)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView(shrinkWrap: true, children: [
                for (var i = 0; i < fields.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    decoration: BoxDecoration(
                      border: i == fields.length - 1
                          ? null
                          : const Border(bottom: BorderSide(color: Color(0xFFF3F3F3))),
                    ),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(
                        width: 170,
                        child: Text(fields[i].$1,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14, color: navy)),
                      ),
                      Expanded(
                        child: fields[i].$3 && _editing
                            ? Row(children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 30,
                                    child: TextField(
                                      controller: _phone,
                                      autofocus: true,
                                      onSubmitted: (_) => _savePhone(),
                                      decoration: const InputDecoration(
                                          contentPadding: EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 6)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                sq(_saving ? Icons.hourglass_empty : Icons.check,
                                    Colors.white, _savePhone,
                                    bg: const Color(0xFF16A34A)),
                                const SizedBox(width: 6),
                                sq(Icons.close, const Color(0xFF64748B),
                                    () => setState(() => _editing = false)),
                              ])
                            : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Expanded(
                                  child: fields[i].$2.trim().isEmpty
                                      ? const Text('(empty)',
                                          style: TextStyle(
                                              fontStyle: FontStyle.italic,
                                              color: Color(0xFF9A9A9A)))
                                      : SelectableText(fields[i].$2,
                                          style: const TextStyle(
                                              fontSize: 14, color: navy, height: 1.45)),
                                ),
                                if (fields[i].$2.trim().isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  sq(Icons.copy, Brand.signal,
                                      () => _copy(fields[i].$2, '${fields[i].$1} copied')),
                                ],
                                if (fields[i].$3) ...[
                                  const SizedBox(width: 6),
                                  sq(Icons.edit, const Color(0xFF0F172A), () {
                                    _phone.text = opsStr(_l['phone']);
                                    setState(() => _editing = true);
                                  }),
                                ],
                              ]),
                      ),
                    ]),
                  ),
              ]),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
            decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFF0F0F0)))),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: navy),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: () => _copy(
                  fields
                      .map((f) => '${f.$1}: ${f.$2.trim().isEmpty ? '(empty)' : f.$2}')
                      .join('\n'),
                  'Lead details copied to clipboard',
                ),
                icon: const Icon(Icons.copy, size: 15),
                label: const Text('Copy Details'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _PrModal extends StatelessWidget {
  const _PrModal({
    required this.eyebrow,
    required this.title,
    required this.child,
    required this.actions,
    this.width = 620,
    this.footerTop,
  });

  final String eyebrow;
  final String title;
  final Widget child;
  final List<Widget> actions;
  final double width;
  final Widget? footerTop;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Dialog(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: width,
            minWidth: width,
            maxHeight: MediaQuery.sizeOf(context).height - 64),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 28, 20, 20),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(eyebrow.toUpperCase(),
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.6,
                          color: Brand.signal)),
                  const SizedBox(height: 6),
                  Text(title,
                      style: TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w800, color: b.paper)),
                ]),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(Icons.close, color: b.paperDim),
              ),
            ]),
          ),
          Divider(height: 1, color: b.rule),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
              child: child,
            ),
          ),
          Divider(height: 1, color: b.rule),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (footerTop != null) ...[footerTop!, const SizedBox(height: 12)],
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  actions[i],
                ],
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

Widget _prLabel(BuildContext context, String t, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Expanded(
          child: Text(t.toUpperCase(),
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: context.brand.paperDim)),
        ),
        ?trailing,
      ]),
    );

class _MemoModal extends StatefulWidget {
  const _MemoModal({required this.lead, required this.svc});
  final Json lead;
  final OpsDataService svc;

  @override
  State<_MemoModal> createState() => _MemoModalState();
}

class _MemoModalState extends State<_MemoModal> {
  late final _text = TextEditingController(text: opsStr(widget.lead['notes']));
  bool _busy = false;
  static const _quick = [
    ('Sent SMS', 'Sent SMS'),
    ('Already Called', 'Already Called'),
    ('No Answering on Phone', 'No Answering'),
    ('Sent Email', 'Sent Email'),
    ('Follow Up', 'Follow Up'),
  ];

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool _has(String t) => _text.text.toLowerCase().contains('- $t'.toLowerCase());

  void _toggle(String t, bool on) {
    final add = '- $t';
    final cur = _text.text;
    if (on) {
      if (!cur.toLowerCase().contains(add.toLowerCase())) {
        _text.text = cur.trim().isNotEmpty ? '${cur.trim()}\n$add' : add;
      }
    } else {
      _text.text = cur
          .split('\n')
          .where((l) => l.trim().toLowerCase() != add.toLowerCase())
          .join('\n')
          .trim();
    }
    setState(() {});
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final r = await widget.svc.updateLeadNote(opsInt(widget.lead['id']), _text.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      opsToast(context, 'Note updated successfully');
      Navigator.of(context).pop(true);
    } else {
      opsToast(context, 'Failed to update note', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _PrModal(
      eyebrow: '03 — Internal Memo',
      title: 'Lead Notes',
      width: 560,
      actions: [
        GhostButton(label: 'Close', onPressed: () => Navigator.of(context).pop()),
        OpsButton(
            label: 'Commit Note', color: Brand.signal, busy: _busy, onPressed: _save),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        _prLabel(context, 'Registry Annotations'),
        TextField(
          controller: _text,
          minLines: 6,
          maxLines: 10,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(hintText: 'Document lead feedback here...'),
        ),
        const SizedBox(height: 20),
        _prLabel(context, 'Quick Status Injection:'),
        Wrap(spacing: 14, runSpacing: 4, children: [
          for (final q in _quick)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Checkbox(value: _has(q.$1), onChanged: (v) => _toggle(q.$1, v ?? false)),
              Text(q.$2, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
            ]),
        ]),
      ]),
    );
  }
}

class _SmsModal extends StatefulWidget {
  const _SmsModal({required this.lead, required this.svc, required this.onSent});
  final Json lead;
  final OpsDataService svc;
  final VoidCallback onSent;

  @override
  State<_SmsModal> createState() => _SmsModalState();
}

class _SmsModalState extends State<_SmsModal>
    with LiveRefresh<_SmsModal> {
  final _msg = TextEditingController();
  final _scroll = ScrollController();
  List<Json>? _thread;
  bool _live = true;
  bool _busy = false;
  String _sig = '';

  int get _id => opsInt(widget.lead['id']);

  Timer? _timer;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _poll());
  }

  @override
  List<String> get liveKeys => const ['clientOffer'];

  @override
  void onLiveChange() => _poll();

  @override
  void dispose() {
    _timer?.cancel();
    _msg.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _poll() async {
    if (_polling) return;
    _polling = true;
    final List<Json>? t;
    try {
      t = await widget.svc.leadSmsThread(_id);
    } finally {
      _polling = false;
    }
    if (!mounted) return;
    if (t == null) {
      setState(() => _live = false);
      return;
    }
    final last = t.isEmpty ? null : t.last;
    final sig = '${t.length}|${last == null ? '' : '${last['id']}|${last['created_at']}'}';
    final grew = sig != _sig;
    setState(() {
      _live = true;
      _sig = sig;
      _thread = t;
    });
    if (!grew) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _send() async {
    final m = _msg.text.trim();
    if (m.isEmpty) return;
    setState(() => _busy = true);
    final r = await widget.svc.sendLeadSms(_id, m);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      opsToast(context, 'SMS dispatched successfully.');
      _msg.clear();
      _poll();
      widget.onSent();
    } else {
      opsToast(context, r.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final name = opsStr(widget.lead['name']);
    final phone = opsStr(widget.lead['phone']);
    return _PrModal(
      eyebrow: '02 — SMS Transmission (PhilSMS)',
      title: 'Send SMS to ${name.isEmpty ? phone : name}',
      width: 560,
      actions: [
        GhostButton(label: 'Close', onPressed: () => Navigator.of(context).pop()),
        OpsButton(
            label: _busy ? 'Sending...' : 'Send SMS',
            color: Brand.signal,
            busy: _busy,
            onPressed: _send),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        _prLabel(context, 'Recipient'),
        TextField(
          enabled: false,
          controller: TextEditingController(text: '${name.isEmpty ? 'Lead' : name} — $phone'),
        ),
        const SizedBox(height: 16),
        _prLabel(context, 'Conversation',
            trailing: Text(_live ? 'Live' : 'offline',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: _live ? b.paperDim : const Color(0xFFE0A800)))),
        Container(
          height: 240,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0x05000000),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: b.rule),
          ),
          child: _thread == null
              ? Center(child: Text('Loading…', style: TextStyle(color: b.paperDim)))
              : _thread!.isEmpty
                  ? Align(
                      alignment: Alignment.topCenter,
                      child: Text('No messages yet.',
                          style: TextStyle(fontSize: 13.5, color: b.paperDim)))
                  : ListView(controller: _scroll, children: [
                      for (final m in _thread!)
                        _SmsBubble(m: m),
                    ]),
        ),
        const SizedBox(height: 16),
        _prLabel(context, 'Message',
            trailing: Text('${_msg.text.length} / 459',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: b.paperDim))),
        TextField(
          controller: _msg,
          minLines: 6,
          maxLines: 6,
          maxLength: 459,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
              counterText: '', hintText: 'Type the SMS message...'),
        ),
        const SizedBox(height: 6),
        Text(
            'Up to 459 characters (3 SMS segments). Replies from the lead appear above when PhilSMS forwards them.',
            style: TextStyle(fontSize: 12, color: b.paperDim)),
      ]),
    );
  }
}

class _SmsBubble extends StatelessWidget {
  const _SmsBubble({required this.m});
  final Json m;

  @override
  Widget build(BuildContext context) {
    final out = opsStr(m['direction']) == 'out';
    final b = context.brand;
    final d = opsParseDate(opsStr(m['created_at']));
    final ts = d == null ? '' : opsFullDate(opsStr(m['created_at']));
    return Align(
      alignment: out ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: const BoxConstraints(maxWidth: 380),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: out ? const Color(0x2E6366F1) : const Color(0x0AFFFFFF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: out ? const Color(0x666366F1) : b.rule),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${out ? 'You' : 'Lead'} • $ts',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: b.paperDim)),
          const SizedBox(height: 2),
          Text(opsStr(m['message']), style: const TextStyle(fontSize: 13.5)),
        ]),
      ),
    );
  }
}

class _Tpl {
  const _Tpl(this.title, this.hint, this.subject, this.body, this.fg, this.bg, {this.id});
  final String title;
  final String hint;
  final String subject;
  final String body;
  final Color fg;
  final Color bg;
  final String? id;
}

const _builtinTpls = <_Tpl>[
  _Tpl('Blank', 'Start fresh', '', '', Color(0xFF666666), Color(0xFFF5F5F5)),
  _Tpl('Welcome', 'Greeting lead', 'Welcome to TinkerPro POS!',
      '<div style="background: #e3f2fd; border: 2px solid #2196f3; border-radius: 12px; padding: 25px; font-family: sans-serif; color: #333; line-height: 1.6;"><h2 style="color: #1565c0; margin-top: 0;">Welcome to TinkerPro!</h2><p>Hi \$name,</p><p>Thank you for choosing TinkerPro! We\'re excited to help you optimize your business operations with our state-of-the-art POS solutions.</p><p>Feel free to reach out if you have any questions or need a demo.</p><p>Best regards,<br><strong>TinkerPro Team</strong></p></div>',
      Color(0xFF1565C0), Color(0xFFE3F2FD)),
  _Tpl('Special Offer', 'Exclusive deal', 'Exclusive Offer: 20% Off Your First Year!',
      '<div style="background: #fff3e0; border: 2px solid #ff9800; border-radius: 12px; padding: 25px; font-family: sans-serif; color: #333; line-height: 1.6; text-align: center;"><h2 style="color: #e65100; margin-top: 0;">Special Offer for You!</h2><p>Hello \$name,</p><p style="font-size: 18px;">Get <strong>20% OFF</strong> your first year\'s subscription on any of our POS packages!</p><p>Don\'t miss this chance to upgrade your business management at a discounted rate.</p><p style="margin-top: 20px;"><a href="#" style="background: #ff9800; color: white; padding: 10px 20px; text-decoration: none; border-radius: 5px; font-weight: bold;">Claim Offer Now</a></p><p style="margin-top: 20px; font-size: 12px; color: #777;">Limited time only. Terms and conditions apply.</p></div>',
      Color(0xFFE65100), Color(0xFFFFF3E0)),
  _Tpl('Follow-up', 'Checking in', 'Checking in on your inquiry',
      '<div style="background: #f3e5f5; border: 2px solid #9c27b0; border-radius: 12px; padding: 25px; font-family: sans-serif; color: #333; line-height: 1.6;"><h3 style="color: #4a148c; margin-top: 0;">Just checking in...</h3><p>Hi \$name,</p><p>I just wanted to follow up on our previous conversation regarding our POS systems. Do you have any further questions or would you like to schedule a personalized walkthrough?</p><p>We\'re here to help you make the best decision for your business.</p><p>Warm regards,<br>Dealer Support</p></div>',
      Color(0xFF4A148C), Color(0xFFF3E5F5)),
  _Tpl('Thank You', 'Post-interaction', 'Thank you for your time!',
      '<div style="background: #fce4ec; border: 2px solid #e91e63; border-radius: 12px; padding: 25px; font-family: sans-serif; color: #333; line-height: 1.6;"><h2 style="color: #880e4f; margin-top: 0;">Thank You!</h2><p>Hi \$name,</p><p>It was a pleasure speaking with you today. Thank you for your interest in TinkerPro and for sharing more about your business needs.</p><p>I\'ll be sending over the additional information we discussed shortly.</p><p>Best,<br><strong>TinkerPro Sales</strong></p></div>',
      Color(0xFF880E4F), Color(0xFFFCE4EC)),
];

class _EmailModal extends StatefulWidget {
  const _EmailModal({required this.leads, required this.svc});
  final List<Json> leads;
  final OpsDataService svc;

  @override
  State<_EmailModal> createState() => _EmailModalState();
}

class _EmailModalState extends State<_EmailModal> {
  final _subject = TextEditingController();
  final _body = TextEditingController();
  List<_Tpl> _tpls = [..._builtinTpls];
  int? _picked;
  bool _showTpls = true;
  bool _busy = false;
  double? _progress;
  String _progressText = '';

  bool get _bulk => widget.leads.length > 1;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    final recent = await widget.svc.recentTemplate();
    final custom = await widget.svc.emailTemplates();
    if (!mounted) return;
    setState(() {
      _tpls = [
        _builtinTpls.first,
        _Tpl('Recent', 'Last used', opsStr(recent['subject']), opsStr(recent['body']),
            const Color(0xFF2E7D32), const Color(0xFFE8F5E9)),
        ..._builtinTpls.skip(1),
        for (final t in custom)
          _Tpl(opsStr(t['name']), opsStr(t['subject']), opsStr(t['subject']),
              opsStr(t['body']), const Color(0xFF1565C0), const Color(0xFFE3F2FD),
              id: opsStr(t['id'])),
      ];
    });
  }

  Future<void> _send() async {
    final subject = _subject.text;
    if (subject.isEmpty) {
      opsToast(context, 'Please fill out the Transmission Subject field.', error: true);
      return;
    }
    final tplId = _picked == null ? null : _tpls[_picked!].id;
    setState(() => _busy = true);
    final body = await widget.svc.richTextHtml(_body.text);
    if (!mounted) return;
    if (body == null) {
      setState(() => _busy = false);
      opsToast(context, 'Error occurred while sending email', error: true);
      return;
    }
    if (_bulk) {
      var ok = 0;
      var fail = 0;
      for (var i = 0; i < widget.leads.length; i++) {
        setState(() {
          _progress = (i + 1) / widget.leads.length;
          _progressText = 'Sending ${i + 1} of ${widget.leads.length}...';
        });
        final r = await widget.svc.sendLeadEmail(
            leadId: opsInt(widget.leads[i]['id']),
            subject: subject,
            body: body,
            templateId: tplId);
        r.ok ? ok++ : fail++;
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Bulk Email Completed'),
          content: Text('Successfully sent: $ok. Failed: $fail.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
      return;
    }
    final r = await widget.svc.sendLeadEmail(
        leadId: opsInt(widget.leads.first['id']),
        subject: subject,
        body: body,
        templateId: tplId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      opsToast(context, 'Email sent successfully');
      Navigator.of(context).pop(true);
    } else {
      opsToast(context, r.message.isEmpty ? 'Failed to send email' : r.message,
          error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _bulk
        ? 'Send Bulk Email to ${widget.leads.length} Leads'
        : 'Send Email to ${opsStr(widget.leads.first['email'])}';
    return _PrModal(
      eyebrow: '02 — Communication Portal',
      title: title,
      width: 820,
      footerTop: _progress == null
          ? null
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                    value: _progress, minHeight: 6, color: Brand.signal),
              ),
              const SizedBox(height: 8),
              Text(_progressText.toUpperCase(),
                  style: const TextStyle(
                      color: Brand.signal, fontWeight: FontWeight.w700, fontSize: 12)),
            ]),
      actions: [
        GhostButton(label: 'Close', onPressed: () => Navigator.of(context).pop()),
        OpsButton(
          label: _busy
              ? (_bulk ? 'Sending Bulk...' : 'Sending...')
              : (_bulk ? 'Send Bulk Email' : 'Send Email'),
          color: Brand.signal,
          busy: _busy,
          onPressed: _send,
        ),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        _prLabel(context, 'Transmission Subject'),
        TextField(
            controller: _subject,
            decoration: const InputDecoration(hintText: 'Enter subject line...')),
        const SizedBox(height: 22),
        InkWell(
          onTap: () => setState(() => _showTpls = !_showTpls),
          child: _prLabel(context, 'Visual Templates',
              trailing: AnimatedRotation(
                turns: _showTpls ? 0.5 : 0,
                duration: const Duration(milliseconds: 300),
                child: const Icon(Icons.keyboard_arrow_down, color: Brand.signal),
              )),
        ),
        if (_showTpls)
          SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _tpls.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final t = _tpls[i];
                final sel = _picked == i;
                return InkWell(
                  onTap: () => setState(() {
                    _picked = i;
                    _subject.text = t.subject;
                    _body.text = t.body;
                  }),
                  child: Container(
                    width: 150,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: t.bg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: sel ? Brand.signal : t.fg.withValues(alpha: 0.6),
                          width: sel ? 2.5 : 1.5),
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: t.fg, fontWeight: FontWeight.w700, fontSize: 13)),
                      const SizedBox(height: 2),
                      Text(t.hint,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: t.fg, fontSize: 11)),
                    ]),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 22),
        _prLabel(context, 'Message Payload'),
        TextField(
          controller: _body,
          minLines: 12,
          maxLines: 18,
          style: const TextStyle(fontSize: 14, height: 1.6),
          decoration: const InputDecoration(
              hintText:
                  'Write your message. Plain text is sent as paragraphs; templates insert styled HTML (\$name is replaced with the lead name).'),
        ),
      ]),
    );
  }
}
