// ui/progress_screen.dart — the Progress / Graphs tab.
//
// Structured like Google Health's data screen: the tab is a list of CATEGORY
// CARDS (Strength / Performance / Recovery / Aesthetics / Sleep / Diet /
// Activity & Vitals / Body). Tapping a card opens that category's own graphing
// area (`CategoryGraphPage` → `_GraphArea`) with its metrics as selectable
// chips, a chart with rank/native/% y-axis labels, timeframe control, and a
// Pearson correlation readout when two are compared. Every metric is loggable
// from its page (manual entry, plus auto-sync from Google Health where available).
import 'package:flutter/material.dart';
import 'diet_screen.dart';
import 'sleep_screen.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math' as math;
import '../data/metrics.dart';
import '../engine/rank_engine.dart' as eng;
import '../engine/rank_engine.dart' show Log;
import '../state/providers.dart';
import 'badge.dart';
import 'home_screen.dart' show openLogSheet;

const List<String> _tierShort = [
  'Wood', 'Brz', 'Slv', 'Gld', 'Plt', 'Dia', 'Chp', 'Tit', 'Glr'
];
const List<String> _tierFull = [
  'Wood', 'Bronze', 'Silver', 'Gold', 'Platinum', 'Diamond', 'Champion', 'Titan', 'Glory'
];

const Color _bg = Color(0xFF08091A);
const Color _bg3 = Color(0xFF161830);
const Color _accent = Color(0xFF5B6AF8);
const Color _muted = Color(0xFF525878);
const Color _border = Color(0x12FFFFFF);

// Display config per category id, in the order they appear on the tab.
const List<(String, String, IconData, bool)> _sections = [
  ('strength', 'Strength', Icons.fitness_center, true),
  ('performance', 'Performance', Icons.bolt, true),
  ('recovery', 'Recovery', Icons.favorite, true),
  ('aesthetics', 'Aesthetics', Icons.face_retouching_natural, false),
  ('sleep', 'Sleep', Icons.bedtime, false),
  ('diet', 'Diet & Nutrition', Icons.restaurant, false),
  ('health', 'Activity & Vitals', Icons.monitor_heart, false),
  ('general', 'Body', Icons.straighten, false),
];

// ═══════════════════════════════════════════════════════════════════════════
// PROGRESS TAB — category cards
// ═══════════════════════════════════════════════════════════════════════════
class ProgressTab extends ConsumerWidget {
  const ProgressTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cats = ref.watch(categoryRanksProvider);
    final logsMap = ref.watch(logsProvider);

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 12),
                child: Text('GRAPHS',
                    style: TextStyle(fontSize: 11, letterSpacing: 2.5, color: _muted, fontWeight: FontWeight.w800)),
              ),
              for (final (id, title, icon, ranked) in _sections)
                _CategoryCard(
                  id: id, title: title, icon: icon, ranked: ranked,
                  rank: cats[id], logsMap: logsMap,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final String id, title;
  final IconData icon;
  final bool ranked;
  final eng.RankResult? rank;
  final Map<String, List<Log>> logsMap;
  const _CategoryCard({
    required this.id, required this.title, required this.icon,
    required this.ranked, required this.rank, required this.logsMap,
  });

  @override
  Widget build(BuildContext context) {
    final cands = [for (final m in metrics) if (m.category == id) m];
    final withData = cands.where((m) => (logsMap[m.id] ?? const []).isNotEmpty).length;
    final allAuto = cands.isNotEmpty && cands.every((m) => m.autoSync);
    final c = (ranked && rank != null) ? tierColor(rank!.tier) : _accent;

    String subtitle;
    if (ranked && rank != null) {
      subtitle = '${rank!.tier} ${rank!.sub} · top ${rank!.topPct.toStringAsFixed(1)}%';
    } else if (withData > 0) {
      subtitle = '$withData of ${cands.length} tracked';
    } else if (allAuto) {
      subtitle = 'Syncs from Google Health · tap to log';
    } else {
      subtitle = 'No data yet · tap to log';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          // Diet and Sleep get bespoke per-domain layouts (macros+trend / stages+
          // trend); other categories use the generic per-category graph page.
          onTap: () {
            if (id == 'diet') {
              openDietScreen(context);
            } else if (id == 'sleep') {
              openSleepScreen(context);
            } else {
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => CategoryGraphPage(categoryId: id, title: title)));
            }
          },
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _bg3,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: (ranked && rank != null) ? c.withValues(alpha: 0.3) : _border),
            ),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.12), shape: BoxShape.circle,
                  border: Border.all(color: c.withValues(alpha: 0.35)),
                ),
                child: Icon(icon, color: c, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              ),
              if (ranked && rank != null)
                RankBadge(tier: rank!.tier, sub: rank!.sub, size: 68),
              const Icon(Icons.chevron_right, color: _muted),
            ]),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CATEGORY GRAPH PAGE — one category's dedicated graphing area
// ═══════════════════════════════════════════════════════════════════════════
class CategoryGraphPage extends StatelessWidget {
  final String categoryId, title;
  const CategoryGraphPage({required this.categoryId, required this.title, super.key});

  @override
  Widget build(BuildContext context) {
    final cands = [for (final m in metrics) if (m.category == categoryId) m];
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: cands.isEmpty
                ? const Center(child: Text('No metrics in this category', style: TextStyle(color: _muted)))
                : _GraphArea(cands),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// GRAPH AREA — chips + chart + correlation, scoped to a set of metrics.
// ═══════════════════════════════════════════════════════════════════════════
class _GraphArea extends ConsumerStatefulWidget {
  final List<MetricDef> candidates;
  const _GraphArea(this.candidates);
  @override
  ConsumerState<_GraphArea> createState() => _GraphAreaState();
}

class _GraphAreaState extends ConsumerState<_GraphArea> {
  final Set<String> _selectedIds = {};
  String _timeframe = 'All';

  @override
  Widget build(BuildContext context) {
    final logsMap = ref.watch(logsProvider);
    if (_selectedIds.isEmpty) _selectedIds.add(widget.candidates.first.id);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      children: [
        _chips(),
        const SizedBox(height: 24),
        _multiChart(logsMap),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _chips() {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8, runSpacing: 8,
      children: [
        for (final m in widget.candidates)
          FilterChip(
            label: Text(m.label, style: const TextStyle(fontSize: 12)),
            selected: _selectedIds.contains(m.id),
            onSelected: (val) => setState(() {
              if (val) {
                _selectedIds.add(m.id);
              } else if (_selectedIds.length > 1) {
                _selectedIds.remove(m.id);
              }
            }),
            selectedColor: _accent.withValues(alpha: 0.2),
            backgroundColor: _bg3,
            side: BorderSide(color: _selectedIds.contains(m.id) ? _accent : _border),
          ),
      ],
    );
  }

  Widget _multiChart(Map<String, List<Log>> logsMap) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    int? timeSpanDays;
    switch (_timeframe) {
      case '1W': timeSpanDays = 7; break;
      case '1M': timeSpanDays = 30; break;
      case '3M': timeSpanDays = 90; break;
      case '6M': timeSpanDays = 180; break;
      case '1Y': timeSpanDays = 365; break;
    }

    final cutoff = timeSpanDays == null ? null : now.subtract(Duration(days: timeSpanDays));

    int globalFirstTs = todayStart;
    if (timeSpanDays != null) {
      globalFirstTs = todayStart - (timeSpanDays * 86400000);
    } else {
      bool found = false;
      for (final mid in _selectedIds) {
        final entries = logsMap[mid] ?? [];
        if (entries.isNotEmpty) {
          final dt = DateTime.parse(entries.first.ts);
          final dTs = DateTime(dt.year, dt.month, dt.day).millisecondsSinceEpoch;
          if (!found || dTs < globalFirstTs) {
            globalFirstTs = dTs;
            found = true;
          }
        }
      }
    }

    int globalLastTs = globalFirstTs;
    final lineBars = <LineChartBarData>[];
    final tooltipData = <double, Map<String, String>>{};
    // Day→value series per metric (rank-space if ranked, native unit otherwise),
    // retained for the correlation readout and single-metric axis labelling.
    final seriesByMetric = <String, Map<int, double>>{};
    double? singleMin, singleMax;
    bool singleRanked = false;

    final colors = [
      const Color(0xFF5B6AF8), const Color(0xFF4CE0C3), const Color(0xFFF85B88),
      const Color(0xFFF8C05B), const Color(0xFFA85BF8),
    ];
    int colorIdx = 0;

    bool hasAnyData = false;
    final m = metricById(_selectedIds.first); // header metric

    for (final metricId in _selectedIds) {
      final met = metricById(metricId);
      final isRanked = eng.standards.containsKey(metricId);
      final entries = logsMap[metricId] ?? [];

      final filtered = cutoff == null ? entries : entries.where((e) => DateTime.parse(e.ts).isAfter(cutoff)).toList();

      final dailyMax = <int, double>{};
      for (final e in filtered) {
        final dt = DateTime.parse(e.ts);
        final dayStart = DateTime(dt.year, dt.month, dt.day).millisecondsSinceEpoch;
        final val = isRanked ? eng.scoreLog(e).rankValue : e.value;
        if (!dailyMax.containsKey(dayStart) || val > dailyMax[dayStart]!) {
          dailyMax[dayStart] = val;
        }
      }

      if (dailyMax.isEmpty) continue;
      hasAnyData = true;

      double mMin = double.infinity, mMax = double.negativeInfinity;
      for (final val in dailyMax.values) {
        if (val < mMin) mMin = val;
        if (val > mMax) mMax = val;
      }

      if (isRanked) {
        mMin = 0; mMax = 8;
      } else {
        if (mMin == mMax) { mMin -= 10; mMax += 10; }
        else { final p = (mMax - mMin) * 0.1; mMin -= p; mMax += p; }
      }

      seriesByMetric[metricId] = Map.of(dailyMax);
      if (_selectedIds.length == 1) {
        singleMin = mMin; singleMax = mMax; singleRanked = isRanked;
      }

      final sortedDays = dailyMax.keys.toList()..sort();
      if (sortedDays.last > globalLastTs) globalLastTs = sortedDays.last;

      final spots = <FlSpot>[];
      for (final d in sortedDays) {
        final days = (d - globalFirstTs) / 86400000;
        final val = dailyMax[d]!;
        final normY = (val - mMin) / (mMax - mMin);
        spots.add(FlSpot(days.toDouble(), normY));

        final tooltipStr = isRanked
            ? '${met.label}: ${_tierShort[val.floor().clamp(0, 8)]} ${val.toStringAsFixed(1)}'
            : '${met.label}: ${val.toStringAsFixed(1)} ${met.unit}';
        tooltipData.putIfAbsent(days.toDouble(), () => {})[metricId] = tooltipStr;
      }

      Color lineCol;
      if (_selectedIds.length == 1 && isRanked) {
        lineCol = tierColor(_tierFull[math.min(8, mMax.floor())]);
      } else {
        lineCol = colors[colorIdx % colors.length];
        colorIdx++;
      }

      lineBars.add(LineChartBarData(
        spots: spots,
        isCurved: true,
        curveSmoothness: 0.35,
        color: lineCol,
        barWidth: 3,
        shadow: Shadow(color: lineCol.withValues(alpha: 0.5), blurRadius: 10),
        dotData: FlDotData(
          show: spots.length == 1,
          getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
            radius: 4, color: lineCol, strokeWidth: 2, strokeColor: _bg,
          ),
        ),
        belowBarData: BarAreaData(
          show: true,
          gradient: LinearGradient(
            colors: [lineCol.withValues(alpha: 0.3), lineCol.withValues(alpha: 0.0)],
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
          ),
        ),
      ));
    }

    final daySpan = timeSpanDays != null
        ? timeSpanDays.toDouble()
        : math.max(1, (globalLastTs - globalFirstTs) / 86400000).toDouble();

    // Header / subtitle
    String subtitle = '';
    Color subColor = _muted;
    if (_selectedIds.length == 1 && hasAnyData) {
      final isRanked = eng.standards.containsKey(m.id);
      final entries = logsMap[m.id]!;
      if (isRanked) {
        final res = eng.scoreLog(entries.last);
        subColor = tierColor(res.tier);
        subtitle = '${res.tier} ${res.sub} · top ${res.topPct.toStringAsFixed(1)}% · '
            'latest ${entries.last.value.toStringAsFixed(1)} ${m.unit}';
      } else {
        subColor = const Color(0xFF4CE0C3);
        subtitle = 'Latest: ${entries.last.value.toStringAsFixed(1)} ${m.unit}';
      }
    } else if (_selectedIds.length == 2) {
      final ids = _selectedIds.toList();
      final r = _pearson(seriesByMetric[ids[0]] ?? {}, seriesByMetric[ids[1]] ?? {});
      if (r != null) {
        subtitle = 'r = ${r.toStringAsFixed(2)} · ${_correlationLabel(r)}';
        subColor = r.abs() >= 0.4
            ? (r > 0 ? const Color(0xFF4CE0C3) : const Color(0xFFF85B88))
            : const Color(0xFF7880A8);
      } else {
        subtitle = 'Comparing 2 metrics · not enough overlapping days';
        subColor = _accent;
      }
    } else if (_selectedIds.length > 2) {
      subtitle = 'Comparing ${_selectedIds.length} metrics';
      subColor = _accent;
    }

    // Empty single-metric state — always offer manual logging (and note auto-sync).
    if (!hasAnyData && _selectedIds.length == 1 && (logsMap[m.id] ?? []).isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(m.label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(m.autoSync ? 'Syncs from Google Health' : 'No data logged yet',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 24),
          Container(
            height: 260,
            decoration: BoxDecoration(color: _bg3, borderRadius: BorderRadius.circular(16), border: Border.all(color: _border)),
            child: Center(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (m.autoSync) ...[
                  const Icon(Icons.sync, color: _muted, size: 40),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text('${m.label} syncs from Google Health / Fitbit. You can also log it manually.',
                        textAlign: TextAlign.center, style: const TextStyle(color: _muted)),
                  ),
                  const SizedBox(height: 16),
                ],
                ElevatedButton.icon(
                  onPressed: () => openLogSheet(context, initialMetricId: m.id),
                  icon: const Icon(Icons.add),
                  label: Text('Log ${m.label}'),
                  style: ElevatedButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.white),
                ),
              ]),
            ),
          ),
        ],
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Text(_selectedIds.length == 1 ? m.label : 'Comparison', textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
      const SizedBox(height: 4),
      Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: subColor, fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 16),
      Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: ['1W', '1M', '3M', '6M', '1Y', 'All'].map((t) {
              final sel = t == _timeframe;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(t, style: const TextStyle(fontSize: 10)),
                  selected: sel,
                  onSelected: (_) => setState(() => _timeframe = t),
                  selectedColor: _accent.withValues(alpha: 0.2),
                  backgroundColor: _bg3,
                  side: BorderSide(color: sel ? _accent : _border),
                  padding: EdgeInsets.zero,
                ),
              );
            }).toList(),
          ),
        ),
      ),
      const SizedBox(height: 24),
      if (!hasAnyData)
        Container(
          height: 260, alignment: Alignment.center,
          child: const Text('No data in this period', style: TextStyle(color: _muted)),
        )
      else
        SizedBox(
          height: 260,
          child: LineChart(LineChartData(
            minY: 0, maxY: 1.0, minX: 0, maxX: daySpan,
            lineBarsData: lineBars,
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => const Color(0xFF1E213E),
                getTooltipItems: (touchedSpots) {
                  if (touchedSpots.isEmpty) return [];
                  final xVal = touchedSpots.first.x;
                  final map = tooltipData[xVal] ?? {};
                  final dt = DateTime.fromMillisecondsSinceEpoch(globalFirstTs + (xVal * 86400000).toInt());
                  final dateStr = '${dt.day}/${dt.month}';
                  return touchedSpots.map((spot) {
                    final metricId = _selectedIds.elementAt(spot.barIndex);
                    final str = map[metricId] ?? '';
                    if (spot.barIndex == 0) {
                      return LineTooltipItem('$dateStr\n$str', const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), textAlign: TextAlign.center);
                    }
                    return LineTooltipItem('\n$str', TextStyle(color: spot.bar.color, fontWeight: FontWeight.w600), textAlign: TextAlign.center);
                  }).toList();
                },
              ),
            ),
            gridData: FlGridData(
              show: true,
              horizontalInterval: 0.25,
              getDrawingHorizontalLine: (_) => const FlLine(color: Color(0x0AFFFFFF), strokeWidth: 1),
              drawVerticalLine: false,
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 40,
                  interval: (_selectedIds.length == 1 && singleRanked) ? 0.125 : 0.25,
                  getTitlesWidget: (v, _) {
                    String text;
                    if (_selectedIds.length > 1) {
                      text = '${(v * 100).round()}%';
                    } else if (singleRanked) {
                      final rank = (v * 8).round();
                      if ((v * 8 - rank).abs() > 0.02 || rank < 0 || rank > 8) {
                        return const SizedBox.shrink();
                      }
                      text = _tierShort[rank];
                    } else {
                      final lo = singleMin ?? 0, hi = singleMax ?? 1;
                      text = (lo + v * (hi - lo)).toStringAsFixed(0);
                    }
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text(text, style: const TextStyle(color: _muted, fontSize: 9, fontWeight: FontWeight.w600)),
                    );
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 32,
                  // ~6 evenly-spaced date labels for ANY timeframe — incl. "All"
                  // (a null interval made fl_chart draw one label per day → cramped).
                  interval: math.max(1.0, daySpan / 6),
                  getTitlesWidget: (v, _) {
                    final dt = DateTime.fromMillisecondsSinceEpoch(globalFirstTs + (v * 86400000).toInt());
                    return Padding(
                      padding: const EdgeInsets.only(top: 12.0),
                      child: Text('${dt.day}/${dt.month}', style: const TextStyle(color: _muted, fontSize: 10, fontWeight: FontWeight.w600)),
                    );
                  },
                ),
              ),
            ),
          )),
        ),
    ]);
  }
}

/// Pearson correlation over the days both metrics share. Null if fewer than 3
/// overlapping points (nearest-date alignment is by calendar day).
double? _pearson(Map<int, double> a, Map<int, double> b) {
  final days = a.keys.where(b.containsKey).toList();
  if (days.length < 3) return null;
  final xs = [for (final d in days) a[d]!];
  final ys = [for (final d in days) b[d]!];
  final n = xs.length;
  final mx = xs.reduce((p, q) => p + q) / n;
  final my = ys.reduce((p, q) => p + q) / n;
  double sxy = 0, sxx = 0, syy = 0;
  for (var i = 0; i < n; i++) {
    final dx = xs[i] - mx, dy = ys[i] - my;
    sxy += dx * dy; sxx += dx * dx; syy += dy * dy;
  }
  if (sxx == 0 || syy == 0) return null;
  return (sxy / math.sqrt(sxx * syy)).clamp(-1.0, 1.0);
}

String _correlationLabel(double r) {
  final a = r.abs();
  final strength = a >= 0.7 ? 'strong' : a >= 0.4 ? 'moderate' : a >= 0.2 ? 'weak' : 'negligible';
  final dir = a < 0.2 ? 'correlation' : (r > 0 ? 'positive correlation' : 'negative correlation');
  return '$strength $dir';
}
