import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'session_store.dart';

/// Resolves the host running the POS shop database.
///
/// We don't speak MySQL directly from the Flutter client — the Dart
/// `mysql1` package desyncs against MariaDB 10.4+ ("Got packets out
/// of order"), which is the protocol shipped by every recent XAMPP
/// install. Instead, each POS box hosts a tiny PHP shim
/// (`tps-shop.php`) on its local Apache that returns the shop info
/// as JSON. This service finds the host running that shim.
///
/// Two production topologies, both must work:
///   • **Single-terminal:** customer_app and the DB live on the same
///     Windows box. Resolves instantly via `127.0.0.1`.
///   • **Multi-terminal:** several Windows POS boxes share one
///     "server" terminal's DB over the shop LAN. The customer_app on
///     a non-server box has to find that server by IP — that's what
///     the /24 sweep is for.
///
/// Waterfall:
///   1. Cached host (last validated one) from [SessionStore].
///   2. Caller-supplied hint hosts.
///   3. Standard candidates: `127.0.0.1`, `localhost`, `10.0.2.2`.
///   4. /24 LAN sweep across every up IPv4 NetworkInterface.
///
/// A TCP-open `:80` is not enough to commit a host — many things
/// listen on 80 (routers, printers, NAS). The caller's [validate]
/// callback hits `/tps-shop.php` and confirms the JSON response is
/// shaped like ours. Only validated hosts get cached.
class PosDiscoveryService {
  PosDiscoveryService(this._store);

  final SessionStore _store;

  static const int _port = 80;
  static const Duration _candidateTimeout = Duration(milliseconds: 600);
  static const Duration _sweepTimeout = Duration(milliseconds: 350);
  static const int _maxConcurrentProbes = 32;

  Future<String?> findHost({
    required Future<bool> Function(String host) validate,
    List<String> hintHosts = const [],
    void Function(String status)? onProgress,
  }) async {
    final triedTcp = <String>{};

    Future<String?> tryHost(String host) async {
      final clean = host.trim();
      if (clean.isEmpty || triedTcp.contains(clean)) return null;
      triedTcp.add(clean);
      onProgress?.call('Trying $clean…');
      if (!await _probe(clean, _candidateTimeout)) return null;
      onProgress?.call('Checking $clean for POS shop info…');
      if (!await validate(clean)) return null;
      onProgress?.call('Connected to POS at $clean');
      return clean;
    }

    final cached = _store.posHost;
    if (cached != null && cached.isNotEmpty) {
      final ok = await tryHost(cached);
      if (ok != null) return ok;
      await _store.setPosHost(null);
    }

    final candidates = <String>[
      ...hintHosts,
      '127.0.0.1',
      'localhost',
      '10.0.2.2', // Android emulator → host machine
    ];
    for (final h in candidates) {
      final ok = await tryHost(h);
      if (ok != null) {
        await _store.setPosHost(ok);
        return ok;
      }
    }

    onProgress?.call('Scanning shop network for POS server…');
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      includeLinkLocal: false,
      type: InternetAddressType.IPv4,
    );
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        final subnet = _slash24(addr.address);
        if (subnet == null) continue;
        final winner = await _sweepSubnet(
          subnet,
          skip: {addr.address, ...triedTcp},
          validate: (h) async {
            triedTcp.add(h);
            onProgress?.call('Checking $h for POS shop info…');
            return validate(h);
          },
          onProgress: onProgress,
        );
        if (winner != null) {
          await _store.setPosHost(winner);
          return winner;
        }
      }
    }
    return null;
  }

  Future<bool> _probe(String host, Duration timeout) async {
    Socket? sock;
    try {
      sock = await Socket.connect(host, _port, timeout: timeout);
      return true;
    } catch (_) {
      return false;
    } finally {
      try {
        sock?.destroy();
      } catch (_) {}
    }
  }

  String? _slash24(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    for (final p in parts) {
      if (int.tryParse(p) == null) return null;
    }
    return '${parts[0]}.${parts[1]}.${parts[2]}.';
  }

  Future<String?> _sweepSubnet(
    String prefix, {
    required Set<String> skip,
    required Future<bool> Function(String host) validate,
    void Function(String status)? onProgress,
  }) async {
    final hosts = <String>[];
    for (var i = 1; i <= 254; i++) {
      final h = '$prefix$i';
      if (!skip.contains(h)) hosts.add(h);
    }

    final openHosts = StreamController<String>(sync: false);
    var inFlight = 0;
    var idx = 0;
    var producerDone = false;
    var consumerWon = false;

    void launchNext() {
      if (consumerWon) return;
      while (inFlight < _maxConcurrentProbes && idx < hosts.length) {
        final host = hosts[idx++];
        inFlight++;
        unawaited(_probe(host, _sweepTimeout).then((open) {
          inFlight--;
          if (consumerWon) return;
          if (open && !openHosts.isClosed) {
            openHosts.add(host);
          }
          if (idx >= hosts.length && inFlight == 0) {
            producerDone = true;
            if (!openHosts.isClosed) openHosts.close();
            return;
          }
          launchNext();
        }));
      }
      if (idx >= hosts.length && inFlight == 0) {
        producerDone = true;
        if (!openHosts.isClosed) openHosts.close();
      }
    }

    launchNext();

    String? winner;
    await for (final host in openHosts.stream) {
      onProgress?.call('Found $host with port 80 open — checking POS shim…');
      if (await validate(host)) {
        winner = host;
        consumerWon = true;
        if (!openHosts.isClosed) await openHosts.close();
        break;
      }
    }
    if (winner == null && !producerDone) {
      try {
        await openHosts.close();
      } catch (_) {}
    }
    if (winner == null) {
      debugPrint('[pos-discovery] no validated POS on $prefix*');
    }
    return winner;
  }
}
