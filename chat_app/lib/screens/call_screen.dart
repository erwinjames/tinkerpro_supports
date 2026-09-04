import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/call_service.dart';
import '../theme.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({super.key, required this.calls});

  final CallService calls;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {

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

    final showMesh = c.isGroup && !isIncoming;
    final showRemote = !showMesh &&
        isVideo &&
        c.phase == CallPhase.connected &&
        c.remoteRenderer?.srcObject != null;

    final status = switch (c.phase) {
      CallPhase.calling => 'Calling…',
      CallPhase.ringing => isIncoming
          ? 'Incoming ${c.isGroup ? 'group ' : ''}${isVideo ? 'video' : 'voice'} call'
          : 'Ringing…',
      CallPhase.connecting => 'Connecting…',
      CallPhase.connected => c.elapsedLabel,
      _ => '',
    };

    return PopScope(

      canPop: !c.isActive,
      child: Scaffold(
        backgroundColor: context.brand.canvas,
        body: Stack(
          fit: StackFit.expand,
          children: [

            if (showMesh)
              _MeshGrid(calls: c)
            else if (showRemote)
              RTCVideoView(
                c.remoteRenderer!,
                objectFit: RTCVideoViewObjectFit
                    .RTCVideoViewObjectFitCover,
              )
            else
              _StagePortrait(name: c.title, pulse: !isIncoming),

            if (!showRemote && !showMesh)
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

            if (isVideo &&
                !showMesh &&
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

            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _GlassPill(label: status, monospace: true),
                        if (c.phase == CallPhase.connecting &&
                            c.iceDiagnostics != null) ...[
                          const SizedBox(height: 6),
                          _GlassPill(
                            label: c.iceDiagnostics!,
                            monospace: true,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),

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
                      c.title,
                      style: TextStyle(
                        color: context.brand.paper,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
              ),

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

class _MeshGrid extends StatelessWidget {
  const _MeshGrid({required this.calls});

  final CallService calls;

  @override
  Widget build(BuildContext context) {
    final isVideo = calls.media == CallMedia.video;
    final tiles = <Widget>[
      _MeshTile(
        label: 'You',
        renderer: isVideo ? calls.localRenderer : null,
        hasVideo: isVideo && !calls.cameraOff,
        mirror: true,
        connecting: false,
      ),
      for (final p in calls.participants)
        _MeshTile(
          label: p.name,
          renderer: isVideo ? p.renderer : null,
          hasVideo: isVideo && p.hasVideo,
          mirror: false,
          connecting: !p.connected,
        ),
    ];

    final cols = tiles.length <= 1
        ? 1
        : tiles.length <= 4
            ? 2
            : 3;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 56, 12, 116),
        child: GridView.count(
          crossAxisCount: cols,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 3 / 4,
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          children: tiles,
        ),
      ),
    );
  }
}

class _MeshTile extends StatelessWidget {
  const _MeshTile({
    required this.label,
    required this.renderer,
    required this.hasVideo,
    required this.mirror,
    required this.connecting,
  });

  final String label;
  final RTCVideoRenderer? renderer;
  final bool hasVideo;
  final bool mirror;
  final bool connecting;

  @override
  Widget build(BuildContext context) {
    final initial =
        label.trim().isEmpty ? '?' : label.trim()[0].toUpperCase();
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.brand.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: connecting
                ? Brand.signalGlow(0.45)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasVideo && renderer != null)
              RTCVideoView(
                renderer!,
                mirror: mirror,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            else
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Color(0xFFFF9433), Brand.signal],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            if (connecting)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Connecting…',
                    style: TextStyle(
                      color: context.brand.paper,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 6,
              bottom: 6,
              right: 6,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.brand.paper,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
            style: TextStyle(
              color: context.brand.paper,
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

class _SelfPreview extends StatelessWidget {
  const _SelfPreview({required this.renderer});
  final RTCVideoRenderer renderer;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.brand.surface,
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
              color: context.brand.paper,
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
        widget.active ? context.brand.paper : Colors.white.withValues(alpha: 0.10),
      _CallButtonTone.danger => const Color(0xFFDC2626),
      _CallButtonTone.success => const Color(0xFF10B981),
    };
    final fg = switch (widget.tone) {
      _CallButtonTone.glass =>
        widget.active ? context.brand.canvas : context.brand.paper,
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
