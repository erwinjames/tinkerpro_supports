import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Same-store LAN discovery via UDP broadcast.
///
/// Why UDP and not mDNS / Bonsoir? Pure Dart, zero native deps, works
/// without Avahi/Bonjour installed, and our scope is the same broadcast
/// domain (one store's WiFi) — exactly what UDP broadcast is for.
///
/// Wire protocol — single JSON object per packet:
///
/// ```json
/// {
///   "v": 1,
///   "type": "tinkerpro-emp-presence",
///   "uid": 42,
///   "store": "D.D.S. Grocery",
///   "ts": 1704067200000
/// }
/// ```
///
/// Each peer broadcasts every [_broadcastInterval] and listens on the
/// same port. A peer that hasn't been heard for [_peerTimeout] is
/// pruned. The UI binds to [peers] (a [ValueListenable]) and rebuilds
/// when the set changes.
class LanPresence {
  LanPresence({
    required this.userId,
    required this.storeName,
    required this.deviceId,
    String employeeName = '',
  }) : _employeeName = employeeName;

  final int userId;
  final String storeName;

  /// Stable per-device id (from SessionStore). Peers are identified by
  /// THIS, not [userId], so two terminals sharing the same store identity
  /// still see each other instead of self-filtering.
  final String deviceId;

  /// The operator's name, broadcast so the roster shows people by name.
  /// Mutable — the landing screen updates it when the operator switches.
  String _employeeName;
  String get employeeName => _employeeName;
  set employeeName(String v) => _employeeName = v.trim();

  static const _port = 56789;
  static const _broadcastInterval = Duration(seconds: 3);
  static const _peerTimeout = Duration(seconds: 10);

  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  Timer? _pruneTimer;
  bool _started = false;

  final ValueNotifier<List<LanPeer>> peers = ValueNotifier(const []);
  // Keyed by peer deviceId so same-store colleagues don't overwrite each
  // other (they'd share a userId).
  final Map<String, LanPeer> _byDev = {};

  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      _socket = await _bindSocket();
      _socket!.broadcastEnabled = true;
      _socket!.listen(_onDatagram);
    } catch (e) {
      debugPrint('[lan-presence] bind failed on :$_port — $e. '
          'Discovery disabled for this session.');
      _started = false;
      return;
    }
    _broadcastTimer = Timer.periodic(_broadcastInterval, (_) => _broadcast());
    _pruneTimer = Timer.periodic(
        const Duration(seconds: 2), (_) => _pruneStale());
    _broadcast();
  }

  /// Bind the UDP socket, working around the fact that `SO_REUSEPORT`
  /// (reusePort) does NOT exist on Windows — passing `reusePort: true`
  /// there throws, which used to silently kill LAN discovery on the POS
  /// desktop. So we only request it where it's supported, and fall back
  /// to a plain reuseAddress bind if any platform still rejects it.
  Future<RawDatagramSocket> _bindSocket() async {
    final wantReusePort = !Platform.isWindows;
    try {
      return await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _port,
        reuseAddress: true,
        reusePort: wantReusePort,
      );
    } catch (e) {
      if (!wantReusePort) rethrow;
      debugPrint('[lan-presence] reusePort bind rejected ($e) — '
          'retrying without it.');
      return RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _port,
        reuseAddress: true,
      );
    }
  }

  Future<void> stop() async {
    _broadcastTimer?.cancel();
    _pruneTimer?.cancel();
    _socket?.close();
    _socket = null;
    _started = false;
    _byDev.clear();
    peers.value = const [];
  }

  void _broadcast() {
    final socket = _socket;
    if (socket == null) return;
    final payload = jsonEncode({
      'v': 1,
      'type': 'tinkerpro-emp-presence',
      'uid': userId,
      'store': storeName,
      'name': _employeeName,
      'dev': deviceId,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
    final bytes = utf8.encode(payload);
    try {
      socket.send(bytes, InternetAddress('255.255.255.255'), _port);
    } catch (e) {
      debugPrint('[lan-presence] send failed: $e');
    }
  }

  void _onDatagram(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final dg = _socket?.receive();
    if (dg == null) return;
    Map<String, dynamic>? msg;
    try {
      final decoded = jsonDecode(utf8.decode(dg.data));
      if (decoded is Map<String, dynamic>) msg = decoded;
    } catch (_) {
      return;
    }
    if (msg == null || msg['type'] != 'tinkerpro-emp-presence') return;
    final dev = (msg['dev'] ?? '').toString();
    // Skip our OWN broadcast — matched by device, so a same-store
    // colleague on another terminal (same uid, different device) still
    // shows up in the roster.
    if (dev.isEmpty || dev == deviceId) return;
    final uid = (msg['uid'] is num) ? (msg['uid'] as num).toInt() : 0;
    if (uid <= 0) return;
    final store = (msg['store'] ?? '').toString();
    final name = (msg['name'] ?? '').toString();
    final next = LanPeer(
      userId: uid,
      storeName: store,
      employeeName: name,
      deviceId: dev,
      address: dg.address.address,
      lastSeen: DateTime.now(),
    );
    final previous = _byDev[dev];
    _byDev[dev] = next;
    if (previous == null ||
        previous.employeeName != next.employeeName ||
        previous.storeName != next.storeName) {
      _publish();
    }
  }

  void _pruneStale() {
    final now = DateTime.now();
    final before = _byDev.length;
    _byDev.removeWhere((_, p) => now.difference(p.lastSeen) > _peerTimeout);
    if (_byDev.length != before) _publish();
  }

  void _publish() {
    String key(LanPeer p) =>
        (p.employeeName.isNotEmpty ? p.employeeName : p.storeName).toLowerCase();
    final list = _byDev.values.toList()..sort((a, b) => key(a).compareTo(key(b)));
    peers.value = List.unmodifiable(list);
  }
}

class LanPeer {
  LanPeer({
    required this.userId,
    required this.storeName,
    required this.employeeName,
    required this.deviceId,
    required this.address,
    required this.lastSeen,
  });

  final int userId;
  final String storeName;
  final String employeeName;
  final String deviceId;
  final String address;
  final DateTime lastSeen;

  /// Best label for the roster: the person's name, falling back to the
  /// store name, then the raw device.
  String get displayName => employeeName.isNotEmpty
      ? employeeName
      : (storeName.isNotEmpty ? storeName : 'Device ${deviceId.length > 6 ? deviceId.substring(deviceId.length - 6) : deviceId}');
}
