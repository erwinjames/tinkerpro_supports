int _int(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

String _str(dynamic v) => v == null ? '' : v.toString();

enum ReminderBucket { overdue, today, week, later, undated }

ReminderBucket _bucket(dynamic raw) {
  switch (_str(raw)) {
    case 'overdue':
      return ReminderBucket.overdue;
    case 'today':
      return ReminderBucket.today;
    case 'week':
      return ReminderBucket.week;
    case 'later':
      return ReminderBucket.later;
    default:
      return ReminderBucket.undated;
  }
}

class TaskReminder {
  const TaskReminder({
    required this.id,
    required this.title,
    required this.bucket,
    required this.label,
    required this.priority,
    required this.project,
    required this.assigner,
  });

  final int id;
  final String title;
  final ReminderBucket bucket;
  final String label;
  final String priority;
  final String project;
  final String assigner;

  factory TaskReminder.fromJson(Map<String, dynamic> j) => TaskReminder(
        id: _int(j['id']),
        title: _str(j['title']),
        bucket: _bucket(j['bucket']),
        label: _str(j['label']),
        priority: _str(j['priority']),
        project: _str(j['project']),
        assigner: _str(j['assigner']),
      );
}

class PtuReminder {
  const PtuReminder({
    required this.id,
    required this.name,
    required this.tin,
    required this.branchCode,
    required this.label,
  });

  final int id;
  final String name;
  final String tin;
  final String branchCode;
  final String label;

  factory PtuReminder.fromJson(Map<String, dynamic> j) => PtuReminder(
        id: _int(j['id']),
        name: _str(j['name']),
        tin: _str(j['tin']),
        branchCode: _str(j['branch_code']),
        label: _str(j['label']),
      );
}

class StickyNote {
  const StickyNote({
    required this.id,
    required this.title,
    required this.body,
    required this.dueDate,
    required this.bucket,
    required this.label,
  });

  final int id;
  final String title;
  final String body;
  final String dueDate;
  final ReminderBucket bucket;
  final String label;

  DateTime? get due => dueDate.isEmpty ? null : DateTime.tryParse(dueDate);

  factory StickyNote.fromJson(Map<String, dynamic> j) => StickyNote(
        id: _int(j['id']),
        title: _str(j['title']),
        body: _str(j['body']),
        dueDate: _str(j['due_date']),
        bucket: _bucket(j['bucket']),
        label: _str(j['label']),
      );
}

class ReminderFeed {
  const ReminderFeed({
    required this.canTask,
    required this.canBir,
    required this.taskMode,
    required this.taskOwner,
    required this.tasks,
    required this.taskOverdue,
    required this.taskToday,
    required this.taskOpen,
    required this.ptuPending,
    required this.ptuCompleted,
    required this.ptuActive,
    required this.notes,
    required this.badge,
  });

  final bool canTask;
  final bool canBir;
  final String taskMode;
  final String taskOwner;
  final List<TaskReminder> tasks;
  final int taskOverdue;
  final int taskToday;
  final int taskOpen;
  final List<PtuReminder> ptuPending;
  final List<PtuReminder> ptuCompleted;
  final int ptuActive;
  final List<StickyNote> notes;
  final int badge;

  static const empty = ReminderFeed(
    canTask: false,
    canBir: false,
    taskMode: 'off',
    taskOwner: '',
    tasks: [],
    taskOverdue: 0,
    taskToday: 0,
    taskOpen: 0,
    ptuPending: [],
    ptuCompleted: [],
    ptuActive: 0,
    notes: [],
    badge: 0,
  );

  bool get isEmpty =>
      tasks.isEmpty && ptuPending.isEmpty && ptuCompleted.isEmpty && notes.isEmpty;

  int get notesDue => notes
      .where((n) =>
          n.bucket == ReminderBucket.overdue || n.bucket == ReminderBucket.today)
      .length;

  factory ReminderFeed.fromJson(Map<String, dynamic> j) {
    final tasks = (j['tasks'] is Map)
        ? Map<String, dynamic>.from(j['tasks'] as Map)
        : <String, dynamic>{};
    final counts = (tasks['counts'] is Map)
        ? Map<String, dynamic>.from(tasks['counts'] as Map)
        : <String, dynamic>{};
    final ptu = (j['ptu'] is Map)
        ? Map<String, dynamic>.from(j['ptu'] as Map)
        : <String, dynamic>{};

    List<Map<String, dynamic>> list(dynamic raw) => raw is List
        ? raw.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
        : const [];

    List<Map<String, dynamic>> section(dynamic raw) =>
        raw is Map ? list(raw['items']) : const [];

    return ReminderFeed(
      canTask: j['can_task'] == true,
      canBir: j['can_bir'] == true,
      taskMode: _str(tasks['mode']).isEmpty ? 'off' : _str(tasks['mode']),
      taskOwner: _str(tasks['owner']),
      tasks: list(tasks['items']).map(TaskReminder.fromJson).toList(),
      taskOverdue: _int(counts['overdue']),
      taskToday: _int(counts['today']),
      taskOpen: _int(counts['open']),
      ptuPending: section(ptu['pending']).map(PtuReminder.fromJson).toList(),
      ptuCompleted: section(ptu['completed']).map(PtuReminder.fromJson).toList(),
      ptuActive: _int(ptu['active']),
      notes: list(j['notes']).map(StickyNote.fromJson).toList(),
      badge: _int(j['badge']),
    );
  }
}
