import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api_client.dart';

String _s(dynamic v) => v == null ? '' : '$v';
int _i(dynamic v) => int.tryParse('${v ?? ''}') ?? 0;
double _d(dynamic v) => double.tryParse('${v ?? ''}') ?? 0;

List<Map<String, dynamic>> _maps(dynamic raw) => raw is List
    ? raw.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
    : <Map<String, dynamic>>[];

String peso(dynamic amount) {
  final v = _d(amount);
  final fixed = v.abs().toStringAsFixed(2);
  final parts = fixed.split('.');
  final whole = parts[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
  return '${v < 0 ? '-' : ''}₱$whole.${parts[1]}';
}

class VendorStats {
  const VendorStats({
    this.vendors = 0,
    this.active = 0,
    this.suspended = 0,
    this.revenueLabel = '₱0.00',
    this.openInvites = 0,
  });

  final int vendors;
  final int active;
  final int suspended;
  final String revenueLabel;
  final int openInvites;

  factory VendorStats.fromJson(Map<String, dynamic> j) => VendorStats(
        vendors: _i(j['vendors']),
        active: _i(j['active']),
        suspended: _i(j['suspended']),
        revenueLabel: _s(j['revenue_label']).isEmpty
            ? '₱0.00'
            : _s(j['revenue_label']),
        openInvites: _i(j['open_invites']),
      );
}

class VendorRow {
  VendorRow(this.raw);
  final Map<String, dynamic> raw;

  int get id => _i(raw['id']);
  String get vendorCode => _s(raw['vendor_code']);
  String get companyName => _s(raw['company_name']);
  String get contactPerson => _s(raw['contact_person']);
  String get email => _s(raw['email']);
  String get status => _s(raw['status']);
  String get lastLoginAt => _s(raw['last_login_at']);
  String get priceLabel => _s(raw['license_price_label']);
  int get submissions => _i(raw['submissions']);
  int get keysPaid => _i(raw['keys_paid']);
  String get revenueLabel => _s(raw['revenue_label']);
}

class VendorPage {
  const VendorPage({
    required this.rows,
    required this.total,
    required this.page,
    required this.perPage,
    required this.stats,
  });

  final List<VendorRow> rows;
  final int total;
  final int page;
  final int perPage;
  final VendorStats stats;
}

class VendorDetail {
  VendorDetail(this.raw);
  final Map<String, dynamic> raw;

  Map<String, dynamic> get vendor => raw['vendor'] is Map
      ? Map<String, dynamic>.from(raw['vendor'])
      : <String, dynamic>{};
  String v(String key) => _s(vendor[key]);
  int get id => _i(vendor['id']);
  bool get isActive => v('status') == 'active';

  Map<String, dynamic> get totals => raw['totals'] is Map
      ? Map<String, dynamic>.from(raw['totals'])
      : <String, dynamic>{};
  List<Map<String, dynamic>> get requests => _maps(raw['requests']);
  List<Map<String, dynamic>> get clients => _maps(raw['clients']);
  int get clientsTotal => _i(raw['clients_total']);
  Map<String, dynamic> get clientCounts => raw['client_counts'] is Map
      ? Map<String, dynamic>.from(raw['client_counts'])
      : <String, dynamic>{};
  List<Map<String, dynamic>> get logs => _maps(raw['logs']);
  int get logsTotal => _i(raw['logs_total']);
}

class VendorInvite {
  VendorInvite(this.raw);
  final Map<String, dynamic> raw;

  int get id => _i(raw['id']);
  String get note => _s(raw['note']);
  String get priceLabel => _s(raw['license_price_label']);
  String get createdByName => _s(raw['created_by_name']);
  String get createdAt => _s(raw['created_at']);
  String get expiresAt => _s(raw['expires_at']);
  String get usedAt => _s(raw['used_at']);
  String get usedByCode => _s(raw['used_by_code']);
  bool get isActive => _i(raw['is_active']) == 1;
  bool get isUsed => _i(raw['is_used']) == 1;
}

class VmResult {
  const VmResult({required this.ok, this.message = '', this.data = const {}});
  final bool ok;
  final String message;
  final Map<String, dynamic> data;

  VendorDetail? get detail =>
      data['vendor'] is Map ? VendorDetail(data) : null;
}

class VendorPortalService {
  VendorPortalService(this.api);
  final ApiClient api;

  static const _endpoint = 'vendor-management-ajax.php';
  String? _csrf;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = api.baseUrl.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base/$path').replace(queryParameters: query);
  }

  Map<String, dynamic> _decode(http.Response res) {
    try {
      final decoded = jsonDecode(res.body.trim());
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    throw Exception(res.statusCode >= 400
        ? 'HTTP ${res.statusCode}'
        : 'Error contacting server.');
  }

  Future<Map<String, dynamic>> _get(Map<String, String> query) async {
    final res = await http.get(_uri(_endpoint, query), headers: {
      ...api.authHeaders(),
      'Accept': 'application/json',
    });
    return _decode(res);
  }

  Future<VendorPage> list({
    String q = '',
    String filter = 'all',
    int page = 1,
  }) async {
    final res = await _get(
        {'action': 'list', 'q': q, 'filter': filter, 'page': '$page'});
    if (res['success'] != true) {
      throw Exception(_s(res['message']).isEmpty
          ? 'Could not load vendors.'
          : _s(res['message']));
    }
    return VendorPage(
      rows: _maps(res['rows']).map(VendorRow.new).toList(),
      total: _i(res['total']),
      page: _i(res['page']) > 0 ? _i(res['page']) : page,
      perPage: _i(res['per_page']) > 0 ? _i(res['per_page']) : 25,
      stats: res['stats'] is Map
          ? VendorStats.fromJson(Map<String, dynamic>.from(res['stats']))
          : const VendorStats(),
    );
  }

  Future<VendorDetail> detail(int vendorId) async {
    final res = await _get({'action': 'detail', 'vendor_id': '$vendorId'});
    if (res['success'] != true) {
      throw Exception(_s(res['message']).isEmpty
          ? 'Could not load this vendor.'
          : _s(res['message']));
    }
    return VendorDetail(res);
  }

  Future<List<VendorInvite>> invites() async {
    final res = await _get({'action': 'invites'});
    if (res['success'] != true) {
      throw Exception(_s(res['message']).isEmpty
          ? 'Could not load invites.'
          : _s(res['message']));
    }
    return _maps(res['invites']).map(VendorInvite.new).toList();
  }

  Future<String> _token({bool refresh = false}) async {
    if (_csrf != null && !refresh) return _csrf!;
    try {
      final res = await api.get('vendorPortalCsrf');
      final t = _s(res['csrf_token']);
      if (t.isNotEmpty) return _csrf = t;
    } catch (_) {}
    try {
      final res = await http.get(_uri('vendor-management.php'),
          headers: api.authHeaders());
      final m = RegExp(r'var CSRF = "([^"]+)"').firstMatch(res.body);
      if (m != null) return _csrf = m.group(1)!;
    } catch (_) {}
    return '';
  }

  Future<VmResult> _post(String action, Map<String, String> data,
      {bool retried = false}) async {
    try {
      final token = await _token(refresh: retried);
      final res = await http.post(
        _uri(_endpoint),
        headers: {...api.authHeaders(), 'Accept': 'application/json'},
        body: {'action': action, 'csrf_token': token, ...data},
      );
      final body = _decode(res);
      final ok = body['success'] == true;
      final msg = _s(body['message']);
      if (!ok &&
          !retried &&
          (res.statusCode == 419 ||
              msg.startsWith('Your session could not be verified'))) {
        return _post(action, data, retried: true);
      }
      return VmResult(
        ok: ok,
        message: msg.isNotEmpty
            ? msg
            : (ok ? 'Saved.' : 'Could not save the change.'),
        data: body,
      );
    } catch (_) {
      return const VmResult(ok: false, message: 'Error contacting server.');
    }
  }

  Future<VmResult> updateDetails(
    int vendorId, {
    required String vendorCode,
    required String companyName,
    required String contactPerson,
    required String email,
    required String mobile,
    required String address,
  }) =>
      _post('updateDetails', {
        'vendor_id': '$vendorId',
        'vendor_code': vendorCode,
        'company_name': companyName,
        'contact_person': contactPerson,
        'email': email,
        'mobile': mobile,
        'address': address,
      });

  Future<VmResult> setPrice(int vendorId, String price) => _post(
      'setPrice', {'vendor_id': '$vendorId', 'license_price': price});

  Future<VmResult> setPassword(int vendorId, String pw, String confirm) =>
      _post('setPassword', {
        'vendor_id': '$vendorId',
        'password': pw,
        'confirm_password': confirm,
      });

  Future<VmResult> setStatus(int vendorId, String status) =>
      _post('setStatus', {'vendor_id': '$vendorId', 'status': status});

  Future<VmResult> createInvite({
    required String note,
    required String price,
    required String hours,
  }) =>
      _post('createInvite',
          {'note': note, 'license_price': price, 'hours': hours});

  Future<VmResult> revokeInvite(int inviteId) =>
      _post('revokeInvite', {'invite_id': '$inviteId'});

  String taxpayerPortalUrl(int clientId) =>
      api.actionUrl('staffOpenTaxpayerPortal', {'id': '$clientId'});

  String get vendorPortalUrl =>
      _uri('vendor-portal').toString();
}
