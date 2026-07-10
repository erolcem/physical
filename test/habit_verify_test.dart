import 'package:flutter_test/flutter_test.dart';
import 'package:physical/data/habits.dart';
import 'package:physical/data/habit_verify.dart';
import 'package:physical/data/diet.dart';
import 'package:physical/data/workout.dart';
import 'package:physical/engine/rank_engine.dart' show Log;

void main() {
  const day = '2026-06-28';
  Habit h(String section, String verify, {String? metric, double? target, String cmp = 'gte', String? goalKey, String unit = ''}) =>
      Habit(id: '$section-$verify-$goalKey', title: 't', section: section, verify: verify,
          linkedMetricId: metric, target: target, compare: cmp, goalKey: goalKey, unit: unit, createdAt: day);

  test('metric target ≥ verifies only when the day value meets it', () {
    final logs = {'sleep_score': [Log('sleep_score', 83, ts: '${day}T08:00:00')]};
    final pass = h('sleep', 'metric', metric: 'sleep_score', target: 80, unit: '/100');
    final fail = h('sleep', 'metric', metric: 'sleep_score', target: 90, unit: '/100');
    expect(habitGoalMet(pass, day, logs: logs, food: const [], workouts: const []), isTrue);
    expect(habitGoalMet(fail, day, logs: logs, food: const [], workouts: const []), isFalse);
  });

  test('diet protein target reads the day total', () {
    final food = [const FoodEntry(id: 'a', dateKey: day, name: 'x', calories: 500, protein: 90),
                  const FoodEntry(id: 'b', dateKey: day, name: 'y', calories: 400, protein: 80)];
    final p = h('diet', 'diet', goalKey: 'protein', target: 150, unit: 'g');
    expect(habitGoalMet(p, day, logs: const {}, food: food, workouts: const []), isTrue); // 170 ≥ 150
  });

  test('calories ≤ (cut) target', () {
    final food = [const FoodEntry(id: 'a', dateKey: day, name: 'x', calories: 1800)];
    final cut = h('diet', 'diet', goalKey: 'calories', cmp: 'lte', target: 2200, unit: 'kcal');
    expect(habitGoalMet(cut, day, logs: const {}, food: food, workouts: const []), isTrue);
  });

  test('strength named-lift sets count', () {
    final w = WorkoutSession(id: 'w', type: 'strength', start: '${day}T18:00:00', sets: [
      for (var i = 0; i < 14; i++)
        const WorkoutSet(name: 'Bench Press', mode: SetMode.weightReps, weight: 80, reps: 8),
    ]);
    final chest = h('exercise', 'workout', goalKey: 'bench,chest,press,fly', target: 12, unit: 'sets');
    expect(habitGoalMet(chest, day, logs: const {}, food: const [], workouts: [w]), isTrue); // 14 ≥ 12
  });

  test('binary (no target) workout passes on any session that day', () {
    const w = WorkoutSession(id: 'w', type: 'run', start: '${day}T07:00:00');
    final train = h('exercise', 'workout');
    expect(habitGoalMet(train, day, logs: const {}, food: const [], workouts: [w]), isTrue);
    expect(habitGoalMet(train, day, logs: const {}, food: const [], workouts: const []), isFalse);
  });

  test('meal identity: a breakfast log can NOT tick a Dinner habit', () {
    // The reported bug: "dinner got verified even though i didnt eat it yet
    // (i logged a breakfast meal)". Food now carries an eaten-at time and
    // meal-identity habits demand the right window.
    final breakfastOnly = [
      const FoodEntry(id: 'a', dateKey: day, name: 'eggs on toast',
          calories: 420, protein: 22, time: '07:40'),
    ];
    const dinner = Habit(id: 'dinner', title: 'Dinner', section: 'diet',
        verify: 'diet', createdAt: day);
    expect(habitGoalMet(dinner, day, logs: const {}, food: breakfastOnly, workouts: const []),
        isFalse);
    // An actual evening meal satisfies it.
    final withDinner = [
      ...breakfastOnly,
      const FoodEntry(id: 'b', dateKey: day, name: 'chicken and rice',
          calories: 700, protein: 45, time: '19:10'),
    ];
    expect(habitGoalMet(dinner, day, logs: const {}, food: withDinner, workouts: const []),
        isTrue);
    // A time-less entry can't prove a meal-specific habit…
    final noTime = [const FoodEntry(id: 'c', dateKey: day, name: 'meal', calories: 600)];
    expect(habitGoalMet(dinner, day, logs: const {}, food: noTime, workouts: const []),
        isFalse);
    // …but still satisfies a generic "log meals" habit.
    const logMeals = Habit(id: 'lm', title: 'Log all meals', section: 'diet',
        verify: 'diet', createdAt: day);
    expect(habitGoalMet(logMeals, day, logs: const {}, food: noTime, workouts: const []),
        isTrue);
  });

  test('meal identity: the habit\'s ideal time defines a ±3h window when unnamed', () {
    const evening = Habit(id: 'e', title: 'Eat clean', section: 'diet',
        verify: 'diet', time: '19:00', createdAt: day);
    final lunchOnly = [
      const FoodEntry(id: 'a', dateKey: day, name: 'salad', calories: 350, time: '12:30'),
    ];
    expect(habitGoalMet(evening, day, logs: const {}, food: lunchOnly, workouts: const []),
        isFalse); // 12:30 is outside 16:00–22:00
    final dinnerTime = [
      const FoodEntry(id: 'b', dateKey: day, name: 'salmon', calories: 600, time: '18:20'),
    ];
    expect(habitGoalMet(evening, day, logs: const {}, food: dinnerTime, workouts: const []),
        isTrue);
  });

  test('AI verdict is authoritative for no-target diet habits (meal identity), '
      'but never for exact target-diet habits', () {
    const dinner = Habit(id: 'dinner', title: 'Dinner', section: 'diet',
        verify: 'diet', createdAt: day);
    final food = [
      const FoodEntry(id: 'a', dateKey: day, name: 'eggs', calories: 420, time: '07:40'),
    ];
    // The verifier judged it done (e.g. user described a special schedule) → honoured.
    expect(habitDoneOn(dinner, day, logs: const {}, food: food, workouts: const [],
        aiVerdict: true), isTrue);
    expect(habitDoneOn(dinner, day, logs: const {}, food: food, workouts: const [],
        aiVerdict: false), isFalse);
    // A protein habit has an EXACT total — the rule wins even with a verdict.
    final protein = h('diet', 'diet', goalKey: 'protein', target: 150, unit: 'g');
    final rich = [const FoodEntry(id: 'b', dateKey: day, name: 'shake',
        calories: 900, protein: 160, time: '10:00')];
    expect(habitDoneOn(protein, day, logs: const {}, food: rich, workouts: const [],
        aiVerdict: false), isTrue); // 160 ≥ 150 — verdict can't unmeasure it
  });

  test('rank_log counts the day\'s manually-tested ranked logs only', () {
    final checkIn = h('misc', 'rank_log', unit: 'tests');
    // Nothing logged → no evidence, not done.
    expect(habitMeasured(checkIn, day, logs: const {}, food: const [], workouts: const []), isNull);
    expect(habitGoalMet(checkIn, day, logs: const {}, food: const [], workouts: const []), isFalse);
    // An auto-synced ranked metric (sleep score) does NOT count — it logs itself.
    final auto = {'sleep_score': [Log('sleep_score', 82, ts: '${day}T08:00:00')]};
    expect(habitGoalMet(checkIn, day, logs: auto, food: const [], workouts: const []), isFalse);
    // A real re-test (bench + plank) counts each distinct metric once.
    final tested = {
      'bench': [Log('bench', 100, bodyweight: 80, ts: '${day}T18:00:00')],
      'plank': [Log('plank', 150, ts: '${day}T18:30:00'),
                Log('plank', 160, ts: '${day}T18:40:00')],
      'sleep_score': [Log('sleep_score', 82, ts: '${day}T08:00:00')],
    };
    expect(habitMeasured(checkIn, day, logs: tested, food: const [], workouts: const []), 2.0);
    expect(habitGoalMet(checkIn, day, logs: tested, food: const [], workouts: const []), isTrue);
    // With a target ("re-test 3 metrics"), the count must reach it.
    final three = h('misc', 'rank_log', target: 3, unit: 'tests');
    expect(habitGoalMet(three, day, logs: tested, food: const [], workouts: const []), isFalse);
  });
}
