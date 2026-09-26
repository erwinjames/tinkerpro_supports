import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

class DashColors {
  const DashColors._(
    this.dark,
    this.surface,
    this.surface2,
    this.ink,
    this.inkSoft,
    this.muted,
    this.muted2,
    this.line,
    this.lineSoft,
  );

  final bool dark;
  final Color surface;
  final Color surface2;
  final Color ink;
  final Color inkSoft;
  final Color muted;
  final Color muted2;
  final Color line;
  final Color lineSoft;

  static const brand = Color(0xFFFF7D00);
  static const brand600 = Color(0xFFEA6E00);
  static const brand700 = Color(0xFFC25C00);
  static const inkHex = Color(0xFF0B1B30);
  static const pos = Color(0xFF0E9F6E);
  static const neg = Color(0xFFE02424);
  static const info = Color(0xFF2563EB);
  static const warn = Color(0xFFD97706);

  Color get brand050 =>
      dark ? brand.withValues(alpha: 0.14) : const Color(0xFFFFF5EC);
  Color get grid => ink.withValues(alpha: 0.06);
  Color get seriesInk => dark ? const Color(0xFFC7D0DB) : inkHex;

  List<Color> get palette => [
    brand,
    seriesInk,
    info,
    pos,
    const Color(0xFF8496A9),
    warn,
    const Color(0xFFFFB066),
    const Color(0xFFC7D0DB),
  ];

  static DashColors of(BuildContext context) {
    final b = context.brand;
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (dark) {
      return DashColors._(
        true,
        b.surface,
        b.surfaceHi,
        b.paper,
        const Color(0xFFD5DEE9),
        b.paperDim,
        const Color(0xFF8496A9),
        b.rule,
        b.rule.withValues(alpha: 0.7),
      );
    }
    return DashColors._(
      false,
      Colors.white,
      const Color(0xFFF8FAFC),
      inkHex,
      const Color(0xFF2E4159),
      const Color(0xFF5A6B80),
      const Color(0xFF8496A9),
      const Color(0xFFE3E8F0),
      const Color(0xFFEEF2F7),
    );
  }
}

String dashFmt(num n) {
  final neg = n < 0;
  final s = n.abs().round().toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return neg ? '-$out' : out.toString();
}

String dashTitleCase(String s) => s
    .replaceAll('_', ' ')
    .replaceAllMapped(RegExp(r'\b\w'), (m) => m.group(0)!.toUpperCase());

double dashNiceStep(double max, {int maxTicks = 6}) {
  if (max <= 0) return 1;
  final raw = max / (maxTicks - 1);
  final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final norm = raw / mag;
  double nice;
  if (norm <= 1) {
    nice = 1;
  } else if (norm <= 2) {
    nice = 2;
  } else if (norm <= 5) {
    nice = 5;
  } else {
    nice = 10;
  }
  return math.max(1, nice * mag);
}

double dashNiceMax(double max, double step) =>
    max <= 0 ? step : (max / step).ceil() * step;

TextStyle _tick(DashColors c) => TextStyle(
  fontSize: 10,
  fontWeight: FontWeight.w600,
  color: c.muted2,
  height: 1.1,
);

class DashNoData extends StatelessWidget {
  const DashNoData({super.key, this.height, this.width});
  final double? height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final c = DashColors.of(context);
    return SizedBox(
      height: height,
      width: width,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CustomPaint(
          painter: _HatchPainter(
            c.dark
                ? Colors.white.withValues(alpha: 0.04)
                : const Color(0xFFF1F5F9).withValues(alpha: 0.75),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CustomPaint(
                  size: const Size(26, 26),
                  painter: _DashedCirclePainter(c.line),
                ),
                const SizedBox(height: 8),
                Text(
                  'NO DATA YET',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.7,
                    color: c.muted2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HatchPainter extends CustomPainter {
  _HatchPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 9
      ..style = PaintingStyle.stroke;
    const period = 18.0 * math.sqrt2;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (double d = -size.height; d < size.width + period; d += period) {
      canvas.drawLine(Offset(d, 0), Offset(d + size.height, size.height), p);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HatchPainter old) => old.color != color;
}

class _DashedCirclePainter extends CustomPainter {
  _DashedCirclePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final r = size.width / 2 - 1;
    final center = size.center(Offset.zero);
    const dashes = 14;
    for (var i = 0; i < dashes; i++) {
      final start = (i / dashes) * 2 * math.pi;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r),
        start,
        (2 * math.pi / dashes) * 0.55,
        false,
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DashedCirclePainter old) => old.color != color;
}

class DashSparkline extends StatelessWidget {
  const DashSparkline({super.key, required this.data, this.primary = false});
  final List<int> data;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: CustomPaint(
        painter: _SparkPainter(data, primary),
        size: Size.infinite,
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.data, this.primary);
  final List<int> data;
  final bool primary;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;
    const vh = 28.0;
    const pad = 3.0;
    final sx = size.width / 100;
    final sy = size.height / vh;
    final maxV = data.reduce(math.max).toDouble();
    final minV = data.reduce(math.min).toDouble();
    final range = (maxV - minV) == 0 ? 1.0 : (maxV - minV);
    final step = 100 / (data.length - 1);
    final pts = <Offset>[
      for (var i = 0; i < data.length; i++)
        Offset(
          i * step * sx,
          (vh - pad - ((data[i] - minV) / range) * (vh - pad * 2)) * sy,
        ),
    ];
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      line.lineTo(p.dx, p.dy);
    }
    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..color = DashColors.brand.withValues(alpha: primary ? 0.24 : 0.12),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = DashColors.brand
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.75
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    final tip = pts.last;
    canvas.drawCircle(
      tip,
      4.5,
      Paint()..color = DashColors.brand.withValues(alpha: 0.22),
    );
    canvas.drawCircle(
      tip,
      2.1,
      Paint()..color = primary ? Colors.white : DashColors.brand,
    );
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) =>
      old.primary != primary || !_listEq(old.data, data);
}

bool _listEq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

LineTouchTooltipData _lineTooltip(DashColors c, String? unit) =>
    LineTouchTooltipData(
      tooltipBorderRadius: BorderRadius.circular(8),
      tooltipPadding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      getTooltipColor: (_) => const Color(0xF50B1B30),
      fitInsideHorizontally: true,
      fitInsideVertically: true,
      maxContentWidth: 220,
      getTooltipItems: (spots) => spots
          .map(
            (s) => LineTooltipItem(
              unit == null
                  ? dashFmt(s.y)
                  : '${dashFmt(s.y)} ${unit.toLowerCase()}',
              const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
          .toList(),
    );

class DashHeartbeatSeries {
  const DashHeartbeatSeries(this.label, this.color, this.values);
  final String label;
  final Color color;
  final List<int> values;
}

class DashHeartbeatChart extends StatelessWidget {
  const DashHeartbeatChart({
    super.key,
    required this.labels,
    required this.series,
    this.height = 320,
  });

  final List<String> labels;
  final List<DashHeartbeatSeries> series;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = DashColors.of(context);
    final n = labels.length;
    final stacked = <List<double>>[];
    for (var s = 0; s < series.length; s++) {
      final row = <double>[];
      for (var i = 0; i < n; i++) {
        final own = i < series[s].values.length ? series[s].values[i] : 0;
        row.add((s == 0 ? 0.0 : stacked[s - 1][i]) + own.toDouble());
      }
      stacked.add(row);
    }
    var maxV = 0.0;
    for (final r in stacked) {
      for (final v in r) {
        maxV = math.max(maxV, v);
      }
    }
    final step = dashNiceStep(maxV);
    final maxY = dashNiceMax(maxV, step);
    final every = n > 12 ? (n / 12).ceil() : 1;

    return SizedBox(
      height: height,
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 18,
              runSpacing: 6,
              children: [
                for (final s in series)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: s.color.withValues(alpha: 0.2),
                          border: Border.all(color: s.color, width: 2),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        s.label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: c.muted,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: math.max(1, n - 1).toDouble(),
                minY: 0,
                maxY: maxY,
                clipData: const FlClipData.all(),
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: step,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: c.grid, strokeWidth: 1),
                ),
                titlesData: _titles(
                  c,
                  step: step,
                  bottom: (v) {
                    final i = v.round();
                    if (i < 0 || i >= n || i % every != 0) return '';
                    return labels[i];
                  },
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    tooltipBorderRadius: BorderRadius.circular(8),
                    tooltipPadding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    getTooltipColor: (_) => const Color(0xF50B1B30),
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    maxContentWidth: 220,
                    getTooltipItems: (spots) => spots.map((s) {
                      final ser = series[s.barIndex];
                      final i = s.x.round();
                      final v = i < ser.values.length ? ser.values[i] : 0;
                      return LineTooltipItem(
                        '${ser.label}: ${dashFmt(v)}',
                        TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          shadows: [Shadow(color: ser.color, blurRadius: 0)],
                        ),
                      );
                    }).toList(),
                  ),
                  getTouchedSpotIndicator: (bar, idx) => idx
                      .map(
                        (_) => TouchedSpotIndicatorData(
                          FlLine(
                            color: c.ink.withValues(alpha: 0.22),
                            strokeWidth: 1,
                            dashArray: const [4, 4],
                          ),
                          FlDotData(
                            getDotPainter: (spot, p, b, i) =>
                                FlDotCirclePainter(
                                  radius: 5,
                                  color: Colors.white,
                                  strokeWidth: 3,
                                  strokeColor: b.color ?? DashColors.brand,
                                ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                lineBarsData: [
                  for (var s = 0; s < series.length; s++)
                    LineChartBarData(
                      spots: [
                        for (var i = 0; i < n; i++)
                          FlSpot(i.toDouble(), stacked[s][i]),
                      ],
                      isCurved: true,
                      curveSmoothness: 0.38,
                      preventCurveOverShooting: true,
                      color: series[s].color,
                      barWidth: 2,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            series[s].color.withValues(alpha: 0.2),
                            series[s].color.withValues(alpha: 0.01),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

FlTitlesData _titles(
  DashColors c, {
  required double step,
  required String Function(double) bottom,
  double leftReserved = 34,
}) {
  return FlTitlesData(
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        interval: step,
        reservedSize: leftReserved,
        getTitlesWidget: (v, meta) => SideTitleWidget(
          meta: meta,
          space: 6,
          child: Text(dashFmt(v), style: _tick(c)),
        ),
      ),
    ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        interval: 1,
        reservedSize: 24,
        getTitlesWidget: (v, meta) {
          if ((v - v.roundToDouble()).abs() > 0.001) {
            return const SizedBox.shrink();
          }
          final t = bottom(v);
          if (t.isEmpty) return const SizedBox.shrink();
          return SideTitleWidget(
            meta: meta,
            space: 6,
            child: Text(t, style: _tick(c)),
          );
        },
      ),
    ),
  );
}

class DashLineChart extends StatelessWidget {
  const DashLineChart({
    super.key,
    required this.labels,
    required this.values,
    required this.unit,
    required this.height,
  });

  final List<String> labels;
  final List<int> values;
  final String unit;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = DashColors.of(context);
    final n = values.length;
    final maxV = values.isEmpty ? 0.0 : values.reduce(math.max).toDouble();
    final step = dashNiceStep(maxV);
    final maxY = dashNiceMax(maxV, step);
    final showDots = n <= 12;
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.only(right: 22, top: 6),
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: math.max(1, n - 1).toDouble(),
            minY: 0,
            maxY: maxY,
            borderData: FlBorderData(show: false),
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: step,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: c.grid, strokeWidth: 1),
            ),
            titlesData: _titles(
              c,
              step: step,
              bottom: (v) {
                final i = v.round();
                return i >= 0 && i < labels.length ? labels[i] : '';
              },
            ),
            lineTouchData: LineTouchData(
              touchTooltipData: _lineTooltip(c, unit),
              getTouchedSpotIndicator: (bar, idx) => idx
                  .map(
                    (_) => TouchedSpotIndicatorData(
                      FlLine(
                        color: c.ink.withValues(alpha: 0.22),
                        strokeWidth: 1,
                        dashArray: const [4, 4],
                      ),
                      FlDotData(
                        getDotPainter: (spot, p, b, i) => FlDotCirclePainter(
                          radius: 6,
                          color: Colors.white,
                          strokeWidth: 3,
                          strokeColor: DashColors.brand,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: [
                  for (var i = 0; i < n; i++)
                    FlSpot(i.toDouble(), values[i].toDouble()),
                ],
                isCurved: n > 2,
                curveSmoothness: 0.38,
                preventCurveOverShooting: true,
                color: DashColors.brand,
                barWidth: 2.5,
                dotData: FlDotData(
                  show: showDots,
                  getDotPainter: (spot, p, b, i) => FlDotCirclePainter(
                    radius: 3,
                    color: Colors.white,
                    strokeWidth: 2,
                    strokeColor: DashColors.brand,
                  ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      DashColors.brand.withValues(alpha: 0.22),
                      DashColors.brand.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DashBarChart extends StatelessWidget {
  const DashBarChart({
    super.key,
    required this.labels,
    required this.values,
    required this.unit,
    required this.height,
  });

  final List<String> labels;
  final List<int> values;
  final String unit;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (labels.length > 5) {
      return _DashHBarChart(
        labels: labels,
        values: values,
        unit: unit,
        height: height,
      );
    }
    final c = DashColors.of(context);
    final n = values.length;
    final maxV = values.isEmpty ? 0.0 : values.reduce(math.max).toDouble();
    final step = dashNiceStep(maxV);
    final maxY = dashNiceMax(maxV, step);
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.only(top: 18, right: 6),
        child: LayoutBuilder(
          builder: (context, box) {
            final band = n == 0 ? 0.0 : (box.maxWidth - 34) / n;
            final w = math.min(34.0, band * 0.8 * 0.66);
            return BarChart(
              BarChartData(
                minY: 0,
                maxY: maxY,
                alignment: BarChartAlignment.spaceAround,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: step,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: c.grid, strokeWidth: 1),
                ),
                titlesData: _titles(
                  c,
                  step: step,
                  bottom: (v) {
                    final i = v.round();
                    return i >= 0 && i < labels.length ? labels[i] : '';
                  },
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    tooltipBorderRadius: BorderRadius.circular(8),
                    tooltipPadding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    getTooltipColor: (_) => const Color(0xF50B1B30),
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(
                      '${labels[g.x]}\n',
                      const TextStyle(
                        color: Color(0x9EFFFFFF),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                      children: [
                        TextSpan(
                          text: '${dashFmt(values[g.x])} ${unit.toLowerCase()}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < n; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: values[i].toDouble(),
                          width: w,
                          borderRadius: BorderRadius.circular(6),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              DashColors.brand.withValues(alpha: 0.62),
                              DashColors.brand,
                            ],
                          ),
                          label: BarChartRodLabel(
                            show: values[i] != 0,
                            text: dashFmt(values[i]),
                            offset: const Offset(0, 6),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: c.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DashHBarChart extends StatefulWidget {
  const _DashHBarChart({
    required this.labels,
    required this.values,
    required this.unit,
    required this.height,
  });

  final List<String> labels;
  final List<int> values;
  final String unit;
  final double height;

  @override
  State<_DashHBarChart> createState() => _DashHBarChartState();
}

class _DashHBarChartState extends State<_DashHBarChart> {
  int? _hover;

  @override
  Widget build(BuildContext context) {
    final c = DashColors.of(context);
    final labels = widget.labels;
    final values = widget.values;
    final n = values.length;
    final maxV = values.isEmpty ? 0.0 : values.reduce(math.max).toDouble();
    final step = dashNiceStep(maxV);
    final maxX = dashNiceMax(maxV, step);
    final ticks = (maxX / step).round();
    final tp = TextPainter(textDirection: TextDirection.ltr);
    var labelW = 0.0;
    for (final l in labels) {
      tp.text = TextSpan(text: l, style: _tick(c));
      tp.layout();
      labelW = math.max(labelW, tp.width);
    }
    labelW = math.min(labelW + 6, 160);
    const axisH = 22.0;

    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, box) {
          final plotW = math.max(10.0, box.maxWidth - labelW - 34);
          final plotH = widget.height - axisH;
          final band = n == 0 ? 0.0 : plotH / n;
          final thick = math.min(34.0, band * 0.8 * 0.66);
          return Stack(
            clipBehavior: Clip.none,
            children: [
              for (var t = 0; t <= ticks; t++)
                Positioned(
                  left: labelW + plotW * t / ticks,
                  top: 0,
                  height: plotH,
                  child: Container(width: 1, color: c.grid),
                ),
              for (var t = 0; t <= ticks; t++)
                Positioned(
                  left: labelW + plotW * t / ticks - 20,
                  width: 40,
                  top: plotH + 6,
                  child: Text(
                    dashFmt(step * t),
                    textAlign: TextAlign.center,
                    style: _tick(c),
                  ),
                ),
              for (var i = 0; i < n; i++) ...[
                Positioned(
                  left: 0,
                  width: labelW - 6,
                  top: band * i,
                  height: band,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      labels[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _tick(c),
                    ),
                  ),
                ),
                Positioned(
                  left: labelW,
                  top: band * i + (band - thick) / 2,
                  height: thick,
                  width: math.max(0, plotW * values[i] / maxX),
                  child: MouseRegion(
                    onEnter: (_) => setState(() => _hover = i),
                    onExit: (_) => setState(() => _hover = null),
                    child: Tooltip(
                      message:
                          '${labels[i]}\n${dashFmt(values[i])} ${widget.unit.toLowerCase()}',
                      decoration: BoxDecoration(
                        color: const Color(0xF50B1B30),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      textStyle: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _hover == i ? c.seriesInk : DashColors.brand,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
                ),
                if (values[i] != 0)
                  Positioned(
                    left: labelW + plotW * values[i] / maxX + 7,
                    top: band * i,
                    height: band,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        dashFmt(values[i]),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: c.muted,
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class DashDoughnut extends StatefulWidget {
  const DashDoughnut({
    super.key,
    required this.labels,
    required this.values,
    required this.colors,
  });

  final List<String> labels;
  final List<int> values;
  final List<Color> colors;

  @override
  State<DashDoughnut> createState() => _DashDoughnutState();
}

class _DashDoughnutState extends State<DashDoughnut> {
  final Set<int> _hidden = {};
  int _touched = -1;

  @override
  Widget build(BuildContext context) {
    final c = DashColors.of(context);
    final values = widget.values;
    final total = values.fold<int>(0, (a, b) => a + b);
    final shownTotal = [
      for (var i = 0; i < values.length; i++)
        if (!_hidden.contains(i)) values[i],
    ].fold<int>(0, (a, b) => a + b);
    final pctBase = total == 0 ? 1 : total;
    Color colorAt(int i) => widget.colors[i % widget.colors.length];

    const size = 152.0;
    const outer = size / 2 - 4;
    const inner = outer * 0.76;

    final chart = SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              startDegreeOffset: -90,
              sectionsSpace: 2,
              centerSpaceRadius: inner,
              pieTouchData: PieTouchData(
                touchCallback: (e, r) {
                  final idx = r?.touchedSection?.touchedSectionIndex ?? -1;
                  if (idx != _touched) setState(() => _touched = idx);
                },
              ),
              sections: [
                for (var i = 0; i < values.length; i++)
                  if (!_hidden.contains(i) && values[i] > 0)
                    PieChartSectionData(
                      value: values[i].toDouble(),
                      color: colorAt(i),
                      radius:
                          (outer - inner) +
                          (_touched >= 0 && _sectionIndexToData(_touched) == i
                              ? 4
                              : 0),
                      showTitle: false,
                      cornerRadius: 4,
                    ),
              ],
            ),
          ),
          IgnorePointer(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  dashFmt(shownTotal),
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'TOTAL',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: c.muted2,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final legend = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < values.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 9),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() {
                  if (!_hidden.remove(i)) _hidden.add(i);
                }),
                child: Opacity(
                  opacity: _hidden.contains(i) ? 0.42 : 1,
                  child: Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: colorAt(i),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          widget.labels[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.2,
                            fontWeight: FontWeight.w600,
                            color: c.muted,
                            decoration: _hidden.contains(i)
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Text(
                        dashFmt(values[i]),
                        style: TextStyle(
                          fontSize: 11.2,
                          fontWeight: FontWeight.w700,
                          color: c.ink,
                        ),
                      ),
                      const SizedBox(width: 9),
                      SizedBox(
                        width: 34,
                        child: Text(
                          '${(values[i] / pctBase * 100).round()}%',
                          textAlign: TextAlign.right,
                          style: TextStyle(fontSize: 10, color: c.muted2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 176),
      child: LayoutBuilder(
        builder: (context, box) {
          if (box.maxWidth < 280) {
            return SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 148,
                    height: 148,
                    child: FittedBox(child: chart),
                  ),
                  const SizedBox(height: 14),
                  legend,
                ],
              ),
            );
          }
          return Row(
            children: [
              chart,
              const SizedBox(width: 18),
              Expanded(child: legend),
            ],
          );
        },
      ),
    );
  }

  int _sectionIndexToData(int sectionIndex) {
    var k = -1;
    for (var i = 0; i < widget.values.length; i++) {
      if (_hidden.contains(i) || widget.values[i] <= 0) continue;
      k++;
      if (k == sectionIndex) return i;
    }
    return -1;
  }
}
