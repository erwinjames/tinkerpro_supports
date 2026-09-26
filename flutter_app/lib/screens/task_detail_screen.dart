library;

import 'package:flutter/material.dart';

import '../models/task_models.dart';
import '../services/task_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';

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
      await widget.service.moveToSection(widget.taskId, _bucketWire(target));
      _dirty = true;
    } catch (e) {
      setState(() => _task = previous);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Move failed: $e')));
      }
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
      await widget.service.updateDue(taskId: widget.taskId, dueDate: picked);
      _dirty = true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to set due date: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final task = _task;
    final statusText = task.statusLabel.isEmpty
        ? _bucketLabel(task.bucket)
        : task.statusLabel;
    final statusColor = _bucketColor(context, task.bucket);
    final assigneeNames = task.assignees
        .map((a) => a.name)
        .where((n) => n.trim().isNotEmpty)
        .toList();
    if (assigneeNames.isEmpty && (task.primaryAssigneeName ?? '').isNotEmpty) {
      assigneeNames.add(task.primaryAssigneeName!);
    }
    final doneCount = _subtasks.where((s) => s.isDone).length;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
      },
      child: StationScaffold(
        stationNumber: '',
        stationLabel: 'Tasks',
        title: task.isSubtask ? 'Subtask' : 'Task',
        subtitle: (task.projectName ?? '').isNotEmpty ? task.projectName! : '',
        showBottomBrand: false,
        onBack: () => Navigator.of(context).pop(_dirty),
        trailing: _busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : null,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            _Rise(
              index: 0,
              child: GlassPanel(
                accent: statusColor,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        IconTile(
                          icon: task.isDone
                              ? Icons.task_alt_rounded
                              : (task.isSubtask
                                    ? Icons.subdirectory_arrow_right_rounded
                                    : Icons.check_circle_outline_rounded),
                          color: statusColor,
                          size: 44,
                          iconSize: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if ((task.projectName ?? '').isNotEmpty)
                                _Breadcrumb(
                                  icon: Icons.folder_open_rounded,
                                  label: task.projectName!,
                                ),
                              if ((task.parentTitle ?? '').isNotEmpty)
                                _Breadcrumb(
                                  icon: Icons.subdirectory_arrow_right_rounded,
                                  label: 'Subtask of ${task.parentTitle}',
                                ),
                              Text(
                                task.title,
                                style: text.titleLarge?.copyWith(
                                  color: task.isDone ? b.paperDim : b.paper,
                                  decoration: task.isDone
                                      ? TextDecoration.lineThrough
                                      : TextDecoration.none,
                                  decorationColor: b.paperDim,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        AnimatedSwitcher(
                          duration:
                              (MediaQuery.maybeOf(context)?.disableAnimations ??
                                  false)
                              ? Duration.zero
                              : const Duration(milliseconds: 280),
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: ScaleTransition(scale: anim, child: child),
                          ),
                          child: GlowBadge(
                            key: ValueKey<String>(statusText),
                            label: statusText,
                            color: statusColor,
                            icon: Icons.circle,
                          ),
                        ),
                        GlowBadge(
                          label: '${_priorityLabel(task.priority)} priority',
                          color: _priorityColor(task.priority),
                          icon: Icons.flag_rounded,
                        ),
                        if (task.dueDate != null)
                          GlowBadge(
                            label: task.isOverdue
                                ? 'Overdue · ${_long(task.dueDate!)}'
                                : 'Due ${_long(task.dueDate!)}',
                            color: task.isOverdue ? Brand.danger : b.paperDim,
                            icon: Icons.calendar_today_rounded,
                          ),
                      ],
                    ),
                    if (assigneeNames.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      const Hairline(),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          for (
                            var i = 0;
                            i < assigneeNames.length && i < 5;
                            i++
                          )
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Tooltip(
                                message: assigneeNames[i],
                                child: AppAvatar(
                                  name: assigneeNames[i],
                                  size: 28,
                                ),
                              ),
                            ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              assigneeNames.length == 1
                                  ? assigneeNames.first
                                  : '${assigneeNames.length} assignees',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const SectionHeader(title: 'Move to'),
            _Rise(
              index: 1,
              child: _BucketActions(
                current: task.bucket,
                busy: _busy,
                onPick: _moveTo,
              ),
            ),
            const SizedBox(height: 20),
            const SectionHeader(title: 'Details'),
            _Rise(
              index: 2,
              child: AppCard(
                radius: Brand.radiusLg,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Column(
                  children: [
                    _FieldRow(
                      icon: Icons.person_outline_rounded,
                      label: 'Assignee',
                      value: (task.primaryAssigneeName ?? '').isEmpty
                          ? '—'
                          : task.primaryAssigneeName!,
                      leadingValue: (task.primaryAssigneeName ?? '').isEmpty
                          ? null
                          : AppAvatar(
                              name: task.primaryAssigneeName!,
                              size: 22,
                            ),
                    ),
                    _FieldRow(
                      icon: Icons.event_rounded,
                      label: 'Due date',
                      value: task.dueDate == null
                          ? 'Add date'
                          : _long(task.dueDate!),
                      onTap: _busy ? null : _pickDueDate,
                      actionable: true,
                      valueColor: task.dueDate == null
                          ? b.signal
                          : (task.isOverdue ? Brand.danger : b.paper),
                    ),
                    _FieldRow(
                      icon: Icons.play_circle_outline_rounded,
                      label: 'Start date',
                      value: task.startDate == null
                          ? '—'
                          : _long(task.startDate!),
                    ),
                    _FieldRow(
                      icon: Icons.flag_outlined,
                      label: 'Priority',
                      value: _priorityLabel(task.priority),
                      pillColor: _priorityColor(task.priority),
                    ),
                    _FieldRow(
                      icon: Icons.donut_large_rounded,
                      label: 'Status',
                      value: statusText,
                      pillColor: statusColor,
                      last: true,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const SectionHeader(title: 'Description'),
            _Rise(
              index: 3,
              child: AppCard(
                radius: Brand.radiusLg,
                child: Text(
                  task.description.trim().isEmpty
                      ? 'No description.'
                      : _stripTags(task.description),
                  style: text.bodyMedium?.copyWith(
                    color: task.description.trim().isEmpty
                        ? b.paperDim
                        : b.paper,
                    height: 1.55,
                  ),
                ),
              ),
            ),
            if (_subtasks.isNotEmpty) ...[
              const SizedBox(height: 20),
              SectionHeader(
                title: 'Subtasks',
                trailing: GlowBadge(
                  label: '$doneCount / ${_subtasks.length}',
                  color: doneCount == _subtasks.length
                      ? Brand.success
                      : b.signal,
                ),
              ),
              _Rise(
                index: 4,
                child: AppCard(
                  radius: Brand.radiusLg,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ProgressBar(
                        value: _subtasks.isEmpty
                            ? 0
                            : doneCount / _subtasks.length,
                        color: Brand.success,
                      ),
                      const SizedBox(height: 8),
                      for (var i = 0; i < _subtasks.length; i++) ...[
                        if (i > 0) const Hairline(),
                        _SubtaskRow(subtask: _subtasks[i]),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _long(DateTime d) {
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
        return Brand.info;
      case TaskBucket.doing:
        return Brand.warning;
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
    final others = <(TaskBucket, String, Color, IconData)>[];
    void add(TaskBucket b, String label, Color tone, IconData icon) {
      if (b != current) others.add((b, label, tone, icon));
    }

    if (current == TaskBucket.todo) {
      add(
        TaskBucket.doing,
        'Doing',
        Brand.warning,
        Icons.local_fire_department_rounded,
      );
      add(TaskBucket.done, 'Done', Brand.success, Icons.check_circle_rounded);
    } else if (current == TaskBucket.doing) {
      add(
        TaskBucket.todo,
        'To do',
        Brand.info,
        Icons.radio_button_unchecked_rounded,
      );
      add(
        TaskBucket.done,
        'Completed',
        Brand.success,
        Icons.check_circle_rounded,
      );
    } else {
      add(
        TaskBucket.todo,
        'To do',
        Brand.info,
        Icons.radio_button_unchecked_rounded,
      );
      add(
        TaskBucket.doing,
        'Doing',
        Brand.warning,
        Icons.local_fire_department_rounded,
      );
    }
    return Row(
      children: [
        for (var i = 0; i < others.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: _BucketButton(
              label: others[i].$2,
              tone: others[i].$3,
              icon: others[i].$4,
              busy: busy,
              onTap: () => onPick(others[i].$1),
            ),
          ),
        ],
      ],
    );
  }
}

class _BucketButton extends StatefulWidget {
  const _BucketButton({
    required this.label,
    required this.tone,
    required this.icon,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final Color tone;
  final IconData icon;
  final bool busy;
  final VoidCallback onTap;

  @override
  State<_BucketButton> createState() => _BucketButtonState();
}

class _BucketButtonState extends State<_BucketButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final busy = widget.busy;
    final tone = widget.tone;
    final icon = widget.icon;
    final label = widget.label;
    final c = busy ? b.paperDim : tone;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AnimatedScale(
      scale: _pressed && !busy ? 0.96 : 1,
      duration: reduce ? Duration.zero : const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      child: Material(
        color: busy ? b.surfaceHi : b.tint(tone, 0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Brand.radiusLg),
          side: BorderSide(color: busy ? b.rule : tone.withValues(alpha: 0.45)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: busy ? null : widget.onTap,
          onTapDown: busy ? null : (_) => setState(() => _pressed = true),
          onTapUp: busy ? null : (_) => setState(() => _pressed = false),
          onTapCancel: busy ? null : () => setState(() => _pressed = false),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: c),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
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
    final b = context.brand;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 13, color: b.paperDim),
          const SizedBox(width: 6),
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

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
    this.actionable = false,
    this.valueColor,
    this.pillColor,
    this.leadingValue,
    this.last = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final bool actionable;
  final Color? valueColor;
  final Color? pillColor;
  final Widget? leadingValue;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final Widget valueWidget = pillColor != null
        ? Align(
            alignment: Alignment.centerLeft,
            child: StatusPill(label: value, color: pillColor, dot: true),
          )
        : Row(
            children: [
              if (leadingValue != null) ...[
                leadingValue!,
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  value,
                  style: text.bodyMedium?.copyWith(
                    color: valueColor ?? b.paper,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          );
    final row = Row(
      children: [
        Icon(icon, size: 18, color: b.paperDim),
        const SizedBox(width: 10),
        SizedBox(width: 88, child: Text(label, style: text.bodySmall)),
        Expanded(child: valueWidget),
        if (actionable)
          Icon(Icons.chevron_right_rounded, size: 20, color: b.paperDim),
      ],
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: b.rule)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: row,
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
    final b = context.brand;
    final assignee = subtask.primaryAssigneeName ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: subtask.isDone ? Brand.success : Colors.transparent,
              border: Border.all(
                color: subtask.isDone ? Brand.success : b.paperDim,
                width: 1.5,
              ),
            ),
            child: subtask.isDone
                ? const Icon(Icons.check_rounded, size: 12, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              subtask.title,
              style: text.bodyMedium?.copyWith(
                color: subtask.isDone ? b.paperDim : b.paper,
                decoration: subtask.isDone
                    ? TextDecoration.lineThrough
                    : TextDecoration.none,
                decorationColor: b.paperDim,
              ),
            ),
          ),
          if (assignee.isNotEmpty) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: assignee,
              child: AppAvatar(name: assignee, size: 22),
            ),
          ],
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
