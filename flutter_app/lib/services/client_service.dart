import 'dart:convert';

import '../api_client.dart';
import '../models/client_models.dart';

/// Service layer for the "Client & Data Sheet" feature. Mirrors the web
/// `ClientFacade` actions on `api.php`. Cookie auth is handled by [ApiClient].
class ClientService {
  ClientService(this.api);
  final ApiClient api;

  /// Paginated list. `getClient` returns {data, totalRecords, limit, page}.
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

  /// Full client record + its invoice items. Null on failure/not found.
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

  /// Create (id == null) or update. [fields] carries the exact `client*` keys;
  /// [items] is serialized into `invoiceItemsData`.
  Future<ClientSaveResult> save({
    int? id,
    required Map<String, String> fields,
    required List<ClientInvoiceItem> items,
  }) async {
    try {
      final body = Map<String, String>.from(fields);
      body['invoiceItemsData'] =
          jsonEncode(items.where((i) => !i.isEmpty).map((i) => i.toJson()).toList());
      final String action;
      if (id == null) {
        action = 'addClient';
      } else {
        action = 'updateClient';
        body['clientID'] = id.toString();
      }
      final res = await api.post(action, body: body);
      final ok = res['status'] == 'success' || res['success'] == true;
      final msg = (res['message'] ??
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

  /// Whether an invoice number is already recorded on a client.
  Future<bool> checkInvoice(String invoice) async {
    try {
      final res = await api.get('checkClientInvoice', {'invoice': invoice});
      return res['exists'] == true || res['exists'] == 1;
    } catch (_) {
      return false;
    }
  }

  /// Refine raw component strings into {component, specification, brand} via the
  /// server's Groq parser (`parseInvoiceSpecs`). Best-effort — empty on failure.
  /// The result aligns by index with the input list.
  Future<List<Map<String, dynamic>>> parseInvoiceSpecs(
      List<String> components) async {
    if (components.isEmpty) return const [];
    try {
      final res =
          await api.postJson('parseInvoiceSpecs', body: {'components': components});
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

  /// Look up invoices on the external Invoice service (for auto-fill). Returns
  /// the raw invoice objects; the form maps the fields it needs.
  Future<List<Map<String, dynamic>>> searchInvoice(String term) async {
    final q = term.trim();
    if (q.isEmpty) return const [];
    try {
      final res = await api.get('searchInvoiceCustomer', {'q': q});
      if (res['error'] != null) return const [];
      if (res['invoice_number'] != null) return [res];
      final raw = res['data'] ?? res['results'] ?? res['invoices'];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return const [];
  }
}

int _asInt(Object? value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}
