import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api_client.dart';
import '../../services/announcements_service.dart';
import '../../services/live_sync.dart';
import '../../theme.dart';
import '../../widgets/premium.dart';
import '../admin/admin_list.dart';
import 'portal_ui.dart';
import '../../widgets/tp_loader.dart';

const _toneColors = <String, Color>{
  'info': Color(0xFF2563EB),
  'success': Color(0xFF16A34A),
  'warning': Color(0xFFFF7D00),
  'critical': Color(0xFFDC2626),
};

Color _toneColor(String tone) => _toneColors[tone] ?? _toneColors['info']!;

const _faIcons = <String, IconData>{
  'fa-bullhorn': Icons.campaign_outlined,
  'fa-gift': Icons.card_giftcard,
  'fa-info-circle': Icons.info_outline,
  'fa-exclamation-triangle': Icons.warning_amber_outlined,
  'fa-tools': Icons.build_outlined,
  'fa-calendar-alt': Icons.event_outlined,
  'fa-shield-alt': Icons.shield_outlined,
  'fa-rocket': Icons.rocket_launch_outlined,
  'fa-graduation-cap': Icons.school_outlined,
  'fa-clock': Icons.schedule,
  'fa-file-alt': Icons.description_outlined,
  'fa-users': Icons.groups_outlined,
  'fa-star': Icons.star_outline,
  'fa-lightbulb': Icons.lightbulb_outline,
  'fa-bug': Icons.bug_report_outlined,
  'fa-server': Icons.dns_outlined,
};

IconData _icon(String fa) => _faIcons[fa] ?? Icons.campaign_outlined;

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

String _fmtDate(DateTime? d) =>
    d == null ? '' : '${_months[d.month - 1]} ${d.day}, ${d.year}';

String _fmtTime(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
}

String _fmtDateTime(DateTime? d) =>
    d == null ? '' : '${_fmtDate(d)}, ${_fmtTime(d)}';

class AnnouncementsScreen extends StatelessWidget {
  const AnnouncementsScreen({
    super.key,
    required this.api,
    required this.canManage,
  });
  final ApiClient api;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final svc = AnnouncementsService(api);
    return canManage ? _ManagePage(svc: svc) : _InboxPage(svc: svc);
  }
}

class _ManagePage extends StatefulWidget {
  const _ManagePage({required this.svc});
  final AnnouncementsService svc;

  @override
  State<_ManagePage> createState() => _ManagePageState();
}

const _statusTabs = <(String, String)>[
  ('all', 'All'),
  ('active', 'Active'),
  ('scheduled', 'Scheduled'),
  ('draft', 'Drafts'),
  ('expired', 'Expired'),
];

const _lifecycleLabels = <String, String>{
  'active': 'Active',
  'draft': 'Draft',
  'scheduled': 'Scheduled',
  'expired': 'Expired',
};

class _ManagePageState extends State<_ManagePage>
    with LiveRefresh<_ManagePage> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _status = 'all';
  bool _loading = true;
  String? _error;
  List<Announcement> _items = const [];
  Map<String, int> _counts = const {};
  int _dbOffset = 0;

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

  @override
  List<String> get liveKeys => const ['announcements'];

  @override
  void onLiveChange() => _load(silent: true);

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final status = _status, q = _search.text.trim();
    try {
      final r = await widget.svc.list(status: status, q: q);
      if (!mounted) return;
      if (silent && (status != _status || q != _search.text.trim())) return;
      setState(() {
        _items = r.items;
        _counts = r.counts;
        _dbOffset = r.dbOffset;
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

  String _window(Announcement a) {
    final from = _fmtDate(AnnouncementsService.fromDb(a.startsAt, _dbOffset));
    final to = _fmtDate(AnnouncementsService.fromDb(a.expiresAt, _dbOffset));
    if (from.isNotEmpty && to.isNotEmpty) return '$from → $to';
    if (from.isNotEmpty) return 'From $from';
    if (to.isNotEmpty) return 'Until $to';
    return 'No end date';
  }

  Future<void> _compose([Announcement? existing]) async {
    AnnOptions opts;
    try {
      opts = await widget.svc.options();
    } catch (e) {
      if (mounted) {
        toast(context, e.toString().replaceFirst('Exception: ', ''));
      }
      return;
    }
    Announcement? full = existing;
    if (existing != null) {
      full = await widget.svc.get(existing.id);
      if (full == null) {
        if (mounted) toast(context, 'Could not load that announcement.');
        return;
      }
    }
    if (!mounted) return;
    final saved = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ComposeDialog(
        svc: widget.svc,
        options: opts,
        existing: full,
        dbOffset: _dbOffset == 0 ? opts.dbOffset : _dbOffset,
      ),
    );
    if (saved == null || !mounted) return;
    toast(
      context,
      saved == 'published' ? 'Announcement published.' : 'Draft saved.',
    );
    _load();
  }

  Future<void> _toggle(Announcement a) async {
    final next = a.published ? 'draft' : 'published';
    final r = await widget.svc.setStatus(a.id, next);
    if (!mounted) return;
    toast(
      context,
      r.ok
          ? (next == 'published'
                ? 'Announcement published.'
                : 'Announcement unpublished.')
          : r.message,
    );
    if (r.ok) _load();
  }

  Future<void> _delete(Announcement a) async {
    if (!await confirmDialog(
      context,
      title: 'Delete announcement',
      message: 'Delete this announcement for good?',
    )) {
      return;
    }
    final r = await widget.svc.delete(a.id);
    if (!mounted) return;
    toast(context, r.ok ? 'Announcement deleted.' : r.message);
    if (r.ok) _load();
  }

  Future<void> _readers(Announcement a) async {
    final reset = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _ReadersDialog(svc: widget.svc, item: a, dbOffset: _dbOffset),
    );
    if (reset == true && mounted) {
      toast(context, 'Read status cleared.');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      onRefresh: _load,
      children: [
        PortalHeader(
          eyebrow: 'Super Admin',
          title: 'Announcements',
          sub:
              'Write an announcement, choose exactly who should see it, and it pops up for them the next time they open the app.',
          subMaxWidth: 390,
          alignEnd: true,
          trailing: _PrimaryButton(onTap: () => _compose()),
        ),
        Row(
          children: [
            for (var i = 0; i < _statusTabs.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              PortalTab(
                label: _statusTabs[i].$2,
                count: _counts[_statusTabs[i].$1] ?? 0,
                selected: _status == _statusTabs[i].$1,
                onTap: () {
                  setState(() => _status = _statusTabs[i].$1);
                  _load();
                },
              ),
            ],
            const SizedBox(width: 10),
            Expanded(
              child: PortalSearch(
                controller: _search,
                hint: 'Search announcements…',
                icon: false,
                height: 40,
                onChanged: (_) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 250), _load);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _body(),
      ],
    );
  }

  Widget _body() {
    if (_loading && _items.isEmpty) {
      return const _AnEmpty(
        icon: Icons.autorenew,
        label: 'Loading announcements…',
      );
    }
    if (_error != null) {
      return _AnEmpty(icon: Icons.error_outline, label: _error!);
    }
    if (_items.isEmpty) {
      return _AnEmpty(
        icon: Icons.campaign_outlined,
        label: _search.text.trim().isNotEmpty
            ? 'No announcements match that search.'
            : 'No announcements yet. Create your first one.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _items.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _AnnCard(
            item: _items[i],
            window: _window(_items[i]),
            onReaders: () => _readers(_items[i]),
            onEdit: () => _compose(_items[i]),
            onToggle: () => _toggle(_items[i]),
            onDelete: () => _delete(_items[i]),
          ),
        ],
      ],
    );
  }
}

class _PrimaryButton extends StatefulWidget {
  const _PrimaryButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          decoration: BoxDecoration(
            color: _hover ? const Color(0xFFFF8A1A) : Brand.signal,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 16, color: Colors.white),
              SizedBox(width: 8),
              Text(
                'New Announcement',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnEmpty extends StatelessWidget {
  const _AnEmpty({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return _AnBox(
      child: Column(
        children: [
          Icon(icon, size: 30, color: const Color(0xFFCBD5E1)),
          const SizedBox(height: 11),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: context.brand.paperDim),
          ),
        ],
      ),
    );
  }
}

class _AnBox extends StatelessWidget {
  const _AnBox({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
      decoration: BoxDecoration(
        color: context.brand.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.brand.rule),
      ),
      child: child,
    );
  }
}

const _toneSoft = <String, Color>{
  'info': Color(0xFFEFF6FF),
  'success': Color(0xFFF0FDF4),
  'warning': Color(0xFFFFF7ED),
  'critical': Color(0xFFFEF2F2),
};

const _chipTones = <String, PortalTone>{
  'active': PortalTone(Color(0xFFDCFCE7), Color(0xFF15803D)),
  'draft': PortalTone.muted,
  'scheduled': PortalTone.indigo,
  'expired': PortalTone.bad,
};

class _AnnCard extends StatelessWidget {
  const _AnnCard({
    required this.item,
    required this.window,
    required this.onReaders,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });
  final Announcement item;
  final String window;
  final VoidCallback onReaders;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final a = item;
    final c = _toneColor(a.tone);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final soft = dark
        ? c.withValues(alpha: 0.14)
        : (_toneSoft[a.tone] ?? _toneSoft['info']!);
    return Container(
      decoration: BoxDecoration(
        color: context.brand.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.brand.rule),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: c),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 17, 19, 17),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: soft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(_icon(a.icon), size: 19, color: c),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                a.title,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: context.brand.paper,
                                ),
                              ),
                              PortalPill(
                                _lifecycleLabels[a.lifecycle] ?? a.lifecycle,
                                _chipTones[a.lifecycle] ?? PortalTone.muted,
                                caps: true,
                              ),
                              if (a.requireAck)
                                const PortalPill(
                                  'Must acknowledge',
                                  PortalTone.warn,
                                  caps: true,
                                ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            a.body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.6,
                              height: 1.55,
                              color: dark
                                  ? context.brand.paperDim
                                  : const Color(0xFF475569),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 16,
                            runSpacing: 4,
                            children: [
                              _Meta(icon: Icons.groups, label: a.audienceLabel),
                              _Meta(
                                icon: Icons.visibility,
                                label: '${a.readCount} of ${a.reach} read',
                              ),
                              _Meta(
                                icon: Icons.calendar_month_outlined,
                                label: window,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _AnIconBtn(
                      icon: Icons.visibility,
                      tooltip: 'Who has read this',
                      onTap: onReaders,
                    ),
                    const SizedBox(width: 6),
                    _AnIconBtn(
                      icon: Icons.edit,
                      tooltip: 'Edit',
                      onTap: onEdit,
                    ),
                    const SizedBox(width: 6),
                    _AnIconBtn(
                      icon: a.published ? Icons.pause : Icons.send,
                      tooltip: a.published ? 'Unpublish' : 'Publish',
                      onTap: onToggle,
                    ),
                    const SizedBox(width: 6),
                    _AnIconBtn(
                      icon: Icons.delete,
                      tooltip: 'Delete',
                      danger: true,
                      onTap: onDelete,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnIconBtn extends StatefulWidget {
  const _AnIconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.danger = false,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool danger;

  @override
  State<_AnIconBtn> createState() => _AnIconBtnState();
}

class _AnIconBtnState extends State<_AnIconBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final hc = widget.danger ? const Color(0xFFDC2626) : Brand.signal;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: context.brand.surface,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: _hover ? hc : context.brand.rule),
            ),
            child: Icon(
              widget.icon,
              size: 15,
              color: _hover ? hc : context.brand.paperDim,
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: context.brand.paperDim),
        const SizedBox(width: 5),
        Text(label, style: portalMeta(context).copyWith(fontSize: 12.2)),
      ],
    );
  }
}

class _ComposeDialog extends StatefulWidget {
  const _ComposeDialog({
    required this.svc,
    required this.options,
    required this.existing,
    required this.dbOffset,
  });
  final AnnouncementsService svc;
  final AnnOptions options;
  final Announcement? existing;
  final int dbOffset;

  @override
  State<_ComposeDialog> createState() => _ComposeDialogState();
}

class _ComposeDialogState extends State<_ComposeDialog> {
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _body = TextEditingController(text: widget.existing?.body ?? '');
  late final _linkUrl = TextEditingController(
    text: widget.existing?.linkUrl ?? '',
  );
  late final _linkLabel = TextEditingController(
    text: widget.existing?.linkLabel ?? '',
  );
  final _people = TextEditingController();
  late String _tone = widget.existing?.tone ?? 'info';
  late String _iconName = widget.existing?.icon ?? 'fa-bullhorn';
  late String _audience = widget.existing?.audienceType ?? 'all';
  late final Set<String> _roles = {...?widget.existing?.audienceRoles};
  late final Set<int> _users = {...?widget.existing?.audienceUsers};
  late bool _requireAck = widget.existing?.requireAck ?? false;
  late DateTime? _starts = AnnouncementsService.fromDb(
    widget.existing?.startsAt ?? '',
    widget.dbOffset,
  );
  late DateTime? _expires = AnnouncementsService.fromDb(
    widget.existing?.expiresAt ?? '',
    widget.dbOffset,
  );
  int? _reach;
  Timer? _reachTimer;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (!widget.options.tones.containsKey(_tone) &&
        widget.options.tones.isNotEmpty) {
      _tone = widget.options.tones.keys.first;
    }
    _refreshReach();
  }

  @override
  void dispose() {
    _reachTimer?.cancel();
    _title.dispose();
    _body.dispose();
    _linkUrl.dispose();
    _linkLabel.dispose();
    _people.dispose();
    super.dispose();
  }

  void _refreshReach() {
    _reachTimer?.cancel();
    _reachTimer = Timer(const Duration(milliseconds: 180), () async {
      try {
        final n = await widget.svc.previewReach(
          audienceType: _audience,
          roles: _roles.toList(),
          users: _users.toList(),
        );
        if (mounted && n != null) setState(() => _reach = n);
      } catch (_) {}
    });
  }

  Future<void> _pickDate(bool start) async {
    final now = DateTime.now();
    final initial = (start ? _starts : _expires) ?? now;
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 5),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (!mounted) return;
    final v = DateTime(d.year, d.month, d.day, t?.hour ?? 0, t?.minute ?? 0);
    setState(() => start ? _starts = v : _expires = v);
  }

  Future<void> _save(String status) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await widget.svc.save(
        id: widget.existing?.id ?? 0,
        title: _title.text,
        body: _body.text,
        icon: _iconName,
        tone: _tone,
        linkUrl: _linkUrl.text,
        linkLabel: _linkLabel.text,
        audienceType: _audience,
        audienceRoles: _roles.toList(),
        audienceUsers: _users.toList(),
        status: status,
        requireAck: _requireAck,
        startsAt: AnnouncementsService.toDb(_starts, widget.dbOffset),
        expiresAt: AnnouncementsService.toDb(_expires, widget.dbOffset),
      );
      if (!mounted) return;
      if (r.ok) {
        Navigator.pop(context, status);
        return;
      }
      setState(() => _error = r.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final o = widget.options;
    final editingLive = widget.existing?.published ?? false;
    final needle = _people.text.trim();
    final people = needle.isEmpty
        ? o.staff
        : o.staff.where((s) => s.matches(needle)).toList();
    final toneC = _toneColor(_tone);
    return WebModal(
      title: widget.existing == null ? 'New Announcement' : 'Edit Announcement',
      subtitle:
          'Everyone you pick sees this as a pop-up on their next page load.',
      icon: Icons.campaign_outlined,
      width: 760,
      onClose: _busy ? () {} : null,
      bodyPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      actions: [
        GhostButton(
          label: 'Cancel',
          onPressed: _busy ? null : () => Navigator.pop(context),
        ),
        const Spacer(),
        GhostButton(
          label: 'Save as draft',
          onPressed: _busy ? null : () => _save('draft'),
        ),
        SignalButton(
          label: editingLive ? 'Save & keep live' : 'Publish',
          icon: editingLive ? Icons.check : Icons.send,
          busy: _busy,
          onPressed: _busy ? null : () => _save('published'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                border: Border.all(color: const Color(0xFFFCA5A5)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _error!,
                style: const TextStyle(color: Color(0xFFB91C1C)),
              ),
            ),
          _Labeled(
            label: 'Title',
            child: TextField(
              controller: _title,
              maxLength: 190,
              decoration: const InputDecoration(
                hintText: 'System maintenance this Saturday',
                counterText: '',
              ),
            ),
          ),
          _Labeled(
            label: 'Message',
            child: TextField(
              controller: _body,
              maxLength: 20000,
              minLines: 6,
              maxLines: 12,
              decoration: const InputDecoration(
                hintText:
                    'Write the announcement here. Line breaks are kept as you type them.',
                counterText: '',
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Labeled(
                  label: 'Tone',
                  hint: 'Sets the colour of the pop-up.',
                  child: DropdownButtonFormField<String>(
                    initialValue: o.tones.containsKey(_tone) ? _tone : null,
                    isExpanded: true,
                    isDense: true,
                    onChanged: (v) => setState(() => _tone = v ?? _tone),
                    items: [
                      for (final e in o.tones.entries)
                        DropdownMenuItem(
                          value: e.key,
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: _toneColor(e.key),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(e.value),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _Labeled(
                  label: 'Icon',
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final ic in o.icons)
                        Tooltip(
                          message: ic
                              .replaceFirst('fa-', '')
                              .replaceAll('-', ' '),
                          child: InkWell(
                            onTap: () => setState(() => _iconName = ic),
                            mouseCursor: SystemMouseCursors.click,
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: _iconName == ic
                                    ? toneC.withValues(alpha: 0.12)
                                    : context.brand.surface,
                                border: Border.all(
                                  color: _iconName == ic
                                      ? toneC
                                      : context.brand.rule,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                _icon(ic),
                                size: 18,
                                color: _iconName == ic
                                    ? toneC
                                    : context.brand.paperDim,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          _Labeled(
            label: 'Who sees this',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    for (final seg in const [
                      ('all', 'Everyone'),
                      ('roles', 'By role'),
                      ('users', 'Specific people'),
                    ]) ...[
                      _SegButton(
                        label: seg.$2,
                        selected: _audience == seg.$1,
                        onTap: () {
                          setState(() => _audience = seg.$1);
                          _refreshReach();
                        },
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
                if (_audience == 'roles') ...[
                  const SizedBox(height: 10),
                  _PickerBox(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final r in o.roles.entries)
                          SizedBox(
                            width: 210,
                            child: _CheckTile(
                              title: r.value,
                              value: _roles.contains(r.key),
                              onChanged: (v) {
                                setState(
                                  () => v
                                      ? _roles.add(r.key)
                                      : _roles.remove(r.key),
                                );
                                _refreshReach();
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                if (_audience == 'users') ...[
                  const SizedBox(height: 10),
                  _PickerBox(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SearchField(
                          controller: _people,
                          hint: 'Search people…',
                          width: null,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 8),
                        if (o.staff.isEmpty)
                          Text(
                            o.staffError.isEmpty
                                ? 'No staff accounts are available to pick.'
                                : o.staffError,
                            style: text.bodySmall,
                          )
                        else if (people.isEmpty)
                          Text(
                            'No one matches that search.',
                            style: text.bodySmall,
                          ),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 220),
                          child: SingleChildScrollView(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 2,
                              children: [
                                for (final p in people)
                                  SizedBox(
                                    width: 220,
                                    child: _CheckTile(
                                      title: p.name,
                                      subtitle: p.roleLabel,
                                      value: _users.contains(p.id),
                                      onChanged: (v) {
                                        setState(
                                          () => v
                                              ? _users.add(p.id)
                                              : _users.remove(p.id),
                                        );
                                        _refreshReach();
                                      },
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                _Meta(
                  icon: Icons.groups_outlined,
                  label: _reach == null
                      ? 'Reaches everyone on the team'
                      : (_reach == 1
                            ? 'Reaches 1 person'
                            : 'Reaches $_reach people'),
                ),
              ],
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _DateField(
                  label: 'Show from',
                  value: _starts,
                  hint: 'Leave blank to start immediately.',
                  onPick: () => _pickDate(true),
                  onClear: () => setState(() => _starts = null),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _DateField(
                  label: 'Stop showing',
                  value: _expires,
                  hint: 'Leave blank to keep it until everyone has read it.',
                  onPick: () => _pickDate(false),
                  onClear: () => setState(() => _expires = null),
                ),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Labeled(
                  label: 'Button link',
                  hint: 'Optional. Adds a button to the pop-up.',
                  child: TextField(
                    controller: _linkUrl,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      hintText: 'help or https://…',
                      counterText: '',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _Labeled(
                  label: 'Button label',
                  child: TextField(
                    controller: _linkLabel,
                    maxLength: 80,
                    decoration: const InputDecoration(
                      hintText: 'Read the guide',
                      counterText: '',
                    ),
                  ),
                ),
              ),
            ],
          ),
          _CheckTile(
            title:
                'Require acknowledgement — the pop-up cannot be dismissed until they confirm they read it.',
            bold: true,
            value: _requireAck,
            onChanged: (v) => setState(() => _requireAck = v),
          ),
        ],
      ),
    );
  }
}

class _Labeled extends StatelessWidget {
  const _Labeled({required this.label, required this.child, this.hint});
  final String label;
  final Widget child;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: text.labelLarge?.copyWith(letterSpacing: 0.8),
          ),
          const SizedBox(height: 6),
          child,
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(hint!, style: text.bodySmall?.copyWith(fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

class _SegButton extends StatelessWidget {
  const _SegButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? context.brand.signalGlow(0.08) : context.brand.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: selected ? Brand.signal : context.brand.rule),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        mouseCursor: SystemMouseCursors.click,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? Brand.signal : context.brand.paper,
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerBox extends StatelessWidget {
  const _PickerBox({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.brand.surfaceHi,
        border: Border.all(color: context.brand.rule),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}

class _CheckTile extends StatelessWidget {
  const _CheckTile({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.bold = false,
  });
  final String title;
  final String? subtitle;
  final bool value;
  final bool bold;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: () => onChanged(!value),
      mouseCursor: SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: Checkbox(
                value: value,
                activeColor: Brand.signal,
                onChanged: (v) => onChanged(v == true),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    overflow: bold ? null : TextOverflow.ellipsis,
                    style: text.bodyMedium?.copyWith(
                      fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(subtitle!, style: text.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.hint,
    required this.onPick,
    required this.onClear,
  });
  final String label;
  final DateTime? value;
  final String hint;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return _Labeled(
      label: label,
      hint: hint,
      child: InkWell(
        onTap: onPick,
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(6),
        child: InputDecorator(
          decoration: InputDecoration(
            suffixIcon: value == null
                ? const Icon(Icons.event, size: 16)
                : IconButton(
                    tooltip: 'Clear',
                    onPressed: onClear,
                    icon: const Icon(Icons.close, size: 16),
                  ),
          ),
          child: Text(
            value == null ? 'mm/dd/yyyy, --:-- --' : _fmtDateTime(value),
            style: value == null
                ? text.bodyMedium?.copyWith(color: context.brand.paperDim)
                : text.bodyMedium,
          ),
        ),
      ),
    );
  }
}

class _ReadersDialog extends StatefulWidget {
  const _ReadersDialog({
    required this.svc,
    required this.item,
    required this.dbOffset,
  });
  final AnnouncementsService svc;
  final Announcement item;
  final int dbOffset;

  @override
  State<_ReadersDialog> createState() => _ReadersDialogState();
}

class _ReadersDialogState extends State<_ReadersDialog>
    with LiveRefresh<_ReadersDialog> {
  bool _loading = true;
  List<AnnReader>? _readers;
  int _reach = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  List<String> get liveKeys => const ['announcements'];

  @override
  void onLiveChange() => _load();

  Future<void> _load() async {
    try {
      final r = await widget.svc.readers(widget.item.id);
      if (!mounted) return;
      setState(() {
        _readers = r?.readers;
        _reach = r?.reach ?? 0;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reset() async {
    if (!await confirmDialog(
      context,
      title: 'Reset read status',
      message:
          'Clear the read status so everyone sees this announcement again?',
      confirmLabel: 'Reset',
    )) {
      return;
    }
    final r = await widget.svc.resetReads(widget.item.id);
    if (!mounted) return;
    if (r.ok) {
      Navigator.pop(context, true);
    } else {
      toast(context, r.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final readers = _readers;
    return WebModal(
      title: 'Who has read this',
      subtitle: readers == null
          ? widget.item.title
          : '${readers.length} of $_reach have read it',
      icon: Icons.visibility_outlined,
      width: 520,
      height: 480,
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      actions: [
        GhostButton(
          label: 'Reset read status',
          icon: Icons.restart_alt,
          onPressed: _reset,
        ),
        const Spacer(),
        GhostButton(label: 'Close', onPressed: () => Navigator.pop(context)),
      ],
      child: _loading
          ? const Center(child: TpLoader())
          : readers == null
          ? const EmptyState(
              label: 'Could not load readers',
              hint: 'Try again later.',
            )
          : readers.isEmpty
          ? const EmptyState(
              label: 'No readers yet',
              icon: Icons.visibility_off_outlined,
              hint: 'Nobody has opened this yet.',
            )
          : ColumnResizeScope(
              tableId: 'announcements:readers',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const WebTableHeader(
                    cells: [
                      Expanded(child: Text('NAME')),
                      SizedBox(width: 60, child: Text('ACK')),
                      SizedBox(
                        width: 170,
                        child: Text('READ AT', textAlign: TextAlign.right),
                      ),
                    ],
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: readers.length,
                      itemBuilder: (_, i) {
                        final r = readers[i];
                        return WebTableRow(
                          cells: [
                            Expanded(
                              child: Text(
                                r.name.isEmpty ? 'User #${r.userId}' : r.name,
                                overflow: TextOverflow.ellipsis,
                                style: text.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 60,
                              child: r.acknowledged
                                  ? const Align(
                                      alignment: Alignment.centerLeft,
                                      child: Icon(
                                        Icons.check_circle,
                                        size: 16,
                                        color: Color(0xFF16A34A),
                                      ),
                                    )
                                  : Text('—', style: text.bodySmall),
                            ),
                            SizedBox(
                              width: 170,
                              child: Text(
                                _fmtDateTime(
                                  AnnouncementsService.fromDb(
                                    r.readAt,
                                    widget.dbOffset,
                                  ),
                                ),
                                textAlign: TextAlign.right,
                                style: text.bodySmall,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _InboxPage extends StatefulWidget {
  const _InboxPage({required this.svc});
  final AnnouncementsService svc;

  @override
  State<_InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<_InboxPage> with LiveRefresh<_InboxPage> {
  bool _loading = true;
  String? _error;
  List<InboxItem> _items = const [];
  int _dbOffset = 0;
  InboxItem? _current;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  List<String> get liveKeys => const ['announcements'];

  @override
  void onLiveChange() => _load(silent: true);

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final r = await widget.svc.inbox();
      if (!mounted) return;
      setState(() {
        _items = r.items;
        _dbOffset = r.dbOffset;
        _loading = false;
        _error = null;
        if (_current != null) {
          final match = _items.where((i) => i.id == _current!.id);
          _current = match.isEmpty ? null : match.first;
        }
      });
    } catch (e) {
      if (!mounted || silent) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  List<InboxItem> get _pending => _items.where((i) => i.isPending).toList();

  Future<void> _markRead(InboxItem item, {required bool ack}) async {
    if (!item.isPending) return;
    if (item.requireAck && !ack) return;
    final was = (item.isRead, item.isAcknowledged, item.isPending);
    setState(() {
      item.isRead = true;
      if (ack) item.isAcknowledged = true;
      item.isPending = false;
    });
    final ok = await widget.svc.markRead(item.id, acknowledged: ack);
    if (!ok && mounted) {
      setState(() {
        item.isRead = was.$1;
        item.isAcknowledged = was.$2;
        item.isPending = was.$3;
      });
      toast(context, 'Could not update the read status.');
    }
  }

  void _open(InboxItem item) {
    setState(() => _current = item);
    _markRead(item, ack: false);
  }

  void _gotIt() {
    final cur = _current;
    if (cur == null) return;
    _markRead(cur, ack: cur.requireAck);
    final next = _pending.where((i) => i.id != cur.id).toList();
    setState(() => _current = next.isEmpty ? cur : next.first);
    if (next.isNotEmpty) _markRead(next.first, ack: false);
  }

  void _markAll() {
    for (final i in _pending) {
      if (!i.requireAck) _markRead(i, ack: false);
    }
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final target = uri.hasScheme
        ? uri
        : Uri.parse(
            '${widget.svc.api.baseUrl}/${url.replaceAll(RegExp(r'^/+'), '')}',
          );
    await launchUrl(target, mode: LaunchMode.externalApplication);
  }

  String _shortDate(String raw) {
    final d = AnnouncementsService.fromDb(raw, _dbOffset);
    if (d == null) return '';
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return _fmtTime(d);
    }
    final base = '${_months[d.month - 1]} ${d.day}';
    return d.year == now.year ? base : '$base, ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final pending = _pending;
    final ackCount = _items.where((i) => i.needsAck).length;
    final bits = <String>[
      if (_items.isEmpty)
        'Nothing posted for you yet'
      else if (pending.isEmpty)
        'You’re all caught up'
      else
        '${pending.length} unread',
      if (ackCount > 0)
        '$ackCount need${ackCount == 1 ? 's' : ''} your acknowledgement',
    ];
    final clearable = pending.any((i) => !i.requireAck);
    return StationScaffold(
      stationNumber: '31',
      stationLabel: 'ANNOUNCEMENTS',
      title: 'Announcements',
      showBottomBrand: false,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (clearable) ...[
            GhostButton(
              onPressed: _markAll,
              icon: Icons.done_all,
              label: 'Mark all read',
            ),
            const SizedBox(width: 10),
          ],
          StationAction(
            icon: Icons.refresh,
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      child: _loading
          ? const Center(child: TpLoader())
          : _error != null
          ? EmptyState(label: 'Could not load', hint: _error!)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${bits.join(' · ')}${_items.isEmpty ? '' : ' · ${_items.length} total'}',
                  style: text.bodySmall,
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: _items.isEmpty
                      ? const EmptyState(
                          label: 'You’re all caught up',
                          hint:
                              'New announcements will show up here as soon as they are posted.',
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(width: 380, child: _list(text)),
                            const SizedBox(width: 16),
                            Expanded(child: _detail(text)),
                          ],
                        ),
                ),
              ],
            ),
    );
  }

  Widget _list(TextTheme text) {
    final pending = _pending;
    final earlier = _items.where((i) => !i.isPending).toList();
    return Container(
      decoration: BoxDecoration(
        color: context.brand.surface,
        border: Border.all(color: context.brand.rule),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView(
        children: [
          if (pending.isNotEmpty) _group('NEW', text),
          for (final i in pending) _row(i, text),
          if (earlier.isNotEmpty) _group('EARLIER', text),
          for (final i in earlier) _row(i, text),
        ],
      ),
    );
  }

  Widget _group(String label, TextTheme text) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
    child: Text(label, style: text.labelLarge),
  );

  Widget _row(InboxItem i, TextTheme text) {
    final c = _toneColor(i.tone);
    final selected = _current?.id == i.id;
    final snippet = i.body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return InkWell(
      onTap: () => _open(i),
      mouseCursor: SystemMouseCursors.click,
      hoverColor: context.brand.surfaceHi,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? context.brand.signalGlow(0.08) : null,
          border: Border(
            left: BorderSide(
              color: selected ? Brand.signal : Colors.transparent,
              width: 3,
            ),
            bottom: BorderSide(color: context.brand.rule),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 10,
              child: i.isPending
                  ? Container(
                      margin: const EdgeInsets.only(top: 12),
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Brand.signal,
                        shape: BoxShape.circle,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 6),
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(_icon(i.icon), size: 18, color: c),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          i.title.isEmpty ? 'Untitled' : i.title,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleSmall?.copyWith(
                            fontWeight: i.isPending
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      Text(_shortDate(i.createdAt), style: text.bodySmall),
                    ],
                  ),
                  if (snippet.isNotEmpty)
                    Text(
                      snippet,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall,
                    ),
                  if (i.needsAck)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: _Pill(
                        label: 'Needs acknowledgement',
                        color: Color(0xFFDC2626),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detail(TextTheme text) {
    final i = _current;
    if (i == null) {
      return const EmptyState(
        label: 'Select an announcement',
        hint: 'Pick one from the list to read it.',
      );
    }
    final c = _toneColor(i.tone);
    final posted = _fmtDate(
      AnnouncementsService.fromDb(i.createdAt, _dbOffset),
    );
    final meta = [
      if (i.author.isNotEmpty) 'Posted by ${i.author}',
      if (posted.isNotEmpty) posted,
    ].join(' · ');
    return Container(
      decoration: BoxDecoration(
        color: context.brand.surface,
        border: Border.all(color: context.brand.rule),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            color: c,
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_icon(i.icon), color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            (i.toneLabel.isEmpty ? 'Information' : i.toneLabel)
                                .toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              letterSpacing: 0.6,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (i.needsAck) ...[
                            const SizedBox(width: 8),
                            const Text(
                              '· ACKNOWLEDGEMENT REQUIRED',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                letterSpacing: 0.6,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        i.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (meta.isNotEmpty)
                        Text(
                          meta,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(i.body, style: text.bodyLarge),
                  if (i.linkUrl.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    GhostButton(
                      onPressed: () => _openLink(i.linkUrl),
                      icon: Icons.arrow_forward,
                      label: i.linkLabel.isEmpty ? 'Open' : i.linkLabel,
                    ),
                  ],
                ],
              ),
            ),
          ),
          Divider(height: 1, color: context.brand.rule),
          Container(
            color: context.brand.surfaceHi,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (i.isPending || i.needsAck)
                  SignalButton(
                    label: i.needsAck ? 'I understand' : 'Got it',
                    icon: Icons.check,
                    onPressed: _gotIt,
                  )
                else
                  Text(
                    i.requireAck && i.isAcknowledged ? 'Acknowledged' : 'Read',
                    style: text.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
