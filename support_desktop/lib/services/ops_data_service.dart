import 'dart:io';

import 'package:http/http.dart' as http;

import '../api_client.dart';

typedef Json = Map<String, dynamic>;

List<Json> _maps(dynamic raw) {
  if (raw is List) {
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
  return <Json>[];
}

bool _ok(Json r) =>
    r['status'] == 'success' || r['success'] == true || r['success'] == 1;

class OpsResult {
  const OpsResult(this.ok, this.message, [this.data = const {}]);
  final bool ok;
  final String message;
  final Json data;
}

OpsResult _result(Json r, String fallback) => OpsResult(
      _ok(r),
      (r['message'] ?? (_ok(r) ? '' : fallback)).toString(),
      r,
    );

class OpsDataService {
  OpsDataService(this.api);
  final ApiClient api;

  static Future<OpsDataService> load() async =>
      OpsDataService(await ApiClient.load());

  String url(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '${api.baseUrl}/${path.replaceAll(RegExp(r'^/+'), '')}';
  }

  Map<String, String> get authHeaders => api.authHeaders();

  Future<Json> ticketMeta() async {
    try {
      return await api.get('desktopTicketMeta');
    } catch (_) {
      return const {};
    }
  }

  Future<List<Json>> tickets() async {
    try {
      final r = await api.get('get_tickets');
      return _maps(r['data'] ?? r);
    } catch (_) {
      return <Json>[];
    }
  }

  Future<Json> ticketDashboard() async {
    try {
      return await api.get('ticketdashboard');
    } catch (_) {
      return const {};
    }
  }

  Future<List<Json>> resolveLeaderboard(String days) async {
    try {
      final r = await api
          .get('resolveLeaderboard', {'since_days': days, 'limit': '10'});
      return _ok(r) ? _maps(r['rows']) : <Json>[];
    } catch (_) {
      return <Json>[];
    }
  }

  Future<List<Json>> storeBreakdown(String days) async {
    try {
      final r =
          await api.get('storeBreakdown', {'since_days': days, 'limit': '10'});
      return _ok(r) ? _maps(r['rows']) : <Json>[];
    } catch (_) {
      return <Json>[];
    }
  }

  Future<List<Json>> agents() async {
    try {
      final r = await api.get('get_agents');
      return _ok(r) ? _maps(r['agents']) : <Json>[];
    } catch (_) {
      return <Json>[];
    }
  }

  Future<List<Json>> helpTopics() async {
    try {
      final r = await api.get('getHelpTopics');
      return r['success'] == true ? _maps(r['data']) : <Json>[];
    } catch (_) {
      return <Json>[];
    }
  }

  Future<List<Json>?> ticketSteps(int ticketId) async {
    try {
      final r = await api.get('get_ticket_steps', {'ticket_id': '$ticketId'});
      return _maps(r['steps']);
    } catch (_) {
      return null;
    }
  }

  Future<OpsResult> _post(String action, Map<String, String> body,
      String fallback) async {
    try {
      final r = await api.post(action, body: body);
      return _result(r, fallback);
    } catch (e) {
      return OpsResult(false, fallback);
    }
  }

  Future<OpsResult> addStep({
    required int ticketId,
    required String type,
    required String title,
    required String details,
    required String reference,
  }) =>
      _post('add_ticket_step', {
        'ticket_id': '$ticketId',
        'step_type': type,
        'title': title,
        'details': details,
        'reference_url': reference,
        'agent_id': '${api.userId ?? ''}',
      }, 'Could not add step');

  Future<OpsResult> deleteStep(int stepId) =>
      _post('delete_ticket_step', {'step_id': '$stepId'},
          'Could not delete step');

  Future<OpsResult> acceptTicket(
    int ticketId, {
    required bool sendEmail,
    String subject = '',
    String message = '',
  }) async {
    try {
      final r = await api.post('accept_ticket', body: {
        'ticket_id': '$ticketId',
        'agent_id': '${api.userId ?? ''}',
        'send_email': sendEmail ? '1' : '0',
        'email_subject': sendEmail ? subject : '',
        'email_message': sendEmail ? message : '',
      });
      final bad = r['status'] == 'error';
      return OpsResult(!bad,
          (r['message'] ?? (bad ? 'Failed to accept ticket' : '')).toString(), r);
    } catch (_) {
      return const OpsResult(false, 'Failed to accept ticket');
    }
  }

  Future<OpsResult> resolveTicket(int ticketId) => _post('markresolved', {
        'ticketId': '$ticketId',
        'agent_id': '${api.userId ?? ''}',
      }, 'Failed to resolve ticket');

  Future<OpsResult> reassignTicket(int ticketId, int agentId) =>
      _post('reassign_ticket', {
        'ticket_id': '$ticketId',
        'agent_id': '$agentId',
      }, 'Could not reassign ticket');

  Future<OpsResult> sendTicketEmail(
          int ticketId, String subject, String message) =>
      _post('send_ticket_email', {
        'ticket_id': '$ticketId',
        'subject': subject,
        'message': message,
      }, 'Could not send the email');

  Future<List<Json>> leads() async {
    try {
      final r = await api.get('getleads');
      return _maps(r['data'] ?? r);
    } catch (_) {
      return <Json>[];
    }
  }

  Future<OpsResult> updateLeadNote(int id, String notes) =>
      _post('updateLeadNote', {'id': '$id', 'notes': notes},
          'Failed to update note');

  Future<OpsResult> updateLeadPhone(int id, String phone) async {
    try {
      final r = await api.post('updateLeadPhone', body: {'id': '$id', 'phone': phone});
      return _result(r, 'Failed to update phone');
    } catch (_) {
      return const OpsResult(false, 'Network error while saving phone');
    }
  }

  Future<OpsResult> deleteLead(int id) =>
      _post('deleteLead', {'id': '$id'}, 'Failed to delete lead.');

  Future<String?> richTextHtml(String text) async {
    try {
      final r = await api.post('desktopRichTextHtml', body: {'text': text});
      if (r['success'] != true) return null;
      return (r['html'] ?? '').toString();
    } catch (_) {
      return null;
    }
  }

  Future<String> exportLeadsCsv(List<int> ids, String saveDir) async {
    final res = await http.post(
      Uri.parse(api.actionUrl('desktopLeadsExportCsv')),
      headers: authHeaders,
      body: {'ids': ids.join(',')},
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw HttpException('HTTP ${res.statusCode}');
    }
    var name = 'leads.csv';
    final cd = res.headers['content-disposition'] ?? '';
    final m = RegExp(r'filename="?([^";]+)"?').firstMatch(cd);
    if (m != null) name = m.group(1)!;
    final file = File('$saveDir${Platform.pathSeparator}$name');
    await file.writeAsBytes(res.bodyBytes);
    return file.path;
  }

  Future<OpsResult> sendLeadEmail({
    required int leadId,
    required String subject,
    required String body,
    String? templateId,
  }) =>
      _post('sendLeadEmail', {
        'lead_id': '$leadId',
        'template_id': templateId ?? '',
        'subject': subject,
        'body': body,
      }, 'Failed to send email');

  Future<List<Json>> emailTemplates() async {
    try {
      final r = await api.get('getTemplates');
      return _maps(r['data'] ?? r);
    } catch (_) {
      return <Json>[];
    }
  }

  Future<Json> recentTemplate() async {
    try {
      return await api.get('getRecentTemplate');
    } catch (_) {
      return const {};
    }
  }

  Future<List<Json>?> leadSmsThread(int id) async {
    try {
      final r = await api.get('getLeadSmsThread', {'id': '$id'});
      if (r['success'] != true) return null;
      return _maps(r['messages']);
    } catch (_) {
      return null;
    }
  }

  Future<OpsResult> sendLeadSms(int id, String message) async {
    try {
      final r =
          await api.post('sendLeadSms', body: {'id': '$id', 'message': message});
      if (r['success'] == true) return OpsResult(true, '', r);
      final resp = r['response'];
      final msg = r['message'] ??
          (resp is Map ? (resp['message'] ?? resp['error']) : null) ??
          'Failed to send SMS.';
      return OpsResult(false, msg.toString(), r);
    } catch (_) {
      return const OpsResult(false, 'Network error while sending SMS.');
    }
  }

  Future<Json> taskRoster() async {
    try {
      return await api.get('desktopTaskRoster');
    } catch (e) {
      return {'success': false, 'message': '$e'};
    }
  }

  Future<Json> userTasks(int userId) async {
    try {
      return await api.getPath('task-user-ajax.php', {
        'ajax_load_user_tasks': '1',
        'user_id': '$userId',
      });
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  Future<OpsResult> addTaskForUser({
    required int userId,
    required String title,
    required String description,
    required String priority,
    required String dueDate,
  }) async {
    try {
      final r = await api.postPath('task-user-ajax.php', body: {
        'target_user_id': '$userId',
        'title': title,
        'description': description,
        'priority': priority,
        'due_date': dueDate,
        'add_task_for_user': '1',
      });
      if (r['success'] == true) return OpsResult(true, '', r);
      return OpsResult(false, 'Error adding task: ${r['message'] ?? ''}', r);
    } catch (_) {
      return const OpsResult(false, 'Network error adding task');
    }
  }

  Future<String> exportTasksCsv({
    required String from,
    required String to,
    required String dateField,
    required String status,
    required String saveDir,
  }) async {
    final res = await http.post(
      Uri.parse(url('task-export-csv.php')),
      headers: authHeaders,
      body: {
        'from_date': from,
        'to_date': to,
        'date_field': dateField,
        'status': status,
      },
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw HttpException('HTTP ${res.statusCode}');
    }
    var name = 'tasks_${from}_to_$to.csv';
    final cd = res.headers['content-disposition'] ?? '';
    final m = RegExp(r'filename="?([^";]+)"?').firstMatch(cd);
    if (m != null) name = m.group(1)!;
    final file = File('$saveDir${Platform.pathSeparator}$name');
    await file.writeAsBytes(res.bodyBytes);
    return file.path;
  }
}
