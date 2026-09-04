import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/chat_models.dart';
import '../platform_info.dart';
import 'chat_realtime.dart';
import 'chat_service.dart';
import 'incoming_call_service.dart';
import 'ringtone_service.dart';

enum CallPhase { idle, calling, ringing, connecting, connected, ended }

enum CallMedia { voice, video }

enum CallRole { caller, callee }

const int kMeshMaxPeers = 6;

class CallParticipant {
  CallParticipant({required this.id, required this.name});

  final int id;
  String name;
  RTCPeerConnection? pc;
  MediaStream? stream;
  final RTCVideoRenderer renderer = RTCVideoRenderer();
  final List<RTCIceCandidate> pendingIce = [];
  bool remoteReady = false;
  bool connected = false;
  bool rendererReady = false;

  bool get hasVideo => stream != null && stream!.getVideoTracks().isNotEmpty;

  String get initial =>
      name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
}

class CallService extends ChangeNotifier {
  CallService({
    required this.realtime,
    required this.chat,
    required this.myUserId,
    List<Map<String, dynamic>>? iceServers,
  }) : _iceOverride = iceServers {
    _signalSub = realtime.callSignalEvents.listen(_onSignal);
  }

  final ChatRealtimeService realtime;
  final ChatService chat;
  final int myUserId;
  final List<Map<String, dynamic>>? _iceOverride;
  List<Map<String, dynamic>> _ice = const [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
  ];
  DateTime? _iceExpiresAt;
  StreamSubscription<CallSignal>? _signalSub;

  String? lastError;

  bool _hasTurn = false;
  bool get hasTurn => _hasTurn;

  String? iceDiagnostics;

  int _localCandidateCount = 0;
  int _remoteCandidateCount = 0;
  String _iceState = 'new';
  final Set<String> _remoteCandidateKinds = {};

  String _candidateKind(String? raw) {
    final c = raw ?? '';
    if (c.contains('.local')) return 'mdns';
    final m = RegExp(r'\btyp (\w+)').firstMatch(c);
    return m?.group(1) ?? '?';
  }

  void _publishIceDiagnostics() {
    final kinds = _remoteCandidateKinds.isEmpty
        ? ''
        : '(${_remoteCandidateKinds.join(",")})';
    iceDiagnostics = 'turn=$_hasTurn · servers=${_ice.length} · $_iceState · '
        'local=$_localCandidateCount remote=$_remoteCandidateCount$kinds';
    notifyListeners();
  }

  CallPhase phase = CallPhase.idle;
  CallRole? role;
  CallMedia media = CallMedia.voice;
  int? peerId;
  String peerName = '';
  String? callId;

  bool isGroup = false;
  String groupName = '';
  int groupConversationId = 0;
  int callerId = 0;

  bool muted = false;
  bool cameraOff = false;
  bool _frontCamera = true;
  DateTime? startedAt;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  bool _renderersReady = false;

  final Map<int, CallParticipant> _peers = {};
  List<Map<String, dynamic>> _roster = [];
  bool _announced = false;

  MediaStream? _localStream;
  RTCSessionDescription? _pendingOffer;

  final Map<String, List<RTCIceCandidate>> _earlyIce = {};

  Timer? _timer;
  Timer? _ringTimeout;
  Timer? _calleeRingTimeout;
  Timer? _connectingTimeout;
  Timer? _staleTimeout;
  bool _accepting = false;

  List<CallParticipant> get participants => _peers.values.toList();

  RTCVideoRenderer? get remoteRenderer =>
      _peers.isEmpty ? null : _peers.values.first.renderer;

  bool get isActive =>
      phase != CallPhase.idle && phase != CallPhase.ended;

  bool get isInLiveCall =>
      phase == CallPhase.connecting || phase == CallPhase.connected;

  bool get isIncomingRinging =>
      phase == CallPhase.ringing && role == CallRole.callee;

  String get title => isGroup
      ? (groupName.isEmpty ? 'Group call' : groupName)
      : peerName;

  Duration get elapsed {
    if (startedAt == null) return Duration.zero;
    return DateTime.now().difference(startedAt!);
  }

  String get elapsedLabel {
    final s = elapsed.inSeconds;
    final mm = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  Future<bool> placeCall({
    required int peerId,
    required String peerName,
    required CallMedia media,
  }) {
    return _startCall(
      media: media,
      roster: [
        {'id': peerId, 'name': peerName}
      ],
      group: false,
    );
  }

  Future<bool> placeGroupCall({
    required int conversationId,
    required String groupName,
    required List<Map<String, dynamic>> members,
    required CallMedia media,
  }) {
    if (members.isEmpty || members.length > kMeshMaxPeers) return Future.value(false);
    return _startCall(
      media: media,
      roster: members,
      group: true,
      groupName: groupName,
      conversationId: conversationId,
    );
  }

  Future<bool> _startCall({
    required CallMedia media,
    required List<Map<String, dynamic>> roster,
    required bool group,
    String groupName = '',
    int conversationId = 0,
  }) async {
    if (isActive) return false;
    _roster = roster
        .map((m) => {
              'id': (m['id'] as num).toInt(),
              'name': (m['name'] ?? 'User').toString(),
            })
        .toList();
    if (_roster.isEmpty) return false;

    isGroup = group;
    this.groupName = groupName;
    groupConversationId = conversationId;
    callerId = myUserId;
    peerId = _roster.first['id'] as int;
    peerName = group
        ? (groupName.isEmpty ? 'Group call' : groupName)
        : (_roster.first['name'] as String);
    this.media = media;
    role = CallRole.caller;
    callId = _newCallId();
    phase = CallPhase.calling;
    muted = false;
    cameraOff = false;
    _frontCamera = true;
    _announced = true;
    startedAt = null;
    _pendingOffer = null;

    await _ensureRenderers();
    await _refreshIce();
    unawaited(RingtoneService.instance.startRingback());
    notifyListeners();

    try {
      if (!await _ensureCapturePermissions(media)) {
        _cleanup(silent: true);
        notifyListeners();
        return false;
      }
      _localStream = await _getMedia(media);
      debugPrint('[call] local stream tracks: '
          '${_localStream!.getAudioTracks().length} audio, '
          '${_localStream!.getVideoTracks().length} video');
      localRenderer.srcObject = _localStream;
    } catch (_) {
      _fail('Could not access ${media == CallMedia.video ? 'camera/mic' : 'microphone'}');
      return false;
    }

    for (final m in _roster) {
      await _addPeer(m['id'] as int, m['name'] as String);
    }
    for (final p in _peers.values.toList()) {
      await _offerTo(p);
    }

    _ringTimeout = Timer(const Duration(seconds: 45), () {
      if (phase == CallPhase.calling || phase == CallPhase.ringing) {
        end(silent: false, reason: 'No answer');
      }
    });
    _armStaleSweep();
    return true;
  }

  Map<String, dynamic> _offerPayload(RTCSessionDescription desc) {
    final payload = <String, dynamic>{'sdp': desc.sdp, 'type': desc.type};
    if (isGroup) {
      payload['group'] = {
        'name': groupName,
        'conversation_id': groupConversationId,
        'caller_id': callerId,
        'roster': _roster,
      };
    }
    return payload;
  }

  Future<void> _offerTo(CallParticipant p) async {
    if (_localStream == null || p.pc != null || callId == null) return;
    final pc = await _createPeer(p);
    for (final t in _localStream!.getTracks()) {
      debugPrint('[call] addTrack ${t.kind} → ${p.id} enabled=${t.enabled}');
      await pc.addTrack(t, _localStream!);
    }
    try {
      final offer = await pc.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': media == CallMedia.video,
      });
      await pc.setLocalDescription(offer);
      debugPrint('[call] → offer to ${p.id} callId $callId');
      await chat.signal(
        peerId: p.id,
        kind: 'offer',
        callId: callId!,
        media: _mediaWire(),
        payload: _offerPayload(offer),
      );
    } catch (_) {
      debugPrint('[call] offer to ${p.id} failed');
    }
  }

  Future<CallParticipant> _addPeer(int id, String name) async {
    final existing = _peers[id];
    if (existing != null) {
      if (name.isNotEmpty && existing.name == 'User') existing.name = name;
      return existing;
    }
    final p = CallParticipant(id: id, name: name.isEmpty ? 'User' : name);
    _peers[id] = p;
    try {
      await p.renderer.initialize();
      p.rendererReady = true;
      if (p.stream != null) p.renderer.srcObject = p.stream;
    } catch (_) {}
    notifyListeners();
    return p;
  }

  void _dropPeer(int id) {
    final p = _peers.remove(id);
    if (p == null) return;
    final pc = p.pc;
    p.pc = null;
    if (pc != null) {
      pc.onIceCandidate = null;
      pc.onTrack = null;
      pc.onConnectionState = null;
      pc.onIceConnectionState = null;
      try {
        pc.close();
      } catch (_) {}
    }
    p.stream = null;
    if (p.rendererReady) {
      p.renderer.srcObject = null;
      unawaited(p.renderer.dispose());
      p.rendererReady = false;
    }
    if (peerId == id) {
      peerId = _peers.isEmpty ? null : _peers.keys.first;
      if (!isGroup && _peers.isNotEmpty) peerName = _peers.values.first.name;
    }
  }

  void _peerLeft(int id) {
    if (!isGroup) {
      _cleanup(silent: true);
      return;
    }
    _dropPeer(id);
    if (_peers.isEmpty) {
      _cleanup(silent: true);
      return;
    }
    notifyListeners();
  }

  void _armStaleSweep() {
    if (!isGroup) return;
    _staleTimeout?.cancel();
    _staleTimeout = Timer(const Duration(seconds: 47), _pruneUnanswered);
  }

  void _pruneUnanswered() {
    if (!isActive || !isGroup) return;
    for (final p in _peers.values.toList()) {
      if (!p.connected) {
        debugPrint('[call] pruning unanswered peer ${p.id}');
        _dropPeer(p.id);
      }
    }
    if (_peers.isEmpty) {
      _cleanup(silent: true);
      return;
    }
    notifyListeners();
  }

  Future<void> _receiveOffer(CallSignal sig) async {

    if (isActive && callId == sig.callId) {
      await _answerPeerOffer(sig);
      return;
    }

    if (isActive) {
      chat.signal(
        peerId: sig.fromId,
        kind: 'busy',
        callId: sig.callId,
        media: sig.media,
      );
      return;
    }

    final grp = sig.payload?['group'];
    final groupMap = grp is Map ? Map<String, dynamic>.from(grp) : null;
    isGroup = groupMap != null;
    groupName = groupMap?['name']?.toString() ?? '';
    groupConversationId =
        int.tryParse(groupMap?['conversation_id']?.toString() ?? '') ?? 0;
    _roster = _parseRoster(groupMap?['roster']);
    _announced = false;

    callerId = sig.fromId;
    peerId = sig.fromId;
    peerName = sig.fromName.isNotEmpty ? sig.fromName : 'User';
    media = sig.media == 'video' ? CallMedia.video : CallMedia.voice;
    role = CallRole.callee;
    callId = sig.callId;
    phase = CallPhase.ringing;
    muted = false;
    cameraOff = false;
    _frontCamera = true;
    startedAt = null;

    if (sig.payload != null) {
      _pendingOffer = RTCSessionDescription(
        sig.payload!['sdp']?.toString(),
        sig.payload!['type']?.toString(),
      );
    }

    await _addPeer(sig.fromId, peerName);

    unawaited(RingtoneService.instance.startIncoming());

    chat.signal(
      peerId: sig.fromId,
      kind: 'ringing',
      callId: callId!,
      media: _mediaWire(),
    );

    _calleeRingTimeout?.cancel();
    _calleeRingTimeout = Timer(const Duration(seconds: 60), () {
      if (phase == CallPhase.ringing && role == CallRole.callee) {
        if (peerId != null && callId != null) {
          chat.signal(
            peerId: peerId!,
            kind: 'decline',
            callId: callId!,
            media: _mediaWire(),
          );
        }
        _cleanup(silent: true);
      }
    });

    notifyListeners();
  }

  Future<void> _answerPeerOffer(CallSignal sig) async {
    if (_localStream == null || callId == null) return;
    if (_peers.length >= kMeshMaxPeers && !_peers.containsKey(sig.fromId)) return;
    final p = await _addPeer(sig.fromId, sig.fromName);
    if (p.pc != null) return;
    if (sig.payload == null) return;

    final pc = await _createPeer(p);
    for (final t in _localStream!.getTracks()) {
      await pc.addTrack(t, _localStream!);
    }
    try {
      await pc.setRemoteDescription(RTCSessionDescription(
        sig.payload!['sdp']?.toString(),
        sig.payload!['type']?.toString(),
      ));
      p.remoteReady = true;
      await _drainIce(p);
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      debugPrint('[call] → mesh answer to ${p.id}');
      await chat.signal(
        peerId: p.id,
        kind: 'answer',
        callId: callId!,
        media: _mediaWire(),
        payload: {'sdp': answer.sdp, 'type': answer.type},
      );
    } catch (_) {
      debugPrint('[call] mesh answer to ${p.id} failed');
      _dropPeer(p.id);
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>?> _fetchOfferFor(String? id) async {
    if (id == null || id.isEmpty) return null;
    for (var attempt = 0; attempt < 3; attempt++) {
      final cached = await chat.fetchPendingOffer();
      if (cached != null && cached['call_id'] == id) return cached;
      if (attempt < 2) {
        await Future.delayed(const Duration(milliseconds: 700));
      }
    }
    return null;
  }

  Future<void> accept() async {
    if (role != CallRole.callee || _accepting) return;
    _accepting = true;
    try {
      await _accept();
    } finally {
      _accepting = false;
    }
  }

  Future<void> _accept() async {
    if (_pendingOffer == null) {
      debugPrint('[call] accept without a seeded offer — fetching $callId');
      final cached = await _fetchOfferFor(callId);
      if (cached == null) {
        lastError = 'Still reaching the caller — tap answer again';
        notifyListeners();
        return;
      }
      _pendingOffer = RTCSessionDescription(cached['sdp']?.toString(), 'offer');
    }
    unawaited(RingtoneService.instance.stop());

    if (callId != null) {
      unawaited(markIncomingCallConnected(callId!));
      unawaited(dismissIncomingCall(callId!));
    }
    phase = CallPhase.connecting;

    _signalHandledElsewhere();
    _calleeRingTimeout?.cancel();
    _calleeRingTimeout = null;

    _connectingTimeout?.cancel();
    _connectingTimeout = Timer(const Duration(seconds: 30), () {
      if (phase == CallPhase.connecting) {
        debugPrint('[call] connecting timeout — auto ending');
        end(silent: false, reason: 'Connection failed');
      }
    });
    notifyListeners();

    await _ensureRenderers();
    await _refreshIce();

    try {
      if (!await _ensureCapturePermissions(media)) {
        _cleanup(silent: true);
        notifyListeners();
        return;
      }
      _localStream = await _getMedia(media);
      debugPrint('[call] local stream tracks: '
          '${_localStream!.getAudioTracks().length} audio, '
          '${_localStream!.getVideoTracks().length} video');
      localRenderer.srcObject = _localStream;
    } catch (_) {

      unawaited(chat.signal(
        peerId: callerId,
        kind: 'decline',
        callId: callId!,
        media: _mediaWire(),
      ));
      _fail('Could not access ${media == CallMedia.video ? 'camera/mic' : 'microphone'}');
      return;
    }

    final p = await _addPeer(callerId, peerName);
    final pc = await _createPeer(p);
    for (final t in _localStream!.getTracks()) {
      debugPrint('[call] addTrack ${t.kind} enabled=${t.enabled}');
      await pc.addTrack(t, _localStream!);
    }

    try {
      await pc.setRemoteDescription(_pendingOffer!);
      _pendingOffer = null;
      p.remoteReady = true;
      await _drainIce(p);

      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      debugPrint('[call] → answer to ${p.id} callId $callId');
      await chat.signal(
        peerId: p.id,
        kind: 'answer',
        callId: callId!,
        media: _mediaWire(),
        payload: {'sdp': answer.sdp, 'type': answer.type},
      );
    } catch (_) {
      _fail('Could not connect');
      return;
    }

    if (isGroup) {
      _announceJoin();
      _armStaleSweep();
    }
  }

  void _announceJoin() {
    final cid = callId;
    if (cid == null) return;
    _announced = true;
    for (final m in _roster) {
      final id = (m['id'] as num?)?.toInt() ?? 0;
      if (id == 0 || id == myUserId || id == callerId) continue;
      unawaited(chat.signal(
        peerId: id,
        kind: 'join',
        callId: cid,
        media: _mediaWire(),
        payload: {'roster': _roster},
      ));
    }
  }

  Future<void> _handleJoin(CallSignal sig) async {
    if (_localStream == null || callId == null) return;
    if (sig.fromId == 0 || sig.fromId == myUserId) return;

    isGroup = true;
    final incoming = _parseRoster(sig.payload?['roster']);
    if (_roster.isEmpty && incoming.isNotEmpty) {
      _roster = incoming;
      if (!_announced) _announceJoin();
    }

    final existing = _peers[sig.fromId];
    if (existing != null && existing.pc != null) return;
    if (existing == null && _peers.length >= kMeshMaxPeers) return;

    if (myUserId < sig.fromId) {
      final p = existing ?? await _addPeer(sig.fromId, sig.fromName);
      await _offerTo(p);
    } else {
      unawaited(chat.signal(
        peerId: sig.fromId,
        kind: 'join',
        callId: callId!,
        media: _mediaWire(),
        payload: {'roster': _roster},
      ));
    }
  }

  static List<Map<String, dynamic>> _parseRoster(Object? raw) {
    if (raw is! List) return [];
    final out = <Map<String, dynamic>>[];
    for (final e in raw) {
      if (e is Map) {
        final id = int.tryParse(e['id']?.toString() ?? '') ?? 0;
        if (id == 0) continue;
        out.add({'id': id, 'name': (e['name'] ?? 'User').toString()});
      }
    }
    return out;
  }

  Future<void> acceptIncomingFromPush({
    required String callId,
    required int callerId,
    required String callerName,
    required String media,
  }) async {

    if (this.callId == callId && isInLiveCall) {
      debugPrint('[call] acceptIncomingFromPush — already live $callId');
      return;
    }

    if (this.callId == callId &&
        role == CallRole.callee &&
        phase == CallPhase.ringing) {
      debugPrint('[call] acceptIncomingFromPush — answering ringing $callId');
      await accept();
      return;
    }

    if (isActive) {

      await chat.signal(
        peerId: callerId,
        kind: 'busy',
        callId: callId,
        media: media,
      );
      return;
    }

    isGroup = false;
    groupName = '';
    groupConversationId = 0;
    _roster = [];
    _announced = false;

    this.callerId = callerId;
    peerId = callerId;
    peerName = callerName.isNotEmpty ? callerName : 'User';
    this.media = media == 'video' ? CallMedia.video : CallMedia.voice;
    role = CallRole.callee;
    this.callId = callId;
    phase = CallPhase.ringing;
    muted = false;
    cameraOff = false;
    _frontCamera = true;
    startedAt = null;
    notifyListeners();

    await chat.signal(
      peerId: callerId,
      kind: 'ringing',
      callId: callId,
      media: media,
    );

    final cached = await _fetchOfferFor(callId);

    if (cached == null) {
      debugPrint('[call] acceptIncomingFromPush — no cached offer for $callId');
      phase = CallPhase.ringing;
      lastError = 'Could not pick up automatically — tap answer again';
      notifyListeners();
      return;
    }

    _pendingOffer = RTCSessionDescription(
      cached['sdp']?.toString(),
      'offer',
    );

    await accept();
  }

  Future<void> declineIncomingFromPush({
    required String callId,
    required int callerId,
    required String media,
  }) async {
    if (callerId <= 0 || callId.isEmpty) return;

    if (this.callId == callId && isActive) {
      if (role == CallRole.callee && phase == CallPhase.ringing) {
        await decline();
      } else {
        debugPrint('[call] ignoring push decline for in-progress call $callId');
      }
      return;
    }

    await chat.signal(
      peerId: callerId,
      kind: 'decline',
      callId: callId,
      media: media,
    );

    unawaited(chat.signal(
      peerId: myUserId,
      kind: 'handled',
      callId: callId,
      media: media,
    ));
  }

  Future<void> decline() async {
    unawaited(RingtoneService.instance.stop());

    final pid = callerId != 0 ? callerId : peerId;
    final cid = callId;
    final wireMedia = _mediaWire();

    _signalHandledElsewhere();
    _cleanup(silent: true);
    if (pid != null && pid != 0 && cid != null) {
      unawaited(chat.signal(
        peerId: pid,
        kind: 'decline',
        callId: cid,
        media: wireMedia,
      ));
    }
  }

  Future<void> _onSignal(CallSignal sig) async {
    debugPrint('[call] ← ${sig.kind} from ${sig.fromId} callId ${sig.callId}');

    if (sig.kind == 'offer') {

      if (isActive && callId != sig.callId) {
        await chat.signal(
          peerId: sig.fromId,
          kind: 'busy',
          callId: sig.callId,
          media: sig.media,
        );
        return;
      }
      await _receiveOffer(sig);
      return;
    }

    if (sig.kind == 'ice' && (!isActive || callId != sig.callId)) {
      _bufferEarlyIce(sig);
      return;
    }

    if (!isActive || callId != sig.callId) return;

    if (sig.kind == 'join') {
      await _handleJoin(sig);
      return;
    }

    final p = _peers[sig.fromId];

    switch (sig.kind) {
      case 'answer':
        if (p?.pc == null || sig.payload == null) return;
        try {
          await p!.pc!.setRemoteDescription(RTCSessionDescription(
            sig.payload!['sdp']?.toString(),
            sig.payload!['type']?.toString(),
          ));
          p.remoteReady = true;
          await _drainIce(p);

          unawaited(RingtoneService.instance.stop());

          if (isGroup && role == CallRole.caller) {
            unawaited(chat.signal(
              peerId: sig.fromId,
              kind: 'join',
              callId: callId!,
              media: _mediaWire(),
              payload: {'roster': _roster},
            ));
          }
        } catch (_) {}
        break;
      case 'ice':
        if (sig.payload == null) return;
        final cand = _candidateOf(sig);
        _remoteCandidateCount++;
        _remoteCandidateKinds.add(
            _candidateKind(sig.payload?['candidate']?.toString()));
        _publishIceDiagnostics();
        if (p == null) {
          _bufferEarlyIce(sig);
          break;
        }
        p.pendingIce.add(cand);
        await _drainIce(p);
        break;
      case 'ringing':
        if (role == CallRole.caller && phase == CallPhase.calling) {
          phase = CallPhase.ringing;
          notifyListeners();
        }
        break;
      case 'handled':
        if (sig.callId.isNotEmpty) {
          unawaited(dismissIncomingCall(sig.callId));
        }
        if (role == CallRole.callee && phase == CallPhase.ringing) {
          _cleanup(silent: true);
        }
        break;
      case 'decline':
      case 'busy':
      case 'end':
        if (sig.callId.isNotEmpty && callId != sig.callId) {
          unawaited(dismissIncomingCall(sig.callId));
        }
        _peerLeft(sig.fromId);
        break;
    }
  }

  RTCIceCandidate _candidateOf(CallSignal sig) => RTCIceCandidate(
        sig.payload!['candidate']?.toString(),
        sig.payload!['sdpMid']?.toString(),
        (sig.payload!['sdpMLineIndex'] as num?)?.toInt(),
      );

  void _bufferEarlyIce(CallSignal sig) {
    if (sig.payload == null) return;
    final key = '${sig.callId}|${sig.fromId}';
    _earlyIce.putIfAbsent(key, () => []).add(_candidateOf(sig));
    debugPrint('[call] remote ICE buffered (pre-offer) for ${sig.fromId}');
  }

  Future<void> _drainIce(CallParticipant p) async {
    final early = _earlyIce.remove('$callId|${p.id}');
    if (early != null && early.isNotEmpty) {
      p.pendingIce.addAll(early);
      debugPrint('[call] queued ${early.length} pre-offer ICE for ${p.id}');
    }
    final pc = p.pc;
    if (pc == null || !p.remoteReady || p.pendingIce.isEmpty) return;
    final queued = List<RTCIceCandidate>.from(p.pendingIce);
    p.pendingIce.clear();
    var added = 0;
    for (final c in queued) {
      try {
        await pc.addCandidate(c);
        added++;
      } catch (_) {
        p.pendingIce.add(c);
      }
    }
    debugPrint('[call] added $added/${queued.length} ICE for ${p.id}'
        '${p.pendingIce.isEmpty ? '' : ' (${p.pendingIce.length} requeued)'}');
  }

  Future<RTCPeerConnection> _createPeer(CallParticipant p) async {
    final pc = await createPeerConnection({
      'iceServers': _ice,
      'iceTransportPolicy': 'all',
      'sdpSemantics': 'unified-plan',
    });
    p.pc = pc;
    pc.onIceCandidate = (RTCIceCandidate cand) {
      if (cand.candidate != null) {
        _localCandidateCount++;
        _publishIceDiagnostics();
      }
      if (cand.candidate == null) {
        debugPrint('[call] local ICE: end-of-candidates for ${p.id}');
        return;
      }
      if (callId == null) return;
      chat.signal(
        peerId: p.id,
        kind: 'ice',
        callId: callId!,
        media: _mediaWire(),
        payload: {
          'candidate': cand.candidate,
          'sdpMid': cand.sdpMid,
          'sdpMLineIndex': cand.sdpMLineIndex,
        },
      );
    };
    pc.onIceGatheringState = (state) {
      debugPrint('[call] ${p.id} iceGatheringState = $state');
    };
    pc.onIceConnectionState = (state) {
      debugPrint('[call] ${p.id} iceConnectionState = $state '
          '(turn=$_hasTurn, servers=${_ice.length})');
      _iceState = state.name.replaceFirst('RTCIceConnectionState', '');
      _publishIceDiagnostics();
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _onPeerConnected(p);
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _peerLeft(p.id);
      }
    };
    pc.onTrack = (RTCTrackEvent event) {
      if (event.streams.isEmpty) return;
      p.stream = event.streams.first;
      if (p.rendererReady) p.renderer.srcObject = p.stream;
      notifyListeners();
    };
    pc.onConnectionState = (RTCPeerConnectionState state) {
      debugPrint('[call] ${p.id} connectionState = $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _onPeerConnected(p);
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _peerLeft(p.id);
      }
    };
    return pc;
  }

  void _onPeerConnected(CallParticipant p) {
    final wasConnected = p.connected;
    p.connected = true;
    if (phase != CallPhase.connected) {
      phase = CallPhase.connected;
      startedAt ??= DateTime.now();
      _ringTimeout?.cancel();
      _ringTimeout = null;
      _connectingTimeout?.cancel();
      _connectingTimeout = null;
      _timer ??= Timer.periodic(
          const Duration(seconds: 1), (_) => notifyListeners());
      notifyListeners();
    } else if (!wasConnected) {
      notifyListeners();
    }
  }

  Future<void> _refreshIce() async {
    if (_iceOverride != null) {
      _ice = _iceOverride;
      return;
    }
    final now = DateTime.now();
    if (_iceExpiresAt != null && now.isBefore(_iceExpiresAt!)) return;

    final res = await chat.iceServers();
    if (res == null) {
      _hasTurn = false;
      debugPrint('[call] ICE fetch failed — using STUN-only fallback');
      lastError = 'No relay server available — this call may not connect';
      return;
    }

    final out = <Map<String, dynamic>>[];
    for (final entry in (res['iceServers'] as List)) {
      if (entry is! Map) continue;
      final m = Map<String, dynamic>.from(entry);
      final urls = m['urls'];
      final list = urls is List ? urls : [urls];
      for (final u in list) {
        if (u == null) continue;
        final one = <String, dynamic>{'urls': u.toString()};
        if (m['username'] != null) one['username'] = m['username'].toString();
        if (m['credential'] != null) {
          one['credential'] = m['credential'].toString();
        }
        out.add(one);
      }
    }
    if (out.isEmpty) {
      _hasTurn = false;
      debugPrint('[call] ICE list empty — using STUN-only fallback');
      lastError = 'No relay server available — this call may not connect';
      return;
    }

    _ice = out;
    final ttl = (res['ttl'] as num?)?.toInt() ?? 43200;
    _iceExpiresAt = now.add(Duration(seconds: (ttl ~/ 2).clamp(150, 86400)));
    _hasTurn = res['has_turn'] == true;
    debugPrint('[call] ICE ready: ${out.length} server(s), turn=$_hasTurn');
    if (!_hasTurn) {
      lastError = 'No relay server available — this call may not connect';
    }
  }

  Future<bool> _ensureCapturePermissions(CallMedia mediaKind) async {
    if (!kIsMobilePlatform) return true;
    try {
      final wanted = <Permission>[
        Permission.microphone,
        if (mediaKind == CallMedia.video) Permission.camera,
      ];
      final statuses = await wanted.request();
      final denied = statuses.entries
          .where((e) => !e.value.isGranted)
          .map((e) => e.key == Permission.camera ? 'camera' : 'microphone')
          .toList();
      if (denied.isEmpty) return true;
      debugPrint('[call] capture permission denied: ${denied.join(", ")}');
      lastError = 'Allow ${denied.join(" and ")} access to take calls';
      return false;
    } catch (e) {
      debugPrint('[call] permission request failed: $e');
      return true;
    }
  }

  Future<MediaStream> _getMedia(CallMedia mediaKind) {
    final constraints = <String, dynamic>{
      'audio': true,
      'video': mediaKind == CallMedia.video
          ? {
              'facingMode': _frontCamera ? 'user' : 'environment',
              'width': {'ideal': 1280},
              'height': {'ideal': 720},
            }
          : false,
    };
    return navigator.mediaDevices.getUserMedia(constraints);
  }

  void toggleMute() {
    if (_localStream == null) return;
    muted = !muted;
    for (final t in _localStream!.getAudioTracks()) {
      t.enabled = !muted;
    }
    notifyListeners();
  }

  void toggleCamera() {
    if (_localStream == null || media != CallMedia.video) return;
    cameraOff = !cameraOff;
    for (final t in _localStream!.getVideoTracks()) {
      t.enabled = !cameraOff;
    }
    notifyListeners();
  }

  Future<void> switchCamera() async {
    if (_localStream == null || media != CallMedia.video) return;
    final tracks = _localStream!.getVideoTracks();
    if (tracks.isEmpty) return;
    try {
      await Helper.switchCamera(tracks.first);
      _frontCamera = !_frontCamera;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> end({bool silent = false, String? reason}) async {
    debugPrint('[call] end() phase=$phase silent=$silent reason=$reason');
    unawaited(RingtoneService.instance.stop());
    final targets = _peers.keys.toList();
    final cid = callId;
    final wasActive = isActive;
    final wireMedia = _mediaWire();

    _cleanup(silent: true);
    if (!silent && wasActive && cid != null) {

      for (final pid in targets) {
        unawaited(chat.signal(
          peerId: pid,
          kind: 'end',
          callId: cid,
          media: wireMedia,
        ));
      }
    }
  }

  void forceReset() {
    if (phase == CallPhase.idle) return;
    _cleanup(silent: true);
  }

  void _cleanup({required bool silent}) {

    final dismissCallId = callId;
    if (dismissCallId != null && dismissCallId.isNotEmpty) {
      unawaited(dismissIncomingCall(dismissCallId));
    }
    unawaited(RingtoneService.instance.stop());
    _ringTimeout?.cancel();
    _ringTimeout = null;
    _calleeRingTimeout?.cancel();
    _calleeRingTimeout = null;
    _connectingTimeout?.cancel();
    _connectingTimeout = null;
    _staleTimeout?.cancel();
    _staleTimeout = null;
    _timer?.cancel();
    _timer = null;

    for (final id in _peers.keys.toList()) {
      _dropPeer(id);
    }
    _peers.clear();

    final stream = _localStream;
    _localStream = null;
    if (stream != null) {
      for (final t in stream.getTracks()) {
        try {
          t.stop();
        } catch (_) {}
      }
      try {
        stream.dispose();
      } catch (_) {}
    }

    if (_renderersReady) {
      localRenderer.srcObject = null;
    }

    phase = CallPhase.ended;
    role = null;
    peerId = null;
    peerName = '';
    callId = null;
    media = CallMedia.voice;
    muted = false;
    cameraOff = false;
    startedAt = null;
    isGroup = false;
    groupName = '';
    groupConversationId = 0;
    callerId = 0;
    _roster = [];
    _announced = false;
    _pendingOffer = null;
    _earlyIce.clear();

    notifyListeners();

    Future<void>.delayed(const Duration(milliseconds: 50), () {
      if (_disposed) return;
      if (phase == CallPhase.ended) {
        phase = CallPhase.idle;
        notifyListeners();
      }
    });
  }

  void _fail(String _) {

    _cleanup(silent: true);
  }

  String _mediaWire() => media == CallMedia.video ? 'video' : 'voice';

  void _signalHandledElsewhere() {
    final cid = callId;
    if (cid == null) return;
    unawaited(chat.signal(
      peerId: myUserId,
      kind: 'handled',
      callId: cid,
      media: _mediaWire(),
    ));
  }

  Future<void> _ensureRenderers() async {
    if (_renderersReady) return;
    await localRenderer.initialize();
    _renderersReady = true;
  }

  static String _newCallId() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int n, int width) =>
        n.toRadixString(16).padLeft(width, '0');
    final s = StringBuffer();
    for (var i = 0; i < bytes.length; i++) {
      s.write(hex(bytes[i], 2));
      if (i == 3 || i == 5 || i == 7 || i == 9) s.write('-');
    }
    return s.toString();
  }

  bool _disposed = false;

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _signalSub?.cancel();
    _signalSub = null;
    _cleanup(silent: true);
    if (_renderersReady) {
      await localRenderer.dispose();
    }
    super.dispose();
  }
}
