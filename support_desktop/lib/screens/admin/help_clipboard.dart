import 'dart:io';

import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';

class HelpClipboardData {
  const HelpClipboardData({
    this.text,
    this.html,
    this.image,
    this.files = const [],
  });

  final String? text;
  final String? html;
  final Uint8List? image;
  final List<String> files;
}

const helpImageExtensions = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};

bool helpIsImagePath(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0) return false;
  return helpImageExtensions.contains(path.substring(dot + 1).toLowerCase());
}

String helpPathFromUri(String raw) {
  var s = raw.trim();
  if (s.startsWith('file://')) {
    try {
      return Uri.parse(s).toFilePath();
    } catch (_) {
      s = Uri.decodeFull(s.substring(7));
    }
  }
  return s;
}

class HelpClipboard {
  HelpClipboard._();

  static Future<HelpClipboardData> read() async {
    String? text;
    try {
      text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } catch (_) {}
    final files = <String>[];
    try {
      for (final f in await Pasteboard.files()) {
        final p = helpPathFromUri(f);
        if (p.isNotEmpty && helpIsImagePath(p) && File(p).existsSync()) files.add(p);
      }
    } catch (_) {}
    if (files.isNotEmpty) return HelpClipboardData(text: text, files: files);
    String? html;
    if (Platform.isWindows) {
      try {
        html = _cfHtmlFragment(await Pasteboard.html);
      } catch (_) {}
    }
    final hasText = (text ?? '').trim().isNotEmpty;
    if (hasText) return HelpClipboardData(text: text, html: html);
    Uint8List? image;
    try {
      image = await Pasteboard.image;
    } catch (_) {}
    if (image != null && image.isNotEmpty) return HelpClipboardData(image: image);
    return HelpClipboardData(text: text, html: html);
  }

  static String? _cfHtmlFragment(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final start = raw.indexOf('<!--StartFragment-->');
    final end = raw.indexOf('<!--EndFragment-->');
    if (start >= 0 && end > start) {
      return raw.substring(start + '<!--StartFragment-->'.length, end);
    }
    final lt = raw.indexOf('<');
    return lt >= 0 ? raw.substring(lt) : raw;
  }
}
