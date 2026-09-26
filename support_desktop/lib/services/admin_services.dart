import '../api_client.dart';
import '../models/admin_models.dart';

List<T> _rows<T>(dynamic raw, T Function(Map<String, dynamic>) parse) {
  if (raw is List) {
    return raw
        .whereType<Map>()
        .map((m) => parse(Map<String, dynamic>.from(m)))
        .toList();
  }
  return <T>[];
}

int _total(Map<String, dynamic> res) =>
    int.tryParse('${res['totalRecords'] ?? res['total'] ?? 0}') ?? 0;

class PosVersionService {
  PosVersionService(this.api);
  final ApiClient api;

  Future<Paged<PosVersion>> list({
    int page = 1,
    int limit = 50,
    String search = '',
  }) async {
    final res = await api.get('getposversion', {
      'page': '$page',
      'limit': '$limit',
      if (search.isNotEmpty) 'search': search,
    });
    return Paged(
      items: _rows(res['data'], PosVersion.fromJson),
      total: _total(res),
    );
  }

  Future<bool> add({required String version, required String releaseDate}) async {
    final res = await api.post('addposversion',
        body: {'version': version, 'release_date': releaseDate});
    return res['success'] == true;
  }

  Future<bool> update({
    required int id,
    required String version,
    required String date,
  }) async {
    final res = await api.post('updateposversion',
        body: {'id': '$id', 'version': version, 'date': date});
    return res['success'] == true;
  }

  Future<bool> delete(int id) async {
    final res = await api.post('deleteposversion', body: {'id': '$id'});
    return res['success'] == true;
  }
}

class EmailService {
  EmailService(this.api);
  final ApiClient api;

  Future<Paged<EmailRecipient>> list({
    int page = 1,
    int limit = 50,
    String search = '',
    String source = 'all',
  }) async {
    final res = await api.post('getEmails', body: {
      'page': '$page',
      'limit': '$limit',
      'search': search,
      'source': source,
    });
    return Paged(
      items: _rows(res['data'], EmailRecipient.fromJson),
      total: _total(res),
    );
  }

  Future<List<String>> allSubscriberEmails() async {
    final res = await api.post('getEmails', body: {
      'page': '1',
      'limit': '1000000',
    });
    final raw = res['data'];
    if (raw is! List) return <String>[];
    return raw
        .whereType<Map>()
        .map((m) => (m['email'] ?? '').toString())
        .toList();
  }

  Future<Map<String, dynamic>> internal({
    int page = 1,
    int limit = 100000,
    String search = '',
    String filter = 'all',
  }) {
    return api.post('getInternalRecipients', body: {
      'page': '$page',
      'limit': '$limit',
      'search': search,
      'filter': filter,
    });
  }

  Future<Map<String, dynamic>> suggestions(String term) {
    return api.post('getInternalSuggestions',
        body: {'search': term, 'limit': '50'});
  }

  Future<List<String>> groupEmails(String filter) async {
    final res =
        await api.post('getInternalGroupEmails', body: {'filter': filter});
    final raw = res['emails'];
    return raw is List ? raw.map((e) => e.toString()).toList() : <String>[];
  }

  Future<({bool ok, String message})> saveContact({
    required String id,
    required String name,
    required String email,
    required String company,
    required String label,
    required String notes,
  }) async {
    final res = await api.post('saveContact', body: {
      'id': id.isEmpty ? '0' : id,
      'name': name,
      'email': email,
      'company': company,
      'label': label,
      'notes': notes,
    });
    return (
      ok: res['success'] == true,
      message: (res['message'] ?? '').toString(),
    );
  }

  Future<({bool ok, String message})> deleteContact(String id) async {
    final res = await api.post('deleteContact', body: {'id': id});
    return (
      ok: res['success'] == true,
      message: (res['message'] ?? '').toString(),
    );
  }

  Future<({bool ok, String message})> delete({
    required int id,
    required String source,
  }) async {
    final res =
        await api.post('deleteEmail', body: {'id': '$id', 'source': source});
    return (
      ok: res['success'] == true,
      message: (res['message'] ?? '').toString(),
    );
  }

  Future<List<Map<String, dynamic>>> templates() async {
    final res = await api.get('desktopEmailTemplates');
    final raw = res['templates'];
    return raw is List
        ? raw.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
        : <Map<String, dynamic>>[];
  }

  Future<String> messageHtml(String text) async {
    final res = await api.post('desktopEmailMessageHtml', body: {'message': text});
    return (res['html'] ?? text).toString();
  }

  Future<Map<String, dynamic>> sendSingle({
    required String email,
    required String subject,
    required String message,
    bool skipLogging = false,
    List<String> cc = const [],
    List<String> bcc = const [],
    List<String> attachmentPaths = const [],
  }) async {
    final fields = <String, String>{
      'subject': subject,
      'message': message,
      'email': email,
      if (skipLogging) 'skipLogging': 'true',
    };
    for (var i = 0; i < cc.length; i++) {
      fields['cc[$i]'] = cc[i];
    }
    for (var i = 0; i < bcc.length; i++) {
      fields['bcc[$i]'] = bcc[i];
    }
    return api.uploadFiles(
      'sendSingleEmail',
      fields: fields,
      filePaths: attachmentPaths,
      fileField: 'attachments[]',
    );
  }

  Map<String, String> _list(String key, List<String> values) => {
        for (var i = 0; i < values.length; i++) '$key[$i]': values[i],
      };

  Future<void> logBulkSend({
    required List<String> emails,
    required String subject,
    required int attachmentCount,
  }) async {
    await api.post('logBulkSend', body: {
      ..._list('emails', emails),
      'subject': subject,
      'attachmentCount': '$attachmentCount',
    });
  }

  Future<void> logAllEmailSend({
    required List<String> emails,
    required String subject,
    required int attachmentCount,
  }) async {
    await api.post('logAllEmailSend', body: {
      ..._list('emails', emails),
      'subject': subject,
      'attachmentCount': '$attachmentCount',
    });
  }

  Future<void> saveRecentTemplate({
    required String html,
    required String subject,
  }) async {
    await api.post('saveRecentTemplate',
        body: {'template_html': html, 'template_subject': subject});
  }

  Future<Map<String, dynamic>> rememberContacts(List<String> emails) {
    return api.post('rememberContacts', body: _list('emails', emails));
  }
}

class UserService {
  UserService(this.api);
  final ApiClient api;

  Future<Paged<AdminUser>> list({
    int page = 1,
    int limit = 100,
    String search = '',
  }) async {
    final res = await api.get('users', {
      'page': '$page',
      'limit': '$limit',
      if (search.isNotEmpty) 'search': search,
    });
    return Paged(
      items: _rows(res['data'], AdminUser.fromJson),
      total: _total(res),
    );
  }

  Future<bool> toggleStatus({required int id, required String status}) async {
    final res = await api
        .post('toggleUserStatus', body: {'id': '$id', 'status': status});
    return res['success'] == true;
  }

  Future<bool> delete(int id) async {
    final res = await api.post('deleteUser', body: {'id': '$id'});
    return res['success'] == true;
  }
}

class CredentialsService {
  CredentialsService(this.api);
  final ApiClient api;

  Future<({bool ok, String message})> requestOtp() async {
    final res = await api.post('requestCredentialsOTP');
    return (
      ok: res['success'] == true,
      message: (res['message'] ?? '').toString(),
    );
  }

  Future<({bool ok, String message})> verifyOtp(String code) async {
    final res =
        await api.post('verifyCredentialsOTP', body: {'otp_code': code});
    return (
      ok: res['success'] == true,
      message: (res['message'] ?? '').toString(),
    );
  }

  Future<Paged<Credential>> list() async {
    final res = await api.get('getCredentials');
    if (res['success'] != true) {
      throw Exception(res['message']?.toString() ?? 'OTP verification required');
    }
    final items = _rows(res['data'], Credential.fromJson);
    return Paged(items: items, total: items.length);
  }

  Future<({bool ok, String message})> save({
    int? id,
    required String clientName,
    required String credentialsText,
  }) async {
    final res = await api.post('saveCredential', body: {
      'id': id == null ? '' : '$id',
      'client_name': clientName,
      'credentials_text': credentialsText,
    });
    return (
      ok: res['success'] == true,
      message: (res['message'] ?? '').toString(),
    );
  }

  Future<({bool ok, String message})> delete(int id) async {
    final res = await api.post('deleteCredential', body: {'id': '$id'});
    return (
      ok: res['success'] == true,
      message: (res['message'] ?? '').toString(),
    );
  }
}

class ActivityLogService {
  ActivityLogService(this.api);
  final ApiClient api;

  Future<Paged<ActivityLog>> list({
    int page = 1,
    int limit = 100,
    String search = '',
  }) async {
    final res = await api.get('getActivityLogs', {
      'page': '$page',
      'limit': '$limit',
      if (search.isNotEmpty) 'search': search,
    });
    return Paged(
      items: _rows(res['data'], ActivityLog.fromJson),
      total: _total(res),
    );
  }
}

class BlogService {
  BlogService(this.api);
  final ApiClient api;

  Future<Paged<BlogPost>> list({
    int page = 1,
    int limit = 50,
    String search = '',
  }) async {
    final res = await api.get('getBlogPosts', {
      'page': '$page',
      'limit': '$limit',
      if (search.isNotEmpty) 'search': search,
    });
    return Paged(
      items: _rows(res['data'], BlogPost.fromJson),
      total: _total(res),
    );
  }

  Future<bool> add({
    required String title,
    required String content,
    bool isDraft = false,
  }) async {
    final res = await api.post('addBlogPost', body: {
      'title': title,
      'content': content,
      'is_draft': isDraft ? '1' : '0',
    });
    return res['success'] == true;
  }

  Future<bool> delete(int id) async {
    final res = await api.post('deleteBlogPost', body: {'id': '$id'});
    return res['success'] == true;
  }
}

class FilesService {
  FilesService(this.api);
  final ApiClient api;

  Future<Paged<FileCollection>> listCollections({String search = ''}) async {
    final res = await api.get('file_list_collections');
    var items = _rows(res['data'], FileCollection.fromJson);
    final q = search.trim().toLowerCase();
    if (q.isNotEmpty) {
      items = items
          .where((c) =>
              c.name.toLowerCase().contains(q) ||
              c.email.toLowerCase().contains(q))
          .toList();
    }
    return Paged(items: items, total: items.length);
  }

  Future<List<FileItem>> collectionFiles(String collectionId) async {
    final res = await api.get('file_collection_files', {'id': collectionId});
    return _rows(res['files'], FileItem.fromJson);
  }

  Future<({bool ok, String? message})> upload({
    required String collectionName,
    String email = '',
    required List<String> filePaths,
  }) async {
    final res = await api.uploadFiles('file_upload', fields: {
      'collection_name': collectionName,
      if (email.isNotEmpty) 'email': email,
    }, filePaths: filePaths);
    return (ok: res['success'] == true, message: res['message']?.toString());
  }

  Future<({String? token, String? permanentToken})> getShareLink(
      String collectionId) async {
    final res = await api.get('get_share_link', {'id': collectionId});
    if (res['success'] != true) return (token: null, permanentToken: null);
    return (
      token: (res['share_token'] as String?),
      permanentToken: (res['permanent_share_token'] as String?),
    );
  }

  Future<String?> generateShareLink(String collectionId) async {
    final res =
        await api.postJson('generate_share_link', body: {'id': collectionId});
    return res['success'] == true ? res['share_token']?.toString() : null;
  }

  Future<String?> generatePermanentShareLink(String collectionId) async {
    final res = await api
        .postJson('generate_permanent_share_link', body: {'id': collectionId});
    return res['success'] == true
        ? res['permanent_share_token']?.toString()
        : null;
  }

  String shareUrl(String token) => '${api.baseUrl}/file-share.php#$token';

  Future<bool> deleteCollection(String id) async {
    final res = await api.postJson('file_delete_collection', body: {'id': id});
    return res['success'] == true;
  }

  Future<bool> deleteFile(String id) async {
    final res = await api.postJson('file_delete_item', body: {'id': id});
    return res['success'] == true;
  }

  String downloadUrl(String fileId) =>
      api.actionUrl('file_download', {'id': fileId});
}

class ReleaseNotesService {
  ReleaseNotesService(this.api);
  final ApiClient api;

  Future<Paged<ReleaseNote>> list({
    int page = 1,
    int limit = 50,
    String search = '',
  }) async {
    final res = await api.get('getReleaseNotes', {
      'page': '$page',
      'limit': '$limit',
      if (search.isNotEmpty) 'search': search,
    });
    return Paged(
      items: _rows(res['data'], ReleaseNote.fromJson),
      total: _total(res),
    );
  }

  Future<List<ActionType>> actionTypes() async {
    final res = await api.get('getActionTypes');
    return _rows(res['data'], ActionType.fromJson);
  }

  Future<List<PosVersion>> versions() async {
    final res = await api.get('getposversion', {'page': '1', 'limit': '500'});
    return _rows(res['data'], PosVersion.fromJson);
  }

  Future<bool> add({
    required int versionId,
    required int actionTypeId,
    required String notes,
  }) async {
    final res = await api.post('AddReleaseNotes', body: {
      'version': '$versionId',
      'actiontype': '$actionTypeId',
      'notes': notes,
    });
    return res['success'] == true;
  }

  Future<bool> update({
    required int id,
    required int versionId,
    required int actionTypeId,
    required String notes,
  }) async {
    final res = await api.post('updateReleaseNotes', body: {
      'id': '$id',
      'version': '$versionId',
      'actiontype': '$actionTypeId',
      'notes': notes,
    });
    return res['success'] == true;
  }

  Future<bool> delete(int id) async {
    final res = await api.post('deleteReleaseNotes', body: {'id': '$id'});
    return res['success'] == true;
  }
}

class HelpService {
  HelpService(this.api);
  final ApiClient api;

  Future<Paged<HelpTopic>> list() async {
    final res = await api.get('getHelpTopics');
    final items = _rows(res['data'], HelpTopic.fromJson);
    return Paged(items: items, total: items.length);
  }

  Future<bool> add({
    required String title,
    required String description,
    required String icon,
    required String iconColor,
  }) async {
    final res = await api.postJson('addHelpTopic', body: {
      'title': title,
      'description': description,
      'icon': icon,
      'iconColor': iconColor,
    });
    return res['success'] != false;
  }

  Future<bool> update({
    required int id,
    required String title,
    required String description,
    required String icon,
    required String iconColor,
  }) async {
    final res = await api.post('updateHelpTopic', body: {
      'id': '$id',
      'title': title,
      'description': description,
      'icon': icon,
      'iconColor': iconColor,
    });
    return res['success'] == true;
  }

  Future<bool> delete(int id) async {
    final res = await api.post('deleteHelpTopic', body: {'id': '$id'});
    return res['success'] == true;
  }
}

class LicenseService {
  LicenseService(this.api);
  final ApiClient api;

  Future<Paged<LicenseKey>> list({int page = 1, int limit = 100}) async {
    final res =
        await api.get('getLicenseKey', {'page': '$page', 'limit': '$limit'});
    return Paged(
      items: _rows(res['data'], LicenseKey.fromJson),
      total: _total(res),
    );
  }

  Future<({String? key, String message})> generateKey() async {
    final res = await api.get('desktopGenerateLicenseKey');
    final key = res['license_key']?.toString() ?? '';
    return (
      key: res['success'] == true && key.isNotEmpty ? key : null,
      message: (res['message'] ?? '').toString(),
    );
  }

  Future<Map<String, dynamic>?> getById(int id) async {
    final res = await api.get('GetLicenseKeyByID', {'id': '$id'});
    return res.isEmpty || res['id'] == null ? null : res;
  }

  Future<({bool ok, String message})> save(Map<String, String> form) async {
    final action = (form['license_id'] ?? '').isNotEmpty
        ? 'update_license_key'
        : 'add_license_key';
    final res = await api.post(action, body: form);
    return (
      ok: res['success'] == true,
      message: (res['message'] ?? '').toString(),
    );
  }

  Future<({bool ok, String message})> delete(int id) async {
    final res = await api.post('delete_license_key', body: {'id': '$id'});
    return (
      ok: res['success'] == true,
      message: (res['message'] ?? '').toString(),
    );
  }
}
