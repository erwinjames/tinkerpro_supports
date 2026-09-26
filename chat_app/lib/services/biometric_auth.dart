import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../api_client.dart';

class BiometricUnavailable implements Exception {
  BiometricUnavailable(this.message);
  final String message;

  @override
  String toString() => message;
}

class BiometricAuth {
  BiometricAuth(this._api, {this.appKey = 'chat'});

  final ApiClient _api;
  final String appKey;

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const _kToken = 'biometric_token';
  static const _kDeviceId = 'biometric_device_id';
  static const _kLabel = 'biometric_label';
  static const _kUserId = 'biometric_user_id';

  final LocalAuthentication _localAuth = LocalAuthentication();

  bool get _supportedPlatform => Platform.isAndroid || Platform.isIOS;

  Future<bool> deviceCanScan() async {
    if (!_supportedPlatform) return false;
    try {
      if (!await _localAuth.isDeviceSupported()) return false;
      if (!await _localAuth.canCheckBiometrics) return false;
      final available = await _localAuth.getAvailableBiometrics();
      return available.contains(BiometricType.fingerprint) ||
          available.contains(BiometricType.strong) ||
          available.contains(BiometricType.face);
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isEnabled() async {
    if (!_supportedPlatform) return false;
    try {
      final token = await _storage.read(key: _kToken);
      return token != null && token.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<String> enrolledLabel() async {
    try {
      return (await _storage.read(key: _kLabel)) ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<int?> enrolledUserId() async {
    try {
      final raw = await _storage.read(key: _kUserId);
      return raw == null ? null : int.tryParse(raw);
    } catch (_) {
      return null;
    }
  }

  Future<bool> isEnabledForCurrentUser() async {
    if (!await isEnabled()) return false;
    final enrolled = await enrolledUserId();
    final current = _api.userId;
    if (enrolled == null || current == null) return false;
    return enrolled == current;
  }

  Future<String> _deviceId() async {
    var id = await _storage.read(key: _kDeviceId);
    if (id != null && id.isNotEmpty) return id;
    final rand = Random.secure();
    id = List<int>.generate(16, (_) => rand.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    await _storage.write(key: _kDeviceId, value: id);
    return id;
  }

  Future<bool> _prompt(String reason) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } on PlatformException catch (e) {
      throw BiometricUnavailable(_platformMessage(e));
    }
  }

  String _platformMessage(PlatformException e) {
    switch (e.code) {
      case 'NotAvailable':
        return 'This device cannot scan fingerprints.';
      case 'NotEnrolled':
        return 'No fingerprint is enrolled on this device. Add one in your phone settings first.';
      case 'LockedOut':
      case 'PermanentlyLockedOut':
        return 'Too many failed attempts. Unlock your phone and try again.';
      default:
        return e.message ?? 'Fingerprint sign-in is not available right now.';
    }
  }

  Future<bool> enable({String label = ''}) async {
    if (!await deviceCanScan()) {
      throw BiometricUnavailable('This device cannot scan fingerprints.');
    }
    if (!await _prompt('Confirm your fingerprint to turn on fingerprint sign-in')) {
      return false;
    }

    await _revokeStored();
    final deviceId = await _deviceId();
    final res = await _api.post('registerBiometricDevice', body: {
      'device_id': deviceId,
      'app': appKey,
      'platform': Platform.operatingSystem,
      'label': label,
    });
    if (res['success'] != true) {
      throw BiometricUnavailable(
        res['message']?.toString() ?? 'Could not turn on fingerprint sign-in.',
      );
    }

    await _storage.write(key: _kToken, value: (res['token'] ?? '').toString());
    await _storage.write(
      key: _kLabel,
      value: label.isNotEmpty ? label : (_api.username ?? ''),
    );
    await _storage.write(key: _kUserId, value: '${_api.userId ?? 0}');
    return true;
  }

  Future<void> disable() async {
    await _revokeStored();
    await forget();
  }

  Future<void> _revokeStored() async {
    String? token;
    try {
      token = await _storage.read(key: _kToken);
    } catch (_) {}
    if (token == null || token.isEmpty) return;
    try {
      await _api.post('revokeBiometricDevice', body: {'token': token});
    } catch (_) {}
  }

  Future<void> forget() async {
    try {
      await _storage.delete(key: _kToken);
      await _storage.delete(key: _kLabel);
      await _storage.delete(key: _kUserId);
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> signIn({bool remember = true}) async {
    final token = await _storage.read(key: _kToken);
    if (token == null || token.isEmpty) return null;
    if (!await deviceCanScan()) {
      throw BiometricUnavailable('This device cannot scan fingerprints.');
    }
    if (!await _prompt('Scan your fingerprint to sign in')) return null;

    final deviceId = await _deviceId();
    await _api.clearSession();
    final res = await _api.post('biometricLogin', body: {
      'token': token,
      'device_id': deviceId,
      'remember': remember ? '1' : '0',
    });
    if (res['success'] != true) {
      if (res['expired'] == true) await forget();
      throw BiometricUnavailable(
        res['message']?.toString() ?? 'Fingerprint sign-in failed.',
      );
    }
    return res;
  }
}
