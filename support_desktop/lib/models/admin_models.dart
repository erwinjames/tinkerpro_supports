// Models for the admin/console pages ported from the web app
// (POS Version, Release Notes, License Key, Users, Email, Help,
// Credentials, Blog Posts, BIR Registration, Files, Activity Logs).
//
// Each model maps one row from its api.php endpoint. Parsing is defensive
// (`_str` / `_int`) because the PHP layer returns loosely-typed JSON.

String _str(dynamic v) => v == null ? '' : v.toString();

int _int(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

/// A page of rows plus the total count, the shape every paginated admin
/// endpoint returns (`{data: [...], totalRecords|total: N}`).
class Paged<T> {
  Paged({required this.items, required this.total});
  final List<T> items;
  final int total;
}

class PosVersion {
  PosVersion({required this.id, required this.version, required this.date});
  final int id;
  final String version;
  final String date;

  factory PosVersion.fromJson(Map<String, dynamic> j) => PosVersion(
        id: _int(j['id']),
        version: _str(j['version']),
        date: _str(j['date']),
      );
}

class EmailRecipient {
  EmailRecipient({
    required this.id,
    required this.email,
    required this.businessType,
    required this.source,
    required this.createdAt,
  });
  final int id;
  final String email;
  final String businessType;
  final String source; // 'emails' | 'leads'
  final String createdAt;

  factory EmailRecipient.fromJson(Map<String, dynamic> j) => EmailRecipient(
        id: _int(j['id']),
        email: _str(j['email']),
        businessType: _str(j['business_type']),
        source: _str(j['source']),
        createdAt: _str(j['created_at']),
      );
}

class AdminUser {
  AdminUser({
    required this.id,
    required this.fullName,
    required this.email,
    required this.username,
    required this.role,
    required this.accountStatus,
    required this.onlineStatus,
  });
  final int id;
  final String fullName;
  final String email;
  final String username;
  final String role;
  final String accountStatus;
  final String onlineStatus;

  bool get isActive => accountStatus.toLowerCase() == 'active';

  factory AdminUser.fromJson(Map<String, dynamic> j) => AdminUser(
        id: _int(j['id']),
        fullName: _str(j['full_name']),
        email: _str(j['email']),
        username: _str(j['username']),
        role: _str(j['role']),
        accountStatus: _str(j['account_status']),
        onlineStatus: _str(j['online_status']),
      );
}

class Credential {
  Credential({
    required this.id,
    required this.clientName,
    required this.credentialsText,
    required this.createdAt,
  });
  final int id;
  final String clientName;
  final String credentialsText;
  final String createdAt;

  factory Credential.fromJson(Map<String, dynamic> j) => Credential(
        id: _int(j['id']),
        clientName: _str(j['client_name']),
        credentialsText: _str(j['credentials_text']),
        createdAt: _str(j['created_at']),
      );
}

class ActivityLog {
  ActivityLog({
    required this.id,
    required this.username,
    required this.action,
    required this.details,
    required this.ipAddress,
    required this.createdAt,
  });
  final int id;
  final String username;
  final String action;
  final String details;
  final String ipAddress;
  final String createdAt;

  factory ActivityLog.fromJson(Map<String, dynamic> j) => ActivityLog(
        id: _int(j['id']),
        username: _str(j['username']),
        action: _str(j['action']),
        details: _str(j['details']),
        ipAddress: _str(j['ip_address']),
        createdAt: _str(j['created_at']),
      );
}

class BlogPost {
  BlogPost({
    required this.id,
    required this.title,
    required this.content,
    required this.status,
    required this.isDraft,
    required this.createdAt,
  });
  final int id;
  final String title;
  final String content;
  final String status;
  final bool isDraft;
  final String createdAt;

  /// Plain-text preview — strips HTML tags from the stored rich content.
  String get preview =>
      content.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  factory BlogPost.fromJson(Map<String, dynamic> j) => BlogPost(
        id: _int(j['id']),
        title: _str(j['title']),
        content: _str(j['content']),
        status: _str(j['status']),
        isDraft: _int(j['is_draft']) == 1,
        createdAt: _str(j['created_at']),
      );
}

class FileCollection {
  FileCollection({
    required this.id,
    required this.name,
    required this.email,
    required this.type,
    required this.fileCount,
    required this.totalSize,
    required this.createdAt,
  });
  // Collection ids are server-generated UUID strings, not ints.
  final String id;
  final String name;
  final String email;
  final String type;
  final int fileCount;
  final int totalSize;
  final String createdAt;

  factory FileCollection.fromJson(Map<String, dynamic> j) => FileCollection(
        id: _str(j['id']),
        name: _str(j['name']),
        email: _str(j['email']),
        type: _str(j['collection_type']),
        fileCount: _int(j['file_count']),
        totalSize: _int(j['total_size']),
        createdAt: _str(j['created_at']),
      );
}

class FileItem {
  FileItem({
    required this.id,
    required this.name,
    required this.size,
    required this.createdAt,
  });
  // File ids are server-generated UUID strings, not ints.
  final String id;
  final String name;
  final int size;
  final String createdAt;

  factory FileItem.fromJson(Map<String, dynamic> j) => FileItem(
        id: _str(j['id']),
        name: _str(j['file_name'] ?? j['original_name'] ?? j['name']),
        size: _int(j['file_size'] ?? j['size']),
        createdAt: _str(j['created_at']),
      );
}

class ActionType {
  ActionType({required this.id, required this.type});
  final int id;
  final String type;
  factory ActionType.fromJson(Map<String, dynamic> j) =>
      ActionType(id: _int(j['id']), type: _str(j['type']));
}

class ReleaseNote {
  ReleaseNote({
    required this.id,
    required this.notes,
    required this.version,
    required this.posVersionId,
    required this.actionId,
    required this.actionType,
    required this.createdAt,
  });

  final int id;
  final String notes;
  final String version;
  final int posVersionId;
  final int actionId;
  final String actionType;
  final String createdAt;

  factory ReleaseNote.fromJson(Map<String, dynamic> j) => ReleaseNote(
        id: _int(j['NotesID']),
        notes: _str(j['release_notes']),
        version: _str(j['version']),
        posVersionId: _int(j['posversionID']),
        actionId: _int(j['actionID']),
        actionType: _str(j['action_type']),
        createdAt: _str(j['created_at']),
      );
}

class HelpTopic {
  HelpTopic({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.iconColor,
  });

  final int id;
  final String title;
  final String description;
  final String icon;
  final String iconColor;

  factory HelpTopic.fromJson(Map<String, dynamic> j) => HelpTopic(
        id: _int(j['id']),
        title: _str(j['title']),
        description: _str(j['description']),
        icon: _str(j['icon']),
        iconColor: _str(j['icon_color']),
      );
}

class LicenseKey {
  LicenseKey({
    required this.id,
    required this.licenseKey,
    required this.type,
    required this.dateExpired,
    required this.storeName,
    required this.storeAddress,
    required this.storeEmail,
    required this.isUsed,
  });

  final int id;
  final String licenseKey;

  /// The `trial` column: '0' (or empty) reads as Permanent, anything else
  /// as a trial/temporary key.
  final String type;
  final String dateExpired;
  final String storeName;
  final String storeAddress;
  final String storeEmail;
  final bool isUsed;

  bool get isPermanent => type.isEmpty || type == '0';

  factory LicenseKey.fromJson(Map<String, dynamic> j) => LicenseKey(
        id: _int(j['id']),
        licenseKey: _str(j['license_key']),
        type: _str(j['trial']),
        dateExpired: _str(j['date_expired']),
        storeName: _str(j['store_name']),
        storeAddress: _str(j['store_address']),
        storeEmail: _str(j['store_email']),
        isUsed: _int(j['is_used']) == 1,
      );
}
