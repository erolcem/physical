// data/workout.dart — exercise SESSIONS (PDF Part 1 "Lifting exercise sets" → volume,
// plus general training). A session has a locked TYPE (Weightlifting/Run/…) + free-text
// title + optional duration/cardio, and contains SETS. Each set has a free-text
// exercise name and a locked MODE (weight×reps · reps · time · distance) with its
// values. Decoupled from ranks (lifts are logged separately for ranking). The
// cardioLoad/zoneMinutes fields are ready for Google session data if an endpoint
// surfaces. Pure model + logic, unit-tested.
import 'habits.dart' show lastNDays;

enum SetMode { weightReps, reps, time, distance }

extension SetModeX on SetMode {
  String get label => switch (this) {
        SetMode.weightReps => 'Weight × Reps',
        SetMode.reps => 'Reps',
        SetMode.time => 'Time',
        SetMode.distance => 'Distance',
      };
}

SetMode setModeFromId(String s) =>
    SetMode.values.firstWhere((m) => m.name == s, orElse: () => SetMode.weightReps);

// Locked session types (free-text title sits alongside).
const List<(String, String)> sessionTypes = [
  ('Weightlifting', '🏋'), ('Run', '🏃'), ('Walk', '🚶'), ('Cycle', '🚴'),
  ('Swim', '🏊'), ('Sport', '⚽'), ('Other', '✨'),
];

String typeEmoji(String type) =>
    sessionTypes.firstWhere((t) => t.$1 == type, orElse: () => ('', '🏋')).$2;

String fmtDuration(double seconds) {
  final t = seconds.round();
  final h = t ~/ 3600, m = (t % 3600) ~/ 60, s = t % 60;
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m${s > 0 ? ' ${s}s' : ''}';
  return '${s}s';
}

class WorkoutSet {
  final String name; // free text, e.g. "Chest Press"
  final SetMode mode;
  final double? weight; // kg (weightReps)
  final int? reps; // weightReps, reps
  final double? seconds; // time
  final double? distance; // km (distance)
  const WorkoutSet({required this.name, required this.mode,
      this.weight, this.reps, this.seconds, this.distance});

  /// Training volume — Σ weight×reps for lifting; 0 for non-weighted modes.
  double get volume =>
      (mode == SetMode.weightReps && weight != null && reps != null) ? weight! * reps! : 0.0;

  String get detail => switch (mode) {
        SetMode.weightReps =>
          '${_n(weight)} kg × ${reps ?? '?'}',
        SetMode.reps => '${reps ?? '?'} reps',
        SetMode.time => fmtDuration(seconds ?? 0),
        SetMode.distance => '${_n(distance)} km',
      };

  static String _n(double? v) => v == null
      ? '?'
      : (v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(v < 10 ? 2 : 1));

  Map<String, dynamic> toJson() => {
        'n': name, 'm': mode.name,
        if (weight != null) 'w': weight,
        if (reps != null) 'r': reps,
        if (seconds != null) 's': seconds,
        if (distance != null) 'd': distance,
      };

  factory WorkoutSet.fromJson(Map<String, dynamic> j) => WorkoutSet(
        // 'e' is a legacy exerciseId from the old fixed-lift model.
        name: (j['n'] ?? j['e'] ?? 'Exercise') as String,
        mode: setModeFromId(j['m'] as String? ?? 'weightReps'),
        weight: (j['w'] as num?)?.toDouble(),
        reps: (j['r'] as num?)?.toInt(),
        seconds: (j['s'] as num?)?.toDouble(),
        distance: (j['d'] as num?)?.toDouble(),
      );
}

class WorkoutSession {
  final String id;
  final String type; // one of sessionTypes
  final String? title; // free-text name
  final String start; // ISO datetime
  final int? durationMins;
  final List<WorkoutSet> sets;
  final double? cardioLoad; // calories-derived load (Google sessions)
  final int? zoneMinutes; // active zone minutes (Google sessions)
  final String source; // 'manual' | 'google'
  final String? googleId; // dedup key for imported Google sessions
  final Map<String, double> summary; // Google cardio summary: calories/distanceKm/steps/avgHr
  const WorkoutSession({
    required this.id, required this.type, this.title, required this.start,
    this.durationMins, this.sets = const [], this.cardioLoad, this.zoneMinutes,
    this.source = 'manual', this.googleId, this.summary = const {},
  });

  String get dateKey => start.length >= 10 ? start.substring(0, 10) : start;
  double get volume => sets.fold(0.0, (a, s) => a + s.volume);
  int get setCount => sets.length;
  Set<String> get exercises => {for (final s in sets) s.name};
  String get label => (title != null && title!.trim().isNotEmpty) ? title! : type;
  bool get fromGoogle => source == 'google';

  WorkoutSession copyWith({List<WorkoutSet>? sets, String? title, int? durationMins}) =>
      WorkoutSession(
        id: id, type: type, start: start,
        title: title ?? this.title,
        durationMins: durationMins ?? this.durationMins,
        sets: sets ?? this.sets,
        cardioLoad: cardioLoad, zoneMinutes: zoneMinutes,
        source: source, googleId: googleId, summary: summary,
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'type': type, if (title != null) 'title': title, 'start': start,
        if (durationMins != null) 'dur': durationMins,
        'sets': [for (final s in sets) s.toJson()],
        if (cardioLoad != null) 'cl': cardioLoad,
        if (zoneMinutes != null) 'zm': zoneMinutes,
        if (source != 'manual') 'src': source,
        if (googleId != null) 'gid': googleId,
        if (summary.isNotEmpty) 'sum': summary,
      };

  factory WorkoutSession.fromJson(Map<String, dynamic> j) => WorkoutSession(
        id: j['id'] as String,
        type: j['type'] as String? ?? 'Weightlifting',
        title: j['title'] as String?,
        // legacy sessions stored 'day' (a date-key) instead of a start datetime.
        start: (j['start'] ?? (j['day'] != null ? '${j['day']}T12:00:00' : DateTime.now().toIso8601String())) as String,
        durationMins: (j['dur'] as num?)?.toInt(),
        sets: [for (final s in (j['sets'] as List? ?? const [])) WorkoutSet.fromJson(s as Map<String, dynamic>)],
        cardioLoad: (j['cl'] as num?)?.toDouble(),
        zoneMinutes: (j['zm'] as num?)?.toInt(),
        source: j['src'] as String? ?? 'manual',
        googleId: j['gid'] as String?,
        summary: {
          for (final e in ((j['sum'] as Map?) ?? const {}).entries)
            e.key as String: (e.value as num).toDouble()
        },
      );

  /// Build a session from a parsed Google `exercise` dataPoint (see backend
  /// /integrations/google/exercises). Imported sessions are read-only at the top
  /// level; the user can still log sets into them.
  factory WorkoutSession.fromGoogle(Map<String, dynamic> g) => WorkoutSession(
        id: 'g:${g['google_id']}',
        type: (g['type'] as String?) ?? 'Other',
        title: g['display_name'] as String?,
        start: (g['start'] as String?) ?? DateTime.now().toIso8601String(),
        durationMins: (g['duration_mins'] as num?)?.toInt(),
        cardioLoad: (g['calories'] as num?)?.toDouble(),
        zoneMinutes: (g['zone_minutes'] as num?)?.toInt(),
        source: 'google',
        googleId: g['google_id'] as String?,
        summary: {
          for (final k in ['calories', 'distance_km', 'steps', 'avg_hr'])
            if (g[k] != null) k: (g[k] as num).toDouble(),
        },
      );
}

/// Sessions most-recent first (by start datetime).
List<WorkoutSession> sortedByRecent(List<WorkoutSession> sessions) =>
    [...sessions]..sort((a, b) => b.start.compareTo(a.start));

/// Group sets under their exercise name, preserving first-seen order.
Map<String, List<WorkoutSet>> groupByExercise(List<WorkoutSet> sets) {
  final m = <String, List<WorkoutSet>>{};
  for (final s in sets) {
    (m[s.name] ??= []).add(s);
  }
  return m;
}

/// Total training volume across sessions in the last [days] days.
double volumeOverDays(List<WorkoutSession> sessions, {int days = 7, DateTime? today}) {
  final window = lastNDays(days, today: today).toSet();
  return sessions.where((s) => window.contains(s.dateKey)).fold(0.0, (a, s) => a + s.volume);
}

/// Training volume per day over the last [days] days, oldest→newest.
List<double> volumePerDay(List<WorkoutSession> sessions, {int days = 7, DateTime? today}) {
  final byDay = <String, double>{};
  for (final s in sessions) {
    byDay[s.dateKey] = (byDay[s.dateKey] ?? 0) + s.volume;
  }
  return [for (final d in lastNDays(days, today: today)) byDay[d] ?? 0.0];
}

/// Distinct exercise names trained in the last [days] days.
Set<String> exercisesOverDays(List<WorkoutSession> sessions, {int days = 7, DateTime? today}) {
  final window = lastNDays(days, today: today).toSet();
  return {for (final s in sessions) if (window.contains(s.dateKey)) ...s.exercises};
}

int sessionsOverDays(List<WorkoutSession> sessions, {int days = 7, DateTime? today}) {
  final window = lastNDays(days, today: today).toSet();
  return sessions.where((s) => window.contains(s.dateKey)).length;
}
