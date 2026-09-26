import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../api_client.dart';

int _int(dynamic v) {
  if (v is int) return v;
  if (v is bool) return v ? 1 : 0;
  return int.tryParse('${v ?? ''}') ?? 0;
}

String _str(dynamic v) => v == null ? '' : '$v';

bool _bool(dynamic v) {
  if (v is bool) return v;
  return _int(v) == 1;
}

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Map<String, dynamic>> _maps(dynamic v) => v is List
    ? v.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
    : <Map<String, dynamic>>[];

class TpStage {
  const TpStage(this.key, this.label);
  final String key;
  final String label;

  static TpStage of(int cStatus, int step2, int finalStep) {
    if (finalStep == 1) return const TpStage('completed', 'Completed');
    if (cStatus == 1 && step2 == 1) {
      return const TpStage('awaiting', 'Awaiting PTU');
    }
    if (cStatus == 1) return const TpStage('processed', 'Waiting for BIR');
    return const TpStage('submitted', 'Submitted');
  }
}

class TpStats {
  const TpStats({
    this.taxpayers = 0,
    this.withPassword = 0,
    this.employeesActive = 0,
    this.employeesInvited = 0,
  });
  final int taxpayers;
  final int withPassword;
  final int employeesActive;
  final int employeesInvited;

  factory TpStats.fromJson(Map<String, dynamic> j) => TpStats(
        taxpayers: _int(j['taxpayers']),
        withPassword: _int(j['with_password']),
        employeesActive: _int(j['employees_active']),
        employeesInvited: _int(j['employees_invited']),
      );
}

class TpRow {
  const TpRow({
    required this.id,
    required this.companyName,
    required this.tin,
    required this.branchCode,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.stage,
    required this.ownerPasswordSet,
    required this.employeesActive,
    required this.employeesTotal,
  });

  final int id;
  final String companyName;
  final String tin;
  final String branchCode;
  final String firstName;
  final String lastName;
  final String email;
  final TpStage stage;
  final bool ownerPasswordSet;
  final int employeesActive;
  final int employeesTotal;

  String get ownerName =>
      [firstName, lastName].where((s) => s.isNotEmpty).join(' ');

  factory TpRow.fromJson(Map<String, dynamic> j) => TpRow(
        id: _int(j['id']),
        companyName: _str(j['company_name']),
        tin: _str(j['tin']),
        branchCode: _str(j['branch_code']),
        firstName: _str(j['first_name']),
        lastName: _str(j['last_name']),
        email: _str(j['email']),
        stage: TpStage.of(
            _int(j['c_status']), _int(j['step2']), _int(j['final_step'])),
        ownerPasswordSet: _bool(j['owner_password_set']),
        employeesActive: _int(j['employees_active']),
        employeesTotal: _int(j['employees_total']),
      );
}

class TpListResult {
  const TpListResult({
    required this.rows,
    required this.total,
    required this.page,
    required this.perPage,
    required this.stats,
  });
  final List<TpRow> rows;
  final int total;
  final int page;
  final int perPage;
  final TpStats stats;
}

class TpEmployee {
  const TpEmployee({
    required this.id,
    required this.fullName,
    required this.email,
    required this.position,
    required this.status,
    required this.invitedAt,
    required this.lastLoginAt,
  });

  final int id;
  final String fullName;
  final String email;
  final String position;
  final String status;
  final String invitedAt;
  final String lastLoginAt;

  factory TpEmployee.fromJson(Map<String, dynamic> j) => TpEmployee(
        id: _int(j['id']),
        fullName: _str(j['full_name']),
        email: _str(j['email']),
        position: _str(j['position']),
        status: _str(j['status']),
        invitedAt: _str(j['invited_at']),
        lastLoginAt: _str(j['last_login_at']),
      );
}

class TpDetail {
  const TpDetail({
    required this.id,
    required this.companyName,
    required this.ownerName,
    required this.email,
    required this.tin,
    required this.branchCode,
    required this.stage,
    required this.ownerPasswordSet,
    required this.ownerPasswordSetAt,
    required this.employees,
    required this.maxEmployees,
  });

  final int id;
  final String companyName;
  final String ownerName;
  final String email;
  final String tin;
  final String branchCode;
  final TpStage stage;
  final bool ownerPasswordSet;
  final String ownerPasswordSetAt;
  final List<TpEmployee> employees;
  final int maxEmployees;

  factory TpDetail.fromJson(Map<String, dynamic> j) {
    final max = _int(j['max_employees']);
    return TpDetail(
      id: _int(j['id']),
      companyName: _str(j['company_name']),
      ownerName: _str(j['owner_name']),
      email: _str(j['email']),
      tin: _str(j['tin']),
      branchCode: _str(j['branch_code']),
      stage: TpStage.of(
          _int(j['c_status']), _int(j['step2']), _int(j['final_step'])),
      ownerPasswordSet: _bool(j['owner_password_set']),
      ownerPasswordSetAt: _str(j['owner_password_set_at']),
      employees: _maps(j['employees']).map(TpEmployee.fromJson).toList(),
      maxEmployees: max > 0 ? max : 25,
    );
  }
}

class TpActionResult {
  const TpActionResult(this.success, this.message, this.detail);
  final bool success;
  final String message;
  final TpDetail? detail;
}

class TpClient {
  const TpClient({
    required this.id,
    required this.companyName,
    required this.tin,
    required this.branchCode,
    required this.firstName,
    required this.lastName,
    required this.stage,
  });

  final int id;
  final String companyName;
  final String tin;
  final String branchCode;
  final String firstName;
  final String lastName;
  final TpStage stage;

  String get ownerName =>
      [firstName, lastName].where((s) => s.isNotEmpty).join(' ');

  factory TpClient.fromJson(Map<String, dynamic> j) {
    final s = TpStage.of(
        _int(j['c_status']), _int(j['step2']), _int(j['final_step']));
    return TpClient(
      id: _int(j['id']),
      companyName: _str(j['company_name']),
      tin: _str(j['tin']),
      branchCode: _str(j['branch_code']),
      firstName: _str(j['first_name']),
      lastName: _str(j['last_name']),
      stage: s.key == 'processed' ? const TpStage('processed', 'BIR Registration') : s,
    );
  }
}

class PortalDoc {
  const PortalDoc({
    required this.label,
    required this.isStatic,
    this.file = '',
    this.docType = '',
  });
  final String label;
  final bool isStatic;
  final String file;
  final String docType;
}

class PortalChecklistItem {
  const PortalChecklistItem(this.label, this.ready, this.note);
  final String label;
  final bool ready;
  final String note;
}

class PortalCustomer {
  PortalCustomer(this.raw);
  final Map<String, dynamic> raw;

  int get id => _int(raw['id']);
  String get companyName => _str(raw['company_name']);
  String get tin => _str(raw['tin']);
  String get branchCode => _str(raw['branch_code']);
  String get effectiveBranchCode {
    final e = _str(raw['effective_branch_code']);
    return e.isNotEmpty ? e : branchCode;
  }

  String get rdo => _str(raw['rdo']);
  String get address => _str(raw['address']);
  String get email => _str(raw['email']);
  String get businessLine => _str(raw['business_line']);
  String get softwareName => _str(raw['softwarename']);
  String get serialNumber => _str(raw['serial_number']);
  String get firstName => _str(raw['first_name']);
  String get lastName => _str(raw['last_name']);
  String get avatarSource {
    final n = [firstName, lastName].where((s) => s.isNotEmpty).join(' ').trim();
    return n.isNotEmpty ? n : companyName.trim();
  }

  String get pdfFile => _str(raw['pdf_file']);
  String get ptuFile => _str(raw['ptu_file']);
  int get cStatus => _int(raw['c_status']);
  bool get step2 => _int(raw['step2']) == 1;
  bool get finalStep => _int(raw['final_step']) == 1;
  bool get hasFeedback => _bool(raw['has_feedback']);
  bool get isV1 => _str(raw['source']) == 'v1';

  Map<String, dynamic> get staff => _map(raw['portal_staff']);
  String get staffName {
    final n = _str(staff['name']);
    return n.isEmpty ? 'staff' : n;
  }

  bool get staffCanManage => !isV1 && _bool(staff['can_manage']);

  String get ownerName {
    final n = [raw['first_name'], raw['middle_name'], raw['last_name']]
        .map(_str)
        .where((s) => s.isNotEmpty)
        .join(' ')
        .trim();
    return n.isEmpty ? '-' : n;
  }

  String get branchDisplay {
    if (branchCode.isNotEmpty) return branchCode;
    final digits = tin.replaceAll(RegExp(r'\D'), '');
    return digits.length > 9 ? digits.substring(9) : '-';
  }

  String get serialDisplay {
    final s = serialNumber.split('/').where((p) => p.isNotEmpty).join(', ');
    return s.isEmpty ? '-' : s;
  }

  bool get hasCsv {
    final data = _str(raw['csv_file_data']).trim();
    final file = _str(raw['csv_file']).trim();
    return data.isNotEmpty || file.isNotEmpty;
  }

  String get vatLabel {
    final v = raw['is_vat'];
    if (v == null || '$v'.trim().isEmpty) return 'Not specified';
    final n = num.tryParse('$v');
    if (n == 1) return 'VAT';
    if (n == 0) return 'Non-VAT';
    final t = '$v'.trim().toUpperCase().replaceAll(RegExp(r'[\s_]+'), '-');
    if (t.startsWith('NON') || t.contains('EXEMPT')) return 'Non-VAT';
    if (t.contains('VAT')) return 'VAT';
    return 'Not specified';
  }

  String get stageKey {
    if (finalStep) return 'completed';
    if (cStatus == 1 && step2) return 'awaiting';
    if (cStatus == 1) return 'processed';
    return 'submitted';
  }

  String get statusText {
    if (finalStep) return 'Completed';
    if (cStatus == 1 && step2) return 'Awaiting PTU';
    if (cStatus == 1) return 'Waiting for BIR Registration';
    return 'Submitted';
  }

  List<PortalChecklistItem> get checklist {
    final c = cStatus == 1;
    final reviewed = c || step2 || finalStep;
    return [
      PortalChecklistItem('BIR Registration PDF', pdfFile.isNotEmpty && (c || step2),
          'After the BIR registration'),
      PortalChecklistItem('Sworn Declaration', reviewed, 'After review'),
      PortalChecklistItem('Sworn Statement', reviewed, 'After review'),
      PortalChecklistItem('Ask For Receipt', finalStep, 'When registration completes'),
      PortalChecklistItem('PTU Document', finalStep && ptuFile.isNotEmpty,
          'When the PTU is released'),
    ];
  }

  List<PortalDoc> get documents {
    final docs = <PortalDoc>[];
    if (pdfFile.isNotEmpty && (cStatus == 1 || step2)) {
      docs.add(PortalDoc(label: 'BIR Registration PDF', isStatic: true, file: pdfFile));
    }
    if (cStatus == 1 || step2 || finalStep) {
      docs.add(const PortalDoc(
          label: 'Sworn Declaration', isStatic: false, docType: 'sworn_declaration'));
      docs.add(const PortalDoc(
          label: 'Sworn Statement', isStatic: false, docType: 'sworn_statement'));
    }
    if (finalStep) {
      docs.add(const PortalDoc(
          label: 'Ask For Receipt', isStatic: false, docType: 'ask_for_receipt'));
      if (ptuFile.isNotEmpty) {
        var idx = 0;
        for (final f in ptuFile.split(',')) {
          final t = f.trim();
          if (t.isEmpty) continue;
          docs.add(PortalDoc(
              label: 'PTU Document${idx > 0 ? ' ${idx + 1}' : ''}',
              isStatic: true,
              file: t));
          idx++;
        }
      }
    }
    return docs;
  }
}

class PortalEmployees {
  const PortalEmployees(this.employees, this.max);
  final List<TpEmployee> employees;
  final int max;
}

class TaxpayerPortalService {
  TaxpayerPortalService(this.api);
  final ApiClient api;

  static const _ajax = 'taxpayer-portal-ajax.php';
  String? _csrf;

  Uri _url(String path, [Map<String, String>? query]) {
    final clean = path.replaceAll(RegExp(r'^/+'), '');
    final uri = Uri.parse('${api.baseUrl}/$clean');
    return query == null ? uri : uri.replace(queryParameters: query);
  }

  Map<String, String> get _headers =>
      {...api.authHeaders(), 'Accept': 'application/json'};

  Map<String, dynamic> _decode(http.Response res) {
    final body = res.body.trim();
    if (body.isEmpty) {
      if (res.statusCode >= 400) {
        throw Exception('HTTP ${res.statusCode}');
      }
      return <String, dynamic>{};
    }
    try {
      final d = jsonDecode(body);
      if (d is Map) return Map<String, dynamic>.from(d);
    } catch (_) {}
    throw Exception(res.statusCode >= 400
        ? 'HTTP ${res.statusCode}'
        : 'Unexpected response from server.');
  }

  Future<Map<String, dynamic>> _get(String path, Map<String, String> query) async {
    final res = await http.get(_url(path, query), headers: _headers);
    return _decode(res);
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, String> body,
      [Map<String, String>? query]) async {
    final res = await http.post(_url(path, query), headers: _headers, body: body);
    return _decode(res);
  }

  static bool _missingAction(Map<String, dynamic> res) =>
      _str(res['message']).contains('Invalid or missing action');

  static const _needsUpdate =
      'The server does not support this yet. Deploy the latest api.php.';

  Future<TpListResult> list({
    String q = '',
    String filter = 'all',
    int page = 1,
  }) async {
    final res = await _get(_ajax, {
      'action': 'list',
      'q': q,
      'filter': filter,
      'page': '$page',
    });
    if (res['success'] != true) {
      throw Exception(_str(res['message']).isEmpty
          ? 'Could not load taxpayers.'
          : _str(res['message']));
    }
    final per = _int(res['per_page']);
    return TpListResult(
      rows: _maps(res['rows']).map(TpRow.fromJson).toList(),
      total: _int(res['total']),
      page: _int(res['page']) > 0 ? _int(res['page']) : page,
      perPage: per > 0 ? per : 25,
      stats: TpStats.fromJson(_map(res['stats'])),
    );
  }

  Future<TpDetail> detail(int customerId) async {
    final res =
        await _get(_ajax, {'action': 'detail', 'customer_id': '$customerId'});
    if (res['success'] != true) {
      throw Exception(_str(res['message']).isEmpty
          ? 'Could not load this taxpayer.'
          : _str(res['message']));
    }
    return TpDetail.fromJson(_map(res['taxpayer']));
  }

  Future<String> _csrfToken({bool refresh = false}) async {
    if (!refresh && _csrf != null && _csrf!.isNotEmpty) return _csrf!;
    try {
      final res = await _get('api.php', {'action': 'taxpayerPortalCsrf'});
      final t = _str(res['csrf_token']);
      if (t.isNotEmpty) return _csrf = t;
    } catch (_) {}
    final page = await http.get(_url('taxpayer-portal.php'), headers: api.authHeaders());
    final m = RegExp(r'var CSRF = "([0-9a-fA-F]+)"').firstMatch(page.body);
    if (m == null) {
      throw Exception('Your session could not be verified. Sign in again.');
    }
    return _csrf = m.group(1)!;
  }

  Future<TpActionResult> _action(
      String action, int customerId, Map<String, String> fields,
      {bool retried = false}) async {
    final token = await _csrfToken(refresh: retried);
    final res = await _post(_ajax, {
      'action': action,
      'customer_id': '$customerId',
      'csrf_token': token,
      ...fields,
    });
    final ok = res['success'] == true;
    final msg = _str(res['message']);
    if (!ok && !retried && msg.contains('could not be verified')) {
      return _action(action, customerId, fields, retried: true);
    }
    final t = res['taxpayer'];
    return TpActionResult(
      ok,
      msg.isEmpty ? (ok ? 'Saved.' : 'Could not save the change.') : msg,
      t is Map ? TpDetail.fromJson(Map<String, dynamic>.from(t)) : null,
    );
  }

  Future<TpActionResult> setOwnerPassword(
          int customerId, String password, String confirm) =>
      _action('setOwnerPassword', customerId,
          {'password': password, 'confirm_password': confirm});

  Future<TpActionResult> clearOwnerPassword(int customerId) =>
      _action('clearOwnerPassword', customerId, {});

  Future<TpActionResult> inviteEmployee(
          int customerId, String name, String email, String position) =>
      _action('inviteEmployee', customerId,
          {'full_name': name, 'email': email, 'position': position});

  Future<TpActionResult> updateEmployee(int customerId, int employeeId,
          String name, String email, String position) =>
      _action('updateEmployee', customerId, {
        'employee_id': '$employeeId',
        'full_name': name,
        'email': email,
        'position': position,
      });

  Future<TpActionResult> setEmployeePassword(
          int customerId, int employeeId, String password, String confirm) =>
      _action('setEmployeePassword', customerId, {
        'employee_id': '$employeeId',
        'password': password,
        'confirm_password': confirm,
      });

  Future<TpActionResult> setEmployeeStatus(
          int customerId, int employeeId, String status) =>
      _action('setEmployeeStatus', customerId,
          {'employee_id': '$employeeId', 'status': status});

  Future<TpActionResult> resendInvite(int customerId, int employeeId) =>
      _action('resendInvite', customerId, {'employee_id': '$employeeId'});

  Future<TpActionResult> removeEmployee(int customerId, int employeeId) =>
      _action('removeEmployee', customerId, {'employee_id': '$employeeId'});

  Future<List<TpClient>> staffSearch(String q) async {
    final res =
        await _get('api.php', {'action': 'staffTaxpayerPortalSearch', 'q': q});
    if (_str(res['status']) != 'success') {
      throw Exception(_str(res['message']).isEmpty
          ? 'Could not load clients.'
          : _str(res['message']));
    }
    return _maps(res['clients']).map(TpClient.fromJson).toList();
  }

  Future<PortalCustomer> openPortal(int customerId) async {
    final res = await _get(
        'api.php', {'action': 'staffOpenTaxpayerPortalJson', 'id': '$customerId'});
    if (_missingAction(res)) throw Exception(_needsUpdate);
    if (_str(res['status']) != 'success' || res['customer'] is! Map) {
      throw Exception(_str(res['message']).isEmpty
          ? 'Could not open this portal.'
          : _str(res['message']));
    }
    return PortalCustomer(_map(res['customer']));
  }

  Future<PortalCustomer> portalSession() async {
    final res = await _get('api.php', {'action': 'getCustomerPortalSession'});
    if (_str(res['status']) != 'success' || res['customer'] is! Map) {
      throw Exception(_str(res['message']).isEmpty
          ? 'No active portal session.'
          : _str(res['message']));
    }
    return PortalCustomer(_map(res['customer']));
  }

  Future<PortalEmployees> portalEmployees() async {
    final res = await _get('api.php', {'action': 'listClientEmployees'});
    if (_str(res['status']) != 'success') {
      throw Exception(_str(res['message']).isEmpty
          ? 'Could not load employees.'
          : _str(res['message']));
    }
    final max = _int(res['max_employees']);
    return PortalEmployees(
      _maps(res['employees']).map(TpEmployee.fromJson).toList(),
      max > 0 ? max : 25,
    );
  }

  Future<void> closePortal() async {
    try {
      await _get('api.php', {'action': 'staffCloseTaxpayerPortalJson'});
    } catch (_) {}
  }

  String uploadUrl(String file) =>
      '${api.baseUrl}/uploads/${Uri.encodeComponent(file)}';

  Future<String> generateDocument(int customerId, PortalDoc doc) async {
    if (doc.docType == 'ask_for_receipt') {
      final res = await http.post(_url('print/bir-card.php'),
          headers: api.authHeaders(), body: {'id': '$customerId'});
      if (res.statusCode >= 400) throw Exception('Error generating the PDF.');
      return '${api.baseUrl}/print/ask-for-receipt.pdf';
    }
    final res = await http.post(_url('print/sworn_declaration.php'),
        headers: api.authHeaders(),
        body: {'id': '$customerId', 'docType': doc.docType});
    final m = RegExp(r'"pdfPath"\s*:\s*"((?:[^"\\]|\\.)*)"').firstMatch(res.body);
    if (res.statusCode >= 400 || m == null) {
      throw Exception('Error generating the PDF.');
    }
    final path = jsonDecode('"${m.group(1)}"') as String;
    return '${api.baseUrl}/print/${Uri.encodeComponent(path)}';
  }

  Future<File> downloadCsv(int customerId) async {
    final res = await http.get(
        _url('api.php', {'action': 'downloadCustomerCsv', 'id': '$customerId'}),
        headers: api.authHeaders());
    if (res.statusCode != 200) {
      final msg = res.body.trim();
      throw Exception(msg.isEmpty || msg.length > 200 ? 'Could not download the CSV.' : msg);
    }
    var name = 'ACCREG_POS_STANDALONE.csv';
    final cd = res.headers['content-disposition'] ?? '';
    final m = RegExp(r'filename="?([^";]+)"?').firstMatch(cd);
    if (m != null) name = m.group(1)!.replaceAll(RegExp(r'[\\/]'), '_');
    Directory? dir;
    try {
      dir = await getDownloadsDirectory();
    } catch (_) {}
    dir ??= await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(res.bodyBytes);
    return file;
  }
}
