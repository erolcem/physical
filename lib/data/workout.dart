// data/workout.dart — exercise/workout logging (PDF Part 1: strength "reps &
// weight → volume & 1RM"; "Lifting exercise sets" → volume + hit muscle groups).
// A session is a dated list of sets; from it we derive total VOLUME (Σ weight×reps)
// and the BEST set per exercise (the one that updates that lift's rank). Pure
// model + logic, unit-tested.
import '../engine/rank_engine.dart' show strengthValue;
import 'habits.dart' show lastNDays;

class WorkoutSet {
  final String exerciseId; // a strength metric id (bench, squat, curl, …)
  final double weight;
  final int reps;
  const WorkoutSet(this.exerciseId, this.weight, this.reps);

  double get volume => weight * reps;

  Map<String, dynamic> toJson() => {'e': exerciseId, 'w': weight, 'r': reps};
  factory WorkoutSet.fromJson(Map<String, dynamic> j) =>
      WorkoutSet(j['e'] as String, (j['w'] as num).toDouble(), (j['r'] as num).toInt());
}

class WorkoutSession {
  final String id;
  final String dateKey;
  final List<WorkoutSet> sets;
  const WorkoutSession({required this.id, required this.dateKey, required this.sets});

  double get volume => sets.fold(0.0, (s, x) => s + x.volume);
  Set<String> get exercises => {for (final s in sets) s.exerciseId};

  Map<String, dynamic> toJson() =>
      {'id': id, 'day': dateKey, 'sets': [for (final s in sets) s.toJson()]};
  factory WorkoutSession.fromJson(Map<String, dynamic> j) => WorkoutSession(
        id: j['id'] as String,
        dateKey: j['day'] as String,
        sets: [for (final s in (j['sets'] as List)) WorkoutSet.fromJson(s as Map<String, dynamic>)],
      );
}

/// Best set per exercise — highest canonical strength value (1RM for compounds,
/// rep-volume for isolations). This is the set that updates the lift's rank.
Map<String, WorkoutSet> bestSets(WorkoutSession session) {
  final best = <String, WorkoutSet>{};
  for (final s in session.sets) {
    final cur = best[s.exerciseId];
    if (cur == null ||
        strengthValue(s.exerciseId, s.weight, s.reps) >
            strengthValue(cur.exerciseId, cur.weight, cur.reps)) {
      best[s.exerciseId] = s;
    }
  }
  return best;
}

/// Total training volume across sessions in the last [days] days.
double volumeOverDays(List<WorkoutSession> sessions, {int days = 7, DateTime? today}) {
  final window = lastNDays(days, today: today).toSet();
  return sessions
      .where((s) => window.contains(s.dateKey))
      .fold(0.0, (a, s) => a + s.volume);
}

/// Distinct exercises trained in the last [days] days.
Set<String> exercisesOverDays(List<WorkoutSession> sessions, {int days = 7, DateTime? today}) {
  final window = lastNDays(days, today: today).toSet();
  return {
    for (final s in sessions)
      if (window.contains(s.dateKey)) ...s.exercises
  };
}

int sessionsOverDays(List<WorkoutSession> sessions, {int days = 7, DateTime? today}) {
  final window = lastNDays(days, today: today).toSet();
  return sessions.where((s) => window.contains(s.dateKey)).length;
}
