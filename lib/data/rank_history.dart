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
    // Full-roster scoring (unlogged = worst), matching the displayed overall/category ranks.
    final totals = rankedCountByCategory;
    (out['overall_rank'] ??= {})[day] = eng.overallByCategoryFull(byCat, totals).rankValue;
    byCat.forEach((cat, catLogs) {
      (out['${cat}_rank'] ??= {})[day] =
          eng.overallFull(catLogs, totals[cat] ?? catLogs.length).rankValue;
    });
  }
  return out;
}

/// Persist the rank-series logs so the ranks graph like other metrics. LIVE, not
/// frozen: a day whose recomputed rank differs from the stored one (because
/// underlying logs were added, revised or deleted) is REPLACED in place — the
/// rank history always reflects the current data. Returns how many days were
/// added or updated.
int backfillRankLogs(Repository repo) {
  final logs = repo.loadLogs();
  var changed = 0;
  rankSeries(logs).forEach((seriesId, byDay) {
    final list = logs[seriesId] ?? const <Log>[];
    final idxByDay = <String, int>{};
    for (var i = 0; i < list.length; i++) {
      if (list[i].ts.length >= 10) idxByDay[list[i].ts.substring(0, 10)] = i;
    }
    byDay.forEach((day, value) {
      final i = idxByDay[day];
      if (i == null) {
        repo.saveLog(seriesId, Log(seriesId, value, ts: '${day}T12:00:00'));
        changed++;
      } else if ((list[i].value - value).abs() > 1e-6) {
        repo.replaceLog(seriesId, i, Log(seriesId, value, ts: list[i].ts));
        changed++;
      }
    });
  });
  return changed;
}

/// The derived, fully recomputable series (rank history + readiness).
const List<String> derivedSeriesIds = [
  'overall_rank', 'strength_rank', 'performance_rank', 'recovery_rank',
  'aesthetics_rank', 'daily_readiness',
];

/// Wipe the derived rank/readiness history so it rebuilds purely from whatever
/// data exists NOW (the owner's "reset ranks" — deleting data used to leave the
/// old category-rank climb behind). Purges without tombstones (the series
/// re-backfills at the same timestamps), then recomputes immediately.
/// Returns how many day-points were rebuilt. Caller reloads providers.
int resetDerivedHistory(Repository repo,
    {int Function(Repository)? readinessBackfill}) {
  for (final id in derivedSeriesIds) {
    repo.purgeMetricLogs(id);
  }
  final readiness = readinessBackfill?.call(repo) ?? 0;
  return readiness + backfillRankLogs(repo);
}
