import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models/chat_models.dart';
import 'chat_realtime.dart';
import 'chat_service.dart';
import 'ringtone_service.dart';

/// Lifecycle phases.
enum CallPhase { idle, calling, ringing, connecting, connected, ended }

/// 'voice' is all the customer app needs for v1; the type is here for
/// parity with the staff side and for if/when we surface video later.
enum CallMedia { voice, video }

/// Caller (we initiated) vs callee (someone called us — currently unused
/// in customer flow because admins call us only via outgoing-from-admin
/// paths that target our shadow user channel).
enum CallRole { caller, callee }

/// Customer-side WebRTC orchestration.
///
/// Outgoing flow (the only one we care about):
///   • [placeCall] → fan-out an SDP offer to ALL admins in the support
///     group simultaneously. Each admin sees an incoming-call ringing UI
///     on their staff page (chat.php inline call OR the global widget).
///   • First admin to answer wins. Their SDP answer locks our peer to
///     them; any other late answer gets a `busy`. Others still ringing
///     get a same-callId `end` so their UI dismisses cleanly.
///   • If every admin who acked declines, end the call immediately
///     (don't wait the full 45s for phantom never-acked candidates).
class CallService extends ChangeNotifier {
  CallService({
    required this.realtime,
    required this.chat,
    required this.shadowUserId,
    required this.conversationId,
    List<Map<String, dynamic>>? iceServers,
  }) : _iceServers = iceServers ??
            const [
              {'urls': 'stun:stun.l.google.com:19302'},
              {'urls': 'stun:stun1.l.google.com:19302'},
              // Production: drop in a TURN server here.
              // {'urls': 'turn:turn.example.com:3478', 'username': '…', 'credential': '…'}
            ] {
    _signalSub = realtime.callSignalEvents.listen(_onSignal);
  }

  final ChatRealtimeService realtime;
  final ChatService chat;

  /// Customer's shadow user id (the user_id the server attributes our
  /// `chat.signal` POSTs to via `as_portal=1`). Useful for skipping
  /// echoes of our own signals if the channel ever gets noisy.
  final int shadowUserId;

  /// Conversation we belong to. Used to broadcast `chat.callPresence`
  /// to colleagues sharing the support thread so their AppBar greys
  /// out call buttons + shows a banner while we're on a call.
  final int conversationId;
  final List<Map<String, dynamic>> _iceServers;
  StreamSubscription<CallSignal>? _signalSub;

  // ── Public state (read-only views for the UI) ────────────────────────
  CallPhase phase = CallPhase.idle;
  CallRole? role;
  CallMedia media = CallMedia.voice;
  String peerLabel = '';      // "Support team" until we lock onto a winner
  int? peerId;                // null until first answer
  String? callId;
  bool muted = false;
  DateTime? startedAt;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();
  bool _renderersReady = false;

  // ── Internals ────────────────────────────────────────────────────────
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  final List<RTCIceCandidate> _pendingIce = [];

  /// Targets we're currently fanning out to. After the first answer the
  /// winner is moved to [peerId] and the rest receive a `end` cancel.
  List<_PeerCandidate> _candidates = [];
  bool _peerLocked = false;

  /// Acknowledged peers — admins who returned a `ringing` ack. Drives the
  /// "everyone reachable has declined → give up" early-end policy.
  final Set<int> _ackedPeers = <int>{};
  bool _everAcked = false;

  /// Cached SDP offer for an incoming call we haven't yet accepted.
  /// Populated by [_receiveOffer]; consumed in [accept].
  RTCSessionDescription? _pendingOffer;
  /// ICE candidates that arrived BEFORE the offer signal. Keyed by callId
  /// so a stale call's leftover candidates can never bleed into a new
  /// call — drained inside [_receiveOffer].
  final Map<String, List<RTCIceCandidate>> _earlyIce = {};

  Timer? _ringTimeout;
  Timer? _connectingTimeout;
  Timer? _calleeRingTimeout;
  Timer? _timer;

  /// True when an incoming offer is sitting in front of the user awaiting
  /// accept/decline. The chat screen uses this to render the in-call
  /// banner / overlay with the right controls.
  bool get isIncomingRinging =>
      phase == CallPhase.ringing && role == CallRole.callee;

  bool get isActive =>
      phase != CallPhase.idle && phase != CallPhase.ended;

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

  /// Ring every admin participant. Returns false if a call is already in
  /// flight, the candidate list is empty, or local media access fails.
  Future<bool> placeCall({
    required List<({int id, String name})> peers,
    required CallMedia media,
  }) async {
    debugPrint(
        '[call] placeCall isActive=$isActive peers=${peers.length} shadow=$shadowUserId');
    if (isActive) return false;
    final clean = peers
        .where((p) => p.id > 0 && p.id != shadowUserId)
        .map((p) => _PeerCandidate(id: p.id, name: p.name))
        .toList();
    debugPrint('[call] cleaned peers: ${clean.map((p) => '${p.id}:${p.name}').toList()}');
    if (clean.isEmpty) return false;

    _candidates = clean;
    _peerLocked = false;
    _ackedPeers.clear();
    _everAcked = false;
    this.media = media;
    role = CallRole.caller;
    callId = _newCallId();
    phase = CallPhase.calling;
    peerLabel = clean.length > 1 ? 'Support team' : clean.first.name;
    peerId = null;
    muted = false;
    startedAt = null;
    _pendingIce.clear();

    await _ensureRenderers();
    unawaited(RingtoneService.instance.startRingback());
    // Let colleagues in the same conversation know we just claimed
    // the call slot so their AppBar buttons grey out before we even
    // touch local media.
    _emitPresence('busy', callId!);
    notifyListeners();

    try {
      _localStream = await _getMedia(media);
      debugPrint('[call] got local stream tracks: ${_localStream!.getTracks().length}');
      localRenderer.srcObject = _localStream;
    } catch (e, st) {
      debugPrint('[call] getUserMedia failed: $e\n$st');
      _fail('Could not access microphone');
      return false;
    }

    _pc = await _createPeer();
    for (final t in _localStream!.getTracks()) {
      await _pc!.addTrack(t, _localStream!);
    }

    try {
      final offer = await _pc!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': media == CallMedia.video,
      });
      await _pc!.setLocalDescription(offer);
      // Fan-out: same callId, same SDP, every admin in parallel.
      final sdpOffer = {'sdp': offer.sdp, 'type': offer.type};
      for (final c in _candidates) {
        unawaited(chat.signal(
          peerId: c.id,
          kind: 'offer',
          callId: callId!,
          media: _mediaWire(),
          payload: sdpOffer,
        ));
      }
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

  // ── Incoming call (admin → customer) ─────────────────────────────────

  void _receiveOffer(CallSignal sig) {
    // Already in a different call → busy.
    if (isActive && callId != sig.callId) {
      unawaited(chat.signal(
        peerId: sig.fromId,
        kind: 'busy',
        callId: sig.callId,
        media: sig.media,
      ));
      return;
    }
    // Same callId duplicate — ignore.
    if (isActive && callId == sig.callId) return;

    peerId = sig.fromId;
    peerLabel = sig.fromName.isNotEmpty ? sig.fromName : 'Support';
    media = sig.media == 'video' ? CallMedia.video : CallMedia.voice;
    role = CallRole.callee;
    callId = sig.callId;
    phase = CallPhase.ringing;
    muted = false;
    startedAt = null;
    _pendingIce.clear();
    _candidates = [];
    _peerLocked = false;
    _ackedPeers.clear();
    _everAcked = false;

    if (sig.payload != null) {
      _pendingOffer = RTCSessionDescription(
        sig.payload!['sdp']?.toString(),
        sig.payload!['type']?.toString(),
      );
    }

    // Drain any pre-offer ICE for this call.
    final early = _earlyIce.remove(sig.callId);
    if (early != null && early.isNotEmpty) {
      _pendingIce.addAll(early);
    }

    // Ring the customer's device so they hear the call even if the
    // app is in the background.
    unawaited(RingtoneService.instance.startIncoming());

    // Ack the caller so they flip from "Calling…" to "Ringing…".
    unawaited(chat.signal(
      peerId: sig.fromId,
      kind: 'ringing',
      callId: sig.callId,
      media: sig.media,
    ));

    // Let colleagues in the same conversation know this terminal is
    // tied up with an incoming call so they can't start a competing
    // one. We'll emit `free` from _cleanup when the ringing resolves.
    _emitPresence('busy', sig.callId);

    // Auto-decline if the customer never picks up. Without this, a caller
    // who hangs up before we accept would leave us stuck in `ringing`.
    _calleeRingTimeout?.cancel();
    _calleeRingTimeout = Timer(const Duration(seconds: 60), () {
      if (phase == CallPhase.ringing && role == CallRole.callee) {
        decline();
      }
    });

    notifyListeners();
  }

  /// Pick up an incoming call. Spins up local mic, builds the SDP answer,
  /// and replies to the caller.
  Future<void> accept() async {
    if (role != CallRole.callee || _pendingOffer == null) return;
    unawaited(RingtoneService.instance.stop());
    phase = CallPhase.connecting;
    _calleeRingTimeout?.cancel();
    _calleeRingTimeout = null;
    // Auto-end if ICE never completes. Same 30s guard as the staff app.
    _connectingTimeout?.cancel();
    _connectingTimeout = Timer(const Duration(seconds: 30), () {
      if (phase == CallPhase.connecting) {
        end(silent: false, reason: 'Connection failed');
      }
    });
    notifyListeners();

    await _ensureRenderers();

    try {
      _localStream = await _getMedia(media);
      localRenderer.srcObject = _localStream;
    } catch (_) {
      await chat.signal(
        peerId: peerId!,
        kind: 'decline',
        callId: callId!,
        media: _mediaWire(),
      );
      _fail('Could not access microphone');
      return;
    }

    _pc = await _createPeer();
    for (final t in _localStream!.getTracks()) {
      await _pc!.addTrack(t, _localStream!);
    }

    try {
      await _pc!.setRemoteDescription(_pendingOffer!);
      _pendingOffer = null;
      // Drain any ICE that arrived before remoteDescription was ready.
      for (final c in _pendingIce) {
        try {
          await _pc!.addCandidate(c);
        } catch (_) {}
      }
      _pendingIce.clear();

      final answer = await _pc!.createAnswer();
      await _pc!.setLocalDescription(answer);
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

  /// Reject an incoming call.
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

  // ── Inbound signaling ─────────────────────────────────────────────────

  Future<void> _onSignal(CallSignal sig) async {
    debugPrint('[call] ← ${sig.kind} from ${sig.fromId} callId ${sig.callId}');

    // Incoming call from an admin. Only path on the customer side that
    // creates state we didn't initiate.
    if (sig.kind == 'offer') {
      _receiveOffer(sig);
      return;
    }

    // Buffer pre-offer / pre-answer ICE that might race ahead of SDP.
    if (sig.kind == 'ice' && (!isActive || callId != sig.callId)) {
      if (sig.payload == null) return;
      final c = RTCIceCandidate(
        sig.payload!['candidate']?.toString(),
        sig.payload!['sdpMid']?.toString(),
        (sig.payload!['sdpMLineIndex'] as num?)?.toInt(),
      );
      // Key by callId so an offer arriving later can drain just its
      // own candidates (multiple parallel calls case).
      _earlyIce.putIfAbsent(sig.callId, () => []).add(c);
      return;
    }

    if (!isActive || callId != sig.callId) return;

    switch (sig.kind) {
      case 'ringing':
        if (role == CallRole.caller && phase == CallPhase.calling) {
          phase = CallPhase.ringing;
          notifyListeners();
        }
        if (sig.fromId > 0) {
          _ackedPeers.add(sig.fromId);
          _everAcked = true;
        }
        break;
      case 'answer':
        if (_pc == null || sig.payload == null) return;
        if (_peerLocked) {
          // Late answer — politely tell them we're already taken.
          unawaited(chat.signal(
            peerId: sig.fromId,
            kind: 'busy',
            callId: callId!,
            media: _mediaWire(),
          ));
          return;
        }
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
          // Admin picked up — silence the caller's ringback.
          unawaited(RingtoneService.instance.stop());
          _peerLocked = true;
          peerId = sig.fromId;
          peerLabel = sig.fromName.isNotEmpty ? sig.fromName : peerLabel;
          phase = CallPhase.connecting;
          notifyListeners();
          // Cancel the others so their ringing UIs dismiss.
          for (final c in _candidates) {
            if (c.id != sig.fromId) {
              unawaited(chat.signal(
                peerId: c.id,
                kind: 'end',
                callId: callId!,
                media: _mediaWire(),
              ));
            }
          }
        } catch (e) {
          debugPrint('[call] setRemoteDescription(answer) failed: $e');
        }
        break;
      case 'ice':
        if (_pc == null || sig.payload == null) return;
        try {
          final cand = RTCIceCandidate(
            sig.payload!['candidate']?.toString(),
            sig.payload!['sdpMid']?.toString(),
            (sig.payload!['sdpMLineIndex'] as num?)?.toInt(),
          );
          final rd = await _pc!.getRemoteDescription();
          if (rd != null) {
            await _pc!.addCandidate(cand);
          } else {
            _pendingIce.add(cand);
          }
        } catch (_) {}
        break;
      case 'decline':
      case 'busy':
      case 'end':
        // If the locked peer hung up / declined / went busy, end the call.
        // Otherwise drop just that candidate; if all who acked have
        // bowed out, give up.
        if (_peerLocked && sig.fromId == peerId) {
          _cleanup(silent: true);
          break;
        }
        _candidates.removeWhere((c) => c.id == sig.fromId);
        _ackedPeers.remove(sig.fromId);
        final noCandidates = _candidates.isEmpty;
        final allAckersGone = _everAcked && _ackedPeers.isEmpty;
        if (noCandidates || allAckersGone) {
          _cleanup(silent: true);
        }
        break;
    }
  }

  // ── Local actions ────────────────────────────────────────────────────

  void toggleMute() {
    if (_localStream == null) return;
    muted = !muted;
    for (final t in _localStream!.getAudioTracks()) {
      t.enabled = !muted;
    }
    notifyListeners();
  }

  Future<void> end({bool silent = false, String? reason}) async {
    debugPrint('[call] end() phase=$phase silent=$silent reason=$reason');
    unawaited(RingtoneService.instance.stop());
    final cid = callId;
    final wasActive = isActive;
    final wireMedia = _mediaWire();
    final ringingTargets =
        (!_peerLocked && _candidates.isNotEmpty) ? _candidates.toList() : null;
    final lockedPeer = peerId;
    _cleanup(silent: true);
    if (!silent && wasActive && cid != null) {
      if (ringingTargets != null) {
        for (final c in ringingTargets) {
          unawaited(chat.signal(
            peerId: c.id,
            kind: 'end',
            callId: cid,
            media: wireMedia,
          ));
        }
      } else if (lockedPeer != null && lockedPeer > 0) {
        unawaited(chat.signal(
          peerId: lockedPeer,
          kind: 'end',
          callId: cid,
          media: wireMedia,
        ));
      }
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
      if (cand.candidate == null || callId == null) return;
      // Fan-out ICE to all candidates while we haven't locked, then only
      // to the winner once locked.
      final targets = _peerLocked
          ? (peerId != null ? [peerId!] : const <int>[])
          : _candidates.map((c) => c.id).toList();
      for (final id in targets) {
        unawaited(chat.signal(
          peerId: id,
          kind: 'ice',
          callId: callId!,
          media: _mediaWire(),
          payload: {
            'candidate': cand.candidate,
            'sdpMid': cand.sdpMid,
            'sdpMLineIndex': cand.sdpMLineIndex,
          },
        ));
      }
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
              'facingMode': 'user',
              'width': {'ideal': 1280},
              'height': {'ideal': 720},
            }
          : false,
    };
    return navigator.mediaDevices.getUserMedia(constraints);
  }

  // ── Lifecycle utilities ──────────────────────────────────────────────

  void _cleanup({required bool silent}) {
    // Capture & emit BEFORE we wipe state so colleagues see "free"
    // with the correct callId. Skips harmlessly if no call was ever
    // started in this instance.
    final cidForPresence = callId;
    if (cidForPresence != null && cidForPresence.isNotEmpty) {
      _emitPresence('free', cidForPresence);
    }
    unawaited(RingtoneService.instance.stop());
    _ringTimeout?.cancel();
    _ringTimeout = null;
    _connectingTimeout?.cancel();
    _connectingTimeout = null;
    _calleeRingTimeout?.cancel();
    _calleeRingTimeout = null;
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
    peerLabel = '';
    callId = null;
    media = CallMedia.voice;
    muted = false;
    startedAt = null;
    _pendingIce.clear();
    _earlyIce.clear();
    _pendingOffer = null;
    _candidates = [];
    _peerLocked = false;
    _ackedPeers.clear();
    _everAcked = false;

    notifyListeners();
    Future<void>.delayed(const Duration(milliseconds: 50), () {
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

  /// Tell colleagues in our conversation that this terminal is now
  /// busy/free with a call. Best-effort; failure here never blocks the
  /// call itself.
  void _emitPresence(String state, String cid) {
    if (conversationId <= 0 || cid.isEmpty) return;
    unawaited(chat.callPresence(
      conversationId: conversationId,
      state: state,
      media: _mediaWire(),
      callId: cid,
    ));
  }

  Future<void> _ensureRenderers() async {
    if (_renderersReady) return;
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    _renderersReady = true;
  }

  static String _newCallId() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int n) => n.toRadixString(16).padLeft(2, '0');
    final s = StringBuffer();
    for (var i = 0; i < bytes.length; i++) {
      s.write(hex(bytes[i]));
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

class _PeerCandidate {
  _PeerCandidate({required this.id, required this.name});
  final int id;
  final String name;
}
