import 'dart:io' show Platform;

import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api_client.dart';

/// An available app update described by the published manifest
/// (`downloads/app-version.json`).
class AppUpdate {
  AppUpdate({
    required this.version,
    required this.build,
    required this.apkUrl,
    required this.changelog,
  });

  final String version;
  final int build;
  final String apkUrl;
  final List<String> changelog;
}

/// Checks the published version manifest and decides whether to prompt the user
/// to update. Android-only (the APK is the mobile distribution channel).
class UpdateService {
  UpdateService(this._api);
  final ApiClient _api;

  static const _kSkippedBuildKey = 'update_skipped_build';

  /// Returns update info when a newer APK is published than the running build
  /// AND the user hasn't already dismissed that build. Null otherwise (incl.
  /// iOS, network errors, or malformed manifest) so callers can ignore it.
  Future<AppUpdate?> check() async {
    try {
      if (!Platform.isAndroid) return null;

      final info = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(info.buildNumber) ?? 0;

      // Cache-bust so a freshly-published manifest isn't masked by a proxy.
      final res = await _api.getPath(
        'downloads/app-version.json',
        {'t': currentBuild.toString()},
      );
      final build = _asInt(res['build']);
      if (build <= currentBuild) return null;

      final prefs = await SharedPreferences.getInstance();
      final skipped = prefs.getInt(_kSkippedBuildKey) ?? 0;
      if (build <= skipped) return null;

      final rawLog = res['changelog'];
      final changelog = rawLog is List
          ? rawLog.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
          : <String>[];

      return AppUpdate(
        version: (res['version'] ?? '').toString(),
        build: build,
        apkUrl: (res['apk_url'] ?? '').toString(),
        changelog: changelog,
      );
    } catch (_) {
      return null;
    }
  }

  /// Remember that the user dismissed [build] so we don't nag until a newer
  /// build ships.
  Future<void> snooze(int build) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kSkippedBuildKey, build);
  }

  int _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}
