import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class RingtoneService {
  RingtoneService._();
  static final RingtoneService instance = RingtoneService._();

  final AudioPlayer _ringPlayer = AudioPlayer();
  final AudioPlayer _ringbackPlayer = AudioPlayer();
  final AudioPlayer _pingPlayer = AudioPlayer();

  Uint8List? _ringBytes;
  Uint8List? _ringbackBytes;
  Uint8List? _pingBytes;
  bool _initStarted = false;
  Future<void>? _initFuture;

  Future<void> _init() {
    if (_initFuture != null) return _initFuture!;
    _initStarted = true;
    _initFuture = () async {
      _ringBytes = _wav([
        const _Seg(440, 0.4), const _Seg(0, 0.05),
        const _Seg(480, 0.4), const _Seg(0, 0.15),
        const _Seg(440, 0.4), const _Seg(0, 0.05),
        const _Seg(480, 0.4), const _Seg(0, 1.8),
      ]);
      _ringbackBytes = _wav([
        const _Seg(440, 1.2), const _Seg(0, 2.8),
      ]);
      _pingBytes = _wav([
        const _Seg(660, 0.10), const _Seg(0, 0.04), const _Seg(880, 0.14),
      ]);
      try {
        await _ringPlayer.setReleaseMode(ReleaseMode.loop);
        await _ringbackPlayer.setReleaseMode(ReleaseMode.loop);
        await _pingPlayer.setReleaseMode(ReleaseMode.release);
      } catch (e) {
        debugPrint('[ringtone] setReleaseMode failed: $e');
      }
    }();
    return _initFuture!;
  }

  Future<void> startIncoming() async {
    await _init();
    try {
      await _ringbackPlayer.stop();
      await _ringPlayer.stop();
      if (_ringBytes != null) {
        await _ringPlayer.play(BytesSource(_ringBytes!));
      }
    } catch (e) {
      debugPrint('[ringtone] startIncoming failed: $e');
    }
  }

  Future<void> startRingback() async {
    await _init();
    try {
      await _ringPlayer.stop();
      await _ringbackPlayer.stop();
      if (_ringbackBytes != null) {
        await _ringbackPlayer.play(BytesSource(_ringbackBytes!));
      }
    } catch (e) {
      debugPrint('[ringtone] startRingback failed: $e');
    }
  }

  Future<void> stop() async {
    if (!_initStarted) return;
    try {
      await _ringPlayer.stop();
      await _ringbackPlayer.stop();
    } catch (e) {
      debugPrint('[ringtone] stop failed: $e');
    }
  }

  Future<void> ping() async {
    await _init();
    try {
      await _pingPlayer.stop();
      if (_pingBytes != null) {
        await _pingPlayer.play(BytesSource(_pingBytes!));
      }
    } catch (e) {
      debugPrint('[ringtone] ping failed: $e');
    }
  }

  Future<void> dispose() async {
    try {
      await _ringPlayer.dispose();
      await _ringbackPlayer.dispose();
      await _pingPlayer.dispose();
    } catch (_) {}
  }

  static const int _sampleRate = 22050;
  static const double _gain = 0.4;

  Uint8List _wav(List<_Seg> pattern) {
    var totalSamples = 0;
    for (final s in pattern) {
      totalSamples += (s.duration * _sampleRate).round();
    }
    final pcm = Int16List(totalSamples);
    var idx = 0;
    for (final seg in pattern) {
      final samples = (seg.duration * _sampleRate).round();
      if (seg.freq <= 0) {
        idx += samples;
        continue;
      }
      final omega = 2 * pi * seg.freq / _sampleRate;
      final fade = min(samples ~/ 4, (_sampleRate * 0.01).round());
      for (var i = 0; i < samples; i++) {
        var env = 1.0;
        if (i < fade) {
          env = i / fade;
        } else if (i > samples - fade) {
          env = (samples - i) / fade;
        }
        final v = (sin(omega * i) * env * _gain * 32767).toInt();
        pcm[idx++] = v.clamp(-32768, 32767);
      }
    }
    final dataBytes = pcm.buffer.asUint8List();
    final dataLen = dataBytes.length;
    final out = BytesBuilder();
    out.add(_ascii('RIFF'));
    out.add(_le32(36 + dataLen));
    out.add(_ascii('WAVE'));
    out.add(_ascii('fmt '));
    out.add(_le32(16));
    out.add(_le16(1));
    out.add(_le16(1));
    out.add(_le32(_sampleRate));
    out.add(_le32(_sampleRate * 2));
    out.add(_le16(2));
    out.add(_le16(16));
    out.add(_ascii('data'));
    out.add(_le32(dataLen));
    out.add(dataBytes);
    return out.toBytes();
  }

  List<int> _ascii(String s) => s.codeUnits;
  List<int> _le16(int v) => [v & 0xff, (v >> 8) & 0xff];
  List<int> _le32(int v) =>
      [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff];
}

class _Seg {
  const _Seg(this.freq, this.duration);
  final double freq;
  final double duration;
}
