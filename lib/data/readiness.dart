// data/readiness.dart — Daily Readiness (PDF Part 1 "Activity & Vitals" headline).
//
// Mirrors Fitbit's model: recovery signals (HRV + resting HR + sleep) tempered by
// recent training load. Each recovery signal is scored 0–1 by a HYBRID baseline —
// the user's own trailing-7-day average once there's a week of history (a personal
// z-score, like Fitbit), else the engine's population percentile. Grounded in the
// same rank engine the ranks use. Pure + unit-tested.
import 'dart:math' as math;
import '../engine/rank_engine.dart' as eng;
import '../engine/rank_engine.dart' show Log;
import 'habits.dart' show lastNDays;
import 'repository.dart';
import 'workout.dart';

// 0–1 "goodness" for a recovery metric. Personal baseline (today vs trailing-7 mean,
// direction-aware) once ≥7 prior readings exist; otherwise the population percentile.
double _goodness(String metricId, List<Log> unsorted, {required bool higherBetter}) {
  // Sort by time — logs can be stored out of order (e.g. after a sync/merge), and the
  // personal baseline depends on "today vs the trailing 7" being chronological.
  final logs = [...unsorted]..sort((a, b) => a.ts.compareTo(b.ts));
  final latest = logs.last.value;
  final prior = logs.length > 7 ? logs.sublist(logs.length - 8, logs.length - 1) : null;
  if (prior != null && prior.length >= 7) {
    final vals = [for (final l in prior) l.value];
    final mean = vals.reduce((a, b) => a + b) / vals.length;
    final variance = vals.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / vals.length;
    final sd = math.sqrt(variance);
    final z = sd > 1e-9 ? (latest - mean) / sd : 0.0;
    final dirZ = higherBetter ? z : -z;
    return (0.5 + dirZ / 4).clamp(0.0, 1.0); // ±2 SD spans 0..1
  }
  return eng.percentile(metricId, latest); // population, direction-aware
}

/// Recent training load over the last [days] days — active zone-minutes + duration +
/// a lifting-volume proxy. Hard recent training tempers readiness (you need recovery).
double recentTrainingLoad(List<WorkoutSession> sessions, {int days = 2, DateTime? today}) {
  final window = lastNDays(days, today: today).toSet();
  var load = 0.0;
  for (final s in sessions) {
    if (!window.contains(s.dateKey)) continue;
    load += (s.zoneMinutes ?? 0).toDouble();
    load += (s.durationMins ?? 0) * 0.5;
    load += s.volume / 200.0;
  }
  return load;
}

/// Daily Readiness (0–100), or null if there's no recovery data. Weights: HRV 35%,
/// sleep 25%, resting-HR 20%, recovery-from-load 20% (re-normalised over whatever
/// signals are present).
double? dailyReadiness(Map<String, List<Log>> logs, List<WorkoutSession> sessions,
    {DateTime? today}) {
  final parts = <(double, double)>[]; // (weight, value 0..1)
  final hrv = logs['hrv'] ?? const <Log>[];
  final sleep = logs['sleep_score'] ?? const <Log>[];
  final rhr = logs['resting_hr'] ?? const <Log>[];
  if (hrv.isNotEmpty) parts.add((0.35, _goodness('hrv', hrv, higherBetter: true)));
  if (sleep.isNotEmpty) parts.add((0.25, _goodness('sleep_score', sleep, higherBetter: true)));
  if (rhr.isNotEmpty) parts.add((0.20, _goodness('resting_hr', rhr, higherBetter: false)));
  if (parts.isEmpty) return null;
  final load = recentTrainingLoad(sessions, today: today);
  parts.add((0.20, 1 - (load / 120).clamp(0.0, 1.0)));
  final wsum = parts.fold(0.0, (a, p) => a + p.$1);
  final score = parts.fold(0.0, (a, p) => a + p.$1 * p.$2) / wsum;
  return (score * 100).clamp(0.0, 100.0);
}

/// Daily Readiness per calendar day across history — each day scored from the
/// recovery readings up to that day — so the metric can be graphed over time.
Map<String, double> readinessSeries(
    Map<String, List<Log>> logs, List<WorkoutSession> sessions) {
  String? d(Log l) => l.ts.length >= 10 ? l.ts.substring(0, 10) : null;
  final days = <String>{};
  for (final id in const ['hrv', 'sleep_score', 'resting_hr']) {
    for (final l in (logs[id] ?? const <Log>[])) {
      final day = d(l);
      if (day != null) days.add(day);
    }
  }
  final out = <String, double>{};
  for (final day in days.toList()..sort()) {
    final upto = <String, List<Log>>{};
    for (final id in const ['hrv', 'sleep_score', 'resting_hr']) {
      final list = [
        for (final l in (logs[id] ?? const <Log>[]))
          if ((d(l) ?? '9').compareTo(day) <= 0) l
      ];
      if (list.isNotEmpty) upto[id] = list;
    }
    final r = dailyReadiness(upto, sessions, today: DateTime.tryParse(day));
    if (r != null) out[day] = r;
  }
  return out;
}

/// Persist the daily_readiness logs so the metric graphs like the rest. LIVE:
/// a day whose recomputed score differs from the stored one (recovery data can
/// arrive or be revised after the day was first scored) is REPLACED in place.
/// Returns how many days were added or updated.
int backfillReadinessLogs(Repository repo) {
  final logs = repo.loadLogs();
  final list = logs['daily_readiness'] ?? const <Log>[];
  final idxByDay = <String, int>{};
  for (var i = 0; i < list.length; i++) {
    if (list[i].ts.length >= 10) idxByDay[list[i].ts.substring(0, 10)] = i;
  }
  var changed = 0;
  readinessSeries(logs, repo.loadWorkouts()).forEach((day, val) {
    final i = idxByDay[day];
    if (i == null) {
      repo.saveLog('daily_readiness', Log('daily_readiness', val, ts: '${day}T12:00:00'));
      changed++;
    } else if ((list[i].value - val).abs() > 0.5) { // re-log only a meaningful shift
      repo.replaceLog('daily_readiness', i, Log('daily_readiness', val, ts: list[i].ts));
      changed++;
    }
  });
  return changed;
}

/// Traffic-light colour for readiness (green = ready … red = rest). NOT the tier
/// palette — high readiness should read as "go", not Titan-red.
int readinessColorValue(double r) => r >= 65
    ? 0xFF4CE0C3 // teal — ready
    : r >= 50
        ? 0xFFF6CF3E // amber — moderate
        : r >= 35
            ? 0xFFF8A55B // orange — take it easy
            : 0xFFFA3737; // red — rest

/// A short readiness label.
String readinessLabel(double r) => r >= 80
    ? 'Primed'
    : r >= 65
        ? 'Ready'
        : r >= 50
            ? 'Moderate'
            : r >= 35
                ? 'Take it easy'
                : 'Rest';
