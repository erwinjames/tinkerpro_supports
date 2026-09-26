import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models/reminder_models.dart';
import '../services/reminder_service.dart';
import '../services/task_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'task_detail_screen.dart';
import 'task_list_screen.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key, required this.api});

  final ApiClient api;

  static int _openCount = 0;

  static bool get isOpen => _openCount > 0;

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  late final ReminderService _service = ReminderService(widget.api);
  ReminderFeed? _feed = ReminderService.latest.value;
  bool _loading = true;
  String? _error;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    RemindersScreen._openCount++;
    _load();
  }

  @override
  void dispose() {
    RemindersScreen._openCount--;
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final feed = await _service.load();
      if (!mounted) return;
      setState(() {
        _feed = feed;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendly(e);
      });
    }
  }

  String _friendly(Object e) {
    var t = e.toString();
    if (t.startsWith('Exception: ')) t = t.substring(11);
    if (t.contains('SocketException') || t.contains('TimeoutException')) {
      return 'Could not reach the server. Pull down to try again.';
    }
    return t;
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(String key, Future<void> Function() action,
      {String? done}) async {
    if (_busy.contains(key)) return;
    setState(() => _busy.add(key));
    try {
      await action();
      await _load();
      if (done != null && mounted) _toast(done);
    } catch (e) {
      if (mounted) _toast(_friendly(e));
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  Future<void> _editNote([StickyNote? note]) async {
    final result = await showModalBottomSheet<_NoteDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _NoteEditor(note: note),
    );
    if (result == null) return;
    if (note == null) {
      await _run(
        'note-new',
        () => _service.addNote(
            title: result.title, body: result.body, due: result.due),
        done: 'Note added',
      );
    } else {
      await _run(
        'note-${note.id}',
        () => _service.updateNote(
            id: note.id, title: result.title, body: result.body, due: result.due),
        done: 'Note saved',
      );
    }
  }

  Future<void> _deleteNote(StickyNote note) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this note?'),
        content: Text(note.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Brand.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run('note-${note.id}', () => _service.deleteNote(note.id),
        done: 'Note deleted');
  }

  Future<void> _openTask(TaskReminder task) async {
    final tasks = TaskService(widget.api);
    try {
      final all = await tasks.listTasks();
      final match = all.where((t) => t.id == task.id).toList();
      if (!mounted) return;
      if (match.isNotEmpty) {
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => TaskDetailScreen(
            taskId: task.id,
            initial: match.first,
            service: tasks,
          ),
        ));
      } else {
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => TaskListScreen(service: tasks),
        ));
      }
      if (mounted) _load();
    } catch (e) {
      if (mounted) _toast(_friendly(e));
    }
  }

  Color _bucketColor(ReminderBucket b) {
    switch (b) {
      case ReminderBucket.overdue:
        return Brand.danger;
      case ReminderBucket.today:
        return Brand.orange;
      case ReminderBucket.week:
        return Brand.info;
      case ReminderBucket.later:
        return Brand.success;
      case ReminderBucket.undated:
        return context.brand.paperDim;
    }
  }

  String _headline(ReminderFeed feed) {
    final parts = <String>[];
    final taskDue = feed.taskOverdue + feed.taskToday;
    if (taskDue > 0) parts.add('$taskDue task${taskDue == 1 ? '' : 's'} due');
    if (feed.ptuActive > 0) parts.add('${feed.ptuActive} PTU to upload');
    if (feed.notesDue > 0) {
      parts.add('${feed.notesDue} note${feed.notesDue == 1 ? '' : 's'} due');
    }
    return parts.isEmpty ? 'You are all caught up' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final feed = _feed;
    return StationScaffold(
      title: 'Reminders',
      subtitle: feed == null ? 'Tasks, PTU uploads and your notes' : _headline(feed),
      onBack: () => Navigator.of(context).maybePop(),
      backAlways: true,
      showBottomBrand: false,
      trailing: StationAction(
        icon: Icons.note_add_rounded,
        tooltip: 'Add note',
        onPressed: () => _editNote(),
      ),
      child: RefreshIndicator(
        onRefresh: _load,
        child: _body(feed),
      ),
    );
  }

  Widget _body(ReminderFeed? feed) {
    if (feed == null && _loading) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: const [SkeletonList(count: 5, avatar: false)],
      );
    }
    if (feed == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 40, 16, 24),
        children: [
          EmptyState(
            icon: Icons.cloud_off_rounded,
            label: 'Could not load reminders',
            hint: _error ?? 'Pull down to try again.',
          ),
        ],
      );
    }

    final children = <Widget>[];
    if (_loading) {
      children.add(const Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: LinearProgressIndicator(minHeight: 2),
      ));
    }
    if (_error != null) {
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: StatusPill(label: _error!, color: Brand.danger, icon: Icons.error_outline),
      ));
    }

    children.add(_tallies(feed));
    children.add(const SizedBox(height: 18));

    children.addAll(_notesSection(feed));
    if (feed.canTask) children.addAll(_tasksSection(feed));
    if (feed.canBir) children.addAll(_ptuSection(feed));

    if (feed.isEmpty) {
      children.add(const Padding(
        padding: EdgeInsets.only(top: 24),
        child: EmptyState(
          icon: Icons.check_circle_outline_rounded,
          label: 'Nothing to remind you about',
          hint: 'Tap the note button at the top to jot something down.',
        ),
      ));
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: children,
    );
  }

  Widget _tallies(ReminderFeed feed) {
    Widget tally(String label, int value, Color color, IconData icon) {
      final text = Theme.of(context).textTheme;
      return Expanded(
        child: AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              IconTile(icon: icon, color: color, size: 34, iconSize: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$value', style: text.titleLarge),
                    Text(label,
                        style: text.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final taskDue = feed.taskOverdue + feed.taskToday;
    return Row(
      children: [
        if (feed.canTask) ...[
          tally('Tasks due', taskDue, taskDue > 0 ? Brand.danger : Brand.success,
              Icons.task_alt_rounded),
          const SizedBox(width: 10),
        ],
        if (feed.canBir) ...[
          tally('PTU to upload', feed.ptuActive,
              feed.ptuActive > 0 ? Brand.orange : Brand.success,
              Icons.upload_file_rounded),
          const SizedBox(width: 10),
        ],
        tally('Notes', feed.notes.length, Brand.info, Icons.sticky_note_2_rounded),
      ],
    );
  }

  List<Widget> _notesSection(ReminderFeed feed) {
    return [
      SectionHeader(
        title: 'My notes',
        trailing: TextButton.icon(
          onPressed: _busy.contains('note-new') ? null : () => _editNote(),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add'),
        ),
      ),
      if (feed.notes.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Text(
            'No notes yet. Notes you add here also show in the Reminders panel on the website.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        )
      else
        ...feed.notes.map((n) => _noteCard(n)),
      const SizedBox(height: 12),
    ];
  }

  Widget _noteCard(StickyNote note) {
    final text = Theme.of(context).textTheme;
    final busy = _busy.contains('note-${note.id}');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        onTap: busy ? null : () => _editNote(note),
        color: const Color(0xFFFFF8E4),
        borderColor: const Color(0xFFE8D49A),
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    note.title,
                    style: text.titleSmall?.copyWith(color: const Color(0xFF3A2B0C)),
                  ),
                  if (note.body.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      note.body,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(color: const Color(0xFF6A5423)),
                    ),
                  ],
                  const SizedBox(height: 8),
                  StatusPill(
                    label: note.label,
                    color: _bucketColor(note.bucket),
                    icon: Icons.event_rounded,
                  ),
                ],
              ),
            ),
            busy
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : IconButton(
                    tooltip: 'Delete note',
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: Color(0xFF8A7440)),
                    onPressed: () => _deleteNote(note),
                  ),
          ],
        ),
      ),
    );
  }

  List<Widget> _tasksSection(ReminderFeed feed) {
    final text = Theme.of(context).textTheme;
    return [
      SectionHeader(title: 'Tasks'),
      if (feed.taskMode == 'user' && feed.taskOwner.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text("Showing ${feed.taskOwner}'s task reminders",
              style: text.bodySmall),
        ),
      if (feed.taskMode == 'off')
        Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Text('Task reminders are turned off for your account.',
              style: text.bodySmall),
        )
      else if (feed.tasks.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Text('No open tasks due soon.', style: text.bodySmall),
        )
      else
        ...feed.tasks.map((t) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                onTap: () => _openTask(t),
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    IconTile(
                      icon: Icons.task_alt_rounded,
                      color: _bucketColor(t.bucket),
                      size: 36,
                      iconSize: 18,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.title,
                              style: text.titleSmall,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 4),
                          Text(
                            [
                              t.label,
                              if (t.project.isNotEmpty) t.project,
                              if (t.assigner.isNotEmpty) 'from ${t.assigner}',
                            ].join(' · '),
                            style: text.bodySmall
                                ?.copyWith(color: _bucketColor(t.bucket)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: context.brand.paperDim),
                  ],
                ),
              ),
            )),
      if (feed.taskMode != 'off' && feed.taskOpen > feed.tasks.length)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => TaskListScreen(service: TaskService(widget.api)),
            )),
            child: Text('See all ${feed.taskOpen} open tasks'),
          ),
        ),
      const SizedBox(height: 12),
    ];
  }

  List<Widget> _ptuSection(ReminderFeed feed) {
    final text = Theme.of(context).textTheme;

    Widget ptuCard(PtuReminder p, {required bool completed}) {
      final key = 'ptu-${p.id}';
      final busy = _busy.contains(key);
      final meta = [
        if (p.tin.isNotEmpty) 'TIN ${p.tin}',
        if (p.branchCode.isNotEmpty) p.branchCode,
        if (completed && p.label.isNotEmpty) p.label,
      ].join(' · ');
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: AppCard(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              IconTile(
                icon: completed
                    ? Icons.check_circle_rounded
                    : Icons.upload_file_rounded,
                color: completed ? Brand.success : Brand.orange,
                size: 36,
                iconSize: 18,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name,
                        style: text.titleSmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(meta, style: text.bodySmall),
                    ],
                  ],
                ),
              ),
              busy
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : TextButton(
                      onPressed: () => _run(
                        key,
                        () => _service.dismissPtu(p.id),
                        done: completed ? 'Marked as done' : 'Reminder hidden',
                      ),
                      child: Text(completed ? 'Done' : 'Hide'),
                    ),
            ],
          ),
        ),
      );
    }

    return [
      SectionHeader(title: 'PTU to upload'),
      if (feed.ptuPending.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Text('No clients are waiting for a PTU upload.',
              style: text.bodySmall),
        )
      else ...[
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            'Upload the PTU from the BIR tab. Hide removes the reminder for you only.',
            style: text.bodySmall,
          ),
        ),
        ...feed.ptuPending.map((p) => ptuCard(p, completed: false)),
      ],
      if (feed.ptuCompleted.isNotEmpty) ...[
        const SizedBox(height: 8),
        SectionHeader(title: 'PTU recently uploaded'),
        ...feed.ptuCompleted.map((p) => ptuCard(p, completed: true)),
      ],
    ];
  }
}

class _NoteDraft {
  const _NoteDraft(this.title, this.body, this.due);
  final String title;
  final String body;
  final DateTime? due;
}

class _NoteEditor extends StatefulWidget {
  const _NoteEditor({this.note});

  final StickyNote? note;

  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  late final TextEditingController _title =
      TextEditingController(text: widget.note?.title ?? '');
  late final TextEditingController _body =
      TextEditingController(text: widget.note?.body ?? '');
  late DateTime? _due = widget.note?.due;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  String _dueText() {
    final d = _due;
    if (d == null) return 'No due date';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return 'Due ${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _due ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => _due = picked);
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Give the note a title first.')),
      );
      return;
    }
    Navigator.of(context).pop(_NoteDraft(title, _body.text.trim(), _due));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.note == null ? 'New note' : 'Edit note',
              style: text.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            autofocus: widget.note == null,
            maxLength: 120,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Note title'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _body,
            minLines: 3,
            maxLines: 6,
            maxLength: 1000,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Details (optional)'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDue,
                  icon: const Icon(Icons.event_rounded, size: 18),
                  label: Text(_dueText()),
                ),
              ),
              if (_due != null)
                IconButton(
                  tooltip: 'Clear due date',
                  onPressed: () => setState(() => _due = null),
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
          const SizedBox(height: 16),
          SignalButton(label: 'Save note', onPressed: _save),
        ],
      ),
    );
  }
}
