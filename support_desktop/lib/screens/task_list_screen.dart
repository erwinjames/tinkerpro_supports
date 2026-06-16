/// Phase 1 — read-only Task tab. Renders the To do / Doing / Done
/// sections matching the admin PHP layout. Tap-through, edits, and
/// subtask drawers land in subsequent phases.
///
/// Backend dependency: needs an `api.php?action=getTasks` action that
/// mirrors the SELECT in `utils/models/task-facade.php` and returns JSON
/// `{success, tasks: [...]}`. Until that ships the screen shows a
/// recoverable error state with retry.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/task_models.dart';
import '../services/task_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'add_task_screen.dart';
import 'project_list_screen.dart';
import 'task_detail_screen.dart';

class TaskListScreen extends StatefulWidget {
  const TaskListScreen({super.key, required this.service});

  final TaskService service;

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

/// Top-of-screen section switcher — mirrors the web admin's
/// "Projects / Tasks / Reporting" tab nav (reporting deferred).
enum _Section { tasks, projects }

class _TaskListScreenState extends State<TaskListScreen>
    with WidgetsBindingObserver {
  late Future<List<TaskItem>> _future;
  /// Signature of the most recently rendered list. Used to skip
  /// rebuilds when the periodic poll returns identical data — which
  /// is what was yanking the user's scroll position back to the top
  /// every 10 seconds.
  String? _lastSig;
  Timer? _pollTimer;
  static const Duration _pollInterval = Duration(seconds: 10);

  _Section _section = _Section.tasks;
  /// Active project filter — when set, [listTasks] is called with this
  /// id so only that project's tasks show. Cleared by tapping the
  /// "Clear filter" pill in the Tasks header.
  int? _projectFilter;
  String? _projectFilterName;

  @override
  void initState() {
    super.initState();
    _future = widget.service.listTasks(projectId: _projectFilter);
    WidgetsBinding.instance.addObserver(this);
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Pause/resume polling on app lifecycle changes so a backgrounded
  /// app doesn't burn network or wake the device on a 10s cadence.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Resuming after a stretch of background time is the most likely
      // moment something changed server-side, so reload immediately
      // rather than waiting up to 10s for the next poll tick.
      _silentReload();
      _startPolling();
    } else {
      _pollTimer?.cancel();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _silentReload());
  }

  /// Hash the bits of each task that change the rendered output, so we
  /// can short-circuit identical poll responses. Order matters here —
  /// reordering counts as a change because the server sorts by
  /// sort_order / priority / due_date.
  String _signatureOf(List<TaskItem> tasks) {
    final b = StringBuffer();
    for (final t in tasks) {
      b.write(t.id);
      b.write('|');
      b.write(t.status.wire);
      b.write('|');
      b.write(t.priority.wire);
      b.write('|');
      b.write(t.dueDate?.toIso8601String() ?? '');
      b.write('|');
      b.write(t.title);
      b.write(';');
    }
    return b.toString();
  }

  /// Re-fetch without flashing the spinner. Compares the new list to
  /// what's already on screen via a cheap string signature and only
  /// triggers a setState when something actually changed — that way a
  /// quiet 10s poll while the user is scrolling doesn't rebuild the
  /// ListView and reset the scroll offset.
  Future<void> _silentReload() async {
    if (!mounted) return;
    try {
      final fresh = await widget.service.listTasks(projectId: _projectFilter);
      if (!mounted) return;
      final sig = _signatureOf(fresh);
      if (sig == _lastSig) return; // no-op, scroll stays put
      _lastSig = sig;
      setState(() {
        _future = Future.value(fresh);
      });
    } catch (_) {
      // Swallow — periodic poll shouldn't surface error toasts.
      // The user-initiated pull-to-refresh path still shows errors.
    }
  }

  Future<void> _reload() async {
    setState(() {
      _future = widget.service.listTasks(projectId: _projectFilter);
      // Force the next silent-poll comparison to treat whatever lands
      // next as fresh, so the user's explicit pull-to-refresh always
      // surfaces in the UI even if the server hasn't changed anything.
      _lastSig = null;
    });
    await _future;
  }

  /// Called from the Projects view when the user taps a project card.
  /// Filters the task list to that project and switches the active
  /// section back to Tasks.
  void _onOpenProject(Project p) {
    setState(() {
      _projectFilter = p.id;
      _projectFilterName = p.name;
      _section = _Section.tasks;
      _lastSig = null;
    });
    _reload();
  }

  Future<void> _openAddTask() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AddTaskScreen(
          service: widget.service,
          currentUserId: widget.service.currentUserId,
        ),
      ),
    );
    if (added == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final inTasks = _section == _Section.tasks;
    final eyebrow = inTasks ? 'MY TASKS' : 'PROJECTS';
    return Scaffold(
      backgroundColor: context.brand.canvas,
      floatingActionButton: inTasks
          ? FloatingActionButton.extended(
              onPressed: _openAddTask,
              backgroundColor: context.brand.signal,
              foregroundColor: context.brand.canvas,
              icon: const Icon(Icons.add),
              label: const Text('ADD TASK',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  )),
            )
          : null,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Section tabs — Projects / Tasks toggle, matches the web
            // admin's nav. Reporting parity comes in a later phase.
            _SectionTabs(
              active: _section,
              onChanged: (s) => setState(() => _section = s),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(eyebrow,
                      style: text.labelLarge?.copyWith(
                          letterSpacing: 2.4, color: context.brand.paperDim)),
                  const SizedBox(height: 6),
                  Text(
                    inTasks ? 'Get things done' : 'Browse and pin work',
                    style: text.headlineMedium
                        ?.copyWith(color: context.brand.paper),
                  ),
                  if (inTasks && _projectFilter != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: _FilterChip(
                        label: 'Filtered by ${_projectFilterName ?? "project"}',
                        onClear: () {
                          setState(() {
                            _projectFilter = null;
                            _projectFilterName = null;
                            _lastSig = null;
                          });
                          _reload();
                        },
                      ),
                    ),
                ],
              ),
            ),
            const Hairline(),
            Expanded(
              child: inTasks
                  ? RefreshIndicator(
                      color: context.brand.signal,
                      backgroundColor: context.brand.surface,
                      onRefresh: _reload,
                      child: FutureBuilder<List<TaskItem>>(
                        future: _future,
                        builder: (context, snap) {
                          if (snap.connectionState ==
                              ConnectionState.waiting) {
                            return const _CenteredSpinner();
                          }
                          if (snap.hasError) {
                            return _ErrorState(
                              error: snap.error.toString(),
                              onRetry: _reload,
                            );
                          }
                          final tasks = snap.data ?? const <TaskItem>[];
                          if (tasks.isEmpty) {
                            return _EmptyState(onRetry: _reload);
                          }
                          return _TaskSections(
                            tasks: tasks,
                            onOpen: _openTask,
                            onToggle: _toggleTask,
                          );
                        },
                      ),
                    )
                  : ProjectListScreen(
                      service: widget.service,
                      onOpenProject: _onOpenProject,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openTask(TaskItem task) async {
    // Phase 2 detail screen — opens the full-screen drawer-style view.
    // After it returns, refresh in case the user edited anything.
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TaskDetailScreen(
          taskId: task.id,
          initial: task,
          service: widget.service,
        ),
      ),
    );
    if (changed == true) _reload();
  }

  Future<void> _toggleTask(TaskItem task) async {
    final next =
        task.isDone ? TaskStatus.pending : TaskStatus.completed;
    // Optimistic: update the in-flight future's cached list so the
    // checkbox flips immediately. The next reload reconciles with the
    // server's truth.
    try {
      await widget.service.toggleStatus(task.id, next);
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Toggle failed: $e')),
      );
    }
  }
}

/// Splits the loaded tasks into the three buckets the admin uses
/// (todo / doing / done) and renders them as collapsible-feeling
/// sections. Phase 2: rows are tap-into and the round checkbox toggles
/// status via the parent screen's callbacks.
class _TaskSections extends StatelessWidget {
  const _TaskSections({
    required this.tasks,
    required this.onOpen,
    required this.onToggle,
  });

  final List<TaskItem> tasks;
  final void Function(TaskItem) onOpen;
  final void Function(TaskItem) onToggle;

  @override
  Widget build(BuildContext context) {
    final todo = <TaskItem>[];
    final doing = <TaskItem>[];
    final done = <TaskItem>[];
    for (final t in tasks) {
      switch (t.bucket) {
        case TaskBucket.todo:
          todo.add(t);
          break;
        case TaskBucket.doing:
          doing.add(t);
          break;
        case TaskBucket.done:
          done.add(t);
          break;
      }
    }
    Widget row(TaskItem t) => _TaskRow(
          task: t,
          onTap: () => onOpen(t),
          onToggle: () => onToggle(t),
        );
    return ListView(
      // PageStorageKey persists the scroll offset across rebuilds —
      // when a real server-side change triggers a FutureBuilder
      // rebuild, the ListView keeps the user where they were instead
      // of snapping to the top.
      key: const PageStorageKey<String>('tk-task-list'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        _SectionHeader(title: 'TO DO', count: todo.length, tone: context.brand.paperDim),
        ...todo.map(row),
        if (todo.isEmpty) _SectionEmpty(label: 'Nothing on the runway.'),
        const SizedBox(height: 24),
        _SectionHeader(
          title: 'DOING',
          count: doing.length,
          tone: const Color(0xFFE05A2A), // amber-rose, matches PHP --tk-overdue
        ),
        ...doing.map(row),
        if (doing.isEmpty) _SectionEmpty(label: 'Nothing overdue. Nice.'),
        const SizedBox(height: 24),
        _SectionHeader(
          title: 'DONE',
          count: done.length,
          tone: const Color(0xFF35A776),
        ),
        ...done.map(row),
        if (done.isEmpty) _SectionEmpty(label: 'Nothing completed yet.'),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    required this.tone,
  });

  final String title;
  final int count;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(title,
              style: text.labelLarge
                  ?.copyWith(letterSpacing: 2.0, color: tone)),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: context.brand.surfaceHi,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: context.brand.rule),
            ),
            child: Text(
              count.toString(),
              style: text.labelSmall?.copyWith(
                color: context.brand.paperDim,
                fontFeatures: const [],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionEmpty extends StatelessWidget {
  const _SectionEmpty({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.brand.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.brand.rule),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: context.brand.paperDim),
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.task,
    required this.onTap,
    required this.onToggle,
  });

  final TaskItem task;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final done = task.isDone;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: context.brand.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.brand.rule),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  // Independent hit target — toggles the task without
                  // opening the detail drawer when the user taps the
                  // round circle on the leading edge.
                  behavior: HitTestBehavior.opaque,
                  onTap: onToggle,
                  child: Container(
                    width: 22,
                    height: 22,
                    margin: const EdgeInsets.only(top: 1, right: 10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done ? const Color(0xFF35A776) : Colors.transparent,
                      border: Border.all(
                        color: done ? const Color(0xFF35A776) : context.brand.rule,
                        width: 1.5,
                      ),
                    ),
                    child: done
                        ? const Icon(Icons.check, size: 12, color: Colors.white)
                        : null,
                  ),
                ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: text.titleSmall?.copyWith(
                    color: done ? context.brand.paperDim : context.brand.paper,
                    decoration:
                        done ? TextDecoration.lineThrough : TextDecoration.none,
                    decorationColor: context.brand.paperDim,
                  ),
                ),
                if (task.projectName != null && task.projectName!.isNotEmpty ||
                    task.parentTitle != null && task.parentTitle!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (task.projectName?.isNotEmpty == true)
                          _MetaChip(
                            icon: Icons.folder_open_outlined,
                            label: task.projectName!,
                          ),
                        if (task.parentTitle?.isNotEmpty == true)
                          _MetaChip(
                            icon: Icons.subdirectory_arrow_right,
                            label: 'Subtask of ${task.parentTitle}',
                          ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      if (task.dueDate != null) ...[
                        Icon(Icons.event,
                            size: 12,
                            color: task.isOverdue
                                ? const Color(0xFFE05A2A)
                                : context.brand.paperDim),
                        const SizedBox(width: 4),
                        Text(
                          _shortDate(task.dueDate!),
                          style: text.labelSmall?.copyWith(
                              color: task.isOverdue
                                  ? const Color(0xFFE05A2A)
                                  : context.brand.paperDim),
                        ),
                        const SizedBox(width: 10),
                      ],
                      _PriorityDot(priority: task.priority),
                      const SizedBox(width: 4),
                      Text(
                        task.priority.wire.toUpperCase(),
                        style: text.labelSmall?.copyWith(
                            color: context.brand.paperDim, letterSpacing: 1.5),
                      ),
                      const Spacer(),
                      if ((task.primaryAssigneeName ?? '').isNotEmpty)
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: context.brand.signal,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            task.primaryAssigneeName![0].toUpperCase(),
                            style: TextStyle(
                              color: context.brand.canvas,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _shortDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[d.month - 1]} ${d.day}';
  }
}

class _PriorityDot extends StatelessWidget {
  const _PriorityDot({required this.priority});
  final TaskPriority priority;

  @override
  Widget build(BuildContext context) {
    Color c;
    switch (priority) {
      case TaskPriority.high:
        c = const Color(0xFFE05A2A);
        break;
      case TaskPriority.low:
        c = const Color(0xFF7AA3E0);
        break;
      case TaskPriority.medium:
        c = const Color(0xFFE0B14C);
        break;
    }
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: context.brand.surfaceHi,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.brand.rule),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: context.brand.paperDim),
          const SizedBox(width: 4),
          Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: context.brand.paperDim, letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }
}

class _CenteredSpinner extends StatelessWidget {
  const _CenteredSpinner();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 20,
        height: 20,
        child:
            CircularProgressIndicator(strokeWidth: 2, color: context.brand.signal),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRetry});
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
      children: [
        Center(
          child: Column(
            children: [
              Icon(Icons.task_alt_outlined,
                  size: 36, color: context.brand.paperDim),
              const SizedBox(height: 12),
              Text('No tasks yet',
                  style: text.titleMedium?.copyWith(color: context.brand.paper)),
              const SizedBox(height: 6),
              Text(
                'Tasks delegated to you will appear here.',
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: context.brand.paperDim),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});
  final String error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
      children: [
        Center(
          child: Column(
            children: [
              Icon(Icons.error_outline,
                  size: 36, color: context.brand.paperDim),
              const SizedBox(height: 12),
              Text('Could not load tasks',
                  style: text.titleMedium?.copyWith(color: context.brand.paper)),
              const SizedBox(height: 6),
              Text(
                error,
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: context.brand.paperDim),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: onRetry,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: context.brand.signal),
                  foregroundColor: context.brand.signal,
                ),
                child: const Text('RETRY'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}


/// Top section tabs — PROJECTS / TASKS toggle. Matches the web admin
/// shell so users get the same hierarchy on mobile.
class _SectionTabs extends StatelessWidget {
  const _SectionTabs({required this.active, required this.onChanged});

  final _Section active;
  final ValueChanged<_Section> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget tab(_Section s, String label, IconData icon) {
      final isActive = s == active;
      return Expanded(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onChanged(s),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon,
                      size: 16,
                      color: isActive
                          ? context.brand.signal
                          : context.brand.paperDim),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: isActive
                          ? context.brand.signal
                          : context.brand.paperDim,
                      fontWeight:
                          isActive ? FontWeight.w700 : FontWeight.w500,
                      letterSpacing: 2.0,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.brand.rule, width: 1),
        ),
      ),
      child: Row(
        children: [
          tab(_Section.projects, "PROJECTS", Icons.folder_open_outlined),
          tab(_Section.tasks, "TASKS", Icons.check_circle_outline),
        ],
      ),
    );
  }
}

/// Small dismissible pill shown under the Tasks header when a project
/// filter is active. Tapping the × clears the filter and reloads.
class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.onClear});

  final String label;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
      decoration: BoxDecoration(
        color: context.brand.signalGlow(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.brand.signal),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.filter_alt_outlined,
              size: 12, color: context.brand.signal),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: context.brand.signal,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          IconButton(
            onPressed: onClear,
            iconSize: 14,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            icon: Icon(Icons.close, color: context.brand.signal),
          ),
        ],
      ),
    );
  }
}
