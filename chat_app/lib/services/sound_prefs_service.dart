import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../api_client.dart';
import 'ringtone_service.dart';
import 'tone_prefs.dart';

class SoundPrefsService {
  SoundPrefsService(this.api);

  final ApiClient api;

  Future<void> load() async {
    try {
      final res = await api.get('getGlobalSoundDefaults');
      if (res['status'] != 'success') return;
      final settings = res['sound_settings'];
      if (settings is! Map) return;
      final effective = settings['effective'];
      if (effective is! Map) return;

      final map = <String, String>{};
      effective.forEach((key, value) {
        if (value is String && value.isNotEmpty) {
          map[key.toString()] = value;
        }
      });
      if (map.isEmpty) return;

      RingtoneService.instance.applyPreferences(
        map,
        customLoader: _loadCustom,
      );
      await RingtoneService.persist(map, _loadCustom);
      await TonePrefs.applyToRingtoneService();
      await TonePrefs.syncChannels();
    } catch (_) {}
  }

  Future<Uint8List?> _loadCustom(String event) async {
    try {
      final uri = Uri.parse(api.actionUrl('getUserSound', {'event': event}));
      final res = await http
          .get(uri, headers: api.authHeaders())
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
      return res.bodyBytes;
    } catch (_) {
      return null;
    }
  }
}
