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

  bool _okStatus(Map<String, dynamic> res) =>
      res['status'] == 'success' || res['success'] == true;
}
