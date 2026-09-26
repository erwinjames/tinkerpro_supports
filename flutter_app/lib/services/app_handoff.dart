import 'dart:io' show Platform;

import '../api_client.dart';

class AppHandoff {
  AppHandoff._();

  static Future<String?> mint(
    ApiClient api, {
    String target = 'chat',
  }) async {
    if (!api.hasSession) return null;
    try {
      final res = await api.post(
        'createAppHandoff',
        body: {
          'target': target,
          'source': 'support',
          'device_name': Platform.operatingSystem,
        },
      ).timeout(const Duration(seconds: 8));
      if (res['success'] != true) return null;
      final token = (res['token'] ?? '').toString();
      return token.isEmpty ? null : token;
    } catch (_) {
      return null;
    }
  }
}
