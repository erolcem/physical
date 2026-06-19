// ui/progress_screen.dart — rank history over your logged sessions. Pushed from
// the app-bar chart icon. X = session order (logs are appended chronologically),
// Y = rank value (0 Wood … 8 Glory). Makes persisted history motivational.
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/metrics.dart';
import '../engine/rank_engine.dart' as eng;
import '../engine/rank_engine.dart' show Log;
import '../state/providers.dart';

const List<String> _tierShort = [
  'Wood', 'Brz', 'Slv', 'Gld', 'Plt', 'Dia', 'Chp', 'Tit', 'Glr'
];

class ProgressScreen extends ConsumerStatefulWidget {
  const ProgressScreen({super.key});
  @override
  ConsumerState<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends ConsumerState<ProgressScreen> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(logsProvider);
    final withData = rankedMetrics
        .where((m) => (logs[m.id]?.isNotEmpty ?? false))
        .toList();

    final selId = (_selected != null && withData.any((m) => m.id == _selected))
        ? _selected!
        : (withData.isNotEmpty ? withData.first.id : null);

    return Scaffold(
      appBar: AppBar(title: const Text('Progress')),
      body: withData.isEmpty
          ? const Center(child: Text('Log something to see your progress.',
              style: TextStyle(color: Colors.grey)))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    for (final m in withData)
                      ChoiceChip(
                        label: Text(m.label),
                        selected: m.id == selId,
                        onSelected: (_) => setState(() => _selected = m.id),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                if (selId != null) _chartFor(selId, logs[selId]!),
              ],
            ),
    );
  }

  Widget _chartFor(String metricId, List<Log> entries) {
    final m = metricById(metricId);
    final latest = eng.scoreLog(entries.last);
    final c = tierColor(latest.tier);
    final spots = <FlSpot>[
      for (var i = 0; i < entries.length; i++)
        FlSpot(i.toDouble(), eng.scoreLog(entries[i]).rankValue),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(m.label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      Text('${latest.tier} ${latest.sub} · top ${latest.topPct.toStringAsFixed(1)}% · '
          'latest ${entries.last.value.toStringAsFixed(1)} ${m.unit}',
          style: TextStyle(color: c, fontSize: 13)),
      const SizedBox(height: 16),
      SizedBox(
        height: 260,
        child: LineChart(LineChartData(
          minY: 0,
          maxY: 8,
          minX: 0,
          maxX: (entries.length - 1).toDouble().clamp(1, double.infinity),
          gridData: FlGridData(
            show: true,
            horizontalInterval: 1,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: Colors.white.withOpacity(0.05), strokeWidth: 1),
            drawVerticalLine: false,
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                getTitlesWidget: (v, _) => Text('${v.toInt() + 1}',
                    style: const TextStyle(color: Colors.grey, fontSize: 9)),
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                reservedSize: 34,
                getTitlesWidget: (v, _) {
                  final i = v.round();
                  if (i < 0 || i >= _tierShort.length) return const SizedBox();
                  return Text(_tierShort[i],
                      style: const TextStyle(color: Colors.grey, fontSize: 9));
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              preventCurveOverShooting: true,
              color: c,
              barWidth: 3,
              dotData: FlDotData(
                show: true,
                getDotPainter: (s, _, __, ___) => FlDotCirclePainter(
                    radius: 3, color: c, strokeWidth: 0),
              ),
              belowBarData: BarAreaData(show: true, color: c.withOpacity(0.12)),
            ),
          ],
        )),
      ),
      const SizedBox(height: 8),
      const Text('Each point is a logged session.',
          style: TextStyle(fontSize: 11, color: Colors.grey)),
    ]);
  }
}
