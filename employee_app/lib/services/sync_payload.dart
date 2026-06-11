import 'dart:convert';

/// Payload encoded in the desktop → mobile sync QR code.
///
/// The desktop employee app is already configured (a store name was typed
/// on first launch, and it knows which TinkerPro server it talks to). It
/// renders this payload as a QR; the mobile APK scans it to adopt the same
/// server URL + store identity, then runs `chat.employeeStart(storeName)`
/// which binds the phone to the very same support conversation (the server
/// looks the store up by name — see findOrCreateEmployeeConversation).
///
/// The trust model matches the existing one: knowing the store name (and
/// server) IS the credential. The QR just transfers it without typing.
class SyncPayload {
  const SyncPayload({
    required this.baseUrl,
    required this.storeName,
    this.helpBaseUrl = '',
    this.tinkerChatApiKey = '',
    this.soketiHost = '',
    this.soketiPort = 0,
    this.soketiKey = '',
    this.soketiTls = false,
    this.soketiPath = '',
  });

  /// TinkerPro API origin the desktop is logged into, e.g.
  /// `https://tinkerpro.example.com/tinkerpro_support`. The mobile app
  /// points its ApiClient here.
  final String baseUrl;

  /// Store identity shown in the support inbox.
  final String storeName;

  /// Optional Help Center origin (defaults baked into the binary if empty).
  final String helpBaseUrl;

  /// Optional tinker-chat tenant key, carried so the phone gets the same
  /// AI-chat tenant without a rebuild.
  final String tinkerChatApiKey;

  /// Resolved Soketi (realtime WebSocket) connection the desktop is already
  /// using successfully. Carried so the phone connects to the exact same
  /// endpoint instead of guessing the compile-time default port (6001),
  /// which production — Soketi fronted on :443 — doesn't expose. Without
  /// this the phone's realtime never connects, so ticket accept/resolve,
  /// chat, and calls only update on a full app restart.
  final String soketiHost;
  final int soketiPort;
  final String soketiKey;
  final bool soketiTls;
  final String soketiPath;

  bool get hasSoketi => soketiHost.isNotEmpty && soketiPort > 0;

  /// Discriminator so a random QR (a product barcode, a URL) is rejected.
  static const _kType = 'tinkerpro.employee.sync';

  Map<String, dynamic> toJson() => {
        't': _kType,
        'v': 1,
        'baseUrl': baseUrl,
        'storeName': storeName,
        if (helpBaseUrl.isNotEmpty) 'helpBaseUrl': helpBaseUrl,
        if (tinkerChatApiKey.isNotEmpty) 'chatKey': tinkerChatApiKey,
        if (hasSoketi) 'wsHost': soketiHost,
        if (hasSoketi) 'wsPort': soketiPort,
        if (hasSoketi) 'wsKey': soketiKey,
        if (hasSoketi) 'wsTls': soketiTls,
        if (hasSoketi && soketiPath.isNotEmpty) 'wsPath': soketiPath,
      };

  String encode() => jsonEncode(toJson());

  /// Parse a scanned QR string. Returns null when [raw] is anything other
  /// than a well-formed TinkerPro employee-sync payload, so the scanner can
  /// keep ignoring unrelated codes until the right one is in frame.
  static SyncPayload? tryDecode(String raw) {
    try {
      final decoded = jsonDecode(raw.trim());
      if (decoded is! Map) return null;
      if (decoded['t'] != _kType) return null;
      final base = (decoded['baseUrl'] ?? '').toString().trim();
      final store = (decoded['storeName'] ?? '').toString().trim();
      if (base.isEmpty || store.isEmpty) return null;
      return SyncPayload(
        baseUrl: base,
        storeName: store,
        helpBaseUrl: (decoded['helpBaseUrl'] ?? '').toString().trim(),
        tinkerChatApiKey: (decoded['chatKey'] ?? '').toString().trim(),
        soketiHost: (decoded['wsHost'] ?? '').toString().trim(),
        soketiPort:
            int.tryParse((decoded['wsPort'] ?? '0').toString()) ?? 0,
        soketiKey: (decoded['wsKey'] ?? '').toString().trim(),
        soketiTls: (decoded['wsTls'] ?? false) == true ||
            (decoded['wsTls'] ?? '').toString() == 'true',
        soketiPath: (decoded['wsPath'] ?? '').toString().trim(),
      );
    } catch (_) {
      return null;
    }
  }
}
