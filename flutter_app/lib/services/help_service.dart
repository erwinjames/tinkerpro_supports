import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../api_client.dart';
import '../models/help_models.dart';

class HelpResult {
  HelpResult({required this.ok, this.message});
  final bool ok;
  final String? message;
}

class HelpCategoryRef {
  const HelpCategoryRef({required this.slug, required this.name});
  final String slug;
  final String name;

  static HelpCategoryRef? fromJson(Object? raw) {
    if (raw is Map) {
      final slug = (raw['slug'] ?? '').toString();
      if (slug.isNotEmpty) {
        final name = (raw['name'] ?? '').toString();
        return HelpCategoryRef(slug: slug, name: name.isEmpty ? slug : name);
      }
    }
    return null;
  }
}

class HelpCategoryResult {
  HelpCategoryResult({
    required this.ok,
    this.message,
    this.category,
    this.subcategory,
    this.subsubcategory,
    this.topicsUpdated = 0,
  });

  final bool ok;
  final String? message;
  final HelpCategoryRef? category;
  final HelpCategoryRef? subcategory;
  final HelpCategoryRef? subsubcategory;
  final int topicsUpdated;
}

class HelpContentResult {
  HelpContentResult({required this.ok, this.html = '', this.message});
  final bool ok;
  final String html;
  final String? message;
}

class HelpUploadResult {
  HelpUploadResult({required this.ok, this.url = '', this.message});
  final bool ok;
  final String url;
  final String? message;
}

class HelpVideoLimits {
  const HelpVideoLimits({required this.chunkBytes, required this.maxBytes});
  final int chunkBytes;
  final int maxBytes;

  static const HelpVideoLimits fallback = HelpVideoLimits(
    chunkBytes: 1024 * 1024,
    maxBytes: 300 * 1024 * 1024,
  );
}

const List<String> kHelpVideoExtensions = [
  'mp4',
  'm4v',
  'mov',
  'webm',
  'ogg',
  'ogv',
];

const List<String> kHelpImageExtensions = ['png', 'jpg', 'jpeg', 'gif', 'webp'];

class HelpService {
  HelpService(this._api);
  final ApiClient _api;

  static const int _chunkCeiling = 8 * 1024 * 1024;

  HelpVideoLimits? _videoLimits;

  String get baseUrl => _api.baseUrl;

  Map<String, String> get mediaHeaders => _api.authHeaders();

  Future<List<HelpTopic>> list() async {
    try {
      final res = await _api.get('getHelpTopics');
      final raw = res['data'];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => HelpTopic.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<HelpCategoryTree> categories() async {
    try {
      final res = await _api.get('getHelpCategories');
      final raw = res['data'];
      if (res['success'] == true && raw is List && raw.isNotEmpty) {
        final systems = raw
            .whereType<Map>()
            .map((e) => HelpCategoryNode.fromJson(Map<String, dynamic>.from(e)))
            .where((n) => n.slug.isNotEmpty)
            .toList();
        if (systems.isNotEmpty) return HelpCategoryTree(systems);
      }
    } catch (_) {}
    return const HelpCategoryTree.fallback();
  }

  Future<HelpCategoryResult> addCategory({
    required String category,
    String subcategory = '',
    String subsubcategory = '',
  }) async {
    try {
      final res = await _api.postJson(
        'addHelpCategory',
        body: {
          'category': category.trim(),
          'subcategory': subcategory.trim(),
          'subsubcategory': subsubcategory.trim(),
        },
      );
      return HelpCategoryResult(
        ok: res['success'] == true,
        message: res['message']?.toString(),
        category: HelpCategoryRef.fromJson(res['category']),
        subcategory: HelpCategoryRef.fromJson(res['subcategory']),
        subsubcategory: HelpCategoryRef.fromJson(res['subsubcategory']),
      );
    } catch (_) {
      return HelpCategoryResult(ok: false, message: 'Error saving category');
    }
  }

  Future<HelpCategoryResult> deleteSubcategory({
    required String category,
    required String subcategory,
    String subsubcategory = '',
  }) async {
    final deep = subsubcategory.trim().isNotEmpty;
    try {
      final res = await _api.postJson(
        'deleteHelpSubcategory',
        body: {
          'category': category.trim(),
          'subcategory': subcategory.trim(),
          'subsubcategory': subsubcategory.trim(),
        },
      );
      return HelpCategoryResult(
        ok: res['success'] == true,
        message: res['message']?.toString(),
        subcategory: HelpCategoryRef.fromJson(res['subcategory']),
        topicsUpdated: _asCount(res['topics_updated']),
      );
    } catch (_) {
      return HelpCategoryResult(
        ok: false,
        message: deep
            ? 'Error deleting the subcategory'
            : 'Error deleting the category',
      );
    }
  }

  Future<HelpResult> add({
    required String title,
    required String description,
    required String icon,
    required String iconColor,
    String subtitle = '',
    String contentHtml = '',
    String category = kDefaultHelpSystem,
    String subcategory = '',
    String subsubcategory = '',
  }) async {
    final html = contentHtml.trim();
    try {
      final res = await _api.postJson(
        'addHelpTopic',
        body: {
          'title': title.trim(),
          'subtitle': subtitle.trim(),
          'description': description.trim(),
          'icon': icon,
          'iconColor': iconColor,
          'category': category.isEmpty ? kDefaultHelpSystem : category,
          'subcategory': subcategory,
          'subsubcategory': subsubcategory,
          if (html.isNotEmpty)
            'ordered': [
              {'type': 'text', 'content': html},
            ],
        },
      );
      return _resultOf(res);
    } catch (_) {
      return HelpResult(ok: false, message: 'Network error');
    }
  }

  Future<HelpResult> update({
    required int id,
    required String title,
    String? description,
    required String icon,
    required String iconColor,
    String? subtitle,
    String? category,
    String? subcategory,
    String? subsubcategory,
  }) async {
    return _formMutate('updateHelpTopic', {
      'id': '$id',
      'title': title.trim(),
      if (description != null) 'description': description.trim(),
      if (subtitle != null) 'subtitle': subtitle.trim(),
      'icon': icon,
      'iconColor': iconColor,
      if (category != null)
        'category': category.isEmpty ? kDefaultHelpSystem : category,
      'subcategory': ?subcategory,
      'subsubcategory': ?subsubcategory,
    });
  }

  Future<HelpContentResult> content(int topicId) async {
    try {
      final res = await _api.get('getHelpContent', {'topic_id': '$topicId'});
      if (res['success'] != true) {
        return HelpContentResult(
          ok: false,
          message: res['message']?.toString() ?? 'Could not load the content.',
        );
      }
      final raw = res['data'];
      return HelpContentResult(
        ok: true,
        html: _composeContent(raw is List ? raw : const []),
      );
    } catch (_) {
      return HelpContentResult(
        ok: false,
        message: 'Could not load the content.',
      );
    }
  }

  Future<HelpResult> saveContent({
    required int topicId,
    required String html,
  }) => _formMutate('saveHelpContent', {
    'topic_id': '$topicId',
    'content[0][content_type]': 'text',
    'content[0][text_content]': html,
    'content[0][sort_order]': '0',
  });

  String _composeContent(List<Object?> items) {
    final parts = <String>[];
    for (final item in items) {
      if (item is! Map) continue;
      final type = (item['content_type'] ?? 'text').toString();
      final text = (item['text_content'] ?? '').toString();
      final image = (item['image_path'] ?? '').toString();
      final buffer = StringBuffer();
      if ((type == 'text' || type == 'text_and_image') && text.isNotEmpty) {
        buffer.write(text);
      }
      if ((type == 'image' || type == 'text_and_image') && image.isNotEmpty) {
        buffer.write('<p><img src="$baseUrl/uploads/help/$image" alt=""></p>');
      }
      if (buffer.isNotEmpty) parts.add(buffer.toString());
    }
    return parts.join('<p></p>');
  }

  Future<HelpVideoLimits> videoLimits() async {
    final cached = _videoLimits;
    if (cached != null) return cached;
    try {
      final res = await _api.get('helpVideoUploadLimits');
      if (res['success'] == true) {
        final chunk = _asCount(res['max_chunk_bytes']);
        final maxBytes = _asCount(res['max_video_bytes']);
        final limits = HelpVideoLimits(
          chunkBytes: chunk > 0
              ? min(chunk, _chunkCeiling)
              : HelpVideoLimits.fallback.chunkBytes,
          maxBytes: maxBytes > 0 ? maxBytes : HelpVideoLimits.fallback.maxBytes,
        );
        _videoLimits = limits;
        return limits;
      }
    } catch (_) {}
    return HelpVideoLimits.fallback;
  }

  Future<HelpUploadResult> uploadVideo(
    String path,
    String name, {
    void Function(double progress)? onProgress,
  }) async {
    final ext = helpFileExtension(name);
    if (!kHelpVideoExtensions.contains(ext)) {
      return HelpUploadResult(
        ok: false,
        message:
            'Unsupported video type. Use ${kHelpVideoExtensions.join(', ')}.',
      );
    }

    final file = File(path);
    final int size;
    try {
      size = await file.length();
    } catch (_) {
      return HelpUploadResult(
        ok: false,
        message: 'Could not read the video file from this device.',
      );
    }
    if (size <= 0) {
      return HelpUploadResult(ok: false, message: 'That video file is empty.');
    }

    final limits = await videoLimits();
    if (size > limits.maxBytes) {
      return HelpUploadResult(
        ok: false,
        message:
            '"$name" is ${helpFormatBytes(size)}. '
            'The limit is ${helpFormatBytes(limits.maxBytes)}.',
      );
    }

    final uploadId = _randomHex(16);
    final totalChunks = max(1, (size / limits.chunkBytes).ceil());

    try {
      final handle = await file.open();
      try {
        for (var index = 0; index < totalChunks; index++) {
          final start = index * limits.chunkBytes;
          final length = min(limits.chunkBytes, size - start);
          await handle.setPosition(start);
          final bytes = await handle.read(length);
          final res = await _api.postBytes(
            'helpVideoUploadChunk',
            bytes: bytes,
            query: {
              'upload_id': uploadId,
              'chunk_index': '$index',
              'total_chunks': '$totalChunks',
              'chunk_bytes': '${bytes.length}',
            },
          );
          if (res['success'] != true) {
            return HelpUploadResult(
              ok: false,
              message:
                  res['message']?.toString() ??
                  'The server rejected chunk $index.',
            );
          }
          onProgress?.call(min(0.99, (start + length) / size));
        }
      } finally {
        await handle.close();
      }

      final done = await _api.postJson(
        'helpVideoUploadFinish',
        body: {
          'upload_id': uploadId,
          'total_chunks': totalChunks,
          'filename': name,
        },
      );
      if (done['success'] != true) {
        return HelpUploadResult(
          ok: false,
          message:
              done['message']?.toString() ??
              'The server could not save the video.',
        );
      }
      onProgress?.call(1);
      return HelpUploadResult(ok: true, url: (done['url'] ?? '').toString());
    } on UploadTimeoutException catch (e) {
      return HelpUploadResult(ok: false, message: e.toString());
    } catch (_) {
      return HelpUploadResult(
        ok: false,
        message: 'The connection dropped while uploading the video.',
      );
    }
  }

  String _randomHex(int byteLength) {
    final rand = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < byteLength; i++) {
      buffer.write(rand.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  Future<HelpResult> delete(int id) =>
      _formMutate('deleteHelpTopic', {'id': '$id'});

  Future<HelpResult> _formMutate(
    String action,
    Map<String, String> body,
  ) async {
    try {
      final res = await _api.post(action, body: body);
      return _resultOf(res);
    } catch (_) {
      return HelpResult(ok: false, message: 'Network error');
    }
  }

  int _asCount(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  HelpResult _resultOf(Map<String, dynamic> res) {
    final ok = res['success'] == true || res['status'] == 'success';
    return HelpResult(ok: ok, message: res['message']?.toString());
  }
}

String helpFileExtension(String name) {
  final match = RegExp(
    r'\.([a-z0-9]+)(?:$|\?)',
  ).firstMatch(name.toLowerCase().trim());
  return match == null ? '' : match.group(1)!;
}

String helpFormatBytes(int bytes) {
  if (bytes >= 1048576) return '${(bytes / 1048576).round()} MB';
  if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
  return '$bytes B';
}
