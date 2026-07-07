// data/ai_verify.dart — LLM habit verification (owner review round 3, items 4+7).
// Rule-based auto-check is brittle: one workout ticks every workout habit, and
// custom habits can't be judged at all. This module gathers the day's REAL
// evidence (sessions with their sets, the food log, every metric reading) and
// asks the backend's Gemini verifier for a per-habit verdict; verdicts are
// stored in the repository and override the rule-based check (habitDoneOn).
// Manual habits are never judged — they stay user-ticked by design.
import 'api_client.dart';
import 'habits.dart';
import 'repository.dart';
import 'workout.dart' show WorkoutTemplate;

/// The habits the AI can judge on [date]: due that day, not manual, and not
/// 'rank_log' (rank check-ins are a deterministic count of ranked-test logs —
/// the model can't know which metrics are ranked, so its verdict would only
/// be able to corrupt a rule that's already exact).
List<Habit> verifiableHabitsOn(List<Habit> habits, DateTime date) => [
      for (final h in habits)
        if (h.verify != 'manual' && h.verify != 'rank_log' && isDueOn(h, date)) h
    ];

/// One habit → the compact dict the verifier reasons over. When the habit
/// carries a workout [plan], the verifier can judge the actual session against
/// the planned exercises, not just "was there a workout".
Map<String, dynamic> habitPayload(Habit h, {WorkoutTemplate? plan}) => {
      'id': h.id,
      'title': h.title,
      'section': h.section,
      'verify': h.verify,
      if (h.linkedMetricId != null) 'metric': h.linkedMetricId,
      if (h.target != null) 'target': h.target,
      if (h.target != null) 'compare': h.compare,
      if (h.unit.isNotEmpty) 'unit': h.unit,
      if (h.goalKey != null) 'goalKey': h.goalKey,
      if (h.time != null) 'time': h.time,
      if (plan != null)
        'planned_workout': {
          'name': plan.name,
          'exercises': plan.exercises.toList(),
          'sets': plan.setCount,
        },
    };

/// Everything recorded on [day], as evidence: workout sessions (with individual
/// sets), food entries, and the day's last reading per metric (derived rank
/// series excluded — they're outputs, not evidence).
Map<String, dynamic> dayEvidence(Repository repo, String day) {
  final workouts = [
    for (final s in repo.loadWorkouts())
      if (s.dateKey == day)
        {
          'type': s.type,
          if (s.title != null) 'title': s.title,
          if (s.durationMins != null) 'duration_mins': s.durationMins,
          // Anchored to a real tracked exercise (IS a watch session, or linked
          // to one covering the same window) vs self-reported typing.
          'watch_verified': s.watchVerified,
          if (s.summary.isNotEmpty) ...s.summary,
          'sets': [
            for (final st in s.sets)
              {
                'name': st.name,
                if (st.weight != null) 'w': st.weight,
                if (st.reps != null) 'r': st.reps,
                if (st.seconds != null) 's': st.seconds,
                if (st.distance != null) 'd': st.distance,
              }
          ],
        }
  ];
  final food = [
    for (final f in repo.loadFood())
      if (f.dateKey == day)
        {
          'name': f.name,
          'calories': f.calories,
          'protein': f.protein,
          'carbs': f.carbs,
          'fat': f.fat,
          'fibre': f.fibre,
        }
  ];
  final metrics = <String, double>{};
  repo.loadLogs().forEach((id, logs) {
    if (id.endsWith('_rank')) return;
    for (final l in logs) {
      if (l.ts.startsWith(day)) metrics[id] = l.value; // last on the day wins
    }
  });
  return {'workouts': workouts, 'food': food, 'metrics': metrics};
}

/// Run the LLM verification for [day] (defaults to today): sends the due
/// non-manual habits + the day's evidence, stores each verdict. Returns how
/// many habits were judged, or null when unavailable (offline / not signed in /
/// no AI key) — the rule-based check keeps working as the fallback.
Future<int?> runAiVerification(ApiClient api, Repository repo, {DateTime? date}) async {
  final d = date ?? DateTime.now();
  final day = dateKey(d);
  final habits = verifiableHabitsOn(repo.loadHabits(), d);
  if (habits.isEmpty) return 0;
  final ev = dayEvidence(repo, day);
  final plans = {for (final t in repo.loadTemplates()) t.id: t};
  final verdicts = await api.verifyHabits(
    day: day,
    habits: [
      for (final h in habits) habitPayload(h, plan: plans[h.templateId])
    ],
    workouts: (ev['workouts'] as List).cast<Map<String, dynamic>>(),
    food: (ev['food'] as List).cast<Map<String, dynamic>>(),
    metrics: (ev['metrics'] as Map).cast<String, dynamic>(),
  );
  if (verdicts == null) return null;
  var judged = 0;
  final known = {for (final h in habits) h.id};
  for (final v in verdicts) {
    final id = v['id'] as String?;
    if (id == null || !known.contains(id)) continue;
    repo.setAiVerdict(id, day, v['done'] == true);
    judged++;
  }
  return judged;
}
