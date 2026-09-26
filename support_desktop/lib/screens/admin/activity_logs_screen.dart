import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../api_client.dart';
import '../../models/admin_models.dart';
import '../../services/admin_services.dart';
import '../../theme.dart';
import '../../widgets/admin_table_page.dart';
import '../../widgets/premium.dart';
import 'activity_trace_dialog.dart';

typedef _Row = Map<String, dynamic>;

String _v(_Row r, String k) => (r[k] ?? '').toString().trim();

List<_Row> _rowsOf(Map<String, dynamic> res) {
  final data = res['data'];
  if (data is List) {
    return data
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }
  if (res.containsKey('error')) return <_Row>[];
  return res.values
      .whereType<Map>()
      .map((m) => Map<String, dynamic>.from(m))
      .toList();
}

class ActivityLogsScreen extends StatefulWidget {
  const ActivityLogsScreen({super.key, required this.service});
  final ActivityLogService service;

  @override
  State<ActivityLogsScreen> createState() => _ActivityLogsScreenState();
}

class _ActivityLogsScreenState extends State<ActivityLogsScreen> {
  int _tab = 0;
  final _counts = List<int>.filled(6, 0);
  final _searchCtrl = TextEditingController();
  String _search = '';
  String _user = '';
  String _action = '';
  DateTime? _from;
  DateTime? _to;
  String _pendingUser = '';
  String _pendingAction = '';
  DateTime? _pendingFrom;
  DateTime? _pendingTo;
  List<String> _users = const [];
  List<String> _actions = const [];
  int _shown = 0;

  final _tkSearch = TextEditingController();
  String _tkQuery = '';
  String _tkStatus = '';
  String _tkPriority = '';
  final _cvSearch = TextEditingController();
  String _cvQuery = '';
  String _cvType = '';

  ApiClient get _api => widget.service.api;

  bool _trace = false;
  String _tileKey = '';

  @override
  void initState() {
    super.initState();
    _loadMapConfig();
  }

  Future<void> _loadMapConfig() async {
    try {
      final res = await _api.get('desktopActivityMapConfig');
      if (!mounted) return;
      setState(() {
        _trace = res['trace'] == true;
        _tileKey = (res['map_tile_key'] ?? '').toString();
      });
    } catch (_) {}
    if (!kDebugMode || !mounted) return;
    final id = Platform.environment['TP_LOG_DETAIL'] ?? '';
    if (id.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_trace) {
        _openTrace(context, 'Log #$id', {'subject': 'log', 'log_id': id});
      } else {
        _details(context, {'id': id});
      }
    });
  }

  Future<void> _openTrace(
    BuildContext context,
    String fallbackTitle,
    Map<String, String> query,
  ) {
    return showActivityTraceDialog(
      context,
      api: _api,
      tileKey: _tileKey,
      fallbackTitle: fallbackTitle,
      query: query,
    );
  }

  AdminRowTap<_Row>? _traceTap(
    String Function(_Row r) title,
    Map<String, String> Function(_Row r) query,
  ) {
    if (!_trace) return null;
    return (ctx, r, _) => _openTrace(ctx, title(r), query(r));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _tkSearch.dispose();
    _cvSearch.dispose();
    super.dispose();
  }

  void _setCount(int i, int n) {
    if (_counts[i] == n) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _counts[i] = n);
    });
  }

  Future<Paged<_Row>> _path(
    String path,
    int tab, [
    Map<String, String>? q,
  ]) async {
    final rows = _rowsOf(await _api.getPath(path, q));
    _setCount(tab, rows.length);
    return Paged(items: rows, total: rows.length);
  }

  Future<Paged<_Row>> _fetchLogs(String _) async {
    final rows = _rowsOf(await _api.getPath('utils/models/get_logs.php'));
    final users = <String>{};
    final actions = <String>{};
    for (final r in rows) {
      final u = _v(r, 'username');
      if (u.isNotEmpty) users.add(u);
      final a = _v(r, 'action');
      if (a.isNotEmpty) actions.add(a);
    }
    _setCount(0, rows.length);
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _users = users.toList()..sort();
          _actions = actions.toList()..sort();
          _shown = rows.where(_logMatches).length;
        });
      });
    }
    _allLogs = rows;
    return Paged(items: rows, total: rows.length);
  }

  List<_Row> _allLogs = const [];

  Future<Paged<_Row>> _fetchConversations(String _) async {
    final rows = _rowsOf(await _api.get('chat.adminListConversations'));
    _setCount(3, rows.length);
    return Paged(items: rows, total: rows.length);
  }

  bool _logMatches(_Row r) {
    if (_user.isNotEmpty && _v(r, 'username') != _user) return false;
    if (_action.isNotEmpty && _v(r, 'action') != _action) return false;
    final d = DateTime.tryParse(_v(r, 'created_at'));
    if (_from != null && (d == null || d.isBefore(_from!))) return false;
    if (_to != null &&
        (d == null || d.isAfter(_to!.add(const Duration(days: 1))))) {
      return false;
    }
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      final hay = [
        _v(r, 'username'),
        _v(r, 'action'),
        _v(r, 'details'),
        _v(r, 'ip_address'),
        _v(r, 'location'),
        _v(r, 'created_at'),
      ].join(' ').toLowerCase();
      if (!hay.contains(q)) return false;
    }
    return true;
  }

  void _apply() {
    setState(() {
      _search = _searchCtrl.text.trim();
      _user = _pendingUser;
      _action = _pendingAction;
      _from = _pendingFrom;
      _to = _pendingTo;
      _shown = _allLogs.where(_logMatches).length;
    });
  }

  void _reset() {
    _searchCtrl.clear();
    setState(() {
      _pendingUser = '';
      _pendingAction = '';
      _pendingFrom = null;
      _pendingTo = null;
    });
    _apply();
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      t,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Color(0xFF374151),
      ),
    ),
  );

  Widget _box(Widget child) => Container(
    height: 40,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: const Color(0xFFD1D5DB)),
    ),
    alignment: Alignment.centerLeft,
    child: child,
  );

  Widget _drop(
    String value,
    String all,
    List<String> options,
    ValueChanged<String> onChanged,
  ) {
    return _box(
      DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: options.contains(value) ? value : '',
          isExpanded: true,
          style: const TextStyle(fontSize: 14, color: AdminTableColors.text),
          items: [
            DropdownMenuItem(value: '', child: Text(all)),
            for (final o in options) DropdownMenuItem(value: o, child: Text(o)),
          ],
          onChanged: (v) => onChanged(v ?? ''),
        ),
      ),
    );
  }

  Widget _date(DateTime? value, String hint, ValueChanged<DateTime?> set) {
    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? now,
          firstDate: DateTime(2015),
          lastDate: DateTime(now.year + 1),
        );
        set(picked);
      },
      child: _box(
        Row(
          children: [
            Expanded(
              child: Text(
                value == null ? hint : adminIsoDate(value),
                style: TextStyle(
                  fontSize: 14,
                  color: value == null
                      ? AdminTableColors.headerText
                      : AdminTableColors.text,
                ),
              ),
            ),
            const Icon(
              Icons.calendar_month,
              size: 15,
              color: Color(0xFF888888),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterButton(String label, Color bg, Color fg, VoidCallback onTap) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 14.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _filterCard(List<Widget> groups, String info) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AdminTableColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, box) {
              if (box.maxWidth >= 1000) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < groups.length; i++) ...[
                      if (i > 0) const SizedBox(width: 15),
                      groups[i],
                    ],
                  ],
                );
              }
              final half = ((box.maxWidth - 15) / 2).floorToDouble();
              return Wrap(
                spacing: 15,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  for (final g in groups)
                    if (g is Expanded)
                      SizedBox(
                        width: g.flex >= 2 || half < 200 ? box.maxWidth : half,
                        child: g.child,
                      )
                    else
                      g,
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(
              style: const TextStyle(
                fontSize: 14,
                color: AdminTableColors.headerText,
              ),
              children: [
                const TextSpan(text: 'Showing '),
                TextSpan(
                  text: info,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AdminTableColors.text,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _group(String label, Widget field, {int flex = 1}) => Expanded(
    flex: flex,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [_label(label), field],
    ),
  );

  Widget _heading(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
    child: Text(
      t,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w500,
        color: AdminTableColors.text,
      ),
    ),
  );

  Widget _locationCell(_Row r) {
    final loc = _v(r, 'location');
    final local = loc.toLowerCase().contains('local');
    return Row(
      children: [
        Icon(
          local ? Icons.lan_outlined : Icons.place_outlined,
          size: 16,
          color: AdminTableColors.headerText,
        ),
        const SizedBox(width: 8),
        Flexible(child: AdminCellText(loc.isEmpty ? '—' : loc)),
      ],
    );
  }

  Widget _ipCell(_Row r) {
    final sub = [
      if (_v(r, 'ip_v4').isNotEmpty) _v(r, 'ip_v4'),
      if (_v(r, 'ip_lan').isNotEmpty) _v(r, 'ip_lan'),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminCellText(_v(r, 'ip_address').isEmpty ? '—' : _v(r, 'ip_address')),
        if (sub.isNotEmpty)
          Text(
            sub.join('   '),
            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
          ),
      ],
    );
  }

  AdminColumn _col(
    String label,
    String field, {
    int flex = 1,
    double? width,
    bool center = false,
  }) => AdminColumn(
    label,
    flex: flex,
    width: width,
    center: center,
    sortValue: (r) => _v(r as _Row, field),
  );

  Widget _userActivity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _filterCard([
          _group(
            'Search',
            _box(
              TextField(
                controller: _searchCtrl,
                onSubmitted: (_) => _apply(),
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Search in all fields...',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
          _group(
            'Username',
            _drop(
              _pendingUser,
              'All Users',
              _users,
              (v) => setState(() => _pendingUser = v),
            ),
          ),
          _group(
            'Action',
            _drop(
              _pendingAction,
              'All Actions',
              _actions,
              (v) => setState(() => _pendingAction = v),
            ),
          ),
          _group(
            'Date Range',
            Row(
              children: [
                Expanded(
                  child: _date(
                    _pendingFrom,
                    'From',
                    (d) => setState(() => _pendingFrom = d),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    'to',
                    style: TextStyle(color: AdminTableColors.headerText),
                  ),
                ),
                Expanded(
                  child: _date(
                    _pendingTo,
                    'To',
                    (d) => setState(() => _pendingTo = d),
                  ),
                ),
              ],
            ),
            flex: 2,
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _filterButton(
                'Apply',
                const Color(0xFF2563EB),
                Colors.white,
                _apply,
              ),
              const SizedBox(width: 8),
              _filterButton(
                'Reset',
                const Color(0xFF6B7280),
                Colors.white,
                _reset,
              ),
            ],
          ),
        ], '$_shown log(s)'),
        _heading('Logs'),
        Expanded(
          child: AdminTablePage<_Row>(
            tableId: 'activity:user',
            stationNumber: '16',
            stationLabel: 'ACTIVITY LOGS',
            title: 'Activity Logs',
            embedded: true,
            searchable: false,
            rowMinHeight: 40,
            pageSizes: const [10, 25, 50, 100],
            initialPageSize: 25,
            liveKeys: const ['activitylogs'],
            fetch: _fetchLogs,
            filterKey: '$_search|$_user|$_action|$_from|$_to',
            rowFilter: _logMatches,
            onRowTap: (ctx, r, _) => _trace
                ? _openTrace(
                    ctx,
                    '${_v(r, 'username').isEmpty ? 'User' : _v(r, 'username')} — ${_v(r, 'action').isEmpty ? 'Activity' : _v(r, 'action')}',
                    {'subject': 'log', 'log_id': _v(r, 'id')},
                  )
                : _details(ctx, r),
            columns: [
              _col('Username', 'username', width: 150),
              _col('Action', 'action', width: 150),
              _col('Details', 'details', flex: 1),
              _col('IP Address', 'ip_address', width: 175),
              _col('Location', 'location', width: 200),
              _col('Created At', 'created_at', width: 190),
            ],
            cells: (ctx, r, _) => [
              AdminCellText(
                _v(r, 'username').isEmpty ? 'Unknown User' : _v(r, 'username'),
              ),
              AdminCellText(_v(r, 'action'), bold: true),
              AdminCellText(_v(r, 'details'), maxLines: 2),
              _ipCell(r),
              _locationCell(r),
              AdminCellText(_v(r, 'created_at')),
            ],
          ),
        ),
      ],
    );
  }

  Widget _simpleFilterCard(
    TextEditingController ctrl,
    String hint,
    List<Widget> extra,
    VoidCallback apply,
    VoidCallback reset,
    String info,
  ) {
    return _filterCard([
      _group(
        'Search',
        _box(
          TextField(
            controller: ctrl,
            onSubmitted: (_) => apply(),
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      ),
      ...extra,
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _filterButton('Apply', const Color(0xFF2563EB), Colors.white, apply),
          const SizedBox(width: 8),
          _filterButton('Reset', const Color(0xFF6B7280), Colors.white, reset),
        ],
      ),
    ], info);
  }

  bool _hay(_Row r, List<String> keys, String q) {
    if (q.isEmpty) return true;
    final s = keys.map((k) => _v(r, k)).join(' ').toLowerCase();
    return s.contains(q.toLowerCase());
  }

  Widget _statusBadge(String s) {
    final t = s.toLowerCase();
    final c = t == 'resolved' || t == 'closed'
        ? Brand.success
        : t == 'in_progress'
        ? Brand.info
        : t == 'assigned'
        ? const Color(0xFF6366F1)
        : Brand.warning;
    return AdminBadge(s.replaceAll('_', ' '), color: c);
  }

  Widget _tickets() {
    bool match(_Row r) =>
        (_tkStatus.isEmpty || _v(r, 'status').toLowerCase() == _tkStatus) &&
        (_tkPriority.isEmpty ||
            _v(r, 'priority').toLowerCase() == _tkPriority) &&
        _hay(r, [
          'subject',
          'customer_name',
          'business_name',
          'agent_full_name',
        ], _tkQuery);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _simpleFilterCard(
          _tkSearch,
          'Subject, customer, business, agent…',
          [
            _group(
              'Status',
              _drop(_tkStatus, 'All', const [
                'new',
                'assigned',
                'in_progress',
                'resolved',
                'closed',
              ], (v) => setState(() => _tkStatus = v)),
            ),
            _group(
              'Priority',
              _drop(_tkPriority, 'All', const [
                'low',
                'medium',
                'high',
              ], (v) => setState(() => _tkPriority = v)),
            ),
          ],
          () => setState(() => _tkQuery = _tkSearch.text.trim()),
          () => setState(() {
            _tkSearch.clear();
            _tkQuery = '';
            _tkStatus = '';
            _tkPriority = '';
          }),
          '${_counts[2]} ticket(s)',
        ),
        _heading('Tickets'),
        Expanded(
          child: AdminTablePage<_Row>(
            tableId: 'activity:tickets',
            stationNumber: '16',
            stationLabel: 'ACTIVITY LOGS',
            title: 'Activity Logs',
            embedded: true,
            searchable: false,
            rowMinHeight: 40,
            pageSizes: const [10, 25, 50, 100],
            initialPageSize: 25,
            liveKeys: const ['activitylogs', 'ticket'],
            fetch: (_) => _path('utils/models/get_tickets_log.php', 2),
            onRowTap: _traceTap(
              (r) =>
                  '#${_v(r, 'ticket_number').isEmpty ? _v(r, 'id') : _v(r, 'ticket_number')} — ${_v(r, 'subject').isEmpty ? 'Ticket' : _v(r, 'subject')}',
              (r) => {'subject': 'ticket', 'ticket_id': _v(r, 'id')},
            ),
            filterKey: '$_tkQuery|$_tkStatus|$_tkPriority',
            rowFilter: match,
            columns: [
              _col('Ticket', 'id', width: 90),
              _col('Subject', 'subject', flex: 2),
              _col('Customer', 'customer_name', width: 200),
              _col('Status', 'status', width: 140, center: true),
              _col('Priority', 'priority', width: 110, center: true),
              _col('Assigned to', 'agent_full_name', width: 170),
              _col('Created', 'created_at', width: 180),
              _col('Updated', 'updated_at', width: 180),
            ],
            cells: (ctx, r, _) => [
              AdminCellText('#${_v(r, 'id')}', bold: true),
              AdminCellText(_v(r, 'subject')),
              AdminCellText(_v(r, 'customer_name')),
              _statusBadge(_v(r, 'status')),
              AdminBadge(
                _v(r, 'priority'),
                color: _v(r, 'priority').toLowerCase() == 'high'
                    ? Brand.danger
                    : _v(r, 'priority').toLowerCase() == 'medium'
                    ? Brand.warning
                    : Brand.success,
              ),
              AdminCellText(_v(r, 'agent_full_name')),
              AdminCellText(_v(r, 'created_at'), size: 14),
              AdminCellText(_v(r, 'updated_at'), size: 14),
            ],
          ),
        ),
      ],
    );
  }

  Widget _conversations() {
    bool match(_Row r) =>
        (_cvType.isEmpty || _v(r, 'type').toLowerCase() == _cvType) &&
        _hay(r, ['name', 'topic', 'type'], _cvQuery);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _simpleFilterCard(
          _cvSearch,
          'Name, topic, type…',
          [
            _group(
              'Type',
              _drop(_cvType, 'All', const [
                'dm',
                'group',
              ], (v) => setState(() => _cvType = v)),
            ),
          ],
          () => setState(() => _cvQuery = _cvSearch.text.trim()),
          () => setState(() {
            _cvSearch.clear();
            _cvQuery = '';
            _cvType = '';
          }),
          '${_counts[3]} conversation(s)',
        ),
        _heading('Conversations'),
        Expanded(
          child: AdminTablePage<_Row>(
            tableId: 'activity:conversations',
            stationNumber: '16',
            stationLabel: 'ACTIVITY LOGS',
            title: 'Activity Logs',
            embedded: true,
            searchable: false,
            rowMinHeight: 40,
            pageSizes: const [10, 25, 50, 100],
            initialPageSize: 25,
            liveKeys: const ['activitylogs', 'chat'],
            fetch: _fetchConversations,
            filterKey: '$_cvQuery|$_cvType',
            rowFilter: match,
            columns: [
              _col('#', 'id', width: 80),
              _col('Conversation', 'name', flex: 2),
              _col('Type', 'type', width: 120, center: true),
              _col('Members', 'member_count', width: 110),
              _col('Messages', 'message_count', width: 120),
              _col('Tickets', 'ticket_count', width: 110),
              _col('Files', 'file_count', width: 100),
              _col('Last activity', 'last_activity_at', width: 190),
            ],
            cells: (ctx, r, _) => [
              AdminCellText(_v(r, 'id'), muted: true),
              AdminCellText(
                _v(r, 'name').isEmpty ? '(untitled)' : _v(r, 'name'),
                bold: true,
              ),
              AdminBadge(
                _v(r, 'type') == 'dm' ? 'Direct' : _v(r, 'type'),
                color: _v(r, 'type') == 'group' ? Brand.info : Brand.signal,
              ),
              AdminCellText(_v(r, 'member_count')),
              AdminCellText(_v(r, 'message_count')),
              AdminCellText(_v(r, 'ticket_count')),
              AdminCellText(_v(r, 'file_count')),
              AdminCellText(_v(r, 'last_activity_at'), size: 14),
            ],
          ),
        ),
      ],
    );
  }

  Widget _plainTable(
    int tab,
    String heading,
    String path,
    List<AdminColumn> columns,
    AdminCellsBuilder<_Row> cells, {
    List<String> liveKeys = const ['activitylogs'],
    AdminRowTap<_Row>? onRowTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(heading),
        Expanded(
          child: AdminTablePage<_Row>(
            tableId: 'activity:$path',
            stationNumber: '16',
            stationLabel: 'ACTIVITY LOGS',
            title: 'Activity Logs',
            embedded: true,
            searchable: false,
            rowMinHeight: 40,
            pageSizes: const [10, 25, 50, 100],
            initialPageSize: 25,
            liveKeys: liveKeys,
            fetch: (_) => _path(path, tab),
            onRowTap: onRowTap,
            columns: columns,
            cells: cells,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      AdminTab(
        'User Activity',
        icon: Icons.manage_history,
        count: '${_counts[0]}',
      ),
      AdminTab('Logged In', icon: Icons.circle, count: '${_counts[1]}'),
      AdminTab(
        'Tickets',
        icon: Icons.confirmation_number,
        count: '${_counts[2]}',
      ),
      AdminTab('Conversations', icon: Icons.forum, count: '${_counts[3]}'),
      AdminTab('Vendor & Taxpayer', icon: Icons.badge, count: '${_counts[4]}'),
      AdminTab(
        'Public Downloads',
        icon: Icons.cloud_download,
        count: '${_counts[5]}',
      ),
    ];
    return Scaffold(
      backgroundColor: context.brand.canvas,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: Colors.white,
            child: AdminTabBar(
              tabs: tabs,
              index: _tab,
              onChanged: (i) => setState(() => _tab = i),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
              child: IndexedStack(
                index: _tab,
                children: [
                  _userActivity(),
                  _plainTable(
                    1,
                    'Currently Logged In',
                    'utils/models/get_online_users.php',
                    [
                      _col('User', 'full_name', flex: 2),
                      _col('Role', 'role', width: 150),
                      _col('Last activity', 'last_activity', width: 210),
                      _col('IP Address', 'ip_address', width: 175),
                      _col('Location', 'location', width: 220),
                    ],
                    (ctx, r, _) => [
                      Row(
                        children: [
                          const Icon(
                            Icons.circle,
                            size: 9,
                            color: Brand.success,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: AdminCellText(
                              _v(r, 'full_name').isEmpty
                                  ? _v(r, 'username')
                                  : _v(r, 'full_name'),
                              bold: true,
                            ),
                          ),
                        ],
                      ),
                      AdminBadge(
                        _v(r, 'role').replaceAll('_', ' '),
                        color: Brand.info,
                      ),
                      AdminCellText(_v(r, 'last_activity'), size: 14),
                      _ipCell(r),
                      _locationCell(r),
                    ],
                    liveKeys: const ['activitylogs', 'user'],
                    onRowTap: _traceTap(
                      (r) =>
                          '${_v(r, 'full_name').isEmpty ? (_v(r, 'username').isEmpty ? 'User' : _v(r, 'username')) : _v(r, 'full_name')} — live trace',
                      (r) => {'subject': 'user', 'user_id': _v(r, 'id')},
                    ),
                  ),
                  _tickets(),
                  _conversations(),
                  _plainTable(
                    4,
                    'Vendor & Taxpayer Activity',
                    'utils/models/get_portal_activity_logs.php',
                    [
                      _col('Portal', 'source', width: 120, center: true),
                      _col('Who', 'actor', width: 190),
                      _col('Business', 'business', width: 210),
                      _col('Action', 'action', width: 180),
                      _col('Details', 'details', flex: 2),
                      _col('IP Address', 'ip_address', width: 150),
                      _col('Location', 'location', width: 180),
                      _col('Created At', 'created_at', width: 180),
                    ],
                    (ctx, r, _) => [
                      AdminBadge(
                        _v(r, 'source'),
                        color: _v(r, 'source').toLowerCase() == 'vendor'
                            ? Brand.info
                            : Brand.signal,
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AdminCellText(_v(r, 'actor'), bold: true, size: 14),
                          if (_v(r, 'actor_type').isNotEmpty)
                            Text(
                              _v(r, 'actor_type'),
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AdminTableColors.muted,
                              ),
                            ),
                        ],
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AdminCellText(_v(r, 'business'), size: 14),
                          if (_v(r, 'reference').isNotEmpty)
                            Text(
                              _v(r, 'reference'),
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AdminTableColors.muted,
                              ),
                            ),
                        ],
                      ),
                      AdminCellText(_v(r, 'action'), bold: true, size: 14),
                      AdminCellText(_v(r, 'details'), maxLines: 2, size: 14),
                      AdminCellText(_v(r, 'ip_address'), size: 14),
                      _locationCell(r),
                      AdminCellText(_v(r, 'created_at'), size: 14),
                    ],
                  ),
                  _plainTable(
                    5,
                    'Public Downloads',
                    'utils/models/get_share_access_logs.php',
                    [
                      _col('Collection', 'collection_name', flex: 2),
                      _col('Token', 'token_type', width: 140, center: true),
                      _col('IP Address', 'ip_address', width: 150),
                      _col('Location', 'location', width: 200),
                      _col('Device', 'device', width: 200),
                      _col('Accessed At', 'accessed_at', width: 190),
                    ],
                    (ctx, r, _) => [
                      AdminCellText(_v(r, 'collection_name'), bold: true),
                      AdminBadge(
                        _v(r, 'token_type').isEmpty
                            ? 'link'
                            : _v(r, 'token_type'),
                        color: _v(r, 'token_type').toLowerCase() == 'permanent'
                            ? Brand.success
                            : Brand.info,
                      ),
                      AdminCellText(_v(r, 'ip_address')),
                      _locationCell(r),
                      AdminCellText(_v(r, 'device'), size: 14),
                      AdminCellText(_v(r, 'accessed_at'), size: 14),
                    ],
                    liveKeys: const ['activitylogs', 'files'],
                    onRowTap: _traceTap(
                      (r) =>
                          '${_v(r, 'collection_name').isEmpty ? 'Share link' : _v(r, 'collection_name')} — opened',
                      (r) => {'subject': 'download', 'access_id': _v(r, 'id')},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _details(BuildContext context, _Row r) {
    final user = _v(r, 'username').isEmpty ? 'Unknown User' : _v(r, 'username');
    return showWebModal<void>(
      context,
      title: _v(r, 'action'),
      subtitle: adminFormatDate(_v(r, 'created_at'), withTime: true),
      icon: Icons.receipt_long_outlined,
      width: 620,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StationDataRow(label: 'Log ID', value: _v(r, 'id')),
          StationDataRow(label: 'User', value: user),
          StationDataRow(label: 'Action', value: _v(r, 'action')),
          StationDataRow(label: 'Date & time', value: _v(r, 'created_at')),
          StationDataRow(label: 'IP address', value: _v(r, 'ip_address')),
          StationDataRow(label: 'Location', value: _v(r, 'location')),
          const SizedBox(height: 14),
          Text(
            'Details',
            style: Theme.of(
              ctx,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ctx.brand.surfaceHi,
              border: Border.all(color: ctx.brand.rule),
              borderRadius: BorderRadius.circular(6),
            ),
            child: SelectableText(
              _v(r, 'details').isEmpty ? '—' : _v(r, 'details'),
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
      actions: (ctx) => [
        SignalButton(label: 'Close', onPressed: () => Navigator.pop(ctx)),
      ],
    );
  }
}
