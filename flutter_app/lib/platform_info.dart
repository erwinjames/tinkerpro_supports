import 'dart:io' show Platform;

final bool kIsDesktopPlatform =
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

final bool kIsMobilePlatform = Platform.isAndroid || Platform.isIOS;
