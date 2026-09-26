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

class DashboardSummary {
  DashboardSummary({required this.stats, required this.recentActivity});

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
    final rawStats = (summary['stats'] is List)
        ? summary['stats'] as List
        : const [];
    final rawItems = (notifications['items'] is List)
        ? notifications['items'] as List
        : const [];
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

const String kCustomerStatusCompleted = 'Completed';
const String kCustomerStatusUploadPtu = 'Upload PTU';
const String kCustomerStatusContinue = 'Continue Registration';
const String kCustomerStatusPending = 'Pending Registration';

const List<String> kCustomerStatuses = [
  kCustomerStatusCompleted,
  kCustomerStatusUploadPtu,
  kCustomerStatusContinue,
  kCustomerStatusPending,
];

String customerStatusLabel(int cStatus, int step2, int finalStep) {
  if (finalStep == 1) return kCustomerStatusCompleted;
  if (cStatus == 1 && step2 == 1) return kCustomerStatusUploadPtu;
  if (cStatus == 0 && step2 == 0) return kCustomerStatusContinue;
  return kCustomerStatusPending;
}

class CustomerBrief {
  CustomerBrief({
    required this.id,
    required this.companyName,
    required this.tin,
    required this.branchCode,
    required this.ownerName,
    required this.address,
    required this.cStatus,
    required this.step2,
    required this.finalStep,
    required this.registrationSource,
  });

  final int id;
  final String companyName;
  final String tin;
  final String branchCode;
  final String ownerName;
  final String address;
  final int cStatus;
  final int step2;
  final int finalStep;
  final String registrationSource;

  String get status => customerStatusLabel(cStatus, step2, finalStep);

  bool get fromClientPortal =>
      registrationSource.trim().toLowerCase() == 'client';

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
      cStatus: _asInt(json['c_status']),
      step2: _asInt(json['step2']),
      finalStep: _asInt(json['final_step']),
      registrationSource: (json['registration_source'] ?? '').toString(),
    );
  }
}

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
    note: (json['notes'] ?? json['note'] ?? '').toString(),
    createdAt: (json['created_at'] ?? '').toString(),
  );
}

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
  final String status;
  final String priority;
  final String agentName;
  final String createdAt;
  final String updatedAt;

  bool get isUnresolved => status != 'resolved' && status != 'closed';

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

class SerialEntry {
  SerialEntry({
    required this.serialNumberType,
    required this.serverType,
    required this.serialNumber,
    required this.brand,
    required this.model,
  });

  final String serialNumberType;
  final String serverType;
  final String serialNumber;
  final String brand;
  final String model;

  factory SerialEntry.fromJson(Map<String, dynamic> json) => SerialEntry(
    serialNumberType: (json['serial_number_type'] ?? '').toString(),
    serverType: (json['server_type'] ?? '').toString(),
    serialNumber: (json['serial_number'] ?? '').toString(),
    brand: (json['brand'] ?? '').toString(),
    model: (json['model'] ?? '').toString(),
  );

  Map<String, dynamic> toJson() => {
    'serial_number_type': serialNumberType,
    'server_type': serverType,
    'serial_number': serialNumber,
    'brand': brand,
    'model': model,
  };
}

class CustomerDocument {
  CustomerDocument({
    required this.id,
    required this.docType,
    required this.originalFilename,
    required this.storedFilename,
    required this.mimeType,
    required this.fileSize,
  });

  final int id;
  final String docType;
  final String originalFilename;
  final String storedFilename;
  final String mimeType;
  final int fileSize;

  factory CustomerDocument.fromJson(Map<String, dynamic> json) =>
      CustomerDocument(
        id: _asInt(json['id']),
        docType: (json['doc_type'] ?? '').toString(),
        originalFilename: (json['original_filename'] ?? '').toString(),
        storedFilename: (json['stored_filename'] ?? '').toString(),
        mimeType: (json['mime_type'] ?? '').toString(),
        fileSize: _asInt(json['file_size']),
      );
}

class UploadedDoc {
  UploadedDoc({
    required this.original,
    required this.stored,
    required this.mime,
    required this.size,
    this.extracted,
  });

  final String original;
  final String stored;
  final String mime;
  final int size;

  final Map<String, dynamic>? extracted;

  factory UploadedDoc.fromStoredFile(Map<String, dynamic> json) => UploadedDoc(
    original: (json['original'] ?? '').toString(),
    stored: (json['stored'] ?? '').toString(),
    mime: (json['mime'] ?? '').toString(),
    size: _asInt(json['size']),
  );

  Map<String, dynamic> toJson() => {
    'original': original,
    'stored': stored,
    'mime': mime,
    'size': size,
    if (extracted != null) 'extracted': extracted,
  };
}

class ExtractionResult {
  ExtractionResult({
    this.error,
    this.companyName = '',
    this.tin = '',
    this.branchCode = '',
    this.tinIssuanceDate = '',
    this.address = '',
    this.businessLine = '',
    this.rdo = '',
    this.firstName = '',
    this.middleName = '',
    this.lastName = '',
    this.isVat,
    this.storedFiles = const [],
    this.idType = '',
    this.idNumber = '',
    this.idBirthdate = '',
    this.validIdDoc,
  });

  factory ExtractionResult.error(String message) =>
      ExtractionResult(error: message);

  final String? error;
  final String companyName;
  final String tin;
  final String branchCode;
  final String tinIssuanceDate;
  final String address;
  final String businessLine;
  final String rdo;
  final String firstName;
  final String middleName;
  final String lastName;
  final bool? isVat;
  final List<UploadedDoc> storedFiles;

  final String idType;
  final String idNumber;
  final String idBirthdate;
  final UploadedDoc? validIdDoc;

  bool get ok => error == null;
}

class CustomerDetail {
  CustomerDetail({
    required this.id,
    required this.companyName,
    required this.tin,
    required this.branchCode,
    required this.tinIssuanceDate,
    required this.rdo,
    required this.businessLine,
    required this.address,
    required this.min,
    required this.ptu,
    required this.posDateIssued,
    required this.invoiceNumber,
    required this.softwareName,
    required this.accNumber,
    required this.serialNumber,
    required this.firstName,
    required this.middleName,
    required this.lastName,
    required this.email,
    required this.username,
    required this.password,
    required this.isVat,
    required this.provinceCode,
    required this.provinceName,
    required this.cityCode,
    required this.cityName,
    required this.cStatus,
    this.step2 = 0,
    this.finalStep = 0,
    this.registrationSource = '',
    this.pdfFile = '',
    this.ptuFile = '',
    required this.serialEntries,
    required this.documents,
    this.createdAt = '',
  });

  final int id;
  final String companyName;
  final String tin;
  final String branchCode;
  final String tinIssuanceDate;
  final String rdo;
  final String businessLine;
  final String address;
  final String min;
  final String ptu;
  final String posDateIssued;
  final String invoiceNumber;
  final String softwareName;
  final String accNumber;
  final String serialNumber;
  final String firstName;
  final String middleName;
  final String lastName;
  final String email;
  final String username;
  final String password;
  final bool isVat;
  final String provinceCode;
  final String provinceName;
  final String cityCode;
  final String cityName;
  final int cStatus;
  final int step2;
  final int finalStep;
  final String registrationSource;
  final String pdfFile;
  final String ptuFile;
  final String createdAt;
  final List<SerialEntry> serialEntries;
  final List<CustomerDocument> documents;

  String get ownerName => [
    firstName,
    middleName,
    lastName,
  ].map((e) => e.trim()).where((e) => e.isNotEmpty).join(' ');

  String get status => customerStatusLabel(cStatus, step2, finalStep);

  bool get fromClientPortal =>
      registrationSource.trim().toLowerCase() == 'client';

  factory CustomerDetail.fromJson(Map<String, dynamic> json) {
    List<T> parseList<T>(dynamic raw, T Function(Map<String, dynamic>) f) {
      if (raw is! List) return <T>[];
      return raw
          .whereType<Map>()
          .map((e) => f(Map<String, dynamic>.from(e)))
          .toList();
    }

    return CustomerDetail(
      id: _asInt(json['id']),
      companyName: (json['company_name'] ?? '').toString(),
      tin: (json['tin'] ?? '').toString(),
      branchCode: (json['branch_code'] ?? '').toString(),
      tinIssuanceDate: _cleanDate(json['tin_issuance_date']),
      rdo: (json['rdo'] ?? '').toString(),
      businessLine: (json['business_line'] ?? '').toString(),
      address: (json['address'] ?? '').toString(),
      min: (json['min'] ?? '').toString(),
      ptu: (json['ptu'] ?? '').toString(),
      posDateIssued: _cleanDate(json['pos_date_issued']),
      invoiceNumber: (json['invoice_number'] ?? '').toString(),
      softwareName: (json['softwarename'] ?? json['software_name'] ?? '')
          .toString(),
      accNumber: (json['acc_num'] ?? json['acc_number'] ?? '').toString(),
      serialNumber: (json['serial_number'] ?? '').toString(),
      firstName: (json['first_name'] ?? '').toString(),
      middleName: (json['middle_name'] ?? '').toString(),
      lastName: (json['last_name'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      password: (json['password'] ?? '').toString(),
      isVat: _asInt(json['is_vat']) == 1,
      provinceCode: _cleanCode(json['province_code']),
      provinceName: (json['province'] ?? '').toString(),
      cityCode: _cleanCode(json['city_code']),
      cityName: (json['city'] ?? '').toString(),
      cStatus: _asInt(json['c_status']),
      step2: _asInt(json['step2']),
      finalStep: _asInt(json['final_step']),
      registrationSource: (json['registration_source'] ?? '').toString(),
      pdfFile: (json['pdf_file'] ?? '').toString(),
      ptuFile: (json['ptu_file'] ?? '').toString(),
      createdAt: (json['created_at'] ?? '').toString(),
      serialEntries: parseList(json['serial_entries'], SerialEntry.fromJson),
      documents: parseList(json['documents'], CustomerDocument.fromJson),
    );
  }
}

class Province {
  Province({required this.code, required this.name});
  final String code;
  final String name;
  factory Province.fromJson(Map<String, dynamic> json) => Province(
    code: (json['province_code'] ?? '').toString(),
    name: (json['province_name'] ?? '').toString(),
  );
}

class City {
  City({required this.code, required this.name, required this.provinceCode});
  final String code;
  final String name;
  final String provinceCode;
  factory City.fromJson(Map<String, dynamic> json) => City(
    code: (json['city_code'] ?? '').toString(),
    name: (json['city_name'] ?? '').toString(),
    provinceCode: (json['province_code'] ?? '').toString(),
  );
}

class CustomerSaveResult {
  CustomerSaveResult({
    required this.ok,
    required this.message,
    this.customerId,
  });
  final bool ok;
  final String message;
  final int? customerId;
}

String _cleanDate(Object? value) {
  final s = (value ?? '').toString().trim();
  if (s.isEmpty || s.startsWith('0000')) return '';
  return s.split(' ').first.split('T').first;
}

String _cleanCode(Object? value) {
  if (value == null) return '';
  final s = value.toString().trim();
  if (s.isEmpty || s == '0') return '';
  return s;
}

int _asInt(Object? value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}
