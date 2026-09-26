import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../api_client.dart';
import '../models/dashboard_models.dart';
import '../models/models.dart';
import 'bir_register_logic.dart';
import 'reminder_service.dart';

class AuthService {
  AuthService(this.api);
  final ApiClient api;

  Future<UserSession> login(
    String email,
    String password, {
    bool remember = true,
  }) async {
    await api.clearSession();

    final res = await api.post(
      'login',
      body: {
        'email': email.trim(),
        'password': password,
        'remember': remember ? '1' : '0',
      },
    );
    if (res['success'] != true) {
      throw Exception(res['message']?.toString() ?? 'Login failed');
    }
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
    await api.setUserRole(session.role);
    await api.setPermissions(session.permissions);
    await syncSession();
    return session;
  }

  Future<UserSession> adoptSession(Map<String, dynamic> res) async {
    final session = UserSession.fromJson(res);
    if (session.userId <= 0) {
      throw Exception(
        'Sign-in succeeded but server did not return a user id. '
        'Please contact support.',
      );
    }
    await api.setUserId(session.userId);
    if (session.username.isNotEmpty && session.username != '—') {
      await api.setUsername(session.username);
    }
    await api.setUserRole(session.role);
    await api.setPermissions(session.permissions);
    await syncSession();
    return session;
  }

  Future<String> googleClientId() async {
    try {
      final res = await api
          .get('mobileAuthConfig')
          .timeout(const Duration(seconds: 8));
      return (res['google_client_id'] ?? '').toString();
    } catch (_) {
      return '';
    }
  }

  Future<UserSession> loginWithGoogle(
    String idToken, {
    bool remember = true,
  }) async {
    await api.clearSession();
    final res = await api.post(
      'mobileOAuthLogin',
      body: {
        'provider': 'google',
        'id_token': idToken,
        'remember': remember ? '1' : '0',
      },
    );
    if (res['success'] != true) {
      throw Exception(res['message']?.toString() ?? 'Google sign-in failed');
    }
    final session = UserSession.fromJson(res);
    if (session.userId <= 0) {
      throw Exception(
        'Sign-in succeeded but server did not return a user id. '
        'Please contact support.',
      );
    }
    await api.setUserId(session.userId);
    if (session.username.isNotEmpty && session.username != '—') {
      await api.setUsername(session.username);
    }
    await api.setUserRole(session.role);
    await api.setPermissions(session.permissions);
    await syncSession();
    return session;
  }

  Future<({bool changed, bool signedOut, String? message})>
  syncSession() async {
    try {
      final res = await api
          .get('getMobileAuthSession')
          .timeout(const Duration(seconds: 8));
      if (res['success'] != true) {
        final message = res['message']?.toString().trim();
        return (
          changed: false,
          signedOut: true,
          message: message == null || message.isEmpty ? null : message,
        );
      }
      if (res['permissions'] == null) {
        return (changed: false, signedOut: false, message: null);
      }
      final session = UserSession.fromJson(Map<String, dynamic>.from(res));
      var changed = false;
      if (session.role.isNotEmpty && session.role != api.userRole) {
        await api.setUserRole(session.role);
        changed = true;
      }
      final fresh = session.permissions;
      final before = api.permissions;
      if (before.length != fresh.length ||
          fresh.entries.any((e) => before[e.key] != e.value)) {
        await api.setPermissions(fresh);
        changed = true;
      }
      final rawHidden = res['hidden_features'];
      final hidden = rawHidden is List
          ? rawHidden.map((e) => e.toString()).toSet()
          : <String>{};
      final hiddenBefore = api.hiddenFeatures;
      if (hidden.length != hiddenBefore.length ||
          !hidden.containsAll(hiddenBefore)) {
        await api.setHiddenFeatures(hidden);
        changed = true;
      }
      return (changed: changed, signedOut: false, message: null);
    } catch (_) {
      return (changed: false, signedOut: false, message: null);
    }
  }

  Future<bool> refreshPermissions() async => (await syncSession()).changed;

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
    ReminderService.badge.value = 0;
    ReminderService.latest.value = null;
    await ReminderWidget.publishSignedOut();
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

  Future<DashboardLive> live() async {
    final res = await api.get('dashboardLive', {
      '_': DateTime.now().millisecondsSinceEpoch.toString(),
    });
    final data = res['data'];
    if (res['status'] != 'success' || data is! Map) {
      throw Exception(res['message']?.toString() ?? 'Dashboard unavailable');
    }
    return DashboardLive.fromJson(Map<String, dynamic>.from(data));
  }

  Future<LicenseRevenue?> licenseRevenue({DateTime? serverNow}) async {
    try {
      final res = await api.get('dashboardRevenue');
      if (res['status'] != 'success' || res['data'] is! Map) return null;
      final d = Map<String, dynamic>.from(res['data'] as Map);
      double num0(dynamic v) =>
          v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
      int int0(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
      final price = d['default_price'];
      return LicenseRevenue(
        available: d['available'] == true,
        total: num0(d['total']),
        month: num0(d['month']),
        today: num0(d['today']),
        paidCount: int0(d['paid_count']),
        monthCount: int0(d['month_count']),
        pendingCount: int0(d['pending_count']),
        pendingValue: num0(d['pending_value']),
        defaultPrice: price == null ? null : num0(price),
        complete: true,
      );
    } catch (_) {
      return null;
    }
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
      final row = _unwrapRow(res);
      if (row != null) return row;
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

  Future<({bool duplicate, String company, String tin})> checkTinDuplicate(
    String tin,
    String branchCode,
  ) async {
    try {
      final res = await api.get('checkTinDuplicate', {
        'tin': tin,
        if (branchCode.isNotEmpty) 'branch_code': branchCode,
      });
      final existing = res['existing'];
      final company = (existing is Map ? (existing['company_name'] ?? '') : '')
          .toString();
      final existingTin = (existing is Map ? (existing['tin'] ?? '') : '')
          .toString();
      return (
        duplicate: res['duplicate'] == true,
        company: company,
        tin: existingTin,
      );
    } catch (_) {
      return (duplicate: false, company: '', tin: '');
    }
  }

  Future<({bool duplicate, String company})> checkSnDuplicate(String sn) async {
    try {
      final res = await api.get('checkSnDuplicate', {'sn': sn});
      final existing = res['existing'];
      final company = (existing is Map ? (existing['company_name'] ?? '') : '')
          .toString();
      return (duplicate: res['duplicate'] == true, company: company);
    } catch (_) {
      return (duplicate: false, company: '');
    }
  }

  Future<List<LicenseSerialSuggestion>> searchLicenseSerials(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    try {
      final res = await api.get('searchLicenseSerials', {'q': q, 'limit': '10'});
      final results = res['results'];
      if (results is! List) return const [];
      return [
        for (final row in results)
          if (row is Map)
            LicenseSerialSuggestion.fromJson(Map<String, dynamic>.from(row)),
      ]..removeWhere((s) => s.serial.isEmpty);
    } catch (_) {
      return const [];
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

  ExtractionResult toExtractionResult(Map<String, dynamic> res) =>
      _buildExtraction(res);

  static Map<String, dynamic>? _jsonMap(http.Response r) {
    try {
      final d = jsonDecode(r.body.trim());
      if (d is Map) return Map<String, dynamic>.from(d);
    } catch (_) {}
    return null;
  }

  Future<MultiDocExtractOutcome> extractDocuments({
    required List<String> paths,
    String? validIdPath,
    String? manualName,
    String? manualBirthdate,
    String mode = 'accurate',
    void Function()? onUploaded,
    void Function(Map<String, dynamic> progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final manual = manualName != null;
    Map<String, dynamic>? first;
    try {
      final res = await api
          .rawPostMultipart(
            api.pathUri('client-multidoc-extract.php'),
            fields: {
              'extract_mode': mode,
              if (!manual && validIdPath != null) 'valid_id_type': '',
              if (manual) 'valid_id_manual': '1',
              if (manual) 'valid_id_manual_name': manualName,
              if (manual) 'valid_id_manual_birthdate': manualBirthdate ?? '',
            },
            files: [
              for (final p in paths) (field: 'files[]', path: p),
              if (!manual && validIdPath != null)
                (field: 'valid_id_file', path: validIdPath),
            ],
          )
          .timeout(const Duration(seconds: 600));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        return const MultiDocExtractOutcome.failed(
          'Server failed to process the uploaded documents.',
        );
      }
      first = _jsonMap(res);
    } on TimeoutException {
      return const MultiDocExtractOutcome.failed(
        'Extraction timed out. Try fewer documents or use Fast mode.',
      );
    } on UploadTimeoutException {
      return const MultiDocExtractOutcome.failed(
        'Extraction timed out. Try fewer documents or use Fast mode.',
      );
    } catch (_) {
      return const MultiDocExtractOutcome.failed(
        'Server failed to process the uploaded documents.',
      );
    }
    if (first == null) {
      return const MultiDocExtractOutcome.failed(
        'Server failed to process the uploaded documents.',
      );
    }
    onUploaded?.call();
    final jobId = (first['job_id'] ?? '').toString();
    if (first['async'] != true || jobId.isEmpty) {
      return MultiDocExtractOutcome.done(first);
    }

    const maxWait = Duration(milliseconds: 900000);
    const maxErrors = 5;
    final startedAt = DateTime.now();
    var consecutiveErrors = 0;

    Duration nextInterval() {
      final age = DateTime.now().difference(startedAt).inMilliseconds;
      if (age < 20000) return const Duration(milliseconds: 900);
      if (age < 90000) return const Duration(milliseconds: 1800);
      return const Duration(milliseconds: 3000);
    }

    while (true) {
      if (isCancelled?.call() == true) {
        return const MultiDocExtractOutcome.failed('Extraction cancelled.');
      }
      try {
        final r = await api
            .rawGet(
              api.pathUri('client-multidoc-extract-status.php', {
                'job': jobId,
                '_': DateTime.now().millisecondsSinceEpoch.toString(),
              }),
            )
            .timeout(const Duration(seconds: 30));
        if (r.statusCode == 403) {
          return const MultiDocExtractOutcome.failed(
            'Lost contact with the server while extracting.',
          );
        }
        final res = (r.statusCode >= 200 && r.statusCode < 300)
            ? _jsonMap(r)
            : null;
        if (res == null) throw const FormatException('bad status response');
        consecutiveErrors = 0;
        final status = (res['status'] ?? '').toString();
        if (status == 'running') {
          onProgress?.call(res);
          if (DateTime.now().difference(startedAt) > maxWait) {
            return const MultiDocExtractOutcome.failed(
              'Extraction is taking too long. Try fewer documents or use Fast mode.',
            );
          }
          await Future<void>.delayed(nextInterval());
          continue;
        }
        if (status == 'error') {
          final err = (res['error'] ?? '').toString();
          return MultiDocExtractOutcome.failed(
            err.isEmpty ? 'Extraction failed on the server.' : err,
          );
        }
        return MultiDocExtractOutcome.done(res);
      } catch (_) {
        consecutiveErrors++;
        if (consecutiveErrors >= maxErrors) {
          return const MultiDocExtractOutcome.failed(
            'Lost contact with the server while extracting.',
          );
        }
        await Future<void>.delayed(nextInterval());
      }
    }
  }

  Map<String, List<SoftwareVersionInfo>>? _catalogCache;

  Future<Map<String, List<SoftwareVersionInfo>>> softwareCatalog({
    bool refresh = false,
  }) async {
    if (!refresh && _catalogCache != null) return _catalogCache!;
    try {
      final res = await api.get('software.catalog');
      if (res['status'] == 'success') {
        _catalogCache = BirLogic.parseCatalog(res['data']);
        return _catalogCache!;
      }
    } catch (_) {}
    return _catalogCache ?? const {};
  }

  List<PsicItem>? _psicCache;

  Future<List<PsicItem>> psicList() async {
    if (_psicCache != null && _psicCache!.isNotEmpty) return _psicCache!;
    try {
      final r = await api.rawGet(api.pathUri('json-reason.js'), json: false);
      if (r.statusCode >= 200 && r.statusCode < 300) {
        final list = BirLogic.parsePsic(utf8.decode(r.bodyBytes));
        if (list.isNotEmpty) _psicCache = list;
        return list;
      }
    } catch (_) {}
    return const [];
  }

  Future<({Map<String, dynamic>? stored, String? error})> uploadAttachment(
    String filePath,
  ) async {
    try {
      final r = await api
          .rawPostMultipart(
            api.pathUri('client-upload-attachment.php'),
            files: [(field: 'file', path: filePath)],
          )
          .timeout(const Duration(seconds: 60));
      final res = _jsonMap(r);
      if (res == null || r.statusCode >= 400) {
        return (stored: null, error: null);
      }
      if (res['error'] != null) {
        return (stored: null, error: res['error'].toString());
      }
      final stored = res['stored_file'];
      if (stored is Map) {
        return (stored: Map<String, dynamic>.from(stored), error: null);
      }
    } catch (_) {}
    return (stored: null, error: null);
  }

  Future<({Map<String, dynamic>? res, bool failed})> addDocument(
    String filePath,
  ) async {
    try {
      final r = await api
          .rawPostMultipart(
            api.pathUri('client-add-document.php'),
            files: [(field: 'file', path: filePath)],
          )
          .timeout(const Duration(seconds: 120));
      final res = _jsonMap(r);
      if (res == null || r.statusCode >= 400) return (res: null, failed: true);
      return (res: res, failed: false);
    } catch (_) {
      return (res: null, failed: true);
    }
  }

  Future<({bool ok, String message, int customerId, String? networkError})>
  addCustomer(Map<String, String> fields) async {
    try {
      final r = await api.rawPostForm(
        api.pathUri('api.php', {'action': 'addcustomer'}),
        fields,
      );
      final res = _jsonMap(r);
      if (res == null) {
        return (
          ok: false,
          message: '',
          customerId: 0,
          networkError: r.statusCode >= 400
              ? 'HTTP ${r.statusCode}'
              : 'Invalid server response',
        );
      }
      return (
        ok: res['status'] == 'success',
        message: (res['message'] ?? '').toString(),
        customerId: _asIntOrNull(res['customer_id']) ?? 0,
        networkError: null,
      );
    } catch (e) {
      return (ok: false, message: '', customerId: 0, networkError: '$e');
    }
  }

  Future<({String? path, String filename, String? error})> exportClientCsv(
    Map<String, String> fields,
  ) async {
    const fallbackName = 'ACCREG_POS_STANDALONE.csv';
    try {
      final r = await api.rawPostForm(api.pathUri('client-export-csv.php'), {
        ...fields,
        'response_mode': 'json',
      });
      if (r.statusCode < 200 || r.statusCode >= 300) {
        return (
          path: null,
          filename: fallbackName,
          error: 'Failed to prepare CSV file.',
        );
      }
      final res = _jsonMap(r);
      if (res == null) {
        return (
          path: null,
          filename: fallbackName,
          error: 'Unexpected export response format.',
        );
      }
      final url = (res['url'] ?? '').toString();
      if (res['success'] != true || url.isEmpty) {
        return (
          path: null,
          filename: fallbackName,
          error: (res['message'] ?? 'Failed to prepare CSV file.').toString(),
        );
      }
      final filename = (res['filename'] ?? '').toString().isEmpty
          ? fallbackName
          : res['filename'].toString();
      final base = api.pathUri(url.split('?').first);
      final query = Map<String, String>.from(Uri.parse(url).queryParameters)
        ..['v'] = DateTime.now().millisecondsSinceEpoch.toString();
      final dl = await api.rawGet(
        base.replace(queryParameters: query),
        json: false,
      );
      if (dl.statusCode < 200 || dl.statusCode >= 300 || dl.bodyBytes.isEmpty) {
        return (
          path: null,
          filename: filename,
          error: 'Failed to download CSV file.',
        );
      }
      io.Directory? dir;
      try {
        dir = await getDownloadsDirectory();
      } catch (_) {}
      dir ??= await getApplicationDocumentsDirectory();
      final safeName = filename.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final file = io.File('${dir.path}${io.Platform.pathSeparator}$safeName');
      await file.writeAsBytes(dl.bodyBytes, flush: true);
      return (path: file.path, filename: filename, error: null);
    } catch (e) {
      return (path: null, filename: fallbackName, error: '$e');
    }
  }

  Future<({Map<String, dynamic>? data, String? error})> extractBirPdf(
    String filePath,
  ) async {
    try {
      final r = await api.rawPostMultipart(
        api.pathUri('pdf-extract-py.php'),
        files: [(field: 'pdf', path: filePath)],
      );
      final res = _jsonMap(r);
      if (res == null || r.statusCode >= 400) {
        return (
          data: null,
          error:
              res?['error']?.toString() ??
              'Failed to process PDF file. Please try again.',
        );
      }
      if (res['error'] != null) {
        return (data: null, error: res['error'].toString());
      }
      return (data: res, error: null);
    } catch (_) {
      return (
        data: null,
        error: 'Failed to process PDF file. Please try again.',
      );
    }
  }

  Future<Map<String, dynamic>?> serialMeta(String sn) async {
    try {
      final res = await api.get('getSerialMeta', {'sn': sn});
      if (res.isNotEmpty) return res;
    } catch (_) {}
    return null;
  }

  List<Province>? _provincesCache;
  List<City>? _allCitiesCache;
  final Map<String, List<City>> _cityByProvince = {};

  Future<List<Province>> provinces() async {
    if (_provincesCache != null) return _provincesCache!;
    try {
      final res = await api.getPath('ph-json/province.json');
      final raw = res['data'];
      if (raw is List) {
        final list =
            raw
                .whereType<Map>()
                .map((e) => Province.fromJson(Map<String, dynamic>.from(e)))
                .toList()
              ..sort(
                (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
              );
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
      final list =
          _allCitiesCache!.where((c) => c.provinceCode == provinceCode).toList()
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );
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

  static List<String> splitSerials(String raw) {
    final out = <String>[];
    for (final part in raw.split(RegExp(r'[/,]'))) {
      final t = part.replaceAll(RegExp(r'\s+'), '');
      if (t.isNotEmpty && !out.contains(t)) out.add(t);
    }
    return out;
  }

  Future<({bool ok, String message})> saveExtractedRegistration({
    required CustomerDetail existing,
    required String companyName,
    required String tin,
    required String rdo,
    required String address,
    required String accNumber,
    required String softwareName,
    required String serialNumber,
    required String firstName,
    required String middleName,
    required String lastName,
    required String pdfFile,
    required String isVat,
  }) async {
    String norm(String v) => v.replaceAll(RegExp(r'\s+'), '');
    final serials = serialNumber
        .split('/')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final entries = <Map<String, dynamic>>[];
    for (final sn in serials) {
      SerialEntry? saved;
      for (final e in existing.serialEntries) {
        if (norm(e.serialNumber) == norm(sn)) {
          saved = e;
          break;
        }
      }
      entries.add(
        SerialEntry(
          serialNumberType: saved?.serialNumberType ?? '',
          serverType: saved?.serverType ?? '',
          serialNumber: sn,
          brand: saved?.brand ?? '',
          model: saved?.model ?? '',
        ).toJson(),
      );
    }
    final fields = <String, String>{
      'customer_id': existing.id.toString(),
      'companyname': companyName,
      'tin': tin,
      'branch_code': existing.branchCode,
      'tin_issuance_date': existing.tinIssuanceDate,
      'rdo': rdo,
      'businessline': existing.businessLine,
      'address': address,
      'min': existing.min,
      'ptu': existing.ptu,
      'pos_date_issued': existing.posDateIssued,
      'invoice_number': existing.invoiceNumber,
      'softwarename': softwareName,
      'acc_number': accNumber,
      'sn': serials.join('/'),
      'firstname': firstName,
      'middlename': middleName,
      'lastname': lastName,
      'email': existing.email,
      'username': existing.username,
      'password': existing.password,
      'is_vat': isVat,
      'province': existing.provinceCode,
      'province_text': existing.provinceName,
      'city': existing.cityCode,
      'city_text': existing.cityName,
      'pdf_file': pdfFile,
      'step2': '1',
      'serial_entries': jsonEncode(entries),
    };
    try {
      final res = await api.post('updateCustomer', body: fields);
      final ok = res['status'] == 'success' || res['success'] == true;
      if (ok) return (ok: true, message: 'Customer Updated Successfully');
      return (
        ok: false,
        message:
            'Customer Not Updated: ${(res['message'] ?? 'Unknown error').toString()}',
      );
    } catch (e) {
      return (ok: false, message: 'An error occurred: $e');
    }
  }

  Future<({List<Map<String, dynamic>>? items, String? error})>
  extractPtuDocuments({
    required int customerId,
    required String serialNumber,
    required List<String> paths,
  }) async {
    if (paths.isEmpty) {
      return (
        items: null,
        error: 'Failed to process PDF file. Please try again.',
      );
    }
    try {
      final r = await api.rawPostMultipart(
        api.pathUri('step3-pdf-text.php'),
        fields: {'cus_id': customerId.toString(), 'serialnum': serialNumber},
        files: [for (final p in paths) (field: 'pdf[]', path: p)],
      );
      if (r.statusCode < 200 || r.statusCode >= 300) {
        return (
          items: null,
          error: 'Failed to process PDF file. Please try again.',
        );
      }
      Object? decoded;
      try {
        decoded = jsonDecode(r.body.trim());
      } catch (_) {
        return (items: null, error: 'Invalid server response');
      }
      if (decoded is Map && decoded['error'] != null) {
        return (items: null, error: decoded['error'].toString());
      }
      final list = decoded is List ? decoded : [decoded];
      return (
        items: list
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
        error: null,
      );
    } catch (_) {
      return (
        items: null,
        error: 'Failed to process PDF file. Please try again.',
      );
    }
  }

  Future<({bool ok, String message})> step3UpdateCustomerData({
    required int customerId,
    required String posDateIssued,
    required String ptu,
    required String min,
    required String filename,
    required String machineDetails,
  }) async {
    try {
      final res = await api.post(
        'step3UpdateCustomerData',
        body: {
          'customerId': customerId.toString(),
          'pos_date_issued': posDateIssued,
          'ptu': ptu,
          'min': min,
          'filename': filename,
          'machineDetails': machineDetails,
        },
      );
      final ok = res['status'] == 'success' || res['success'] == true;
      if (ok) return (ok: true, message: 'Successfully Added');
      return (
        ok: false,
        message:
            'Failed to update customer: ${(res['message'] ?? 'Unknown error').toString()}',
      );
    } catch (e) {
      return (ok: false, message: 'Failed to update customer: $e');
    }
  }

  Future<({bool ok, String message})> advancePtuManual({
    required int customerId,
    required String ptu,
    required String min,
    String accNum = '',
    String posDateIssued = '',
  }) async {
    try {
      final res = await api.post(
        'advancePtuManual',
        body: {
          'customerId': customerId.toString(),
          'ptu': ptu,
          'min': min,
          'acc_num': accNum,
          'pos_date_issued': posDateIssued,
        },
      );
      if (res['status'] == 'success') {
        return (ok: true, message: 'Registration completed successfully.');
      }
      return (
        ok: false,
        message: (res['message'] ?? 'Failed to complete registration.')
            .toString(),
      );
    } catch (e) {
      return (ok: false, message: 'Failed to complete registration: $e');
    }
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
