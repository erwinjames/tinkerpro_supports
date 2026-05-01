import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/call_service.dart';
import '../theme.dart';

/// Full-screen call UI. Renders four states off the same scaffold:
///   * outgoing  → calling / ringing
///   * incoming  → ringing with Accept / Decline
///   * connecting
///   * connected → mute, camera (video only), end
///
/// Pops itself when the underlying [CallService] returns to idle.
class CallScreen extends StatefulWidget {
  const CallScreen({super.key, required this.calls});

  final CallService calls;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  // CallService.notifyListeners fires twice during teardown — once when
  // phase flips to `ended`, again 50ms later when it settles to `idle`.
  // The pop animation isn't finished yet when the second one fires, so
  // our listener is still attached. Without this guard we'd pop a second
  // time and accidentally close the chat thread underneath us.
  bool _popped = false;

  @override
  void initState() {
    super.initState();
    widget.calls.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.calls.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (!mounted || _popped) return;
    if (widget.calls.phase == CallPhase.idle ||
        widget.calls.phase == CallPhase.ended) {
      // Auto-pop when the call wraps up (locally or remotely). Use the
      // root navigator because [HomeShell._onCallChange] pushed this
      // route via `rootNavigator: true`; the nested tab navigator we'd
      // otherwise resolve doesn't own this route.
      //
      // Use pop() (not maybePop) because PopScope below still has the
      // stale canPop=false from the just-active call — we haven't rebuilt
      // yet, so maybePop() would be blocked. The user already initiated
      // the dismissal (or the peer ended); PopScope is meant to guard
      // against accidental swipe-back, not against our own teardown.
      _popped = true;
      Navigator.of(context, rootNavigator: true).pop();
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.calls;
    final isVideo = c.media == CallMedia.video;
    final isIncoming =
        c.role == CallRole.callee && c.phase == CallPhase.ringing;
    final showRemote = isVideo &&
        c.phase == CallPhase.connected &&
        c.remoteRenderer.srcObject != null;

    final status = switch (c.phase) {
      CallPhase.calling => 'Calling…',
      CallPhase.ringing => isIncoming
          ? 'Incoming ${isVideo ? 'video' : 'voice'} call'
          : 'Ringing…',
      CallPhase.connecting => 'Connecting…',
      CallPhase.connected => c.elapsedLabel,
      _ => '',
    };

    return PopScope(
      // Prevent accidental back-out mid-call; the Decline / End buttons
      // are the only path off this screen.
      canPop: !c.isActive,
      child: Scaffold(
        backgroundColor: Brand.canvas,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Remote full-bleed video (only after we have a stream).
            if (showRemote)
              RTCVideoView(
                c.remoteRenderer,
                objectFit: RTCVideoViewObjectFit
                    .RTCVideoViewObjectFitCover,
              )
            else
              _StagePortrait(name: c.peerName, pulse: !isIncoming),

            // Soft brand glow on the dark canvas.
            if (!showRemote)
              IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(-0.4, -0.6),
                      radius: 1.1,
                      colors: [
                        Brand.signalGlow(0.16),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

            // Self preview — picture-in-picture on top right (video only).
            if (isVideo &&
                (c.phase == CallPhase.connected ||
                    c.phase == CallPhase.connecting ||
                    c.phase == CallPhase.calling))
              Positioned(
                top: MediaQuery.of(context).padding.top + 70,
                right: 16,
                width: 110,
                height: 160,
                child: _SelfPreview(renderer: c.localRenderer),
              ),

            // Top bar — pinned to the top with Positioned + Center so the
            // Row doesn't get vertically centered by the surrounding Stack
            // on platforms without a status-bar inset (Linux/Windows
            // desktop), and the pill stays above the avatar instead of
            // overlapping it. The redundant "VOICE CALL"/"VIDEO CALL" type
            // label is removed — the controls and the call_screen context
            // already make the call type unambiguous.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Center(
                    child: _GlassPill(label: status, monospace: true),
                  ),
                ),
              ),
            ),

            // Stage caption (over remote video this becomes a subtle overlay).
            if (showRemote)
              Positioned(
                left: 0,
                right: 0,
                bottom: 200,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      c.peerName,
                      style: const TextStyle(
                        color: Brand.paper,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
              ),

            // Controls.
            Positioned(
              left: 0,
              right: 0,
              bottom: 32 + MediaQuery.of(context).padding.bottom,
              child: Center(
                child: isIncoming
                    ? _IncomingControls(
                        onAccept: c.accept,
                        onDecline: c.decline,
                      )
                    : _ActiveControls(
                        muted: c.muted,
                        cameraOff: c.cameraOff,
                        showCamera: isVideo,
                        onMute: c.toggleMute,
                        onCamera: c.toggleCamera,
                        onSwitchCamera: c.switchCamera,
                        onEnd: () => c.end(),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────── stage (no remote video yet) ────────

class _StagePortrait extends StatefulWidget {
  const _StagePortrait({required this.name, required this.pulse});
  final String name;
  final bool pulse;

  @override
  State<_StagePortrait> createState() => _StagePortraitState();
}

class _StagePortraitState extends State<_StagePortrait>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initial =
        widget.name.trim().isEmpty ? '?' : widget.name.trim()[0].toUpperCase();
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = _c.value;
              final ringSize = 132 + (widget.pulse ? 60 * t : 0);
              final ringOpacity = widget.pulse ? (1 - t) * 0.45 : 0.0;
              return SizedBox(
                width: 200,
                height: 200,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (widget.pulse)
                      Container(
                        width: ringSize.toDouble(),
                        height: ringSize.toDouble(),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Brand.signalGlow(ringOpacity),
                        ),
                      ),
                    Container(
                      width: 132,
                      height: 132,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF9433), Brand.signal],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Brand.signalGlow(0.34),
                            blurRadius: 32,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        initial,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 48,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          Text(
            widget.name,
            style: const TextStyle(
              color: Brand.paper,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────── self preview ───────────────────────

class _SelfPreview extends StatelessWidget {
  const _SelfPreview({required this.renderer});
  final RTCVideoRenderer renderer;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Brand.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: RTCVideoView(
          renderer,
          mirror: true,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────── glass pill ─────────────────────────

class _GlassPill extends StatelessWidget {
  const _GlassPill({required this.label, this.monospace = false});
  final String label;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Brand.paper,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: monospace ? 1.2 : 0.4,
              fontFeatures: monospace
                  ? const [FontFeature.tabularFigures()]
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────── controls ───────────────────────────

class _ActiveControls extends StatelessWidget {
  const _ActiveControls({
    required this.muted,
    required this.cameraOff,
    required this.showCamera,
    required this.onMute,
    required this.onCamera,
    required this.onSwitchCamera,
    required this.onEnd,
  });

  final bool muted;
  final bool cameraOff;
  final bool showCamera;
  final VoidCallback onMute;
  final VoidCallback onCamera;
  final VoidCallback onSwitchCamera;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _CallButton(
          icon: muted ? Icons.mic_off : Icons.mic,
          active: muted,
          onTap: onMute,
        ),
        const SizedBox(width: 18),
        if (showCamera) ...[
          _CallButton(
            icon: cameraOff ? Icons.videocam_off : Icons.videocam,
            active: cameraOff,
            onTap: onCamera,
          ),
          const SizedBox(width: 18),
          _CallButton(
            icon: Icons.cameraswitch_outlined,
            active: false,
            onTap: onSwitchCamera,
          ),
          const SizedBox(width: 18),
        ],
        _CallButton(
          icon: Icons.call_end,
          tone: _CallButtonTone.danger,
          onTap: onEnd,
        ),
      ],
    );
  }
}

class _IncomingControls extends StatelessWidget {
  const _IncomingControls({required this.onAccept, required this.onDecline});
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _CallButton(
          icon: Icons.call_end,
          tone: _CallButtonTone.danger,
          onTap: onDecline,
        ),
        const SizedBox(width: 28),
        _CallButton(
          icon: Icons.call,
          tone: _CallButtonTone.success,
          pulse: true,
          onTap: onAccept,
        ),
      ],
    );
  }
}

enum _CallButtonTone { glass, danger, success }

class _CallButton extends StatefulWidget {
  const _CallButton({
    required this.icon,
    required this.onTap,
    this.tone = _CallButtonTone.glass,
    this.active = false,
    this.pulse = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final _CallButtonTone tone;
  final bool active;
  final bool pulse;

  @override
  State<_CallButton> createState() => _CallButtonState();
}

class _CallButtonState extends State<_CallButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (widget.pulse) _pulseController.repeat();
  }

  @override
  void didUpdateWidget(covariant _CallButton old) {
    super.didUpdateWidget(old);
    if (widget.pulse && !_pulseController.isAnimating) {
      _pulseController.repeat();
    } else if (!widget.pulse && _pulseController.isAnimating) {
      _pulseController.stop();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = switch (widget.tone) {
      _CallButtonTone.glass =>
        widget.active ? Brand.paper : Colors.white.withValues(alpha: 0.10),
      _CallButtonTone.danger => const Color(0xFFDC2626),
      _CallButtonTone.success => const Color(0xFF10B981),
    };
    final fg = switch (widget.tone) {
      _CallButtonTone.glass =>
        widget.active ? Brand.canvas : Brand.paper,
      _ => Colors.white,
    };
    final glow = switch (widget.tone) {
      _CallButtonTone.danger => const Color(0xFFDC2626).withValues(alpha: 0.4),
      _CallButtonTone.success => const Color(0xFF10B981).withValues(alpha: 0.4),
      _ => Colors.transparent,
    };

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        final pulseRadius = widget.pulse ? 14.0 * _pulseController.value : 0.0;
        final pulseOpacity = widget.pulse ? (1 - _pulseController.value) : 0.0;
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            if (widget.pulse)
              Container(
                width: 64 + pulseRadius * 2,
                height: 64 + pulseRadius * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: glow.withValues(alpha: pulseOpacity * 0.35),
                ),
              ),
            Material(
              color: bg,
              shape: const CircleBorder(),
              elevation: widget.tone == _CallButtonTone.glass ? 0 : 8,
              shadowColor: glow,
              child: InkWell(
                onTap: widget.onTap,
                customBorder: const CircleBorder(),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: Icon(widget.icon, color: fg, size: 26),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
