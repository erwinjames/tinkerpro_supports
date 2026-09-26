import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/call_service.dart';
import '../theme.dart';

const Color _callBg = Brand.navy;
const Color _callTile = Color(0xFF12304F);
const Color _callChip = Color(0xFF1B3D62);
const Color _callText = Color(0xFFF3F4F6);
const Color _callTextDim = Color(0xFF9CA3AF);

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'[\s._@-]+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

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
    final showRemote =
        !showMesh &&
        isVideo &&
        c.phase == CallPhase.connected &&
        c.remoteRenderer?.srcObject != null;

    final status = switch (c.phase) {
      CallPhase.calling => 'Calling…',
      CallPhase.ringing =>
        isIncoming
            ? 'Incoming ${c.isGroup ? 'group ' : ''}${isVideo ? 'video' : 'voice'} call'
            : 'Ringing…',
      CallPhase.connecting => 'Connecting…',
      CallPhase.connected => c.elapsedLabel,
      _ => '',
    };

    return PopScope(
      canPop: !c.isActive,
      child: Scaffold(
        backgroundColor: _callBg,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (showMesh)
              _MeshGrid(calls: c)
            else if (showRemote)
              RTCVideoView(
                c.remoteRenderer!,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            else
              _StagePortrait(
                name: c.title,
                pulse: !isIncoming && c.phase != CallPhase.connected,
                caption: isIncoming
                    ? status
                    : (isVideo ? 'Video call' : 'Voice call'),
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
                    child: _CallPill(
                      label: status,
                      monospace: c.phase == CallPhase.connected,
                      live: c.phase == CallPhase.connected,
                    ),
                  ),
                ),
              ),
            ),

            if (showRemote)
              Positioned(
                left: 0,
                right: 0,
                bottom: 190 + MediaQuery.of(context).padding.bottom,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      c.title,
                      style: const TextStyle(
                        color: _callText,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),

            Positioned(
              left: 0,
              right: 0,
              bottom: 28 + MediaQuery.of(context).padding.bottom,
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
        padding: const EdgeInsets.fromLTRB(12, 56, 12, 156),
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
    final initial = _initials(label);
    return ClipRRect(
      borderRadius: BorderRadius.circular(Brand.radiusLg),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _callTile,
          borderRadius: BorderRadius.circular(Brand.radiusLg),
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
                    color: Brand.orange,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
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
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Connecting…',
                    style: TextStyle(
                      color: _callText,
                      fontSize: 11,
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _callText,
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
  const _StagePortrait({
    required this.name,
    required this.pulse,
    required this.caption,
  });
  final String name;
  final bool pulse;
  final String caption;

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
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) {
      _c.stop();
      _c.value = 0;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initial = _initials(widget.name);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = _c.value;
              final animate = widget.pulse && _c.isAnimating;
              final ringSize = 138 + (animate ? 64 * t : 0);
              final ringOpacity = animate ? (1 - t) * 0.72 : 0.0;
              return SizedBox(
                width: 200,
                height: 200,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (animate)
                      Container(
                        width: ringSize.toDouble(),
                        height: ringSize.toDouble(),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Brand.signal.withValues(alpha: ringOpacity),
                            width: 2,
                          ),
                        ),
                      ),
                    Container(
                      width: 132,
                      height: 132,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Brand.orange,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        initial,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 46,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Semantics(
              header: true,
              child: Text(
                widget.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: _callText,
                      fontWeight: FontWeight.w700,
                    ) ??
                    const TextStyle(
                      color: _callText,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ),
          if (widget.caption.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              widget.caption,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _callTextDim,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
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
      borderRadius: BorderRadius.circular(Brand.radiusLg),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _callTile,
          borderRadius: BorderRadius.circular(Brand.radiusLg),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
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

class _CallSurface extends StatelessWidget {
  const _CallSurface({
    required this.child,
    required this.radius,
    this.padding = EdgeInsets.zero,
    this.hairline = false,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final bool hairline;

  @override
  Widget build(BuildContext context) {
    final border = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _callTile,
        borderRadius: border,
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: ClipRRect(
        borderRadius: border,
        child: Stack(
          children: [
            Padding(padding: padding, child: child),
            if (hairline)
              Positioned(
                top: 0,
                left: 28,
                right: 28,
                child: IgnorePointer(
                  child: Container(height: 1.5, color: Brand.signal),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CallPill extends StatelessWidget {
  const _CallPill({
    required this.label,
    this.monospace = false,
    this.live = false,
  });
  final String label;
  final bool monospace;
  final bool live;

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox.shrink();
    return Semantics(
      liveRegion: !monospace,
      label: label,
      excludeSemantics: true,
      child: _CallSurface(
        radius: 999,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (live) ...[
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Brand.success,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
            ],
            AnimatedSwitcher(
              duration:
                  (MediaQuery.maybeOf(context)?.disableAnimations ?? false)
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              child: Text(
                label,
                key: ValueKey(monospace ? 'timer' : label),
                style: TextStyle(
                  color: _callText,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFeatures: monospace
                      ? const [FontFeature.tabularFigures()]
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlDock extends StatelessWidget {
  const _ControlDock({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return _CallSurface(
      radius: 32,
      hairline: true,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
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
    return _ControlDock(
      children: [
        _CallButton(
          icon: muted ? Icons.mic_off_rounded : Icons.mic_rounded,
          label: muted ? 'Unmute' : 'Mute',
          active: muted,
          onTap: onMute,
        ),
        const SizedBox(width: 12),
        if (showCamera) ...[
          _CallButton(
            icon: cameraOff
                ? Icons.videocam_off_rounded
                : Icons.videocam_rounded,
            label: cameraOff ? 'Camera on' : 'Camera off',
            active: cameraOff,
            onTap: onCamera,
          ),
          const SizedBox(width: 12),
          _CallButton(
            icon: Icons.cameraswitch_rounded,
            label: 'Flip',
            tooltip: 'Switch camera',
            active: false,
            onTap: onSwitchCamera,
          ),
          const SizedBox(width: 12),
        ],
        _CallButton(
          icon: Icons.call_end_rounded,
          label: 'End',
          tooltip: 'End call',
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CallButton(
          icon: Icons.call_end_rounded,
          label: 'Decline',
          tone: _CallButtonTone.danger,
          size: 72,
          onTap: onDecline,
        ),
        const SizedBox(width: 72),
        _CallButton(
          icon: Icons.call_rounded,
          label: 'Accept',
          tone: _CallButtonTone.success,
          size: 72,
          pulse: true,
          onTap: onAccept,
        ),
      ],
    );
  }
}

enum _CallButtonTone { neutral, danger, success }

class _CallButton extends StatefulWidget {
  const _CallButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.tooltip,
    this.tone = _CallButtonTone.neutral,
    this.active = false,
    this.pulse = false,
    this.size = 64,
  });

  final IconData icon;
  final String label;
  final String? tooltip;
  final double size;
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
  }

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  void _syncPulse() {
    final want = widget.pulse && !_reduceMotion;
    if (want && !_pulseController.isAnimating) {
      _pulseController.repeat();
    } else if (!want && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant _CallButton old) {
    super.didUpdateWidget(old);
    _syncPulse();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = switch (widget.tone) {
      _CallButtonTone.neutral => widget.active ? _callText : _callChip,
      _CallButtonTone.danger => Brand.danger,
      _CallButtonTone.success => Brand.success,
    };
    final fg = switch (widget.tone) {
      _CallButtonTone.neutral => widget.active ? _callBg : _callText,
      _ => Colors.white,
    };
    final pulseTint = switch (widget.tone) {
      _CallButtonTone.danger => Brand.danger,
      _CallButtonTone.success => Brand.success,
      _ => Colors.transparent,
    };

    final size = widget.size;
    final button = AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        final animating = _pulseController.isAnimating;
        final pulseRadius = animating ? 14.0 * _pulseController.value : 0.0;
        final pulseOpacity = animating ? (1 - _pulseController.value) : 0.0;
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            if (animating)
              Container(
                width: size + pulseRadius * 2,
                height: size + pulseRadius * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: pulseTint.withValues(alpha: pulseOpacity * 0.35),
                ),
              ),
            Material(
              color: bg,
              shape: CircleBorder(
                side: widget.tone == _CallButtonTone.neutral && !widget.active
                    ? BorderSide(color: Colors.white.withValues(alpha: 0.14))
                    : BorderSide.none,
              ),
              elevation: 0,
              child: InkWell(
                onTap: widget.onTap,
                customBorder: const CircleBorder(),
                child: SizedBox(
                  width: size,
                  height: size,
                  child: Icon(widget.icon, color: fg, size: size * 0.42),
                ),
              ),
            ),
          ],
        );
      },
    );
    return Semantics(
      button: true,
      label: widget.tooltip ?? widget.label,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: Tooltip(
        message: widget.tooltip ?? widget.label,
        child: SizedBox(
          width: size < 64 ? 64 : size,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              button,
              const SizedBox(height: 8),
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.visible,
                softWrap: false,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _callText,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
