// API layer for the License Key feature. All endpoints live on `api.php`:
//   * getLicenseKey      GET   page,limit            → {data:[...], total}
//   * add_license_key    POST  license_key, license_type, expiration_date
//   * update_license_key POST  license_id, ... , store_*
//   * delete_license_key POST  id                    → {success, message}

import '../api_client.dart';
import '../models/license_models.dart';

class LicenseResult {
  LicenseResult({required this.ok, this.message});
  final bool ok;
  final String? message;
}

class LicenseService {
  LicenseService(this._api);
  final ApiClient _api;

  /// Fetch a page of license keys. The backend paginates; we pull a large
  /// page so the mobile list is simple (pull-to-refresh, no infinite scroll
  /// yet). Returns an empty list on any failure so the UI still renders.
  Future<List<LicenseKey>> list({int page = 1, int limit = 100}) async {
    try {
      final res = await _api.get('getLicenseKey', {
        'page': '$page',
        'limit': '$limit',
      });
      final raw = res['data'];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => LicenseKey.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  /// Create a key. [trial] true → an [expirationDate] (YYYY-MM-DD) is
  /// required by the backend; permanent keys ignore it.
  Future<LicenseResult> add({
    required String licenseKey,
    required bool trial,
    String? expirationDate,
  }) async {
    return _mutate('add_license_key', {
      'license_key': licenseKey.trim(),
      'license_type': trial ? '1' : '0',
      if (trial && expirationDate != null) 'expiration_date': expirationDate,
    });
  }

  Future<LicenseResult> update({
    required int id,
    required String licenseKey,
    required bool trial,
    String? expirationDate,
    String storeName = '',
    String storeAddress = '',
    String storeEmail = '',
  }) async {
    return _mutate('update_license_key', {
      'license_id': '$id',
      'license_key': licenseKey.trim(),
      'license_type': trial ? '1' : '0',
      if (trial && expirationDate != null) 'expiration_date': expirationDate,
      'store_name': storeName,
      'store_address': storeAddress,
      'store_email': storeEmail,
    });
  }

  Future<LicenseResult> delete(int id) =>
      _mutate('delete_license_key', {'id': '$id'});

  Future<LicenseResult> _mutate(
      String action, Map<String, String> body) async {
    try {
      final res = await _api.post(action, body: body);
      final ok = res['success'] == true || res['status'] == 'success';
      return LicenseResult(ok: ok, message: res['message']?.toString());
    } catch (e) {
      return LicenseResult(ok: false, message: 'Network error');
    }
  }
}
