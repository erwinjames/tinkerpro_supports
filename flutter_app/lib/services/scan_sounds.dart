import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

import '../models/barcode_models.dart';

enum _Wave { sine, triangle, square }

class ScanSounds {
  ScanSounds._();
  static final ScanSounds instance = ScanSounds._();

  final AudioPlayer _player = AudioPlayer();
  Uint8List? _saved;
  Uint8List? _exists;
  Uint8List? _error;

  static const int _rate = 22050;

  Future<void> play(ScanOutcome outcome) async {
    switch (outcome) {
      case ScanOutcome.saved:
        HapticFeedback.lightImpact();
      case ScanOutcome.exists:
        HapticFeedback.heavyImpact();
      case ScanOutcome.error:
        HapticFeedback.vibrate();
    }
    _saved ??= _tone(880, 0.14, _Wave.sine);
    _exists ??= _tone(330, 0.22, _Wave.triangle);
    _error ??= _tone(200, 0.25, _Wave.square);
    final bytes = switch (outcome) {
      ScanOutcome.saved => _saved!,
      ScanOutcome.exists => _exists!,
      ScanOutcome.error => _error!,
    };
    try {
      await _player.stop();
      await _player.play(BytesSource(bytes));
    } catch (_) {}
  }

  Uint8List _tone(double freq, double seconds, _Wave wave) {
    final samples = (seconds * _rate).round();
    final pcm = Int16List(samples);
    for (var i = 0; i < samples; i++) {
      final t = i / _rate;
      final phase = (freq * t) % 1.0;
      final double v = switch (wave) {
        _Wave.sine => sin(2 * pi * phase),
        _Wave.triangle => 1 - 4 * (phase - 0.5).abs(),
        _Wave.square => phase < 0.5 ? 1.0 : -1.0,
      };
      final decay = 0.12 * pow(0.001 / 0.12, t / seconds);
      final attack = i < 60 ? i / 60 : 1.0;
      pcm[i] = (v * decay * attack * 32767 * 2.2).round().clamp(-32768, 32767);
    }
    final data = pcm.buffer.asUint8List();
    final header = ByteData(44);
    void ascii(int offset, String s) {
      for (var k = 0; k < s.length; k++) {
        header.setUint8(offset + k, s.codeUnitAt(k));
      }
    }

    ascii(0, 'RIFF');
    header.setUint32(4, 36 + data.length, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, _rate, Endian.little);
    header.setUint32(28, _rate * 2, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    header.setUint32(40, data.length, Endian.little);
    return Uint8List.fromList([...header.buffer.asUint8List(), ...data]);
  }
}
