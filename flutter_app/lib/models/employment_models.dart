const List<String> kMaritalStatuses = [
  'Single',
  'Married',
  'Widowed',
  'Annulled',
  'Separated',
];

const List<String> kSpouselessStatuses = [
  'Single',
  'Widowed',
  'Annulled',
  'Separated',
];

const int kMinEmergencyContacts = 1;
const int kMaxEmergencyContacts = 6;
const int kMaxDependents = 12;

const String kEmploymentMailSubject =
    'Please complete your Employment Information Sheet';
const String kEmploymentMailMessage =
    'Please complete your Basic Employment Information Sheet. '
    'It takes a few minutes, and everything you enter is kept confidential.';

int _int(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is bool) return v ? 1 : 0;
  return int.tryParse('${v ?? ''}'.trim()) ?? 0;
}

String _str(dynamic v) => v == null ? '' : v.toString();

String employmentStatusLabel(String status) {
  switch (status) {
    case 'submitted':
      return 'Awaiting review';
    case 'reviewed':
      return 'Reviewed';
    case 'archived':
      return 'Archived';
    default:
      return status;
  }
}

class EmploymentSummary {
  const EmploymentSummary({
    this.total = 0,
    this.submitted = 0,
    this.reviewed = 0,
    this.today = 0,
    this.activeLinks = 0,
  });

  final int total;
  final int submitted;
  final int reviewed;
  final int today;
  final int activeLinks;

  int get archived {
    final rest = total - submitted - reviewed;
    return rest < 0 ? 0 : rest;
  }

  factory EmploymentSummary.fromJson(Map<String, dynamic> json) =>
      EmploymentSummary(
        total: _int(json['total']),
        submitted: _int(json['submitted']),
        reviewed: _int(json['reviewed']),
        today: _int(json['today']),
        activeLinks: _int(json['active_links']),
      );
}

class EmploymentPulse {
  const EmploymentPulse({
    required this.total,
    required this.latestId,
    required this.stamp,
  });

  final int total;
  final int latestId;
  final int stamp;

  String get key => '$latestId:$total:$stamp';

  factory EmploymentPulse.fromJson(Map<String, dynamic> json) =>
      EmploymentPulse(
        total: _int(json['total']),
        latestId: _int(json['latest_id']),
        stamp: _int(json['stamp']),
      );
}

class EmploymentRecordBrief {
  const EmploymentRecordBrief({
    required this.id,
    required this.fullName,
    required this.email,
    required this.cellPhone,
    required this.jobTitle,
    required this.workLocation,
    required this.maritalStatus,
    required this.startDate,
    required this.status,
    required this.createdAt,
    required this.linkLabel,
    required this.staffUserId,
    required this.staffName,
    required this.staffRole,
    required this.staffLinkSkipped,
    required this.dependentCount,
  });

  final int id;
  final String fullName;
  final String email;
  final String cellPhone;
  final String jobTitle;
  final String workLocation;
  final String maritalStatus;
  final String startDate;
  final String status;
  final String createdAt;
  final String linkLabel;
  final int staffUserId;
  final String staffName;
  final String staffRole;
  final bool staffLinkSkipped;
  final int dependentCount;

  bool get isStaffLinked => staffName.trim().isNotEmpty || staffLinkSkipped;

  factory EmploymentRecordBrief.fromJson(Map<String, dynamic> json) =>
      EmploymentRecordBrief(
        id: _int(json['id']),
        fullName: _str(json['full_name']),
        email: _str(json['email']),
        cellPhone: _str(json['cell_phone']),
        jobTitle: _str(json['job_title']),
        workLocation: _str(json['work_location']),
        maritalStatus: _str(json['marital_status']),
        startDate: _str(json['start_date']),
        status: _str(json['status']),
        createdAt: _str(json['created_at']),
        linkLabel: _str(json['link_label']),
        staffUserId: _int(json['staff_user_id']),
        staffName: _str(json['staff_name']),
        staffRole: _str(json['staff_role']),
        staffLinkSkipped: _int(json['staff_link_skipped']) == 1,
        dependentCount: _int(json['dependent_count']),
      );
}

class EmploymentRecordPage {
  const EmploymentRecordPage({
    required this.records,
    required this.total,
    required this.summary,
  });

  final List<EmploymentRecordBrief> records;
  final int total;
  final EmploymentSummary summary;
}

class EmergencyContact {
  EmergencyContact({
    this.fullName = '',
    this.address = '',
    this.primaryPhone = '',
    this.cellPhone = '',
    this.relationship = '',
  });

  String fullName;
  String address;
  String primaryPhone;
  String cellPhone;
  String relationship;

  factory EmergencyContact.fromJson(Map<String, dynamic> json) =>
      EmergencyContact(
        fullName: _str(json['full_name']),
        address: _str(json['address']),
        primaryPhone: _str(json['primary_phone']),
        cellPhone: _str(json['cell_phone']),
        relationship: _str(json['relationship']),
      );

  Map<String, String> toJson() => {
    'full_name': fullName.trim(),
    'address': address.trim(),
    'primary_phone': primaryPhone.trim(),
    'cell_phone': cellPhone.trim(),
    'relationship': relationship.trim(),
  };
}

class EmploymentDependent {
  EmploymentDependent({this.name = '', this.relationship = ''});

  String name;
  String relationship;

  factory EmploymentDependent.fromJson(Map<String, dynamic> json) =>
      EmploymentDependent(
        name: _str(json['dependent_name'] ?? json['name']),
        relationship: _str(json['relationship']),
      );

  Map<String, String> toJson() => {
    'dependent_name': name.trim(),
    'relationship': relationship.trim(),
  };
}

class EmploymentRecord {
  EmploymentRecord({required this.id, required this.raw});

  final int id;
  final Map<String, dynamic> raw;

  String field(String key) => _str(raw[key]);

  String get fullName => field('full_name');
  String get status => field('status');
  String get maritalStatus => field('marital_status');
  String get createdAt => field('created_at');
  String get linkLabel => field('link_label');
  String get staffName => field('staff_name');
  String get reviewedByName => field('reviewed_by_name');
  int get staffUserId => _int(raw['staff_user_id']);
  bool get staffLinkSkipped => _int(raw['staff_link_skipped']) == 1;
  bool get hasNoDependents => _int(raw['has_no_dependents']) == 1;
  bool get isMarried => maritalStatus == 'Married';
  bool get isStaffLinked => staffName.trim().isNotEmpty || staffLinkSkipped;

  List<EmergencyContact> get emergencyContacts {
    final list = raw['emergency_contacts'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => EmergencyContact.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  List<EmploymentDependent> get dependents {
    final list = raw['dependents'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => EmploymentDependent.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  EmploymentRecord copyWith(Map<String, dynamic> changes) =>
      EmploymentRecord(id: id, raw: {...raw, ...changes});

  factory EmploymentRecord.fromJson(Map<String, dynamic> json) =>
      EmploymentRecord(id: _int(json['id']), raw: json);
}

class EmploymentLink {
  const EmploymentLink({
    required this.id,
    required this.label,
    required this.userId,
    required this.note,
    required this.sentTo,
    required this.sentAt,
    required this.isReusable,
    required this.useCount,
    required this.isRevoked,
    required this.expiresAt,
    required this.lastUsedAt,
    required this.createdAt,
    required this.userRole,
    required this.createdByName,
    required this.isActive,
    required this.url,
  });

  final int id;
  final String label;
  final int userId;
  final String note;
  final String sentTo;
  final String sentAt;
  final bool isReusable;
  final int useCount;
  final bool isRevoked;
  final String expiresAt;
  final String lastUsedAt;
  final String createdAt;
  final String userRole;
  final String createdByName;
  final bool isActive;
  final String url;

  bool get isUsed => !isReusable && useCount > 0;

  bool get isConsumed => !isActive && !isReusable && !isRevoked && useCount > 0;

  String get statusLabel {
    if (isActive) return 'Active';
    if (isRevoked) return 'Revoked';
    if (isUsed) return 'Used';
    return 'Expired';
  }

  factory EmploymentLink.fromJson(Map<String, dynamic> json) => EmploymentLink(
    id: _int(json['id']),
    label: _str(json['label']),
    userId: _int(json['user_id']),
    note: _str(json['note']),
    sentTo: _str(json['sent_to']),
    sentAt: _str(json['sent_at']),
    isReusable: _int(json['is_reusable']) == 1,
    useCount: _int(json['use_count']),
    isRevoked: _int(json['is_revoked']) == 1,
    expiresAt: _str(json['expires_at']),
    lastUsedAt: _str(json['last_used_at']),
    createdAt: _str(json['created_at']),
    userRole: _str(json['user_role']),
    createdByName: _str(json['created_by_name']),
    isActive: _int(json['is_active']) == 1,
    url: _str(json['url']),
  );
}

class EmploymentStaff {
  const EmploymentStaff({
    required this.id,
    required this.name,
    required this.username,
    required this.email,
    required this.role,
    required this.openLinks,
    required this.sheetCount,
  });

  final int id;
  final String name;
  final String username;
  final String email;
  final String role;
  final int openLinks;
  final int sheetCount;

  factory EmploymentStaff.fromJson(Map<String, dynamic> json) =>
      EmploymentStaff(
        id: _int(json['id']),
        name: _str(json['name']),
        username: _str(json['username']),
        email: _str(json['email']),
        role: _str(json['role']),
        openLinks: _int(json['open_links']),
        sheetCount: _int(json['sheet_count']),
      );
}

class EmploymentStaffList {
  const EmploymentStaffList({required this.users, this.message});

  final List<EmploymentStaff> users;
  final String? message;
}

class EmploymentResult {
  const EmploymentResult({
    required this.ok,
    this.message,
    this.errors = const {},
    this.data = const {},
  });

  final bool ok;
  final String? message;
  final Map<String, String> errors;
  final Map<String, dynamic> data;

  factory EmploymentResult.fromJson(Map<String, dynamic> json) {
    final rawErrors = json['errors'];
    final errors = <String, String>{};
    if (rawErrors is Map) {
      rawErrors.forEach((k, v) => errors[k.toString()] = v.toString());
    }
    final msg = json['message']?.toString().trim();
    return EmploymentResult(
      ok: json['status'] == 'success',
      message: msg == null || msg.isEmpty ? null : msg,
      errors: errors,
      data: json,
    );
  }

  factory EmploymentResult.failure(String message) =>
      EmploymentResult(ok: false, message: message);
}

const List<String> _kMonthsShort = [
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

const List<String> _kMonthsLong = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

DateTime? parseEmploymentDate(String value) {
  final v = value.trim();
  if (v.isEmpty || v.startsWith('0000-00-00')) return null;
  return DateTime.tryParse(v.replaceFirst(' ', 'T'));
}

String employmentDate(String value) {
  final d = parseEmploymentDate(value);
  if (d == null) return value.trim().isEmpty ? '—' : value;
  return '${_kMonthsShort[d.month - 1]} ${d.day}, ${d.year}';
}

String employmentLongDate(DateTime d) =>
    '${_kMonthsLong[d.month - 1]} ${d.day}, ${d.year}';

String employmentDateTime(String value) {
  final d = parseEmploymentDate(value);
  if (d == null) return value.trim().isEmpty ? '—' : value;
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  final ap = d.hour < 12 ? 'AM' : 'PM';
  return '${_kMonthsShort[d.month - 1]} ${d.day}, ${d.year}, '
      '${h.toString().padLeft(2, '0')}:$m $ap';
}

String employmentIsoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
