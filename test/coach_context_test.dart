import 'package:flutter_test/flutter_test.dart';
import 'package:physical/data/coach_context.dart';
import 'package:physical/data/diet.dart';
import 'package:physical/data/habits.dart';
import 'package:physical/data/workout.dart';
import 'package:physical/engine/rank_engine.dart' show Log;

void main() {
  List<Log> series(String id, List<double> vals, {String from = '2026-06-10'}) {
    final base = DateTime.parse('${from}T08:00:00');
    return [for (var i = 0; i < vals.length; i++)
      Log(id, vals[i], ts: base.add(Duration(days: i)).toIso8601String())];
  }

  test('trendOf detects up/down/flat', () {
    expect(trendOf(series('x', [50, 55, 60, 65])), 'up');
    expect(trendOf(series('x', [65, 60, 55, 50])), 'down');
    expect(trendOf(series('x', [50, 50, 50, 50])), 'flat');
  });

  test('coachCorrelations finds strong day-aligned pairs, excludes rank series', () {
    final logs = {
      'hrv': series('hrv', [40, 45, 50, 55, 60, 65]),
      'sleep_score': series('sleep_score', [70, 74, 78, 82, 86, 90]), // co-moves with hrv
      'overall_rank': series('overall_rank', [1, 2, 3, 4, 5, 6]),     // excluded
    };
    final c = coachCorrelations(logs);
    expect(c.any((p) => {p['a'], p['b']}.containsAll({'hrv', 'sleep_score'})), isTrue);
    expect(c.any((p) => p['a'] == 'overall_rank' || p['b'] == 'overall_rank'), isFalse);
    expect((c.first['r'] as double).abs() >= 0.4, isTrue);
  });

  test('coachWorkoutSets exposes per-exercise sets + volume', () {
    const w = WorkoutSession(id: 'w', type: 'strength', start: '2026-06-28T18:00:00', sets: [
      WorkoutSet(name: 'Bench', mode: SetMode.weightReps, weight: 80, reps: 8),
      WorkoutSet(name: 'Bench', mode: SetMode.weightReps, weight: 80, reps: 7),
    ]);
    final out = coachWorkoutSets([w]);
    expect(out.first['exercises'][0]['name'], 'Bench');
    expect(out.first['exercises'][0]['sets'].length, 2);
    expect(out.first['exercises'][0]['volume'], (80 * 8 + 80 * 7));
  });

  test('coachHabits reports measured/met/adherence (evidence-only for auto habits)', () {
    final today = todayKey();
    final h = Habit(id: 'h', title: 'Protein', section: 'diet', verify: 'diet',
        goalKey: 'protein', target: 150, unit: 'g', createdAt: today);
    // A manual tick alone must NOT satisfy an auto habit — only real data does.
    final ticked = coachHabits([h], {'h': {today}}, logs: const {}, food: const [], workouts: const []);
    expect(ticked.first['met'], isFalse);
    // With food meeting the protein target, it's met from evidence.
    final met = coachHabits([h], const {},
        logs: const {},
        food: [FoodEntry(id: 'f', dateKey: today, name: 'meal', calories: 600, protein: 160)],
        workouts: const []);
    expect(met.first['title'], 'Protein');
    expect(met.first['target'], 150);
    expect(met.first['met'], isTrue);
    expect(met.first['adherence'], isNotNull);
  });

  test('coachInsights surfaces readiness, correlation, weak area, slipping habit', () {
    final ins = coachInsights(
      readiness: 48,
      correlations: [{'a': 'deep_sleep', 'b': 'bench', 'r': 0.61, 'n': 12}],
      ranks: {'categories': {
        'strength': {'tier': 'Gold', 'rank_value': 3.4},
        'recovery': {'tier': 'Silver', 'rank_value': 2.1},
      }},
      trends: {'sleep_score': {'direction': 'down', 'change': -7}},
      habits: [{'title': 'PM skincare', 'adherence': 40}],
    );
    final titles = ins.map((i) => i.title).toList();
    expect(titles, contains('Readiness 48'));
    expect(titles, contains('Pattern found'));
    expect(titles, contains('Weakest area'));
    expect(titles, contains('Slipping habit'));
    // weak area is the lowest rank_value category (recovery)
    expect(ins.firstWhere((i) => i.title == 'Weakest area').body.contains('recovery'), isTrue);
  });

  test('coachHistory returns downsampled per-metric series incl. background metrics', () {
    final base = DateTime(2026, 5, 1);
    final logs = {
      'bench': [for (var i = 0; i < 50; i++) Log('bench', 100 + i.toDouble(),
          bodyweight: 80, ts: base.add(Duration(days: i)).toIso8601String())],
      'steps': [for (var i = 0; i < 5; i++) Log('steps', 8000 + i * 100.0,
          ts: base.add(Duration(days: i)).toIso8601String())], // background metric
      'overall_rank': [Log('overall_rank', 3, ts: '2026-06-01T12:00:00')], // excluded
    };
    final h = coachHistory(logs, window: 365, maxPoints: 30);
    expect(h.containsKey('bench'), isTrue);
    expect(h.containsKey('steps'), isTrue, reason: 'background metrics included');
    expect(h.containsKey('overall_rank'), isFalse, reason: 'derived series excluded');
    expect(h['bench']!.length, lessThanOrEqualTo(30)); // downsampled
  });

  test('coachEnergy gives in/out series from food + sessions', () {
    final today = todayKey();
    final food = [FoodEntry(id: 'f', dateKey: today, name: 'meal', calories: 2200, protein: 150)];
    final e = coachEnergy(food, const [], weightKg: 80, heightCm: 180, age: 28, days: 7);
    expect((e['in'] as List).last, 2200);
    expect(e['out'], isNotNull);   // BMR + active
    expect(e['bmr'], isNotNull);
  });
}
