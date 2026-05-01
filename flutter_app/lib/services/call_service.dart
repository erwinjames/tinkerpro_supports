import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models/chat_models.dart';
import 'chat_realtime.dart';
import 'chat_service.dart';
import 'ringtone_service.dart';

/// Phase of a call. Maps 1:1 with the JS `call.state` machine on the web side.
enum CallPhase { idle, calling, ringing, connecting, connected, ended }

/// Voice or video. Drives whether we request a video track from the OS and
/// whether the call screen renders the remote video.
enum CallMedia { voice, video }

/// Caller (we initiated) vs callee (they initiated, we're answering).
enum CallRole { caller, callee }

/// Single in-flight call. Two-party only — group/multiparty needs an SFU
/// (LiveKit / Mediasoup), which is out of scope for the MVP.
///
/// Lifecycle:
///   * caller: open → calling → ringing → connecting → connected → ended
///   * callee: receive offer → ringing → accept/decline → connecting → connected → ended
///
/// Consumers listen via `addListener`; the call screen (re-)renders on each
/// notification. The service owns the streams, peer connection, renderers,
/// and timer; UI only consumes.
class CallService extends ChangeNotifier {
  CallService({
    required this.realtime,
    required this.chat,
    required this.myUserId,
    List<Map<String, dynamic>>? iceServers,
  }) : _iceServers = iceServers ??
            const [
              {'urls': 'stun:stun.l.google.com:19302'},
              {'urls': 'stun:stun1.l.google.com:19302'},
              // For production add a TURN server:
              // {'urls': 'turn:turn.example.com:3478', 'username': '...', 'credential': '...'}
            ] {
    _signalSub = realtime.callSignalEvents.listen(_onSignal);
  }

  final ChatRealtimeService realtime;
  final ChatService chat;
  final int myUserId;
  final List<Map<String, dynamic>> _iceServers;
  StreamSubscription<CallSignal>? _signalSub;

  // ── Public state (read-only views for the UI) ────────────────────────
  CallPhase phase = CallPhase.idle;
  CallRole? role;
  CallMedia media = CallMedia.voice;
  int? peerId;
  String peerName = '';
  String? callId;

  bool muted = false;
  bool cameraOff = false;
  bool _frontCamera = true;
  DateTime? startedAt;

  /// Self-preview surface. The call screen wires this to a [RTCVideoView].
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();
  bool _renderersReady = false;

  // ── Internals ────────────────────────────────────────────────────────
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  RTCSessionDescription? _pendingOffer; // callee: cached until accept()
  final List<RTCIceCandidate> _pendingIce = [];

  /// ICE candidates that arrive on the wire BEFORE the offer signal does.
  /// Keyed by callId so a stale call's leftover candidates can never bleed
  /// into a new call. Drained inside [_receiveOffer].
  final Map<String, List<RTCIceCandidate>> _earlyIce = {};

  Timer? _timer;
  Timer? _ringTimeout;        // caller-side 45s "no answer" guard
  Timer? _calleeRingTimeout;  // callee-side 60s "caller never followed up" guard
  Timer? _connectingTimeout;  // 30s guard for stuck connecting phase (ICE never completes)

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

  /// Initiate a call to [peerId]. Returns false if a call is already active
  /// or if media access was denied.
  Future<bool> placeCall({
    required int peerId,
    required String peerName,
    required CallMedia media,
  }) async {
    if (isActive) return false;
    this.peerId = peerId;
    this.peerName = peerName;
    this.media = media;
    role = CallRole.caller;
    callId = _newCallId();
    phase = CallPhase.calling;
    muted = false;
    cameraOff = false;
    _frontCamera = true;
    startedAt = null;
    _pendingIce.clear();
    _pendingOffer = null;

    await _ensureRenderers();
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

    _pc = await _createPeer();
    for (final t in _localStream!.getTracks()) {
      debugPrint('[call] addTrack ${t.kind} enabled=${t.enabled}');
      await _pc!.addTrack(t, _localStream!);
    }

    try {
      final offer = await _pc!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': media == CallMedia.video,
      });
      await _pc!.setLocalDescription(offer);
      debugPrint('[call] local SDP after setLocal:\n${offer.sdp}');
      debugPrint('[call] → offer to $peerId callId $callId');
      await chat.signal(
        peerId: peerId,
        kind: 'offer',
        callId: callId!,
        media: _mediaWire(),
        payload: {'sdp': offer.sdp, 'type': offer.type},
      );
      // Auto-cancel if no one answers within 45 s.
      _ringTimeout = Timer(const Duration(seconds: 45), () {
        if (phase == CallPhase.calling || phase == CallPhase.ringing) {
          end(silent: false, reason: 'No answer');
        }
      });
    } catch (_) {
      _fail('Could not start call');
      return false;
    }
    return true;
  }

  // ── Incoming call ────────────────────────────────────────────────────

  void _receiveOffer(CallSignal sig) {
    // Already in a call → politely tell the other side we're busy.
    if (isActive) {
      chat.signal(
        peerId: sig.fromId,
        kind: 'busy',
        callId: sig.callId,
        media: sig.media,
      );
      return;
    }
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
    _pendingIce.clear();

    if (sig.payload != null) {
      _pendingOffer = RTCSessionDescription(
        sig.payload!['sdp']?.toString(),
        sig.payload!['type']?.toString(),
      );
    }

    // Recover ICE candidates that arrived before this offer (race condition).
    final early = _earlyIce.remove(sig.callId);
    if (early != null && early.isNotEmpty) {
      _pendingIce.addAll(early);
      debugPrint('[call] drained ${early.length} pre-offer ICE');
    }

    // Foreground ringtone — kicks in only when CallKit isn't already
    // covering the ring (i.e. the offer arrived via Pusher in-app, not
    // via FCM data push waking up the killed app).
    unawaited(RingtoneService.instance.startIncoming());

    // Acknowledge so the caller can flip to "Ringing…"
    chat.signal(
      peerId: peerId!,
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

  /// Callee answers. Spins up local media + peer connection, replies with
  /// SDP answer, and drains queued ICE.
  Future<void> accept() async {
    if (role != CallRole.callee || _pendingOffer == null) return;
    unawaited(RingtoneService.instance.stop());
    phase = CallPhase.connecting;
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

    try {
      _localStream = await _getMedia(media);
      debugPrint('[call] local stream tracks: '
          '${_localStream!.getAudioTracks().length} audio, '
          '${_localStream!.getVideoTracks().length} video');
      localRenderer.srcObject = _localStream;
    } catch (_) {
      await chat.signal(
        peerId: peerId!,
        kind: 'decline',
        callId: callId!,
        media: _mediaWire(),
      );
      _fail('Could not access ${media == CallMedia.video ? 'camera/mic' : 'microphone'}');
      return;
    }

    _pc = await _createPeer();
    for (final t in _localStream!.getTracks()) {
      debugPrint('[call] addTrack ${t.kind} enabled=${t.enabled}');
      await _pc!.addTrack(t, _localStream!);
    }

    try {
      await _pc!.setRemoteDescription(_pendingOffer!);
      _pendingOffer = null;

      // Drain ICE that arrived before remoteDescription was ready.
      for (final c in _pendingIce) {
        try {
          await _pc!.addCandidate(c);
        } catch (_) {}
      }
      _pendingIce.clear();

      final answer = await _pc!.createAnswer();
      await _pc!.setLocalDescription(answer);
      debugPrint('[call] local SDP after setLocal:\n${answer.sdp}');
      debugPrint('[call] → answer to $peerId callId $callId');
      await chat.signal(
        peerId: peerId!,
        kind: 'answer',
        callId: callId!,
        media: _mediaWire(),
        payload: {'sdp': answer.sdp, 'type': answer.type},
      );
    } catch (_) {
      _fail('Could not connect');
    }
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
    _pendingIce.clear();
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
    if (peerId != null && callId != null) {
      await chat.signal(
        peerId: peerId!,
        kind: 'decline',
        callId: callId!,
        media: _mediaWire(),
      );
    }
    _cleanup(silent: true);
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
      _receiveOffer(sig);
      return;
    }

    // ICE may race ahead of offer/answer SDP. Buffer pre-offer ICE keyed
    // on callId so it isn't lost when the callee hasn't seen the offer yet.
    if (sig.kind == 'ice' && (!isActive || callId != sig.callId)) {
      if (sig.payload == null) return;
      final cand = RTCIceCandidate(
        sig.payload!['candidate']?.toString(),
        sig.payload!['sdpMid']?.toString(),
        (sig.payload!['sdpMLineIndex'] as num?)?.toInt(),
      );
      final list = _earlyIce.putIfAbsent(sig.callId, () => []);
      list.add(cand);
      debugPrint('[call] remote ICE buffered (pre-offer)');
      return;
    }

    // All other kinds must match the in-flight call.
    if (!isActive || callId != sig.callId) return;

    switch (sig.kind) {
      case 'answer':
        if (_pc == null || sig.payload == null) return;
        try {
          await _pc!.setRemoteDescription(RTCSessionDescription(
            sig.payload!['sdp']?.toString(),
            sig.payload!['type']?.toString(),
          ));
          for (final c in _pendingIce) {
            try {
              await _pc!.addCandidate(c);
            } catch (_) {}
          }
          _pendingIce.clear();
          // Peer answered — silence the caller's ringback.
          unawaited(RingtoneService.instance.stop());
        } catch (_) {}
        break;
      case 'ice':
        if (sig.payload == null) return;
        final cand = RTCIceCandidate(
          sig.payload!['candidate']?.toString(),
          sig.payload!['sdpMid']?.toString(),
          (sig.payload!['sdpMLineIndex'] as num?)?.toInt(),
        );
        // ICE candidates can race ahead of the answer/offer SDP exchange.
        // If remoteDescription isn't set yet, queue and drain on setRemote.
        final pc = _pc;
        if (pc == null) {
          _pendingIce.add(cand);
          break;
        }
        try {
          final rd = await pc.getRemoteDescription();
          if (rd != null) {
            await pc.addCandidate(cand);
          } else {
            _pendingIce.add(cand);
          }
        } catch (_) {
          _pendingIce.add(cand);
        }
        break;
      case 'ringing':
        if (role == CallRole.caller && phase == CallPhase.calling) {
          phase = CallPhase.ringing;
          notifyListeners();
        }
        break;
      case 'decline':
      case 'busy':
      case 'end':
        _cleanup(silent: true);
        break;
    }
  }

  // ── Peer connection wiring ───────────────────────────────────────────

  Future<RTCPeerConnection> _createPeer() async {
    final pc = await createPeerConnection({
      'iceServers': _iceServers,
      'iceTransportPolicy': 'all',
      'sdpSemantics': 'unified-plan',
    });
    pc.onIceCandidate = (RTCIceCandidate cand) {
      if (cand.candidate == null) {
        debugPrint('[call] local ICE: end-of-candidates');
        return;
      }
      debugPrint('[call] local ICE: ${cand.candidate}');
      if (peerId == null || callId == null) return;
      chat.signal(
        peerId: peerId!,
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
      debugPrint('[call] iceGatheringState = $state');
    };
    pc.onIceConnectionState = (state) {
      debugPrint('[call] iceConnectionState = $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        if (phase != CallPhase.connected) {
          phase = CallPhase.connected;
          startedAt ??= DateTime.now();
          _ringTimeout?.cancel();
          _connectingTimeout?.cancel();
          _connectingTimeout = null;
          _timer ??= Timer.periodic(
              const Duration(seconds: 1), (_) => notifyListeners());
          notifyListeners();
        }
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _cleanup(silent: true);
      }
    };
    pc.onTrack = (RTCTrackEvent event) {
      if (event.streams.isEmpty) return;
      _remoteStream = event.streams.first;
      remoteRenderer.srcObject = _remoteStream;
      notifyListeners();
    };
    pc.onConnectionState = (RTCPeerConnectionState state) {
      debugPrint('[call] connectionState = $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        if (phase != CallPhase.connected) {
          phase = CallPhase.connected;
          startedAt ??= DateTime.now();
          _ringTimeout?.cancel();
          _connectingTimeout?.cancel();
          _connectingTimeout = null;
          _timer ??= Timer.periodic(
              const Duration(seconds: 1), (_) => notifyListeners());
          notifyListeners();
        }
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _cleanup(silent: true);
      }
    };
    return pc;
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
    final pid = peerId;
    final cid = callId;
    final wasActive = isActive;
    final wireMedia = _mediaWire();
    // Cleanup first so the UI pops even if the network round-trip below
    // is slow / fails. Don't gate the user's escape on a successful POST.
    _cleanup(silent: true);
    if (!silent && wasActive && pid != null && cid != null) {
      // Fire-and-forget: don't await. If this fails (offline, 401, etc.)
      // we've still cleaned up locally — the peer will hit their own
      // ringing/connecting timeout. Awaiting here used to hold the Future
      // open with no UI consequence, which was confusing during debugging.
      unawaited(chat.signal(
        peerId: pid,
        kind: 'end',
        callId: cid,
        media: wireMedia,
      ));
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
    unawaited(RingtoneService.instance.stop());
    _ringTimeout?.cancel();
    _ringTimeout = null;
    _calleeRingTimeout?.cancel();
    _calleeRingTimeout = null;
    _connectingTimeout?.cancel();
    _connectingTimeout = null;
    _timer?.cancel();
    _timer = null;

    final pc = _pc;
    _pc = null;
    if (pc != null) {
      pc.onIceCandidate = null;
      pc.onTrack = null;
      pc.onConnectionState = null;
      try {
        pc.close();
      } catch (_) {}
    }

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

    _remoteStream = null;
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;

    phase = CallPhase.ended;
    role = null;
    peerId = null;
    peerName = '';
    callId = null;
    media = CallMedia.voice;
    muted = false;
    cameraOff = false;
    startedAt = null;
    _pendingOffer = null;
    _pendingIce.clear();

    notifyListeners();

    // Settle to idle on the next tick so the UI can fade out the "ended"
    // state if it wants to.
    Future<void>.delayed(const Duration(milliseconds: 50), () {
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

  Future<void> _ensureRenderers() async {
    if (_renderersReady) return;
    await localRenderer.initialize();
    await remoteRenderer.initialize();
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

  @override
  Future<void> dispose() async {
    await _signalSub?.cancel();
    _signalSub = null;
    _cleanup(silent: true);
    if (_renderersReady) {
      await localRenderer.dispose();
      await remoteRenderer.dispose();
    }
    super.dispose();
  }
}
