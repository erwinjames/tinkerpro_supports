import 'dart:convert';

import '../api_client.dart';

class BirStep2Result {
  const BirStep2Result(this.ok, this.data, this.message, {this.title = ''});
  final bool ok;
  final Map<String, dynamic> data;
  final String message;
  final String title;
}

class BirSerialEntry {
  BirSerialEntry({
    this.type = '',
    this.serverType = '',
    this.serialNumber = '',
    this.brand = '',
    this.model = '',
  });

  factory BirSerialEntry.fromJson(Map<String, dynamic> j) => BirSerialEntry(
    type: (j['serial_number_type'] ?? '').toString(),
    serverType: (j['server_type'] ?? '').toString(),
    serialNumber: (j['serial_number'] ?? '').toString(),
    brand: (j['brand'] ?? '').toString(),
    model: (j['model'] ?? '').toString(),
  );

  String type;
  String serverType;
  String serialNumber;
  String brand;
  String model;

  Map<String, String> toJson() => {
    'serial_number_type': type,
    'server_type': serverType,
    'serial_number': serialNumber,
    'brand': brand,
    'model': model,
  };
}

class BirStep2FormData {
  BirStep2FormData({
    required this.fields,
    required this.serialEntries,
    this.showMin = false,
    this.showPtu = false,
    this.showPosDateIssued = false,
    this.isPendingRegistration = false,
    this.isUploadPtu = false,
    this.showAdvanced = false,
    this.originalStep2 = 0,
    this.fromView = false,
  });

  final Map<String, String> fields;
  final List<BirSerialEntry> serialEntries;
  final bool showMin;
  final bool showPtu;
  final bool showPosDateIssued;
  final bool isPendingRegistration;
  final bool isUploadPtu;
  final bool showAdvanced;
  final int originalStep2;
  final bool fromView;

  bool get isUpdate => (fields['customer_id'] ?? '').isNotEmpty;
}

class BirStep2Service {
  BirStep2Service(this.api);

  final ApiClient api;

  static Map<String, String> _strMap(dynamic v) {
    if (v is! Map) return <String, String>{};
    return v.map((k, val) => MapEntry(k.toString(), (val ?? '').toString()));
  }

  static List<BirSerialEntry> _entries(dynamic v) {
    if (v is! List) return <BirSerialEntry>[];
    return v
        .whereType<Map>()
        .map((e) => BirSerialEntry.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static String _err(Object e) => e.toString();

  Future<BirStep2Result> _guard(
    Future<Map<String, dynamic>> Function() run, {
    String fallback = 'Something went wrong. Please try again.',
  }) async {
    try {
      final r = await run();
      final status = (r['status'] ?? '').toString();
      final ok = status == 'success';
      return BirStep2Result(
        ok,
        r,
        (r['message'] ?? (ok ? '' : fallback)).toString(),
        title: (r['title'] ?? '').toString(),
      );
    } catch (e) {
      return BirStep2Result(false, const {}, '$fallback ${_err(e)}'.trim());
    }
  }

  Future<BirStep2FormData?> editForm(int id, {bool fromView = false}) async {
    try {
      final r = await api.get('desktopBirStep2EditForm', {'id': '$id'});
      if (r['status'] != 'success') return null;
      return BirStep2FormData(
        fields: _strMap(r['form']),
        serialEntries: _entries(r['serial_entries']),
        showMin: r['show_min'] == true,
        showPtu: r['show_ptu'] == true,
        showPosDateIssued: r['show_pos_date_issued'] == true,
        isPendingRegistration: r['is_pending_registration'] == true,
        isUploadPtu: r['is_upload_ptu'] == true,
        showAdvanced: r['show_advanced'] == true,
        originalStep2: int.tryParse('${r['original_step2']}') ?? 0,
        fromView: fromView,
      );
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> customerById(int id) async {
    try {
      final r = await api.get('getCustomerbyID', {'id': '$id'});
      return r.isEmpty ? null : r;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> extractRegistrationPdf(String path) async {
    try {
      return await api.postPathMultipart(
        'pdf-extract-py.php',
        files: {'pdf': path},
      );
    } catch (e) {
      return {'error': 'Failed to process PDF file. Please try again.'};
    }
  }

  Future<BirStep2Result> registrationPrefill({
    required String customerId,
    required Map<String, dynamic> extraction,
  }) {
    return _guard(
      () => api.post(
        'desktopBirStep2PdfPrefill',
        body: {'customer_id': customerId, 'extraction': jsonEncode(extraction)},
      ),
      fallback: 'Failed to process PDF file. Please try again.',
    );
  }

  Future<BirStep2Result> prepareSave({
    required String isVat,
    required List<BirSerialEntry> entries,
    required bool isPendingRegistration,
    required int originalStep2,
  }) {
    return _guard(
      () => api.post(
        'desktopBirStep2PrepareSave',
        body: {
          'is_vat': isVat,
          'serial_entries': jsonEncode(entries.map((e) => e.toJson()).toList()),
          'is_pending_registration': isPendingRegistration ? '1' : '0',
          'original_step2': '$originalStep2',
        },
      ),
    );
  }

  Future<BirStep2Result> saveCustomer({
    required bool update,
    required Map<String, String> fields,
  }) async {
    try {
      final r = await api.post(
        update ? 'updateCustomer' : 'addcustomer',
        body: fields,
      );
      final ok = r['status'] == 'success';
      return BirStep2Result(ok, r, (r['message'] ?? '').toString());
    } catch (e) {
      return BirStep2Result(false, const {}, _err(e));
    }
  }

  Future<List<Map<String, dynamic>>> _jsonList(String path) async {
    try {
      final r = await api.getPath(path);
      final d = r['data'];
      if (d is List) {
        return d
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return <Map<String, dynamic>>[];
  }

  Future<List<Map<String, dynamic>>> provinces() =>
      _jsonList('ph-json/province.json');

  Future<List<Map<String, dynamic>>> cities() => _jsonList('ph-json/city.json');

  Future<List<Map<String, dynamic>>> businessLines() =>
      _jsonList('json-reason.js');

  Future<Map<String, dynamic>> extractPtu({
    required String customerId,
    required String serialNumber,
    required List<String> paths,
  }) async {
    try {
      final r = await api.postPathMultipartFiles(
        'step3-pdf-text.php',
        fields: {'cus_id': customerId, 'serialnum': serialNumber},
        files: [for (final p in paths) (field: 'pdf[]', path: p)],
      );
      return r;
    } catch (_) {
      return {'__failed': true};
    }
  }

  Future<BirStep2Result> ptuResolve({
    required String customerId,
    required String serialNumber,
    required dynamic extraction,
  }) {
    return _guard(
      () => api.post(
        'desktopBirStep2PtuResolve',
        body: {
          'customerId': customerId,
          'serialnum': serialNumber,
          'extraction': jsonEncode(extraction),
        },
      ),
      fallback: 'Failed to process PDF file. Please try again.',
    );
  }

  Future<BirStep2Result> step3Update(Map<String, String> payload) {
    return _guard(
      () => api.post('step3UpdateCustomerData', body: payload),
      fallback: 'Failed to update customer:',
    );
  }

  Future<BirStep2Result> advanceForm(int id) {
    return _guard(() => api.get('desktopBirStep2AdvanceForm', {'id': '$id'}));
  }

  Future<BirStep2Result> advancePayload(Map<String, String> fields) {
    return _guard(
      () => api.post('desktopBirStep2AdvancePayload', body: fields),
      fallback: 'Failed to complete registration:',
    );
  }

  Future<BirStep2Result> advancePtuManual(Map<String, String> payload) {
    return _guard(
      () => api.post('advancePtuManual', body: payload),
      fallback: 'Failed to complete registration:',
    );
  }
}
