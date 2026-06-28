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

// A score-level colour (NOT a rank) for a 0–100 score, drawn across the full 9 rank-
// tier palette: 20→Wood, 30→Bronze, 40→Silver … 100→Glory, interpolated between.
// Used for tracked aesthetics — same palette as ranks, so it reads cohesively.
Color scoreColor(double score) {
  final t = ((score - 20) / 10).clamp(0.0, (_tierOrder.length - 1).toDouble());
  final lo = t.floor(), hi = t.ceil();
  if (lo == hi) return tierColor(_tierOrder[lo]);
  return Color.lerp(tierColor(_tierOrder[lo]), tierColor(_tierOrder[hi]), t - lo)!;
}

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
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          const Expanded(child: Divider(color: _border, thickness: 1, endIndent: 12)),
          Text(text, style: _secTitle()),
          const Expanded(child: Divider(color: _border, thickness: 1, indent: 12)),
        ]),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// OVERALL CARD — with progress bar + sub-rank ticks + weakest metric
// ═══════════════════════════════════════════════════════════════════════════
// A modern rank progress bar: a gradient fill with a tier-coloured glow, a thin
// specular highlight, and the I/II/III sub-rank ticks at the thirds. [frac] is
// progress WITHIN the current tier (0..1), so the ticks read as sub-ranks.
class _RankBar extends StatelessWidget {
  final double frac;
  final Color color;
  final double height;
  final bool showThirds;
  const _RankBar({required this.frac, required this.color, this.height = 12, this.showThirds = true});

  @override
  Widget build(BuildContext context) {
    final radius = height / 2;
    final f = frac.clamp(0.0, 1.0);
    return SizedBox(
      height: height,
      child: LayoutBuilder(builder: (context, cons) {
        final w = cons.maxWidth;
        return Stack(clipBehavior: Clip.none, children: [
          // Track.
          Container(decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          )),
          // Glowing gradient fill.
          FractionallySizedBox(
            widthFactor: f,
            child: Container(decoration: BoxDecoration(
              gradient: LinearGradient(colors: [color.withValues(alpha: 0.5), color]),
              borderRadius: BorderRadius.circular(radius),
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 12, spreadRadius: -1)],
            )),
          ),
          // Bright leading-edge cap at the progress point — an energy-bar flourish.
          if (f > 0.04 && f < 0.992)
            Positioned(
              left: (f * w) - height * 0.5,
              top: -height * 0.18, bottom: -height * 0.18,
              child: Container(
                width: height,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.92),
                  boxShadow: [BoxShadow(color: color, blurRadius: height, spreadRadius: height * 0.18)],
                ),
              ),
            ),
          // Thin specular highlight along the top of the fill (a Padding band so it
          // spans the fill width — an Align'd width-less Container would collapse).
          if (f > 0.02)
            FractionallySizedBox(
              widthFactor: f,
              child: Padding(
                padding: EdgeInsets.fromLTRB(radius * 0.7, height * 0.2, radius * 0.7, height * 0.55),
                child: Container(decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(radius),
                )),
              ),
            ),
          // Sub-rank thirds.
          if (showThirds)
            for (final p in const [0.3333, 0.6666])
              Positioned(left: p * w, top: 1.5, bottom: 1.5,
                  child: Container(width: 1.5, color: Colors.black.withValues(alpha: 0.30))),
        ]);
      }),
    );
  }
}

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
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [c.withValues(alpha: 0.18), _bg2],
        ),
        border: Border.all(color: c.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 32, offset: const Offset(0, 8)),
          BoxShadow(color: c.withValues(alpha: 0.22), blurRadius: 34, spreadRadius: -6),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
        RankBadge(tier: r.tier, sub: r.sub, size: 244, animated: true),
        const SizedBox(height: 16),
        const Text('OVERALL RANK',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, letterSpacing: 2.5, color: _muted, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('${r.tier} ${r.sub}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: c, height: 1)),
        const SizedBox(height: 6),
        Text('Top ${r.topPct.toStringAsFixed(1)}% of young men',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c)),
        const SizedBox(height: 14),
        _RankBar(frac: frac, color: c, height: 12),
        const SizedBox(height: 6),
        Text('Avg ${r.rankValue.toStringAsFixed(2)}/8',
            style: const TextStyle(fontSize: 11, color: _muted2)),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('open',
              style: TextStyle(fontSize: 10.5, letterSpacing: 1.5, color: c.withValues(alpha: 0.8), fontWeight: FontWeight.w700)),
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
const List<(String, String)> _rankedCategories = [
  ('strength', 'Strength'),
  ('performance', 'Performance'),
  ('recovery', 'Recovery'),
  ('aesthetics', 'Aesthetics'),
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
    final overallFrac = overall.rankValue - overall.rankValue.floor();
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
        // Cap below full height so a consistent strip of scrim stays at the top —
        // tap it (or the handle) to dismiss, which is reliable on iPhone.
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 14, top: 2),
                child: Center(child: Container(width: 44, height: 5,
                    decoration: BoxDecoration(color: _border2, borderRadius: BorderRadius.circular(3)))),
              ),
            ),
            Center(child: RankBadge(tier: overall.tier, sub: overall.sub, size: 220, animated: true)),
            const SizedBox(height: 10),
            Center(child: Text('${overall.tier} ${overall.sub}',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: c, height: 1))),
            const SizedBox(height: 4),
            Center(child: Text('Top ${overall.topPct.toStringAsFixed(1)}% of young men',
                style: TextStyle(color: c, fontWeight: FontWeight.w600))),
            const SizedBox(height: 14),
            _RankBar(frac: overallFrac, color: c, height: 12),
            const SizedBox(height: 6),
            Center(child: Text('Avg ${overall.rankValue.toStringAsFixed(2)}/8',
                style: const TextStyle(fontSize: 11, color: _muted2))),
            const SizedBox(height: 22),
            Text('CATEGORY RANKINGS', style: _secTitle()),
            const SizedBox(height: 10),
            for (final (id, name) in _rankedCategories)
              _categoryRow(id, name, cats[id]),
            const SizedBox(height: 12),
            Text('RANK DISTRIBUTION', style: _secTitle()),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 14,
              alignment: WrapAlignment.center,
              children: [for (final t in _tierOrder) _distChip(t, dist[t] ?? 0)],
            ),
            const SizedBox(height: 24),
            Center(child: _stat('$totalLogs', 'TOTAL LOGS')),
          ]),
        ),
      ),
    );
  }

  Widget _stat(String value, String label) => Column(children: [
        Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        Text(label, style: const TextStyle(fontSize: 10.5, letterSpacing: 1.2, color: _muted, fontWeight: FontWeight.w700)),
      ]);

  // One tier's medallion + a count pill (figure 3). Dimmed when no metric sits there.
  Widget _distChip(String tier, int count) {
    final col = tierColor(tier);
    final on = count > 0;
    return SizedBox(
      width: 112,
      child: Column(children: [
        SizedBox(
          width: 102, height: 102,
          child: Stack(clipBehavior: Clip.none, children: [
            Center(child: Opacity(opacity: on ? 1.0 : 0.22, child: RankBadge(tier: tier, size: 100))),
            if (on)
              Positioned(
                right: -4, top: -4,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  padding: const EdgeInsets.all(3),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle, color: _bg2,
                    border: Border.all(color: col, width: 1.5),
                  ),
                  child: Text('$count',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: col)),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 3),
        Text(tier, style: TextStyle(fontSize: 10.5, color: on ? col : _muted, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _categoryRow(String id, String name, RankResult? r) {
    final ranked = r != null;
    final c = ranked ? tierColor(r.tier) : _muted;
    final frac = ranked ? (r.rankValue - r.rankValue.floor()) : 0.0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ranked ? c.withValues(alpha: 0.3) : _border),
      ),
      child: Row(children: [
        if (ranked)
          RankBadge(tier: r.tier, sub: r.sub, size: 108)
        else
          Container(
            width: 106, height: 106, alignment: Alignment.center,
            decoration: BoxDecoration(
                shape: BoxShape.circle, color: _surface, border: Border.all(color: _border)),
            child: const Icon(Icons.lock_outline, size: 28, color: _muted),
          ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
              Text(ranked ? '${r.tier} ${r.sub}' : 'No data',
                  style: TextStyle(color: c, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 9),
            _RankBar(frac: frac, color: c, height: 9, showThirds: ranked),
            if (ranked) ...[
              const SizedBox(height: 5),
              Text('Top ${r.topPct.toStringAsFixed(1)}%  ·  avg ${r.rankValue.toStringAsFixed(2)}/8',
                  style: const TextStyle(fontSize: 11, color: _muted)),
            ],
          ]),
        ),
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
          const _BodyStatsStrip(),
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
      Text(label, style: const TextStyle(fontSize: 11, letterSpacing: 2.5,
          color: _muted, fontWeight: FontWeight.w700)),
    ]);
  }
}

// Bio strip at the foot of the body section: Age · Sex · Height · Weight.
// Age/height/weight auto-port from Google Health; gender isn't exposed by the API,
// so Sex shows the app's reference population (young male).
class _BodyStatsStrip extends ConsumerWidget {
  const _BodyStatsStrip();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(logsProvider);
    double? v(String id) {
      final l = logs[id];
      return (l == null || l.isEmpty) ? null : l.last.value;
    }
    final age = v('age'), h = v('height'), w = v('bodyweight');
    final items = <(String, String)>[
      ('AGE', age == null ? '—' : age.toStringAsFixed(0)),
      ('SEX', 'Male'),
      ('HEIGHT', h == null ? '—' : '${h.toStringAsFixed(0)} cm'),
      ('WEIGHT', w == null ? '—' : '${w.toStringAsFixed(1)} kg'),
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(6, 14, 6, 2),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Row(children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) Container(width: 1, height: 26, color: _border),
          Expanded(
            child: Column(children: [
              Text(items[i].$2,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(items[i].$1,
                  style: const TextStyle(fontSize: 9.5, letterSpacing: 1.5,
                      color: _muted, fontWeight: FontWeight.w700)),
            ]),
          ),
        ],
      ]),
    );
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
        crossAxisCount: 2, mainAxisSpacing: 8, crossAxisSpacing: 8,
        // FIXED height (not width-relative) so cells stay compact on wide screens
        // instead of growing tall. Fits the 2-line label + value with a little slack.
        mainAxisExtent: 64,
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
          borderRadius: BorderRadius.circular(12),
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
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Row(children: [
                Container(width: 11, height: 11,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      boxShadow: hasData
                          ? [BoxShadow(color: c.withValues(alpha: 0.8), blurRadius: 7, spreadRadius: 0.5)]
                          : null,
                    )),
                const SizedBox(width: 10),
                // Label on up to two lines, then the value on its own line.
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.label, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.08)),
                      const SizedBox(height: 2),
                      hasData
                          ? Text('${log!.value.toStringAsFixed(0)} ${m.unit}',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: c))
                          : const Text('—', style: TextStyle(fontSize: 12, color: _muted)),
                    ],
                  ),
                ),
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

// Recognisable glyph per tracked aesthetic — "what it should be" at a glance.
const Map<String, IconData> _aestheticIcons = {
  'skin': Icons.face_retouching_natural,
  'hair': Icons.face_3,
  'eye': Icons.remove_red_eye,
  'oral': Icons.sentiment_very_satisfied,
  'grooming': Icons.content_cut,
  'voice': Icons.graphic_eq,
};

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
        final logs = logsMap[m.id] ?? [];
        final hasData = logs.isNotEmpty;
        final v = hasData ? logs.last.value : null;
        // Ranked aesthetic — coloured by its TIER (eye/voice aren't /100, so a raw-score
        // colour would be wrong; the tier is correct for every aesthetic).
        final color = hasData && eng.standards.containsKey(m.id)
            ? tierColor(eng.scoreLog(logs.last).tier)
            : const Color(0xFF454964);
        // Value label, formatted per unit (/100 → int, logMAR → 2dp, AVQI → 1dp).
        final label = v == null
            ? '—'
            : m.unit == '/100'
                ? v.round().toString()
                : v.toStringAsFixed(m.unit == 'logMAR' ? 2 : 1);

        return Column(mainAxisSize: MainAxisSize.min, children: [
          Material(
            color: Colors.transparent,
            child: Ink(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: hasData
                    ? LinearGradient(
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [color.withValues(alpha: 0.18), const Color(0xFF161830)])
                    : null,
                color: hasData ? null : const Color(0xFF161830),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: hasData ? color.withValues(alpha: 0.6) : const Color(0x12FFFFFF)),
                boxShadow: hasData ? [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 10)] : [],
              ),
              child: InkWell(
                onTap: () => openDetailSheet(parentContext, m.id),
                borderRadius: BorderRadius.circular(14),
                child: Center(child: Icon(_aestheticIcons[m.id] ?? Icons.spa, color: color, size: 24)),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w800,
                  color: hasData ? color : _muted)),
        ]);
      }).toList(),
    );
  }
}

