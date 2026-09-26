library;

import 'package:flutter/material.dart';

import '../models/task_models.dart';
import '../services/task_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';

class AddTaskScreen extends StatefulWidget {
  const AddTaskScreen({super.key, required this.service, this.currentUserId});

  final TaskService service;
  final int? currentUserId;

  @override
  State<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends State<AddTaskScreen> {
  final _titleCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  TaskPriority _priority = TaskPriority.medium;
  DateTime? _startDate;
  DateTime? _dueDate;
  List<Assignee> _assignees = const [];
  Assignee? _selectedAssignee;
  bool _loadingUsers = true;
  bool _saving = false;
  String? _userLoadError;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      final users = await widget.service.assignableUsers();
      setState(() {
        _assignees = users;
        _selectedAssignee = users.isEmpty
            ? null
            : users.firstWhere(
                (u) => u.userId == widget.currentUserId,
                orElse: () => users.first,
              );
        _loadingUsers = false;
      });
    } catch (e) {
      setState(() {
        _loadingUsers = false;
        _userLoadError = e.toString();
      });
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked == null) return;
    setState(() {
      _startDate = picked;
      if (_dueDate != null && picked.isAfter(_dueDate!)) {
        _dueDate = picked;
      }
    });
  }

  Future<void> _pickDue() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? _startDate ?? DateTime.now(),
      firstDate:
          _startDate ?? DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _pickAssignee() async {
    if (_assignees.isEmpty) return;
    final selected = await showModalBottomSheet<Assignee>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final text = Theme.of(ctx).textTheme;
        final b = ctx.brand;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.75,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text('Assign to', style: text.titleLarge),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                    itemCount: _assignees.length,
                    itemBuilder: (_, i) {
                      final u = _assignees[i];
                      final isCurrent = u.userId == _selectedAssignee?.userId;
                      return ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(Brand.radiusSm),
                        ),
                        selected: isCurrent,
                        selectedTileColor: b.tint(b.signal, 0.08),
                        leading: AppAvatar(name: u.name, size: 32),
                        title: Text(
                          u.name,
                          style: text.titleSmall?.copyWith(color: b.paper),
                        ),
                        trailing: isCurrent
                            ? Icon(Icons.check_circle_rounded, color: b.signal)
                            : null,
                        onTap: () => Navigator.pop(ctx, u),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected != null) setState(() => _selectedAssignee = selected);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await widget.service.addTask(
        title: _titleCtrl.text.trim(),
        priority: _priority,
        startDate: _startDate,
        dueDate: _dueDate,
        assigneeUserId: _selectedAssignee?.userId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to add task: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return StationScaffold(
      stationNumber: '',
      stationLabel: 'Tasks',
      title: 'New task',
      showBottomBrand: false,
      onBack: () {
        if (_saving) return;
        Navigator.pop(context);
      },
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            _Rise(
              index: 0,
              child: _FormSection(
                icon: Icons.edit_note_rounded,
                title: 'Details',
                children: [
                  const _FieldLabel('Title'),
                  TextFormField(
                    controller: _titleCtrl,
                    autofocus: true,
                    maxLength: 255,
                    textCapitalization: TextCapitalization.sentences,
                    style: text.bodyLarge?.copyWith(color: b.paper),
                    decoration: const InputDecoration(
                      hintText: 'What needs to be done?',
                      counterText: '',
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Title is required'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  const _FieldLabel('Priority'),
                  _PriorityRow(
                    value: _priority,
                    onChanged: (p) => setState(() => _priority = p),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _Rise(
              index: 1,
              child: _FormSection(
                icon: Icons.calendar_month_rounded,
                title: 'Schedule',
                children: [
                  const _FieldLabel('Start date'),
                  _Tile(
                    icon: Icons.play_circle_outline_rounded,
                    label: _startDate == null
                        ? 'No start date'
                        : _formatDate(_startDate!),
                    dim: _startDate == null,
                    trailing: _startDate == null
                        ? null
                        : IconButton(
                            tooltip: 'Clear start date',
                            icon: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: b.paperDim,
                            ),
                            onPressed: () => setState(() => _startDate = null),
                          ),
                    onTap: _pickStart,
                  ),
                  const SizedBox(height: 14),
                  const _FieldLabel('Due date'),
                  _Tile(
                    icon: Icons.event_rounded,
                    label: _dueDate == null
                        ? 'No due date'
                        : _formatDate(_dueDate!),
                    dim: _dueDate == null,
                    trailing: _dueDate == null
                        ? null
                        : IconButton(
                            tooltip: 'Clear due date',
                            icon: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: b.paperDim,
                            ),
                            onPressed: () => setState(() => _dueDate = null),
                          ),
                    onTap: _pickDue,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _Rise(
              index: 2,
              child: _FormSection(
                icon: Icons.person_outline_rounded,
                title: 'Assignee',
                children: [
                  if (_loadingUsers)
                    const Skeleton(height: 48, radius: Brand.radiusSm + 2)
                  else if (_userLoadError != null)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          size: 16,
                          color: Brand.danger,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _userLoadError!,
                            style: text.bodySmall?.copyWith(
                              color: Brand.danger,
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    _Tile(
                      icon: Icons.person_outline_rounded,
                      label: _selectedAssignee?.name ?? 'Unassigned',
                      onTap: _pickAssignee,
                      leadingAvatar: _selectedAssignee?.name,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _Rise(
              index: 3,
              child: SignalButton(
                label: 'Save task',
                icon: Icons.check_rounded,
                busy: _saving,
                onPressed: _saving ? null : _save,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime d) {
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

class _FormSection extends StatelessWidget {
  const _FormSection({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      radius: Brand.radiusLg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconTile(icon: icon, size: 36, iconSize: 19),
              const SizedBox(width: 10),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(color: context.brand.paper),
      ),
    );
  }
}

class _PriorityRow extends StatelessWidget {
  const _PriorityRow({required this.value, required this.onChanged});

  final TaskPriority value;
  final ValueChanged<TaskPriority> onChanged;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    Color colorFor(TaskPriority p) {
      switch (p) {
        case TaskPriority.high:
          return Brand.danger;
        case TaskPriority.low:
          return Brand.info;
        case TaskPriority.medium:
          return Brand.warning;
      }
    }

    Widget chip(TaskPriority p, String label) {
      final active = p == value;
      final tone = colorFor(p);
      return ChoiceChip(
        selected: active,
        onSelected: (_) => onChanged(p),
        showCheckmark: false,
        avatar: Icon(Icons.flag_rounded, size: 16, color: tone),
        label: Text(label),
        labelStyle: TextStyle(
          color: active ? tone : b.paper,
          fontWeight: active ? FontWeight.w600 : FontWeight.w500,
          fontSize: 13,
        ),
        selectedColor: b.tint(tone, 0.14),
        side: BorderSide(
          color: active ? tone.withValues(alpha: 0.6) : b.rule,
          width: active ? 1.4 : 1,
        ),
      );
    }

    Widget wrapped(TaskPriority p, String label) {
      final active = p == value;
      final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      return AnimatedScale(
        scale: active ? 1.04 : 1,
        duration: reduce ? Duration.zero : const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: chip(p, label),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        wrapped(TaskPriority.low, 'Low'),
        wrapped(TaskPriority.medium, 'Medium'),
        wrapped(TaskPriority.high, 'High'),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.dim = false,
    this.trailing,
    this.leadingAvatar,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool dim;
  final Widget? trailing;
  final String? leadingAvatar;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Material(
      color: b.surfaceHi,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Brand.radiusLg),
        side: BorderSide(
          color: dim ? b.rule : b.signal.withValues(alpha: 0.35),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              14,
              trailing == null ? 12 : 2,
              6,
              trailing == null ? 12 : 2,
            ),
            child: Row(
              children: [
                if (leadingAvatar != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: AppAvatar(name: leadingAvatar!, size: 26),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Icon(
                      icon,
                      size: 18,
                      color: dim ? b.paperDim : b.signal,
                    ),
                  ),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: dim ? b.paperDim : b.paper,
                    ),
                  ),
                ),
                trailing ??
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: b.paperDim,
                    ),
              ],
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
