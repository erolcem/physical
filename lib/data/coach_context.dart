// data/coach_context.dart — the app computes the FULL analytical context for the AI
// coach (the app is authoritative: it holds every log + the canonical rank engine).
// Pure functions (no Flutter/Riverpod) so they're unit-tested: ranks, trends, day-aligned
// correlations, recent workout sets, and rich habit adherence. The coach screen passes in
// provider snapshots; the backend formats these into the prompt.
import 'correlation.dart' show alignByDay, pearson;
import 'habit_verify.dart';
import 'habits.dart';
import 'metrics.dart' show metricById, metrics, rankedCountByCategory;
import 'workout.dart';
import 'diet.dart' show FoodEntry, dietTotals, bmrMifflin;
import '../engine/rank_engine.dart' as eng;
import '../engine/rank_engine.dart' show Log, RankResult;

/// Downsampled daily history for EVERY logged metric (ranked AND background) over the last
/// [window] days, capped to [maxPoints] points each (evenly sampled, newest kept). Lets the
/// coach see the real data over time and find its own connections. Excludes the derived
/// rank pseudo-metrics (circular). Compact: {metricId: [oldest … newest]}.
Map<String, List<double>> coachHistory(Map<String, List<Log>> logs,
    {int window = 180, int maxPoints = 45}) {
  final cutoff = DateTime.now().subtract(Duration(days: window));
  final out = <String, List<double>>{};
  for (final e in logs.entries) {
    if (e.key.endsWith('_rank')) continue; // derived/circular
    final byDay = <String, double>{};
    for (final l in e.value) {
      final d = DateTime.tryParse(l.ts);
      if (d == null || d.isBefore(cutoff)) continue;
      if (l.ts.length >= 10) byDay[l.ts.substring(0, 10)] = l.value; // last per day
    }
    if (byDay.isEmpty) continue;
    final days = byDay.keys.toList()..sort();
    var vals = [for (final d in days) byDay[d]!];
    if (vals.length > maxPoints) {
      final step = vals.length / maxPoints;
      vals = [
        for (var i = 0; i < maxPoints - 1; i++) vals[(i * step).floor()],
        vals.last, // always keep the newest
      ];
    }
    out[e.key] = [for (final v in vals) double.parse(v.toStringAsFixed(2))];
  }
  return out;
}

/// Daily energy balance over the last [days] days: calories IN (food) and estimated
/// calories OUT (Mifflin BMR + active calories from sessions). Bodyweight is in history,
/// so the coach can relate intake/expenditure to weight change and adjust its advice.
Map<String, dynamic> coachEnergy(List<FoodEntry> entries, List<WorkoutSession> sessions,
    {double? weightKg, double? heightCm, int? age, int days = 30}) {
  final keys = lastNDays(days);
  final inSeries = [for (final d in keys) dietTotals(entries, d).calories.round()];
  if (inSeries.every((c) => c == 0)) return const {};
  final out = <String, dynamic>{'in': inSeries};
  if (weightKg != null && heightCm != null && age != null) {
    final bmr = bmrMifflin(weightKg, heightCm, age);
    out['out'] = [for (final d in keys) (bmr + activeCaloriesOn(sessions, d)).round()];
    out['bmr'] = bmr.round();
  }
  return out;
}

Map<String, dynamic> _rr(RankResult r) =>
    {'tier': r.tier, 'sub': r.sub, 'top_pct': r.topPct, 'rank_value': r.rankValue};

/// up / down / flat over a metric's recent history (last ~8 day-values).
String trendOf(List<Log>? logs) {
  if (logs == null || logs.length < 3) return 'flat';
  final byDay = <String, double>{};
  for (final l in logs) {
    if (l.ts.length >= 10) byDay[l.ts.substring(0, 10)] = l.value;
  }
  final days = byDay.keys.toList()..sort();
  if (days.length < 3) return 'flat';
  final vals = [for (final d in days) byDay[d]!];
  final recent = vals.length > 8 ? vals.sublist(vals.length - 8) : vals;
  final first = recent.first, last = recent.last;
  final mean = recent.reduce((a, b) => a + b) / recent.length;
  final thresh = (mean.abs()) * 0.03 + 1e-9; // 3% of level = meaningful
  if (last - first > thresh) return 'up';
  if (first - last > thresh) return 'down';
  return 'flat';
}

/// Overall + category + per-metric ranks with a trend arrow, from the rank engine.
Map<String, dynamic> coachRanks({
  required RankResult overall,
  required Map<String, RankResult> categories,
  required Map<String, Log> latest,
  required Map<String, List<Log>> logs,
}) {
  final out = <Map<String, dynamic>>[];
  for (final e in latest.entries) {
    if (!eng.standards.containsKey(e.key)) continue;
    try {
      final r = eng.scoreLog(e.value);
      out.add({
        'id': e.key,
        'label': metricById(e.key).label,
        'tier': r.tier,
        'sub': r.sub,
        'top_pct': r.topPct,
        'rank_value': r.rankValue,
        'value': e.value.value,
        'trend': trendOf(logs[e.key]),
      });
    } catch (_) {/* e.g. a strength log missing its bodyweight snapshot */}
  }
  // Coverage: how much of the ranked roster is actually logged. With "unrated = worst"
  // scoring, a low rank can mean UNTESTED rather than weak — the coach uses this to tell
  // the difference and to prioritise logging the gaps.
  final totals = rankedCountByCategory;
  final loggedByCat = <String, int>{};
  for (final m in out) {
    final cat = metricById(m['id'] as String).category;
    loggedByCat[cat] = (loggedByCat[cat] ?? 0) + 1;
  }
  final coverage = {
    for (final e in totals.entries)
      e.key: {'logged': loggedByCat[e.key] ?? 0, 'total': e.value}
  };
  final totalAll = totals.values.fold(0, (a, b) => a + b);
  final loggedAll = loggedByCat.values.fold(0, (a, b) => a + b);

  return {
    'overall': _rr(overall),
    'categories': {for (final e in categories.entries) e.key: _rr(e.value)},
    'metrics': out,
    'coverage': {'overall': {'logged': loggedAll, 'total': totalAll}, ...coverage},
  };
}

const _trendKeys = [
  'sleep_score', 'hrv', 'resting_hr', 'vo2max', 'body_fat_pct', 'bodyweight',
  'daily_readiness', 'overall_rank', 'sleep_duration', 'deep_sleep', 'steps',
];

/// Recent series + change + direction for the headline metrics, so the coach can
/// reason about patterns (improving / plateauing / regressing) over time.
Map<String, dynamic> coachTrends(Map<String, List<Log>> logs) {
  final out = <String, dynamic>{};
  for (final k in _trendKeys) {
    final ls = logs[k];
    if (ls == null || ls.length < 3) continue;
    final byDay = <String, double>{};
    for (final l in ls) {
      if (l.ts.length >= 10) byDay[l.ts.substring(0, 10)] = l.value;
    }
    final days = byDay.keys.toList()..sort();
    if (days.length < 3) continue;
    final vals = [for (final d in days) byDay[d]!];
    final recent = vals.length > 10 ? vals.sublist(vals.length - 10) : vals;
    final change = recent.last - recent.first;
    out[k] = {
      'recent': [for (final v in recent) double.parse(v.toStringAsFixed(2))],
      'change': double.parse(change.toStringAsFixed(2)),
      'direction': trendOf(ls),
    };
  }
  return out;
}

/// Day-aligned Pearson correlations across logged metrics, strongest first. Excludes the
/// derived rank/readiness pseudo-metrics (they'd be circular) and weak/low-overlap pairs.
List<Map<String, dynamic>> coachCorrelations(Map<String, List<Log>> logs,
    {double minAbsR = 0.4, int minOverlap = 5, int top = 20}) {
  final hidden = {for (final m in metrics) if (m.category == 'rank') m.id}
    ..addAll(['daily_readiness']);
  final ids = [
    for (final e in logs.entries)
      if (!hidden.contains(e.key) && e.value.length >= minOverlap) e.key
  ]..sort();
  final out = <Map<String, dynamic>>[];
  for (var i = 0; i < ids.length; i++) {
    for (var j = i + 1; j < ids.length; j++) {
      final (xs, ys) = alignByDay(logs[ids[i]]!, logs[ids[j]]!);
      if (xs.length < minOverlap) continue;
      final r = pearson(xs, ys);
      if (r.abs() < minAbsR) continue;
      out.add({'a': ids[i], 'b': ids[j], 'r': double.parse(r.toStringAsFixed(2)), 'n': xs.length});
    }
  }
  out.sort((a, b) => (b['r'] as double).abs().compareTo((a['r'] as double).abs()));
  return out.take(top).toList();
}

/// Recent sessions with their individual sets, so the coach can read weight×reps,
/// per-exercise volume, and progression.
List<Map<String, dynamic>> coachWorkoutSets(List<WorkoutSession> sessions, {int take = 10}) {
  final recent = sortedByRecent(sessions).take(take);
  return [
    for (final s in recent)
      {
        'date': s.dateKey,
        'type': s.type,
        'exercises': [
          for (final e in groupByExercise(s.sets).entries)
            {
              'name': e.key,
              'sets': [
                for (final st in e.value)
                  {
                    if (st.weight != null) 'w': st.weight,
                    if (st.reps != null) 'r': st.reps,
                    if (st.seconds != null) 's': st.seconds,
                  }
              ],
              'volume': e.value.fold<double>(0, (a, st) => a + st.volume).round(),
            }
        ],
      }
  ];
}

String _labelize(String id) {
  try {
    return metricById(id).label;
  } catch (_) {
    return id.replaceAll('_', ' ');
  }
}

/// Proactive, LLM-free insights for the coach home — surfaces the strongest correlation,
/// weakest category, today's readiness, a notable trend, and the slipping habit, each with
/// a ready prompt to dig in. Computed entirely from local data (instant + free + offline).
List<({String title, String body, String ask})> coachInsights({
  List<Map<String, dynamic>> correlations = const [],
  Map<String, dynamic>? ranks,
  Map<String, dynamic> trends = const {},
  List<Map<String, dynamic>> habits = const [],
  double? readiness,
}) {
  final out = <({String title, String body, String ask})>[];

  if (readiness != null) {
    final r = readiness.round();
    final label = r >= 65 ? 'ready to train' : (r >= 50 ? 'moderate' : 'low — prioritise recovery');
    out.add((title: 'Readiness $r', body: 'Recovery looks $label today.',
        ask: 'My readiness is $r today — how should I adjust training?'));
  }

  if (correlations.isNotEmpty) {
    final c = correlations.first;
    final r = c['r'] as double;
    final dir = r >= 0 ? 'rise together' : 'move oppositely';
    out.add((
      title: 'Pattern found',
      body: '${_labelize(c['a'])} & ${_labelize(c['b'])} $dir (r=${r.toStringAsFixed(2)}, ${c['n']}d).',
      ask: 'Explain the correlation between ${c['a']} and ${c['b']}, and whether it could be causal.'
    ));
  }

  final cats = (ranks?['categories'] as Map?)?.cast<String, dynamic>() ?? const {};
  if (cats.isNotEmpty) {
    String? weak;
    double lo = 1e9;
    cats.forEach((k, v) {
      final rv = (v as Map)['rank_value'];
      if (rv is num && rv < lo) {
        lo = rv.toDouble();
        weak = k;
      }
    });
    if (weak != null) {
      final tier = (cats[weak] as Map)['tier'];
      out.add((title: 'Weakest area', body: '$weak is your lowest category ($tier).',
          ask: 'My weakest category is $weak — what is the highest-leverage way to raise it?'));
    }
  }

  // The biggest meaningful recent move among the headline trends.
  String? tKey;
  double tMag = 0;
  trends.forEach((k, v) {
    if (v is Map && v['direction'] != 'flat') {
      final ch = (v['change'] as num?)?.abs().toDouble() ?? 0;
      if (ch > tMag) {
        tMag = ch;
        tKey = k;
      }
    }
  });
  if (tKey != null) {
    final t = trends[tKey] as Map;
    final ch = (t['change'] as num).toDouble();
    out.add((
      title: 'Trend',
      body: '${_labelize(tKey!)} ${ch >= 0 ? 'up' : 'down'} ${ch.abs().toStringAsFixed(1)} recently.',
      ask: 'My ${_labelize(tKey!)} is trending ${ch >= 0 ? 'up' : 'down'} — what does that mean and what next?'
    ));
  }

  // The habit slipping the most (lowest 30-day adherence).
  Map<String, dynamic>? slip;
  for (final h in habits) {
    final a = h['adherence'];
    if (a is num && (slip == null || a < (slip['adherence'] as num))) slip = h;
  }
  final slipping = slip;
  if (slipping != null && (slipping['adherence'] as num) < 70) {
    out.add((title: 'Slipping habit',
        body: '"${slipping['title']}" is at ${(slipping['adherence'] as num).round()}% this month.',
        ask: 'I keep missing "${slipping['title']}" — help me fix my adherence.'));
  }

  return out.take(5).toList();
}

/// Rich habit context: target, today's measured value + met, streak, 30-day adherence,
/// and the products used (for aesthetics reasoning). [aiVerdicts] (from the LLM
/// verification round) override the rule-based done-check per habit+day.
List<Map<String, dynamic>> coachHabits(
  List<Habit> habits,
  Map<String, Set<String>> completions, {
  required Map<String, List<Log>> logs,
  required List<FoodEntry> food,
  required List<WorkoutSession> workouts,
  Map<String, Map<String, bool>> aiVerdicts = const {},
  DateTime? today,
}) {
  final t = today ?? DateTime.now();
  final tkey = dateKey(t);
  final window = lastNDays(30, today: t);
  return [
    for (final h in habits)
      () {
        bool metOn(String day) => habitDoneOn(h, day,
            logs: logs, food: food, workouts: workouts, ticked: completions[h.id],
            aiVerdict: aiVerdicts[h.id]?[day]);
        final dueDays = [for (final d in window) if (isDueOn(h, DateTime.parse('${d}T12:00:00'))) d];
        final doneDays = {for (final d in window) if (metOn(d)) d};
        final adherence = dueDays.isEmpty
            ? null
            : (dueDays.where(doneDays.contains).length / dueDays.length * 100).round();
        return {
          'title': h.title,
          'section': h.section,
          if (h.target != null) 'target': h.target,
          if (h.target != null) 'compare': h.compare,
          if (h.unit.isNotEmpty) 'unit': h.unit,
          if (h.verify != 'manual')
            'measured': habitMeasured(h, tkey, logs: logs, food: food, workouts: workouts),
          'met': metOn(tkey),
          'streak': currentStreak(doneDays, today: t),
          if (adherence != null) 'adherence': adherence,
          if (h.products.isNotEmpty) 'products': h.products,
        };
      }()
  ];
}
