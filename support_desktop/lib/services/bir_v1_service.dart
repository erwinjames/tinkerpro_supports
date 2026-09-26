import 'dart:convert';
import 'dart:io' as io;

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../api_client.dart';

class BirV1Exception implements Exception {
  BirV1Exception(this.message);
  final String message;
  @override
  String toString() => message;
}

class BirV1Service {
  BirV1Service(this.api);
  final ApiClient api;

  static const endpoint = 'bir-v1.php';

  String get _base => api.baseUrl.replaceAll(RegExp(r'/+$'), '');

  Uri v1Url(String path, [Map<String, String>? extra]) => Uri.parse(
    '$_base/$endpoint',
  ).replace(queryParameters: {'path': path, ...?extra});

  Map<String, String> get _headers => {
    ...api.authHeaders(),
    'Accept': 'application/json',
  };

  static String errorMessage(dynamic payload, String fallback) {
    if (payload is! Map || payload['error'] == null) return fallback;
    final err = payload['error'];
    if (err is! Map) return fallback;
    var msg = (err['message'] ?? fallback).toString();
    if (msg.isEmpty) msg = fallback;
    final details = err['details'];
    if (details is Map && details.isNotEmpty) {
      msg +=
          '\n\n${details.entries.map((e) => '${e.key}: ${e.value}').join('\n')}';
    }
    return msg;
  }

  dynamic _decode(http.Response res, String fallback) {
    dynamic body;
    try {
      body = jsonDecode(res.body.trim());
    } catch (_) {
      body = null;
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw BirV1Exception(errorMessage(body, fallback));
    }
    return body;
  }

  Future<dynamic> _get(
    String path,
    String fallback, [
    Map<String, String>? q,
  ]) async {
    final http.Response res;
    try {
      res = await http.get(v1Url(path, q), headers: _headers);
    } catch (_) {
      throw BirV1Exception(fallback);
    }
    return _decode(res, fallback);
  }

  Future<dynamic> _write(
    String path,
    String method,
    Map<String, dynamic> body,
    String fallback,
  ) async {
    final http.Response res;
    try {
      res = await http.post(
        v1Url(path, {'_method': method}),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
    } catch (_) {
      throw BirV1Exception(fallback);
    }
    return _decode(res, fallback);
  }

  Future<http.Response> _postForm(String path, Map<String, String> data) async {
    return http.post(v1Url(path), headers: _headers, body: data);
  }

  Future<Map<String, dynamic>> _multipart(
    String path,
    Map<String, String> fields,
    List<({String field, String path})> files,
    String fallback,
  ) async {
    final http.Response res;
    try {
      final req = http.MultipartRequest('POST', v1Url(path));
      req.headers.addAll(_headers);
      req.fields.addAll(fields);
      for (final f in files) {
        req.files.add(await http.MultipartFile.fromPath(f.field, f.path));
      }
      res = await http.Response.fromStream(await req.send());
    } catch (_) {
      throw BirV1Exception(fallback);
    }
    final body = _decode(res, fallback);
    return {'raw': body, 'text': res.body};
  }

  Future<Map<String, dynamic>> record(int id, {String? fallback}) async {
    final r = await _get(
      'registrations/$id',
      fallback ?? 'Could not load this V1 record.',
    );
    final d = r is Map ? r['data'] : null;
    if (d is! Map) {
      throw BirV1Exception(fallback ?? 'Could not load this V1 record.');
    }
    return Map<String, dynamic>.from(d);
  }

  Future<List<Map<String, dynamic>>> documents(int id) async {
    final r = await _get(
      'registrations/$id/documents',
      'Could not load documents.',
    );
    final d = r is Map ? r['data'] : null;
    if (d is! List) return const [];
    return d.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Map<String, dynamic>?> update(
    int id,
    Map<String, dynamic> payload,
  ) async {
    final r = await _write(
      'registrations/$id',
      'PATCH',
      payload,
      'Could not update this V1 record.',
    );
    final d = r is Map ? r['data'] : null;
    return d is Map ? Map<String, dynamic>.from(d) : null;
  }

  Future<Map<String, dynamic>?> workflow(
    int id,
    Map<String, dynamic> payload,
  ) async {
    final r = await _write(
      'registrations/$id/workflow',
      'POST',
      payload,
      'Could not change the status.',
    );
    final d = r is Map ? r['data'] : null;
    return d is Map ? Map<String, dynamic>.from(d) : null;
  }

  Future<void> uploadDocument(int id, String filePath, String docType) async {
    await _multipart(
      'registrations/$id/documents',
      {'doc_type': docType},
      [(field: 'file', path: filePath)],
      'Could not upload the document.',
    );
  }

  Future<void> deleteDocument(int id, int docId) async {
    await _write(
      'registrations/$id/documents/$docId',
      'DELETE',
      const {},
      'Could not delete the document.',
    );
  }

  Future<void> deleteRecord(int id) async {
    await _write(
      'registrations/$id',
      'DELETE',
      const {},
      'Could not delete this V1 record.',
    );
  }

  Future<dynamic> step3Extract(List<String> paths) async {
    final r = await _multipart('legacy/step3-extract', const {}, [
      for (final p in paths) (field: 'pdf[]', path: p),
    ], 'Could not read the PDF.');
    final raw = r['raw'];
    if (raw == null) {
      throw BirV1Exception('The extractor returned an unreadable response.');
    }
    return raw;
  }

  Future<Map<String, String>> step3Check(int id, dynamic extract) async {
    Map<String, dynamic> r;
    try {
      r = await api.post(
        'desktopBirV1Step3Check',
        body: {'id': '$id', 'extract': jsonEncode(extract)},
      );
    } catch (_) {
      throw BirV1Exception('The extractor returned an unreadable response.');
    }
    if (r['success'] != true) {
      throw BirV1Exception(
        (r['message'] ?? 'The extractor returned an unreadable response.')
            .toString(),
      );
    }
    final v = r['values'];
    if (v is! Map) {
      throw BirV1Exception('The extractor returned an unreadable response.');
    }
    return v.map((k, val) => MapEntry(k.toString(), (val ?? '').toString()));
  }

  Future<void> step3Update(int id, Map<String, String> values) async {
    const fallback = 'The V1 system could not save the PTU details.';
    final http.Response res;
    try {
      res = await _postForm('legacy/step3-update', {
        'customerId': '$id',
        'pos_date_issued': values['pos_date_issued'] ?? '',
        'ptu': values['ptu'] ?? '',
        'min': values['min'] ?? '',
        'filename': values['filename'] ?? '',
        'machineDetails': values['machineDetails'] ?? '',
      });
    } catch (_) {
      throw BirV1Exception(fallback);
    }
    final body = _decode(res, fallback);
    if (body is Map &&
        body['status'] != null &&
        body['status'] != '' &&
        body['status'] != 'success') {
      throw BirV1Exception(
        (body['message'] ?? 'The V1 system rejected the PTU details.')
            .toString(),
      );
    }
  }

  Future<String?> swornDeclaration(int id, String docType) async {
    const fallback = 'Could not generate the sworn document.';
    final http.Response res;
    try {
      res = await _postForm('legacy/sworn-declaration', {
        'id': '$id',
        'docType': docType,
      });
    } catch (_) {
      throw BirV1Exception(fallback);
    }
    final body = _decode(res, fallback);
    if (body is! Map) throw BirV1Exception(fallback);
    final p = (body['pdfPath'] ?? '').toString();
    return p.isEmpty ? null : p;
  }

  Future<void> email(String path, Map<String, String> data) async {
    final res = await _postForm(path, data);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw BirV1Exception('Email sending failed');
    }
  }

  Future<String> download(
    String path,
    Map<String, String> query,
    String fallbackName,
  ) async {
    final http.Response res;
    try {
      res = await http.get(v1Url(path, query), headers: api.authHeaders());
    } catch (_) {
      throw BirV1Exception('Download failed.');
    }
    final type = (res.headers['content-type'] ?? '').toLowerCase();
    if (res.statusCode < 200 ||
        res.statusCode >= 300 ||
        type.contains('application/json') ||
        type.contains('text/html')) {
      dynamic body;
      try {
        body = jsonDecode(res.body);
      } catch (_) {}
      if (body is Map) {
        throw BirV1Exception(errorMessage(body, 'Download failed.'));
      }
      if (type.contains('text/html')) {
        final strong = RegExp(r'<strong>(.*?)</strong>').firstMatch(res.body);
        throw BirV1Exception(
          strong != null
              ? 'Document unavailable — the V1 archive does not have ${strong.group(1)} on disk.'
              : 'Download failed.',
        );
      }
      throw BirV1Exception('Download failed.');
    }
    var name = fallbackName;
    final disp = res.headers['content-disposition'] ?? '';
    final m = RegExp(r'filename="?([^";]+)"?').firstMatch(disp);
    if (m != null) name = m.group(1)!.trim();
    name = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (name.isEmpty) name = fallbackName;
    io.Directory dir;
    try {
      dir = await getDownloadsDirectory() ?? await getTemporaryDirectory();
    } catch (_) {
      dir = await getTemporaryDirectory();
    }
    final file = io.File('${dir.path}${io.Platform.pathSeparator}$name');
    await file.writeAsBytes(res.bodyBytes, flush: true);
    return file.path;
  }

  Future<void> open(String path) async {
    await OpenFilex.open(path);
  }
}
