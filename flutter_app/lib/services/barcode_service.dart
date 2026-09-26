import 'dart:convert';

import '../api_client.dart';
import '../models/barcode_models.dart';

class InvoiceSearchResult {
  const InvoiceSearchResult({required this.matches, this.error});

  final List<InvoiceMatch> matches;
  final String? error;
}

class BarcodeService {
  BarcodeService(this._api);
  final ApiClient _api;

  Future<InvoiceSearchResult> searchInvoices(String term) async {
    try {
      final response = await _api.rawGet(
        _api.pathUri('api.php', {'action': 'searchInvoiceCustomer', 'q': term}),
      );
      Object? decoded;
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        return const InvoiceSearchResult(
          matches: [],
          error: 'Could not reach the invoice service.',
        );
      }
      if (decoded is Map && decoded['error'] != null) {
        return InvoiceSearchResult(
          matches: const [],
          error: decoded['error'].toString(),
        );
      }
      final list = _extractList(decoded);
      final matches = <InvoiceMatch>[];
      for (final item in list) {
        if (item is! Map) continue;
        final map = item.cast<String, dynamic>();
        matches.add(
          InvoiceMatch(
            invoiceNumber: _invoiceNoOf(map),
            customerName: _customerOf(map),
          ),
        );
      }
      return InvoiceSearchResult(matches: matches);
    } catch (_) {
      return const InvoiceSearchResult(
        matches: [],
        error: 'Could not reach the invoice service.',
      );
    }
  }

  Future<BarcodeInvoice?> activeInvoice() async {
    try {
      final res = await _api.get('getBarcodeInvoice');
      final data = res['data'];
      if (data is Map && (data['invoice_number'] ?? '').toString().isNotEmpty) {
        return BarcodeInvoice(
          invoiceNumber: data['invoice_number'].toString(),
          customerName: (data['customer_name'] ?? '').toString(),
          batch: barcodeInt(data['batch']) == 0 ? 1 : barcodeInt(data['batch']),
        );
      }
    } catch (_) {}
    return null;
  }

  Future<void> setActiveInvoice(String invoice, String customer) async {
    try {
      await _api.post(
        'setBarcodeInvoice',
        body: {'invoice_number': invoice, 'customer_name': customer},
      );
    } catch (_) {}
  }

  Future<void> clearActiveInvoice() async {
    try {
      await _api.post('clearBarcodeInvoice', body: const {});
    } catch (_) {}
  }

  Future<BarcodeList> list(String invoice, {int? batch}) async {
    try {
      final res = await _api.get('getBarcodes', {
        'limit': '300',
        'invoice_number': invoice,
        if (batch != null) 'batch': '$batch',
      });
      if (res['success'] != true) return BarcodeList.failed;
      final rows = res['data'];
      final batches = res['batches'];
      return BarcodeList(
        ok: true,
        rows: rows is List
            ? rows
                  .whereType<Map>()
                  .map((e) => BarcodeRecord.fromJson(e.cast<String, dynamic>()))
                  .toList()
            : const [],
        batch: barcodeInt(res['batch']),
        nextBatch: barcodeInt(res['next_batch']),
        batches: batches is List
            ? batches
                  .whereType<Map>()
                  .map((e) => BarcodeBatch.fromJson(e.cast<String, dynamic>()))
                  .toList()
            : const [],
      );
    } catch (_) {
      return BarcodeList.failed;
    }
  }

  Future<BarcodeScanResult> scan({
    required String code,
    required String invoice,
    required String customer,
  }) async {
    try {
      final res = await _api.post(
        'scanBarcode',
        body: {
          'code': code,
          'invoice_number': invoice,
          'customer_name': customer,
        },
      );
      return BarcodeScanResult.fromJson(res, code);
    } catch (_) {
      return BarcodeScanResult(
        outcome: ScanOutcome.error,
        code: code,
        message: 'Network error — is the server reachable?',
      );
    }
  }

  Future<BarcodeActionResult> delete(int id) =>
      _action('deleteBarcode', {'id': '$id'});

  Future<BarcodeActionResult> startBatch(String invoice, int batch) => _action(
    'resetBarcodeBatch',
    {'invoice_number': invoice, 'batch': '$batch'},
  );

  Future<BarcodeActionResult> resetBatch(String invoice, int batch) => _action(
    'clearBarcodeBatch',
    {'invoice_number': invoice, 'batch': '$batch'},
  );

  Future<BarcodeActionResult> _action(
    String action,
    Map<String, String> body,
  ) async {
    try {
      final res = await _api.post(action, body: body);
      return BarcodeActionResult(
        ok: res['status'] == 'success',
        message: res['message']?.toString(),
        batch: barcodeInt(res['batch']),
        existingInNew: barcodeInt(res['existing_in_new']),
        deleted: barcodeInt(res['deleted']),
      );
    } catch (_) {
      return const BarcodeActionResult(
        ok: false,
        message: 'Network error — please try again.',
      );
    }
  }

  List<Object?> _extractList(Object? resp) {
    if (resp is List) return resp;
    if (resp is Map) {
      final data = resp['data'];
      if (data is List) return data;
      if (data is Map && data['data'] is List) return data['data'] as List;
    }
    return const [];
  }

  String _pick(Map<String, dynamic>? obj, List<String> keys) {
    if (obj == null) return '';
    for (final k in keys) {
      final v = obj[k];
      if (v != null && v.toString().isNotEmpty) return v.toString();
    }
    return '';
  }

  String _invoiceNoOf(Map<String, dynamic> item) => _pick(item, const [
    'invoice_number',
    'invoiceNumber',
    'invoice_no',
    'invoiceNo',
    'number',
    'invoice',
  ]);

  String _customerOf(Map<String, dynamic> item) {
    final nested = item['customer'];
    final c = nested is Map ? nested.cast<String, dynamic>() : item;
    final fromCustomer = _pick(c, const [
      'display_name',
      'name',
      'company_name',
      'customerName',
    ]);
    if (fromCustomer.isNotEmpty) return fromCustomer;
    return _pick(item, const ['customer_name', 'name']);
  }
}
