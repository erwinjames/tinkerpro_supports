import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api_client.dart';

class BirRegisterException implements Exception {
  BirRegisterException(this.message);
  final String message;
  @override
  String toString() => message;
}

class BirStoredFile {
  BirStoredFile(this.raw);
  final Map<String, dynamic> raw;
  String get original => (raw['original'] ?? raw['stored'] ?? '').toString();
  String get stored => (raw['stored'] ?? '').toString();
  String get mime => (raw['mime'] ?? '').toString();
  bool get isValidId => raw['is_valid_id'] == true || raw['_docType'] == 'ID';
}

class BirRegisterService {
  BirRegisterService(this.api);
  final ApiClient api;

  String get base => api.baseUrl.replaceAll(RegExp(r'/+$'), '');

  String uploadUrl(String stored) => '$base/uploads/${Uri.encodeComponent(stored)}';

  Map<String, dynamic> _map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  Future<Map<String, dynamic>?> customer(int id) async {
    try {
      final r = await api.get('getCustomerbyID', {'id': '$id'});
      if (r['id'] != null) return r;
    } catch (_) {}
    return null;
  }

  Future<String> startExtraction({
    required List<String> files,
    String? validIdPath,
    String? manualName,
    String? manualBirthdate,
  }) async {
    final Map<String, dynamic> r;
    try {
      r = await api.postPathMultipartFiles(
        'client-multidoc-extract.php',
        fields: {
          'extract_mode': 'accurate',
          if (manualName == null && validIdPath != null) 'valid_id_type': '',
          if (manualName != null) 'valid_id_manual': '1',
          'valid_id_manual_name': ?manualName,
          if (manualName != null) 'valid_id_manual_birthdate': manualBirthdate ?? '',
        },
        files: [
          for (final p in files) (field: 'files[]', path: p),
          if (manualName == null && validIdPath != null)
            (field: 'valid_id_file', path: validIdPath),
        ],
      ).timeout(const Duration(minutes: 10));
    } on TimeoutException {
      throw BirRegisterException(
        'Extraction timed out. Try fewer documents or use Fast mode.',
      );
    } catch (_) {
      throw BirRegisterException(
        'Server failed to process the uploaded documents.',
      );
    }
    if (r['error'] != null) throw BirRegisterException(r['error'].toString());
    final job = (r['job_id'] ?? '').toString();
    if (r['async'] == true && job.isNotEmpty) return job;
    throw BirRegisterException('Extraction failed.');
  }

  Future<Map<String, dynamic>> pollExtraction(
    String job, {
    void Function(Map<String, dynamic> progress)? onProgress,
  }) async {
    final started = DateTime.now();
    var errors = 0;
    while (true) {
      final age = DateTime.now().difference(started).inMilliseconds;
      try {
        final res = await api
            .getPath('client-multidoc-extract-status.php', {
              'job': job,
              '_': '${DateTime.now().millisecondsSinceEpoch}',
            })
            .timeout(const Duration(seconds: 30));
        errors = 0;
        final status = (res['status'] ?? '').toString();
        if (status == 'running') {
          onProgress?.call(res);
          if (age > 900000) {
            throw BirRegisterException(
              'Extraction is taking too long. Try fewer documents or use Fast mode.',
            );
          }
        } else if (status == 'error') {
          throw BirRegisterException(
            (res['error'] ?? 'Extraction failed on the server.').toString(),
          );
        } else {
          if (res['error'] != null) {
            throw BirRegisterException(res['error'].toString());
          }
          return res;
        }
      } on BirRegisterException {
        rethrow;
      } catch (e) {
        errors++;
        if (errors >= 5 || e.toString().contains('HTTP 403')) {
          throw BirRegisterException(
            'Lost contact with the server while extracting.',
          );
        }
      }
      await Future<void>.delayed(
        Duration(milliseconds: age < 20000 ? 900 : (age < 90000 ? 1800 : 3000)),
      );
    }
  }

  Future<Map<String, dynamic>> _op(
    String op, {
    Map<String, String>? query,
    Map<String, String>? body,
  }) async {
    final Map<String, dynamic> r;
    try {
      if (body != null) {
        final res = await http.post(
          Uri.parse(api.actionUrl('desktopBirRegister', {'op': op, ...?query})),
          headers: {...api.authHeaders(), 'Accept': 'application/json'},
          body: body,
        );
        r = _map(jsonDecode(res.body));
      } else {
        r = await api.get('desktopBirRegister', {'op': op, ...?query});
      }
    } catch (_) {
      throw BirRegisterException('Could not reach the server.');
    }
    if (r['status'] != 'success') {
      throw BirRegisterException((r['message'] ?? 'Request failed.').toString());
    }
    return r;
  }

  Future<Map<String, dynamic>> meta() => _op('meta');

  Future<Map<String, dynamic>> prefill(
    String job, {
    int? customerId,
    String? manualName,
    String? manualBirthdate,
  }) => _op(
    'prefill',
    query: {
      'job': job,
      if (customerId != null) 'customer_id': '$customerId',
      if (manualName != null) 'valid_id_manual': '1',
      'valid_id_manual_name': ?manualName,
      if (manualName != null) 'valid_id_manual_birthdate': manualBirthdate ?? '',
    },
  );

  Future<Map<String, dynamic>> completeContext(int customerId) =>
      _op('complete', query: {'customer_id': '$customerId'});

  Future<List<Map<String, dynamic>>> psic(String q) async {
    try {
      final r = await _op('psic', query: {'q': q});
      final d = r['data'];
      return d is List ? d.whereType<Map>().map(_map).toList() : const [];
    } catch (_) {
      return const [];
    }
  }

  Future<Map<String, dynamic>> review(Map<String, dynamic> data) async {
    try {
      final res = await http.post(
        Uri.parse(api.actionUrl('desktopBirRegister', {'op': 'review'})),
        headers: {...api.authHeaders(), 'Accept': 'application/json'},
        body: {'data': jsonEncode(data)},
      );
      return _map(jsonDecode(res.body));
    } catch (_) {
      return {'status': 'error', 'message': 'Could not reach the server.'};
    }
  }

  Future<({bool duplicate, String message})> checkTin(
    String tinDigits,
    String branchDigits, {
    bool upload = false,
  }) async {
    try {
      final r = await api.get('checkTinDuplicate', {
        'tin': tinDigits,
        if (branchDigits.isNotEmpty) 'branch_code': branchDigits,
      });
      if (r['duplicate'] != true) return (duplicate: false, message: '');
      final ex = _map(r['existing']);
      final company = (ex['company_name'] ?? '').toString();
      final existingTin = (ex['tin'] ?? tinDigits).toString();
      final String msg;
      if (upload) {
        msg = company.isNotEmpty
            ? 'The extracted TIN ($existingTin) is already registered to "$company". Please upload documents for a different client or verify the documents are correct.'
            : 'The extracted TIN ($existingTin) is already registered. Please upload documents for a different client or verify the documents are correct.';
      } else {
        msg = company.isNotEmpty
            ? 'This TIN ($existingTin) is already registered to "$company". Please verify before saving.'
            : 'This TIN ($existingTin) is already registered. Please verify before saving.';
      }
      return (duplicate: true, message: msg);
    } catch (_) {
      return (duplicate: false, message: '');
    }
  }

  Future<bool> snTaken(String sn) async {
    try {
      final r = await api.get('checkSnDuplicate', {'sn': sn});
      return r['duplicate'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> snSuggest(String q, String type) async {
    try {
      final r = await api.get('searchLicenseSerials', {
        'q': q,
        'limit': '10',
        'machine_type': type,
      });
      final d = r['results'];
      return d is List
          ? d
                .whereType<Map>()
                .map(_map)
                .where((e) => (e['serial'] ?? '').toString().isNotEmpty)
                .toList()
          : const [];
    } catch (_) {
      return const [];
    }
  }

  Future<Map<String, dynamic>> addDocument(String path) async {
    final Map<String, dynamic> r;
    try {
      r = await api
          .postPathMultipart('client-add-document.php', files: {'file': path})
          .timeout(const Duration(seconds: 120));
    } catch (_) {
      throw BirRegisterException('Failed to process document.');
    }
    if (r['error'] != null) throw BirRegisterException('Error: ${r['error']}');
    return _op('apply_document', body: {'doc': jsonEncode(r)});
  }

  Future<Map<String, dynamic>> uploadRequirement(String path) async {
    final Map<String, dynamic> r;
    try {
      r = await api
          .postPathMultipart('client-upload-attachment.php', files: {'file': path})
          .timeout(const Duration(seconds: 60));
    } catch (_) {
      throw BirRegisterException('Failed to upload file.');
    }
    if (r['error'] != null) throw BirRegisterException('Error: ${r['error']}');
    final s = r['stored_file'];
    if (s is! Map) throw BirRegisterException('Failed to upload file.');
    return _map(s);
  }

  String _encode(List<Map<String, dynamic>> pairs) => pairs
      .map(
        (p) =>
            '${Uri.encodeQueryComponent((p['name'] ?? '').toString())}=${Uri.encodeQueryComponent((p['value'] ?? '').toString())}',
      )
      .join('&');

  Future<Map<String, dynamic>> submit(
    String action,
    List<Map<String, dynamic>> payload,
  ) async {
    try {
      final res = await http.post(
        Uri.parse(api.actionUrl(action)),
        headers: {
          ...api.authHeaders(),
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          'Accept': 'application/json',
        },
        body: _encode(payload),
      );
      try {
        return _map(jsonDecode(res.body));
      } catch (_) {
        return {'status': 'error', 'message': 'HTTP ${res.statusCode}'};
      }
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  Future<({String url, String filename})> exportCsv(
    List<Map<String, dynamic>> payload,
  ) async {
    final res = await http.post(
      Uri.parse('$base/client-export-csv.php'),
      headers: {
        ...api.authHeaders(),
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
      },
      body: _encode([
        ...payload,
        {'name': 'response_mode', 'value': 'json'},
      ]),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw BirRegisterException('Failed to prepare CSV file.');
    }
    if (!(res.headers['content-type'] ?? '').contains('application/json')) {
      throw BirRegisterException('Unexpected export response format.');
    }
    final j = _map(jsonDecode(res.body));
    if (j['success'] != true || (j['url'] ?? '').toString().isEmpty) {
      throw BirRegisterException(
        (j['message'] ?? 'Failed to prepare CSV file.').toString(),
      );
    }
    return (
      url: j['url'].toString(),
      filename: (j['filename'] ?? 'ACCREG_POS_STANDALONE.csv').toString(),
    );
  }
}
