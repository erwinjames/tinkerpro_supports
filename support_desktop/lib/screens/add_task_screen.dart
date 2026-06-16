/// Compose a new task — Phase 2 add-task screen.
///
/// Mirrors the admin web's inline-add form: title (required), priority,
/// due date, assignee. Project picker lands in Phase 4 alongside the
/// projects screen. Description is omitted from the quick-add UI to
/// match the admin's "title first, fill the rest from the drawer" flow.
library;

import 'package:flutter/material.dart';

import '../models/task_models.dart';
import '../services/task_service.dart';
import '../theme.dart';

class AddTaskScreen extends StatefulWidget {
  const AddTaskScreen({
    super.key,
    required this.service,
    this.currentUserId,
  });

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
      // Asana-style: if the user picks a start after the existing due
      // date, push the due forward to match so the range stays valid.
      if (_dueDate != null && picked.isAfter(_dueDate!)) {
        _dueDate = picked;
      }
    });
  }

  Future<void> _pickDue() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? _startDate ?? DateTime.now(),
      firstDate: _startDate ?? DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _pickAssignee() async {
    if (_assignees.isEmpty) return;
    final selected = await showModalBottomSheet<Assignee>(
      context: context,
      backgroundColor: context.brand.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: _assignees.length,
            separatorBuilder: (_, _) => Divider(
                height: 1, color: context.brand.rule),
            itemBuilder: (_, i) {
              final u = _assignees[i];
              final isCurrent = u.userId == _selectedAssignee?.userId;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: context.brand.signal,
                  radius: 14,
                  child: Text(
                    u.initial,
                    style: TextStyle(
                      color: context.brand.canvas,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                title: Text(u.name,
                    style: TextStyle(color: context.brand.paper)),
                trailing: isCurrent
                    ? Icon(Icons.check, color: context.brand.signal)
                    : null,
                onTap: () => Navigator.pop(ctx, u),
              );
            },
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add task: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: context.brand.canvas,
      appBar: AppBar(
        backgroundColor: context.brand.canvas,
        foregroundColor: context.brand.paper,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _saving ? null : () => Navigator.pop(context),
        ),
        title: Text('NEW TASK',
            style: text.titleMedium?.copyWith(letterSpacing: 2.0)),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: context.brand.signal),
                  )
                : Text('SAVE',
                    style: TextStyle(
                      color: context.brand.signal,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    )),
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: context.brand.rule),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            // ── Title ────────────────────────────────────────────────
            Text('TITLE',
                style: text.labelSmall
                    ?.copyWith(color: context.brand.paperDim, letterSpacing: 2.0)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _titleCtrl,
              autofocus: true,
              maxLength: 255,
              style: TextStyle(color: context.brand.paper, fontSize: 16),
              cursorColor: context.brand.signal,
              decoration: InputDecoration(
                filled: true,
                fillColor: context.brand.surface,
                hintText: 'What needs to be done?',
                hintStyle: TextStyle(color: context.brand.paperDim),
                counterText: '',
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 14),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: context.brand.rule),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: context.brand.signal),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE05A2A)),
                ),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Title is required' : null,
            ),
            const SizedBox(height: 24),

            // ── Priority ─────────────────────────────────────────────
            Text('PRIORITY',
                style: text.labelSmall
                    ?.copyWith(color: context.brand.paperDim, letterSpacing: 2.0)),
            const SizedBox(height: 8),
            _PriorityRow(
              value: _priority,
              onChanged: (p) => setState(() => _priority = p),
            ),
            const SizedBox(height: 24),

            // ── Start date ───────────────────────────────────────────
            Text('START DATE',
                style: text.labelSmall
                    ?.copyWith(color: context.brand.paperDim, letterSpacing: 2.0)),
            const SizedBox(height: 8),
            _Tile(
              icon: Icons.play_arrow_outlined,
              label: _startDate == null
                  ? 'No start date'
                  : _formatDate(_startDate!),
              dim: _startDate == null,
              trailing: _startDate == null
                  ? null
                  : IconButton(
                      icon: Icon(Icons.close,
                          size: 18, color: context.brand.paperDim),
                      onPressed: () => setState(() => _startDate = null),
                    ),
              onTap: _pickStart,
            ),
            const SizedBox(height: 16),

            // ── Due date ─────────────────────────────────────────────
            Text('DUE DATE',
                style: text.labelSmall
                    ?.copyWith(color: context.brand.paperDim, letterSpacing: 2.0)),
            const SizedBox(height: 8),
            _Tile(
              icon: Icons.event,
              label: _dueDate == null
                  ? 'No due date'
                  : _formatDate(_dueDate!),
              dim: _dueDate == null,
              trailing: _dueDate == null
                  ? null
                  : IconButton(
                      icon: Icon(Icons.close,
                          size: 18, color: context.brand.paperDim),
                      onPressed: () => setState(() => _dueDate = null),
                    ),
              onTap: _pickDue,
            ),
            const SizedBox(height: 24),

            // ── Assignee ─────────────────────────────────────────────
            Text('ASSIGNEE',
                style: text.labelSmall
                    ?.copyWith(color: context.brand.paperDim, letterSpacing: 2.0)),
            const SizedBox(height: 8),
            if (_loadingUsers)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: context.brand.signal),
                ),
              )
            else if (_userLoadError != null)
              Text(_userLoadError!,
                  style: text.bodySmall?.copyWith(color: const Color(0xFFE05A2A)))
            else
              _Tile(
                icon: Icons.person_outline,
                label: _selectedAssignee?.name ?? 'Unassigned',
                onTap: _pickAssignee,
                leadingAvatar: _selectedAssignee?.initial,
              ),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
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
          return const Color(0xFFE05A2A);
        case TaskPriority.low:
          return const Color(0xFF7AA3E0);
        case TaskPriority.medium:
          return const Color(0xFFE0B14C);
      }
    }

    Widget chip(TaskPriority p, String label) {
      final active = p == value;
      final tone = colorFor(p);
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: InkWell(
            onTap: () => onChanged(p),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: active ? tone.withValues(alpha: 0.12) : context.brand.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: active ? tone : context.brand.rule,
                  width: active ? 1.5 : 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration:
                        BoxDecoration(color: tone, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: active ? tone : context.brand.paperDim,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      letterSpacing: 1.2,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // EdgeInsets can't be negative — flutter asserts on
    // `padding.isNonNegative`. The per-chip horizontal:4 padding inside
    // each Expanded already gives the row visual spacing, so the outer
    // wrapper just needs to be a plain Row.
    return Row(
      children: [
        chip(TaskPriority.low, 'LOW'),
        chip(TaskPriority.medium, 'MEDIUM'),
        chip(TaskPriority.high, 'HIGH'),
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
    return Material(
      color: context.brand.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: context.brand.rule),
          ),
          child: Row(
            children: [
              if (leadingAvatar != null)
                Container(
                  width: 22,
                  height: 22,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: context.brand.signal,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    leadingAvatar!,
                    style: TextStyle(
                      color: context.brand.canvas,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Icon(icon, size: 18, color: context.brand.paperDim),
                ),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: dim ? context.brand.paperDim : context.brand.paper,
                    fontSize: 15,
                  ),
                ),
              ),
              trailing ??
                  Icon(Icons.chevron_right,
                      size: 20, color: context.brand.paperDim),
            ],
          ),
        ),
      ),
    );
  }
}
