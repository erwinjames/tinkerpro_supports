/// Domain models for the task feature. Mirror the shapes returned by the
/// PHP backend's task-facade.php + projects-facade.php so the JSON
/// adapters stay thin.
library;

import 'package:flutter/foundation.dart';

enum TaskStatus { pending, completed }

enum TaskPriority { low, medium, high }

/// Derived bucket — not a column on the DB. Computed from
/// `status` + `due_date` to mirror the PHP renderer's sectioning.
enum TaskBucket { todo, doing, done }

/// Project accent colors. Matches the `color` enum used in the
/// PHP projects table.
enum ProjectColor { slate, emerald, amber, rose, blue, violet }

extension TaskStatusX on TaskStatus {
  String get wire => this == TaskStatus.completed ? 'completed' : 'pending';
  static TaskStatus parse(String? raw) =>
      raw == 'completed' ? TaskStatus.completed : TaskStatus.pending;
}

extension TaskPriorityX on TaskPriority {
  String get wire {
    switch (this) {
      case TaskPriority.high:
        return 'high';
      case TaskPriority.low:
        return 'low';
      case TaskPriority.medium:
        return 'medium';
    }
  }

  static TaskPriority parse(String? raw) {
    switch (raw) {
      case 'high':
        return TaskPriority.high;
      case 'low':
        return TaskPriority.low;
      default:
        return TaskPriority.medium;
    }
  }
}

extension ProjectColorX on ProjectColor {
  String get wire => name;
  static ProjectColor parse(String? raw) {
    for (final c in ProjectColor.values) {
      if (c.name == raw) return c;
    }
    return ProjectColor.slate;
  }
}

/// A user attached to a task either as creator (`assigned_by`) or as
/// one of the assignees (`task_assignees` row).
@immutable
class Assignee {
  final int userId;
  final String name;
  final String initial;

  const Assignee({
    required this.userId,
    required this.name,
    required this.initial,
  });

  factory Assignee.fromJson(Map<String, dynamic> j) {
    final name = (j['name'] ?? '').toString();
    final initial = (j['initial'] ?? '').toString().isNotEmpty
        ? j['initial'].toString()
        : (name.isNotEmpty ? name[0].toUpperCase() : 'U');
    return Assignee(
      userId: (j['user_id'] as num?)?.toInt() ?? 0,
      name: name,
      initial: initial,
    );
  }
}

/// One top-level task. Subtasks live in their own list keyed by parent_id
/// because the server returns them in a separate map.
@immutable
class TaskItem {
  final int id;
  final int parentTaskId;
  final String title;
  final String description;
  final TaskStatus status;
  final TaskPriority priority;
  final DateTime? startDate;
  final DateTime? dueDate;
  final int projectId;
  final String? projectName;
  final String? parentTitle;
  final int assignedBy;
  final int primaryUserId;
  final String? primaryAssigneeName;
  final List<Assignee> assignees;
  final String statusLabel;

  const TaskItem({
    required this.id,
    required this.parentTaskId,
    required this.title,
    required this.description,
    required this.status,
    required this.priority,
    required this.startDate,
    required this.dueDate,
    required this.projectId,
    required this.projectName,
    required this.parentTitle,
    required this.assignedBy,
    required this.primaryUserId,
    required this.primaryAssigneeName,
    required this.assignees,
    required this.statusLabel,
  });

  bool get isSubtask => parentTaskId > 0;
  bool get isDone => status == TaskStatus.completed;

  /// True when the due date has passed and the task isn't completed yet —
  /// drives the "Doing" bucket in the PHP renderer.
  bool get isOverdue {
    final due = dueDate;
    if (due == null || isDone) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(due.year, due.month, due.day);
    return dueDay.isBefore(today);
  }

  TaskBucket get bucket {
    if (isDone) return TaskBucket.done;
    if (isOverdue) return TaskBucket.doing;
    return TaskBucket.todo;
  }

  factory TaskItem.fromJson(Map<String, dynamic> j) {
    DateTime? parse(dynamic v) {
      final s = (v ?? '').toString();
      if (s.isEmpty || s == '0000-00-00') return null;
      return DateTime.tryParse(s);
    }

    return TaskItem(
      id: (j['id'] as num?)?.toInt() ?? 0,
      parentTaskId: (j['parent_task_id'] as num?)?.toInt() ?? 0,
      title: (j['title'] ?? '').toString(),
      description: (j['description'] ?? '').toString(),
      status: TaskStatusX.parse(j['status']?.toString()),
      priority: TaskPriorityX.parse(j['priority']?.toString()),
      startDate: parse(j['start_date']),
      dueDate: parse(j['due_date']),
      projectId: (j['project_id'] as num?)?.toInt() ?? 0,
      projectName: j['project_name']?.toString(),
      parentTitle: j['parent_title']?.toString(),
      assignedBy: (j['assigned_by'] as num?)?.toInt() ?? 0,
      primaryUserId: (j['user_id'] as num?)?.toInt() ?? 0,
      primaryAssigneeName:
          j['full_name']?.toString() ?? j['username']?.toString(),
      assignees: const [],
      statusLabel: (j['status_label'] ?? '').toString(),
    );
  }

  TaskItem copyWith({
    TaskStatus? status,
    TaskPriority? priority,
    DateTime? startDate,
    DateTime? dueDate,
    String? description,
    List<Assignee>? assignees,
    String? title,
  }) {
    return TaskItem(
      id: id,
      parentTaskId: parentTaskId,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      startDate: startDate ?? this.startDate,
      dueDate: dueDate ?? this.dueDate,
      projectId: projectId,
      projectName: projectName,
      parentTitle: parentTitle,
      assignedBy: assignedBy,
      primaryUserId: primaryUserId,
      primaryAssigneeName: primaryAssigneeName,
      assignees: assignees ?? this.assignees,
      statusLabel: statusLabel,
    );
  }
}

/// A subtask returned from the same `tasks` table (parent_task_id > 0).
/// Slim shape because the parent drawer is the only place this renders.
@immutable
class Subtask {
  final int id;
  final int parentTaskId;
  final String title;
  final TaskStatus status;
  final DateTime? startDate;
  final DateTime? dueDate;
  final int assignedBy;
  final int primaryUserId;
  final String? primaryAssigneeName;
  final List<Assignee> assignees;

  const Subtask({
    required this.id,
    required this.parentTaskId,
    required this.title,
    required this.status,
    required this.startDate,
    required this.dueDate,
    required this.assignedBy,
    required this.primaryUserId,
    required this.primaryAssigneeName,
    required this.assignees,
  });

  bool get isDone => status == TaskStatus.completed;

  factory Subtask.fromJson(Map<String, dynamic> j) {
    DateTime? parse(dynamic v) {
      final s = (v ?? '').toString();
      if (s.isEmpty || s == '0000-00-00') return null;
      return DateTime.tryParse(s);
    }

    final List rawAss = (j['assignees'] is List) ? j['assignees'] as List : const [];
    return Subtask(
      id: (j['id'] as num?)?.toInt() ?? 0,
      parentTaskId: (j['parent_task_id'] as num?)?.toInt() ?? 0,
      title: (j['title'] ?? '').toString(),
      status: TaskStatusX.parse(j['status']?.toString()),
      startDate: parse(j['start_date']),
      dueDate: parse(j['due_date']),
      assignedBy: (j['assigned_by'] as num?)?.toInt() ?? 0,
      primaryUserId: (j['user_id'] as num?)?.toInt() ?? 0,
      primaryAssigneeName: j['assignee_name']?.toString(),
      assignees: rawAss
          .whereType<Map<String, dynamic>>()
          .map(Assignee.fromJson)
          .toList(growable: false),
    );
  }
}

@immutable
class Project {
  final int id;
  final String name;
  final String category;
  final ProjectColor color;
  final bool starred;
  final bool archived;
  final int taskCount;
  final int ownerId;
  final String ownerName;
  final DateTime? updatedAt;

  const Project({
    required this.id,
    required this.name,
    required this.category,
    required this.color,
    required this.starred,
    required this.archived,
    required this.taskCount,
    required this.ownerId,
    required this.ownerName,
    required this.updatedAt,
  });

  factory Project.fromJson(Map<String, dynamic> j) {
    return Project(
      id: (j['id'] as num?)?.toInt() ?? 0,
      name: (j['name'] ?? '').toString(),
      category: (j['category'] ?? 'Uncategorized').toString(),
      color: ProjectColorX.parse(j['color']?.toString()),
      starred: (j['starred'] as num?)?.toInt() == 1,
      archived: (j['archived'] as num?)?.toInt() == 1,
      taskCount: (j['task_count'] as num?)?.toInt() ?? 0,
      ownerId: (j['owner_id'] as num?)?.toInt() ?? 0,
      ownerName: (j['owner_name'] ?? 'Unassigned').toString(),
      updatedAt: DateTime.tryParse((j['updated_at'] ?? '').toString()),
    );
  }
}

/// Notification rows surfaced by api.php?action=getNotifications.
@immutable
class TaskNotification {
  final int id;
  final String type; // 'task_assigned' | 'subtask_assigned' | ...
  final String title;
  final String body;
  final int refId;
  final Map<String, dynamic> meta;
  final bool isRead;
  final DateTime? createdAt;

  const TaskNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.refId,
    required this.meta,
    required this.isRead,
    required this.createdAt,
  });

  factory TaskNotification.fromJson(Map<String, dynamic> j) {
    final rawMeta = j['meta'];
    Map<String, dynamic> meta = const {};
    if (rawMeta is Map<String, dynamic>) {
      meta = rawMeta;
    } else if (rawMeta is String && rawMeta.isNotEmpty) {
      try {
        // Server already decodes meta to a map for getRecent, but accept
        // the raw JSON string fallback just in case.
        meta = Map<String, dynamic>.from({}..addAll({'_raw': rawMeta}));
      } catch (_) {}
    }
    return TaskNotification(
      id: (j['id'] as num?)?.toInt() ?? 0,
      type: (j['type'] ?? '').toString(),
      title: (j['title'] ?? '').toString(),
      body: (j['body'] ?? '').toString(),
      refId: (j['ref_id'] as num?)?.toInt() ?? 0,
      meta: meta,
      isRead: (j['is_read'] as num?)?.toInt() == 1,
      createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()),
    );
  }
}
