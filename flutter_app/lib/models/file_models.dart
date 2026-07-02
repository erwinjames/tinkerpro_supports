// Domain models for the File Management feature. Mirror the row shapes
// returned by api.php's `file_*` actions (see utils/models/file-collection-facade.php).
//
// Collection and file IDs are server-generated UUID strings (not ints), so
// every id here is a String.

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
  });

  final String id;
  final String name;
  final String email;

  /// 'default' or 'distribution'.
  final String collectionType;
  final String createdAt;
  final int fileCount;

  /// Sum of all member file sizes, in bytes.
  final int totalSize;

  /// True when the timed (expiring) share link is no longer valid.
  final bool linkExpired;

  /// True when a permanent share token has been issued for this collection.
  final bool hasPermanentLink;

  bool get isDistribution => collectionType == 'distribution';

  factory FileCollection.fromJson(Map<String, dynamic> json) => FileCollection(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        email: (json['email'] ?? '').toString(),
        collectionType: (json['collection_type'] ?? 'default').toString(),
        createdAt: (json['created_at'] ?? '').toString(),
        fileCount: _asInt(json['file_count']),
        totalSize: _asInt(json['total_size']),
        linkExpired: _asBool(json['link_expired']),
        hasPermanentLink: _asBool(json['has_permanent_link']),
      );
}

class StoredFile {
  StoredFile({
    required this.id,
    required this.collectionId,
    required this.filename,
    required this.fileSize,
    required this.mimeType,
  });

  final String id;
  final String collectionId;
  final String filename;
  final int fileSize;

  /// May be empty — the backend table has no mime column, so this is best
  /// effort from whatever the row happens to expose.
  final String mimeType;

  factory StoredFile.fromJson(Map<String, dynamic> json) => StoredFile(
        id: (json['id'] ?? '').toString(),
        collectionId: (json['collection_id'] ?? '').toString(),
        // Backend column is `file_name`; accept `filename` too for safety.
        filename: (json['file_name'] ?? json['filename'] ?? '').toString(),
        fileSize: _asInt(json['file_size']),
        mimeType: (json['mime_type'] ?? '').toString(),
      );
}

/// Bytes → human-readable size (e.g. 1536 → "1.5 KB").
String humanFileSize(int bytes) {
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

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? num.tryParse(value)?.toInt() ?? 0;
  return 0;
}

bool _asBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) return value == '1' || value.toLowerCase() == 'true';
  return false;
}
