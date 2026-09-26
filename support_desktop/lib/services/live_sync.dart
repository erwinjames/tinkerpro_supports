import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import '../api_client.dart';

class LiveSync {
  LiveSync._();
  static final LiveSync instance = LiveSync._();

  ApiClient? _api;
  Timer? _timer;
  bool _busy = false;
  final Map<String, String> _stamps = {};
  final Map<String, List<VoidCallback>> _listeners = {};
  void Function(String message)? onSessionLost;

  static const Duration interval = Duration(seconds: 5);
  static const Duration idleInterval = Duration(seconds: 30);
  static const Duration maxBackoff = Duration(minutes: 2);

  int _failures = 0;
  bool _running = false;
  final _rand = Random();

  void start(ApiClient api) {
    _api = api;
    _running = true;
    _schedule(Duration.zero);
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
    _stamps.clear();
    _failures = 0;
  }

  Future<Duration> _nextDelay() async {
    final api = _api;
    if (api != null && api.coolingDown) {
      return api.coolDownLeft +
          Duration(milliseconds: 500 + _rand.nextInt(2000));
    }
    if (_failures > 0) {
      final secs = (5 * pow(2, _failures - 1)).toInt();
      final d = Duration(seconds: secs);
      return d > maxBackoff ? maxBackoff : d;
    }
    var idle = false;
    try {
      idle =
          await windowManager.isMinimized() || !await windowManager.isFocused();
    } catch (_) {}
    final base = idle ? idleInterval : interval;
    return base + Duration(milliseconds: _rand.nextInt(2000) - 1000);
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    if (!_running) return;
    _timer = Timer(delay, () async {
      await pollNow();
      if (!_running) return;
      _schedule(await _nextDelay());
    });
  }

  VoidCallback listen(String key, VoidCallback onChange) {
    final list = _listeners.putIfAbsent(key, () => []);
    list.add(onChange);
    return () => list.remove(onChange);
  }

  void notifyAll() {
    for (final entry in _listeners.entries.toList()) {
      if (entry.key == 'me') continue;
      for (final cb in List.of(entry.value)) {
        cb();
      }
    }
  }

  Future<void> pollNow() async {
    final api = _api;
    if (api == null || _busy || api.coolingDown) return;
    _busy = true;
    try {
      final res = await api
          .get('desktopChangeStamps')
          .timeout(const Duration(seconds: 8));
      if (res['session_lost'] == true) {
        final cb = onSessionLost;
        stop();
        cb?.call(res['message']?.toString() ?? 'Your session has ended.');
        return;
      }
      final raw = res['stamps'];
      if (res['success'] != true || raw is! Map) {
        _failures = (_failures + 1).clamp(0, 6);
        return;
      }
      _failures = 0;
      final changed = <String>[];
      raw.forEach((k, v) {
        final key = k.toString();
        final value = v.toString();
        final before = _stamps[key];
        if (before != null && before != value) changed.add(key);
        _stamps[key] = value;
      });
      for (final key in changed) {
        for (final cb in List.of(_listeners[key] ?? const <VoidCallback>[])) {
          cb();
        }
      }
    } catch (_) {
      _failures = (_failures + 1).clamp(0, 6);
    } finally {
      _busy = false;
    }
  }
}

mixin LiveRefresh<T extends StatefulWidget> on State<T> {
  final List<VoidCallback> _liveCancels = [];
  Timer? _liveDebounce;

  List<String> get liveKeys;

  void onLiveChange();

  @override
  void initState() {
    super.initState();
    for (final key in liveKeys) {
      _liveCancels.add(LiveSync.instance.listen(key, _schedule));
    }
  }

  void _schedule() {
    _liveDebounce?.cancel();
    _liveDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) onLiveChange();
    });
  }

  @override
  void dispose() {
    _liveDebounce?.cancel();
    for (final c in _liveCancels) {
      c();
    }
    super.dispose();
  }
}
