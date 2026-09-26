import 'dart:convert';
import 'dart:io' as io;

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api_client.dart';
import '../models/employment_models.dart';

class EmploymentService {
  EmploymentService(this.api);

  final ApiClient api;

  static const _kAuthNameKey = 'empAuthName';
  static const _kAuthRememberKey = 'empAuthNameRemember';

  String _error(Object e, String fallback) {
    final msg = e is HttpException ? e.message.trim() : '';
    if (msg.isEmpty || msg.startsWith('HTTP ') || msg.startsWith('Non-JSON')) {
      return fallback;
    }
    return msg;
  }

  Future<EmploymentResult> _post(
    String action,
    Map<String, String> body,
    String fallback,
  ) async {
    try {
      final res = await api.post(action, body: body);
      final result = EmploymentResult.fromJson(res);
      if (!result.ok && result.message == null) {
        return EmploymentResult(
          ok: false,
          message: fallback,
          errors: result.errors,
          data: result.data,
        );
      }
      return result;
    } catch (e) {
      return EmploymentResult.failure(_error(e, fallback));
    }
  }

  Future<int> pendingCount() async {
    try {
      final res = await api.get('employmentPendingCount');
      if (res['status'] != 'success') return 0;
      final v = res['count'];
      if (v is num) return v.toInt();
      return int.tryParse('$v') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<EmploymentPulse?> pulse() async {
    try {
      final res = await api.get('employmentPulse');
      if (res['status'] != 'success') return null;
      return EmploymentPulse.fromJson(res);
    } catch (_) {
      return null;
    }
  }

  Future<EmploymentRecordPage> records({
    String search = '',
    String status = '',
    int page = 1,
    int limit = 25,
  }) async {
    final res = await api.get('employmentRecords', {
      'search': search,
      'status': status,
      'page': '$page',
      'limit': '$limit',
    });
    if (res['status'] != 'success') {
      throw HttpException(
        res['message']?.toString() ?? 'Could not load the sheets.',
      );
    }
    final raw = res['data'];
    final list = raw is List
        ? raw
              .whereType<Map>()
              .map(
                (e) => EmploymentRecordBrief.fromJson(
                  Map<String, dynamic>.from(e),
                ),
              )
              .toList()
        : <EmploymentRecordBrief>[];
    final total = res['totalRecords'];
    final summary = res['summary'];
    return EmploymentRecordPage(
      records: list,
      total: total is num ? total.toInt() : int.tryParse('$total') ?? 0,
      summary: summary is Map
          ? EmploymentSummary.fromJson(Map<String, dynamic>.from(summary))
          : const EmploymentSummary(),
    );
  }

  Future<EmploymentRecord> record(int id) async {
    final res = await api.get('employmentRecord', {'id': '$id'});
    final rec = res['record'];
    if (res['status'] != 'success' || rec is! Map) {
      throw HttpException(res['message']?.toString() ?? 'Record not found');
    }
    return EmploymentRecord.fromJson(Map<String, dynamic>.from(rec));
  }

  Future<List<EmploymentLink>> links({int limit = 200}) async {
    final res = await api.get('employmentLinks', {'limit': '$limit'});
    if (res['status'] != 'success') {
      throw HttpException(
        res['message']?.toString() ?? 'Could not load the share links.',
      );
    }
    final raw = res['links'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => EmploymentLink.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<EmploymentStaffList> staff() async {
    try {
      final res = await api.get('employmentStaff');
      final raw = res['users'];
      final users = raw is List
          ? raw
                .whereType<Map>()
                .map(
                  (e) => EmploymentStaff.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList()
          : <EmploymentStaff>[];
      return EmploymentStaffList(
        users: users,
        message: res['status'] == 'success' ? null : res['message']?.toString(),
      );
    } catch (e) {
      return EmploymentStaffList(
        users: const [],
        message: _error(e, 'Could not load the staff list.'),
      );
    }
  }

  Future<EmploymentResult> createLink({
    required bool reusable,
    int userId = 0,
    String label = '',
    String note = '',
    int days = 30,
  }) => _post('employmentCreateLink', {
    'user_id': '$userId',
    'label': label,
    'note': note,
    'days': '$days',
    'reusable': reusable ? '1' : '0',
  }, 'Could not create the link');

  Future<EmploymentResult> emailLink({
    required int id,
    required String email,
    String subject = '',
    String message = '',
  }) => _post('employmentEmailLink', {
    'id': '$id',
    'email': email,
    'subject': subject,
    'message': message,
  }, 'Could not send the email.');

  Future<EmploymentResult> revokeLink(int id) =>
      _post('employmentRevokeLink', {'id': '$id'}, 'Could not revoke the link');

  Future<EmploymentResult> deleteLink(int id) =>
      _post('employmentDeleteLink', {'id': '$id'}, 'Could not delete the link');

  Future<EmploymentResult> updateRecord(int id, Map<String, String> fields) =>
      _post('employmentUpdateRecord', {
        ...fields,
        'id': '$id',
      }, 'Could not save the changes');

  Future<EmploymentResult> linkStaff(int id, int userId) => _post(
    'employmentLinkStaff',
    {'id': '$id', 'user_id': '$userId'},
    'Could not save the staff account',
  );

  Future<EmploymentResult> setStatus(int id, String status) => _post(
    'employmentSetStatus',
    {'id': '$id', 'new_status': status},
    'Could not update the status',
  );

  Future<EmploymentResult> deleteRecord(int id) => _post(
    'employmentDeleteRecord',
    {'id': '$id'},
    'Could not delete the record',
  );

  static String encodeList(List<Map<String, String>> rows) => jsonEncode(rows);

  Future<({String name, bool remember})> authNamePref() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      name: prefs.getString(_kAuthNameKey) ?? '',
      remember: prefs.getString(_kAuthRememberKey) == '1',
    );
  }

  Future<void> saveAuthName(String name, {required bool remember}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAuthNameKey, name);
    if (remember) {
      await prefs.setString(_kAuthRememberKey, '1');
    } else {
      await prefs.remove(_kAuthRememberKey);
    }
  }

  Future<void> forgetAuthRemember() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAuthRememberKey);
  }

  Future<String> downloadPdf(int id, String authName) async {
    final uri = api.pathUri('print/employment-pdf.php', {
      'id': '$id',
      if (authName.isNotEmpty) 'auth_name': authName,
    });
    final res = await api.rawGet(uri, json: false);
    final type = (res.headers['content-type'] ?? '').toLowerCase();
    final bytes = res.bodyBytes;
    final looksPdf =
        bytes.length > 4 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46;
    if (res.statusCode < 200 ||
        res.statusCode >= 300 ||
        (!looksPdf && !type.contains('pdf'))) {
      final body = res.body.trim();
      throw HttpException(
        body.isNotEmpty && body.length < 160 && !body.startsWith('<')
            ? body
            : 'Could not generate the PDF',
      );
    }
    final dir = await getTemporaryDirectory();
    final file = io.File('${dir.path}/employment-sheet-$id.pdf');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}
