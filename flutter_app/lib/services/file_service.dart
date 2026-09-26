import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../api_client.dart';
import '../models/file_models.dart';

class FileResult {
  FileResult({required this.ok, this.message, this.data = const {}});
  final bool ok;
  final String? message;
  final Map<String, dynamic> data;
}

class ShareLink {
  ShareLink({
    this.token,
    this.expiresAt,
    this.expired = false,
    this.permanentToken,
  });

  final String? token;
  final String? expiresAt;
  final bool expired;

  final String? permanentToken;

  bool get hasExpiring => (token ?? '').isNotEmpty;
  bool get hasPermanent => (permanentToken ?? '').isNotEmpty;
}

class CollectionContents {
  CollectionContents({this.collection, this.files = const []});
  final FileCollection? collection;
  final List<StoredFile> files;
}

typedef UploadCandidate = ({String path, String name, int size});

enum UploadPhase { preparing, sending, retrying, finalizing }

class UploadProgress {
  const UploadProgress({
    required this.phase,
    required this.sent,
    required this.total,
    this.note = '',
  });

  final UploadPhase phase;
  final int sent;
  final int total;
  final String note;

  double get fraction => total <= 0 ? 0 : (sent / total).clamp(0, 1).toDouble();
}

class UploadCancelToken {
  bool _cancelled = false;
  http.Client? _client;

  bool get isCancelled => _cancelled;

  void bind(http.Client client) {
    _client = client;
    if (_cancelled) client.close();
  }

  void cancel() {
    _cancelled = true;
    try {
      _client?.close();
    } catch (_) {}
  }
}

class UploadOutcome {
  UploadOutcome({
    required this.ok,
    this.cancelled = false,
    this.message,
    this.collectionId = '',
    this.collectionType = '',
    this.shareToken = '',
    this.expiresAt = '',
    this.permanentShareToken = '',
    this.replaced = false,
    this.added = false,
  });

  final bool ok;
  final bool cancelled;
  final String? message;
  final String collectionId;
  final String collectionType;
  final String shareToken;
  final String expiresAt;
  final String permanentShareToken;
  final bool replaced;
  final bool added;
}

class _ChunkFailure implements Exception {
  _ChunkFailure(this.code, {this.message, this.serverCode, this.status});
  final String code;
  final String? message;
  final String? serverCode;
  final int? status;

  bool get worthShrinking =>
      code == 'network' ||
      code == 'http' ||
      code == 'parse' ||
      code == 'stall' ||
      code == '413' ||
      serverCode == 'body_missing' ||
      serverCode == 'body_truncated';
}

class FileService {
  FileService(this._api);
  final ApiClient _api;

  static const int _chunkCeiling = 20 * 1024 * 1024;
  static const int _chunkFallback = 2 * 1024 * 1024;
  static const int _chunkFloor = 256 * 1024;

  bool get isSuperAdmin => _api.isSuperAdmin;

  bool get canFiles => isSuperAdmin || _api.hasPermission('files');

  bool get canInstaller => isSuperAdmin || _api.hasPermission('installer');

  bool get restrictedToShared {
    if (isSuperAdmin) return false;
    final perms = _api.permissions;
    if (perms.containsKey('filesShareOjt')) {
      return perms['filesShareOjt'] == true;
    }
    if (perms.containsKey('filesAllFolders')) {
      return perms['filesAllFolders'] != true;
    }
    return _api.userRole.trim().toLowerCase() == 'ojt';
  }

  bool get canShareOjt => isSuperAdmin || (canFiles && !restrictedToShared);

  bool get canFolderSync {
    if (isSuperAdmin) return true;
    if (!canFiles) return false;
    final perms = _api.permissions;
    if (!perms.containsKey('filesFolderSync')) return true;
    return perms['filesFolderSync'] == true;
  }

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

  Future<CollectionContents> collectionContents(String collectionId) async {
    try {
      final res = await _api.get('file_collection_files', {'id': collectionId});
      final rawFiles = res['files'] ?? res['data'];
      final rawCollection = res['collection'];
      return CollectionContents(
        collection: rawCollection is Map
            ? FileCollection.fromJson(Map<String, dynamic>.from(rawCollection))
            : null,
        files: rawFiles is List
            ? rawFiles
                  .whereType<Map>()
                  .map((e) => StoredFile.fromJson(Map<String, dynamic>.from(e)))
                  .toList()
            : const [],
      );
    } catch (_) {
      return CollectionContents();
    }
  }

  Future<List<StoredFile>> collectionFiles(String collectionId) async =>
      (await collectionContents(collectionId)).files;

  Future<StorageUsage?> storageUsage() async {
    try {
      final res = await _api.get('file_storage_usage');
      if (res['success'] != true) return null;
      return StorageUsage.fromJson(res);
    } catch (_) {
      return null;
    }
  }

  Future<int> maxChunkBytes() async {
    try {
      final res = await _api.get('file_upload_limits');
      final value = res['success'] == true
          ? int.tryParse('${res['max_chunk_bytes']}')
          : null;
      if (value != null && value > 0) return math.min(value, _chunkCeiling);
    } catch (_) {}
    return _chunkFallback;
  }

  Future<FileResult> createFolder(String name, {String? parentId}) =>
      _mutateJson('file_create_folder', {
        'name': name.trim(),
        'parent_id': (parentId ?? '').isEmpty ? null : parentId,
      });

  Future<FileResult> renameCollection(String id, String name) =>
      _mutateJson('file_rename_collection', {'id': id, 'name': name.trim()});

  Future<FileResult> moveCollection(String id, String? parentId) => _mutateJson(
    'file_move_collection',
    {'id': id, 'parent_id': (parentId ?? '').isEmpty ? null : parentId},
  );

  Future<FileResult> deleteCollection(String collectionId) =>
      _mutateJson('file_delete_collection', {'id': collectionId});

  Future<FileResult> deleteItem(String fileId) =>
      _mutateJson('file_delete_item', {'id': fileId});

  Future<FileResult> setFavorite(String collectionId, bool favorite) =>
      _mutateJson('file_toggle_favorite', {
        'id': collectionId,
        'favorite': favorite,
      });

  Future<FileResult> setVendorVisible(String collectionId, bool visible) =>
      _mutateJson('file_set_vendor_visible', {
        'collection_id': collectionId,
        'vendor_visible': visible ? 1 : 0,
      });

  Future<FileResult> setOjtVisible(String collectionId, bool visible) =>
      _mutateJson('file_set_ojt_visible', {
        'collection_id': collectionId,
        'ojt_visible': visible ? 1 : 0,
      });

  Future<FileResult> setReleaseNotes(String collectionId, String notes) =>
      _mutateJson('file_set_release_notes', {
        'id': collectionId,
        'release_notes': notes,
      });

  Future<List<String>> posVersions() async {
    try {
      final res = await _api.get('getposversion', {
        'page': '1',
        'limit': '100',
      });
      final raw = res['data'];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => (e['version'] ?? '').toString())
            .where((v) => v.trim().isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<String?> versionReleaseNotes(String version) async {
    final value = version.trim();
    if (value.isEmpty) return null;
    try {
      final res = await _api.get('file_version_release_notes', {
        'version': value,
      });
      if (res['success'] != true) return null;
      return (res['notes'] ?? '').toString();
    } catch (_) {
      return null;
    }
  }

  Future<FileResult> updateCollectionType(
    String collectionId,
    String type, {
    String playStoreUrl = '',
  }) => _mutateJson('file_update_collection_type', {
    'id': collectionId,
    'collection_type': type,
    'play_store_url': type == 'distribution' ? playStoreUrl.trim() : '',
  });

  Future<({FileChecksum? checksum, String? error})> checksum(
    String fileId,
  ) async {
    try {
      final res = await _api.get('file_checksum', {'id': fileId});
      if (res['success'] != true) {
        return (
          checksum: null,
          error: (res['message'] ?? 'Could not compute the checksum.')
              .toString(),
        );
      }
      return (checksum: FileChecksum.fromJson(res), error: null);
    } catch (e) {
      return (checksum: null, error: _errorText(e));
    }
  }

  Future<({String? path, String? error})> download(
    StoredFile file, {
    void Function(int received, int total)? onProgress,
  }) async {
    final client = http.Client();
    try {
      final uri = Uri.parse(_api.actionUrl('file_download', {'id': file.id}));
      final request = http.Request('GET', uri)
        ..headers.addAll(_api.authHeaders());
      final response = await client.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await response.stream.bytesToString();
        return (path: null, error: _messageFrom(body) ?? 'Download failed.');
      }
      final type = (response.headers['content-type'] ?? '').toLowerCase();
      if (type.contains('json')) {
        final body = await response.stream.bytesToString();
        return (
          path: null,
          error: _messageFrom(body) ?? 'This file is no longer available.',
        );
      }
      io.Directory? dir;
      try {
        dir = await getDownloadsDirectory();
      } catch (_) {}
      dir ??= await getApplicationDocumentsDirectory();
      final safe = file.filename
          .split(RegExp(r'[\\/]'))
          .last
          .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
      final target = io.File(
        '${dir.path}${io.Platform.pathSeparator}'
        '${safe.isEmpty ? 'download' : safe}',
      );
      final sink = target.openWrite();
      final total = response.contentLength ?? file.fileSize;
      var received = 0;
      await response.stream
          .map((chunk) {
            received += chunk.length;
            onProgress?.call(received, total);
            return chunk;
          })
          .pipe(sink);
      return (path: target.path, error: null);
    } catch (e) {
      return (path: null, error: _errorText(e));
    } finally {
      client.close();
    }
  }

  Future<UploadOutcome> uploadFiles({
    required List<UploadCandidate> files,
    String collectionName = '',
    String email = '',
    String collectionType = 'default',
    String playStoreUrl = '',
    String? parentId,
    String? addToCollectionId,
    String? replaceCollectionId,
    String? installerCollectionId,
    bool installerStrict = false,
    String posVersion = '',
    String releaseNotes = '',
    void Function(UploadProgress)? onProgress,
    UploadCancelToken? cancelToken,
  }) async {
    if (files.isEmpty) {
      return UploadOutcome(ok: false, message: 'Pick at least one file.');
    }
    final token = cancelToken ?? UploadCancelToken();
    final client = http.Client();
    token.bind(client);

    final total = files.fold<int>(0, (sum, f) => sum + f.size);
    var chunkSize = math.min(await maxChunkBytes(), _chunkCeiling);

    try {
      for (;;) {
        if (token.isCancelled) return UploadOutcome(ok: false, cancelled: true);
        final uploadId = _randomHex(16);
        try {
          final manifest = await _sendAllChunks(
            client: client,
            token: token,
            uploadId: uploadId,
            files: files,
            chunkSize: chunkSize,
            total: total,
            onProgress: onProgress,
          );
          onProgress?.call(
            UploadProgress(
              phase: UploadPhase.finalizing,
              sent: total,
              total: total,
              note: 'Processing on the server…',
            ),
          );
          return await _finalize(
            client: client,
            uploadId: uploadId,
            manifest: manifest,
            collectionName: collectionName,
            email: email,
            collectionType: collectionType,
            playStoreUrl: playStoreUrl,
            parentId: parentId,
            addToCollectionId: addToCollectionId,
            replaceCollectionId: replaceCollectionId,
            installerCollectionId: installerCollectionId,
            installerStrict: installerStrict,
            posVersion: posVersion,
            releaseNotes: releaseNotes,
          );
        } on _ChunkFailure catch (err) {
          if (token.isCancelled || err.code == 'abort') {
            return UploadOutcome(ok: false, cancelled: true);
          }
          if (!err.worthShrinking || chunkSize <= _chunkFloor) {
            return UploadOutcome(ok: false, message: _chunkMessage(err));
          }
          chunkSize = math.max(_chunkFloor, chunkSize ~/ 4);
          onProgress?.call(
            UploadProgress(
              phase: UploadPhase.retrying,
              sent: 0,
              total: total,
              note:
                  'The server refused a piece — retrying with smaller '
                  '${humanFileSize(chunkSize)} pieces…',
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 1200));
        }
      }
    } catch (e) {
      if (token.isCancelled) return UploadOutcome(ok: false, cancelled: true);
      return UploadOutcome(ok: false, message: _errorText(e));
    } finally {
      client.close();
    }
  }

  Future<List<Map<String, dynamic>>> _sendAllChunks({
    required http.Client client,
    required UploadCancelToken token,
    required String uploadId,
    required List<UploadCandidate> files,
    required int chunkSize,
    required int total,
    void Function(UploadProgress)? onProgress,
  }) async {
    final manifest = <Map<String, dynamic>>[];
    var completed = 0;

    for (var index = 0; index < files.length; index++) {
      final candidate = files[index];
      final handle = await io.File(candidate.path).open();
      try {
        final size = candidate.size;
        final totalChunks = math.max(1, (size / chunkSize).ceil());
        for (var chunkIndex = 0; chunkIndex < totalChunks; chunkIndex++) {
          if (token.isCancelled) throw _ChunkFailure('abort');
          final start = chunkIndex * chunkSize;
          final length = math.min(chunkSize, size - start);
          await handle.setPosition(start);
          final bytes = await handle.read(length < 0 ? 0 : length);

          var attempt = 0;
          for (;;) {
            try {
              await _sendChunk(
                client: client,
                token: token,
                uploadId: uploadId,
                fileIndex: index,
                chunkIndex: chunkIndex,
                totalChunks: totalChunks,
                bytes: bytes,
              );
              break;
            } on _ChunkFailure catch (err) {
              if (err.code == 'abort' || err.code == '413') rethrow;
              if (++attempt >= 3) rethrow;
              await Future<void>.delayed(Duration(seconds: attempt));
            }
          }

          completed += bytes.length;
          onProgress?.call(
            UploadProgress(
              phase: UploadPhase.sending,
              sent: completed,
              total: total,
              note: files.length == 1
                  ? candidate.name
                  : '${candidate.name} (${index + 1}/${files.length})',
            ),
          );
        }
        manifest.add({
          'index': index,
          'name': candidate.name,
          'size': size,
          'total_chunks': totalChunks,
        });
      } finally {
        await handle.close();
      }
    }
    return manifest;
  }

  Future<void> _sendChunk({
    required http.Client client,
    required UploadCancelToken token,
    required String uploadId,
    required int fileIndex,
    required int chunkIndex,
    required int totalChunks,
    required List<int> bytes,
  }) async {
    final uri = Uri.parse(
      _api.actionUrl('file_upload_chunk', {
        'upload_id': uploadId,
        'file_index': '$fileIndex',
        'chunk_index': '$chunkIndex',
        'total_chunks': '$totalChunks',
        'chunk_bytes': '${bytes.length}',
      }),
    );
    final raw = Duration(seconds: 45 + (bytes.length / (16 * 1024)).ceil());
    final budget = raw > const Duration(minutes: 10)
        ? const Duration(minutes: 10)
        : raw;
    http.Response response;
    try {
      response = await client
          .post(
            uri,
            headers: {
              ..._api.authHeaders(),
              'Accept': 'application/json',
              'Content-Type': 'application/octet-stream',
            },
            body: bytes,
          )
          .timeout(budget);
    } on TimeoutException {
      throw _ChunkFailure('stall');
    } catch (_) {
      if (token.isCancelled) throw _ChunkFailure('abort');
      throw _ChunkFailure('network');
    }

    if (response.statusCode == 413) throw _ChunkFailure('413');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _ChunkFailure(
        'http',
        status: response.statusCode,
        message: _messageFrom(response.body),
      );
    }
    Map<String, dynamic> decoded;
    try {
      final value = jsonDecode(response.body.trim());
      decoded = value is Map
          ? Map<String, dynamic>.from(value)
          : <String, dynamic>{};
    } catch (_) {
      throw _ChunkFailure('parse', status: response.statusCode);
    }
    if (decoded['success'] != true) {
      throw _ChunkFailure(
        'server',
        message: decoded['message']?.toString(),
        serverCode: decoded['error_code']?.toString(),
      );
    }
  }

  Future<UploadOutcome> _finalize({
    required http.Client client,
    required String uploadId,
    required List<Map<String, dynamic>> manifest,
    required String collectionName,
    required String email,
    required String collectionType,
    required String playStoreUrl,
    required String? parentId,
    required String? addToCollectionId,
    required String? replaceCollectionId,
    required String? installerCollectionId,
    required bool installerStrict,
    required String posVersion,
    required String releaseNotes,
  }) async {
    final payload = <String, dynamic>{
      'upload_id': uploadId,
      'manifest': jsonEncode(manifest),
      'collection_name': collectionName,
      'email': email,
      'collection_type': collectionType,
    };
    if (collectionType == 'installer' && posVersion.trim().isNotEmpty) {
      payload['pos_version'] = posVersion.trim();
    }
    if (collectionType == 'installer' && releaseNotes.trim().isNotEmpty) {
      payload['release_notes'] = releaseNotes.trim();
    }
    if (collectionType == 'installer' &&
        (installerCollectionId ?? '').isNotEmpty) {
      payload['installer_collection_id'] = installerCollectionId;
    }
    if (installerStrict) {
      payload['installer_strict'] = '1';
    }
    if (collectionType != 'installer' &&
        (replaceCollectionId ?? '').isNotEmpty) {
      payload['replace_collection_id'] = replaceCollectionId;
    }
    if (collectionType == 'distribution' && playStoreUrl.trim().isNotEmpty) {
      payload['play_store_url'] = playStoreUrl.trim();
    }
    if ((addToCollectionId ?? '').isNotEmpty) {
      payload['add_to_collection_id'] = addToCollectionId;
    } else if ((parentId ?? '').isNotEmpty) {
      payload['parent_id'] = parentId;
    }

    http.Response response;
    try {
      response = await client
          .post(
            Uri.parse(_api.actionUrl('file_upload_finalize')),
            headers: {
              ..._api.authHeaders(),
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(minutes: 15));
    } on TimeoutException {
      return UploadOutcome(
        ok: false,
        message:
            'All pieces were sent, but the server took too long to assemble '
            'them. Check the collection before uploading again.',
      );
    } catch (_) {
      return UploadOutcome(
        ok: false,
        message:
            'All pieces were sent, but the connection dropped while the '
            'server was assembling them. Check the collection before '
            'uploading again.',
      );
    }

    Map<String, dynamic> res;
    try {
      final value = jsonDecode(response.body.trim());
      res = value is Map ? Map<String, dynamic>.from(value) : {};
    } catch (_) {
      return UploadOutcome(
        ok: false,
        message:
            'The server could not finish the upload '
            '(HTTP ${response.statusCode}).',
      );
    }
    if (res['success'] != true) {
      return UploadOutcome(
        ok: false,
        message: (res['message'] ?? 'Upload failed.').toString(),
      );
    }
    return UploadOutcome(
      ok: true,
      message: (res['message'] ?? 'Files uploaded successfully').toString(),
      collectionId: (res['collection_id'] ?? '').toString(),
      collectionType: (res['collection_type'] ?? '').toString(),
      shareToken: (res['share_token'] ?? '').toString(),
      expiresAt: (res['expires_at'] ?? '').toString(),
      permanentShareToken: (res['permanent_share_token'] ?? '').toString(),
      replaced: res['replaced'] == true,
      added: res['added'] == true,
    );
  }

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

  Future<ShareLink?> generateExpiringLink(String collectionId) async {
    try {
      final res = await _api.postJson(
        'generate_share_link',
        body: {'id': collectionId},
      );
      if (res['success'] != true) return null;
      final token = res['share_token']?.toString() ?? '';
      if (token.isEmpty) return null;
      return ShareLink(token: token, expiresAt: res['expires_at']?.toString());
    } catch (_) {
      return null;
    }
  }

  Future<String?> generatePermanentLink(String collectionId) async {
    try {
      final res = await _api.postJson(
        'generate_permanent_share_link',
        body: {'id': collectionId},
      );
      if (res['success'] != true) return null;
      final t = res['permanent_share_token']?.toString() ?? '';
      return t.isEmpty ? null : t;
    } catch (_) {
      return null;
    }
  }

  Future<FileResult> revokePermanentLink(String collectionId) =>
      _mutateJson('revoke_permanent_share_link', {'id': collectionId});

  String shareUrl(String token) => '${_api.baseUrl}/file-share.php#$token';

  Future<FileResult> _mutateJson(
    String action,
    Map<String, dynamic> body,
  ) async {
    try {
      final res = await _api.postJson(action, body: body);
      final ok = res['success'] == true || res['status'] == 'success';
      return FileResult(ok: ok, message: res['message']?.toString(), data: res);
    } catch (e) {
      return FileResult(ok: false, message: _errorText(e));
    }
  }

  String _chunkMessage(_ChunkFailure err) {
    switch (err.code) {
      case '413':
        return 'A piece of the upload was rejected (413). The chunk size is '
            'over a proxy limit — please contact the administrator.';
      case 'stall':
        return 'The upload stalled — no data moved for a while. Keep the app '
            'in the foreground and try again on a steadier connection.';
      case 'network':
        return 'The connection dropped while uploading. Please try again.';
      case 'http':
        return err.message ??
            'The server rejected a piece of the upload '
                '(HTTP ${err.status ?? '?'}).';
      case 'parse':
        return 'The server sent an unreadable response '
            '(HTTP ${err.status ?? '?'}).';
      default:
        return err.message ?? 'Upload failed.';
    }
  }

  String _randomHex(int byteLength) {
    final rnd = math.Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < byteLength; i++) {
      buffer.write(rnd.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  String? _messageFrom(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        final message = decoded['message'];
        if (message is String && message.trim().isNotEmpty) {
          return message.trim();
        }
      }
    } catch (_) {}
    return null;
  }

  String _errorText(Object error) {
    if (error is HttpException) return error.message;
    if (error is UploadTimeoutException) {
      return 'The request timed out. Please try again.';
    }
    return 'Network error';
  }
}
