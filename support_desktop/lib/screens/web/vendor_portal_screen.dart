import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:url_launcher/url_launcher.dart';

import '../../api_client.dart';
import '../../services/live_sync.dart';
import '../../services/vendor_portal_service.dart';
import '../../theme.dart';
import '../../widgets/premium.dart';
import 'portal_ui.dart';
import '../../widgets/tp_loader.dart';

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

String _fmtDate(String raw, [bool withTime = false]) {
  if (raw.isEmpty) return '';
  final d = DateTime.tryParse(raw.replaceFirst(' ', 'T'));
  if (d == null) return '';
  final date = '${d.day} ${_months[d.month - 1]} ${d.year}';
  if (!withTime) return date;
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$date, $h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message), persist: false));
}

Future<bool> _confirm(
  BuildContext context,
  String title,
  String message,
  String confirm,
) async {
  final ok = await showWebModal<bool>(
    context,
    title: title,
    icon: Icons.help_outline,
    width: 460,
    builder: (ctx) => Text(message, style: Theme.of(ctx).textTheme.bodyMedium),
    actions: (ctx) => [
      GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx, false)),
      DangerButton(label: confirm, onPressed: () => Navigator.pop(ctx, true)),
    ],
  );
  return ok ?? false;
}

class VendorPortalScreen extends StatefulWidget {
  const VendorPortalScreen({
    super.key,
    required this.api,
    required this.canManage,
  });
  final ApiClient api;
  final bool canManage;

  @override
  State<VendorPortalScreen> createState() => _VendorPortalScreenState();
}

class _VendorPortalScreenState extends State<VendorPortalScreen>
    with LiveRefresh<VendorPortalScreen> {
  late final VendorPortalService _svc = VendorPortalService(widget.api);
  final _searchCtrl = TextEditingController();
  Timer? _searchTimer;

  String _q = '';
  String _filter = 'all';
  int _page = 1;
  int _perPage = 25;
  int _total = 0;
  VendorStats _stats = const VendorStats();
  List<VendorRow> _rows = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  List<String> get liveKeys => const ['vendorportal'];

  @override
  void onLiveChange() => _load(silent: true);

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final q = _q, filter = _filter, pg = _page;
    try {
      final page = await _svc.list(q: q, filter: filter, page: pg);
      if (!mounted) return;
      if (silent && (q != _q || filter != _filter || pg != _page)) return;
      setState(() {
        _rows = page.rows;
        _total = page.total;
        _perPage = page.perPage;
        _stats = page.stats;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || silent) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _openVendor(int id) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _VendorPanel(
        service: _svc,
        vendorId: id,
        canManage: widget.canManage,
        onClose: () => Navigator.of(ctx).maybePop(),
        onChanged: _load,
      ),
    );
  }

  Future<void> _openInvites(bool focus) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _InvitesPanel(
        service: _svc,
        focusForm: focus,
        onClose: () => Navigator.of(ctx).maybePop(),
        onChanged: _load,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final from = _total == 0 ? 0 : (_page - 1) * _perPage + 1;
    final to = (_page * _perPage).clamp(0, _total);
    return PortalPage(
      onRefresh: _load,
      children: [
        PortalHeader(
          eyebrow:
              'Workspace · ${widget.canManage ? 'Super admin' : 'View only'}',
          title: 'Vendor Portal',
          sub: widget.canManage
              ? 'Manage every vendor account: details, sign-in password, license key price, status, and the clients and license keys they filed. Every change is recorded in Activity Logs.'
              : 'Every vendor account with its clients, license keys and activity. View only: a super admin makes changes to vendor accounts.',
          trailing: PortalStats(
            items: [
              ('${_stats.vendors}', 'Vendors'),
              ('${_stats.active}', 'Active'),
              ('${_stats.suspended}', 'Suspended'),
              (_stats.revenueLabel, 'License key revenue'),
              ('${_stats.openInvites}', 'Open invites'),
            ],
          ),
        ),
        LayoutBuilder(builder: (context, box) {
          final search = PortalSearch(
                controller: _searchCtrl,
                hint: 'Search vendor ID, company, contact, email or mobile',
                onChanged: (v) {
                  _searchTimer?.cancel();
                  _searchTimer = Timer(const Duration(milliseconds: 300), () {
                    _q = v.trim();
                    _page = 1;
                    _load();
                  });
                },
              );
          final controls = <Widget>[
            for (final f in const [
              ('all', 'All'),
              ('active', 'Active'),
              ('suspended', 'Suspended'),
            ]) ...[
              PortalTab(
                label: f.$2,
                selected: _filter == f.$1,
                onTap: () => _setFilter(f.$1),
              ),
            ],
            PortalButton(
              big: true,
              label: 'Open portal (admin view)',
              icon: Icons.open_in_new,
              onPressed: () => launchUrl(Uri.parse(_svc.vendorPortalUrl)),
            ),
            if (widget.canManage) ...[
              PortalButton(
                big: true,
                label: 'Invites',
                icon: Icons.link,
                onPressed: () => _openInvites(false),
              ),
              PortalButton(
                big: true,
                primary: true,
                label: 'Invite vendor',
                icon: Icons.person_add_alt_1,
                onPressed: () => _openInvites(true),
              ),
            ],
          ];
          final bar = Wrap(
            spacing: 6,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: controls,
          );
          if (box.maxWidth < 1100) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [search, const SizedBox(height: 10), bar],
            );
          }
          return Row(
            children: [
              Expanded(child: search),
              const SizedBox(width: 10),
              bar,
            ],
          );
        }),
        const SizedBox(height: 16),
        PortalCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null && _rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Text(_error!, style: portalCell(context)),
                      const SizedBox(height: 12),
                      PortalButton(
                        label: 'Retry',
                        icon: Icons.refresh,
                        onPressed: _load,
                      ),
                    ],
                  ),
                )
              else
                _table(),
              PortalPager(
                info: '$from–$to of $_total',
                onPrev: _page > 1
                    ? () {
                        setState(() => _page--);
                        _load();
                      }
                    : null,
                onNext: to < _total
                    ? () {
                        setState(() => _page++);
                        _load();
                      }
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _setFilter(String f) {
    setState(() {
      _filter = f;
      _page = 1;
    });
    _load();
  }

  Widget _table() {
    final meta = portalMeta(context);
    final name = portalName(context);
    final cell = portalCell(context);
    return PortalTable(
      tableId: 'portal:vendor',
      loading: _loading,
      empty: 'No vendors match this search.',
      onRowTap: (i) => _openVendor(_rows[i].id),
      columns: const [
        PortalCol('Vendor', flex: 30),
        PortalCol('Vendor ID', flex: 18),
        PortalCol('Price / key', flex: 12),
        PortalCol('Registrations', flex: 15),
        PortalCol('Keys paid', flex: 11),
        PortalCol('Status', flex: 12),
        PortalCol('Actions', right: true, width: 190),
      ],
      rows: [
        for (final r in _rows)
          [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.companyName, style: name),
                Text(
                  '${r.contactPerson.isNotEmpty ? r.contactPerson : 'No contact'} · ${r.email}',
                  style: meta,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.vendorCode, style: cell),
                Text(
                  r.lastLoginAt.isNotEmpty
                      ? 'Signed in ${_fmtDate(r.lastLoginAt)}'
                      : 'Never signed in',
                  style: meta,
                ),
              ],
            ),
            Text(r.priceLabel, style: cell),
            Text('${r.submissions}', style: name),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${r.keysPaid}', style: name),
                Text(r.revenueLabel, style: meta),
              ],
            ),
            _statusPill(r.status == 'active'),
            PortalButton(
              primary: true,
              onPressed: () => _openVendor(r.id),
              icon: widget.canManage ? Icons.manage_accounts : Icons.visibility,
              label: widget.canManage ? 'Manage' : 'View',
            ),
          ],
      ],
    );
  }
}

Widget _statusPill(bool active) => active
    ? const PortalPill('Active', PortalTone.ok, icon: Icons.check_circle)
    : const PortalPill('Suspended', PortalTone.bad, icon: Icons.block);

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});
  final String text;
  final Color color;

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
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: context.brand.surfaceHi,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.brand.rule),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: context.brand.paperDim),
            ),
          ],
        ),
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({this.title, required this.child, this.danger = false});
  final String? title;
  final Widget child;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: danger
            ? Brand.danger.withValues(alpha: 0.05)
            : context.brand.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: danger
              ? Brand.danger.withValues(alpha: 0.4)
              : context.brand.rule,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: danger ? Brand.danger : null,
              ),
            ),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    if (message.isEmpty) return const SizedBox.shrink();
    final c = Theme.of(context).colorScheme.error;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Text(message, style: TextStyle(color: c, fontSize: 13)),
    );
  }
}

class _ListRow extends StatelessWidget {
  const _ListRow({required this.main, required this.side});
  final List<Widget> main;
  final List<Widget> side;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.brand.rule)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: main,
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < side.length; i++) ...[
                if (i > 0) const SizedBox(height: 6),
                side[i],
              ],
            ],
          ),
        ],
      ),
    );
  }
}

Widget _soft(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 24),
  child: Center(
    child: Text(text, style: TextStyle(color: context.brand.paperDim)),
  ),
);

Widget _titleText(String t) =>
    Text(t, style: const TextStyle(fontWeight: FontWeight.w600));

Widget _subText(BuildContext context, String t) =>
    Text(t, style: TextStyle(fontSize: 12, color: context.brand.paperDim));

class _VendorPanel extends StatefulWidget {
  const _VendorPanel({
    required this.service,
    required this.vendorId,
    required this.canManage,
    required this.onClose,
    required this.onChanged,
  });
  final VendorPortalService service;
  final int vendorId;
  final bool canManage;
  final VoidCallback onClose;
  final VoidCallback onChanged;

  @override
  State<_VendorPanel> createState() => _VendorPanelState();
}

class _VendorPanelState extends State<_VendorPanel>
    with LiveRefresh<_VendorPanel> {
  VendorDetail? _d;
  String? _loadError;
  int _tab = 0;

  final _code = TextEditingController();
  final _company = TextEditingController();
  final _contact = TextEditingController();
  final _mobile = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _price = TextEditingController();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  bool _showPw = false;
  bool _showPw2 = false;

  String _detailsError = '';
  String _priceError = '';
  String _pwError = '';
  String _busy = '';

  @override
  void initState() {
    super.initState();
    _pw.addListener(_rulesChanged);
    _pw2.addListener(_rulesChanged);
    _fetch();
  }

  void _rulesChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [
      _code,
      _company,
      _contact,
      _mobile,
      _email,
      _address,
      _price,
      _pw,
      _pw2,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final d = await widget.service.detail(widget.vendorId);
      if (!mounted) return;
      _apply(d, true);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      _toast(
        context,
        msg.startsWith('HTTP') ? 'Error contacting server.' : msg,
      );
      setState(() => _loadError = msg);
      widget.onClose();
    }
  }

  @override
  List<String> get liveKeys => const ['vendorportal'];

  @override
  void onLiveChange() => _refresh();

  Future<void> _refresh() async {
    if (_busy.isNotEmpty || _d == null) return;
    try {
      final d = await widget.service.detail(widget.vendorId);
      if (!mounted || _busy.isNotEmpty || _d == null) return;
      final old = _d!;
      setState(() {
        _d = d;
        for (final (c, k) in [
          (_code, 'vendor_code'),
          (_company, 'company_name'),
          (_contact, 'contact_person'),
          (_mobile, 'mobile'),
          (_email, 'email'),
          (_address, 'address'),
          (_price, 'license_price'),
        ]) {
          if (c.text == old.v(k) && c.text != d.v(k)) c.text = d.v(k);
        }
      });
    } catch (e) {
      if (!mounted) return;
      if (!e.toString().toLowerCase().contains('not found')) return;
      setState(() {
        _d = null;
        _loadError = 'This vendor was removed.';
      });
    }
  }

  void _apply(VendorDetail d, bool fill) {
    setState(() {
      _d = d;
      if (fill) {
        _code.text = d.v('vendor_code');
        _company.text = d.v('company_name');
        _contact.text = d.v('contact_person');
        _mobile.text = d.v('mobile');
        _email.text = d.v('email');
        _address.text = d.v('address');
        _price.text = d.v('license_price');
      }
    });
  }

  Future<VmResult?> _run(
    String busy,
    Future<VmResult> Function() call, {
    void Function(String)? setError,
    bool refill = false,
  }) async {
    setState(() {
      _busy = busy;
      setError?.call('');
    });
    final res = await call();
    if (!mounted) return null;
    setState(() => _busy = '');
    if (!res.ok) {
      if (setError != null) {
        setState(() => setError(res.message));
      } else {
        _toast(context, res.message);
      }
      return null;
    }
    _toast(context, res.message);
    widget.onChanged();
    final detail = res.detail;
    if (detail != null) _apply(detail, refill);
    return res;
  }

  Future<void> _saveDetails() async {
    final company = _company.text.trim();
    final email = _email.text.trim();
    final code = _code.text.trim();
    String hint = '';
    if (code.length < 4) {
      hint = 'Vendor ID must be 4 to 30 characters.';
    } else if (company.isEmpty) {
      hint = 'Company name is required.';
    } else if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      hint = 'Enter a valid email address.';
    }
    if (hint.isNotEmpty) {
      setState(() => _detailsError = hint);
      return;
    }
    await _runDetails();
  }

  Future<void> _runDetails() => _run(
    'details',
    () => widget.service.updateDetails(
      widget.vendorId,
      vendorCode: _code.text.trim(),
      companyName: _company.text.trim(),
      contactPerson: _contact.text.trim(),
      email: _email.text.trim(),
      mobile: _mobile.text.trim(),
      address: _address.text.trim(),
    ),
    setError: (m) => _detailsError = m,
    refill: true,
  );

  Future<void> _savePrice() async {
    if (_price.text.trim().isEmpty) {
      setState(() => _priceError = 'Enter the license key price.');
      return;
    }
    await _runPrice();
  }

  Future<void> _runPrice() => _run(
    'price',
    () => widget.service.setPrice(widget.vendorId, _price.text.trim()),
    setError: (m) => _priceError = m,
    refill: true,
  );

  Future<void> _savePassword() async {
    final err = portalPasswordError(_pw.text, _pw2.text);
    if (err.isNotEmpty) {
      setState(() => _pwError = err);
      return;
    }
    final res = await _run(
      'pw',
      () => widget.service.setPassword(widget.vendorId, _pw.text, _pw2.text),
      setError: (m) => _pwError = m,
    );
    if (res != null && mounted) {
      setState(() {
        _pw.clear();
        _pw2.clear();
        _showPw = false;
        _showPw2 = false;
      });
    }
  }

  Future<void> _toggleStatus() async {
    final d = _d;
    if (d == null) return;
    final suspending = d.isActive;
    if (suspending &&
        !await _confirm(
          context,
          'Suspend vendor',
          'Suspend ${d.v('company_name')}? They are signed out everywhere and cannot sign in.',
          'Suspend',
        )) {
      return;
    }
    await _run(
      'status',
      () => widget.service.setStatus(
        widget.vendorId,
        suspending ? 'suspended' : 'active',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final contact = d == null
        ? null
        : '${d.v('contact_person').isNotEmpty ? d.v('contact_person') : 'No contact'} · ${d.v('email')}${d.v('mobile').isNotEmpty ? ' · ${d.v('mobile')}' : ''}';
    return WebModal(
      title: d == null ? 'Loading…' : d.v('company_name'),
      subtitle: contact,
      icon: Icons.storefront_outlined,
      width: 920,
      height: 820,
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      onClose: widget.onClose,
      actions: [
        if (d != null)
          GhostButton(
            label: 'Email vendor',
            icon: Icons.email_outlined,
            onPressed: () =>
                launchUrl(Uri(scheme: 'mailto', path: d.v('email'))),
          ),
        GhostButton(label: 'Close', onPressed: widget.onClose),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _head(d),
          Divider(height: 1, color: context.brand.rule),
          Expanded(
            child: d == null
                ? Center(
                    child: _loadError != null
                        ? Text(_loadError!)
                        : const SizedBox(
                            width: 22,
                            height: 22,
                            child: TpLoader(
                              strokeWidth: 2,
                              color: Brand.signal,
                            ),
                          ),
                  )
                : Container(
                    color: context.brand.canvas,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: switch (_tab) {
                        0 => _account(d),
                        1 => _keys(d),
                        2 => _clients(d),
                        _ => _activity(d),
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _head(VendorDetail? d) {
    Widget chip(String t, {IconData? icon}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: context.brand.surfaceHi,
        border: Border.all(color: context.brand.rule),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: context.brand.paperDim),
            const SizedBox(width: 4),
          ],
          Text(
            t,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (d != null)
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                chip(d.v('vendor_code'), icon: Icons.badge_outlined),
                chip('${d.v('license_price_label')} / key'),
                _statusPill(d.isActive),
              ],
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              _tabBtn(0, Icons.manage_accounts_outlined, 'Account', null),
              _tabBtn(1, Icons.key, 'License keys', d?.requests.length ?? 0),
              _tabBtn(2, Icons.people_outline, 'Clients', d?.clientsTotal ?? 0),
              _tabBtn(3, Icons.history, 'Activity', null),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tabBtn(int i, IconData icon, String label, int? count) {
    final on = _tab == i;
    final color = on ? Brand.signal : context.brand.paperDim;
    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      onTap: () => setState(() => _tab = i),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: on ? Brand.signal : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 13,
                color: on ? Brand.signal : context.brand.paper,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: on
                      ? Brand.signal.withValues(alpha: 0.12)
                      : context.brand.surfaceHi,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: context.brand.rule),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _input(
    TextEditingController c,
    String label, {
    bool obscure = false,
    Widget? suffix,
    String? prefix,
  }) {
    return TextField(
      controller: c,
      enabled: widget.canManage,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        suffixIcon: suffix,
        prefixText: prefix,
      ),
    );
  }

  Widget _saveBtn(
    String key,
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool danger = false,
  }) {
    final busy = _busy == key;
    final action = _busy.isNotEmpty ? null : onTap;
    if (danger) {
      return DangerButton(
        label: busy ? 'Saving…' : label,
        icon: icon,
        onPressed: action,
      );
    }
    return SignalButton(
      label: busy ? 'Saving…' : label,
      icon: icon,
      busy: busy,
      onPressed: action,
    );
  }

  Widget _account(VendorDetail d) {
    final active = d.isActive;
    final joined = _fmtDate(d.v('created_at'));
    final last = d.v('last_login_at');
    final lead = active
        ? 'Can sign in, file registrations and request license keys.'
        : 'Cannot sign in or file anything until reactivated.';
    final statusText =
        '$lead Joined $joined${last.isNotEmpty ? ', last sign-in ${_fmtDate(last, true)}' : ', never signed in'}.';
    final meta = TextStyle(fontSize: 12, color: context.brand.paperDim);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Block(
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: (active ? Brand.success : Brand.danger)
                    .withValues(alpha: 0.15),
                child: Icon(
                  active ? Icons.storefront : Icons.block,
                  size: 18,
                  color: active ? Brand.success : Brand.danger,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      active ? 'Active account' : 'Suspended',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(statusText, style: meta),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!widget.canManage)
          _Block(
            child: Row(
              children: [
                const Icon(Icons.visibility_outlined, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'View only. A super admin can edit details, change the price or password, and suspend this vendor.',
                    style: meta,
                  ),
                ),
              ],
            ),
          ),
        _Block(
          title: 'Vendor details',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ErrorLine(_detailsError),
              Row(
                children: [
                  Expanded(child: _input(_code, 'Vendor ID')),
                  const SizedBox(width: 12),
                  Expanded(child: _input(_company, 'Company name')),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _input(_contact, 'Contact person')),
                  const SizedBox(width: 12),
                  Expanded(child: _input(_mobile, 'Mobile')),
                ],
              ),
              const SizedBox(height: 12),
              _input(_email, 'Email (used to sign in)'),
              const SizedBox(height: 12),
              _input(_address, 'Address'),
              if (widget.canManage) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: _saveBtn(
                    'details',
                    Icons.save_outlined,
                    'Save details',
                    _saveDetails,
                  ),
                ),
              ],
            ],
          ),
        ),
        _Block(
          title: 'License key price',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ErrorLine(_priceError),
              Row(
                children: [
                  Expanded(
                    child: _input(
                      _price,
                      'Price per license key',
                      prefix: '₱ ',
                    ),
                  ),
                  if (widget.canManage) ...[
                    const SizedBox(width: 12),
                    _saveBtn(
                      'price',
                      Icons.sell_outlined,
                      'Save price',
                      _savePrice,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Applies to new license key requests. Existing requests keep the price they were created with.',
                style: meta,
              ),
            ],
          ),
        ),
        if (widget.canManage) ...[
          _Block(
            title: 'Sign-in password',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ErrorLine(_pwError),
                _input(
                  _pw,
                  'New password',
                  obscure: !_showPw,
                  suffix: IconButton(
                    tooltip: _showPw ? 'Hide password' : 'Show password',
                    icon: Icon(
                      _showPw
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () => setState(() => _showPw = !_showPw),
                  ),
                ),
                const SizedBox(height: 12),
                _input(
                  _pw2,
                  'Confirm password',
                  obscure: !_showPw2,
                  suffix: IconButton(
                    tooltip: _showPw2 ? 'Hide password' : 'Show password',
                    icon: Icon(
                      _showPw2
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () => setState(() => _showPw2 = !_showPw2),
                  ),
                ),
                const SizedBox(height: 8),
                PortalPasswordRules(_pw.text, _pw2.text),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: _saveBtn(
                    'pw',
                    Icons.key,
                    'Save password',
                    _savePassword,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Signs the vendor out of remembered devices. They can still reset it themselves with an emailed code.',
                  style: meta,
                ),
              ],
            ),
          ),
          _Block(
            title: active ? 'Danger zone' : 'Account status',
            danger: active,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    active
                        ? 'Suspend the account. The vendor is signed out everywhere and cannot sign in until you reactivate it.'
                        : 'Reactivate the account so the vendor can sign in again.',
                    style: meta,
                  ),
                ),
                const SizedBox(width: 12),
                _saveBtn(
                  'status',
                  active ? Icons.block : Icons.check,
                  active ? 'Suspend vendor' : 'Reactivate vendor',
                  _toggleStatus,
                  danger: active,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _keys(VendorDetail d) {
    final t = d.totals;
    final reqs = d.requests;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _Mini('Keys paid', '${t['keys_paid'] ?? 0}'),
            _Mini('Revenue', peso(t['revenue'])),
            _Mini('Pending keys', '${t['pending'] ?? 0}'),
          ],
        ),
        const SizedBox(height: 12),
        if (reqs.isEmpty)
          _soft(context, 'No license key requests yet.')
        else
          for (final r in reqs) _keyRow(r),
      ],
    );
  }

  Widget _keyRow(Map<String, dynamic> r) {
    final paid = '${r['payment_status'] ?? ''}' == 'paid';
    final keys = <String>[];
    final raw = r['license_keys'];
    if (raw is List) {
      for (final k in raw) {
        if (k is String) {
          keys.add(k);
        } else if (k is Map) {
          keys.add('${k['license_key'] ?? k['key'] ?? ''}');
        }
      }
    }
    if (keys.isEmpty && '${r['license_key'] ?? ''}'.isNotEmpty) {
      keys.add('${r['license_key']}');
    }
    final qty = int.tryParse('${r['quantity'] ?? 1}') ?? 1;
    final when = _fmtDate(
      '${r['paid_at'] ?? ''}'.isNotEmpty
          ? '${r['paid_at']}'
          : '${r['created_at'] ?? ''}',
    );
    final biz = '${r['business_name'] ?? ''}';
    final tin = '${r['tin'] ?? ''}';
    final ps = '${r['payment_status'] ?? ''}';
    return _ListRow(
      main: [
        _titleText(biz.isNotEmpty ? biz : 'Untitled'),
        _subText(
          context,
          'TIN ${tin.isNotEmpty ? tin : '—'} · $qty key${qty > 1 ? 's' : ''} · $when',
        ),
        if (keys.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final k in keys)
                  InkWell(
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: k));
                      if (mounted) _toast(context, 'License key copied');
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: context.brand.surfaceHi,
                        border: Border.all(color: context.brand.rule),
                      ),
                      child: Text(
                        k,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
      side: [
        Text(
          peso(r['amount']),
          style: const TextStyle(
            fontFamily: 'monospace',
            fontWeight: FontWeight.w700,
          ),
        ),
        _Pill(
          text: paid ? 'Paid' : (ps.isNotEmpty ? ps : 'Pending'),
          color: paid ? Brand.success : Brand.signal,
        ),
      ],
    );
  }

  (Color, String) _stage(Map<String, dynamic> c) {
    int n(String k) => int.tryParse('${c[k] ?? 0}') ?? 0;
    if (n('final_step') == 1) return (Brand.success, 'Completed');
    if (n('c_status') == 1 && n('step2') == 1) {
      return (Brand.signal, 'Awaiting PTU');
    }
    if (n('c_status') == 1) return (Brand.signal, 'Waiting for BIR');
    return (context.brand.paperDim, 'Submitted');
  }

  Widget _clients(VendorDetail d) {
    final counts = d.clientCounts;
    int n(String k) => int.tryParse('${counts[k] ?? 0}') ?? 0;
    final clients = d.clients;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _Mini('Total', '${n('all')}'),
            _Mini('Submitted', '${n('submitted')}'),
            _Mini('In progress', '${n('processed') + n('awaiting')}'),
            _Mini('Completed', '${n('completed')}'),
          ],
        ),
        const SizedBox(height: 12),
        if (clients.isEmpty)
          _soft(context, 'This vendor has not filed any registrations yet.')
        else ...[
          for (final c in clients) _clientRow(c),
          if (d.clientsTotal > clients.length)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _subText(
                context,
                'Showing the latest ${clients.length} of ${d.clientsTotal}.',
              ),
            ),
        ],
      ],
    );
  }

  Widget _clientRow(Map<String, dynamic> c) {
    final st = _stage(c);
    final owner = [
      '${c['first_name'] ?? ''}',
      '${c['last_name'] ?? ''}',
    ].where((s) => s.isNotEmpty).join(' ');
    final docs = int.tryParse('${c['doc_count'] ?? 0}') ?? 0;
    final filed = '${c['vendor_filed_at'] ?? ''}';
    final company = '${c['company_name'] ?? ''}';
    final tin = '${c['tin'] ?? ''}';
    final branch = '${c['branch_code'] ?? ''}';
    final id = int.tryParse('${c['id'] ?? 0}') ?? 0;
    return _ListRow(
      main: [
        _titleText(company.isNotEmpty ? company : '—'),
        _subText(
          context,
          'TIN ${tin.isNotEmpty ? tin : '—'} · Branch ${branch.isNotEmpty ? branch : '00000'}${owner.isNotEmpty ? ' · $owner' : ''}',
        ),
        _subText(
          context,
          '$docs document${docs == 1 ? '' : 's'}${filed.isNotEmpty ? ' · filed ${_fmtDate(filed)}' : ''}',
        ),
      ],
      side: [
        _Pill(text: st.$2, color: st.$1),
        GhostButton(
          onPressed: () =>
              launchUrl(Uri.parse(widget.service.taxpayerPortalUrl(id))),
          icon: Icons.open_in_new,
          label: 'Portal',
        ),
      ],
    );
  }

  Widget _activity(VendorDetail d) {
    final logs = d.logs;
    if (logs.isEmpty) return _soft(context, 'No activity recorded yet.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final l in logs) _logRow(l),
        if (d.logsTotal > logs.length)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _subText(
              context,
              'Showing the latest ${logs.length} of ${d.logsTotal}.',
            ),
          ),
      ],
    );
  }

  Widget _logRow(Map<String, dynamic> l) {
    final label = '${l['action'] ?? ''}'
        .replaceFirst(RegExp(r'^vendor_'), '')
        .replaceAll('_', ' ');
    final cap = label.isEmpty
        ? label
        : label[0].toUpperCase() + label.substring(1);
    final ip = '${l['ip_address'] ?? ''}';
    return _ListRow(
      main: [_titleText(cap), _subText(context, '${l['details'] ?? ''}')],
      side: [
        _subText(context, _fmtDate('${l['created_at'] ?? ''}', true)),
        if (ip.isNotEmpty)
          Text(
            ip,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: context.brand.paperDim,
            ),
          ),
      ],
    );
  }
}

class _InvitesPanel extends StatefulWidget {
  const _InvitesPanel({
    required this.service,
    required this.focusForm,
    required this.onClose,
    required this.onChanged,
  });
  final VendorPortalService service;
  final bool focusForm;
  final VoidCallback onClose;
  final VoidCallback onChanged;

  @override
  State<_InvitesPanel> createState() => _InvitesPanelState();
}

class _InvitesPanelState extends State<_InvitesPanel>
    with LiveRefresh<_InvitesPanel> {
  final _note = TextEditingController();
  final _price = TextEditingController();
  String _hours = '48';
  String _error = '';
  bool _busy = false;
  String _url = '';
  bool _copied = false;
  List<VendorInvite>? _invites;
  String? _listError;
  final Set<int> _revoking = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  List<String> get liveKeys => const ['vendorportal'];

  @override
  void onLiveChange() => _load(silent: true);

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _invites = null;
        _listError = null;
      });
    }
    try {
      final list = await widget.service.invites();
      if (mounted) {
        setState(() {
          _invites = list;
          _listError = null;
        });
      }
    } catch (_) {
      if (mounted && !silent) {
        setState(() => _listError = 'Could not load invites.');
      }
    }
  }

  Future<void> _create() async {
    if (_price.text.trim().isEmpty) {
      setState(() => _error = 'Set the license key price for this vendor.');
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    final res = await widget.service.createInvite(
      note: _note.text.trim(),
      price: _price.text.trim(),
      hours: _hours,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.ok) {
      setState(() => _error = res.message);
      return;
    }
    _toast(context, res.message);
    widget.onChanged();
    setState(() {
      _url = '${res.data['url'] ?? ''}';
      _note.clear();
    });
    _load();
  }

  Future<void> _revoke(VendorInvite i) async {
    if (!await _confirm(
      context,
      'Revoke invite',
      'Revoke this invite? The link stops working immediately.',
      'Revoke',
    )) {
      return;
    }
    setState(() => _revoking.add(i.id));
    final res = await widget.service.revokeInvite(i.id);
    if (!mounted) return;
    setState(() => _revoking.remove(i.id));
    _toast(context, res.message);
    if (res.ok) {
      widget.onChanged();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return WebModal(
      title: 'Vendor invites',
      subtitle: 'Registration is invite-only',
      icon: Icons.link,
      width: 760,
      height: 780,
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      onClose: widget.onClose,
      actions: [GhostButton(label: 'Close', onPressed: widget.onClose)],
      child: Container(
        color: context.brand.canvas,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _Block(
              title: 'Create an invite link',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ErrorLine(_error),
                  TextField(
                    controller: _note,
                    autofocus: widget.focusForm,
                    maxLength: 191,
                    decoration: const InputDecoration(
                      labelText: 'Who is it for? (optional)',
                      hintText: 'Company or contact name',
                      isDense: true,
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _price,
                          decoration: const InputDecoration(
                            labelText: 'Price per license key',
                            prefixText: '₱ ',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _hours,
                          isDense: true,
                          decoration: const InputDecoration(
                            labelText: 'Link expires in',
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: '24',
                              child: Text('24 hours'),
                            ),
                            DropdownMenuItem(
                              value: '48',
                              child: Text('48 hours'),
                            ),
                            DropdownMenuItem(
                              value: '72',
                              child: Text('3 days'),
                            ),
                            DropdownMenuItem(
                              value: '168',
                              child: Text('7 days'),
                            ),
                          ],
                          onChanged: (v) => setState(() => _hours = v ?? '48'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: SignalButton(
                      onPressed: _busy ? null : _create,
                      busy: _busy,
                      icon: Icons.link,
                      label: _busy ? 'Saving…' : 'Create link',
                    ),
                  ),
                  if (_url.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: context.brand.surfaceHi,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: context.brand.rule),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: SelectableText(
                              _url,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GhostButton(
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: _url),
                              );
                              if (!mounted) return;
                              setState(() => _copied = true);
                              Future.delayed(
                                const Duration(milliseconds: 1800),
                                () {
                                  if (mounted) setState(() => _copied = false);
                                },
                              );
                            },
                            icon: _copied ? Icons.check : Icons.copy,
                            label: _copied ? 'Copied' : 'Copy',
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Recent invites',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            if (_listError != null)
              _soft(context, _listError!)
            else if (_invites == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: TpLoader()),
              )
            else if (_invites!.isEmpty)
              _soft(context, 'No invites yet.')
            else
              for (final i in _invites!) _inviteRow(i),
          ],
        ),
      ),
    );
  }

  Widget _inviteRow(VendorInvite i) {
    final Widget pill = i.isActive
        ? const _Pill(text: 'Open', color: Brand.signal)
        : (i.usedByCode.isNotEmpty
              ? _Pill(text: 'Used by ${i.usedByCode}', color: Brand.success)
              : _Pill(
                  text: i.isUsed ? 'Revoked' : 'Expired',
                  color: context.brand.paperDim,
                ));
    final line2 = i.isActive
        ? 'Expires ${_fmtDate(i.expiresAt, true)}'
        : (i.usedAt.isNotEmpty ? 'Used ${_fmtDate(i.usedAt)}' : '');
    return _ListRow(
      main: [
        _titleText(i.note.isNotEmpty ? i.note : 'No note'),
        _subText(
          context,
          '${i.priceLabel} / key · by ${i.createdByName.isNotEmpty ? i.createdByName : 'staff'} · ${_fmtDate(i.createdAt)}',
        ),
        if (line2.isNotEmpty) _subText(context, line2),
      ],
      side: [
        pill,
        if (i.isActive)
          DangerButton(
            onPressed: _revoking.contains(i.id) ? null : () => _revoke(i),
            icon: Icons.close,
            label: 'Revoke',
          ),
      ],
    );
  }
}
