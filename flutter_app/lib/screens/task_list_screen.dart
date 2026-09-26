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

enum _Section { tasks, projects }

class _TaskListScreenState extends State<TaskListScreen>
    with WidgetsBindingObserver {
  late Future<List<TaskItem>> _future;
  String? _lastSig;
  Timer? _pollTimer;
  static const Duration _pollInterval = Duration(seconds: 10);

  _Section _section = _Section.tasks;
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
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

  Future<void> _silentReload() async {
    if (!mounted) return;
    try {
      final fresh = await widget.service.listTasks(projectId: _projectFilter);
      if (!mounted) return;
      final sig = _signatureOf(fresh);
      if (sig == _lastSig) return;
      _lastSig = sig;
      setState(() {
        _future = Future.value(fresh);
      });
    } catch (_) {}
  }

  Future<void> _reload() async {
    setState(() {
      _future = widget.service.listTasks(projectId: _projectFilter);
      _lastSig = null;
    });
    await _future;
  }

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
    final b = context.brand;
    final inTasks = _section == _Section.tasks;
    final eyebrow = inTasks ? 'My tasks' : 'Projects';
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      backgroundColor: b.canvas,
      floatingActionButton: inTasks
          ? FloatingActionButton.extended(
              onPressed: _openAddTask,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add task'),
            )
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppHeaderBand(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    if (canPop) ...[
                      AppIconButton(
                        icon: Icons.arrow_back_rounded,
                        tooltip: 'Back',
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            eyebrow,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.labelMedium?.copyWith(
                              color: Brand.orange,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),
                          Semantics(
                            header: true,
                            child: Text(
                              inTasks
                                  ? 'Get things done'
                                  : 'Browse and pin work',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.headlineLarge?.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _SectionTabs(
                  active: _section,
                  onChanged: (s) => setState(() => _section = s),
                ),
              ],
            ),
          ),
          if (inTasks && _projectFilter != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Align(
                alignment: Alignment.centerLeft,
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
            ),
          const SizedBox(height: 12),
          Expanded(
            child: SafeArea(
              top: false,
              child: inTasks
                  ? RefreshIndicator(
                      onRefresh: _reload,
                      child: FutureBuilder<List<TaskItem>>(
                        future: _future,
                        builder: (context, snap) {
                          if (snap.connectionState == ConnectionState.waiting) {
                            return const SkeletonList(
                              count: 6,
                              avatar: false,
                              padding: EdgeInsets.fromLTRB(20, 4, 20, 20),
                            );
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
          ),
        ],
      ),
    );
  }

  Future<void> _openTask(TaskItem task) async {
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
    final next = task.isDone ? TaskStatus.pending : TaskStatus.completed;
    try {
      await widget.service.toggleStatus(task.id, next);
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Toggle failed: $e')));
    }
  }
}

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
    var seq = 0;
    Widget row(TaskItem t) => _Rise(
      index: seq++,
      child: _TaskRow(
        task: t,
        onTap: () => onOpen(t),
        onToggle: () => onToggle(t),
      ),
    );
    Widget head(String title, int count, Color tone, IconData icon) => _Rise(
      index: seq++,
      child: _SectionHeader(title: title, count: count, tone: tone, icon: icon),
    );
    return ListView(
      key: const PageStorageKey<String>('tk-task-list'),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        _Rise(
          index: seq++,
          child: _MomentumHero(
            todo: todo.length,
            doing: doing.length,
            done: done.length,
          ),
        ),
        const SizedBox(height: 18),
        head(
          'To do',
          todo.length,
          Brand.info,
          Icons.radio_button_unchecked_rounded,
        ),
        ...todo.map(row),
        if (todo.isEmpty) const _SectionEmpty(label: 'Nothing on the runway.'),
        const SizedBox(height: 20),
        head(
          'Doing',
          doing.length,
          Brand.warning,
          Icons.local_fire_department_rounded,
        ),
        ...doing.map(row),
        if (doing.isEmpty) const _SectionEmpty(label: 'Nothing overdue. Nice.'),
        const SizedBox(height: 20),
        head('Done', done.length, Brand.success, Icons.check_circle_rounded),
        ...done.map(row),
        if (done.isEmpty) const _SectionEmpty(label: 'Nothing completed yet.'),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    required this.tone,
    required this.icon,
  });

  final String title;
  final int count;
  final Color tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: tone),
          const SizedBox(width: 8),
          Text(title, style: text.titleMedium),
          const SizedBox(width: 8),
          AnimatedSwitcher(
            duration: reduce
                ? Duration.zero
                : const Duration(milliseconds: 240),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: ScaleTransition(scale: anim, child: child),
            ),
            child: GlowBadge(
              key: ValueKey<int>(count),
              label: count.toString(),
              color: tone,
            ),
          ),
        ],
      ),
    );
  }
}

class _MomentumHero extends StatelessWidget {
  const _MomentumHero({
    required this.todo,
    required this.doing,
    required this.done,
  });

  final int todo;
  final int doing;
  final int done;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final total = todo + doing + done;
    final ratio = total == 0 ? 0.0 : done / total;
    return GlassPanel(
      accent: doing > 0 ? Brand.warning : b.signal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Momentum',
                  style: text.labelMedium?.copyWith(
                    color: b.signal,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              GlowBadge(
                label: '$done of $total done',
                color: done == total && total > 0 ? Brand.success : b.signal,
                icon: Icons.check_circle_outline_rounded,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _ProgressBar(value: ratio, color: Brand.success),
          const SizedBox(height: 12),
          Row(
            children: [
              GlowBadge(
                label: '$todo to do',
                color: Brand.info,
                icon: Icons.radio_button_unchecked_rounded,
              ),
              const SizedBox(width: 8),
              GlowBadge(
                label: '$doing doing',
                color: Brand.warning,
                icon: Icons.local_fire_department_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final target = value < 0 ? 0.0 : (value > 1 ? 1.0 : value);
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 8,
        color: b.isDark
            ? Colors.white.withValues(alpha: 0.12)
            : Brand.navy.withValues(alpha: 0.1),
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: target),
          duration: reduce ? Duration.zero : const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          builder: (_, v, _) => Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: v,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: color,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionEmpty extends StatelessWidget {
  const _SectionEmpty({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Brand.radiusLg),
        border: Border.all(color: b.rule),
        color: b.surfaceHi,
      ),
      child: Row(
        children: [
          Icon(Icons.inbox_rounded, size: 16, color: b.paperDim),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

Color _priorityColor(TaskPriority p) {
  switch (p) {
    case TaskPriority.high:
      return Brand.danger;
    case TaskPriority.low:
      return Brand.info;
    case TaskPriority.medium:
      return Brand.warning;
  }
}

String _priorityLabel(TaskPriority p) {
  final w = p.wire;
  return w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}';
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
    final b = context.brand;
    final done = task.isDone;
    final names = task.assignees
        .map((a) => a.name)
        .where((n) => n.trim().isNotEmpty)
        .toList();
    if (names.isEmpty && (task.primaryAssigneeName ?? '').isNotEmpty) {
      names.add(task.primaryAssigneeName!);
    }
    final dueColor = task.isOverdue ? Brand.danger : b.paperDim;
    final accent = done
        ? Brand.success
        : (task.isOverdue ? Brand.danger : _priorityColor(task.priority));
    final flagged = task.isOverdue || task.priority == TaskPriority.high;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        onTap: onTap,
        radius: Brand.radiusLg,
        borderColor: flagged && !done ? accent.withValues(alpha: 0.42) : null,
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CheckMorph(done: done, onToggle: onToggle),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    style: text.titleSmall?.copyWith(
                      color: done ? b.paperDim : b.paper,
                      decoration: done
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                      decorationColor: b.paperDim,
                    ),
                  ),
                  if (task.projectName != null &&
                          task.projectName!.isNotEmpty ||
                      task.parentTitle != null && task.parentTitle!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (task.projectName?.isNotEmpty == true)
                            _MetaChip(
                              icon: Icons.folder_open_rounded,
                              label: task.projectName!,
                            ),
                          if (task.parentTitle?.isNotEmpty == true)
                            _MetaChip(
                              icon: Icons.subdirectory_arrow_right_rounded,
                              label: 'Subtask of ${task.parentTitle}',
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      GlowBadge(
                        label: _priorityLabel(task.priority),
                        color: _priorityColor(task.priority),
                        icon: Icons.flag_rounded,
                      ),
                      if (task.dueDate != null) ...[
                        const SizedBox(width: 8),
                        if (task.isOverdue)
                          Flexible(
                            child: GlowBadge(
                              label: 'Overdue · ${_shortDate(task.dueDate!)}',
                              color: Brand.danger,
                              icon: Icons.calendar_today_rounded,
                            ),
                          )
                        else ...[
                          Icon(
                            Icons.calendar_today_rounded,
                            size: 13,
                            color: dueColor,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              _shortDate(task.dueDate!),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.labelMedium?.copyWith(
                                color: dueColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ],
                      const Spacer(),
                      if (names.isNotEmpty) _AvatarStack(names: names),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _shortDate(DateTime d) {
    const months = [
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
    return '${months[d.month - 1]} ${d.day}';
  }
}

class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.names});

  final List<String> names;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    const size = 24.0;
    const step = 16.0;
    final shown = names.take(3).toList();
    final extra = names.length - shown.length;
    final count = shown.length + (extra > 0 ? 1 : 0);
    final children = <Widget>[];
    for (var i = 0; i < shown.length; i++) {
      children.add(
        Positioned(
          left: i * step,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: b.surface, width: 2),
            ),
            child: Tooltip(
              message: shown[i],
              child: AppAvatar(name: shown[i], size: size),
            ),
          ),
        ),
      );
    }
    if (extra > 0) {
      children.add(
        Positioned(
          left: shown.length * step,
          child: Container(
            width: size + 4,
            height: size + 4,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: b.surfaceHi,
              border: Border.all(color: b.surface, width: 2),
            ),
            child: Text(
              '+$extra',
              style: TextStyle(
                color: b.paperDim,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      width: (count - 1) * step + size + 4,
      height: size + 4,
      child: Stack(children: children),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: b.surfaceHi,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: b.paperDim),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRetry});
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
      children: const [
        EmptyState(
          label: 'No tasks yet',
          hint: 'Tasks delegated to you will appear here.',
          icon: Icons.task_alt_rounded,
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
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
      children: [
        EmptyState(
          label: 'Could not load tasks',
          hint: error,
          icon: Icons.error_outline_rounded,
          action: OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
          ),
        ),
      ],
    );
  }
}

class _SectionTabs extends StatelessWidget {
  const _SectionTabs({required this.active, required this.onChanged});

  final _Section active;
  final ValueChanged<_Section> onChanged;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    Widget tab(_Section s, String label, IconData icon) {
      final isActive = s == active;
      return Expanded(
        child: Semantics(
          button: true,
          selected: isActive,
          child: AnimatedContainer(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: isActive ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(Brand.radiusSm),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(Brand.radiusSm),
                onTap: () => onChanged(s),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icon,
                        size: 18,
                        color: isActive
                            ? Brand.orange
                            : Colors.white.withValues(alpha: 0.78),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: TextStyle(
                          color: isActive
                              ? Brand.navy
                              : Colors.white.withValues(alpha: 0.85),
                          fontWeight: isActive
                              ? FontWeight.w700
                              : FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Brand.radius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          tab(_Section.projects, 'Projects', Icons.folder_open_rounded),
          const SizedBox(width: 4),
          tab(_Section.tasks, 'Tasks', Icons.check_circle_outline_rounded),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.onClear});

  final String label;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 2, 2, 2),
      decoration: BoxDecoration(
        color: b.tint(b.signal),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: b.signal.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.filter_alt_rounded, size: 14, color: b.signal),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: b.signal,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ),
          IconButton(
            onPressed: onClear,
            tooltip: 'Clear filter',
            iconSize: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: Icon(Icons.close_rounded, color: b.signal),
          ),
        ],
      ),
    );
  }
}

class _CheckMorph extends StatelessWidget {
  const _CheckMorph({required this.done, required this.onToggle});

  final bool done;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Semantics(
      button: true,
      checked: done,
      label: done ? 'Mark as not done' : 'Mark as done',
      child: InkResponse(
        onTap: onToggle,
        radius: 22,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Align(
            alignment: const Alignment(-0.6, -0.6),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: done ? 1 : 0, end: done ? 1 : 0),
              duration: reduce
                  ? Duration.zero
                  : const Duration(milliseconds: 280),
              curve: Curves.easeOutBack,
              builder: (_, v, _) {
                final t = v < 0 ? 0.0 : (v > 1 ? 1.0 : v);
                return Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Brand.success.withValues(alpha: t),
                    border: Border.all(
                      color:
                          Color.lerp(b.paperDim, Brand.success, t) ??
                          Brand.success,
                      width: 1.5,
                    ),
                  ),
                  child: Transform.scale(
                    scale: v,
                    child: Opacity(
                      opacity: t,
                      child: const Icon(
                        Icons.check_rounded,
                        size: 15,
                        color: Colors.white,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Rise extends StatefulWidget {
  const _Rise({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_Rise> createState() => _RiseState();
}

class _RiseState extends State<_Rise> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOut,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.07),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _c.value = 1;
      return;
    }
    final steps = widget.index < 0 ? 0 : (widget.index > 7 ? 7 : widget.index);
    if (steps == 0) {
      _c.forward();
      return;
    }
    Future<void>.delayed(Duration(milliseconds: 45 * steps), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _fade,
    child: SlideTransition(position: _slide, child: widget.child),
  );
}
