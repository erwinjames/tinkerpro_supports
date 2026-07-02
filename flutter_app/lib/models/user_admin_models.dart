// Domain model for the Users / User Management feature. Mirrors the rows
// returned by `users` on api.php (data: [...], totalRecords: N), with fields
// id, full_name, email, username, role, permissions, account_status.

import 'dart:convert';

// The known permission feature flags. Order here drives the switch list in the
// edit/add form. Keep in sync with the backend's permission map.
const List<String> kUserPermissionKeys = [
  'dashboard',
  'ticket',
  'chat',
  'posversion',
  'releasenotes',
  'licensekey',
  'blogposts',
  'customer',
  'client',
  'clientOffer',
  'user',
  'emails',
  'settings',
  'activitylogs',
  'task',
  'helpPage',
  'analyze',
  'files',
  'credentials',
];

// The role choices offered in the form's dropdown.
const List<String> kUserRoles = [
  'admin',
  'user',
  'technical_staff',
  'developer',
];

/// Default permissions applied when a role is selected in the user form.
/// Mirrors the web's `defaultPermissions` map (user.php). Keys not listed for a
/// role default to false via [defaultPermissionsForRole].
const Map<String, Map<String, bool>> kRoleDefaultPermissions = {
  'admin': {
    'dashboard': true,
    'ticket': true,
    'chat': true,
    'posversion': true,
    'releasenotes': true,
    'licensekey': true,
    'blogposts': true,
    'customer': true,
    'client': true,
    'clientOffer': true,
    'user': true,
    'emails': true,
    'settings': true,
    'activitylogs': false,
    'task': true,
    'helpPage': true,
    'analyze': true,
  },
  'user': {
    'dashboard': true,
    'ticket': true,
    'chat': true,
    'settings': true,
    'task': true,
  },
  'technical_staff': {
    'dashboard': true,
    'ticket': true,
    'chat': true,
    'licensekey': true,
    'client': true,
    'settings': true,
    'files': true,
  },
  'developer': {
    'dashboard': true,
    'ticket': true,
    'chat': true,
    'posversion': true,
    'releasenotes': true,
    'licensekey': true,
    'customer': true,
    'client': true,
    'settings': true,
    'task': true,
    'credentials': true,
    'files': true,
  },
};

/// A full permission map for [role] — every key in [kUserPermissionKeys],
/// defaulting unspecified keys to false. Returns a fresh mutable map.
Map<String, bool> defaultPermissionsForRole(String role) {
  final defaults = kRoleDefaultPermissions[role] ?? const {};
  return {for (final k in kUserPermissionKeys) k: defaults[k] ?? false};
}

class AdminUser {
  AdminUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.email,
    required this.role,
    required this.status,
    required this.permissions,
  });

  final int id;
  final String username;
  final String fullName;
  final String email;
  final String role;

  /// true = active account, false = disabled.
  final bool status;

  /// Feature flags. Only the known keys are tracked; missing keys default false.
  final Map<String, bool> permissions;

  factory AdminUser.fromJson(Map<String, dynamic> json) => AdminUser(
        id: _asInt(json['id']),
        username: (json['username'] ?? '').toString(),
        fullName: (json['userfullname'] ?? json['full_name'] ?? '').toString(),
        email: (json['useremail'] ?? json['email'] ?? '').toString(),
        role: (json['role'] ?? '').toString(),
        status: _asStatus(json['status'] ?? json['account_status']),
        permissions: _parsePermissions(json['permissions']),
      );
}

// Build a full {key: bool} map over the known keys from whatever the backend
// returns: a JSON object, a JSON-encoded string, or a list of granted keys.
Map<String, bool> _parsePermissions(Object? raw) {
  final result = <String, bool>{for (final k in kUserPermissionKeys) k: false};

  Object? decoded = raw;
  if (decoded is String) {
    final s = decoded.trim();
    if (s.isEmpty) return result;
    try {
      decoded = jsonDecode(s);
    } catch (_) {
      return result;
    }
  }

  if (decoded is Map) {
    decoded.forEach((key, value) {
      final k = key.toString();
      if (result.containsKey(k)) result[k] = _asBool(value);
    });
  } else if (decoded is List) {
    for (final item in decoded) {
      final k = item.toString();
      if (result.containsKey(k)) result[k] = true;
    }
  }
  return result;
}

bool _asBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final s = value.trim().toLowerCase();
    return s == '1' || s == 'true';
  }
  return false;
}

// Account status: backend uses 'active'/'disabled' strings; also accept 1/0.
bool _asStatus(Object? value) {
  if (value == null) return true;
  if (value is bool) return value;
  if (value is num) return value != 0;
  final s = value.toString().trim().toLowerCase();
  if (s == 'disabled' || s == 'inactive' || s == '0' || s == 'false') {
    return false;
  }
  return true;
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
