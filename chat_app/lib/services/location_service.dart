import 'package:geolocator/geolocator.dart';

import '../api_client.dart';
import '../platform_info.dart';

class LocationReport {
  const LocationReport({this.latitude, this.longitude, this.accuracy});

  final double? latitude;
  final double? longitude;
  final double? accuracy;

  bool get hasFix => latitude != null && longitude != null;
}

class LocationService {
  LocationService(this.api);

  final ApiClient api;

  /// Asks for location permission and reports the position to the server so
  /// the web activity log records where this session was opened.
  ///
  /// Best-effort throughout: a denied prompt, disabled location services, or
  /// an unsupported platform still posts the "App Opened" row, just without
  /// coordinates. Never throws and never blocks the caller's UI.
  Future<LocationReport> reportOnOpen({String source = 'TinkerPro Chat'}) async {
    final fix = await _currentPosition();
    await _post(fix, source);
    return fix;
  }

  Future<LocationReport> _currentPosition() async {
    if (!kIsMobilePlatform) return const LocationReport();
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationReport();
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return const LocationReport();
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 12),
        ),
      );
      return LocationReport(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
      );
    } catch (_) {
      return const LocationReport();
    }
  }

  Future<void> _post(LocationReport fix, String source) async {
    if (!api.hasSession) return;
    try {
      await api.post('recordClientLocation', body: {
        'log': '1',
        'source': source,
        if (fix.hasFix) ...{
          'gps_lat': fix.latitude!.toStringAsFixed(7),
          'gps_lon': fix.longitude!.toStringAsFixed(7),
          if (fix.accuracy != null)
            'gps_accuracy': fix.accuracy!.round().toString(),
        },
      });
    } catch (_) {}
  }
}
