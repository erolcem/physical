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
}
