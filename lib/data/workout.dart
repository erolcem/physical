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

  /// An unfilled slot — a planned set with no values yet (from a template). You
  /// tap it in the session to log what you actually did.
  bool get isBlank => weight == null && reps == null && seconds == null && distance == null;

  /// A value-stripped copy — the structure only (name + mode), for templates.
  WorkoutSet blankCopy() => WorkoutSet(name: name, mode: mode);

  /// Same logged values (name/mode/numbers) — the fallback identity when the
  /// exact instance is gone (e.g. the holder absorbed into its watch parent
  /// while an edit dialog was open). Identical duplicate sets are
  /// indistinguishable anyway, so matching the first equal one is safe.
  bool sameValues(WorkoutSet o) =>
      name == o.name && mode == o.mode && weight == o.weight &&
      reps == o.reps && seconds == o.seconds && distance == o.distance;

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
  // The PDF's two-step verification: a manual set-logging session is only REAL
  // once a watch-tracked Google exercise covers the same window. Auto-linked on
  // import/sync (linkSessionsToWatch); unlinked manual sessions read as
  // "unverified" and the AI verifier won't credit exercise habits from them.
  final String? linkedGoogleId;
  final Map<String, double> summary; // Google cardio summary: calories/distanceKm/steps/avgHr
  // Ids of manual set-holders this watch session absorbed — the paper trail that
  // lets an open detail screen re-bind to the parent when its holder merges away.
  final List<String> absorbedIds;
  const WorkoutSession({
    required this.id, required this.type, this.title, required this.start,
    this.durationMins, this.sets = const [], this.cardioLoad, this.zoneMinutes,
    this.source = 'manual', this.googleId, this.linkedGoogleId,
    this.summary = const {}, this.absorbedIds = const [],
  });

  String get dateKey => start.length >= 10 ? start.substring(0, 10) : start;
  double get volume => sets.fold(0.0, (a, s) => a + s.volume);
  int get setCount => sets.length;
  Set<String> get exercises => {for (final s in sets) s.name};
  String get label => (title != null && title!.trim().isNotEmpty) ? title! : type;
  bool get fromGoogle => source == 'google';

  /// Anchored to a real tracked exercise: either it IS the watch session, or a
  /// watch session covering the same window has been linked to it.
  bool get watchVerified => fromGoogle || linkedGoogleId != null;

  WorkoutSession copyWith(
          {List<WorkoutSet>? sets, String? title, int? durationMins,
          String? linkedGoogleId, List<String>? absorbedIds}) =>
      WorkoutSession(
        id: id, type: type, start: start,
        title: title ?? this.title,
        durationMins: durationMins ?? this.durationMins,
        sets: sets ?? this.sets,
        cardioLoad: cardioLoad, zoneMinutes: zoneMinutes,
        source: source, googleId: googleId,
        linkedGoogleId: linkedGoogleId ?? this.linkedGoogleId,
        summary: summary,
        absorbedIds: absorbedIds ?? this.absorbedIds,
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'type': type, if (title != null) 'title': title, 'start': start,
        if (durationMins != null) 'dur': durationMins,
        'sets': [for (final s in sets) s.toJson()],
        if (cardioLoad != null) 'cl': cardioLoad,
        if (zoneMinutes != null) 'zm': zoneMinutes,
        if (source != 'manual') 'src': source,
        if (googleId != null) 'gid': googleId,
        if (linkedGoogleId != null) 'lgid': linkedGoogleId,
        if (summary.isNotEmpty) 'sum': summary,
        if (absorbedIds.isNotEmpty) 'abs': absorbedIds,
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
        linkedGoogleId: j['lgid'] as String?,
        summary: {
          for (final e in ((j['sum'] as Map?) ?? const {}).entries)
            e.key as String: (e.value as num).toDouble()
        },
        absorbedIds: [for (final a in (j['abs'] as List? ?? const [])) a as String],
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
        cardioLoad: (g['cardio_load'] as num?)?.toDouble(),
        zoneMinutes: (g['zone_minutes'] as num?)?.toInt(),
        source: 'google',
        googleId: g['google_id'] as String?,
        summary: {
          for (final k in ['calories', 'distance_km', 'steps', 'avg_hr'])
            if (g[k] != null) k: (g[k] as num).toDouble(),
        },
      );
}

// ── Workout templates (Hevy-style fast logging) ────────────────────────────
// A template saves a workout's exercises + sets (with their last-used weights/
// reps) under a name, so starting "Push day" pre-fills every set instead of
// retyping them. Saved from any session; starting from a template creates a new
// session seeded with the template's sets.
class WorkoutTemplate {
  final String id;
  final String name;
  final String type; // one of sessionTypes
  final List<WorkoutSet> sets;
  const WorkoutTemplate({
    required this.id,
    required this.name,
    this.type = 'Weightlifting',
    this.sets = const [],
  });

  int get setCount => sets.length;
  Set<String> get exercises => {for (final s in sets) s.name};

  /// The template's structure as EMPTY set slots (name + mode, no values) — what
  /// gets dropped into a session so you fill in the real weight/reps as you lift.
  /// Value-stripped defensively so a legacy/AI template with numbers still yields
  /// blanks (you can't predict a future workout's loads).
  List<WorkoutSet> get blankSets => [for (final s in sets) s.blankCopy()];

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'type': type,
        'sets': [for (final s in sets) s.toJson()],
      };

  factory WorkoutTemplate.fromJson(Map<String, dynamic> j) => WorkoutTemplate(
        id: j['id'] as String,
        name: j['name'] as String,
        type: j['type'] as String? ?? 'Weightlifting',
        sets: [
          for (final s in (j['sets'] as List? ?? const []))
            WorkoutSet.fromJson(s as Map<String, dynamic>)
        ],
      );

  /// Snapshot a finished session's STRUCTURE as a reusable template — the
  /// exercises and how many sets of each, but NOT the weights/reps (those are
  /// what you fill in fresh each time; a template is a plan, not a prediction).
  factory WorkoutTemplate.fromSession(WorkoutSession s, {required String name}) =>
      WorkoutTemplate(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name,
        type: s.type,
        sets: [for (final st in s.sets) st.blankCopy()],
      );
}

/// Sessions most-recent first (by start datetime).
List<WorkoutSession> sortedByRecent(List<WorkoutSession> sessions) =>
    [...sessions]..sort((a, b) => b.start.compareTo(a.start));

/// Absorb every linked manual session INTO its parent watch exercise: the sets
/// become CHILDREN of the real tracked exercise (one workout = one entry, the
/// watch session), and the manual container is deleted. The parent keeps its
/// cardio summary and gains the sets + the manual title (e.g. "Push day") when
/// it has a custom one. Returns (updated parents, manual ids to delete).
/// Pure + unit-tested.
(List<WorkoutSession>, List<String>) absorbLinkedSessions(
    List<WorkoutSession> sessions) {
  final byGid = {
    for (final s in sessions)
      if (s.fromGoogle && s.googleId != null) s.googleId!: s
  };
  final parents = <String, WorkoutSession>{};
  final remove = <String>[];
  for (final s in sessions) {
    if (s.fromGoogle || s.linkedGoogleId == null) continue;
    final parent = parents[s.linkedGoogleId!] ?? byGid[s.linkedGoogleId!];
    if (parent == null) continue;
    parents[s.linkedGoogleId!] = parent.copyWith(
      sets: [...parent.sets, ...s.sets],
      title: (s.title != null && s.title!.trim().isNotEmpty)
          ? s.title
          : parent.title,
      absorbedIds: [...parent.absorbedIds, s.id, ...s.absorbedIds],
    );
    remove.add(s.id);
  }
  return (parents.values.toList(), remove);
}

/// Link manual set-logging sessions to the watch-tracked Google exercise that
/// covers them (two-step verification). A time-window overlap (with [slackMins]
/// of tolerance on both ends) is preferred; when nothing overlaps, the NEAREST
/// same-day tracked exercise is used — a holder's timestamp is when you typed
/// the sets, which is routinely hours after the workout the sets describe, and
/// the same-day watch exercise is still the real anchor. Never links across
/// days. Returns the sessions that gained a link (updated copies).
/// Pure + unit-tested.
List<WorkoutSession> linkSessionsToWatch(List<WorkoutSession> sessions,
    {int slackMins = 45}) {
  final google = [for (final s in sessions) if (s.fromGoogle) s];
  if (google.isEmpty) return const [];
  final slack = Duration(minutes: slackMins);
  final changed = <WorkoutSession>[];
  for (final s in sessions) {
    if (s.fromGoogle || s.linkedGoogleId != null) continue;
    final start = DateTime.tryParse(s.start);
    if (start == null) continue;
    final end = start.add(Duration(minutes: s.durationMins ?? 60));
    String? overlapId;
    String? nearestId;
    Duration? nearestGap;
    for (final g in google) {
      if (g.dateKey != s.dateKey || g.googleId == null) continue;
      final gStart = DateTime.tryParse(g.start);
      if (gStart == null) continue;
      final gEnd = gStart.add(Duration(minutes: g.durationMins ?? 60));
      final overlaps = start.isBefore(gEnd.add(slack)) &&
          gStart.isBefore(end.add(slack));
      if (overlaps) {
        overlapId = g.googleId;
        break;
      }
      final gap = gStart.difference(start).abs();
      if (nearestGap == null || gap < nearestGap) {
        nearestGap = gap;
        nearestId = g.googleId;
      }
    }
    final target = overlapId ?? nearestId;
    if (target != null) changed.add(s.copyWith(linkedGoogleId: target));
  }
  return changed;
}

/// Active calories burned on [day] (YYYY-MM-DD), summed from sessions' Google calorie
/// summaries. Estimated (watch-derived) — feeds the diet energy-balance "out" figure.
double activeCaloriesOn(List<WorkoutSession> sessions, String day) {
  var kcal = 0.0;
  for (final s in sessions) {
    if (s.dateKey == day) kcal += s.summary['calories'] ?? 0;
  }
  return kcal;
}

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
