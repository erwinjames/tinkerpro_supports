import 'dart:io' show Platform;

/// Centralised platform predicates. The employee app ships as both a POS
/// desktop build (Windows/Linux) and a mobile APK (Android). A few features
/// are desktop-only — notably the bundled RustDesk remote-desktop flow,
/// which has no mobile counterpart — so they gate on [kIsDesktopPlatform].
///
/// The mobile build instead onboards by scanning a sync QR shown by the
/// already-configured desktop app (see QrSyncScreen / SyncMobileScreen).
final bool kIsDesktopPlatform =
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

final bool kIsMobilePlatform = Platform.isAndroid || Platform.isIOS;
