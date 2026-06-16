/// API layer for the task feature.
///
/// Talks to two PHP entry points on the admin backend:
///   * `task.php`         — POST handlers for every task / subtask mutation
///                           (toggle, update_due, add_subtask, etc). The same
///                           file also renders the page HTML, so the AJAX
///                           handlers short-circuit before any layout output.
///   * `projects.php`     — POST handlers for project CRUD + the project list
///                           SELECT used by the projects board.
///   * `api.php`          — `getNotifications` / `markNotificationRead` for
///                           the bell (already used by the existing app).
///
/// The list/detail data themselves come from the rendered task.php HTML
/// today; for the mobile port we'll add a `getTasks` API action in a
/// later phase. For Phase 1, [listTasks] uses a temporary scraping
/// fallback via `task-poll.php`'s shape so we have *something* to show.
library;

import 'dart:convert';

import '../api_client.dart';
import '../models/task_models.dart';

class TaskService {
  TaskService(this._api);

  final ApiClient _api;

  /// Authenticated user id captured at login time. Forwarded straight
  /// from the api client so screens that want to default an assignee
  /// picker to the current user don't have to plumb ApiClient through.
  int? get currentUserId => _api.userId;

  // ── Tasks ────────────────────────────────────────────────────────────

  /// Fetch the current user's visible tasks (top-level + subtasks they're
  /// assigned to). Backed by a new `getTasks` action on the server — added
  /// alongside this Flutter screen so the mobile client doesn't have to
  /// parse rendered HTML. Returns parent tasks; subtasks are fetched
  /// per-task on demand via [listSubtasks].
  Future<List<TaskItem>> listTasks({int? projectId}) async {
    final query = <String, String>{};
    if (projectId != null && projectId > 0) {
      query['project_id'] = projectId.toString();
    }
    final res = await _api.get('getTasks', query.isEmpty ? null : query);
    if (res['success'] != true) {
      throw Exception(res['message']?.toString() ?? 'Failed to load tasks');
    }
    final rows = (res['tasks'] as List?) ?? const [];
    return rows
        .whereType<Map>()
        .map((m) => TaskItem.fromJson(m.cast<String, dynamic>()))
        .toList(growable: false);
  }

  /// Fetch subtasks for a parent task. Returns full assignee list so the
  /// drawer can render multi-assignee stacks without an extra round-trip.
  Future<List<Subtask>> listSubtasks(int parentTaskId) async {
    final res = await _api.get('getSubtasks', {
      'parent_task_id': parentTaskId.toString(),
    });
    if (res['success'] != true) {
      throw Exception(res['message']?.toString() ?? 'Failed to load subtasks');
    }
    final rows = (res['subtasks'] as List?) ?? const [];
    return rows
        .whereType<Map>()
        .map((m) => Subtask.fromJson(m.cast<String, dynamic>()))
        .toList(growable: false);
  }

  /// Move a top-level task between the three derived buckets the admin
  /// uses (`todo` / `doing` / `done`). Server-side bundles the status +
  /// due-date side-effects in one round-trip:
  ///   * todo  → status=pending, due_date cleared
  ///   * doing → status=pending, due_date=yesterday (forces "overdue")
  ///   * done  → status=completed (due_date untouched)
  Future<void> moveToSection(int taskId, String section) async {
    if (!const {'todo', 'doing', 'done'}.contains(section)) {
      throw ArgumentError.value(section, 'section');
    }
    final res = await _api.postPath('task.php', body: {
      'move_to_section': '1',
      'task_id': taskId.toString(),
      'section': section,
    });
    if (res['success'] == false) {
      throw Exception(res['message']?.toString() ?? 'Move failed');
    }
  }

  /// Flip the task's `status` between pending and completed. Used by both
  /// the round checkbox on the row and the "Mark complete" CTA in the
  /// drawer. Returns the new status as confirmed by the server.
  Future<TaskStatus> toggleStatus(int taskId, TaskStatus next) async {
    final res = await _api.postPath('task.php', body: {
      'toggle_status': '1',
      'task_id': taskId.toString(),
      'new_status': next.wire,
    });
    // task.php's toggle handler responds with a redirect HTML snippet on
    // success (it's also rendered for browsers). Treat any 2xx as ok.
    if (res['success'] == false) {
      throw Exception(res['message']?.toString() ?? 'Toggle failed');
    }
    return next;
  }

  /// Update a task's due / start date pair. Server-side this is creator-
  /// only on top-level tasks, but assignees on subtasks can still hit it
  /// via the same endpoint (no extra wiring needed here).
  Future<void> updateDue({
    required int taskId,
    DateTime? dueDate,
    DateTime? startDate,
    bool clearStart = false,
  }) async {
    final body = <String, String>{
      'update_due': '1',
      'task_id': taskId.toString(),
      'due_date': dueDate == null ? '' : _fmtDate(dueDate),
    };
    // The server's update_due treats start_date as a separate, optional
    // field — only include it when we explicitly want to set/clear it.
    if (startDate != null) body['start_date'] = _fmtDate(startDate);
    if (clearStart) body['start_date'] = '';
    final res = await _api.postPath('task.php', body: body);
    if (res['success'] == false) {
      throw Exception(res['message']?.toString() ?? 'Date update failed');
    }
  }

  /// Update a task's free-text description. Creator-only on the server.
  Future<void> updateDescription(int taskId, String description) async {
    final res = await _api.postPath('task.php', body: {
      'update_description': '1',
      'task_id': taskId.toString(),
      'description': description,
    });
    if (res['success'] == false) {
      throw Exception(
          res['message']?.toString() ?? 'Description update failed');
    }
  }

  /// Update a task's priority (low / medium / high).
  Future<void> updatePriority(int taskId, TaskPriority priority) async {
    final res = await _api.postPath('task.php', body: {
      'update_priority': '1',
      'task_id': taskId.toString(),
      'priority': priority.wire,
    });
    if (res['success'] == false) {
      throw Exception(res['message']?.toString() ?? 'Priority update failed');
    }
  }

  /// Create a new top-level task. Mirrors the admin web's inline-add
  /// form on task.php — the server stamps `assigned_by` from the
  /// current session, defaults priority to "medium" when not provided,
  /// and inserts the assignee into `task_assignees` so multi-assignee
  /// queries pick it up.
  Future<void> addTask({
    required String title,
    String description = '',
    TaskPriority priority = TaskPriority.medium,
    DateTime? startDate,
    DateTime? dueDate,
    int? assigneeUserId,
    int? projectId,
  }) async {
    final body = <String, String>{
      'add_task': '1',
      'title': title,
      'description': description,
      'priority': priority.wire,
    };
    if (startDate != null) body['start_date'] = _fmtDate(startDate);
    if (dueDate != null) body['due_date'] = _fmtDate(dueDate);
    if (assigneeUserId != null && assigneeUserId > 0) {
      body['user_id'] = assigneeUserId.toString();
    }
    if (projectId != null && projectId > 0) {
      body['project_id'] = projectId.toString();
    }
    final res = await _api.postPath('task.php', body: body);
    if (res['success'] == false) {
      throw Exception(res['message']?.toString() ?? 'Add task failed');
    }
  }

  // ── Multi-assignee ───────────────────────────────────────────────────

  /// Add a user to the task's assignee list. Server returns the updated
  /// list so the chip stack can repaint without a separate fetch.
  Future<List<Assignee>> addAssignee(int taskId, int userId) async {
    final res = await _api.postPath('task.php', body: {
      'add_assignee': '1',
      'task_id': taskId.toString(),
      'user_id': userId.toString(),
    });
    if (res['success'] != true) {
      throw Exception(res['message']?.toString() ?? 'Add assignee failed');
    }
    return ((res['assignees'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => Assignee.fromJson(m.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<List<Assignee>> removeAssignee(int taskId, int userId) async {
    final res = await _api.postPath('task.php', body: {
      'remove_assignee': '1',
      'task_id': taskId.toString(),
      'user_id': userId.toString(),
    });
    if (res['success'] != true) {
      throw Exception(res['message']?.toString() ?? 'Remove assignee failed');
    }
    return ((res['assignees'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => Assignee.fromJson(m.cast<String, dynamic>()))
        .toList(growable: false);
  }

  /// List the users a task can be assigned to (admin staff). Cached at
  /// the app level by callers; the server returns a flat array each call.
  Future<List<Assignee>> assignableUsers() async {
    final res = await _api.get('getAssignableUsers');
    if (res['success'] != true) {
      throw Exception(res['message']?.toString() ?? 'Failed to load users');
    }
    return ((res['users'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => Assignee.fromJson(m.cast<String, dynamic>()))
        .toList(growable: false);
  }

  // ── Subtasks ─────────────────────────────────────────────────────────

  Future<Subtask> addSubtask({
    required int parentTaskId,
    required String title,
    DateTime? startDate,
    DateTime? dueDate,
    int? assigneeUserId,
  }) async {
    final body = <String, String>{
      'add_subtask': '1',
      'parent_task_id': parentTaskId.toString(),
      'title': title,
    };
    if (startDate != null) body['start_date'] = _fmtDate(startDate);
    if (dueDate != null) body['due_date'] = _fmtDate(dueDate);
    if (assigneeUserId != null && assigneeUserId > 0) {
      body['user_id'] = assigneeUserId.toString();
    }
    final res = await _api.postPath('task.php', body: body);
    if (res['success'] != true) {
      throw Exception(res['message']?.toString() ?? 'Add subtask failed');
    }
    final s = (res['subtask'] as Map?)?.cast<String, dynamic>();
    if (s == null) {
      throw Exception('Add subtask returned no payload');
    }
    return Subtask.fromJson({
      ...s,
      'parent_task_id': parentTaskId,
      // Carry the multi-assignee list through if the server included it.
      'assignees': s['assignees'] ?? const [],
    });
  }

  Future<void> toggleSubtask(int subtaskId, TaskStatus next) async {
    final res = await _api.postPath('task.php', body: {
      'toggle_subtask': '1',
      'subtask_id': subtaskId.toString(),
      'new_status': next.wire,
    });
    if (res['success'] != true) {
      throw Exception(res['message']?.toString() ?? 'Toggle subtask failed');
    }
  }

  Future<void> deleteSubtask(int subtaskId) async {
    final res = await _api.postPath('task.php', body: {
      'delete_subtask': '1',
      'subtask_id': subtaskId.toString(),
    });
    if (res['success'] != true) {
      throw Exception(res['message']?.toString() ?? 'Delete subtask failed');
    }
  }

  // ── Projects ─────────────────────────────────────────────────────────

  Future<List<Project>> listProjects() async {
    final res = await _api.get('getProjects');
    if (res['success'] != true) {
      throw Exception(res['message']?.toString() ?? 'Failed to load projects');
    }
    return ((res['projects'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => Project.fromJson(m.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<void> toggleProjectStar(int projectId, bool starred) async {
    final res = await _api.postPath('projects.php', body: {
      'toggle_project_star': '1',
      'project_id': projectId.toString(),
      'starred': starred ? '1' : '0',
    });
    if (res['success'] == false) {
      throw Exception(res['message']?.toString() ?? 'Toggle star failed');
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  static String _fmtDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  /// Convenience helper for the future Phase 5 wiring: decode a Pusher
  /// `task.subtask_updated` event payload. Kept here so the realtime
  /// channel layer doesn't have to know the field names.
  static ({int subtaskId, int parentTaskId, TaskStatus status})?
      decodeSubtaskUpdate(Object? raw) {
    if (raw is! Map) return null;
    final j = raw.cast<String, dynamic>();
    final id = (j['subtask_id'] as num?)?.toInt();
    if (id == null || id <= 0) return null;
    return (
      subtaskId: id,
      parentTaskId: (j['parent_task_id'] as num?)?.toInt() ?? 0,
      status: TaskStatusX.parse(j['status']?.toString()),
    );
  }

  // Surfaced so callers can shove arbitrary JSON through if the typed
  // helpers above don't cover a niche endpoint yet.
  // ignore: unused_element
  static String _encodeJson(Map<String, dynamic> m) => jsonEncode(m);
}
