/// Task detail "drawer" — mirrors the admin web's offcanvas with the
/// title, breadcrumb, field grid, description, and (later phases)
/// subtasks + comments. Phase 2 covers:
///   * Read-only field grid (assignees, dates, priority, status, project)
///   * Mark complete / reopen
///   * Tap-to-edit due date (creator-only on the server, but we let the
///     UI try anyway — the server rejects with a message on a non-creator)
///   * Pull-to-refresh
///
/// Subtask CRUD lands in Phase 3.
library;

import 'package:flutter/material.dart';

import '../models/task_models.dart';
import '../services/task_service.dart';
import '../theme.dart';

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

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  late TaskItem _task = widget.initial;
  bool _dirty = false;
  bool _busy = false;
  List<Subtask> _subtasks = const [];

  @override
  void initState() {
    super.initState();
    _loadSubtasks();
  }

  Future<void> _loadSubtasks() async {
    try {
      final s = await widget.service.listSubtasks(widget.taskId);
      if (mounted) setState(() => _subtasks = s);
    } catch (_) {
      // Non-fatal; subtasks just stay empty.
    }
  }

  /// Move the task into one of the three buckets via the same
  /// `move_to_section` endpoint the admin web uses. Optimistically
  /// updates the local copy so the UI flips immediately; the next list
  /// poll reconciles with the server.
  Future<void> _moveTo(TaskBucket target) async {
    final previous = _task;
    final next = _bucketToOptimistic(target, _task);
    setState(() {
      _busy = true;
      _task = next;
    });
    try {
      await widget.service.moveToSection(widget.taskId, _bucketWire(target));
      _dirty = true;
    } catch (e) {
      // Revert
      setState(() => _task = previous);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Move failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Project the local TaskItem forward based on which bucket the user
  /// chose, mirroring the server-side side-effects in
  /// `task-facade.php`'s move_to_section so the optimistic UI matches
  /// what the next refresh will see.
  static TaskItem _bucketToOptimistic(TaskBucket target, TaskItem t) {
    switch (target) {
      case TaskBucket.todo:
        // status=pending, due_date cleared
        return t.copyWith(status: TaskStatus.pending, dueDate: null);
      case TaskBucket.doing:
        // status=pending, due_date=yesterday (forces overdue bucket)
        final yesterday =
            DateTime.now().subtract(const Duration(days: 1));
        return t.copyWith(status: TaskStatus.pending, dueDate: yesterday);
      case TaskBucket.done:
        // status=completed, due_date untouched
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
      await widget.service.updateDue(taskId: widget.taskId, dueDate: picked);
      _dirty = true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to set due date: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final task = _task;
    return PopScope(
      // Return whether anything changed so the list can refresh.
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
      },
      child: Scaffold(
        backgroundColor: context.brand.canvas,
        appBar: AppBar(
          backgroundColor: context.brand.canvas,
          foregroundColor: context.brand.paper,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(_dirty),
          ),
          title: Text(
            task.isSubtask ? 'Subtask' : 'Task',
            style: text.titleMedium?.copyWith(letterSpacing: 2.0),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Divider(height: 1, color: context.brand.rule),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            // ── Breadcrumb (project / parent) ────────────────────────
            if ((task.projectName ?? '').isNotEmpty)
              _Breadcrumb(
                icon: Icons.folder_open_outlined,
                label: task.projectName!,
              ),
            if ((task.parentTitle ?? '').isNotEmpty)
              _Breadcrumb(
                icon: Icons.subdirectory_arrow_right,
                label: 'Subtask of ${task.parentTitle}',
              ),
            if ((task.projectName ?? '').isNotEmpty ||
                (task.parentTitle ?? '').isNotEmpty)
              const SizedBox(height: 12),

            // ── Title ───────────────────────────────────────────────
            Text(
              task.title,
              style: text.headlineSmall?.copyWith(
                color: task.isDone ? context.brand.paperDim : context.brand.paper,
                decoration: task.isDone
                    ? TextDecoration.lineThrough
                    : TextDecoration.none,
                decorationColor: context.brand.paperDim,
              ),
            ),
            const SizedBox(height: 16),

            // ── Move-to-bucket actions ─────────────────────────────
            // Shows the TWO non-current buckets as buttons. Tapping one
            // calls move_to_section on the server which bundles the
            // status + due-date side-effects in one round-trip.
            _BucketActions(
              current: task.bucket,
              busy: _busy,
              onPick: _moveTo,
            ),
            const SizedBox(height: 20),

            // ── Field grid ──────────────────────────────────────────
            _FieldRow(
              label: 'ASSIGNEE',
              value: (task.primaryAssigneeName ?? '').isEmpty
                  ? '—'
                  : task.primaryAssigneeName!,
            ),
            _FieldRow(
              label: 'DUE DATE',
              value: task.dueDate == null ? 'Add date' : _long(task.dueDate!),
              onTap: _busy ? null : _pickDueDate,
              actionable: true,
              valueColor: task.isOverdue
                  ? const Color(0xFFE05A2A)
                  : context.brand.paper,
            ),
            _FieldRow(
              label: 'START DATE',
              value: task.startDate == null ? '—' : _long(task.startDate!),
            ),
            _FieldRow(
              label: 'PRIORITY',
              value: _priorityLabel(task.priority),
              valueColor: _priorityColor(task.priority),
            ),
            _FieldRow(
              label: 'STATUS',
              value: task.statusLabel.isEmpty
                  ? _bucketLabel(task.bucket)
                  : task.statusLabel,
              valueColor: _bucketColor(context, task.bucket),
            ),

            // ── Description ─────────────────────────────────────────
            const SizedBox(height: 24),
            Text('DESCRIPTION',
                style: text.labelSmall
                    ?.copyWith(color: context.brand.paperDim, letterSpacing: 2.0)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.brand.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: context.brand.rule),
              ),
              child: Text(
                task.description.trim().isEmpty
                    ? 'No description.'
                    : _stripTags(task.description),
                style: text.bodyMedium?.copyWith(
                  color: task.description.trim().isEmpty
                      ? context.brand.paperDim
                      : context.brand.paper,
                  height: 1.55,
                ),
              ),
            ),

            // ── Subtasks (read-only, full CRUD in Phase 3) ──────────
            if (_subtasks.isNotEmpty) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  Text('SUBTASKS',
                      style: text.labelSmall?.copyWith(
                          color: context.brand.paperDim, letterSpacing: 2.0)),
                  const SizedBox(width: 8),
                  Text(
                    '${_subtasks.where((s) => s.isDone).length} / ${_subtasks.length}',
                    style: text.labelSmall?.copyWith(color: context.brand.paperDim),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ..._subtasks.map((s) => _SubtaskRow(subtask: s)),
            ],
          ],
        ),
      ),
    );
  }

  static String _long(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
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
        return const Color(0xFFE05A2A);
      case TaskPriority.low:
        return const Color(0xFF7AA3E0);
      case TaskPriority.medium:
        return const Color(0xFFE0B14C);
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

  /// Takes a BuildContext so the "to do" tone can pull from the active
  /// theme's `paper` — flips from off-white in dark mode to slate in
  /// light mode. The amber/green for doing/done stays fixed across
  /// themes since they read fine on either canvas.
  Color _bucketColor(BuildContext context, TaskBucket b) {
    switch (b) {
      case TaskBucket.todo:
        return context.brand.paper;
      case TaskBucket.doing:
        return const Color(0xFFE05A2A);
      case TaskBucket.done:
        return const Color(0xFF35A776);
    }
  }

  static String _stripTags(String html) {
    // Server stores TinyMCE HTML. The mobile preview keeps it simple —
    // strip tags, collapse whitespace, decode the most common entities.
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

/// Bucket transition control. Renders the TWO buckets the task is NOT
/// currently in as tap-able outlined buttons. Per the user's spec:
///   * To do     → shows [Doing, Done]
///   * Doing     → shows [To do, Completed]
///   * Completed → shows [To do, Doing]
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
    // Order matches the user's spec: each bucket lists the other two
    // in a fixed order so the button positions stay predictable.
    final others = <(TaskBucket, String, Color)>[];
    void add(TaskBucket b, String label, Color tone) {
      if (b != current) others.add((b, label, tone));
    }
    if (current == TaskBucket.todo) {
      add(TaskBucket.doing, 'Doing', const Color(0xFFE05A2A));
      add(TaskBucket.done, 'Done', const Color(0xFF35A776));
    } else if (current == TaskBucket.doing) {
      add(TaskBucket.todo, 'To do', context.brand.paperDim);
      add(TaskBucket.done, 'Completed', const Color(0xFF35A776));
    } else {
      add(TaskBucket.todo, 'To do', context.brand.paperDim);
      add(TaskBucket.doing, 'Doing', const Color(0xFFE05A2A));
    }
    return Row(
      children: [
        for (var i = 0; i < others.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: _BucketButton(
              label: others[i].$2,
              tone: others[i].$3,
              busy: busy,
              onTap: () => onPick(others[i].$1),
            ),
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
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: context.brand.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: busy ? context.brand.rule : tone, width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.arrow_forward, size: 14, color: busy ? context.brand.paperDim : tone),
              const SizedBox(width: 8),
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: busy ? context.brand.paperDim : tone,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 12, color: context.brand.paperDim),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: context.brand.paperDim, letterSpacing: 0.4),
            ),
          ),
        ],
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
  });

  final String label;
  final String value;
  final VoidCallback? onTap;
  final bool actionable;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final row = Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: text.labelSmall
                ?.copyWith(color: context.brand.paperDim, letterSpacing: 2.0),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: text.bodyMedium?.copyWith(color: valueColor ?? context.brand.paper),
          ),
        ),
        if (actionable)
          Icon(Icons.chevron_right, size: 18, color: context.brand.paperDim),
      ],
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 1),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.brand.rule)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: row,
          ),
        ),
      ),
    );
  }
}

class _SubtaskRow extends StatelessWidget {
  const _SubtaskRow({required this.subtask});
  final Subtask subtask;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.brand.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.brand.rule),
      ),
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: subtask.isDone
                  ? const Color(0xFF35A776)
                  : Colors.transparent,
              border: Border.all(
                color: subtask.isDone
                    ? const Color(0xFF35A776)
                    : context.brand.rule,
                width: 1.5,
              ),
            ),
            child: subtask.isDone
                ? const Icon(Icons.check, size: 10, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 10),
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
        ],
      ),
    );
  }
}
