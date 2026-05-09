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
  ///
  /// Implementation notes:
  /// • One single text-protocol query — no prepared statements, no
  ///   per-call multi-query chain. mysql1 has a known "Got packets out
  ///   of order" bug against MariaDB 10.4+ when the prepared-statement
  ///   protocol path is taken, and the bug also reproduces when a
  ///   second query fires on the same connection. Dropping back to
  ///   plain COM_QUERY with a fresh connection sidesteps both.
  /// • The shop table is a one-row config table per POS install, so
  ///   "ORDER BY id LIMIT 1" returns the right row without needing to
  ///   filter by TIN. We surface businessName='' here — the form's
  ///   merge step then prefers the customer's company_name (from the
  ///   support backend) for display.
  Future<ShopInfo?> _readShop(String host, String cleanTin) async {
    // mysql1 + MariaDB 10.4+ occasionally errors "Got packets out of
    // order" on the first connect/query — usually a stale state or an
    // unexpected EOF packet. Retry once with a brand-new connection
    // before giving up; the second attempt almost always succeeds.
    var attempts = 0;
    while (true) {
      attempts++;
      final result = await _readShopOnce(host, cleanTin);
      if (result != null) return result;
      final err = _lastError ?? '';
      final retryable = attempts < 2 &&
          (err.contains('packets out of order') ||
              err.contains('1156') ||
              err.contains('08S01'));
      if (!retryable) return null;
      debugPrint('[pos-shop] retrying $host after: $err');
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  Future<ShopInfo?> _readShopOnce(String host, String cleanTin) async {
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

      final res = await conn.query(
        'SELECT shop_name, vat_reg FROM shop ORDER BY id ASC LIMIT 1',
      );
      if (res.isEmpty) {
        _lastError = '$host: shop table empty';
        return null;
      }

      final row = res.first.fields;
      final vatReg = int.tryParse((row['vat_reg'] ?? 0).toString()) ?? 0;
      return ShopInfo(
        // Always defer business-name display to the customer record —
        // the POS shop_name is typically the POS provider's brand
        // ("Tinkerpro") rather than the merchant's business.
        businessName: '',
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
