// data/habit_verify.dart — turns a habit's Table-2 target into a same-day measured
// value and a pass/fail, by reading the day's logs (metric / Google Health), food log
// (diet macros + diet-health), and workout sets (volume / named-lift sets). Kept apart
// from habits.dart so that file stays Flutter- and data-dependency-free.
import '../engine/rank_engine.dart' show Log;
import 'diet.dart';
import 'habits.dart';
import 'workout.dart';

/// The day's measured value for a habit's goal, or null if there's no data to judge.
/// - metric  : the day's last log of the linked metric (sleep_score, steps, hrv, plank…)
/// - diet    : the day's total for goalKey (protein|carbs|fat|fibre|calories|health|<axis>)
/// - workout : training volume that day, or sets of lifts whose name matches goalKey
double? habitMeasured(
  Habit h,
  String day, {
  required Map<String, List<Log>> logs,
  required List<FoodEntry> food,
  required List<WorkoutSession> workouts,
}) {
  switch (h.verify) {
    case 'metric':
      final id = h.linkedMetricId;
      if (id == null) return null;
      double? v;
      for (final l in (logs[id] ?? const <Log>[])) {
        if (l.ts.startsWith(day)) v = l.value; // last on the day wins
      }
      return v;
    case 'diet':
      final t = dietTotals(food, day);
      if (t.items == 0) return null;
      switch (h.goalKey) {
        case 'protein': return t.protein;
        case 'carbs': return t.carbs;
        case 'fat': return t.fat;
        case 'fibre': return t.fibre;
        case 'calories': return t.calories;
        case 'health': return t.healthScore;
        case null: return t.calories; // generic "log meals"
        default: return t.health[h.goalKey]; // a named diet-health axis
      }
    case 'workout':
      final day0 = [for (final w in workouts) if (w.dateKey == day) w];
      if (day0.isEmpty) return null;
      final filters = (h.goalKey ?? '')
          .split(',').map((s) => s.trim().toLowerCase()).where((s) => s.isNotEmpty).toList();
      if (h.unit == 'sets' && filters.isNotEmpty) {
        // Count sets of exercises whose name contains any filter term (e.g. chest lifts).
        var sets = 0;
        for (final w in day0) {
          for (final s in w.sets) {
            final n = s.name.toLowerCase();
            if (filters.any(n.contains)) sets++;
          }
        }
        return sets.toDouble();
      }
      // Otherwise total training volume that day (binary habits ignore the number).
      return day0.fold<double>(0.0, (a, w) => a + w.volume);
    default:
      return null; // manual
  }
}

/// Whether a habit counts as DONE on [day]. Auto-verifiable habits (metric/diet/workout)
/// can ONLY be earned from real data — a manual tick never satisfies them. Truly manual
/// habits (aesthetics/misc) are done when ticked.
bool habitDoneOn(
  Habit h,
  String day, {
  required Map<String, List<Log>> logs,
  required List<FoodEntry> food,
  required List<WorkoutSession> workouts,
  Set<String>? ticked,
}) {
  if (h.verify == 'manual') return ticked?.contains(day) ?? false;
  return habitGoalMet(h, day, logs: logs, food: food, workouts: workouts);
}

/// Is the habit's goal met on [day]? Target habits compare the measured value; binary
/// habits (no target / manual) pass when any corroborating data exists that day.
bool habitGoalMet(
  Habit h,
  String day, {
  required Map<String, List<Log>> logs,
  required List<FoodEntry> food,
  required List<WorkoutSession> workouts,
}) {
  if (h.verify == 'manual') return false; // nothing to corroborate
  final measured = habitMeasured(h, day, logs: logs, food: food, workouts: workouts);
  return meetsTarget(target: h.target, compare: h.compare, measured: measured);
}
