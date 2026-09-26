import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  'handoff': SoundPreset([
    Seg(622.25, 0.10), Seg(0, 0.03), Seg(830.61, 0.10), Seg(0, 0.03),
    Seg(622.25, 0.10), Seg(0, 0.03), Seg(1108.73, 0.26),
  ], 0.19),
};

const Map<String, String> kSoundFactoryDefaults = {
  'notify': 'chime',
  'incoming': 'classic',
  'react': 'pop',
  'sent': 'none',
  'fb': 'messenger',
  'fbmove': 'handoff',
};

const List<String> kPushSoundEvents = ['notify', 'fb', 'fbmove'];
const String _kEffectiveKey = 'sound_effective';

const MethodChannel _toneChannel =
    MethodChannel('com.tinkerpro.support/chat_bubble');

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

  Map<String, String> _events = const {};

  Future<Uint8List?> Function(String event)? _customLoader;

  final Map<String, Uint8List> _presetCache = {};
  final Map<String, Uint8List> _customCache = {};

  Object? _messageTone;
  Object? _callTone;

  void applyLocalTones({Object? message, Object? call}) {
    _messageTone = message;
    _callTone = call;
  }

  String? _localKindOf(Object? tone) {
    if (tone == null) return null;
    try {
      final kind = (tone as dynamic).kind;
      return kind?.name as String?;
    } catch (_) {
      return null;
    }
  }

  String _localValueOf(Object? tone) {
    try {
      return ((tone as dynamic).value as String?) ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<bool> _playLocal(Object? tone, {required bool loop}) async {
    final kind = _localKindOf(tone);
    if (kind == null || kind == 'web') return false;
    if (kind == 'silent') return true;
    if (kind == 'preset') {
      final bytes = _presetBytes(_localValueOf(tone));
      if (bytes == null) return false;
      await _playBytes(bytes, loop: loop);
      return true;
    }
    try {
      await _toneChannel.invokeMethod('playPreview', {
        'uri': _localValueOf(tone),
        'loop': loop,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _playBytes(Uint8List bytes, {required bool loop}) async {
    await _init();
    final player = loop ? _ringPlayer : _pingPlayer;
    await player.stop();
    await player.setReleaseMode(loop ? ReleaseMode.loop : ReleaseMode.release);
    await player.play(BytesSource(bytes));
  }

  Future<void> previewPreset(String name) async {
    final bytes = _presetBytes(name);
    if (bytes == null) return;
    try {
      await _playBytes(bytes, loop: false);
    } catch (e) {
      debugPrint('[ringtone] previewPreset failed: $e');
    }
  }

  Future<void> stopPreview() async {
    if (!_initStarted) return;
    try {
      await _pingPlayer.stop();
    } catch (_) {}
  }

  String valueFor(String event) => _valueFor(event);

  Future<Uint8List?> bytesForEvent(
    String event, {
    String? presetOverride,
  }) async {
    if (presetOverride != null) return _presetBytes(presetOverride);
    return _bytesFor(event);
  }

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
      if (await _playLocal(_callTone, loop: true)) return;
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
    try {
      await _toneChannel.invokeMethod('stopPreview');
    } catch (_) {}
    if (!_initStarted) return;
    try {
      await _ringPlayer.stop();
      await _ringbackPlayer.stop();
    } catch (e) {
      debugPrint('[ringtone] stop failed: $e');
    }
  }

  Future<void> ping({bool facebook = false}) =>
      playEvent(facebook ? 'fb' : 'notify');

  Future<Duration> playEvent(String event) async {
    await _init();
    try {
      if (await _playLocal(_messageTone, loop: false)) return Duration.zero;
      await _pingPlayer.stop();
      if (_valueFor(event) == 'none') return Duration.zero;
      final bytes = await _bytesFor(event) ?? _pingBytes;
      if (bytes != null) {
        await _pingPlayer.play(BytesSource(bytes));
        return _estimateDuration(bytes);
      }
    } catch (e) {
      debugPrint('[ringtone] play $event failed: $e');
    }
    return Duration.zero;
  }

  Duration _estimateDuration(Uint8List bytes) {
    if (bytes.length > 44 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF') {
      final ms = ((bytes.length - 44) / (_sampleRate * 2) * 1000).round();
      return Duration(milliseconds: ms.clamp(0, 5000));
    }
    return const Duration(seconds: 3);
  }

  static Future<Directory> _soundDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/notification_sounds');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<void> persist(
    Map<String, String> effective,
    Future<Uint8List?> Function(String event) customLoader,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kEffectiveKey, jsonEncode(effective));
      final dir = await _soundDir();
      for (final event in kPushSoundEvents) {
        final file = File('${dir.path}/$event.bin');
        if (effective[event] != 'custom') {
          if (await file.exists()) await file.delete();
          continue;
        }
        final bytes = await customLoader(event);
        if (bytes != null && bytes.isNotEmpty) {
          await file.writeAsBytes(bytes, flush: true);
        }
      }
    } catch (e) {
      debugPrint('[ringtone] persist failed: $e');
    }
  }

  Future<void> loadFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final raw = prefs.getString(_kEffectiveKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final map = <String, String>{};
      decoded.forEach((k, v) {
        if (v is String && v.isNotEmpty) map[k.toString()] = v;
      });
      _customCache.clear();
      applyPreferences(map, customLoader: (event) async {
        final dir = await _soundDir();
        final file = File('${dir.path}/$event.bin');
        if (!await file.exists()) return null;
        return file.readAsBytes();
      });
    } catch (e) {
      debugPrint('[ringtone] loadFromDisk failed: $e');
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
