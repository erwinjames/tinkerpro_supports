import 'dart:async';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api_client.dart';
import '../../services/live_sync.dart';
import '../../services/taxpayer_portal_service.dart';
import '../../theme.dart';
import '../../widgets/premium.dart';
import 'portal_ui.dart';
import '../../widgets/tp_loader.dart';

const _ok = Color(0xFF16A34A);
const _warn = Color(0xFFD97706);
const _muted = Color(0xFF64748B);
const _bad = Color(0xFFDC2626);

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

String _fmtDate(String raw) {
  if (raw.isEmpty) return '';
  final d = DateTime.tryParse(raw.replaceFirst(' ', 'T'));
  if (d == null) return '';
  return '${d.day} ${_months[d.month - 1]} ${d.year}';
}

String _initials(String text) {
  final parts = text
      .replaceAll(RegExp(r'[^A-Za-z0-9 ]'), ' ')
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'TP';
  if (parts.length == 1) {
    final p = parts.first;
    return (p.length > 1 ? p.substring(0, 2) : p).toUpperCase();
  }
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

Color _stageColor(String key) {
  switch (key) {
    case 'completed':
      return _ok;
    case 'awaiting':
    case 'processed':
      return _warn;
    default:
      return _muted;
  }
}

void _toast(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), backgroundColor: error ? _bad : null),
  );
}

Future<bool> _confirm(
  BuildContext context,
  String title,
  String message,
  String action,
) async {
  final ok = await showWebModal<bool>(
    context,
    title: title,
    icon: Icons.help_outline,
    width: 460,
    builder: (ctx) => Text(message, style: Theme.of(ctx).textTheme.bodyMedium),
    actions: (ctx) => [
      GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx, false)),
      DangerButton(label: action, onPressed: () => Navigator.pop(ctx, true)),
    ],
  );
  return ok ?? false;
}

class _UnderlineTab extends StatelessWidget {
  const _UnderlineTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Brand.signal : context.brand.paperDim;
    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? Brand.signal : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? Brand.signal : context.brand.paper,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.label, this.color, {this.icon});
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.child, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: context.brand.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.brand.rule),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.text, {this.size = 40});
  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Brand.signal.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size / 4),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Brand.signal,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.34,
        ),
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();
  @override
  Widget build(BuildContext context) => const Center(child: TpLoader());
}

class _ErrorView extends StatelessWidget {
  const _ErrorView(this.message, this.onRetry);
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 30, color: context.brand.paperDim),
          const SizedBox(height: 8),
          Text(
            'Could not load',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          SignalButton(label: 'Retry', icon: Icons.refresh, onPressed: onRetry),
        ],
      ),
    );
  }
}

class _PwField extends StatefulWidget {
  const _PwField({
    required this.controller,
    required this.label,
    this.onChanged,
  });
  final TextEditingController controller;
  final String label;
  final ValueChanged<String>? onChanged;

  @override
  State<_PwField> createState() => _PwFieldState();
}

class _PwFieldState extends State<_PwField> {
  bool _show = false;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: !_show,
      maxLength: 100,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        labelText: widget.label,
        isDense: true,
        counterText: '',
        suffixIcon: IconButton(
          tooltip: _show ? 'Hide password' : 'Show password',
          icon: Icon(_show ? Icons.visibility_off : Icons.visibility, size: 18),
          onPressed: () => setState(() => _show = !_show),
        ),
      ),
    );
  }
}

class TaxpayerPortalScreen extends StatelessWidget {
  const TaxpayerPortalScreen({
    super.key,
    required this.api,
    required this.canManage,
  });
  final ApiClient api;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    return canManage ? _ManageView(api: api) : _StaffView(api: api);
  }
}

class _ManageView extends StatefulWidget {
  const _ManageView({required this.api});
  final ApiClient api;

  @override
  State<_ManageView> createState() => _ManageViewState();
}

class _ManageViewState extends State<_ManageView>
    with LiveRefresh<_ManageView> {
  late final TaxpayerPortalService _svc = TaxpayerPortalService(widget.api);
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  String _q = '';
  String _filter = 'all';
  int _page = 1;
  int _perPage = 25;
  int _total = 0;
  bool _loading = true;
  String? _error;
  List<TpRow> _rows = const [];
  TpStats _stats = const TpStats();
  int _seq = 0;

  static const _filters = [
    ('all', 'All'),
    ('password', 'Password set'),
    ('tin_only', 'TIN only'),
    ('employees', 'Has employees'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  List<String> get liveKeys => const ['taxpayerportal'];

  @override
  void onLiveChange() => _load(silent: true);

  Future<void> _load({bool silent = false}) async {
    final mine = ++_seq;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final r = await _svc.list(q: _q, filter: _filter, page: _page);
      if (!mounted || mine != _seq) return;
      setState(() {
        _rows = r.rows;
        _total = r.total;
        _perPage = r.perPage;
        _stats = r.stats;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || mine != _seq) return;
      if (silent) {
        if (_loading) setState(() => _loading = false);
        return;
      }
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _q = v.trim();
      _page = 1;
      _load();
    });
  }

  Future<void> _openPortal(int id) => _showPortalModal(context, _svc, id);

  Future<void> _openManage(int id) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _ManagePanel(
        service: _svc,
        customerId: id,
        onClose: () => Navigator.of(ctx).maybePop(),
        onChanged: () => _load(silent: true),
        onOpenPortal: () => _showPortalModal(ctx, _svc, id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final from = _total == 0 ? 0 : (_page - 1) * _perPage + 1;
    final to = (_page * _perPage) < _total ? _page * _perPage : _total;
    return PortalPage(
      onRefresh: _load,
      children: [
        PortalHeader(
          eyebrow: 'Clients · Super admin',
          title: 'Taxpayer Portal',
          sub:
              "Manage every taxpayer's portal access: the owner's sign-in password and the employees they gave access to. Every change is recorded in Activity Logs.",
          trailing: PortalStats(
            items: [
              ('${_stats.taxpayers}', 'Taxpayers'),
              ('${_stats.withPassword}', 'Owners with a password'),
              ('${_stats.employeesActive}', 'Active employees'),
              ('${_stats.employeesInvited}', 'Pending invites'),
            ],
          ),
        ),
        Row(
          children: [
            Expanded(
              child: PortalSearch(
                controller: _searchCtrl,
                onChanged: _onSearch,
                hint: 'Search company, owner, TIN, email or employee',
              ),
            ),
            const SizedBox(width: 10),
            for (var i = 0; i < _filters.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              PortalTab(
                label: _filters[i].$2,
                selected: _filter == _filters[i].$1,
                onTap: () {
                  if (_filter == _filters[i].$1) return;
                  setState(() => _filter = _filters[i].$1);
                  _page = 1;
                  _load();
                },
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        PortalCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) _ErrorView(_error!, _load) else _table(),
              PortalPager(
                info: '$from–$to of $_total',
                onPrev: _page <= 1
                    ? null
                    : () {
                        _page--;
                        _load();
                      },
                onNext: to >= _total
                    ? null
                    : () {
                        _page++;
                        _load();
                      },
              ),
            ],
          ),
        ),
      ],
    );
  }

  PortalTone _stageTone(String key) {
    switch (key) {
      case 'completed':
        return PortalTone.ok;
      case 'awaiting':
      case 'processed':
        return PortalTone.warn;
      default:
        return PortalTone.muted;
    }
  }

  Widget _table() {
    final meta = portalMeta(context);
    final name = portalName(context);
    final cell = portalCell(context);
    return PortalTable(
      tableId: 'portal:taxpayer',
      loading: _loading,
      empty: 'No taxpayers match this search.',
      onRowTap: (i) => _openManage(_rows[i].id),
      columns: const [
        PortalCol('Taxpayer', flex: 16),
        PortalCol('TIN / Branch', flex: 20),
        PortalCol('Owner sign-in', flex: 22),
        PortalCol('Employees', flex: 17),
        PortalCol('Registration', flex: 16),
        PortalCol('Actions', right: true, width: 190),
      ],
      rows: [
        for (final r in _rows)
          [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.companyName.isEmpty ? '—' : r.companyName,
                  overflow: TextOverflow.ellipsis,
                  style: name,
                ),
                Text(
                  '${r.ownerName.isEmpty ? 'No owner name' : r.ownerName}${r.email.isNotEmpty ? ' · ${r.email}' : ''}',
                  overflow: TextOverflow.ellipsis,
                  style: meta,
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.tin.isEmpty ? '—' : r.tin, style: cell),
                Text(
                  'Branch ${r.branchCode.isEmpty ? '00000' : r.branchCode}',
                  style: meta,
                ),
              ],
            ),
            r.ownerPasswordSet
                ? const PortalPill(
                    'Password set',
                    PortalTone.ok,
                    icon: Icons.lock,
                  )
                : const PortalPill(
                    'TIN only',
                    PortalTone.warn,
                    icon: Icons.lock_open,
                  ),
            r.employeesTotal > 0
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: '${r.employeesActive}', style: name),
                            TextSpan(text: ' active', style: cell),
                          ],
                        ),
                      ),
                      Text('${r.employeesTotal} total', style: meta),
                    ],
                  )
                : Text('None', style: meta),
            PortalPill(r.stage.label, _stageTone(r.stage.key)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PortalButton(
                  primary: true,
                  onPressed: () => _openManage(r.id),
                  icon: Icons.manage_accounts,
                  label: 'Manage',
                ),
                const SizedBox(width: 6),
                PortalButton(
                  tooltip: "Open this taxpayer's portal",
                  icon: Icons.open_in_new,
                  label: '',
                  onPressed: () => _openPortal(r.id),
                ),
              ],
            ),
          ],
      ],
    );
  }
}

Future<void> _showPortalModal(
  BuildContext context,
  TaxpayerPortalService service,
  int customerId,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => _PortalRoute(service: service, customerId: customerId),
  );
}

class _ManagePanel extends StatefulWidget {
  const _ManagePanel({
    required this.service,
    required this.customerId,
    required this.onClose,
    required this.onChanged,
    required this.onOpenPortal,
  });
  final TaxpayerPortalService service;
  final int customerId;
  final VoidCallback onClose;
  final VoidCallback onChanged;
  final VoidCallback onOpenPortal;

  @override
  State<_ManagePanel> createState() => _ManagePanelState();
}

class _ManagePanelState extends State<_ManagePanel>
    with LiveRefresh<_ManagePanel> {
  TpDetail? _t;
  String? _error;
  String _tab = 'owner';
  bool _busy = false;
  int? _busyEmp;

  final _ownerPw = TextEditingController();
  final _ownerConfirm = TextEditingController();
  String _ownerError = '';

  String? _formMode;
  TpEmployee? _formEmp;
  final _empName = TextEditingController();
  final _empEmail = TextEditingController();
  final _empPosition = TextEditingController();
  final _empPw = TextEditingController();
  final _empConfirm = TextEditingController();
  String _empError = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _ownerPw,
      _ownerConfirm,
      _empName,
      _empEmail,
      _empPosition,
      _empPw,
      _empConfirm,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  List<String> get liveKeys => const ['taxpayerportal'];

  @override
  void onLiveChange() => _liveReload();

  Future<void> _liveReload() async {
    if (_busy || _t == null || _error != null) return;
    try {
      final t = await widget.service.detail(widget.customerId);
      if (!mounted || _busy || _error != null) return;
      setState(() => _t = t);
    } catch (e) {
      if (!mounted) return;
      if (!e.toString().toLowerCase().contains('not found')) return;
      setState(() => _error = 'This taxpayer was removed.');
    }
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final t = await widget.service.detail(widget.customerId);
      if (!mounted) return;
      setState(() => _t = t);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<bool> _run(
    Future<TpActionResult> Function() call, {
    void Function(String)? onError,
    int? empId,
  }) async {
    setState(() {
      _busy = true;
      _busyEmp = empId;
    });
    try {
      final res = await call();
      if (!mounted) return false;
      if (res.detail != null) setState(() => _t = res.detail);
      if (!res.success) {
        if (onError != null) {
          onError(res.message);
        } else {
          _toast(context, res.message, error: true);
        }
        return false;
      }
      _toast(context, res.message);
      widget.onChanged();
      return true;
    } catch (e) {
      if (!mounted) return false;
      final msg = e.toString().replaceFirst('Exception: ', '');
      if (onError != null) {
        onError(msg);
      } else {
        _toast(context, msg, error: true);
      }
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyEmp = null;
        });
      }
    }
  }

  Future<void> _saveOwner() async {
    final t = _t;
    if (t == null) return;
    final err = portalPasswordError(_ownerPw.text, _ownerConfirm.text);
    if (err.isNotEmpty) {
      setState(() => _ownerError = err);
      return;
    }
    setState(() => _ownerError = '');
    final ok = await _run(
      () => widget.service.setOwnerPassword(
        t.id,
        _ownerPw.text,
        _ownerConfirm.text,
      ),
      onError: (m) => setState(() => _ownerError = m),
    );
    if (ok) {
      _ownerPw.clear();
      _ownerConfirm.clear();
      setState(() {});
    }
  }

  Future<void> _clearOwner() async {
    final t = _t;
    if (t == null) return;
    if (!await _confirm(
      context,
      'Remove password',
      'Remove the owner password? They will sign in with the TIN only and be asked to set a new one.',
      'Remove password',
    )) {
      return;
    }
    await _run(() => widget.service.clearOwnerPassword(t.id));
  }

  void _showForm(String mode, TpEmployee? emp) {
    setState(() {
      _formMode = mode;
      _formEmp = emp;
      _empError = '';
      _empName.text = mode == 'edit' ? (emp?.fullName ?? '') : '';
      _empEmail.text = mode == 'edit' ? (emp?.email ?? '') : '';
      _empPosition.text = mode == 'edit' ? (emp?.position ?? '') : '';
      _empPw.clear();
      _empConfirm.clear();
    });
  }

  void _hideForm() => setState(() {
    _formMode = null;
    _formEmp = null;
  });

  Future<void> _submitForm() async {
    final t = _t;
    final mode = _formMode;
    if (t == null || mode == null) return;
    void onError(String m) => setState(() => _empError = m);
    if (mode == 'password') {
      final err = portalPasswordError(_empPw.text, _empConfirm.text);
      if (err.isNotEmpty) {
        onError(err);
        return;
      }
      setState(() => _empError = '');
      final ok = await _run(
        () => widget.service.setEmployeePassword(
          t.id,
          _formEmp!.id,
          _empPw.text,
          _empConfirm.text,
        ),
        onError: onError,
      );
      if (ok) _hideForm();
      return;
    }
    final name = _empName.text.trim();
    final email = _empEmail.text.trim();
    if (name.length < 2) {
      onError('Enter the employee name.');
      return;
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      onError('Enter a valid email address.');
      return;
    }
    setState(() => _empError = '');
    final pos = _empPosition.text.trim();
    final ok = await _run(
      () => mode == 'edit'
          ? widget.service.updateEmployee(t.id, _formEmp!.id, name, email, pos)
          : widget.service.inviteEmployee(t.id, name, email, pos),
      onError: onError,
    );
    if (ok) _hideForm();
  }

  Future<void> _empOp(String op, TpEmployee e) async {
    final t = _t;
    if (t == null) return;
    if (op == 'edit' || op == 'password') {
      _showForm(op, e);
      return;
    }
    if (op == 'remove' &&
        !await _confirm(
          context,
          'Remove employee',
          'Remove ${e.fullName}? They lose access immediately.',
          'Remove',
        )) {
      return;
    }
    if (!mounted) return;
    if (op == 'disable' &&
        !await _confirm(
          context,
          'Revoke access',
          'Revoke access for ${e.fullName}?',
          'Revoke',
        )) {
      return;
    }
    final svc = widget.service;
    switch (op) {
      case 'disable':
        await _run(
          () => svc.setEmployeeStatus(t.id, e.id, 'disabled'),
          empId: e.id,
        );
        break;
      case 'enable':
        await _run(
          () => svc.setEmployeeStatus(t.id, e.id, 'active'),
          empId: e.id,
        );
        break;
      case 'resend':
        await _run(() => svc.resendInvite(t.id, e.id), empId: e.id);
        break;
      case 'remove':
        await _run(() => svc.removeEmployee(t.id, e.id), empId: e.id);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    return WebModal(
      title: t == null
          ? 'Loading…'
          : (t.companyName.isEmpty ? 'Taxpayer' : t.companyName),
      subtitle: t == null
          ? null
          : 'Owner: ${t.ownerName.isEmpty ? 'No owner name' : t.ownerName}${t.email.isNotEmpty ? ' · ${t.email}' : ''}',
      icon: Icons.manage_accounts_outlined,
      width: 880,
      height: 820,
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      onClose: widget.onClose,
      actions: [
        GhostButton(
          label: 'Open portal',
          icon: Icons.open_in_new,
          onPressed: widget.onOpenPortal,
        ),
        GhostButton(label: 'Close', onPressed: widget.onClose),
      ],
      child: _error != null
          ? _ErrorView(_error!, _load)
          : t == null
          ? const _Spinner()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _head(t),
                Divider(height: 1, color: context.brand.rule),
                Expanded(
                  child: Container(
                    color: context.brand.canvas,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: _tab == 'owner' ? _ownerTab(t) : _empTab(t),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _head(TpDetail t) {
    final text = Theme.of(context).textTheme;
    Widget chip(String s) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: context.brand.surfaceHi,
        border: Border.all(color: context.brand.rule),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        s,
        style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              chip('TIN ${t.tin.isEmpty ? '—' : t.tin}'),
              chip('Branch ${t.branchCode.isEmpty ? '00000' : t.branchCode}'),
              _Pill(t.stage.label, _stageColor(t.stage.key)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _UnderlineTab(
                label: 'Owner access',
                icon: Icons.admin_panel_settings_outlined,
                selected: _tab == 'owner',
                onTap: () => setState(() => _tab = 'owner'),
              ),
              _UnderlineTab(
                label: 'Employees (${t.employees.length})',
                icon: Icons.group_outlined,
                selected: _tab == 'emp',
                onTap: () => setState(() => _tab = 'emp'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _ownerTab(TpDetail t) {
    final text = Theme.of(context).textTheme;
    final set = t.ownerPasswordSet;
    final when = _fmtDate(t.ownerPasswordSetAt);
    return _Box(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: (set ? _ok : _warn).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  set ? Icons.lock : Icons.lock_open,
                  size: 18,
                  color: set ? _ok : _warn,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      set ? 'Protected with a password' : 'TIN-only sign-in',
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      set
                          ? 'The owner signs in with the TIN and a password${when.isNotEmpty ? ', last changed $when' : ''}.'
                          : 'Anyone with the TIN can open this portal until a password is set. The owner is asked to create one on their next sign-in.',
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Divider(height: 1, color: context.brand.rule),
          const SizedBox(height: 16),
          Text(
            set ? 'Change owner password' : 'Set owner password',
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          if (_ownerError.isNotEmpty) ...[
            Text(
              _ownerError,
              style: const TextStyle(color: _bad, fontSize: 12.5),
            ),
            const SizedBox(height: 8),
          ],
          _PwField(
            controller: _ownerPw,
            label: 'New password',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          _PwField(
            controller: _ownerConfirm,
            label: 'Confirm password',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          PortalPasswordRules(_ownerPw.text, _ownerConfirm.text),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: SignalButton(
              onPressed: _busy ? null : _saveOwner,
              busy: _busy,
              icon: Icons.key,
              label: _busy ? 'Saving…' : 'Save password',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Applies to every branch on this TIN and signs the owner out of remembered devices.',
            style: text.bodySmall,
          ),
          if (set) ...[
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _bad.withValues(alpha: 0.4)),
                color: _bad.withValues(alpha: 0.04),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Danger zone',
                    style: text.titleSmall?.copyWith(
                      color: _bad,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Remove the password. The owner signs in with the TIN only and is asked to create a new one.',
                          style: text.bodySmall,
                        ),
                      ),
                      const SizedBox(width: 10),
                      DangerButton(
                        onPressed: _busy ? null : _clearOwner,
                        icon: Icons.lock_open,
                        label: 'Remove password',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _empTab(TpDetail t) {
    final text = Theme.of(context).textTheme;
    final count = t.employees.length;
    final max = t.maxEmployees;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$count of $max seats used', style: text.bodySmall),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: max == 0 ? 0 : (count / max).clamp(0, 1).toDouble(),
                    color: Brand.signal,
                    backgroundColor: context.brand.rule,
                    minHeight: 5,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            SignalButton(
              onPressed: count >= max || _busy
                  ? null
                  : () => _showForm('invite', null),
              icon: Icons.person_add,
              label: 'Invite employee',
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_formMode != null) ...[_empForm(), const SizedBox(height: 14)],
        if (t.employees.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                Icon(
                  Icons.person_add_alt,
                  size: 34,
                  color: context.brand.paperDim,
                ),
                const SizedBox(height: 8),
                Text('No employees yet', style: text.titleSmall),
                const SizedBox(height: 4),
                Text(
                  'Invite the people who follow this registration. They sign in with the TIN and their own password, read-only.',
                  textAlign: TextAlign.center,
                  style: text.bodySmall,
                ),
              ],
            ),
          )
        else
          for (final e in t.employees) ...[
            _empCard(e),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  Widget _empForm() {
    final text = Theme.of(context).textTheme;
    final mode = _formMode!;
    final who = _formEmp?.fullName ?? '';
    final title = {
      'invite': 'Invite employee',
      'edit': 'Edit $who',
      'password': 'Set password for $who',
    }[mode]!;
    final note = {
      'invite':
          'We email them a link to set their own password. It expires in 72 hours.',
      'edit': 'Changing the email does not resend the invite.',
      'password':
          'Replaces any pending invite and their current password, and signs them out of remembered devices.',
    }[mode]!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.brand.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Brand.signal.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(note, style: text.bodySmall),
          const SizedBox(height: 10),
          if (_empError.isNotEmpty) ...[
            Text(
              _empError,
              style: const TextStyle(color: _bad, fontSize: 12.5),
            ),
            const SizedBox(height: 8),
          ],
          if (mode == 'password') ...[
            _PwField(
              controller: _empPw,
              label: 'New password',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            _PwField(
              controller: _empConfirm,
              label: 'Confirm password',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            PortalPasswordRules(_empPw.text, _empConfirm.text),
          ] else ...[
            TextField(
              controller: _empName,
              maxLength: 120,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Full name',
                isDense: true,
                counterText: '',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _empEmail,
              maxLength: 150,
              decoration: const InputDecoration(
                labelText: 'Email',
                isDense: true,
                counterText: '',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _empPosition,
              maxLength: 100,
              decoration: const InputDecoration(
                labelText: 'Position (optional)',
                hintText: 'Cashier, Bookkeeper…',
                isDense: true,
                counterText: '',
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              GhostButton(label: 'Cancel', onPressed: _busy ? null : _hideForm),
              const SizedBox(width: 8),
              SignalButton(
                onPressed: _busy ? null : _submitForm,
                busy: _busy,
                icon: mode == 'invite' ? Icons.send : Icons.save,
                label: _busy
                    ? 'Saving…'
                    : (mode == 'invite' ? 'Send invite' : 'Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _empCard(TpEmployee e) {
    final text = Theme.of(context).textTheme;
    final pill = switch (e.status) {
      'active' => const _Pill('Active', _ok, icon: Icons.check_circle),
      'invited' => const _Pill('Invite sent', _warn, icon: Icons.send),
      'expired' => const _Pill('Invite expired', _muted, icon: Icons.schedule),
      'disabled' => const _Pill('Revoked', _bad, icon: Icons.block),
      _ => _Pill(e.status, _muted),
    };
    String activity;
    if (e.status == 'active') {
      activity = e.lastLoginAt.isNotEmpty
          ? 'Last sign-in ${_fmtDate(e.lastLoginAt)}'
          : 'Never signed in';
    } else if (e.status == 'disabled') {
      activity = e.lastLoginAt.isNotEmpty
          ? 'Access revoked · last sign-in ${_fmtDate(e.lastLoginAt)}'
          : 'Access revoked';
    } else {
      activity = e.invitedAt.isNotEmpty
          ? 'Invited ${_fmtDate(e.invitedAt)}'
          : '';
    }
    final working = _busy && _busyEmp == e.id;
    Widget btn(String op, IconData icon, String label, {bool danger = false}) =>
        IconButton(
          tooltip: label,
          visualDensity: VisualDensity.compact,
          onPressed: _busy ? null : () => _empOp(op, e),
          icon: Icon(icon, size: 17, color: danger ? _bad : null),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
      decoration: BoxDecoration(
        color: context.brand.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.brand.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Avatar(_initials(e.fullName), size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.fullName,
                      style: text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${e.email}${e.position.isNotEmpty ? ' · ${e.position}' : ''}',
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
              pill,
              const SizedBox(width: 6),
            ],
          ),
          Row(
            children: [
              Expanded(child: Text(activity, style: text.bodySmall)),
              if (working)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: TpLoader(
                      strokeWidth: 2,
                      color: Brand.signal,
                    ),
                  ),
                ),
              btn('edit', Icons.edit, 'Edit details'),
              btn('password', Icons.key, 'Set password'),
              if (e.status == 'active')
                btn('disable', Icons.block, 'Revoke access'),
              if (e.status == 'disabled')
                btn('enable', Icons.undo, 'Restore access'),
              if (e.status == 'invited' || e.status == 'expired')
                btn('resend', Icons.send, 'Resend invite'),
              btn(
                'remove',
                Icons.delete_outline,
                'Remove employee',
                danger: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PortalRoute extends StatefulWidget {
  const _PortalRoute({required this.service, required this.customerId});
  final TaxpayerPortalService service;
  final int customerId;

  @override
  State<_PortalRoute> createState() => _PortalRouteState();
}

class _PortalRouteState extends State<_PortalRoute> {
  @override
  void dispose() {
    widget.service.closePortal();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return WebModal(
      title: 'Taxpayer Portal',
      subtitle: 'Staff view · read-only',
      icon: Icons.shield_outlined,
      width: 1320,
      height: size.height - 64,
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      child: Container(
        color: context.brand.canvas,
        padding: const EdgeInsets.all(20),
        child: _PortalView(
          service: widget.service,
          customerId: widget.customerId,
        ),
      ),
    );
  }
}

class _StaffView extends StatefulWidget {
  const _StaffView({required this.api});
  final ApiClient api;

  @override
  State<_StaffView> createState() => _StaffViewState();
}

class _StaffViewState extends State<_StaffView> with LiveRefresh<_StaffView> {
  late final TaxpayerPortalService _svc = TaxpayerPortalService(widget.api);
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  bool _loading = true;
  String? _error;
  List<TpClient> _clients = const [];
  int _seq = 0;
  bool _opened = false;
  int? _selectedId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    if (_opened) _svc.closePortal();
    super.dispose();
  }

  @override
  List<String> get liveKeys => const ['taxpayerportal'];

  @override
  void onLiveChange() => _load(silent: true);

  Future<void> _load({bool silent = false}) async {
    final mine = ++_seq;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final c = await _svc.staffSearch(_searchCtrl.text.trim());
      if (!mounted || mine != _seq) return;
      setState(() {
        _clients = c;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || mine != _seq) return;
      if (silent) {
        if (_loading) setState(() => _loading = false);
        return;
      }
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return StationScaffold(
      stationNumber: 'TP',
      stationLabel: 'TAXPAYER PORTAL · STAFF VIEW',
      title: 'Taxpayer Portal',
      showBottomBrand: false,
      trailing: OutlinedIconButton(
        icon: Icons.refresh,
        tooltip: 'Refresh',
        onPressed: _load,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 380, child: _picker()),
          const SizedBox(width: 16),
          Expanded(
            child: _selectedId == null
                ? const _Box(
                    child: EmptyState(
                      label: 'Open a taxpayer portal',
                      hint:
                          'Choose a client to view their portal as staff (read-only).',
                    ),
                  )
                : _PortalView(
                    key: ValueKey(_selectedId),
                    service: _svc,
                    customerId: _selectedId!,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _picker() {
    final text = Theme.of(context).textTheme;
    Widget body;
    if (_loading) {
      body = const _Spinner();
    } else if (_error != null) {
      body = _ErrorView(_error!, _load);
    } else if (_clients.isEmpty) {
      body = const EmptyState(
        label: 'No clients',
        hint: 'No clients match your search.',
      );
    } else {
      body = ListView.builder(
        itemCount: _clients.length,
        itemBuilder: (_, i) {
          final c = _clients[i];
          final name = c.companyName.isNotEmpty
              ? c.companyName
              : (c.ownerName.isNotEmpty ? c.ownerName : 'Unnamed client');
          final selected = c.id == _selectedId;
          return WebTableRow(
            selected: selected,
            onTap: () => setState(() {
              _selectedId = c.id;
              _opened = true;
            }),
            cells: [
              Expanded(
                child: Row(
                  children: [
                    _Avatar(
                      _initials(
                        c.companyName.isNotEmpty ? c.companyName : c.ownerName,
                      ),
                      size: 34,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'TIN ${c.tin.isEmpty ? '—' : c.tin} · Branch ${c.branchCode.isEmpty ? '—' : c.branchCode}${c.ownerName.isNotEmpty ? ' · ${c.ownerName}' : ''}',
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    _Pill(c.stage.label, _stageColor(c.stage.key)),
                  ],
                ),
              ),
            ],
          );
        },
      );
    }
    return _Box(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SearchField(
              controller: _searchCtrl,
              width: null,
              hint: 'Search business name, owner or TIN',
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 250), _load);
              },
            ),
          ),
          Divider(height: 1, color: context.brand.rule),
          Expanded(child: body),
        ],
      ),
    );
  }
}

const _stageOrder = ['submitted', 'processed', 'awaiting', 'completed'];

const _stageInfo = {
  'submitted': (
    label: 'Submitted',
    icon: Icons.send,
    title: 'Submitted for review',
    note:
        'We received your documents. Our team will review them before filing with the BIR.',
    done: 'Documents received',
    current: 'Under review',
  ),
  'processed': (
    label: 'BIR Registration',
    icon: Icons.draw,
    title: 'Waiting for the BIR registration',
    note:
        'Your documents passed review. We are waiting for your BIR registration (Form 2303) to be issued.',
    done: 'BIR registration received',
    current: 'Waiting for BIR registration',
  ),
  'awaiting': (
    label: 'Awaiting PTU',
    icon: Icons.schedule,
    title: 'Awaiting PTU release',
    note:
        'Your BIR registration is on file. The Permit to Use (PTU) is the last document to be released.',
    done: 'PTU released',
    current: 'PTU being released',
  ),
  'completed': (
    label: 'Completed',
    icon: Icons.check_circle,
    title: 'Registration complete',
    note: 'Your PTU and BIR documents are ready. Download them any time.',
    done: 'All documents ready',
    current: 'All documents ready',
  ),
};

class _PortalView extends StatefulWidget {
  const _PortalView({
    super.key,
    required this.service,
    required this.customerId,
  });
  final TaxpayerPortalService service;
  final int customerId;

  @override
  State<_PortalView> createState() => _PortalViewState();
}

class _PortalViewState extends State<_PortalView>
    with LiveRefresh<_PortalView> {
  PortalCustomer? _c;
  String? _error;
  bool _loading = true;
  String _view = 'overview';
  PortalEmployees? _team;
  String? _teamError;
  String? _docBusy;
  bool _csvBusy = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final c = await widget.service.openPortal(widget.customerId);
      if (!mounted) return;
      setState(() {
        _c = c;
        _loading = false;
      });
      _loadTeam();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _refresh() async {
    try {
      final c = await widget.service.portalSession();
      if (!mounted) return;
      if (c.id != widget.customerId) {
        await _open();
        return;
      }
      setState(() => _c = c);
      _loadTeam();
    } catch (_) {
      await _open();
    }
  }

  @override
  List<String> get liveKeys => const ['taxpayerportal'];

  @override
  void onLiveChange() => _liveReload();

  Future<void> _liveReload() async {
    if (_loading || _error != null || _c == null) return;
    try {
      final c = await widget.service.portalSession();
      if (!mounted || _loading || _error != null) return;
      if (c.id != widget.customerId) return;
      setState(() => _c = c);
      _loadTeam(silent: true);
    } catch (_) {}
  }

  Future<void> _loadTeam({bool silent = false}) async {
    final c = _c;
    if (c == null || c.isV1) return;
    try {
      final t = await widget.service.portalEmployees();
      if (!mounted) return;
      setState(() {
        _team = t;
        _teamError = null;
      });
    } catch (e) {
      if (!mounted || silent) return;
      setState(() => _teamError = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _launch(String url) async {
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) _toast(context, 'Could not open $url', error: true);
  }

  Future<void> _openDoc(PortalDoc d) async {
    final c = _c;
    if (c == null) return;
    setState(() => _docBusy = d.label);
    try {
      final url = d.isStatic
          ? widget.service.uploadUrl(d.file)
          : await widget.service.generateDocument(c.id, d);
      await _launch(url);
    } catch (e) {
      if (mounted) {
        _toast(
          context,
          e.toString().replaceFirst('Exception: ', ''),
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _docBusy = null);
    }
  }

  Future<void> _downloadCsv() async {
    final c = _c;
    if (c == null) return;
    setState(() => _csvBusy = true);
    try {
      final f = await widget.service.downloadCsv(c.id);
      if (!mounted) return;
      _toast(context, 'Saved ${f.path}');
      await OpenFilex.open(f.path);
    } catch (e) {
      if (mounted) {
        _toast(
          context,
          e.toString().replaceFirst('Exception: ', ''),
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _csvBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _Box(child: _Spinner());
    if (_error != null) return _Box(child: _ErrorView(_error!, _open));
    final c = _c!;
    final text = Theme.of(context).textTheme;
    final views = [
      ('overview', 'Overview', Icons.dashboard_outlined),
      ('documents', 'Documents', Icons.folder_open),
      if (!c.isV1) ('team', 'Team', Icons.group_outlined),
      if (!c.isV1) ('feedback', 'Feedback', Icons.rate_review_outlined),
    ];
    final meta = <String>[
      if (c.tin.isNotEmpty) 'TIN ${c.tin}',
      if (c.effectiveBranchCode.isNotEmpty) 'Branch ${c.effectiveBranchCode}',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Box(
          child: Row(
            children: [
              _Avatar(_initials(c.avatarSource)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.companyName.isEmpty ? '-' : c.companyName,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      meta.isEmpty
                          ? 'Registration dashboard'
                          : meta.join('  ·  '),
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
              const _Pill(
                'Staff view',
                Brand.signal,
                icon: Icons.shield_outlined,
              ),
              const SizedBox(width: 8),
              _Pill(c.statusText, _stageColor(c.stageKey)),
              const SizedBox(width: 8),
              OutlinedIconButton(
                icon: Icons.refresh,
                tooltip: 'Refresh',
                onPressed: _refresh,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Brand.signal.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Brand.signal.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              const Icon(Icons.shield_outlined, size: 18, color: Brand.signal),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(
                        text: 'Staff view · read-only. ',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(
                        text: c.staffCanManage
                            ? 'Signed in as ${c.staffName} (super admin). Manage the owner password and employees from the Taxpayer Portal manage panel. Changes are recorded in Activity Logs.'
                            : 'Signed in as ${c.staffName}. You can see everything the taxpayer sees, but you cannot change their password, employees or feedback.',
                      ),
                    ],
                  ),
                  style: text.bodySmall,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: context.brand.rule)),
          ),
          child: Row(
            children: [
              for (final v in views)
                _UnderlineTab(
                  icon: v.$3,
                  label: v.$1 == 'documents' && c.documents.isNotEmpty
                      ? '${v.$2} (${c.documents.length})'
                      : v.$1 == 'team' && (_team?.employees.isNotEmpty ?? false)
                      ? '${v.$2} (${_team!.employees.length})'
                      : v.$2,
                  selected: _view == v.$1,
                  onTap: () => setState(() => _view = v.$1),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: SingleChildScrollView(
            child: switch (_view) {
              'documents' => _documents(c),
              'team' => _teamView(),
              'feedback' => _feedback(),
              _ => _overview(c),
            },
          ),
        ),
      ],
    );
  }

  Widget _overview(PortalCustomer c) {
    final text = Theme.of(context).textTheme;
    final key = c.stageKey;
    final info = _stageInfo[key]!;
    final index = _stageOrder.indexOf(key);
    final allDone = key == 'completed';
    final checklist = c.checklist;
    final ready = checklist.where((i) => i.ready).length;
    Widget detail(String label, String value) => SizedBox(
      width: 260,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: text.bodySmall?.copyWith(color: context.brand.paperDim),
            ),
            const SizedBox(height: 2),
            SelectableText(
              value.isEmpty ? '-' : value,
              style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Box(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(info.icon, color: _stageColor(key)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Current status · ${info.label}',
                          style: text.bodySmall?.copyWith(
                            color: context.brand.paperDim,
                          ),
                        ),
                        Text(
                          info.title,
                          style: text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    allDone
                        ? 'All 4 stages complete'
                        : 'Stage ${index + 1} of 4',
                    style: text.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(info.note, style: text.bodySmall),
              const SizedBox(height: 14),
              Row(
                children: [
                  for (var i = 0; i < _stageOrder.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(child: _stageTile(i, index, allDone)),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: _Box(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Business details',
                          style: text.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        if (c.hasCsv)
                          GhostButton(
                            onPressed: _csvBusy ? null : _downloadCsv,
                            icon: Icons.download,
                            label: _csvBusy ? 'Downloading…' : 'Download CSV',
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 16,
                      children: [
                        detail('Company', c.companyName),
                        detail('TIN', c.tin),
                        detail('Owner', c.ownerName),
                        detail('Address', c.address),
                        detail('Branch', c.branchDisplay),
                        detail('RDO', c.rdo),
                        detail('Email', c.email),
                        detail('Business line', c.businessLine),
                        detail('Software', c.softwareName),
                        detail('Serial number', c.serialDisplay),
                        detail('Registration type', c.vatLabel),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: _Box(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Document checklist',
                          style: text.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '$ready of ${checklist.length} ready',
                          style: text.bodySmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    for (final item in checklist)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          item.ready
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: item.ready ? _ok : context.brand.paperDim,
                          size: 20,
                        ),
                        title: Text(item.label),
                        subtitle: Text(
                          item.ready ? 'Ready to download' : item.note,
                        ),
                        trailing: Text(
                          item.ready ? 'Ready' : 'Pending',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: item.ready ? _ok : context.brand.paperDim,
                          ),
                        ),
                        onTap: item.ready
                            ? () => setState(() => _view = 'documents')
                            : null,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _stageTile(int i, int index, bool allDone) {
    final text = Theme.of(context).textTheme;
    final info = _stageInfo[_stageOrder[i]]!;
    final done = allDone || i < index;
    final current = !allDone && i == index;
    final color = done
        ? _ok
        : (current ? Brand.signal : context.brand.paperDim);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: current ? Brand.signal.withValues(alpha: 0.07) : null,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: current
              ? Brand.signal.withValues(alpha: 0.5)
              : context.brand.rule,
        ),
      ),
      child: Row(
        children: [
          Icon(done ? Icons.check : info.icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.label,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  done ? info.done : (current ? info.current : 'Not started'),
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _documents(PortalCustomer c) {
    final text = Theme.of(context).textTheme;
    final docs = c.documents;
    if (c.isV1) {
      return const _Box(
        child: EmptyState(
          label: 'Archived record',
          hint: 'V1 archive documents are not available in the staff view.',
        ),
      );
    }
    if (docs.isEmpty) {
      return const _Box(
        child: EmptyState(
          label: 'No documents yet',
          hint: 'They appear here as soon as the registration is processed.',
        ),
      );
    }
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final d in docs)
          SizedBox(
            width: 320,
            child: _Box(
              padding: EdgeInsets.zero,
              child: InkWell(
                mouseCursor: SystemMouseCursors.click,
                onTap: _docBusy == null ? () => _openDoc(d) : null,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(
                        d.isStatic ? Icons.picture_as_pdf : Icons.description,
                        color: Brand.signal,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              d.label,
                              style: text.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              d.isStatic
                                  ? 'Official PDF Document'
                                  : 'Generated PDF Document',
                              style: text.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      _docBusy == d.label
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: TpLoader(
                                strokeWidth: 2,
                                color: Brand.signal,
                              ),
                            )
                          : const Icon(Icons.download, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _teamView() {
    final text = Theme.of(context).textTheme;
    if (_teamError != null) {
      return _Box(child: _ErrorView(_teamError!, _loadTeam));
    }
    final team = _team;
    if (team == null) return const _Box(child: _Spinner());
    final pills = {
      'active': const _Pill('Active', _ok),
      'invited': const _Pill('Invite sent', _warn),
      'expired': const _Pill('Invite expired', _muted),
      'disabled': const _Pill('Revoked', _bad),
    };
    String activity(TpEmployee e) {
      if (e.status == 'active') {
        final last = _fmtDate(e.lastLoginAt);
        return last.isNotEmpty ? 'Last sign-in $last' : 'Never signed in';
      }
      if (e.status == 'expired') return 'Invite expired';
      if (e.status == 'disabled') return 'Access revoked';
      final sent = _fmtDate(e.invitedAt);
      return sent.isNotEmpty ? 'Invited $sent' : 'Invite sent';
    }

    return _Box(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Team access',
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                '${team.employees.length} of ${team.max} seats used',
                style: text.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Staff view is read-only. Only the account owner can invite or remove employees.',
            style: text.bodySmall,
          ),
          const SizedBox(height: 12),
          if (team.employees.isEmpty)
            const EmptyState(
              label: 'No employees yet',
              hint: 'The owner has not invited anyone to this registration.',
            )
          else
            for (final e in team.employees) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.brand.rule),
                ),
                child: Row(
                  children: [
                    _Avatar(_initials(e.fullName), size: 32),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.fullName,
                            style: text.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${e.email}${e.position.isNotEmpty ? ' · ${e.position}' : ''}',
                            style: text.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Text(activity(e), style: text.bodySmall),
                    const SizedBox(width: 10),
                    pills[e.status] ?? pills['invited']!,
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }

  Widget _feedback() {
    return const _Box(
      child: Row(
        children: [
          Icon(Icons.shield_outlined, color: Brand.signal),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Staff view is read-only. Only the taxpayer can send feedback from here.',
            ),
          ),
        ],
      ),
    );
  }
}
