// data/habits.dart — the Habits accountability layer (Phase 2). A daily check-off
// model with streaks and optional two-step verification: a check-off is "verified"
// when it's corroborated by a same-day log of a linked metric (e.g. ticking
// "Train" alongside a logged lift). Pure model + logic, no Flutter/Riverpod, so it
// is fully unit-tested; storage lives behind Repository like everything else.

/// A habit the user commits to (daily cadence for now).
class Habit {
  final String id;
  final String title;
  final String? linkedMetricId; // optional: a same-day log of this metric verifies the tick
  final String createdAt; // ISO-8601

  const Habit(
      {required this.id,
      required this.title,
      this.linkedMetricId,
      required this.createdAt});

  Map<String, dynamic> toJson() =>
      {'id': id, 'title': title, 'metric': linkedMetricId, 'created': createdAt};

  factory Habit.fromJson(Map<String, dynamic> j) => Habit(
        id: j['id'] as String,
        title: j['title'] as String,
        linkedMetricId: j['metric'] as String?,
        createdAt: j['created'] as String? ?? DateTime.now().toIso8601String(),
      );
}

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
