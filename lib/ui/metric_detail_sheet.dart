// ui/metric_detail_sheet.dart — tap a muscle or row to open this. Shows the
// rank, the derived tier ladder (achieved/next/locked), log history, and an
// inline log form. Showcases the engine's derived thresholds.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/metrics.dart';
import '../engine/rank_engine.dart' as eng;
import '../engine/rank_engine.dart' show Log, est1rm;
import '../state/providers.dart';
import 'badge.dart';

const List<String> _ladderTiers = [
  'Bronze', 'Silver', 'Gold', 'Platinum', 'Diamond', 'Champion', 'Titan'
];

void openDetailSheet(BuildContext context, String metricId) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF12152E),
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _MetricDetailSheet(metricId: metricId),
  );
}

class _MetricDetailSheet extends ConsumerStatefulWidget {
  final String metricId;
  const _MetricDetailSheet({required this.metricId});
  @override
  ConsumerState<_MetricDetailSheet> createState() => _MetricDetailSheetState();
}

class _MetricDetailSheetState extends ConsumerState<_MetricDetailSheet> {
  final _weight = TextEditingController();
  final _reps = TextEditingController(text: '5');
  final _value = TextEditingController();
  final _bw = TextEditingController();

  @override
  void initState() {
    super.initState();
    final bw = ref.read(currentBodyweightProvider);
    if (bw != null) _bw.text = bw.toStringAsFixed(0);
  }

  void _save() {
    final m = metricById(widget.metricId);
    Log log;
    if (m.isStrength) {
      final w = double.tryParse(_weight.text);
      final reps = int.tryParse(_reps.text);
      final bw = double.tryParse(_bw.text);
      if (w == null || reps == null || bw == null) return;
      log = Log(m.id, est1rm(w, reps),
          bodyweight: bw, ts: DateTime.now().toIso8601String());
    } else {
      final v = double.tryParse(_value.text);
      if (v == null) return;
      log = Log(m.id, v, ts: DateTime.now().toIso8601String());
    }
    ref.read(logsProvider.notifier).add(m.id, log);
    _weight.clear();
    _value.clear();
  }

  @override
  Widget build(BuildContext context) {
    final m = metricById(widget.metricId);
    final logs = ref.watch(logsProvider)[m.id] ?? const [];
    final latest = logs.isNotEmpty ? logs.last : null;
    final ranked = latest != null && eng.standards.containsKey(m.id);
    final r = ranked ? eng.scoreLog(latest!) : null;
    final c = r != null ? tierColor(r.tier) : const Color(0xFF5A6072);
    final bw = m.bodyweightScaled ? ref.watch(currentBodyweightProvider) : null;
    final curIdx = r != null ? r.rankValue.floor() : 0;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
              left: 18, right: 18, top: 18,
              bottom: MediaQuery.of(context).viewInsets.bottom + 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ── Header ──
            Row(children: [
              RankBadge(tier: r?.tier ?? 'Wood', sub: r?.sub, size: 40),
              const SizedBox(width: 12),
              Expanded(child: Text(m.label,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
              if (r != null)
                Text('${r.tier} ${r.sub}',
                    style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 16)),
            ]),
            const SizedBox(height: 2),
            Text('📍 ${m.exercise}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 10),
            if (r != null) ...[
              Text('Top ${r.topPct.toStringAsFixed(1)}% of young men',
                  style: TextStyle(color: c, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                  value: r.rankValue - curIdx, color: c, backgroundColor: c.withOpacity(0.15)),
            ] else
              const Text('No logs yet — add one below.',
                  style: TextStyle(color: Colors.grey)),

            // ── Milestone ladder (derived thresholds) ──
            const SizedBox(height: 18),
            const Text('TIER LADDER',
                style: TextStyle(fontSize: 10, letterSpacing: 2, color: Colors.grey)),
            const SizedBox(height: 6),
            for (var i = 0; i < _ladderTiers.length; i++)
              _ladderRow(m, _ladderTiers[i], i + 1, curIdx, bw),

            // ── History ──
            if (logs.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('HISTORY · ${logs.length}',
                  style: const TextStyle(fontSize: 10, letterSpacing: 2, color: Colors.grey)),
              const SizedBox(height: 6),
              for (var i = logs.length - 1; i >= 0; i--) _historyRow(m, logs[i], i),
            ],

            // ── Log form ──
            const SizedBox(height: 18),
            Text('LOG ${m.exercise.isEmpty ? m.label : m.exercise}'.toUpperCase(),
                style: const TextStyle(fontSize: 10, letterSpacing: 2, color: Colors.grey)),
            const SizedBox(height: 8),
            if (m.isStrength) ...[
              Row(children: [
                Expanded(child: _field(_weight, 'Weight (kg)')),
                const SizedBox(width: 8),
                Expanded(child: _field(_reps, 'Reps')),
              ]),
              const SizedBox(height: 8),
              _field(_bw, 'Bodyweight now (kg) — snapshotted'),
            ] else
              _field(_value, '${m.label} (${m.unit})'),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity,
                child: FilledButton(onPressed: _save, child: const Text('Save'))),
          ]),
        ),
      ),
    );
  }

  Widget _ladderRow(MetricDef m, String tier, int tierIdx, int curIdx, double? bw) {
    final thr = eng.threshold(m.id, tier, bw);
    final achieved = curIdx >= tierIdx;
    final isNext = curIdx == tierIdx - 1;
    final col = tierColor(tier);
    final icon = achieved ? '✓' : (isNext ? '🎯' : '🔒');
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: achieved ? col.withOpacity(0.12) : const Color(0xFF0E1124),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isNext ? col : Colors.transparent, width: 1),
      ),
      child: Row(children: [
        Text(icon, style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 10),
        Expanded(child: Text(tier,
            style: TextStyle(
                fontWeight: FontWeight.w700,
                color: achieved ? col : Colors.grey))),
        Text('${thr.toStringAsFixed(1)} ${m.unit}',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                color: achieved ? col : Colors.grey)),
        const SizedBox(width: 8),
        Text('top ${eng.tierTopPct[tier]!.toStringAsFixed(0)}%',
            style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ]),
    );
  }

  Widget _historyRow(MetricDef m, Log log, int index) {
    final r = eng.standards.containsKey(m.id) ? eng.scoreLog(log) : null;
    final c = r != null ? tierColor(r.tier) : Colors.grey;
    final date = log.ts != null ? DateTime.tryParse(log.ts!) : null;
    final dateStr = date != null
        ? '${date.day}/${date.month}/${date.year % 100}'
        : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Container(width: 8, height: 8,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '${log.value.toStringAsFixed(1)} ${m.unit}'
            '${m.bodyweightScaled && log.bodyweight != null ? ' @ ${log.bodyweight!.toStringAsFixed(0)} kg' : ''}',
            style: const TextStyle(fontSize: 13),
          ),
        ),
        if (r != null)
          Text('${r.tier} ${r.sub}',
              style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        Text(dateStr, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        IconButton(
          icon: const Icon(Icons.close, size: 16),
          color: Colors.grey,
          onPressed: () => ref.read(logsProvider.notifier).remove(m.id, index),
        ),
      ]),
    );
  }

  Widget _field(TextEditingController ctrl, String label) => TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      );
}
