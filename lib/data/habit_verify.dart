// data/habit_verify.dart — turns a habit's Table-2 target into a same-day measured
// value and a pass/fail, by reading the day's logs (metric / Google Health), food log
// (diet macros + diet-health), and workout sets (volume / named-lift sets). Kept apart
// from habits.dart so that file stays Flutter- and data-dependency-free.
import '../engine/rank_engine.dart' show Log;
import 'diet.dart';
import 'habits.dart';
import 'metrics.dart' show rankedMetrics;
import 'workout.dart';

/// The day's measured value for a habit's goal, or null if there's no data to judge.
/// - metric  : the day's last log of the linked metric (sleep_score, steps, hrv, plank…)
/// - diet    : the day's total for goalKey (protein|carbs|fat|fibre|calories|health|<axis>)
/// - workout : training volume that day, or sets of lifts whose name matches goalKey
/// - rank_log: distinct manually-tested RANKED metrics logged that day (rank upkeep)
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
    case 'rank_log':
      // Rank upkeep: how many manually-tested ranked metrics got a fresh log
      // this day. Auto-synced ranked metrics (sleep score) are excluded — they
      // log themselves and would self-complete the reminder.
      var n = 0;
      for (final m in rankedMetrics) {
        if (m.autoSync) continue;
        if ((logs[m.id] ?? const <Log>[]).any((l) => l.ts.startsWith(day))) n++;
      }
      return n == 0 ? null : n.toDouble();
    default:
      return null; // manual
  }
}

/// Whether a habit counts as DONE on [day]. STRICT by design (the owner's
/// accountability principle): a data-verifiable habit (metric/diet/workout)
/// counts ONLY from real evidence — a watch session with real heart-rate data,
/// logged sets, a synced food total. A manual tick can never satisfy it; that's
/// what keeps the AI's picture of the day honest. Inherently manual habits
/// (brush teeth, journaling) are tick-only, as they should be.
///
/// [aiVerdict] is the LLM verifier's judgement for this habit+day. It is
/// authoritative for the habits where the rule is genuinely ambiguous:
/// - WORKOUT habits (which session counts for which habit; does a custom
///   activity like "evening makiwara" match; evidence-exclusivity so one
///   session can't tick two);
/// - NO-TARGET DIET habits (meal identity: "Dinner" needs an evening meal —
///   the rule's only signal was "some food was logged today", which let a
///   breakfast entry tick a Dinner habit).
/// For metric/rank_log/target-diet habits the measured value is DETERMINISTIC
/// and computed exactly (a protein total, a diet-health score, a sleep reading
/// vs its target), so the exact rule wins — an LLM can't recompute those and
/// must not override them (and can't reach a legacy verdict left on a
/// since-edited habit).
bool habitDoneOn(
  Habit h,
  String day, {
  required Map<String, List<Log>> logs,
  required List<FoodEntry> food,
  required List<WorkoutSession> workouts,
  Set<String>? ticked,
  bool? aiVerdict,
}) {
  if (h.verify == 'manual') return ticked?.contains(day) ?? false;
  final aiAuthoritative =
      h.verify == 'workout' || (h.verify == 'diet' && h.target == null);
  if (aiAuthoritative && aiVerdict != null) return aiVerdict;
  return habitGoalMet(h, day, logs: logs, food: food, workouts: workouts);
}

/// Minutes since midnight for 'HH:MM', or null.
int? _mins(String? hhmm) {
  if (hhmm == null || hhmm.length < 4 || !hhmm.contains(':')) return null;
  final parts = hhmm.split(':');
  final h = int.tryParse(parts[0]), m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}

/// The meal window (minutes since midnight) a meal-identity habit demands, or
/// null when the habit is generic ("Log all meals"). Named meals win; else the
/// habit's ideal time defines a ±3h window.
(int, int)? mealWindowFor(Habit h) {
  final text = '${h.title} ${h.description}'.toLowerCase();
  if (text.contains('breakfast')) return (4 * 60, 11 * 60);
  if (text.contains('lunch')) return (11 * 60, 16 * 60);
  if (text.contains('dinner') || text.contains('supper')) return (16 * 60 + 30, 23 * 60 + 59);
  final t = _mins(h.time);
  if (t != null) return (t - 180, t + 180);
  return null;
}

/// Deterministic meal-identity check — the OFFLINE fallback behind the AI
/// verdict: a "Dinner" habit needs a food entry actually eaten in dinner's
/// window, not just "some food today" (a breakfast log used to tick it).
/// Entries without a time can only satisfy generic eating habits.
bool mealIdentityMet(Habit h, String day, List<FoodEntry> food) {
  final entries = entriesFor(food, day);
  if (entries.isEmpty) return false;
  final window = mealWindowFor(h);
  if (window == null) return true; // generic "log meals" — any entry counts
  for (final f in entries) {
    final t = _mins(f.time);
    if (t != null && t >= window.$1 && t <= window.$2) return true;
  }
  return false;
}

/// Is the habit's goal met on [day]? Target habits compare the measured value; binary
/// habits (no target / manual) pass when any corroborating data exists that day —
/// except meal-identity diet habits, which also need the right TIME of day.
bool habitGoalMet(
  Habit h,
  String day, {
  required Map<String, List<Log>> logs,
  required List<FoodEntry> food,
  required List<WorkoutSession> workouts,
}) {
  if (h.verify == 'manual') return false; // nothing to corroborate
  if (h.verify == 'diet' && h.target == null) return mealIdentityMet(h, day, food);
  final measured = habitMeasured(h, day, logs: logs, food: food, workouts: workouts);
  return meetsTarget(target: h.target, compare: h.compare, measured: measured);
}
