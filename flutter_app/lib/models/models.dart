/// Tiny data-class layer. Backend returns flat JSON; these structs only need
/// enough shape for list/detail rendering. When the wire format changes,
/// update just the factories.

class UserSession {
  UserSession({
    required this.userId,
    required this.username,
    required this.role,
  });

  final int userId;
  final String username;
  final String role;

  factory UserSession.fromJson(Map<String, dynamic> json) => UserSession(
        userId: _asInt(json['userID'] ?? json['user_id']),
        username: (json['username'] ?? json['user_name'] ?? '—').toString(),
        role: (json['userRole'] ?? json['user_role'] ?? 'user').toString(),
      );
}

/// Maps 1:1 to `getMobileDashboardSummary` response.
/// Backend returns:
///   { success, stats: [{label, value, icon}, ...], charts: {...} }
class DashboardSummary {
  DashboardSummary({
    required this.stats,
    required this.recentActivity,
  });

  final List<MetricStat> stats;
  final List<ActivityItem> recentActivity;

  int byLabel(String needle, {int fallback = 0}) {
    for (final s in stats) {
      if (s.label.toLowerCase() == needle.toLowerCase()) return s.value;
    }
    return fallback;
  }

  factory DashboardSummary.fromJson(
    Map<String, dynamic> summary,
    Map<String, dynamic> notifications,
  ) {
    final rawStats =
        (summary['stats'] is List) ? summary['stats'] as List : const [];
    final rawItems =
        (notifications['items'] is List) ? notifications['items'] as List : const [];
    return DashboardSummary(
      stats: rawStats
          .whereType<Map>()
          .map((e) => MetricStat.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      recentActivity: rawItems
          .whereType<Map>()
          .map((e) => ActivityItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  static DashboardSummary empty() =>
      DashboardSummary(stats: const [], recentActivity: const []);
}

class MetricStat {
  MetricStat({required this.label, required this.value, required this.icon});
  final String label;
  final int value;
  final String icon;

  factory MetricStat.fromJson(Map<String, dynamic> json) => MetricStat(
        label: (json['label'] ?? '—').toString(),
        value: _asInt(json['value']),
        icon: (json['icon'] ?? '').toString(),
      );
}

/// Matches `getMobileNotificationSummary` item shape:
///   {id, type: 'customer'|'lead', title, subtitle}
class ActivityItem {
  ActivityItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.type,
  });
  final int id;
  final String title;
  final String subtitle;
  final String type;

  factory ActivityItem.fromJson(Map<String, dynamic> json) => ActivityItem(
        id: _asInt(json['id']),
        title: (json['title'] ?? '—').toString(),
        subtitle: (json['subtitle'] ?? '').toString(),
        type: (json['type'] ?? 'activity').toString(),
      );
}

/// Row shape from `getcustomer` → `data[i]`. Backend returns every `customer`
/// column; we snapshot the ones that appear in lists.
class CustomerBrief {
  CustomerBrief({
    required this.id,
    required this.companyName,
    required this.tin,
    required this.branchCode,
    required this.ownerName,
    required this.address,
    required this.status,
  });

  final int id;
  final String companyName;
  final String tin;
  final String branchCode;
  final String ownerName;
  final String address;
  final String status; // 'Processed' | 'Submitted'

  factory CustomerBrief.fromJson(Map<String, dynamic> json) {
    final owner = [
      json['first_name'] ?? '',
      json['middle_name'] ?? '',
      json['last_name'] ?? '',
    ].map((e) => e.toString().trim()).where((e) => e.isNotEmpty).join(' ');
    return CustomerBrief(
      id: _asInt(json['id']),
      companyName: (json['company_name'] ?? '—').toString(),
      tin: (json['tin'] ?? '').toString(),
      branchCode: (json['branch_code'] ?? '').toString(),
      ownerName: owner,
      address: (json['address'] ?? '').toString(),
      status: _asInt(json['c_status']) == 1 ? 'Processed' : 'Submitted',
    );
  }
}

/// Row shape from the bare `getleads` array. Columns match `leads` table.
class LeadBrief {
  LeadBrief({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.location,
    required this.businessType,
    required this.selectedPackage,
    required this.note,
    required this.createdAt,
  });

  final int id;
  final String name;
  final String email;
  final String phone;
  final String location;
  final String businessType;
  final String selectedPackage;
  final String note;
  final String createdAt;

  factory LeadBrief.fromJson(Map<String, dynamic> json) => LeadBrief(
        id: _asInt(json['id']),
        name: (json['name'] ?? '—').toString(),
        email: (json['email'] ?? '').toString(),
        phone: (json['phone'] ?? '').toString(),
        location: (json['location'] ?? '').toString(),
        businessType: (json['businessType'] ?? json['customBusinessType'] ?? '')
            .toString(),
        selectedPackage: (json['selectedPackage'] ?? '').toString(),
        // Backend column is `notes` (plural). Tolerate both.
        note: (json['notes'] ?? json['note'] ?? '').toString(),
        createdAt: (json['created_at'] ?? '').toString(),
      );
}

/// Row shape from `get_tickets`. Matches `tickets` table + joined `agent_name`.
class TicketBrief {
  TicketBrief({
    required this.id,
    required this.subject,
    required this.description,
    required this.customerName,
    required this.customerEmail,
    required this.status,
    required this.priority,
    required this.agentName,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String subject;
  final String description;
  final String customerName;
  final String customerEmail;
  final String status; // new | assigned | in_progress | resolved | closed
  final String priority; // low | medium | high
  final String agentName;
  final String createdAt;
  final String updatedAt;

  bool get isUnresolved =>
      status != 'resolved' && status != 'closed';

  factory TicketBrief.fromJson(Map<String, dynamic> json) => TicketBrief(
        id: _asInt(json['id']),
        subject: (json['subject'] ?? '—').toString(),
        description: (json['description'] ?? '').toString(),
        customerName: (json['customer_name'] ?? '').toString(),
        customerEmail: (json['customer_email'] ?? '').toString(),
        status: (json['status'] ?? 'new').toString(),
        priority: (json['priority'] ?? 'medium').toString(),
        agentName: (json['agent_name'] ?? '').toString(),
        createdAt: (json['created_at'] ?? '').toString(),
        updatedAt: (json['updated_at'] ?? '').toString(),
      );
}

int _asInt(Object? value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}
