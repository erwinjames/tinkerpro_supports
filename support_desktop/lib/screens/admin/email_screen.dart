import 'package:flutter/material.dart';

import '../../models/admin_models.dart';
import '../../services/admin_services.dart';
import '../../theme.dart';
import '../../widgets/admin_table_page.dart';
import '../../widgets/premium.dart';
import 'admin_email_compose.dart';
import 'admin_list.dart';

class EmailScreen extends StatefulWidget {
  const EmailScreen({super.key, required this.service});
  final EmailService service;

  @override
  State<EmailScreen> createState() => _EmailScreenState();
}

class _EmailScreenState extends State<EmailScreen> {
  EmailService get service => widget.service;
  final _subs = AdminTableController();
  final _internal = AdminTableController();
  int _tab = 0;
  String _source = 'all';
  bool _selectMode = false;
  final Set<String> _selected = {};
  int _internalCount = 0;
  List<EmailRecipient> _subsItems = const [];
  List<Map<String, dynamic>> _internalItems = const [];
  final _composer = GmComposerState();
  bool _showList = false;
  String _internalFilter = 'all';
  String _internalQuery = '';
  List<Map<String, dynamic>> _roles = const [];
  List<Map<String, dynamic>> _labels = const [];

  Future<Paged<EmailRecipient>> _fetchSubs(String search) async {
    final res = await service.api.post(
      'getEmails',
      body: {
        'page': '1',
        'limit': '100000',
        'search': search,
        'source': _source,
      },
    );
    final raw = res['data'];
    final items = raw is List
        ? raw
              .whereType<Map>()
              .map((m) => EmailRecipient.fromJson(Map<String, dynamic>.from(m)))
              .toList()
        : <EmailRecipient>[];
    _subsItems = items;
    return Paged(
      items: items,
      total:
          int.tryParse('${res['totalRecords'] ?? items.length}') ??
          items.length,
    );
  }

  List<Map<String, dynamic>> _maps(dynamic raw) => raw is List
      ? raw.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
      : <Map<String, dynamic>>[];

  Future<Paged<Map<String, dynamic>>> _fetchInternal(String search) async {
    final res = await service.internal(
      search: _internalQuery,
      filter: _internalFilter,
    );
    final items = _maps(res['data']);
    _internalItems = items;
    final total =
        int.tryParse('${res['totalRecords'] ?? items.length}') ?? items.length;
    _syncFilters(res['filters'], total: _internalFilter == 'all' ? total : null);
    return Paged(items: items, total: total);
  }

  void _syncFilters(dynamic filters, {int? total}) {
    final f = filters is Map ? filters : const {};
    final roles = _maps(f['roles']);
    final labels = _maps(f['labels']);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _roles = roles;
        _labels = labels;
        if (total != null) _internalCount = total;
        if (!_filterValues().contains(_internalFilter)) {
          _internalFilter = 'all';
        }
      });
    });
  }

  Future<void> _loadInternalCount() async {
    try {
      final res = await service.internal(page: 1, limit: 1, filter: 'all');
      _syncFilters(
        res['filters'],
        total: int.tryParse('${res['totalRecords'] ?? 0}') ?? 0,
      );
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _loadInternalCount();
  }

  @override
  void dispose() {
    _composer.subject.dispose();
    _composer.message.dispose();
    super.dispose();
  }

  List<String> _filterValues() => [
    'all',
    'staff',
    for (final r in _roles) 'role:${r['role']}',
    'contacts',
    for (final l in _labels) 'label:${l['label']}',
    'label:__none__',
  ];

  String _prettyRole(String r) => (r.isEmpty ? 'user' : r).replaceAll('_', ' ');

  Widget _panelHeader(String title, List<Widget> trailing) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 14, 16, 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AdminTableColors.border)),
      ),
      child: Row(
        children: [
          Container(width: 3, height: 16, color: Brand.signal),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AdminTableColors.text,
            ),
          ),
          const Spacer(),
          ...trailing,
        ],
      ),
    );
  }

  Widget _sourceButton() {
    const labels = {'all': 'All', 'emails': 'Emails', 'leads': 'Leads'};
    const colors = {
      'all': Color(0xFF6C757D),
      'emails': Color(0xFF28A745),
      'leads': Color(0xFF007BFF),
    };
    return Material(
      color: colors[_source],
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () {
          const order = ['all', 'emails', 'leads'];
          setState(() => _source = order[(order.indexOf(_source) + 1) % 3]);
          _subs.reload();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.filter_alt, size: 14, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                labels[_source]!,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _subscribers() {
    return AdminTablePage<EmailRecipient>(
      stationNumber: '13',
      stationLabel: 'EMAIL',
      title: 'Email',
      tableId: 'email:subscribers',
      embedded: true,
      controller: _subs,
      liveKeys: const ['emails'],
      filterKey: _source,
      searchHint: 'Search email…',
      searchInToolbar: false,
      pageSizes: const [10, 15, 20, 25, 30],
      initialPageSize: 30,
      fetch: _fetchSubs,
      onRowTap: _selectMode
          ? (ctx, r, refresh) => setState(
              () => _selected.contains(r.email)
                  ? _selected.remove(r.email)
                  : _selected.add(r.email),
            )
          : (ctx, r, refresh) => _compose(ctx, to: r.email),
      columns: [
        const AdminColumn('No.', width: 70, sortable: false),
        AdminColumn(
          'Email',
          flex: 3,
          sortValue: (r) => (r as EmailRecipient).email,
        ),
        AdminColumn(
          'Business type',
          flex: 3,
          sortValue: (r) => (r as EmailRecipient).businessType,
        ),
        AdminColumn(
          'Source',
          width: 100,
          center: true,
          sortValue: (r) => (r as EmailRecipient).source,
        ),
        AdminColumn(
          'Date subscribed',
          flex: 3,
          sortValue: (r) => (r as EmailRecipient).createdAt,
        ),
        const AdminColumn('Action', width: 140, center: true, sortable: false),
      ],
      cells: (ctx, r, refresh) {
        final leads = r.source.toLowerCase() == 'leads';
        final picked = _selected.contains(r.email);
        return [
          AdminCellText('${_subsItems.indexOf(r) + 1}'),
          AdminCellText(r.email),
          AdminCellText(
            r.businessType.isEmpty ? 'Not provided' : r.businessType,
          ),
          AdminBadge(
            r.source.isEmpty ? 'emails' : r.source,
            solid: true,
            color: leads ? const Color(0xFF007BFF) : const Color(0xFF28A745),
          ),
          AdminCellText(adminFormatDate(r.createdAt, withTime: true)),
          _selectMode
              ? IconButton(
                  tooltip: picked ? 'Deselect' : 'Select',
                  icon: Icon(
                    picked ? Icons.check_box : Icons.check_box_outline_blank,
                    color: picked ? Brand.signal : AdminTableColors.muted,
                  ),
                  onPressed: () => setState(
                    () => picked
                        ? _selected.remove(r.email)
                        : _selected.add(r.email),
                  ),
                )
              : AdminRowMenu(
                  actions: [
                    AdminMenuAction(
                      'Send Email',
                      Icons.send_outlined,
                      () => _compose(ctx, to: r.email),
                    ),
                    AdminMenuAction(
                      'Delete',
                      Icons.delete_outline,
                      () => _delete(ctx, refresh, r),
                      danger: true,
                    ),
                  ],
                ),
        ];
      },
      tableTitle: _panelHeader('Email List', [
        _sourceButton(),
        const SizedBox(width: 10),
        SizedBox(
          width: 280,
          child: SearchField(
            hint: 'Search email…',
            width: 280,
            onSubmitted: (v) => _subsSearch(v),
            onChanged: (v) => _subsSearch(v),
          ),
        ),
      ]),
      searchable: false,
    );
  }

  String _subsQuery = '';
  void _subsSearch(String v) {
    if (v.trim() == _subsQuery) return;
    _subsQuery = v.trim();
    _subs.search(_subsQuery);
  }

  Widget _filterDropdown() {
    DropdownMenuItem<String> item(String v, String t, {bool head = false}) =>
        DropdownMenuItem(
          value: v,
          enabled: !head,
          child: Text(
            t,
            style: TextStyle(
              fontSize: 13,
              fontWeight: head ? FontWeight.w800 : FontWeight.w500,
              color: head ? AdminTableColors.muted : AdminTableColors.text,
            ),
          ),
        );
    final items = <DropdownMenuItem<String>>[
      item('all', 'All recipients'),
      item('__h_staff', 'Staff accounts', head: true),
      item('staff', '  All staff'),
      for (final r in _roles)
        item('role:${r['role']}', '  ${_prettyRole('${r['role']}')} (${r['total']})'),
      item('__h_added', 'Added emails', head: true),
      item('contacts', '  All added emails'),
      for (final l in _labels)
        item('label:${l['label']}', '  ${l['label']} (${l['total']})'),
      item('label:__none__', '  — No label —'),
    ];
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AdminTableColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _internalFilter,
          items: items,
          onChanged: (v) {
            if (v == null || v.startsWith('__h_')) return;
            setState(() => _internalFilter = v);
            _internal.reload();
          },
        ),
      ),
    );
  }

  void _addToTo(Map<String, dynamic> r) {
    final email = (r['email'] ?? '').toString();
    final name = (r['name'] ?? '').toString();
    final chip = GmChip(
      kind: 'email',
      value: email,
      label: name.isEmpty ? email : name,
      sub: email,
    );
    final alreadyInTo = _composer.hasChip('to', chip);
    final res = _composer.addChip('to', chip);
    setState(() => _showList = false);
    final who = name.isEmpty ? email : name;
    if (res == null) {
      toast(context, '$who added to To.');
    } else if (alreadyInTo) {
      toast(context, '$who is already in To.');
    } else if (res.isNotEmpty) {
      toast(context, res);
    }
  }

  Future<void> _editContact(Map<String, dynamic>? contact) async {
    final saved = await showContactModal(
      context,
      service: service,
      contact: contact,
      labels: [for (final l in _labels) '${l['label']}'],
    );
    if (saved) {
      _composer.suggestCache.clear();
      _internal.reload();
    }
  }

  Future<void> _deleteContact(Map<String, dynamic> r) async {
    final email = (r['email'] ?? '').toString();
    if (!await confirmDialog(
      context,
      title: 'Remove this email?',
      message: '$email will be removed from the internal recipient list.',
      confirmLabel: 'Remove email',
    )) {
      return;
    }
    if (!mounted) return;
    adminUndoDelete(
      context,
      message: 'Email removed',
      commit: () async {
        try {
          final res = await service.deleteContact('${r['id']}');
          if (res.ok) {
            _composer.suggestCache.clear();
            _selected.remove(email);
            if (mounted) setState(() => _composer.removeEmail(email));
          } else if (mounted) {
            toast(
              context,
              res.message.isNotEmpty ? res.message : 'Could not remove email.',
            );
          }
        } catch (_) {
          if (mounted) toast(context, 'Could not remove email.');
        }
        _internal.reload();
      },
    );
  }

  Widget _internalTable() {
    return AdminTablePage<Map<String, dynamic>>(
      stationNumber: '13',
      stationLabel: 'EMAIL',
      title: 'Email',
      tableId: 'email:internal',
      embedded: true,
      controller: _internal,
      liveKeys: const ['emails', 'user'],
      searchHint: 'Search name, email, company…',
      searchable: false,
      filterKey: _internalFilter,
      pageSizes: const [10, 15, 20, 25, 30],
      initialPageSize: 10,
      emptyLabel:
          'No recipients yet — use Add Email to include someone without an account',
      fetch: _fetchInternal,
      tableTitle: _panelHeader('Internal Recipients', [
        GhostButton(
          label: 'Composer',
          icon: Icons.arrow_back,
          onPressed: () => setState(() => _showList = false),
        ),
        const SizedBox(width: 8),
        SignalButton(
          label: 'Add Email',
          icon: Icons.add,
          onPressed: () => _editContact(null),
        ),
        const SizedBox(width: 8),
        _filterDropdown(),
        const SizedBox(width: 8),
        SizedBox(
          width: 260,
          child: SearchField(
            hint: 'Search name, email, company…',
            width: 260,
            onChanged: (v) {
              if (v.trim() == _internalQuery) return;
              _internalQuery = v.trim();
              _internal.reload();
            },
            onSubmitted: (v) {
              _internalQuery = v.trim();
              _internal.reload();
            },
          ),
        ),
      ]),
      columns: [
        const AdminColumn('No.', width: 70, sortable: false),
        AdminColumn(
          'Name',
          flex: 3,
          sortValue: (r) => '${(r as Map)['name'] ?? ''}',
        ),
        AdminColumn(
          'Email',
          flex: 3,
          sortValue: (r) => '${(r as Map)['email'] ?? ''}',
        ),
        AdminColumn(
          'Type',
          width: 120,
          center: true,
          sortValue: (r) => '${(r as Map)['source'] ?? ''}',
        ),
        AdminColumn(
          'Role / Label',
          width: 170,
          center: true,
          sortValue: (r) => '${(r as Map)['tag'] ?? ''}',
        ),
        const AdminColumn('Action', width: 140, center: true, sortable: false),
      ],
      cells: (ctx, r, refresh) {
        final staff = r['source'] == 'staff';
        final contact = r['source'] == 'contact';
        final tag = (r['tag'] ?? '').toString();
        final sub = (r['subtitle'] ?? '').toString();
        final name = (r['name'] ?? '').toString();
        return [
          AdminCellText('${_internalItems.indexOf(r) + 1}'),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AdminCellText(
                name.isEmpty ? '—' : name,
                bold: true,
                size: 14.5,
              ),
              if (sub.isNotEmpty)
                Text(
                  staff ? '@$sub' : sub,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AdminTableColors.muted,
                  ),
                ),
            ],
          ),
          AdminCellText((r['email'] ?? '').toString()),
          AdminBadge(
            staff ? 'Staff' : 'Added',
            color: staff ? Brand.info : Brand.signal,
          ),
          tag.isEmpty
              ? const AdminCellText('—', muted: true)
              : AdminBadge(
                  staff ? _prettyRole(tag) : tag,
                  color: staff ? const Color(0xFF6366F1) : Brand.success,
                ),
          AdminRowMenu(
            actions: [
              AdminMenuAction(
                "Add to the composer's To field",
                Icons.send_outlined,
                () => _addToTo(r),
              ),
              if (contact) ...[
                AdminMenuAction(
                  'Edit Email',
                  Icons.edit_outlined,
                  () => _editContact(r),
                ),
                AdminMenuAction(
                  'Delete Email',
                  Icons.delete_outline,
                  () => _deleteContact(r),
                  danger: true,
                ),
              ],
            ],
          ),
        ];
      },
    );
  }

  Widget _internalPanel() {
    return IndexedStack(
      index: _showList ? 1 : 0,
      children: [
        InternalComposer(
          service: service,
          state: _composer,
          onManage: () => setState(() => _showList = true),
          onRecipientsChanged: () {
            if (mounted) setState(() {});
            _loadInternalCount();
          },
        ),
        _internalTable(),
      ],
    );
  }

  void _exitSelection() {
    _selectMode = false;
    _selected.clear();
  }

  Future<void> _sendSelected() async {
    if (_selected.isEmpty) {
      await showWebModal<void>(
        context,
        title: 'No Recipients Selected',
        icon: Icons.warning_amber_rounded,
        width: 420,
        builder: (_) => const Text('Please select at least one recipient'),
        actions: (c) => [
          SignalButton(label: 'OK', onPressed: () => Navigator.pop(c)),
        ],
      );
      return;
    }
    final emails = _selected.toList();
    final done = await showSubscriberCompose(
      context,
      service: service,
      mode: ComposeMode.selected,
      selected: emails,
    );
    if (done && mounted) {
      setState(_exitSelection);
      _subs.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StationScaffold(
      stationNumber: '13',
      stationLabel: 'EMAIL',
      title: 'Email',
      showBottomBrand: false,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      trailing: _tab != 0
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SignalButton(
                  label: 'Mail All',
                  icon: Icons.send,
                  onPressed: () => showSubscriberCompose(
                    context,
                    service: service,
                    mode: ComposeMode.all,
                  ),
                ),
                const SizedBox(width: 10),
                GhostButton(
                  label: _selectMode ? 'Cancel' : 'Bulk Send',
                  icon: _selectMode ? Icons.close : Icons.check_box_outlined,
                  onPressed: () => setState(() {
                    if (_selectMode) {
                      _exitSelection();
                    } else {
                      _selectMode = true;
                    }
                  }),
                ),
                if (_selectMode) ...[
                  const SizedBox(width: 10),
                  SignalButton(
                    label: 'Send to Selected ${_selected.length}',
                    icon: Icons.send,
                    onPressed: _sendSelected,
                  ),
                ],
              ],
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminTabBar(
            tabs: [
              const AdminTab('Subscribers', icon: Icons.groups),
              AdminTab(
                'Internal Email',
                icon: Icons.admin_panel_settings,
                count: '$_internalCount',
              ),
            ],
            index: _tab,
            onChanged: (i) => setState(() {
              if (i != _tab) _exitSelection();
              _tab = i;
            }),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [_subscribers(), _internalPanel()],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    VoidCallback refresh,
    EmailRecipient r,
  ) async {
    final source = r.source.isEmpty ? 'emails' : r.source;
    if (!await confirmDialog(
      context,
      title: 'Delete this $source entry?',
      message: 'This $source record will be permanently removed from your list.',
      confirmLabel: 'Delete entry',
    )) {
      return;
    }
    if (!context.mounted) return;
    adminUndoDelete(
      context,
      message: 'Email removed',
      commit: () async {
        try {
          final res = await service.delete(id: r.id, source: source);
          if (!res.ok && context.mounted) {
            toast(
              context,
              res.message.isNotEmpty ? res.message : 'Failed to delete entry.',
            );
          }
        } catch (_) {
          if (context.mounted) toast(context, 'Failed to delete entry.');
        }
        refresh();
      },
    );
  }

  Future<void> _compose(BuildContext context, {required String to}) async {
    await showSubscriberCompose(
      context,
      service: service,
      mode: ComposeMode.single,
      email: to,
    );
  }
}
