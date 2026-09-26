import 'dart:async';

import 'package:flutter/material.dart';

import '../../api_client.dart';
import '../../services/feedback_service.dart';
import '../../services/live_sync.dart';
import '../../theme.dart';
import '../../widgets/premium.dart';
import '../admin/admin_list.dart';
import 'op_page_header.dart';
import '../../widgets/tp_loader.dart';

String _timeAgo(String raw) {
  if (raw.isEmpty) return '';
  final d = DateTime.tryParse(raw.replaceFirst(' ', 'T'));
  if (d == null) return raw;
  final diff = DateTime.now().difference(d).inSeconds;
  final s = diff < 0 ? 0 : diff;
  if (s < 60) return 'just now';
  if (s < 3600) return '${s ~/ 60}m ago';
  if (s < 86400) return '${s ~/ 3600}h ago';
  if (s < 2592000) return '${s ~/ 86400}d ago';
  return '${d.month}/${d.day}/${d.year}';
}

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .take(2);
  final out = parts.map((p) => p[0].toUpperCase()).join();
  return out.isEmpty ? '?' : out;
}

class FeedbackInboxScreen extends StatefulWidget {
  const FeedbackInboxScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<FeedbackInboxScreen> createState() => _FeedbackInboxScreenState();
}

class _FeedbackInboxScreenState extends State<FeedbackInboxScreen>
    with LiveRefresh<FeedbackInboxScreen> {
  late final FeedbackService _svc = FeedbackService(widget.api);
  final _search = TextEditingController();
  Timer? _debounce;
  String _status = '';
  String _category = '';
  bool _loading = true;
  String? _error;
  FeedbackPage? _page;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  List<String> get liveKeys => const ['feedbackinbox'];

  @override
  void onLiveChange() => _load(quiet: true);

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final p = await _svc.list(
        status: _status,
        category: _category,
        search: _search.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _page = p;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || quiet) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _setStatus(FeedbackEntry f, String status) async {
    final r = await _svc.setStatus(id: f.id, status: status, note: f.adminNote);
    if (!mounted) return;
    toast(context, r.message);
    _load(quiet: true);
  }

  Future<void> _note(FeedbackEntry f) async {
    final ctrl = TextEditingController(text: f.adminNote);
    final who = f.userName.isEmpty ? 'this user' : f.userName;
    final ok = await showWebModal<bool>(
      context,
      title: f.adminNote.isEmpty
          ? 'Add an internal note'
          : 'Edit internal note',
      icon: Icons.edit_note,
      width: 560,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Only super admins see this. It stays on the feedback from $who.',
            style: Theme.of(ctx).textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: ctrl,
            autofocus: true,
            maxLength: 4000,
            minLines: 5,
            maxLines: 10,
            decoration: const InputDecoration(
              hintText: 'What did you find, or what happens next?',
            ),
          ),
        ],
      ),
      actions: (ctx) => [
        GhostButton(
          label: 'Cancel',
          onPressed: () => Navigator.pop(ctx, false),
        ),
        SignalButton(
          label: f.adminNote.isEmpty ? 'Add note' : 'Save note',
          onPressed: () => Navigator.pop(ctx, true),
        ),
      ],
    );
    final note = ctrl.text;
    ctrl.dispose();
    if (ok != true) return;
    final r = await _svc.setStatus(
      id: f.id,
      status: f.status.isEmpty ? 'reviewed' : f.status,
      note: note,
    );
    if (!mounted) return;
    toast(context, r.message);
    _load(quiet: true);
  }

  Future<void> _delete(FeedbackEntry f) async {
    final who = f.userName.isEmpty ? 'this user' : f.userName;
    if (!await confirmDialog(
      context,
      title: 'Delete this feedback?',
      message:
          'The message from $who and any attached images will be removed for good.',
    )) {
      return;
    }
    final r = await _svc.delete(f.id);
    if (!mounted) return;
    toast(context, r.message);
    _load(quiet: true);
  }

  void _openImage(FeedbackAttachment a) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black87,
        insetPadding: const EdgeInsets.all(32),
        child: GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: InteractiveViewer(
                  child: Image.network(
                    _svc.attachmentUrl(a.id),
                    headers: _svc.authHeaders,
                    errorBuilder: (_, _, _) => const Padding(
                      padding: EdgeInsets.all(40),
                      child: Icon(
                        Icons.broken_image,
                        color: Colors.white70,
                        size: 48,
                      ),
                    ),
                  ),
                ),
              ),
              if (a.name.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    a.name,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.brand.canvas,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Brand.signal, width: 4)),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(11, 14, 11, 32),
          children: [
            _header(),
            const SizedBox(height: 16),
            _stats(),
            const SizedBox(height: 18),
            _toolbar(),
            const SizedBox(height: 14),
            ..._list(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'SUPER ADMIN',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.7,
                  color: Brand.signal,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Feedback',
                style: TextStyle(
                  fontSize: 33,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  height: 1.15,
                  color: context.brand.paper,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Everything users have sent through the Feedback button in the sidebar.',
                style: TextStyle(fontSize: 13, color: context.brand.paperDim),
              ),
            ],
          ),
        ),
        OpPillButton(
          label: 'Refresh',
          icon: Icons.sync,
          dense: true,
          onPressed: _load,
        ),
      ],
    );
  }

  Widget _stats() {
    final st = _page?.stats;
    final cells = <(String, String, bool)>[
      ('Total', '${st?.total ?? 0}', false),
      ('New', '${st?.fresh ?? 0}', true),
      ('In progress', '${st?.inProgress ?? 0}', false),
      ('Resolved', '${st?.resolved ?? 0}', false),
      ('Avg rating', st == null ? '—' : st.avgRating, false),
    ];
    return Row(
      children: [
        for (var i = 0; i < cells.length; i++) ...[
          if (i > 0) const SizedBox(width: 11),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(
                color: context.brand.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _fbBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cells[i].$1.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: context.brand.paperDim,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    cells[i].$2,
                    style: TextStyle(
                      fontSize: 25.6,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                      color: cells[i].$3 ? Brand.signal : context.brand.paper,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  InputDecoration _fieldDecoration({String? hint}) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _fbBorder),
    );
    return InputDecoration(
      isDense: true,
      hintText: hint,
      filled: true,
      fillColor: context.brand.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: Brand.signal),
      ),
    );
  }

  Widget _toolbar() {
    final fieldText = TextStyle(fontSize: 13, color: context.brand.paper);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        SizedBox(
          width: 150,
          child: DropdownButtonFormField<String>(
            initialValue: _status,
            isDense: true,
            style: fieldText,
            decoration: _fieldDecoration(),
            onChanged: (v) {
              setState(() => _status = v ?? '');
              _load();
            },
            items: [
              const DropdownMenuItem(value: '', child: Text('All statuses')),
              for (final e in FeedbackService.statuses.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
          ),
        ),
        SizedBox(
          width: 170,
          child: DropdownButtonFormField<String>(
            initialValue: _category,
            isDense: true,
            style: fieldText,
            decoration: _fieldDecoration(),
            onChanged: (v) {
              setState(() => _category = v ?? '');
              _load();
            },
            items: [
              const DropdownMenuItem(value: '', child: Text('All categories')),
              for (final e in FeedbackService.categories.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: TextField(
            controller: _search,
            style: fieldText,
            decoration: _fieldDecoration(
              hint: 'Search name, subject or message…',
            ),
            onChanged: (_) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), _load);
            },
          ),
        ),
      ],
    );
  }

  Widget _emptyBox(IconData icon, String label, {bool spin = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: context.brand.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _fbBorder),
      ),
      child: Column(
        children: [
          spin
              ? const SizedBox(
                  width: 28,
                  height: 28,
                  child: TpLoader(
                    strokeWidth: 2.5,
                    color: Color(0xFFCBD5E1),
                  ),
                )
              : Icon(icon, size: 34, color: const Color(0xFFCBD5E1)),
          const SizedBox(height: 12),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: context.brand.paperDim),
          ),
        ],
      ),
    );
  }

  List<Widget> _list() {
    if (_loading && _page == null) {
      return [_emptyBox(Icons.sync, 'Loading feedback…', spin: true)];
    }
    if (_error != null) {
      return [
        _emptyBox(Icons.warning_amber_rounded, 'Could not load feedback.'),
      ];
    }
    final items = _page?.items ?? const <FeedbackEntry>[];
    if (items.isEmpty) {
      return [_emptyBox(Icons.inbox, 'No feedback matches these filters yet.')];
    }
    return [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) const SizedBox(height: 11),
        _card(items[i]),
      ],
    ];
  }

  Widget _statusPill(String status) {
    final colors =
        _statusPillColors[status] ??
        (const Color(0x29647488), const Color(0xFF475569));
    return _pill(
      (FeedbackService.statuses[status] ?? status).toUpperCase(),
      colors.$1,
      colors.$2,
    );
  }

  Widget _pill(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.8,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: fg,
        ),
      ),
    );
  }

  String _stars(int rating) {
    if (rating <= 0) return '';
    final r = rating.clamp(0, 5);
    return '${'★' * r}${'☆' * (5 - r)}';
  }

  Widget _card(FeedbackEntry f) {
    final isNew = f.status == 'new';
    final stars = _stars(f.rating);
    final muted = TextStyle(fontSize: 11.5, color: context.brand.paperDim);
    return _FeedbackCard(
      isNew: isNew,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0x140C233E),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  _initials(f.userName),
                  style: TextStyle(
                    fontSize: 13.6,
                    fontWeight: FontWeight.w800,
                    color: context.brand.paper,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      f.userName.isEmpty ? 'Unknown user' : f.userName,
                      style: TextStyle(
                        fontSize: 14.7,
                        fontWeight: FontWeight.w800,
                        color: context.brand.paper,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 7,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _pill(
                          (f.categoryLabel.isEmpty
                                  ? f.category
                                  : f.categoryLabel)
                              .toUpperCase(),
                          const Color(0x140C233E),
                          const Color(0xFF334155),
                        ),
                        _statusPill(f.status),
                        if (stars.isNotEmpty)
                          Text(
                            stars,
                            style: const TextStyle(
                              fontSize: 11.5,
                              letterSpacing: 1,
                              color: Brand.signal,
                            ),
                          ),
                        Text(_timeAgo(f.createdAt), style: muted),
                        if (f.userRole.isNotEmpty)
                          Text(
                            '· ${f.userRole.replaceAll('_', ' ')}',
                            style: muted,
                          ),
                        if (f.pageUrl.isNotEmpty)
                          Text('· ${f.pageUrl}', style: muted),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (f.subject.isNotEmpty) ...[
            const SizedBox(height: 11),
            Text(
              f.subject,
              style: TextStyle(
                fontSize: 14.7,
                fontWeight: FontWeight.w700,
                color: context.brand.paper,
              ),
            ),
          ],
          const SizedBox(height: 4),
          SelectableText(
            f.message,
            style: const TextStyle(
              fontSize: 13.6,
              height: 1.6,
              color: Color(0xFF334155),
            ),
          ),
          if (f.attachments.isNotEmpty) ...[
            const SizedBox(height: 11),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final a in f.attachments)
                  Tooltip(
                    message: a.name,
                    child: InkWell(
                      mouseCursor: SystemMouseCursors.zoomIn,
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => _openImage(a),
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _fbBorder),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Image.network(
                          _svc.attachmentUrl(a.id),
                          headers: _svc.authHeaders,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Icon(
                            Icons.broken_image,
                            color: context.brand.paperDim,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (f.adminNote.isNotEmpty) ...[
            const SizedBox(height: 11),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(11, 5, 0, 5),
              decoration: const BoxDecoration(
                border: Border(left: BorderSide(color: _fbBorder, width: 3)),
              ),
              child: Text.rich(
                TextSpan(
                  style: TextStyle(
                    fontSize: 12.5,
                    color: context.brand.paperDim,
                  ),
                  children: [
                    TextSpan(
                      text:
                          '${f.handledByName.isEmpty ? 'Admin' : f.handledByName}: ',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(text: f.adminNote),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 13),
          const _DashedRule(),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _FbAct(
                icon: Icons.visibility,
                label: 'Reviewed',
                onTap: () => _setStatus(f, 'reviewed'),
              ),
              _FbAct(
                icon: Icons.autorenew,
                label: 'In progress',
                onTap: () => _setStatus(f, 'in_progress'),
              ),
              _FbAct(
                icon: Icons.check,
                label: 'Resolved',
                onTap: () => _setStatus(f, 'resolved'),
              ),
              _FbAct(
                icon: Icons.archive,
                label: 'Archive',
                onTap: () => _setStatus(f, 'archived'),
              ),
              _FbAct(
                icon: Icons.edit,
                label: f.adminNote.isEmpty ? 'Add note' : 'Edit note',
                onTap: () => _note(f),
              ),
              _FbAct(
                icon: Icons.delete,
                label: 'Delete',
                danger: true,
                onTap: () => _delete(f),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

const _fbBorder = Color(0xFFE4E7EC);

const _statusPillColors = <String, (Color, Color)>{
  'new': (Color(0x29FF7D00), Color(0xFFC2410C)),
  'reviewed': (Color(0x243B82F6), Color(0xFF1D4ED8)),
  'in_progress': (Color(0x24A855F7), Color(0xFF7E22CE)),
  'resolved': (Color(0x2922C55E), Color(0xFF15803D)),
  'archived': (Color(0x29647488), Color(0xFF475569)),
};

class _FeedbackCard extends StatefulWidget {
  const _FeedbackCard({required this.isNew, required this.child});
  final bool isNew;
  final Widget child;

  @override
  State<_FeedbackCard> createState() => _FeedbackCardState();
}

class _FeedbackCardState extends State<_FeedbackCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: context.brand.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _fbBorder),
          boxShadow: _hover
              ? const [
                  BoxShadow(
                    color: Color(0x120C233E),
                    blurRadius: 22,
                    offset: Offset(0, 8),
                  ),
                ]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Container(
          padding: EdgeInsets.fromLTRB(widget.isNew ? 14 : 18, 16, 18, 16),
          decoration: widget.isNew
              ? const BoxDecoration(
                  border: Border(
                    left: BorderSide(color: Brand.signal, width: 4),
                  ),
                  gradient: LinearGradient(
                    colors: [Color(0x0DFF7D00), Color(0x00FF7D00)],
                    stops: [0, 0.2],
                  ),
                )
              : null,
          child: widget.child,
        ),
      ),
    );
  }
}

class _DashedRule extends StatelessWidget {
  const _DashedRule();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, c) {
        final n = (c.maxWidth / 6).floor();
        return Row(
          children: [
            for (var i = 0; i < n; i++)
              Container(
                width: 3,
                height: 1,
                margin: const EdgeInsets.only(right: 3),
                color: _fbBorder,
              ),
          ],
        );
      },
    );
  }
}

class _FbAct extends StatefulWidget {
  const _FbAct({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  State<_FbAct> createState() => _FbActState();
}

class _FbActState extends State<_FbAct> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final hi = widget.danger ? Brand.danger : Brand.signal;
    final fg = _hover ? hi : const Color(0xFF475569);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: context.brand.surface,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: _hover ? hi : _fbBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 13, color: fg),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
