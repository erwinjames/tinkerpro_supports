import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/task_models.dart';
import '../services/live_sync.dart';
import '../services/ops_data_service.dart';
import '../services/task_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'add_task_screen.dart';
import 'ops_task_roster.dart';
import 'project_list_screen.dart';
import 'task_detail_screen.dart';
import '../widgets/tp_loader.dart';

class TaskListScreen extends StatefulWidget {
  const TaskListScreen({super.key, required this.service});

  final TaskService service;

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

enum _Section { tasks, projects }

class _TaskListScreenState extends State<TaskListScreen>
    with LiveRefresh<TaskListScreen> {
  late Future<List<TaskItem>> _future;
  bool _silentSwap = false;

  final _search = TextEditingController();
  _Section _section = _Section.tasks;
  int? _projectFilter;
  String? _projectFilterName;
  int _projectsNonce = 0;
  final Set<TaskBucket> _collapsed = {};
  OpsDataService? _ops;
  Json? _roster;

  bool get _isRoster => _roster?['is_super_admin'] == true;

  Future<void> _loadRoster() async {
    _ops ??= await OpsDataService.load();
    final r = await _ops!.taskRoster();
    if (mounted) setState(() => _roster = r);
  }

  @override
  void initState() {
    super.initState();
    _loadRoster();
    _future = widget.service.listTasks(projectId: _projectFilter);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  List<String> get liveKeys => const ['task'];

  @override
  void onLiveChange() {
    if (_roster != null && _isRoster) {
      _liveRoster();
      if (_projectFilter == null) return;
    }
    _silentReload();
  }

  Future<void> _liveRoster() async {
    final ops = _ops;
    if (ops == null) return;
    final r = await ops.taskRoster();
    if (!mounted || r['success'] == false || r['is_super_admin'] != true) {
      return;
    }
    setState(() => _roster = r);
  }

  bool _silentBusy = false;

  Future<void> _silentReload() async {
    if (!mounted || _silentBusy) return;
    _silentBusy = true;
    final filter = _projectFilter;
    try {
      final fresh = await widget.service.listTasks(projectId: filter);
      if (!mounted || filter != _projectFilter) return;
      setState(() {
        _silentSwap = true;
        _future = Future.value(fresh);
      });
    } catch (_) {
    } finally {
      _silentBusy = false;
    }
  }

  Future<void> _reload() async {
    setState(() {
      _future = widget.service.listTasks(projectId: _projectFilter);
      _silentSwap = false;
    });
    try {
      await _future;
    } catch (_) {}
  }

  void _refresh() {
    if (_isRoster && _section == _Section.tasks) {
      _loadRoster();
    } else if (_section == _Section.projects) {
      setState(() => _projectsNonce++);
    } else {
      _reload();
    }
  }

  void _onOpenProject(Project p) {
    setState(() {
      _projectFilter = p.id;
      _projectFilterName = p.name;
      _section = _Section.tasks;
    });
    _reload();
  }

  void _clearFilter() {
    setState(() {
      _projectFilter = null;
      _projectFilterName = null;
    });
    _reload();
  }

  Future<void> _openAddTask() async {
    final added = await AddTaskScreen.show(
      context,
      service: widget.service,
      currentUserId: widget.service.currentUserId,
      projectId: _projectFilter,
    );
    if (added == true) _reload();
  }

  Future<void> _openTask(TaskItem task) async {
    final changed = await TaskDetailScreen.show(
      context,
      task: task,
      service: widget.service,
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

  Widget _rosterPage(BuildContext context) {
    return Container(
      color: context.brand.canvas,
      padding: const EdgeInsets.fromLTRB(70, 10, 70, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionTabs(
            active: _section,
            admin: true,
            onChanged: (s) => setState(() => _section = s),
            onReporting: () => launchUrl(Uri.parse(_ops!.url('reporting.php'))),
            onExport: () => opsOpenTaskExport(context, _ops!),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _section == _Section.tasks
                ? OpsTaskRoster(
                    svc: _ops!,
                    data: _roster!,
                    onReload: _loadRoster,
                  )
                : ProjectListScreen(
                    key: ValueKey(_projectsNonce),
                    service: widget.service,
                    onOpenProject: _onOpenProject,
                    readOnly: true,
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_roster == null) {
      return Container(
        color: context.brand.canvas,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 20,
          height: 20,
          child: TpLoader(strokeWidth: 2, color: Brand.signal),
        ),
      );
    }
    if (_isRoster && _projectFilter == null) return _rosterPage(context);
    final inTasks = _section == _Section.tasks;
    return StationScaffold(
      stationNumber: '09',
      stationLabel: 'TASKS',
      title: 'Task',
      leading: _SectionTabs(
        active: _section,
        onChanged: (s) => setState(() => _section = s),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (inTasks && _projectFilter != null) ...[
            _FilterChip(
              label: _projectFilterName ?? 'Project',
              onClear: _clearFilter,
            ),
            const SizedBox(width: 10),
          ],
          if (inTasks) ...[
            SearchField(
              controller: _search,
              hint: 'Search tasks…',
              width: 260,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(width: 10),
          ],
          StationAction(
            icon: Icons.refresh,
            tooltip: 'Refresh',
            onPressed: _refresh,
          ),
          if (inTasks) ...[
            const SizedBox(width: 10),
            SignalButton(
              label: 'Add task',
              icon: Icons.add,
              onPressed: _openAddTask,
            ),
          ],
        ],
      ),
      child: inTasks
          ? WebCard(
              padding: EdgeInsets.zero,
              expandChild: true,
              child: ColumnResizeScope(
                tableId: 'tasks',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const WebTableHeader(
                      cells: [
                        SizedBox(width: 40),
                        Expanded(child: Text('NAME')),
                        SizedBox(width: 200, child: Text('ASSIGNEE')),
                        SizedBox(width: 130, child: Text('DUE DATE')),
                        SizedBox(width: 110, child: Text('PRIORITY')),
                        SizedBox(width: 110, child: Text('STATUS')),
                      ],
                    ),
                    Expanded(
                      child: FutureBuilder<List<TaskItem>>(
                        future: _future,
                        builder: (context, snap) {
                          if (snap.connectionState == ConnectionState.waiting &&
                              !(_silentSwap && snap.hasData)) {
                            return const Center(child: TpLoader());
                          }
                          if (snap.hasError) {
                            return _ErrorState(
                              error: snap.error.toString(),
                              onRetry: _reload,
                            );
                          }
                          final all = snap.data ?? const <TaskItem>[];
                          if (all.isEmpty) {
                            return const EmptyState(
                              icon: Icons.task_alt_outlined,
                              label: 'No tasks yet',
                              hint: 'Tasks delegated to you will appear here.',
                            );
                          }
                          final q = _search.text.trim().toLowerCase();
                          final tasks = q.isEmpty
                              ? all
                              : all
                                    .where(
                                      (t) =>
                                          t.title.toLowerCase().contains(q) ||
                                          (t.projectName ?? '')
                                              .toLowerCase()
                                              .contains(q) ||
                                          (t.primaryAssigneeName ?? '')
                                              .toLowerCase()
                                              .contains(q),
                                    )
                                    .toList();
                          return _TaskSections(
                            tasks: tasks,
                            collapsed: _collapsed,
                            onToggleGroup: (b) => setState(() {
                              if (!_collapsed.remove(b)) _collapsed.add(b);
                            }),
                            onOpen: _openTask,
                            onToggle: _toggleTask,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ProjectListScreen(
              key: ValueKey(_projectsNonce),
              service: widget.service,
              onOpenProject: _onOpenProject,
            ),
    );
  }
}

Color _bucketTone(BuildContext context, TaskBucket b) {
  switch (b) {
    case TaskBucket.todo:
      return context.brand.paperDim;
    case TaskBucket.doing:
      return Brand.danger;
    case TaskBucket.done:
      return Brand.success;
  }
}

String _bucketLabel(TaskBucket b) {
  switch (b) {
    case TaskBucket.todo:
      return 'To do';
    case TaskBucket.doing:
      return 'Doing';
    case TaskBucket.done:
      return 'Done';
  }
}

Color _priorityTone(TaskPriority p) {
  switch (p) {
    case TaskPriority.high:
      return Brand.danger;
    case TaskPriority.low:
      return Brand.info;
    case TaskPriority.medium:
      return Brand.warning;
  }
}

class _TaskSections extends StatelessWidget {
  const _TaskSections({
    required this.tasks,
    required this.collapsed,
    required this.onToggleGroup,
    required this.onOpen,
    required this.onToggle,
  });

  final List<TaskItem> tasks;
  final Set<TaskBucket> collapsed;
  final ValueChanged<TaskBucket> onToggleGroup;
  final void Function(TaskItem) onOpen;
  final void Function(TaskItem) onToggle;

  @override
  Widget build(BuildContext context) {
    final groups = <TaskBucket, List<TaskItem>>{
      TaskBucket.todo: [],
      TaskBucket.doing: [],
      TaskBucket.done: [],
    };
    for (final t in tasks) {
      groups[t.bucket]!.add(t);
    }
    const empties = {
      TaskBucket.todo: 'No tasks here — hit Add task above.',
      TaskBucket.doing: 'Nothing overdue. Nice.',
      TaskBucket.done: 'Nothing completed yet.',
    };
    return ListView(
      key: const PageStorageKey<String>('tk-task-list'),
      children: [
        for (final entry in groups.entries) ...[
          _GroupHeader(
            title: _bucketLabel(entry.key),
            count: entry.value.length,
            tone: _bucketTone(context, entry.key),
            expanded: !collapsed.contains(entry.key),
            onTap: () => onToggleGroup(entry.key),
          ),
          if (!collapsed.contains(entry.key)) ...[
            for (final t in entry.value)
              _TaskRow(
                task: t,
                onTap: () => onOpen(t),
                onToggle: () => onToggle(t),
              ),
            if (entry.value.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 72,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: context.brand.rule)),
                ),
                child: Text(
                  empties[entry.key]!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ],
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.title,
    required this.count,
    required this.tone,
    required this.expanded,
    required this.onTap,
  });

  final String title;
  final int count;
  final Color tone;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Material(
      color: context.brand.surface,
      child: InkWell(
        onTap: onTap,
        mouseCursor: SystemMouseCursors.click,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: context.brand.rule),
              left: BorderSide(color: tone, width: 3),
            ),
          ),
          child: Row(
            children: [
              Icon(
                expanded ? Icons.expand_more : Icons.chevron_right,
                size: 20,
                color: context.brand.paperDim,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: text.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: context.brand.paper,
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(label: '$count', color: tone),
            ],
          ),
        ),
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
    final hasProject = task.projectName?.isNotEmpty == true;
    final hasParent = task.parentTitle?.isNotEmpty == true;
    final assignee = task.primaryAssigneeName ?? '';
    return WebTableRow(
      onTap: onTap,
      cells: [
        SizedBox(
          width: 40,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Tooltip(
              message: done ? 'Mark as not done' : 'Mark complete',
              child: InkWell(
                onTap: onToggle,
                mouseCursor: SystemMouseCursors.click,
                customBorder: const CircleBorder(),
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done ? Brand.success : Colors.transparent,
                    border: Border.all(
                      color: done ? Brand.success : Brand.inputBorder,
                      width: 1.5,
                    ),
                  ),
                  child: done
                      ? const Icon(Icons.check, size: 12, color: Colors.white)
                      : null,
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: done
                          ? context.brand.paperDim
                          : context.brand.paper,
                      decoration: done
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                      decorationColor: context.brand.paperDim,
                    ),
                  ),
                ),
                if (hasProject) ...[
                  const SizedBox(width: 8),
                  _MetaChip(
                    icon: Icons.folder_open_outlined,
                    label: task.projectName!,
                  ),
                ],
                if (hasParent) ...[
                  const SizedBox(width: 6),
                  _MetaChip(
                    icon: Icons.subdirectory_arrow_right,
                    label: 'Subtask of ${task.parentTitle}',
                  ),
                ],
              ],
            ),
          ),
        ),
        SizedBox(
          width: 200,
          child: assignee.isEmpty
              ? Text('—', style: text.bodySmall)
              : Row(
                  children: [
                    CircleAvatar(
                      radius: 11,
                      backgroundColor: Brand.signal,
                      child: Text(
                        assignee[0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        assignee,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyMedium,
                      ),
                    ),
                  ],
                ),
        ),
        SizedBox(
          width: 130,
          child: task.dueDate == null
              ? Text('—', style: text.bodySmall)
              : Row(
                  children: [
                    Icon(
                      Icons.event,
                      size: 14,
                      color: task.isOverdue
                          ? Brand.danger
                          : context.brand.paperDim,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _shortDate(task.dueDate!),
                      style: text.bodyMedium?.copyWith(
                        color: task.isOverdue ? Brand.danger : null,
                      ),
                    ),
                  ],
                ),
        ),
        SizedBox(
          width: 110,
          child: Align(
            alignment: Alignment.centerLeft,
            child: StatusPill(
              label: task.priority.wire.toUpperCase(),
              color: _priorityTone(task.priority),
            ),
          ),
        ),
        SizedBox(
          width: 110,
          child: Align(
            alignment: Alignment.centerLeft,
            child: StatusPill(
              label:
                  (task.statusLabel.isEmpty
                          ? _bucketLabel(task.bucket)
                          : task.statusLabel)
                      .toUpperCase(),
              color: _bucketTone(context, task.bucket),
            ),
          ),
        ),
      ],
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
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: context.brand.surfaceHi,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: context.brand.rule),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: context.brand.paperDim),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: context.brand.paperDim),
              ),
            ),
          ],
        ),
      ),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const IconTile(
              icon: Icons.error_outline,
              size: 52,
              color: Brand.danger,
            ),
            const SizedBox(height: 14),
            Text('Could not load tasks', style: text.titleMedium),
            const SizedBox(height: 4),
            Text(error, textAlign: TextAlign.center, style: text.bodySmall),
            const SizedBox(height: 16),
            GhostButton(
              label: 'Retry',
              icon: Icons.refresh,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTabs extends StatelessWidget {
  const _SectionTabs({
    required this.active,
    required this.onChanged,
    this.admin = false,
    this.onReporting,
    this.onExport,
  });

  final _Section active;
  final ValueChanged<_Section> onChanged;
  final bool admin;
  final VoidCallback? onReporting;
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    Widget tab(
      String label,
      IconData icon,
      bool isActive,
      VoidCallback onTap, {
      bool boxed = false,
    }) {
      final c = isActive ? const Color(0xFFD86700) : context.brand.paperDim;
      return InkWell(
        onTap: onTap,
        mouseCursor: SystemMouseCursors.click,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
        child: Container(
          height: admin ? 46 : 56,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: boxed ? context.brand.surfaceHi : null,
            borderRadius: boxed ? BorderRadius.circular(4) : null,
            border: boxed
                ? Border.all(color: context.brand.paperDim, width: 1.5)
                : Border(
                    bottom: BorderSide(
                      color: isActive ? Brand.signal : Colors.transparent,
                      width: 2,
                    ),
                  ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: c),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isActive
                      ? c
                      : context.brand.paper.withValues(alpha: 0.85),
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  fontSize: 14.5,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        tab(
          'Projects',
          Icons.folder_open_outlined,
          active == _Section.projects,
          () => onChanged(_Section.projects),
        ),
        const SizedBox(width: 4),
        tab(
          'Tasks',
          Icons.check_circle_outline,
          active == _Section.tasks,
          () => onChanged(_Section.tasks),
        ),
        if (admin) ...[
          const SizedBox(width: 4),
          tab('Reporting', Icons.bar_chart, false, onReporting ?? () {}),
          const SizedBox(width: 4),
          tab(
            'Export',
            Icons.description_outlined,
            false,
            onExport ?? () {},
            boxed: true,
          ),
        ],
      ],
    );
    final scroller = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: row,
    );
    if (!admin) return scroller;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.brand.rule)),
      ),
      alignment: Alignment.centerLeft,
      child: scroller,
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.onClear});

  final String label;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.fromLTRB(10, 0, 2, 0),
      decoration: BoxDecoration(
        color: Brand.signalGlow(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Brand.signalGlow(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.filter_alt_outlined, size: 14, color: Brand.signal),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Brand.signal,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Clear project filter',
            onPressed: onClear,
            iconSize: 14,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            icon: const Icon(Icons.close, color: Brand.signal),
          ),
        ],
      ),
    );
  }
}
