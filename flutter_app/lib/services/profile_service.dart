// API layer for the signed-in user's own profile. Endpoints on api.php:
//   * getSelfSettings       GET                       → {status, data:{...}}
//   * updateProfilePicture  POST multipart (profile_picture=file)
//                                                     → {status, profile_picture}
//   * removeProfilePicture  POST                      → {status}
//
// These mirror the web Settings page's avatar controls. Responses use the
// `status: 'success' | 'error'` convention (not the `success: true` shape).

import '../api_client.dart';
import '../models/profile_models.dart';

class ProfileResult {
  ProfileResult({required this.ok, this.message, this.profilePicture});
  final bool ok;
  final String? message;

  /// New server-relative avatar path on a successful upload.
  final String? profilePicture;
}

class ProfileService {
  ProfileService(this._api);
  final ApiClient _api;

  /// Absolute URL for a server-relative avatar path, or null when [relPath]
  /// is null/empty. Avatars live under `uploads/avatars/` and are served
  /// statically, so this is just base URL + path.
  String? avatarUrl(String? relPath) {
    if (relPath == null || relPath.isEmpty) return null;
    final clean = relPath.replaceAll(RegExp(r'^/+'), '');
    return '${_api.baseUrl}/$clean';
  }

  /// Cookie headers so an authed image loader (CachedNetworkImage) can fetch
  /// the avatar if the server ever gates the uploads directory.
  Map<String, String> get imageHeaders => _api.authHeaders();

  /// Load the current account (name/email/username/avatar). Returns null on
  /// any failure so the caller can show a fallback.
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

  /// Upload a new avatar from a local file path (multipart, field
  /// `profile_picture`). On success the new server-relative path is returned
  /// in [ProfileResult.profilePicture].
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

  /// Clear the user's avatar.
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
