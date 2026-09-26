import 'sound_engine.dart';

class RingtoneService {
  RingtoneService._();
  static final RingtoneService instance = RingtoneService._();

  SoundEngine get _engine => SoundEngine.instance;

  Future<void> startIncoming() => _engine.startIncoming();

  Future<void> startRingback() => _engine.startRingback();

  Future<void> stop() => _engine.stopLoop();

  Future<void> ping() => _engine.playPreset('ding');

  Future<void> dispose() => _engine.stopLoop();
}
