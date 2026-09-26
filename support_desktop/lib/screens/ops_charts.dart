import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

const _tickColor = Color(0xFF6B6358);
const _gridColor = Color(0x0D000000);
const _tooltipBg = Color(0xFF0C233E);

const opsResolverPalette = <Color>[
  Color(0xFFFF7D00),
  Color(0xFF2563EB),
  Color(0xFF16A34A),
  Color(0xFFDC2626),
  Color(0xFFD97706),
  Color(0xFF7C3AED),
  Color(0xFF0891B2),
  Color(0xFFDB2777),
  Color(0xFF0F766E),
  Color(0xFF9333EA),
];

const opsStorePalette = <Color>[
  Color(0xFF2563EB),
  Color(0xFFFF7D00),
  Color(0xFF16A34A),
  Color(0xFFDC2626),
  Color(0xFFD97706),
  Color(0xFF7C3AED),
  Color(0xFF0891B2),
  Color(0xFFDB2777),
  Color(0xFF0F766E),
  Color(0xFF9333EA),
];

Color opsColorFor(String name, List<Color> palette) {
  final s = name.isEmpty ? '?' : name;
  final a = s.codeUnitAt(0);
  final b = s.length > 1 ? s.codeUnitAt(1) : 0;
  return palette[(a + b) % palette.length];
}

double _niceStep(double max, int targetTicks) {
  if (max <= 0) return 1;
  final rough = max / targetTicks;
  final mag = math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
  for (final m in const [1.0, 2.0, 2.5, 5.0, 10.0]) {
    final step = m * mag;
    if (step >= rough) return step < 1 ? 1 : step;
  }
  return 10 * mag;
}

String _fmt(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

class OpsBar {
  const OpsBar(this.label, this.value, this.color);
  final String label;
  final double value;
  final Color color;
}

class OpsBarChart extends StatelessWidget {
  const OpsBarChart({
    super.key,
    required this.bars,
    required this.unit,
    this.height = 200,
  });

  final List<OpsBar> bars;
  final String unit;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: bars.length > 4
          ? _HorizontalBars(bars: bars, unit: unit)
          : _VerticalBars(bars: bars, unit: unit),
    );
  }
}

class _VerticalBars extends StatelessWidget {
  const _VerticalBars({required this.bars, required this.unit});
  final List<OpsBar> bars;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final maxV = bars.fold<double>(0, (m, b) => math.max(m, b.value));
    final step = _niceStep(maxV, 6);
    final top = math.max(step, (maxV / step).ceil() * step);
    const tick = TextStyle(fontSize: 11, color: _tickColor);
    return LayoutBuilder(builder: (context, c) {
      final slot = (c.maxWidth - 40) / math.max(1, bars.length);
      final barW = (slot * 0.78 * 0.7).clamp(6.0, 400.0);
      return BarChart(
        BarChartData(
          maxY: top.toDouble(),
          minY: 0,
          alignment: BarChartAlignment.spaceAround,
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: step,
            getDrawingHorizontalLine: (_) =>
                const FlLine(color: _gridColor, strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 34,
                interval: step,
                getTitlesWidget: (v, meta) => SideTitleWidget(
                  meta: meta,
                  child: Text(_fmt(v), style: tick),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= bars.length) return const SizedBox();
                  return SideTitleWidget(
                    meta: meta,
                    child: SizedBox(
                      width: slot,
                      child: Text(
                        bars[i].label,
                        style: tick,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => _tooltipBg,
              tooltipPadding: const EdgeInsets.all(10),
              getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                '${bars[group.x].label}\n',
                const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
                children: [
                  TextSpan(
                    text: ' ${_fmt(rod.toY)} $unit',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w400),
                  ),
                ],
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < bars.length; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: bars[i].value,
                  color: bars[i].color,
                  width: barW,
                  borderRadius: BorderRadius.circular(6),
                ),
              ]),
          ],
        ),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutQuart,
      );
    });
  }
}

class _HorizontalBars extends StatelessWidget {
  const _HorizontalBars({required this.bars, required this.unit});
  final List<OpsBar> bars;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final maxV = bars.fold<double>(0, (m, b) => math.max(m, b.value));
    const tick = TextStyle(fontSize: 11, color: _tickColor);
    return LayoutBuilder(builder: (context, c) {
      final labelW = math.min(260.0, c.maxWidth * 0.42);
      final plotW = c.maxWidth - labelW - 16;
      final step = _niceStep(maxV, math.max(3, (plotW / 70).floor()));
      final top = math.max(step, (maxV / step).ceil() * step);
      final ticks = <double>[for (var v = 0.0; v <= top + 0.001; v += step) v];
      const axisH = 22.0;
      final rowH = (c.maxHeight - axisH) / bars.length;
      final barH = (rowH * 0.78 * 0.7).clamp(4.0, 40.0);
      return Stack(children: [
        Positioned(
          left: labelW + 8,
          top: 0,
          bottom: axisH,
          width: plotW,
          child: CustomPaint(
            painter: _VGridPainter(count: ticks.length),
          ),
        ),
        Positioned.fill(
          bottom: axisH,
          child: Column(children: [
            for (final b in bars)
              SizedBox(
                height: rowH,
                child: Row(children: [
                  SizedBox(
                    width: labelW,
                    child: Text(
                      b.label,
                      style: tick,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: plotW,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Tooltip(
                        message: '${b.label}\n ${_fmt(b.value)} $unit',
                        decoration: BoxDecoration(
                          color: _tooltipBg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        textStyle:
                            const TextStyle(color: Colors.white, fontSize: 12),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: 1),
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeOutQuart,
                          builder: (_, t, _) => Container(
                            width: math.max(
                                4, plotW * (b.value / top) * t),
                            height: barH,
                            decoration: BoxDecoration(
                              color: b.color,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
          ]),
        ),
        Positioned(
          left: labelW + 8,
          width: plotW,
          bottom: 0,
          height: axisH,
          child: Stack(clipBehavior: Clip.none, children: [
            for (var i = 0; i < ticks.length; i++)
              Positioned(
                left: plotW * (ticks[i] / top) - 20,
                width: 40,
                bottom: 2,
                child: Text(_fmt(ticks[i]),
                    style: tick, textAlign: TextAlign.center),
              ),
          ]),
        ),
      ]);
    });
  }
}

class _VGridPainter extends CustomPainter {
  _VGridPainter({required this.count});
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = _gridColor
      ..strokeWidth = 1;
    if (count < 2) return;
    for (var i = 0; i < count; i++) {
      final x = size.width * i / (count - 1);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
  }

  @override
  bool shouldRepaint(covariant _VGridPainter old) => old.count != count;
}

class OpsChartEmpty extends StatelessWidget {
  const OpsChartEmpty({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final dim = context.brand.paperDim;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 24, color: dim.withValues(alpha: 0.6)),
        const SizedBox(height: 8),
        Text(text, style: TextStyle(fontSize: 13.5, color: dim)),
      ]),
    );
  }
}
