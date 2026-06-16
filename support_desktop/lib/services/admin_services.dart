// Service layer for the admin/console pages. Each service wraps the
// matching api.php actions with cookie-aware GET/POST via [ApiClient].

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

  /// getEmails reads `$_POST` (page/size/search/source).
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

  Future<bool> delete({required int id, required String source}) async {
    final res =
        await api.post('deleteEmail', body: {'id': '$id', 'source': source});
    return res['success'] == true;
  }

  Future<bool> sendSingle({
    required String email,
    required String subject,
    required String message,
  }) async {
    final res = await api.post('sendSingleEmail',
        body: {'email': email, 'subject': subject, 'message': message});
    return res['success'] == true;
  }

  Future<bool> sendAll({
    required String subject,
    required String message,
  }) async {
    final res = await api.post('sendEmailToAll',
        body: {'subject': subject, 'message': message});
    return res['success'] == true;
  }
}

class UserService {
  UserService(this.api);
  final ApiClient api;

  /// getUsers reads `$_GET` (search/page/limit) and excludes super_admin /
  /// customer / guest roles.
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

  /// Sends a 6-digit OTP to the signed-in user's email. Required before
  /// the credentials vault can be read or written this session.
  Future<({bool ok, String message})> requestOtp() async {
    final res = await api.post('requestCredentialsOTP');
    return (
      ok: res['success'] == true,
      message: (res['message'] ?? '').toString(),
    );
  }

  Future<bool> verifyOtp(String code) async {
    final res =
        await api.post('verifyCredentialsOTP', body: {'otp_code': code});
    return res['success'] == true;
  }

  Future<Paged<Credential>> list() async {
    final res = await api.get('getCredentials');
    if (res['success'] != true) {
      throw Exception(res['message']?.toString() ?? 'OTP verification required');
    }
    final items = _rows(res['data'], Credential.fromJson);
    return Paged(items: items, total: items.length);
  }

  Future<bool> save({
    int? id,
    required String clientName,
    required String credentialsText,
  }) async {
    final res = await api.post('saveCredential', body: {
      if (id != null) 'id': '$id',
      'client_name': clientName,
      'credentials_text': credentialsText,
    });
    return res['success'] == true;
  }

  Future<bool> delete(int id) async {
    final res = await api.post('deleteCredential', body: {'id': '$id'});
    return res['success'] == true;
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

  /// Creates a text post. [isDraft] saves it as a draft, otherwise it
  /// publishes immediately. (Category/media attachment is web-only.)
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

  /// The endpoint returns every collection; [search] filters client-side
  /// by name or email.
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

  /// Upload one or more files, creating a new collection named [collectionName].
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

  /// Existing share token for a collection (null if none issued yet).
  Future<({String? token, String? permanentToken})> getShareLink(
      String collectionId) async {
    final res = await api.get('get_share_link', {'id': collectionId});
    if (res['success'] != true) return (token: null, permanentToken: null);
    return (
      token: (res['share_token'] as String?),
      permanentToken: (res['permanent_share_token'] as String?),
    );
  }

  /// Issue (or rotate) a temporary share token; returns the token.
  Future<String?> generateShareLink(String collectionId) async {
    final res =
        await api.postJson('generate_share_link', body: {'id': collectionId});
    return res['success'] == true ? res['share_token']?.toString() : null;
  }

  /// Issue (or rotate) a permanent share token; returns the token.
  Future<String?> generatePermanentShareLink(String collectionId) async {
    final res = await api
        .postJson('generate_permanent_share_link', body: {'id': collectionId});
    return res['success'] == true
        ? res['permanent_share_token']?.toString()
        : null;
  }

  /// Public, shareable URL for a token (mirrors the web's file-share page).
  String shareUrl(String token) => '${api.baseUrl}/file-share.php#$token';

  /// file_delete_collection / file_delete_item read a JSON body.
  Future<bool> deleteCollection(String id) async {
    final res = await api.postJson('file_delete_collection', body: {'id': id});
    return res['success'] == true;
  }

  Future<bool> deleteFile(String id) async {
    final res = await api.postJson('file_delete_item', body: {'id': id});
    return res['success'] == true;
  }

  /// Authenticated download URL for a file (opened via the OS handler).
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

  /// Versions for the editor dropdown (id + label), sourced from posversion.
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
    // addHelpTopic reads php://input JSON, not $_POST.
    final res = await api.postJson('addHelpTopic', body: {
      'title': title,
      'description': description,
      'icon': icon,
      'iconColor': iconColor,
    });
    return res['success'] != false; // returns inserted id on success
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

  /// licenseType: '0' = permanent, '1' = trial. expirationDate ignored when
  /// permanent.
  Future<bool> add({
    required String licenseKey,
    required String licenseType,
    String? expirationDate,
  }) async {
    final res = await api.post('add_license_key', body: {
      'license_key': licenseKey,
      'license_type': licenseType,
      'expiration_date': licenseType == '0' ? '' : (expirationDate ?? ''),
    });
    return res['success'] == true;
  }

  Future<bool> update({
    required int id,
    required String licenseKey,
    required String licenseType,
    String? expirationDate,
    String storeName = '',
    String storeAddress = '',
    String storeEmail = '',
  }) async {
    final res = await api.post('update_license_key', body: {
      'license_id': '$id',
      'license_key': licenseKey,
      'license_type': licenseType,
      'expiration_date': licenseType == '0' ? '' : (expirationDate ?? ''),
      'store_name': storeName,
      'store_address': storeAddress,
      'store_email': storeEmail,
    });
    return res['success'] == true;
  }

  Future<bool> delete(int id) async {
    final res = await api.post('delete_license_key', body: {'id': '$id'});
    return res['success'] == true;
  }
}
