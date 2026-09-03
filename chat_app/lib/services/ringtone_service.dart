import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Mirrors PRESETS in layout/audio-cues.php so a sound picked on the web
/// plays identically here — same frequencies, durations and relative gain.
class SoundPreset {
  const SoundPreset(this.pattern, this.gain);
  final List<Seg> pattern;
  final double gain;
}

const Map<String, SoundPreset> kSoundPresets = {
  'chime': SoundPreset([
    Seg(783.99, 0.13), Seg(0, 0.03), Seg(1046.50, 0.30),
  ], 0.16),
  'ding': SoundPreset([
    Seg(660, 0.10), Seg(0, 0.04), Seg(880, 0.14),
  ], 0.18),
  'bell': SoundPreset([Seg(1174.66, 0.5)], 0.12),
  'pop': SoundPreset([
    Seg(523.25, 0.06), Seg(0, 0.02), Seg(659.25, 0.06),
  ], 0.16),
  'classic': SoundPreset([
    Seg(440, 0.4), Seg(0, 0.05), Seg(480, 0.4), Seg(0, 0.15),
    Seg(440, 0.4), Seg(0, 0.05), Seg(480, 0.4), Seg(0, 1.8),
  ], 0.22),
  'soft': SoundPreset([Seg(523.25, 0.2)], 0.12),
  'alert': SoundPreset([
    Seg(880, 0.12), Seg(0, 0.05), Seg(880, 0.12),
  ], 0.20),
  'messenger': SoundPreset([
    Seg(987.77, 0.07), Seg(0, 0.02), Seg(1318.51, 0.07),
    Seg(0, 0.02), Seg(1567.98, 0.20),
  ], 0.17),
  'visitor': SoundPreset([
    Seg(1318.51, 0.07), Seg(0, 0.03), Seg(1046.50, 0.15),
  ], 0.15),
};

/// SoundSettings::FACTORY on the server.
const Map<String, String> kSoundFactoryDefaults = {
  'notify': 'chime',
  'incoming': 'classic',
  'react': 'pop',
  'sent': 'none',
  'fb': 'messenger',
};

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

  /// Effective per-event sound names from the server, resolved there against
  /// the user's own picks and the global defaults.
  Map<String, String> _events = const {};

  /// Fetches the bytes of an uploaded custom sound for an event.
  Future<Uint8List?> Function(String event)? _customLoader;

  final Map<String, Uint8List> _presetCache = {};
  final Map<String, Uint8List> _customCache = {};

  void applyPreferences(
    Map<String, String> effective, {
    Future<Uint8List?> Function(String event)? customLoader,
  }) {
    _events = Map<String, String>.from(effective);
    _customLoader = customLoader;
  }

  String _valueFor(String event) {
    final v = _events[event];
    if (v != null && v.isNotEmpty) return v;
    return kSoundFactoryDefaults[event] ?? 'chime';
  }

  Future<Uint8List?> _bytesFor(String event) async {
    final value = _valueFor(event);
    if (value == 'none') return null;
    if (value == 'custom') {
      final cached = _customCache[event];
      if (cached != null) return cached;
      final loaded = await _customLoader?.call(event);
      if (loaded != null && loaded.isNotEmpty) {
        _customCache[event] = loaded;
        return loaded;
      }
      // Upload missing or unreachable — fall back to the factory tone.
      return _presetBytes(kSoundFactoryDefaults[event] ?? 'chime');
    }
    return _presetBytes(value);
  }

  Uint8List? _presetBytes(String name) {
    final preset = kSoundPresets[name];
    if (preset == null) return null;
    return _presetCache[name] ??= _wav(preset.pattern, gain: preset.gain);
  }

  Future<void> _init() {
    if (_initFuture != null) return _initFuture!;
    _initStarted = true;
    _initFuture = () async {
      _ringBytes = _wav([
        const Seg(440, 0.4), const Seg(0, 0.05),
        const Seg(480, 0.4), const Seg(0, 0.15),
        const Seg(440, 0.4), const Seg(0, 0.05),
        const Seg(480, 0.4), const Seg(0, 1.8),
      ]);
      _ringbackBytes = _wav([
        const Seg(440, 1.2), const Seg(0, 2.8),
      ]);
      _pingBytes = _wav([
        const Seg(660, 0.10), const Seg(0, 0.04), const Seg(880, 0.14),
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
      final bytes = await _bytesFor('incoming') ?? _ringBytes;
      if (bytes != null) {
        await _ringPlayer.play(BytesSource(bytes));
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

  /// New-message cue. Facebook page threads use the `fb` slot, everything
  /// else `notify` — the same split the web app makes.
  Future<void> ping({bool facebook = false}) async {
    await _init();
    try {
      await _pingPlayer.stop();
      final bytes = await _bytesFor(facebook ? 'fb' : 'notify') ?? _pingBytes;
      if (bytes != null) {
        await _pingPlayer.play(BytesSource(bytes));
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

  Uint8List _wav(List<Seg> pattern, {double gain = _gain}) {
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
        final v = (sin(omega * i) * env * gain * 32767).toInt();
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

class Seg {
  const Seg(this.freq, this.duration);
  final double freq;
  final double duration;
}
