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
  LanPresence({required this.userId, required this.storeName});

  final int userId;
  final String storeName;

  static const _port = 56789;
  static const _broadcastInterval = Duration(seconds: 3);
  static const _peerTimeout = Duration(seconds: 10);

  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  Timer? _pruneTimer;
  bool _started = false;

  final ValueNotifier<List<LanPeer>> peers = ValueNotifier(const []);
  final Map<int, LanPeer> _byUid = {};

  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _port,
        reuseAddress: true,
        reusePort: true,
      );
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

  Future<void> stop() async {
    _broadcastTimer?.cancel();
    _pruneTimer?.cancel();
    _socket?.close();
    _socket = null;
    _started = false;
    _byUid.clear();
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
    final uid = (msg['uid'] is num) ? (msg['uid'] as num).toInt() : 0;
    if (uid <= 0 || uid == userId) return;
    final store = (msg['store'] ?? '').toString();
    final next = LanPeer(
      userId: uid,
      storeName: store,
      address: dg.address.address,
      lastSeen: DateTime.now(),
    );
    final previous = _byUid[uid];
    _byUid[uid] = next;
    if (previous == null || previous.storeName != next.storeName) {
      _publish();
    }
  }

  void _pruneStale() {
    final now = DateTime.now();
    final before = _byUid.length;
    _byUid.removeWhere((_, p) => now.difference(p.lastSeen) > _peerTimeout);
    if (_byUid.length != before) _publish();
  }

  void _publish() {
    final list = _byUid.values.toList()
      ..sort((a, b) => a.storeName.toLowerCase().compareTo(
            b.storeName.toLowerCase(),
          ));
    peers.value = List.unmodifiable(list);
  }
}

class LanPeer {
  LanPeer({
    required this.userId,
    required this.storeName,
    required this.address,
    required this.lastSeen,
  });

  final int userId;
  final String storeName;
  final String address;
  final DateTime lastSeen;
}
