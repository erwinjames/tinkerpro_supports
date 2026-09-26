import '../api_client.dart';
import '../models/vendor_models.dart';

class VendorAdminService {
  VendorAdminService(this.api);

  final ApiClient api;

  String _error(Object e, String fallback) {
    final msg = e is HttpException ? e.message.trim() : '';
    if (msg.isEmpty || msg.startsWith('HTTP ') || msg.startsWith('Non-JSON')) {
      return fallback;
    }
    return msg;
  }

  Future<VendorPage> list({
    String search = '',
    int page = 1,
    int limit = 25,
  }) async {
    final res = await api.get('vendorAdminList', {
      'search': search.trim(),
      'page': '$page',
      'limit': '$limit',
    });
    if (res['status'] != 'success') {
      throw HttpException(
        res['message']?.toString() ?? 'Could not load the vendors.',
      );
    }
    final raw = res['data'];
    final rows = raw is List
        ? raw
              .whereType<Map>()
              .map((e) => VendorRow.fromJson(Map<String, dynamic>.from(e)))
              .toList()
        : <VendorRow>[];
    final resolvedLimit = int.tryParse('${res['limit']}') ?? limit;
    return VendorPage(
      vendors: rows,
      total: int.tryParse('${res['totalRecords']}') ?? rows.length,
      limit: resolvedLimit < 1 ? limit : resolvedLimit,
    );
  }

  Future<VendorDetail> detail(int vendorId) async {
    final res = await api.get('vendorAdminDetail', {'vendor_id': '$vendorId'});
    if (res['status'] != 'success') {
      throw HttpException(
        res['message']?.toString() ?? 'Could not load the vendor.',
      );
    }
    return VendorDetail.fromJson(res);
  }

  Future<VendorLogPage> logs(
    int vendorId, {
    int limit = 30,
    int offset = 0,
    String search = '',
  }) async {
    final res = await api.get('vendorAdminLogs', {
      'vendor_id': '$vendorId',
      'limit': '$limit',
      'offset': '$offset',
      'search': search.trim(),
    });
    if (res['status'] != 'success') {
      throw HttpException(
        res['message']?.toString() ?? 'Could not load the activity log.',
      );
    }
    final raw = res['logs'];
    return VendorLogPage(
      logs: raw is List
          ? raw
                .whereType<Map>()
                .map(
                  (e) => VendorLogEntry.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList()
          : const [],
      total: int.tryParse('${res['total']}') ?? 0,
      limit: int.tryParse('${res['limit']}') ?? limit,
      offset: int.tryParse('${res['offset']}') ?? offset,
    );
  }

  Future<VendorInvitePage> invites({int limit = 30, int offset = 0}) async {
    final res = await api.get('vendorInviteList', {
      'limit': '$limit',
      'offset': '$offset',
    });
    if (res['status'] != 'success') {
      throw HttpException(
        res['message']?.toString() ?? 'Could not load invites.',
      );
    }
    final raw = res['invites'];
    return VendorInvitePage(
      invites: raw is List
          ? raw
                .whereType<Map>()
                .map((e) => VendorInvite.fromJson(Map<String, dynamic>.from(e)))
                .toList()
          : const [],
      total: int.tryParse('${res['total']}') ?? 0,
    );
  }

  Future<VendorInviteLink?> createInvite({
    String note = '',
    int hours = 48,
    required String licensePrice,
  }) async {
    try {
      final res = await api.post(
        'vendorGenerateInvite',
        body: {
          'note': note.trim(),
          'hours': '$hours',
          'license_price': vendorCleanPrice(licensePrice),
        },
      );
      if (res['status'] != 'success') {
        throw HttpException(
          res['message']?.toString() ?? 'Failed to generate the token.',
        );
      }
      return VendorInviteLink.fromJson(res);
    } on HttpException {
      rethrow;
    } catch (e) {
      throw HttpException(_error(e, 'Network error.'));
    }
  }

  Future<VendorActionResult> revokeInvite(int inviteId) => _mutate(
    'vendorRevokeInvite',
    {'id': '$inviteId'},
    'Could not revoke the invite.',
  );

  Future<VendorActionResult> setLicensePrice(int vendorId, String price) =>
      _mutate('vendorSetLicensePrice', {
        'id': '$vendorId',
        'license_price': vendorCleanPrice(price),
      }, 'Could not update the price.');

  Future<VendorActionResult> setStatus(int vendorId, String status) => _mutate(
    'vendorSetStatus',
    {'id': '$vendorId', 'status': status},
    'Could not update the vendor.',
  );

  Future<VendorNewRegistrations> newRegistrations() async {
    try {
      final res = await api.get('vendorNewRegistrations');
      if (res['success'] != true) return const VendorNewRegistrations();
      return VendorNewRegistrations.fromJson(res);
    } catch (_) {
      return const VendorNewRegistrations();
    }
  }

  Future<bool> ackRegistration(int customerId) async {
    try {
      final res = await api.post(
        'vendorAckRegistration',
        body: {'id': '$customerId'},
      );
      return res['success'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<VendorActionResult> _mutate(
    String action,
    Map<String, String> body,
    String fallback,
  ) async {
    try {
      final res = await api.post(action, body: body);
      final ok = res['status'] == 'success' || res['success'] == true;
      final message = res['message']?.toString();
      return VendorActionResult(
        ok: ok,
        message: (message == null || message.trim().isEmpty)
            ? (ok ? null : fallback)
            : message,
        data: res,
      );
    } catch (e) {
      return VendorActionResult.failure(_error(e, 'Network error.'));
    }
  }
}
