import 'dart:convert';
import 'dart:io' as io;

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../api_client.dart';
import '../models/bir_v1_models.dart';

class BirV1Exception implements Exception {
  BirV1Exception(this.message, [this.details = const <String, String>{}]);

  final String message;
  final Map<String, String> details;

  String get fullMessage {
    if (details.isEmpty) return message;
    final lines = details.entries
        .map((e) => '${birV1Humanize(e.key)}: ${e.value}')
        .join('\n');
    return '$message\n\n$lines';
  }

  @override
  String toString() => fullMessage;
}

class BirV1Service {
  BirV1Service(this.api);

  final ApiClient api;

  static const String endpoint = 'bir-v1.php';

  bool get canAccess => api.canAccess('customer', 'customer');

  Uri uriFor(String path, [Map<String, String>? extra]) =>
      api.pathUri(endpoint, <String, String>{'path': path, ...?extra});

  Future<BirV1Page> list({
    String search = '',
    String status = '',
    int page = 1,
    int limit = 30,
    String sort = '',
    String order = '',
  }) async {
    final json = await _get('registrations', <String, String>{
      'page': '${page < 1 ? 1 : page}',
      'limit': '${limit < 1 ? 1 : (limit > 100 ? 100 : limit)}',
      if (search.trim().isNotEmpty) 'search': search.trim(),
      if (status.trim().isNotEmpty) 'status': status.trim(),
      if (sort.isNotEmpty) 'sort': sort,
      if (order.isNotEmpty) 'order': order,
    });
    return BirV1Page.fromJson(json);
  }

  Future<int> total() async {
    final json = await _get('registrations', const <String, String>{
      'limit': '1',
    });
    return BirV1Page.fromJson(json).total;
  }

  Future<BirV1Record> detail(int id) async {
    final json = await _get('registrations/$id');
    return BirV1Record.fromJson(_dataMap(json));
  }

  Future<List<BirV1Document>> documents(int id) async {
    final json = await _get('registrations/$id/documents');
    final data = json['data'];
    if (data is! List) return const <BirV1Document>[];
    return data
        .whereType<Map>()
        .map((e) => BirV1Document.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  Future<BirV1Meta> meta() async {
    try {
      final json = await _get('meta');
      return BirV1Meta.fromJson(_dataMap(json));
    } catch (_) {
      return BirV1Meta.fallback;
    }
  }

  Future<BirV1Record> update(int id, Map<String, String> fields) async {
    final json = await _post(
      'registrations/$id',
      query: const <String, String>{'_method': 'PATCH'},
      body: fields,
    );
    return BirV1Record.fromJson(_dataMap(json));
  }

  Future<BirV1Record> applyWorkflow(
    int id, {
    required String status,
    String ptu = '',
    String min = '',
    String posDateIssued = '',
  }) async {
    final json = await _post(
      'registrations/$id/workflow',
      body: <String, String>{
        'status': status,
        if (ptu.trim().isNotEmpty) 'ptu': ptu.trim(),
        if (min.trim().isNotEmpty) 'min': min.trim(),
        if (posDateIssued.trim().isNotEmpty)
          'pos_date_issued': posDateIssued.trim(),
      },
    );
    return BirV1Record.fromJson(_dataMap(json));
  }

  Future<int> deleteRecord(int id) async {
    final json = await _post(
      'registrations/$id',
      query: const <String, String>{'_method': 'DELETE'},
    );
    final data = _dataMap(json);
    final removed = data['documents_removed'];
    return removed is int ? removed : int.tryParse('$removed') ?? 0;
  }

  Future<void> deleteDocument(int id, int documentId) async {
    await _post(
      'registrations/$id/documents/$documentId',
      query: const <String, String>{'_method': 'DELETE'},
    );
  }

  Future<BirV1Document> uploadDocument(
    int id, {
    required String filePath,
    required String docType,
  }) async {
    final response = await api.rawPostMultipart(
      uriFor('registrations/$id/documents'),
      fields: <String, String>{'doc_type': docType},
      files: <({String field, String path})>[(field: 'file', path: filePath)],
    );
    final json = _decode(response.statusCode, response.body);
    return BirV1Document.fromJson(_dataMap(json));
  }

  Future<String> downloadDocument(int id, BirV1Document document) async {
    return _download(
      uriFor('registrations/$id/documents/${document.id}', const {
        'download': '1',
      }),
      document.displayName.isEmpty
          ? 'v1-document-${document.id}'
          : document.displayName,
      'Could not download this document.',
    );
  }

  Future<String> downloadArchiveFile(String filename) async {
    final name = filename.trim();
    if (name.isEmpty) {
      throw BirV1Exception('This record has no stored file to open.');
    }
    return _download(
      uriFor('legacy/upload-file', <String, String>{
        'file': name,
        'download': '1',
      }),
      name,
      'The V1 archive does not have "$name" on disk.',
    );
  }

  Future<String> downloadBirCard(int id) async {
    return _download(
      uriFor('registrations/$id/bir-card', const {'download': '1'}),
      'bir-card-$id.pdf',
      'Could not generate the BIR card.',
    );
  }

  Future<String> generateSwornDocument(int id, String docType) async {
    final response = await api.rawPostForm(
      uriFor('legacy/sworn-declaration'),
      <String, String>{'id': '$id', 'docType': docType},
    );
    final json = _decode(
      response.statusCode,
      response.body,
      fallback: 'Could not generate the sworn document.',
    );
    final file = '${json['pdfPath'] ?? ''}'.trim();
    if (file.isEmpty) {
      throw BirV1Exception(
        'The V1 system did not return a generated document.',
      );
    }
    return _download(
      uriFor('legacy/print-file', <String, String>{
        'file': file,
        'download': '1',
      }),
      file,
      'Could not open the generated document.',
    );
  }

  Future<List<Map<String, dynamic>>> step3Extract(List<String> paths) async {
    final files = paths
        .where((p) => p.trim().isNotEmpty)
        .toList(growable: false);
    if (files.isEmpty) {
      throw BirV1Exception('Choose at least one Permit to Use PDF.');
    }

    final http.Response response;
    try {
      response = await api.rawPostMultipart(
        uriFor('legacy/step3-extract'),
        files: <({String field, String path})>[
          for (final path in files) (field: 'pdf[]', path: path),
        ],
      );
    } catch (e) {
      throw BirV1Exception('$e');
    }

    final body = response.body.trim();
    Object? decoded;
    if (body.isNotEmpty) {
      try {
        decoded = jsonDecode(body);
      } catch (_) {}
    }

    final ok = response.statusCode >= 200 && response.statusCode < 300;
    if (!ok || (decoded is Map && decoded['success'] == false)) {
      _decode(
        response.statusCode,
        response.body,
        fallback: 'Could not read the PDF.',
      );
    }
    if (decoded == null) {
      throw BirV1Exception('The extractor returned an unreadable response.');
    }
    if (decoded is Map && decoded['error'] != null) {
      throw BirV1Exception('${decoded['error']}');
    }

    final items = (decoded is List ? decoded : <Object?>[decoded])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
    if (items.isEmpty) {
      throw BirV1Exception('The extractor returned an unreadable response.');
    }
    return items;
  }

  Future<void> step3Update(
    int id, {
    required String posDateIssued,
    required String ptu,
    required String min,
    required String filename,
    required String machineDetails,
  }) async {
    final response = await api
        .rawPostForm(uriFor('legacy/step3-update'), <String, String>{
          'customerId': '$id',
          'pos_date_issued': posDateIssued,
          'ptu': ptu,
          'min': min,
          'filename': filename,
          'machineDetails': machineDetails,
        });
    final json = _decode(
      response.statusCode,
      response.body,
      fallback: 'The V1 system could not save the PTU details.',
    );
    final status = '${json['status'] ?? ''}'.trim();
    if (status.isNotEmpty && status != 'success') {
      final message = '${json['message'] ?? ''}'.trim();
      throw BirV1Exception(
        message.isEmpty ? 'The V1 system rejected the PTU details.' : message,
      );
    }
  }

  Future<Map<String, dynamic>> _get(
    String path, [
    Map<String, String>? query,
  ]) async {
    final response = await api.rawGet(uriFor(path, query));
    return _decode(response.statusCode, response.body);
  }

  Future<Map<String, dynamic>> _post(
    String path, {
    Map<String, String>? query,
    Map<String, String> body = const <String, String>{},
  }) async {
    final response = await api.rawPostForm(uriFor(path, query), body);
    return _decode(response.statusCode, response.body);
  }

  Future<String> _download(Uri uri, String filename, String fallback) async {
    final http.Response response;
    try {
      response = await api.rawGet(uri, json: false);
    } catch (e) {
      throw BirV1Exception('$e');
    }
    final type = (response.headers['content-type'] ?? '').toLowerCase();
    final bytes = response.bodyBytes;
    final failed =
        response.statusCode < 200 ||
        response.statusCode >= 300 ||
        bytes.isEmpty ||
        type.contains('text/html');
    if (failed) {
      if (type.contains('json')) {
        _decode(response.statusCode, response.body, fallback: fallback);
      }
      throw BirV1Exception(fallback);
    }
    final directory = await getTemporaryDirectory();
    final safe = filename
        .split(RegExp(r'[\\/]'))
        .last
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    final file = io.File(
      '${directory.path}${io.Platform.pathSeparator}'
      '${safe.isEmpty ? 'v1-file' : safe}',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Map<String, dynamic> _dataMap(Map<String, dynamic> json) {
    final data = json['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    return json;
  }

  Map<String, dynamic> _decode(
    int status,
    String body, {
    String fallback = 'The V1 system could not complete this request.',
  }) {
    Map<String, dynamic>? decoded;
    final trimmed = body.trim();
    if (trimmed.isNotEmpty) {
      try {
        final value = jsonDecode(trimmed);
        if (value is Map) decoded = Map<String, dynamic>.from(value);
      } catch (_) {}
    }

    final ok = status >= 200 && status < 300;
    final flagged = decoded != null && decoded['success'] == false;

    if (!ok || flagged) {
      final error = decoded?['error'];
      var message = fallback;
      var details = const <String, String>{};
      if (error is Map) {
        final raw = '${error['message'] ?? ''}'.trim();
        if (raw.isNotEmpty) message = raw;
        final rawDetails = error['details'];
        if (rawDetails is Map) {
          details = rawDetails.map((k, v) => MapEntry('$k', '$v'));
        }
      } else if (!ok) {
        message = status == 401
            ? 'Your session expired. Sign in again to use the V1 records.'
            : status == 403
            ? 'You do not have access to BIR Registration.'
            : fallback;
      }
      throw BirV1Exception(message, details);
    }

    if (decoded == null) throw BirV1Exception(fallback);
    return decoded;
  }
}
