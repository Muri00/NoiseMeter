import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/measurement_service.dart';

/// Една линия в графика: точки (x, ниво в dB) и цвят.
class ChartLine {
  const ChartLine(this.points, this.color, {this.dashed = false});

  final List<(double, double)> points;
  final Color color;
  final bool dashed;
}

/// Линейна графика на нива в dB. [xLabel] форматира стойностите по оста X.
class LevelLineChart extends StatelessWidget {
  const LevelLineChart({
    super.key,
    required this.lines,
    required this.xLabel,
    this.minX,
    this.maxX,
    this.xInterval,
  });

  final List<ChartLine> lines;
  final String Function(double) xLabel;
  final double? minX;
  final double? maxX;
  final double? xInterval;

  @override
  Widget build(BuildContext context) {
    final values = [for (final l in lines) for (final p in l.points) p.$2];
    final minY = values.isEmpty ? 30.0 : (values.reduce(math.min) / 10).floor() * 10.0 - 5;
    final maxY = values.isEmpty ? 100.0 : (values.reduce(math.max) / 10).ceil() * 10.0 + 5;

    return LineChart(
      duration: Duration.zero,
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem(
                  '${xLabel(s.x)}\n${s.y.toStringAsFixed(1)} dB',
                  TextStyle(color: s.bar.color, fontSize: 11),
                ),
            ],
          ),
        ),
        gridData: const FlGridData(drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            axisNameWidget: const Text('dB', style: TextStyle(fontSize: 11)),
            sideTitles: SideTitles(showTitles: true, reservedSize: 36, interval: 10, getTitlesWidget: dbAxisLabel),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: xInterval,
              getTitlesWidget: (v, meta) {
                // Крайните етикети често се застъпват със съседните - пропускаме ги.
                if (v == meta.min || v == meta.max) return const SizedBox.shrink();
                return SideTitleWidget(meta: meta, child: Text(xLabel(v), style: const TextStyle(fontSize: 10)));
              },
            ),
          ),
        ),
        lineBarsData: [
          for (final l in lines)
            LineChartBarData(
              spots: [for (final (x, y) in l.points) FlSpot(x, y)],
              color: l.color,
              barWidth: l.dashed ? 1 : 2,
              dashArray: l.dashed ? [4, 3] : null,
              // При малко точки (напр. кратки записи) линията почти не се вижда - показваме и точките.
              dotData: FlDotData(show: l.points.length <= 30),
            ),
        ],
      ),
    );
  }
}

Widget dbAxisLabel(double v, TitleMeta meta) =>
    SideTitleWidget(meta: meta, child: Text(v.toInt().toString(), style: const TextStyle(fontSize: 10)));

/// Графика на живо за последните [MeasurementService.historySeconds] секунди.
class LevelHistoryChart extends StatelessWidget {
  const LevelHistoryChart({super.key, required this.points});

  final List<(double, double)> points;

  @override
  Widget build(BuildContext context) {
    final maxX = points.isEmpty ? MeasurementService.historySeconds : points.last.$1;
    return LevelLineChart(
      lines: [ChartLine(points, Theme.of(context).colorScheme.primary)],
      minX: math.max(0, maxX - MeasurementService.historySeconds),
      maxX: math.max(maxX, 1),
      xInterval: 10,
      xLabel: (v) => '${v.toInt()} s',
    );
  }
}

/// Стълбовидна графика на нивата в октавните / терцоктавните ленти (изискване 3.8).
class BandChart extends StatelessWidget {
  const BandChart({super.key, required this.spectrum});

  final BandsData spectrum;

  static String _freqLabel(double f) {
    if (f >= 1000) {
      final k = f / 1000;
      return '${k == k.roundToDouble() ? k.toInt() : k}k';
    }
    return f == f.roundToDouble() ? f.toInt().toString() : f.toString();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.tertiary;
    final levels = spectrum.levels;
    final maxY = levels.isEmpty ? 100.0 : (levels.reduce(math.max) / 10).ceil() * 10.0 + 5;
    // При терцоктави етикетите се показват през две ленти, за да не се застъпват.
    final labelStep = spectrum.mode == '1/3' ? 3 : 1;

    return BarChart(
      duration: Duration.zero,
      BarChartData(
        minY: 0,
        maxY: math.max(maxY, 40),
        alignment: BarChartAlignment.spaceAround,
        gridData: const FlGridData(drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, _, rod, _) => BarTooltipItem(
              '${_freqLabel(spectrum.centers[group.x])} Hz\n${rod.toY.toStringAsFixed(1)} dB',
              const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 36, interval: 20, getTitlesWidget: dbAxisLabel),
          ),
          bottomTitles: AxisTitles(
            axisNameWidget: const Text('Hz', style: TextStyle(fontSize: 11)),
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i % labelStep != 0 || i >= spectrum.centers.length) return const SizedBox.shrink();
                return SideTitleWidget(meta: meta, child: Text(_freqLabel(spectrum.centers[i]), style: const TextStyle(fontSize: 9)));
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < levels.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: math.max(levels[i], 0),
                color: color,
                width: spectrum.mode == '1/3' ? 6 : 16,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
              ),
            ]),
        ],
      ),
    );
  }
}
