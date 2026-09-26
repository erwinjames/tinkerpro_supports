import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class ChatAppLauncher {
  ChatAppLauncher._();

  static final ChatAppLauncher instance = ChatAppLauncher._();

  static final Uri _openUri = Uri.parse('tinkerprochat://open');

  static const _kInstalledKey = 'chat_app_installed';

  static const MethodChannel _channel =
      MethodChannel('com.tinkerpro.support/chat_app');

  bool? _installed;

  static Future<bool> installedFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      return prefs.getBool(_kInstalledKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kInstalledKey, _installed ?? false);
    } catch (_) {}
  }

  bool get installed => _installed ?? false;

  @visibleForTesting
  set debugInstalled(bool? value) => _installed = value;

  bool get _supported => Platform.isAndroid || Platform.isIOS;

  Future<bool> refresh() async {
    if (!_supported) return _installed = false;
    try {
      _installed = await canLaunchUrl(_openUri);
    } catch (_) {
      _installed = false;
    }
    await _persist();
    return _installed!;
  }

  Future<bool> trustsInstalledChatApp() async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('isTrusted');
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  Uri _uriFor({int? conversationId, String? handoff}) {
    final query = <String, String>{
      if (conversationId != null) 'conversation': '$conversationId',
      if (handoff != null && handoff.isNotEmpty) 'handoff': handoff,
    };
    if (query.isEmpty) return _openUri;
    return Uri(
      scheme: 'tinkerprochat',
      host: conversationId == null ? 'open' : 'chat',
      queryParameters: query,
    );
  }

  Future<bool> open({int? conversationId, String? handoff}) async {
    if (!_supported) return false;

    if (handoff != null && handoff.isNotEmpty) {
      final sent = await _openTrusted(_uriFor(
        conversationId: conversationId,
        handoff: handoff,
      ));
      if (sent) return true;
    }

    return _openAny(_uriFor(conversationId: conversationId));
  }

  Future<bool> _openTrusted(Uri uri) async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('open', {
        'uri': uri.toString(),
      });
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _openAny(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        _installed = false;
        await _persist();
      }
      return ok;
    } catch (_) {
      _installed = false;
      await _persist();
      return false;
    }
  }
}
