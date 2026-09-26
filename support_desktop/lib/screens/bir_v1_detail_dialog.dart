import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/bir_v1_service.dart';
import 'bir_v1_ui.dart';
import 'bir_widgets.dart';

class BirV1DetailDialog extends StatefulWidget {
  const BirV1DetailDialog({
    super.key,
    required this.svc,
    required this.id,
    this.initialTab = 'details',
    required this.onChanged,
  });

  final BirV1Service svc;
  final int id;
  final String initialTab;
  final VoidCallback onChanged;

  @override
  State<BirV1DetailDialog> createState() => _BirV1DetailDialogState();
}

class _BirV1DetailDialogState extends State<BirV1DetailDialog>
    with SingleTickerProviderStateMixin {
  static const _detailFields = [
    ('company_name', 'Company Name'),
    ('tin', 'TIN'),
    ('branch_code', 'Branch Code'),
    ('rdo', 'RDO'),
    ('address', 'Business Address'),
    ('province', 'Province'),
    ('city', 'City'),
    ('barangay', 'Barangay'),
    ('business_line', 'Line of Business'),
    ('softwarename', 'Software Name'),
    ('acc_num', 'Accreditation No.'),
    ('serial_number', 'Serial Number(s)'),
    ('min', 'MIN'),
    ('ptu', 'PTU'),
    ('pos_date_issued', 'POS Date Issued'),
    ('email', 'Email'),
    ('username', 'Username'),
    ('tin_issuance_date', 'TIN Issuance Date'),
  ];

  static const _docTypes = [
    ('ptu', 'PTU'),
    ('application', 'Application'),
    ('valid_id', 'Valid ID'),
    ('extraction_doc', 'Extraction Doc'),
    ('bir_form', 'BIR Form'),
    ('sworn_declaration', 'Sworn Declaration'),
    ('other', 'Other'),
  ];

  static const _tabKeys = ['details', 'edit', 'workflow', 'docs'];

  late final TabController _tabs;
  Map<String, dynamic>? _r;
  String _loadError = '';
  String _title = 'Loading…';

  final _c = <String, TextEditingController>{
    for (final k in [
      'company_name',
      'tin',
      'branch_code',
      'rdo',
      'address',
      'first_name',
      'middle_name',
      'last_name',
      'email',
      'softwarename',
      'acc_num',
      'business_line',
      'username',
      'password',
      'serial_number',
      'wf_date',
      'wf_ptu',
      'wf_min',
    ])
      k: TextEditingController(),
  };
  String _isVat = '0';
  String _wfStatus = 'draft';
  bool _showPw = false;
  bool _saving = false;
  bool _applying = false;

  List<Map<String, dynamic>> _docs = const [];
  bool _docsLoading = false;
  String _docsError = '';
  String _docType = 'other';
  String? _docPath;
  String? _docName;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _open();
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _s(String k) {
    final v = _r?[k];
    return v == null ? '' : v.toString();
  }

  bool get _vat {
    final v = _r?['is_vat'];
    return v == true || v == 1 || v == '1';
  }

  Future<void> _open() async {
    try {
      final r = await widget.svc.record(widget.id);
      if (!mounted) return;
      setState(() {
        _r = r;
        _title = _s('company_name').isEmpty
            ? 'Registration #${widget.id}'
            : _s('company_name');
        _fill();
        _setDocs(r['documents']);
      });
      final i = _tabKeys.indexOf(widget.initialTab);
      _tabs.index = i < 0 ? 0 : i;
    } on BirV1Exception catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    }
  }

  void _setDocs(dynamic raw) {
    _docs = raw is List
        ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : const [];
  }

  void _fill() {
    for (final k in [
      'company_name',
      'tin',
      'branch_code',
      'rdo',
      'address',
      'first_name',
      'middle_name',
      'last_name',
      'email',
      'softwarename',
      'acc_num',
      'business_line',
      'serial_number',
      'username',
      'password',
    ]) {
      _c[k]!.text = _s(k);
    }
    _isVat = _vat ? '1' : '0';
    _showPw = false;
    final st = _s('status');
    _wfStatus = const ['draft', 'for_ptu', 'completed'].contains(st)
        ? st
        : 'draft';
    _c['wf_ptu']!.text = _s('ptu');
    _c['wf_min']!.text = _s('min');
    _c['wf_date']!.text = _s('pos_date_issued');
  }

  Future<void> _loadDocuments() async {
    setState(() {
      _docsLoading = true;
      _docsError = '';
    });
    try {
      final d = await widget.svc.documents(widget.id);
      if (!mounted) return;
      setState(() {
        _docs = d;
        _docsLoading = false;
      });
    } on BirV1Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _docsLoading = false;
        _docsError = e.message;
      });
    }
  }

  Future<void> _save() async {
    if (_r == null || _saving) return;
    final payload = <String, dynamic>{
      'company_name': _c['company_name']!.text,
      'tin': _c['tin']!.text,
      'branch_code': _c['branch_code']!.text,
      'rdo': _c['rdo']!.text,
      'is_vat': _isVat == '1',
      'address': _c['address']!.text,
      'first_name': _c['first_name']!.text,
      'middle_name': _c['middle_name']!.text,
      'last_name': _c['last_name']!.text,
      'email': _c['email']!.text,
      'softwarename': _c['softwarename']!.text,
      'acc_num': _c['acc_num']!.text,
      'business_line': _c['business_line']!.text,
      'serial_number': _c['serial_number']!.text,
      'username': _c['username']!.text,
      'password': _c['password']!.text,
    };
    setState(() => _saving = true);
    try {
      final rec = await widget.svc.update(widget.id, payload);
      if (!mounted) return;
      setState(() {
        _r = rec ?? _r;
        _fill();
      });
      widget.onChanged();
      await birV1Toast(
        context,
        'success',
        'Saved',
        'The V1 record has been updated.',
      );
      _tabs.index = 0;
    } on BirV1Exception catch (e) {
      if (mounted) {
        await birV1Toast(context, 'error', 'Update failed', e.message);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _applyWorkflow() async {
    if (_r == null || _applying) return;
    final payload = <String, dynamic>{'status': _wfStatus};
    final ptu = _c['wf_ptu']!.text.trim();
    final min = _c['wf_min']!.text.trim();
    final issued = _c['wf_date']!.text.trim();
    if (ptu.isNotEmpty) payload['ptu'] = ptu;
    if (min.isNotEmpty) payload['min'] = min;
    if (issued.isNotEmpty) payload['pos_date_issued'] = issued;
    setState(() => _applying = true);
    try {
      final rec = await widget.svc.workflow(widget.id, payload);
      if (!mounted) return;
      setState(() {
        _r = rec ?? _r;
        _fill();
      });
      widget.onChanged();
      await birV1Toast(
        context,
        'success',
        'Status updated',
        'This V1 record is now "${_s('status')}".',
      );
      _tabs.index = 0;
    } on BirV1Exception catch (e) {
      if (mounted) {
        await birV1Toast(context, 'error', 'Transition rejected', e.message);
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  Future<void> _pickDoc() async {
    FilePickerResult? res;
    try {
      res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      );
    } catch (_) {
      res = null;
    }
    final f = res?.files.single;
    if (f == null || f.path == null) return;
    setState(() {
      _docPath = f.path;
      _docName = f.name;
    });
  }

  Future<void> _upload() async {
    if (_r == null || _uploading) return;
    if (_docPath == null) {
      await birV1Toast(
        context,
        'warning',
        'Choose a file',
        'Pick a PDF, JPEG, PNG or WebP file first.',
      );
      return;
    }
    setState(() => _uploading = true);
    try {
      await widget.svc.uploadDocument(widget.id, _docPath!, _docType);
      if (!mounted) return;
      setState(() {
        _docPath = null;
        _docName = null;
      });
      _loadDocuments();
      widget.onChanged();
      await birV1Toast(
        context,
        'success',
        'Uploaded',
        'The document is now attached to this V1 record.',
      );
    } on BirV1Exception catch (e) {
      if (mounted) {
        await birV1Toast(context, 'error', 'Upload failed', e.message);
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _downloadDoc(Map<String, dynamic> doc) async {
    final docId = '${doc['id']}';
    try {
      final path = await widget.svc.download(
        'registrations/${widget.id}/documents/$docId',
        const {},
        (doc['original_filename'] ?? 'document-$docId').toString(),
      );
      await widget.svc.open(path);
    } on BirV1Exception catch (e) {
      if (mounted) {
        await birV1Toast(context, 'error', 'Download failed', e.message);
      }
    }
  }

  Future<void> _deleteDoc(Map<String, dynamic> doc) async {
    final docId = int.tryParse('${doc['id']}') ?? 0;
    final name = (doc['original_filename'] ?? '').toString();
    final ok = await birV1Confirm(
      context,
      title: 'Delete document?',
      text:
          '$name will be removed from the V1 system, including the file on disk.',
    );
    if (!ok || !mounted) return;
    try {
      await widget.svc.deleteDocument(widget.id, docId);
      if (!mounted) return;
      _loadDocuments();
      widget.onChanged();
    } on BirV1Exception catch (e) {
      if (mounted) {
        await birV1Toast(context, 'error', 'Delete failed', e.message);
      }
    }
  }

  Widget _grid(List<(int, Widget)> cells) {
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 16.0;
        return Wrap(
          spacing: gap,
          runSpacing: 14,
          children: [
            for (final c in cells)
              SizedBox(
                width: c.$1 == 12
                    ? box.maxWidth
                    : ((box.maxWidth + gap) * c.$1 / 12) - gap,
                child: c.$2,
              ),
          ],
        );
      },
    );
  }

  Widget _value(String label, Widget v) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [birV1Label(label), v],
  );

  Widget _details() {
    if (_loadError.isNotEmpty) {
      return Text(_loadError, style: const TextStyle(color: birV1Danger));
    }
    if (_r == null) {
      return const Text(
        'Loading record…',
        style: TextStyle(color: Color(0xFF6C757D)),
      );
    }
    final owner = [
      _s('first_name'),
      _s('middle_name'),
      _s('last_name'),
    ].where((e) => e.isNotEmpty).join(' ');
    final missing = _r!['bir_card_missing_fields'];
    final ready = _r!['bir_card_ready'] == true;
    return _grid([
      (
        12,
        _value(
          'Status',
          Row(
            children: [
              birV1StatusBadge(_s('status')),
              const SizedBox(width: 6),
              Text(
                'V1 record #${_s('id')}',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF6C757D),
                ),
              ),
            ],
          ),
        ),
      ),
      (6, _value('Owner Name', SelectableText(owner.isEmpty ? '—' : owner))),
      (6, _value('VAT Registered', Text(_vat ? 'Yes' : 'No'))),
      for (final f in _detailFields)
        (6, _value(f.$2, SelectableText(_s(f.$1).isEmpty ? '—' : _s(f.$1)))),
      if (!ready && missing is List && missing.isNotEmpty)
        (
          12,
          BirV1Note(
            'BIR card not available yet — missing: ${missing.join(', ')}',
          ),
        ),
    ]);
  }

  Widget _text(
    String key,
    String label,
    int max, {
    int lines = 1,
    String? hint,
    bool obscure = false,
    Widget? suffix,
  }) => _value(
    label,
    TextField(
      controller: _c[key],
      maxLength: max,
      maxLines: obscure ? 1 : lines,
      minLines: 1,
      obscureText: obscure,
      decoration: birV1InputDecoration(hint: hint, suffix: suffix),
      style: const TextStyle(fontSize: 14),
    ),
  );

  Widget _select(
    String label,
    String value,
    List<(String, String)> items,
    ValueChanged<String> onChanged,
  ) => _value(
    label,
    DropdownButtonFormField<String>(
      key: ValueKey('$label|$value'),
      initialValue: value,
      isExpanded: true,
      decoration: birV1InputDecoration(),
      style: const TextStyle(fontSize: 14, color: Color(0xFF212529)),
      items: [
        for (final i in items) DropdownMenuItem(value: i.$1, child: Text(i.$2)),
      ],
      onChanged: (v) => onChanged(v ?? value),
    ),
  );

  Widget _formFooter(
    String label,
    bool busy,
    String busyLabel,
    VoidCallback onSubmit,
  ) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        BirSolidButton(
          label: 'Cancel',
          color: const Color(0xFF6C757D),
          height: 40,
          fontWeight: FontWeight.w500,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        const SizedBox(width: 8),
        BirSolidButton(
          label: busy ? busyLabel : label,
          color: const Color(0xFF007BFF),
          height: 40,
          fontWeight: FontWeight.w500,
          onPressed: busy || _r == null ? null : onSubmit,
        ),
      ],
    ),
  );

  Widget _edit() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _grid([
          (6, _text('company_name', 'Company Name', 100)),
          (6, _text('tin', 'TIN', 100)),
          (4, _text('branch_code', 'Branch Code', 50)),
          (4, _text('rdo', 'RDO', 20)),
          (
            4,
            _select('VAT Registered', _isVat, const [
              ('1', 'Yes'),
              ('0', 'No'),
            ], (v) => setState(() => _isVat = v)),
          ),
          (12, _text('address', 'Business Address', 500, lines: 2)),
          (4, _text('first_name', 'First Name', 100)),
          (4, _text('middle_name', 'Middle Name', 100)),
          (4, _text('last_name', 'Last Name', 100)),
          (6, _text('email', 'Email', 100)),
          (6, _text('softwarename', 'Software Name', 100)),
          (6, _text('acc_num', 'Accreditation No.', 100)),
          (6, _text('business_line', 'Line of Business', 800)),
          (6, _text('username', 'Username', 100)),
          (
            6,
            _text(
              'password',
              'Password',
              100,
              obscure: !_showPw,
              suffix: IconButton(
                tooltip: _showPw ? 'Hide password' : 'Show password',
                icon: Icon(
                  _showPw ? Icons.visibility_off : Icons.visibility,
                  size: 18,
                ),
                onPressed: () => setState(() => _showPw = !_showPw),
              ),
            ),
          ),
          (
            12,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _text('serial_number', 'Serial Number(s)', 1000),
                const SizedBox(height: 4),
                const Text.rich(
                  TextSpan(
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF6C757D)),
                    children: [
                      TextSpan(text: 'Separate multiple serials with '),
                      TextSpan(
                        text: '/',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          color: Color(0xFFE83E8C),
                        ),
                      ),
                      TextSpan(text: ' — one BIR card page each.'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ]),
        _formFooter('Save Changes', _saving, 'Saving…', _save),
      ],
    );
  }

  Widget _workflow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _grid([
          (
            6,
            _select('Status', _wfStatus, const [
              ('draft', 'Draft'),
              ('for_ptu', 'For PTU'),
              ('completed', 'Completed'),
            ], (v) => setState(() => _wfStatus = v)),
          ),
          (6, _text('wf_date', 'POS Date Issued', 100, hint: 'May 26, 2026')),
          (6, _text('wf_ptu', 'PTU', 100)),
          (6, _text('wf_min', 'MIN', 100)),
        ]),
        const SizedBox(height: 16),
        const BirV1Note(
          'Completing a registration needs PTU, MIN and POS Date Issued — send them here if they are not stored yet.',
        ),
        _formFooter('Apply Transition', _applying, 'Applying…', _applyWorkflow),
      ],
    );
  }

  Widget _docRow(Map<String, dynamic> doc) {
    final size = num.tryParse('${doc['file_size'] ?? ''}') ?? 0;
    final missing = doc['exists'] == false;
    final sub = <InlineSpan>[
      TextSpan(text: (doc['doc_type'] ?? '').toString()),
      if (size > 0)
        TextSpan(text: ' · ${(size / 1024 / 1024).toStringAsFixed(2)} MB'),
      if ('${doc['uploaded_at'] ?? ''}'.isNotEmpty)
        TextSpan(text: ' · ${doc['uploaded_at']}'),
      if (missing) ...[
        const TextSpan(text: ' · '),
        const TextSpan(
          text: 'file missing on disk',
          style: TextStyle(color: Color(0xFFB91C1C)),
        ),
      ],
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: Row(
        children: [
          const Icon(Icons.insert_drive_file, color: birV1Orange, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (doc['original_filename'] ?? '').toString(),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Color(0xFF0F172A),
                  ),
                ),
                Text.rich(
                  TextSpan(children: sub),
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          _smallBtn(
            Icons.download,
            'Download',
            const Color(0xFF6C757D),
            missing ? null : () => _downloadDoc(doc),
          ),
          const SizedBox(width: 6),
          _smallBtn(Icons.delete, 'Delete', birV1Danger, () => _deleteDoc(doc)),
        ],
      ),
    );
  }

  Widget _smallBtn(
    IconData icon,
    String tip,
    Color color,
    VoidCallback? onPressed,
  ) => Tooltip(
    message: tip,
    child: SizedBox(
      width: 34,
      height: 31,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          foregroundColor: color,
          side: BorderSide(
            color: color.withValues(alpha: onPressed == null ? 0.4 : 1),
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        child: Icon(icon, size: 16),
      ),
    ),
  );

  Widget _documents() {
    Widget list;
    if (_docsLoading) {
      list = const Text(
        'Loading documents…',
        style: TextStyle(fontSize: 13.5, color: Color(0xFF6C757D)),
      );
    } else if (_docsError.isNotEmpty) {
      list = Text(
        _docsError,
        style: const TextStyle(fontSize: 13.5, color: birV1Danger),
      );
    } else if (_docs.isEmpty) {
      list = const Text(
        'No documents on this record yet.',
        style: TextStyle(fontSize: 13.5, color: Color(0xFF6C757D)),
      );
    } else {
      list = Column(children: [for (final d in _docs) _docRow(d)]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        list,
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, box) {
            final unit = (box.maxWidth - 32) / 12;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(
                  width: unit * 5,
                  child: _select(
                    'Document Type',
                    _docType,
                    _docTypes,
                    (v) => setState(() => _docType = v),
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: unit * 5,
                  child: _value(
                    'File',
                    InkWell(
                      onTap: _uploading ? null : _pickDoc,
                      child: InputDecorator(
                        decoration: birV1InputDecoration(),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              color: const Color(0xFFE9ECEF),
                              child: const Text(
                                'Choose File',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _docName ?? 'No file chosen',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: unit * 2,
                  child: BirSolidButton(
                    label: _uploading ? 'Uploading…' : 'Upload',
                    color: const Color(0xFF007BFF),
                    height: 44,
                    fontWeight: FontWeight.w500,
                    onPressed: _uploading || _r == null ? null : _upload,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        const Text(
          'PDF, JPEG, PNG or WebP — max 20 MB.',
          style: TextStyle(fontSize: 12.5, color: Color(0xFF6C757D)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return BirV1Shell(
      title: _title,
      scrollable: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: const Color(0xFF495057),
            unselectedLabelColor: const Color(0xFF007BFF),
            indicatorColor: birV1Orange,
            dividerColor: const Color(0xFFE2E8F0),
            tabs: [
              const Tab(text: 'Details'),
              const Tab(text: 'Edit'),
              const Tab(text: 'Workflow'),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Documents'),
                    const SizedBox(width: 6),
                    BirBadge(
                      label: '${_docs.length}',
                      bg: const Color(0xFF6C757D),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Flexible(
            child: AnimatedBuilder(
              animation: _tabs,
              builder: (context, _) => SingleChildScrollView(
                padding: const EdgeInsets.only(top: 16),
                child: switch (_tabs.index) {
                  1 => _edit(),
                  2 => _workflow(),
                  3 => _documents(),
                  _ => _details(),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
