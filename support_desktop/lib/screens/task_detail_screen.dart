import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/task_models.dart';
import '../services/live_sync.dart';
import '../services/task_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'ops_widgets.dart';
import '../widgets/tp_loader.dart';

typedef _J = Map<String, dynamic>;

class TaskDetailScreen extends StatefulWidget {
  const TaskDetailScreen({
    super.key,
    required this.taskId,
    required this.initial,
    required this.service,
  });

  final int taskId;
  final TaskItem initial;
  final TaskService service;

  static Future<bool?> show(
    BuildContext context, {
    required TaskItem task,
    required TaskService service,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) =>
          TaskDetailScreen(taskId: task.id, initial: task, service: service),
    );
  }

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen>
    with LiveRefresh<TaskDetailScreen> {
  late TaskItem _task = widget.initial;
  bool _dirty = false;
  bool _busy = false;
  bool _removed = false;
  bool _seen = false;
  bool _liveBusy = false;
  List<Subtask> _subtasks = const [];
  _J? _detail;
  List<Assignee> _users = const [];

  bool _toggling = false;
  bool _deleting = false;
  String? _attachPath;

  final _desc = TextEditingController();
  final _descFocus = FocusNode();
  String _descBaseline = '';
  bool _descSaving = false;

  bool _commentsTab = true;
  final _comment = TextEditingController();
  bool _commentBusy = false;

  bool _subAdding = false;
  bool _subBusy = false;
  final _subTitle = TextEditingController();
  DateTime? _subStart;
  DateTime? _subDue;
  int _subUser = 0;

  TaskService get _svc => widget.service;

  @override
  void initState() {
    super.initState();
    _loadSubtasks();
    _loadDetail();
    _lookup(apply: false);
    _descFocus.addListener(() {
      if (!_descFocus.hasFocus) _saveDescription();
    });
    _svc.assignableUsers().then((u) {
      if (mounted) setState(() => _users = u);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _desc.dispose();
    _descFocus.dispose();
    _comment.dispose();
    _subTitle.dispose();
    super.dispose();
  }

  @override
  List<String> get liveKeys => const ['task'];

  @override
  void onLiveChange() {
    if (_busy || _removed) return;
    _lookup(apply: true);
    _loadSubtasks();
    _loadDetail();
  }

  bool get _canEdit => _detail?['can_edit'] == true;
  bool get _canDelete => _detail?['can_delete'] == true;
  bool get _readonly => _detail?['readonly'] == true;

  Future<void> _loadDetail() async {
    try {
      final d = await _svc.taskDetail(widget.taskId);
      if (!mounted) return;
      final t = (d['task'] as Map?)?.cast<String, dynamic>() ?? const {};
      final text = opsStr(t['description_text']);
      setState(() {
        _detail = d;
        if (!_descFocus.hasFocus && !_descSaving) {
          _descBaseline = text;
          _desc.text = text;
        }
      });
    } catch (_) {}
  }

  Future<TaskItem?> _find() async {
    TaskItem? pick(List<TaskItem> list) {
      for (final t in list) {
        if (t.id == widget.taskId) return t;
      }
      return null;
    }

    final hit = pick(await _svc.listTasks());
    if (hit != null || _task.projectId <= 0) return hit;
    return pick(await _svc.listTasks(projectId: _task.projectId));
  }

  Future<void> _lookup({required bool apply}) async {
    if (_liveBusy) return;
    _liveBusy = true;
    TaskItem? found;
    try {
      found = await _find();
    } catch (_) {
      _liveBusy = false;
      return;
    }
    _liveBusy = false;
    if (!mounted) return;
    if (found == null) {
      if (apply && _seen) setState(() => _removed = true);
      return;
    }
    _seen = true;
    if (!apply || _busy) return;
    final next = found;
    setState(() => _task = next);
  }

  Future<void> _loadSubtasks() async {
    try {
      final s = await _svc.listSubtasks(widget.taskId);
      if (mounted) setState(() => _subtasks = s);
    } catch (_) {}
  }

  Future<void> _moveTo(TaskBucket target) async {
    final previous = _task;
    final next = _bucketToOptimistic(target, _task);
    setState(() {
      _busy = true;
      _task = next;
    });
    try {
      await _svc.moveToSection(widget.taskId, _bucketWire(target));
      _dirty = true;
    } catch (e) {
      setState(() => _task = previous);
      if (mounted) opsToast(context, 'Move failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static TaskItem _bucketToOptimistic(TaskBucket target, TaskItem t) {
    switch (target) {
      case TaskBucket.todo:
        return t.copyWith(status: TaskStatus.pending, dueDate: null);
      case TaskBucket.doing:
        final yesterday = DateTime.now().subtract(const Duration(days: 1));
        return t.copyWith(status: TaskStatus.pending, dueDate: yesterday);
      case TaskBucket.done:
        return t.copyWith(status: TaskStatus.completed);
    }
  }

  static String _bucketWire(TaskBucket b) {
    switch (b) {
      case TaskBucket.todo:
        return 'todo';
      case TaskBucket.doing:
        return 'doing';
      case TaskBucket.done:
        return 'done';
    }
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _task.dueDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 5)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked == null) return;
    setState(() {
      _busy = true;
      _task = _task.copyWith(dueDate: picked);
    });
    try {
      await _svc.updateDue(
          taskId: widget.taskId, dueDate: picked, startDate: _task.startDate);
      _dirty = true;
      _loadDetail();
    } catch (e) {
      if (mounted) opsToast(context, 'Failed to set due date: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setStatus(TaskStatus next, {String? attachment}) async {
    setState(() => _toggling = true);
    final r = await _svc.drawerToggleStatus(widget.taskId, next,
        screenshotPath: attachment);
    if (!mounted) return;
    setState(() => _toggling = false);
    if (r.ok) {
      Navigator.of(context).pop(true);
    } else {
      opsToast(context, r.message, error: true);
    }
  }

  Future<void> _pickAttachment() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = res?.files.single.path;
    if (path == null || !mounted) return;
    final ext = path.split('.').last.toLowerCase();
    if (!const ['jpg', 'jpeg', 'png', 'gif'].contains(ext)) {
      opsToast(context,
          'Invalid file type! Only JPG, JPEG, PNG, and GIF images are allowed.',
          error: true);
      return;
    }
    setState(() => _attachPath = path);
  }

  Future<void> _delete() async {
    final ok = await opsConfirm(
      context,
      title: 'Are you sure?',
      message: 'Are you sure you want to delete this task?',
      confirm: 'Yes',
    );
    if (!ok || !mounted) return;
    setState(() => _deleting = true);
    final r = await _svc.drawerDeleteTask(widget.taskId);
    if (!mounted) return;
    setState(() => _deleting = false);
    if (r.ok) {
      opsToast(context, r.message);
      Navigator.of(context).pop(true);
    } else {
      opsToast(context, r.message, error: true);
    }
  }

  Future<void> _saveDescription() async {
    if (!_canEdit || _descSaving) return;
    final text = _desc.text;
    if (text.trim() == _descBaseline.trim()) return;
    _descSaving = true;
    final r = await _svc.updateDescriptionText(widget.taskId, text);
    _descSaving = false;
    if (!mounted) return;
    if (r.ok) {
      _descBaseline = text;
      _dirty = true;
      _loadDetail();
    } else {
      opsToast(context, r.message, error: true);
    }
  }

  Future<void> _addComment() async {
    final body = _comment.text.trim();
    if (body.isEmpty || _commentBusy) return;
    setState(() => _commentBusy = true);
    final r = await _svc.addComment(widget.taskId, body);
    if (!mounted) return;
    setState(() => _commentBusy = false);
    if (!r.ok) return;
    _comment.clear();
    _loadDetail();
  }

  Future<void> _deleteComment(int id) async {
    final d = _detail;
    if (d == null) return;
    final before = List<Map>.from((d['comments'] as List?) ?? const []);
    setState(() {
      d['comments'] = before.where((c) => opsInt(c['id']) != id).toList();
    });
    final ok = await _svc.deleteComment(id);
    if (!mounted) return;
    if (!ok) setState(() => d['comments'] = before);
    _loadDetail();
  }

  Future<void> _toggleSub(Subtask s) async {
    final next = s.isDone ? TaskStatus.pending : TaskStatus.completed;
    final before = _subtasks;
    setState(() {
      _subtasks = [
        for (final x in _subtasks)
          x.id == s.id ? _withStatus(x, next) : x,
      ];
    });
    final ok = await _svc.toggleSubtask(s.id, next);
    if (!mounted) return;
    if (!ok) {
      setState(() => _subtasks = before);
      return;
    }
    _dirty = true;
    _loadDetail();
  }

  static Subtask _withStatus(Subtask s, TaskStatus st) => Subtask(
        id: s.id,
        parentTaskId: s.parentTaskId,
        title: s.title,
        status: st,
        startDate: s.startDate,
        dueDate: s.dueDate,
        assignedBy: s.assignedBy,
        primaryUserId: s.primaryUserId,
        primaryAssigneeName: s.primaryAssigneeName,
        assignees: s.assignees,
      );

  Future<void> _deleteSub(Subtask s) async {
    setState(() => _subtasks = _subtasks.where((x) => x.id != s.id).toList());
    await _svc.deleteSubtask(s.id);
    if (!mounted) return;
    _dirty = true;
    _loadSubtasks();
    _loadDetail();
  }

  void _resetSubForm() {
    _subTitle.clear();
    _subStart = null;
    _subDue = null;
    _subUser = 0;
  }

  Future<void> _createSub() async {
    final title = _subTitle.text.trim();
    if (title.isEmpty || _subBusy) return;
    setState(() => _subBusy = true);
    final r = await _svc.addSubtask(
      parentTaskId: widget.taskId,
      title: title,
      startDate: _subStart,
      dueDate: _subDue,
      assigneeUserId: _subUser,
    );
    if (!mounted) return;
    setState(() {
      _subBusy = false;
      if (r.ok) _resetSubForm();
    });
    if (!r.ok) return;
    _dirty = true;
    _loadSubtasks();
    _loadDetail();
  }

  Future<DateTime?> _pickDate(DateTime? initial, {DateTime? first, DateTime? last}) {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: initial ?? first ?? now,
      firstDate: first ?? DateTime(now.year - 5),
      lastDate: last ?? DateTime(now.year + 5),
    );
  }

  void _close() => Navigator.of(context).pop(_dirty);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final task = _task;
    final d = _detail;
    final dt = (d?['task'] as Map?)?.cast<String, dynamic>();
    final done = dt == null ? task.isDone : opsStr(dt['status']) == 'completed';
    final crumbs = [
      if ((task.projectName ?? '').isNotEmpty) task.projectName!,
      if ((task.parentTitle ?? '').isNotEmpty) 'Subtask of ${task.parentTitle}',
    ];
    final lockedTip = _readonly ? 'Only the assignee can change this' : null;
    final actions = <Widget>[
      Tooltip(
        message: _canDelete ? '' : 'Only the task creator can delete this',
        child: DangerButton(
          label: _deleting ? 'Deleting…' : (done ? 'Delete' : 'Delete task'),
          icon: Icons.delete_outline,
          onPressed: (_removed || !_canDelete || _deleting) ? null : _delete,
        ),
      ),
      if (done)
        Tooltip(
          message: lockedTip ?? '',
          child: GhostButton(
            label: 'Reopen',
            icon: Icons.undo,
            onPressed: (_removed || _readonly || _toggling || d == null)
                ? null
                : () => _setStatus(TaskStatus.pending),
          ),
        )
      else
        Tooltip(
          message: lockedTip ?? '',
          child: SignalButton(
            label: 'Mark complete',
            icon: Icons.check_circle,
            busy: _toggling,
            onPressed: (_removed || _readonly || d == null)
                ? null
                : () => _setStatus(TaskStatus.completed),
          ),
        ),
      GhostButton(label: 'Close', onPressed: _close),
    ];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: WebModal(
        title: task.isSubtask ? 'Subtask' : 'Task',
        subtitle: crumbs.isEmpty ? null : crumbs.join('  ›  '),
        icon: done ? Icons.task_alt : Icons.check_circle_outline,
        width: 820,
        onClose: _close,
        actions: actions,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_removed)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Brand.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Brand.danger.withValues(alpha: 0.3),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Brand.danger),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This record was removed',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    task.title,
                    style: text.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: done ? context.brand.paperDim : context.brand.paper,
                      decoration:
                          done ? TextDecoration.lineThrough : TextDecoration.none,
                      decorationColor: context.brand.paperDim,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                StatusPill(
                  label: done
                      ? 'COMPLETED'
                      : (task.statusLabel.isEmpty
                              ? _bucketLabel(task.bucket)
                              : task.statusLabel)
                          .toUpperCase(),
                  color: done ? Brand.success : _bucketColor(context, task.bucket),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  'Move to',
                  style: text.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 12),
                _BucketActions(
                  current: task.bucket,
                  busy: _busy || _removed,
                  onPick: _moveTo,
                ),
                if (_busy) ...[
                  const SizedBox(width: 12),
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: TpLoader(
                      strokeWidth: 2,
                      color: Brand.signal,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            _fields(context, task, dt, done),
            const SizedBox(height: 20),
            _sectionTitle(context, 'Description'),
            const SizedBox(height: 8),
            _description(context, task),
            if (!task.isSubtask) ...[
              const SizedBox(height: 20),
              _subtasksSection(context),
            ],
            ..._screenshots(context, d, done),
            if (!done) ...[
              const SizedBox(height: 20),
              _completionSection(context),
            ],
            const SizedBox(height: 20),
            _activitySection(context),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String label, {Widget? trailing}) {
    final text = Theme.of(context).textTheme;
    return Row(children: [
      Text(label, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
      if (trailing != null) ...[const SizedBox(width: 8), trailing],
    ]);
  }

  Widget _fields(BuildContext context, TaskItem task, _J? dt, bool done) {
    final assignees = ((_detail?['assignees'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => opsStr(m['name']))
        .where((n) => n.isNotEmpty)
        .toList();
    final assigneeText = _detail == null
        ? ((task.primaryAssigneeName ?? '').isEmpty ? '—' : task.primaryAssigneeName!)
        : (assignees.isEmpty ? 'Unassigned' : assignees.join(', '));
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.brand.rule),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _FieldRow(
                  label: assignees.length > 1 ? 'Assignees' : 'Assignee',
                  value: assigneeText,
                ),
              ),
              Expanded(
                child: _FieldRow(
                  label: 'Priority',
                  value: _priorityLabel(task.priority),
                  valueColor: _priorityColor(task.priority),
                  leftBorder: true,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: _FieldRow(
                  label: 'Start date',
                  value: dt != null
                      ? opsStr(dt['start_label'])
                      : (task.startDate == null ? '—' : _long(task.startDate!)),
                ),
              ),
              Expanded(
                child: _FieldRow(
                  label: 'Due date',
                  value: task.dueDate == null ? 'Add date' : _long(task.dueDate!),
                  onTap: (_busy || !_canEdit) ? null : _pickDueDate,
                  actionable: _canEdit,
                  leftBorder: true,
                  valueColor: task.isOverdue
                      ? Brand.danger
                      : (task.dueDate == null ? Brand.signal : null),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: _FieldRow(
                  label: 'Project',
                  value: (task.projectName ?? '').isEmpty ? '—' : task.projectName!,
                  last: true,
                ),
              ),
              Expanded(
                child: _FieldRow(
                  label: done ? 'Completed' : 'Status',
                  value: done
                      ? (dt == null ? '—' : opsStr(dt['completed_label']))
                      : 'In progress',
                  leftBorder: true,
                  last: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _description(BuildContext context, TaskItem task) {
    final text = Theme.of(context).textTheme;
    if (_detail != null && _canEdit) {
      return TextField(
        controller: _desc,
        focusNode: _descFocus,
        minLines: 3,
        maxLines: 10,
        maxLength: 10000,
        decoration: const InputDecoration(
          hintText: 'Add a description…',
          counterText: '',
        ),
      );
    }
    final body = _detail != null
        ? _desc.text
        : _stripTags(task.description);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.brand.surfaceHi,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: context.brand.rule),
      ),
      child: SelectableText(
        body.trim().isEmpty ? 'No description.' : body,
        style: text.bodyMedium?.copyWith(
          color: body.trim().isEmpty ? context.brand.paperDim : context.brand.paper,
          height: 1.55,
        ),
      ),
    );
  }

  Widget _subtasksSection(BuildContext context) {
    final doneCount = _subtasks.where((s) => s.isDone).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(
          context,
          'Subtasks',
          trailing: _subtasks.isEmpty
              ? null
              : StatusPill(label: '$doneCount/${_subtasks.length}'),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.brand.rule),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final s in _subtasks)
                _SubtaskRow(
                  subtask: s,
                  onToggle: () => _toggleSub(s),
                  onDelete: () => _deleteSub(s),
                ),
              if (_subAdding) _subAddRow(context) else _subStub(context),
            ],
          ),
        ),
      ],
    );
  }

  Widget _subStub(BuildContext context) {
    return InkWell(
      onTap: () => setState(() => _subAdding = true),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: context.brand.rule, width: 1.5),
            ),
          ),
          const SizedBox(width: 10),
          Text('Add subtask',
              style: TextStyle(color: context.brand.paperDim, fontSize: 13.5)),
        ]),
      ),
    );
  }

  Widget _subAddRow(BuildContext context) {
    String fmt(DateTime? d) => d == null ? '' : _short(d);
    Widget chip(IconData icon, String label, VoidCallback onTap, {VoidCallback? onClear}) =>
        InputChip(
          avatar: Icon(icon, size: 14),
          label: Text(label, style: const TextStyle(fontSize: 12)),
          onPressed: onTap,
          onDeleted: onClear,
          deleteIcon: onClear == null ? null : const Icon(Icons.close, size: 14),
        );
    final picked = _users.where((u) => u.userId == _subUser);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): () => setState(() {
                    _resetSubForm();
                    _subAdding = false;
                  }),
            },
            child: TextField(
              controller: _subTitle,
              autofocus: true,
              maxLength: 255,
              onSubmitted: (_) => _createSub(),
              decoration: const InputDecoration(
                hintText: 'Subtask name',
                counterText: '',
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              chip(Icons.play_arrow_outlined,
                  _subStart == null ? 'Start' : fmt(_subStart), () async {
                final p = await _pickDate(_subStart, last: _subDue);
                if (p != null) setState(() => _subStart = p);
              }, onClear: _subStart == null ? null : () => setState(() => _subStart = null)),
              chip(Icons.event, _subDue == null ? 'Due' : fmt(_subDue), () async {
                final p = await _pickDate(_subDue ?? _subStart, first: _subStart);
                if (p != null) setState(() => _subDue = p);
              }, onClear: _subDue == null ? null : () => setState(() => _subDue = null)),
              PopupMenuButton<int>(
                tooltip: 'Assign this subtask',
                onSelected: (v) => setState(() => _subUser = v),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 0, child: Text('Unassigned')),
                  for (final u in _users)
                    PopupMenuItem(value: u.userId, child: Text(u.name)),
                ],
                child: Chip(
                  avatar: const Icon(Icons.person_add_alt_1_outlined, size: 14),
                  label: Text(picked.isEmpty ? 'Assignee' : picked.first.name,
                      style: const TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 6),
              GhostButton(
                label: 'Cancel',
                onPressed: () => setState(() {
                  _resetSubForm();
                  _subAdding = false;
                }),
              ),
              SignalButton(
                label: _subBusy ? 'Adding…' : 'Add',
                busy: _subBusy,
                onPressed: _createSub,
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _screenshots(BuildContext context, _J? d, bool done) {
    final shot = opsStr(d?['screenshot']);
    final comp = opsStr(d?['completion_screenshot']);
    Widget img(String title, String path) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            _sectionTitle(context, title),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (ctx) => Dialog(
                    child: InteractiveViewer(
                      child: Image.network(_svc.url(path),
                          headers: _svc.authHeaders, fit: BoxFit.contain),
                    ),
                  ),
                ),
                child: Image.network(
                  _svc.url(path),
                  headers: _svc.authHeaders,
                  height: 220,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox(
                      height: 60, child: Center(child: Icon(Icons.broken_image))),
                ),
              ),
            ),
          ],
        );
    return [
      if (shot.isNotEmpty)
        img(done ? 'Original screenshot' : 'Attached screenshot', shot),
      if (comp.isNotEmpty) img('Completion attachment', comp),
    ];
  }

  Widget _completionSection(BuildContext context) {
    final b = context.brand;
    if (_detail != null && _readonly) {
      return Row(children: [
        Icon(Icons.lock_outline, size: 15, color: b.paperDim),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'You delegated this task — only the assignee can mark it complete.',
            style: TextStyle(color: b.paperDim, fontSize: 13.5),
          ),
        ),
      ]);
    }
    final name = _attachPath == null
        ? 'No file selected'
        : _attachPath!.split(RegExp(r'[\\/]')).last;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(context, 'Completion attachment',
            trailing: Text('(optional)',
                style: TextStyle(color: b.paperDim, fontSize: 12.5))),
        const SizedBox(height: 8),
        Row(children: [
          GhostButton(
            label: 'Select file',
            icon: Icons.attach_file,
            onPressed: _toggling ? null : _pickAttachment,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: b.paperDim, fontSize: 13)),
          ),
          SignalButton(
            label: 'Mark complete with attachment',
            icon: Icons.check_circle,
            busy: _toggling,
            onPressed: (_removed || _detail == null)
                ? null
                : () => _setStatus(TaskStatus.completed, attachment: _attachPath),
          ),
        ]),
      ],
    );
  }

  Widget _activitySection(BuildContext context) {
    final b = context.brand;
    final comments = ((_detail?['comments'] as List?) ?? const [])
        .whereType<Map>()
        .toList();
    final all = ((_detail?['activity'] as List?) ?? const [])
        .whereType<Map>()
        .toList();
    Widget tab(String label, bool active, VoidCallback onTap, {String? count}) =>
        InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                    color: active ? Brand.signal : Colors.transparent, width: 2),
              ),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: active ? b.paper : b.paperDim)),
              if (count != null) ...[
                const SizedBox(width: 6),
                StatusPill(label: count),
              ],
            ]),
          ),
        );
    Widget item(Map m, {bool comment = false}) {
      final author = opsStr(m['author_name']).isEmpty ? 'Someone' : opsStr(m['author_name']);
      final verb = opsStr(m['verb']);
      final body = opsStr(m['body']);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: Brand.signal.withValues(alpha: 0.15),
            child: Text(opsStr(m['author_initial']),
                style: const TextStyle(
                    color: Brand.signal, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(author, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                if (verb.isNotEmpty)
                  Text(verb, style: TextStyle(color: b.paperDim, fontSize: 13)),
                Text(opsStr(m['time_label']),
                    style: TextStyle(color: b.paperDim, fontSize: 12)),
              ]),
              if (body.isNotEmpty) ...[
                const SizedBox(height: 3),
                SelectableText(body, style: const TextStyle(fontSize: 13.5, height: 1.45)),
              ],
            ]),
          ),
          if (comment && m['is_mine'] == true)
            IconButton(
              tooltip: 'Delete comment',
              iconSize: 16,
              visualDensity: VisualDensity.compact,
              onPressed: () => _deleteComment(opsInt(m['id'])),
              icon: Icon(Icons.close, color: b.paperDim),
            ),
        ]),
      );
    }

    final list = _commentsTab
        ? (comments.isEmpty
            ? [Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('No comments yet.', style: TextStyle(color: b.paperDim)))]
            : [for (final c in comments) item(c, comment: true)])
        : (all.isEmpty
            ? [Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('Nothing has happened yet.', style: TextStyle(color: b.paperDim)))]
            : [for (final a in all) item(a)]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: b.rule))),
          child: Row(children: [
            tab('Comments', _commentsTab, () => setState(() => _commentsTab = true),
                count: '${comments.length}'),
            const SizedBox(width: 18),
            tab('All activity', !_commentsTab, () => setState(() => _commentsTab = false)),
          ]),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: ListView(shrinkWrap: true, children: list),
        ),
        const SizedBox(height: 8),
        CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.enter, control: true): _addComment,
            const SingleActivator(LogicalKeyboardKey.enter, meta: true): _addComment,
          },
          child: TextField(
            controller: _comment,
            enabled: !_commentBusy,
            minLines: 2,
            maxLines: 5,
            maxLength: 4000,
            decoration: const InputDecoration(
              hintText: 'Add a comment…',
              counterText: '',
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: SignalButton(
            label: 'Comment',
            busy: _commentBusy,
            onPressed: _addComment,
          ),
        ),
      ],
    );
  }

  static String _long(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  static String _short(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}';
  }

  static String _priorityLabel(TaskPriority p) {
    switch (p) {
      case TaskPriority.high:
        return 'High';
      case TaskPriority.low:
        return 'Low';
      case TaskPriority.medium:
        return 'Medium';
    }
  }

  static Color _priorityColor(TaskPriority p) {
    switch (p) {
      case TaskPriority.high:
        return Brand.danger;
      case TaskPriority.low:
        return Brand.info;
      case TaskPriority.medium:
        return Brand.warning;
    }
  }

  static String _bucketLabel(TaskBucket b) {
    switch (b) {
      case TaskBucket.todo:
        return 'To do';
      case TaskBucket.doing:
        return 'Doing';
      case TaskBucket.done:
        return 'Done';
    }
  }

  Color _bucketColor(BuildContext context, TaskBucket b) {
    switch (b) {
      case TaskBucket.todo:
        return context.brand.paper;
      case TaskBucket.doing:
        return Brand.danger;
      case TaskBucket.done:
        return Brand.success;
    }
  }

  static String _stripTags(String html) {
    var s = html.replaceAll(RegExp(r'<[^>]+>'), ' ');
    s = s
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

class _BucketActions extends StatelessWidget {
  const _BucketActions({
    required this.current,
    required this.busy,
    required this.onPick,
  });

  final TaskBucket current;
  final bool busy;
  final void Function(TaskBucket) onPick;

  @override
  Widget build(BuildContext context) {
    final others = <(TaskBucket, String, Color)>[];
    void add(TaskBucket b, String label, Color tone) {
      if (b != current) others.add((b, label, tone));
    }

    if (current == TaskBucket.todo) {
      add(TaskBucket.doing, 'Doing', Brand.danger);
      add(TaskBucket.done, 'Done', Brand.success);
    } else if (current == TaskBucket.doing) {
      add(TaskBucket.todo, 'To do', context.brand.paperDim);
      add(TaskBucket.done, 'Completed', Brand.success);
    } else {
      add(TaskBucket.todo, 'To do', context.brand.paperDim);
      add(TaskBucket.doing, 'Doing', Brand.danger);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < others.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          _BucketButton(
            label: others[i].$2,
            tone: others[i].$3,
            busy: busy,
            onTap: () => onPick(others[i].$1),
          ),
        ],
      ],
    );
  }
}

class _BucketButton extends StatelessWidget {
  const _BucketButton({
    required this.label,
    required this.tone,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final Color tone;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = busy ? context.brand.paperDim : tone;
    return OutlinedButton.icon(
      onPressed: busy ? null : onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        foregroundColor: c,
        side: BorderSide(color: busy ? context.brand.rule : tone),
      ),
      icon: Icon(Icons.arrow_forward, size: 14, color: c),
      label: Text(
        label,
        style: TextStyle(color: c, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.label,
    required this.value,
    this.onTap,
    this.actionable = false,
    this.valueColor,
    this.leftBorder = false,
    this.last = false,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;
  final bool actionable;
  final Color? valueColor;
  final bool leftBorder;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final row = Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: text.bodySmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodyMedium?.copyWith(
              color: valueColor ?? context.brand.paper,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (actionable)
          Icon(
            Icons.edit_calendar_outlined,
            size: 16,
            color: context.brand.paperDim,
          ),
      ],
    );
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: last ? BorderSide.none : BorderSide(color: context.brand.rule),
          left: leftBorder ? BorderSide(color: context.brand.rule) : BorderSide.none,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          mouseCursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: row,
          ),
        ),
      ),
    );
  }
}

class _SubtaskRow extends StatelessWidget {
  const _SubtaskRow({
    required this.subtask,
    required this.onToggle,
    required this.onDelete,
  });
  final Subtask subtask;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final names = subtask.assignees.map((a) => a.name).where((n) => n.isNotEmpty).toList();
    if (names.isEmpty && (subtask.primaryAssigneeName ?? '').isNotEmpty) {
      names.add(subtask.primaryAssigneeName!);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.brand.rule)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: subtask.isDone ? 'Mark incomplete' : 'Mark complete',
            visualDensity: VisualDensity.compact,
            onPressed: onToggle,
            icon: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: subtask.isDone ? Brand.success : Colors.transparent,
                border: Border.all(
                  color: subtask.isDone ? Brand.success : context.brand.rule,
                  width: 1.5,
                ),
              ),
              child: subtask.isDone
                  ? const Icon(Icons.check, size: 10, color: Colors.white)
                  : null,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              subtask.title,
              style: text.bodyMedium?.copyWith(
                color: subtask.isDone ? context.brand.paperDim : context.brand.paper,
                decoration: subtask.isDone
                    ? TextDecoration.lineThrough
                    : TextDecoration.none,
              ),
            ),
          ),
          if (subtask.dueDate != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                _TaskDetailScreenState._short(subtask.dueDate!),
                style: text.bodySmall,
              ),
            ),
          if (names.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Tooltip(
                message: names.join(', '),
                child: CircleAvatar(
                  radius: 11,
                  backgroundColor: Brand.signal,
                  child: Text(
                    names.first.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Delete subtask',
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            onPressed: onDelete,
            icon: Icon(Icons.close, color: context.brand.paperDim),
          ),
        ],
      ),
    );
  }
}
