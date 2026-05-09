import 'package:flutter/foundation.dart';
import 'package:mysql_client_patched/mysql_client.dart';

import 'pos_discovery_service.dart';
import 'session_store.dart';
import 'ticket_service.dart' show ShopInfo;

/// Reads `shop_name` + `vat_reg` directly from each POS's MariaDB on
/// the LAN — no PHP shim, no manual config.
///
/// We use a vendored fork of `mysql_client` (third_party/
/// mysql_client_patched) because both available pure-Dart MySQL
/// clients have show-stopper bugs against current MariaDB:
///   • upstream `mysql_client` mishandles empty-password handshakes
///     (sends a 20-byte SHA1(empty) blob instead of a zero-length
///     authResponse) — fatal for XAMPP / TinkerPro POS installs
///     which ship with empty root password.
///   • `mysql1` desyncs with "Got packets out of order" against
///     MariaDB 10.4+ — fatal for the same installs.
/// The fork patches the empty-password path; mysql_client's parser
/// doesn't have the packet-ordering desync, so we get end-to-end
/// auto-discovery + credential check + database read.
///
/// Discovery walks cached → hint hosts → standard candidates → /24
/// LAN sweep, validating each by attempting a real MariaDB
/// handshake + a SELECT against `tinkerpro.shop`. Only hosts where
/// every step succeeds get cached. Any host that has port 3306 open
/// but isn't actually our POS gets skipped automatically.
///
/// Compile-time overrides:
///   TPS_POS_HOST     pin to a specific host, skip discovery
///   TPS_POS_PORT     default 3306
///   TPS_POS_USER     default root
///   TPS_POS_PASS     default empty (XAMPP / TinkerPro POS default)
///   TPS_POS_DB       default tinkerpro
class PosShopService {
  PosShopService({
    required SessionStore store,
    PosDbConfig? config,
    PosDiscoveryService? discovery,
  })  : _config = config ?? PosDbConfig.fromDefines(),
        _discovery = discovery ?? PosDiscoveryService(store);

  final PosDbConfig _config;
  final PosDiscoveryService _discovery;
  String? _resolvedHost;
  String? _lastError;
  ShopInfo? _lastResult;

  PosDbConfig get config => _config;
  String? get resolvedHost => _resolvedHost;
  String? get lastError => _lastError;

  Future<ShopInfo?> getShopInfo({
    String? tin,
    List<String> hintHosts = const [],
    void Function(String status)? onProgress,
  }) async {
    _lastError = null;
    _lastResult = null;
    final cleanTin = (tin ?? '').replaceAll(RegExp(r'[^0-9]'), '');

    if (_config.host.isNotEmpty) {
      onProgress?.call('Using configured POS host ${_config.host}…');
      final pinned = await _readShop(_config.host, cleanTin);
      if (pinned != null) {
        _resolvedHost = _config.host;
        return pinned;
      }
      return null;
    }

    final winner = await _discovery.findHost(
      hintHosts: hintHosts,
      onProgress: onProgress,
      validate: (host) async {
        final result = await _readShop(host, cleanTin);
        if (result != null) {
          _lastResult = result;
          return true;
        }
        return false;
      },
    );
    if (winner == null) {
      _lastError ??= 'No POS on this network accepted our connection.';
      return null;
    }
    _resolvedHost = winner;
    return _lastResult;
  }

  /// Connect to one candidate, run the shop SELECT, return the row.
  /// Returns null on any failure (caught + recorded into [_lastError]
  /// so the form can surface the cause to the user). The discovery
  /// service interprets that as "this host isn't our POS, try the
  /// next" — so a host whose MariaDB rejects us, or a host with port
  /// 3306 open but no `tinkerpro` database, gets skipped silently.
  Future<ShopInfo?> _readShop(String host, String cleanTin) async {
    MySQLConnection? conn;
    try {
      conn = await MySQLConnection.createConnection(
        host: host,
        port: _config.port,
        userName: _config.user,
        password: _config.pass,
        databaseName: _config.db,
        secure: false,
      );
      // Tight timeout — discovery already TCP-probed, so anything
      // slow at this point is more likely to be a wrong-port service
      // than an actual POS that's far away.
      await conn.connect(timeoutMs: 4000);

      // One single text-protocol query. Shop is a one-row config
      // table per POS install, so the first row is the right row.
      final res = await conn.execute(
        'SELECT shop_name, vat_reg FROM shop ORDER BY id ASC LIMIT 1',
      );
      if (res.numOfRows == 0) {
        _lastError = '$host: shop table empty';
        return null;
      }

      final row = res.rows.first.assoc();
      final vatReg = int.tryParse((row['vat_reg'] ?? '0').toString()) ?? 0;
      return ShopInfo(
        // Defer business-name display to the customer record from
        // the support backend — the POS shop_name is typically the
        // POS provider's brand ("Tinkerpro") rather than the
        // merchant's own business.
        businessName: '',
        vatReg: vatReg,
        vatLabel: vatReg == 1 ? 'VAT' : 'Non-VAT',
        tin: cleanTin,
        email: '',
        fullName: '',
      );
    } catch (e) {
      _lastError = '$host: $e';
      debugPrint('[pos-shop] read failed at $host: $e');
      return null;
    } finally {
      try {
        await conn?.close();
      } catch (_) {}
    }
  }
}

class PosDbConfig {
  const PosDbConfig({
    required this.host,
    required this.port,
    required this.user,
    required this.pass,
    required this.db,
  });

  final String host;
  final int port;
  final String user;
  final String pass;
  final String db;

  factory PosDbConfig.fromDefines() => const PosDbConfig(
        host: String.fromEnvironment('TPS_POS_HOST', defaultValue: ''),
        port: int.fromEnvironment('TPS_POS_PORT', defaultValue: 3306),
        user: String.fromEnvironment('TPS_POS_USER', defaultValue: 'root'),
        pass: String.fromEnvironment('TPS_POS_PASS', defaultValue: ''),
        db: String.fromEnvironment('TPS_POS_DB', defaultValue: 'tinkerpro'),
      );
}
