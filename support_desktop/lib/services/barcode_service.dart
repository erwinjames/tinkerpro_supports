import '../api_client.dart';

String _s(dynamic v) => v == null ? '' : '$v';
int _i(dynamic v) => v is int ? v : int.tryParse('${v ?? ''}') ?? 0;
DateTime? _d(dynamic v) {
  final raw = _s(v).trim();
  if (raw.isEmpty) return null;
  return DateTime.tryParse(raw.replaceFirst(' ', 'T'));
}

List<Map<String, dynamic>> _maps(dynamic raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((m) => Map<String, dynamic>.from(m))
      .toList();
}

String _pick(Map<String, dynamic>? m, List<String> keys) {
  if (m == null) return '';
  for (final k in keys) {
    final v = m[k];
    if (v != null && '$v' != '') return '$v';
  }
  return '';
}

class BcException implements Exception {
  BcException(this.message);
  final String message;
  @override
  String toString() => message;
}

class BcInvoiceHit {
  const BcInvoiceHit({required this.invoice, required this.customer});
  final String invoice;
  final String customer;

  factory BcInvoiceHit.fromJson(Map<String, dynamic> item) {
    final c = item['customer'] is Map
        ? Map<String, dynamic>.from(item['customer'])
        : item;
    final inv = _pick(item, const [
      'invoice_number',
      'invoiceNumber',
      'invoice_no',
      'invoiceNo',
      'number',
      'invoice',
    ]);
    var cust = _pick(c, const ['display_name', 'name', 'company_name', 'customerName']);
    if (cust.isEmpty) cust = _pick(item, const ['customer_name', 'name']);
    return BcInvoiceHit(invoice: inv, customer: cust);
  }
}

class BcActiveInvoice {
  const BcActiveInvoice({
    required this.invoice,
    required this.customer,
    required this.batch,
  });
  final String invoice;
  final String customer;
  final int batch;
}

class BcBarcode {
  BcBarcode(this.raw);
  final Map<String, dynamic> raw;
  int get id => _i(raw['id']);
  String get code => _s(raw['code']);
  String get invoiceNumber => _s(raw['invoice_number']);
  String get customerName => _s(raw['customer_name']);
  int get batch => _i(raw['batch']);
  String get scannedBy => _s(raw['scanned_by']);
  DateTime? get createdAt => _d(raw['created_at']);
}

class BcBatch {
  const BcBatch({required this.batch, required this.count, this.lastScan});
  final int batch;
  final int count;
  final DateTime? lastScan;
}

class BcList {
  const BcList({
    required this.rows,
    required this.batch,
    required this.nextBatch,
    required this.batches,
  });
  final List<BcBarcode> rows;
  final int batch;
  final int nextBatch;
  final List<BcBatch> batches;
}

class BcScanResult {
  BcScanResult(this.raw);
  final Map<String, dynamic> raw;
  String get status => _s(raw['status']);
  String get message => _s(raw['message']);
  String get code => _s(raw['code']);
  int get id => _i(raw['id']);
  String get invoiceNumber => _s(raw['invoice_number']);
  String get customerName => _s(raw['customer_name']);
  int get batch => _i(raw['batch']);
  DateTime? get firstScanned => _d(raw['first_scanned']);
}

class BcBatchResult {
  const BcBatchResult({required this.batch, required this.existingInNew});
  final int batch;
  final int existingInNew;
}

class BarcodeService {
  BarcodeService(this.api);
  final ApiClient api;

  Future<List<BcInvoiceHit>> searchInvoices(String term) async {
    final res = await api.get('searchInvoiceCustomer', {'q': term});
    if (_s(res['error']).isNotEmpty) throw BcException(_s(res['error']));
    dynamic list = res['data'];
    if (list is Map && list['data'] is List) list = list['data'];
    return _maps(list).map(BcInvoiceHit.fromJson).toList();
  }

  Future<BcActiveInvoice?> activeInvoice() async {
    final res = await api.get('getBarcodeInvoice');
    final d = res['data'];
    if (d is! Map || _s(d['invoice_number']).isEmpty) return null;
    return BcActiveInvoice(
      invoice: _s(d['invoice_number']),
      customer: _s(d['customer_name']),
      batch: _i(d['batch']),
    );
  }

  Future<void> setActiveInvoice(String invoice, String customer) async {
    await api.post('setBarcodeInvoice',
        body: {'invoice_number': invoice, 'customer_name': customer});
  }

  Future<void> clearActiveInvoice() async {
    await api.post('clearBarcodeInvoice');
  }

  Future<BcList> list(String invoice, {int? batch}) async {
    final res = await api.get('getBarcodes', {
      'limit': '300',
      'invoice_number': invoice,
      if (batch != null) 'batch': '$batch',
    });
    return BcList(
      rows: _maps(res['data']).map(BcBarcode.new).toList(),
      batch: _i(res['batch']),
      nextBatch: _i(res['next_batch']),
      batches: _maps(res['batches'])
          .map((b) => BcBatch(
              batch: _i(b['batch']),
              count: _i(b['count']),
              lastScan: _d(b['last_scan'])))
          .toList(),
    );
  }

  Future<BcScanResult> scan(String code, String invoice, String customer) async {
    final res = await api.post('scanBarcode', body: {
      'code': code,
      'invoice_number': invoice,
      'customer_name': customer,
    });
    return BcScanResult(res);
  }

  Future<void> delete(int id) async {
    final res = await api.post('deleteBarcode', body: {'id': '$id'});
    if (_s(res['status']) != 'success') {
      throw BcException(_s(res['message']).isEmpty ? 'Delete failed.' : _s(res['message']));
    }
  }

  Future<BcBatchResult> startBatch(String invoice, String batch) async {
    final res = await api.post('resetBarcodeBatch',
        body: {'invoice_number': invoice, 'batch': batch});
    if (_s(res['status']) != 'success') {
      throw BcException(_s(res['message']).isEmpty
          ? 'Could not start the batch.'
          : _s(res['message']));
    }
    return BcBatchResult(
        batch: _i(res['batch']), existingInNew: _i(res['existing_in_new']));
  }

  Future<BcBatchResult> clearBatch(String invoice, int batch) async {
    final res = await api.post('clearBarcodeBatch',
        body: {'invoice_number': invoice, 'batch': '$batch'});
    if (_s(res['status']) != 'success') {
      throw BcException(_s(res['message']).isEmpty
          ? 'Could not reset the batch.'
          : _s(res['message']));
    }
    return BcBatchResult(batch: _i(res['batch']), existingInNew: 0);
  }
}
