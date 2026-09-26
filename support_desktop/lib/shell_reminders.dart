import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'services/live_sync.dart';
import 'shell_icons.dart';

const _paper = Color(0xFFFFF8E4);
const _paper2 = Color(0xFFFDEEC4);
const _edge = Color(0xFFE8D49A);
const _ink = Color(0xFF3A2B0C);
const _inkSoft = Color(0xFF6A5423);
const _inkFaint = Color(0xFF8A7440);
const _late = Color(0xFFB3261E);
const _soon = Color(0xFFA65A06);
const _info = Color(0xFF1F6FB2);
const _ok = Color(0xFF14714B);
const _line = Color(0x618A7440);

class _Data {
  _Data(this.raw);
  final Map<String, dynamic> raw;

  Map<String, dynamic> _map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  List<Map<String, dynamic>> _list(dynamic v) => [
        if (v is List)
          for (final e in v)
            if (e is Map) Map<String, dynamic>.from(e)
      ];
  int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  bool get canTask => raw['can_task'] == true;
  bool get canBir => raw['can_bir'] == true;
  Map<String, dynamic> get tasks => _map(raw['tasks']);
  String get mode => '${tasks['mode'] ?? 'off'}';
  String get owner => '${tasks['owner'] ?? ''}';
  List<Map<String, dynamic>> get items =>
      mode == 'off' ? const [] : _list(tasks['items']);
  int get taskDue => _int(tasks['due']);
  int count(String k) => _int(_map(tasks['counts'])[k]);
  Map<String, dynamic> get ptu => _map(raw['ptu']);
  List<Map<String, dynamic>> get ptuPending =>
      _list(_map(ptu['pending'])['items']);
  List<Map<String, dynamic>> get ptuDone =>
      _list(_map(ptu['completed'])['items']);
  int get ptuActive => _int(ptu['active']);
  List<Map<String, dynamic>> get notes => _list(raw['notes']);

  int get badge {
    final due = taskDue + ptuActive;
    return due > 0 ? due : count('open');
  }

  bool get alert => count('overdue') > 0;

  String get meta {
    final due = taskDue;
    if (due > 0) return '$due need${due == 1 ? 's' : ''} attention';
    if (ptuActive > 0) return '$ptuActive awaiting PTU';
    if (count('week') > 0) return '${count('week')} due this week';
    if (count('undated') > 0) return '${count('undated')} unscheduled';
    return 'Nothing due';
  }

  bool get visible {
    if (!canTask && !canBir) return false;
    final hasItem = items.isNotEmpty ||
        ptuPending.isNotEmpty ||
        ptuDone.isNotEmpty ||
        notes.isNotEmpty;
    return hasItem || canTask;
  }
}

class ShellReminders extends StatefulWidget {
  const ShellReminders({
    super.key,
    required this.api,
    required this.activeKey,
    required this.onOpenPage,
  });

  final ApiClient api;
  final String activeKey;
  final ValueChanged<String> onOpenPage;

  @override
  State<ShellReminders> createState() => _ShellRemindersState();
}

class _ShellRemindersState extends State<ShellReminders>
    with LiveRefresh<ShellReminders> {
  _Data? _data;
  bool _open = true;
  bool _stowed = false;
  bool _composing = false;
  int? _editingId;
  Offset _pos = const Offset(20, 111);
  Timer? _timer;
  SharedPreferences? _prefs;
  bool _hoverNote = false;
  bool _hoverTab = false;

  final _title = TextEditingController();
  final _body = TextEditingController();
  final _titleFocus = FocusNode();
  final Set<String> _busy = {};
  String _due = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _restore();
    _load();
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => _load());
  }

  @override
  List<String> get liveKeys => const ['reminders', 'task'];

  @override
  void onLiveChange() => _load();

  @override
  void didUpdateWidget(ShellReminders old) {
    super.didUpdateWidget(old);
    if (old.activeKey != widget.activeKey) _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _title.dispose();
    _body.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    try {
      final p = await SharedPreferences.getInstance();
      _prefs = p;
      final o = p.getString('tpRemNoteOpen2');
      final s = p.getString('tpRemNoteStowed');
      final pos = p.getString('tpRemNotePos');
      if (!mounted) return;
      setState(() {
        _open = o == null ? true : o == '1';
        _stowed = s == '1';
        if (pos != null) {
          final parts = pos.split(',');
          if (parts.length == 2) {
            final dx = double.tryParse(parts[0]);
            final dy = double.tryParse(parts[1]);
            if (dx != null && dy != null) _pos = Offset(dx, dy);
          }
        }
      });
    } catch (_) {}
  }

  void _save(String k, String v) {
    try {
      _prefs?.setString(k, v);
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      final r = await widget.api.get('mobileReminders');
      if (r['success'] != true || !mounted) return;
      setState(() => _data = _Data(r));
    } catch (_) {}
  }

  void _setOpen(bool v) {
    setState(() => _open = v);
    _save('tpRemNoteOpen2', v ? '1' : '0');
  }

  void _setStowed(bool v) {
    setState(() => _stowed = v);
    _save('tpRemNoteStowed', v ? '1' : '0');
  }

  void _drag(DragUpdateDetails d, Size area) {
    setState(() {
      _pos = Offset(
        (_pos.dx - d.delta.dx).clamp(0.0, math.max(0.0, area.width - 330)),
        (_pos.dy + d.delta.dy).clamp(0.0, math.max(0.0, area.height - 60)),
      );
    });
  }

  void _dragEnd() => _save('tpRemNotePos', '${_pos.dx},${_pos.dy}');

  Future<Map<String, dynamic>> _form(
          String action, Map<String, String> fields) =>
      widget.api.postPathMultipart('api.php',
          query: {'action': action}, fields: fields);

  void _toast(Map<String, dynamic>? r) {
    final m = '${r?['message'] ?? ''}'.trim();
    if (m.isEmpty || !mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _dismissPtu(int id) async {
    if (id <= 0 || _busy.contains('ptu$id')) return;
    setState(() => _busy.add('ptu$id'));
    try {
      final r = await _form('dismissPtuReminder', {'customer_id': '$id'});
      if (r['success'] == true) {
        await _load();
      } else {
        _toast(r);
      }
    } catch (_) {}
    if (mounted) setState(() => _busy.remove('ptu$id'));
  }

  Future<void> _deleteNote(int id) async {
    if (id <= 0 || _busy.contains('note$id')) return;
    setState(() => _busy.add('note$id'));
    try {
      final r = await _form('deleteStickyNote', {'id': '$id'});
      if (r['success'] == true) {
        if (_editingId == id) _closeCompose();
        await _load();
      } else {
        _toast(r);
      }
    } catch (_) {}
    if (mounted) setState(() => _busy.remove('note$id'));
  }

  void _startCompose([Map<String, dynamic>? note]) {
    setState(() {
      _composing = true;
      _editingId = note == null ? null : _toInt(note['id']);
      if (_editingId == 0) _editingId = null;
      _title.text = note == null ? '' : '${note['title'] ?? ''}';
      _body.text = note == null ? '' : '${note['body'] ?? ''}';
      _due = note == null ? '' : '${note['due_date'] ?? ''}';
    });
  }

  void _toggleCompose() {
    if (_composing && _editingId != null) {
      _startCompose();
      return;
    }
    if (_composing) {
      _closeCompose();
    } else {
      _startCompose();
    }
  }

  void _closeCompose() {
    setState(() {
      _composing = false;
      _editingId = null;
      _title.clear();
      _body.clear();
      _due = '';
    });
  }

  Future<void> _submitNote() async {
    final title = _title.text.trim();
    final body = _body.text.trim();
    if (title.isEmpty && body.isEmpty) {
      _titleFocus.requestFocus();
      return;
    }
    final editing = _editingId;
    setState(() => _saving = true);
    try {
      final r = await _form(editing != null ? 'updateStickyNote' : 'addStickyNote', {
        'title': title,
        'body': body,
        'due_date': _due,
        if (editing != null) 'id': '$editing',
      });
      if (!mounted) return;
      setState(() => _saving = false);
      if (r['success'] == true && r['note'] is Map) {
        _closeCompose();
        await _load();
      } else {
        _toast(r);
      }
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  int _toInt(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (d == null || !d.visible) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, c) {
      final area = Size(c.maxWidth, c.maxHeight);
      final double right = _pos.dx.clamp(0.0, math.max(0.0, area.width - 330)).toDouble();
      final double top = _pos.dy.clamp(0.0, math.max(0.0, area.height - 60)).toDouble();
      return Stack(clipBehavior: Clip.none, children: [
        if (_stowed)
          Positioned(right: 0, top: top, child: _handle(d))
        else
          Positioned(
            right: right,
            top: top,
            child: SizedBox(
              width: 316,
              child: Align(
                alignment: Alignment.topRight,
                child: _open ? _note(d, area) : _tab(d, area),
              ),
            ),
          ),
        if (_composing && !_stowed && _open)
          Positioned(
            right: right + 332,
            top: top + 18,
            child: _composer(),
          ),
      ]);
    });
  }

  Widget _handle(_Data d) {
    final alert = d.alert;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _setStowed(false),
        child: Tooltip(
          message: 'Show reminders',
          child: SizedBox(
            width: 34,
            height: 58,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned(
                right: 0,
                top: 4,
                child: Container(
                  width: 30,
                  height: 54,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: alert
                          ? const [Color(0xFFE4564D), _late]
                          : const [Color(0xFFFF9433), Color(0xFFFF7D00)],
                    ),
                    borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(12)),
                    boxShadow: [
                      BoxShadow(
                        color: (alert ? _late : const Color(0xFFFF7D00))
                            .withValues(alpha: 0.4),
                        blurRadius: 18,
                        offset: const Offset(-4, 6),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: const CustomPaint(
                      size: Size(15, 28), painter: _BangPainter(Colors.white)),
                ),
              ),
              if (d.badge > 0)
                Positioned(left: 0, top: 0, child: _countPill(d.badge, alert)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _countPill(int n, bool alert, {bool bordered = true}) => Container(
        constraints: const BoxConstraints(minWidth: 19),
        height: bordered ? 19 : 20,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: alert && !bordered ? _late : const Color(0xFF0B1B30),
          borderRadius: BorderRadius.circular(999),
          border: bordered ? Border.all(color: Colors.white, width: 2) : null,
        ),
        child: Text('$n',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 10.5,
                height: 1,
                fontWeight: FontWeight.w700)),
      );

  Widget _tab(_Data d, Size area) {
    final badge = d.badge;
    return MouseRegion(
      onEnter: (_) => setState(() => _hoverTab = true),
      onExit: (_) => setState(() => _hoverTab = false),
      child: Padding(
        padding: const EdgeInsets.only(top: 12, right: 10),
        child: Stack(clipBehavior: Clip.none, children: [
          GestureDetector(
            onTap: () => _setOpen(true),
            onPanUpdate: (e) => _drag(e, area),
            onPanEnd: (_) => _dragEnd(),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment(-0.5, -1),
                    end: Alignment(0.5, 1),
                    colors: [_paper, _paper2],
                  ),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: _hoverTab ? const Color(0xFFC9A94F) : _edge),
                  boxShadow: [
                    BoxShadow(
                      color: _ink.withValues(alpha: 0.5),
                      blurRadius: 18,
                      spreadRadius: -8,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (badge <= 0) ...[
                    const CustomPaint(
                        size: Size(17, 17),
                        painter: _PinOutlinePainter(Color(0xFFC25E00))),
                    const SizedBox(width: 8),
                  ],
                  const Text('Reminders',
                      style: TextStyle(
                          color: _ink,
                          fontSize: 12.8,
                          height: 1,
                          fontWeight: FontWeight.w600)),
                  if (badge > 0) ...[
                    const SizedBox(width: 8),
                    _countPill(badge, d.alert, bordered: false),
                  ],
                ]),
              ),
            ),
          ),
          if (badge > 0)
            Positioned(
              top: -30,
              left: 0,
              right: 0,
              child: Center(
                child: CustomPaint(
                    size: const Size(20, 40),
                    painter:
                        _BangPainter(d.alert ? _late : const Color(0xFFE06200))),
              ),
            ),
          if (_hoverTab)
            Positioned(
              top: -9,
              right: -9,
              child: _RoundBtn(
                size: 24,
                icon: Fa.times,
                iconSize: 10.5,
                tooltip: 'Stow to edge',
                onTap: () => _setStowed(true),
                hoverBg: _late,
              ),
            ),
        ]),
      ),
    );
  }

  Widget _note(_Data d, Size area) {
    final alert = d.alert;
    final ptu = d.canBir && d.ptuPending.isNotEmpty;
    final groups = const {
      'overdue': 'Overdue',
      'today': 'Due today',
      'week': 'Coming up',
      'undated': 'Unscheduled',
    };
    final body = <Widget>[];

    if (d.notes.isNotEmpty) {
      body.add(_group('My notes'));
      body.add(_capped(190, [
        for (var i = 0; i < d.notes.length; i++)
          _row(
            first: i == 0,
            bucket: '${d.notes[i]['bucket'] ?? ''}',
            prio: null,
            title: '${d.notes[i]['title'] ?? ''}',
            sub: '${d.notes[i]['body'] ?? ''}'.isEmpty
                ? null
                : Text('${d.notes[i]['body']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _subStyle),
            due: '${d.notes[i]['label'] ?? ''}',
            onTap: () => _startCompose(d.notes[i]),
            trailing: [
              _XBtn(
                  tooltip: 'Delete note',
                  onTap: () => _deleteNote(_toInt(d.notes[i]['id']))),
            ],
          ),
      ]));
    }

    if (d.canBir && d.ptuPending.isNotEmpty) {
      body.add(_group('PTU upload'));
      body.add(_capped(190, [
        for (var i = 0; i < d.ptuPending.length; i++)
          _row(
            first: i == 0,
            bucket: 'today',
            prio: 'medium',
            title: '${d.ptuPending[i]['name'] ?? ''}',
            sub: _ptuSub(d.ptuPending[i]),
            due: 'Awaiting PTU',
            trailing: [
              _GoBtn(
                  tooltip: 'Upload PTU',
                  onTap: () => widget.onOpenPage('customer')),
              _XBtn(
                  tooltip: 'Hide this reminder',
                  onTap: () => _dismissPtu(_toInt(d.ptuPending[i]['id']))),
            ],
          ),
      ]));
    }

    if (d.canBir && d.ptuDone.isNotEmpty) {
      body.add(_group('Completed registrations'));
      body.add(_capped(190, [
        for (var i = 0; i < d.ptuDone.length; i++)
          _row(
            first: i == 0,
            bucket: 'done',
            age: '${d.ptuDone[i]['age'] ?? 'old'}',
            prio: null,
            title: '${d.ptuDone[i]['name'] ?? ''}',
            sub: _ptuSub(d.ptuDone[i]),
            due: '${d.ptuDone[i]['label'] ?? ''}',
            trailing: [
              _GoBtn(
                  tooltip: 'Mark as done (clears this reminder)',
                  icon: Fa.check,
                  hoverBg: _ok,
                  onTap: () => _dismissPtu(_toInt(d.ptuDone[i]['id']))),
            ],
          ),
      ]));
    }

    final items = d.items;
    if (items.isNotEmpty) {
      final rows = <Widget>[];
      String last = '';
      var first = true;
      for (final it in items) {
        final b = '${it['bucket'] ?? ''}';
        if (b != last) {
          last = b;
          rows.add(_group(groups[b] ?? b));
          first = true;
        }
        final project = '${it['project'] ?? ''}';
        final assigner = '${it['assigner'] ?? ''}';
        rows.add(_row(
          first: first,
          bucket: b,
          prio: '${it['priority'] ?? ''}',
          title: '${it['title'] ?? ''}',
          sub: project.isEmpty && assigner.isEmpty
              ? null
              : Row(children: [
                  if (project.isNotEmpty) ...[
                    const Icon(Fa.folder, size: 9.5, color: _inkSoft),
                    const SizedBox(width: 3),
                    Flexible(
                        child: Text(project,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _subStyle)),
                  ],
                  if (assigner.isNotEmpty) ...[
                    if (project.isNotEmpty) const SizedBox(width: 7),
                    const Icon(Fa.userRegular, size: 9.5, color: _inkSoft),
                    const SizedBox(width: 3),
                    Flexible(
                        child: Text('from $assigner',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _subStyle)),
                  ],
                ]),
          due: '${it['label'] ?? ''}',
          trailing: [
            _GoBtn(
                tooltip: 'Open task', onTap: () => widget.onOpenPage('task')),
          ],
        ));
        first = false;
      }
      body.add(_capped(320, rows));
      if (d.count('later') > 0) {
        body.add(Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('${d.count('later')} more scheduled further out.',
              style: const TextStyle(fontSize: 10.6, color: _inkFaint)),
        ));
      }
    } else if (d.canTask) {
      final open = d.count('open');
      body.add(Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
        child: Column(children: [
          const Icon(Fa.checkCircle, size: 20, color: _ok),
          const SizedBox(height: 6),
          Text(open > 0 ? 'Nothing due this week' : 'You are all caught up',
              style: const TextStyle(
                  fontSize: 12.8, fontWeight: FontWeight.w700, color: _ink)),
          const SizedBox(height: 2),
          Text(
              open > 0
                  ? '$open open task${open == 1 ? '' : 's'} scheduled further out.'
                  : 'No open tasks are assigned to you right now.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10.9, color: _inkSoft)),
        ]),
      ));
    }

    final card = MouseRegion(
      onEnter: (_) => setState(() => _hoverNote = true),
      onExit: (_) => setState(() => _hoverNote = false),
      child: AnimatedRotation(
        turns: _hoverNote ? 0 : -1.1 / 360,
        alignment: const Alignment(0, -0.97),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutBack,
        child: Stack(clipBehavior: Clip.none, children: [
          Container(
            width: 316,
            padding: const EdgeInsets.fromLTRB(16, 26, 16, 14),
            decoration: BoxDecoration(
              border: Border.all(
                  color: alert ? _late.withValues(alpha: 0.42) : _edge),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(3),
                topRight: Radius.circular(3),
                bottomLeft: Radius.circular(3),
                bottomRight: Radius.circular(12),
              ),
              gradient: const LinearGradient(
                begin: Alignment(-0.37, -1),
                end: Alignment(0.37, 1),
                colors: [_paper, _paper2],
              ),
              boxShadow: [
                BoxShadow(
                  color: _ink.withValues(alpha: 0.55),
                  blurRadius: 34,
                  spreadRadius: -18,
                  offset: const Offset(0, 18),
                ),
                BoxShadow(
                  color: _ink.withValues(alpha: 0.25),
                  blurRadius: 8,
                  spreadRadius: -4,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            foregroundDecoration: const BoxDecoration(
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(3),
                topRight: Radius.circular(3),
                bottomLeft: Radius.circular(3),
                bottomRight: Radius.circular(12),
              ),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment(0, -0.72),
                colors: [Color(0x8CFFFFFF), Color(0x00FFFFFF)],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GestureDetector(
                  onPanUpdate: (e) => _drag(e, area),
                  onPanEnd: (_) => _dragEnd(),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Reminders',
                                      style: TextStyle(
                                          fontSize: 14.7,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.15,
                                          color: _ink)),
                                  const SizedBox(height: 2),
                                  Text.rich(
                                    TextSpan(children: [
                                      if (d.owner.isNotEmpty) ...[
                                        const WidgetSpan(
                                          alignment:
                                              PlaceholderAlignment.middle,
                                          child: Padding(
                                            padding: EdgeInsets.only(right: 3),
                                            child: Icon(Fa.eye,
                                                size: 10.5, color: _inkSoft),
                                          ),
                                        ),
                                        TextSpan(text: '${d.owner} · '),
                                      ],
                                      TextSpan(text: d.meta),
                                    ]),
                                    style: const TextStyle(
                                        fontSize: 11.2,
                                        height: 1.35,
                                        color: _inkSoft),
                                  ),
                                ],
                              ),
                            ),
                            Transform.translate(
                              offset: const Offset(-2, -4),
                              child: _SquareBtn(
                                icon: Fa.plus,
                                iconSize: 11.5,
                                radius: 8,
                                tooltip: 'Add sticky note',
                                active: _composing,
                                onTap: _toggleCompose,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Transform.translate(
                              offset: const Offset(4, -4),
                              child: _SquareBtn(
                                icon: Fa.chevronDown,
                                iconSize: 12.5,
                                radius: 6,
                                tooltip: 'Minimize',
                                subtleHover: true,
                                onTap: () => _setOpen(false),
                              ),
                            ),
                          ]),
                    ),
                  ),
                ),
                const _Dash(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 10, 0, 11),
                  child: Row(children: [
                    _tally(
                        d.count('overdue'),
                        'Overdue',
                        d.count('overdue') > 0 ? _late : _inkFaint),
                    const SizedBox(width: 6),
                    _tally(d.count('today'), 'Due today',
                        d.count('today') > 0 ? _soon : _inkFaint),
                    if (ptu) ...[
                      const SizedBox(width: 6),
                      _tally(d.ptuActive, 'PTU',
                          d.ptuActive > 0 ? _soon : _inkFaint),
                    ],
                    const SizedBox(width: 6),
                    _tally(d.count('open'), 'Open', _ink),
                  ]),
                ),
                ...body,
                const SizedBox(height: 10),
                const _Dash(),
                const SizedBox(height: 9),
                Align(
                  alignment: Alignment.centerRight,
                  child: _FootLink(
                    label: d.canTask
                        ? 'Open task board'
                        : 'Open BIR registration',
                    onTap: () =>
                        widget.onOpenPage(d.canTask ? 'task' : 'customer'),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.only(bottomRight: Radius.circular(12)),
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomRight,
                      end: Alignment.topLeft,
                      stops: [0, 0.45, 0.46, 1],
                      colors: [
                        Color(0x1A000000),
                        Color(0x0A000000),
                        Color(0x00000000),
                        Color(0x00000000),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Positioned(
            top: -15,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: CustomPaint(
                    size: Size(26, 32), painter: _PinPainter()),
              ),
            ),
          ),
        ]),
      ),
    );
    return card;
  }

  static const _subStyle = TextStyle(fontSize: 10.6, color: _inkSoft);

  Widget? _ptuSub(Map<String, dynamic> it) {
    final tin = '${it['tin'] ?? ''}';
    final br = '${it['branch_code'] ?? ''}';
    if (tin.isEmpty && br.isEmpty) return null;
    return Row(children: [
      if (tin.isNotEmpty) ...[
        const Icon(Fa.idCardRegular, size: 9.5, color: _inkSoft),
        const SizedBox(width: 3),
        Flexible(
            child: Text('TIN $tin',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _subStyle)),
      ],
      if (br.isNotEmpty) ...[
        if (tin.isNotEmpty) const SizedBox(width: 7),
        const Icon(Fa.building, size: 9.5, color: _inkSoft),
        const SizedBox(width: 3),
        Text(br, style: _subStyle),
      ],
    ]);
  }

  Widget _capped(double max, List<Widget> rows) => ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: math.min(
                max, MediaQuery.of(context).size.height * 0.42)),
        child: SingleChildScrollView(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
        ),
      );

  Widget _group(String t) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 3),
        child: Text(t.toUpperCase(),
            style: const TextStyle(
                fontSize: 9.6,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.77,
                color: _inkFaint)),
      );

  Widget _tally(int n, String cap, Color color) => Expanded(
        child: Column(children: [
          Text('$n',
              style: TextStyle(
                  fontSize: 18.9,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(height: 1),
          Text(cap.toUpperCase(),
              style: const TextStyle(
                  fontSize: 9.6,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.67,
                  color: _inkSoft)),
        ]),
      );

  Widget _row({
    required bool first,
    required String bucket,
    required String? prio,
    required String title,
    required Widget? sub,
    required String due,
    required List<Widget> trailing,
    String age = '',
    VoidCallback? onTap,
  }) {
    Color dot;
    switch (prio) {
      case 'high':
        dot = _late;
        break;
      case 'medium':
        dot = _soon;
        break;
      case 'low':
        dot = _info;
        break;
      default:
        dot = _inkFaint;
    }
    Color dueBg = _inkFaint.withValues(alpha: 0.16);
    Color dueFg = _inkSoft;
    Color? ageColor;
    if (bucket == 'overdue') {
      dueBg = _late.withValues(alpha: 0.14);
      dueFg = _late;
    } else if (bucket == 'today') {
      dueBg = _soon.withValues(alpha: 0.16);
      dueFg = _soon;
    } else if (bucket == 'done') {
      ageColor = age == 'recent'
          ? const Color(0xFFA65A06)
          : age == 'old'
              ? const Color(0xFF6A5423)
              : _ok;
      dot = ageColor;
      dueBg = ageColor;
      dueFg = const Color(0xFFFFF8E4);
    }
    return _HoverRow(
      first: first,
      accent: ageColor,
      onTap: onTap,
      builder: (hover) => Row(children: [
        Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                      color: _ink)),
              if (sub != null) ...[const SizedBox(height: 1), sub],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: EdgeInsets.symmetric(
              horizontal: bucket == 'done' ? 9 : 7,
              vertical: bucket == 'done' ? 3 : 2),
          decoration: BoxDecoration(
              color: dueBg, borderRadius: BorderRadius.circular(999)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (bucket == 'done') ...[
              Icon(Fa.check, size: 8.5, color: dueFg),
              const SizedBox(width: 4),
            ],
            Text(due,
                style: TextStyle(
                    fontSize: 9.9, fontWeight: FontWeight.w700, color: dueFg)),
          ]),
        ),
        for (final t in trailing) ...[
          const SizedBox(width: 8),
          Opacity(
              opacity: hover || t is! _XBtn ? 1 : 0,
              child: t),
        ],
      ]),
    );
  }

  Widget _composer() {
    return Transform.rotate(
      angle: -0.6 * math.pi / 180,
      child: Stack(clipBehavior: Clip.none, children: [
        Material(
          color: Colors.transparent,
          child: Container(
            width: 292,
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(2),
                topRight: Radius.circular(14),
                bottomLeft: Radius.circular(2),
                bottomRight: Radius.circular(2),
              ),
              gradient: const LinearGradient(
                begin: Alignment(-0.47, -1),
                end: Alignment(0.47, 1),
                stops: [0, 0.58, 1],
                colors: [
                  Color(0xFFFFF6D8),
                  Color(0xFFFDE9B4),
                  Color(0xFFF8DFA2)
                ],
              ),
              boxShadow: [
                BoxShadow(
                    color: _ink.withValues(alpha: 0.55),
                    blurRadius: 34,
                    spreadRadius: -18,
                    offset: const Offset(0, 18)),
                BoxShadow(
                    color: _ink.withValues(alpha: 0.16),
                    blurRadius: 6,
                    offset: const Offset(0, 2)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(
                        (_editingId != null ? 'Edit note' : 'New note')
                            .toUpperCase(),
                        style: const TextStyle(
                            fontSize: 9.9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                            color: Color(0xFF7A6428))),
                  ),
                  _RoundBtn(
                    size: 30,
                    icon: Fa.times,
                    iconSize: 12.5,
                    tooltip: 'Close',
                    flat: true,
                    onTap: _closeCompose,
                    hoverBg: _late.withValues(alpha: 0.14),
                    hoverFg: _late,
                  ),
                ]),
                const SizedBox(height: 6),
                TextField(
                  controller: _title,
                  focusNode: _titleFocus,
                  autofocus: true,
                  maxLength: 120,
                  style: const TextStyle(
                      fontSize: 15.2,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2E220A)),
                  cursorColor: const Color(0xFFFF7D00),
                  decoration: InputDecoration(
                    isDense: true,
                    counterText: '',
                    hintText: 'Note title',
                    hintStyle: TextStyle(
                        color: const Color(0xFF6A5423).withValues(alpha: 0.72),
                        fontWeight: FontWeight.w600),
                    filled: false,
                    contentPadding: const EdgeInsets.fromLTRB(2, 2, 2, 7),
                    border: UnderlineInputBorder(
                        borderSide: BorderSide(
                            color: _inkFaint.withValues(alpha: 0.4))),
                    enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                            color: _inkFaint.withValues(alpha: 0.4))),
                    focusedBorder: const UnderlineInputBorder(
                        borderSide:
                            BorderSide(color: Color(0x8CFF7D00), width: 2)),
                  ),
                ),
                const SizedBox(height: 4),
                CustomPaint(
                  painter: const _LinedPainter(),
                  child: TextField(
                    controller: _body,
                    maxLength: 500,
                    minLines: 5,
                    maxLines: 8,
                    style: const TextStyle(
                        fontSize: 13.1,
                        height: 26 / 13.1,
                        fontWeight: FontWeight.w500,
                        color: _ink),
                    cursorColor: const Color(0xFFFF7D00),
                    decoration: InputDecoration(
                      isDense: true,
                      counterText: '',
                      filled: false,
                      hintText: 'Write your note…',
                      hintStyle: TextStyle(
                          color:
                              const Color(0xFF6A5423).withValues(alpha: 0.68)),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const _Dash(),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: InkWell(
                      onTap: _pickDate,
                      child: Row(children: [
                        const Icon(Fa.calendar,
                            size: 11, color: Color(0xFF7A6428)),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            _due.isEmpty ? 'mm/dd/yyyy' : _fmtDate(_due),
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11.2,
                                fontWeight: FontWeight.w600,
                                color: _due.isEmpty
                                    ? const Color(0xFF7A6428)
                                    : _ink),
                          ),
                        ),
                        if (_due.isNotEmpty)
                          GestureDetector(
                            onTap: () => setState(() => _due = ''),
                            child: const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: Icon(Fa.times,
                                  size: 9, color: Color(0xFF7A6428)),
                            ),
                          ),
                      ]),
                    ),
                  ),
                  _NoteBtn(label: 'Cancel', onTap: _closeCompose),
                  const SizedBox(width: 6),
                  _NoteBtn(
                    label: _editingId != null ? 'Save note' : 'Add note',
                    primary: true,
                    onTap: _saving ? null : _submitNote,
                  ),
                ]),
              ],
            ),
          ),
        ),
        Positioned(
          top: -11,
          left: 0,
          right: 0,
          child: Center(
            child: Transform.rotate(
              angle: -2.2 * math.pi / 180,
              child: Container(
                width: 86,
                height: 22,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x9EFFFFFF), Color(0x80FFF6D8)],
                  ),
                  boxShadow: [
                    BoxShadow(
                        color: _ink.withValues(alpha: 0.18),
                        blurRadius: 3,
                        offset: const Offset(0, 1)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  String _fmtDate(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.month)}/${two(d.day)}/${d.year}';
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final init = DateTime.tryParse(_due) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10),
    );
    if (picked == null || !mounted) return;
    String two(int v) => v.toString().padLeft(2, '0');
    setState(() =>
        _due = '${picked.year}-${two(picked.month)}-${two(picked.day)}');
  }
}

class _HoverRow extends StatefulWidget {
  const _HoverRow({
    required this.first,
    required this.builder,
    this.accent,
    this.onTap,
  });
  final bool first;
  final Widget Function(bool hover) builder;
  final Color? accent;
  final VoidCallback? onTap;

  @override
  State<_HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<_HoverRow> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(
            border: widget.first
                ? null
                : Border(
                    top: BorderSide(
                        color: _inkFaint.withValues(alpha: 0.18))),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.fromLTRB(0, 7, 4, 7),
            decoration: BoxDecoration(
              color: _hover
                  ? Colors.white.withValues(alpha: 0.55)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
              border: widget.accent == null
                  ? null
                  : Border(left: BorderSide(color: widget.accent!, width: 2)),
            ),
            child: widget.builder(_hover),
          ),
        ),
      ),
    );
  }
}

class _SquareBtn extends StatefulWidget {
  const _SquareBtn({
    required this.icon,
    required this.iconSize,
    required this.radius,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.subtleHover = false,
  });
  final IconData icon;
  final double iconSize;
  final double radius;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;
  final bool subtleHover;

  @override
  State<_SquareBtn> createState() => _SquareBtnState();
}

class _SquareBtnState extends State<_SquareBtn> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final on = _hover || widget.active;
    final dark = on && !widget.subtleHover;
    final bg = dark
        ? _ink
        : on
            ? _inkFaint.withValues(alpha: 0.14)
            : Colors.white.withValues(alpha: widget.subtleHover ? 0.55 : 0.6);
    final border = dark
        ? _ink
        : on
            ? _inkFaint.withValues(alpha: 0.3)
            : _inkFaint.withValues(alpha: 0.32);
    final fg = dark ? const Color(0xFFFFF8E4) : (on ? _ink : _inkSoft);
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(widget.radius),
              border: Border.all(color: border),
            ),
            alignment: Alignment.center,
            child: Icon(widget.icon, size: widget.iconSize, color: fg),
          ),
        ),
      ),
    );
  }
}

class _GoBtn extends StatefulWidget {
  const _GoBtn({
    required this.tooltip,
    required this.onTap,
    this.icon = Fa.arrowRight,
    this.hoverBg = _ink,
  });
  final String tooltip;
  final VoidCallback onTap;
  final IconData icon;
  final Color hoverBg;

  @override
  State<_GoBtn> createState() => _GoBtnState();
}

class _GoBtnState extends State<_GoBtn> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: _hover
                  ? widget.hoverBg
                  : Colors.white.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: _hover
                      ? widget.hoverBg
                      : _inkFaint.withValues(alpha: 0.32)),
            ),
            alignment: Alignment.center,
            child: Icon(widget.icon,
                size: 10,
                color: _hover ? const Color(0xFFFFF8E4) : _inkSoft),
          ),
        ),
      ),
    );
  }
}

class _XBtn extends StatefulWidget {
  const _XBtn({required this.tooltip, required this.onTap});
  final String tooltip;
  final VoidCallback onTap;

  @override
  State<_XBtn> createState() => _XBtnState();
}

class _XBtnState extends State<_XBtn> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: _hover
                  ? _late.withValues(alpha: 0.12)
                  : Colors.transparent,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(Fa.times,
                size: 10, color: _hover ? _late : _inkFaint),
          ),
        ),
      ),
    );
  }
}

class _RoundBtn extends StatefulWidget {
  const _RoundBtn({
    required this.size,
    required this.icon,
    required this.iconSize,
    required this.tooltip,
    required this.onTap,
    required this.hoverBg,
    this.hoverFg = Colors.white,
    this.flat = false,
  });
  final double size;
  final IconData icon;
  final double iconSize;
  final String tooltip;
  final VoidCallback onTap;
  final Color hoverBg;
  final Color hoverFg;
  final bool flat;

  @override
  State<_RoundBtn> createState() => _RoundBtnState();
}

class _RoundBtnState extends State<_RoundBtn> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final base = widget.flat ? Colors.transparent : Colors.white;
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: _hover ? widget.hoverBg : base,
              shape: BoxShape.circle,
              border: widget.flat
                  ? null
                  : Border.all(color: _hover ? widget.hoverBg : _edge),
              boxShadow: widget.flat
                  ? null
                  : [
                      BoxShadow(
                          color: _ink.withValues(alpha: 0.5),
                          blurRadius: 10,
                          spreadRadius: -4,
                          offset: const Offset(0, 4)),
                    ],
            ),
            alignment: Alignment.center,
            child: Icon(widget.icon,
                size: widget.iconSize,
                color: _hover
                    ? widget.hoverFg
                    : (widget.flat ? const Color(0xFF7A6428) : _inkSoft)),
          ),
        ),
      ),
    );
  }
}

class _NoteBtn extends StatefulWidget {
  const _NoteBtn({required this.label, required this.onTap, this.primary = false});
  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  State<_NoteBtn> createState() => _NoteBtnState();
}

class _NoteBtnState extends State<_NoteBtn> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final p = widget.primary;
    final bg = p
        ? (_hover ? const Color(0xFF55400F) : _ink)
        : (_hover ? Colors.white.withValues(alpha: 0.85) : Colors.white.withValues(alpha: 0.55));
    final fg = p ? const Color(0xFFFFF6D8) : (_hover ? _ink : _inkSoft);
    final border = p
        ? (_hover ? const Color(0xFF55400F) : _ink)
        : _inkFaint.withValues(alpha: 0.38);
    return Opacity(
      opacity: widget.onTap == null ? 0.55 : 1,
      child: MouseRegion(
        cursor: widget.onTap == null
            ? SystemMouseCursors.forbidden
            : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 30),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: border),
            ),
            alignment: Alignment.center,
            child: Text(widget.label,
                style: TextStyle(
                    fontSize: 11.4,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    color: fg)),
          ),
        ),
      ),
    );
  }
}

class _FootLink extends StatefulWidget {
  const _FootLink({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  State<_FootLink> createState() => _FootLinkState();
}

class _FootLinkState extends State<_FootLink> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final c = _hover ? const Color(0xFF7A3A00) : const Color(0xFFA14D00);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(widget.label,
              style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w700, color: c)),
          const SizedBox(width: 6),
          Icon(Fa.arrowRight, size: 11, color: c),
        ]),
      ),
    );
  }
}

class _Dash extends StatelessWidget {
  const _Dash();
  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 1,
        width: double.infinity,
        child: CustomPaint(painter: _DashPainter()),
      );
}

class _DashPainter extends CustomPainter {
  const _DashPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = _line
      ..strokeWidth = 1;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0.5), Offset(math.min(x + 3, size.width), 0.5), p);
      x += 6;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _LinedPainter extends CustomPainter {
  const _LinedPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = _inkFaint.withValues(alpha: 0.22)
      ..strokeWidth = 1;
    for (double y = 25.5; y < size.height; y += 26) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _PinPainter extends CustomPainter {
  const _PinPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 32;
    canvas.save();
    canvas.scale(s, s);
    canvas.drawCircle(
        const Offset(16, 13),
        10,
        Paint()
          ..color = _ink.withValues(alpha: 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    canvas.drawLine(
        const Offset(16, 15.5),
        const Offset(16, 35),
        Paint()
          ..color = const Color(0xFF7C4A12)
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round);
    final head = Rect.fromCenter(center: const Offset(16, 11), width: 20, height: 16);
    canvas.drawOval(head, Paint()..color = const Color(0xFFFF7D00));
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(12.6, 8.2), width: 6.8, height: 4.8),
        Paint()..color = Colors.white.withValues(alpha: 0.42));
    canvas.drawOval(
        head,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0xFFC25E00));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _PinOutlinePainter extends CustomPainter {
  const _PinOutlinePainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    canvas.save();
    canvas.scale(s, s);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(9, 4)
      ..lineTo(15, 4)
      ..lineTo(14, 9)
      ..lineTo(17.2, 11.6)
      ..lineTo(16.6, 13.4)
      ..lineTo(7.4, 13.4)
      ..lineTo(6.8, 11.6)
      ..lineTo(10, 9)
      ..close();
    canvas.drawPath(path, p);
    canvas.drawLine(const Offset(12, 13.4), const Offset(12, 20), p);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PinOutlinePainter old) => old.color != color;
}

class _BangPainter extends CustomPainter {
  const _BangPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 16;
    canvas.save();
    canvas.scale(s, s);
    canvas.drawLine(
        const Offset(8, 3.4),
        const Offset(8, 18.6),
        Paint()
          ..color = color
          ..strokeWidth = 5.4
          ..strokeCap = StrokeCap.round);
    canvas.drawCircle(const Offset(8, 26.6), 3, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BangPainter old) => old.color != color;
}
