class AdminPermDef {
  const AdminPermDef(
    this.key,
    this.label,
    this.icon,
    this.cat, {
    this.parent,
    this.hint,
    this.inheritWhenMissing = false,
    this.childrenDefaultAll = false,
    this.exclusiveWith,
  });
  final String key;
  final String label;
  final String icon;
  final String cat;
  final String? parent;
  final String? hint;
  final bool inheritWhenMissing;
  final bool childrenDefaultAll;
  final String? exclusiveWith;
}

const kAdminPermCategories = [
  'Core Suite',
  'Operations & POS',
  'CRM & Clients',
  'Admin & System',
];

const kAdminPermDefs = <AdminPermDef>[
  AdminPermDef(
    'dashboard',
    'Dashboard',
    'fas fa-th-large',
    'Core Suite',
    childrenDefaultAll: true,
  ),
  AdminPermDef(
    'dashboardSignals',
    'Signal Chips',
    'fas fa-bolt',
    'Core Suite',
    parent: 'dashboard',
    hint: 'Open tickets, unassigned, chats waiting',
    inheritWhenMissing: true,
  ),
  AdminPermDef(
    'dashboardToday',
    'Today',
    'fas fa-sun',
    'Core Suite',
    parent: 'dashboard',
    hint: 'Counters since midnight',
    inheritWhenMissing: true,
  ),
  AdminPermDef(
    'dashboardHeartbeat',
    'Activity Heartbeat',
    'fas fa-wave-square',
    'Core Suite',
    parent: 'dashboard',
    hint: 'Streaming 24-hour activity chart',
    inheritWhenMissing: true,
  ),
  AdminPermDef(
    'dashboardFeed',
    'Activity Stream',
    'fas fa-satellite-dish',
    'Core Suite',
    parent: 'dashboard',
    hint: 'Live feed of staff activity',
    inheritWhenMissing: true,
  ),
  AdminPermDef(
    'dashboardTotals',
    'Totals',
    'fas fa-layer-group',
    'Core Suite',
    parent: 'dashboard',
    hint: 'Stat cards with 14-day trend',
    inheritWhenMissing: true,
  ),
  AdminPermDef(
    'dashboardRevenue',
    'License Revenue',
    'fas fa-coins',
    'Core Suite',
    parent: 'dashboard',
    hint: 'Vendor licence payment figures (admins only)',
  ),
  AdminPermDef(
    'dashboardStatus',
    'Status Overview',
    'fas fa-chart-pie',
    'Core Suite',
    parent: 'dashboard',
    hint: 'Doughnut charts for health signals',
    inheritWhenMissing: true,
  ),
  AdminPermDef(
    'dashboardDistribution',
    'Distribution',
    'fas fa-map-marked-alt',
    'Core Suite',
    parent: 'dashboard',
    hint: 'Market and geography charts',
    inheritWhenMissing: true,
  ),
  AdminPermDef(
    'dashboardTrends',
    'Activity Trends',
    'fas fa-chart-line',
    'Core Suite',
    parent: 'dashboard',
    hint: 'Ticket priority and 6-month trend',
    inheritWhenMissing: true,
  ),
  AdminPermDef(
    'dashboardThroughput',
    'Throughput',
    'fas fa-tachometer-alt',
    'Core Suite',
    parent: 'dashboard',
    hint: 'Emails, files and barcodes over 6 months',
    inheritWhenMissing: true,
  ),
  AdminPermDef('ticket', 'Ticket Support', 'fas fa-ticket-alt', 'Core Suite'),
  AdminPermDef('chat', 'Chat Messaging', 'fas fa-comments', 'Core Suite'),
  AdminPermDef(
    'chatCustomers',
    'Customer Chats',
    'fas fa-user-tag',
    'Core Suite',
    parent: 'chat',
    hint: 'Customer, guest and Facebook conversations',
  ),
  AdminPermDef(
    'chatVendors',
    'Vendor Chats',
    'fas fa-store',
    'Core Suite',
    parent: 'chat',
    hint: 'Conversations opened from the vendor portal',
  ),
  AdminPermDef(
    'messageRequests',
    'Facebook Chats',
    'fab fa-facebook-messenger',
    'Core Suite',
    parent: 'chat',
    hint: 'Handles the Facebook Chats queue',
  ),
  AdminPermDef('task', 'Tasks Matrix', 'fas fa-tasks', 'Core Suite'),
  AdminPermDef(
    'posversion',
    'POS Versions',
    'fas fa-cash-register',
    'Operations & POS',
  ),
  AdminPermDef(
    'releasenotes',
    'Release Notes',
    'fas fa-clipboard-list',
    'Operations & POS',
  ),
  AdminPermDef('licensekey', 'License Keys', 'fas fa-key', 'Operations & POS'),
  AdminPermDef(
    'zreading',
    'Z-Reading Requests',
    'fas fa-receipt',
    'Operations & POS',
  ),
  AdminPermDef(
    'installer',
    'Installer Suite',
    'fas fa-download',
    'Operations & POS',
  ),
  AdminPermDef(
    'customer',
    'BIR Registration',
    'fas fa-file-invoice',
    'CRM & Clients',
  ),
  AdminPermDef(
    'clientOffer',
    'Leads & Forms',
    'fas fa-user-plus',
    'CRM & Clients',
  ),
  AdminPermDef(
    'taxpayerPortal',
    'Taxpayer Portal Access',
    'fas fa-user-shield',
    'CRM & Clients',
    hint: "Open any taxpayer's portal (view only) without their password",
  ),
  AdminPermDef(
    'vendorPortal',
    'Vendor Portal Access',
    'fas fa-store',
    'CRM & Clients',
    hint:
        'View every vendor account, their clients, license keys and activity (view only)',
  ),
  AdminPermDef(
    'client',
    'Client Directory',
    'fas fa-building',
    'CRM & Clients',
  ),
  AdminPermDef(
    'credentials',
    'Credentials Vault',
    'fas fa-shield-alt',
    'CRM & Clients',
  ),
  AdminPermDef('blogposts', 'Blog Posts', 'fas fa-blog', 'CRM & Clients'),
  AdminPermDef('user', 'User Control', 'fas fa-users-cog', 'Admin & System'),
  AdminPermDef(
    'employmentInfo',
    'Employment Info',
    'far fa-address-card',
    'Admin & System',
    parent: 'user',
    hint: 'Review and manage employment information sheets',
  ),
  AdminPermDef(
    'disabledAccounts',
    'Disabled Accounts',
    'fas fa-user-slash',
    'Admin & System',
  ),
  AdminPermDef('emails', 'Email Center', 'fas fa-envelope', 'Admin & System'),
  AdminPermDef(
    'activitylogs',
    'Activity Logs',
    'fas fa-history',
    'Admin & System',
  ),
  AdminPermDef('settings', 'System Settings', 'fas fa-cog', 'Admin & System'),
  AdminPermDef(
    'analyze',
    'Data Analytics',
    'fas fa-chart-line',
    'Admin & System',
  ),
  AdminPermDef(
    'files',
    'Files Management',
    'fas fa-folder-open',
    'Admin & System',
  ),
  AdminPermDef(
    'filesAllFolders',
    'All Folders',
    'fas fa-folder-tree',
    'Admin & System',
    parent: 'files',
    hint: 'Sees every folder',
    exclusiveWith: 'filesShareOjt',
  ),
  AdminPermDef(
    'filesShareOjt',
    'OJT File Management',
    'fas fa-user-graduate',
    'Admin & System',
    parent: 'files',
    hint: 'Sees only folders shared with OJT',
    exclusiveWith: 'filesAllFolders',
  ),
  AdminPermDef(
    'filesFolderSync',
    'Folder Sync',
    'fas fa-sync-alt',
    'Admin & System',
    parent: 'files',
    hint: 'Opens their own Folder Sync workspace',
    inheritWhenMissing: true,
  ),
  AdminPermDef(
    'helpPage',
    'Help Center',
    'fas fa-question-circle',
    'Admin & System',
  ),
];

List<AdminPermDef> get kAdminModuleDefs =>
    kAdminPermDefs.where((p) => p.parent == null).toList();

Map<String, dynamic> adminHydratePerms(Map<String, dynamic> perms) {
  for (final p in kAdminPermDefs) {
    if (p.parent == null || !p.inheritWhenMissing) continue;
    if (!perms.containsKey(p.key)) {
      perms[p.key] = adminPermOn(perms[p.parent]) ? 1 : 0;
    }
  }
  return perms;
}

bool adminPermOn(dynamic v) => v == 1 || v == true || v == '1';

List<AdminPermDef> adminChildPerms(String key) =>
    kAdminPermDefs.where((p) => p.parent == key).toList();

AdminPermDef? adminPermDef(String key) {
  for (final p in kAdminPermDefs) {
    if (p.key == key) return p;
  }
  return null;
}
