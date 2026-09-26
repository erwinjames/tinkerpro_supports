import 'dart:convert';
import 'dart:io' show File, Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ringtone_service.dart';

const MethodChannel _nativeChannel =
    MethodChannel('com.tinkerpro.support/chat_bubble');

enum ToneSlot { message, call }

enum ToneKind { web, preset, device, custom, silent }

class ToneChoice {
  const ToneChoice({
    required this.kind,
    this.value = '',
    this.label = '',
  });

  static const web = ToneChoice(kind: ToneKind.web, label: 'Web setting');
  static const silent = ToneChoice(kind: ToneKind.silent, label: 'Silent');

  final ToneKind kind;
  final String value;
  final String label;

  bool get isWeb => kind == ToneKind.web;
  bool get isSilent => kind == ToneKind.silent;
  bool get isUri => kind == ToneKind.device || kind == ToneKind.custom;

  String get displayLabel {
    if (label.isNotEmpty) return label;
    return switch (kind) {
      ToneKind.web => 'Web setting',
      ToneKind.silent => 'Silent',
      ToneKind.preset => value,
      _ => 'Custom sound',
    };
  }

  String get signature => switch (kind) {
        ToneKind.web => 'web',
        ToneKind.silent => 'silent',
        ToneKind.preset => 'p$value',
        ToneKind.device => 'd${value.hashCode.abs()}',
        ToneKind.custom => 'c${value.hashCode.abs()}',
      };

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'value': value,
        'label': label,
      };

  static ToneChoice fromJson(String? raw) {
    if (raw == null || raw.isEmpty) return web;
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return web;
      final kind = ToneKind.values.firstWhere(
        (k) => k.name == '${map['kind']}',
        orElse: () => ToneKind.web,
      );
      return ToneChoice(
        kind: kind,
        value: '${map['value'] ?? ''}',
        label: '${map['label'] ?? ''}',
      );
    } catch (_) {
      return web;
    }
  }
}

class DeviceSound {
  const DeviceSound(this.title, this.uri);
  final String title;
  final String uri;
}

class TonePrefs {
  TonePrefs._();

  static const _kMessageKey = 'tone_message';
  static const _kCallKey = 'tone_call';
  static const _kChannelPrefix = 'sound_channel_';

  static bool get supported => Platform.isAndroid;

  static Future<ToneChoice> read(ToneSlot slot) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      return ToneChoice.fromJson(prefs.getString(_keyFor(slot)));
    } catch (_) {
      return ToneChoice.web;
    }
  }

  static String _keyFor(ToneSlot slot) =>
      slot == ToneSlot.message ? _kMessageKey : _kCallKey;

  static Future<void> write(ToneSlot slot, ToneChoice choice) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFor(slot), jsonEncode(choice.toJson()));
    await applyToRingtoneService();
    if (slot == ToneSlot.message) await syncChannels();
  }

  static Future<void> applyToRingtoneService() async {
    RingtoneService.instance.applyLocalTones(
      message: await read(ToneSlot.message),
      call: await read(ToneSlot.call),
    );
  }

  static Future<List<DeviceSound>> deviceSounds(ToneSlot slot) async {
    if (!supported) return const [];
    try {
      final raw = await _nativeChannel.invokeListMethod<Object?>(
        'listDeviceSounds',
        {'kind': slot == ToneSlot.call ? 'ringtone' : 'notification'},
      );
      final out = <DeviceSound>[];
      for (final row in raw ?? const []) {
        if (row is Map) {
          final title = '${row['title'] ?? ''}';
          final uri = '${row['uri'] ?? ''}';
          if (title.isNotEmpty && uri.isNotEmpty) {
            out.add(DeviceSound(title, uri));
          }
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  static Future<String> importFile(ToneSlot slot, String path) async {
    if (!supported) return '';
    try {
      final bytes = await File(path).readAsBytes();
      if (bytes.isEmpty) return '';
      final uri = await _nativeChannel.invokeMethod<String>('importSound', {
        'slot': slot == ToneSlot.call ? 'callcustom' : 'msgcustom',
        'signature': '${bytes.length}${DateTime.now().millisecondsSinceEpoch}',
        'bytes': bytes,
      });
      return uri ?? '';
    } catch (e) {
      debugPrint('[tones] import failed: $e');
      return '';
    }
  }

  static Future<bool> preview(ToneChoice choice, {bool loop = false}) async {
    await stopPreview();
    if (choice.isSilent) return true;
    if (choice.isUri) {
      try {
        return await _nativeChannel.invokeMethod<bool>('playPreview', {
              'uri': choice.value,
              'loop': loop,
            }) ??
            false;
      } catch (_) {
        return false;
      }
    }
    if (choice.kind == ToneKind.preset) {
      await RingtoneService.instance.previewPreset(choice.value);
      return true;
    }
    await RingtoneService.instance.playEvent('notify');
    return true;
  }

  static Future<void> stopPreview() async {
    try {
      await _nativeChannel.invokeMethod('stopPreview');
    } catch (_) {}
    await RingtoneService.instance.stopPreview();
  }

  static Future<String?> channelFor(String event) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      return prefs.getString('$_kChannelPrefix$event');
    } catch (_) {
      return null;
    }
  }

  static Future<void> syncChannels() async {
    if (!supported) return;
    try {
      final choice = await read(ToneSlot.message);
      final specs = <Map<String, dynamic>>[];
      for (final event in kPushSoundEvents) {
        specs.add(await _specFor(event, choice));
      }
      final result = await _nativeChannel.invokeMapMethod<String, dynamic>(
        'configureSoundChannels',
        {'channels': specs},
      );
      if (result == null) return;
      final prefs = await SharedPreferences.getInstance();
      for (final entry in result.entries) {
        final id = '${entry.value}';
        if (id.isNotEmpty) {
          await prefs.setString('$_kChannelPrefix${entry.key}', id);
        }
      }
    } catch (e) {
      debugPrint('[tones] syncChannels failed: $e');
    }
  }

  static Future<Map<String, dynamic>> _specFor(
    String event,
    ToneChoice choice,
  ) async {
    final label = switch (event) {
      'fb' => 'Facebook messages',
      'fbmove' => 'Facebook chat moved',
      _ => 'Chat messages',
    };
    if (choice.isSilent) {
      return {
        'event': event,
        'signature': 'silent',
        'label': label,
        'silent': true,
      };
    }
    if (choice.isUri) {
      return {
        'event': event,
        'signature': choice.signature,
        'label': label,
        'uri': choice.value,
      };
    }
    final name = choice.kind == ToneKind.preset
        ? choice.value
        : RingtoneService.instance.valueFor(event);
    if (name == 'none') {
      return {
        'event': event,
        'signature': 'silent',
        'label': label,
        'silent': true,
      };
    }
    final bytes = await RingtoneService.instance.bytesForEvent(
      event,
      presetOverride: choice.kind == ToneKind.preset ? name : null,
    );
    return {
      'event': event,
      'signature': choice.kind == ToneKind.preset
          ? choice.signature
          : 'w$name${bytes?.length ?? 0}',
      'label': label,
      'bytes': bytes ?? Uint8List(0),
    };
  }
}
