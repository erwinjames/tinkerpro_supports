const List<String> kBirV1Statuses = <String>['draft', 'for_ptu', 'completed'];

const List<String> kBirV1DocTypes = <String>[
  'application',
  'ptu',
  'valid_id',
  'extraction_doc',
  'bir_form',
  'sworn_declaration',
  'other',
];

const int kBirV1MaxUploadBytes = 20971520;

String birV1StatusLabel(String status) {
  switch (status) {
    case 'completed':
      return 'Completed';
    case 'for_ptu':
      return 'For PTU';
    case 'draft':
      return 'Draft';
    default:
      return status.isEmpty ? 'Draft' : birV1Humanize(status);
  }
}

String birV1Humanize(String raw) {
  final value = raw.replaceAll('_', ' ').trim();
  if (value.isEmpty) return value;
  return value[0].toUpperCase() + value.substring(1);
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}'.trim()) ?? 0;
}

int? _asIntOrNull(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  final text = '$value'.trim();
  if (text.isEmpty) return null;
  return int.tryParse(text);
}

String _asText(Object? value) {
  if (value == null) return '';
  final text = '$value'.trim();
  if (text.toLowerCase() == 'null') return '';
  return text;
}

bool _asBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = '${value ?? ''}'.trim().toLowerCase();
  return text == '1' || text == 'true' || text == 'yes' || text == 'on';
}

List<String> _asStringList(Object? value) {
  if (value is List) {
    return value
        .map((e) => _asText(e))
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }
  return const <String>[];
}

class BirV1Document {
  const BirV1Document({
    required this.id,
    required this.customerId,
    required this.docType,
    required this.originalFilename,
    required this.storedFilename,
    required this.filePath,
    required this.mimeType,
    required this.fileSize,
    required this.uploadedBy,
    required this.uploadedAt,
    required this.exists,
  });

  final int id;
  final int customerId;
  final String docType;
  final String originalFilename;
  final String storedFilename;
  final String filePath;
  final String mimeType;
  final int? fileSize;
  final String uploadedBy;
  final String uploadedAt;
  final bool exists;

  factory BirV1Document.fromJson(Map<String, dynamic> json) {
    return BirV1Document(
      id: _asInt(json['id']),
      customerId: _asInt(json['customer_id']),
      docType: _asText(json['doc_type']),
      originalFilename: _asText(json['original_filename']),
      storedFilename: _asText(json['stored_filename']),
      filePath: _asText(json['file_path']),
      mimeType: _asText(json['mime_type']),
      fileSize: _asIntOrNull(json['file_size']),
      uploadedBy: _asText(json['uploaded_by']),
      uploadedAt: _asText(json['uploaded_at']),
      exists: json['exists'] == null ? true : _asBool(json['exists']),
    );
  }

  String get displayName =>
      originalFilename.isEmpty ? storedFilename : originalFilename;

  String get sizeLabel {
    final bytes = fileSize ?? 0;
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String get subtitle {
    final parts = <String>[
      birV1Humanize(docType),
      if (sizeLabel.isNotEmpty) sizeLabel,
      if (uploadedAt.isNotEmpty) uploadedAt,
    ];
    return parts.join(' · ');
  }
}

class BirV1Record {
  const BirV1Record({
    required this.id,
    required this.companyName,
    required this.tin,
    required this.tinIssuanceDate,
    required this.rdo,
    required this.branchCode,
    required this.address,
    required this.region,
    required this.province,
    required this.city,
    required this.barangay,
    required this.firstName,
    required this.middleName,
    required this.lastName,
    required this.email,
    required this.username,
    required this.password,
    required this.businessLine,
    required this.softwareName,
    required this.accNumber,
    required this.serialNumber,
    required this.serialNumbers,
    required this.min,
    required this.ptu,
    required this.posDateIssued,
    required this.isVat,
    required this.step2,
    required this.finalStep,
    required this.cStatus,
    required this.actionNotes,
    required this.pdfFile,
    required this.ptuFile,
    required this.status,
    required this.birCardReady,
    required this.birCardMissingFields,
    required this.documents,
  });

  final int id;
  final String companyName;
  final String tin;
  final String tinIssuanceDate;
  final String rdo;
  final String branchCode;
  final String address;
  final String region;
  final String province;
  final String city;
  final String barangay;
  final String firstName;
  final String middleName;
  final String lastName;
  final String email;
  final String username;
  final String password;
  final String businessLine;
  final String softwareName;
  final String accNumber;
  final String serialNumber;
  final List<String> serialNumbers;
  final String min;
  final String ptu;
  final String posDateIssued;
  final bool isVat;
  final bool step2;
  final bool finalStep;
  final bool cStatus;
  final String actionNotes;
  final String pdfFile;
  final String ptuFile;
  final String status;
  final bool birCardReady;
  final List<String> birCardMissingFields;
  final List<BirV1Document> documents;

  factory BirV1Record.fromJson(Map<String, dynamic> json) {
    final docs = json['documents'];
    return BirV1Record(
      id: _asInt(json['id']),
      companyName: _asText(json['company_name']),
      tin: _asText(json['tin']),
      tinIssuanceDate: _asText(json['tin_issuance_date']),
      rdo: _asText(json['rdo']),
      branchCode: _asText(json['branch_code']),
      address: _asText(json['address']),
      region: _asText(json['region']),
      province: _asText(json['province']),
      city: _asText(json['city']),
      barangay: _asText(json['barangay']),
      firstName: _asText(json['first_name']),
      middleName: _asText(json['middle_name']),
      lastName: _asText(json['last_name']),
      email: _asText(json['email']),
      username: _asText(json['username']),
      password: _asText(json['password']),
      businessLine: _asText(json['business_line']),
      softwareName: _asText(json['softwarename']),
      accNumber: _asText(json['acc_num']),
      serialNumber: _asText(json['serial_number']),
      serialNumbers: _asStringList(json['serial_numbers']),
      min: _asText(json['min']),
      ptu: _asText(json['ptu']),
      posDateIssued: _asText(json['pos_date_issued']),
      isVat: _asBool(json['is_vat']),
      step2: _asBool(json['step2']),
      finalStep: _asBool(json['final_step']),
      cStatus: _asBool(json['c_status']),
      actionNotes: _asText(json['action_notes']),
      pdfFile: _asText(json['pdf_file']),
      ptuFile: _asText(json['ptu_file']),
      status: _asText(json['status']).isEmpty
          ? 'draft'
          : _asText(json['status']),
      birCardReady: _asBool(json['bir_card_ready']),
      birCardMissingFields: _asStringList(json['bir_card_missing_fields']),
      documents: docs is List
          ? docs
                .whereType<Map>()
                .map(
                  (e) => BirV1Document.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList(growable: false)
          : const <BirV1Document>[],
    );
  }

  String get ownerName =>
      [firstName, middleName, lastName].where((p) => p.isNotEmpty).join(' ');

  String get statusLabel => birV1StatusLabel(status);

  String get tinWithBranch =>
      branchCode.isEmpty || tin.isEmpty ? tin : '$tin-$branchCode';

  String get title => companyName.isEmpty ? 'Registration #$id' : companyName;

  List<String> get ptuFiles => ptuFile
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);

  bool get isCompleted => status == 'completed';

  bool get isForPtu => status == 'for_ptu';
}

class BirV1Page {
  const BirV1Page({
    required this.rows,
    required this.page,
    required this.limit,
    required this.total,
    required this.totalPages,
  });

  final List<BirV1Record> rows;
  final int page;
  final int limit;
  final int total;
  final int totalPages;

  static const BirV1Page empty = BirV1Page(
    rows: <BirV1Record>[],
    page: 1,
    limit: 30,
    total: 0,
    totalPages: 1,
  );

  factory BirV1Page.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    final meta = json['meta'] is Map
        ? Map<String, dynamic>.from(json['meta'] as Map)
        : const <String, dynamic>{};
    final rows = data is List
        ? data
              .whereType<Map>()
              .map((e) => BirV1Record.fromJson(Map<String, dynamic>.from(e)))
              .toList(growable: false)
        : const <BirV1Record>[];
    final limit = _asInt(meta['limit']);
    final totalPages = _asInt(meta['total_pages']);
    return BirV1Page(
      rows: rows,
      page: meta['page'] == null ? 1 : _asInt(meta['page']),
      limit: limit <= 0 ? 30 : limit,
      total: _asInt(meta['total']),
      totalPages: totalPages <= 0 ? 1 : totalPages,
    );
  }
}

class BirV1Meta {
  const BirV1Meta({
    required this.statuses,
    required this.documentTypes,
    required this.maxUploadBytes,
  });

  final List<String> statuses;
  final List<String> documentTypes;
  final int maxUploadBytes;

  static const BirV1Meta fallback = BirV1Meta(
    statuses: kBirV1Statuses,
    documentTypes: kBirV1DocTypes,
    maxUploadBytes: kBirV1MaxUploadBytes,
  );

  factory BirV1Meta.fromJson(Map<String, dynamic> json) {
    final statuses = _asStringList(json['statuses']);
    final types = _asStringList(json['document_types']);
    final max = _asInt(json['max_upload_bytes']);
    return BirV1Meta(
      statuses: statuses.isEmpty ? kBirV1Statuses : statuses,
      documentTypes: types.isEmpty ? kBirV1DocTypes : types,
      maxUploadBytes: max <= 0 ? kBirV1MaxUploadBytes : max,
    );
  }
}
