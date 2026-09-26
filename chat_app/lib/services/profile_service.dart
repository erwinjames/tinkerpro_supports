import '../api_client.dart';
import '../models/profile_models.dart';

class ProfileResult {
  ProfileResult({required this.ok, this.message, this.profilePicture});
  final bool ok;
  final String? message;

  final String? profilePicture;
}

class ProfileService {
  ProfileService(this._api);
  final ApiClient _api;

  String? avatarUrl(String? relPath) {
    if (relPath == null || relPath.isEmpty) return null;
    final clean = relPath.replaceAll(RegExp(r'^/+'), '');
    return '${_api.baseUrl}/$clean';
  }

  Map<String, String> get imageHeaders => _api.authHeaders();

  Future<ProfileInfo?> load() async {
    try {
      final res = await _api.get('getSelfSettings');
      if (_okStatus(res)) {
        final data = res['data'];
        if (data is Map) {
          return ProfileInfo.fromJson(Map<String, dynamic>.from(data));
        }
      }
    } catch (_) {}
    return null;
  }

  Future<ProfileResult> uploadPicture(String filePath) async {
    try {
      final res = await _api.postMultipart(
        'updateProfilePicture',
        files: {'profile_picture': filePath},
      );
      final ok = _okStatus(res);
      return ProfileResult(
        ok: ok,
        message: res['message']?.toString(),
        profilePicture: ok ? res['profile_picture']?.toString() : null,
      );
    } catch (_) {
      return ProfileResult(ok: false, message: 'Network error');
    }
  }

  Future<ProfileResult> removePicture() async {
    try {
      final res = await _api.post('removeProfilePicture');
      return ProfileResult(
        ok: _okStatus(res),
        message: res['message']?.toString(),
      );
    } catch (_) {
      return ProfileResult(ok: false, message: 'Network error');
    }
  }

  Future<ProfileResult> saveChatAlias(ProfileInfo current, String alias) async {
    try {
      final res = await _api.post(
        'updateSelfAccount',
        body: {
          'full_name': current.fullName,
          'email': current.email,
          'chat_alias': alias.trim(),
        },
      );
      return ProfileResult(
        ok: _okStatus(res),
        message: res['message']?.toString(),
      );
    } catch (_) {
      return ProfileResult(ok: false, message: 'Network error');
    }
  }

  Future<({bool enabled, String start, String end, String tz})?>
      agentHours() async {
    try {
      final res = await _api.get('getAgentHoursSettings');
      if (res['status'] != 'success') return null;
      final on = res['enabled'];
      return (
        enabled: on == true || on == 1 || on == '1',
        start: (res['start'] ?? '08:00').toString(),
        end: (res['end'] ?? '17:00').toString(),
        tz: (res['tz'] ?? '').toString(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<ProfileResult> saveAgentHours({
    required bool enabled,
    required String start,
    required String end,
  }) async {
    try {
      final res = await _api.post(
        'saveAgentHoursSettings',
        body: {'enabled': enabled ? '1' : '0', 'start': start, 'end': end},
      );
      return ProfileResult(
        ok: _okStatus(res),
        message: res['message']?.toString(),
      );
    } catch (_) {
      return ProfileResult(ok: false, message: 'Network error');
    }
  }

  bool _okStatus(Map<String, dynamic> res) =>
      res['status'] == 'success' || res['success'] == true;
}
