import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../api_client.dart';

class BirMiscException implements Exception {
  BirMiscException(this.message);
  final String message;
  @override
  String toString() => message;
}

class BirApiToken {
  BirApiToken(this.raw);
  final Map<String, dynamic> raw;

  String _s(String k) => (raw[k] ?? '').toString();
  int get id => int.tryParse(_s('id')) ?? 0;
  bool get active => raw['active'] == true || _s('active') == '1';
  String get label => _s('label');
  String get masked => _s('masked');
  String get source => _s('source');
  String get createdIp => _s('created_ip');
  String get createdByName => _s('created_by_name');
  String get deviceSerial => _s('device_serial');
  String get requestCount =>
      _s('request_count').isEmpty ? '0' : _s('request_count');
  String get lastUsedAt => _s('last_used_at');
  String get revokedAt => _s('revoked_at');
}

class BirSoftwareRow {
  BirSoftwareRow(this.raw);
  final Map<String, dynamic> raw;
  String _s(String k) => (raw[k] ?? '').toString();
  int get id => int.tryParse(_s('id')) ?? 0;
  String get name => _s('software_name');
  String get version => _s('version');
  String get accNumber => _s('acc_number');
  bool get isActive {
    final v = raw['is_active'];
    if (v is bool) return v;
    return v != null && v.toString() != '0' && v.toString().isNotEmpty;
  }
}

class BirFieldPrefs {
  const BirFieldPrefs({
    required this.hasSaved,
    required this.preview,
    required this.export,
    required this.allPreview,
  });
  final bool hasSaved;
  final List<String>? preview;
  final List<String>? export;
  final List<String>? allPreview;
}

class BirSavedFile {
  const BirSavedFile(this.path, this.name);
  final String path;
  final String name;
}

class BirMiscService {
  BirMiscService(this.api);
  final ApiClient api;

  String get base => api.baseUrl.replaceAll(RegExp(r'/+$'), '');

  Uri pathUri(String path) =>
      Uri.parse('$base/${path.replaceAll(RegExp(r'^/+'), '')}');

  Map<String, dynamic> _json(http.Response res, String fallback) {
    final body = res.body.trim();
    try {
      final d = jsonDecode(body);
      if (d is Map) return Map<String, dynamic>.from(d);
    } catch (_) {}
    throw BirMiscException(fallback);
  }

  Future<Map<String, dynamic>> _post(
    Uri uri,
    Object body,
    String fallback,
  ) async {
    final res = await http.post(
      uri,
      headers: {...api.authHeaders(), 'Accept': 'application/json'},
      body: body,
    );
    return _json(res, fallback);
  }

  Future<Map<String, dynamic>> saveActionNote({
    required int customerId,
    required List<String> checks,
    required String text,
  }) async {
    final parts = <String>[
      'customer_id=${Uri.encodeQueryComponent('$customerId')}',
      for (final c in checks)
        '${Uri.encodeQueryComponent('checks[]')}=${Uri.encodeQueryComponent(c)}',
      'text=${Uri.encodeQueryComponent(text)}',
    ];
    final res = await http.post(
      Uri.parse(api.actionUrl('desktopSaveCustomerActionNote')),
      headers: {
        ...api.authHeaders(),
        'Accept': 'application/json',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: parts.join('&'),
    );
    return _json(res, 'Error saving notes.');
  }

  Future<List<BirApiToken>> apiTokens(int customerId) async {
    final res = await http.get(
      Uri.parse(
        api.actionUrl('getCustomerApiTokens', {'customer_id': '$customerId'}),
      ),
      headers: {...api.authHeaders(), 'Accept': 'application/json'},
    );
    final r = _json(res, 'Could not load tokens.');
    if (r['status'] != 'success') {
      final m = (r['message'] ?? '').toString();
      throw BirMiscException(m.isEmpty ? 'Could not load tokens.' : m);
    }
    final raw = r['tokens'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => BirApiToken(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<Map<String, dynamic>> createApiToken(int customerId, String label) =>
      _post(
        Uri.parse(api.actionUrl('createCustomerApiToken')),
        {'customer_id': '$customerId', 'label': label},
        'Could not create the token.',
      );

  Future<Map<String, dynamic>> revokeApiToken(int tokenId, int customerId) =>
      _post(
        Uri.parse(api.actionUrl('revokeCustomerApiToken')),
        {'token_id': '$tokenId', 'customer_id': '$customerId'},
        'Could not revoke the token.',
      );

  Future<bool> deleteCustomer(int id) async {
    final res = await http.post(
      Uri.parse(api.actionUrl('deleteCustomer')),
      headers: {...api.authHeaders(), 'Accept': 'application/json'},
      body: {'id': '$id'},
    );
    if (res.statusCode < 200 || res.statusCode >= 300) return false;
    try {
      jsonDecode(res.body.trim());
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<BirSoftwareRow>> softwareList() async {
    final res = await http.get(
      Uri.parse(api.actionUrl('software.list')),
      headers: {...api.authHeaders(), 'Accept': 'application/json'},
    );
    final r = _json(res, 'Could not load software accreditations.');
    if (r['status'] != 'success') {
      final m = (r['message'] ?? '').toString();
      throw BirMiscException(
        m.isEmpty ? 'Could not load software accreditations.' : m,
      );
    }
    final raw = r['data'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => BirSoftwareRow(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<Map<String, dynamic>> softwareSave({
    required String id,
    required String name,
    required String version,
    required String accNumber,
    required bool active,
  }) => _post(Uri.parse(api.actionUrl('software.save')), {
    'id': id,
    'software_name': name,
    'version': version,
    'acc_number': accNumber,
    'is_active': active ? '1' : '0',
  }, 'Could not save the entry.');

  Future<Map<String, dynamic>> softwareDelete(int id) => _post(
    Uri.parse(api.actionUrl('software.delete')),
    {'id': '$id'},
    'Could not delete the entry.',
  );

  Future<void> softwareCatalog() async {
    try {
      await http.get(
        Uri.parse(api.actionUrl('software.catalog')),
        headers: {...api.authHeaders(), 'Accept': 'application/json'},
      );
    } catch (_) {}
  }

  Future<BirFieldPrefs> fieldPrefs() async {
    try {
      final res = await http.get(
        Uri.parse(api.actionUrl('getCustomerFieldPickerPrefs')),
        headers: {...api.authHeaders(), 'Accept': 'application/json'},
      );
      final r = _json(res, '');
      List<String>? l(dynamic v) =>
          v is List ? v.map((e) => e.toString()).toList() : null;
      if (r['success'] == true && r['has_saved'] == true) {
        return BirFieldPrefs(
          hasSaved: true,
          preview: l(r['preview_fields']),
          export: l(r['export_fields']),
          allPreview: l(r['all_preview_fields']),
        );
      }
    } catch (_) {}
    return const BirFieldPrefs(
      hasSaved: false,
      preview: null,
      export: null,
      allPreview: null,
    );
  }

  Future<Map<String, dynamic>?> saveFieldPrefs({
    required List<String> preview,
    required List<String> export,
    required List<String> allPreview,
  }) async {
    final parts = <String>[];
    void add(String k, List<String> vs) {
      for (final v in vs) {
        parts.add(
          '${Uri.encodeQueryComponent('$k[]')}=${Uri.encodeQueryComponent(v)}',
        );
      }
    }

    add('preview_fields', preview);
    add('export_fields', export);
    add('all_preview_fields', allPreview);
    try {
      final res = await http.post(
        Uri.parse(api.actionUrl('saveCustomerFieldPickerPrefs')),
        headers: {
          ...api.authHeaders(),
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': 'application/json',
        },
        body: parts.join('&'),
      );
      return _json(res, '');
    } catch (_) {
      return null;
    }
  }

  Future<http.Response> fetch(Uri uri) =>
      http.get(uri, headers: api.authHeaders());

  Future<Uint8List?> bytes(String path) async {
    try {
      final res = await fetch(pathUri(path));
      if (res.statusCode >= 200 && res.statusCode < 300) return res.bodyBytes;
    } catch (_) {}
    return null;
  }

  Future<BirSavedFile?> fetchPdfUpload(String filename) async {
    try {
      final res = await fetch(
        pathUri('uploads/${Uri.encodeComponent(filename)}'),
      );
      final type = (res.headers['content-type'] ?? '').toLowerCase();
      if (res.statusCode < 200 ||
          res.statusCode >= 300 ||
          !type.contains('pdf')) {
        return null;
      }
      return saveBytes(res.bodyBytes, filename, temp: true);
    } catch (_) {
      return null;
    }
  }

  Future<String> swornPdfPath(int id, String docType) async {
    final r = await _post(
      pathUri('print/sworn_declaration.php'),
      {'id': '$id', 'docType': docType},
      'Failed to prepare one or more documents. Please try again.',
    );
    final p = (r['pdfPath'] ?? '').toString();
    if (p.isEmpty) {
      throw BirMiscException(
        'Failed to prepare one or more documents. Please try again.',
      );
    }
    return 'print/$p';
  }

  Future<void> prepareAskReceipt(int id) async {
    final res = await http.post(
      pathUri('print/bir-card.php'),
      headers: api.authHeaders(),
      body: {'id': '$id'},
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw BirMiscException(
        'Failed to prepare one or more documents. Please try again.',
      );
    }
  }

  Future<BirSavedFile> fetchToFile(
    String path,
    String name, {
    bool temp = false,
  }) async {
    final res = await fetch(pathUri(path));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw BirMiscException(
        'Failed to prepare one or more documents. Please try again.',
      );
    }
    return saveBytes(res.bodyBytes, name, temp: temp);
  }

  Future<bool> postEmail(String path, Map<String, String> body) async {
    try {
      final res = await http.post(
        pathUri(path),
        headers: api.authHeaders(),
        body: body,
      );
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  static String dispositionName(http.Response res, String fallback) {
    final disp = res.headers['content-disposition'] ?? '';
    final m = RegExp(r'filename="?(.+?)"?$').firstMatch(disp.trim());
    return m != null ? m.group(1)!.trim() : fallback;
  }

  Future<BirSavedFile> saveBytes(
    List<int> data,
    String name, {
    bool temp = false,
  }) async {
    final clean = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    io.Directory dir;
    if (temp) {
      dir = await getTemporaryDirectory();
    } else {
      try {
        dir = await getDownloadsDirectory() ?? await getTemporaryDirectory();
      } catch (_) {
        dir = await getTemporaryDirectory();
      }
    }
    final file = io.File('${dir.path}${io.Platform.pathSeparator}$clean');
    await file.writeAsBytes(data, flush: true);
    return BirSavedFile(file.path, clean);
  }

  Future<List<int>> bytesFromFile(String path) => io.File(path).readAsBytes();

  Future<void> open(String path) async {
    await OpenFilex.open(path);
  }
}
