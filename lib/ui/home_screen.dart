// ui/home_screen.dart — overall rank, the front/back body graph (tap a muscle
// to log its lift), and the ranked-metric list.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/metrics.dart';
import '../data/body_figure_data.dart';
import '../engine/rank_engine.dart' as eng;
import '../engine/rank_engine.dart' show Log, RankResult, est1rm;
import '../state/providers.dart';
import 'badge.dart';
import 'body_graph.dart';
import 'metric_detail_sheet.dart';
import 'progress_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overall = ref.watch(overallProvider);
    final latest = ref.watch(latestLogsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Physical'), actions: [
        IconButton(
          icon: const Icon(Icons.show_chart),
          tooltip: 'Progress',
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ProgressScreen())),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openLogSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Log'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _OverallCard(overall),
          const SizedBox(height: 12),
          // ── Body graph: tap a muscle to log its lift ──
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _figure('Front', frontRegions, context)),
            const SizedBox(width: 8),
            Expanded(child: _figure('Back', backRegions, context)),
          ]),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('RANKED METRICS',
                style: TextStyle(fontSize: 11, letterSpacing: 2, color: Colors.grey)),
          ),
          for (final m in rankedMetrics) _MetricRow(metric: m, latest: latest[m.id]),
        ],
      ),
    );
  }

  Widget _figure(String label, List<BodyRegion> regions, BuildContext context) {
    return Column(children: [
      AspectRatio(
        aspectRatio: 148 / 420,
        child: BodyGraph(
          regions: regions,
          onTapMetric: (mid) => openDetailSheet(context, mid),
        ),
      ),
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
    ]);
  }
}

class _OverallCard extends StatelessWidget {
  final RankResult r;
  const _OverallCard(this.r);
  @override
  Widget build(BuildContext context) {
    final c = tierColor(r.tier);
    return Card(
      color: c.withOpacity(0.12),
      shape: RoundedRectangleBorder(
          side: BorderSide(color: c.withOpacity(0.5)),
          borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(children: [
          RankBadge(tier: r.tier, sub: r.sub, size: 68),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('OVERALL',
                  style: TextStyle(fontSize: 11, letterSpacing: 2, color: Colors.grey)),
              const SizedBox(height: 6),
              Text('${r.tier} ${r.sub}',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: c)),
              Text('Top ${r.topPct.toStringAsFixed(1)}% of young men',
                  style: TextStyle(color: c)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _MetricRow extends ConsumerWidget {
  final MetricDef metric;
  final Log? latest;
  const _MetricRow({required this.metric, this.latest});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (latest == null) {
      return ListTile(
        title: Text(metric.label),
        trailing: const Text('—', style: TextStyle(color: Colors.grey)),
        onTap: () => openDetailSheet(context, metric.id),
      );
    }
    final r = eng.scoreLog(latest!);
    final c = tierColor(r.tier);
    final idx = r.rankValue.floor();
    String next = '';
    if (idx < 7) {
      final bw = metric.bodyweightScaled ? latest!.bodyweight : null;
      final t = eng.threshold(metric.id, eng.tiers[idx + 1], bw);
      next = 'Next: ${eng.tiers[idx + 1]} at ${t.toStringAsFixed(1)} ${metric.unit}';
    }
    final frac = r.rankValue - idx;
    return Card(
      child: InkWell(
        onTap: () => openDetailSheet(context, metric.id),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 10, height: 10,
                  decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(child: Text(metric.label,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
              Text('${r.tier} ${r.sub}',
                  style: TextStyle(color: c, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 4),
            Text('Latest ${latest!.value.toStringAsFixed(1)} ${metric.unit}'
                '${metric.bodyweightScaled && latest!.bodyweight != null ? ' @ ${latest!.bodyweight!.toStringAsFixed(0)} kg BW' : ''}'
                '  ·  top ${r.topPct.toStringAsFixed(1)}%',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: frac, color: c, backgroundColor: c.withOpacity(0.15)),
            if (next.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 4),
                  child: Text(next, style: const TextStyle(fontSize: 11, color: Colors.grey))),
          ]),
        ),
      ),
    );
  }
}

void openLogSheet(BuildContext context, {String? initialMetricId}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
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

  List<MetricDef> get _loggable => [...rankedMetrics, metricById('bodyweight')];

  @override
  void initState() {
    super.initState();
    _metric = _loggable.firstWhere((m) => m.id == widget.initialMetricId,
        orElse: () => rankedMetrics.first);
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
      log = Log(_metric.id, est1rm(w, reps), bodyweight: bw);
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
          items: [
            for (final m in _loggable)
              DropdownMenuItem(value: m, child: Text('${m.label} (${m.unit})'))
          ],
          onChanged: (m) => setState(() => _metric = m!),
        ),
        const SizedBox(height: 8),
        if (_metric.isStrength) ...[
          Row(children: [
            Expanded(child: _field(_weight, 'Weight (kg)')),
            const SizedBox(width: 8),
            Expanded(child: _field(_reps, 'Reps')),
          ]),
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
