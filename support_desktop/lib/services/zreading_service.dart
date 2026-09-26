import '../api_client.dart';

String _s(dynamic v) => v == null ? '' : '$v';
int _i(dynamic v) => v is int ? v : int.tryParse('${v ?? ''}') ?? 0;
bool _b(dynamic v) => v == true || v == 1 || v == '1' || v == 'true';
DateTime? _d(dynamic v) {
  final raw = _s(v).trim();
  if (raw.isEmpty) return null;
  return DateTime.tryParse(raw.replaceFirst(' ', 'T'));
}

List<Map<String, dynamic>> _maps(dynamic raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((m) => Map<String, dynamic>.from(m))
      .toList();
}

String _message(Map<String, dynamic> res, String fallback) {
  final m = _s(res['message']).trim();
  return m.isEmpty ? fallback : m;
}

class ZrSettings {
  const ZrSettings({
    this.warnThreshold = 3,
    this.warnWindowHours = 24,
    this.codeTtlMinutes = 15,
    this.maxAttempts = 5,
  });

  final int warnThreshold;
  final int warnWindowHours;
  final int codeTtlMinutes;
  final int maxAttempts;

  factory ZrSettings.fromJson(Map<String, dynamic> j) => ZrSettings(
        warnThreshold: _i(j['warn_threshold']),
        warnWindowHours: _i(j['warn_window_hours']),
        codeTtlMinutes: _i(j['code_ttl_minutes']),
        maxAttempts: _i(j['max_attempts']),
      );
}

class ZrSummary {
  const ZrSummary({
    this.pending = 0,
    this.approved = 0,
    this.verified = 0,
    this.today = 0,
    this.flaggedUsers = 0,
    this.blockedUsers = 0,
  });

  final int pending;
  final int approved;
  final int verified;
  final int today;
  final int flaggedUsers;
  final int blockedUsers;

  factory ZrSummary.fromJson(Map<String, dynamic> j) => ZrSummary(
        pending: _i(j['pending']),
        approved: _i(j['approved']),
        verified: _i(j['verified']),
        today: _i(j['today']),
        flaggedUsers: _i(j['flagged_users']),
        blockedUsers: _i(j['blocked_users']),
      );
}

class ZrRequest {
  ZrRequest(this.raw);
  final Map<String, dynamic> raw;

  int get id => _i(raw['id']);
  String get reference => _s(raw['reference']);
  String get status => _s(raw['status']).toLowerCase();
  String get posUser => _s(raw['pos_user']);
  String get tinBase => _s(raw['tin_base']);
  String get tin => _s(raw['tin']);
  String get clientName => _s(raw['client_name']);
  String get machineSerial => _s(raw['machine_serial']);
  String get customerId => _s(raw['customer_id']);
  String get reason => _s(raw['reason']);
  String get source => _s(raw['source']);
  String get passcode => _s(raw['passcode']);
  String get approvedByName => _s(raw['approved_by_name']);
  String get deniedByName => _s(raw['denied_by_name']);
  String get denyReason => _s(raw['deny_reason']);
  int get attempts => _i(raw['attempts']);
  bool get isBlockedUser => _b(raw['is_blocked_user']);
  bool get codeActive => _b(raw['code_active']);
  DateTime? get requestedAt => _d(raw['requested_at']);
  DateTime? get businessDate => _d(raw['business_date']);
  DateTime? get verifiedAt => _d(raw['verified_at']);
  DateTime? get codeExpiresAt => _d(raw['code_expires_at']);
  DateTime? get codeDeliveredAt => _d(raw['code_delivered_at']);
}

class ZrGroup {
  ZrGroup(this.raw)
      : requests = _maps(raw['requests']).map(ZrRequest.new).toList();
  final Map<String, dynamic> raw;
  final List<ZrRequest> requests;

  String get key => _s(raw['key']);
  String get clientName => _s(raw['client_name']);
  String get tin => _s(raw['tin']);
  String get tinBase => _s(raw['tin_base']);
  String get branch => _s(raw['branch']);
  String get machineSerial => _s(raw['machine_serial']);
  String get terminalId => _s(raw['terminal_id']);
  int get totalRequests => _i(raw['total_requests']);
  int get pendingCount => _i(raw['pending_count']);
  int get recentCount => _i(raw['recent_count']);
  bool get flagged => _b(raw['flagged']);
  bool get hasMore => _b(raw['has_more']);
  DateTime? get lastRequestedAt => _d(raw['last_requested_at']);
  List<String> get blockedUsers =>
      _maps(raw['blocked_users']).map((b) => _s(b['pos_user'])).toList();
}

class ZrPage {
  const ZrPage({
    required this.groups,
    required this.total,
    required this.summary,
    required this.settings,
  });
  final List<ZrGroup> groups;
  final int total;
  final ZrSummary summary;
  final ZrSettings? settings;
}

class ZrEvent {
  ZrEvent(this.raw);
  final Map<String, dynamic> raw;
  String get event => _s(raw['event']).replaceAll('_', ' ');
  String get actor => _s(raw['actor']);
  String get actorType => _s(raw['actor_type']);
  String get ip => _s(raw['ip']);
  String get detail => _s(raw['detail']);
  DateTime? get createdAt => _d(raw['created_at']);
}

class ZrTrail {
  const ZrTrail({required this.request, required this.events});
  final ZrRequest request;
  final List<ZrEvent> events;
}

class ZrBlock {
  ZrBlock(this.raw);
  final Map<String, dynamic> raw;
  int get id => _i(raw['id']);
  String get posUser => _s(raw['pos_user']);
  String get clientName => _s(raw['client_name']);
  String get tinBase => _s(raw['tin_base']);
  String get machineSerial => _s(raw['machine_serial']);
  String get blockedByName => _s(raw['blocked_by_name']);
  String get reason => _s(raw['reason']);
  DateTime? get blockedAt => _d(raw['blocked_at']);
}

class ZrApproval {
  const ZrApproval({
    required this.passcode,
    required this.posUser,
    required this.clientName,
    required this.reference,
    required this.expiresAt,
  });
  final String passcode;
  final String posUser;
  final String clientName;
  final String reference;
  final String expiresAt;
}

class ZrLogResult {
  const ZrLogResult({required this.reference, required this.blocked});
  final String reference;
  final bool blocked;
}

class ZrException implements Exception {
  ZrException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ZReadingService {
  ZReadingService(this.api);
  final ApiClient api;

  Future<ZrPage> list({
    int page = 1,
    int limit = 10,
    String search = '',
    String status = '',
    bool flaggedOnly = false,
  }) async {
    final res = await api.get('getZReadingRequests', {
      'page': '$page',
      'limit': '$limit',
      'search': search,
      'status': status,
      'flagged_only': flaggedOnly ? '1' : '0',
    });
    if (res['success'] != true) {
      throw ZrException(_message(res, 'Failed to load requests'));
    }
    return ZrPage(
      groups: _maps(res['data']).map(ZrGroup.new).toList(),
      total: _i(res['totalRecords']),
      summary: res['summary'] is Map
          ? ZrSummary.fromJson(Map<String, dynamic>.from(res['summary']))
          : const ZrSummary(),
      settings: res['settings'] is Map
          ? ZrSettings.fromJson(Map<String, dynamic>.from(res['settings']))
          : null,
    );
  }

  Future<ZrApproval> approve(int id) async {
    final res = await api.post('approveZReadingRequest', body: {'id': '$id'});
    if (res['success'] != true) {
      throw ZrException(_message(res, 'Approve failed'));
    }
    return ZrApproval(
      passcode: _s(res['passcode']),
      posUser: _s(res['pos_user']),
      clientName: _s(res['client_name']),
      reference: _s(res['reference']),
      expiresAt: _s(res['expires_at']),
    );
  }

  Future<void> deny(int id, String reason) async {
    final res = await api.post('denyZReadingRequest',
        body: {'id': '$id', 'reason': reason});
    if (res['success'] != true) {
      throw ZrException(_message(res, 'Deny failed'));
    }
  }

  Future<ZrTrail> trail(int id) async {
    final res = await api.get('getZReadingEvents', {'id': '$id'});
    if (res['success'] != true || res['request'] is! Map) {
      throw ZrException(_message(res, 'Could not load the trail'));
    }
    return ZrTrail(
      request: ZrRequest(Map<String, dynamic>.from(res['request'])),
      events: _maps(res['events']).map(ZrEvent.new).toList(),
    );
  }

  Future<void> block(ZrRequest r, String reason) async {
    final res = await api.post('blockZReadingUser', body: {
      'request_id': '${r.id}',
      'tin_base': r.tinBase,
      'pos_user': r.posUser,
      'client_name': r.clientName,
      'machine_serial': r.machineSerial,
      'customer_id': r.customerId,
      'reason': reason,
    });
    if (res['success'] != true) {
      throw ZrException(_message(res, 'Block failed'));
    }
  }

  Future<void> unblockRequest(ZrRequest r) async {
    final res = await api.post('unblockZReadingUser', body: {
      'request_id': '${r.id}',
      'pos_user': r.posUser,
      'tin_base': r.tinBase,
    });
    if (res['success'] != true) {
      throw ZrException(_message(res, 'Unblock failed'));
    }
  }

  Future<void> unblockById(int blockId) async {
    final res =
        await api.post('unblockZReadingUser', body: {'block_id': '$blockId'});
    if (res['success'] != true) {
      throw ZrException(_message(res, 'Unblock failed'));
    }
  }

  Future<List<ZrBlock>> blocks() async {
    final res = await api.get('getZReadingBlocks');
    if (res['success'] != true) {
      throw ZrException(_message(res, 'Could not load blocked users'));
    }
    return _maps(res['blocks']).map(ZrBlock.new).toList();
  }

  Future<void> delete(int id) async {
    final res = await api.post('deleteZReadingRequest', body: {'id': '$id'});
    if (res['success'] != true) {
      throw ZrException(_message(res, 'Delete failed'));
    }
  }

  Future<ZrLogResult> logManual(Map<String, String> fields) async {
    final res = await api.post('addZReadingRequest', body: fields);
    final ref = _s(res['reference']);
    if (ref.isEmpty) {
      throw ZrException(_message(res, 'Could not log the request'));
    }
    return ZrLogResult(reference: ref, blocked: _b(res['blocked']));
  }
}
