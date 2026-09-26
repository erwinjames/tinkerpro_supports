import '../api_client.dart';
import '../models/email_models.dart';

class EmailResult {
  EmailResult({required this.ok, this.message});
  final bool ok;
  final String? message;
}

class EmailService {
  EmailService(this._api);
  final ApiClient _api;

  Future<List<EmailEntry>> list({
    int page = 1,
    int limit = 200,
    String search = '',
    String source = 'all',
  }) async {
    try {
      final res = await _api.post(
        'getEmails',
        body: {
          'page': '$page',
          'limit': '$limit',
          'search': search,
          'source': source,
        },
      );
      final raw = res['data'];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => EmailEntry.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<EmailResult> delete(int id, String source) async {
    try {
      final res = await _api.post(
        'deleteEmail',
        body: {'id': '$id', 'source': source},
      );
      final ok = res['success'] == true || res['status'] == 'success';
      return EmailResult(ok: ok, message: res['message']?.toString());
    } catch (e) {
      return EmailResult(ok: false, message: 'Network error');
    }
  }

  Future<EmailResult> sendSingle({
    required String email,
    required String subject,
    required String message,
    String? attachmentPath,
  }) async {
    try {
      final Map<String, dynamic> res;
      if (attachmentPath != null && attachmentPath.isNotEmpty) {
        res = await _api.postMultipart(
          'sendSingleEmail',
          fields: {'email': email, 'subject': subject, 'message': message},
          files: {'attachments': attachmentPath},
        );
      } else {
        res = await _api.post(
          'sendSingleEmail',
          body: {'email': email, 'subject': subject, 'message': message},
        );
      }
      final ok = res['success'] == true || res['status'] == 'success';
      return EmailResult(ok: ok, message: res['message']?.toString());
    } catch (e) {
      return EmailResult(ok: false, message: 'Network error');
    }
  }

  Future<EmailResult> sendAll({
    required String subject,
    required String message,
    String? attachmentPath,
  }) async {
    try {
      final Map<String, dynamic> res;
      if (attachmentPath != null && attachmentPath.isNotEmpty) {
        res = await _api.postMultipart(
          'sendEmailToAll',
          fields: {'subject': subject, 'message': message},
          files: {'attachments': attachmentPath},
        );
      } else {
        res = await _api.post(
          'sendEmailToAll',
          body: {'subject': subject, 'message': message},
        );
      }
      final ok = res['success'] == true || res['status'] == 'success';
      return EmailResult(ok: ok, message: res['message']?.toString());
    } catch (e) {
      return EmailResult(ok: false, message: 'Network error');
    }
  }

  Future<InternalRecipientPage> internalRecipients({
    int page = 1,
    int limit = 200,
    String search = '',
    String filter = 'all',
  }) async {
    try {
      final res = await _api.post(
        'getInternalRecipients',
        body: {
          'page': '$page',
          'limit': '$limit',
          'search': search,
          'filter': filter,
        },
      );
      final raw = res['data'];
      final rows = raw is List
          ? raw
                .whereType<Map>()
                .map(
                  (e) =>
                      InternalRecipient.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList()
          : <InternalRecipient>[];
      final filters = res['filters'];
      return InternalRecipientPage(
        rows: rows,
        totalRecords: _int(res['totalRecords']),
        filters: filters is Map
            ? InternalFilters.fromJson(Map<String, dynamic>.from(filters))
            : const InternalFilters(),
        contactsError: (res['contactsError'] ?? '').toString(),
      );
    } catch (_) {
      return const InternalRecipientPage(ok: false);
    }
  }

  Future<InternalSuggestions> internalSuggestions({
    String search = '',
    int limit = 50,
  }) async {
    try {
      final res = await _api.post(
        'getInternalSuggestions',
        body: {'search': search, 'limit': '$limit'},
      );
      if (res['success'] != true) return const InternalSuggestions();
      final groups = res['groups'];
      final people = res['people'];
      return InternalSuggestions(
        groups: groups is List
            ? groups
                  .whereType<Map>()
                  .map(
                    (e) =>
                        RecipientGroup.fromJson(Map<String, dynamic>.from(e)),
                  )
                  .toList()
            : const [],
        people: people is List
            ? people
                  .whereType<Map>()
                  .map(
                    (e) => InternalRecipient.fromJson(
                      Map<String, dynamic>.from(e),
                    ),
                  )
                  .toList()
            : const [],
        peopleTotal: _int(res['peopleTotal']),
      );
    } catch (_) {
      return const InternalSuggestions();
    }
  }

  Future<List<String>> internalGroupEmails(String filter) async {
    final res = await _api.post(
      'getInternalGroupEmails',
      body: {'filter': filter},
    );
    final raw = res['emails'];
    if (raw is List) {
      return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    }
    return const [];
  }

  Future<SaveContactResult> saveContact(ContactDraft draft) async {
    try {
      final res = await _api.post(
        'saveContact',
        body: {
          'id': '${draft.id}',
          'name': draft.name,
          'email': draft.email,
          'company': draft.company,
          'label': draft.label,
          'notes': draft.notes,
        },
      );
      final ok = res['success'] == true;
      return SaveContactResult(
        ok: ok,
        id: _int(res['id']),
        message: res['message']?.toString(),
      );
    } catch (_) {
      return const SaveContactResult(ok: false);
    }
  }

  Future<EmailResult> deleteContact(int id) async {
    try {
      final res = await _api.post('deleteContact', body: {'id': '$id'});
      return EmailResult(
        ok: res['success'] == true,
        message: res['message']?.toString(),
      );
    } catch (_) {
      return EmailResult(ok: false, message: 'Could not remove email.');
    }
  }

  Future<RememberResult> rememberContacts(List<String> emails) async {
    if (emails.isEmpty) return const RememberResult(ok: true);
    try {
      final body = <String, String>{};
      for (var i = 0; i < emails.length; i++) {
        body['emails[$i]'] = emails[i];
      }
      final res = await _api.post('rememberContacts', body: body);
      final added = res['added'];
      return RememberResult(
        ok: res['success'] == true,
        added: added is List
            ? added.map((e) => e.toString()).toList()
            : const [],
      );
    } catch (_) {
      return const RememberResult(ok: false);
    }
  }

  Future<void> logBulkSend({
    required List<String> emails,
    required String subject,
    int attachmentCount = 0,
  }) async {
    try {
      final body = <String, String>{
        'subject': subject,
        'attachmentCount': '$attachmentCount',
      };
      for (var i = 0; i < emails.length; i++) {
        body['emails[$i]'] = emails[i];
      }
      await _api.post('logBulkSend', body: body);
    } catch (_) {}
  }

  Future<void> saveRecentTemplate({
    required String html,
    required String subject,
  }) async {
    try {
      await _api.post(
        'saveRecentTemplate',
        body: {'template_html': html, 'template_subject': subject},
      );
    } catch (_) {}
  }

  Future<EmailResult> sendInternalMessage({
    required String to,
    required String subject,
    required String message,
    List<String> cc = const [],
    List<String> bcc = const [],
    List<String> attachmentPaths = const [],
  }) async {
    try {
      final fields = <String, String>{
        'email': to,
        'subject': subject,
        'message': message,
        'skipLogging': 'true',
      };
      for (var i = 0; i < cc.length; i++) {
        fields['cc[$i]'] = cc[i];
      }
      for (var i = 0; i < bcc.length; i++) {
        fields['bcc[$i]'] = bcc[i];
      }

      final Map<String, dynamic> res;
      if (attachmentPaths.isEmpty) {
        res = await _api.post('sendSingleEmail', body: fields);
      } else {
        final files = <String, String>{};
        for (var i = 0; i < attachmentPaths.length; i++) {
          files['attachments[$i]'] = attachmentPaths[i];
        }
        res = await _api.postMultipart(
          'sendSingleEmail',
          fields: fields,
          files: files,
        );
      }
      final ok = res['success'] == true || res['status'] == 'success';
      return EmailResult(ok: ok, message: res['message']?.toString());
    } catch (e) {
      return EmailResult(ok: false, message: 'Network error');
    }
  }
}

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
