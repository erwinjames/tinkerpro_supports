// API layer for the File Management feature. All endpoints live on api.php:
//   * file_list_collections  GET                        → {success, data:[...]}
//   * file_collection_files   GET   id                  → {success, collection, files:[...]}
//   * file_upload             POST  (multipart)         collection_name, email?,
//                                   collection_type, files[]  → {success, collection_id}
//   * file_delete_collection  POST  id                  → {success, message}
//   * file_delete_item        POST  id                  → {success, message}
//   * get_share_link          GET   id                  → {success, share_token, expires_at, ...}
//
// CAVEAT — file_delete_collection / file_delete_item read the id from a JSON
// body (php://input: `json_decode(...)->id`), NOT from $_POST. ApiClient.post
// sends a url-encoded body, so $_POST is populated but php://input is the
// url-encoded string and `->id` resolves to null. These two deletes therefore
// require a backend tweak (read $_POST['id'] as a fallback) to actually work.
// We still implement them via api.post as a best effort.

import '../api_client.dart';
import '../models/file_models.dart';

class FileResult {
  FileResult({required this.ok, this.message});
  final bool ok;
  final String? message;
}

class ShareLink {
  ShareLink({
    this.token,
    this.expiresAt,
    this.expired = false,
    this.permanentToken,
  });

  /// Expiring share token (may be absent until generated).
  final String? token;
  final String? expiresAt;
  final bool expired;

  /// Permanent share token (absent until generated).
  final String? permanentToken;

  bool get hasExpiring => (token ?? '').isNotEmpty;
  bool get hasPermanent => (permanentToken ?? '').isNotEmpty;
}

class FileService {
  FileService(this._api);
  final ApiClient _api;

  /// All collections, newest first. Returns an empty list on any failure so
  /// the UI still renders.
  Future<List<FileCollection>> listCollections() async {
    try {
      final res = await _api.get('file_list_collections');
      final raw = res['data'] ?? res;
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => FileCollection.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  /// Files inside one collection. Empty list on failure.
  Future<List<StoredFile>> collectionFiles(String collectionId) async {
    try {
      final res = await _api.get('file_collection_files', {'id': collectionId});
      final raw = res['files'] ?? res['data'];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => StoredFile.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  /// Upload a single file, creating a new collection. The PHP facade expects
  /// the form field `files[]` (array-style), matching the web uploader.
  Future<FileResult> upload({
    required String collectionName,
    String? email,
    String collectionType = 'default',
    required String filePath,
  }) async {
    try {
      final res = await _api.postMultipart(
        'file_upload',
        fields: {
          'collection_name': collectionName.trim(),
          'collection_type': collectionType,
          if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
        },
        files: {'files[]': filePath},
      );
      final ok = res['success'] == true || res['status'] == 'success';
      return FileResult(ok: ok, message: res['message']?.toString());
    } catch (e) {
      return FileResult(ok: false, message: 'Network error');
    }
  }

  // These two handlers read `id` from a raw JSON request body
  // (php://input), not $_POST — so they must be sent as JSON.
  Future<FileResult> deleteCollection(String collectionId) =>
      _mutateJson('file_delete_collection', {'id': collectionId});

  Future<FileResult> deleteItem(String fileId) =>
      _mutateJson('file_delete_item', {'id': fileId});

  /// Fetch the current share tokens (expiring + permanent) for a collection.
  /// Either may be empty until generated. Returns null only on failure.
  Future<ShareLink?> getShareLink(String collectionId) async {
    try {
      final res = await _api.get('get_share_link', {'id': collectionId});
      final ok = res['success'] == true || res['status'] == 'success';
      if (!ok) return null;
      return ShareLink(
        token: res['share_token']?.toString(),
        expiresAt: res['expires_at']?.toString(),
        expired: res['expired'] == true || res['expired'] == 1,
        permanentToken: res['permanent_share_token']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  /// (Re)generate the expiring share token. Reads `id` from a JSON body.
  Future<ShareLink?> generateExpiringLink(String collectionId) async {
    try {
      final res =
          await _api.postJson('generate_share_link', body: {'id': collectionId});
      if (res['success'] != true) return null;
      final token = res['share_token']?.toString() ?? '';
      if (token.isEmpty) return null;
      return ShareLink(token: token, expiresAt: res['expires_at']?.toString());
    } catch (_) {
      return null;
    }
  }

  /// Generate the permanent share token. Reads `id` from a JSON body.
  Future<String?> generatePermanentLink(String collectionId) async {
    try {
      final res = await _api
          .postJson('generate_permanent_share_link', body: {'id': collectionId});
      if (res['success'] != true) return null;
      final t = res['permanent_share_token']?.toString() ?? '';
      return t.isEmpty ? null : t;
    } catch (_) {
      return null;
    }
  }

  /// Build the public viewer URL the way the web app does:
  /// `<baseUrl>/file-share.php#<token>`.
  String shareUrl(String token) => '${_api.baseUrl}/file-share.php#$token';

  Future<FileResult> _mutateJson(
      String action, Map<String, dynamic> body) async {
    try {
      final res = await _api.postJson(action, body: body);
      final ok = res['success'] == true || res['status'] == 'success';
      return FileResult(ok: ok, message: res['message']?.toString());
    } catch (e) {
      return FileResult(ok: false, message: 'Network error');
    }
  }
}
