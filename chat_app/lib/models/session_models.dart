import 'dart:convert';

class UserSession {
  UserSession({
    required this.userId,
    required this.username,
    required this.role,
    this.permissions = const {},
  });

  final int userId;
  final String username;
  final String role;
  final Map<String, bool> permissions;

  bool can(String feature) => permissions[feature] == true;

  factory UserSession.fromJson(Map<String, dynamic> json) => UserSession(
        userId: _asInt(json['userID'] ?? json['user_id']),
        username: (json['username'] ?? json['user_name'] ?? '—').toString(),
        role: (json['userRole'] ?? json['user_role'] ?? 'user').toString(),
        permissions: _asPermissions(json['permissions']),
      );
}

Map<String, bool> _asPermissions(dynamic raw) {
  if (raw is String && raw.isNotEmpty) {
    try {
      raw = jsonDecode(raw);
    } catch (_) {
      return const {};
    }
  }
  if (raw is! Map) return const {};
  final out = <String, bool>{};
  raw.forEach((key, value) {
    out[key.toString()] = _asBool(value);
  });
  return out;
}

bool _asBool(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.trim().toLowerCase();
    return s == '1' || s == 'true' || s == 'yes';
  }
  return false;
}

int _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}
