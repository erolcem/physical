// ui/diet_screen.dart — a holistic diet page (PDF Part 1/Part 2 per-domain layout):
// today's energy + a macro breakdown bar (protein/carbs/fat by kcal) + fibre, a
// 7-day calorie trend, and the day's food entries. Feeds the coach.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../data/diet.dart';
import '../data/habits.dart' show todayKey, lastNDays;
import '../data/metrics.dart' show MetricDef, MetricTier;
import '../data/sync.dart' show apiClientProvider;
import '../data/workout.dart' show activeCaloriesOn;
import '../engine/rank_engine.dart' show Log;
import '../state/log_providers.dart';
import '../state/providers.dart' show latestLogsProvider, logsProvider;
import 'progress_screen.dart' show GraphArea;

const _bg = Color(0xFF08091A);
const _card = Color(0xFF12152E);
const _gold = Color(0xFFF6CF3E);
const _teal = Color(0xFF4CE0C3);
const _accent = Color(0xFF5B6AF8);
const _pink = Color(0xFFF85B88);
const _muted = Color(0xFF7880A8);

void openDietScreen(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DietScreen()));
}

class DietScreen extends ConsumerWidget {
  const DietScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(dietProvider);
    final today = entriesFor(entries, todayKey());
    final t = todayDiet(entries);
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(backgroundColor: _bg, title: const Text('Diet')),
      // No manual "Log food" — food is auto-imported from Google Health (nutrition-log).
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
        const _DietHealthEnricher(),
        _totals(t),
        const SizedBox(height: 12),
        _energyBalance(ref, t),
        const SizedBox(height: 12),
        _healthRadar(t),
        const SizedBox(height: 12),
        const _EnergyTrend(),
        const SizedBox(height: 16),
        Text('TODAY · ${today.length}', style: const TextStyle(fontSize: 10, letterSpacing: 2, color: _muted)),
        const SizedBox(height: 6),
        if (today.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('No food logged today.', style: TextStyle(color: _muted))))
        // Short lists inline; long ones scroll inside a fixed window (page stays bounded).
        else if (today.length <= 10)
          for (final e in today.reversed) _entryRow(ref, e)
        else
          SizedBox(
            height: 320,
            child: ListView(
              padding: EdgeInsets.zero,
              children: [for (final e in today.reversed) _entryRow(ref, e)],
            ),
          ),
        const SizedBox(height: 16),
        const _DietMetricGraph(),
      ]),
    );
  }

  Widget _totals(DietTotals t) {
    final macroKcal = t.proteinKcal + t.carbsKcal + t.fatKcal;
    return Card(
      color: _card,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text("TODAY'S TOTAL", style: TextStyle(fontSize: 10, letterSpacing: 2, color: _muted)),
          const SizedBox(height: 8),
          Text('${t.calories.round()} kcal',
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: _gold)),
          const SizedBox(height: 12),
          // Macro split of energy (protein/carbs/fat by kcal).
          if (macroKcal > 0)
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: Row(children: [
                Expanded(flex: (t.proteinKcal * 100).round().clamp(0, 1 << 30),
                    child: Container(height: 10, color: _teal)),
                Expanded(flex: (t.carbsKcal * 100).round().clamp(0, 1 << 30),
                    child: Container(height: 10, color: _accent)),
                Expanded(flex: (t.fatKcal * 100).round().clamp(0, 1 << 30),
                    child: Container(height: 10, color: _pink)),
              ]),
            ),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _macro('Protein', t.protein, _teal),
            _macro('Carbs', t.carbs, _accent),
            _macro('Fat', t.fat, _pink),
            _macro('Fibre', t.fibre, _gold),
          ]),
          if (t.micros.values.any((v) => v > 0)) ...[
            const SizedBox(height: 16),
            const Text('MICRONUTRIENTS', style: TextStyle(fontSize: 10, letterSpacing: 2, color: _muted)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final k in microLabels.keys)
                if ((t.micros[k] ?? 0) > 0) _microChip(k, t.micros[k]!),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _microChip(String key, double v) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _accent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _accent.withValues(alpha: 0.3)),
        ),
        child: Text('${microLabels[key]} ${v.round()}${microUnit(key)}',
            style: const TextStyle(fontSize: 11, color: _accent, fontWeight: FontWeight.w600)),
      );

  Widget _macro(String label, double g, Color c) => Column(children: [
        Text('${g.round()}g', style: TextStyle(fontWeight: FontWeight.w800, color: c)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 10, color: _muted)),
      ]);

  // Energy balance: calories in (food) vs out (estimated BMR + active from Google
  // exercise sessions) + current weight. Out is ESTIMATED (watch-derived) — relative.
  Widget _energyBalance(WidgetRef ref, DietTotals t) {
    final latest = ref.watch(latestLogsProvider);
    final sessions = ref.watch(workoutProvider);
    final w = latest['bodyweight']?.value;
    final h = latest['height']?.value;
    final age = latest['age']?.value;
    final hasBody = w != null && h != null && age != null;
    final out = hasBody
        ? bmrMifflin(w, h, age.round()) + activeCaloriesOn(sessions, todayKey())
        : null;
    final net = out == null ? null : t.calories - out;
    return Card(
      color: _card,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('ENERGY BALANCE', style: TextStyle(fontSize: 10, letterSpacing: 2, color: _muted)),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _energyStat('In', '${t.calories.round()}', 'kcal', _gold),
            _energyStat('Out (est)', out == null ? '—' : '${out.round()}', 'kcal', _teal),
            _energyStat(net == null ? 'Net' : (net >= 0 ? 'Surplus' : 'Deficit'),
                net == null ? '—' : '${net.abs().round()}', 'kcal',
                net == null ? _muted : (net >= 0 ? _pink : _teal)),
            _energyStat('Weight', w == null ? '—' : w.toStringAsFixed(1), 'kg', _accent),
          ]),
          if (!hasBody) ...[
            const SizedBox(height: 10),
            const Text('Sync weight/height/age (☁) for the burn estimate.',
                style: TextStyle(fontSize: 11, color: _muted)),
          ] else ...[
            const SizedBox(height: 10),
            Text('Out = BMR ${bmrMifflin(w, h, age.round()).round()} + active '
                '${activeCaloriesOn(sessions, todayKey()).round()} kcal · estimated',
                style: const TextStyle(fontSize: 10.5, color: _muted)),
          ],
        ]),
      ),
    );
  }

  Widget _energyStat(String label, String value, String unit, Color c) =>
      Column(children: [
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: c)),
        Text(unit, style: const TextStyle(fontSize: 9, color: _muted)),
        const SizedBox(height: 3),
        Text(label, style: const TextStyle(fontSize: 10.5, color: _muted, fontWeight: FontWeight.w600)),
      ]);

  // Diet-health radar: the day's accumulated points per axis + an averaged /100 score.
  Widget _healthRadar(DietTotals t) {
    final axes = healthAxisLabels.keys.toList();
    final score = t.healthScore;
    final c = score >= 67 ? _teal : (score >= 34 ? _gold : _pink);
    final hasAny = axes.any((k) => (t.health[k] ?? 0) > 0);
    return Card(
      color: _card,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('DIET HEALTH',
                style: TextStyle(fontSize: 10, letterSpacing: 2, color: _muted))),
            Text('${score.round()}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: c)),
            const Padding(padding: EdgeInsets.only(left: 2, bottom: 3),
                child: Text('/100', style: TextStyle(fontSize: 11, color: _muted))),
          ]),
          const SizedBox(height: 8),
          // Always render the web (the 100-ring draws the hexagon even with no data).
          SizedBox(
            height: 240,
            child: RadarChart(RadarChartData(
              radarShape: RadarShape.polygon,
              tickCount: 4,
              ticksTextStyle: const TextStyle(color: Colors.transparent, fontSize: 0),
              radarBorderData: const BorderSide(color: Color(0x22FFFFFF)),
              gridBorderData: const BorderSide(color: Color(0x18FFFFFF)),
              tickBorderData: const BorderSide(color: Color(0x18FFFFFF)),
              titleTextStyle: const TextStyle(color: _muted, fontSize: 10, fontWeight: FontWeight.w600),
              getTitle: (i, _) => RadarChartTitle(text: healthAxisLabels[axes[i]] ?? axes[i]),
              dataSets: [
                // Faint 0–100 reference ring so the shape reads on an absolute scale.
                RadarDataSet(
                  fillColor: Colors.transparent,
                  borderColor: const Color(0x14FFFFFF),
                  borderWidth: 1,
                  entryRadius: 0,
                  dataEntries: [for (final _ in axes) const RadarEntry(value: 100)],
                ),
                RadarDataSet(
                  fillColor: c.withValues(alpha: 0.22),
                  borderColor: c,
                  borderWidth: 2,
                  entryRadius: 2,
                  // 0.01 floor so the shape is a visible speck (not collapsed) when empty.
                  dataEntries: [for (final k in axes) RadarEntry(value: (t.health[k] ?? 0).clamp(0.01, 100))],
                ),
              ],
            )),
          ),
          if (!hasAny)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Center(child: Text('Log food with AI auto-fill to fill the radar.',
                  style: TextStyle(color: _muted, fontSize: 11))),
            ),
        ]),
      ),
    );
  }

  Widget _entryRow(WidgetRef ref, FoodEntry e) => Card(
        color: _card,
        child: ListTile(
          title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
              '${e.calories.round()} kcal · ${e.protein.round()}P / ${e.carbs.round()}C / ${e.fat.round()}F'
              '${e.fibre > 0 ? ' / ${e.fibre.round()}fib' : ''}',
              style: const TextStyle(fontSize: 12, color: _muted)),
          trailing: IconButton(
            icon: const Icon(Icons.close, size: 18, color: _muted),
            onPressed: () => ref.read(dietProvider.notifier).remove(e.id),
          ),
        ),
      );

}

// Energy trend: calories IN (food) vs OUT (BMR + active) and weight, over a timeframe.
class _EnergyTrend extends ConsumerStatefulWidget {
  const _EnergyTrend();
  @override
  ConsumerState<_EnergyTrend> createState() => _EnergyTrendState();
}

class _EnergyTrendState extends ConsumerState<_EnergyTrend> {
  int _days = 30;
  static const _frames = [(7, '1W'), (30, '1M'), (90, '3M'), (180, '6M')];

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(dietProvider);
    final sessions = ref.watch(workoutProvider);
    final logs = ref.watch(logsProvider);
    final latest = ref.watch(latestLogsProvider);
    final days = lastNDays(_days); // oldest → newest
    final w = latest['bodyweight']?.value;
    final h = latest['height']?.value;
    final age = latest['age']?.value;
    final bmr = (w != null && h != null && age != null) ? bmrMifflin(w, h, age.round()) : null;

    final inSeries = [for (final d in days) dietTotals(entries, d).calories];
    final outSeries = bmr == null
        ? const <double>[]
        : [for (final d in days) bmr + activeCaloriesOn(sessions, d)];

    // Weight carried forward from the latest bodyweight log on/before each day.
    final wlogs = [...(logs['bodyweight'] ?? const <Log>[])]
      ..sort((a, b) => a.ts.compareTo(b.ts));
    final weightSeries = <double?>[];
    for (final d in days) {
      double? v;
      for (final l in wlogs) {
        if (l.ts.length >= 10 && l.ts.substring(0, 10).compareTo(d) <= 0) v = l.value;
      }
      weightSeries.add(v);
    }
    final wPts = [for (var i = 0; i < days.length; i++)
        if (weightSeries[i] != null) FlSpot(i.toDouble(), weightSeries[i]!)];

    double maxKcal = 100;
    for (final v in [...inSeries, ...outSeries]) {
      if (v > maxKcal) maxKcal = v;
    }
    final firstW = weightSeries.firstWhere((v) => v != null, orElse: () => null);
    final lastW = weightSeries.lastWhere((v) => v != null, orElse: () => null);
    final dW = (firstW != null && lastW != null) ? lastW - firstW : null;

    return Card(
      color: _card,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('ENERGY TREND',
                style: TextStyle(fontSize: 10, letterSpacing: 2, color: _muted))),
            for (final (d, label) in _frames)
              GestureDetector(
                onTap: () => setState(() => _days = d),
                child: Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: _days == d ? FontWeight.w800 : FontWeight.w500,
                          color: _days == d ? _teal : _muted)),
                ),
              ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _legend('In', _gold), const SizedBox(width: 14), _legend('Out (est)', _teal),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            height: 130,
            child: LineChart(LineChartData(
              minY: 0, maxY: maxKcal * 1.15,
              titlesData: const FlTitlesData(show: false),
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              lineTouchData: const LineTouchData(enabled: false),
              lineBarsData: [
                LineChartBarData(
                  spots: [for (var i = 0; i < inSeries.length; i++) FlSpot(i.toDouble(), inSeries[i])],
                  isCurved: true, color: _gold, barWidth: 2, dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(show: true, color: _gold.withValues(alpha: 0.12)),
                ),
                if (outSeries.isNotEmpty)
                  LineChartBarData(
                    spots: [for (var i = 0; i < outSeries.length; i++) FlSpot(i.toDouble(), outSeries[i])],
                    isCurved: true, color: _teal, barWidth: 2, dotData: const FlDotData(show: false),
                  ),
              ],
            )),
          ),
          if (wPts.length >= 2) ...[
            const SizedBox(height: 14),
            Row(children: [
              const Expanded(child: Text('WEIGHT',
                  style: TextStyle(fontSize: 9, letterSpacing: 2, color: _muted))),
              if (dW != null)
                Text('${dW >= 0 ? '+' : ''}${dW.toStringAsFixed(1)} kg',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                        color: dW > 0 ? _pink : _teal)),
            ]),
            const SizedBox(height: 6),
            SizedBox(
              height: 70,
              child: LineChart(LineChartData(
                titlesData: const FlTitlesData(show: false),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                lineTouchData: const LineTouchData(enabled: false),
                lineBarsData: [
                  LineChartBarData(spots: wPts, isCurved: true, color: _accent,
                      barWidth: 2, dotData: const FlDotData(show: false)),
                ],
              )),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _legend(String label, Color c) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 9, height: 9,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 11, color: _muted)),
      ]);
}

// Extended diet graph: any diet quantity (weight, macros + health axes) over time —
// driven by the shared GraphArea so it matches every other section (timeframes incl. All,
// overlay, axes, tooltips). Series are derived from the food log + bodyweight logs.
const List<MetricDef> _dietCandidates = [
  // Calories first so the graph defaults to a series that's present whenever you've eaten;
  // Weight is right after it for the weight-vs-diet comparison.
  MetricDef('d_calories', 'Calories', 'diet', MetricTier.background, 'kcal'),
  MetricDef('d_weight', 'Weight', 'diet', MetricTier.background, 'kg'),
  MetricDef('d_protein', 'Protein', 'diet', MetricTier.background, 'g'),
  MetricDef('d_carbs', 'Carbs', 'diet', MetricTier.background, 'g'),
  MetricDef('d_fat', 'Fat', 'diet', MetricTier.background, 'g'),
  MetricDef('d_fibre', 'Fibre', 'diet', MetricTier.background, 'g'),
  MetricDef('d_health', 'Health score', 'diet', MetricTier.background, '/100'),
  MetricDef('d_micronutrients', 'Micronutrients', 'diet', MetricTier.background, '/100'),
  MetricDef('d_gut_health', 'Gut Health', 'diet', MetricTier.background, '/100'),
  MetricDef('d_antioxidants', 'Antioxidants', 'diet', MetricTier.background, '/100'),
  MetricDef('d_healthy_fats', 'Healthy Fats', 'diet', MetricTier.background, '/100'),
  MetricDef('d_whole_food', 'Whole-food', 'diet', MetricTier.background, '/100'),
];

Map<String, List<Log>> _buildDietSeries(List<FoodEntry> entries, List<Log> weightLogs) {
  final out = {for (final m in _dietCandidates) m.id: <Log>[]};
  final days = entries.map((e) => e.dateKey).toSet().toList()..sort();
  for (final day in days) {
    final t = dietTotals(entries, day);
    if (t.items == 0) continue;
    final ts = '${day}T12:00:00';
    out['d_calories']!.add(Log('d_calories', t.calories, ts: ts));
    out['d_protein']!.add(Log('d_protein', t.protein, ts: ts));
    out['d_carbs']!.add(Log('d_carbs', t.carbs, ts: ts));
    out['d_fat']!.add(Log('d_fat', t.fat, ts: ts));
    out['d_fibre']!.add(Log('d_fibre', t.fibre, ts: ts));
    out['d_health']!.add(Log('d_health', t.healthScore, ts: ts));
    for (final k in ['micronutrients', 'gut_health', 'antioxidants', 'healthy_fats', 'whole_food']) {
      out['d_$k']!.add(Log('d_$k', t.health[k] ?? 0, ts: ts));
    }
  }
  out['d_weight'] = [for (final l in weightLogs) Log('d_weight', l.value, ts: l.ts)];
  return out;
}

class _DietMetricGraph extends ConsumerWidget {
  const _DietMetricGraph();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = _buildDietSeries(ref.watch(dietProvider), ref.watch(logsProvider)['bodyweight'] ?? const []);
    return Card(
      color: _card,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: GraphArea(_dietCandidates, logsOverride: logs),
      ),
    );
  }
}

// Diet-health enricher: on open, AI-fills the health radar for any foods that lack it
// (mainly Google-imported). Visible status + a manual retry so it's never a silent no-op.
class _DietHealthEnricher extends ConsumerStatefulWidget {
  const _DietHealthEnricher();
  @override
  ConsumerState<_DietHealthEnricher> createState() => _DietHealthEnricherState();
}

class _DietHealthEnricherState extends ConsumerState<_DietHealthEnricher> {
  bool _busy = false;
  String? _error;

  int get _pending =>
      ref.read(dietProvider).where((f) => f.health.isEmpty && f.calories > 0).length;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pending > 0) _run();
    });
  }

  Future<void> _run() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      await ref.read(dietProvider.notifier).enrichFoodHealth(ref.read(apiClientProvider));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(dietProvider).where((f) => f.health.isEmpty && f.calories > 0).length;
    if (!_busy && _error == null && pending == 0) return const SizedBox.shrink();
    final (icon, text, color) = _busy
        ? (null, 'Analysing $pending food${pending == 1 ? '' : 's'} for the health web…', _teal)
        : _error != null
            ? (Icons.error_outline, 'Health analysis failed — tap to retry', _pink)
            : (Icons.auto_awesome, 'Analyse $pending food${pending == 1 ? '' : 's'} for the health web', _gold);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _busy ? null : _run,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Row(children: [
              if (_busy)
                const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _teal))
              else
                Icon(icon, size: 18, color: color),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: TextStyle(fontSize: 12.5, color: color, fontWeight: FontWeight.w600))),
            ]),
          ),
        ),
      ),
    );
  }
}
