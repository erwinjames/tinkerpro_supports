import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, SystemMouseCursors;
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api_client.dart';
import '../../services/employment_service.dart';
import '../../services/live_sync.dart';
import '../../theme.dart';
import '../../widgets/premium.dart';
import '../../widgets/web_zbe_kit.dart';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
const _longMonths = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

DateTime? _parse(String raw) {
  if (raw.isEmpty || raw.startsWith('0000-00-00')) return null;
  return DateTime.tryParse(raw.replaceFirst(' ', 'T'));
}

String _fmtDate(String raw) {
  final d = _parse(raw);
  if (d == null) return raw.isEmpty || raw.startsWith('0000') ? '—' : raw;
  return '${_months[d.month - 1]} ${d.day}, ${d.year}';
}

String _fmtLongDate(DateTime d) =>
    '${_longMonths[d.month - 1]} ${d.day}, ${d.year}';

String _fmtDateTime(String raw) {
  final d = _parse(raw);
  if (d == null) return raw.isEmpty ? '—' : raw;
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '${_months[d.month - 1]} ${d.day}, ${d.year}, $h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
}

String _statusLabel(String s) => switch (s) {
  'submitted' => 'Awaiting review',
  'reviewed' => 'Reviewed',
  'archived' => 'Archived',
  _ => s,
};

bool _has(String v) => v.trim().isNotEmpty && v.trim() != '—';

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message), persist: false));
}

Future<void> _copy(
  BuildContext context,
  String text, [
  String ok = 'Link copied',
]) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) _toast(context, ok);
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirm,
}) => zbeConfirm(
  context,
  title: title,
  message: message,
  confirm: confirm,
  danger: confirm == 'Delete' || confirm == 'Revoke',
);

class EmploymentScreen extends StatefulWidget {
  const EmploymentScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<EmploymentScreen> createState() => _EmploymentScreenState();
}

class _EmploymentScreenState extends State<EmploymentScreen>
    with LiveRefresh<EmploymentScreen> {
  late final EmploymentService _svc = EmploymentService(widget.api);
  final _searchCtrl = TextEditingController();
  Timer? _searchTimer;
  bool _recordsBusy = false;
  bool _pulseBusy = false;
  String? _pulseKey;
  int _pulseLatest = 0;

  EmploymentMeta _meta = EmploymentMeta.fallback;
  EmploymentSummary _summary = const EmploymentSummary();
  int _tab = 0;
  String _search = '';
  String _status = '';
  int _page = 1;
  int _pageSize = 15;
  int _total = 0;
  List<EmploymentRow> _rows = const [];
  bool _loading = true;
  String? _error;
  final Set<int> _hiddenRecords = {};

  List<EmploymentLink> _links = const [];
  bool _linksLoaded = false;
  bool _linksLoading = false;
  String? _linksError;
  final Set<int> _hiddenLinks = {};

  List<StaffOption>? _staff;
  String _staffMessage = '';

  @override
  void initState() {
    super.initState();
    _svc.meta().then((m) {
      if (mounted) setState(() => _meta = m);
    });
    _loadRecords();
    _pulseCheck();
  }

  @override
  List<String> get liveKeys => const ['employment'];

  @override
  void onLiveChange() {
    if (!_recordsBusy) _loadRecords(silent: true);
    if (_linksLoaded && !_linksLoading) _loadLinks(silent: true);
    _pulseCheck();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRecords({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    _recordsBusy = true;
    try {
      final page = await _svc.records(
        search: _search,
        status: _status,
        page: _page,
        limit: _pageSize,
      );
      if (!mounted) return;
      final lastPage = page.total == 0 ? 1 : (page.total / _pageSize).ceil();
      if (_page > lastPage) {
        _page = lastPage;
        _recordsBusy = false;
        return _loadRecords(silent: silent);
      }
      setState(() {
        _rows = page.rows;
        _total = page.total;
        _summary = page.summary;
        if (!silent) _hiddenRecords.clear();
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (silent && _rows.isNotEmpty) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      _recordsBusy = false;
    }
  }

  Future<void> _loadLinks({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _linksLoading = true;
        _linksError = null;
      });
    }
    try {
      final links = await _svc.links();
      if (!mounted) return;
      setState(() {
        _links = links;
        _linksLoaded = true;
        if (!silent) _hiddenLinks.clear();
        _linksLoading = false;
        _linksError = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (silent && _linksLoaded) return;
      setState(() {
        _linksLoading = false;
        _linksError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _pulseCheck() async {
    if (_pulseBusy) return;
    _pulseBusy = true;
    try {
      final p = await _svc.pulse();
      if (p == null || !mounted) return;
      if (_pulseKey == null) {
        _pulseKey = p.key;
        _pulseLatest = p.latestId;
        return;
      }
      if (p.key == _pulseKey) return;
      final fresh = p.latestId > _pulseLatest;
      _pulseKey = p.key;
      _pulseLatest = p.latestId;
      if (fresh && mounted) {
        _toast(context, 'A new employment information sheet just came in.');
      }
    } finally {
      _pulseBusy = false;
    }
  }

  void _refreshAll() {
    _loadRecords();
    if (_linksLoaded) _loadLinks();
  }

  Future<List<StaffOption>> _loadStaff({bool force = false}) async {
    if (_staff != null && !force) return _staff!;
    try {
      final res = await _svc.staff();
      _staff = res.users;
      _staffMessage = res.message;
      if (res.users.isEmpty && mounted) {
        _toast(
          context,
          _staffMessage.isNotEmpty
              ? _staffMessage
              : 'No staff accounts available — use "Someone else" to type the name',
        );
      }
    } catch (_) {
      _staff = [];
      if (mounted) {
        _toast(
          context,
          'Could not load the staff list — use "Someone else" to type the name',
        );
      }
    }
    return _staff!;
  }

  void _onSearch(String v) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 300), () {
      _search = v;
      _page = 1;
      _loadRecords();
    });
  }

  Future<void> _openCreateLink() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CreateLinkDialog(
        service: _svc,
        meta: _meta,
        loadStaff: _loadStaff,
        onCreated: () {
          _staff = null;
          _loadLinks();
          _loadRecords();
        },
        onEmailed: _loadLinks,
      ),
    );
  }

  Future<EmploymentRecord?> _fetch(int id) async {
    final r = await _svc.fetchRecord(id);
    if (r.record == null && mounted) _toast(context, r.message);
    return r.record;
  }

  Future<bool> _ensureStaffLinked({
    required int id,
    required String name,
    required bool linked,
  }) async {
    if (linked) return true;
    final staff = await _loadStaff();
    if (!mounted) return false;
    final res = await showDialog<EmpResult>(
      context: context,
      builder: (_) => _StaffLinkDialog(
        service: _svc,
        recordId: id,
        name: name,
        staff: staff,
      ),
    );
    if (res == null || !res.ok) return false;
    _staff = null;
    if (mounted) _toast(context, res.message);
    _loadRecords();
    return true;
  }

  Future<void> _openRecord(int id) async {
    final record = await _fetch(id);
    if (record == null || !mounted) return;
    final ok = await _ensureStaffLinked(
      id: record.id,
      name: record.fullName,
      linked: record.isStaffLinked,
    );
    if (!ok || !mounted) return;
    final fresh = record.isStaffLinked ? record : (await _fetch(id) ?? record);
    if (!mounted) return;
    final action = await showDialog<String>(
      context: context,
      builder: (_) => _RecordViewDialog(
        record: fresh,
        service: _svc,
        onReviewed: _loadRecords,
      ),
    );
    if (!mounted) return;
    if (action == 'edit') {
      _editById(fresh.id);
    } else if (action == 'print') {
      _promptPrint(fresh.id);
    }
  }

  Future<void> _editById(int id) async {
    final record = await _fetch(id);
    if (record == null || !mounted) return;
    _openEdit(record);
  }

  Future<void> _openEdit(EmploymentRecord record) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _EditRecordDialog(record: record, meta: _meta, service: _svc),
    );
    if (saved == true) _loadRecords();
  }

  Future<void> _printRow(EmploymentRow row) async {
    final ok = await _ensureStaffLinked(
      id: row.id,
      name: row.fullName,
      linked: row.isStaffLinked,
    );
    if (ok) _promptPrint(row.id);
  }

  Future<void> _promptPrint(int id) async {
    final saved = await _svc.authName();
    if (!mounted) return;
    if (saved.remember) {
      _printPdf(id, saved.name);
      final shown = saved.name.isNotEmpty
          ? '"${saved.name}"'
          : 'a blank authorization name';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Printing with $shown.'),
          duration: const Duration(seconds: 6),
          persist: false,
          action: SnackBarAction(
            label: 'Change',
            onPressed: () async {
              await _svc.forgetAuthRemember();
              if (mounted) _promptPrint(id);
            },
          ),
        ),
      );
      return;
    }
    final result = await showDialog<({String name, bool remember})>(
      context: context,
      builder: (_) => _AuthNameDialog(initial: saved.name),
    );
    if (result == null) return;
    await _svc.saveAuthName(result.name, result.remember);
    _printPdf(id, result.name);
  }

  Future<void> _printPdf(int id, String authName) async {
    try {
      final path = await _svc.downloadPdf(id, authName);
      final r = await OpenFilex.open(path);
      if (r.type != ResultType.done && mounted) {
        _toast(context, 'Saved to $path');
      }
    } catch (e) {
      if (mounted) {
        _toast(
          context,
          'Could not print the sheet: ${e.toString().replaceFirst('Exception: ', '')}',
        );
      }
    }
  }

  Future<void> _markReviewed(EmploymentRow row) async {
    final next = row.status == 'reviewed' ? 'submitted' : 'reviewed';
    final res = await _svc.setStatus(row.id, next);
    if (!mounted) return;
    _toast(context, res.message.isNotEmpty ? res.message : 'Updated');
    if (res.ok) _loadRecords();
  }

  void _undoable({
    required String message,
    required VoidCallback hide,
    required VoidCallback unhide,
    required Future<void> Function() commit,
  }) {
    hide();
    final controller = ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 5),
        persist: false,
        action: SnackBarAction(label: 'Undo', onPressed: () {}),
      ),
    );
    controller.closed.then((reason) {
      if (reason == SnackBarClosedReason.action) {
        unhide();
      } else {
        commit();
      }
    });
  }

  Future<void> _deleteRecord(EmploymentRow row) async {
    if (!await _confirm(
      context,
      title: 'Delete this sheet?',
      message:
          'The employee record and its dependents are permanently removed.',
      confirm: 'Delete',
    )) {
      return;
    }
    if (!mounted) return;
    _undoable(
      message: 'Record deleted',
      hide: () => setState(() => _hiddenRecords.add(row.id)),
      unhide: () {
        if (mounted) setState(() => _hiddenRecords.remove(row.id));
      },
      commit: () async {
        final res = await _svc.deleteRecord(row.id);
        if (!res.ok && mounted) _toast(context, res.message);
        if (mounted) _loadRecords();
      },
    );
  }

  Future<void> _revokeLink(EmploymentLink link) async {
    if (!await _confirm(
      context,
      title: 'Revoke this link?',
      message: 'Anyone holding it will no longer be able to open the form.',
      confirm: 'Revoke',
    )) {
      return;
    }
    final res = await _svc.revokeLink(link.id);
    if (!mounted) return;
    _toast(context, res.message.isNotEmpty ? res.message : 'Revoked');
    if (res.ok) {
      _loadLinks();
      _loadRecords();
    }
  }

  Future<void> _deleteLink(EmploymentLink link) async {
    if (!await _confirm(
      context,
      title: 'Delete this link?',
      message: 'Submissions already made through it are kept.',
      confirm: 'Delete',
    )) {
      return;
    }
    if (!mounted) return;
    _undoable(
      message: 'Link deleted',
      hide: () => setState(() => _hiddenLinks.add(link.id)),
      unhide: () {
        if (mounted) setState(() => _hiddenLinks.remove(link.id));
      },
      commit: () async {
        final res = await _svc.deleteLink(link.id);
        if (!res.ok && mounted) _toast(context, res.message);
        if (mounted) {
          _loadLinks();
          _loadRecords();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final muted = context.brand.paperDim;
    return StationScaffold(
      stationNumber: 'EI',
      stationLabel: 'EMPLOYMENT INFO',
      title: 'Employment Info',
      showBottomBrand: false,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: zbeTint(
                      context,
                      const Color(0xFFFFF3E6),
                      Brand.signal,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock, size: 10, color: Color(0xFFC25E00)),
                      SizedBox(width: 5),
                      Text(
                        'ADMIN ONLY',
                        style: TextStyle(
                          fontSize: 9.9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.9,
                          color: Color(0xFFC25E00),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    'Share a fill-up link, collect the Basic Employment Information Sheet, then review or print it as a PDF.',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: muted),
                  ),
                ),
                const SizedBox(width: 16),
                _EmpBtn(label: 'Refresh', icon: Icons.sync, onTap: _refreshAll),
                const SizedBox(width: 7),
                _EmpBtn(
                  label: 'Create share link',
                  icon: Icons.link,
                  primary: true,
                  onTap: _openCreateLink,
                ),
              ],
            ),
          ),
          _stats(),
          const SizedBox(height: 9),
          _tabBar(),
          const SizedBox(height: 9),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: context.brand.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: zbeLine(context)),
              ),
              clipBehavior: Clip.antiAlias,
              child: _tab == 0 ? _recordsTable() : _linksTable(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stats() {
    Widget stat(
      int v,
      String label, {
      bool alert = false,
      bool first = false,
    }) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13.6, vertical: 8),
        decoration: BoxDecoration(
          border: first
              ? null
              : Border(left: BorderSide(color: zbeSoftLine(context))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '$v',
              style: TextStyle(
                fontSize: 16.8,
                height: 1.1,
                fontWeight: FontWeight.w800,
                color: alert ? Brand.signal : context.brand.paper,
              ),
            ),
            const SizedBox(width: 6.4),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                  color: context.brand.paperDim,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: context.brand.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: zbeLine(context)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            stat(_summary.total, 'Total sheets', first: true),
            stat(
              _summary.submitted,
              'Awaiting review',
              alert: _summary.submitted > 0,
            ),
            stat(_summary.reviewed, 'Reviewed'),
            stat(_summary.today, 'Submitted today'),
            stat(_summary.activeLinks, 'Active links'),
          ],
        ),
      ),
    );
  }

  Widget _tabBar() {
    Widget tab(int i, String label) {
      final on = _tab == i;
      return _EmpTab(
        label: label,
        on: on,
        onTap: () {
          if (_tab == i) return;
          setState(() => _tab = i);
          if (_tab == 1) _loadLinks();
        },
      );
    }

    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: zbeLine(context)),
    );

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: zbeLine(context))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          tab(0, 'Submissions'),
          const SizedBox(width: 3),
          tab(1, 'Share links'),
          const SizedBox(width: 12),
          if (_tab == 0)
            Expanded(
              child: Align(
                alignment: Alignment.bottomRight,
                child: Padding(
              padding: const EdgeInsets.only(bottom: 5.6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: SizedBox(
                    width: 260,
                    height: 32,
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: _onSearch,
                      expands: true,
                      maxLines: null,
                      textAlignVertical: TextAlignVertical.center,
                      style: const TextStyle(fontSize: 12.8),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: context.brand.surface,
                        hintText: 'Search name, email, job title, ID…',
                        hintStyle: TextStyle(
                          fontSize: 12.8,
                          color: context.brand.paperDim,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 9.6,
                        ),
                        border: border,
                        enabledBorder: border,
                        focusedBorder: border.copyWith(
                          borderSide: const BorderSide(color: Brand.signal),
                        ),
                      ),
                    ),
                  ),
                  ),
                  const SizedBox(width: 6.4),
                  Container(
                    height: 32,
                    constraints: const BoxConstraints(minWidth: 140),
                    padding: const EdgeInsets.only(left: 9.6, right: 4),
                    decoration: BoxDecoration(
                      color: context.brand.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: zbeLine(context)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _status,
                        isDense: true,
                        borderRadius: BorderRadius.circular(8),
                        icon: Icon(
                          Icons.keyboard_arrow_down,
                          size: 16,
                          color: context.brand.paper,
                        ),
                        style: TextStyle(
                          fontSize: 12.8,
                          color: context.brand.paper,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: '',
                            child: Text('All statuses'),
                          ),
                          DropdownMenuItem(
                            value: 'submitted',
                            child: Text('Awaiting review'),
                          ),
                          DropdownMenuItem(
                            value: 'reviewed',
                            child: Text('Reviewed'),
                          ),
                          DropdownMenuItem(
                            value: 'archived',
                            child: Text('Archived'),
                          ),
                        ],
                        onChanged: (v) {
                          setState(() {
                            _status = v ?? '';
                            _page = 1;
                          });
                          _loadRecords();
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
              ),
            ),
        ],
      ),
    );
  }

  static const _tabHeadStyle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.6,
  );

  Widget _thead(List<(String, int?, double?, bool)> cols) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: context.brand.surface,
        border: Border(bottom: BorderSide(color: zbeLine(context))),
      ),
      child: Builder(
        builder: (context) => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: resizableRowCells(context, [
            for (var i = 0; i < cols.length; i++)
              _sized(
                cols[i].$2,
                cols[i].$3,
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(
                        color: i == cols.length - 1
                            ? Colors.transparent
                            : zbeLine(context),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          cols[i].$1.toUpperCase(),
                          overflow: TextOverflow.ellipsis,
                          style: _tabHeadStyle.copyWith(
                            color: context.brand.paperDim,
                          ),
                        ),
                      ),
                      if (cols[i].$4)
                        Icon(
                          Icons.arrow_drop_up,
                          size: 20,
                          color: context.brand.paperDim.withValues(alpha: 0.6),
                        ),
                    ],
                  ),
                ),
              ),
          ], header: true),
        ),
      ),
    );
  }

  Widget _sized(int? flex, double? width, Widget child) {
    if (width != null) return SizedBox(width: width, child: child);
    return Expanded(flex: flex ?? 1, child: child);
  }

  Widget _trow(
    List<(int?, double?, Widget, bool)> cells, {
    VoidCallback? onTap,
    Color? accent,
  }) {
    return _EmpRow(
      onTap: onTap,
      accent: accent,
      children: [
        for (var i = 0; i < cells.length; i++)
          _sized(
            cells[i].$1,
            cells[i].$2,
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              alignment: cells[i].$4 ? Alignment.center : Alignment.centerLeft,
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(
                    color: i == cells.length - 1
                        ? Colors.transparent
                        : zbeLine(context),
                  ),
                ),
              ),
              child: cells[i].$3,
            ),
          ),
      ],
    );
  }

  Widget _empty(String msg) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        msg,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 15, color: context.brand.paperDim),
      ),
    ),
  );

  Widget _recordsTable() {
    final rows = _rows.where((r) => !_hiddenRecords.contains(r.id)).toList();
    Widget body;
    if (_error != null || (_loading && _rows.isEmpty)) {
      body = ZbeStateView(
        loading: _loading && _error == null,
        error: _error,
        onRetry: _loadRecords,
      );
    } else if (rows.isEmpty) {
      body = _empty(
        'No employment information sheets yet. Create a share link and send it to an employee.',
      );
    } else {
      body = ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: rows.length,
        itemBuilder: (_, i) => _recordRow(rows[i]),
      );
    }
    final lastPage = _total == 0 ? 1 : (_total / _pageSize).ceil();
    return ColumnResizeScope(
      tableId: 'employment:records',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _thead(const [
            ('Employee', 2, null, true),
            ('Job', 2, null, true),
            ('Marital status', 1, null, true),
            ('Dependents', 1, null, true),
            ('Status', 1, null, true),
            ('Submitted', 1, null, true),
            ('Actions', null, 110, false),
          ]),
          if (_loading && _rows.isNotEmpty)
            const LinearProgressIndicator(minHeight: 2, color: Brand.signal),
          Expanded(child: body),
          ZbePager(
            page: _page,
            pages: lastPage,
            pageSize: _pageSize,
            onPage: (p) {
              setState(() => _page = p);
              _loadRecords();
            },
            onPageSize: (v) {
              setState(() {
                _pageSize = v;
                _page = 1;
              });
              _loadRecords();
            },
          ),
        ],
      ),
    );
  }

  Widget _recordRow(EmploymentRow r) {
    final dim = TextStyle(fontSize: 12.2, color: context.brand.paperDim);
    const td = TextStyle(fontSize: 15);
    final sub = r.staffName.isNotEmpty
        ? '${r.staffName}${r.staffRole.isNotEmpty ? ' · ${r.staffRole.replaceAll('_', ' ')}' : ''}'
        : (r.staffLinkSkipped
              ? 'Not a staff account'
              : 'Not linked to a staff account');
    final deps = r.dependentCount;
    return _trow(
      [
        (
          2,
          null,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(r.fullName, style: td, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2.4),
              Row(
                children: [
                  if (r.staffName.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 3),
                      child: Icon(
                        Icons.badge,
                        size: 11,
                        color: context.brand.paperDim,
                      ),
                    ),
                  Flexible(
                    child: Text(
                      sub,
                      style: dim,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
          false,
        ),
        (
          2,
          null,
          Tooltip(
            message: r.workLocation.isNotEmpty
                ? '${_has(r.jobTitle) ? r.jobTitle : '—'} · ${r.workLocation}'
                : (_has(r.jobTitle) ? r.jobTitle : '—'),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: _has(r.jobTitle) ? r.jobTitle : '—',
                    style: td,
                  ),
                  if (r.workLocation.isNotEmpty)
                    TextSpan(text: ' · ${r.workLocation}', style: dim),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          false,
        ),
        (
          1,
          null,
          Text(_has(r.maritalStatus) ? r.maritalStatus : '—', style: td),
          false,
        ),
        (
          1,
          null,
          Text(
            deps == 0
                ? 'None'
                : '$deps ${deps == 1 ? 'dependent' : 'dependents'}',
            style: td,
          ),
          true,
        ),
        (1, null, _StatusPill(status: r.status), true),
        (1, null, Text(_fmtDateTime(r.createdAt), style: td), false),
        (
          null,
          110,
          _kebab([
            if (r.status != 'reviewed')
              (
                'review',
                Icons.check_circle,
                'Mark as reviewed',
                () => _markReviewed(r),
                Brand.signal,
              ),
            ('view', Icons.visibility, 'View', () => _openRecord(r.id), null),
            ('edit', Icons.edit, 'Edit', () => _editById(r.id), null),
            (
              'print',
              Icons.picture_as_pdf,
              'Print PDF',
              () => _printRow(r),
              null,
            ),
            (
              'delete',
              Icons.delete,
              'Delete',
              () => _deleteRecord(r),
              const Color(0xFFDC2626),
            ),
          ]),
          true,
        ),
      ],
      onTap: () => _openRecord(r.id),
      accent: r.status == 'submitted' ? Brand.signal : null,
    );
  }

  Widget _kebab(List<(String, IconData, String, VoidCallback, Color?)> items) {
    return PopupMenuButton<String>(
      tooltip: 'Actions',
      position: PopupMenuPosition.under,
      onSelected: (v) {
        for (final it in items) {
          if (it.$1 == v) it.$4();
        }
      },
      itemBuilder: (_) => [
        for (final it in items)
          PopupMenuItem(
            value: it.$1,
            height: 40,
            child: Row(
              children: [
                Icon(it.$2, size: 16, color: it.$5 ?? context.brand.paperDim),
                const SizedBox(width: 10),
                Text(
                  it.$3,
                  style: TextStyle(
                    fontSize: 14,
                    color: it.$5 == const Color(0xFFDC2626) ? it.$5 : null,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.brand.surface,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: zbeLine(context)),
        ),
        child: Icon(Icons.more_vert, size: 16, color: context.brand.paperDim),
      ),
    );
  }

  Widget _smallIconBtn(IconData icon, String tip, VoidCallback onTap) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: context.brand.surface,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: zbeLine(context)),
          ),
          child: Icon(icon, size: 14, color: context.brand.paperDim),
        ),
      ),
    );
  }

  Widget _linksTable() {
    final links = _links.where((l) => !_hiddenLinks.contains(l.id)).toList();
    Widget body;
    if (_linksError != null || (_linksLoading && !_linksLoaded)) {
      body = ZbeStateView(
        loading: _linksLoading && _linksError == null,
        error: _linksError,
        onRetry: _loadLinks,
      );
    } else if (links.isEmpty) {
      body = _empty('No share links yet.');
    } else {
      body = ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: links.length,
        itemBuilder: (_, i) => _linkRow(links[i]),
      );
    }
    return ColumnResizeScope(
      tableId: 'employment:links',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _thead(const [
            ('Label', 2, null, true),
            ('Link', 3, null, false),
            ('Type', 1, null, true),
            ('Expires', 1, null, true),
            ('Status', 1, null, true),
            ('Actions', null, 110, false),
          ]),
          if (_linksLoading && _linksLoaded)
            const LinearProgressIndicator(minHeight: 2, color: Brand.signal),
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _linkRow(EmploymentLink l) {
    final dim = TextStyle(fontSize: 12.2, color: context.brand.paperDim);
    const td = TextStyle(fontSize: 15);
    final meta = [
      if (l.sentTo.isNotEmpty) 'emailed to ${l.sentTo}',
      if (l.note.isNotEmpty) l.note,
    ];
    final usedSingle = !l.isReusable && l.useCount > 0;
    final statusText = l.isActive
        ? 'Active'
        : (l.isRevoked ? 'Revoked' : (usedSingle ? 'Used' : 'Expired'));
    final pill = l.isActive
        ? (const Color(0xFFDCFCE7), const Color(0xFF15803D))
        : (usedSingle
              ? (const Color(0xFFF1F5F9), const Color(0xFF475569))
              : (const Color(0xFFFEE2E2), const Color(0xFFB91C1C)));
    final hideOpen =
        !l.isActive && !l.isReusable && !l.isRevoked && l.useCount > 0;
    return _trow([
      (
        2,
        null,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l.label.isNotEmpty ? l.label : 'Untitled link',
              style: td.copyWith(fontWeight: FontWeight.w700),
            ),
            if (meta.isNotEmpty) Text(meta.join(' · '), style: dim),
          ],
        ),
        false,
      ),
      (
        3,
        null,
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: zbeDark(context)
                ? context.brand.surfaceHi
                : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: zbeLine(context)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l.url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _smallIconBtn(Icons.copy, 'Copy', () => _copy(context, l.url)),
            ],
          ),
        ),
        false,
      ),
      (
        1,
        null,
        l.isReusable
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Shared',
                    style: td.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    l.useCount > 0
                        ? '${l.useCount} ${l.useCount == 1 ? 'sheet filed' : 'sheets filed'}'
                        : 'no sheets yet',
                    style: dim,
                  ),
                ],
              )
            : const Text('Single use', style: td),
        true,
      ),
      (1, null, Text(_fmtDateTime(l.expiresAt), style: td), false),
      (
        1,
        null,
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6.4,
          runSpacing: 4,
          children: [
            ZbeWebChip(statusText, pill.$1, pill.$2, fontSize: 11.2),
            if (l.lastUsedAt.isNotEmpty)
              Text(_fmtDateTime(l.lastUsedAt), style: dim),
          ],
        ),
        true,
      ),
      (
        null,
        110,
        _kebab([
          if (!hideOpen) ...[
            (
              'open',
              Icons.open_in_new,
              'Open form',
              () => launchUrl(Uri.parse(l.url)),
              null,
            ),
            (
              'copy',
              Icons.copy,
              'Copy link',
              () => _copy(context, l.url),
              null,
            ),
          ],
          if (l.isActive)
            ('revoke', Icons.block, 'Revoke', () => _revokeLink(l), null),
          (
            'delete',
            Icons.delete,
            'Delete',
            () => _deleteLink(l),
            const Color(0xFFDC2626),
          ),
        ]),
        true,
      ),
    ]);
  }
}

class _EmpRow extends StatefulWidget {
  const _EmpRow({required this.children, this.onTap, this.accent});
  final List<Widget> children;
  final VoidCallback? onTap;
  final Color? accent;

  @override
  State<_EmpRow> createState() => _EmpRowState();
}

class _EmpRowState extends State<_EmpRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final hoverBg = zbeDark(context)
        ? context.brand.surfaceHi
        : const Color(0xFFF1F7FE);
    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 50),
          decoration: BoxDecoration(
            color: _hover ? hoverBg : context.brand.surface,
            border: Border(
              left: widget.accent == null
                  ? BorderSide.none
                  : BorderSide(color: widget.accent!, width: 3),
              bottom: BorderSide(color: zbeLine(context)),
            ),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: resizableRowCells(context, widget.children),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmpTab extends StatefulWidget {
  const _EmpTab({required this.label, required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  State<_EmpTab> createState() => _EmpTabState();
}

class _EmpTabState extends State<_EmpTab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final lit = widget.on || _hover;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(11, 7, 11, 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: widget.on ? Brand.signal : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 13.1,
              fontWeight: FontWeight.w700,
              color: lit ? context.brand.paper : context.brand.paperDim,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmpBtn extends StatefulWidget {
  const _EmpBtn({
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  @override
  State<_EmpBtn> createState() => _EmpBtnState();
}

class _EmpBtnState extends State<_EmpBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final dark = zbeDark(context);
    final Color bg;
    final Color bd;
    final Color fg;
    if (widget.primary) {
      bg = _hover ? const Color(0xFFE86F00) : Brand.signal;
      bd = bg;
      fg = Colors.white;
    } else {
      bg = _hover
          ? (dark ? context.brand.surfaceHi : const Color(0xFFF8FAFC))
          : context.brand.surface;
      bd = _hover && !dark ? const Color(0xFFCBD5E1) : zbeLine(context);
      fg = context.brand.paper;
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12.8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: bd),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 14, color: fg),
              const SizedBox(width: 6.4),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12.6,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      'submitted' => const ZbeWebChip(
        'Awaiting review',
        Color(0xFFFFF3E6),
        Color(0xFFC25E00),
        icon: Icons.error,
        fontSize: 11.2,
      ),
      'reviewed' => const ZbeWebChip(
        'Reviewed',
        Color(0xFFDCFCE7),
        Color(0xFF15803D),
        icon: Icons.check_circle,
        fontSize: 11.2,
      ),
      'archived' => const ZbeWebChip(
        'Archived',
        Color(0xFFF1F5F9),
        Color(0xFF475569),
        icon: Icons.archive,
        fontSize: 11.2,
      ),
      _ => ZbeWebChip(status, const Color(0xFFF1F5F9), const Color(0xFF475569)),
    };
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Brand.signalGlow(0.08),
        border: Border.all(color: Brand.signal.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: Brand.signal),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

class _ViewItem extends StatelessWidget {
  const _ViewItem(this.label, this.value, {this.noCopy = false});
  final String label;
  final String value;
  final bool noCopy;

  @override
  Widget build(BuildContext context) {
    final has = _has(value);
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.brand.rule)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 170,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              has ? value : '—',
              style: TextStyle(
                fontSize: 14,
                color: has ? context.brand.paper : context.brand.paperDim,
              ),
            ),
          ),
          if (has && !noCopy)
            IconButton(
              tooltip: 'Copy $label',
              visualDensity: VisualDensity.compact,
              iconSize: 14,
              icon: Icon(Icons.copy, color: context.brand.paperDim),
              onPressed: () => _copy(context, value, '$label copied'),
            ),
        ],
      ),
    );
  }
}

Widget _grid(List<Widget> items) {
  final rows = <Widget>[];
  for (var i = 0; i < items.length; i += 2) {
    rows.add(
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: items[i]),
          const SizedBox(width: 24),
          Expanded(
            child: i + 1 < items.length ? items[i + 1] : const SizedBox(),
          ),
        ],
      ),
    );
  }
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
}

Widget _pairs(List<Widget> items, {double gap = 14}) {
  final rows = <Widget>[];
  for (var i = 0; i < items.length; i += 2) {
    if (i > 0) rows.add(SizedBox(height: gap));
    rows.add(
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: items[i]),
          const SizedBox(width: 14),
          Expanded(
            child: i + 1 < items.length ? items[i + 1] : const SizedBox(),
          ),
        ],
      ),
    );
  }
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
}

class _RecordViewDialog extends StatefulWidget {
  const _RecordViewDialog({
    required this.record,
    required this.service,
    required this.onReviewed,
  });
  final EmploymentRecord record;
  final EmploymentService service;
  final VoidCallback onReviewed;

  @override
  State<_RecordViewDialog> createState() => _RecordViewDialogState();
}

class _RecordViewDialogState extends State<_RecordViewDialog>
    with LiveRefresh<_RecordViewDialog> {
  late EmploymentRecord _record = widget.record;
  late String _status = widget.record.status;
  bool _removed = false;
  bool _refreshing = false;

  @override
  List<String> get liveKeys => const ['employment'];

  @override
  void onLiveChange() => _refresh();

  Future<void> _refresh() async {
    if (_refreshing || _removed) return;
    _refreshing = true;
    try {
      final fresh = await widget.service.record(_record.id);
      if (!mounted) return;
      setState(() {
        if (fresh == null) {
          _removed = true;
        } else {
          _record = fresh;
          _status = fresh.status;
        }
      });
    } catch (_) {
    } finally {
      _refreshing = false;
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.record.status == 'submitted') {
      widget.service.setStatus(widget.record.id, 'reviewed').then((res) {
        if (!res.ok) return;
        if (mounted) setState(() => _status = 'reviewed');
        widget.onReviewed();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_removed) {
      return WebModal(
        title: _record.fullName.isEmpty
            ? 'Employment information'
            : _record.fullName,
        subtitle: 'Basic Employment Information Sheet',
        icon: Icons.badge_outlined,
        width: 520,
        actions: [
          GhostButton(label: 'Close', onPressed: () => Navigator.pop(context)),
        ],
        child: const _Notice('This record was removed.'),
      );
    }
    final r = _record;
    final married = r.field('marital_status') == 'Married';
    final contacts = r.contacts;
    final deps = r.dependents;
    final dim = TextStyle(color: context.brand.paperDim, fontSize: 13.5);
    return WebModal(
      title: r.fullName.isEmpty ? 'Employment information' : r.fullName,
      subtitle: 'Basic Employment Information Sheet',
      icon: Icons.badge_outlined,
      width: 1000,
      actions: [
        GhostButton(label: 'Close', onPressed: () => Navigator.pop(context)),
        GhostButton(
          label: 'Edit',
          icon: Icons.edit_outlined,
          onPressed: () => Navigator.pop(context, 'edit'),
        ),
        SignalButton(
          label: 'Print PDF',
          icon: Icons.picture_as_pdf_outlined,
          onPressed: () => Navigator.pop(context, 'print'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ZbeSection(
            number: 1,
            icon: Icons.person_outline,
            title: 'Employee information',
            trailing: _StatusPill(status: _status),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _grid([
                  _ViewItem('Full name', r.field('full_name')),
                  _ViewItem('Address', r.field('address')),
                  _ViewItem('Birth place', r.field('birth_place')),
                  _ViewItem('Cell phone', r.field('cell_phone')),
                  _ViewItem('Email address', r.field('email')),
                  _ViewItem('SSS / Government ID', r.field('government_id')),
                  _ViewItem('Birth date', _fmtDate(r.field('birth_date'))),
                  _ViewItem('Marital status', r.field('marital_status')),
                  if (married) ...[
                    _ViewItem("Spouse's name", r.field('spouse_name')),
                    _ViewItem("Spouse's employer", r.field('spouse_employer')),
                    _ViewItem(
                      "Spouse's work phone",
                      r.field('spouse_work_phone'),
                    ),
                  ],
                ]),
                if (!married) ...[
                  const SizedBox(height: 12),
                  const _Notice(
                    'No legal spouse under the law — spouse fields not applicable.',
                  ),
                ],
              ],
            ),
          ),
          ZbeSection(
            number: 2,
            icon: Icons.work_outline,
            title: 'Job information',
            child: _grid([
              _ViewItem('Title', r.field('job_title')),
              _ViewItem('Supervisor', r.field('supervisor')),
              _ViewItem('Work location', r.field('work_location')),
              _ViewItem('E-mail address', r.field('work_email')),
              _ViewItem('Work phone', r.field('work_phone')),
              _ViewItem('Cell phone', r.field('work_cell_phone')),
              _ViewItem(
                'Start date',
                r.field('start_date').isNotEmpty
                    ? _fmtDate(r.field('start_date'))
                    : '',
              ),
              _ViewItem('Salary', r.field('salary')),
            ]),
          ),
          ZbeSection(
            number: 3,
            icon: Icons.contact_phone_outlined,
            title: 'Emergency contacts',
            child: contacts.isEmpty
                ? Text('None recorded.', style: dim)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < contacts.length; i++) ...[
                        if (i > 0) const SizedBox(height: 16),
                        Text(
                          'Contact ${i + 1}',
                          style: const TextStyle(
                            color: Brand.signal,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        _grid([
                          _ViewItem(
                            'Full name',
                            contacts[i]['full_name'] ?? '',
                          ),
                          _ViewItem('Address', contacts[i]['address'] ?? ''),
                          _ViewItem(
                            'Primary phone',
                            contacts[i]['primary_phone'] ?? '',
                          ),
                          _ViewItem(
                            'Cell phone',
                            contacts[i]['cell_phone'] ?? '',
                          ),
                          _ViewItem(
                            'Relationship',
                            contacts[i]['relationship'] ?? '',
                          ),
                        ]),
                      ],
                    ],
                  ),
          ),
          ZbeSection(
            number: 4,
            icon: Icons.family_restroom,
            title: 'Dependents (insurance purposes only)',
            child: (r.hasNoDependents || deps.isEmpty)
                ? Text('No dependents declared.', style: dim)
                : Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: context.brand.rule),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ColumnResizeScope(
                      tableId: 'employment:dependents',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const WebTableHeader(
                            cells: [
                              ZbeHead('Name of dependent'),
                              ZbeHead('Relationship to employee'),
                            ],
                          ),
                          for (final d in deps)
                            ZbeRow(
                              cells: [
                                Expanded(
                                  child: _copyCell(
                                    'Dependent name',
                                    d['dependent_name'] ?? '',
                                  ),
                                ),
                                Expanded(
                                  child: _copyCell(
                                    'Relationship',
                                    d['relationship'] ?? '',
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
          ),
          ZbeSection(
            number: 5,
            icon: Icons.inbox_outlined,
            title: 'Submission',
            child: _grid([
              _ViewItem('Status', _statusLabel(_status), noCopy: true),
              _ViewItem(
                'Submitted',
                _fmtDateTime(r.field('created_at')),
                noCopy: true,
              ),
              _ViewItem('Share link', r.field('link_label'), noCopy: true),
              _ViewItem('Staff account', r.field('staff_name'), noCopy: true),
              _ViewItem(
                'Last updated by',
                r.field('reviewed_by_name'),
                noCopy: true,
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _copyCell(String label, String value) {
    final has = _has(value);
    return Row(
      children: [
        Flexible(child: SelectableText(has ? value : '—')),
        if (has)
          IconButton(
            tooltip: 'Copy $label',
            visualDensity: VisualDensity.compact,
            iconSize: 14,
            icon: Icon(Icons.copy, color: context.brand.paperDim),
            onPressed: () => _copy(context, value, '$label copied'),
          ),
      ],
    );
  }
}

class _EditRecordDialog extends StatefulWidget {
  const _EditRecordDialog({
    required this.record,
    required this.meta,
    required this.service,
  });
  final EmploymentRecord record;
  final EmploymentMeta meta;
  final EmploymentService service;

  @override
  State<_EditRecordDialog> createState() => _EditRecordDialogState();
}

class _EditRecordDialogState extends State<_EditRecordDialog> {
  static const _fields = [
    'full_name',
    'address',
    'birth_place',
    'cell_phone',
    'email',
    'government_id',
    'birth_date',
    'spouse_name',
    'spouse_employer',
    'spouse_work_phone',
    'job_title',
    'supervisor',
    'work_location',
    'work_email',
    'work_phone',
    'work_cell_phone',
    'start_date',
    'salary',
  ];
  static const _contactFields = [
    ('full_name', 'Full name *', true),
    ('address', 'Address *', true),
    ('primary_phone', 'Primary phone *', false),
    ('cell_phone', 'Cell phone', false),
    ('relationship', 'Relationship *', false),
  ];
  static const _spouseFields = [
    'spouse_name',
    'spouse_employer',
    'spouse_work_phone',
  ];

  final Map<String, TextEditingController> _c = {};
  String _marital = '';
  bool _noDeps = false;
  final List<Map<String, TextEditingController>> _contacts = [];
  final List<(TextEditingController, TextEditingController)> _deps = [];
  Map<String, String> _errors = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.record;
    for (final f in _fields) {
      _c[f] = TextEditingController(text: r.field(f));
    }
    _marital = r.field('marital_status');
    _noDeps = r.hasNoDependents;
    final contacts = r.contacts.toList();
    while (contacts.length < widget.meta.minContacts) {
      contacts.add({});
    }
    for (final c in contacts) {
      _contacts.add(_contactCtrls(c));
    }
    final deps = r.dependents;
    if (deps.isEmpty) {
      _deps.add((TextEditingController(), TextEditingController()));
    } else {
      for (final d in deps) {
        _deps.add((
          TextEditingController(text: d['dependent_name'] ?? ''),
          TextEditingController(text: d['relationship'] ?? ''),
        ));
      }
    }
    if (_spouseless) {
      for (final f in _spouseFields) {
        _c[f]!.clear();
      }
    }
  }

  Map<String, TextEditingController> _contactCtrls(Map<String, String> c) => {
    for (final f in _contactFields)
      f.$1: TextEditingController(text: c[f.$1] ?? ''),
  };

  bool get _spouseless => widget.meta.spouselessStatuses.contains(_marital);

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    for (final m in _contacts) {
      for (final c in m.values) {
        c.dispose();
      }
    }
    for (final d in _deps) {
      d.$1.dispose();
      d.$2.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _errors = {};
      _saving = true;
    });
    final payload = <String, String>{'id': '${widget.record.id}'};
    for (final f in _fields) {
      final disabled = _spouseless && _spouseFields.contains(f);
      payload[f] = disabled ? '' : _c[f]!.text;
    }
    payload['marital_status'] = _marital;
    if (_noDeps) payload['has_no_dependents'] = '1';
    final deps = <Map<String, String>>[];
    for (final d in _deps) {
      final name = d.$1.text.trim();
      if (name.isEmpty) continue;
      deps.add({'dependent_name': name, 'relationship': d.$2.text.trim()});
    }
    payload['dependents'] = jsonEncode(deps);
    payload['emergency_contacts'] = jsonEncode([
      for (final m in _contacts)
        {for (final e in m.entries) e.key: e.value.text.trim()},
    ]);
    final res = await widget.service.updateRecord(payload);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.ok) {
      _toast(context, res.message.isNotEmpty ? res.message : 'Saved');
      Navigator.pop(context, true);
      return;
    }
    setState(() => _errors = res.errors);
    _toast(context, res.message);
  }

  Widget _field(
    String name,
    String label, {
    bool date = false,
    bool enabled = true,
  }) {
    final ctrl = _c[name]!;
    return TextField(
      controller: ctrl,
      enabled: enabled,
      readOnly: date,
      mouseCursor: date && enabled ? SystemMouseCursors.click : null,
      decoration: InputDecoration(
        labelText: label,
        errorText: _errors[name],
        suffixIcon: date
            ? IconButton(
                icon: const Icon(Icons.calendar_today, size: 16),
                onPressed: enabled ? () => _pickDate(ctrl) : null,
              )
            : null,
      ),
      onTap: date && enabled ? () => _pickDate(ctrl) : null,
    );
  }

  Future<void> _pickDate(TextEditingController ctrl) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(ctrl.text) ?? now,
      firstDate: DateTime(1900),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) {
      ctrl.text =
          '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    }
  }

  Widget _errorText(String key) {
    final e = _errors[key];
    if (e == null || e.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        e,
        style: TextStyle(
          color: Theme.of(context).colorScheme.error,
          fontSize: 12,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statuses = widget.meta.maritalStatuses.toList();
    if (_marital.isNotEmpty && !statuses.contains(_marital)) {
      statuses.add(_marital);
    }
    final maxContacts = widget.meta.maxContacts;
    return WebModal(
      title: 'Edit employment information',
      subtitle: widget.record.fullName,
      icon: Icons.edit_outlined,
      width: 1000,
      actions: [
        GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
        SignalButton(
          label: 'Save changes',
          icon: Icons.save_outlined,
          busy: _saving,
          onPressed: _save,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ZbeSection(
            number: 1,
            icon: Icons.person_outline,
            title: 'Employee information',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _field('full_name', 'Full name *'),
                const SizedBox(height: 14),
                _field('address', 'Address *'),
                const SizedBox(height: 14),
                _pairs([
                  _field('birth_place', 'Birth place *'),
                  _field('cell_phone', 'Cell phone *'),
                  _field('email', 'Email address *'),
                  _field('government_id', 'SSS / Government ID *'),
                  _field('birth_date', 'Birth date *', date: true),
                  DropdownButtonFormField<String>(
                    initialValue: _marital,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Marital status *',
                      errorText: _errors['marital_status'],
                    ),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('Select…')),
                      for (final s in statuses)
                        DropdownMenuItem(value: s, child: Text(s)),
                    ],
                    onChanged: (v) => setState(() {
                      _marital = v ?? '';
                      if (_spouseless) {
                        for (final f in _spouseFields) {
                          _c[f]!.clear();
                        }
                      }
                    }),
                  ),
                ]),
                const SizedBox(height: 14),
                if (_spouseless) ...[
                  const _Notice(
                    'You do not have a legal spouse under the law — the spouse fields are not required.',
                  ),
                  const SizedBox(height: 14),
                ],
                _field('spouse_name', "Spouse's name", enabled: !_spouseless),
                const SizedBox(height: 14),
                _pairs([
                  _field(
                    'spouse_employer',
                    "Spouse's employer",
                    enabled: !_spouseless,
                  ),
                  _field(
                    'spouse_work_phone',
                    "Spouse's work phone",
                    enabled: !_spouseless,
                  ),
                ]),
              ],
            ),
          ),
          ZbeSection(
            number: 2,
            icon: Icons.work_outline,
            title: 'Job information',
            child: _pairs([
              _field('job_title', 'Title *'),
              _field('supervisor', 'Supervisor'),
              _field('work_location', 'Work location *'),
              _field('work_email', 'E-mail address *'),
              _field('work_phone', 'Work phone'),
              _field('work_cell_phone', 'Cell phone'),
              _field('start_date', 'Start date', date: true),
              _field('salary', 'Salary'),
            ]),
          ),
          ZbeSection(
            number: 3,
            icon: Icons.contact_phone_outlined,
            title: 'Emergency contacts',
            trailing: GhostButton(
              label: 'Add contact',
              icon: Icons.add,
              onPressed: _contacts.length >= maxContacts
                  ? null
                  : () =>
                        setState(() => _contacts.add(_contactCtrls(const {}))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < _contacts.length; i++) _contactBlock(i),
                _errorText('emergency_contacts'),
              ],
            ),
          ),
          ZbeSection(
            number: 4,
            icon: Icons.family_restroom,
            title: 'Dependents (insurance)',
            trailing: GhostButton(
              label: 'Add dependent',
              icon: Icons.add,
              onPressed: _noDeps
                  ? null
                  : () => setState(
                      () => _deps.add((
                        TextEditingController(),
                        TextEditingController(),
                      )),
                    ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Opacity(
                  opacity: _noDeps ? 0.45 : 1,
                  child: Column(
                    children: [
                      for (var i = 0; i < _deps.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _deps[i].$1,
                                  enabled: !_noDeps,
                                  decoration: const InputDecoration(
                                    labelText: 'Name of dependent',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: TextField(
                                  controller: _deps[i].$2,
                                  enabled: !_noDeps,
                                  decoration: const InputDecoration(
                                    labelText: 'Relationship to employee',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              IconButton(
                                tooltip: 'Remove',
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                  color: Brand.danger,
                                ),
                                onPressed: () => setState(() {
                                  final d = _deps.removeAt(i);
                                  d.$1.dispose();
                                  d.$2.dispose();
                                  if (_deps.isEmpty) {
                                    _deps.add((
                                      TextEditingController(),
                                      TextEditingController(),
                                    ));
                                  }
                                }),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () => setState(() => _noDeps = !_noDeps),
                  borderRadius: BorderRadius.circular(6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        value: _noDeps,
                        onChanged: (v) => setState(() => _noDeps = v ?? false),
                      ),
                      const Text('No dependents to declare'),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
                _errorText('dependents'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _contactBlock(int index) {
    final m = _contacts[index];
    final title = _contacts.length == 1
        ? 'Emergency contact'
        : 'Contact ${index + 1}${index == 0 ? ' — called first' : ''}';
    Widget input((String, String, bool) f) => TextField(
      controller: m[f.$1],
      decoration: InputDecoration(
        labelText: f.$2,
        errorText: _errors['emergency_${index}_${f.$1}'],
      ),
    );
    final wide = _contactFields.where((f) => f.$3).toList();
    final narrow = _contactFields.where((f) => !f.$3).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.brand.surfaceHi,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.brand.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (_contacts.length > widget.meta.minContacts)
                IconButton(
                  tooltip: 'Remove contact',
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: Brand.danger,
                  ),
                  onPressed: () => setState(() {
                    final removed = _contacts.removeAt(index);
                    for (final c in removed.values) {
                      c.dispose();
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _pairs([for (final f in wide) input(f)]),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < narrow.length; i++) ...[
                if (i > 0) const SizedBox(width: 14),
                Expanded(child: input(narrow[i])),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _AuthNameDialog extends StatefulWidget {
  const _AuthNameDialog({required this.initial});
  final String initial;

  @override
  State<_AuthNameDialog> createState() => _AuthNameDialogState();
}

class _AuthNameDialogState extends State<_AuthNameDialog> {
  late final _ctrl = TextEditingController(text: widget.initial);
  bool _remember = true;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() =>
      Navigator.pop(context, (name: _ctrl.text.trim(), remember: _remember));

  @override
  Widget build(BuildContext context) {
    return WebModal(
      title: 'Authorization Name',
      subtitle: 'Printed under Account Information',
      icon: Icons.draw_outlined,
      width: 480,
      actions: [
        GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
        SignalButton(
          label: 'Print',
          icon: Icons.print_outlined,
          onPressed: _submit,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'This name appears under Account Information. Leave it blank to print an empty line.',
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Authorization name',
              hintText: 'Name printed on the sheet',
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _remember,
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Remember this name and stop asking'),
            onChanged: (v) => setState(() => _remember = v ?? false),
          ),
        ],
      ),
    );
  }
}

class _StaffLinkDialog extends StatefulWidget {
  const _StaffLinkDialog({
    required this.service,
    required this.recordId,
    required this.name,
    required this.staff,
  });
  final EmploymentService service;
  final int recordId;
  final String name;
  final List<StaffOption> staff;

  @override
  State<_StaffLinkDialog> createState() => _StaffLinkDialogState();
}

class _StaffLinkDialogState extends State<_StaffLinkDialog> {
  int? _picked;
  bool _busy = false;

  Future<void> _submit(int userId) async {
    setState(() => _busy = true);
    final res = await widget.service.linkStaff(widget.recordId, userId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.ok) {
      _toast(context, res.message);
      return;
    }
    Navigator.pop(context, res);
  }

  String _label(StaffOption u) {
    final suffix = [
      if (u.role.isNotEmpty) u.role,
      if (u.username.isNotEmpty) '@${u.username}',
    ];
    return u.name + (suffix.isNotEmpty ? ' — ${suffix.join(' · ')}' : '');
  }

  @override
  Widget build(BuildContext context) {
    return WebModal(
      title: 'Who is this sheet for?',
      subtitle: widget.name,
      icon: Icons.badge_outlined,
      width: 560,
      actions: [
        GhostButton(
          label: 'Not a staff account',
          onPressed: _busy ? null : () => _submit(0),
        ),
        SignalButton(
          label: 'Link & continue',
          icon: Icons.link,
          busy: _busy,
          onPressed: () {
            if (_picked == null) {
              _toast(
                context,
                'Pick a staff account, or choose "Not a staff account"',
              );
              return;
            }
            _submit(_picked!);
          },
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${widget.name.isNotEmpty ? widget.name : 'This sheet'} is not linked to a staff account yet. Pick who this is, or continue without linking.',
          ),
          const SizedBox(height: 16),
          DropdownMenu<int>(
            expandedInsets: EdgeInsets.zero,
            label: const Text('Staff account'),
            hintText: 'Search staff by name…',
            enableFilter: true,
            requestFocusOnTap: true,
            menuHeight: 320,
            dropdownMenuEntries: [
              for (final u in widget.staff)
                DropdownMenuEntry(value: u.id, label: _label(u)),
            ],
            onSelected: (v) => setState(() => _picked = v),
          ),
          const SizedBox(height: 6),
          Text(
            widget.staff.isEmpty
                ? 'No staff accounts available — continue with "Not a staff account".'
                : 'Start typing to search the staff list.',
            style: TextStyle(fontSize: 12.5, color: context.brand.paperDim),
          ),
        ],
      ),
    );
  }
}

class _CreateLinkDialog extends StatefulWidget {
  const _CreateLinkDialog({
    required this.service,
    required this.meta,
    required this.loadStaff,
    required this.onCreated,
    required this.onEmailed,
  });
  final EmploymentService service;
  final EmploymentMeta meta;
  final Future<List<StaffOption>> Function({bool force}) loadStaff;
  final VoidCallback onCreated;
  final VoidCallback onEmailed;

  @override
  State<_CreateLinkDialog> createState() => _CreateLinkDialogState();
}

class _CreateLinkDialogState extends State<_CreateLinkDialog> {
  static const _other = -1;

  List<StaffOption>? _staff;
  bool _shared = false;
  int? _picked;
  String _preset = '30';
  final _label = TextEditingController();
  final _note = TextEditingController();
  final _days = TextEditingController(text: '30');
  final _email = TextEditingController();
  final _subject = TextEditingController();
  final _message = TextEditingController();
  bool _busy = false;
  int _formKey = 0;

  bool _done = false;
  int _linkId = 0;
  String _url = '';
  String _linkFor = '';
  String _expiry = '';
  String _sendHint = '';
  bool? _sendOk;
  bool _sending = false;
  bool _sent = false;
  bool _compose = false;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _resetCompose();
    _fetchStaff(false);
  }

  Future<void> _fetchStaff(bool force) async {
    final s = await widget.loadStaff(force: force);
    if (mounted) setState(() => _staff = s);
  }

  @override
  void dispose() {
    for (final c in [_label, _note, _days, _email, _subject, _message]) {
      c.dispose();
    }
    super.dispose();
  }

  void _resetCompose() {
    _subject.text = widget.meta.mailSubject;
    _message.text = widget.meta.mailMessage;
  }

  int get _selectedDays {
    if (_preset == 'custom') {
      final n = int.tryParse(_days.text) ?? 30;
      return n.clamp(1, 365);
    }
    return int.tryParse(_preset) ?? 30;
  }

  void _reset() {
    setState(() {
      _shared = false;
      _picked = null;
      _preset = '30';
      _label.clear();
      _note.clear();
      _days.text = '30';
      _email.clear();
      _resetCompose();
      _done = false;
      _sendHint = '';
      _sendOk = null;
      _sent = false;
      _compose = false;
      _copied = false;
      _staff = null;
      _formKey++;
    });
    _fetchStaff(true);
  }

  StaffOption? get _pickedStaff {
    if (_picked == null || _picked == _other) return null;
    for (final u in _staff ?? const <StaffOption>[]) {
      if (u.id == _picked) return u;
    }
    return null;
  }

  String get _userHint {
    if (_picked == _other) {
      return 'Type the name this link is for — it will not be tied to a staff account.';
    }
    final u = _pickedStaff;
    if (u == null) {
      return 'Pick a staff account, or choose "Someone else" to type a name.';
    }
    if (u.openLinks > 0) {
      return 'This person already has an unused link — the new one will work as well.';
    }
    if (u.sheetCount > 0) {
      return 'This person already submitted ${u.sheetCount} ${u.sheetCount == 1 ? 'sheet' : 'sheets'}.';
    }
    return "The link will be labelled with this person's name.";
  }

  bool get _userHintWarn {
    final u = _pickedStaff;
    return u != null && (u.openLinks > 0 || u.sheetCount > 0);
  }

  Future<void> _generate() async {
    if (!_shared) {
      if (_picked == null) {
        _toast(context, 'Pick who this link is for');
        return;
      }
      if (_picked == _other && _label.text.trim().isEmpty) {
        _toast(context, 'Type the name this link is for');
        return;
      }
    }
    setState(() => _busy = true);
    final useLabel = _shared || _picked == _other;
    final res = await widget.service.createLink(
      userId: useLabel ? 0 : _picked!,
      label: useLabel ? _label.text : '',
      note: _note.text,
      days: _selectedDays,
      reusable: _shared,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.ok) {
      _toast(
        context,
        res.message.isNotEmpty ? res.message : 'Could not create the link',
      );
      return;
    }
    final d = res.data;
    final chosen = _shared ? null : _pickedStaff;
    final label = '${d['label'] ?? ''}';
    final exp = _parse('${d['expires_at'] ?? ''}');
    setState(() {
      _done = true;
      _linkId = int.tryParse('${d['id']}') ?? 0;
      _url = '${d['url'] ?? ''}';
      _email.text = chosen?.email ?? '';
      _sendOk = null;
      _sendHint = _shared
          ? 'Send it to whoever should pass it around.'
          : (chosen != null && chosen.email.isNotEmpty
                ? 'Taken from their staff account — change it if needed.'
                : 'No email on file, type where it should go.');
      _linkFor = _shared
          ? 'everyone you share it with'
          : (label.isNotEmpty ? label : 'this employee');
      _expiry =
          (_shared
              ? 'Unlimited submissions · expires '
              : 'Single use · expires ') +
          (exp != null ? _fmtLongDate(exp) : '${d['expires_at'] ?? ''}');
    });
    _toast(
      context,
      _shared
          ? 'Shared link created — anyone with it can file a sheet'
          : 'Share link created for ${label.isNotEmpty ? label : 'the employee'}',
    );
    widget.onCreated();
  }

  Future<void> _send() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() {
        _sendOk = false;
        _sendHint = 'Enter an email address first.';
      });
      return;
    }
    setState(() => _sending = true);
    final res = await widget.service.emailLink(
      id: _linkId,
      email: email,
      subject: _subject.text,
      message: _message.text,
    );
    if (!mounted) return;
    setState(() {
      _sending = false;
      _sendOk = res.ok;
      _sent = res.ok;
      _sendHint = res.ok
          ? res.message
          : (res.message.isNotEmpty
                ? res.message
                : 'Could not send the email.');
    });
    if (res.ok) {
      _toast(context, res.message);
      widget.onEmailed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sub = _shared
        ? 'One link for a whole batch — every person who opens it files their own sheet.'
        : 'Send it to one person. It closes the moment they submit.';
    return WebModal(
      title: 'Create a fill-up link',
      subtitle: sub,
      icon: Icons.link,
      width: 620,
      actions: _done
          ? [
              SignalButton(
                label: 'Done',
                onPressed: () => Navigator.pop(context),
              ),
            ]
          : [
              GhostButton(
                label: 'Cancel',
                onPressed: () => Navigator.pop(context),
              ),
              SignalButton(
                label: _busy ? 'Generating…' : 'Generate link',
                icon: Icons.link,
                busy: _busy,
                onPressed: _generate,
              ),
            ],
      child: _done ? _doneStep() : _formStep(),
    );
  }

  Widget _hint(String text, {bool warn = false, bool? ok}) {
    final color = ok == true
        ? const Color(0xFF16A34A)
        : (ok == false || warn ? Brand.signal : context.brand.paperDim);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(text, style: TextStyle(fontSize: 12, color: color)),
    );
  }

  Widget _formStep() {
    final closes = DateTime.now().add(Duration(days: _selectedDays));
    final staff = _staff;
    return Column(
      key: ValueKey(_formKey),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Who can use this link?',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        ZbeSegmented<bool>(
          value: _shared,
          options: const [(false, 'One person'), (true, 'Many people')],
          onChanged: (v) => setState(() {
            _shared = v;
            _label.clear();
          }),
        ),
        _hint(
          _shared
              ? 'The link stays open until it expires or you revoke it — as many people as you like can fill it in.'
              : 'One link, one sheet — it closes the moment they submit.',
        ),
        const SizedBox(height: 18),
        if (!_shared) ...[
          if (staff == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Loading staff…'),
            )
          else
            DropdownMenu<int>(
              expandedInsets: EdgeInsets.zero,
              label: const Text('Who is this for?'),
              hintText: 'Select a staff account…',
              enableFilter: true,
              requestFocusOnTap: true,
              menuHeight: 320,
              dropdownMenuEntries: [
                for (final u in staff)
                  DropdownMenuEntry(
                    value: u.id,
                    label:
                        u.name +
                        (() {
                          final s = [
                            if (u.role.isNotEmpty) u.role,
                            if (u.sheetCount > 0)
                              '${u.sheetCount} ${u.sheetCount == 1 ? 'sheet' : 'sheets'}',
                            if (u.openLinks > 0) 'link active',
                          ];
                          return s.isEmpty ? '' : ' — ${s.join(' · ')}';
                        })(),
                  ),
                const DropdownMenuEntry(
                  value: _other,
                  label: 'Someone else — type a name',
                ),
              ],
              onSelected: (v) => setState(() {
                _picked = v;
                if (v != _other) _label.clear();
              }),
            ),
          _hint(_userHint, warn: _userHintWarn),
          const SizedBox(height: 14),
        ],
        if (_shared || _picked == _other) ...[
          TextField(
            controller: _label,
            decoration: InputDecoration(
              labelText: _shared
                  ? 'Name this link (optional)'
                  : 'Name on the link',
              hintText: _shared
                  ? 'e.g. New hires — Batch 1'
                  : 'e.g. Juan Dela Cruz — new hire',
            ),
          ),
          if (_shared)
            _hint(
              'Only for your own list of links — everyone fills in their own name on the form.',
            ),
          const SizedBox(height: 14),
        ],
        const Text(
          'Link expires after',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in const [
              ('7', '7 days'),
              ('15', '15 days'),
              ('30', '30 days'),
              ('60', '60 days'),
              ('custom', 'Custom'),
            ])
              ZbeToggle(
                label: p.$2,
                selected: _preset == p.$1,
                onTap: () => setState(() => _preset = p.$1),
              ),
          ],
        ),
        if (_preset == 'custom') ...[
          const SizedBox(height: 10),
          SizedBox(
            width: 180,
            child: TextField(
              controller: _days,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Number of days'),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
        _hint(
          'If nobody fills it in, the link stops working on ${_fmtLongDate(closes)}.',
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _note,
          decoration: const InputDecoration(
            labelText: 'Internal note (optional)',
            hintText: 'Only visible to admins',
          ),
        ),
      ],
    );
  }

  Widget _doneStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Column(
            children: [
              const IconTile(
                icon: Icons.check_circle,
                size: 52,
                color: Color(0xFF16A34A),
              ),
              const SizedBox(height: 8),
              Text(
                'Link ready for $_linkFor',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                _expiry,
                style: TextStyle(fontSize: 13, color: context.brand.paperDim),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Share this link',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Container(
                height: 40,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: context.brand.surfaceHi,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Brand.inputBorder),
                ),
                child: SelectableText(
                  _url,
                  maxLines: 1,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GhostButton(
              onPressed: () async {
                await _copy(context, _url);
                if (!mounted) return;
                setState(() => _copied = true);
                Future.delayed(const Duration(seconds: 2), () {
                  if (mounted) setState(() => _copied = false);
                });
              },
              icon: _copied ? Icons.check : Icons.copy,
              label: _copied ? 'Copied' : 'Copy',
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: Divider(color: context.brand.rule)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'or send it for them',
                style: TextStyle(fontSize: 12, color: context.brand.paperDim),
              ),
            ),
            Expanded(child: Divider(color: context.brand.rule)),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Email it to',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(hintText: 'name@example.com'),
                onChanged: (_) => setState(() {
                  _sent = false;
                  _sendOk = null;
                }),
              ),
            ),
            const SizedBox(width: 8),
            SignalButton(
              onPressed: _send,
              busy: _sending,
              icon: _sent ? Icons.check : Icons.send,
              label: _sending ? 'Sending…' : (_sent ? 'Sent' : 'Send'),
            ),
          ],
        ),
        if (_sendHint.isNotEmpty) _hint(_sendHint, ok: _sendOk),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => setState(() => _compose = !_compose),
          icon: const Icon(Icons.edit, size: 16),
          label: Text(_compose ? 'Hide message' : 'Compose message'),
        ),
        if (_compose) ...[
          const SizedBox(height: 6),
          TextField(
            controller: _subject,
            maxLength: 190,
            decoration: const InputDecoration(labelText: 'Subject'),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _message,
            maxLength: 2000,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Message'),
          ),
          _hint(
            'The link, expiry date and your name are added automatically below your message.',
          ),
          TextButton(
            onPressed: () {
              setState(_resetCompose);
              _toast(context, 'Subject and message reset to the default');
            },
            child: const Text('Reset to default'),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            GhostButton(
              onPressed: () => launchUrl(Uri.parse(_url)),
              icon: Icons.open_in_new,
              label: 'Preview form',
            ),
            const SizedBox(width: 8),
            GhostButton(
              onPressed: _reset,
              icon: Icons.add,
              label: 'Create another',
            ),
          ],
        ),
      ],
    );
  }
}
