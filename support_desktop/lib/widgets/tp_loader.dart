import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'brand_asset.dart';

class TpLoader extends StatefulWidget {
  const TpLoader({
    super.key,
    this.size,
    this.strokeWidth,
    this.color,
    this.value,
    this.valueColor,
    this.backgroundColor,
    this.semanticsLabel,
    this.showLogo,
  });

  final double? size;
  final double? strokeWidth;
  final Color? color;
  final double? value;
  final Animation<Color?>? valueColor;
  final Color? backgroundColor;
  final String? semanticsLabel;
  final bool? showLogo;

  static const double fullSize = 62;
  static const Color orange = Color(0xFFFF7D00);

  @override
  State<TpLoader> createState() => _TpLoaderState();
}

class _TpLoaderState extends State<TpLoader> with TickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  );
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _spin.duration = Duration(milliseconds: reduce ? 2400 : 850);
    if (widget.value == null && !_spin.isAnimating) _spin.repeat();
    if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
  }

  @override
  void dispose() {
    _spin.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final arcColor =
        widget.valueColor?.value ?? widget.color ?? TpLoader.orange;
    return Semantics(
      label: widget.semanticsLabel ?? 'Loading',
      child: LayoutBuilder(
        builder: (context, c) {
          double side;
          if (widget.size != null) {
            side = widget.size!;
          } else {
            final maxW = c.hasBoundedWidth ? c.maxWidth : double.infinity;
            final maxH = c.hasBoundedHeight ? c.maxHeight : double.infinity;
            final limit = math.min(maxW, maxH);
            side = limit.isFinite
                ? math.min(limit, TpLoader.fullSize)
                : TpLoader.fullSize;
          }
          final logo = widget.showLogo ?? side >= 40;
          final stroke =
              widget.strokeWidth ?? (logo ? 3.0 : math.max(2.0, side / 10));
          final track =
              widget.backgroundColor ?? arcColor.withValues(alpha: 0.22);
          return SizedBox(
            width: side,
            height: side,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedBuilder(
                  animation: _spin,
                  builder: (_, _) => Transform.rotate(
                    angle: widget.value == null ? _spin.value * 2 * math.pi : 0,
                    child: CustomPaint(
                      size: Size.square(side),
                      painter: _RingPainter(
                        stroke: stroke,
                        track: track,
                        arc: arcColor,
                        value: widget.value,
                      ),
                    ),
                  ),
                ),
                if (logo)
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (_, child) {
                      final t = Curves.easeInOut.transform(_pulse.value);
                      return Opacity(
                        opacity: 0.55 + 0.45 * t,
                        child: Transform.scale(
                          scale: 0.9 + 0.1 * t,
                          child: child,
                        ),
                      );
                    },
                    child: Image(
                      image: brandAsset('assets/brand/logo.png'),
                      width: side * 28 / 62,
                      height: side * 28 / 62,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.stroke,
    required this.track,
    required this.arc,
    this.value,
  });
  final double stroke;
  final Color track;
  final Color arc;
  final double? value;

  @override
  void paint(Canvas canvas, Size size) {
    final rect =
        Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawArc(rect, 0, 2 * math.pi, false, base);
    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt
      ..color = arc;
    if (value != null) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * value!.clamp(0.0, 1.0),
        false,
        fg,
      );
    } else {
      canvas.drawArc(rect, -math.pi * 3 / 4, math.pi / 2, false, fg);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.stroke != stroke ||
      old.track != track ||
      old.arc != arc ||
      old.value != value;
}
