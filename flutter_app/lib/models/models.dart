import 'dart:convert';

/// Tiny data-class layer. Backend returns flat JSON; these structs only need
/// enough shape for list/detail rendering. When the wire format changes,
/// update just the factories.

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

  /// Feature flags mirrored from the web app's `$_SESSION['permissions']`
  /// map (e.g. `{'task': true, 'chat': true}`). Drives client-side gating
  /// of UI like the Task screen so mobile matches the sidebar on web.
  final Map<String, bool> permissions;

  bool can(String feature) => permissions[feature] == true;

  factory UserSession.fromJson(Map<String, dynamic> json) => UserSession(
        userId: _asInt(json['userID'] ?? json['user_id']),
        username: (json['username'] ?? json['user_name'] ?? '—').toString(),
        role: (json['userRole'] ?? json['user_role'] ?? 'user').toString(),
        permissions: _asPermissions(json['permissions']),
      );
}

/// Coerce the backend `permissions` payload into a `Map<String,bool>`.
/// The value may arrive as an already-decoded map, or (defensively) as a
/// JSON string. Truthy values from PHP can be `1`, `"1"`, `true` or
/// `"true"`, so normalise all of them.
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

/// One serial-number entry attached to a customer. Mirrors a
/// `customer_serial_entries` row and the JSON element the web form posts in
/// the `serial_entries` field.
class SerialEntry {
  SerialEntry({
    required this.serialNumberType,
    required this.serverType,
    required this.serialNumber,
    required this.brand,
    required this.model,
  });

  final String serialNumberType; // Server | Terminal | Standalone
  final String serverType; // Consolidator | Global (only when type == Server)
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

/// A document attached to a customer (`customer_documents` row). Read-only in
/// the app — surfaced on the detail/edit screens.
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
  final String docType; // extraction_doc | valid_id | requirement
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

/// Metadata returned by the raw upload endpoint (`client-upload-attachment.php`
/// → `stored_file`). Passed back to `addcustomer` inside the
/// `document_files` / `valid_id_files` / `requirement_files` JSON arrays.
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

  /// Optional extracted data (e.g. valid-ID fields id_type/id_name/id_number/
  /// id_birthdate) stored as `extracted_data` by the backend.
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

/// Result of running the AI/OCR extraction endpoint
/// (`client-multidoc-extract.php`) over uploaded BIR documents. Carries the
/// parsed, form-ready field values plus the stored-document metadata to hand
/// to `addcustomer`. Mirrors the prefill the web form does in customer.js.
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
  final String tin; // formatted xxx-xxx-xxx
  final String branchCode;
  final String tinIssuanceDate;
  final String address;
  final String businessLine;
  final String rdo;
  final String firstName;
  final String middleName;
  final String lastName;
  final bool? isVat; // null when undetermined
  final List<UploadedDoc> storedFiles; // extraction docs only

  // Valid ID (present when a valid ID was scanned alongside the BIR docs).
  final String idType;
  final String idNumber;
  final String idBirthdate;
  final UploadedDoc? validIdDoc;

  bool get ok => error == null;
}

/// Full customer row from `getCustomerbyID` — every column the intake/edit
/// form needs, plus the joined `documents` and `serial_entries`.
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
    required this.serialEntries,
    required this.documents,
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
  final String provinceCode; // numeric province_code
  final String provinceName; // province (text name)
  final String cityCode; // numeric city_code
  final String cityName; // city (text name)
  final int cStatus;
  final List<SerialEntry> serialEntries;
  final List<CustomerDocument> documents;

  String get ownerName => [firstName, middleName, lastName]
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .join(' ');

  String get status => cStatus == 1 ? 'Processed' : 'Submitted';

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
      softwareName:
          (json['softwarename'] ?? json['software_name'] ?? '').toString(),
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
      serialEntries: parseList(json['serial_entries'], SerialEntry.fromJson),
      documents: parseList(json['documents'], CustomerDocument.fromJson),
    );
  }
}

/// PSGC province from `ph-json/province.json`.
class Province {
  Province({required this.code, required this.name});
  final String code;
  final String name;
  factory Province.fromJson(Map<String, dynamic> json) => Province(
        code: (json['province_code'] ?? '').toString(),
        name: (json['province_name'] ?? '').toString(),
      );
}

/// PSGC city/municipality from `ph-json/city.json`.
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

/// Outcome of a create/update call to the customer endpoints.
class CustomerSaveResult {
  CustomerSaveResult({required this.ok, required this.message, this.customerId});
  final bool ok;
  final String message;
  final int? customerId;
}

/// Normalise a date column that may arrive as null, empty, or a zero-date
/// (`0000-00-00`) into '' — otherwise keep the `YYYY-MM-DD` prefix.
String _cleanDate(Object? value) {
  final s = (value ?? '').toString().trim();
  if (s.isEmpty || s.startsWith('0000')) return '';
  // Drop any time component so it round-trips cleanly through the date picker.
  return s.split(' ').first.split('T').first;
}

/// Coerce a numeric PSGC code column that may arrive as int/num/string into a
/// plain string, mapping null/0 to ''.
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
