import 'package:flutter/material.dart';

import '../models/task_models.dart';
import '../services/task_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import '../widgets/tp_loader.dart';

class AddTaskScreen extends StatefulWidget {
  const AddTaskScreen({
    super.key,
    required this.service,
    this.currentUserId,
    this.projectId,
    this.boardSection = 'todo',
  });

  final TaskService service;
  final int? currentUserId;
  final int? projectId;
  final String boardSection;

  static Future<bool?> show(
    BuildContext context, {
    required TaskService service,
    int? currentUserId,
    int? projectId,
    String boardSection = 'todo',
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AddTaskScreen(
        service: service,
        currentUserId: currentUserId,
        projectId: projectId,
        boardSection: boardSection,
      ),
    );
  }

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
      if (!mounted) return;
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
      if (!mounted) return;
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

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await widget.service.addTask(
        title: _titleCtrl.text,
        priority: _priority,
        startDate: _startDate,
        dueDate: _dueDate,
        assigneeUserId: _selectedAssignee?.userId,
        projectId: widget.projectId,
        boardSection: widget.boardSection,
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
    return WebModal(
      title: 'Add task',
      subtitle: 'Title first — fill in the rest from the task details',
      icon: Icons.add_task,
      width: 640,
      onClose: _saving ? () {} : () => Navigator.of(context).pop(),
      actions: [
        GhostButton(
          label: 'Cancel',
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
        SignalButton(
          label: 'Save task',
          icon: Icons.check,
          busy: _saving,
          onPressed: _save,
        ),
      ],
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _titleCtrl,
              autofocus: true,
              maxLength: 255,
              decoration: const InputDecoration(
                labelText: 'Task name *',
                hintText: 'Write a task name',
                counterText: '',
              ),
              onFieldSubmitted: (_) => _save(),
              validator: (v) => (v == null || v.isEmpty)
                  ? 'Please fill out this field.'
                  : null,
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _DateField(
                    label: 'Start date',
                    icon: Icons.play_arrow_outlined,
                    value: _startDate,
                    placeholder: 'No start date',
                    onTap: _pickStart,
                    onClear: () => setState(() => _startDate = null),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _DateField(
                    label: 'Due date',
                    icon: Icons.event,
                    value: _dueDate,
                    placeholder: 'No due date',
                    onTap: _pickDue,
                    onClear: () => setState(() => _dueDate = null),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Priority',
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                    ),
                    child: _PriorityRow(
                      value: _priority,
                      onChanged: (p) => setState(() => _priority = p),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(child: _assigneeField(text)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _assigneeField(TextTheme text) {
    if (_loadingUsers) {
      return const InputDecorator(
        decoration: InputDecoration(labelText: 'Assignee'),
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 16,
            height: 16,
            child: TpLoader(
              strokeWidth: 2,
              color: Brand.signal,
            ),
          ),
        ),
      );
    }
    if (_userLoadError != null) {
      return InputDecorator(
        decoration: const InputDecoration(labelText: 'Assignee'),
        child: Text(
          _userLoadError!,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: text.bodySmall?.copyWith(color: Brand.danger),
        ),
      );
    }
    return DropdownButtonFormField<int>(
      initialValue: _selectedAssignee?.userId,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Assignee'),
      hint: const Text('Unassigned'),
      items: [
        for (final u in _assignees)
          DropdownMenuItem(
            value: u.userId,
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Brand.signal,
                  radius: 11,
                  child: Text(
                    u.initial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    u.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
      onChanged: (id) {
        if (id == null) return;
        setState(() {
          _selectedAssignee = _assignees.firstWhere((u) => u.userId == id);
        });
      },
    );
  }
}

String _formatDate(DateTime d) {
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

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.icon,
    required this.value,
    required this.placeholder,
    required this.onTap,
    required this.onClear,
  });

  final String label;
  final IconData icon;
  final DateTime? value;
  final String placeholder;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      mouseCursor: SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(6),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 18),
          prefixIconConstraints: const BoxConstraints(minWidth: 38),
          suffixIcon: value == null
              ? const Icon(Icons.calendar_today_outlined, size: 16)
              : IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: onClear,
                ),
        ),
        child: Text(
          value == null ? placeholder : _formatDate(value!),
          style: text.bodyMedium?.copyWith(
            color: value == null ? context.brand.paperDim : null,
          ),
        ),
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
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: InkWell(
            onTap: () => onChanged(p),
            mouseCursor: SystemMouseCursors.click,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              height: 30,
              decoration: BoxDecoration(
                color: active ? tone.withValues(alpha: 0.12) : null,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: active ? tone : context.brand.rule),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: tone,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: active ? tone : context.brand.paperDim,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip(TaskPriority.low, 'Low'),
        chip(TaskPriority.medium, 'Medium'),
        chip(TaskPriority.high, 'High'),
      ],
    );
  }
}
