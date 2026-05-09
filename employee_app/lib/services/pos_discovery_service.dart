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

/// One row in the diagnostic scan result — a LAN host that has at
/// least one of the probed MariaDB ports open. The optional device
/// name comes from reverse DNS or NetBIOS lookup so a tech can tell
/// "which workstation is 192.168.1.42 — is that the front register?"
class PosScanRow {
  PosScanRow({
    required this.host,
    required this.port,
    this.deviceName,
  });
  final String host;
  final int port;
  final String? deviceName;

  @override
  String toString() {
    final name = deviceName == null ? '' : ' ($deviceName)';
    return '$host:$port$name';
  }
}

/// What an exhaustive [PosDiscoveryService.scanLan] call found.
/// Surfaces *all* open targets so the diagnostic UI can list them and
/// let the tech pick one manually — even if discovery's per-port
/// validate failed (e.g., MariaDB rejected our credentials and we
/// stopped probing).
class PosScanReport {
  PosScanReport({
    required this.interfaces,
    required this.openTargets,
  });
  final List<PosScanInterface> interfaces;
  final List<PosScanRow> openTargets;
}

class PosScanInterface {
  PosScanInterface({
    required this.name,
    required this.address,
    required this.subnet,
  });
  final String name;
  final String address;
  final String subnet; // /24 prefix being swept, e.g. "192.168.1."
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

  /// Persist a manually-picked target (from the diagnostic panel)
  /// so the next ticket-form open hits it directly.
  Future<void> cacheTarget(String host, int port) =>
      _store.setPosTarget(host, port);

  /// Exhaustive sweep used by the diagnostic panel. Unlike
  /// [findTarget], this does NOT short-circuit on the first open
  /// target and does NOT attempt validate — it just reports every
  /// LAN host that has any probed port open, with a best-effort
  /// device name resolved via reverse DNS / NetBIOS.
  ///
  /// Caller can then show the list and let the tech tap one to pin.
  Future<PosScanReport> scanLan({
    required List<int> ports,
    void Function(String status)? onProgress,
    Duration probeTimeout = const Duration(milliseconds: 350),
    int maxConcurrent = 64,
  }) async {
    final interfaces = <PosScanInterface>[];
    final openTargets = <PosScanRow>[];
    if (ports.isEmpty) {
      return PosScanReport(interfaces: interfaces, openTargets: openTargets);
    }

    final ifaces = await NetworkInterface.list(
      includeLoopback: false,
      includeLinkLocal: false,
      type: InternetAddressType.IPv4,
    );

    final targets = <({String host, int port})>[];
    final seenHosts = <String>{};
    for (final iface in ifaces) {
      for (final addr in iface.addresses) {
        final subnet = _slash24(addr.address);
        if (subnet == null) continue;
        interfaces.add(PosScanInterface(
          name: iface.name,
          address: addr.address,
          subnet: '$subnet*',
        ));
        for (var i = 1; i <= 254; i++) {
          final h = '$subnet$i';
          if (h == addr.address) continue;
          if (seenHosts.contains(h)) continue;
          seenHosts.add(h);
          for (final p in ports) {
            targets.add((host: h, port: p));
          }
        }
      }
    }

    if (targets.isEmpty) {
      return PosScanReport(interfaces: interfaces, openTargets: openTargets);
    }

    onProgress?.call(
        'Scanning ${seenHosts.length} hosts × ${ports.length} ports…');

    var idx = 0;
    var done = 0;
    final completer = Completer<void>();
    var inFlight = 0;

    void launch() {
      while (inFlight < maxConcurrent && idx < targets.length) {
        final t = targets[idx++];
        inFlight++;
        unawaited(_probe(t.host, t.port, probeTimeout).then((open) {
          inFlight--;
          done++;
          if (open) {
            openTargets.add(PosScanRow(host: t.host, port: t.port));
            onProgress?.call(
                'Found ${t.host}:${t.port} ($done/${targets.length} probed)');
          }
          if (done >= targets.length) {
            if (!completer.isCompleted) completer.complete();
            return;
          }
          launch();
        }));
      }
    }

    launch();
    await completer.future;

    // Resolve device names in parallel for whatever turned up.
    onProgress?.call('Resolving device names…');
    final names = await Future.wait(
      openTargets.map((row) => _resolveDeviceName(row.host)),
    );
    final resolved = <PosScanRow>[];
    for (var i = 0; i < openTargets.length; i++) {
      resolved.add(PosScanRow(
        host: openTargets[i].host,
        port: openTargets[i].port,
        deviceName: names[i],
      ));
    }
    resolved.sort((a, b) {
      final h = _compareIp(a.host, b.host);
      return h != 0 ? h : a.port.compareTo(b.port);
    });

    return PosScanReport(interfaces: interfaces, openTargets: resolved);
  }

  /// Best-effort hostname for a LAN IP. Tries DNS PTR first, then
  /// falls back to Windows `nbtstat -A` to recover the NetBIOS
  /// workstation name (the `<00> UNIQUE` row). Returns null if both
  /// silent-fail — the diagnostic UI just shows the IP in that case.
  Future<String?> _resolveDeviceName(String ip) async {
    try {
      final addr = await InternetAddress(ip).reverse();
      final host = addr.host;
      if (host.isNotEmpty && host != ip) return host;
    } catch (_) {}
    if (Platform.isWindows) {
      try {
        final result = await Process.run('nbtstat', ['-A', ip])
            .timeout(const Duration(seconds: 2));
        final out = result.stdout.toString();
        final match = RegExp(r'^\s+(\S+)\s+<00>\s+UNIQUE', multiLine: true)
            .firstMatch(out);
        if (match != null) return match.group(1);
      } catch (_) {}
    }
    return null;
  }

  int _compareIp(String a, String b) {
    final ap = a.split('.');
    final bp = b.split('.');
    for (var i = 0; i < 4 && i < ap.length && i < bp.length; i++) {
      final ai = int.tryParse(ap[i]) ?? 0;
      final bi = int.tryParse(bp[i]) ?? 0;
      if (ai != bi) return ai.compareTo(bi);
    }
    return a.compareTo(b);
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
