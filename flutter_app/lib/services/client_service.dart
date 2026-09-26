import 'dart:convert';
import 'dart:io' as io;

import 'package:path_provider/path_provider.dart';

import '../api_client.dart';
import '../models/client_models.dart';
import '../models/delivery_models.dart';

class ClientService {
  ClientService(this.api);
  final ApiClient api;

  static const Duration _deliveryMinAge = Duration(seconds: 45);
  static const Duration _readyCountMinAge = Duration(seconds: 60);

  DeliveryListResult? _deliveryCache;
  DateTime? _deliveryCacheAt;
  Future<DeliveryListResult>? _deliveryInflight;
  int? _readyCountCache;
  DateTime? _readyCountAt;

  Future<({List<ClientBrief> rows, int total})> list({
    String? search,
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final res = await api.get('getClient', {
        'page': '$page',
        'limit': '$limit',
        if (search != null && search.isNotEmpty) 'search': search,
      });
      final raw = res['data'];
      final total = _asInt(res['totalRecords']);
      if (raw is List) {
        final rows = raw
            .whereType<Map>()
            .map((e) => ClientBrief.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        return (rows: rows, total: total == 0 ? rows.length : total);
      }
    } catch (_) {}
    return (rows: const <ClientBrief>[], total: 0);
  }

  Future<({bool ok, String? message, int customerId})> importToBir(
    int id,
  ) async {
    try {
      final res = await api.post(
        'importClientToBir',
        body: {'id': id.toString()},
      );
      final ok = res['status'] == 'success';
      final raw = res['customer_id'];
      final customerId = raw is int ? raw : int.tryParse('${raw ?? ''}') ?? 0;
      return (
        ok: ok,
        message: res['message']?.toString(),
        customerId: customerId,
      );
    } catch (_) {
      return (
        ok: false,
        message: 'Could not import client to BIR Registration.',
        customerId: 0,
      );
    }
  }

  Future<ClientDetail?> detail(int id) async {
    try {
      final res = await api.get('getClientbyID', {'id': id.toString()});
      if (res['id'] != null) return ClientDetail.fromJson(res);
      final data = res['data'];
      if (data is Map) {
        return ClientDetail.fromJson(Map<String, dynamic>.from(data));
      }
    } catch (_) {}
    return null;
  }

  Future<ClientSaveResult> save({
    int? id,
    required Map<String, String> fields,
    required List<ClientInvoiceItem> items,
  }) async {
    try {
      final body = Map<String, String>.from(fields);
      final payloadItems = items
          .where((i) => !i.isEmpty)
          .map((i) => i.toJson())
          .toList();
      if (payloadItems.isNotEmpty) {
        body['invoiceItemsData'] = jsonEncode(payloadItems);
      }
      final String action;
      if (id == null) {
        action = 'addClient';
      } else {
        action = 'updateClient';
        body['clientID'] = id.toString();
      }
      final res = await api.post(action, body: body);
      final ok = res['status'] == 'success' || res['success'] == true;
      final msg =
          (res['message'] ??
                  (ok ? 'Saved' : 'Could not save. Please try again.'))
              .toString();
      return ClientSaveResult(ok: ok, message: msg, clientId: id);
    } catch (_) {
      return ClientSaveResult(
        ok: false,
        message: 'Network error. Check your connection and try again.',
      );
    }
  }

  Future<bool> delete(int id) async {
    try {
      final res = await api.post('deleteClient', body: {'id': id.toString()});
      return res['status'] == 'success' || res['success'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<ClientInvoiceCheck> checkInvoice(
    String invoice, {
    String branch = '',
  }) async {
    try {
      final res = await api.get('checkClientInvoice', {
        'invoice': invoice,
        'branch': branch,
      });
      final exists = res['exists'] == true || res['exists'] == 1;
      final matched = res['branch_matched'];
      return ClientInvoiceCheck(
        exists: exists,
        branch: (res['branch'] ?? '').toString(),
        branchMatched: matched == null || matched == true || matched == 1,
        clientName: (res['client_name'] ?? '').toString(),
      );
    } catch (_) {
      return ClientInvoiceCheck.free;
    }
  }

  Future<({bool ok, String message})> addSpecReplacement({
    required int clientId,
    required String src,
    required int index,
    required String serialField,
    required String oldComponent,
    required String newComponent,
    required String newSerial,
  }) async {
    try {
      final res = await api.post(
        'addClientSpecReplacement',
        body: {
          'clientID': clientId.toString(),
          'src': src,
          'idx': index.toString(),
          'serialField': serialField,
          'oldComponent': oldComponent,
          'newComponent': newComponent,
          'newSerial': newSerial,
        },
      );
      final ok = res['status'] == 'success';
      return (
        ok: ok,
        message:
            (res['message'] ??
                    (ok
                        ? 'Replacement recorded'
                        : 'Could not record the replacement.'))
                .toString(),
      );
    } catch (_) {
      return (ok: false, message: 'Could not record the replacement.');
    }
  }

  Future<List<Map<String, dynamic>>> parseInvoiceSpecs(
    List<String> components,
  ) async {
    if (components.isEmpty) return const [];
    try {
      final res = await api.postJson(
        'parseInvoiceSpecs',
        body: {'components': components},
      );
      if (res['status'] != 'success') return const [];
      final data = res['data'];
      if (data is List) {
        return data
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<({List<Map<String, dynamic>> rows, String error})> searchInvoice(
    String term,
  ) async {
    final q = term.trim();
    if (q.isEmpty) return (rows: const <Map<String, dynamic>>[], error: '');
    try {
      final res = await api.get('searchInvoiceCustomer', {'q': q});
      final error = res['error'];
      if (error != null) {
        return (rows: const <Map<String, dynamic>>[], error: error.toString());
      }
      if (res['invoice_number'] != null) {
        return (rows: <Map<String, dynamic>>[res], error: '');
      }
      final raw = res['data'] ?? res['results'] ?? res['invoices'];
      if (raw is List) {
        return (
          rows: raw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList(),
          error: '',
        );
      }
      return (rows: const <Map<String, dynamic>>[], error: '');
    } catch (_) {
      return (
        rows: const <Map<String, dynamic>>[],
        error: 'Could not reach the invoice service.',
      );
    }
  }

  Future<DeliveryListResult> deliveries({bool force = false}) {
    final cached = _deliveryCache;
    final at = _deliveryCacheAt;
    if (!force &&
        cached != null &&
        at != null &&
        DateTime.now().difference(at) < _deliveryMinAge) {
      return Future<DeliveryListResult>.value(cached);
    }
    final inflight = _deliveryInflight;
    if (inflight != null) return inflight;
    final request = _fetchDeliveries();
    _deliveryInflight = request;
    return request.whenComplete(() => _deliveryInflight = null);
  }

  Future<DeliveryListResult> _fetchDeliveries() async {
    final res = await api.get('getDeliveries', {'per_page': '100'});
    final error = res['error'];
    if (error != null && res['data'] is! List) {
      throw DeliveryException(
        (res['message'] ?? error).toString(),
        retryAfter: _asInt(res['retry_after']),
      );
    }
    final raw = res['data'];
    final rows = raw is List
        ? raw
              .whereType<Map>()
              .map((e) => DeliveryBrief.fromJson(Map<String, dynamic>.from(e)))
              .toList()
        : <DeliveryBrief>[];
    rows.sort(
      (a, b) =>
          deliveryStatusRank(a.status).compareTo(deliveryStatusRank(b.status)),
    );
    final result = DeliveryListResult(
      rows: rows,
      stale: res['stale'] == true,
      cached: res['cached'] == true,
      message: (res['message'] ?? '').toString(),
    );
    _deliveryCache = result;
    _deliveryCacheAt = DateTime.now();
    _readyCountCache = result.readyCount;
    _readyCountAt = _deliveryCacheAt;
    return result;
  }

  Future<int> readyDeliveryCount({bool force = false}) async {
    final cached = _readyCountCache;
    final at = _readyCountAt;
    if (!force &&
        cached != null &&
        at != null &&
        DateTime.now().difference(at) < _readyCountMinAge) {
      return cached;
    }
    try {
      final res = await api.get('getDeliveries', {
        'light': '1',
        'status': 'Ready for Delivery',
        'per_page': '100',
      });
      final raw = res['data'];
      if (raw is! List) return cached ?? 0;
      final count = raw
          .whereType<Map>()
          .where((e) => (e['status'] ?? '').toString() == 'Ready for Delivery')
          .length;
      _readyCountCache = count;
      _readyCountAt = DateTime.now();
      return count;
    } catch (_) {
      return cached ?? 0;
    }
  }

  Future<DeliveryDetailResult> delivery(String id) async {
    final res = await api.get('getDelivery', {'id': id});
    final data = res['data'];
    if (data is! Map) {
      throw DeliveryException(
        (res['message'] ?? res['error'] ?? 'Failed to load delivery.')
            .toString(),
        retryAfter: _asInt(res['retry_after']),
      );
    }
    return DeliveryDetailResult(
      detail: DeliveryDetail.fromJson(Map<String, dynamic>.from(data)),
      stale: res['stale'] == true,
      message: (res['message'] ?? '').toString(),
    );
  }

  Future<DeliveryStatusResult> updateDeliveryStatus({
    required String id,
    required String status,
    bool notify = false,
    bool sms = false,
  }) async {
    try {
      final res = await api.post(
        'updateDeliveryStatus',
        body: {
          'id': id,
          'status': status,
          'notify': notify ? '1' : '0',
          'sms': sms ? '1' : '0',
        },
      );
      final ok = res['success'] == true;
      if (ok) {
        _deliveryCache = null;
        _deliveryCacheAt = null;
        _readyCountCache = null;
        _readyCountAt = null;
      }
      final email = res['email'];
      final smsRes = res['sms'];
      return DeliveryStatusResult(
        ok: ok,
        message: (res['message'] ?? (ok ? 'Status updated.' : '')).toString(),
        emailSent: email is Map && email['success'] == true,
        emailMessage: email is Map ? (email['message'] ?? '').toString() : '',
        smsSent: smsRes is Map && smsRes['success'] == true,
        smsMessage: smsRes is Map ? (smsRes['message'] ?? '').toString() : '',
      );
    } on HttpException catch (e) {
      return DeliveryStatusResult(ok: false, message: e.message);
    } catch (_) {
      return const DeliveryStatusResult(
        ok: false,
        message: 'Failed to update status.',
      );
    }
  }

  Future<String> downloadDeliveryPdf(String id, String doc) async {
    final uri = Uri.parse(
      api.actionUrl('getDeliveryPdf', {'id': id, 'doc': doc, 'download': '1'}),
    );
    final res = await api.rawGet(uri, json: false);
    final bytes = res.bodyBytes;
    final type = (res.headers['content-type'] ?? '').toLowerCase();
    final looksPdf =
        bytes.length > 4 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46;
    if (res.statusCode < 200 ||
        res.statusCode >= 300 ||
        (!looksPdf && !type.contains('pdf'))) {
      throw DeliveryException(
        _pdfError(res.body, res.statusCode),
        retryAfter: _retryAfter(res.body),
      );
    }
    final dir = await getTemporaryDirectory();
    final safeId = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    final file = io.File('${dir.path}/$doc-$safeId.pdf');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}

class DeliveryException implements Exception {
  DeliveryException(this.message, {this.retryAfter = 0});

  final String message;
  final int retryAfter;

  @override
  String toString() => message;
}

String _pdfError(String body, int statusCode) {
  try {
    final decoded = jsonDecode(body.trim());
    if (decoded is Map) {
      final message = decoded['message'];
      if (message is String && message.trim().isNotEmpty) return message.trim();
    }
  } catch (_) {}
  if (statusCode == 429) {
    return 'The document service is handling too many requests. Please try again shortly.';
  }
  return 'Could not fetch the requested PDF.';
}

int _retryAfter(String body) {
  try {
    final decoded = jsonDecode(body.trim());
    if (decoded is Map) return _asInt(decoded['retry_after']);
  } catch (_) {}
  return 0;
}

int _asInt(Object? value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}
