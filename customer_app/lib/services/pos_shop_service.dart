import 'package:flutter/foundation.dart';
import 'package:mysql1/mysql1.dart';

import 'pos_discovery_service.dart';
import 'session_store.dart';
import 'ticket_service.dart' show ShopInfo;

/// Reads `shop_name` + `vat_reg` directly from the local POS MySQL on
/// the LAN. Designed for the offline-friendly path: customer_app on a
/// Windows POS sits on the same wifi as the DB, so the read works
/// even when the shop's internet to the cloud support backend is down.
///
/// Host discovery is delegated to [PosDiscoveryService], but this
/// service supplies the validate callback — discovery's TCP probe is
/// not enough to commit a host because MariaDB may reject our auth
/// (multi-terminal POSes need an `'root'@'%'` grant; without it, a
/// non-server terminal's MariaDB will TCP-listen on `:3306` but
/// reject any source IP that doesn't match a grant row). Only hosts
/// that authenticate AND return a row from `shop` get cached.
///
/// Auth params (user / pass / db / port) come from `--dart-define`s:
///   TPS_POS_PORT  (default: 3306)
///   TPS_POS_USER  (default: root)
///   TPS_POS_PASS  (default: empty — XAMPP / typical TinkerPro POS dev)
///   TPS_POS_DB    (default: tinkerpro)
///   TPS_POS_HOST  (optional: forces a specific host, skipping discovery)
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

  /// Most recent failure reason from a [getShopInfo] attempt, or null
  /// when the last attempt succeeded. Surfaced in the ticket form so
  /// the customer (and us during dev) can see whether discovery ran
  /// dry vs. MySQL handshake refused us vs. the query itself failed.
  String? get lastError => _lastError;

  Future<ShopInfo?> getShopInfo({
    String? tin,
    List<String> hintHosts = const [],
    void Function(String status)? onProgress,
  }) async {
    _lastError = null;
    _lastResult = null;
    final cleanTin = (tin ?? '').replaceAll(RegExp(r'[^0-9]'), '');

    // Explicit pin via TPS_POS_HOST — skip discovery, just try it.
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
      _lastError ??= 'No POS server on this network accepted our connection.';
      return null;
    }
    _resolvedHost = winner;
    return _lastResult;
  }

  /// Connect + query a single candidate host. Returns the ShopInfo on
  /// success, null on any failure (caught + recorded into [_lastError]
  /// so the form can surface it).
  Future<ShopInfo?> _readShop(String host, String cleanTin) async {
    MySqlConnection? conn;
    try {
      final settings = ConnectionSettings(
        host: host,
        port: _config.port,
        user: _config.user,
        password: _config.pass.isEmpty ? null : _config.pass,
        db: _config.db,
        timeout: const Duration(seconds: 4),
      );
      conn = await MySqlConnection.connect(settings);

      Results res;
      bool matchedByTin = false;
      if (cleanTin.isNotEmpty) {
        res = await conn.query(
          "SELECT shop_name, vat_reg FROM shop "
          "WHERE REPLACE(REPLACE(REPLACE(COALESCE(shop_tin, ''), '-', ''), ' ', ''), '_', '') = ? "
          "   OR REPLACE(REPLACE(REPLACE(COALESCE(tin, ''), '-', ''), ' ', ''), '_', '') = ? "
          "LIMIT 1",
          [cleanTin, cleanTin],
        );
        if (res.isNotEmpty) matchedByTin = true;
      } else {
        res = await conn.query(
            'SELECT shop_name, vat_reg FROM shop ORDER BY id ASC LIMIT 1');
      }
      // Single-row config fallback when TIN didn't match — the POS
      // shop table is one row per install, so its vat_reg drives the
      // badge even when the customer's TIN was never written into the
      // shop row.
      if (res.isEmpty && cleanTin.isNotEmpty) {
        res = await conn.query(
            'SELECT shop_name, vat_reg FROM shop ORDER BY id ASC LIMIT 1');
      }
      if (res.isEmpty) {
        _lastError = '$host: shop table empty';
        return null;
      }

      final row = res.first.fields;
      final shopName = (row['shop_name'] ?? '').toString();
      final vatReg = int.tryParse((row['vat_reg'] ?? 0).toString()) ?? 0;
      return ShopInfo(
        // Only adopt the POS shop_name when the row actually matched
        // the customer's TIN; otherwise the single-row fallback would
        // overwrite the customer's company name with the POS provider's
        // own brand.
        businessName: matchedByTin ? shopName : '',
        vatReg: vatReg,
        vatLabel: vatReg == 1 ? 'VAT' : 'Non-VAT',
        tin: cleanTin,
        email: '',
        fullName: '',
      );
    } catch (e, st) {
      _lastError = '$host: $e';
      debugPrint('[pos-shop] read failed at $host: $e');
      debugPrint(st.toString());
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
        // Empty string by default → discovery runs. Set TPS_POS_HOST at
        // build time to pin to a specific box and skip discovery.
        host: String.fromEnvironment('TPS_POS_HOST', defaultValue: ''),
        port: int.fromEnvironment('TPS_POS_PORT', defaultValue: 3306),
        user: String.fromEnvironment('TPS_POS_USER', defaultValue: 'root'),
        pass: String.fromEnvironment('TPS_POS_PASS', defaultValue: ''),
        db: String.fromEnvironment('TPS_POS_DB', defaultValue: 'tinkerpro'),
      );
}
