import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'session_store.dart';

/// (host, port) pair — the resolved location of the POS `tinkerpro`
/// MariaDB on the LAN.
class PosTarget {
  const PosTarget(this.host, this.port);
  final String host;
  final int port;

  @override
  String toString() => '$host:$port';
}

/// Resolves the host *and port* running the POS `tinkerpro` MariaDB.
///
/// Older builds assumed MariaDB was always on 3306, which broke at
/// merchants who run it on an alt port (e.g., XAMPP side-by-side with
/// another MySQL on 3307, or MAMP on 8889). This version walks a list
/// of likely MariaDB ports and tries each open `host:port` against the
/// caller's [validate] callback (which actually authenticates + reads
/// `shop`). A TCP-open port is not enough to commit a target — many
/// things can listen on these ports; only a `(host, port)` where
/// validate succeeds is committed and cached.
///
/// Two production topologies, both must work:
///   • **Single-terminal:** customer_app and the DB live on the same
///     Windows box. Resolves instantly via `127.0.0.1`.
///   • **Multi-terminal:** several Windows POS boxes share one
///     "server" terminal's DB over the shop LAN. The customer_app on
///     a non-server box has to find that server by IP — that's what
///     the /24 sweep is for.
///
/// Waterfall (per port, in order):
///   1. Cached `(host, port)` (last validated one) from [SessionStore].
///   2. Caller-supplied hint hosts.
///   3. Standard candidates: `127.0.0.1`, `localhost`, `10.0.2.2`.
///   4. /24 LAN sweep across every up IPv4 NetworkInterface.
class PosDiscoveryService {
  PosDiscoveryService(this._store);

  final SessionStore _store;

  static const Duration _candidateTimeout = Duration(milliseconds: 700);
  static const Duration _sweepTimeout = Duration(milliseconds: 350);
  static const int _maxConcurrentProbes = 32;

  Future<PosTarget?> findTarget({
    required Future<bool> Function(String host, int port) validate,
    required List<int> ports,
    List<String> hintHosts = const [],
    void Function(String status)? onProgress,
  }) async {
    if (ports.isEmpty) return null;
    final triedTcp = <String>{}; // entries are "host:port"

    Future<PosTarget?> tryCombo(String host, int port) async {
      final clean = host.trim();
      if (clean.isEmpty) return null;
      final key = '$clean:$port';
      if (triedTcp.contains(key)) return null;
      triedTcp.add(key);
      onProgress?.call('Trying $clean:$port…');
      if (!await _probe(clean, port, _candidateTimeout)) return null;
      onProgress?.call('Authenticating with $clean:$port…');
      if (!await validate(clean, port)) return null;
      onProgress?.call('Connected to POS at $clean:$port');
      return PosTarget(clean, port);
    }

    // 1. Cached (host, port) — try just that combo, on the cached port.
    final cachedHost = _store.posHost;
    final cachedPort = _store.posPort;
    if (cachedHost != null && cachedHost.isNotEmpty && cachedPort != null) {
      final win = await tryCombo(cachedHost, cachedPort);
      if (win != null) return win;
      await _store.setPosTarget(null, null);
    }

    // 2. Sweep per port — fast path is port 3306 working everywhere,
    // but we honor whatever port list the caller passed in.
    final standards = const ['127.0.0.1', 'localhost', '10.0.2.2'];
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      includeLinkLocal: false,
      type: InternetAddressType.IPv4,
    );

    for (final port in ports) {
      // 2a. hints + standards on this port.
      final candidates = <String>[...hintHosts, ...standards];
      for (final h in candidates) {
        final win = await tryCombo(h, port);
        if (win != null) {
          await _store.setPosTarget(win.host, win.port);
          return win;
        }
      }

      // 2b. /24 LAN sweep on this port.
      onProgress?.call('Scanning network for MariaDB on port $port…');
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final subnet = _slash24(addr.address);
          if (subnet == null) continue;
          final winner = await _sweepSubnet(
            subnet,
            port,
            skip: {addr.address},
            triedTcp: triedTcp,
            validate: (h) async {
              onProgress?.call('Authenticating with $h:$port…');
              return validate(h, port);
            },
            onProgress: onProgress,
          );
          if (winner != null) {
            await _store.setPosTarget(winner, port);
            return PosTarget(winner, port);
          }
        }
      }
    }
    return null;
  }

  Future<bool> _probe(String host, int port, Duration timeout) async {
    Socket? sock;
    try {
      sock = await Socket.connect(host, port, timeout: timeout);
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
    String prefix,
    int port, {
    required Set<String> skip,
    required Set<String> triedTcp,
    required Future<bool> Function(String host) validate,
    void Function(String status)? onProgress,
  }) async {
    final hosts = <String>[];
    for (var i = 1; i <= 254; i++) {
      final h = '$prefix$i';
      if (skip.contains(h)) continue;
      if (triedTcp.contains('$h:$port')) continue;
      hosts.add(h);
    }
    if (hosts.isEmpty) return null;

    final openHosts = StreamController<String>(sync: false);
    var inFlight = 0;
    var idx = 0;
    var producerDone = false;
    var consumerWon = false;

    void launchNext() {
      if (consumerWon) return;
      while (inFlight < _maxConcurrentProbes && idx < hosts.length) {
        final host = hosts[idx++];
        triedTcp.add('$host:$port');
        inFlight++;
        unawaited(_probe(host, port, _sweepTimeout).then((open) {
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
      onProgress?.call('Found $host:$port open — authenticating…');
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
      debugPrint('[pos-discovery] no validated POS on $prefix*:$port');
    }
    return winner;
  }
}
