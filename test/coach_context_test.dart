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
    // STRICT: a manual tick alone must NOT satisfy an auto habit — only real data.
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
    // Pattern memory: the last 14 due days ride along as a ✓/×/– string.
    expect((met.first['recent_days'] as String).length, 14);
    expect(met.first['recent_days'], endsWith('✓')); // today, met from evidence
  });

  test('coachHabits remembers ARCHIVED habits: past roster + lifetime adherence '
      '(deleting a habit never erases the coach\'s memory of it)', () {
    final now = DateTime.now();
    String iso(int daysAgo) =>
        now.subtract(Duration(days: daysAgo)).toIso8601String();
    final old = Habit(
        id: 'old', title: 'Morning run', section: 'exercise', verify: 'manual',
        createdAt: iso(30), archivedAt: iso(10));
    // Ticked on 15 of its ~20 active days.
    final ticks = {for (var d = 11; d < 26; d++) dateKey(now.subtract(Duration(days: d)))};
    final out = coachHabits([old], {'old': ticks},
        logs: const {}, food: const [], workouts: const []);
    final e = out.single;
    expect(e['archived'], isTrue);
    expect(e['archived_on'], (old.archivedAt as String).substring(0, 10));
    expect(e['lifetime_due_days'], 20); // created ≤ d < archived
    expect(e['lifetime_done_days'], 15);
    expect(e['lifetime_adherence'], 75);
    // Archived entries carry no active-only fields (met/streak/recent_days).
    expect(e.containsKey('met'), isFalse);
    expect(e.containsKey('recent_days'), isFalse);
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

  // ── coachQueryResult: the coach's mid-chat query_history lookups, answered
  // entirely from on-device data. ──
  group('coachQueryResult', () {
    Map<String, dynamic> run(Map<String, dynamic> args,
            {List<Habit> habits = const [],
            Map<String, Set<String>> completions = const {},
            Map<String, List<Log>> logs = const {},
            List<FoodEntry> food = const [],
            List<WorkoutSession> workouts = const [],
            DateTime? today}) =>
        coachQueryResult(args,
            habits: habits, completions: completions, logs: logs,
            food: food, workouts: workouts,
            today: today ?? DateTime.parse('2026-07-10T12:00:00'));

    test('metric: full-resolution daily values within the range, last per day', () {
      final logs = {
        'bench': [
          Log('bench', 95, ts: '2026-02-28T10:00:00'),  // before range
          Log('bench', 100, ts: '2026-03-02T09:00:00'),
          Log('bench', 98, ts: '2026-03-02T18:00:00'),  // same day → last wins
          Log('bench', 105, ts: '2026-03-20T10:00:00'),
          Log('bench', 110, ts: '2026-04-05T10:00:00'), // after range
        ],
      };
      final r = run({'topic': 'metric', 'id': 'bench',
                     'start': '2026-03-01', 'end': '2026-03-31'}, logs: logs);
      expect(r['days'], {'2026-03-02': 98.0, '2026-03-20': 105.0});
      expect(r.containsKey('note'), isFalse);
    });

    test('metric: unknown id answers with the real logged metric ids', () {
      final r = run({'topic': 'metric', 'id': 'benchpress',
                     'start': '2026-03-01', 'end': '2026-03-31'},
          logs: {'bench': [Log('bench', 100, ts: '2026-03-02T09:00:00')]});
      expect(r['note'], contains('benchpress'));
      expect(r['logged_metrics'], ['bench']);
    });

    test('habit: day-by-day ✓/× with adherence — archived habits included', () {
      const h = Habit(id: 'run', title: 'Morning run', section: 'exercise',
          verify: 'manual', createdAt: '2026-03-01T08:00:00',
          archivedAt: '2026-03-11T08:00:00');
      final ticks = {'run': {'2026-03-02', '2026-03-04', '2026-03-05'}};
      final r = run({'topic': 'habit', 'id': 'morning RUN',
                     'start': '2026-03-01', 'end': '2026-03-31'},
          habits: [h], completions: ticks);
      // Active window is created ≤ day < archived → due 1st..10th only.
      expect(r['title'], 'Morning run');
      expect(r['archived'], isTrue);
      expect(r['due'], 10);
      expect(r['done'], 3);
      expect(r['adherence'], 30);
      expect((r['days'] as Map)['2026-03-02'], '✓');
      expect((r['days'] as Map)['2026-03-03'], '×');
      expect((r['days'] as Map).containsKey('2026-03-11'), isFalse);
    });

    test('habit: unknown title answers with the real habit titles', () {
      const h = Habit(id: 'x', title: 'Stretch', section: 'recovery',
          verify: 'manual', createdAt: '2026-01-01T08:00:00');
      final r = run({'topic': 'habit', 'id': 'Yoga',
                     'start': '2026-03-01', 'end': '2026-03-31'}, habits: [h]);
      expect(r['note'], contains('Yoga'));
      expect(r['known_habits'], ['Stretch']);
    });

    test('meals: grouped per day with eaten-at times, range-filtered', () {
      final food = [
        const FoodEntry(id: 'a', dateKey: '2026-03-02', name: 'Oats', calories: 420,
            protein: 38, time: '08:10'),
        const FoodEntry(id: 'b', dateKey: '2026-03-02', name: 'Chicken rice',
            calories: 650, protein: 45),
        const FoodEntry(id: 'c', dateKey: '2026-05-01', name: 'Pizza', calories: 900,
            protein: 30), // outside range
      ];
      final r = run({'topic': 'meals', 'start': '2026-03-01', 'end': '2026-03-31'},
          food: food);
      final day = (r['days'] as Map)['2026-03-02'] as List;
      expect(day.length, 2);
      expect(day.first['t'], '08:10');
      expect(day.first['n'], 'Oats');
      expect((r['days'] as Map).containsKey('2026-05-01'), isFalse);
    });

    test('workouts: sessions in range with per-exercise set counts + volume', () {
      const w = WorkoutSession(id: 'w', type: 'strength',
          start: '2026-03-05T18:00:00', sets: [
            WorkoutSet(name: 'Bench', mode: SetMode.weightReps, weight: 80, reps: 8),
            WorkoutSet(name: 'Bench', mode: SetMode.weightReps, weight: 80, reps: 7),
          ]);
      const later = WorkoutSession(id: 'x', type: 'run', start: '2026-06-01T18:00:00');
      final r = run({'topic': 'workouts', 'start': '2026-03-01', 'end': '2026-03-31'},
          workouts: [w, later]);
      final sessions = r['sessions'] as List;
      expect(sessions.length, 1);
      expect(sessions.first['type'], 'strength');
      expect(sessions.first['exercises'].first['name'], 'Bench');
      expect(sessions.first['exercises'].first['sets'], 2);
      expect(sessions.first['exercises'].first['volume'], 80 * 8 + 80 * 7);
    });

    test('guards: reversed ranges swap, future ends clamp to today, bad topics/dates error', () {
      final logs = {'hrv': [Log('hrv', 55, ts: '2026-07-09T08:00:00')]};
      final swapped = run({'topic': 'metric', 'id': 'hrv',
                           'start': '2026-07-09', 'end': '2026-07-01'}, logs: logs);
      expect(swapped['start'], '2026-07-01');
      expect(swapped['days'], {'2026-07-09': 55.0});
      final future = run({'topic': 'metric', 'id': 'hrv',
                          'start': '2026-07-01', 'end': '2027-01-01'}, logs: logs);
      expect(future['end'], '2026-07-10'); // clamped to "today"
      expect(run({'topic': 'teleport', 'start': '2026-07-01', 'end': '2026-07-02'})['error'],
          contains('unknown topic'));
      expect(run({'topic': 'metric', 'id': 'hrv', 'start': 'March'})['error'],
          contains('YYYY-MM-DD'));
    });
  });
}
