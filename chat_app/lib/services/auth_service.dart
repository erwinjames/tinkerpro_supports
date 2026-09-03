import '../api_client.dart';
import '../models/session_models.dart';

class AuthService {
  AuthService(this.api);
  final ApiClient api;

  Future<UserSession> login(
    String email,
    String password, {
    bool remember = true,
  }) async {

    await api.clearSession();

    final res = await api.post('login', body: {
      'email': email.trim(),
      'password': password,
      'remember': remember ? '1' : '0',
    });
    if (res['success'] != true) {
      throw Exception(res['message']?.toString() ?? 'Login failed');
    }
    final session = UserSession.fromJson(res);
    if (session.userId <= 0) {

      throw Exception(
          'Login succeeded but server did not return a user id. '
          'Please contact support.');
    }
    await api.setUserId(session.userId);
    if (session.username.isNotEmpty && session.username != '—') {
      await api.setUsername(session.username);
    }
    await api.setUserRole(session.role);
    await api.setPermissions(session.permissions);
    return session;
  }

  Future<String> googleClientId() async {
    try {
      final res =
          await api.get('mobileAuthConfig').timeout(const Duration(seconds: 8));
      return (res['google_client_id'] ?? '').toString();
    } catch (_) {
      return '';
    }
  }

  Future<UserSession> loginWithGoogle(String idToken) async {
    await api.clearSession();
    final res = await api.post('mobileOAuthLogin', body: {
      'provider': 'google',
      'id_token': idToken,
    });
    if (res['success'] != true) {
      throw Exception(res['message']?.toString() ?? 'Google sign-in failed');
    }
    final session = UserSession.fromJson(res);
    if (session.userId <= 0) {
      throw Exception(
          'Sign-in succeeded but server did not return a user id. '
          'Please contact support.');
    }
    await api.setUserId(session.userId);
    if (session.username.isNotEmpty && session.username != '—') {
      await api.setUsername(session.username);
    }
    await api.setUserRole(session.role);
    await api.setPermissions(session.permissions);
    return session;
  }

  Future<bool> refreshPermissions() async {
    try {
      final res = await api
          .get('getMobileAuthSession')
          .timeout(const Duration(seconds: 8));
      if (res['success'] == true && res['permissions'] != null) {
        final session = UserSession.fromJson(Map<String, dynamic>.from(res));
        if (session.role.isNotEmpty && session.role != api.userRole) {
          await api.setUserRole(session.role);
        }
        final fresh = session.permissions;
        final before = api.permissions;
        final changed = before.length != fresh.length ||
            fresh.entries.any((e) => before[e.key] != e.value);
        if (changed) await api.setPermissions(fresh);
        return changed;
      }
    } catch (_) {}
    return false;
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

          await api.setUserId(parsed);
          return parsed;
        }
      }
    } catch (_) {}
    return null;
  }

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
