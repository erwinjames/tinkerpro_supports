import 'package:flutter/material.dart';

import '../services/call_service.dart';
import '../theme.dart';

/// Full-screen call UI. Pops itself when the underlying [CallService]
/// returns to idle (locally or remotely ended). Mirrors the staff app's
/// surface so the customer experience reads as part of the same family —
/// big avatar / status pill / mute + end controls.
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

  String _statusText() {
    final c = widget.calls;
    if (c.isIncomingRinging) {
      return 'Incoming voice call';
    }
    switch (c.phase) {
      case CallPhase.calling:
        return 'Calling…';
      case CallPhase.ringing:
        return 'Ringing…';
      case CallPhase.connecting:
        return 'Connecting…';
      case CallPhase.connected:
        return c.elapsedLabel;
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.calls;
    return PopScope(
      canPop: !c.isActive,
      child: Scaffold(
        backgroundColor: Brand.ink,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _StagePortrait(name: c.peerLabel.isEmpty ? 'Support' : c.peerLabel,
                pulse: c.phase != CallPhase.connected),
            // Brand glow
            IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.4, -0.6),
                    radius: 1.1,
                    colors: [
                      Brand.signalGlow(0.18),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            // Top bar — pinned to the top with Positioned + Align so the
            // Row doesn't get centered vertically by the surrounding Stack
            // on platforms without a status-bar inset (Linux desktop), and
            // so it stays above the avatar instead of overlapping it.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Center(
                    child: _GlassPill(
                      label: _statusText(),
                      monospace: true,
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
                child: c.isIncomingRinging
                    ? _IncomingControls(
                        onAccept: c.accept,
                        onDecline: c.decline,
                      )
                    : _ActiveControls(
                        muted: c.muted,
                        onMute: c.toggleMute,
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
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat();
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
            builder: (_, __) {
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
                        gradient: Brand.primary,
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
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
        ],
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
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
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
    required this.onMute,
    required this.onEnd,
  });
  final bool muted;
  final VoidCallback onMute;
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
        _CallButton(
          icon: Icons.call_end,
          danger: true,
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
          danger: true,
          onTap: onDecline,
        ),
        const SizedBox(width: 28),
        _CallButton(
          icon: Icons.call,
          accept: true,
          onTap: onAccept,
        ),
      ],
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.icon,
    required this.onTap,
    this.danger = false,
    this.active = false,
    this.accept = false,
  });
  final IconData icon;
  final VoidCallback onTap;
  final bool danger;
  final bool active;
  final bool accept;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    if (danger) {
      bg = const Color(0xFFDC2626);
      fg = Colors.white;
    } else if (accept) {
      bg = const Color(0xFF10B981);
      fg = Colors.white;
    } else if (active) {
      bg = Colors.white;
      fg = Brand.ink;
    } else {
      bg = Colors.white.withValues(alpha: 0.12);
      fg = Colors.white;
    }
    return Material(
      color: bg,
      shape: const CircleBorder(),
      elevation: (danger || accept) ? 8 : 0,
      shadowColor: danger
          ? const Color(0xFFDC2626).withValues(alpha: 0.4)
          : (accept
              ? const Color(0xFF10B981).withValues(alpha: 0.4)
              : null),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 64,
          height: 64,
          child: Icon(icon, color: fg, size: 26),
        ),
      ),
    );
  }
}
