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

  Future<LicenseResult> add({
    required String licenseKey,
    required bool trial,
    required String machineType,
    String? expirationDate,
  }) async {
    return _mutate('add_license_key', {
      'license_key': licenseKey.trim(),
      'machine_type': machineType,
      'license_type': trial ? '1' : '0',
      if (trial && expirationDate != null) 'expiration_date': expirationDate,
    });
  }

  Future<LicenseResult> update({
    required int id,
    required String licenseKey,
    required bool trial,
    required String machineType,
    String? expirationDate,
    String storeName = '',
    String storeAddress = '',
    String storeEmail = '',
  }) async {
    return _mutate('update_license_key', {
      'license_id': '$id',
      'license_key': licenseKey.trim(),
      'machine_type': machineType,
      'license_type': trial ? '1' : '0',
      if (trial && expirationDate != null) 'expiration_date': expirationDate,
      'store_name': storeName,
      'store_address': storeAddress,
      'store_email': storeEmail,
    });
  }

  Future<LicenseResult> delete(int id) =>
      _mutate('delete_license_key', {'id': '$id'});

  Future<LicenseResult> _mutate(String action, Map<String, String> body) async {
    try {
      final res = await _api.post(action, body: body);
      final ok = res['success'] == true || res['status'] == 'success';
      return LicenseResult(ok: ok, message: res['message']?.toString());
    } catch (e) {
      return LicenseResult(ok: false, message: 'Network error');
    }
  }
}
