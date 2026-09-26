import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models/chat_models.dart';
import 'chat_realtime.dart';
import 'chat_service.dart';
import 'ringtone_service.dart';

// Desktop build: there is no native CallKit/incoming-call sheet (that's the
// mobile killed-app push path). Incoming calls arrive live over the realtime
// signaling channel instead, so the CallKit dismiss is a no-op here.
Future<void> dismissIncomingCall(String callId) async {}

/// Phase of a call. Maps 1:1 with the JS `call.state` machine on the web side.
enum CallPhase { idle, calling, ringing, connecting, connected, ended }

/// Voice or video. Drives whether we request a video track from the OS and
/// whether the call screen renders the remote video.
enum CallMedia { voice, video }

/// Caller (we initiated) vs callee (they initiated, we're answering).
enum CallRole { caller, callee }

/// Upper bound on mesh size. Every participant uploads their media once per
/// other participant, so this stops a large channel from melting the device.
const int kMeshMaxPeers = 6;

/// One remote participant: their peer connection, media, and video surface.
/// A two-party call is just a mesh with a single entry.
class CallParticipant {
  CallParticipant({required this.id, required this.name});

  final int id;
  String name;
  RTCPeerConnection? pc;
  MediaStream? stream;
  final RTCVideoRenderer renderer = RTCVideoRenderer();
  final List<RTCIceCandidate> pendingIce = [];
  bool connected = false;
  bool rendererReady = false;

  bool get hasVideo => stream != null && stream!.getVideoTracks().isNotEmpty;

  String get initial =>
      name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
}

/// Single in-flight call, two-party or group. Group calls run as a full mesh
/// (every participant holds a peer connection to every other), which is why
/// [kMeshMaxPeers] is deliberately small — beyond that an SFU is required.
///
/// Lifecycle:
///   * caller: open → calling → ringing → connecting → connected → ended
///   * callee: receive offer → ringing → accept/decline → connecting → connected → ended
///
/// Mesh formation: the caller fans an offer out to every invitee, carrying the
/// roster. Each callee that accepts broadcasts `join` to the rest; whichever
/// side has the lower user id sends the offer, so two peers never dial each
/// other at once. Invitees still ringing ignore joins and announce themselves
/// when they accept, so the mesh converges regardless of accept order.
///
/// Consumers listen via `addListener`; the call screen (re-)renders on each
/// notification. The service owns the streams, peer connections, renderers,
/// and timer; UI only consumes.
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

  // ── Public state (read-only views for the UI) ────────────────────────
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

  /// Self-preview surface. The call screen wires this to a [RTCVideoView].
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  bool _renderersReady = false;

  // ── Internals ────────────────────────────────────────────────────────
  final Map<int, CallParticipant> _peers = {};
  List<Map<String, dynamic>> _roster = [];
  bool _announced = false;

  MediaStream? _localStream;
  RTCSessionDescription? _pendingOffer; // callee: cached until accept()

  /// ICE candidates that arrive on the wire BEFORE the offer signal does.
  /// Keyed by `callId|fromId` so a stale call's leftover candidates can never
  /// bleed into a new call, and a mesh peer's candidates can't be applied to
  /// the wrong connection. Drained inside [_drainIce].
  final Map<String, List<RTCIceCandidate>> _earlyIce = {};

  Timer? _timer;
  Timer? _ringTimeout;        // caller-side 45s "no answer" guard
  Timer? _calleeRingTimeout;  // callee-side 60s "caller never followed up" guard
  Timer? _connectingTimeout;  // 30s guard for stuck connecting phase (ICE never completes)
  Timer? _staleTimeout;       // group: prune invitees who never answered

  /// Every remote participant, ordered by join. The call screen builds its
  /// grid from this; a two-party call yields exactly one entry.
  List<CallParticipant> get participants => _peers.values.toList();

  /// Primary remote video surface — the only one in a two-party call. Null
  /// before anyone is added, so the call screen must null-check.
  RTCVideoRenderer? get remoteRenderer =>
      _peers.isEmpty ? null : _peers.values.first.renderer;

  bool get isActive =>
      phase != CallPhase.idle && phase != CallPhase.ended;

  /// True only when a real peer connection is established or actively
  /// negotiating media. Distinct from [isActive], which is also true for
  /// stuck "calling" / "ringing" phases that never reached the network.
  bool get isInLiveCall =>
      phase == CallPhase.connecting || phase == CallPhase.connected;

  /// True when an incoming offer is sitting in front of the user awaiting
  /// accept/decline. Used by the chat thread screen to give a different
  /// message ("ANSWER INCOMING CALL FIRST") instead of force-resetting.
  bool get isIncomingRinging =>
      phase == CallPhase.ringing && role == CallRole.callee;

  /// Display title — the group name for a mesh call, the peer's name for a DM.
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

  // ── Outgoing call ────────────────────────────────────────────────────

  /// Initiate a two-party call to [peerId]. Returns false if a call is already
  /// active or if media access was denied.
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

  /// Initiate a mesh call across a group/channel. [members] is every invitee
  /// except me, as `{'id': int, 'name': String}`. Returns false when a call is
  /// already active, the roster is empty or oversized, or media was denied.
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

    // Auto-cancel if no one answers within 45 s.
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

  // ── Peer registry ────────────────────────────────────────────────────

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

  /// One participant dropped out. In a two-party call that ends everything;
  /// in a mesh the call survives until the last peer is gone.
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

  // ── Incoming call ────────────────────────────────────────────────────

  Future<void> _receiveOffer(CallSignal sig) async {
    // Already in this same call → a mesh peer is dialing us directly.
    if (isActive && callId == sig.callId) {
      await _answerPeerOffer(sig);
      return;
    }
    // Already in a different call → politely tell the other side we're busy.
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

    // Foreground ringtone — kicks in only when CallKit isn't already
    // covering the ring (i.e. the offer arrived via Pusher in-app, not
    // via FCM data push waking up the killed app).
    unawaited(RingtoneService.instance.startIncoming());

    // Acknowledge so the caller can flip to "Ringing…"
    chat.signal(
      peerId: sig.fromId,
      kind: 'ringing',
      callId: callId!,
      media: _mediaWire(),
    );

    // Auto-decline if the user never picks up. Without this, a caller who
    // hangs up before we accept would leave us stuck in `ringing` forever.
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

  /// A peer we're already in a call with sent us an offer — the mesh pairing
  /// path. We have media up, so answer immediately without ringing the user.
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

  /// Callee answers. Spins up local media + peer connection, replies with
  /// SDP answer, and drains queued ICE.
  Future<void> accept() async {
    if (role != CallRole.callee || _pendingOffer == null) return;
    unawaited(RingtoneService.instance.stop());
    phase = CallPhase.connecting;
    // Dismiss the incoming UI on our OWN other surfaces (web, mobile, another
    // desktop session) — they ring the same private-user-{me} channel. Sent
    // after the phase flip so our own echo is ignored (we only dismiss while
    // still `ringing`).
    _signalHandledElsewhere();
    _calleeRingTimeout?.cancel();
    _calleeRingTimeout = null;
    // If ICE never completes (peer's answer lost, NAT issues, no TURN, etc.)
    // the connecting phase would otherwise hang forever — UI buttons remain
    // visible but the user has no signal that the call is wedged. Auto-end.
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
      _localStream = await _getMedia(media);
      debugPrint('[call] local stream tracks: '
          '${_localStream!.getAudioTracks().length} audio, '
          '${_localStream!.getVideoTracks().length} video');
      localRenderer.srcObject = _localStream;
    } catch (_) {
      // Fire-and-forget the decline so a slow signal POST can't wedge us in
      // the connecting state — _fail() tears the call down immediately.
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

  /// Tell every other invitee we're in. Whoever is already in the call pairs
  /// with us; the lower user id always sends the offer so both sides never
  /// dial each other at once. Invitees still ringing ignore this and announce
  /// themselves when they accept.
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
    // A join can only happen in a mesh. Trusting it here is what lets a
    // cold-start callee — whose cached push offer carried no roster — still
    // discover the rest of the call.
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

  /// Killed-app path: user just tapped Accept on the native CallKit sheet.
  /// We don't have the offer SDP yet (the Soketi `offer` signal was missed
  /// while the app wasn't running), so we seed local state, fetch the
  /// cached SDP from the server, then run the normal accept() flow.
  ///
  /// Idempotent on the same callId — a duplicate Accept (e.g. CallKit
  /// firing twice on cold start) is a no-op while we're already setting
  /// up that call.
  Future<void> acceptIncomingFromPush({
    required String callId,
    required int callerId,
    required String callerName,
    required String media,
  }) async {
    if (this.callId == callId && isActive) {
      debugPrint('[call] acceptIncomingFromPush — already handling $callId');
      return;
    }
    if (isActive) {
      // Some other call is in flight — politely busy out the new one.
      await chat.signal(
        peerId: callerId,
        kind: 'busy',
        callId: callId,
        media: media,
      );
      return;
    }

    // The cached offer carries no roster, so a group call answered from a
    // cold start starts out looking two-party. The `join` other participants
    // send on their own accept promotes it back to a mesh (see [_handleJoin]).
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

    // Send the `ringing` ack now so the caller flips from "Calling…" to
    // "Ringing…" while we're still fetching the SDP. (The actual SDP-set
    // and `answer` happen inside accept() below.)
    await chat.signal(
      peerId: callerId,
      kind: 'ringing',
      callId: callId,
      media: media,
    );

    final cached = await chat.fetchPendingOffer();
    if (cached == null || cached['call_id'] != callId) {
      // Caller hung up between push send and our accept — nothing to
      // negotiate. Tell them and clean up.
      debugPrint('[call] acceptIncomingFromPush — no cached offer for $callId');
      await chat.signal(
        peerId: callerId,
        kind: 'decline',
        callId: callId,
        media: media,
      );
      _cleanup(silent: true);
      return;
    }

    _pendingOffer = RTCSessionDescription(
      cached['sdp']?.toString(),
      'offer',
    );

    await accept();
  }

  /// Killed-app path: user tapped Decline on the native CallKit sheet.
  /// Send the decline signal so the caller stops ringing; no local call
  /// state to clean up because we never seeded any.
  Future<void> declineIncomingFromPush({
    required String callId,
    required int callerId,
    required String media,
  }) async {
    if (callerId <= 0 || callId.isEmpty) return;
    await chat.signal(
      peerId: callerId,
      kind: 'decline',
      callId: callId,
      media: media,
    );
  }

  /// Callee declines. Notifies caller and cleans up local state.
  Future<void> decline() async {
    unawaited(RingtoneService.instance.stop());
    // Capture peer/call/media BEFORE cleanup wipes them, then tear down the
    // UI first so the incoming screen dismisses instantly — don't gate the
    // user's escape on a slow/failed `decline` POST (the caller will hit
    // their own ring timeout if the signal never lands).
    final pid = callerId != 0 ? callerId : peerId;
    final cid = callId;
    final wireMedia = _mediaWire();
    // Dismiss the incoming UI on our own other surfaces before cleanup wipes
    // the call id (they ring the same private-user-{me} channel).
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

  // ── Inbound signaling (offer/answer/ICE/control) ────────────────────

  Future<void> _onSignal(CallSignal sig) async {
    debugPrint('[call] ← ${sig.kind} from ${sig.fromId} callId ${sig.callId}');

    if (sig.kind == 'offer') {
      // Fresh offer for a different callId while we're busy → reject.
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

    // ICE may race ahead of offer/answer SDP. Buffer pre-offer ICE keyed
    // on callId + sender so it isn't lost when the callee hasn't seen the
    // offer yet, and can't be applied to the wrong mesh connection.
    if (sig.kind == 'ice' && (!isActive || callId != sig.callId)) {
      _bufferEarlyIce(sig);
      return;
    }

    // All other kinds must match the in-flight call.
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
          await _drainIce(p);
          // Peer answered — silence the caller's ringback.
          unawaited(RingtoneService.instance.stop());
          // A callee whose offer arrived without a roster (cold-start push)
          // learns the rest of the mesh from this.
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
        if (p == null) {
          _bufferEarlyIce(sig);
          break;
        }
        final pc = p.pc;
        if (pc == null) {
          p.pendingIce.add(cand);
          break;
        }
        try {
          final rd = await pc.getRemoteDescription();
          if (rd != null) {
            await pc.addCandidate(cand);
          } else {
            p.pendingIce.add(cand);
          }
        } catch (_) {
          p.pendingIce.add(cand);
        }
        break;
      case 'ringing':
        if (role == CallRole.caller && phase == CallPhase.calling) {
          phase = CallPhase.ringing;
          notifyListeners();
        }
        break;
      case 'handled':
        // Another of our OWN surfaces (web, desktop, another mobile session)
        // accepted or declined this same incoming call. Silently dismiss our
        // still-ringing UI — don't signal the caller; the surface that handled
        // it already did. Ignored once we've moved past `ringing` (so our own
        // accept-echo can't tear down the live call we just answered).
        if (role == CallRole.callee && phase == CallPhase.ringing) {
          _cleanup(silent: true);
        }
        break;
      case 'decline':
      case 'busy':
      case 'end':
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
      debugPrint('[call] drained ${early.length} pre-offer ICE for ${p.id}');
    }
    final pc = p.pc;
    if (pc == null) return;
    for (final c in p.pendingIce) {
      try {
        await pc.addCandidate(c);
      } catch (_) {}
    }
    p.pendingIce.clear();
  }

  // ── Peer connection wiring ───────────────────────────────────────────

  Future<RTCPeerConnection> _createPeer(CallParticipant p) async {
    final pc = await createPeerConnection({
      'iceServers': _ice,
      'iceTransportPolicy': 'all',
      'sdpSemantics': 'unified-plan',
    });
    p.pc = pc;
    pc.onIceCandidate = (RTCIceCandidate cand) {
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
      debugPrint('[call] ${p.id} iceConnectionState = $state');
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

  /// Pull fresh ICE config (STUN + ephemeral TURN credentials) from the
  /// server, caching it for half the credential lifetime so a call started
  /// near the boundary stays valid for its whole duration. On any failure we
  /// keep the previous config — public STUN alone still covers most direct
  /// calls, though not a peer behind symmetric NAT.
  ///
  /// Entries whose `urls` is a list are expanded to one entry per URL, which
  /// every flutter_webrtc platform accepts.
  Future<void> _refreshIce() async {
    if (_iceOverride != null) {
      _ice = _iceOverride;
      return;
    }
    final now = DateTime.now();
    if (_iceExpiresAt != null && now.isBefore(_iceExpiresAt!)) return;

    final res = await chat.iceServers();
    if (res == null) return;

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
    if (out.isEmpty) return;

    _ice = out;
    final ttl = (res['ttl'] as num?)?.toInt() ?? 43200;
    _iceExpiresAt = now.add(Duration(seconds: (ttl ~/ 2).clamp(150, 86400)));
    if (res['has_turn'] != true) {
      debugPrint('[call] no TURN configured — calls will fail behind symmetric NAT');
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

  // ── User actions ─────────────────────────────────────────────────────

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

  /// End the call. If [silent] is true, no `end` signal is sent (used when
  /// we're responding to a remote `end`/`decline`/`busy` so we don't echo).
  Future<void> end({bool silent = false, String? reason}) async {
    debugPrint('[call] end() phase=$phase silent=$silent reason=$reason');
    unawaited(RingtoneService.instance.stop());
    final targets = _peers.keys.toList();
    final cid = callId;
    final wasActive = isActive;
    final wireMedia = _mediaWire();
    // Cleanup first so the UI pops even if the network round-trip below
    // is slow / fails. Don't gate the user's escape on a successful POST.
    _cleanup(silent: true);
    if (!silent && wasActive && cid != null) {
      // Fire-and-forget: don't await. If this fails (offline, 401, etc.)
      // we've still cleaned up locally — the peer will hit their own
      // ringing/connecting timeout. Awaiting here used to hold the Future
      // open with no UI consequence, which was confusing during debugging.
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

  /// Nuke any in-flight call state without sending an `end` signal. Used by
  /// [_placeCall] in the chat thread to recover from a stuck `calling` /
  /// `ringing` (caller side) without forcing the user to restart the app.
  /// Safe to call from any phase — silent on idle.
  void forceReset() {
    if (phase == CallPhase.idle) return;
    _cleanup(silent: true);
  }

  void _cleanup({required bool silent}) {
    // Dismiss any native incoming-call sheet (Android CallKit shown from the
    // FCM background path). Without this, a caller hanging up before we
    // answer leaves the heads-up incoming UI stuck on screen. Idempotent and
    // a no-op for outgoing calls / platforms without CallKit.
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

    // Only touch the renderer if it was actually initialized. Declining an
    // incoming call tears down before accept() ever calls _ensureRenderers,
    // and setting srcObject on an uninitialized renderer throws
    // "Call initialize before setting the stream".
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

    // Settle to idle on the next tick so the UI can fade out the "ended"
    // state if it wants to. Guard on _disposed: dispose() calls _cleanup and
    // then super.dispose() synchronously, so this timer would otherwise fire
    // notifyListeners() on an already-disposed notifier (e.g. on hot restart).
    Future<void>.delayed(const Duration(milliseconds: 50), () {
      if (_disposed) return;
      if (phase == CallPhase.ended) {
        phase = CallPhase.idle;
        notifyListeners();
      }
    });
  }

  void _fail(String _) {
    // Cleanup, no signal — caller hasn't sent anything actionable yet.
    _cleanup(silent: true);
  }

  String _mediaWire() => media == CallMedia.video ? 'video' : 'voice';

  /// Broadcast a `handled` signal to our OWN user channel so any other surface
  /// (web, mobile, another desktop session) still ringing this same
  /// incoming call dismisses it. Fire-and-forget; no-op without a call id.
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
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
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
