// API layer for the Emails (subscribers) feature. All endpoints live on
// `api.php`:
//   * getEmails       POST  page, limit, search, source  → {data:[...], totalRecords, limit, page}
//   * deleteEmail     POST  id, source                    → {success:true}
//   * sendSingleEmail POST  email, subject, message, attachments(file?), skipLogging?
//   * sendEmailToAll  POST  subject, message, attachments(file?)
// Attachments are uploaded under the multipart field name `attachments`.

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

  /// Fetch a page of subscribers. [source] is 'all' | 'emails' | 'leads'.
  /// We pull a large page so the mobile list stays simple (pull-to-refresh,
  /// no infinite scroll). Returns an empty list on any failure.
  Future<List<EmailEntry>> list({
    int page = 1,
    int limit = 200,
    String search = '',
    String source = 'all',
  }) async {
    try {
      final res = await _api.post('getEmails', body: {
        'page': '$page',
        'limit': '$limit',
        'search': search,
        'source': source,
      });
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

  /// Delete a subscriber. For leads this unsubscribes; for emails it removes
  /// the row. [source] must be 'emails' or 'leads'.
  Future<EmailResult> delete(int id, String source) async {
    try {
      final res = await _api.post('deleteEmail', body: {
        'id': '$id',
        'source': source,
      });
      final ok = res['success'] == true || res['status'] == 'success';
      return EmailResult(ok: ok, message: res['message']?.toString());
    } catch (e) {
      return EmailResult(ok: false, message: 'Network error');
    }
  }

  /// Send to a single subscriber. When [attachmentPath] is set the request is
  /// sent as multipart (field name `attachments`); otherwise a plain POST.
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
          fields: {
            'email': email,
            'subject': subject,
            'message': message,
          },
          files: {'attachments': attachmentPath},
        );
      } else {
        res = await _api.post('sendSingleEmail', body: {
          'email': email,
          'subject': subject,
          'message': message,
        });
      }
      final ok = res['success'] == true || res['status'] == 'success';
      return EmailResult(ok: ok, message: res['message']?.toString());
    } catch (e) {
      return EmailResult(ok: false, message: 'Network error');
    }
  }

  /// Broadcast to every subscriber. Multipart when an attachment is set.
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
          fields: {
            'subject': subject,
            'message': message,
          },
          files: {'attachments': attachmentPath},
        );
      } else {
        res = await _api.post('sendEmailToAll', body: {
          'subject': subject,
          'message': message,
        });
      }
      final ok = res['success'] == true || res['status'] == 'success';
      return EmailResult(ok: ok, message: res['message']?.toString());
    } catch (e) {
      return EmailResult(ok: false, message: 'Network error');
    }
  }
}
