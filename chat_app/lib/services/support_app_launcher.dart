import 'dart:io' show Platform;

import 'package:url_launcher/url_launcher.dart';

class SupportAppLauncher {
  SupportAppLauncher._();

  static final SupportAppLauncher instance = SupportAppLauncher._();

  static final Uri _probeUri = Uri.parse('tinkerprosupport://open');

  bool? _installed;

  bool get installed => _installed ?? false;

  bool get _supported => Platform.isAndroid || Platform.isIOS;

  Future<bool> refresh() async {
    if (!_supported) return _installed = false;
    try {
      _installed = await canLaunchUrl(_probeUri);
    } catch (_) {
      _installed = false;
    }
    return _installed!;
  }
}
