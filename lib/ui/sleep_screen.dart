// ui/sleep_screen.dart — a per-domain sleep page (PDF per-domain layout): the latest
// night's STAGE breakdown (deep / REM / light), a 7-night sleep-score + hours-asleep
// trend, and recovery stats (efficiency, time-to-sleep, awakenings). All auto-synced
// from Google Health; feeds the coach. Routed from the Sleep card on the Graphs tab.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/habits.dart' show valuesLastNDays;
import '../data/metrics.dart' show tierColor, metrics;
import '../engine/rank_engine.dart' show Log, tierOf;
import '../state/providers.dart';
import 'progress_screen.dart' show GraphArea;

const _bg = Color(0xFF08091A);
const _card = Color(0xFF12152E);
const _indigo = Color(0xFF7A6CF0);
const _deepC = Color(0xFF3D5AF1);
const _remC = Color(0xFF9B6CF0);
const _lightC = Color(0xFF4CE0C3);
const _muted = Color(0xFF7880A8);

void openSleepScreen(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SleepScreen()));
}

class SleepScreen extends ConsumerWidget {
  const SleepScreen({super.key});

  static double? _latest(Map<String, List<Log>> m, String id) {
    final l = m[id];
    return (l != null && l.isNotEmpty) ? l.last.value : null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(logsProvider);
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(backgroundColor: _bg, title: const Text('Sleep')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
        _lastNight(
          _latest(logs, 'sleep_score'),
          _latest(logs, 'sleep_duration'),
          _latest(logs, 'deep_sleep'),
          _latest(logs, 'rem_sleep'),
        ),
        const SizedBox(height: 12),
        _barCard('LAST 7 NIGHTS · SLEEP SCORE',
            valuesLastNDays(logs['sleep_score'] ?? const []), 100, _indigo,
            (v) => v.round().toString()),
        const SizedBox(height: 12),
        _durationTrend(valuesLastNDays(logs['sleep_duration'] ?? const [])),
        const SizedBox(height: 12),
        _stats(_latest(logs, 'sleep_efficiency'), _latest(logs, 'time_to_sleep'),
            _latest(logs, 'full_awakenings')),
        const SizedBox(height: 24),
        const Text('ALL SLEEP METRICS',
            style: TextStyle(fontSize: 11, letterSpacing: 2, color: _muted, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('Pick a metric + timeframe (1W · 3M · 6M · 1Y · All).',
            style: TextStyle(fontSize: 12, color: _muted)),
        const SizedBox(height: 8),
        // Full multi-metric graph of every sleep sub-metric over any timeframe.
        GraphArea([for (final m in metrics) if (m.category == 'sleep') m]),
      ]),
    );
  }

  static String _hm(double mins) {
    final h = mins ~/ 60;
    final m = (mins % 60).round();
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  Widget _lastNight(double? score, double? durH, double? deep, double? rem) {
    final asleep = (durH ?? 0) * 60;
    final d = deep ?? 0, r = rem ?? 0;
    final light = (asleep - d - r).clamp(0, asleep).toDouble();
    final hasStages = (d + r + light) > 0;
    return Card(
      color: _card,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('LAST NIGHT', style: TextStyle(fontSize: 10, letterSpacing: 2, color: _muted)),
            const Spacer(),
            if (score != null) _scoreBadge(score),
          ]),
          const SizedBox(height: 10),
          Text(durH != null ? _hm(asleep) : 'No sleep data yet',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: _indigo)),
          if (hasStages) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: Row(children: [
                Expanded(flex: (d * 10).round().clamp(0, 1 << 30), child: Container(height: 12, color: _deepC)),
                Expanded(flex: (r * 10).round().clamp(0, 1 << 30), child: Container(height: 12, color: _remC)),
                Expanded(flex: (light * 10).round().clamp(0, 1 << 30), child: Container(height: 12, color: _lightC)),
              ]),
            ),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _stage('Deep', d, _deepC),
              _stage('REM', r, _remC),
              _stage('Light', light, _lightC),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _scoreBadge(double score) {
    final c = tierColor(tierOf('sleep_score', score, null).tier);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Text('${score.round()} · ${tierOf('sleep_score', score, null).tier}',
          style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 13)),
    );
  }

  Widget _stage(String label, double mins, Color c) => Column(children: [
        Text('${mins.round()}m', style: TextStyle(fontWeight: FontWeight.w800, color: c)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 10, color: _muted)),
      ]);

  Widget _durationTrend(List<double?> vals) {
    final maxH = vals.whereType<double>().fold<double>(8, (m, v) => v > m ? v : m);
    return _barCard('LAST 7 NIGHTS · HOURS ASLEEP', vals, maxH, _lightC,
        (v) => v.toStringAsFixed(1));
  }

  Widget _barCard(String title, List<double?> vals, double maxV, Color color,
      String Function(double) fmt) {
    return Card(
      color: _card,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 10, letterSpacing: 2, color: _muted)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < vals.length; i++)
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(vals[i] != null ? fmt(vals[i]!) : '',
                      style: const TextStyle(fontSize: 8, color: _muted)),
                  const SizedBox(height: 2),
                  Container(
                    width: 22,
                    height: 4 + 46 * ((vals[i] ?? 0) / maxV).clamp(0.0, 1.0),
                    decoration: BoxDecoration(
                        color: i == vals.length - 1 ? color : color.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(4)),
                  ),
                ]),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _stats(double? eff, double? tts, double? awak) {
    Widget tile(String label, String val) => Expanded(
          child: Card(
            color: _card,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(children: [
                Text(val, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _indigo)),
                const SizedBox(height: 4),
                Text(label, style: const TextStyle(fontSize: 10, color: _muted), textAlign: TextAlign.center),
              ]),
            ),
          ),
        );
    // IntrinsicHeight bounds the Row's height so `stretch` (equal-height cards) works
    // inside the scrolling ListView — without it the Row gets infinite height.
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        tile('Efficiency', eff != null ? '${eff.round()}%' : '—'),
        tile('To sleep', tts != null ? '${tts.round()}m' : '—'),
        tile('Awakenings', awak != null ? awak.round().toString() : '—'),
      ]),
    );
  }
}
