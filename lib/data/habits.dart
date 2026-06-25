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

// Mirrors the PDF Table 2 habit categories.
const Map<String, HabitCategory> habitCategories = {
  'strength': HabitCategory('strength', 'Strength', '💪', 0xFF4CE0C3),
  'performance': HabitCategory('performance', 'Performance', '⚡', 0xFF5B6AF8),
  'sleep': HabitCategory('sleep', 'Sleep', '😴', 0xFF8E8EFF),
  'diet': HabitCategory('diet', 'Diet', '🥗', 0xFFF6CF3E),
  'aesthetics': HabitCategory('aesthetics', 'Aesthetics', '✨', 0xFFE67BE6),
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

/// A Google Calendar "create event" URL for a timed daily habit — opens the
/// calendar pre-filled (a daily recurring event) so the user can add it in one
/// tap, the friction-reducing "calendar push" from the plan. Null if the habit
/// has no time (a calendar event needs one). Times are floating/local.
String? googleCalendarUrl(Habit h, {DateTime? now}) {
  if (h.time == null) return null;
  final parts = h.time!.split(':');
  final hh = int.tryParse(parts[0]) ?? 0;
  final mm = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
  final base = now ?? DateTime.now();
  final start = DateTime(base.year, base.month, base.day, hh, mm);
  final end = start.add(Duration(minutes: h.durationMins > 0 ? h.durationMins : 30));
  String p2(int n) => n.toString().padLeft(2, '0');
  String fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}${p2(d.month)}${p2(d.day)}T${p2(d.hour)}${p2(d.minute)}00';
  final params = {
    'action': 'TEMPLATE',
    'text': h.title,
    'dates': '${fmt(start)}/${fmt(end)}',
    'recur': 'RRULE:FREQ=DAILY',
    'details': 'Physical habit',
  };
  final query = params.entries
      .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
      .join('&');
  return 'https://calendar.google.com/calendar/render?$query';
}

/// The last [n] day-keys, oldest first, ending today.
List<String> lastNDays(int n, {DateTime? today}) {
  final t = today ?? DateTime.now();
  final base = DateTime(t.year, t.month, t.day);
  return [
    for (var i = n - 1; i >= 0; i--) dateKey(base.subtract(Duration(days: i)))
  ];
}

/// For each of the last [n] days (oldest first), how many of [habits] were ticked
/// — the data behind the weekly summary strip.
List<int> dailyDoneCounts(
    List<Habit> habits, Map<String, Set<String>> completions,
    {int n = 7, DateTime? today}) {
  return [
    for (final day in lastNDays(n, today: today))
      habits.where((h) => (completions[h.id] ?? const {}).contains(day)).length
  ];
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
