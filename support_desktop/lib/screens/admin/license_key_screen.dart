import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../models/admin_models.dart';
import '../../services/admin_services.dart';
import '../../theme.dart';
import '../../widgets/admin_table_page.dart';
import '../../widgets/premium.dart';
import 'admin_list.dart';
import '../../widgets/tp_loader.dart';

typedef _Row = Map<String, dynamic>;

String _s(_Row r, String k) => (r[k] ?? '').toString().trim();
bool _used(_Row r) => int.tryParse(_s(r, 'is_used')) == 1;

({String group, String key, String label, String detail}) _source(_Row r) {
  final vn = _s(r, 'vendor_name');
  final vc = _s(r, 'vendor_code');
  if (vn.isNotEmpty || vc.isNotEmpty) {
    return (
      group: 'vendor',
      key: 'v:${(vc.isNotEmpty ? vc : vn).toLowerCase()}',
      label: vn.isNotEmpty ? vn : vc,
      detail: vn.isNotEmpty ? vc : '',
    );
  }
  final staff = _s(r, 'staff_name').isNotEmpty
      ? _s(r, 'staff_name')
      : _s(r, 'staff_username');
  if (staff.isNotEmpty) {
    return (
      group: 'staff',
      key: 's:${staff.toLowerCase()}',
      label: staff,
      detail: '',
    );
  }
  return (group: 'none', key: 'none', label: 'Unattributed', detail: '');
}

class LicenseKeyScreen extends StatefulWidget {
  const LicenseKeyScreen({super.key, required this.service});
  final LicenseService service;

  @override
  State<LicenseKeyScreen> createState() => _LicenseKeyScreenState();
}

class _LicenseKeyScreenState extends State<LicenseKeyScreen> {
  LicenseService get service => widget.service;
  String _status = 'all';
  String _sourceFilter = '';

  bool _matchesSource(_Row r) {
    if (_sourceFilter.isEmpty) return true;
    final src = _source(r);
    if (_sourceFilter == 'vendor' ||
        _sourceFilter == 'staff' ||
        _sourceFilter == 'none') {
      return src.group == _sourceFilter;
    }
    return src.key == _sourceFilter;
  }

  Future<Paged<_Row>> _fetch(String _) async {
    final res = await service.api.get('getLicenseKey');
    final raw = res['data'];
    final rows = raw is List
        ? raw.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
        : <_Row>[];
    return Paged(items: rows, total: rows.length);
  }

  List<DropdownMenuItem<String>> _sourceOptions(List<_Row> rows) {
    final vendors = <String, ({String label, int total})>{};
    final staff = <String, ({String label, int total})>{};
    final counts = {'vendor': 0, 'staff': 0, 'none': 0};
    for (final r in rows) {
      final s = _source(r);
      counts[s.group] = counts[s.group]! + 1;
      if (s.group == 'none') continue;
      final bucket = s.group == 'vendor' ? vendors : staff;
      final label = s.detail.isNotEmpty ? '${s.label} · ${s.detail}' : s.label;
      bucket[s.key] = (label: label, total: (bucket[s.key]?.total ?? 0) + 1);
    }
    DropdownMenuItem<String> opt(
      String v,
      String t,
      int n, {
      bool group = false,
    }) => DropdownMenuItem(
      value: v,
      child: Text(
        '$t ($n)',
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          fontWeight: group ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
    final out = <DropdownMenuItem<String>>[opt('', 'All sources', rows.length)];
    void section(
      Map<String, ({String label, int total})> b,
      String all,
      String allText,
      int total,
    ) {
      if (b.isEmpty) return;
      out.add(opt(all, allText, total, group: true));
      final keys = b.keys.toList()
        ..sort((a, c) => b[a]!.label.compareTo(b[c]!.label));
      for (final k in keys) {
        out.add(opt(k, '   ${b[k]!.label}', b[k]!.total));
      }
    }

    section(vendors, 'vendor', 'All vendors', counts['vendor']!);
    section(staff, 'staff', 'All staff', counts['staff']!);
    if (counts['none']! > 0) {
      out.add(opt('none', 'Unattributed', counts['none']!));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return AdminTablePage<_Row>(
      stationNumber: '08',
      stationLabel: 'LICENSE KEY',
      title: 'License Keys',
      addLabel: 'New license',
      searchHint: 'Search keys or stores...',
      pageSizes: const [25, 50, 100],
      rowMinHeight: 45,
      liveKeys: const ['licensekey'],
      fetch: _fetch,
      filterKey: '$_status|$_sourceFilter',
      rowFilter: (r) {
        if (!_matchesSource(r)) return false;
        if (_status == 'used') return _used(r);
        if (_status == 'unused') return !_used(r);
        return true;
      },
      localFilter: (r, q) {
        final status = _s(r, 'superseded_by_key').isNotEmpty
            ? 'superseded replaced'
            : (_used(r) ? 'activated' : 'available');
        return [
          _s(r, 'store_name'),
          _s(r, 'store_email'),
          _s(r, 'store_address'),
          _s(r, 'license_key'),
          _s(r, 'machine_type'),
          _s(r, 'computer_name'),
          _s(r, 'serial_number'),
          _s(r, 'superseded_by_key'),
          _s(r, 'replaces_license_key'),
          status,
        ].any((s) => s.toLowerCase().contains(q));
      },
      onAdd: (ctx, refresh) => _edit(ctx, refresh),
      onRowTap: (ctx, r, refresh) =>
          _edit(ctx, refresh, existing: LicenseKey.fromJson(r)),
      summary: (ctx, items, total, search) {
        final data = items.where(_matchesSource).toList();
        final used = data.where(_used).length;
        final unused = data.length - used;
        String pad(int n) => n.toString().padLeft(2, '0');
        final opts = _sourceOptions(items);
        if (!opts.any((o) => o.value == _sourceFilter)) _sourceFilter = '';
        return AdminTicker(
          items: [
            AdminTickerItem(
              'Total registry',
              pad(data.length),
              Icons.vpn_key,
              Brand.info,
            ),
            AdminTickerItem(
              'Activated',
              pad(used),
              Icons.check_circle,
              Brand.success,
            ),
            AdminTickerItem(
              'Available',
              pad(unused),
              Icons.hourglass_bottom,
              Brand.warning,
            ),
          ],
          trailing: [
            const Icon(
              Icons.admin_panel_settings_outlined,
              size: 15,
              color: AdminTableColors.headerText,
            ),
            const Text(
              'GENERATED BY',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: AdminTableColors.headerText,
              ),
            ),
            Container(
              width: 240,
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AdminTableColors.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _sourceFilter,
                  isExpanded: true,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AdminTableColors.text,
                  ),
                  items: opts,
                  onChanged: (v) => setState(() => _sourceFilter = v ?? ''),
                ),
              ),
            ),
            const SizedBox(width: 20),
            const Icon(
              Icons.filter_alt,
              size: 14,
              color: AdminTableColors.headerText,
            ),
            const Text(
              'STATUS',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: AdminTableColors.headerText,
              ),
            ),
            AdminChip(
              label: 'All',
              count: '${data.length}',
              active: _status == 'all',
              onTap: () => setState(() => _status = 'all'),
            ),
            AdminChip(
              label: 'Available',
              count: '$unused',
              active: _status == 'unused',
              onTap: () => setState(() => _status = 'unused'),
            ),
            AdminChip(
              label: 'Activated',
              count: '$used',
              active: _status == 'used',
              onTap: () => setState(() => _status = 'used'),
            ),
          ],
        );
      },
      searchInToolbar: true,
      columns: [
        AdminColumn(
          'Business / Entity Name',
          flex: 4,
          sortValue: (r) => _s(r as _Row, 'store_name'),
        ),
        AdminColumn(
          'Address',
          flex: 3,
          sortValue: (r) => _s(r as _Row, 'store_address'),
        ),
        AdminColumn(
          'Secure Key',
          flex: 3,
          sortValue: (r) => _s(r as _Row, 'license_key'),
        ),
        AdminColumn(
          'Serial Number',
          width: 170,
          sortValue: (r) => _s(r as _Row, 'serial_number'),
        ),
        AdminColumn(
          'Generated By',
          width: 190,
          sortValue: (r) => _source(r as _Row).label,
        ),
        AdminColumn(
          'Provision',
          width: 180,
          sortValue: (r) => _s(r as _Row, 'trial'),
        ),
        AdminColumn(
          'Status',
          width: 150,
          center: true,
          sortValue: (r) => _s(r as _Row, 'is_used'),
        ),
        const AdminColumn('Action', width: 110, center: true, sortable: false),
      ],
      cells: (ctx, r, refresh) {
        final name = _s(r, 'store_name');
        final email = _s(r, 'store_email');
        final src = _source(r);
        final trial = int.tryParse(_s(r, 'trial')) == 1;
        final exp = _s(r, 'date_expired');
        final superseded = _s(r, 'superseded_by_key');
        final replaces = _s(r, 'replaces_license_key');
        final used = _used(r);
        return [
          Row(
            children: [
              Flexible(
                child: AdminCellText(name.isEmpty ? 'TINKERPRO_CORE' : name),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  email.isEmpty ? 'no-reply@protocol.com' : email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AdminTableColors.muted,
                  ),
                ),
              ),
            ],
          ),
          _s(r, 'store_address').isEmpty
              ? const AdminCellText('', muted: true)
              : AdminCellText(_s(r, 'store_address'), size: 13.5),
          _KeyCell(licenseKey: _s(r, 'license_key')),
          AdminCellText(_s(r, 'serial_number')),
          src.group == 'none'
              ? const AdminCellText('', muted: true)
              : Row(
                  children: [
                    AdminBadge(
                      src.group == 'vendor' ? 'Vendor' : 'Staff',
                      color: src.group == 'vendor' ? Brand.info : Brand.success,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: AdminCellText(src.label, bold: true, size: 13.5),
                    ),
                  ],
                ),
          Row(
            children: [
              AdminBadge(
                trial ? 'Temporary' : 'Permanent',
                color: trial ? Brand.info : Brand.success,
              ),
              if (trial) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Ends: ${exp.isEmpty ? 'PERPETUAL' : adminFormatDate(exp)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AdminTableColors.muted,
                    ),
                  ),
                ),
              ],
            ],
          ),
          Tooltip(
            message: superseded.isNotEmpty
                ? 'Replaced by $superseded'
                : (replaces.isNotEmpty ? 'Upgraded from $replaces' : ''),
            child: superseded.isNotEmpty
                ? const AdminBadge(
                    'Superseded',
                    color: AdminTableColors.headerText,
                  )
                : AdminBadge(
                    used ? 'Activated' : 'Available',
                    color: used ? Brand.danger : Brand.success,
                  ),
          ),
          AdminRowMenu(
            actions: [
              AdminMenuAction(
                'Modify Provision',
                Icons.edit_outlined,
                () => _edit(ctx, refresh, existing: LicenseKey.fromJson(r)),
              ),
              AdminMenuAction(
                'Purge Record',
                Icons.delete_outline,
                () => _delete(ctx, refresh, LicenseKey.fromJson(r)),
                danger: true,
              ),
            ],
          ),
        ];
      },
    );
  }

  Future<void> _delete(
    BuildContext context,
    VoidCallback refresh,
    LicenseKey k,
  ) async {
    if (!await confirmDialog(
      context,
      title: 'Revoke this license key?',
      message:
          'The license key will be permanently purged from the registry and can no longer be used.',
      confirmLabel: 'Revoke license',
    )) {
      return;
    }
    if (!context.mounted) return;
    adminUndoDelete(
      context,
      message: 'License Registry Purged',
      commit: () async {
        final res = await service.delete(k.id);
        if (!res.ok && context.mounted) toast(context, 'Purge Failed');
        refresh();
      },
    );
  }

  Future<void> _edit(
    BuildContext context,
    VoidCallback refresh, {
    LicenseKey? existing,
  }) async {
    Map<String, dynamic>? rec;
    if (existing != null) {
      rec = await service.getById(existing.id);
      if (!context.mounted) return;
      if (rec == null) {
        toast(context, 'Provision Failed');
        return;
      }
    }
    await showDialog<void>(
      context: context,
      builder: (_) => _LicenseProvisionDialog(
        service: service,
        record: rec,
        onSaved: refresh,
      ),
    );
  }
}

String _fmtRegistry(String v) {
  if (v.trim().isEmpty) return '\u2014';
  final f = adminFormatDate(v, withTime: v.contains(':'));
  return f.isEmpty ? '\u2014' : f;
}

class _LicenseProvisionDialog extends StatefulWidget {
  const _LicenseProvisionDialog({
    required this.service,
    required this.record,
    required this.onSaved,
  });
  final LicenseService service;
  final Map<String, dynamic>? record;
  final VoidCallback onSaved;

  @override
  State<_LicenseProvisionDialog> createState() =>
      _LicenseProvisionDialogState();
}

class _LicenseProvisionDialogState extends State<_LicenseProvisionDialog> {
  Map<String, dynamic>? get rec => widget.record;
  bool get isEdit => rec != null;
  String _r(String k) => (rec?[k] ?? '').toString();

  late final _key = TextEditingController(text: _r('license_key'));
  late final _serial = TextEditingController(text: _r('serial_number'));
  late final _computer = TextEditingController(text: _r('computer_name'));
  late final _exp = TextEditingController(
    text: _r('trial') == '1' ? _r('date_expired') : '',
  );
  late final _storeName = TextEditingController(text: _r('store_name'));
  late final _storeAddr = TextEditingController(text: _r('store_address'));
  late final _storeEmail = TextEditingController(text: _r('store_email'));
  late final String _machine = _r('machine_type');
  late String _type = isEdit ? (_r('trial') == '1' ? '1' : '0') : '';
  late final int _origStatus = int.tryParse(_r('is_used')) == 1 ? 1 : 0;
  late final int _origTrial = _r('trial') == '1' ? 1 : 0;
  late String _status = isEdit ? '$_origStatus' : '0';
  bool _generating = false;
  bool _submitting = false;
  String? _keyError;
  String? _typeError;

  @override
  void dispose() {
    for (final c in [
      _key,
      _serial,
      _computer,
      _exp,
      _storeName,
      _storeAddr,
      _storeEmail,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() => _generating = true);
    try {
      final res = await widget.service.generateKey();
      if (!mounted) return;
      if (res.key != null) {
        _key.text = res.key!;
        _keyError = null;
      } else {
        toast(
          context,
          res.message.isNotEmpty ? res.message : 'Could not generate a key',
        );
      }
    } catch (e) {
      if (mounted) toast(context, 'An error occurred: $e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  ({String hint, IconData icon, Color tone}) _statusHint() {
    var icon = Icons.info_outline;
    Color tone = Brand.info;
    String hint;
    if (_origStatus == 1 && _status == '0') {
      tone = Brand.warning;
      icon = Icons.lock_open;
      hint =
          'On save this key is released: the activation date is cleared and it can be activated again on another terminal.';
    } else if (_origStatus == 0 && _status == '1') {
      tone = Brand.danger;
      icon = Icons.lock;
      hint =
          'On save this key is marked consumed \u2014 the next activation attempt will be rejected.';
    } else if (_status == '1') {
      hint = 'Currently consumed. Pick AVAILABLE to release it for reuse.';
    } else {
      hint = 'Currently free to activate. No status change.';
    }
    final nowTrial = _type == '1' ? 1 : 0;
    if (_origTrial == 1 && nowTrial == 0) {
      tone = Brand.warning;
      icon = Icons.all_inclusive;
      hint +=
          ' It also stops being temporary: the end of service date is cleared and the key never expires.';
    } else if (_origTrial == 0 && nowTrial == 1) {
      tone = Brand.warning;
      icon = Icons.hourglass_bottom;
      hint +=
          ' It also becomes temporary \u2014 set an end of service date, or it will never expire anyway.';
    }
    return (hint: hint, icon: icon, tone: tone);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _keyError = _key.text.trim().isEmpty ? 'Please fill out this field.' : null;
      _typeError = _type.isEmpty ? 'Please select an item in the list.' : null;
    });
    if (_keyError != null || _typeError != null) return;
    setState(() => _submitting = true);
    final form = <String, String>{
      'license_id': isEdit ? _r('id') : '',
      'license_key': _key.text,
      'serial_number': _serial.text,
      'computer_name': _computer.text,
      'machine_type': _machine,
      'license_type': _type,
      'expiration_date': _exp.text,
      'store_name': _storeName.text,
      'store_address': _storeAddr.text,
      'store_email': _storeEmail.text,
      'license_status': _status,
    };
    try {
      final res = await widget.service.save(form);
      if (!mounted) return;
      if (res.ok) {
        toast(context, 'License Provision Successful');
        Navigator.of(context).pop();
        widget.onSaved();
      } else {
        toast(
          context,
          res.message.isNotEmpty ? res.message : 'Provision Failed',
        );
      }
    } catch (e) {
      if (mounted) toast(context, 'An error occurred: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _card(String title, String sub, IconData icon, List<Widget> body) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AdminTableColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Brand.signal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: Brand.signal),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AdminTableColors.text,
                        ),
                      ),
                      Text(
                        sub,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AdminTableColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AdminTableColors.cellRule),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: body,
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, Widget child, {String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AdminTableColors.headerText,
            ),
          ),
          const SizedBox(height: 6),
          child,
          if (hint != null) ...[
            const SizedBox(height: 5),
            Text(
              hint,
              style: const TextStyle(
                fontSize: 11.5,
                color: AdminTableColors.muted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusChoice(String value, String title, String desc, IconData icon,
      Color color) {
    final active = _status == value;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => _status = value),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: active ? color.withValues(alpha: 0.08) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? color : AdminTableColors.border,
              width: active ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                    Text(
                      desc,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AdminTableColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _aside() {
    final superseded = _r('superseded_by_key');
    final replaces = _r('replaces_license_key');
    final hint = _statusHint();
    Widget meta(String k, String v) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              k,
              style: const TextStyle(
                fontSize: 12,
                color: AdminTableColors.muted,
              ),
            ),
          ),
          Flexible(
            child: Text(
              v,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AdminTableColors.text,
              ),
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AdminSectionTitle('Provision Record', icon: Icons.history),
        meta('Generated on', _fmtRegistry(_r('created_at'))),
        meta(
          'Activated on',
          _origStatus == 1 ? _fmtRegistry(_r('used_at')) : 'Not activated',
        ),
        if (superseded.isNotEmpty)
          meta('Superseded by', superseded)
        else if (replaces.isNotEmpty)
          meta('Replaces', replaces),
        const SizedBox(height: 6),
        const AdminSectionTitle('Provision Status', icon: Icons.shield_outlined),
        Row(
          children: [
            _statusChoice(
              '0',
              'AVAILABLE',
              'Free to activate on a terminal',
              Icons.lock_open,
              Brand.success,
            ),
            const SizedBox(width: 8),
            _statusChoice(
              '1',
              'ACTIVATED',
              'Consumed \u2014 in use by a client',
              Icons.lock,
              Brand.danger,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: hint.tone.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: hint.tone.withValues(alpha: 0.3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(hint.icon, size: 15, color: hint.tone),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hint.hint,
                  style: const TextStyle(fontSize: 12, height: 1.35),
                ),
              ),
            ],
          ),
        ),
        if (_origTrial == 1) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AdminTableColors.header,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AdminTableColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'This is a temporary provision. Keep the same key, drop its end of service date and hand it back to the shop as a permanent one.',
                  style: TextStyle(fontSize: 12, height: 1.35),
                ),
                const SizedBox(height: 10),
                GhostButton(
                  label: 'MAKE PERMANENT & AVAILABLE',
                  icon: Icons.all_inclusive,
                  onPressed: () => setState(() {
                    _type = '0';
                    _exp.clear();
                    _status = '0';
                  }),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final used = _origStatus == 1;
    final superseded = _r('superseded_by_key').isNotEmpty;
    final main = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(
          'Key Configuration',
          'The identity a POS terminal sends when it activates.',
          Icons.fingerprint,
          [
            _field(
              'License Key Identifier',
              TextField(
                controller: _key,
                autofocus: !isEdit,
                style: const TextStyle(fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: 'TP-XXXX-XXXX-XXXX-XXXX',
                  errorText: _keyError,
                  suffixIcon: IconButton(
                    tooltip: 'Generate a secure key',
                    icon: _generating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: TpLoader(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync, size: 18),
                    onPressed: _generating ? null : _generate,
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
              hint:
                  'Must be unique \u2014 the POS terminal sends this exact string to activate.',
            ),
            if (isEdit) ...[
              _field(
                'Serial Number',
                TextField(
                  controller: _serial,
                  decoration: const InputDecoration(
                    hintText: 'Terminal serial(s)',
                  ),
                ),
              ),
              _field(
                'Computer Name',
                TextField(
                  controller: _computer,
                  maxLength: 150,
                  decoration: const InputDecoration(
                    hintText: 'e.g. CASHIER-01',
                    counterText: '',
                  ),
                ),
                hint:
                    'Sent by the POS when it activates. Edit only if it is wrong.',
              ),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _field(
                    'Provision Type',
                    DropdownButtonFormField<String>(
                      initialValue: _type.isEmpty ? null : _type,
                      key: ValueKey('type-$_type'),
                      hint: const Text('Select Type...'),
                      decoration: InputDecoration(errorText: _typeError),
                      items: const [
                        DropdownMenuItem(
                          value: '1',
                          child: Text('Temporary / Trial'),
                        ),
                        DropdownMenuItem(
                          value: '0',
                          child: Text('Permanent / Perpetual'),
                        ),
                      ],
                      onChanged: (v) => setState(() {
                        _type = v ?? '';
                        _typeError = null;
                        if (_type != '1') _exp.clear();
                      }),
                    ),
                  ),
                ),
                if (_type == '1') ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: _field(
                      'End of Service Date',
                      AdminDateField(controller: _exp, lastYearOffset: 10),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        if (isEdit)
          _card(
            'Registrant Details',
            'Who this provision is issued to.',
            Icons.store_outlined,
            [
              _field(
                'Registrant Entity',
                TextField(
                  controller: _storeName,
                  autofocus: true,
                  decoration: const InputDecoration(hintText: 'Entity name'),
                ),
              ),
              _field(
                'Headquarters Address',
                TextField(
                  controller: _storeAddr,
                  decoration: const InputDecoration(
                    hintText: 'Physical location',
                  ),
                ),
              ),
              _field(
                'Protocol Email',
                TextField(
                  controller: _storeEmail,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    hintText: 'contact@entity.com',
                  ),
                ),
              ),
            ],
          ),
      ],
    );
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isEdit ? 980 : 560,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              color: const Color(0xFF0F172A),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.vpn_key_outlined,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'LICENSE REGISTRY',
                          style: TextStyle(
                            fontSize: 10.5,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w700,
                            color: Colors.white60,
                          ),
                        ),
                        Text(
                          isEdit ? 'Update Provision' : 'New License Provision',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isEdit) ...[
                    Text(
                      _r('license_key'),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12.5,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(width: 8),
                    AdminBadge(
                      superseded
                          ? 'SUPERSEDED'
                          : (used ? 'ACTIVATED' : 'AVAILABLE'),
                      color: superseded
                          ? AdminTableColors.headerText
                          : (used ? Brand.danger : Brand.success),
                    ),
                  ],
                  IconButton(
                    tooltip: 'Close dialog',
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: isEdit
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 3, child: main),
                          const SizedBox(width: 20),
                          Expanded(flex: 2, child: _aside()),
                        ],
                      )
                    : main,
              ),
            ),
            const Divider(height: 1, color: AdminTableColors.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Row(
                children: [
                  Icon(
                    isEdit ? Icons.bolt : Icons.lock_open,
                    size: 14,
                    color: AdminTableColors.muted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isEdit
                          ? 'Changes apply immediately'
                          : 'New keys start as AVAILABLE',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AdminTableColors.muted,
                      ),
                    ),
                  ),
                  GhostButton(
                    label: 'DISCARD',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 10),
                  SignalButton(
                    label: _submitting
                        ? 'Authorizing...'
                        : (isEdit ? 'SAVE CHANGES' : 'AUTHORIZE KEY'),
                    icon: Icons.check,
                    onPressed: _submitting ? null : _submit,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KeyCell extends StatelessWidget {
  const _KeyCell({required this.licenseKey});
  final String licenseKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              border: Border.all(color: const Color(0xFFEEEEEE)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              licenseKey,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                color: AdminTableColors.text,
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Copy key',
          visualDensity: VisualDensity.compact,
          iconSize: 16,
          icon: Icon(Icons.copy, color: context.brand.paperDim),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: licenseKey));
            if (context.mounted) toast(context, 'Secure key copied');
          },
        ),
      ],
    );
  }
}
