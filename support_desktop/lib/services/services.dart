import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import '../api_client.dart';
import '../models/models.dart';

class AuthService {
  AuthService(this.api);
  final ApiClient api;

  Future<UserSession> login(String email, String password) async {
    await api.clearSession();

    final res = await api.post(
      'login',
      body: {'email': email.trim(), 'password': password, 'remember': '1'},
    );
    if (res['success'] != true) {
      final wait =
          int.tryParse(
            '${res['retry_after'] ?? res['lockout_seconds'] ?? ''}',
          ) ??
          0;
      throw LoginFailure(
        res['message']?.toString() ?? 'Login failed',
        retryAfter: Duration(seconds: wait),
        locked: res['locked'] == true || res['rate_limited'] == true,
        wrongCredentials:
            res['locked'] != true &&
            res['rate_limited'] != true &&
            res['ambiguous_email'] != true,
      );
    }
    return _adoptSession(res);
  }

  Future<UserSession> _adoptSession(Map<String, dynamic> res) async {
    final session = UserSession.fromJson(res);
    if (session.userId <= 0) {
      throw Exception(
        'Login succeeded but server did not return a user id. '
        'Please contact support.',
      );
    }
    await api.setUserId(session.userId);
    if (session.username.isNotEmpty && session.username != '—') {
      await api.setUsername(session.username);
    }
    await api.setPermissions(session.permissions);
    return session;
  }

  static String get desktopPlatformLabel {
    final os = Platform.isWindows
        ? 'Windows'
        : Platform.isMacOS
        ? 'macOS'
        : Platform.isLinux
        ? 'Linux'
        : Platform.operatingSystem;
    return 'TinkerPro Support Desktop · $os';
  }

  Future<PhoneLoginRequest> startPhoneLogin(String identifier) async {
    await api.clearSession();
    final res = await api.post(
      'desktopPhoneLoginStart',
      body: {'identifier': identifier.trim(), 'platform': desktopPlatformLabel},
    );
    if (res['success'] != true) {
      final wait = int.tryParse('${res['retry_after'] ?? ''}') ?? 0;
      throw LoginFailure(
        res['message']?.toString() ?? 'Could not send the sign-in request.',
        retryAfter: Duration(seconds: wait),
        locked: res['rate_limited'] == true,
      );
    }
    final requestId = (res['request_id'] ?? '').toString();
    final pollToken = (res['poll_token'] ?? '').toString();
    if (requestId.isEmpty || pollToken.isEmpty) {
      throw LoginFailure('Could not send the sign-in request.');
    }
    return PhoneLoginRequest(
      requestId: requestId,
      pollToken: pollToken,
      matchNumber: int.tryParse('${res['match_number']}') ?? 0,
      expiresAt: DateTime.now().add(
        Duration(seconds: int.tryParse('${res['expires_in']}') ?? 120),
      ),
    );
  }

  Future<PhoneLoginPoll> pollPhoneLogin(PhoneLoginRequest request) async {
    final res = await api.post(
      'desktopPhoneLoginPoll',
      body: {
        'request_id': request.requestId,
        'poll_token': request.pollToken,
        'remember': '1',
      },
    );
    final status = (res['status'] ?? '').toString();
    final message = res['message']?.toString() ?? '';
    if (status == 'approved' && res['success'] == true) {
      final session = await _adoptSession(res);
      return PhoneLoginPoll(PhoneLoginState.approved, session: session);
    }
    switch (status) {
      case 'pending':
        return PhoneLoginPoll(
          PhoneLoginState.pending,
          retryAfter: Duration(
            seconds: int.tryParse('${res['retry_after'] ?? ''}') ?? 0,
          ),
        );
      case 'denied':
        return PhoneLoginPoll(
          PhoneLoginState.denied,
          message: message.isEmpty
              ? 'Sign-in was denied on your phone.'
              : message,
        );
      default:
        return PhoneLoginPoll(
          PhoneLoginState.expired,
          message: message.isEmpty
              ? 'The sign-in request expired. Please try again.'
              : message,
        );
    }
  }

  Future<bool> refreshPermissions() async {
    try {
      final res = await api
          .get('getMobileAuthSession')
          .timeout(const Duration(seconds: 8));
      if (res['success'] == true && res['permissions'] != null) {
        final fresh = UserSession.fromJson(
          Map<String, dynamic>.from(res),
        ).permissions;
        if (fresh.isEmpty) return false;
        final before = api.permissions;
        final changed =
            before.length != fresh.length ||
            fresh.entries.any((e) => before[e.key] != e.value);
        if (changed) await api.setPermissions(fresh);
        return changed;
      }
    } catch (_) {}
    return false;
  }

  Future<UserSession?> currentSession() async {
    try {
      final res = await api.get('getMobileAuthSession');
      if (res['success'] == true && res['user'] is Map) {
        return UserSession.fromJson(
          Map<String, dynamic>.from(res['user'] as Map),
        );
      }
    } catch (_) {}
    return null;
  }

  Future<int?> currentUserId() async {
    final cached = api.userId;
    if (cached != null && cached > 0) return cached;
    try {
      final res = await api
          .get('getMobileAuthSession')
          .timeout(const Duration(seconds: 8));
      if (res['success'] == true) {
        final raw = res['userID'] ?? res['user_id'];
        int? parsed;
        if (raw is int) {
          parsed = raw;
        } else if (raw is num) {
          parsed = raw.toInt();
        } else if (raw is String) {
          parsed = int.tryParse(raw);
        }
        if (parsed != null && parsed > 0) {
          await api.setUserId(parsed);
          return parsed;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<({int? userId, String? error})> currentUserIdWithReason() async {
    final cached = api.userId;
    if (cached != null && cached > 0) return (userId: cached, error: null);
    try {
      final res = await api
          .get('getMobileAuthSession')
          .timeout(const Duration(seconds: 8));
      if (res['success'] == true) {
        final raw = res['userID'] ?? res['user_id'];
        int? parsed;
        if (raw is int) {
          parsed = raw;
        } else if (raw is num) {
          parsed = raw.toInt();
        } else if (raw is String) {
          parsed = int.tryParse(raw);
        }
        if (parsed != null && parsed > 0) {
          await api.setUserId(parsed);
          return (userId: parsed, error: null);
        }
        return (userId: null, error: 'Server did not return a user id.');
      }
      final msg = (res['message'] ?? 'No active session').toString();
      return (userId: null, error: msg);
    } catch (e) {
      return (userId: null, error: 'Network error');
    }
  }

  Future<void> logout() async {
    try {
      await api.post('logout');
    } catch (_) {}
    await api.clearSession();
  }
}

class DashboardService {
  DashboardService(this.api);
  final ApiClient api;

  Future<DashboardSummary> fetch() async {
    Map<String, dynamic> summary = {};
    Map<String, dynamic> notifications = {};
    try {
      summary = await api.get('getMobileDashboardSummary');
    } catch (_) {}
    try {
      notifications = await api.get('getMobileNotificationSummary');
    } catch (_) {}
    if (summary['success'] != true && notifications['success'] != true) {
      return DashboardSummary.empty();
    }
    return DashboardSummary.fromJson(summary, notifications);
  }
}

class CustomerService {
  CustomerService(this.api);
  final ApiClient api;

  Future<List<CustomerBrief>> list({String? search, int limit = 50}) async {
    try {
      final res = await api.get('getcustomer', {
        'limit': '$limit',
        'page': '1',
        if (search != null && search.isNotEmpty) 'search': search,
      });
      final raw = res['data'];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => CustomerBrief.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<Map<String, dynamic>?> detail(int id) async {
    try {
      final res = await api.get('getCustomerbyID', {'id': id.toString()});
      for (final key in ['data', 'customer', 'row']) {
        final v = res[key];
        if (v is Map) return Map<String, dynamic>.from(v);
      }
      if (res['id'] != null) return res;
    } catch (_) {}
    return null;
  }

  Future<CustomerDetail?> detailFull(int id) async {
    try {
      final res = await api.get('getCustomerbyID', {'id': id.toString()});
      final row = _unwrapRow(res);
      if (row != null) return CustomerDetail.fromJson(row);
    } catch (_) {}
    return null;
  }

  Map<String, dynamic>? _unwrapRow(Map<String, dynamic> res) {
    for (final key in ['data', 'customer', 'row']) {
      final v = res[key];
      if (v is Map) return Map<String, dynamic>.from(v);
    }
    if (res['id'] != null) return res;
    return null;
  }

  Future<CustomerSaveResult> save({
    int? id,
    required Map<String, String> fields,
  }) async {
    try {
      final body = Map<String, String>.from(fields);
      final String action;
      if (id == null) {
        action = 'addcustomer';
      } else {
        action = 'updateCustomer';
        body['customer_id'] = id.toString();
      }
      final res = await api.post(action, body: body);
      final ok = res['success'] == true || res['status'] == 'success';
      final msg =
          (res['message'] ??
                  (ok ? 'Saved' : 'Could not save. Please try again.'))
              .toString();
      return CustomerSaveResult(
        ok: ok,
        message: msg,
        customerId: _asIntOrNull(res['customer_id']) ?? id,
      );
    } catch (_) {
      return CustomerSaveResult(
        ok: false,
        message: 'Network error. Check your connection and try again.',
      );
    }
  }

  Future<bool> delete(int id) async {
    try {
      final res = await api.post('deleteCustomer', body: {'id': id.toString()});
      return res['success'] == true || res['status'] == 'success';
    } catch (_) {
      return false;
    }
  }

  Future<({bool duplicate, String company})> checkTinDuplicate(
    String tin,
    String branchCode,
  ) async {
    try {
      final res = await api.get('checkTinDuplicate', {
        'tin': tin,
        'branch_code': branchCode,
      });
      final existing = res['existing'];
      final company = (existing is Map ? (existing['company_name'] ?? '') : '')
          .toString();
      return (duplicate: res['duplicate'] == true, company: company);
    } catch (_) {
      return (duplicate: false, company: '');
    }
  }

  Future<({bool ok, String? invoice, String? error})> searchInvoice(
    String term,
  ) async {
    final q = term.trim();
    if (q.isEmpty) return (ok: false, invoice: null, error: 'not_found');
    try {
      final res = await api.get('searchInvoiceCustomer', {'q': q});
      if (res['error'] != null) {
        return (ok: false, invoice: null, error: res['error'].toString());
      }
      String invNo(Map m) =>
          (m['invoice_number'] ??
                  m['invoiceNumber'] ??
                  m['invoice_no'] ??
                  m['invoiceNo'] ??
                  m['number'] ??
                  m['invoice'] ??
                  '')
              .toString();
      List list;
      if (res['invoice_number'] != null) {
        list = [res];
      } else {
        final raw = res['data'] ?? res['results'] ?? res['invoices'];
        list = raw is List ? raw : const [];
      }
      for (final item in list.whereType<Map>()) {
        final m = Map<String, dynamic>.from(item);
        if (invNo(m).trim().toLowerCase() == q.toLowerCase()) {
          return (ok: true, invoice: invNo(m), error: null);
        }
      }
      return (ok: false, invoice: null, error: 'not_found');
    } catch (_) {
      return (ok: false, invoice: null, error: 'unreachable');
    }
  }

  Future<UploadedDoc?> uploadDocument(String filePath) async {
    try {
      final res = await api.postPathMultipart(
        'client-upload-attachment.php',
        files: {'file': filePath},
      );
      final stored = res['stored_file'];
      if (res['success'] == true && stored is Map) {
        return UploadedDoc.fromStoredFile(Map<String, dynamic>.from(stored));
      }
    } catch (_) {}
    return null;
  }

  Future<ExtractionResult> extractDocuments(
    List<String> paths, {
    String mode = 'accurate',
    String? validIdPath,
    String? validIdType,
  }) async {
    if (paths.isEmpty) return ExtractionResult.error('No files selected.');
    try {
      final res = await api
          .postPathMultipartFiles(
            'client-multidoc-extract.php',
            fields: {
              'extract_mode': mode,
              if (validIdType != null && validIdType.isNotEmpty)
                'valid_id_type': validIdType,
            },
            files: [
              for (final p in paths) (field: 'files[]', path: p),
              if (validIdPath != null && validIdPath.isNotEmpty)
                (field: 'valid_id_file', path: validIdPath),
            ],
          )
          .timeout(const Duration(minutes: 4));
      if (res['error'] != null) {
        return ExtractionResult.error(res['error'].toString());
      }
      return _buildExtraction(res);
    } on TimeoutException {
      return ExtractionResult.error('Extraction timed out. Please try again.');
    } catch (_) {
      return ExtractionResult.error('Extraction failed. Please try again.');
    }
  }

  static String encodeSerialEntries(List<SerialEntry> entries) =>
      jsonEncode(entries.map((e) => e.toJson()).toList());

  int? _asIntOrNull(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }
}

class LeadService {
  LeadService(this.api);
  final ApiClient api;

  Future<List<LeadBrief>> list() async {
    try {
      final res = await api.get('getleads');
      final raw = res['data'] ?? res;
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => LeadBrief.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<bool> updateNote(int id, String note) async {
    try {
      final res = await api.post(
        'updateLeadNote',
        body: {'id': id.toString(), 'note': note},
      );
      return res['success'] == true || res['status'] == 'success';
    } catch (_) {
      return false;
    }
  }

  Future<bool> delete(int id) async {
    try {
      final res = await api.post('deleteLead', body: {'id': id.toString()});
      return res['success'] == true || res['status'] == 'success';
    } catch (_) {
      return false;
    }
  }
}

class TicketService {
  TicketService(this.api);
  final ApiClient api;

  Future<List<TicketBrief>> list() async {
    try {
      final res = await api.get('get_tickets');
      final raw = res['data'] ?? res;
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => TicketBrief.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    return const [];
  }
}

ExtractionResult _buildExtraction(Map<String, dynamic> res) {
  String s(dynamic v) => (v ?? '').toString();

  final rawStored = res['storedFiles'];
  final docs = <UploadedDoc>[];
  Map<String, dynamic>? validIdStored;
  if (rawStored is List) {
    for (final e in rawStored.whereType<Map>()) {
      final m = Map<String, dynamic>.from(e);
      if (m['is_valid_id'] == true) {
        validIdStored = m;
        continue;
      }
      docs.add(UploadedDoc.fromStoredFile(m));
    }
  }

  final vIdType = s(res['ValidIDType']);
  final vIdName = s(res['IDHolderName']);
  final vIdNumber = s(res['ValidIDNumber']);
  final vIdBirthdate = s(res['ValidIDBirthdate']);
  final hasValidId =
      validIdStored != null || vIdType.isNotEmpty || vIdName.isNotEmpty;
  UploadedDoc? validIdDoc;
  if (validIdStored != null) {
    validIdDoc = UploadedDoc(
      original: (validIdStored['original'] ?? '').toString(),
      stored: (validIdStored['stored'] ?? '').toString(),
      mime: (validIdStored['mime'] ?? '').toString(),
      size: int.tryParse('${validIdStored['size'] ?? ''}') ?? 0,
      extracted: {
        'id_type': vIdType,
        'id_name': vIdName,
        'id_number': vIdNumber,
        'id_birthdate': vIdBirthdate,
      },
    );
  }

  final tinDigits = (s(res['TIN_BranchCode']) + s(res['BranchCode']))
      .replaceAll(RegExp(r'[^0-9]'), '');
  final tin9 = tinDigits.length >= 9 ? tinDigits.substring(0, 9) : tinDigits;
  final branch = tinDigits.length > 9 ? tinDigits.substring(9) : '';
  final tinFormatted = tin9.length == 9
      ? '${tin9.substring(0, 3)}-${tin9.substring(3, 6)}-${tin9.substring(6, 9)}'
      : _groupBy3(tin9);

  var company = s(res['BusinessName']);
  final owner = _parseOwnerName(s(res['OwnerName']));
  var first = owner.first, middle = owner.middle, last = owner.last;
  if (owner.isCorporate) {
    if (company.trim().isEmpty) company = owner.full;
    first = '';
    middle = '';
    last = '';
  }

  if (hasValidId) {
    var idFirst = s(res['IDHolderFirstName']).trim();
    var idMiddle = s(res['IDHolderMiddleName']).trim();
    var idLast = s(res['IDHolderLastName']).trim();
    if (idFirst.isEmpty &&
        idMiddle.isEmpty &&
        idLast.isEmpty &&
        vIdName.isNotEmpty) {
      final p = _parseOwnerName(vIdName);
      idFirst = p.first;
      idMiddle = p.middle;
      idLast = p.last;
    }
    if (idFirst.isNotEmpty || idMiddle.isNotEmpty || idLast.isNotEmpty) {
      first = idFirst;
      middle = idMiddle;
      last = idLast;
    }
  }

  return ExtractionResult(
    companyName: company,
    tin: tinFormatted,
    branchCode: branch,
    tinIssuanceDate: s(res['TINIssuanceDate']),
    address: s(res['BusinessAddress']),
    businessLine: s(res['LineOfBusiness']),
    rdo: s(res['RDOCode']),
    firstName: first,
    middleName: middle,
    lastName: last,
    isVat: _detectVat(s(res['RegistrationType']), s(res['RawExtractedText'])),
    storedFiles: docs,
    idType: vIdType,
    idNumber: vIdNumber,
    idBirthdate: vIdBirthdate,
    validIdDoc: validIdDoc,
  );
}

String _groupBy3(String digits) {
  if (digits.isEmpty) return '';
  final parts = <String>[];
  for (var i = 0; i < digits.length; i += 3) {
    final end = (i + 3) < digits.length ? i + 3 : digits.length;
    parts.add(digits.substring(i, end));
  }
  return parts.join('-');
}

bool? _detectVat(String registrationType, String rawText) {
  String norm(String v) {
    final u = v.trim().toUpperCase();
    if (u.contains('NON') && u.contains('VAT')) return 'NON-VAT';
    if (u.contains('EXEMPT') && u.contains('VAT')) return 'NON-VAT';
    if (u.contains('PERCENTAGE TAX')) return 'NON-VAT';
    if (u.contains('VAT')) return 'VAT';
    return '';
  }

  var vat = norm(registrationType);
  if (vat.isEmpty && rawText.isNotEmpty) {
    final u = rawText.toUpperCase();
    if (u.contains('NON-VAT') ||
        u.contains('NON VAT') ||
        u.contains('NONVAT') ||
        u.contains('VAT-EXEMPT') ||
        u.contains('VAT EXEMPT') ||
        u.contains('PERCENTAGE TAX') ||
        (u.contains('2551Q') && !u.contains('2550M') && !u.contains('2550Q'))) {
      vat = 'NON-VAT';
    } else if (u.contains('VAT REGISTERED') ||
        u.contains('VALUE ADDED TAX') ||
        u.contains('2550M') ||
        u.contains('2550Q')) {
      vat = 'VAT';
    }
  }
  if (vat == 'VAT') return true;
  if (vat == 'NON-VAT') return false;
  return null;
}

({String full, String first, String middle, String last, bool isCorporate})
_parseOwnerName(String raw) {
  const empty = (full: '', first: '', middle: '', last: '', isCorporate: false);

  var cleaned = raw
      .replaceAll(RegExp(r'^[\s.,\-_:;|/\\#*]+'), '')
      .replaceAll(RegExp(r'[\s.,\-_:;|/\\#*]+$'), '')
      .trim()
      .toUpperCase();
  if (cleaned.isEmpty) return empty;
  cleaned = cleaned
      .replaceAll(RegExp(r',\s*;'), ',')
      .replaceAll(RegExp(r';\s*,'), ',')
      .replaceAll(';', ',');

  const garbage = [
    'REPUBLIKA',
    'PILIPINAS',
    'KAGAWARAN',
    'PANANALAPI',
    'KAWANIHAN',
    'KAWANEAN',
    'RENTAS',
    'INTERNAS',
    'KAGAWARA',
    'EUITWAS',
    'PANANALA',
    'PANANALAP',
    'PANAN',
    'RERIO',
    'RNAS',
    'BUREAU OF INTERNAL REVENUE',
    'CERTIFICATE OF REGISTRATION',
    'BIR FORM',
    'ASSISTANT REVENUE',
    'DISTRICT OFFICER',
    'TIN ISSUANCE',
    'NAME OF TAXPAYER',
    'OF TAXPAYER',
    'TIN & BRANCH',
    'BRANCH CODE',
    'REGISTERED NAME',
    'DATE OF REGISTRATION',
    'BUSINESS ADDRESS',
    'RDO CODE',
    'LINE OF BUSINESS',
    'REGISTRATION TYPE',
    'DATE OCN GENERATED',
    'OCN GENERATED',
    'PAYMENT MODE',
    'QUARTERLY',
    'MONTHLY',
    'ANNUALLY',
    'SEMI-ANNUALLY',
    'HEAD OFFICE',
    'REGISTERING OFFICE',
    'TRADE NAME',
    'BUSINESS INFORMATION',
  ];
  for (final g in garbage) {
    if (cleaned.contains(g)) return empty;
  }
  if (RegExp(r'^(N/A|NA|NONE|NULL|-+)$').hasMatch(cleaned)) return empty;

  final corpSuffixes = RegExp(
    r'\b(INC\.?|INCS?|ING\.?|CORP\.?|CORPORATION|LLC|LTD\.?|LIMITED|ENTERPRISES?|OPC|FOUNDATION|ASSOCIATION)\b',
  );
  final bizKeywords = RegExp(
    r'\b(CAFE|RESTAURANT|TRADING|SHOP|STORE|MART|SALON|BAKERY|PHARMACY|HARDWARE|HOTEL|RESORT|CONSTRUCTION|SERVICES|SUPPLY|MANUFACTURING|FOOD|BEVERAGES|REALTY|PROPERTIES|DEVELOPMENT|LOGISTICS|TRANSPORT|FREIGHT|PRINTING|MARKETING)\b',
  );
  var isCorporate = corpSuffixes.hasMatch(cleaned);
  if (!isCorporate) {
    final bizHits = bizKeywords.allMatches(cleaned).length;
    final wordCount = cleaned
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .length;
    isCorporate = bizHits >= 2 || (bizHits >= 1 && wordCount >= 4);
  }
  if (isCorporate) {
    return (full: cleaned, first: '', middle: '', last: '', isCorporate: true);
  }

  if (RegExp(r'^\d{3}[-\s]?\d{2,3}').hasMatch(cleaned)) return empty;
  if (RegExp(r'[A-Z]').allMatches(cleaned).length < 3) return empty;

  const months =
      'JANUARY|FEBRUARY|MARCH|APRIL|MAY|JUNE|JULY|AUGUST|SEPTEMBER|OCTOBER|NOVEMBER|DECEMBER';
  cleaned = cleaned
      .replaceAll(RegExp(r'\s+(' + months + r')\s+\d{1,2},?\s+\d{4}\s*$'), '')
      .trim();
  cleaned = cleaned.replaceAll(RegExp(r'\s+(' + months + r')\s*$'), '').trim();
  if (cleaned.isEmpty) return empty;

  var first = '', middle = '', last = '';
  if (cleaned.contains(',')) {
    final commaParts = cleaned.split(',');
    last = commaParts[0].trim();
    final rest = commaParts.sublist(1).join(',').trim();
    final restWords = rest
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    if (restWords.length >= 2) {
      first = restWords.sublist(0, restWords.length - 1).join(' ');
      middle = restWords.last;
    } else if (restWords.length == 1) {
      first = restWords[0];
    }
    cleaned = [first, middle, last].where((e) => e.isNotEmpty).join(' ');
  } else {
    final words = cleaned
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    if (words.length >= 3) {
      first = words[0];
      middle = words.sublist(1, words.length - 1).join(' ');
      last = words.last;
    } else if (words.length == 2) {
      first = words[0];
      last = words[1];
    } else if (words.length == 1) {
      first = words[0];
    }
  }
  return (
    full: cleaned,
    first: first,
    middle: middle,
    last: last,
    isCorporate: false,
  );
}

class PhoneLoginRequest {
  PhoneLoginRequest({
    required this.requestId,
    required this.pollToken,
    required this.matchNumber,
    required this.expiresAt,
  });
  final String requestId;
  final String pollToken;
  final int matchNumber;
  final DateTime expiresAt;
}

enum PhoneLoginState { pending, approved, denied, expired }

class PhoneLoginPoll {
  PhoneLoginPoll(
    this.state, {
    this.message = '',
    this.session,
    this.retryAfter = Duration.zero,
  });
  final PhoneLoginState state;
  final String message;
  final UserSession? session;
  final Duration retryAfter;
}

class LoginFailure implements Exception {
  LoginFailure(
    this.message, {
    this.retryAfter = Duration.zero,
    this.locked = false,
    this.wrongCredentials = false,
  });
  final String message;
  final Duration retryAfter;
  final bool locked;
  final bool wrongCredentials;
  @override
  String toString() => message;
}
