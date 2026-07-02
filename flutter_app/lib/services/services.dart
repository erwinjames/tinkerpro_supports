import 'dart:async';

import '../api_client.dart';
import '../models/models.dart';

/// Service layer. Each method calls `api.php?action=<x>` and returns typed
/// results. The wire shapes here are verified against the live backend:
///   * getMobileDashboardSummary  → {success, stats: [...], charts: {...}}
///   * getMobileNotificationSummary → {success, items: [{id,type,title,subtitle}]}
///   * getcustomer                → {data: [...], totalRecords, limit, page}
///   * getCustomerbyID            → single customer row (shape varies)
///   * getleads                   → bare array of leads
///   * get_tickets                → bare array of tickets (+ agent_name join)
///
/// On any failure the method returns an empty-but-valid result so the UI
/// still renders. Raw errors are rethrown only from login.

class AuthService {
  AuthService(this.api);
  final ApiClient api;

  Future<UserSession> login(String email, String password) async {
    // Defensive: wipe ANY user-scoped state from a previous session
    // before we even touch the server. Handles the case where logout
    // was incomplete (network failure, app killed mid-flight, upgraded
    // from an older build with broken logout, etc.) so no notification
    // cursor / cached user id / leftover cookie from account A leaks
    // into account B's session.
    await api.clearSession();

    final res = await api.post('login', body: {
      'email': email.trim(),
      'password': password,
      'remember': '1',
    });
    if (res['success'] != true) {
      throw Exception(res['message']?.toString() ?? 'Login failed');
    }
    final session = UserSession.fromJson(res);
    if (session.userId <= 0) {
      // Server said success=true but didn't include a usable userID.
      // Refusing rather than handing the caller a HomeShell with no
      // identity — that's exactly the state that produced "CHAT
      // UNAVAILABLE" loops in the wild.
      throw Exception(
          'Login succeeded but server did not return a user id. '
          'Please contact support.');
    }
    await api.setUserId(session.userId);
    if (session.username.isNotEmpty && session.username != '—') {
      await api.setUsername(session.username);
    }
    await api.setPermissions(session.permissions);
    return session;
  }

  /// Fetch the server's native social-sign-in config. Returns the Google web
  /// OAuth client id to use as the SDK's `serverClientId`, or '' when Google
  /// sign-in isn't configured on this server (button should be hidden).
  /// Best-effort: returns '' on any failure.
  Future<String> googleClientId() async {
    try {
      final res =
          await api.get('mobileAuthConfig').timeout(const Duration(seconds: 8));
      return (res['google_client_id'] ?? '').toString();
    } catch (_) {
      return '';
    }
  }

  /// Sign in with a Google OpenID Connect ID token obtained from the native
  /// SDK. The server verifies it and signs in via the same link-to-existing
  /// path as the web OAuth callback. Mirrors [login]'s session persistence.
  /// Throws on failure with the server's message (e.g. "No account is linked").
  Future<UserSession> loginWithGoogle(String idToken) async {
    await api.clearSession();
    final res = await api.post('mobileOAuthLogin', body: {
      'provider': 'google',
      'id_token': idToken,
    });
    if (res['success'] != true) {
      throw Exception(res['message']?.toString() ?? 'Google sign-in failed');
    }
    final session = UserSession.fromJson(res);
    if (session.userId <= 0) {
      throw Exception(
          'Sign-in succeeded but server did not return a user id. '
          'Please contact support.');
    }
    await api.setUserId(session.userId);
    if (session.username.isNotEmpty && session.username != '—') {
      await api.setUsername(session.username);
    }
    await api.setPermissions(session.permissions);
    return session;
  }

  /// Re-read the user's feature permissions from the server and persist
  /// them locally. The backend refreshes them from the DB on this call, so
  /// role changes made on the web side take effect on next app open without
  /// a re-login. Best-effort: a network failure leaves the cached map
  /// (from login) untouched. Returns true when the map actually changed.
  Future<bool> refreshPermissions() async {
    try {
      final res = await api
          .get('getMobileAuthSession')
          .timeout(const Duration(seconds: 8));
      if (res['success'] == true && res['permissions'] != null) {
        final fresh =
            UserSession.fromJson(Map<String, dynamic>.from(res)).permissions;
        final before = api.permissions;
        final changed = before.length != fresh.length ||
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
            Map<String, dynamic>.from(res['user'] as Map));
      }
    } catch (_) {}
    return null;
  }

  /// Returns the authenticated user's id. Reads the value persisted at
  /// login time (cheap, no network) first, then falls back to a one-shot
  /// `getMobileAuthSession` call with an 8-second timeout for users
  /// upgrading from older builds that didn't persist the id.
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
          // Cache for next launch so the next bootstrap is offline-friendly.
          await api.setUserId(parsed);
          return parsed;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Variant that returns both the user id (or null) AND the server's
  /// last-message reason on failure — used by the chat bootstrap so the
  /// "CHAT UNAVAILABLE" screen can show *why* (No active session / HTTP
  /// error / network) instead of a generic "check your connection".
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
        return (
          userId: null,
          error: 'Server did not return a user id.',
        );
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

  /// `getCustomerbyID` returns the full customer row. Response shape has
  /// varied across installs, so we sniff for the usual wrappers.
  Future<Map<String, dynamic>?> detail(int id) async {
    try {
      final res = await api.get('getCustomerbyID', {'id': id.toString()});
      final row = _unwrapRow(res);
      if (row != null) return row;
    } catch (_) {}
    return null;
  }

  /// Typed variant of [detail] — the full row plus its joined `documents` and
  /// `serial_entries`. Returns null on any failure.
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
    // Some endpoints return the row directly with `id` as a top-level key.
    if (res['id'] != null) return res;
    return null;
  }

  /// Create (when [id] is null) or update a BIR/customer record. The web
  /// server does all the processing — we just POST the form body to
  /// `addcustomer` / `updateCustomer`. [fields] must already carry the exact
  /// backend field names (see CustomerFormScreen).
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
      final msg = (res['message'] ??
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

  /// Inline TIN duplicate check. Returns whether a record already exists and,
  /// if so, the existing company name (for a helpful warning).
  Future<({bool duplicate, String company})> checkTinDuplicate(
      String tin, String branchCode) async {
    try {
      final res = await api.get('checkTinDuplicate', {
        'tin': tin,
        'branch_code': branchCode,
      });
      final existing = res['existing'];
      final company =
          (existing is Map ? (existing['company_name'] ?? '') : '').toString();
      return (duplicate: res['duplicate'] == true, company: company);
    } catch (_) {
      return (duplicate: false, company: '');
    }
  }

  Future<({bool duplicate, String company})> checkSnDuplicate(
      String sn) async {
    try {
      final res = await api.get('checkSnDuplicate', {'sn': sn});
      final existing = res['existing'];
      final company =
          (existing is Map ? (existing['company_name'] ?? '') : '').toString();
      return (duplicate: res['duplicate'] == true, company: company);
    } catch (_) {
      return (duplicate: false, company: '');
    }
  }

  /// Verify an invoice number against TinkerPro Invoice (the same
  /// `searchInvoiceCustomer` external lookup the web uses). Returns the matched
  /// invoice number on an exact match, or an error code ('not_found' /
  /// 'unreachable' / a server message).
  Future<({bool ok, String? invoice, String? error})> searchInvoice(
      String term) async {
    final q = term.trim();
    if (q.isEmpty) return (ok: false, invoice: null, error: 'not_found');
    try {
      final res = await api.get('searchInvoiceCustomer', {'q': q});
      if (res['error'] != null) {
        return (ok: false, invoice: null, error: res['error'].toString());
      }
      String invNo(Map m) => (m['invoice_number'] ??
              m['invoiceNumber'] ??
              m['invoice_no'] ??
              m['invoiceNo'] ??
              m['number'] ??
              m['invoice'] ??
              '')
          .toString();
      // The list may arrive under data/results/invoices, as a bare array
      // (wrapped by ApiClient as {'data': [...]}), or as a single object.
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

  /// Upload one document file to the web server's raw-store endpoint and get
  /// back the metadata to hand to `addcustomer`. Pure storage (no OCR) — the
  /// `doc_type` is decided by which array the metadata lands in at save time.
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

  /// Run the AI/OCR extraction over uploaded BIR documents and return
  /// form-ready field values plus the stored-document metadata (extraction
  /// docs). Mirrors the web's `client-multidoc-extract.php` → customer.js
  /// prefill flow. The endpoint keeps the connection alive during OCR, which
  /// can take a while — hence the generous timeout.
  /// Run the AI/OCR extraction over BIR documents, optionally including a valid
  /// ID (sent as `valid_id_file` + `valid_id_type`). We use THIS endpoint for
  /// the valid ID rather than the dedicated `valid-id-extract.php` because only
  /// this one streams keep-alive bytes during the long OCR — the dedicated
  /// endpoint blocks and times out behind the production proxy.
  Future<ExtractionResult> extractDocuments(
    List<String> paths, {
    String mode = 'fast',
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

  // PSGC address data lives as static JSON at the site root; fetched once and
  // cached on this service instance (which lives for the whole session).
  List<Province>? _provincesCache;
  List<City>? _allCitiesCache;
  final Map<String, List<City>> _cityByProvince = {};

  Future<List<Province>> provinces() async {
    if (_provincesCache != null) return _provincesCache!;
    try {
      final res = await api.getPath('ph-json/province.json');
      final raw = res['data'];
      if (raw is List) {
        final list = raw
            .whereType<Map>()
            .map((e) => Province.fromJson(Map<String, dynamic>.from(e)))
            .toList()
          ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        _provincesCache = list;
        return list;
      }
    } catch (_) {}
    return const [];
  }

  Future<List<City>> citiesFor(String provinceCode) async {
    if (provinceCode.isEmpty) return const [];
    final cached = _cityByProvince[provinceCode];
    if (cached != null) return cached;
    try {
      _allCitiesCache ??= await _loadAllCities();
      final list = _allCitiesCache!
          .where((c) => c.provinceCode == provinceCode)
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _cityByProvince[provinceCode] = list;
      return list;
    } catch (_) {}
    return const [];
  }

  Future<List<City>> _loadAllCities() async {
    final res = await api.getPath('ph-json/city.json');
    final raw = res['data'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => City.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return const [];
  }

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
      // Backend returns either a bare array or ApiClient wraps it as {'data': [...]}.
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
      final res = await api.post('updateLeadNote',
          body: {'id': id.toString(), 'note': note});
      return res['success'] == true || res['status'] == 'success';
    } catch (_) {
      return false;
    }
  }

  Future<bool> delete(int id) async {
    try {
      final res =
          await api.post('deleteLead', body: {'id': id.toString()});
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

// ─────────────────────────────────────────────────────────────────────────────
// Document-extraction parsing — Dart ports of the web's customer.js prefill
// logic so the app fills the BIR form the same way the web app does.
// ─────────────────────────────────────────────────────────────────────────────

ExtractionResult _buildExtraction(Map<String, dynamic> res) {
  String s(dynamic v) => (v ?? '').toString();

  // Stored files — split BIR extraction docs from the (optional) valid-ID entry.
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

  // Valid ID (present when one was scanned): capture its details + document.
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

  // TIN + branch: digits only; first 9 → TIN (xxx-xxx-xxx), the rest → branch.
  final tinDigits = (s(res['TIN_BranchCode']) + s(res['BranchCode']))
      .replaceAll(RegExp(r'[^0-9]'), '');
  final tin9 = tinDigits.length >= 9 ? tinDigits.substring(0, 9) : tinDigits;
  final branch = tinDigits.length > 9 ? tinDigits.substring(9) : '';
  final tinFormatted = tin9.length == 9
      ? '${tin9.substring(0, 3)}-${tin9.substring(3, 6)}-${tin9.substring(6, 9)}'
      : _groupBy3(tin9);

  // Owner name → first/middle/last (or promote a corporate name to company).
  var company = s(res['BusinessName']);
  final owner = _parseOwnerName(s(res['OwnerName']));
  var first = owner.first, middle = owner.middle, last = owner.last;
  if (owner.isCorporate) {
    if (company.trim().isEmpty) company = owner.full;
    first = '';
    middle = '';
    last = '';
  }

  // Prefer the valid-ID holder's name for the owner when a valid ID was scanned
  // (matches the web registration/extraction form).
  if (hasValidId) {
    var idFirst = s(res['IDHolderFirstName']).trim();
    var idMiddle = s(res['IDHolderMiddleName']).trim();
    var idLast = s(res['IDHolderLastName']).trim();
    if (idFirst.isEmpty && idMiddle.isEmpty && idLast.isEmpty && vIdName.isNotEmpty) {
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

/// Port of normalizeRegistrationType() + the raw-text VAT scan in customer.js.
/// Returns true (VAT), false (Non-VAT), or null when undetermined.
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

/// Port of parseOwnerName() in customer.js — turns a raw BIR "name of taxpayer"
/// string into first/middle/last, rejecting OCR garbage and detecting
/// corporate names.
({String full, String first, String middle, String last, bool isCorporate})
    _parseOwnerName(String raw) {
  const empty =
      (full: '', first: '', middle: '', last: '', isCorporate: false);

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
    'REPUBLIKA', 'PILIPINAS', 'KAGAWARAN', 'PANANALAPI', 'KAWANIHAN',
    'KAWANEAN', 'RENTAS', 'INTERNAS', 'KAGAWARA', 'EUITWAS', 'PANANALA',
    'PANANALAP', 'PANAN', 'RERIO', 'RNAS',
    'BUREAU OF INTERNAL REVENUE', 'CERTIFICATE OF REGISTRATION',
    'BIR FORM', 'ASSISTANT REVENUE', 'DISTRICT OFFICER',
    'TIN ISSUANCE', 'NAME OF TAXPAYER', 'OF TAXPAYER',
    'TIN & BRANCH', 'BRANCH CODE',
    'REGISTERED NAME', 'DATE OF REGISTRATION', 'BUSINESS ADDRESS',
    'RDO CODE', 'LINE OF BUSINESS', 'REGISTRATION TYPE',
    'DATE OCN GENERATED', 'OCN GENERATED',
    'PAYMENT MODE', 'QUARTERLY', 'MONTHLY', 'ANNUALLY',
    'SEMI-ANNUALLY', 'HEAD OFFICE', 'REGISTERING OFFICE',
    'TRADE NAME', 'BUSINESS INFORMATION',
  ];
  for (final g in garbage) {
    if (cleaned.contains(g)) return empty;
  }
  if (RegExp(r'^(N/A|NA|NONE|NULL|-+)$').hasMatch(cleaned)) return empty;

  final corpSuffixes = RegExp(
      r'\b(INC\.?|INCS?|ING\.?|CORP\.?|CORPORATION|LLC|LTD\.?|LIMITED|ENTERPRISES?|OPC|FOUNDATION|ASSOCIATION)\b');
  final bizKeywords = RegExp(
      r'\b(CAFE|RESTAURANT|TRADING|SHOP|STORE|MART|SALON|BAKERY|PHARMACY|HARDWARE|HOTEL|RESORT|CONSTRUCTION|SERVICES|SUPPLY|MANUFACTURING|FOOD|BEVERAGES|REALTY|PROPERTIES|DEVELOPMENT|LOGISTICS|TRANSPORT|FREIGHT|PRINTING|MARKETING)\b');
  var isCorporate = corpSuffixes.hasMatch(cleaned);
  if (!isCorporate) {
    final bizHits = bizKeywords.allMatches(cleaned).length;
    final wordCount =
        cleaned.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).length;
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
      .replaceAll(
          RegExp(r'\s+(' + months + r')\s+\d{1,2},?\s+\d{4}\s*$'), '')
      .trim();
  cleaned =
      cleaned.replaceAll(RegExp(r'\s+(' + months + r')\s*$'), '').trim();
  if (cleaned.isEmpty) return empty;

  var first = '', middle = '', last = '';
  if (cleaned.contains(',')) {
    // "LASTNAME, FIRSTNAME MIDDLENAME"
    final commaParts = cleaned.split(',');
    last = commaParts[0].trim();
    final rest = commaParts.sublist(1).join(',').trim();
    final restWords = rest.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (restWords.length >= 2) {
      first = restWords.sublist(0, restWords.length - 1).join(' ');
      middle = restWords.last;
    } else if (restWords.length == 1) {
      first = restWords[0];
    }
    cleaned = [first, middle, last].where((e) => e.isNotEmpty).join(' ');
  } else {
    // "FIRSTNAME MIDDLENAME LASTNAME"
    final words = cleaned.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
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
  return (full: cleaned, first: first, middle: middle, last: last, isCorporate: false);
}
