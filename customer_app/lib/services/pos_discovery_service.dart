import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'session_store.dart';

/// Resolves the host running the POS `tinkerpro` MariaDB.
///
/// Two production topologies, both must work:
///   • **Single-terminal:** customer_app and the DB live on the same
///     Windows box. Resolves instantly via `127.0.0.1`.
///   • **Multi-terminal:** several Windows POS boxes share one
///     "server" terminal's DB over the shop LAN. The customer_app on
///     a non-server box has to find that server by IP — that's what
///     the /24 sweep is for.
///
/// Critical detail: a TCP-open `:3306` does NOT mean the host is the
/// right one. MariaDB might reject our auth (e.g., grant only allows
/// `root@localhost`, source IP isn't in the grant tables). So this
/// service doesn't return "the first port-open host" — it asks the
/// caller's [validate] callback to confirm each candidate before
/// committing. Only validated hosts get cached.
///
/// Order tried:
///   1. Cached host from [SessionStore].
///   2. Caller-supplied hint hosts.
///   3. Standard candidates: `127.0.0.1`, `localhost`, `10.0.2.2`.
///   4. /24 LAN sweep across every up IPv4 NetworkInterface.
class PosDiscoveryService {
  PosDiscoveryService(this._store);

  final SessionStore _store;

  static const int _port = 3306;
  static const Duration _candidateTimeout = Duration(milliseconds: 400);
  static const Duration _sweepTimeout = Duration(milliseconds: 250);
  static const int _maxConcurrentProbes = 32;

  /// Walks the discovery waterfall and returns the first host where
  /// [validate] returns true. Hosts whose TCP probe fails are skipped.
  /// Hosts that pass the TCP probe but fail [validate] (e.g., MySQL
  /// auth refused) are also skipped — the next candidate gets tried.
  ///
  /// On success, caches the winning host in [SessionStore]. On total
  /// failure (exhausted all candidates) returns null and clears the
  /// cache.
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
      onProgress?.call('Authenticating with $clean…');
      if (!await validate(clean)) return null;
      onProgress?.call('Connected to POS at $clean');
      return clean;
    }

    // 1. Cached host.
    final cached = _store.posHost;
    if (cached != null && cached.isNotEmpty) {
      final ok = await tryHost(cached);
      if (ok != null) return ok;
      // Cached host didn't work — clear it now so we don't try it on
      // every form open while it's broken.
      await _store.setPosHost(null);
    }

    // 2 + 3. Hints + standard candidates.
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

    // 4. LAN /24 sweep across every up IPv4 interface — multi-terminal
    // POS deployments park the DB on one box and other POS terminals
    // share it over the shop wifi.
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
            onProgress?.call('Authenticating with $h…');
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

  /// "192.168.1.42" → "192.168.1.". Returns null when [ip] isn't a
  /// dotted-quad IPv4.
  String? _slash24(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    for (final p in parts) {
      if (int.tryParse(p) == null) return null;
    }
    return '${parts[0]}.${parts[1]}.${parts[2]}.';
  }

  /// Sweeps a /24 in parallel for hosts with `:3306` open, then
  /// hands each open host to [validate] in arrival order. First
  /// validated host wins; any in-flight probes are abandoned.
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

    // Pipeline: producer fans out TCP probes with bounded concurrency
    // and pushes open hosts onto a queue. Consumer drains the queue
    // sequentially, calling validate on each. First validate=true wins.
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
      onProgress?.call('Found $host with port open — authenticating…');
      if (await validate(host)) {
        winner = host;
        consumerWon = true;
        if (!openHosts.isClosed) await openHosts.close();
        break;
      }
    }
    // Drain anything still buffered if we exit without a winner.
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
