// API layer for the Credentials Storage feature. All endpoints live on
// `api.php` and are gated behind an emailed OTP (a server session flag):
//   * requestCredentialsOTP POST  (none)                 → {success, message}
//   * verifyCredentialsOTP  POST  user_id, otp_code       → {success, message}
//   * getCredentials        GET   (none; needs prior OTP) → {success, data:[...]}
//   * saveCredential        POST  id?, client_name, credentials_text
//   * deleteCredential      POST  id                      → {success, message}

import '../api_client.dart';
import '../models/credential_models.dart';

class CredentialResult {
  CredentialResult({required this.ok, this.message});
  final bool ok;
  final String? message;
}

class CredentialService {
  CredentialService(this._api);
  final ApiClient _api;

  /// Logged-in user id, used for verifyCredentialsOTP.
  int? get currentUserId => _api.userId;

  /// Ask the backend to email an OTP to the logged-in user.
  Future<CredentialResult> requestOtp() => _mutate('requestCredentialsOTP', {});

  /// Verify the emailed OTP. Sets the server-side session flag that unlocks
  /// the credentials endpoints.
  Future<CredentialResult> verifyOtp(String otp) => _mutate(
        'verifyCredentialsOTP',
        {
          'user_id': '${currentUserId ?? ''}',
          'otp_code': otp.trim(),
        },
      );

  /// Fetch all stored credentials. Requires a prior successful [verifyOtp].
  /// Returns an empty list on any failure so the UI still renders.
  Future<List<Credential>> list() async {
    try {
      final res = await _api.get('getCredentials');
      final raw = res['data'];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => Credential.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  /// Create (empty/null [id]) or update a credential.
  Future<CredentialResult> save({
    int? id,
    required String clientName,
    required String credentialsText,
  }) {
    return _mutate('saveCredential', {
      if (id != null) 'id': '$id',
      'client_name': clientName.trim(),
      'credentials_text': credentialsText,
    });
  }

  Future<CredentialResult> delete(int id) =>
      _mutate('deleteCredential', {'id': '$id'});

  Future<CredentialResult> _mutate(
      String action, Map<String, String> body) async {
    try {
      final res = await _api.post(action, body: body);
      final ok = res['success'] == true || res['status'] == 'success';
      return CredentialResult(ok: ok, message: res['message']?.toString());
    } catch (e) {
      return CredentialResult(ok: false, message: 'Network error');
    }
  }
}
