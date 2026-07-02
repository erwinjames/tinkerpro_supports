// Domain model for the Activity Logs feature. Mirrors the `getActivityLogs`
// row shape returned by `api.php` (data: [...], totalRecords: N).

class ActivityLog {
  ActivityLog({
    required this.id,
    required this.userId,
    required this.action,
    required this.details,
    required this.ipAddress,
    required this.createdAt,
    required this.username,
  });

  final int id;
  final int userId;
  final String action;
  final String details;
  final String ipAddress;
  final String createdAt;

  /// Joined from the users table; may be empty when the user was removed.
  final String username;

  factory ActivityLog.fromJson(Map<String, dynamic> json) => ActivityLog(
        id: _asInt(json['id']),
        userId: _asInt(json['user_id']),
        action: (json['action'] ?? '').toString(),
        details: (json['details'] ?? '').toString(),
        ipAddress: (json['ip_address'] ?? '').toString(),
        createdAt: (json['created_at'] ?? '').toString(),
        username: (json['username'] ?? '').toString(),
      );
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
