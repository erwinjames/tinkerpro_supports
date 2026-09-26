import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

final Map<String, File?> _bundleFiles = {};

File? bundleAssetFile(String path) {
  if (_bundleFiles.containsKey(path)) return _bundleFiles[path];
  File? found;
  try {
    final dir = File(Platform.resolvedExecutable).parent.path;
    final sep = Platform.pathSeparator;
    final f = File(
      '$dir${sep}data${sep}flutter_assets$sep${path.replaceAll('/', sep)}',
    );
    if (f.existsSync()) found = f;
  } catch (_) {}
  _bundleFiles[path] = found;
  return found;
}

ImageProvider brandAsset(String path) {
  final f = bundleAssetFile(path);
  if (f != null) return FileImage(f);
  return ExactAssetImage(path);
}

Future<ByteData> loadBrandAssetBytes(String path) async {
  final f = bundleAssetFile(path);
  if (f != null) {
    try {
      return ByteData.sublistView(await f.readAsBytes());
    } catch (_) {}
  }
  return rootBundle.load(path);
}
