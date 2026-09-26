import 'dart:async';

import 'package:flutter/material.dart';

import '../services/bir_data_service.dart';
import '../services/bir_v1_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'bir_table.dart';
import 'bir_v1_detail_dialog.dart';
import 'bir_v1_print_dialog.dart';
import 'bir_v1_step3_dialog.dart';
import 'bir_v1_ui.dart';
import 'bir_widgets.dart';

class BirV1Pane extends StatefulWidget {
  const BirV1Pane({super.key, required this.bir, required this.onTotal});

  final BirDataService bir;
  final ValueChanged<int?> onTotal;

  @override
  State<BirV1Pane> createState() => _BirV1PaneState();
}

class _BirV1PaneState extends State<BirV1Pane> {
  static const _pageSizes = <int>[15, 20, 25, 30, 50, 100];
  final _search = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  String _notice = '';
  String _status = '';
  int _page = 1;
  int _lastPage = 1;
  int _pageSize = 30;
  int _seq = 0;
  final _hidden = <String>{};
  late final BirV1Service _svc = BirV1Service(widget.bir.api);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() => _loading = true);
    try {
      final p = await widget.bir.v1Registrations(
        page: _page,
        limit: _pageSize,
        search: _search.text,
        status: _status,
      );
      if (!mounted || seq != _seq) return;
      setState(() {
        _rows = p.rows;
        _lastPage = p.lastPage;
        _loading = false;
        _notice = '';
      });
      widget.onTotal(p.total);
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _rows = const [];
        _loading = false;
        _notice = e is BirDownloadException
            ? e.message
            : 'Could not load the V1 registrations.';
      });
      widget.onTotal(null);
    }
  }

  String _s(Map<String, dynamic> r, String k) => (r[k] ?? '').toString().trim();

  int _id(Map<String, dynamic> row) => int.tryParse(_s(row, 'id')) ?? 0;

  Future<void> _view(Map<String, dynamic> row, [String tab = 'details']) async {
    await showDialog<void>(
      context: context,
      builder: (_) => BirV1DetailDialog(
        svc: _svc,
        id: _id(row),
        initialTab: tab,
        onChanged: _load,
      ),
    );
  }

  Future<void> _openPrint(Map<String, dynamic> row) async {
    Map<String, dynamic> record;
    try {
      record = await _svc.record(_id(row));
    } on BirV1Exception catch (e) {
      if (mounted) {
        await birV1Toast(context, 'error', 'Could not open Print', e.message);
      }
      return;
    }
    if (!mounted) return;
    final choice = await showDialog<BirV1PrintChoice>(
      context: context,
      builder: (_) => BirV1PrintDialog(record: record),
    );
    if (choice == null || !mounted) return;
    if (choice.email) {
      await _sendEmail(record, choice);
    } else {
      await _print(record, choice);
    }
  }

  Future<bool> _fetchOpen(
    String path,
    Map<String, String> query,
    String name,
  ) async {
    try {
      final file = await _svc.download(path, query, name);
      await _svc.open(file);
      return true;
    } on BirV1Exception catch (e) {
      if (mounted) {
        await birV1Toast(context, 'error', 'Document unavailable', e.message);
      }
      return false;
    }
  }

  Future<void> _print(Map<String, dynamic> record, BirV1PrintChoice c) async {
    final id = int.tryParse('${record['id']}') ?? 0;
    if (c.application) {
      final f = '${record['pdf_file'] ?? ''}';
      await _fetchOpen('legacy/upload-file', {'file': f}, f);
    }
    if (c.ptu) {
      for (final name in birV1PtuFiles(record)) {
        await _fetchOpen('legacy/upload-file', {'file': name}, name);
      }
    }
    if (c.askReceipt) {
      await _fetchOpen('registrations/$id/bir-card', {
        'download': '0',
      }, 'bir-card-$id.pdf');
    }
    final docType = c.swornDocType;
    if (docType == null || !mounted) return;
    String? file;
    try {
      file = await _svc.swornDeclaration(id, docType);
    } on BirV1Exception catch (e) {
      if (mounted) {
        await birV1Toast(context, 'error', 'Print failed', e.message);
      }
      return;
    }
    if (!mounted) return;
    if (file == null) {
      await birV1Toast(
        context,
        'error',
        'Print failed',
        'The V1 system did not return a generated document.',
      );
      return;
    }
    await _fetchOpen('legacy/print-file', {'file': file}, file);
  }

  Future<void> _sendEmail(
    Map<String, dynamic> record,
    BirV1PrintChoice c,
  ) async {
    final to = c.receiverEmail;
    final id = '${record['id']}';
    final calls = <Future<void>>[
      if (c.application)
        _svc.email('legacy/email/application', {
          'pdfFile': '${record['pdf_file'] ?? ''}',
          'receiverEmail': to,
        }),
      if (c.ptu)
        _svc.email('legacy/email/ptu', {
          'ptuFile': '${record['ptu_file'] ?? ''}',
          'receiverEmail': to,
        }),
      if (c.askReceipt)
        _svc.email('legacy/email/ask-receipt', {'id': id, 'receiverEmail': to}),
      if (c.swornDocType != null)
        _svc.email('legacy/email/statement', {
          'id': id,
          'docType': c.swornDocType!,
          'receiverEmail': to,
        }),
    ];
    birV1ShowLoading(
      context,
      'Sending…',
      'Sending the selected documents to $to.',
    );
    var ok = true;
    try {
      await Future.wait(calls);
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    if (ok) {
      await birV1Toast(
        context,
        'success',
        'Emails sent',
        'The selected documents were sent to $to.',
      );
    } else {
      await birV1Toast(
        context,
        'error',
        'Email sending failed',
        'One or more documents could not be sent. Please try again.',
      );
    }
  }

  Future<void> _openStep3(Map<String, dynamic> row) async {
    Map<String, dynamic> record;
    try {
      record = await _svc.record(_id(row));
    } on BirV1Exception catch (e) {
      if (mounted) {
        await birV1Toast(context, 'error', 'Could not open Step 3', e.message);
      }
      return;
    }
    if (!mounted) return;
    final res = await showDialog<BirV1Step3Result>(
      context: context,
      builder: (_) => BirV1Step3Dialog(svc: _svc, record: record),
    );
    if (res == null || !mounted) return;
    _load();
    final company = '${record['company_name'] ?? ''}'.trim();
    await birV1Toast(
      context,
      'success',
      'Successfully Added',
      '${company.isEmpty ? 'This registration' : company} is now completed (PTU ${res.ptu}).',
    );
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final id = _id(row);
    final key = '$id';
    final label = _s(row, 'company_name').isNotEmpty
        ? _s(row, 'company_name')
        : 'V1 record #$id';
    final ok = await birV1Confirm(
      context,
      title: 'Delete this V1 record?',
      text:
          '$label and all of its documents will be permanently removed from the V1 system.',
    );
    if (!ok || !mounted) return;
    setState(() => _hidden.add(key));
    var undone = false;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final ctl = messenger.showSnackBar(
      SnackBar(
        content: Text('$label deleted'),
        duration: const Duration(seconds: 5),
        persist: false,
        action: SnackBarAction(label: 'Undo', onPressed: () => undone = true),
      ),
    );
    await ctl.closed;
    if (undone) {
      if (mounted) setState(() => _hidden.remove(key));
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Delete undone'),
          duration: Duration(milliseconds: 1800),
          persist: false,
        ),
      );
      return;
    }
    try {
      await _svc.deleteRecord(id);
      if (!mounted) return;
      _hidden.remove(key);
      _load();
    } on BirV1Exception catch (e) {
      if (!mounted) return;
      setState(() => _hidden.remove(key));
      await birV1Toast(context, 'error', 'Delete failed', e.message);
    }
  }

  void _onAction(String action, Map<String, dynamic> row) {
    switch (action) {
      case 'view':
        _view(row, 'details');
      case 'edit':
        _view(row, 'edit');
      case 'print':
        _openPrint(row);
      case 'step3':
        _openStep3(row);
      case 'done':
        birV1Toast(
          context,
          'info',
          'Already completed',
          'You can print all the documents from the Print action.',
        );
      case 'delete':
        _delete(row);
    }
  }

  PopupMenuItem<String> _menuItem(
    String value,
    IconData icon,
    String label,
    String tip, {
    Color? fill,
    Color fg = const Color(0xFF212529),
  }) => PopupMenuItem<String>(
    value: value,
    height: 38,
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    child: Tooltip(
      message: tip,
      waitDuration: const Duration(milliseconds: 600),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 10),
            Text(label, style: TextStyle(fontSize: 14, color: fg)),
          ],
        ),
      ),
    ),
  );

  List<PopupMenuEntry<String>> _menu(Map<String, dynamic> row) {
    final status = _s(row, 'status');
    return [
      _menuItem('view', Icons.visibility, 'View', 'View the full V1 record'),
      _menuItem('edit', Icons.edit, 'Edit', 'Edit this V1 record'),
      _menuItem(
        'print',
        Icons.print,
        'Print',
        'Print or email the V1 application documents',
      ),
      if (status == 'for_ptu')
        _menuItem(
          'step3',
          Icons.description,
          'Step 3',
          'Upload the Permit to Use PDF and complete this registration',
          fill: const Color(0xFFFFC107),
        ),
      if (status == 'completed')
        _menuItem(
          'done',
          Icons.check_circle,
          'Completed',
          'This registration is completed',
          fill: const Color(0xFF28A745),
          fg: Colors.white,
        ),
      _menuItem(
        'delete',
        Icons.delete,
        'Delete',
        'Delete this V1 record and its documents',
      ),
    ];
  }

  List<BirColumn> get _columns => [
    BirColumn(
      title: 'No.',
      width: 70,
      cell: (r, i) => Text('${(_page - 1) * _pageSize + i + 1}'),
    ),
    BirColumn(
      title: 'Company Name',
      width: 240,
      sortKey: (r) => _s(r, 'company_name'),
      cell: (r, _) => Text(_s(r, 'company_name')),
    ),
    BirColumn(
      title: 'Branch Code',
      width: 130,
      center: true,
      cell: (r, _) =>
          Text(_s(r, 'branch_code').isEmpty ? '—' : _s(r, 'branch_code')),
    ),
    BirColumn(
      title: 'TIN',
      width: 160,
      sortKey: (r) => _s(r, 'tin'),
      cell: (r, _) => Text(_s(r, 'tin')),
    ),
    BirColumn(
      title: 'Address',
      width: 260,
      cell: (r, _) => Text(_s(r, 'address'), overflow: TextOverflow.ellipsis),
    ),
    BirColumn(
      title: 'Owner Name',
      width: 190,
      cell: (r, _) => Text(
        [
          _s(r, 'first_name'),
          _s(r, 'middle_name'),
          _s(r, 'last_name'),
        ].where((e) => e.isNotEmpty).join(' '),
      ),
    ),
    BirColumn(
      title: 'Software',
      width: 200,
      cell: (r, _) => Text(_s(r, 'softwarename')),
    ),
    BirColumn(
      title: 'PTU',
      width: 180,
      cell: (r, _) => _s(r, 'ptu').isEmpty
          ? const Text(
              '—',
              style: TextStyle(fontSize: 12, color: Color(0xFF6C757D)),
            )
          : Text(_s(r, 'ptu')),
    ),
  ];

  List<BirColumn> get _frozen => [
    BirColumn(
      title: 'Status',
      width: 150,
      cell: (r, _) => birV1StatusBadge(_s(r, 'status')),
    ),
    BirColumn(
      title: 'Action',
      width: 110,
      center: true,
      cell: (r, _) => SizedBox(
        width: 34,
        height: 31,
        child: PopupMenuButton<String>(
          tooltip: 'Actions',
          position: PopupMenuPosition.under,
          color: Colors.white,
          surfaceTintColor: Colors.white,
          constraints: const BoxConstraints(minWidth: 190),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          onSelected: (v) => _onAction(v, r),
          itemBuilder: (_) => _menu(r),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF6C757D)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Icon(
              Icons.arrow_drop_down,
              size: 20,
              color: Color(0xFF6C757D),
            ),
          ),
        ),
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
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
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFFED7AA)),
                  ),
                  child: const Text(
                    'VERSION 1',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF9A3412),
                    ),
                  ),
                ),
                const Spacer(),
                Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: Brand.inputBorder),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _status,
                      style: const TextStyle(fontSize: 14, color: Brand.navy),
                      items: const [
                        DropdownMenuItem(
                          value: '',
                          child: Text('All statuses'),
                        ),
                        DropdownMenuItem(value: 'draft', child: Text('Draft')),
                        DropdownMenuItem(
                          value: 'for_ptu',
                          child: Text('For PTU'),
                        ),
                        DropdownMenuItem(
                          value: 'completed',
                          child: Text('Completed'),
                        ),
                      ],
                      onChanged: (v) {
                        _status = v ?? '';
                        _page = 1;
                        _load();
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SearchField(
                  controller: _search,
                  hint: 'Search V1 Client',
                  width: 240,
                  onChanged: (_) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 300), () {
                      _page = 1;
                      _load();
                    });
                  },
                ),
                const SizedBox(width: 10),
                OutlinedIconButton(
                  icon: Icons.sync,
                  tooltip: 'Reload from the V1 system',
                  onPressed: _load,
                ),
              ],
            ),
          ),
          if (_notice.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFED7AA)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber,
                    size: 16,
                    color: Color(0xFF9A3412),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _notice,
                      style: const TextStyle(color: Color(0xFF9A3412)),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: BirTable(
              tableId: 'bir:v1',
              columns: _columns,
              frozen: _frozen,
              rows: _hidden.isEmpty
                  ? _rows
                  : _rows.where((r) => !_hidden.contains(_s(r, 'id'))).toList(),
              loading: _loading,
              placeholder: 'No V1 records found',
              onRowTap: (r) => _view(r),
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
