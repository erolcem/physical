// data/habits.dart — the Habits layer (Phase 2). Reconciles two things the design
// doc wants together: the prototype's planner/budgeter (category, time, duration,
// monthly $/time rollup, a 24h density bar) AND an accountability layer (daily
// check-off, streaks, and two-step verification — a tick corroborated by a
// same-day log of a linked metric). Pure model + logic, no Flutter/Riverpod, so it
// is fully unit-tested; storage lives behind Repository like everything else.

/// A habit the user commits to (daily cadence for now).
class Habit {
  final String id;
  final String title;
  final String category; // 'fitness' | 'sleep' | 'diet' | 'other'
  final String? time; // 'HH:MM' (local), or null if untimed
  final int durationMins; // 0 if unset
  final double costPerMonth; // 0 if unset
  final String? linkedMetricId; // a same-day log of this metric verifies the tick
  final String createdAt; // ISO-8601

  const Habit({
    required this.id,
    required this.title,
    this.category = 'other',
    this.time,
    this.durationMins = 0,
    this.costPerMonth = 0,
    this.linkedMetricId,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'cat': category,
        'time': time,
        'dur': durationMins,
        'cost': costPerMonth,
        'metric': linkedMetricId,
        'created': createdAt,
      };

  // Tolerant of habits saved before the planner fields existed (they default).
  factory Habit.fromJson(Map<String, dynamic> j) => Habit(
        id: j['id'] as String,
        title: j['title'] as String,
        category: j['cat'] as String? ?? 'other',
        time: j['time'] as String?,
        durationMins: (j['dur'] as num?)?.toInt() ?? 0,
        costPerMonth: (j['cost'] as num?)?.toDouble() ?? 0,
        linkedMetricId: j['metric'] as String?,
        createdAt: j['created'] as String? ?? DateTime.now().toIso8601String(),
      );
}

/// Planner category — label, emoji, and an ARGB colour (kept as an int so this
/// file stays Flutter-free; the UI wraps it in a Color).
class HabitCategory {
  final String id;
  final String label;
  final String emoji;
  final int color;
  const HabitCategory(this.id, this.label, this.emoji, this.color);
}

const Map<String, HabitCategory> habitCategories = {
  'fitness': HabitCategory('fitness', 'Fitness', '💪', 0xFF4CE0C3),
  'sleep': HabitCategory('sleep', 'Sleep', '😴', 0xFF8E8EFF),
  'diet': HabitCategory('diet', 'Diet', '🥗', 0xFFF6CF3E),
  'other': HabitCategory('other', 'Other', '⚙️', 0xFFC28A67),
};

HabitCategory categoryOf(String id) =>
    habitCategories[id] ?? habitCategories['other']!;

/// Verification state of a habit for a given day.
enum HabitStatus { notDone, manual, verified }

/// Local YYYY-MM-DD key for a date.
String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String todayKey() => dateKey(DateTime.now());

/// Consecutive completed days ending today — or yesterday if today isn't ticked
/// yet, so an unchecked "today" doesn't read as a broken streak before day's end.
int currentStreak(Set<String> done, {DateTime? today}) {
  final t = today ?? DateTime.now();
  var d = DateTime(t.year, t.month, t.day);
  if (!done.contains(dateKey(d))) d = d.subtract(const Duration(days: 1));
  var streak = 0;
  while (done.contains(dateKey(d))) {
    streak++;
    d = d.subtract(const Duration(days: 1));
  }
  return streak;
}

/// Two-step verification rule: a ticked habit is [verified] when it has a linked
/// metric and that metric was logged the same day, else [manual]; untouched is
/// [notDone].
HabitStatus statusFor(Habit h,
    {required bool doneToday, required bool hasLinkedLogToday}) {
  if (!doneToday) return HabitStatus.notDone;
  if (h.linkedMetricId != null && hasLinkedLogToday) return HabitStatus.verified;
  return HabitStatus.manual;
}

/// Budgeter rollup across all (daily-cadence) habits.
class HabitPlan {
  final int minutesPerDay;
  final int minutesPerMonth; // minutesPerDay × 30
  final double costPerMonth;
  final double pctOfMonth; // share of a 24h × 30-day month spent on habits

  const HabitPlan(
      this.minutesPerDay, this.minutesPerMonth, this.costPerMonth, this.pctOfMonth);
}

HabitPlan planFor(List<Habit> habits) {
  final perDay = habits.fold<int>(0, (s, h) => s + h.durationMins);
  final perMonth = perDay * 30;
  final cost = habits.fold<double>(0, (s, h) => s + h.costPerMonth);
  const minutesInMonth = 24 * 30 * 60; // 43,200
  return HabitPlan(perDay, perMonth, cost, perMonth / minutesInMonth * 100);
}

/// One of the 48 half-hour slots of the day: which category occupies it (last
/// writer wins for colour) and how many habits overlap there.
class DaySlot {
  final String? categoryId;
  final int overlap;
  const DaySlot(this.categoryId, this.overlap);
}

/// A 24h occupancy map (48 × 30-min slots) from habits that have a time+duration.
List<DaySlot> densitySlots(List<Habit> habits) {
  const slotCount = 48;
  var slots = List<DaySlot>.filled(slotCount, const DaySlot(null, 0));
  for (final h in habits) {
    if (h.time == null || h.durationMins <= 0) continue;
    final parts = h.time!.split(':');
    final hh = int.tryParse(parts[0]) ?? 0;
    final mm = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    final start = ((hh * 60 + mm) / 30).floor();
    final durSlots = (h.durationMins / 30).ceil();
    for (var i = 0; i < durSlots; i++) {
      final s = (start + i) % slotCount;
      slots[s] = DaySlot(slots[s].categoryId ?? h.category, slots[s].overlap + 1);
    }
  }
  return slots;
}
