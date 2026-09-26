import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../api_client.dart';

typedef FmRow = Map<String, dynamic>;

String fmSize(dynamic raw) {
  final bytes = raw is num ? raw.toInt() : int.tryParse('$raw') ?? 0;
  if (bytes <= 0) return '0 B';
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  var i = (log(bytes) / log(1024)).floor();
  if (i > sizes.length - 1) i = sizes.length - 1;
  final v = bytes / pow(1024, i);
  var s = v.toStringAsFixed(1);
  if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
  return '$s ${sizes[i]}';
}

class FmError implements Exception {
  FmError(this.code, {this.message, this.status, this.body, this.serverCode});
  final Object code;
  final String? message;
  final int? status;
  final String? body;
  final String? serverCode;
  String? at;
}

class FmPickedFile {
  FmPickedFile(this.path, this.name, this.size);
  final String path;
  final String name;
  final int size;
}

class FmUploadMeta {
  FmUploadMeta({
    required this.name,
    required this.email,
    required this.collectionType,
    this.posVersion = '',
    this.releaseNotes = '',
    this.installerStrict = false,
    this.playStoreUrl = '',
    this.installerId = '',
    this.replaceId = '',
    this.addToId = '',
    this.parentId = '',
  });
  final String name;
  final String email;
  final String collectionType;
  final String posVersion;
  final String releaseNotes;
  final bool installerStrict;
  final String playStoreUrl;
  final String installerId;
  final String replaceId;
  final String addToId;
  final String parentId;
}

class AdminFilesApi {
  AdminFilesApi(this.api);
  final ApiClient api;

  static const chunkCeiling = 20 * 1024 * 1024;
  static const chunkFallback = 2 * 1024 * 1024;
  static const minChunk = 256 * 1024;
  static const sendStall = Duration(seconds: 45);
  static const replyStall = Duration(seconds: 180);
  static const finalizeTimeout = Duration(minutes: 15);

  Uri _uri(String action, [Map<String, String>? q]) => Uri.parse(
    '${api.baseUrl}/api.php',
  ).replace(queryParameters: {'action': action, ...?q});

  Map<String, dynamic> _decode(http.Response r) {
    try {
      final d = jsonDecode(r.body);
      if (d is Map) return Map<String, dynamic>.from(d);
    } catch (_) {}
    return {
      'success': false,
      'message': 'HTTP ${r.statusCode}',
      '_http': r.statusCode,
    };
  }

  Future<Map<String, dynamic>> getJ(
    String action, [
    Map<String, String>? q,
  ]) async {
    final r = await http.get(
      _uri(action, {...?q, '_': '${DateTime.now().millisecondsSinceEpoch}'}),
      headers: {...api.authHeaders(), 'Accept': 'application/json'},
    );
    return _decode(r);
  }

  Future<Map<String, dynamic>> postJ(
    String action,
    Map<String, dynamic> body,
  ) async {
    final r = await http.post(
      _uri(action),
      headers: {
        ...api.authHeaders(),
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    return _decode(r);
  }

  String shareUrl(String token) => '${api.baseUrl}/file-share.php#$token';
  String downloadUrl(String fileId) =>
      api.actionUrl('file_download', {'id': fileId});

  Future<Map<String, dynamic>> pageMeta() => getJ('desktopFilesPageMeta');
  Future<Map<String, dynamic>> listCollections() =>
      getJ('file_list_collections');
  Future<Map<String, dynamic>> storageUsage() => getJ('file_storage_usage');
  Future<Map<String, dynamic>> collectionFiles(String id) =>
      getJ('file_collection_files', {'id': id});
  Future<Map<String, dynamic>> versionReleaseNotes(String version) =>
      getJ('file_version_release_notes', {'version': version});
  Future<Map<String, dynamic>> checksum(String fileId) =>
      getJ('file_checksum', {'id': fileId});
  Future<Map<String, dynamic>> getShareLink(String id) =>
      getJ('get_share_link', {'id': id});

  Future<Map<String, dynamic>> createFolder(String name, String? parentId) =>
      postJ('file_create_folder', {'name': name, 'parent_id': parentId});
  Future<Map<String, dynamic>> rename(String id, String name) =>
      postJ('file_rename_collection', {'id': id, 'name': name});
  Future<Map<String, dynamic>> move(String id, String? parentId) =>
      postJ('file_move_collection', {'id': id, 'parent_id': parentId});
  Future<Map<String, dynamic>> toggleFavorite(String id, bool favorite) =>
      postJ('file_toggle_favorite', {'id': id, 'favorite': favorite});
  Future<Map<String, dynamic>> setVendorVisible(String id, bool v) => postJ(
    'file_set_vendor_visible',
    {'collection_id': id, 'vendor_visible': v ? 1 : 0},
  );
  Future<Map<String, dynamic>> setOjtVisible(String id, bool v) => postJ(
    'file_set_ojt_visible',
    {'collection_id': id, 'ojt_visible': v ? 1 : 0},
  );
  Future<Map<String, dynamic>> setReleaseNotes(String id, String notes) =>
      postJ('file_set_release_notes', {'id': id, 'release_notes': notes});
  Future<Map<String, dynamic>> updateType(
    String id,
    String type,
    String playStoreUrl,
  ) => postJ('file_update_collection_type', {
    'id': id,
    'collection_type': type,
    'play_store_url': playStoreUrl,
  });
  Future<Map<String, dynamic>> deleteCollection(String id) =>
      postJ('file_delete_collection', {'id': id});
  Future<Map<String, dynamic>> deleteItem(String id) =>
      postJ('file_delete_item', {'id': id});
  Future<Map<String, dynamic>> generateShareLink(String id) =>
      postJ('generate_share_link', {'id': id});
  Future<Map<String, dynamic>> generatePermanent(String id) =>
      postJ('generate_permanent_share_link', {'id': id});
  Future<Map<String, dynamic>> revokePermanent(String id) =>
      postJ('revoke_permanent_share_link', {'id': id});
  Future<Map<String, dynamic>> installerName({
    required String name,
    required String posVersion,
    required String firstFileName,
  }) => postJ('desktopFilesInstallerName', {
    'name': name,
    'pos_version': posVersion,
    'first_file_name': firstFileName,
  });
}

String fmServerSnippet(String? text) {
  if (text == null || text.isEmpty) return '';
  final stripped = text
      .replaceAll(
        RegExp(r'<script[\s\S]*?</script>', caseSensitive: false),
        ' ',
      )
      .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return stripped.length > 180 ? '${stripped.substring(0, 180)}…' : stripped;
}

class FmChunkedUpload {
  FmChunkedUpload(this.files_, this.meta);
  final AdminFilesApi files_;
  final FmUploadMeta meta;

  int chunkSize = AdminFilesApi.chunkCeiling;
  bool _cancelled = false;
  http.Client? _client;
  void Function(String label)? onLabel;
  void Function(int loaded)? onProgress;
  void Function()? onFinalizing;
  void Function()? onRetrying;

  void cancel() {
    _cancelled = true;
    _client?.close();
  }

  static String randomHex(int byteLen) {
    final r = Random.secure();
    return List.generate(
      byteLen,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<void> resolveChunkSize() async {
    try {
      final res = await files_.getJ('file_upload_limits');
      final n = res['success'] == true
          ? int.tryParse('${res['max_chunk_bytes']}')
          : null;
      chunkSize = (n != null && n > 0)
          ? min(n, AdminFilesApi.chunkCeiling)
          : AdminFilesApi.chunkFallback;
    } catch (_) {
      chunkSize = AdminFilesApi.chunkFallback;
    }
  }

  Future<Map<String, dynamic>> _uploadChunk({
    required String uploadId,
    required int fileIndex,
    required int chunkIndex,
    required int totalChunks,
    required Uint8List body,
  }) async {
    final api = files_.api;
    final uri = Uri.parse('${api.baseUrl}/api.php').replace(
      queryParameters: {
        'action': 'file_upload_chunk',
        'upload_id': uploadId,
        'file_index': '$fileIndex',
        'chunk_index': '$chunkIndex',
        'total_chunks': '$totalChunks',
        'chunk_bytes': '${body.length}',
      },
    );
    final client = http.Client();
    _client = client;
    try {
      final req = http.Request('POST', uri)
        ..headers.addAll({
          ...api.authHeaders(),
          'Content-Type': 'application/octet-stream',
        })
        ..bodyBytes = body;
      final streamed = await client
          .send(req)
          .timeout(AdminFilesApi.sendStall + AdminFilesApi.replyStall);
      final resp = await http.Response.fromStream(
        streamed,
      ).timeout(AdminFilesApi.replyStall);
      if (resp.statusCode == 413) throw FmError(413);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw FmError(
          'http',
          status: resp.statusCode,
          body: fmServerSnippet(resp.body),
        );
      }
      Map<String, dynamic> res;
      try {
        res = Map<String, dynamic>.from(jsonDecode(resp.body) as Map);
      } catch (_) {
        throw FmError(
          'parse',
          status: resp.statusCode,
          body: fmServerSnippet(resp.body),
        );
      }
      if (res['success'] != true) {
        throw FmError(
          'server',
          message: res['message']?.toString(),
          serverCode: res['error_code']?.toString(),
        );
      }
      return res;
    } on FmError {
      rethrow;
    } on TimeoutException {
      throw FmError(_cancelled ? 'abort' : 'stall');
    } catch (_) {
      throw FmError(_cancelled ? 'abort' : 'network');
    } finally {
      client.close();
      if (identical(_client, client)) _client = null;
    }
  }

  Future<List<Map<String, dynamic>>> _sendAll(
    List<FmPickedFile> files,
    String sessionId,
    int size,
  ) async {
    var completed = 0;
    final manifest = <Map<String, dynamic>>[];
    for (var fi = 0; fi < files.length; fi++) {
      final file = files[fi];
      final totalChunks = max(1, (file.size / size).ceil());
      final raf = await File(file.path).open();
      try {
        for (var ci = 0; ci < totalChunks; ci++) {
          if (_cancelled) throw FmError('abort');
          final start = ci * size;
          final len = min(start + size, file.size) - start;
          Uint8List body;
          try {
            await raf.setPosition(start);
            body = await raf.read(len);
          } catch (_) {
            throw FmError(
              'read',
              message: 'Could not read this file from the device.',
            );
          }
          var attempt = 0;
          for (;;) {
            try {
              await _uploadChunk(
                uploadId: sessionId,
                fileIndex: fi,
                chunkIndex: ci,
                totalChunks: totalChunks,
                body: body,
              );
              break;
            } on FmError catch (err) {
              if (err.code == 'abort' || err.code == 413) {
                err.at = 'chunk ${ci + 1} of $totalChunks';
                rethrow;
              }
              if (++attempt >= 3) {
                err.at =
                    'chunk ${ci + 1} of $totalChunks (${fmSize(body.length)})';
                rethrow;
              }
              await Future<void>.delayed(
                Duration(milliseconds: 1000 * attempt),
              );
            }
          }
          completed += body.length;
          onProgress?.call(completed);
        }
      } finally {
        await raf.close();
      }
      manifest.add({
        'index': fi,
        'name': file.name,
        'size': file.size,
        'total_chunks': totalChunks,
      });
    }
    return manifest;
  }

  Future<Map<String, dynamic>> _finalize(
    String uploadId,
    List<Map<String, dynamic>> manifest,
  ) async {
    final payload = <String, dynamic>{
      'upload_id': uploadId,
      'manifest': jsonEncode(manifest),
      'collection_name': meta.name,
      'email': meta.email,
      'collection_type': meta.collectionType,
    };
    if (meta.collectionType == 'installer' && meta.installerId.isNotEmpty) {
      payload['installer_collection_id'] = meta.installerId;
    }
    if (meta.collectionType == 'installer' && meta.posVersion.isNotEmpty) {
      payload['pos_version'] = meta.posVersion;
    }
    if (meta.collectionType == 'installer' && meta.releaseNotes.isNotEmpty) {
      payload['release_notes'] = meta.releaseNotes;
    }
    if (meta.installerStrict) payload['installer_strict'] = '1';
    if (meta.replaceId.isNotEmpty) {
      payload['replace_collection_id'] = meta.replaceId;
    }
    if (meta.collectionType == 'distribution' && meta.playStoreUrl.isNotEmpty) {
      payload['play_store_url'] = meta.playStoreUrl;
    }
    if (meta.addToId.isNotEmpty) {
      payload['add_to_collection_id'] = meta.addToId;
    } else if (meta.parentId.isNotEmpty) {
      payload['parent_id'] = meta.parentId;
    }
    final api = files_.api;
    http.Response r;
    try {
      r = await http
          .post(
            Uri.parse(
              '${api.baseUrl}/api.php',
            ).replace(queryParameters: {'action': 'file_upload_finalize'}),
            headers: {...api.authHeaders(), 'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(AdminFilesApi.finalizeTimeout);
    } catch (_) {
      throw FmError(
        'finalize-network',
        message:
            'All chunks uploaded, but the connection dropped while the server was '
            'assembling them. This is usually a proxy or PHP timeout on the final step.',
      );
    }
    try {
      return Map<String, dynamic>.from(jsonDecode(r.body) as Map);
    } catch (_) {
      final snip = fmServerSnippet(r.body);
      throw FmError(
        'server',
        message:
            'The server could not finish the upload (HTTP ${r.statusCode})'
            '${snip.isNotEmpty ? ': $snip' : '.'}',
      );
    }
  }

  Future<Map<String, dynamic>> run(List<FmPickedFile> files) async {
    await resolveChunkSize();
    for (;;) {
      final sessionId = randomHex(16);
      try {
        final manifest = await _sendAll(files, sessionId, chunkSize);
        onFinalizing?.call();
        return await _finalize(sessionId, manifest);
      } on FmError catch (err) {
        final code = err.code;
        final worth =
            code == 'network' ||
            code == 413 ||
            code == 'http' ||
            code == 'parse' ||
            code == 'stall' ||
            err.serverCode == 'body_missing' ||
            err.serverCode == 'body_truncated';
        if (code == 'abort' || !worth || chunkSize <= AdminFilesApi.minChunk) {
          rethrow;
        }
        chunkSize = max(AdminFilesApi.minChunk, (chunkSize / 4).floor());
        onRetrying?.call();
        onLabel?.call(
          '${code == 'stall' ? 'Upload stalled at ' : 'Upload was refused at '}'
          '${err.at ?? 'a chunk'} — retrying with smaller ${fmSize(chunkSize)} pieces...',
        );
        onProgress?.call(0);
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      }
    }
  }

  String errorMessage(Object err) {
    if (err is! FmError) {
      return 'Upload failed at an unknown point — the connection dropped even at '
          '${fmSize(chunkSize)} chunks. Check the server error log; this is a network or proxy fault, not the file.';
    }
    switch (err.code) {
      case 'abort':
        return 'Upload cancelled';
      case 413:
        return 'A chunk was rejected (413). The chunk size exceeds a proxy limit — please contact the administrator.';
      case 'stall':
        return 'Upload stalled at ${err.at ?? 'a chunk'} — no data moved for '
            '${AdminFilesApi.sendStall.inSeconds}s even at ${fmSize(chunkSize)} pieces. '
            'Keep this window open, then try again.';
      case 'read':
        return err.message ?? 'Could not read this file from the device.';
      case 'server':
        return err.message ?? 'Server rejected the upload.';
      case 'finalize-network':
        return err.message ?? '';
      case 'http':
        return 'The server rejected a chunk (HTTP ${err.status})'
            '${(err.body ?? '').isNotEmpty ? ': ${err.body}' : '.'}';
      case 'parse':
        return 'The server sent an unreadable response (HTTP ${err.status})'
            '${(err.body ?? '').isNotEmpty ? ': ${err.body}' : '.'}';
    }
    return 'Upload failed at ${err.at ?? 'an unknown point'} — the connection dropped even at '
        '${fmSize(chunkSize)} chunks. Check the server error log; this is a network or proxy fault, not the file.';
  }
}
