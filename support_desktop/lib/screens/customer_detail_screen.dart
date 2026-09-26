import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import '../services/bir_misc_service.dart';
import '../services/bir_data_service.dart';
import '../services/live_sync.dart';
import '../services/services.dart';
import '../theme.dart';
import 'bir_print_dialog.dart';
import 'bir_widgets.dart';
import '../widgets/tp_loader.dart';

class CustomerDetailScreen extends StatefulWidget {
  const CustomerDetailScreen({
    super.key,
    required this.service,
    required this.brief,
  });

  final CustomerService service;
  final CustomerBrief brief;

  static Future<String?> show(
    BuildContext context, {
    required CustomerService service,
    required CustomerBrief brief,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => CustomerDetailScreen(service: service, brief: brief),
    );
  }

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _Field {
  const _Field(this.label, this.value, {this.serials});
  final String label;
  final String value;
  final List<Map<String, String>>? serials;
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen>
    with LiveRefresh<CustomerDetailScreen> {
  late final BirDataService _bir = BirDataService(widget.service.api);
  late final BirMiscService _misc = BirMiscService(widget.service.api);
  Map<String, dynamic>? _c;
  bool _loading = true;
  bool _removed = false;
  int _pv = -1;
  int _pvToken = 0;
  bool _pvLoading = false;
  bool _pvFailed = false;
  Uint8List? _pvBytes;
  int _seq = 0;
  String? _copied;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  List<String> get liveKeys => const ['customer'];

  @override
  void onLiveChange() {
    if (_loading || _c == null) return;
    _refresh();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() => _loading = true);
    final c = await _bir.customer(widget.brief.id);
    if (!mounted || seq != _seq) return;
    setState(() {
      _c = c;
      _removed = false;
      _loading = false;
    });
  }

  Future<void> _refresh() async {
    final seq = ++_seq;
    try {
      final c = await _bir.customerStrict(widget.brief.id);
      if (!mounted || seq != _seq) return;
      setState(() {
        if (c == null) {
          _removed = true;
        } else {
          _c = c;
          _removed = false;
        }
      });
    } catch (_) {}
  }

  String _s(String k) {
    final v = _c?[k];
    return v == null ? '' : v.toString().trim();
  }

  int _i(String k) => int.tryParse(_s(k)) ?? 0;

  String _birthdate(String raw) {
    final m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(raw);
    if (m == null) return raw;
    return '${m.group(2)!.padLeft(2, '0')}/${m.group(3)!.padLeft(2, '0')}/${m.group(1)}';
  }

  List<Map<String, String>> _serialEntries() {
    final raw = _c?['serial_entries'];
    if (raw is List && raw.isNotEmpty) {
      return raw.whereType<Map>().map((e) {
        return {
          for (final k in [
            'serial_number',
            'serial_number_type',
            'server_type',
            'brand',
            'model',
          ])
            k: (e[k] ?? '').toString().trim(),
        };
      }).toList();
    }
    return _s('serial_number')
        .split('/')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .map((e) => {'serial_number': e})
        .toList();
  }

  List<_Field> _fields() {
    final name = [
      _s('first_name'),
      _s('middle_name'),
      _s('last_name'),
    ].where((e) => e.isNotEmpty).join(' ');
    final vat = _s('is_vat');
    final serials = _serialEntries();
    final snJoined = serials
        .map((e) => e['serial_number'] ?? '')
        .where((e) => e.isNotEmpty)
        .join('/');
    return [
      _Field('Company Name', _s('company_name')),
      _Field('TIN', _s('tin')),
      _Field('Branch Code', _s('branch_code')),
      _Field('Owner / Authorized Name', name),
      _Field('Birthdate (mm/dd/yyyy)', _birthdate(_s('birthdate'))),
      _Field('Phone Number', _s('phone_number')),
      _Field('Email', _s('email')),
      _Field('Address', _s('address')),
      _Field('RDO Code', _s('rdo')),
      _Field('Line of Business', _s('business_line')),
      _Field(
        'Registration Type',
        vat == '1' ? 'VAT' : (vat == '0' ? 'NON-VAT' : ''),
      ),
      _Field('Software', _s('softwarename')),
      _Field(
        'Serial Number',
        snJoined.isNotEmpty ? snJoined : _s('serial_number'),
        serials: serials.isEmpty ? null : serials,
      ),
      _Field('Accreditation No.', _s('acc_num')),
      _Field('MIN', _s('min')),
      _Field('PTU', _s('ptu')),
      _Field('Date Issued', _s('pos_date_issued')),
      _Field('Username', _s('username')),
      _Field('Password', _s('password')),
    ];
  }

  int get _stage {
    final finalDone = _i('final_step') == 1;
    final cStatus = _i('c_status') == 1;
    final step2 = _i('step2') == 1;
    if (finalDone) return 4;
    if (cStatus && step2) return 3;
    if (!cStatus && !step2) return 2;
    return 1;
  }

  Future<void> _copy(String key, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    setState(() => _copied = key);
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted && _copied == key) setState(() => _copied = null);
    });
  }

  Future<void> _print() async {
    final c = _c;
    if (c == null) return;
    await BirPrintDialog.show(context, bir: _bir, customer: c);
  }

  List<Map> get _docs => (_c?['documents'] is List)
      ? (_c!['documents'] as List).whereType<Map>().toList()
      : <Map>[];

  String _docPath(Map d) => (d['file_path'] ?? '').toString();
  String _docName(Map d) =>
      (d['original_filename'] ?? d['stored_filename'] ?? '').toString();

  String _docKind(Map d) {
    final mime = (d['mime_type'] ?? '').toString();
    final url = _docPath(d);
    if (RegExp(r'^image/', caseSensitive: false).hasMatch(mime) ||
        RegExp(
          r'\.(jpe?g|png|gif|webp|bmp|svg)(\?|$)',
          caseSensitive: false,
        ).hasMatch(url)) {
      return 'img';
    }
    if (RegExp('pdf', caseSensitive: false).hasMatch(mime) ||
        RegExp(r'\.pdf(\?|$)', caseSensitive: false).hasMatch(url)) {
      return 'pdf';
    }
    return 'other';
  }

  Future<void> _showPreview(int idx, {bool reload = false}) async {
    final docs = _docs;
    if (idx < 0 || idx >= docs.length) return;
    final token = ++_pvToken;
    setState(() {
      _pv = idx;
      _pvBytes = null;
      _pvFailed = false;
      _pvLoading = _docKind(docs[idx]) == 'img';
    });
    if (_docKind(docs[idx]) != 'img') return;
    final path = _docPath(docs[idx]);
    Uint8List? data;
    for (var attempt = 0; attempt < 3 && data == null; attempt++) {
      if (attempt > 0) {
        await Future.delayed(Duration(milliseconds: 400 * attempt));
      }
      if (token != _pvToken) return;
      final bust = reload || attempt > 0;
      data = await _misc.bytes(
        bust
            ? '$path${path.contains('?') ? '&' : '?'}_r=${DateTime.now().millisecondsSinceEpoch}'
            : path,
      );
      if (data != null && data.isEmpty) data = null;
    }
    if (!mounted || token != _pvToken) return;
    setState(() {
      _pvLoading = false;
      _pvBytes = data;
      _pvFailed = data == null;
    });
  }

  void _closePreview() {
    _pvToken++;
    setState(() {
      _pv = -1;
      _pvBytes = null;
      _pvLoading = false;
      _pvFailed = false;
    });
  }

  Future<void> _openExternal(Map doc) async {
    final path = _docPath(doc);
    if (path.isEmpty) return;
    final name = _docName(doc).isEmpty ? 'file' : _docName(doc);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final local = await _bir.downloadPath(path, name);
      await _bir.open(local);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final stage = _loading ? 1 : _stage;
    final preview = _pv >= 0 && _pv < _docs.length;
    final width = preview ? 1600.0 : 1000.0;
    final ready = !_loading && !_removed && _c != null;
    Widget content = _loading
        ? const SizedBox(
            height: 260,
            child: Center(child: TpLoader()),
          )
        : _removed
        ? const SizedBox(
            height: 200,
            child: Center(child: Text('This record was removed.')),
          )
        : (_c == null
              ? const SizedBox(
                  height: 200,
                  child: Center(
                    child: Text(
                      'An error occurred while fetching customer details.',
                    ),
                  ),
                )
              : SingleChildScrollView(child: _body(stage)));
    if (preview && ready) {
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width:
                (screen.width < width + 48 ? screen.width - 48 : width) * 0.46,
            child: content,
          ),
          const VerticalDivider(width: 1, color: Color(0xFFF0F0F0)),
          Expanded(child: _previewPane()),
        ],
      );
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.of(context).pop(),
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
            if (_pv > 0) _showPreview(_pv - 1);
          },
          const SingleActivator(LogicalKeyboardKey.arrowRight): () {
            if (_pv >= 0) _showPreview(_pv + 1);
          },
        },
        child: Focus(
          autofocus: true,
          child: Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 16,
            ),
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: Color(0xFFECECEC)),
            ),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: width,
                minWidth: screen.width < width + 40 ? screen.width - 48 : width,
                maxHeight: screen.height - 32,
                minHeight: preview ? screen.height - 32 : 0,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  preview ? Expanded(child: content) : Flexible(child: content),
                  Container(
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: Color(0xFFF0F0F0))),
                    ),
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        BirSolidButton(
                          label: 'Close',
                          color: Colors.black,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        if (ready && stage != 2) ...[
                          const SizedBox(width: 10),
                          BirSolidButton(
                            label: 'Download/Print',
                            icon: Icons.print,
                            color: Colors.black,
                            onPressed: _print,
                          ),
                        ],
                        const SizedBox(width: 10),
                        BirSolidButton(
                          label: 'Edit',
                          icon: Icons.edit,
                          color: Brand.signal,
                          onPressed: ready
                              ? () => Navigator.of(context).pop('edit')
                              : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pvBtn(IconData icon, String tip, VoidCallback? onTap) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Tooltip(
        message: tip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Opacity(
            opacity: onTap == null ? 0.35 : 1,
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFECECEC)),
              ),
              child: Icon(icon, size: 15, color: Colors.black),
            ),
          ),
        ),
      ),
    );
  }

  Widget _previewPane() {
    final docs = _docs;
    final d = docs[_pv];
    final name = _docName(d);
    final kind = _docKind(d);
    Widget body;
    if (kind == 'img' && _pvLoading) {
      body = const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TpLoader(strokeWidth: 2, color: Brand.signal),
          SizedBox(height: 10),
          Text('Loading…', style: TextStyle(color: Color(0xFF6B6B6B))),
        ],
      );
    } else if (kind == 'img' && _pvBytes != null) {
      body = Padding(
        padding: const EdgeInsets.all(16),
        child: InteractiveViewer(
          child: Image.memory(_pvBytes!, fit: BoxFit.contain),
        ),
      );
    } else {
      final failed = kind == 'img' && _pvFailed;
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            failed
                ? Icons.warning_amber_rounded
                : (kind == 'pdf'
                      ? Icons.picture_as_pdf
                      : Icons.insert_drive_file),
            size: 40,
            color: Brand.signal,
          ),
          const SizedBox(height: 12),
          Text(
            failed
                ? 'The attachment did not load completely.'
                : 'Preview is not available for this file type.',
            style: const TextStyle(fontSize: 14, color: Color(0xFF6B6B6B)),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              if (failed)
                BirSolidButton(
                  label: 'Reload',
                  height: 38,
                  onPressed: () => _showPreview(_pv, reload: true),
                ),
              BirSolidButton(
                label: 'Open file',
                height: 38,
                onPressed: () => _openExternal(d),
              ),
            ],
          ),
        ],
      );
    }
    return Container(
      color: const Color(0xFFFAFAFA),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
            child: Row(
              children: [
                _pvBtn(
                  Icons.chevron_left,
                  'Previous',
                  _pv > 0 ? () => _showPreview(_pv - 1) : null,
                ),
                _pvBtn(
                  Icons.chevron_right,
                  'Next',
                  _pv < docs.length - 1 ? () => _showPreview(_pv + 1) : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
                Text(
                  '${_pv + 1} / ${docs.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9A9A9A),
                  ),
                ),
                _pvBtn(
                  Icons.sync,
                  'Reload',
                  _pvLoading ? null : () => _showPreview(_pv, reload: true),
                ),
                _pvBtn(
                  Icons.open_in_new,
                  'Open in new tab',
                  () => _openExternal(d),
                ),
                _pvBtn(Icons.close, 'Close preview', _closePreview),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF0F0F0)),
          Expanded(child: Center(child: body)),
        ],
      ),
    );
  }

  Widget _body(int stage) {
    final fields = _fields();
    final empty = fields.where((f) => f.value.isEmpty).length;
    final docs = _docs;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Customer Details',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w800,
              color: Colors.black,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 16),
          BirStageSteps(current: stage, allDone: stage == 4),
          const SizedBox(height: 20),
          if (stage == 3) ...[
            Center(
              child: BirSolidButton(
                label: 'Upload PTU Document',
                icon: Icons.description,
                color: const Color(0xFFF5A623),
                height: 40,
                onPressed: () => Navigator.of(context).pop('ptu'),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (empty > 0) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                border: Border.all(color: const Color(0xFFF5D27A)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_rounded,
                    size: 18,
                    color: Colors.black,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: Colors.black,
                        ),
                        children: [
                          TextSpan(
                            text: '$empty field(s) are empty.',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const TextSpan(
                            text:
                                ' You may edit this customer to fill them in.',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFF0F0F0)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                for (var i = 0; i < fields.length; i++)
                  _row(fields[i], i == fields.length - 1),
              ],
            ),
          ),
          if (docs.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              'ATTACHMENTS (${docs.length})',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
                letterSpacing: 0.5,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < docs.length; i++) _attachment(docs[i], i),
          ],
        ],
      ),
    );
  }

  Widget _copyBtn(String key, String value) {
    final done = _copied == key;
    return Tooltip(
      message: 'Copy',
      child: InkWell(
        onTap: () => _copy(key, value),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 30,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: done ? const Color(0xFFECFDF5) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: done ? const Color(0xFF22C55E) : const Color(0xFFECECEC),
            ),
          ),
          child: Icon(
            done ? Icons.check : Icons.copy_outlined,
            size: 16,
            color: done ? const Color(0xFF22C55E) : Brand.signal,
          ),
        ),
      ),
    );
  }

  Widget _row(_Field f, bool last) {
    const labelStyle = TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: 13.5,
      color: Colors.black,
    );
    const valueStyle = TextStyle(
      fontSize: 14,
      color: Colors.black,
      height: 1.45,
    );
    final empty = f.value.isEmpty;
    Widget value;
    if (empty) {
      value = const Text(
        '(empty)',
        style: TextStyle(
          fontStyle: FontStyle.italic,
          color: Color(0xFF9A9A9A),
          fontSize: 14,
        ),
      );
    } else if (f.serials != null) {
      value = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < f.serials!.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: _serialLine(f.serials![i], i),
            ),
        ],
      );
    } else {
      value = SelectableText(f.value, style: valueStyle);
    }
    return Container(
      constraints: const BoxConstraints(minHeight: 37),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: Color(0xFFF3F3F3))),
      ),
      child: Row(
        children: [
          SizedBox(width: 150, child: Text(f.label, style: labelStyle)),
          const SizedBox(width: 16),
          Expanded(child: value),
          const SizedBox(width: 16),
          if (empty || f.serials != null)
            const SizedBox(width: 30)
          else
            _copyBtn(f.label, f.value),
        ],
      ),
    );
  }

  Widget _serialLine(Map<String, String> e, int index) {
    final type = e['serial_number_type'] ?? '';
    final server = e['server_type'] ?? '';
    final sn = e['serial_number'] ?? '';
    final meta = [
      e['brand'] ?? '',
      e['model'] ?? '',
    ].where((v) => v.isNotEmpty).join(' ');
    final label = type.isEmpty
        ? 'Unspecified'
        : (type == 'Server' && server.isNotEmpty ? '$type · $server' : type);
    return Row(
      children: [
        Container(
          constraints: const BoxConstraints(minWidth: 120),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: type.isEmpty ? const Color(0xFFF0F0F0) : Colors.black,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label.toUpperCase(),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: type.isEmpty ? const Color(0xFF9A9A9A) : Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(width: 9),
        SizedBox(
          width: 150,
          child: Text(
            meta,
            style: const TextStyle(fontSize: 12, color: Color(0xFF9A9A9A)),
          ),
        ),
        Expanded(
          child: sn.isEmpty
              ? const Text(
                  '(empty)',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: Color(0xFF9A9A9A),
                  ),
                )
              : SelectableText(
                  sn,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13.5,
                    color: Colors.black,
                  ),
                ),
        ),
        if (sn.isNotEmpty) _copyBtn('sn$index', sn),
      ],
    );
  }

  Widget _attachment(Map d, int index) {
    final name = (d['original_filename'] ?? d['stored_filename'] ?? '')
        .toString();
    final mime = (d['mime_type'] ?? '').toString();
    final docType = (d['doc_type'] ?? '').toString();
    final typeLabel = docType == 'valid_id'
        ? 'Valid ID'
        : (docType == 'requirement' ? 'Requirement' : 'Business Doc');
    final icon = RegExp('pdf', caseSensitive: false).hasMatch(mime)
        ? Icons.picture_as_pdf
        : (mime.startsWith('image/') ? Icons.image : Icons.insert_drive_file);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: const Color(0xFFFAFAFA),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFFECECEC)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            if (index == _pv) {
              _closePreview();
            } else {
              _showPreview(index);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                Icon(icon, size: 17, color: Brand.signal),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.3, color: Colors.black),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    typeLabel.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10.4,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
