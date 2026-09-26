import 'dart:convert';

class PermissionDef {
  const PermissionDef(
    this.key,
    this.label, {
    this.parent,
    this.hint,
    this.exclusiveWith,
    this.inheritWhenMissing = false,
  });

  final String key;
  final String label;
  final String? parent;
  final String? hint;
  final String? exclusiveWith;
  final bool inheritWhenMissing;
}

class PermissionGroup {
  const PermissionGroup(this.title, this.items);
  final String title;
  final List<PermissionDef> items;
}

const List<PermissionGroup> kPermissionGroups = [
  PermissionGroup('Core Suite', [
    PermissionDef('dashboard', 'Dashboard'),
    PermissionDef(
      'dashboardSignals',
      'Signal Chips',
      parent: 'dashboard',
      hint: 'Open tickets, unassigned, chats waiting',
      inheritWhenMissing: true,
    ),
    PermissionDef(
      'dashboardToday',
      'Today',
      parent: 'dashboard',
      hint: 'Counters since midnight',
      inheritWhenMissing: true,
    ),
    PermissionDef(
      'dashboardHeartbeat',
      'Activity Heartbeat',
      parent: 'dashboard',
      hint: 'Streaming 24-hour activity chart',
      inheritWhenMissing: true,
    ),
    PermissionDef(
      'dashboardFeed',
      'Activity Stream',
      parent: 'dashboard',
      hint: 'Live feed of staff activity',
      inheritWhenMissing: true,
    ),
    PermissionDef(
      'dashboardTotals',
      'Totals',
      parent: 'dashboard',
      hint: 'Stat cards with 14-day trend',
      inheritWhenMissing: true,
    ),
    PermissionDef(
      'dashboardRevenue',
      'License Revenue',
      parent: 'dashboard',
      hint: 'Vendor licence payment figures (admins only)',
    ),
    PermissionDef(
      'dashboardStatus',
      'Status Overview',
      parent: 'dashboard',
      hint: 'Doughnut charts for health signals',
      inheritWhenMissing: true,
    ),
    PermissionDef(
      'dashboardDistribution',
      'Distribution',
      parent: 'dashboard',
      hint: 'Market and geography charts',
      inheritWhenMissing: true,
    ),
    PermissionDef(
      'dashboardTrends',
      'Activity Trends',
      parent: 'dashboard',
      hint: 'Ticket priority and 6-month trend',
      inheritWhenMissing: true,
    ),
    PermissionDef(
      'dashboardThroughput',
      'Throughput',
      parent: 'dashboard',
      hint: 'Emails, files and barcodes over 6 months',
      inheritWhenMissing: true,
    ),
    PermissionDef('ticket', 'Ticket'),
    PermissionDef('chat', 'Chat'),
    PermissionDef(
      'chatCustomers',
      'Customer Chats',
      parent: 'chat',
      hint: 'Customer, guest and Facebook conversations',
    ),
    PermissionDef(
      'chatVendors',
      'Vendor Chats',
      parent: 'chat',
      hint: 'Conversations opened from the vendor portal',
    ),
    PermissionDef(
      'messageRequests',
      'Facebook Chats',
      parent: 'chat',
      hint: 'Handles the Facebook Chats queue',
    ),
    PermissionDef('task', 'Task'),
  ]),
  PermissionGroup('Operations & POS', [
    PermissionDef('posversion', 'POS Version'),
    PermissionDef('releasenotes', 'Release Notes'),
    PermissionDef('licensekey', 'License Key'),
    PermissionDef('zreading', 'Z-Reading Request'),
    PermissionDef('installer', 'Installer'),
    PermissionDef('barcode', 'Barcode'),
  ]),
  PermissionGroup('CRM & Clients', [
    PermissionDef('customer', 'BIR Registration'),
    PermissionDef('clientOffer', 'Leads / Forms'),
    PermissionDef('client', 'Client'),
    PermissionDef('credentials', 'Credentials Storage'),
    PermissionDef('blogposts', 'Blog Posts'),
  ]),
  PermissionGroup('Admin & System', [
    PermissionDef('user', 'User'),
    PermissionDef(
      'employmentInfo',
      'Employment Info',
      parent: 'user',
      hint: 'Review and manage employment information sheets',
    ),
    PermissionDef('disabledAccounts', 'Disabled Accounts'),
    PermissionDef('emails', 'Email'),
    PermissionDef('activitylogs', 'Activity Logs'),
    PermissionDef('settings', 'Settings'),
    PermissionDef('analyze', 'Analyze'),
    PermissionDef('files', 'Files Management'),
    PermissionDef(
      'filesAllFolders',
      'All Folders',
      parent: 'files',
      hint: 'Sees every folder',
      exclusiveWith: 'filesShareOjt',
    ),
    PermissionDef(
      'filesShareOjt',
      'OJT File Management',
      parent: 'files',
      hint: 'Sees only folders shared with OJT',
      exclusiveWith: 'filesAllFolders',
    ),
    PermissionDef(
      'filesFolderSync',
      'Folder Sync',
      parent: 'files',
      hint: 'Opens their own Folder Sync workspace',
      inheritWhenMissing: true,
    ),
    PermissionDef('helpPage', 'Help Page'),
  ]),
];

final List<PermissionDef> kPermissionDefs = [
  for (final g in kPermissionGroups) ...g.items,
];

final List<String> kUserPermissionKeys = [
  for (final p in kPermissionDefs) p.key,
];

PermissionDef? permissionDef(String key) {
  for (final p in kPermissionDefs) {
    if (p.key == key) return p;
  }
  return null;
}

List<PermissionDef> childPermissionsOf(String parent) =>
    kPermissionDefs.where((p) => p.parent == parent).toList();

const List<String> kUserRoles = [
  'admin',
  'developer',
  'technical_staff',
  'sales',
  'user',
  'ojt',
];

const Map<String, String> kBuiltinRoleLabels = {
  'admin': 'Administrator',
  'developer': 'Developer',
  'technical_staff': 'Technical Staff',
  'sales': 'Sales',
  'user': 'Standard User',
  'ojt': 'OJT / Trainee',
};

const Map<String, String> kBuiltinRoleAccess = {
  'admin': 'Full Access',
  'developer': 'Build Access',
  'technical_staff': 'Support Access',
  'sales': 'Commercial Access',
  'user': 'Limited Access',
  'ojt': 'Restricted Access',
};

class RoleOption {
  const RoleOption({
    required this.slug,
    required this.label,
    this.custom = false,
    this.description = '',
    this.users = 0,
  });

  final String slug;
  final String label;
  final bool custom;
  final String description;
  final int users;

  factory RoleOption.fromJson(Map<String, dynamic> json) {
    final slug = (json['slug'] ?? '').toString().trim();
    final label = (json['label'] ?? '').toString().trim();
    final c = json['custom'];
    return RoleOption(
      slug: slug,
      label: label.isEmpty ? slug : label,
      custom: c == true || c == 1 || c.toString() == '1',
      description: (json['description'] ?? '').toString(),
      users: _asInt(json['users']),
    );
  }
}

const List<String> kReservedRoleSlugs = [
  'super_admin',
  'customer',
  'guest',
  'vendor',
  'none',
  'admin',
  'developer',
  'technical_staff',
  'sales',
  'user',
  'ojt',
];

String slugifyRoleName(String label) {
  var slug = label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  slug = slug.replaceAll(RegExp(r'_+'), '_');
  slug = slug.replaceAll(RegExp(r'^_+|_+$'), '');
  return slug.length > 30 ? slug.substring(0, 30) : slug;
}

class Branch {
  const Branch({
    required this.id,
    required this.name,
    required this.code,
    this.address = '',
    this.contactNumber = '',
    this.status = 'active',
    this.isMain = false,
    this.staffCount = 0,
  });

  final int id;
  final String name;
  final String code;
  final String address;
  final String contactNumber;
  final String status;
  final bool isMain;
  final int staffCount;

  bool get active => status.toLowerCase() != 'inactive';

  factory Branch.fromJson(Map<String, dynamic> json) => Branch(
    id: _asInt(json['id']),
    name: (json['name'] ?? '').toString(),
    code: (json['code'] ?? '').toString(),
    address: (json['address'] ?? '').toString(),
    contactNumber: (json['contact_number'] ?? '').toString(),
    status: (json['status'] ?? 'active').toString(),
    isMain: _asBool(json['is_main']),
    staffCount: _asInt(json['staff_count']),
  );
}

List<RoleOption> builtinRoleOptions() => [
  for (final r in kUserRoles)
    RoleOption(slug: r, label: kBuiltinRoleLabels[r] ?? r),
];

const Set<String> _allOn = {'__all__'};

const Map<String, Set<String>> _kRoleDefaultOn = {
  'admin': _allOn,
  'user': {
    'dashboard',
    'dashboardSignals',
    'dashboardToday',
    'dashboardHeartbeat',
    'dashboardFeed',
    'dashboardTotals',
    'dashboardStatus',
    'dashboardDistribution',
    'dashboardTrends',
    'dashboardThroughput',
    'ticket',
    'chat',
    'chatCustomers',
    'chatVendors',
    'settings',
    'task',
    'barcode',
  },
  'technical_staff': {
    'dashboard',
    'dashboardSignals',
    'dashboardToday',
    'dashboardHeartbeat',
    'dashboardFeed',
    'dashboardTotals',
    'dashboardStatus',
    'dashboardDistribution',
    'dashboardTrends',
    'dashboardThroughput',
    'ticket',
    'chat',
    'chatCustomers',
    'chatVendors',
    'licensekey',
    'client',
    'settings',
    'files',
    'filesAllFolders',
    'filesFolderSync',
    'zreading',
    'barcode',
  },
  'developer': {
    'dashboard',
    'dashboardSignals',
    'dashboardToday',
    'dashboardHeartbeat',
    'dashboardFeed',
    'dashboardTotals',
    'dashboardStatus',
    'dashboardDistribution',
    'dashboardTrends',
    'dashboardThroughput',
    'ticket',
    'chat',
    'chatCustomers',
    'chatVendors',
    'posversion',
    'releasenotes',
    'licensekey',
    'customer',
    'client',
    'settings',
    'task',
    'credentials',
    'files',
    'filesAllFolders',
    'filesFolderSync',
    'installer',
    'zreading',
    'barcode',
  },
  'sales': {
    'dashboard',
    'dashboardSignals',
    'dashboardToday',
    'dashboardHeartbeat',
    'dashboardFeed',
    'dashboardTotals',
    'dashboardStatus',
    'dashboardDistribution',
    'dashboardTrends',
    'dashboardThroughput',
    'ticket',
    'chat',
    'chatCustomers',
    'chatVendors',
    'blogposts',
    'customer',
    'client',
    'clientOffer',
    'emails',
    'settings',
    'helpPage',
    'files',
    'filesAllFolders',
    'filesFolderSync',
  },
  'ojt': {'helpPage', 'barcode', 'files', 'filesShareOjt'},
};

const Set<String> _kAdminOff = {'activitylogs', 'filesShareOjt'};

bool hasFactoryRolePreset(String role) => _kRoleDefaultOn.containsKey(role);

Map<String, bool> factoryRolePreset(String role) {
  final on = _kRoleDefaultOn[role];
  if (on == null) {
    return {for (final k in kUserPermissionKeys) k: false};
  }
  if (identical(on, _allOn)) {
    return {for (final k in kUserPermissionKeys) k: !_kAdminOff.contains(k)};
  }
  return {for (final k in kUserPermissionKeys) k: on.contains(k)};
}

Map<String, bool> defaultPermissionsForRole(
  String role, [
  Map<String, Map<String, bool>>? serverDefaults,
]) {
  final server = serverDefaults?[role];
  if (server != null && server.isNotEmpty) {
    return normalizePermissions({
      for (final k in kUserPermissionKeys) k: server[k] ?? false,
    });
  }
  final on = _kRoleDefaultOn[role] ?? _kRoleDefaultOn['user']!;
  if (identical(on, _allOn)) {
    return {for (final k in kUserPermissionKeys) k: !_kAdminOff.contains(k)};
  }
  return {for (final k in kUserPermissionKeys) k: on.contains(k)};
}

void applyPermissionChange(
  Map<String, bool> perms,
  PermissionDef d,
  bool value, {
  String role = '',
}) {
  bool on(String k) => perms[k] ?? false;
  perms[d.key] = value;
  if (value && d.exclusiveWith != null) perms[d.exclusiveWith!] = false;
  final kids = childPermissionsOf(d.key);
  if (value && kids.isNotEmpty && !kids.any((k) => on(k.key))) {
    if (d.key == 'files') {
      if (role == 'ojt') {
        perms['filesShareOjt'] = true;
      } else {
        perms['filesAllFolders'] = true;
        perms['filesFolderSync'] = true;
      }
    } else {
      for (final k in kids) {
        if (k.key == 'messageRequests' || k.key == 'dashboardRevenue') continue;
        perms[k.key] = true;
      }
    }
  }
  if (!value &&
      d.parent == 'files' &&
      !on('filesAllFolders') &&
      !on('filesShareOjt')) {
    perms['files'] = false;
    perms['filesFolderSync'] = false;
  }
}

Map<String, bool> normalizePermissions(Map<String, bool> input) {
  final p = {for (final k in kUserPermissionKeys) k: input[k] ?? false};
  for (final d in kPermissionDefs) {
    if (d.parent != null && !(p[d.parent!] ?? false)) p[d.key] = false;
  }
  var all = p['filesAllFolders'] ?? false;
  var shared = p['filesShareOjt'] ?? false;
  if (shared) all = false;
  if (!all && !shared) {
    p['files'] = false;
  } else if (!(p['files'] ?? false)) {
    all = false;
    shared = false;
  }
  p['filesAllFolders'] = all;
  p['filesShareOjt'] = shared;
  if (!(p['files'] ?? false)) p['filesFolderSync'] = false;
  return p;
}

Map<String, Map<String, bool>> parseRoleDefaults(Object? raw) {
  final out = <String, Map<String, bool>>{};
  if (raw is! Map) return out;
  raw.forEach((role, perms) {
    if (perms is Map) {
      out[role.toString()] = {
        for (final e in perms.entries) e.key.toString(): _asBool(e.value),
      };
    }
  });
  return out;
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
    this.branchId = 0,
  });

  final int id;
  final String username;
  final String fullName;
  final String email;
  final String role;
  final bool status;
  final Map<String, bool> permissions;
  final int branchId;

  factory AdminUser.fromJson(Map<String, dynamic> json) => AdminUser(
    id: _asInt(json['id']),
    username: (json['username'] ?? '').toString(),
    fullName: (json['userfullname'] ?? json['full_name'] ?? '').toString(),
    email: (json['useremail'] ?? json['email'] ?? '').toString(),
    role: (json['role'] ?? '').toString(),
    status: _asStatus(json['status'] ?? json['account_status']),
    permissions: _parsePermissions(json['permissions']),
    branchId: _asInt(json['branch_id']),
  );
}

Map<String, bool> _parsePermissions(Object? raw) {
  final result = <String, bool>{for (final k in kUserPermissionKeys) k: false};
  final seen = <String>{};

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
      if (result.containsKey(k)) {
        result[k] = _asBool(value);
        seen.add(k);
      }
    });
  } else if (decoded is List) {
    for (final item in decoded) {
      final k = item.toString();
      if (result.containsKey(k)) {
        result[k] = true;
        seen.add(k);
      }
    }
  }
  for (final d in kPermissionDefs) {
    if (d.inheritWhenMissing && d.parent != null && !seen.contains(d.key)) {
      result[d.key] = result[d.parent!] ?? false;
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
