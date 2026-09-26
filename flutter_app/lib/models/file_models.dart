class FileCollection {
  FileCollection({
    required this.id,
    required this.name,
    required this.email,
    required this.collectionType,
    required this.createdAt,
    required this.fileCount,
    required this.totalSize,
    required this.linkExpired,
    required this.hasPermanentLink,
    this.parentId,
    this.subfolderCount = 0,
    this.isFavorite = false,
    this.vendorVisible = false,
    this.ojtVisible = false,
    this.playStoreUrl = '',
    this.posVersion = '',
    this.releaseNotes = '',
    this.shareToken = '',
    this.shareTokenExpiresAt = '',
    this.permanentShareToken = '',
  });

  final String id;
  final String name;
  final String email;

  final String collectionType;
  final String createdAt;
  final int fileCount;

  final int totalSize;

  final bool linkExpired;

  final bool hasPermanentLink;

  final String? parentId;
  final int subfolderCount;
  final bool isFavorite;
  final bool vendorVisible;
  final bool ojtVisible;
  final String playStoreUrl;
  final String posVersion;
  final String releaseNotes;
  final String shareToken;
  final String shareTokenExpiresAt;
  final String permanentShareToken;

  bool get isDistribution => collectionType == 'distribution';
  bool get isInstaller => collectionType == 'installer';
  bool get isDefaultType => !isDistribution && !isInstaller;

  String get displayName => name.trim().isEmpty ? 'Untitled collection' : name;

  DateTime? get expiresAt => parseServerDate(shareTokenExpiresAt);

  bool get expiringLinkUsable {
    if (shareToken.isEmpty || linkExpired) return false;
    final at = expiresAt;
    return at != null && at.isAfter(DateTime.now());
  }

  FileCollection copyWith({
    String? name,
    String? collectionType,
    bool? isFavorite,
    bool? vendorVisible,
    bool? ojtVisible,
    String? releaseNotes,
    String? playStoreUrl,
    String? permanentShareToken,
    bool? hasPermanentLink,
    String? parentId,
    bool clearParent = false,
  }) => FileCollection(
    id: id,
    name: name ?? this.name,
    email: email,
    collectionType: collectionType ?? this.collectionType,
    createdAt: createdAt,
    fileCount: fileCount,
    totalSize: totalSize,
    linkExpired: linkExpired,
    hasPermanentLink: hasPermanentLink ?? this.hasPermanentLink,
    parentId: clearParent ? null : (parentId ?? this.parentId),
    subfolderCount: subfolderCount,
    isFavorite: isFavorite ?? this.isFavorite,
    vendorVisible: vendorVisible ?? this.vendorVisible,
    ojtVisible: ojtVisible ?? this.ojtVisible,
    playStoreUrl: playStoreUrl ?? this.playStoreUrl,
    posVersion: posVersion,
    releaseNotes: releaseNotes ?? this.releaseNotes,
    shareToken: shareToken,
    shareTokenExpiresAt: shareTokenExpiresAt,
    permanentShareToken: permanentShareToken ?? this.permanentShareToken,
  );

  factory FileCollection.fromJson(Map<String, dynamic> json) {
    final parent = (json['parent_id'] ?? '').toString().trim();
    return FileCollection(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      collectionType: (json['collection_type'] ?? 'default').toString(),
      createdAt: (json['created_at'] ?? '').toString(),
      fileCount: _asInt(json['file_count']),
      totalSize: _asInt(json['total_size']),
      linkExpired: _asBool(json['link_expired']),
      hasPermanentLink:
          _asBool(json['has_permanent_link']) ||
          (json['permanent_share_token'] ?? '').toString().isNotEmpty,
      parentId: parent.isEmpty || parent.toLowerCase() == 'null'
          ? null
          : parent,
      subfolderCount: _asInt(json['subfolder_count']),
      isFavorite: _asBool(json['is_favorite']),
      vendorVisible: _asBool(json['vendor_visible']),
      ojtVisible: _asBool(json['ojt_visible']),
      playStoreUrl: (json['play_store_url'] ?? '').toString(),
      posVersion: (json['pos_version'] ?? '').toString(),
      releaseNotes: (json['release_notes'] ?? '').toString(),
      shareToken: (json['share_token'] ?? '').toString(),
      shareTokenExpiresAt: (json['share_token_expires_at'] ?? '').toString(),
      permanentShareToken: (json['permanent_share_token'] ?? '').toString(),
    );
  }
}

class StoredFile {
  StoredFile({
    required this.id,
    required this.collectionId,
    required this.filename,
    required this.fileSize,
    required this.mimeType,
    this.createdAt = '',
    this.fileHash = '',
  });

  final String id;
  final String collectionId;
  final String filename;
  final int fileSize;

  final String mimeType;
  final String createdAt;
  final String fileHash;

  factory StoredFile.fromJson(Map<String, dynamic> json) => StoredFile(
    id: (json['id'] ?? '').toString(),
    collectionId: (json['collection_id'] ?? '').toString(),
    filename: (json['file_name'] ?? json['filename'] ?? '').toString(),
    fileSize: _asInt(json['file_size']),
    mimeType: (json['mime_type'] ?? '').toString(),
    createdAt: (json['created_at'] ?? '').toString(),
    fileHash: (json['file_hash'] ?? '').toString(),
  );
}

class FolderTotals {
  const FolderTotals({
    required this.files,
    required this.size,
    required this.folders,
  });
  final int files;
  final int size;
  final int folders;
}

class StorageUsage {
  StorageUsage({
    required this.available,
    required this.path,
    required this.diskTotal,
    required this.diskFree,
    required this.diskUsed,
    required this.usedPercent,
    required this.managedBytes,
    required this.collectionsBytes,
    required this.folderSyncBytes,
    required this.folderSyncFiles,
    required this.folderSyncPartial,
    required this.status,
  });

  final bool available;
  final String path;
  final double diskTotal;
  final double diskFree;
  final double diskUsed;
  final double usedPercent;
  final double managedBytes;
  final double collectionsBytes;
  final double folderSyncBytes;
  final int folderSyncFiles;
  final bool folderSyncPartial;
  final String status;

  bool get critical => status == 'critical';
  bool get warning => status == 'warning';

  factory StorageUsage.fromJson(Map<String, dynamic> json) => StorageUsage(
    available: _asBool(json['available']),
    path: (json['path'] ?? '').toString(),
    diskTotal: _asDouble(json['disk_total']),
    diskFree: _asDouble(json['disk_free']),
    diskUsed: _asDouble(json['disk_used']),
    usedPercent: _asDouble(json['used_percent']),
    managedBytes: _asDouble(json['managed_bytes']),
    collectionsBytes: _asDouble(json['collections_bytes']),
    folderSyncBytes: _asDouble(json['folder_sync_bytes']),
    folderSyncFiles: _asInt(json['folder_sync_files']),
    folderSyncPartial: _asBool(json['folder_sync_partial']),
    status: (json['status'] ?? 'unknown').toString(),
  );
}

class FileChecksum {
  FileChecksum({
    required this.fileName,
    required this.fileSize,
    required this.sha256,
  });
  final String fileName;
  final int fileSize;
  final String sha256;

  factory FileChecksum.fromJson(Map<String, dynamic> json) => FileChecksum(
    fileName: (json['file_name'] ?? '').toString(),
    fileSize: _asInt(json['file_size']),
    sha256: (json['sha256'] ?? '').toString(),
  );
}

String humanFileSize(num bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  final str = unit == 0
      ? size.toStringAsFixed(0)
      : size.toStringAsFixed(size >= 100 ? 0 : 1);
  return '$str ${units[unit]}';
}

const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

DateTime? parseServerDate(String? raw) {
  final value = (raw ?? '').trim();
  if (value.isEmpty || value.startsWith('0000')) return null;
  return DateTime.tryParse(value.replaceFirst(' ', 'T'));
}

String formatDateLabel(String? raw) {
  final date = parseServerDate(raw);
  if (date == null) return '';
  return '${_months[date.month - 1]} ${date.day}, ${date.year}';
}

String formatCountdown(Duration left) {
  if (left.inSeconds <= 0) return 'expired';
  final hours = left.inHours;
  final minutes = left.inMinutes % 60;
  final seconds = left.inSeconds % 60;
  if (hours > 0) return '${hours}h ${minutes}m';
  if (minutes > 0) {
    return '${minutes}m ${seconds < 10 ? '0' : ''}${seconds}s';
  }
  return '${seconds}s';
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    return int.tryParse(value) ?? num.tryParse(value)?.toInt() ?? 0;
  }
  return 0;
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

bool _asBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) return value == '1' || value.toLowerCase() == 'true';
  return false;
}
