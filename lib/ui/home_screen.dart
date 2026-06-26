// ui/home_screen.dart — overall rank, aesthetics strip, the front/inner/back
// body graph, strength metrics grid, performance & recovery grid, and log sheet.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/metrics.dart';
import '../data/body_figure_data.dart';
import '../data/correlation.dart';
import '../engine/rank_engine.dart' as eng;
import '../engine/rank_engine.dart' show Log, RankResult, strengthValue, isolationLifts;
import '../state/log_providers.dart';
import '../state/providers.dart';
import 'badge.dart';
import 'body_graph.dart';
import 'metric_detail_sheet.dart';
import 'dart:math' as math;

// ── Design tokens ──────────────────────────────────────────────────────────
const _bg2 = Color(0xFF0F1128);
const _bg3 = Color(0xFF161830);
const _surface = Color(0x0AFFFFFF); // white @ 4%
const _border = Color(0x12FFFFFF); // white @ 7%
const _border2 = Color(0x21FFFFFF); // white @ 13%
const _muted = Color(0xFF525878);
const _muted2 = Color(0xFF7880A8);

TextStyle _secTitle() => const TextStyle(
    fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 2.5,
    color: _muted);

class HomeTab extends ConsumerWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overall = ref.watch(overallProvider);
    final latest = ref.watch(latestLogsProvider);
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          children: [
            // 1. Overall rank card
            _OverallCard(overall, latest),
            const SizedBox(height: 14),

            // 2. Coach-pinned correlations (PDF Part 5 "strategic correlations")
            const _PinnedInsights(),

            // 3. Body graph section (gradient container)
            _BodyGraphSection(context),
            const SizedBox(height: 16),

            // Ranked metric grids — one section per category (PDF Table 1).
            for (final (cat, title) in const [
              ('strength', 'STRENGTH'),
              ('performance', 'PERFORMANCE'),
              ('recovery', 'RECOVERY'),
            ]) ...[
              _SectionTitle(title),
              const SizedBox(height: 8),
              _MetricGrid(
                metricIds: [
                  for (final m in rankedMetrics)
                    if (m.category == cat) m.id
                ],
                latest: latest,
                onTap: (mid) => openDetailSheet(context, mid),
              ),
              const SizedBox(height: 16),
            ],

            // Aesthetics (tracked, not ranked).
            const _SectionTitle('AESTHETICS'),
            const SizedBox(height: 8),
            _MetricGrid(
              metricIds: [
                for (final m in metrics)
                  if (m.category == 'aesthetics') m.id
              ],
              latest: latest,
              onTap: (mid) => openDetailSheet(context, mid),
            ),
            const SizedBox(height: 80), // room for FAB
          ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PINNED INSIGHTS — correlations the coach pinned to the dashboard (PDF Part 5)
// ═══════════════════════════════════════════════════════════════════════════
class _PinnedInsights extends ConsumerWidget {
  const _PinnedInsights();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pins = ref.watch(pinsProvider);
    if (pins.isEmpty) return const SizedBox.shrink();
    final logs = ref.watch(logsProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _SectionTitle('COACH INSIGHTS'),
      const SizedBox(height: 8),
      for (final p in pins) _pinCard(ref, p, logs),
      const SizedBox(height: 16),
    ]);
  }

  String _label(String id) {
    try {
      return metricById(id).label;
    } catch (_) {
      return id;
    }
  }

  Widget _pinCard(WidgetRef ref, PinnedCorrelation p, Map<String, List<Log>> logs) {
    final r = correlationOf(logs[p.a] ?? const [], logs[p.b] ?? const []);
    final c = r == null
        ? _muted
        : (r >= 0 ? const Color(0xFF4CE0C3) : const Color(0xFFFA3737));
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _bg3,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${_label(p.a)}  ↔  ${_label(p.b)}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 2),
            Text(
                r == null
                    ? 'Not enough overlapping data yet'
                    : 'r = ${r.toStringAsFixed(2)} · ${correlationLabel(r)}',
                style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600)),
          ]),
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 16, color: _muted),
          onPressed: () => ref.read(pinsProvider.notifier).remove(p.key),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION TITLE
// ═══════════════════════════════════════════════════════════════════════════
class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Container(
          padding: const EdgeInsets.only(bottom: 6),
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _border, width: 1))),
          child: Text(text, style: _secTitle()),
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// OVERALL CARD — with progress bar + sub-rank ticks + weakest metric
// ═══════════════════════════════════════════════════════════════════════════
class _OverallCard extends StatelessWidget {
  final RankResult r;
  final Map<String, Log> latest;
  const _OverallCard(this.r, this.latest);

  @override
  Widget build(BuildContext context) {
    final c = tierColor(r.tier);
    final frac = r.rankValue - r.rankValue.floor();


    return GestureDetector(
      onTap: () => openOverallBreakdown(context),
      child: Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [c.withValues(alpha: 0.12), _bg2],
        ),
        border: Border.all(color: c.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 32, offset: const Offset(0, 8)),
          BoxShadow(color: c.withValues(alpha: 0.08), blurRadius: 24, spreadRadius: -4),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
        RankBadge(tier: r.tier, sub: r.sub, size: 100, animated: true),
        const SizedBox(height: 16),
        const Text('OVERALL RANK',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, letterSpacing: 2.5, color: _muted, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('${r.tier} ${r.sub}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: c, height: 1)),
        const SizedBox(height: 6),
        Text('Top ${r.topPct.toStringAsFixed(1)}% of young men',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c)),
        const SizedBox(height: 14),
        // Progress bar with sub-rank ticks
        SizedBox(
          height: 10,
          child: LayoutBuilder(builder: (context, constraints) {
            final barWidth = constraints.maxWidth;
            return Stack(children: [
              // Track
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              // Fill
              FractionallySizedBox(
                widthFactor: frac.clamp(0, 1),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [c.withValues(alpha: 0.8), c]),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              // Sub-rank tick marks at 33% and 66% of the actual bar width
              for (final pct in [0.333, 0.666])
                Positioned(
                  left: pct * barWidth,
                  top: 0, bottom: 0,
                  child: Container(width: 2, color: Colors.white.withValues(alpha: 0.4)),
                ),
            ]);
          }),
        ),
        const SizedBox(height: 6),
        Text('Avg ${r.rankValue.toStringAsFixed(2)}/8',
            style: const TextStyle(fontSize: 10, color: _muted2)),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('TAP FOR CATEGORY BREAKDOWN',
              style: TextStyle(fontSize: 9, letterSpacing: 1.5, color: c.withValues(alpha: 0.8), fontWeight: FontWeight.w700)),
          Icon(Icons.chevron_right, size: 14, color: c.withValues(alpha: 0.8)),
        ]),
      ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CATEGORY BREAKDOWN SHEET — opened by tapping the overall card. Shows the
// overall rank plus Strength / Performance / Recovery sub-ranks with bars.
// ═══════════════════════════════════════════════════════════════════════════
const List<(String, String, IconData)> _rankedCategories = [
  ('strength', 'Strength', Icons.fitness_center),
  ('performance', 'Performance', Icons.bolt),
  ('recovery', 'Recovery', Icons.favorite),
];

const List<String> _tierOrder = [
  'Wood', 'Bronze', 'Silver', 'Gold', 'Platinum', 'Diamond', 'Champion', 'Titan', 'Glory'
];

void openOverallBreakdown(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: _bg2,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => const _OverallBreakdownSheet(),
  );
}

class _OverallBreakdownSheet extends ConsumerWidget {
  const _OverallBreakdownSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overall = ref.watch(overallProvider);
    final cats = ref.watch(categoryRanksProvider);
    final latest = ref.watch(latestLogsProvider);
    final c = tierColor(overall.tier);
    final totalLogs =
        ref.watch(logsProvider).values.fold<int>(0, (a, b) => a + b.length);
    final metricsActive =
        latest.keys.where((id) => eng.standards.containsKey(id)).length;
    // Figure 3 "RANK BADGES" — how many ranked metrics sit at each tier.
    final dist = <String, int>{};
    for (final e in latest.entries) {
      if (!eng.standards.containsKey(e.key)) continue;
      try {
        final t = eng.scoreLog(e.value).tier;
        dist[t] = (dist[t] ?? 0) + 1;
      } catch (_) {/* strength log missing its bodyweight snapshot — skip */}
    }

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: Container(width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: _border2, borderRadius: BorderRadius.circular(2)))),
            Center(child: RankBadge(tier: overall.tier, sub: overall.sub, size: 92, animated: true)),
            const SizedBox(height: 10),
            Center(child: Text('${overall.tier} ${overall.sub}',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: c, height: 1))),
            const SizedBox(height: 4),
            Center(child: Text('Top ${overall.topPct.toStringAsFixed(1)}% of young men',
                style: TextStyle(color: c, fontWeight: FontWeight.w600))),
            const SizedBox(height: 18),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _stat('$totalLogs', 'TOTAL LOGS'),
              _stat('$metricsActive', 'METRICS RANKED'),
              _stat(overall.rankValue.toStringAsFixed(2), 'AVG / 8'),
            ]),
            const SizedBox(height: 22),
            Text('CATEGORY RANKINGS', style: _secTitle()),
            const SizedBox(height: 10),
            for (final (id, name, icon) in _rankedCategories)
              _categoryRow(name, icon, cats[id]),
            const SizedBox(height: 12),
            Text('RANK DISTRIBUTION', style: _secTitle()),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [for (final t in _tierOrder) _distChip(t, dist[t] ?? 0)],
            ),
          ]),
        ),
      ),
    );
  }

  Widget _stat(String value, String label) => Column(children: [
        Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        Text(label, style: const TextStyle(fontSize: 9, letterSpacing: 1.2, color: _muted, fontWeight: FontWeight.w700)),
      ]);

  // One tier's badge + count (figure 3). Dimmed when no metric sits there.
  Widget _distChip(String tier, int count) {
    final col = tierColor(tier);
    final on = count > 0;
    return Container(
      width: 64,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: on ? col.withValues(alpha: 0.12) : _surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: on ? col.withValues(alpha: 0.4) : _border),
      ),
      child: Column(children: [
        Text('$count',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w900, color: on ? col : _muted)),
        Text(tier,
            style: TextStyle(fontSize: 9, color: on ? col : _muted, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _categoryRow(String name, IconData icon, RankResult? r) {
    final ranked = r != null;
    final c = ranked ? tierColor(r.tier) : _muted;
    final frac = ranked ? (r.rankValue / 8).clamp(0.0, 1.0) : 0.0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ranked ? c.withValues(alpha: 0.3) : _border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 18, color: c),
          const SizedBox(width: 8),
          Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
          Text(ranked ? '${r.tier} ${r.sub}' : 'No data',
              style: TextStyle(color: c, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
              value: frac, minHeight: 7, color: c,
              backgroundColor: Colors.white.withValues(alpha: 0.06)),
        ),
        if (ranked) ...[
          const SizedBox(height: 4),
          Text('Top ${r.topPct.toStringAsFixed(1)}%  ·  avg ${r.rankValue.toStringAsFixed(2)}/8',
              style: const TextStyle(fontSize: 10, color: _muted)),
        ],
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// BODY GRAPH SECTION — gradient container with 4 figures
// ═══════════════════════════════════════════════════════════════════════════
class _BodyGraphSection extends StatelessWidget {
  final BuildContext parentContext;
  const _BodyGraphSection(this.parentContext);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [_bg3, _bg2],
        ),
        border: Border.all(color: _border2),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 32, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        children: [
          _AestheticsStrip(parentContext),
          const SizedBox(height: 16),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _figure('Front', frontRegions)),
            const SizedBox(width: 8),
            Expanded(child: _figure('Inner', innerRegions)),
            const SizedBox(width: 8),
            Expanded(child: _figure('Back', backRegions)),
          ]),
        ],
      ),
    );
  }

  Widget _figure(String label, List<BodyRegion> regions, {bool headZoom = false}) {
    final graph = BodyGraph(
      regions: regions,
      onTapMetric: (mid) => openDetailSheet(parentContext, mid),
      isHeadOnly: headZoom,
    );
    return Column(children: [
      if (headZoom)
        ClipRect(child: SizedBox(height: 110, width: 70, child: graph))
      else
        AspectRatio(aspectRatio: 148 / 420, child: graph),
      const SizedBox(height: 6),
      Text(label, style: const TextStyle(fontSize: 10, letterSpacing: 2.5,
          color: _muted, fontWeight: FontWeight.w700)),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// METRIC GRID — 2-column grid of compact metric cards
// ═══════════════════════════════════════════════════════════════════════════
class _MetricGrid extends ConsumerWidget {
  final List<String> metricIds;
  final Map<String, Log> latest;
  final void Function(String) onTap;
  const _MetricGrid({required this.metricIds, required this.latest, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // De-duplicate while preserving order
    final seen = <String>{};
    final ids = metricIds.where((id) => seen.add(id)).toList();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, mainAxisSpacing: 6, crossAxisSpacing: 6,
        childAspectRatio: 3.3,
      ),
      itemCount: ids.length,
      itemBuilder: (ctx, i) => _MetricCell(ids[i], latest[ids[i]], onTap),
    );
  }
}

class _MetricCell extends StatelessWidget {
  final String metricId;
  final Log? log;
  final void Function(String) onTap;
  const _MetricCell(this.metricId, this.log, this.onTap);

  @override
  Widget build(BuildContext context) {
    final MetricDef m;
    try { m = metricById(metricId); } catch (_) { return const SizedBox.shrink(); }
    final hasStandard = eng.standards.containsKey(metricId);
    final hasData = log != null;
    final r = (hasData && hasStandard) ? eng.scoreLog(log!) : null;
    final c = r != null ? tierColor(r.tier) : (hasData ? const Color(0xFF4CE0C3) : _muted);

    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: _surface,
          border: Border.all(color: hasData ? c.withValues(alpha: 0.35) : _border),
          borderRadius: BorderRadius.circular(4),
          gradient: hasData
              ? LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [c.withValues(alpha: 0.15), _surface],
                )
              : null,
        ),
        child: Material(
          color: hasData ? c.withValues(alpha: 0.12) : Colors.transparent,
          child: InkWell(
            onTap: () => onTap(metricId),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(children: [
                Container(width: 10, height: 10,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      boxShadow: hasData
                          ? [BoxShadow(color: c.withValues(alpha: 0.8), blurRadius: 6)]
                          : null,
                    )),
                const SizedBox(width: 8),
                Expanded(child: Text(m.label, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                if (hasData) ...[
                  Text('${log!.value.toStringAsFixed(0)}${m.unit}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c)),
                ] else
                  const Text('—', style: TextStyle(fontSize: 11, color: _muted)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// LOG SHEET — bottom sheet to log any metric
// ═══════════════════════════════════════════════════════════════════════════
void openLogSheet(BuildContext context, {String? initialMetricId}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: _bg2,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
      child: _LogSheet(initialMetricId: initialMetricId),
    ),
  );
}

class _LogSheet extends ConsumerStatefulWidget {
  final String? initialMetricId;
  const _LogSheet({this.initialMetricId});
  @override
  ConsumerState<_LogSheet> createState() => _LogSheetState();
}

class _LogSheetState extends ConsumerState<_LogSheet> {
  late MetricDef _metric;
  final _weight = TextEditingController();
  final _reps = TextEditingController(text: '5');
  final _value = TextEditingController();
  final _bw = TextEditingController();

  late List<MetricDef> _loggableList;

  @override
  void initState() {
    super.initState();
    _loggableList = [
      ...metrics.where((m) => m.tier != MetricTier.background && !m.autoSync),
      metricById('bodyweight')
    ];
    if (widget.initialMetricId != null) {
      final initialM = metricById(widget.initialMetricId!);
      if (!_loggableList.any((m) => m.id == initialM.id)) {
        _loggableList.add(initialM);
      }
      _metric = initialM;
    } else {
      _metric = rankedMetrics.first;
    }
    final bw = ref.read(currentBodyweightProvider);
    if (bw != null) _bw.text = bw.toStringAsFixed(0);
  }

  void _save() {
    Log log;
    if (_metric.isStrength) {
      final w = double.tryParse(_weight.text);
      final reps = int.tryParse(_reps.text);
      final bw = double.tryParse(_bw.text);
      if (w == null || reps == null || bw == null) return;
      log = Log(_metric.id, strengthValue(_metric.id, w, reps), bodyweight: bw);
    } else {
      final v = double.tryParse(_value.text);
      if (v == null) return;
      log = Log(_metric.id, v);
    }
    ref.read(logsProvider.notifier).add(_metric.id, log);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButton<MetricDef>(
          isExpanded: true,
          value: _metric,
          dropdownColor: _bg3,
          items: _loggableList
              .map((m) =>
                  DropdownMenuItem(value: m, child: Text('${m.label} (${m.unit})')))
              .toList(),
          onChanged: (m) => setState(() => _metric = m!),
        ),
        const SizedBox(height: 8),
        if (_metric.isStrength) ...[
          Row(children: [
            Expanded(child: _field(_weight, 'Weight (kg)')),
            const SizedBox(width: 8),
            Expanded(child: _field(_reps, 'Reps')),
          ]),
          if (isolationLifts.contains(_metric.id))
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Scored by working-set volume: weight × reps',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
            ),
          const SizedBox(height: 8),
          _field(_bw, 'Bodyweight now (kg) — snapshotted to this lift'),
        ] else
          _field(_value, '${_metric.label} (${_metric.unit})'),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity,
            child: FilledButton(onPressed: _save, child: const Text('Save'))),
        const SizedBox(height: 8),
      ]),
    );
  }

  Widget _field(TextEditingController c, String label) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      );
}

class _AestheticsStrip extends ConsumerWidget {
  final BuildContext parentContext;
  const _AestheticsStrip(this.parentContext);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsMap = ref.watch(logsProvider);
    final metricsToDisplay = metrics.where((m) => m.category == 'aesthetics').toList();
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: metricsToDisplay.map((m) {
        final region = headRegions.firstWhere((r) => r.muscle == m.id, orElse: () => const BodyRegion('', []));
        final logs = logsMap[m.id] ?? [];
        final hasData = logs.isNotEmpty;
        Color color = const Color(0xFF454964);
        if (hasData) {
          final isRanked = eng.standards.containsKey(m.id);
          if (isRanked) {
            color = tierColor(eng.scoreLog(logs.last).tier);
          } else {
            color = const Color(0xFF4CE0C3);
          }
        }

        return Material(
          color: Colors.transparent,
          child: Ink(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF161830),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: hasData ? color.withValues(alpha: 0.5) : const Color(0x12FFFFFF)),
              boxShadow: hasData ? [BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 8)] : [],
            ),
            child: InkWell(
              onTap: () => openDetailSheet(parentContext, m.id),
              borderRadius: BorderRadius.circular(12),
              child: CustomPaint(
                painter: _RegionIconPainter(region, color),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _RegionIconPainter extends CustomPainter {
  final BodyRegion region;
  final Color color;
  _RegionIconPainter(this.region, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (region.polys.isEmpty) return;
    final path = Path();
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    for (final pStr in region.polys) {
      final points = parsePoly(pStr);
      if (points.isEmpty) continue;
      path.moveTo(points.first.dx, points.first.dy);
      for (var i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      path.close();
      for (final p in points) {
        if (p.dx < minX) minX = p.dx;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dy > maxY) maxY = p.dy;
      }
    }

    final w = maxX - minX;
    final h = maxY - minY;
    if (w <= 0 || h <= 0) return;

    final scale = math.min(size.width / w, size.height / h) * 0.55;
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(-(minX + w / 2), -(minY + h / 2));

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_RegionIconPainter old) => old.region != region || old.color != color;
}
