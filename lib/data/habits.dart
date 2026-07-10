import '../engine/rank_engine.dart' show Log;

// data/habits.dart — the Habits layer (Phase 2), redesigned to be SCAFFOLDED:
// a habit lives in a SECTION (sleep/exercise/diet/aesthetics/recovery/misc), is
// usually a PRESET from that section's menu (so data checks stay in-realm and the
// AI can reason), but the title can be lightly customised (bounded free text).
// Verification is automatic from the user's logs per the habit's `verify` mode:
//   metric  → a same-day log of a linked metric (e.g. sleep_score)
//   workout → any workout session that day
//   diet    → any food logged that day
//   manual  → ticked only (e.g. skincare)
// Habits have an ideal time + duration and a daily/weekly cadence. Pure model +
// logic, no Flutter/Riverpod, so it's fully unit-tested.

// ── Sections (the scaffolds) ──────────────────────────────────────────────
class HabitSection {
  final String id;
  final String label;
  final String emoji;
  final int color; // ARGB (kept as int so this file stays Flutter-free)
  final String verify; // default verification mode for the section
  const HabitSection(this.id, this.label, this.emoji, this.color, this.verify);
}

const Map<String, HabitSection> habitSections = {
  'sleep': HabitSection('sleep', 'Sleep', '😴', 0xFF8E8EFF, 'metric'),
  'exercise': HabitSection('exercise', 'Exercise', '💪', 0xFF4CE0C3, 'workout'),
  'diet': HabitSection('diet', 'Diet', '🥗', 0xFFF6CF3E, 'diet'),
  'aesthetics': HabitSection('aesthetics', 'Aesthetics', '✨', 0xFFE67BE6, 'manual'),
  'recovery': HabitSection('recovery', 'Recovery', '🫀', 0xFF5B6AF8, 'metric'),
  'misc': HabitSection('misc', 'Misc', '⚙️', 0xFFC28A67, 'manual'),
};

HabitSection sectionOf(String id) =>
    habitSections[id] ?? habitSections['misc']!;

// Back-compat alias for older call sites that used categories.
HabitSection categoryOf(String id) => sectionOf(id);
const Map<String, HabitSection> habitCategories = habitSections;
typedef HabitCategory = HabitSection;

// ── Presets (the in-realm menu per section) ───────────────────────────────
class HabitPreset {
  final String section;
  final String title;
  final String verify; // metric|workout|diet|manual
  final String? linkedMetricId; // when verify == 'metric'
  final double? target; // default Table-2 target (editable in the UI)
  final String compare;
  final String? goalKey;
  final String unit;
  const HabitPreset(this.section, this.title, this.verify,
      {this.linkedMetricId, this.target, this.compare = 'gte', this.goalKey, this.unit = ''});
}

const List<HabitPreset> habitPresets = [
  // ── sleep — verified against the night's sleep data (auto-synced) ──
  HabitPreset('sleep', 'Sleep score', 'metric', linkedMetricId: 'sleep_score', target: 80, unit: '/100'),
  HabitPreset('sleep', 'Sleep duration', 'metric', linkedMetricId: 'sleep_duration', target: 8, unit: 'h'),
  HabitPreset('sleep', 'Deep sleep', 'metric', linkedMetricId: 'deep_sleep', target: 90, unit: 'min'),
  HabitPreset('sleep', 'REM sleep', 'metric', linkedMetricId: 'rem_sleep', target: 90, unit: 'min'),
  HabitPreset('sleep', 'In bed by', 'metric', linkedMetricId: 'sleep_schedule', compare: 'lte', target: 23, unit: 'h'),
  HabitPreset('sleep', 'Fewer interruptions', 'metric', linkedMetricId: 'sleep_interruptions', compare: 'lte', target: 2, unit: 'count'),
  HabitPreset('sleep', 'No screens before bed', 'manual'),
  // ── strength — from the day's workout sets (volume / intensity / named lift) ──
  HabitPreset('exercise', 'Train', 'workout'),
  HabitPreset('exercise', 'Training volume', 'workout', target: 8000, unit: 'vol'),
  HabitPreset('exercise', 'Chest sets', 'workout', goalKey: 'bench,chest,press,fly', target: 12, unit: 'sets'),
  HabitPreset('exercise', 'Back sets', 'workout', goalKey: 'row,pull,lat,deadlift', target: 12, unit: 'sets'),
  HabitPreset('exercise', 'Leg sets', 'workout', goalKey: 'squat,leg,lunge,calf,rdl', target: 12, unit: 'sets'),
  HabitPreset('exercise', 'Arm sets', 'workout', goalKey: 'curl,tricep,skull', target: 8, unit: 'sets'),
  HabitPreset('exercise', 'Shoulder sets', 'workout', goalKey: 'ohp,overhead,lateral,raise', target: 9, unit: 'sets'),
  // ── performance — endurance / mobility / cardio / explosiveness + activity ──
  HabitPreset('exercise', 'Steps', 'metric', linkedMetricId: 'steps', target: 8000, unit: 'steps'),
  HabitPreset('exercise', 'Active zone minutes', 'metric', linkedMetricId: 'active_zone', target: 30, unit: 'min'),
  HabitPreset('exercise', 'Plank hold', 'metric', linkedMetricId: 'plank', target: 120, unit: 's'),
  HabitPreset('exercise', '5k pace', 'metric', linkedMetricId: 'run5k_kmh', target: 10, unit: 'km/h'),
  HabitPreset('exercise', 'Vertical jump', 'metric', linkedMetricId: 'vert', target: 50, unit: 'cm'),
  HabitPreset('exercise', 'Hamstring mobility', 'metric', linkedMetricId: 'hamstring_mobility', target: 10, unit: 'cm'),
  HabitPreset('exercise', 'Cardio session', 'workout'),
  HabitPreset('exercise', 'Mobility / stretch', 'manual'),
  // ── diet — from the day's food log (macros + diet-health) + body composition ──
  HabitPreset('diet', 'Protein', 'diet', goalKey: 'protein', target: 150, unit: 'g'),
  HabitPreset('diet', 'Calories (cut)', 'diet', goalKey: 'calories', compare: 'lte', target: 2200, unit: 'kcal'),
  HabitPreset('diet', 'Calories (bulk)', 'diet', goalKey: 'calories', target: 2800, unit: 'kcal'),
  HabitPreset('diet', 'Fibre', 'diet', goalKey: 'fibre', target: 30, unit: 'g'),
  HabitPreset('diet', 'Diet-health score', 'diet', goalKey: 'health', target: 60, unit: '/100'),
  HabitPreset('diet', 'Micronutrient score', 'diet', goalKey: 'micronutrients', target: 60, unit: '/100'),
  HabitPreset('diet', 'Gut-health score', 'diet', goalKey: 'gut_health', target: 60, unit: '/100'),
  HabitPreset('diet', 'Bodyweight target', 'metric', linkedMetricId: 'bodyweight', compare: 'lte', target: 80, unit: 'kg'),
  HabitPreset('diet', 'Body fat', 'metric', linkedMetricId: 'body_fat_pct', compare: 'lte', target: 15, unit: '%'),
  HabitPreset('diet', 'Log all meals', 'diet'),
  // ── aesthetics — manual care routines (record products used) + measurement reminders ──
  HabitPreset('aesthetics', 'Skincare (AM)', 'manual'),
  HabitPreset('aesthetics', 'Skincare (PM)', 'manual'),
  HabitPreset('aesthetics', 'Sunscreen', 'manual'),
  HabitPreset('aesthetics', 'Oral care', 'manual'),
  HabitPreset('aesthetics', 'Hair care', 'manual'),
  HabitPreset('aesthetics', 'Eye rest (20-20-20)', 'manual'),
  HabitPreset('aesthetics', 'Vocal warm-up', 'manual'),
  HabitPreset('aesthetics', 'Measure skin', 'metric', linkedMetricId: 'skin'),
  HabitPreset('aesthetics', 'Measure hair', 'metric', linkedMetricId: 'hair'),
  HabitPreset('aesthetics', 'Hearing test', 'metric', linkedMetricId: 'ear'),
  // ── recovery ──
  HabitPreset('recovery', 'Meditate', 'manual'),
  HabitPreset('recovery', 'Breathwork', 'manual'),
  HabitPreset('recovery', 'Cold shower', 'manual'),
  HabitPreset('recovery', 'Morning sunlight', 'manual'),
  HabitPreset('recovery', 'HRV', 'metric', linkedMetricId: 'hrv', target: 50, unit: 'ms'),
  HabitPreset('recovery', 'Resting HR', 'metric', linkedMetricId: 'resting_hr', compare: 'lte', target: 60, unit: 'bpm'),
  // ── diet — measurement reminders ──
  HabitPreset('diet', 'Morning weigh-in', 'metric', linkedMetricId: 'bodyweight'),
  // ── misc — rank upkeep + manual to-dos worth tracking ──
  // Rank check-in: done when ≥1 manually-tested RANKED metric (a lift, a jump,
  // plank, 5k…) got a fresh log that day — the reminder that keeps ranks live.
  HabitPreset('misc', 'Rank check-in', 'rank_log', unit: 'tests'),
  HabitPreset('misc', 'Journaling', 'manual'),
  HabitPreset('misc', 'Posture check', 'manual'),
  HabitPreset('misc', 'Ab vacuum', 'manual'),
  HabitPreset('misc', 'Shave / trim', 'manual'),
  HabitPreset('misc', 'Read', 'manual'),
];

List<HabitPreset> presetsFor(String section) =>
    [for (final p in habitPresets) if (p.section == section) p];

// ── The habit ──────────────────────────────────────────────────────────────
class Habit {
  final String id;
  final String title;
  final String section; // sleep|exercise|diet|aesthetics|recovery|misc
  final String verify; // metric|workout|diet|manual
  final String? linkedMetricId; // when verify == 'metric'
  // Quantitative target (Table 2): the day's measured value must satisfy it to verify.
  // null target → binary (any relevant log that day corroborates, e.g. a routine done).
  final double? target;
  final String compare; // 'gte' (≥, default) | 'lte' (≤, e.g. calories/body-fat)
  final String? goalKey; // diet field (protein/calories/…), or an exercise-name filter
  final String unit; // display unit for the target (g, kcal, sets, /100, …)
  // Free-text context for the AI verifier + coach: what SPECIFICALLY counts.
  // e.g. "Evening makiwara punching session, 20+ min, heart rate up" so a random
  // afternoon walk can't tick it. Applies to every category.
  final String description;
  final List<String> products; // aesthetics: products/items used in this routine
  // Exercise habits can CARRY THEIR WORKOUT PLAN: the id of a WorkoutTemplate
  // (exercises + sets). On a due day the habit offers a one-tap "start" that
  // pre-fills a session from the plan — the habit is the plan, the log is what
  // actually happened, and the AI verifier judges the two against each other.
  final String? templateId;
  final String? time; // ideal time 'HH:MM' (drives calendar + reminder)
  final int durationMins;
  final double cost; // money per occurrence (the planner/budgeter angle)
  final String cadence; // 'daily' | 'weekly'
  final List<int> days; // weekly: weekday ints 1..7 (Mon..Sun); empty = all
  final String createdAt; // ISO-8601

  const Habit({
    required this.id,
    required this.title,
    this.section = 'misc',
    this.verify = 'manual',
    this.linkedMetricId,
    this.target,
    this.compare = 'gte',
    this.goalKey,
    this.unit = '',
    this.description = '',
    this.products = const [],
    this.templateId,
    this.time,
    this.durationMins = 0,
    this.cost = 0,
    this.cadence = 'daily',
    this.days = const [],
    required this.createdAt,
  });

  /// Roughly how many times this habit recurs in a 30-day month.
  double get occurrencesPerMonth => cadence == 'weekly' && days.isNotEmpty
      ? days.length * (30 / 7)
      : 30;

  // The section drives the card colour/emoji; alias kept for old call sites.
  String get category => section;

  /// Human-readable target, e.g. "≥ 80", "≤ 2200 kcal", or '' when binary.
  String get targetLabel => target == null
      ? ''
      : '${compare == 'lte' ? '≤' : '≥'} ${target! == target!.roundToDouble() ? target!.round() : target}${unit.isEmpty ? '' : (unit.startsWith('/') ? unit : ' $unit')}';

  Map<String, dynamic> toJson() => {
        'id': id, 'title': title, 'cat': section, 'verify': verify,
        'metric': linkedMetricId,
        if (target != null) 'target': target,
        if (compare != 'gte') 'cmp': compare,
        if (goalKey != null) 'goalKey': goalKey,
        if (unit.isNotEmpty) 'unit': unit,
        if (description.isNotEmpty) 'desc': description,
        if (products.isNotEmpty) 'products': products,
        if (templateId != null) 'tpl': templateId,
        'time': time, 'dur': durationMins,
        if (cost > 0) 'cost': cost,
        'cadence': cadence, 'days': days, 'created': createdAt,
      };

  factory Habit.fromJson(Map<String, dynamic> j) {
    final section = j['cat'] as String? ?? 'misc';
    return Habit(
      id: j['id'] as String,
      title: j['title'] as String,
      section: habitSections.containsKey(section) ? section : 'misc',
      verify: j['verify'] as String? ?? sectionOf(section).verify,
      linkedMetricId: j['metric'] as String?,
      target: (j['target'] as num?)?.toDouble(),
      compare: j['cmp'] as String? ?? 'gte',
      goalKey: j['goalKey'] as String?,
      unit: j['unit'] as String? ?? '',
      description: j['desc'] as String? ?? '',
      products: [for (final p in (j['products'] as List? ?? const [])) p as String],
      templateId: j['tpl'] as String?,
      time: j['time'] as String?,
      durationMins: (j['dur'] as num?)?.toInt() ?? 0,
      cost: (j['cost'] as num?)?.toDouble() ?? 0,
      cadence: j['cadence'] as String? ?? 'daily',
      days: [for (final d in (j['days'] as List? ?? const [])) (d as num).toInt()],
      createdAt: j['created'] as String? ?? DateTime.now().toIso8601String(),
    );
  }
}

/// Does a measured value satisfy a target? No target → any measurement corroborates.
bool meetsTarget({double? target, String compare = 'gte', double? measured}) {
  if (target == null) return measured != null;
  if (measured == null) return false;
  return compare == 'lte' ? measured <= target : measured >= target;
}

/// Verification state of a habit for a day.
enum HabitStatus { notDone, manual, verified }

const List<String> weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Local YYYY-MM-DD key for a date.
String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String todayKey() => dateKey(DateTime.now());

/// Whether a habit is scheduled on a given date (daily, or a chosen weekday).
bool isDueOn(Habit h, DateTime date) =>
    h.cadence != 'weekly' || h.days.isEmpty || h.days.contains(date.weekday);

bool isDueToday(Habit h, {DateTime? today}) => isDueOn(h, today ?? DateTime.now());

/// The habit's creation DATE-KEY (YYYY-MM-DD), or null if unparseable.
String? _createdKey(Habit h) {
  final d = DateTime.tryParse(h.createdAt);
  return d == null ? null : dateKey(d);
}

/// Whether a habit was ACTIVE and due on [date]: scheduled that day AND on or
/// after the day it was created. Days before creation are not "missed" — the
/// habit didn't exist yet — so adherence, streaks and the heatmap must not
/// count them (a brand-new weekly habit otherwise shows weeks of false red).
bool isDueAndActive(Habit h, DateTime date) {
  if (!isDueOn(h, date)) return false;
  final created = _createdKey(h);
  return created == null || dateKey(date).compareTo(created) >= 0;
}

/// Two-step verification: a ticked habit is [verified] when its `verify` rule is
/// corroborated by the day's data, else [manual]; untouched is [notDone].
HabitStatus statusFor(Habit h,
    {required bool doneToday, required bool corroborated}) {
  if (!doneToday) return HabitStatus.notDone;
  if (h.verify != 'manual' && corroborated) return HabitStatus.verified;
  return HabitStatus.manual;
}

/// Is the habit's verify rule corroborated by the day's data? Pure + testable.
/// Works for both manual logs AND auto-synced Google Health logs — both are `Log`s
/// carrying a same-day `ts` (e.g. a synced sleep_score sample), so a metric habit
/// like "Sleep 8h" verifies straight off the auto-collected data.
bool corroboratedOn(Habit h, String day, {
  required Map<String, List<Log>> logs,
  required Set<String> workoutDays, // dateKeys with a workout session
  required Set<String> foodDays, // dateKeys with a food entry
}) {
  switch (h.verify) {
    case 'metric':
      final ls = h.linkedMetricId == null ? null : logs[h.linkedMetricId];
      return ls != null && ls.any((l) => l.ts.startsWith(day));
    case 'workout':
      return workoutDays.contains(day);
    case 'diet':
      return foodDays.contains(day);
    default:
      return false;
  }
}

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

/// Streak counted over the habit's DUE days only: a weekly Mon/Thu habit builds
/// its streak in Mon/Thu steps (non-due days are skipped, not "missed").
/// Counting raw calendar days froze every weekly habit's streak at 0–1 forever.
/// An unchecked TODAY doesn't break the run (the day isn't over); an unchecked
/// past due day does. [horizon] caps the walk (match the caller's done-window).
int dueStreak(Habit h, Set<String> done, {DateTime? today, int horizon = 366}) {
  final t = today ?? DateTime.now();
  var d = DateTime(t.year, t.month, t.day);
  final todayK = dateKey(d);
  final created = _createdKey(h);
  var streak = 0;
  for (var i = 0; i < horizon; i++) {
    final key = dateKey(d);
    // Stop at the habit's creation day — earlier due days never existed.
    if (created != null && key.compareTo(created) < 0) break;
    if (isDueOn(h, d)) {
      if (done.contains(key)) {
        streak++;
      } else if (key != todayK) {
        break;
      }
    }
    d = d.subtract(const Duration(days: 1));
  }
  return streak;
}

/// A Google Calendar "create event" URL for a timed habit — opens it pre-filled
/// (daily, or weekly on the chosen days). Null if the habit has no ideal time.
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
  const byDay = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
  final rule = (h.cadence == 'weekly' && h.days.isNotEmpty)
      ? 'RRULE:FREQ=WEEKLY;BYDAY=${h.days.map((d) => byDay[d - 1]).join(',')}'
      : 'RRULE:FREQ=DAILY';
  final params = {
    'action': 'TEMPLATE',
    'text': h.title,
    'dates': '${fmt(start)}/${fmt(end)}',
    'recur': rule,
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

/// The last logged value on each of the last [n] days (oldest→newest), or null
/// for days with no log — for per-domain metric trends (e.g. nightly sleep score).
List<double?> valuesLastNDays(List<Log> logs, {int n = 7, DateTime? today}) {
  final byDay = <String, double>{};
  for (final l in logs) {
    if (l.ts.length >= 10) byDay[l.ts.substring(0, 10)] = l.value; // last wins
  }
  return [for (final d in lastNDays(n, today: today)) byDay[d]];
}

/// For each of the last [n] days (oldest first), how many of [habits] were ticked.
List<int> dailyDoneCounts(
    List<Habit> habits, Map<String, Set<String>> completions,
    {int n = 7, DateTime? today}) {
  return [
    for (final day in lastNDays(n, today: today))
      habits.where((h) => (completions[h.id] ?? const {}).contains(day)).length
  ];
}

/// Total scheduled minutes per day across habits (the budget rollup).
int minutesPerDay(List<Habit> habits) =>
    habits.fold<int>(0, (s, h) => s + h.durationMins);

/// Planner/budgeter rollup: scheduled minutes + money per 30-day month.
class HabitBudget {
  final int minutesPerMonth;
  final double costPerMonth;
  const HabitBudget(this.minutesPerMonth, this.costPerMonth);
  double get hoursPerMonth => minutesPerMonth / 60.0;
}

HabitBudget monthlyBudget(List<Habit> habits) {
  var mins = 0.0, cost = 0.0;
  for (final h in habits) {
    mins += h.durationMins * h.occurrencesPerMonth;
    cost += h.cost * h.occurrencesPerMonth;
  }
  return HabitBudget(mins.round(), cost);
}

/// Habits-per-hour across a 24h day (index 0..23) — the planner's density bar.
List<int> hourDensity(List<Habit> habits) {
  final d = List<int>.filled(24, 0);
  for (final h in habits) {
    final t = h.time;
    if (t == null) continue;
    final hh = int.tryParse(t.split(':').first);
    if (hh != null && hh >= 0 && hh < 24) d[hh]++;
  }
  return d;
}
