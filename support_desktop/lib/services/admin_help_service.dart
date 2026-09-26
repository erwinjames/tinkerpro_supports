import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../api_client.dart';

class HelpCategoryNode {
  const HelpCategoryNode(this.slug, this.name, this.subs);
  final String slug;
  final String name;
  final List<HelpCategoryNode> subs;

  static HelpCategoryNode fromJson(Map m) => HelpCategoryNode(
    '${m['slug'] ?? ''}',
    '${m['name'] ?? ''}',
    [
      for (final s in (m['subcategories'] is List
          ? m['subcategories'] as List
          : const []))
        if (s is Map) HelpCategoryNode.fromJson(s),
    ],
  );
}

class HelpApiError implements Exception {
  HelpApiError(this.message);
  final String message;
  @override
  String toString() => message;
}

class HelpVideoLimits {
  const HelpVideoLimits(this.chunkBytes, this.maxBytes);
  final int chunkBytes;
  final int maxBytes;
}

class AdminHelpApi {
  AdminHelpApi(this.api);
  final ApiClient api;

  static const videoExtensions = ['mp4', 'm4v', 'mov', 'webm', 'ogg', 'ogv'];
  static const _chunkCeiling = 8 * 1024 * 1024;
  static const _chunkFallback = 1024 * 1024;
  static const _defaultMaxBytes = 300 * 1024 * 1024;
  HelpVideoLimits? _limits;

  Uri _uri(String action, [Map<String, String>? query]) =>
      Uri.parse('${api.baseUrl}/api.php').replace(
        queryParameters: {'action': action, ...?query},
      );

  Map<String, String> get _headers => {
    ...api.authHeaders(),
    'Accept': 'application/json',
  };

  Map<String, dynamic> _read(
    http.Response res, {
    String Function(int status)? emptyMessage,
  }) {
    final body = res.body.trim();
    if (body.isEmpty) {
      throw HelpApiError(
        emptyMessage?.call(res.statusCode) ??
            'The server returned an empty response (HTTP ${res.statusCode}). The save did not go through — check the server error log.',
      );
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      return {'data': decoded};
    } catch (_) {
      throw HelpApiError(
        'The server returned an unexpected response (HTTP ${res.statusCode}): ${body.length > 160 ? body.substring(0, 160) : body}',
      );
    }
  }

  Future<Map<String, dynamic>> _getJson(
    String action, [
    Map<String, String>? query,
  ]) async {
    final res = await http.get(_uri(action, query), headers: _headers);
    return _read(res);
  }

  Future<Map<String, dynamic>> _postJson(
    String action,
    Map<String, dynamic> body, {
    String Function(int status)? emptyMessage,
  }) async {
    final res = await http.post(
      _uri(action),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return _read(res, emptyMessage: emptyMessage);
  }

  Future<Map<String, dynamic>> _postForm(
    String action,
    Map<String, String> fields,
  ) async {
    final req = http.MultipartRequest('POST', _uri(action));
    req.headers.addAll(_headers);
    req.fields.addAll(fields);
    final res = await http.Response.fromStream(await req.send());
    return _read(res);
  }

  Future<List<HelpCategoryNode>> categories() async {
    final res = await _getJson('getHelpCategories');
    final data = res['data'];
    if (res['success'] == true && data is List && data.isNotEmpty) {
      return data.whereType<Map>().map(HelpCategoryNode.fromJson).toList();
    }
    return const [];
  }

  Future<List<Map<String, dynamic>>> topics() async {
    final res = await _getJson('getHelpTopics');
    if (res['success'] != true) {
      throw HelpApiError('Failed to load help topics');
    }
    final data = res['data'];
    return data is List
        ? data.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
        : <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> addCategory(
    String category,
    String subcategory,
    String subsubcategory,
  ) => _postJson('addHelpCategory', {
    'category': category,
    'subcategory': subcategory,
    'subsubcategory': subsubcategory,
  });

  Future<Map<String, dynamic>> deleteSubcategory(
    String category,
    String subcategory,
    String subsubcategory,
  ) => _postJson('deleteHelpSubcategory', {
    'category': category,
    'subcategory': subcategory,
    'subsubcategory': subsubcategory,
  });

  Future<Map<String, dynamic>> reorder(List<int> ids) => _postJson(
    'reorderHelpTopics',
    {
      'topics': [
        for (final id in ids) {'id': id},
      ],
    },
  );

  Future<Map<String, dynamic>> document(int topicId) =>
      _getJson('desktopHelpDocument', {'topic_id': '$topicId'});

  Future<String> summary(String html) async {
    final res = await _postJson('desktopHelpSummary', {'html': html});
    return '${res['description'] ?? ''}';
  }

  Future<Map<String, dynamic>> addTopic(Map<String, dynamic> payload) =>
      _postJson(
        'addHelpTopic',
        payload,
        emptyMessage: (status) =>
            'The server returned an empty response (HTTP $status). The topic was not saved — check the server error log.',
      );

  Future<Map<String, dynamic>> updateTopic(Map<String, String> fields) =>
      _postForm('updateHelpTopic', fields);

  Future<Map<String, dynamic>> saveContent(int topicId, String html) =>
      _postForm('saveHelpContent', {
        'topic_id': '$topicId',
        'content[0][content_type]': 'text',
        'content[0][text_content]': html,
        'content[0][sort_order]': '0',
      });

  Future<Map<String, dynamic>> deleteTopic(int id) =>
      _postForm('deleteHelpTopic', {'id': '$id'});

  Future<Map<String, dynamic>> videoLink(String url, {int width = 720}) =>
      _postJson('desktopHelpVideoLink', {'url': url, 'width': width});

  Future<HelpVideoLimits> videoLimits() async {
    if (_limits != null) return _limits!;
    try {
      final res = await _getJson('helpVideoUploadLimits');
      final chunk = res['success'] == true
          ? int.tryParse('${res['max_chunk_bytes']}') ?? 0
          : 0;
      final max = int.tryParse('${res['max_video_bytes']}') ?? 0;
      _limits = HelpVideoLimits(
        chunk > 0 ? min(chunk, _chunkCeiling) : _chunkFallback,
        max > 0 ? max : _defaultMaxBytes,
      );
    } catch (_) {
      _limits = const HelpVideoLimits(_chunkFallback, _defaultMaxBytes);
    }
    return _limits!;
  }

  static String formatBytes(int n) {
    if (n >= 1048576) return '${(n / 1048576).round()} MB';
    if (n >= 1024) return '${(n / 1024).round()} KB';
    return '$n B';
  }

  static String extensionOf(String name) {
    final m = RegExp(r'\.([a-z0-9]+)(?:$|\?)').firstMatch(name.toLowerCase());
    return m?.group(1) ?? '';
  }

  static String _randomHex(int bytes) {
    final r = Random.secure();
    return List.generate(
      bytes,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<Map<String, dynamic>> uploadVideo(
    File file,
    String name,
    void Function(int pct) onProgress,
  ) async {
    final cfg = await videoLimits();
    final size = await file.length();
    if (size > cfg.maxBytes) {
      throw HelpApiError(
        '"$name" is ${formatBytes(size)}. The limit is ${formatBytes(cfg.maxBytes)}.',
      );
    }
    if (!videoExtensions.contains(extensionOf(name))) {
      throw HelpApiError(
        'Unsupported video type. Use ${videoExtensions.join(', ')}.',
      );
    }
    final uploadId = _randomHex(16);
    final totalChunks = max(1, (size / cfg.chunkBytes).ceil());
    var sent = 0;
    final raf = await file.open();
    try {
      for (var i = 0; i < totalChunks; i++) {
        final start = i * cfg.chunkBytes;
        await raf.setPosition(start);
        final Uint8List buffer;
        try {
          buffer = await raf.read(min(cfg.chunkBytes, size - start));
        } catch (_) {
          throw HelpApiError('Could not read the video file from this device.');
        }
        final http.Response res;
        try {
          res = await http.post(
            _uri('helpVideoUploadChunk', {
              'upload_id': uploadId,
              'chunk_index': '$i',
              'total_chunks': '$totalChunks',
              'chunk_bytes': '${buffer.length}',
            }),
            headers: {
              ..._headers,
              'Content-Type': 'application/octet-stream',
            },
            body: buffer,
          );
        } catch (_) {
          throw HelpApiError('The connection dropped while uploading the video.');
        }
        if (res.statusCode == 413) {
          throw HelpApiError(
            'The server rejected the upload chunk as too large (413).',
          );
        }
        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw HelpApiError('Upload failed (HTTP ${res.statusCode}).');
        }
        Map<String, dynamic> body;
        try {
          body = jsonDecode(res.body) as Map<String, dynamic>;
        } catch (_) {
          throw HelpApiError(
            'The server sent an unreadable response while uploading.',
          );
        }
        if (body['success'] != true) {
          throw HelpApiError('${body['message'] ?? 'Upload failed.'}');
        }
        sent += buffer.length;
        onProgress(min(99, (sent / size * 100).round()));
      }
    } finally {
      await raf.close();
    }
    final res = await http.post(
      _uri('helpVideoUploadFinish'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'upload_id': uploadId,
        'total_chunks': totalChunks,
        'filename': name,
      }),
    );
    Map<String, dynamic> body;
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw HelpApiError(
        'The server could not finish the upload (HTTP ${res.statusCode}).',
      );
    }
    if (body['success'] != true) {
      throw HelpApiError(
        '${body['message'] ?? 'The server could not save the video.'}',
      );
    }
    onProgress(100);
    return body;
  }
}
