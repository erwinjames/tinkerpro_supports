import '../api_client.dart';
import '../models/activity_models.dart';

class ActivityService {
  ActivityService(this._api);
  final ApiClient _api;

  static const String tracePath = 'utils/models/get_log_detail.php';
  static const String onlineUsersPath = 'utils/models/get_online_users.php';
  static const String ticketsPath = 'utils/models/get_tickets_log.php';
  static const String portalActivityPath =
      'utils/models/get_portal_activity_logs.php';
  static const String shareAccessPath =
      'utils/models/get_share_access_logs.php';

  bool get isSuperAdmin => _api.isSuperAdmin;

  Future<ActivityLogPage> fetch({
    String search = '',
    int page = 1,
    int limit = 40,
  }) async {
    try {
      final res = await _api.get('getActivityLogs', {
        'page': '$page',
        'limit': '$limit',
        if (search.trim().isNotEmpty) 'search': search.trim(),
      });
      final raw = res['data'];
      if (raw is! List) return ActivityLogPage.empty;
      final rows = raw
          .whereType<Map>()
          .map((e) => ActivityLog.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
      final total = res['totalRecords'];
      return ActivityLogPage(
        rows: rows,
        total: total is int ? total : int.tryParse('$total') ?? rows.length,
      );
    } catch (_) {
      return ActivityLogPage.empty;
    }
  }

  Future<ActivityTrace?> trace(int logId) async {
    if (!isSuperAdmin || logId <= 0) return null;
    try {
      final res = await _api.getPath(tracePath, {
        'subject': 'log',
        'log_id': '$logId',
      });
      if (res['success'] != true) return null;
      return ActivityTrace.fromJson(res);
    } catch (_) {
      return null;
    }
  }

  Future<TraceHeartbeat?> heartbeat(int userId) async {
    if (!isSuperAdmin || userId <= 0) return null;
    try {
      final res = await _api.getPath(tracePath, {
        'live': '1',
        'live_kind': 'user',
        'user_id': '$userId',
      });
      if (res['success'] != true) return null;
      final user = res['user'];
      final latest = res['latest_id'];
      return TraceHeartbeat(
        latestId: latest is int ? latest : int.tryParse('$latest') ?? 0,
        user: user is Map
            ? TracePresence.fromJson(Map<String, dynamic>.from(user))
            : null,
      );
    } catch (_) {
      return null;
    }
  }

  Future<ActivityTrace?> traceFor(Map<String, String> query) async {
    if (!isSuperAdmin) return null;
    final res = await _api.getPath(tracePath, query);
    if (res['success'] != true) return null;
    return ActivityTrace.fromJson(res);
  }

  Future<TraceHeartbeat?> heartbeatFor(Map<String, String> query) async {
    if (!isSuperAdmin) return null;
    try {
      final res = await _api.getPath(tracePath, query);
      if (res['success'] != true) return null;
      final user = res['user'];
      final latest = res['latest_id'];
      return TraceHeartbeat(
        latestId: latest is int ? latest : int.tryParse('$latest') ?? 0,
        user: user is Map
            ? TracePresence.fromJson(Map<String, dynamic>.from(user))
            : null,
      );
    } catch (_) {
      return null;
    }
  }

  List<Map<String, dynamic>> _rows(Map<String, dynamic> res) {
    final raw = res['data'];
    if (raw is! List) {
      final message = res['error'] ?? res['message'];
      if (message != null) throw Exception('$message');
      return const <Map<String, dynamic>>[];
    }
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  Future<List<OnlineUser>> onlineUsers() async {
    final res = await _api.getPath(onlineUsersPath);
    return _rows(res).map(OnlineUser.fromJson).toList(growable: false);
  }

  Future<List<TicketLog>> tickets() async {
    final res = await _api.getPath(ticketsPath);
    return _rows(res).map(TicketLog.fromJson).toList(growable: false);
  }

  Future<List<PortalActivityLog>> portalActivity() async {
    final res = await _api.getPath(portalActivityPath);
    return _rows(res).map(PortalActivityLog.fromJson).toList(growable: false);
  }

  Future<List<PublicDownloadLog>> publicDownloads() async {
    final res = await _api.getPath(shareAccessPath);
    return _rows(res).map(PublicDownloadLog.fromJson).toList(growable: false);
  }

  Future<List<ConversationLog>> conversations() async {
    final res = await _api.get('chat.adminListConversations');
    if (res['success'] == false) {
      throw Exception('${res['message'] ?? 'Could not load conversations.'}');
    }
    return _rows(res).map(ConversationLog.fromJson).toList(growable: false);
  }

  Future<ConversationActivity> conversationActivity(int conversationId) async {
    final res = await _api.get('chat.getConversationActivity', {
      'conversation_id': '$conversationId',
    });
    if (res['success'] != true) {
      throw Exception('${res['message'] ?? 'Could not load conversation.'}');
    }
    return ConversationActivity.fromJson(res);
  }
}
