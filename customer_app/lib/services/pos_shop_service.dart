import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'pos_discovery_service.dart';
import 'session_store.dart';
import 'ticket_service.dart' show ShopInfo;

/// Reads `shop_name` + `vat_reg` from the local POS over HTTP by
/// hitting the small PHP shim deployed alongside each POS box's
/// XAMPP install (see customer_app/deploy/tps-shop.php).
///
/// Why HTTP instead of MySQL:
/// • Dart's mysql1 package desyncs against MariaDB 10.4+ ("Got
///   packets out of order") and the alternative `mysql_client`
///   package mishandles empty-password handshakes. PHP's `pdo_mysql`
///   has neither bug, so we pay one small HTTP round-trip and let
///   PHP do the database talk.
/// • XAMPP ships Apache+PHP+MariaDB together, so any POS install
///   capable of running the database is already capable of serving
///   the shim. No extra runtime to install.
///
/// Discovery walks cached → hint hosts → standard candidates → /24
/// LAN sweep, validating each with an HTTP GET to /tps-shop.php and
/// parsing the JSON response. Only validated hosts get cached.
///
/// Runtime overrides (compile-time dart-defines):
///   TPS_POS_HOST     pin to a specific host, skip discovery
///   TPS_POS_HTTP_PORT  default 80
///   TPS_POS_PATH       default /tps-shop.php
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
      _lastError ??= 'No POS shim on this network accepted our request.';
      return null;
    }
    _resolvedHost = winner;
    return _lastResult;
  }

  /// HTTP GET → tps-shop.php on a single candidate host. Returns the
  /// ShopInfo on success, null on any failure (caught + recorded into
  /// [_lastError] so the form can surface the cause).
  Future<ShopInfo?> _readShop(String host, String cleanTin) async {
    HttpClient? client;
    try {
      final uri = Uri(
        scheme: 'http',
        host: host,
        port: _config.httpPort,
        path: _config.path,
      );
      client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 3)
        ..idleTimeout = const Duration(seconds: 3);
      final req = await client.getUrl(uri);
      // Some XAMPP defaults reject HTTP/1.0 — be explicit about 1.1.
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      req.headers.set(HttpHeaders.userAgentHeader, 'TpCustomerApp/1.0');
      final res = await req.close().timeout(const Duration(seconds: 4));
      if (res.statusCode != HttpStatus.ok) {
        _lastError = '$host: HTTP ${res.statusCode}';
        return null;
      }
      final body = await res.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        _lastError = '$host: shim response was not a JSON object';
        return null;
      }
      // Require the marker so we don't mistake some other JSON-spitting
      // service on this LAN for our shim.
      if (decoded['tps_shop'] != true) {
        _lastError = '$host: response did not look like our POS shim';
        return null;
      }
      final vatReg = int.tryParse((decoded['vat_reg'] ?? 0).toString()) ?? 0;
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
    } catch (e) {
      _lastError = '$host: $e';
      debugPrint('[pos-shop] read failed at $host: $e');
      return null;
    } finally {
      try {
        client?.close(force: true);
      } catch (_) {}
    }
  }
}

class PosDbConfig {
  const PosDbConfig({
    required this.host,
    required this.httpPort,
    required this.path,
  });

  /// Optional override for the POS host. Empty = run discovery.
  final String host;

  /// Apache port hosting the shim. Defaults to 80.
  final int httpPort;

  /// Path to the shim under the document root.
  final String path;

  factory PosDbConfig.fromDefines() => const PosDbConfig(
        host: String.fromEnvironment('TPS_POS_HOST', defaultValue: ''),
        httpPort: int.fromEnvironment('TPS_POS_HTTP_PORT', defaultValue: 80),
        path: String.fromEnvironment('TPS_POS_PATH', defaultValue: '/tps-shop.php'),
      );
}
