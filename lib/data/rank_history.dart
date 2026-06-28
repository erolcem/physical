// data/rank_history.dart — turns the metric-log history into rank-over-time series so
// you can graph your Overall rank + each category rank climbing through the tiers.
// Mirrors readiness.dart's backfill: compute per day, persist missing days as logs
// under pseudo-metric ids (overall_rank, strength_rank, …). Pure where it can be.
import '../engine/rank_engine.dart' as eng;
import '../engine/rank_engine.dart' show Log;
import 'metrics.dart';
import 'repository.dart';

String? _day(Log l) => l.ts.length >= 10 ? l.ts.substring(0, 10) : null;

/// Per-day rank value (0–9 tier scale) for the overall + each category that has data.
/// Keyed by series id ('overall_rank' | '{category}_rank') → { 'YYYY-MM-DD' → rankValue }.
Map<String, Map<String, double>> rankSeries(Map<String, List<Log>> logs) {
  final rankedIds = [for (final m in metrics) if (eng.standards.containsKey(m.id)) m.id];
  final days = <String>{};
  for (final id in rankedIds) {
    for (final l in (logs[id] ?? const <Log>[])) {
      final d = _day(l);
      if (d != null) days.add(d);
    }
  }
  final out = <String, Map<String, double>>{};
  for (final day in days.toList()..sort()) {
    final byCat = <String, List<Log>>{};
    for (final id in rankedIds) {
      // latest log of this metric on/before `day`
      Log? best;
      for (final l in (logs[id] ?? const <Log>[])) {
        final d = _day(l);
        if (d != null && d.compareTo(day) <= 0 && (best == null || l.ts.compareTo(best.ts) > 0)) {
          best = l;
        }
      }
      if (best == null) continue;
      final m = metricById(id);
      if (m.bodyweightScaled && best.bodyweight == null) continue; // can't score without bw
      (byCat[m.category] ??= []).add(best);
    }
    if (byCat.isEmpty) continue;
    (out['overall_rank'] ??= {})[day] = eng.overallByCategory(byCat).rankValue;
    byCat.forEach((cat, catLogs) {
      (out['${cat}_rank'] ??= {})[day] = eng.overall(catLogs).rankValue;
    });
  }
  return out;
}

/// Persist any missing rank-series logs so the ranks graph like other metrics.
/// Idempotent (skips days already logged per series). Returns how many were added.
int backfillRankLogs(Repository repo) {
  final logs = repo.loadLogs();
  var added = 0;
  rankSeries(logs).forEach((seriesId, byDay) {
    final have = {
      for (final l in (logs[seriesId] ?? const <Log>[]))
        if (l.ts.length >= 10) l.ts.substring(0, 10)
    };
    byDay.forEach((day, value) {
      if (have.contains(day)) return;
      repo.saveLog(seriesId, Log(seriesId, value, ts: '${day}T12:00:00'));
      added++;
    });
  });
  return added;
}
