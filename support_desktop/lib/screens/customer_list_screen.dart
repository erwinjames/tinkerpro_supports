import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../services/bir_data_service.dart';
import '../services/bir_register_service.dart';
import '../services/live_sync.dart';
import '../services/notification_center.dart';
import '../services/services.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'bir_misc_actions.dart';
import 'bir_pdf_upload_screen.dart';
import 'bir_ptu_upload_screen.dart';
import 'bir_step2_form_screen.dart';
import 'bir_notes_dialog.dart';
import 'bir_print_dialog.dart';
import 'bir_register_review_dialog.dart';
import 'bir_register_upload_dialog.dart';
import 'bir_table.dart';
import 'bir_tool_dialogs.dart';
import 'bir_v1_pane.dart';
import 'bir_widgets.dart';
import 'customer_detail_screen.dart';
import 'invoice_lookup_dialog.dart';

class CustomerListScreen extends StatefulWidget {
  const CustomerListScreen({
    super.key,
    required this.service,
    required this.notifications,
  });
  final CustomerService service;
  final NotificationCenter notifications;

  @override
  State<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _MenuAction {
  const _MenuAction(
    this.key,
    this.label,
    this.icon, {
    this.fill,
    this.fg,
    this.disabled = false,
    this.danger = false,
    this.children,
  });
  final String key;
  final String label;
  final IconData icon;
  final Color? fill;
  final Color? fg;
  final bool disabled;
  final bool danger;
  final List<_MenuAction>? children;
}

class _CustomerListScreenState extends State<CustomerListScreen>
    with LiveRefresh<CustomerListScreen> {
  static const _pageSizes = <int>[15, 20, 25, 30];
  static const _months = [
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

  late final BirDataService _bir = BirDataService(widget.service.api);
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  int _pageSize = 30;
  int _page = 1;
  int _lastPage = 1;
  int _reqSeq = 0;
  bool _v1 = false;
  int? _v1Total;
  bool _v1Failed = false;
  BirPageMeta _meta = const BirPageMeta();

  @override
  void initState() {
    super.initState();
    _load();
    _bir.meta().then((m) {
      if (mounted) setState(() => _meta = m);
    });
    _bir.v1Total().then((t) {
      if (mounted) {
        setState(() {
          _v1Total = t;
          _v1Failed = t == null;
        });
      }
    });
  }

  @override
  List<String> get liveKeys => const ['customer'];

  @override
  void onLiveChange() {
    if (!_v1) _load(silent: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final seq = ++_reqSeq;
    if (!silent) setState(() => _loading = true);
    try {
      final p = await _bir.customers(
        page: _page,
        limit: _pageSize,
        search: _searchController.text,
      );
      if (!mounted || seq != _reqSeq) return;
      setState(() {
        _rows = p.rows;
        _lastPage = p.lastPage;
        if (_page > _lastPage) _page = _lastPage;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || seq != _reqSeq) return;
      setState(() => _loading = false);
    }
    widget.notifications.refresh();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _page = 1;
      _load();
    });
  }

  String _s(Map<String, dynamic> r, String k) => (r[k] ?? '').toString().trim();
  int _n(Map<String, dynamic> r, String k) => int.tryParse(_s(r, k)) ?? 0;

  CustomerBrief _brief(Map<String, dynamic> r) => CustomerBrief.fromJson(r);

  void _ack(Map<String, dynamic> r) {
    if (_n(r, 'vendor_id') > 0 && _s(r, 'vendor_seen_at').isEmpty) {
      r['vendor_seen_at'] = DateTime.now().toIso8601String();
      setState(() {});
      widget.service.api
          .post('vendorAckRegistration', body: {'id': _s(r, 'id')})
          .catchError((_) => <String, dynamic>{});
    }
  }

  Future<void> _openCreate() async {
    final invoice = await InvoiceLookupDialog.show(context, widget.service);
    if (invoice == null || !mounted) return;
    final up = await BirRegisterUploadDialog.show(
      context,
      api: widget.service.api,
    );
    if (up == null || !mounted) return;
    if (up.birRegistrationPdf) {
      await _openBirRegistrationPdf(invoiceNumber: invoice);
      return;
    }
    final saved = await BirRegisterReviewDialog.show(
      context,
      api: widget.service.api,
      data: up.prefill!,
      mode: BirReviewMode.add,
      invoiceNumber: invoice,
    );
    if (saved == true) _load();
  }

  Future<void> _openBirRegistrationPdf({
    String invoiceNumber = '',
    Map<String, dynamic>? pendingCustomer,
  }) async {
    final saved = await BirPdfUploadScreen.show(
      context,
      api: widget.service.api,
      customerId: pendingCustomer == null
          ? null
          : int.tryParse('${pendingCustomer['id']}'),
      invoiceNumber: invoiceNumber,
      pendingRegistration: pendingCustomer != null,
      originalStep2: int.tryParse('${pendingCustomer?['step2'] ?? 0}') == 1
          ? 1
          : 0,
    );
    if (saved == true) _load();
  }

  Future<void> _continueRegistration(Map<String, dynamic> r) async {
    final svc = BirRegisterService(widget.service.api);
    final id = _n(r, 'id');
    final customer = await svc.customer(id);
    if (!mounted) return;
    if (customer == null) {
      _snack('Failed to load customer details.');
      return;
    }
    final fromClient = _s(r, 'registration_source').toLowerCase() == 'client';
    if (fromClient) {
      final up = await BirRegisterUploadDialog.show(
        context,
        api: widget.service.api,
        customerId: id,
      );
      if (up == null || !mounted) return;
      if (up.birRegistrationPdf) {
        await _openBirRegistrationPdf(
          invoiceNumber: (customer['invoice_number'] ?? '').toString(),
          pendingCustomer: customer,
        );
        return;
      }
      final saved = await BirRegisterReviewDialog.show(
        context,
        api: widget.service.api,
        data: up.prefill!,
        mode: BirReviewMode.continueUpload,
        customerId: id,
        invoiceNumber: (customer['invoice_number'] ?? '').toString(),
      );
      if (saved == true) _load();
      return;
    }
    Map<String, dynamic> ctx;
    try {
      ctx = await svc.completeContext(id);
    } on BirRegisterException catch (e) {
      _snack(e.message);
      return;
    }
    if (!mounted) return;
    final saved = await BirRegisterReviewDialog.show(
      context,
      api: widget.service.api,
      data: ctx,
      mode: BirReviewMode.complete,
      customerId: id,
      onViewDetails: () => _openDetail(r),
    );
    if (saved == true) _load();
  }

  Future<void> _openDetail(Map<String, dynamic> r) async {
    _ack(r);
    final action = await CustomerDetailScreen.show(
      context,
      service: widget.service,
      brief: _brief(r),
    );
    if (!mounted || action == null) return;
    _load();
    if (action.isNotEmpty) await _runAction(action, r);
  }

  Future<void> _edit(Map<String, dynamic> r) async {
    final saved = await BirStep2FormScreen.showEdit(
      context,
      api: widget.service.api,
      customerId: _n(r, 'id'),
    );
    if (saved == true) _load();
  }

  Future<void> _uploadPdf(Map<String, dynamic> r) async {
    final saved = await BirPdfUploadScreen.show(
      context,
      api: widget.service.api,
      customerId: _n(r, 'id'),
    );
    if (saved == true) _load();
  }

  Future<void> _uploadPtu(Map<String, dynamic> r) async {
    final saved = await BirPtuUploadScreen.show(
      context,
      api: widget.service.api,
      customerId: _n(r, 'id'),
      serialNumber: _s(r, 'serial_number'),
    );
    if (saved == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> r) async {
    await BirMiscActions.delete(
      context,
      widget.service.api,
      r,
      onHide: () {
        if (mounted) {
          setState(
            () => _rows = _rows.where((e) => !identical(e, r)).toList(),
          );
        }
      },
      onRestore: () {
        if (mounted) _load(silent: true);
      },
      onCommitted: () {
        if (mounted) _load(silent: true);
      },
    );
  }

  Future<void> _openTaxpayerPortal(Map<String, dynamic> r) async {
    final ok = await launchUrl(
      Uri.parse(
        widget.service.api.actionUrl('staffOpenTaxpayerPortal', {
          'id': _s(r, 'id'),
        }),
      ),
      mode: LaunchMode.externalApplication,
    );
    if (!ok) _snack('Could not open the taxpayer portal.');
  }

  Future<void> _notes(Map<String, dynamic> r) async {
    final saved = await BirNotesDialog.show(
      context,
      bir: _bir,
      customerId: _n(r, 'id'),
      rawNotes: _s(r, 'action_notes'),
      author: _meta.noteAdminUsername,
    );
    if (saved != null && mounted) {
      setState(() => r['action_notes'] = saved);
      _snack('Action notes saved.');
    }
  }

  Future<void> _print(Map<String, dynamic> r) async {
    final full = await _bir.customer(_n(r, 'id'));
    if (!mounted) return;
    await BirPrintDialog.show(
      context,
      bir: _bir,
      customer: full ?? r,
      printOnly: true,
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  List<_MenuAction> _actions(Map<String, dynamic> r) {
    final out = <_MenuAction>[];
    final step2 = _n(r, 'step2') == 1;
    final finalDone = _n(r, 'final_step') == 1;
    final cStatus = _n(r, 'c_status') == 1;
    final hasPdf = _s(r, 'pdf_file').isNotEmpty;
    final hasCsv =
        _s(r, 'csv_file_data').isNotEmpty || _s(r, 'csv_file').isNotEmpty;
    const warn = Color(0xFFFFC107);
    if (step2 && !finalDone) {
      out.add(
        const _MenuAction(
          'ptu',
          'Upload PTU Document',
          Icons.description,
          fill: warn,
          fg: Colors.black,
        ),
      );
    }
    if (cStatus && !step2) {
      out.add(
        _MenuAction(
          'pdf',
          hasPdf ? 'Re-upload BIR Registration PDF' : 'Upload Registration PDF',
          Icons.upload_file,
          fill: const Color(0xFF007BFF),
          fg: Colors.white,
        ),
      );
    }
    if (finalDone) {
      out.add(
        const _MenuAction(
          'done',
          'Completed',
          Icons.check_circle,
          fill: Color(0xFF28A745),
          fg: Colors.white,
          disabled: true,
        ),
      );
    }
    const note = _MenuAction('note', 'Note', Icons.sticky_note_2);
    const del = _MenuAction('delete', 'Delete', Icons.delete, danger: true);
    const csv = _MenuAction('csv', 'Download CSV', Icons.description_outlined);
    const xlsx = _MenuAction(
      'xlsx',
      'Download as Excel (.xlsx)',
      Icons.grid_on,
    );
    const docs = _MenuAction('docs', 'Download Doc', Icons.folder_zip_outlined);
    if (cStatus || finalDone) {
      out.addAll([
        const _MenuAction('view', 'View', Icons.visibility),
        const _MenuAction('edit', 'Edit', Icons.edit_note),
        const _MenuAction('print', 'Print', Icons.print),
        _MenuAction(
          'download',
          'Download',
          Icons.download,
          children: [
            if (hasCsv) ...[csv, xlsx],
            docs,
          ],
        ),
        note,
        del,
      ]);
    } else {
      out.addAll([
        const _MenuAction(
          'continue',
          'Continue Registration',
          Icons.memory,
          fill: warn,
          fg: Colors.black,
        ),
        const _MenuAction('view', 'View', Icons.visibility),
        _MenuAction(
          'download',
          'Download',
          Icons.download,
          children: [
            _MenuAction(
              'csv',
              'Download CSV',
              Icons.description_outlined,
              disabled: !hasCsv,
            ),
            _MenuAction(
              'xlsx',
              'Download as Excel (.xlsx)',
              Icons.grid_on,
              disabled: !hasCsv,
            ),
            docs,
          ],
        ),
        note,
        const _MenuAction('apitoken', 'POS API Token', Icons.key),
        del,
      ]);
    }
    if (_meta.canViewTaxpayerPortal) {
      out.add(
        const _MenuAction(
          'taxpayer',
          'Open Taxpayer Portal',
          Icons.admin_panel_settings,
        ),
      );
    }
    return out;
  }

  Future<void> _runAction(String key, Map<String, dynamic> r) async {
    _ack(r);
    switch (key) {
      case 'view':
        await _openDetail(r);
      case 'continue':
        await _continueRegistration(r);
      case 'edit':
        await _edit(r);
      case 'ptu':
        await _uploadPtu(r);
      case 'pdf':
        await _uploadPdf(r);
      case 'print':
        await _print(r);
      case 'csv':
        await BirMiscActions.downloadCsv(context, widget.service.api, r);
      case 'xlsx':
        await BirMiscActions.downloadXlsx(context, widget.service.api, r);
      case 'docs':
        await BirMiscActions.downloadDocs(context, widget.service.api, r);
      case 'apitoken':
        await BirMiscActions.apiToken(context, widget.service.api, r);
      case 'taxpayer':
        await _openTaxpayerPortal(r);
      case 'note':
        await _notes(r);
      case 'delete':
        await _delete(r);
    }
  }

  PopupMenuEntry<String> _menuItem(_MenuAction a, {bool nested = false}) {
    final fg = a.danger
        ? const Color(0xFFDC3545)
        : (a.fg ?? const Color(0xFF212529));
    return PopupMenuItem<String>(
      value: a.key,
      enabled: !a.disabled || a.fill != null,
      height: 44,
      padding: EdgeInsets.symmetric(horizontal: nested ? 8 : 6),
      child: Container(
        width: double.infinity,
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color:
              a.fill?.withValues(alpha: a.disabled ? 0.75 : 1) ??
              (a.danger ? const Color(0xFFFFF1F2) : null),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              a.icon,
              size: 18,
              color: a.disabled && a.fill == null
                  ? const Color(0xFFADB5BD)
                  : fg,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                a.label,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: a.disabled && a.fill == null
                      ? const Color(0xFFADB5BD)
                      : fg,
                ),
              ),
            ),
            if (a.children != null)
              const Icon(Icons.arrow_right, size: 20, color: Colors.black),
          ],
        ),
      ),
    );
  }

  Future<void> _openMenu(BuildContext btnCtx, Map<String, dynamic> r) async {
    final box = btnCtx.findRenderObject() as RenderBox;
    final overlay = Overlay.of(btnCtx).context.findRenderObject() as RenderBox;
    final rect = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset(0, box.size.height), ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    final actions = _actions(r);
    final picked = await showMenu<String>(
      context: context,
      position: rect,
      color: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 8,
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [for (final a in actions) _menuItem(a)],
    );
    if (picked == null || !mounted) return;
    final parent = actions.where((a) => a.key == picked).firstOrNull;
    if (parent?.children != null) {
      final sub = await showMenu<String>(
        context: context,
        position: rect,
        color: Colors.white,
        surfaceTintColor: Colors.white,
        constraints: const BoxConstraints(minWidth: 240, maxWidth: 300),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        items: [for (final c in parent!.children!) _menuItem(c, nested: true)],
      );
      if (sub != null && mounted) await _runAction(sub, r);
      return;
    }
    await _runAction(picked, r);
  }

  String _branch(Map<String, dynamic> r) {
    final tin = _s(r, 'tin');
    final digits = tin.replaceAll(RegExp(r'[^0-9]'), '');
    if (_n(r, 'c_status') == 1 && digits.length > 9) {
      return tin.substring(tin.length - 3);
    }
    return _s(r, 'branch_code');
  }

  Widget _muted(String t) =>
      Text(t, style: const TextStyle(fontSize: 12, color: Color(0xFF6C757D)));

  Widget _notesCell(Map<String, dynamic> r) {
    final raw = _s(r, 'action_notes');
    final empty = _muted('No notes...');
    if (raw.isEmpty) return empty;
    String last;
    int count;
    try {
      final j = jsonDecode(raw);
      final lines = (j is Map ? (j['text'] ?? '').toString() : '')
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();
      if (lines.isEmpty) return empty;
      last = lines.last
          .replaceAll(RegExp(r' · by ([^·\n]+)$'), '')
          .replaceFirst(RegExp(r'^\s*[✅\-]\s+'), '')
          .trim();
      count = lines.length;
    } catch (_) {
      last = raw;
      count = 0;
    }
    return Row(
      children: [
        const Icon(Icons.sticky_note_2, size: 15, color: Brand.signal),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            last,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
          ),
        ),
        if (count > 0)
          Container(
            margin: const EdgeInsets.only(left: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFFFED7AA)),
            ),
            child: Text(
              '$count ${count > 1 ? 'notes' : 'note'}',
              style: const TextStyle(
                fontSize: 10.2,
                fontWeight: FontWeight.w700,
                color: Color(0xFF9A3412),
              ),
            ),
          ),
      ],
    );
  }

  Widget _dateCell(Map<String, dynamic> r) {
    final v = _s(r, 'created_at');
    if (v.isEmpty) return _muted('—');
    final d = DateTime.tryParse(v.replaceFirst(' ', 'T'));
    if (d == null) return Text(v);
    var h = d.hour % 12;
    if (h == 0) h = 12;
    final time =
        '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '${_months[d.month - 1]} ${d.day}, ${d.year}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextSpan(
            text: ' $time',
            style: const TextStyle(fontSize: 12, color: Color(0xFF6C757D)),
          ),
        ],
      ),
    );
  }

  Widget _statusCell(Map<String, dynamic> r) {
    final cStatus = _n(r, 'c_status') == 1;
    final step2 = _n(r, 'step2') == 1;
    final finalDone = _n(r, 'final_step') == 1;
    Widget badge;
    if (finalDone) {
      badge = const BirBadge(label: 'Completed', bg: Color(0xFF28A745));
    } else if (cStatus && step2) {
      badge = const BirBadge(
        label: 'Upload PTU',
        bg: Color(0xFFFFC107),
        fg: Color(0xFF212529),
      );
    } else if (!cStatus && !step2) {
      badge = const BirBadge(label: 'Continue Registration', bg: Colors.red);
    } else {
      badge = const BirBadge(
        label: 'Pending Registration',
        bg: Color(0xFF6C757D),
      );
    }
    final client = _s(r, 'registration_source').toLowerCase() == 'client';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: badge),
        if (client) ...[
          const SizedBox(width: 4),
          const BirBadge(label: 'Client', bg: Brand.navy, fontSize: 12),
        ],
      ],
    );
  }

  List<BirColumn> get _columns => [
    BirColumn(
      title: 'No.',
      width: 47,
      cell: (r, i) => Text('${(_page - 1) * _pageSize + i + 1}'),
    ),
    BirColumn(
      title: 'Company Name',
      width: 166,
      sortKey: (r) => _s(r, 'company_name'),
      cell: (r, _) => Text(_s(r, 'company_name')),
    ),
    BirColumn(
      title: 'Invoice',
      width: 116,
      center: true,
      sortKey: (r) => _s(r, 'invoice_number'),
      cell: (r, _) {
        final v = _s(r, 'invoice_number');
        if (v.isEmpty) return _muted('—');
        if (_n(r, 'invoice_has_client') != 1) return Text(v);
        return Text(
          v,
          style: const TextStyle(
            color: Brand.signal,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
            decorationColor: Brand.signal,
          ),
        );
      },
    ),
    BirColumn(
      title: 'Branch Code',
      width: 143,
      center: true,
      sortKey: _branch,
      cell: (r, _) => Text(_branch(r)),
    ),
    BirColumn(
      title: 'TIN',
      width: 144,
      sortKey: (r) => _s(r, 'tin'),
      cell: (r, _) => Text(_s(r, 'tin')),
    ),
    BirColumn(
      title: 'Address',
      width: 255,
      sortKey: (r) => _s(r, 'address'),
      cell: (r, _) => Tooltip(
        message: _s(r, 'address'),
        waitDuration: const Duration(milliseconds: 500),
        child: Text(_s(r, 'address'), overflow: TextOverflow.ellipsis),
      ),
    ),
    BirColumn(
      title: 'Owner Name',
      width: 138,
      sortKey: _owner,
      cell: (r, _) => Text(_owner(r)),
    ),
    BirColumn(
      title: 'Vendor',
      width: 146,
      sortKey: (r) => _s(r, 'vendor_code'),
      cell: (r, _) {
        final code = _s(r, 'vendor_code');
        if (code.isEmpty) return _muted('Direct');
        final company = _s(r, 'vendor_company');
        return Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: code,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Brand.navy,
                ),
              ),
              if (company.isNotEmpty)
                TextSpan(
                  text: ' $company',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6C757D),
                  ),
                ),
            ],
          ),
          overflow: TextOverflow.ellipsis,
        );
      },
    ),
    BirColumn(
      title: 'Software',
      width: 192,
      sortKey: (r) => _s(r, 'softwarename'),
      cell: (r, _) => Text(_s(r, 'softwarename')),
    ),
    BirColumn(
      title: 'Notes',
      width: 240,
      sortKey: (r) => _s(r, 'action_notes'),
      cell: (r, _) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _notes(r),
          child: _notesCell(r),
        ),
      ),
    ),
    BirColumn(
      title: 'Date Created',
      width: 150,
      center: true,
      sortKey: (r) => _s(r, 'created_at'),
      cell: (r, _) => _dateCell(r),
    ),
  ];

  String _owner(Map<String, dynamic> r) => [
    _s(r, 'first_name'),
    _s(r, 'middle_name'),
    _s(r, 'last_name'),
  ].where((e) => e.isNotEmpty).join(' ');

  List<BirColumn> get _frozen => [
    BirColumn(
      title: 'Status',
      width: 206,
      sortKey: (r) =>
          '${_n(r, 'final_step')}${_n(r, 'c_status')}${_n(r, 'step2')}',
      cell: (r, _) => _statusCell(r),
    ),
    BirColumn(
      title: 'Action',
      width: 110,
      center: true,
      cell: (r, _) => Builder(
        builder: (btnCtx) => SizedBox(
          width: 34,
          height: 31,
          child: OutlinedButton(
            onPressed: () => _openMenu(btnCtx, r),
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
              foregroundColor: const Color(0xFF6C757D),
              side: const BorderSide(color: Color(0xFF6C757D)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            child: const Icon(Icons.arrow_drop_down, size: 20),
          ),
        ),
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return StationScaffold(
      stationNumber: '04',
      stationLabel: 'BIR REGISTRATION',
      title: 'BIR Registration',
      showBottomBrand: false,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _topBar(),
          const SizedBox(height: 18),
          Expanded(
            child: _v1
                ? BirV1Pane(
                    bir: _bir,
                    onTotal: (t) {
                      if (mounted) {
                        setState(() {
                          _v1Total = t;
                          _v1Failed = t == null;
                        });
                      }
                    },
                  )
                : _v2Card(),
          ),
        ],
      ),
    );
  }

  Widget _topBar() {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 10,
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F3F6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E6EB)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _tab('Version 2', !_v1, () {
                if (!_v1) return;
                setState(() => _v1 = false);
                _load(silent: true);
              }),
              const SizedBox(width: 4),
              _tab(
                'Version 1',
                _v1,
                () => setState(() => _v1 = true),
                count: _v1Failed ? '!' : (_v1Total == null ? '–' : '$_v1Total'),
              ),
            ],
          ),
        ),
        if (!_v1)
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
          BirSolidButton(
            label: 'Add Customer',
            height: 38,
            fontSize: 16,
            fontWeight: FontWeight.w500,
            onPressed: _openCreate,
          ),
          if (_meta.isSuperAdmin) ...[
            BirOutlineButton(
              label: 'Configure Fields',
              icon: Icons.view_list,
              trailing: const Icon(Icons.arrow_drop_down, size: 18),
              onPressed: () => BirFieldConfigDialog.show(context, _bir),
            ),
            BirOutlineButton(
              label: 'Software Accreditation',
              icon: Icons.verified,
              onPressed: () => BirSoftwareDialog.show(context, _bir),
            ),
          ],
          BirOutlineButton(
            label: 'Client Register QR',
            icon: Icons.qr_code_2,
            onPressed: () => BirQrDialog.show(context, _bir),
          ),
            ],
          ),
      ],
    );
  }

  Widget _tab(String label, bool active, VoidCallback onTap, {String? count}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: active ? Brand.signal : Brand.navy,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E6EB),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  count,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF475569),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _v2Card() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: Row(
              children: [
                const Text(
                  'Client List',
                  style: TextStyle(fontSize: 17.6, color: Color(0xFF212529)),
                ),
                const Spacer(),
                SearchField(
                  controller: _searchController,
                  hint: 'Search Client',
                  width: 260,
                  onChanged: _onSearchChanged,
                ),
              ],
            ),
          ),
          Expanded(
            child: BirTable(
              tableId: 'bir:customers',
              columns: _columns,
              frozen: _frozen,
              rows: _rows,
              loading: _loading,
              placeholder: 'No customers found',
              onRowTap: _openDetail,
              rowHighlight: (r) =>
                  _n(r, 'vendor_id') > 0 && _s(r, 'vendor_seen_at').isEmpty,
            ),
          ),
          BirPager(
            page: _page,
            lastPage: _lastPage,
            pageSize: _pageSize,
            pageSizes: _pageSizes,
            onPage: (p) {
              _page = p;
              _load();
            },
            onPageSize: (s) {
              _pageSize = s;
              _page = 1;
              _load();
            },
          ),
        ],
      ),
    );
  }
}
