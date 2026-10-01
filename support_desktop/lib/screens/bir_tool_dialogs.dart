import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/bir_data_service.dart';
import '../services/bir_misc_service.dart';
import '../theme.dart';
import '../widgets/resizable_columns.dart';
import 'bir_misc_ui.dart';
import 'bir_widgets.dart';
import '../widgets/tp_loader.dart';

class BirQrDialog extends StatefulWidget {
  const BirQrDialog({super.key, required this.bir});
  final BirDataService bir;

  static Future<void> show(BuildContext context, BirDataService bir) =>
      showDialog<void>(
        context: context,
        builder: (_) => BirQrDialog(bir: bir),
      );

  @override
  State<BirQrDialog> createState() => _BirQrDialogState();
}

class _BirQrDialogState extends State<BirQrDialog> {
  static const _prodRegisterUrl =
      'https://support.tinkerpro.com/client-register?register=1';
  static const _fbAppId = '787214717774513';

  late final BirMiscService _svc = BirMiscService(widget.bir.api);
  late final Future<Uint8List?> _qr = _svc.bytes(
    'client-register-qr.php?variant=prod&format=png&v=2',
  );

  Future<void> _download() async {
    try {
      final res = await _svc.fetch(_svc.pathUri('client-register-qr.php'));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw BirMiscException('Download failed.');
      }
      final saved = await _svc.saveBytes(
        res.bodyBytes,
        'client-register-qr.svg',
      );
      if (mounted) {
        birToast(context, 'Saved to ${saved.path}', kind: BirToastKind.success);
      }
    } catch (e) {
      if (mounted) birToast(context, e.toString(), kind: BirToastKind.error);
    }
  }

  Future<void> _share() async {
    if (_svc.base.startsWith('https:')) {
      final url =
          'https://www.facebook.com/dialog/send?app_id=$_fbAppId'
          '&link=${Uri.encodeComponent(_prodRegisterUrl)}'
          '&redirect_uri=${Uri.encodeComponent(_prodRegisterUrl)}';
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return;
    }
    try {
      await Clipboard.setData(const ClipboardData(text: _prodRegisterUrl));
    } catch (_) {}
    await launchUrl(
      Uri.parse('https://www.messenger.com/'),
      mode: LaunchMode.externalApplication,
    );
    if (mounted) {
      birToast(
        context,
        'Messenger opened! Select a contact and press Ctrl+V to paste the link.',
        kind: BirToastKind.success,
        duration: const Duration(seconds: 8),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BirDialogShell(
      title: 'Client Register QR',
      icon: Icons.qr_code_2,
      width: 500,
      child: Column(
        children: [
          SizedBox(
            width: 200,
            height: 200,
            child: FutureBuilder<Uint8List?>(
              future: _qr,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(
                    child: TpLoader(
                      strokeWidth: 2,
                      color: Brand.signal,
                    ),
                  );
                }
                final b = snap.data;
                if (b == null) {
                  return const Center(child: Icon(Icons.qr_code_2, size: 120));
                }
                return Image.memory(b, fit: BoxFit.contain);
              },
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'One static QR for sharing the BIR registration page outside the customer list table.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Color(0xFF475569)),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              BirSolidButton(
                label: 'Open Registration',
                icon: Icons.open_in_new,
                height: 40,
                onPressed: () => launchUrl(
                  _svc.pathUri('client-register?register=1'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              BirOutlineButton(
                label: 'Download QR',
                icon: Icons.download,
                onPressed: _download,
              ),
              BirOutlineButton(
                label: 'Share to Messenger',
                icon: Icons.send,
                onPressed: _share,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class BirSoftwareDialog extends StatefulWidget {
  const BirSoftwareDialog({super.key, required this.bir});
  final BirDataService bir;

  static Future<void> show(BuildContext context, BirDataService bir) =>
      showDialog<void>(
        context: context,
        builder: (_) => BirSoftwareDialog(bir: bir),
      );

  @override
  State<BirSoftwareDialog> createState() => _BirSoftwareDialogState();
}

class _BirSoftwareDialogState extends State<BirSoftwareDialog> {
  late final BirMiscService _svc = BirMiscService(widget.bir.api);
  List<BirSoftwareRow> _rows = const [];
  bool _loading = true;
  String _editId = '';
  bool _active = true;
  bool _saving = false;
  final _name = TextEditingController();
  final _version = TextEditingController();
  final _acc = TextEditingController();
  final _nameFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _version.dispose();
    _acc.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await _svc.softwareList();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      birToast(context, e.toString(), kind: BirToastKind.error);
    }
  }

  void _reset() {
    _editId = '';
    _name.clear();
    _version.clear();
    _acc.clear();
    _active = true;
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _version.text.trim().isEmpty) {
      birToast(
        context,
        'Please fill out the Software Name and Version.',
        kind: BirToastKind.warning,
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final r = await _svc.softwareSave(
        id: _editId,
        name: _name.text,
        version: _version.text,
        accNumber: _acc.text,
        active: _active,
      );
      if (!mounted) return;
      if (r['status'] != 'success') {
        final m = (r['message'] ?? '').toString();
        birToast(
          context,
          m.isEmpty ? 'Could not save the entry.' : m,
          kind: BirToastKind.error,
        );
      } else {
        birToast(
          context,
          (r['message'] ?? '').toString(),
          kind: BirToastKind.success,
        );
        setState(_reset);
        _load();
        _svc.softwareCatalog();
      }
    } catch (_) {
      if (mounted) {
        birToast(
          context,
          'Could not save the entry.',
          kind: BirToastKind.error,
        );
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _delete(BirSoftwareRow e) async {
    final ok = await birAlert(
      context,
      icon: BirAlertIcon.warning,
      title: 'Delete this entry?',
      text: '${e.name} - ${e.version}',
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
      confirmColor: const Color(0xFFDC3545),
    );
    if (!ok || !mounted) return;
    try {
      final r = await _svc.softwareDelete(e.id);
      if (!mounted) return;
      if (r['status'] != 'success') {
        final m = (r['message'] ?? '').toString();
        birToast(
          context,
          m.isEmpty ? 'Could not delete the entry.' : m,
          kind: BirToastKind.error,
        );
        return;
      }
      birToast(
        context,
        (r['message'] ?? '').toString(),
        kind: BirToastKind.success,
      );
      _load();
      _svc.softwareCatalog();
    } catch (_) {
      if (mounted) {
        birToast(
          context,
          'Could not delete the entry.',
          kind: BirToastKind.error,
        );
      }
    }
  }

  Widget _field(String label, Widget child) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: Color(0xFF475569),
        ),
      ),
      const SizedBox(height: 6),
      child,
    ],
  );

  @override
  Widget build(BuildContext context) {
    const head = TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w700,
      color: Color(0xFF212529),
    );
    final names = <String>{for (final r in _rows) r.name}.toList();
    return BirDialogShell(
      title: 'Software Accreditation',
      icon: Icons.verified_outlined,
      width: 820,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Each entry is one software category with its version and BIR accreditation number. These drive the Software Name and Software Version dropdowns in the Extracted Data Preview, and fill the accreditation number automatically.',
            style: TextStyle(fontSize: 13.5, color: Color(0xFF6C757D)),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                flex: 4,
                child: _field(
                  'Software Name',
                  RawAutocomplete<String>(
                    textEditingController: _name,
                    focusNode: _nameFocus,
                    optionsBuilder: (v) => names.where(
                      (n) => n.toLowerCase().contains(v.text.toLowerCase()),
                    ),
                    fieldViewBuilder: (ctx, ctl, focus, submit) => TextField(
                      controller: ctl,
                      focusNode: focus,
                      decoration: const InputDecoration(
                        hintText: 'e.g. TinkerPro POS - QuickServe',
                      ),
                    ),
                    optionsViewBuilder: (ctx, onSelected, options) => Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 4,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxHeight: 200,
                            maxWidth: 300,
                          ),
                          child: ListView(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            children: [
                              for (final o in options)
                                ListTile(
                                  dense: true,
                                  title: Text(o),
                                  onTap: () => onSelected(o),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: _field(
                  'Version',
                  TextField(
                    controller: _version,
                    decoration: const InputDecoration(hintText: 'e.g. V1.0'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: _field(
                  'Accreditation Number',
                  TextField(
                    controller: _acc,
                    decoration: const InputDecoration(
                      hintText: 'e.g. 0800108314172024092105',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _field(
                'Active',
                SizedBox(
                  height: 44,
                  child: Checkbox(
                    value: _active,
                    activeColor: Brand.signal,
                    onChanged: (v) => setState(() => _active = v ?? false),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              BirSolidButton(
                label: _saving
                    ? 'Saving...'
                    : (_editId.isEmpty ? 'Add' : 'Update'),
                height: 44,
                color: const Color(0xFF007BFF),
                onPressed: _saving ? null : _save,
              ),
              if (_editId.isNotEmpty) ...[
                const SizedBox(width: 6),
                BirOutlineButton(
                  label: 'Cancel',
                  height: 44,
                  onPressed: () => setState(_reset),
                ),
              ],
            ],
          ),
          const SizedBox(height: 18),
          ColumnResizeScope(
            tableId: 'bir:software',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFDEE2E6)),
                    ),
                  ),
                  child: Builder(
                    builder: (context) => Row(
                      children: resizableRowCells(
                        context,
                        [
                          Expanded(
                            flex: 4,
                            child: Text('Software Name', style: head),
                          ),
                          SizedBox(
                            width: 110,
                            child: Text('Version', style: head),
                          ),
                          SizedBox(
                            width: 220,
                            child: Text('Accreditation No.', style: head),
                          ),
                          SizedBox(
                            width: 90,
                            child: Text('Status', style: head),
                          ),
                          SizedBox(
                            width: 80,
                            child: Text(
                              'Action',
                              style: head,
                              textAlign: TextAlign.end,
                            ),
                          ),
                        ],
                        header: true,
                        extra: 20,
                      ),
                    ),
                  ),
                ),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: Text(
                        'Loading...',
                        style: TextStyle(color: Color(0xFF6C757D)),
                      ),
                    ),
                  )
                else if (_rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: Text(
                        'No software configured yet.',
                        style: TextStyle(color: Color(0xFF6C757D)),
                      ),
                    ),
                  )
                else
                  for (final e in _rows)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Color(0xFFDEE2E6)),
                        ),
                      ),
                      child: Builder(
                        builder: (context) => Row(
                          children: resizableRowCells(context, [
                            Expanded(flex: 4, child: Text(e.name)),
                            SizedBox(width: 110, child: Text(e.version)),
                            SizedBox(
                              width: 220,
                              child: Text(
                                e.accNumber.isEmpty ? '—' : e.accNumber,
                                style: const TextStyle(fontFamily: 'monospace'),
                              ),
                            ),
                            SizedBox(
                              width: 90,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: BirBadge(
                                  label: e.isActive ? 'Active' : 'Inactive',
                                  bg: e.isActive
                                      ? const Color(0xFF198754)
                                      : const Color(0xFF6C757D),
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 80,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  IconButton(
                                    tooltip: 'Edit',
                                    iconSize: 16,
                                    onPressed: () => setState(() {
                                      _editId = '${e.id}';
                                      _name.text = e.name;
                                      _version.text = e.version;
                                      _acc.text = e.accNumber;
                                      _active = e.isActive;
                                    }),
                                    icon: const Icon(
                                      Icons.edit,
                                      color: Color(0xFF007BFF),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Delete',
                                    iconSize: 16,
                                    onPressed: () => _delete(e),
                                    icon: const Icon(
                                      Icons.delete,
                                      color: Color(0xFFDC3545),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class BirFieldConfigDialog extends StatefulWidget {
  const BirFieldConfigDialog({super.key, required this.bir});
  final BirDataService bir;

  static Future<void> show(BuildContext context, BirDataService bir) =>
      showDialog<void>(
        context: context,
        builder: (_) => BirFieldConfigDialog(bir: bir),
      );

  @override
  State<BirFieldConfigDialog> createState() => _BirFieldConfigDialogState();
}

class _BirFieldConfigDialogState extends State<BirFieldConfigDialog> {
  static const _preview = [
    ('raw_text', 'OCR Extraction Log'),
    ('companyname', 'Business Name'),
    ('tin', 'TIN'),
    ('branch_code', 'Branch Code'),
    ('address', 'Business Address'),
    ('rdo', 'RDO Code'),
    ('line_of_business', 'Line of Business'),
    ('registration_type', 'Registration Type'),
    ('birthdate', 'Birthdate'),
    ('authorized_person', 'ID Holder Name'),
    ('software_name', 'Software Name'),
    ('software_version', 'Software Version'),
    ('serial_number_type', 'Serial Number Type'),
    ('server_type', 'Server Type'),
    ('serial_number', 'Serial Number'),
    ('brand', 'Brand'),
    ('model', 'Model'),
  ];
  static const _export = [
    ('TIN', 'TIN'),
    ('Branch Code', 'Branch Code'),
    ('BusinessName', 'Business Name'),
  ];

  late final BirMiscService _svc = BirMiscService(widget.bir.api);
  final Set<String> _p = {for (final f in _preview) f.$1};
  final Set<String> _e = {for (final f in _export) f.$1};
  bool _loading = true;
  bool _saving = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _svc.fieldPrefs().then((r) {
      if (!mounted) return;
      setState(() {
        if (r.hasSaved && r.preview != null) {
          final known = r.allPreview;
          _p
            ..clear()
            ..addAll(r.preview!)
            ..addAll(
              _preview
                  .map((f) => f.$1)
                  .where((f) => known != null && !known.contains(f)),
            );
        }
        if (r.hasSaved && r.export != null) {
          _e
            ..clear()
            ..addAll(r.export!);
        }
        _loading = false;
      });
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final r = await _svc.saveFieldPrefs(
      preview: [
        for (final f in _preview)
          if (_p.contains(f.$1)) f.$1,
      ],
      export: [
        for (final f in _export)
          if (_e.contains(f.$1)) f.$1,
      ],
      allPreview: [for (final f in _preview) f.$1],
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saved = true;
    });
    if (r != null && r['success'] == false && r['message'] != null) {
      birToast(context, r['message'].toString(), kind: BirToastKind.error);
    } else {
      birToast(
        context,
        'Field configuration saved. Changes will apply to the Extracted Data Preview.',
        kind: BirToastKind.success,
        duration: const Duration(seconds: 3),
      );
    }
    await Future.delayed(const Duration(milliseconds: 1000));
    if (mounted) Navigator.of(context).pop();
  }

  Widget _group(String title, List<(String, String)> items, Set<String> set) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 6),
        for (final f in items)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: Brand.signal,
            visualDensity: VisualDensity.compact,
            value: set.contains(f.$1),
            title: Text(f.$2, style: const TextStyle(fontSize: 14)),
            onChanged: (v) => setState(() {
              if (v == true) {
                set.add(f.$1);
              } else {
                set.remove(f.$1);
              }
            }),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return BirDialogShell(
      title: 'Configure Fields',
      icon: Icons.view_list,
      width: 420,
      footer: SizedBox(
        width: double.infinity,
        child: BirSolidButton(
          label: _saving
              ? 'Saving...'
              : (_saved ? 'Saved!' : 'Save Configuration'),
          icon: _saved ? Icons.check : Icons.save,
          busy: _saving,
          onPressed: (_loading || _saved) ? null : _save,
        ),
      ),
      child: _loading
          ? const Padding(
              padding: EdgeInsets.all(30),
              child: Center(
                child: TpLoader(
                  strokeWidth: 2,
                  color: Brand.signal,
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _group('Show in Extracted Data Preview', _preview, _p),
                const Divider(height: 28),
                _group('Include in CSV Export', _export, _e),
              ],
            ),
    );
  }
}
