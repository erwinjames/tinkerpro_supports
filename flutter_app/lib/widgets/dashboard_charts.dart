import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

String formatCount(num n) {
  final negative = n < 0;
  final digits = n.abs().round().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return negative ? '-$buf' : buf.toString();
}

String formatPeso(num amount) {
  final negative = amount < 0;
  final cents = (amount.abs() * 100).round();
  final whole = formatCount(cents ~/ 100);
  final frac = (cents % 100).toString().padLeft(2, '0');
  return '${negative ? '-' : ''}₱$whole.$frac';
}

class ChartPalette {
  ChartPalette._();

  static const brand = Color(0xFFFF7D00);
  static const live = Color(0xFF0E9F6E);
  static const info = Color(0xFF2563EB);
  static const warn = Color(0xFFD97706);
  static const muted = Color(0xFF8496A9);

  static Color ink(BrandColors b) =>
      b.isDark ? const Color(0xFFD7E1EE) : const Color(0xFF0B1B30);

  static List<Color> categorical(BrandColors b) => [
    brand,
    ink(b),
    info,
    live,
    muted,
    warn,
    const Color(0xFFFFB066),
    b.isDark ? const Color(0xFF5B7390) : const Color(0xFFC7D0DB),
  ];

  static Color tooltipBg(BrandColors b) =>
      b.isDark ? const Color(0xFF23456B) : const Color(0xF50B1B30);

  static Color grid(BrandColors b) =>
      b.isDark ? Colors.white.withValues(alpha: 0.07) : const Color(0x0F0B1B30);

  static Color areaFill(Color c, {double alpha = 0.18}) =>
      c.withValues(alpha: alpha);
}

bool chartReduceMotion(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;

Duration chartMotion(BuildContext context, int ms) =>
    chartReduceMotion(context) ? Duration.zero : Duration(milliseconds: ms);

class ChartSeries {
  const ChartSeries({
    required this.label,
    required this.color,
    required this.values,
  });

  final String label;
  final Color color;
  final List<int> values;
}

List<int> _niceTicks(int maxValue, {int target = 4}) {
  if (maxValue <= 0) return const [0, 1];
  final raw = maxValue / target;
  final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final norm = raw / mag;
  final mult = norm <= 1
      ? 1
      : norm <= 2
      ? 2
      : norm <= 5
      ? 5
      : 10;
  final step = math.max(1, (mult * mag).round());
  final top = (maxValue / step).ceil() * step;
  return [for (var v = 0; v <= top; v += step) v];
}

TextPainter _text(
  String s,
  TextStyle style, {
  double maxWidth = double.infinity,
  TextAlign align = TextAlign.left,
}) {
  final tp = TextPainter(
    text: TextSpan(text: s, style: style),
    textDirection: TextDirection.ltr,
    textAlign: align,
    maxLines: 1,
    ellipsis: '…',
  );
  tp.layout(maxWidth: maxWidth.isFinite ? math.max(0, maxWidth) : maxWidth);
  return tp;
}

void _addSmooth(Path path, List<Offset> p, {bool moveFirst = true}) {
  if (p.isEmpty) return;
  if (moveFirst) {
    path.moveTo(p[0].dx, p[0].dy);
  } else {
    path.lineTo(p[0].dx, p[0].dy);
  }
  final n = p.length;
  if (n == 1) return;
  final d = List<double>.generate(n - 1, (i) {
    final dx = p[i + 1].dx - p[i].dx;
    return dx == 0 ? 0 : (p[i + 1].dy - p[i].dy) / dx;
  });
  final m = List<double>.filled(n, 0);
  m[0] = d[0];
  m[n - 1] = d[n - 2];
  for (var i = 1; i < n - 1; i++) {
    m[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2;
  }
  for (var i = 0; i < n - 1; i++) {
    if (d[i] == 0) {
      m[i] = 0;
      m[i + 1] = 0;
      continue;
    }
    final a = m[i] / d[i];
    final b = m[i + 1] / d[i];
    final s = a * a + b * b;
    if (s > 9) {
      final t = 3 / math.sqrt(s);
      m[i] = t * a * d[i];
      m[i + 1] = t * b * d[i];
    }
  }
  for (var i = 0; i < n - 1; i++) {
    final dx = p[i + 1].dx - p[i].dx;
    path.cubicTo(
      p[i].dx + dx / 3,
      p[i].dy + m[i] * dx / 3,
      p[i + 1].dx - dx / 3,
      p[i + 1].dy - m[i + 1] * dx / 3,
      p[i + 1].dx,
      p[i + 1].dy,
    );
  }
}

void _dashedVLine(Canvas canvas, double x, double top, double bottom, Paint p) {
  var y = top;
  while (y < bottom) {
    canvas.drawLine(Offset(x, y), Offset(x, math.min(y + 4, bottom)), p);
    y += 8;
  }
}

void _paintTooltip(
  Canvas canvas,
  Size size,
  BrandColors b,
  double anchorX,
  double top,
  String title,
  List<(Color, String)> rows,
) {
  const pad = 10.0;
  final titleTp = _text(
    title.toUpperCase(),
    TextStyle(
      color: Colors.white.withValues(alpha: 0.62),
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.4,
    ),
  );
  final rowTps = [
    for (final r in rows)
      _text(
        r.$2,
        const TextStyle(
          color: Colors.white,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
  ];
  var w = titleTp.width;
  for (final t in rowTps) {
    w = math.max(w, t.width + 14);
  }
  w += pad * 2;
  var h = pad * 2 + titleTp.height;
  for (final t in rowTps) {
    h += t.height + 4;
  }
  var left = anchorX + 12;
  if (left + w > size.width) left = anchorX - 12 - w;
  if (left < 0) left = 0;
  final rect = RRect.fromRectAndRadius(
    Rect.fromLTWH(left, top, w, h),
    const Radius.circular(8),
  );
  canvas.drawRRect(rect, Paint()..color = ChartPalette.tooltipBg(b));
  var y = top + pad;
  titleTp.paint(canvas, Offset(left + pad, y));
  y += titleTp.height + 4;
  for (var i = 0; i < rows.length; i++) {
    final t = rowTps[i];
    canvas.drawCircle(
      Offset(left + pad + 4, y + t.height / 2),
      4,
      Paint()..color = rows[i].$1,
    );
    t.paint(canvas, Offset(left + pad + 14, y));
    y += t.height + 4;
  }
}

class AreaChart extends StatefulWidget {
  const AreaChart({
    super.key,
    required this.labels,
    required this.series,
    this.height = 220,
    this.stacked = false,
    this.maxXLabels = 6,
    this.labelFormatter,
    this.unit,
  });

  final List<String> labels;
  final List<ChartSeries> series;
  final double height;
  final bool stacked;
  final int maxXLabels;
  final String Function(String)? labelFormatter;
  final String? unit;

  @override
  State<AreaChart> createState() => _AreaChartState();
}

class _AreaChartState extends State<AreaChart> {
  int? _hover;
  double _width = 0;

  int get _count {
    var n = widget.labels.length;
    for (final s in widget.series) {
      n = math.max(n, s.values.length);
    }
    return n;
  }

  void _toggle(double dx) {
    final before = _hover;
    _track(dx);
    if (before != null && before == _hover) _clear();
  }

  void _track(double dx) {
    final n = _count;
    if (n < 2 || _width <= 0) return;
    final plotLeft = _AreaPainter.axisWidth;
    final plotW = _width - plotLeft - 4;
    final i = ((dx - plotLeft) / plotW * (n - 1)).round().clamp(0, n - 1);
    if (i != _hover) setState(() => _hover = i);
  }

  void _clear() {
    if (_hover != null) setState(() => _hover = null);
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return LayoutBuilder(
      builder: (context, c) {
        _width = c.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _toggle(d.localPosition.dx),
          onHorizontalDragStart: (d) => _track(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => _track(d.localPosition.dx),
          onHorizontalDragEnd: (_) => _clear(),
          onHorizontalDragCancel: _clear,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: chartMotion(context, 650),
            curve: Curves.easeOutQuart,
            builder: (context, t, _) => CustomPaint(
              size: Size(c.maxWidth, widget.height),
              painter: _AreaPainter(
                labels: widget.labels,
                series: widget.series,
                stacked: widget.stacked,
                hover: _hover,
                brand: b,
                progress: t,
                maxXLabels: widget.maxXLabels,
                labelFormatter: widget.labelFormatter,
                unit: widget.unit,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AreaPainter extends CustomPainter {
  _AreaPainter({
    required this.labels,
    required this.series,
    required this.stacked,
    required this.hover,
    required this.brand,
    required this.progress,
    required this.maxXLabels,
    required this.labelFormatter,
    required this.unit,
  });

  static const axisWidth = 34.0;

  final List<String> labels;
  final List<ChartSeries> series;
  final bool stacked;
  final int? hover;
  final BrandColors brand;
  final double progress;
  final int maxXLabels;
  final String Function(String)? labelFormatter;
  final String? unit;

  @override
  void paint(Canvas canvas, Size size) {
    var n = labels.length;
    for (final s in series) {
      n = math.max(n, s.values.length);
    }
    if (n < 2 || series.isEmpty) return;

    int valueAt(ChartSeries s, int i) => i < s.values.length ? s.values[i] : 0;

    final cumulative = <List<int>>[];
    for (var k = 0; k < series.length; k++) {
      final row = <int>[];
      for (var i = 0; i < n; i++) {
        final below = stacked && k > 0 ? cumulative[k - 1][i] : 0;
        row.add(below + valueAt(series[k], i));
      }
      cumulative.add(row);
    }
    var maxV = 0;
    for (final row in cumulative) {
      for (final v in row) {
        maxV = math.max(maxV, v);
      }
    }
    final ticks = _niceTicks(maxV);
    final top = ticks.last.toDouble();

    final tickStyle = TextStyle(
      color: brand.paperDim,
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
    );
    const plotTop = 8.0;
    const bottomPad = 20.0;
    final plotLeft = axisWidth;
    final plotRight = size.width - 4;
    final plotBottom = size.height - bottomPad;
    final plotW = plotRight - plotLeft;
    final plotH = plotBottom - plotTop;

    double xAt(int i) => plotLeft + plotW * i / (n - 1);
    double yAt(num v) => plotBottom - plotH * (v / top) * progress;

    final gridPaint = Paint()
      ..color = ChartPalette.grid(brand)
      ..strokeWidth = 1;
    for (final t in ticks) {
      final y = plotBottom - plotH * (t / top);
      canvas.drawLine(Offset(plotLeft, y), Offset(plotRight, y), gridPaint);
      final tp = _text(formatCount(t), tickStyle);
      tp.paint(canvas, Offset(plotLeft - 6 - tp.width, y - tp.height / 2));
    }

    final step = math.max(1, (n / maxXLabels).ceil());
    for (var i = n - 1; i >= 0; i -= step) {
      if (i >= labels.length) continue;
      final raw = labels[i];
      final label = labelFormatter == null ? raw : labelFormatter!(raw);
      final tp = _text(label, tickStyle, maxWidth: plotW / maxXLabels + 12);
      var x = xAt(i) - tp.width / 2;
      x = x.clamp(plotLeft - 4, size.width - tp.width);
      tp.paint(canvas, Offset(x, plotBottom + 6));
    }

    for (var k = series.length - 1; k >= 0; k--) {
      final s = series[k];
      final upper = [
        for (var i = 0; i < n; i++) Offset(xAt(i), yAt(cumulative[k][i])),
      ];
      final lower = stacked && k > 0
          ? [
              for (var i = n - 1; i >= 0; i--)
                Offset(xAt(i), yAt(cumulative[k - 1][i])),
            ]
          : [Offset(xAt(n - 1), plotBottom), Offset(xAt(0), plotBottom)];
      final area = Path();
      _addSmooth(area, upper);
      if (stacked && k > 0) {
        _addSmooth(area, lower, moveFirst: false);
      } else {
        area.lineTo(lower[0].dx, lower[0].dy);
        area.lineTo(lower[1].dx, lower[1].dy);
      }
      area.close();
      final fill = Paint()
        ..color = ChartPalette.areaFill(s.color, alpha: stacked ? 0.20 : 0.18);
      canvas.drawPath(area, fill);
    }

    for (var k = 0; k < series.length; k++) {
      final s = series[k];
      final pts = [
        for (var i = 0; i < n; i++) Offset(xAt(i), yAt(cumulative[k][i])),
      ];
      final line = Path();
      _addSmooth(line, pts);
      canvas.drawPath(
        line,
        Paint()
          ..color = s.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
      if (series.length == 1 && n <= 12) {
        for (final p in pts) {
          canvas.drawCircle(p, 3, Paint()..color = brand.surface);
          canvas.drawCircle(
            p,
            3,
            Paint()
              ..color = s.color
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          );
        }
      }
    }

    final h = hover;
    if (h != null && h >= 0 && h < n) {
      final x = xAt(h);
      _dashedVLine(
        canvas,
        x,
        plotTop,
        plotBottom,
        Paint()
          ..color = brand.paperDim.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
      for (var k = 0; k < series.length; k++) {
        final p = Offset(x, yAt(cumulative[k][h]));
        canvas.drawCircle(p, 5, Paint()..color = brand.surface);
        canvas.drawCircle(
          p,
          5,
          Paint()
            ..color = series[k].color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
      }
      final title = h < labels.length ? labels[h] : '';
      final rows = <(Color, String)>[
        for (final s in series)
          (
            s.color,
            series.length == 1
                ? '${formatCount(valueAt(s, h))} ${(unit ?? s.label).toLowerCase()}'
                : '${s.label}: ${formatCount(valueAt(s, h))}',
          ),
      ];
      _paintTooltip(canvas, size, brand, x, plotTop, title, rows);
    }
  }

  @override
  bool shouldRepaint(covariant _AreaPainter old) =>
      old.hover != hover ||
      old.progress != progress ||
      old.series != series ||
      old.labels != labels ||
      old.brand != brand ||
      old.stacked != stacked;
}

class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    this.color = ChartPalette.brand,
    this.height = 28,
  });

  final List<int> values;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparkPainter(values, color, context.brand.surface),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color, this.surface);

  final List<int> values;
  final Color color;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    const pad = 3.0;
    final maxV = values.reduce(math.max);
    final minV = values.reduce(math.min);
    final range = (maxV - minV) == 0 ? 1 : (maxV - minV);
    final w = size.width - 5;
    final h = size.height;
    final step = w / (values.length - 1);
    final pts = [
      for (var i = 0; i < values.length; i++)
        Offset(
          i * step,
          h - pad - ((values[i] - minV) / range) * (h - pad * 2),
        ),
    ];
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      line.lineTo(p.dx, p.dy);
    }
    final area = Path.from(line)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      area,
      Paint()..color = ChartPalette.areaFill(color, alpha: 0.18),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    final tip = pts.last;
    canvas.drawCircle(tip, 3.4, Paint()..color = surface);
    canvas.drawCircle(tip, 2.6, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) =>
      old.values != values || old.color != color || old.surface != surface;
}

class DonutChart extends StatefulWidget {
  const DonutChart({
    super.key,
    required this.labels,
    required this.values,
    required this.colors,
    this.size = 132,
  });

  final List<String> labels;
  final List<int> values;
  final List<Color> colors;
  final double size;

  @override
  State<DonutChart> createState() => _DonutChartState();
}

class _DonutChartState extends State<DonutChart> {
  final Set<int> _hidden = {};

  @override
  void didUpdateWidget(covariant DonutChart old) {
    super.didUpdateWidget(old);
    if (old.labels.length != widget.labels.length) _hidden.clear();
  }

  Color _color(int i) => widget.colors.isEmpty
      ? ChartPalette.muted
      : widget.colors[i % widget.colors.length];

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final total = widget.values.fold<int>(0, (a, v) => a + v);
    final shown = [
      for (var i = 0; i < widget.values.length; i++)
        _hidden.contains(i) ? 0 : widget.values[i],
    ];
    final legend = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < widget.labels.length; i++)
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => setState(() {
              if (!_hidden.remove(i)) _hidden.add(i);
            }),
            child: Opacity(
              opacity: _hidden.contains(i) ? 0.4 : 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
                child: Row(
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: _color(i),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.labels[i],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(
                          color: b.paper,
                          fontWeight: FontWeight.w500,
                          decoration: _hidden.contains(i)
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatCount(widget.values[i]),
                      style: text.labelLarge?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      child: Text(
                        '${total == 0 ? 0 : (widget.values[i] / total * 100).round()}%',
                        textAlign: TextAlign.right,
                        style: text.labelMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: chartMotion(context, 700),
          curve: Curves.easeOutQuart,
          builder: (context, t, _) => CustomPaint(
            size: Size.square(widget.size),
            painter: _DonutPainter(
              values: shown,
              colors: [for (var i = 0; i < shown.length; i++) _color(i)],
              progress: t,
              brand: b,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(child: legend),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.values,
    required this.colors,
    required this.progress,
    required this.brand,
  });

  final List<int> values;
  final List<Color> colors;
  final double progress;
  final BrandColors brand;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<int>(0, (a, v) => a + v);
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 2;
    final thickness = radius * 0.24;
    final rect = Rect.fromCircle(
      center: center,
      radius: radius - thickness / 2,
    );
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = brand.surfaceHi
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness,
    );
    if (total > 0) {
      final nonZero = values.where((v) => v > 0).length;
      final gap = nonZero > 1 ? 0.035 : 0.0;
      var start = -math.pi / 2;
      final sweepAll = math.pi * 2 * progress;
      for (var i = 0; i < values.length; i++) {
        if (values[i] <= 0) continue;
        final sweep = sweepAll * values[i] / total;
        final draw = math.max(0.0, sweep - gap);
        canvas.drawArc(
          rect,
          start + gap / 2,
          draw,
          false,
          Paint()
            ..color = colors[i]
            ..style = PaintingStyle.stroke
            ..strokeWidth = thickness
            ..strokeCap = StrokeCap.butt,
        );
        start += sweep;
      }
    }
    final num = _text(
      formatCount(total),
      TextStyle(
        color: brand.paper,
        fontSize: radius > 55 ? 21 : 17,
        fontWeight: FontWeight.w700,
      ),
    );
    final cap = _text(
      'TOTAL',
      TextStyle(
        color: brand.paperDim,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
    num.paint(canvas, center - Offset(num.width / 2, num.height / 2 + 5));
    cap.paint(canvas, center + Offset(-cap.width / 2, num.height / 2 - 3));
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.progress != progress ||
      old.values != values ||
      old.brand != brand ||
      old.colors != colors;
}

class BarChart extends StatelessWidget {
  const BarChart({
    super.key,
    required this.labels,
    required this.values,
    this.color = ChartPalette.brand,
    this.height = 220,
  });

  final List<String> labels;
  final List<int> values;
  final Color color;
  final double height;

  bool get horizontal => labels.length > 5;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final h = horizontal ? labels.length * 30.0 + 26 : height;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: chartMotion(context, 650),
      curve: Curves.easeOutQuart,
      builder: (context, t, _) => CustomPaint(
        size: Size(double.infinity, h),
        painter: horizontal
            ? _HBarPainter(labels, values, color, b, t)
            : _VBarPainter(labels, values, color, b, t),
      ),
    );
  }
}

class _VBarPainter extends CustomPainter {
  _VBarPainter(this.labels, this.values, this.color, this.brand, this.progress);

  final List<String> labels;
  final List<int> values;
  final Color color;
  final BrandColors brand;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    if (n == 0) return;
    final ticks = _niceTicks(values.reduce(math.max));
    final top = ticks.last.toDouble();
    final tickStyle = TextStyle(
      color: brand.paperDim,
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
    );
    const plotTop = 18.0;
    const plotLeft = 34.0;
    final plotRight = size.width - 4;
    final plotBottom = size.height - 22;
    final plotW = plotRight - plotLeft;
    final plotH = plotBottom - plotTop;
    final grid = Paint()
      ..color = ChartPalette.grid(brand)
      ..strokeWidth = 1;
    for (final t in ticks) {
      final y = plotBottom - plotH * t / top;
      canvas.drawLine(Offset(plotLeft, y), Offset(plotRight, y), grid);
      final tp = _text(formatCount(t), tickStyle);
      tp.paint(canvas, Offset(plotLeft - 6 - tp.width, y - tp.height / 2));
    }
    final slot = plotW / n;
    final barW = math.min(34.0, slot * 0.8 * 0.66);
    final valueStyle = TextStyle(
      color: brand.paperDim,
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
    );
    for (var i = 0; i < n; i++) {
      final cx = plotLeft + slot * (i + 0.5);
      final bh = plotH * values[i] / top * progress;
      final r = Rect.fromLTWH(cx - barW / 2, plotBottom - bh, barW, bh);
      if (bh > 0) {
        final rr = RRect.fromRectAndRadius(
          r,
          Radius.circular(math.min(7, barW / 2)),
        );
        canvas.drawRRect(rr, Paint()..color = color);
      }
      if (values[i] > 0) {
        final vt = _text(formatCount(values[i]), valueStyle);
        vt.paint(canvas, Offset(cx - vt.width / 2, r.top - vt.height - 3));
      }
      final lt = _text(
        labels[i],
        tickStyle,
        maxWidth: slot - 4,
        align: TextAlign.center,
      );
      lt.paint(canvas, Offset(cx - lt.width / 2, plotBottom + 6));
    }
  }

  @override
  bool shouldRepaint(covariant _VBarPainter old) =>
      old.progress != progress ||
      old.values != values ||
      old.labels != labels ||
      old.brand != brand;
}

class _HBarPainter extends CustomPainter {
  _HBarPainter(this.labels, this.values, this.color, this.brand, this.progress);

  final List<String> labels;
  final List<int> values;
  final Color color;
  final BrandColors brand;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    if (n == 0) return;
    final ticks = _niceTicks(values.reduce(math.max), target: 3);
    final top = ticks.last.toDouble();
    final labelStyle = TextStyle(
      color: brand.paper,
      fontSize: 11.5,
      fontWeight: FontWeight.w500,
    );
    final tickStyle = TextStyle(
      color: brand.paperDim,
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
    );
    var labelW = 0.0;
    for (final l in labels) {
      labelW = math.max(labelW, _text(l, labelStyle).width);
    }
    labelW = math.min(labelW, size.width * 0.38) + 8;
    final plotLeft = labelW;
    final plotRight = size.width - 34;
    final plotBottom = size.height - 20;
    final plotW = plotRight - plotLeft;
    final rowH = plotBottom / n;
    final grid = Paint()
      ..color = ChartPalette.grid(brand)
      ..strokeWidth = 1;
    for (final t in ticks) {
      final x = plotLeft + plotW * t / top;
      canvas.drawLine(Offset(x, 0), Offset(x, plotBottom), grid);
      final tp = _text(formatCount(t), tickStyle);
      tp.paint(canvas, Offset(x - tp.width / 2, plotBottom + 5));
    }
    final valueStyle = TextStyle(
      color: brand.paperDim,
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
    );
    final barH = math.min(18.0, rowH * 0.62);
    for (var i = 0; i < n; i++) {
      final cy = rowH * (i + 0.5);
      final lt = _text(labels[i], labelStyle, maxWidth: labelW - 8);
      lt.paint(canvas, Offset(0, cy - lt.height / 2));
      final bw = plotW * values[i] / top * progress;
      if (bw > 0) {
        final rect = Rect.fromLTWH(plotLeft, cy - barH / 2, bw, barH);
        final rr = RRect.fromRectAndRadius(
          rect,
          Radius.circular(math.min(7, barH / 2)),
        );
        canvas.drawRRect(rr, Paint()..color = color);
      }
      if (values[i] > 0) {
        final vt = _text(formatCount(values[i]), valueStyle);
        vt.paint(canvas, Offset(plotLeft + bw + 6, cy - vt.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HBarPainter old) =>
      old.progress != progress ||
      old.values != values ||
      old.labels != labels ||
      old.brand != brand;
}
