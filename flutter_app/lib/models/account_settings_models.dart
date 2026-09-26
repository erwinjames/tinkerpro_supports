class SelfSettings {
  const SelfSettings({
    required this.fullName,
    required this.email,
    required this.emailVerified,
    required this.username,
    required this.role,
    required this.mfaEnabled,
    required this.chatAlias,
  });

  final String fullName;
  final String email;
  final bool emailVerified;
  final String username;
  final String role;
  final bool mfaEnabled;
  final String chatAlias;

  factory SelfSettings.fromJson(Map<String, dynamic> json) => SelfSettings(
    fullName: (json['full_name'] ?? '').toString(),
    email: (json['email'] ?? '').toString(),
    emailVerified: settingsFlag(json['email_verified']),
    username: (json['username'] ?? '').toString(),
    role: (json['role'] ?? '').toString(),
    mfaEnabled: settingsFlag(json['mfa_enabled']),
    chatAlias: (json['chat_alias'] ?? '').toString(),
  );
}

class AgentHours {
  const AgentHours({
    required this.enabled,
    required this.start,
    required this.end,
    required this.timezone,
  });

  final bool enabled;
  final String start;
  final String end;
  final String timezone;
}

class TicketReminder {
  const TicketReminder({required this.enabled, required this.days});

  final bool enabled;
  final int days;
}

class PosApiKey {
  const PosApiKey({
    required this.id,
    required this.label,
    required this.masked,
    required this.createdAt,
    required this.lastUsedAt,
    required this.lastUsedIp,
    required this.requestCount,
    required this.revokedAt,
    required this.active,
  });

  final int id;
  final String label;
  final String masked;
  final String createdAt;
  final String lastUsedAt;
  final String lastUsedIp;
  final int requestCount;
  final String revokedAt;
  final bool active;

  factory PosApiKey.fromJson(Map<String, dynamic> json) => PosApiKey(
    id: settingsInt(json['id']),
    label: (json['label'] ?? '').toString(),
    masked: (json['masked'] ?? '').toString(),
    createdAt: (json['created_at'] ?? '').toString(),
    lastUsedAt: (json['last_used_at'] ?? '').toString(),
    lastUsedIp: (json['last_used_ip'] ?? '').toString(),
    requestCount: settingsInt(json['request_count']),
    revokedAt: (json['revoked_at'] ?? '').toString(),
    active: json['active'] == true || json['active'] == 1,
  );
}

class ReminderOption {
  const ReminderOption({required this.id, required this.name});

  final int id;
  final String name;
}

class GlobalReminder {
  const GlobalReminder({
    required this.mode,
    required this.sourceUserId,
    required this.users,
  });

  final String mode;
  final int sourceUserId;
  final List<ReminderOption> users;
}

class SidebarItem {
  const SidebarItem(this.key, this.label);

  final String key;
  final String label;
}

class SidebarCategory {
  const SidebarCategory(this.title, this.items);

  final String title;
  final List<SidebarItem> items;
}

const List<SidebarCategory> kSidebarCategories = [
  SidebarCategory('Overview & Support', [
    SidebarItem('whatsnew', "What's New"),
    SidebarItem('dashboard', 'Dashboard'),
    SidebarItem('ticket', 'Ticket'),
    SidebarItem('chat', 'Chat'),
  ]),
  SidebarCategory('Product Suite', [
    SidebarItem('posversion', 'POS Version'),
    SidebarItem('releasenotes', 'Release Notes'),
    SidebarItem('licensekey', 'License Key'),
    SidebarItem('blogposts', 'Blog Posts'),
  ]),
  SidebarCategory('Clients & Accounts', [
    SidebarItem('customer', 'BIR Registration'),
    SidebarItem('clientOffer', 'Leads / Forms'),
    SidebarItem('client', 'Client Directory'),
    SidebarItem('zreading', 'Z-Reading Request'),
    SidebarItem('credentials', 'Credentials Storage'),
  ]),
  SidebarCategory('Workspace Modules', [
    SidebarItem('user', 'User Management'),
    SidebarItem('employment', 'Employment Info'),
    SidebarItem('offers', 'Offers'),
    SidebarItem('pricing', 'Pricing'),
    SidebarItem('emails', 'Email'),
    SidebarItem('files', 'Files Management'),
    SidebarItem('task', 'Task'),
    SidebarItem('activitylogs', 'Activity Logs'),
  ]),
  SidebarCategory('System Tools', [
    SidebarItem('helpPage', 'Help Page'),
    SidebarItem('barcode', 'Barcode'),
    SidebarItem('settings', 'Settings'),
    SidebarItem('feedback', 'Feedback Button'),
    SidebarItem('feedbackinbox', 'Feedback Inbox'),
    SidebarItem('announcements', 'Announcements'),
  ]),
];

class SettingsResult {
  const SettingsResult({required this.ok, this.message, this.data});

  final bool ok;
  final String? message;
  final Map<String, dynamic>? data;
}

bool settingsFlag(Object? v) => v == true || v == 1 || v == '1' || v == 'true';

int settingsInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}
