import '../api_client.dart';
import '../models/models.dart';

/// Service layer. Each method calls `api.php?action=<x>` and returns typed
/// results. The wire shapes here are verified against the live backend:
///   * getMobileDashboardSummary  → {success, stats: [...], charts: {...}}
///   * getMobileNotificationSummary → {success, items: [{id,type,title,subtitle}]}
///   * getcustomer                → {data: [...], totalRecords, limit, page}
///   * getCustomerbyID            → single customer row (shape varies)
///   * getleads                   → bare array of leads
///   * get_tickets                → bare array of tickets (+ agent_name join)
///
/// On any failure the method returns an empty-but-valid result so the UI
/// still renders. Raw errors are rethrown only from login.

class AuthService {
  AuthService(this.api);
  final ApiClient api;

  Future<UserSession> login(String email, String password) async {
    // Defensive: wipe ANY user-scoped state from a previous session
    // before we even touch the server. Handles the case where logout
    // was incomplete (network failure, app killed mid-flight, upgraded
    // from an older build with broken logout, etc.) so no notification
    // cursor / cached user id / leftover cookie from account A leaks
    // into account B's session.
    await api.clearSession();

    final res = await api.post('login', body: {
      'email': email.trim(),
      'password': password,
      'remember': '1',
    });
    if (res['success'] != true) {
      throw Exception(res['message']?.toString() ?? 'Login failed');
    }
    final session = UserSession.fromJson(res);
    if (session.userId <= 0) {
      // Server said success=true but didn't include a usable userID.
      // Refusing rather than handing the caller a HomeShell with no
      // identity — that's exactly the state that produced "CHAT
      // UNAVAILABLE" loops in the wild.
      throw Exception(
          'Login succeeded but server did not return a user id. '
          'Please contact support.');
    }
    await api.setUserId(session.userId);
    if (session.username.isNotEmpty && session.username != '—') {
      await api.setUsername(session.username);
    }
    return session;
  }

  Future<UserSession?> currentSession() async {
    try {
      final res = await api.get('getMobileAuthSession');
      if (res['success'] == true && res['user'] is Map) {
        return UserSession.fromJson(
            Map<String, dynamic>.from(res['user'] as Map));
      }
    } catch (_) {}
    return null;
  }

  /// Returns the authenticated user's id. Reads the value persisted at
  /// login time (cheap, no network) first, then falls back to a one-shot
  /// `getMobileAuthSession` call with an 8-second timeout for users
  /// upgrading from older builds that didn't persist the id.
  Future<int?> currentUserId() async {
    final cached = api.userId;
    if (cached != null && cached > 0) return cached;
    try {
      final res = await api
          .get('getMobileAuthSession')
          .timeout(const Duration(seconds: 8));
      if (res['success'] == true) {
        final raw = res['userID'] ?? res['user_id'];
        int? parsed;
        if (raw is int) {
          parsed = raw;
        } else if (raw is num) {
          parsed = raw.toInt();
        } else if (raw is String) {
          parsed = int.tryParse(raw);
        }
        if (parsed != null && parsed > 0) {
          // Cache for next launch so the next bootstrap is offline-friendly.
          await api.setUserId(parsed);
          return parsed;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Variant that returns both the user id (or null) AND the server's
  /// last-message reason on failure — used by the chat bootstrap so the
  /// "CHAT UNAVAILABLE" screen can show *why* (No active session / HTTP
  /// error / network) instead of a generic "check your connection".
  Future<({int? userId, String? error})> currentUserIdWithReason() async {
    final cached = api.userId;
    if (cached != null && cached > 0) return (userId: cached, error: null);
    try {
      final res = await api
          .get('getMobileAuthSession')
          .timeout(const Duration(seconds: 8));
      if (res['success'] == true) {
        final raw = res['userID'] ?? res['user_id'];
        int? parsed;
        if (raw is int) {
          parsed = raw;
        } else if (raw is num) {
          parsed = raw.toInt();
        } else if (raw is String) {
          parsed = int.tryParse(raw);
        }
        if (parsed != null && parsed > 0) {
          await api.setUserId(parsed);
          return (userId: parsed, error: null);
        }
        return (
          userId: null,
          error: 'Server did not return a user id.',
        );
      }
      final msg = (res['message'] ?? 'No active session').toString();
      return (userId: null, error: msg);
    } catch (e) {
      return (userId: null, error: 'Network error');
    }
  }

  Future<void> logout() async {
    try {
      await api.post('logout');
    } catch (_) {}
    await api.clearSession();
  }
}

class DashboardService {
  DashboardService(this.api);
  final ApiClient api;

  Future<DashboardSummary> fetch() async {
    Map<String, dynamic> summary = {};
    Map<String, dynamic> notifications = {};
    try {
      summary = await api.get('getMobileDashboardSummary');
    } catch (_) {}
    try {
      notifications = await api.get('getMobileNotificationSummary');
    } catch (_) {}
    if (summary['success'] != true && notifications['success'] != true) {
      return DashboardSummary.empty();
    }
    return DashboardSummary.fromJson(summary, notifications);
  }
}

class CustomerService {
  CustomerService(this.api);
  final ApiClient api;

  Future<List<CustomerBrief>> list({String? search, int limit = 50}) async {
    try {
      final res = await api.get('getcustomer', {
        'limit': '$limit',
        'page': '1',
        if (search != null && search.isNotEmpty) 'search': search,
      });
      final raw = res['data'];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => CustomerBrief.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  /// `getCustomerbyID` returns the full customer row. Response shape has
  /// varied across installs, so we sniff for the usual wrappers.
  Future<Map<String, dynamic>?> detail(int id) async {
    try {
      final res = await api.get('getCustomerbyID', {'id': id.toString()});
      for (final key in ['data', 'customer', 'row']) {
        final v = res[key];
        if (v is Map) return Map<String, dynamic>.from(v);
      }
      // Some endpoints return the row directly with `id` as a top-level key.
      if (res['id'] != null) return res;
    } catch (_) {}
    return null;
  }
}

class LeadService {
  LeadService(this.api);
  final ApiClient api;

  Future<List<LeadBrief>> list() async {
    try {
      final res = await api.get('getleads');
      // Backend returns either a bare array or ApiClient wraps it as {'data': [...]}.
      final raw = res['data'] ?? res;
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => LeadBrief.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<bool> updateNote(int id, String note) async {
    try {
      final res = await api.post('updateLeadNote',
          body: {'id': id.toString(), 'note': note});
      return res['success'] == true || res['status'] == 'success';
    } catch (_) {
      return false;
    }
  }

  Future<bool> delete(int id) async {
    try {
      final res =
          await api.post('deleteLead', body: {'id': id.toString()});
      return res['success'] == true || res['status'] == 'success';
    } catch (_) {
      return false;
    }
  }
}

class TicketService {
  TicketService(this.api);
  final ApiClient api;

  Future<List<TicketBrief>> list() async {
    try {
      final res = await api.get('get_tickets');
      final raw = res['data'] ?? res;
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => TicketBrief.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    return const [];
  }
}
