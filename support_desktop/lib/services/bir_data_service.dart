import 'dart:convert';
import 'dart:io' as io;

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../api_client.dart';

class BirPageMeta {
  const BirPageMeta({
    this.isSuperAdmin = false,
    this.canViewTaxpayerPortal = false,
    this.noteAdminUsername = '',
  });
  final bool isSuperAdmin;
  final bool canViewTaxpayerPortal;
  final String noteAdminUsername;
}

class BirPage {
  const BirPage({
    required this.rows,
    required this.total,
    required this.lastPage,
  });
  final List<Map<String, dynamic>> rows;
  final int total;
  final int lastPage;
}

class BirSoftwareEntry {
  BirSoftwareEntry({
    required this.id,
    required this.name,
    required this.version,
    required this.accNumber,
  });
  final int id;
  final String name;
  final String version;
  final String accNumber;
}

class BirDownloadException implements Exception {
  BirDownloadException(this.message);
  final String message;
  @override
  String toString() => message;
}

class BirDataService {
  BirDataService(this.api);
  final ApiClient api;

  String get _base => api.baseUrl.replaceAll(RegExp(r'/+$'), '');

  Future<BirPageMeta> meta() async {
    try {
      final r = await api.get('desktopBirPageMeta');
      return BirPageMeta(
        isSuperAdmin: r['is_super_admin'] == true,
        canViewTaxpayerPortal: r['can_view_taxpayer_portal'] == true,
        noteAdminUsername: (r['note_admin_username'] ?? '').toString(),
      );
    } catch (_) {
      return const BirPageMeta();
    }
  }

  Future<BirPage> customers({
    required int page,
    required int limit,
    String search = '',
  }) async {
    final r = await api.get('getcustomer', {
      'page': '$page',
      'limit': '$limit',
      if (search.trim().isNotEmpty) 'search': search.trim(),
    });
    final raw = r['data'];
    final rows = raw is List
        ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    final total = int.tryParse('${r['totalRecords'] ?? 0}') ?? 0;
    final lim = int.tryParse('${r['limit'] ?? limit}') ?? limit;
    final last = lim <= 0 ? 1 : ((total + lim - 1) ~/ lim);
    return BirPage(rows: rows, total: total, lastPage: last < 1 ? 1 : last);
  }

  Future<Map<String, dynamic>?> customer(int id) async {
    try {
      return await customerStrict(id);
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> customerStrict(int id) async {
    final r = await api.get('getCustomerbyID', {'id': '$id'});
    for (final k in ['data', 'customer', 'row']) {
      final v = r[k];
      if (v is Map) return Map<String, dynamic>.from(v);
    }
    if (r['id'] != null) return r;
    return null;
  }

  Future<BirPage> v1Registrations({
    required int page,
    required int limit,
    String search = '',
    String status = '',
  }) async {
    final r = await api.getPath('bir-v1.php', {
      'path': 'registrations',
      'page': '$page',
      'limit': '${limit > 100 ? 100 : limit}',
      if (search.trim().isNotEmpty) 'search': search.trim(),
      if (status.isNotEmpty) 'status': status,
    });
    if (r['success'] == false) {
      final err = r['error'];
      throw BirDownloadException(
        err is Map
            ? (err['message'] ?? 'Could not load the V1 registrations.')
                  .toString()
            : 'Could not load the V1 registrations.',
      );
    }
    final raw = r['data'];
    final rows = raw is List
        ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    final meta = r['meta'] is Map ? Map<String, dynamic>.from(r['meta']) : {};
    final total = int.tryParse('${meta['total'] ?? rows.length}') ?? 0;
    final pages = int.tryParse('${meta['total_pages'] ?? 1}') ?? 1;
    return BirPage(rows: rows, total: total, lastPage: pages < 1 ? 1 : pages);
  }

  Future<int?> v1Total() async {
    try {
      final p = await v1Registrations(page: 1, limit: 1);
      return p.total;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> v1Registration(int id) async {
    try {
      final r = await api.getPath('bir-v1.php', {'path': 'registrations/$id'});
      final d = r['data'];
      if (d is Map) return Map<String, dynamic>.from(d);
    } catch (_) {}
    return null;
  }

  Future<bool> saveNotes(int customerId, Map<String, dynamic> notes) async {
    try {
      final r = await api.post(
        'saveCustomerActionNote',
        body: {'customer_id': '$customerId', 'action_notes': jsonEncode(notes)},
      );
      return r['status'] == 'success';
    } catch (_) {
      return false;
    }
  }

  Future<List<BirSoftwareEntry>> softwareList() async {
    final r = await api.get('software.list');
    if (r['status'] == 'error') {
      throw BirDownloadException((r['message'] ?? 'Unauthorized').toString());
    }
    final raw = r['data'];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) {
      final m = Map<String, dynamic>.from(e);
      return BirSoftwareEntry(
        id: int.tryParse('${m['id'] ?? 0}') ?? 0,
        name: (m['software_name'] ?? m['name'] ?? '').toString(),
        version: (m['version'] ?? '').toString(),
        accNumber: (m['acc_number'] ?? '').toString(),
      );
    }).toList();
  }

  Future<String?> softwareSave({
    int? id,
    required String name,
    required String version,
    required String accNumber,
  }) async {
    try {
      final r = await api.post(
        'software.save',
        body: {
          if (id != null) 'id': '$id',
          'software_name': name,
          'version': version,
          'acc_number': accNumber,
        },
      );
      if (r['status'] == 'success' || r['success'] == true) return null;
      return (r['message'] ?? 'Could not save.').toString();
    } catch (_) {
      return 'Network error.';
    }
  }

  Future<String?> softwareDelete(int id) async {
    try {
      final r = await api.post('software.delete', body: {'id': '$id'});
      if (r['status'] == 'success' || r['success'] == true) return null;
      return (r['message'] ?? 'Could not delete.').toString();
    } catch (_) {
      return 'Network error.';
    }
  }

  Future<({List<String>? preview, List<String>? export})> fieldPrefs() async {
    try {
      final r = await api.get('getCustomerFieldPickerPrefs');
      if (r['success'] == true && r['has_saved'] == true) {
        List<String>? l(dynamic v) =>
            v is List ? v.map((e) => e.toString()).toList() : null;
        return (preview: l(r['preview_fields']), export: l(r['export_fields']));
      }
    } catch (_) {}
    return (preview: null, export: null);
  }

  Future<bool> saveFieldPrefs({
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
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  String qrPngUrl() =>
      '$_base/client-register-qr.php?variant=prod&format=png&v=2';

  String registrationUrl() => '$_base/client-register?register=1';

  Future<String> downloadAction(
    String action,
    Map<String, String> query,
    String fallbackName,
  ) {
    return _download(Uri.parse(api.actionUrl(action, query)), fallbackName);
  }

  Future<String> downloadPath(String path, String fallbackName) {
    final clean = path.replaceAll(RegExp(r'^/+'), '');
    return _download(Uri.parse('$_base/$clean'), fallbackName);
  }

  Future<String?> swornPdfPath(int id, String docType) async {
    final r = await api.postPath(
      'print/sworn_declaration.php',
      body: {'id': '$id', 'docType': docType},
    );
    final p = (r['pdfPath'] ?? '').toString();
    return p.isEmpty ? null : 'print/$p';
  }

  Future<void> prepareAskReceipt(int id) async {
    final res = await http.post(
      Uri.parse('$_base/print/bir-card.php'),
      headers: api.authHeaders(),
      body: {'id': '$id'},
    );
    if (res.statusCode >= 400) {
      throw BirDownloadException('Could not build the Ask for Receipt card.');
    }
  }

  Future<String> _download(Uri uri, String fallbackName) async {
    final res = await http.get(uri, headers: api.authHeaders());
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final body = res.body.trim();
      throw BirDownloadException(
        body.isNotEmpty && body.length < 300 ? body : 'Download failed.',
      );
    }
    final type = (res.headers['content-type'] ?? '').toLowerCase();
    if (type.contains('application/json') || type.contains('text/html')) {
      var msg = 'Download failed.';
      try {
        final j = jsonDecode(res.body);
        if (j is Map && j['message'] != null) msg = j['message'].toString();
      } catch (_) {}
      throw BirDownloadException(msg);
    }
    var name = fallbackName;
    final disp = res.headers['content-disposition'] ?? '';
    final m = RegExp(r'filename="?([^";]+)"?').firstMatch(disp);
    if (m != null) name = m.group(1)!.trim();
    name = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
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
