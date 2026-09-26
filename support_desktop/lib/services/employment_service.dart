import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api_client.dart';

String _s(dynamic v) => v == null ? '' : '$v';
int _i(dynamic v) => int.tryParse('${v ?? ''}') ?? 0;

class EmpResult {
  const EmpResult({
    required this.ok,
    this.message = '',
    this.data = const {},
    this.errors = const {},
  });

  final bool ok;
  final String message;
  final Map<String, dynamic> data;
  final Map<String, String> errors;

  factory EmpResult.from(Map<String, dynamic> res, String fallback) {
    final ok = res['status'] == 'success';
    final raw = res['errors'];
    final errors = <String, String>{};
    if (raw is Map) {
      raw.forEach((k, v) => errors['$k'] = '$v');
    }
    final msg = _s(res['message']);
    return EmpResult(
      ok: ok,
      message: msg.isNotEmpty ? msg : (ok ? '' : fallback),
      data: res,
      errors: errors,
    );
  }

  factory EmpResult.failure(Object e, String fallback) {
    final text = '$e';
    return EmpResult(
      ok: false,
      message: text.contains('HTTP 403') ? 'Unauthorized' : fallback,
    );
  }
}

class EmploymentMeta {
  const EmploymentMeta({
    required this.maritalStatuses,
    required this.spouselessStatuses,
    required this.minContacts,
    required this.maxContacts,
    required this.mailSubject,
    required this.mailMessage,
  });

  final List<String> maritalStatuses;
  final List<String> spouselessStatuses;
  final int minContacts;
  final int maxContacts;
  final String mailSubject;
  final String mailMessage;

  static const fallback = EmploymentMeta(
    maritalStatuses: ['Single', 'Married', 'Widowed', 'Annulled', 'Separated'],
    spouselessStatuses: ['Single', 'Widowed', 'Annulled', 'Separated'],
    minContacts: 1,
    maxContacts: 6,
    mailSubject: '',
    mailMessage: '',
  );

  factory EmploymentMeta.fromJson(Map<String, dynamic> j) {
    List<String> list(dynamic v, List<String> def) =>
        v is List ? v.map((e) => '$e').toList() : def;
    return EmploymentMeta(
      maritalStatuses: list(j['marital_statuses'], fallback.maritalStatuses),
      spouselessStatuses:
          list(j['spouseless_statuses'], fallback.spouselessStatuses),
      minContacts: _i(j['min_emergency_contacts']) > 0
          ? _i(j['min_emergency_contacts'])
          : fallback.minContacts,
      maxContacts: _i(j['max_emergency_contacts']) > 0
          ? _i(j['max_emergency_contacts'])
          : fallback.maxContacts,
      mailSubject: _s(j['mail_subject']),
      mailMessage: _s(j['mail_message']),
    );
  }
}

class EmploymentSummary {
  const EmploymentSummary({
    this.total = 0,
    this.submitted = 0,
    this.reviewed = 0,
    this.today = 0,
    this.activeLinks = 0,
  });

  final int total;
  final int submitted;
  final int reviewed;
  final int today;
  final int activeLinks;

  factory EmploymentSummary.fromJson(Map<String, dynamic> j) =>
      EmploymentSummary(
        total: _i(j['total']),
        submitted: _i(j['submitted']),
        reviewed: _i(j['reviewed']),
        today: _i(j['today']),
        activeLinks: _i(j['active_links']),
      );
}

class EmploymentRow {
  EmploymentRow(this.raw);
  final Map<String, dynamic> raw;

  int get id => _i(raw['id']);
  String get fullName => _s(raw['full_name']);
  String get jobTitle => _s(raw['job_title']);
  String get workLocation => _s(raw['work_location']);
  String get maritalStatus => _s(raw['marital_status']);
  String get status => _s(raw['status']);
  String get createdAt => _s(raw['created_at']);
  String get staffName => _s(raw['staff_name']);
  String get staffRole => _s(raw['staff_role']);
  bool get staffLinkSkipped => _i(raw['staff_link_skipped']) == 1;
  int get dependentCount => _i(raw['dependent_count']);
  bool get isStaffLinked => staffName.trim().isNotEmpty || staffLinkSkipped;
}

class EmploymentRecord {
  EmploymentRecord(this.raw);
  final Map<String, dynamic> raw;

  int get id => _i(raw['id']);
  String field(String key) => _s(raw[key]);
  String get fullName => field('full_name');
  String get status => field('status');
  String get staffName => field('staff_name');
  bool get staffLinkSkipped => _i(raw['staff_link_skipped']) == 1;
  bool get hasNoDependents => _i(raw['has_no_dependents']) == 1;
  bool get isStaffLinked => staffName.trim().isNotEmpty || staffLinkSkipped;

  List<Map<String, String>> _list(String key) {
    final v = raw[key];
    if (v is! List) return [];
    return v
        .whereType<Map>()
        .map((m) => m.map((k, val) => MapEntry('$k', _s(val))))
        .toList();
  }

  List<Map<String, String>> get contacts => _list('emergency_contacts');
  List<Map<String, String>> get dependents => _list('dependents');
}

class EmploymentPage {
  const EmploymentPage({
    required this.rows,
    required this.total,
    required this.limit,
    required this.summary,
  });

  final List<EmploymentRow> rows;
  final int total;
  final int limit;
  final EmploymentSummary summary;
}

class EmploymentLink {
  EmploymentLink(this.raw);
  final Map<String, dynamic> raw;

  int get id => _i(raw['id']);
  String get label => _s(raw['label']);
  String get note => _s(raw['note']);
  String get sentTo => _s(raw['sent_to']);
  String get url => _s(raw['url']);
  bool get isReusable => _i(raw['is_reusable']) == 1;
  int get useCount => _i(raw['use_count']);
  bool get isRevoked => _i(raw['is_revoked']) == 1;
  bool get isActive => _i(raw['is_active']) == 1;
  String get expiresAt => _s(raw['expires_at']);
  String get lastUsedAt => _s(raw['last_used_at']);
}

class StaffOption {
  StaffOption(this.raw);
  final Map<String, dynamic> raw;

  int get id => _i(raw['id']);
  String get name => _s(raw['name']);
  String get username => _s(raw['username']);
  String get email => _s(raw['email']);
  String get role => _s(raw['role']);
  int get openLinks => _i(raw['open_links']);
  int get sheetCount => _i(raw['sheet_count']);
}

class StaffList {
  const StaffList(this.users, this.message);
  final List<StaffOption> users;
  final String message;
}

class EmploymentPulse {
  const EmploymentPulse(this.key, this.latestId);
  final String key;
  final int latestId;
}

class EmploymentService {
  EmploymentService(this.api);
  final ApiClient api;

  static const _authNameKey = 'empAuthName';
  static const _authRememberKey = 'empAuthNameRemember';

  Future<EmploymentMeta> meta() async {
    try {
      final res = await api.get('employmentMeta');
      if (res['status'] == 'success') return EmploymentMeta.fromJson(res);
    } catch (_) {}
    return EmploymentMeta.fallback;
  }

  Future<EmploymentPage> records({
    String search = '',
    String status = '',
    int page = 1,
    int limit = 15,
  }) async {
    final res = await api.get('employmentRecords', {
      'search': search,
      'status': status,
      'page': '$page',
      'limit': '$limit',
    });
    if (res['status'] != 'success') {
      throw Exception(_s(res['message']).isEmpty
          ? 'Could not load the sheets'
          : _s(res['message']));
    }
    final data = res['data'];
    final summary = res['summary'];
    return EmploymentPage(
      rows: data is List
          ? data
              .whereType<Map>()
              .map((m) => EmploymentRow(Map<String, dynamic>.from(m)))
              .toList()
          : [],
      total: _i(res['totalRecords']),
      limit: _i(res['limit']) > 0 ? _i(res['limit']) : limit,
      summary: summary is Map
          ? EmploymentSummary.fromJson(Map<String, dynamic>.from(summary))
          : const EmploymentSummary(),
    );
  }

  Future<EmploymentPulse?> pulse() async {
    try {
      final res = await api.get('employmentPulse');
      if (res['status'] != 'success') return null;
      return EmploymentPulse(
        '${res['latest_id']}:${res['total']}:${res['stamp']}',
        _i(res['latest_id']),
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<EmploymentLink>> links() async {
    final res = await api.get('employmentLinks', {'limit': '200'});
    final raw = res['links'];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((m) => EmploymentLink(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<StaffList> staff() async {
    final res = await api.get('employmentStaff');
    final raw = res['users'];
    return StaffList(
      raw is List
          ? raw
              .whereType<Map>()
              .map((m) => StaffOption(Map<String, dynamic>.from(m)))
              .toList()
          : [],
      _s(res['message']),
    );
  }

  Future<EmpResult> _post(
      String action, Map<String, String> body, String fallback) async {
    try {
      final res = await api.post(action, body: body);
      return EmpResult.from(res, fallback);
    } catch (e) {
      return EmpResult.failure(e, fallback);
    }
  }

  Future<EmpResult> createLink({
    required int userId,
    required String label,
    required String note,
    required int days,
    required bool reusable,
  }) =>
      _post(
          'employmentCreateLink',
          {
            'user_id': '$userId',
            'label': label,
            'note': note,
            'days': '$days',
            'reusable': reusable ? '1' : '0',
          },
          'Could not create the link');

  Future<EmpResult> emailLink({
    required int id,
    required String email,
    required String subject,
    required String message,
  }) =>
      _post(
          'employmentEmailLink',
          {
            'id': '$id',
            'email': email,
            'subject': subject,
            'message': message,
          },
          'Could not send the email.');

  Future<EmpResult> revokeLink(int id) => _post(
      'employmentRevokeLink', {'id': '$id'}, 'Could not revoke the link');

  Future<EmpResult> deleteLink(int id) => _post(
      'employmentDeleteLink', {'id': '$id'}, 'Could not delete the link');

  Future<EmploymentRecord?> record(int id) async {
    final res = await api.get('employmentRecord', {'id': '$id'});
    final rec = res['record'];
    if (res['status'] != 'success' || rec is! Map) return null;
    return EmploymentRecord(Map<String, dynamic>.from(rec));
  }

  Future<({EmploymentRecord? record, String message})> fetchRecord(
      int id) async {
    try {
      final res = await api.get('employmentRecord', {'id': '$id'});
      final rec = res['record'];
      if (res['status'] == 'success' && rec is Map) {
        return (
          record: EmploymentRecord(Map<String, dynamic>.from(rec)),
          message: ''
        );
      }
      final msg = _s(res['message']);
      return (record: null, message: msg.isNotEmpty ? msg : 'Record not found');
    } catch (e) {
      return (
        record: null,
        message: '$e'.contains('HTTP 403') ? 'Unauthorized' : 'Record not found'
      );
    }
  }

  Future<EmpResult> updateRecord(Map<String, String> payload) => _post(
      'employmentUpdateRecord', payload, 'Could not save the changes');

  Future<EmpResult> linkStaff(int id, int userId) => _post(
      'employmentLinkStaff',
      {'id': '$id', 'user_id': '$userId'},
      'Could not save the staff account');

  Future<EmpResult> setStatus(int id, String status) => _post(
      'employmentSetStatus',
      {'id': '$id', 'new_status': status},
      'Could not update the status');

  Future<EmpResult> deleteRecord(int id) => _post(
      'employmentDeleteRecord', {'id': '$id'}, 'Could not delete the record');

  Future<String> downloadPdf(int id, String authName) async {
    final base = api.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/print/employment-pdf.php').replace(
      queryParameters: {
        'id': '$id',
        if (authName.isNotEmpty) 'auth_name': authName,
      },
    );
    final response = await http.get(uri, headers: api.authHeaders());
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = response.body.trim();
      throw Exception(body.isNotEmpty && body.length < 200
          ? body
          : 'HTTP ${response.statusCode}');
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/employment_sheet_$id.pdf';
    await File(path).writeAsBytes(response.bodyBytes, flush: true);
    return path;
  }

  Future<({String name, bool remember})> authName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (
        name: prefs.getString(_authNameKey) ?? '',
        remember: prefs.getString(_authRememberKey) == '1',
      );
    } catch (_) {
      return (name: '', remember: false);
    }
  }

  Future<void> saveAuthName(String name, bool remember) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_authNameKey, name);
      if (remember) {
        await prefs.setString(_authRememberKey, '1');
      } else {
        await prefs.remove(_authRememberKey);
      }
    } catch (_) {}
  }

  Future<void> forgetAuthRemember() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_authRememberKey);
    } catch (_) {}
  }
}
