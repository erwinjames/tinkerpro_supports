import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api_client.dart';
import '../../services/live_sync.dart';
import '../../services/zreading_service.dart';
import '../../theme.dart';
import '../../widgets/premium.dart';
import '../../widgets/web_zbe_kit.dart';
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

String _fmtDate(DateTime? d) {
  if (d == null) return '—';
  return '${_months[d.month - 1]} ${d.day}, ${d.year}';
}

String _fmtDateTime(DateTime? d) {
  if (d == null) return '—';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ampm = d.hour < 12 ? 'AM' : 'PM';
  return '${_fmtDate(d)} · ${h.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} $ampm';
}

String _timeAgo(DateTime? d) {
  if (d == null) return '';
  final secs = DateTime.now().difference(d).inSeconds;
  if (secs < 60) return 'just now';
  if (secs < 3600) return '${secs ~/ 60}m ago';
  if (secs < 86400) return '${secs ~/ 3600}h ago';
  return '${secs ~/ 86400}d ago';
}

String _countdown(DateTime? d) {
  if (d == null) return '';
  final secs = d.difference(DateTime.now()).inSeconds;
  if (secs <= 0) return 'expired';
  return 'expires in ${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';
}

bool _isFresh(DateTime? d) =>
    d != null && DateTime.now().difference(d).inMilliseconds < 3600000;

const _statusLabel = {
  'pending': 'Waiting approval',
  'approved': 'Code issued',
  'verified': 'Unlocked',
  'denied': 'Denied',
  'expired': 'Expired',
  'blocked': 'Blocked attempt',
};

class ZReadingScreen extends StatefulWidget {
  const ZReadingScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<ZReadingScreen> createState() => _ZReadingScreenState();
}

class _ZReadingScreenState extends State<ZReadingScreen>
    with LiveRefresh<ZReadingScreen> {
  late final ZReadingService _svc = ZReadingService(widget.api);
  final _searchCtrl = TextEditingController();
  Timer? _searchTimer;
  Timer? _tickTimer;
  bool _livePending = false;
  bool _rerun = false;

  int _page = 1;
  int _limit = 10;
  int _total = 0;
  String _status = '';
  bool _flaggedOnly = false;
  bool _live = true;
  bool _busy = false;
  bool _loading = true;
  String? _error;
  int _modalDepth = 0;
  List<ZrGroup> _groups = const [];
  ZrSummary _summary = const ZrSummary();
  ZrSettings _settings = const ZrSettings();
  final Set<String> _expanded = {};
  final Set<int> _hidden = {};

  @override
  void initState() {
    super.initState();
    _load();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _modalDepth > 0) return;
      if (_livePending && _live && !_busy) {
        _livePending = false;
        _load(silent: true);
        return;
      }
      final anyLive = _groups.any(
        (g) => g.requests.any(
          (r) => r.status == 'approved' && r.passcode.isNotEmpty,
        ),
      );
      if (anyLive) setState(() {});
    });
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _tickTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  List<String> get liveKeys => const ['zreading'];

  @override
  void onLiveChange() {
    if (!_live) return;
    if (_modalDepth > 0 || _busy || (_searchTimer?.isActive ?? false)) {
      _livePending = true;
      return;
    }
    _load(silent: true);
  }

  int get _pages => _total <= 0 ? 1 : ((_total + _limit - 1) ~/ _limit);

  Future<void> _load({bool silent = false}) async {
    if (_busy) {
      if (!silent) _rerun = true;
      return;
    }
    _busy = true;
    if (!silent && _groups.isEmpty) setState(() => _loading = true);
    try {
      final res = await _svc.list(
        page: _page,
        limit: _limit,
        search: _searchCtrl.text.trim(),
        status: _status,
        flaggedOnly: _flaggedOnly,
      );
      if (!mounted) return;
      setState(() {
        _groups = res.groups;
        _total = res.total;
        _summary = res.summary;
        if (res.settings != null) _settings = res.settings!;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_groups.isEmpty) _error = '$e';
      });
      if (!silent) _toast('$e');
    } finally {
      _busy = false;
      if (_rerun && mounted) {
        _rerun = false;
        _load();
      }
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<T?> _modal<T>(WidgetBuilder builder) async {
    _modalDepth++;
    try {
      return await showDialog<T>(context: context, builder: builder);
    } finally {
      _modalDepth--;
    }
  }

  Future<bool> _confirm(
    String title,
    String message,
    String confirm, {
    bool danger = false,
  }) async {
    _modalDepth++;
    try {
      return await zbeConfirm(
        context,
        title: title,
        message: message,
        confirm: confirm,
        danger: danger,
      );
    } finally {
      _modalDepth--;
    }
  }

  ({ZrRequest request, ZrGroup group})? _find(int id) {
    for (final g in _groups) {
      for (final r in g.requests) {
        if (r.id == id) return (request: r, group: g);
      }
    }
    return null;
  }

  Future<void> _approve(ZrRequest r) async {
    final found = _find(r.id);
    final reissue = r.status != 'pending';
    final machine = found?.group.machineSerial ?? '';
    final ok = await _confirm(
      reissue ? 'Issue a new passcode?' : 'Approve this unlock request?',
      '${r.posUser.isEmpty ? 'The POS user' : r.posUser} on ${machine.isEmpty ? 'this machine' : machine} will receive a ${_settings.codeTtlMinutes}-minute passcode to enter on the POS.',
      reissue ? 'Re-issue code' : 'Approve',
    );
    if (!ok) return;
    try {
      final res = await _svc.approve(r.id);
      _load(silent: true);
      if (!mounted) return;
      await _modal<void>(
        (ctx) => _PasscodeDialog(
          approval: res,
          ttlMinutes: _settings.codeTtlMinutes,
          onCopied: () => _toast('Passcode copied'),
        ),
      );
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _deny(ZrRequest r) async {
    final ctrl = TextEditingController();
    final ok = await _modal<bool>(
      (ctx) => WebModal(
        title: 'Deny this request?',
        subtitle: r.reference,
        icon: Icons.block,
        width: 480,
        actions: [
          GhostButton(
            label: 'Cancel',
            onPressed: () => Navigator.pop(ctx, false),
          ),
          DangerButton(
            label: 'Deny',
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
        child: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Reason',
            hintText: 'Reason (optional)',
          ),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
      ),
    );
    final reason = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true) return;
    try {
      await _svc.deny(r.id, reason);
      _toast('Request denied');
      _load(silent: true);
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _trail(ZrRequest r) async {
    ZrTrail trail;
    try {
      trail = await _svc.trail(r.id);
    } catch (e) {
      _toast('$e');
      return;
    }
    if (!mounted) return;
    await _modal<void>((ctx) => _TrailDialog(trail: trail));
  }

  Future<void> _block(ZrRequest r) async {
    final ctrl = TextEditingController();
    var busy = false;
    await _modal<void>(
      (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          Future<void> submit() async {
            if (busy) return;
            setLocal(() => busy = true);
            try {
              await _svc.block(r, ctrl.text.trim());
              _toast('POS user blocked');
              if (ctx.mounted) Navigator.pop(ctx);
              _load(silent: true);
            } catch (e) {
              _toast('$e');
              if (ctx.mounted) setLocal(() => busy = false);
            }
          }

          return WebModal(
            title: 'Block POS user',
            subtitle: r.posUser,
            icon: Icons.person_off_outlined,
            width: 520,
            actions: [
              GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx)),
              DangerButton(
                label: 'Block user',
                icon: Icons.person_off,
                onPressed: busy ? null : submit,
              ),
            ],
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'POS user ${r.posUser} of ${r.clientName.isEmpty ? 'this client' : r.clientName} will no longer be able to request a Z-reading unlock from the POS application. Their attempts are still logged here so you can see them.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  onSubmitted: (_) => submit(),
                  decoration: const InputDecoration(
                    labelText: 'Reason',
                    hintText: 'e.g. repeated unlock requests without approval',
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    ctrl.dispose();
  }

  Future<void> _unblock(ZrRequest r) async {
    final ok = await _confirm(
      'Unblock this POS user?',
      '${r.posUser} will be able to request Z-reading unlocks again.',
      'Unblock',
    );
    if (!ok) return;
    try {
      await _svc.unblockRequest(r);
      _toast('POS user unblocked');
      _load(silent: true);
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _openBlocked() async {
    await _modal<void>(
      (ctx) => _BlockedDialog(
        service: _svc,
        onChanged: () {
          _toast('POS user unblocked');
          _load(silent: true);
        },
        onError: _toast,
      ),
    );
  }

  Future<void> _delete(ZrRequest r) async {
    final ok = await _confirm(
      'Delete this request record?',
      'The request and its trail are removed from the log.',
      'Delete',
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _hidden.add(r.id));
    var undone = false;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final controller = messenger.showSnackBar(
      SnackBar(
        content: const Text('Record deleted'),
        duration: const Duration(seconds: 5),
        persist: false,
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () {
            undone = true;
            if (mounted) setState(() => _hidden.remove(r.id));
          },
        ),
      ),
    );
    await controller.closed;
    if (undone) return;
    try {
      await _svc.delete(r.id);
    } catch (e) {
      _toast('$e');
    }
    if (mounted) setState(() => _hidden.remove(r.id));
    _load(silent: true);
  }

  Future<void> _logManual() async {
    await _modal<void>(
      (ctx) => _ManualDialog(
        onSubmit: (fields) async {
          try {
            final res = await _svc.logManual(fields);
            _toast(
              res.blocked
                  ? 'Logged, but that POS user is blocked (${res.reference})'
                  : 'Request logged as ${res.reference}',
            );
            _load(silent: true);
            return true;
          } catch (e) {
            _toast('$e');
            return false;
          }
        },
      ),
    );
  }

  void _onSearch(String _) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 300), () {
      _page = 1;
      _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return StationScaffold(
      stationNumber: 'ZR',
      stationLabel: 'Z-READING',
      title: 'Z-Reading Requests',
      showBottomBrand: false,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ZbePillButton(
                label: 'Blocked users (${_summary.blockedUsers})',
                icon: Icons.person_off,
                height: 42,
                onTap: _openBlocked,
              ),
              const SizedBox(width: 8),
              ZbePillButton(
                label: 'Log request',
                icon: Icons.edit,
                height: 42,
                onTap: _logManual,
              ),
              const SizedBox(width: 8),
              ZbePillButton(
                label: 'REFRESH',
                icon: Icons.sync,
                dark: true,
                height: 42,
                fontSize: 13,
                onTap: _load,
              ),
            ],
          ),
          const SizedBox(height: 6),
          _ticker(),
          const SizedBox(height: 4),
          _commandStrip(),
          const SizedBox(height: 4),
          Flexible(child: _tableCard()),
        ],
      ),
    );
  }

  Widget _ticker() {
    Widget item(IconData icon, String label, int value, {bool alert = false}) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 12, color: Brand.signal),
                const SizedBox(width: 6),
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11.2,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: context.brand.paperDim,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '$value',
              style: TextStyle(
                fontSize: 24,
                height: 1,
                fontWeight: FontWeight.w700,
                color: alert ? const Color(0xFFDC2626) : context.brand.paper,
              ),
            ),
          ],
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: context.brand.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: zbeLine(context)),
      ),
      child: Wrap(
        spacing: 36,
        runSpacing: 12,
        children: [
          item(Icons.hourglass_bottom, 'Waiting approval', _summary.pending),
          item(Icons.key, 'Code issued', _summary.approved),
          item(Icons.lock_open, 'Unlocked', _summary.verified),
          item(Icons.calendar_today, 'Requests today', _summary.today),
          item(
            Icons.warning,
            'Requesting too much',
            _summary.flaggedUsers,
            alert: _summary.flaggedUsers > 0,
          ),
          item(Icons.person_off, 'Blocked users', _summary.blockedUsers),
        ],
      ),
    );
  }

  Widget _commandStrip() {
    return Row(
      children: [
        Expanded(
          child: ZbePillSearch(
            controller: _searchCtrl,
            hint: 'Search reference, client, TIN, machine, POS user...',
            onChanged: _onSearch,
          ),
        ),
        const SizedBox(width: 12),
        ZbePillSelect<String>(
          value: _status,
          width: 160,
          items: [
            const DropdownMenuItem(value: '', child: Text('All statuses')),
            for (final e in _statusLabel.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) {
            setState(() => _status = v ?? '');
            _page = 1;
            _load();
          },
        ),
        const SizedBox(width: 12),
        ZbePillButton(
          label: 'Over-requesting only',
          icon: Icons.warning,
          on: _flaggedOnly,
          height: 44,
          onTap: () {
            setState(() => _flaggedOnly = !_flaggedOnly);
            _page = 1;
            _load();
          },
        ),
        const SizedBox(width: 12),
        ZbePillButton(
          label: 'Expand all',
          icon: Icons.keyboard_double_arrow_down,
          height: 44,
          onTap: () =>
              setState(() => _expanded.addAll(_groups.map((g) => g.key))),
        ),
        const SizedBox(width: 12),
        ZbePillButton(
          label: 'Collapse all',
          icon: Icons.keyboard_double_arrow_up,
          height: 44,
          onTap: () => setState(_expanded.clear),
        ),
        const SizedBox(width: 12),
        ZbePillButton(
          label: 'Live',
          icon: Icons.satellite_alt,
          on: _live,
          height: 44,
          onTap: () {
            final v = !_live;
            setState(() => _live = v);
            _livePending = false;
            if (v) _load(silent: true);
            _toast(v ? 'Live updates on' : 'Live updates paused');
          },
        ),
      ],
    );
  }

  static const _wReq = 150.0;
  static const _wWait = 130.0;
  static const _wFlag = 160.0;
  static const _wToggle = 60.0;

  Widget _th(String label, {int? flex, double? width}) {
    final t = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        label.toUpperCase(),
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10.9,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
          color: context.brand.paperDim,
        ),
      ),
    );
    if (width != null) return SizedBox(width: width, child: t);
    return Expanded(flex: flex ?? 1, child: t);
  }

  Widget _tableCard() {
    Widget body;
    if (_loading) {
      body = const SizedBox(height: 140, child: ZbeStateView(loading: true));
    } else if (_error != null && _groups.isEmpty) {
      body = SizedBox(
        height: 260,
        child: ZbeStateView(loading: false, error: _error, onRetry: _load),
      );
    } else if (_groups.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt, size: 32, color: zbeLine(context)),
            const SizedBox(height: 10),
            Text(
              'No Z-reading unlock requests yet.',
              style: TextStyle(fontSize: 13.6, color: context.brand.paperDim),
            ),
          ],
        ),
      );
    } else {
      body = ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          for (final g in _groups) ...[
            _parentRow(g),
            if (_expanded.contains(g.key)) _childBlock(g),
          ],
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: context.brand.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: zbeLine(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ColumnResizeScope(
        tableId: 'zreading:groups',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 46,
              decoration: BoxDecoration(
                color: zbeDark(context)
                    ? context.brand.surfaceHi
                    : const Color(0xFFFAFAF9),
                border: Border(bottom: BorderSide(color: zbeLine(context))),
              ),
              child: Builder(
                builder: (context) => Row(
                  children: resizableRowCells(context, [
                    const SizedBox(width: _wToggle),
                    _th('Client', flex: 57),
                    _th('POS Machine', flex: 27),
                    _th('Requests', width: _wReq),
                    _th('Last request', flex: 31),
                    _th('Waiting', width: _wWait),
                    _th('Flag', width: _wFlag),
                  ], header: true),
                ),
              ),
            ),
            Flexible(child: body),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _sub(String s) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Text(
      s,
      style: TextStyle(fontSize: 11.5, color: context.brand.paperDim),
    ),
  );

  Widget _dash() => Text(
    '—',
    style: TextStyle(fontSize: 13.6, color: context.brand.paperDim),
  );

  Widget _statusChip(String status, {bool fresh = false}) {
    const map = {
      'pending': (Color(0xFFFFF4E5), Color(0xFFB45309)),
      'approved': (Color(0xFFE0F2FE), Color(0xFF0369A1)),
      'verified': (Color(0xFFDCFCE7), Color(0xFF15803D)),
      'denied': (Color(0xFFFEE2E2), Color(0xFFB91C1C)),
      'expired': (Color(0xFFF1F5F9), Color(0xFF475569)),
      'blocked': (Color(0xFFEDE9FE), Color(0xFF6D28D9)),
    };
    final c = map[status] ?? map['expired']!;
    return ZbeWebChip(_statusLabel[status] ?? status, c.$1, c.$2);
  }

  Widget _blockedChip(String label) =>
      ZbeWebChip(label, const Color(0xFFEDE9FE), const Color(0xFF6D28D9));

  Widget _cell(Widget child, {int? flex, double? width, double opacity = 1}) {
    Widget w = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Align(alignment: Alignment.centerLeft, child: child),
    );
    if (opacity < 1) w = Opacity(opacity: opacity, child: w);
    if (width != null) return SizedBox(width: width, child: w);
    return Expanded(flex: flex ?? 1, child: w);
  }

  Widget _parentRow(ZrGroup g) {
    final open = _expanded.contains(g.key);
    final waiting = g.pendingCount > 0;
    final liveCode = g.requests.any(
      (r) => r.status == 'approved' && r.codeActive,
    );
    final settled = !waiting && !liveCode && !open;
    final dim = settled ? 0.55 : 1.0;
    final soft = settled ? 0.78 : 1.0;
    final tinLabel =
        'TIN ${g.tin.isNotEmpty ? g.tin : (g.tinBase.isNotEmpty ? g.tinBase : '—')}${g.branch.isNotEmpty ? ' · Branch ${g.branch}' : ''}';
    final dark = zbeDark(context);

    return ZbeRow(
      padding: const EdgeInsets.symmetric(vertical: 14.4),
      minHeight: 73,
      accent: g.flagged
          ? const Color(0xFFDC2626)
          : (waiting ? Brand.signal : null),
      ruleColor: zbeSoftLine(context),
      color: open
          ? (dark
                ? Color.alphaBlend(
                    Brand.signal.withValues(alpha: 0.08),
                    context.brand.surface,
                  )
                : const Color(0xFFFFF7EF))
          : null,
      hoverColor: dark
          ? Color.alphaBlend(
              Brand.signal.withValues(alpha: 0.05),
              context.brand.surface,
            )
          : const Color(0xFFFDF8F3),
      onTap: () => setState(() {
        if (open) {
          _expanded.remove(g.key);
        } else {
          _expanded.add(g.key);
        }
      }),
      cells: [
        SizedBox(
          width: _wToggle - 3,
          child: Opacity(
            opacity: soft,
            child: Padding(
              padding: const EdgeInsets.only(left: 13),
              child: Align(
                alignment: Alignment.centerLeft,
                child: AnimatedRotation(
                  turns: open ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: context.brand.surface,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: open ? Brand.signal : zbeLine(context),
                      ),
                    ),
                    child: Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: open ? Brand.signal : context.brand.paper,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        _cell(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                g.clientName.isEmpty ? 'Unknown client' : g.clientName,
                style: const TextStyle(
                  fontSize: 13.6,
                  fontWeight: FontWeight.w700,
                ),
              ),
              _sub(tinLabel),
            ],
          ),
          flex: 57,
          opacity: soft,
        ),
        _cell(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                g.machineSerial.isEmpty ? 'UNSPECIFIED' : g.machineSerial,
                style: const TextStyle(
                  fontSize: 13.6,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              if (g.terminalId.isNotEmpty) _sub('Terminal ${g.terminalId}'),
            ],
          ),
          flex: 27,
          opacity: dim,
        ),
        _cell(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ZbeCountPill('${g.totalRequests}'),
                  const SizedBox(width: 4),
                  const Text('total', style: TextStyle(fontSize: 13.6)),
                ],
              ),
              _sub('${g.recentCount} in last ${_settings.warnWindowHours}h'),
            ],
          ),
          width: _wReq,
          opacity: dim,
        ),
        _cell(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _fmtDateTime(g.lastRequestedAt),
                style: const TextStyle(fontSize: 13.6),
              ),
              _sub(_timeAgo(g.lastRequestedAt)),
            ],
          ),
          flex: 31,
          opacity: dim,
        ),
        _cell(
          waiting
              ? ZbeWebChip(
                  '${g.pendingCount} waiting',
                  const Color(0xFFFFF4E5),
                  const Color(0xFFB45309),
                )
              : _dash(),
          width: _wWait,
          opacity: dim,
        ),
        _cell(
          g.flagged
              ? const ZbeWebChip(
                  'Too many',
                  Color(0xFFFEE2E2),
                  Color(0xFFB91C1C),
                  icon: Icons.warning,
                )
              : (g.blockedUsers.isNotEmpty
                    ? _blockedChip('User blocked')
                    : _dash()),
          width: _wFlag - 3,
          opacity: dim,
        ),
      ],
    );
  }

  Widget _childBlock(ZrGroup g) {
    final rows = g.requests.where((r) => !_hidden.contains(r.id)).toList();
    final dark = zbeDark(context);

    Widget th(String l, int flex, {TextAlign? align}) => Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13.6),
        child: Text(
          l.toUpperCase(),
          textAlign: align,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: context.brand.paperDim,
          ),
        ),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: dark ? context.brand.canvas : const Color(0xFFFBFBFA),
        border: Border(bottom: BorderSide(color: zbeSoftLine(context))),
      ),
      padding: const EdgeInsets.fromLTRB(52, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'UNLOCK REQUESTS (${g.requests.length}${g.hasMore ? ' OF ${g.totalRequests}' : ''})',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 11.5,
              letterSpacing: 1.4,
              color: Brand.signal,
            ),
          ),
          const SizedBox(height: 10),
          if (g.flagged)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: zbeTint(
                  context,
                  const Color(0xFFFEF2F2),
                  const Color(0xFFDC2626),
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning, size: 14, color: Color(0xFFB91C1C)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${g.recentCount} unlock requests in the last ${_settings.warnWindowHours} hours from this machine — threshold is ${_settings.warnThreshold}. Consider blocking the POS user if this keeps up.',
                      style: const TextStyle(
                        fontSize: 12.2,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFB91C1C),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (g.blockedUsers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Blocked users:',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.brand.paperDim,
                    ),
                  ),
                  for (final u in g.blockedUsers) _blockedChip(u),
                ],
              ),
            ),
          Container(
            decoration: BoxDecoration(
              color: context.brand.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: zbeLine(context)),
            ),
            clipBehavior: Clip.antiAlias,
            child: ColumnResizeScope(
              tableId: 'zreading:requests',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 36,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: zbeLine(context)),
                      ),
                    ),
                    child: Builder(
                      builder: (context) => Row(
                        children: resizableRowCells(context, [
                          const SizedBox(width: 3),
                          th('Reference', 14),
                          th('When', 14),
                          th('Requested by', 13),
                          th('Business date', 10),
                          th('Status', 13),
                          th('Passcode', 13),
                          th('Tries', 6),
                          SizedBox(
                            width: 110,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 13.6,
                              ),
                              child: Text(
                                'ACTION',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                  color: context.brand.paperDim,
                                ),
                              ),
                            ),
                          ),
                        ], header: true),
                      ),
                    ),
                  ),
                  if (rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No requests logged.',
                        style: TextStyle(
                          fontSize: 12.6,
                          color: context.brand.paperDim,
                        ),
                      ),
                    )
                  else
                    for (var i = 0; i < rows.length; i++)
                      _requestRow(rows[i], last: i == rows.length - 1),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _requestRow(ZrRequest r, {bool last = false}) {
    final status = r.status;
    final fresh = status == 'pending' && _isFresh(r.requestedAt);
    final active = status == 'approved' && r.codeActive;
    final muted = status != 'pending' && !active;
    const td = TextStyle(fontSize: 12.6);

    Widget cell(Widget child, int flex) => Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13.6),
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    );

    Widget code;
    if (status == 'approved' && r.passcode.isNotEmpty) {
      code = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SelectableText(
            r.passcode,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: 3.5,
              color: Color(0xFF0369A1),
            ),
          ),
          Text(
            '${_countdown(r.codeExpiresAt)} · ${r.codeDeliveredAt != null ? 'sent to POS' : 'not fetched yet'}',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: context.brand.paperDim,
            ),
          ),
        ],
      );
    } else if (status == 'verified') {
      code = Text(
        'used ${_fmtDateTime(r.verifiedAt)}',
        style: TextStyle(fontSize: 11.5, color: context.brand.paperDim),
      );
    } else {
      code = _dash();
    }

    final row = ZbeRow(
      padding: const EdgeInsets.symmetric(vertical: 9.6),
      minHeight: 40,
      ruleColor: last
          ? Colors.transparent
          : (zbeDark(context) ? context.brand.rule : const Color(0xFFF4F4F2)),
      accent: status == 'pending'
          ? Brand.signal
          : (active ? const Color(0xFF38BDF8) : null),
      color: status == 'pending'
          ? zbeTint(context, const Color(0xFFFFF8EF), Brand.signal, 0.06)
          : null,
      onTap: () => _trail(r),
      cells: [
        cell(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    r.reference,
                    style: const TextStyle(
                      fontSize: 12.6,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  if (status == 'pending') ...[
                    const SizedBox(width: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: Brand.signal,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: fresh
                            ? [
                                BoxShadow(
                                  color: Brand.signal.withValues(alpha: 0.35),
                                  blurRadius: 6,
                                ),
                              ]
                            : null,
                      ),
                      child: const Text(
                        'NEW',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9.3,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (r.reason.isNotEmpty) _sub(r.reason),
            ],
          ),
          14,
        ),
        cell(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_fmtDateTime(r.requestedAt), style: td),
              _sub(_timeAgo(r.requestedAt)),
            ],
          ),
          14,
        ),
        cell(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    r.posUser.isEmpty ? 'Unknown' : r.posUser,
                    style: td.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (r.isBlockedUser) _blockedChip('Blocked'),
                ],
              ),
              if (r.source == 'manual') _sub('logged by staff'),
            ],
          ),
          13,
        ),
        cell(
          r.businessDate == null
              ? _dash()
              : Text(_fmtDate(r.businessDate), style: td),
          10,
        ),
        cell(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _statusChip(status, fresh: fresh),
              if (status == 'approved' && r.approvedByName.isNotEmpty)
                _sub('by ${r.approvedByName}'),
              if (status == 'denied' && r.deniedByName.isNotEmpty)
                _sub(
                  'by ${r.deniedByName}${r.denyReason.isNotEmpty ? ' — ${r.denyReason}' : ''}',
                ),
            ],
          ),
          13,
        ),
        cell(code, 13),
        cell(
          r.attempts > 0
              ? ZbeCountPill(
                  '${r.attempts}',
                  hot: r.attempts >= _settings.maxAttempts,
                )
              : _dash(),
          6,
        ),
        SizedBox(
          width: 110,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13.6),
            child: Align(alignment: Alignment.centerRight, child: _actions(r)),
          ),
        ),
      ],
    );
    return muted ? _MutedHover(child: row) : row;
  }

  Widget _actions(ZrRequest r) {
    final reissue =
        r.status == 'approved' || r.status == 'expired' || r.status == 'denied';
    PopupMenuItem<String> item(
      String value,
      IconData icon,
      String label, {
      Color? color,
      Color? iconColor,
    }) => PopupMenuItem(
      value: value,
      height: 40,
      child: Row(
        children: [
          Icon(
            icon,
            size: 17,
            color: iconColor ?? color ?? context.brand.paperDim,
          ),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(fontSize: 14, color: color)),
        ],
      ),
    );
    return PopupMenuButton<String>(
      tooltip: 'Actions',
      position: PopupMenuPosition.under,
      onOpened: () => _modalDepth++,
      onCanceled: () => _modalDepth--,
      onSelected: (v) {
        _modalDepth--;
        switch (v) {
          case 'approve':
            _approve(r);
          case 'deny':
            _deny(r);
          case 'trail':
            _trail(r);
          case 'block':
            _block(r);
          case 'unblock':
            _unblock(r);
          case 'delete':
            _delete(r);
        }
      },
      itemBuilder: (_) => [
        if (r.status != 'verified')
          item(
            'approve',
            Icons.key,
            reissue ? 'Re-issue passcode' : 'Approve & generate passcode',
            iconColor: const Color(0xFF16A34A),
          ),
        if (r.status == 'pending' || r.status == 'approved')
          item(
            'deny',
            Icons.block,
            'Deny request',
            color: const Color(0xFFDC2626),
          ),
        item('trail', Icons.history, 'View trail'),
        if (r.isBlockedUser)
          item('unblock', Icons.how_to_reg, 'Unblock this POS user')
        else
          item(
            'block',
            Icons.person_off,
            'Block this POS user',
            color: const Color(0xFFDC2626),
          ),
        item('delete', Icons.delete_outline, 'Delete record'),
      ],
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.brand.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: zbeLine(context)),
        ),
        child: Icon(Icons.more_vert, size: 16, color: context.brand.paper),
      ),
    );
  }

  Widget _footer() {
    final first = _total == 0 ? 0 : ((_page - 1) * _limit) + 1;
    final last = (_page * _limit) > _total ? _total : _page * _limit;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13.6),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: zbeLine(context))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Showing $first-$last of $_total client/machine group(s)',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: context.brand.paperDim),
            ),
          ),
          ZbePillSelect<int>(
            value: const [10, 15, 25, 50].contains(_limit) ? _limit : 10,
            width: 110,
            height: 34,
            items: [
              for (final n in const [10, 15, 25, 50])
                DropdownMenuItem(value: n, child: Text('$n / page')),
            ],
            onChanged: (v) {
              if (v == null) return;
              _limit = v;
              _page = 1;
              _load();
            },
          ),
          const SizedBox(width: 6),
          ZbeCircleButton(
            icon: Icons.chevron_left,
            onTap: _page > 1
                ? () {
                    _page -= 1;
                    _load();
                  }
                : null,
          ),
          const SizedBox(width: 6),
          Text(
            '$_page / $_pages',
            style: TextStyle(fontSize: 12.5, color: context.brand.paperDim),
          ),
          const SizedBox(width: 6),
          ZbeCircleButton(
            icon: Icons.chevron_right,
            onTap: _page < _pages
                ? () {
                    _page += 1;
                    _load();
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

class _MutedHover extends StatefulWidget {
  const _MutedHover({required this.child});
  final Widget child;

  @override
  State<_MutedHover> createState() => _MutedHoverState();
}

class _MutedHoverState extends State<_MutedHover> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Opacity(opacity: _hover ? 1 : 0.45, child: widget.child),
    );
  }
}

class _PasscodeDialog extends StatelessWidget {
  const _PasscodeDialog({
    required this.approval,
    required this.ttlMinutes,
    required this.onCopied,
  });
  final ZrApproval approval;
  final int ttlMinutes;
  final VoidCallback onCopied;

  @override
  Widget build(BuildContext context) {
    return WebModal(
      title: 'Passcode generated',
      subtitle: approval.reference,
      icon: Icons.key,
      width: 480,
      actions: [
        GhostButton(
          label: 'Copy code',
          icon: Icons.copy,
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: approval.passcode));
            onCopied();
          },
        ),
        SignalButton(label: 'Done', onPressed: () => Navigator.pop(context)),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Brand.signal.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Brand.signal.withValues(alpha: 0.4)),
            ),
            child: SelectableText(
              approval.passcode,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 36,
                fontWeight: FontWeight.w700,
                letterSpacing: 8,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Sent to ${approval.posUser} on the POS machine for ${approval.clientName}.\nReference ${approval.reference} · valid for $ttlMinutes minutes (${approval.expiresAt}).',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _TrailDialog extends StatelessWidget {
  const _TrailDialog({required this.trail});
  final ZrTrail trail;

  @override
  Widget build(BuildContext context) {
    final r = trail.request;
    final dim = TextStyle(fontSize: 12.5, color: context.brand.paperDim);
    Widget meta(String k, String v) => SizedBox(
      width: 200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            k.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: context.brand.paperDim,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            v.isEmpty ? '—' : v,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
    return WebModal(
      title: 'Request trail',
      subtitle: r.reference,
      icon: Icons.history,
      width: 720,
      actions: [
        SignalButton(label: 'Close', onPressed: () => Navigator.pop(context)),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.brand.surfaceHi,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.brand.rule),
            ),
            child: Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                meta(
                  'Client',
                  r.clientName.isEmpty ? 'Unknown client' : r.clientName,
                ),
                meta('TIN', r.tin),
                meta('Machine', r.machineSerial),
                meta('POS user', r.posUser),
                meta('Status', _statusLabel[r.status] ?? r.status),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (trail.events.isEmpty)
            Text('No events recorded.', style: dim)
          else
            for (var i = 0; i < trail.events.length; i++)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: i == trail.events.length - 1
                      ? null
                      : Border(bottom: BorderSide(color: context.brand.rule)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 5, right: 12),
                      child: Icon(Icons.circle, size: 9, color: Brand.signal),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            trail.events[i].event,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '${_fmtDateTime(trail.events[i].createdAt)} · ${trail.events[i].actor.isEmpty ? 'system' : trail.events[i].actor} (${trail.events[i].actorType})${trail.events[i].ip.isNotEmpty ? ' · ${trail.events[i].ip}' : ''}',
                            style: dim,
                          ),
                          if (trail.events[i].detail.isNotEmpty)
                            Text(trail.events[i].detail, style: dim),
                        ],
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

class _BlockedDialog extends StatefulWidget {
  const _BlockedDialog({
    required this.service,
    required this.onChanged,
    required this.onError,
  });
  final ZReadingService service;
  final VoidCallback onChanged;
  final void Function(String) onError;

  @override
  State<_BlockedDialog> createState() => _BlockedDialogState();
}

class _BlockedDialogState extends State<_BlockedDialog>
    with LiveRefresh<_BlockedDialog> {
  List<ZrBlock>? _blocks;
  String? _error;

  @override
  List<String> get liveKeys => const ['zreading'];

  @override
  void onLiveChange() => _load();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final b = await widget.service.blocks();
      if (mounted) setState(() => _blocks = b);
    } catch (e) {
      if (mounted && _blocks == null) setState(() => _error = '$e');
    }
  }

  Future<void> _unblock(ZrBlock b) async {
    try {
      await widget.service.unblockById(b.id);
      widget.onChanged();
      await _load();
    } catch (e) {
      widget.onError('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final dim = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: context.brand.paperDim);
    Widget content;
    if (_error != null) {
      content = Text(_error!);
    } else if (_blocks == null) {
      content = const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: TpLoader(strokeWidth: 2, color: Brand.signal),
        ),
      );
    } else if (_blocks!.isEmpty) {
      content = Text('No POS user is blocked right now.', style: dim);
    } else {
      content = Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.brand.rule),
        ),
        clipBehavior: Clip.antiAlias,
        child: ColumnResizeScope(
          tableId: 'zreading:blocks',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const WebTableHeader(
                cells: [
                  ZbeHead('POS user', flex: 2),
                  ZbeHead('Client / Machine', flex: 3),
                  ZbeHead('Blocked', flex: 3),
                  ZbeHead('', width: 110),
                ],
              ),
              for (final b in _blocks!)
                ZbeRow(
                  cells: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        b.posUser,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            b.clientName.isEmpty
                                ? 'Unknown client'
                                : b.clientName,
                          ),
                          Text(
                            'TIN ${b.tinBase.isEmpty ? '—' : b.tinBase}${b.machineSerial.isNotEmpty ? ' · ${b.machineSerial}' : ''}',
                            style: dim,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_fmtDateTime(b.blockedAt)),
                          Text(
                            'by ${b.blockedByName.isEmpty ? 'staff' : b.blockedByName}${b.reason.isNotEmpty ? ' — ${b.reason}' : ''}',
                            style: dim,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 110,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: GhostButton(
                          label: 'Unblock',
                          icon: Icons.how_to_reg,
                          onPressed: () => _unblock(b),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      );
    }
    return WebModal(
      title: 'Blocked POS users',
      subtitle: 'These POS users cannot request a Z-reading unlock.',
      icon: Icons.person_off_outlined,
      width: 820,
      actions: [
        SignalButton(label: 'Close', onPressed: () => Navigator.pop(context)),
      ],
      child: content,
    );
  }
}

class _ManualDialog extends StatefulWidget {
  const _ManualDialog({required this.onSubmit});
  final Future<bool> Function(Map<String, String> fields) onSubmit;

  @override
  State<_ManualDialog> createState() => _ManualDialogState();
}

class _ManualDialogState extends State<_ManualDialog> {
  final _form = GlobalKey<FormState>();
  final _client = TextEditingController();
  final _tin = TextEditingController();
  final _machine = TextEditingController();
  final _terminal = TextEditingController();
  final _posUser = TextEditingController();
  final _date = TextEditingController();
  final _reason = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [
      _client,
      _tin,
      _machine,
      _terminal,
      _posUser,
      _date,
      _reason,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2015),
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null) {
      _date.text =
          '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _submit() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    final ok = await widget.onSubmit(<String, String>{
      'client_name': _client.text.trim(),
      'tin': _tin.text.trim(),
      'machine_serial': _machine.text.trim(),
      'terminal_id': _terminal.text.trim(),
      'pos_user': _posUser.text.trim(),
      'business_date': _date.text.trim(),
      'reason': _reason.text.trim(),
    });
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget pair(Widget a, Widget b) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: a),
        const SizedBox(width: 14),
        Expanded(child: b),
      ],
    );
    return WebModal(
      title: 'Log a request manually',
      subtitle: 'Record an unlock request that came in by phone or chat.',
      icon: Icons.edit_note,
      width: 720,
      actions: [
        GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
        SignalButton(
          label: 'Log request',
          icon: Icons.check,
          onPressed: _busy ? null : _submit,
        ),
      ],
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            pair(
              TextFormField(
                controller: _client,
                autofocus: true,
                validator: _required,
                decoration: const InputDecoration(
                  labelText: 'Client / Company *',
                ),
              ),
              TextFormField(
                controller: _tin,
                validator: _required,
                decoration: const InputDecoration(
                  labelText: 'TIN *',
                  hintText: '000-000-000-00000',
                ),
              ),
            ),
            const SizedBox(height: 14),
            pair(
              TextFormField(
                controller: _machine,
                decoration: const InputDecoration(
                  labelText: 'POS machine / serial',
                ),
              ),
              TextFormField(
                controller: _terminal,
                decoration: const InputDecoration(labelText: 'Terminal ID'),
              ),
            ),
            const SizedBox(height: 14),
            pair(
              TextFormField(
                controller: _posUser,
                validator: _required,
                decoration: const InputDecoration(
                  labelText: 'Requested by (POS user) *',
                ),
              ),
              TextFormField(
                controller: _date,
                readOnly: true,
                onTap: _pickDate,
                mouseCursor: SystemMouseCursors.click,
                decoration: const InputDecoration(
                  labelText: 'Business date',
                  hintText: 'YYYY-MM-DD',
                  suffixIcon: Icon(Icons.calendar_today, size: 16),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _reason,
              decoration: const InputDecoration(
                labelText: 'Reason',
                hintText:
                    'e.g. terminal shut down before the Z-read was printed',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
