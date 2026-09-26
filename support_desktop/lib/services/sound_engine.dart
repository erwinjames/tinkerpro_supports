import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api_client.dart';
import 'live_sync.dart';

class SoundEventInfo {
  const SoundEventInfo(this.event, this.title, this.desc);
  final String event;
  final String title;
  final String desc;
}

class SoundState {
  const SoundState({
    this.effective = const {},
    this.global = const {},
    this.inheritsGlobal = true,
  });

  final Map<String, String> effective;
  final Map<String, String> global;
  final bool inheritsGlobal;

  static Map<String, String> _strMap(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, String>{};
    raw.forEach((k, v) {
      final s = '${v ?? ''}';
      if (s.isNotEmpty) out['$k'] = s;
    });
    return out;
  }

  factory SoundState.fromJson(Object? raw) {
    if (raw is! Map) return const SoundState();
    return SoundState(
      effective: _strMap(raw['effective']),
      global: _strMap(raw['global']),
      inheritsGlobal: raw['inherits_global'] != false,
    );
  }
}

class _Tone {
  const _Tone(this.freq, this.dur);
  final double freq;
  final double dur;
}

class _Preset {
  const _Preset(this.pattern, this.gain);
  final List<_Tone> pattern;
  final double gain;
}

class SoundEngine {
  SoundEngine._();
  static final SoundEngine instance = SoundEngine._();

  static const List<SoundEventInfo> events = [
    SoundEventInfo('notify', 'New message / notification',
        'Incoming chat messages and header-bell alerts.'),
    SoundEventInfo('incoming', 'Incoming call',
        'Ringtone when a voice or video call comes in.'),
    SoundEventInfo(
        'react', 'Message reaction', 'When someone reacts to your message.'),
    SoundEventInfo('sent', 'Message sent',
        'Plays when you send a message (off by default).'),
    SoundEventInfo('fb', 'Facebook Messenger message',
        'Incoming messages from Facebook chats, so they stand out from internal chats.'),
    SoundEventInfo('fbmove', 'Facebook chat moved to agents',
        'When a Facebook chat is moved out of the Facebook tab into the main chat list.'),
  ];

  static const Map<String, String> presetLabels = {
    'chime': 'Chime',
    'ding': 'Ding',
    'bell': 'Bell',
    'pop': 'Pop',
    'classic': 'Classic',
    'soft': 'Soft',
    'alert': 'Alert',
    'messenger': 'Messenger',
    'handoff': 'Handoff',
  };

  static const Map<String, String> factory = {
    'notify': 'chime',
    'incoming': 'classic',
    'react': 'pop',
    'sent': 'none',
    'fb': 'messenger',
    'fbmove': 'handoff',
  };

  static const Map<String, _Preset> _presets = {
    'chime': _Preset([_Tone(783.99, 0.13), _Tone(0, 0.03), _Tone(1046.50, 0.30)], 0.16),
    'ding': _Preset([_Tone(660, 0.10), _Tone(0, 0.04), _Tone(880, 0.14)], 0.18),
    'bell': _Preset([_Tone(1174.66, 0.5)], 0.12),
    'pop': _Preset([_Tone(523.25, 0.06), _Tone(0, 0.02), _Tone(659.25, 0.06)], 0.16),
    'classic': _Preset([
      _Tone(440, 0.4), _Tone(0, 0.05), _Tone(480, 0.4), _Tone(0, 0.15),
      _Tone(440, 0.4), _Tone(0, 0.05), _Tone(480, 0.4), _Tone(0, 1.8),
    ], 0.22),
    'soft': _Preset([_Tone(523.25, 0.2)], 0.12),
    'alert': _Preset([_Tone(880, 0.12), _Tone(0, 0.05), _Tone(880, 0.12)], 0.20),
    'messenger': _Preset([
      _Tone(987.77, 0.07), _Tone(0, 0.02), _Tone(1318.51, 0.07),
      _Tone(0, 0.02), _Tone(1567.98, 0.20),
    ], 0.17),
    'visitor': _Preset([_Tone(1318.51, 0.07), _Tone(0, 0.03), _Tone(1046.50, 0.15)], 0.15),
    'handoff': _Preset([
      _Tone(622.25, 0.10), _Tone(0, 0.03), _Tone(830.61, 0.10), _Tone(0, 0.03),
      _Tone(622.25, 0.10), _Tone(0, 0.03), _Tone(1108.73, 0.26),
    ], 0.19),
    '_ringback': _Preset([_Tone(440, 1.2), _Tone(0, 2.8)], 0.14),
  };

  static const Duration _customTtl = Duration(minutes: 10);
  static const int _sampleRate = 44100;

  final ValueNotifier<SoundState> state = ValueNotifier(const SoundState());
  final ValueNotifier<bool> chatMuted = ValueNotifier(false);

  final Map<String, String> _local = {};
  final Map<String, String> _presetPaths = {};
  final Map<String, (String, DateTime)> _customCache = {};
  final Map<String, Future<String?>> _customFetch = {};
  final Set<int> _playedMessages = <int>{};
  final List<AudioPlayer> _fx = [];
  int _fxNext = 0;
  AudioPlayer? _loop;
  int _loopToken = 0;

  ApiClient? _api;
  int? _uid;
  Directory? _dir;
  final List<VoidCallback> _liveCancels = [];
  Timer? _liveDebounce;
  bool Function()? _chatConnected;

  bool get attached => _api != null;

  Future<void> attach(ApiClient api, int? uid) async {
    if (identical(api, _api) && uid == _uid) return;
    detach();
    _api = api;
    _uid = uid;
    try {
      final p = await SharedPreferences.getInstance();
      chatMuted.value = p.getBool(_muteKey) ?? false;
    } catch (_) {}
    for (final k in const ['settings', 'me']) {
      _liveCancels.add(LiveSync.instance.listen(k, _onLive));
    }
    unawaited(reload());
  }

  void detach() {
    for (final c in _liveCancels) {
      c();
    }
    _liveCancels.clear();
    _liveDebounce?.cancel();
    _api = null;
    _uid = null;
    _chatConnected = null;
    _local.clear();
    _customCache.clear();
    _playedMessages.clear();
    state.value = const SoundState();
    unawaited(stopLoop());
  }

  set chatConnected(bool Function()? probe) => _chatConnected = probe;

  String get _muteKey => 'tpChatMuted:${_uid ?? 0}';

  Future<void> setChatMuted(bool muted) async {
    chatMuted.value = muted;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_muteKey, muted);
    } catch (_) {}
  }

  void _onLive() {
    _liveDebounce?.cancel();
    _liveDebounce = Timer(const Duration(milliseconds: 400), () {
      _customCache.clear();
      unawaited(reload());
    });
  }

  Future<void> reload() async {
    final api = _api;
    if (api == null) return;
    try {
      final res = await api
          .get('getGlobalSoundDefaults')
          .timeout(const Duration(seconds: 10));
      if (res['status'] == 'success') {
        apply(SoundState.fromJson(res['sound_settings']));
      }
    } catch (e) {
      debugPrint('[sound] reload failed: $e');
    }
  }

  void apply(SoundState s) {
    debugPrint('[sound] settings ${s.effective}');
    _local.clear();
    state.value = s;
  }

  void setPref(String event, String value) => _local[event] = value;

  String valueFor(String event) {
    final v = _local[event] ?? state.value.effective[event];
    if (v == null || v.isEmpty) return factory[event] ?? 'none';
    return v;
  }

  void invalidateCustom([String? event]) {
    if (event == null) {
      _customCache.clear();
    } else {
      _customCache.remove(event);
    }
  }

  bool _firstPlay(int messageId) {
    if (messageId <= 0) return true;
    if (!_playedMessages.add(messageId)) return false;
    if (_playedMessages.length > 500) {
      _playedMessages.remove(_playedMessages.first);
    }
    return true;
  }

  void chatMessage({
    required int messageId,
    required int senderId,
    bool silent = false,
    String source = '',
  }) {
    if (silent) return;
    if (_uid != null && senderId == _uid) return;
    if (!_firstPlay(messageId)) return;
    if (chatMuted.value) return;
    unawaited(play(source == 'facebook' ? 'fb' : 'notify', reason: 'chat #$messageId'));
  }

  void bellItems(Iterable<Map<String, dynamic>> items) {
    String? pick;
    for (final n in items) {
      final type = '${n['type'] ?? ''}';
      final meta = n['meta'] is Map ? n['meta'] as Map : const {};
      if (type == 'chat' || type == 'chat_mention') {
        final mid = int.tryParse('${meta['message_id'] ?? ''}') ?? 0;
        final live = _chatConnected?.call() ?? false;
        if (live || chatMuted.value) continue;
        if (!_firstPlay(mid)) continue;
        pick ??= meta['source'] == 'facebook' ? 'fb' : 'notify';
        continue;
      }
      if (type == 'chat_fb_moved') {
        pick ??= 'fbmove';
        continue;
      }
      pick ??= meta['source'] == 'facebook' ? 'fb' : 'notify';
    }
    if (pick != null) unawaited(play(pick, reason: 'bell'));
  }

  final Set<String> _reactKeys = <String>{};

  void reaction(String key) {
    if (!_reactKeys.add(key)) return;
    if (_reactKeys.length > 200) _reactKeys.remove(_reactKeys.first);
    if (chatMuted.value) return;
    unawaited(play('react', reason: 'reaction'));
  }

  void sent() {
    if (chatMuted.value) return;
    unawaited(play('sent', reason: 'sent'));
  }

  Future<void> play(String event, {String reason = ''}) {
    final v = valueFor(event);
    debugPrint('[sound] $event -> $v${reason.isEmpty ? '' : ' ($reason)'}');
    return _playValue(event, v, loop: false);
  }

  Future<void> preview(String event, String value) async {
    await stopLoop();
    await _playValue(event, value, loop: false);
  }

  Future<void> playPreset(String preset) => _playValue('', preset, loop: false);

  Future<void> startIncoming() async {
    debugPrint('[sound] incoming -> ${valueFor('incoming')} (call)');
    await _playValue('incoming', valueFor('incoming'), loop: true);
  }

  Future<void> startRingback() => _playValue('', '_ringback', loop: true);

  Future<void> stopLoop() async {
    _loopToken++;
    final p = _loop;
    if (p == null) return;
    try {
      await p.stop();
    } catch (_) {}
  }

  Future<void> _playValue(String event, String value, {required bool loop}) async {
    if (loop) await stopLoop();
    final token = _loopToken;
    if (value == 'none') return;
    String? path;
    if (value == 'custom' && event.isNotEmpty) {
      path = await _customPath(event);
      path ??= await _presetPath(factory[event] ?? 'chime');
    } else {
      final key = _presets.containsKey(value) ? value : (factory[event] ?? 'chime');
      path = await _presetPath(_presets.containsKey(key) ? key : 'chime');
    }
    if (path == null) return;
    if (loop && token != _loopToken) return;
    try {
      final player = loop ? _loopPlayer() : _nextFx();
      await player.stop();
      await player.setReleaseMode(loop ? ReleaseMode.loop : ReleaseMode.stop);
      if (loop && token != _loopToken) return;
      await player.play(DeviceFileSource(path));
      if (loop && token != _loopToken) await player.stop();
    } catch (e) {
      debugPrint('[sound] playback failed: $e');
    }
  }

  AudioPlayer _loopPlayer() => _loop ??= AudioPlayer();

  AudioPlayer _nextFx() {
    if (_fx.length < 3) {
      final p = AudioPlayer();
      _fx.add(p);
      return p;
    }
    final p = _fx[_fxNext % _fx.length];
    _fxNext++;
    return p;
  }

  Future<Directory?> _soundDir() async {
    if (_dir != null) return _dir;
    try {
      final base = await getApplicationSupportDirectory();
      final d = Directory('${base.path}${Platform.pathSeparator}sounds');
      if (!await d.exists()) await d.create(recursive: true);
      _dir = d;
    } catch (e) {
      debugPrint('[sound] no cache dir: $e');
    }
    return _dir;
  }

  Future<String?> _presetPath(String key) async {
    final cached = _presetPaths[key];
    if (cached != null) return cached;
    final preset = _presets[key];
    final dir = await _soundDir();
    if (preset == null || dir == null) return null;
    final name = key.startsWith('_') ? key.substring(1) : key;
    final f = File('${dir.path}${Platform.pathSeparator}preset-$name.wav');
    try {
      await f.writeAsBytes(_wav(preset), flush: true);
    } catch (e) {
      debugPrint('[sound] preset write failed: $e');
      return null;
    }
    return _presetPaths[key] = f.path;
  }

  Future<String?> _customPath(String event) {
    final hit = _customCache[event];
    if (hit != null &&
        DateTime.now().difference(hit.$2) < _customTtl &&
        File(hit.$1).existsSync()) {
      return Future.value(hit.$1);
    }
    return _customFetch[event] ??=
        _downloadCustom(event).whenComplete(() => _customFetch.remove(event));
  }

  Future<String?> _downloadCustom(String event) async {
    final api = _api;
    final dir = await _soundDir();
    if (api == null || dir == null) return null;
    try {
      final url = api.actionUrl('getUserSound', {
        'event': event,
        '_': '${DateTime.now().millisecondsSinceEpoch}',
      });
      final res = await http
          .get(Uri.parse(url), headers: api.authHeaders())
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) {
        debugPrint('[sound] custom $event unavailable (${res.statusCode})');
        return null;
      }
      final ct = (res.headers['content-type'] ?? '').toLowerCase();
      final ext = ct.contains('mpeg')
          ? 'mp3'
          : ct.contains('wav')
              ? 'wav'
              : ct.contains('ogg')
                  ? 'ogg'
                  : ct.contains('mp4')
                      ? 'm4a'
                      : ct.contains('aac')
                          ? 'aac'
                          : ct.contains('webm')
                              ? 'webm'
                              : 'bin';
      final sep = Platform.pathSeparator;
      final f = File('${dir.path}${sep}custom-u${_uid ?? 0}-$event-'
          '${DateTime.now().millisecondsSinceEpoch}.$ext');
      await f.writeAsBytes(res.bodyBytes, flush: true);
      final old = _customCache[event];
      _customCache[event] = (f.path, DateTime.now());
      if (old != null && old.$1 != f.path) {
        try {
          await File(old.$1).delete();
        } catch (_) {}
      }
      return f.path;
    } catch (e) {
      debugPrint('[sound] custom $event download failed: $e');
      return null;
    }
  }

  static Uint8List _wav(_Preset preset) {
    const floor = 0.0001;
    final peak = preset.gain;
    var total = 0.0;
    for (final t in preset.pattern) {
      total += t.dur;
    }
    final samples = (total * _sampleRate).ceil();
    final pcm = Int16List(samples);
    var start = 0.0;
    for (final tone in preset.pattern) {
      final d = tone.dur;
      if (tone.freq > 0) {
        final attackEnd = 0.02;
        final holdEnd = max(0.02, d - 0.04);
        final from = (start * _sampleRate).round();
        final to = min(samples, ((start + d) * _sampleRate).round());
        final omega = 2 * pi * tone.freq / _sampleRate;
        for (var i = from; i < to; i++) {
          final t = (i - from) / _sampleRate;
          double g;
          if (t < attackEnd) {
            g = floor * pow(peak / floor, t / attackEnd);
          } else if (t < holdEnd) {
            g = peak;
          } else {
            final span = d - holdEnd;
            final x = span <= 0 ? 1.0 : ((t - holdEnd) / span).clamp(0.0, 1.0);
            g = peak * pow(floor / peak, x);
          }
          final v = sin(omega * (i - from)) * g * 32767;
          pcm[i] = v.round().clamp(-32768, 32767);
        }
      }
      start += d;
    }
    final data = pcm.buffer.asUint8List();
    final b = BytesBuilder();
    void le32(int v) => b.add([v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]);
    void le16(int v) => b.add([v & 0xff, (v >> 8) & 0xff]);
    b.add('RIFF'.codeUnits);
    le32(36 + data.length);
    b.add('WAVE'.codeUnits);
    b.add('fmt '.codeUnits);
    le32(16);
    le16(1);
    le16(1);
    le32(_sampleRate);
    le32(_sampleRate * 2);
    le16(2);
    le16(16);
    b.add('data'.codeUnits);
    le32(data.length);
    b.add(data);
    return b.toBytes();
  }
}
