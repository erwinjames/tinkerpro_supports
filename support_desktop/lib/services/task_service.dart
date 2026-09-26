import 'package:http/http.dart' as http;

import '../api_client.dart';
import '../models/task_models.dart';

class TaskResult {
  const TaskResult(this.ok, this.message, [this.data = const {}]);
  final bool ok;
  final String message;
  final Map<String, dynamic> data;
}

class TaskService {
  TaskService(this._api);

  final ApiClient _api;

  int? get currentUserId => _api.userId;

  String url(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '${_api.baseUrl}/${path.replaceAll(RegExp(r'^/+'), '')}';
  }

  Map<String, String> get authHeaders => _api.authHeaders();

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

  Future<Map<String, dynamic>> taskDetail(int taskId) async {
    final res = await _api.get('desktopTaskDetail', {'task_id': '$taskId'});
    if (res['success'] != true) {
      throw Exception(res['message']?.toString() ?? 'Failed to load task');
    }
    return res;
  }

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

  Future<TaskStatus> toggleStatus(int taskId, TaskStatus next) async {
    final res = await _api.postPath('task.php', body: {
      'task_id': taskId.toString(),
      'new_status': next.wire,
      'toggle_status': '1',
    });
    if (res['success'] == false) {
      throw Exception(res['message']?.toString() ?? 'Toggle failed');
    }
    return next;
  }

  Future<TaskResult> drawerToggleStatus(
    int taskId,
    TaskStatus next, {
    String? screenshotPath,
  }) async {
    final fields = {
      'task_id': taskId.toString(),
      'new_status': next.wire,
      'toggle_status': '1',
    };
    final withFile = next == TaskStatus.completed &&
        screenshotPath != null &&
        screenshotPath.isNotEmpty;
    try {
      final res = withFile
          ? await _api.postPathMultipart('task.php',
              fields: fields, files: {'completion_screenshot': screenshotPath})
          : await _api.postPath('task.php', body: fields);
      if (res['success'] == true) return TaskResult(true, '', res);
      return TaskResult(
          false, (res['message'] ?? 'Failed to update task').toString(), res);
    } catch (_) {
      return const TaskResult(false, 'Network error occurred');
    }
  }

  Future<TaskResult> drawerDeleteTask(int taskId) async {
    try {
      final res = await _api.postPathMultipart(
        'task-user-ajax.php',
        fields: {'task_id': taskId.toString(), 'action': 'delete_task'},
      );
      if (res['success'] == true) {
        return TaskResult(true, (res['message'] ?? '').toString(), res);
      }
      return TaskResult(
          false, (res['message'] ?? 'Failed to delete task').toString(), res);
    } catch (_) {
      return const TaskResult(false, 'Network error occurred');
    }
  }

  Future<void> updateDue({
    required int taskId,
    DateTime? dueDate,
    DateTime? startDate,
  }) async {
    final res = await _api.postPath('task.php', body: {
      'update_due': '1',
      'task_id': taskId.toString(),
      'due_date': dueDate == null ? '' : _fmtDate(dueDate),
      'start_date': startDate == null ? '' : _fmtDate(startDate),
    });
    if (res['success'] == false) {
      throw Exception(res['message']?.toString() ?? 'Date update failed');
    }
  }

  Future<TaskResult> updateDescriptionText(int taskId, String text) async {
    try {
      final conv = await _api.post('desktopRichTextHtml', body: {'text': text});
      if (conv['success'] != true) {
        return TaskResult(false,
            (conv['message'] ?? 'Could not save the description').toString());
      }
      final html = (conv['html'] ?? '').toString();
      final res = await _api.postPath('task.php', body: {
        'update_description': '1',
        'task_id': taskId.toString(),
        'description': html,
      });
      if (res['success'] == true) return TaskResult(true, '', res);
      return TaskResult(false,
          (res['message'] ?? 'Could not save the description').toString(), res);
    } catch (_) {
      return const TaskResult(false, 'Could not save the description');
    }
  }

  Future<void> addTask({
    required String title,
    TaskPriority priority = TaskPriority.medium,
    DateTime? startDate,
    DateTime? dueDate,
    int? assigneeUserId,
    int? projectId,
    String boardSection = 'todo',
  }) async {
    final body = <String, String>{
      'add_task': '1',
      'description': '',
      'project_id': (projectId ?? 0).toString(),
      'board_section': boardSection,
      'title': title,
      'start_date': startDate == null ? '' : _fmtDate(startDate),
      'due_date': dueDate == null ? '' : _fmtDate(dueDate),
      'priority': priority.wire,
      if (assigneeUserId != null && assigneeUserId > 0)
        'user_id': assigneeUserId.toString(),
    };
    final res = await _api.postPath('task.php', body: body);
    if (res['success'] == false) {
      throw Exception(res['message']?.toString() ?? 'Add task failed');
    }
  }

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

  Future<TaskResult> addSubtask({
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
      if (startDate != null) 'start_date': _fmtDate(startDate),
      if (dueDate != null) 'due_date': _fmtDate(dueDate),
      if (assigneeUserId != null && assigneeUserId > 0)
        'user_id': assigneeUserId.toString(),
    };
    try {
      final res = await _api.postPath('task.php', body: body);
      if (res['success'] == true && res['subtask'] != null) {
        return TaskResult(true, '', res);
      }
      return TaskResult(
          false, (res['message'] ?? 'Could not add the subtask').toString(), res);
    } catch (_) {
      return const TaskResult(false, 'Could not add the subtask');
    }
  }

  Future<bool> toggleSubtask(int subtaskId, TaskStatus next) async {
    try {
      final res = await _api.postPath('task.php', body: {
        'toggle_subtask': '1',
        'subtask_id': subtaskId.toString(),
        'new_status': next.wire,
      });
      return res['success'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> deleteSubtask(int subtaskId) async {
    try {
      await _api.postPath('task.php', body: {
        'delete_subtask': '1',
        'subtask_id': subtaskId.toString(),
      });
    } catch (_) {}
  }

  Future<TaskResult> addComment(int taskId, String body) async {
    try {
      final res = await _api.postPath('task.php', body: {
        'add_comment': '1',
        'task_id': taskId.toString(),
        'body': body,
      });
      if (res['success'] == true) return TaskResult(true, '', res);
      return TaskResult(false, (res['message'] ?? '').toString(), res);
    } catch (_) {
      return const TaskResult(false, '');
    }
  }

  Future<bool> deleteComment(int commentId) async {
    try {
      final res = await _api.postPath('task.php', body: {
        'delete_comment': '1',
        'comment_id': commentId.toString(),
      });
      return res['success'] == true;
    } catch (_) {
      return false;
    }
  }

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
    try {
      await _api.postPath('projects.php', body: {
        'toggle_project_star': '1',
        'project_id': projectId.toString(),
        'starred': starred ? '1' : '0',
      });
    } catch (_) {}
  }

  Future<TaskResult> createProject({
    required String name,
    required String category,
    required String color,
  }) async {
    try {
      final req = http.Request('POST', Uri.parse(url('projects.php')))
        ..followRedirects = false
        ..headers.addAll(authHeaders)
        ..bodyFields = {
          'create_project': '1',
          'name': name,
          'category': category,
          'color': color,
        };
      final res = await http.Response.fromStream(await req.send());
      if (res.statusCode == 403) {
        return const TaskResult(false, 'Projects are read-only for super admin.');
      }
      final loc = res.headers['location'] ?? '';
      if (res.statusCode >= 300 && res.statusCode < 400) {
        final err = Uri.tryParse(loc)?.queryParameters['error'];
        if (err == null || err.isEmpty) return const TaskResult(true, '');
        if (err == 'missing_name') {
          return const TaskResult(false, 'Please fill out the Project name field.');
        }
        return TaskResult(false, err);
      }
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return const TaskResult(true, '');
      }
      return TaskResult(false, 'HTTP ${res.statusCode}');
    } catch (_) {
      return const TaskResult(false, 'Could not reach the server.');
    }
  }

  Future<TaskResult> deleteProject(int projectId) async {
    try {
      final res = await _api.postPath('projects.php', body: {
        'delete_project': '1',
        'project_id': projectId.toString(),
      });
      if (res['success'] == true) return const TaskResult(true, 'Project deleted.');
      return TaskResult(false,
          (res['message'] ?? 'Could not delete the project.').toString(), res);
    } catch (_) {
      return const TaskResult(false, 'Could not reach the server.');
    }
  }

  static String _fmtDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }
}
