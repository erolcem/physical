// LLM habit verification (items 4+7): the verdict override, the evidence
// payload, and verdict storage — with the network faked.
import 'package:flutter_test/flutter_test.dart';
import 'package:physical/data/ai_verify.dart';
import 'package:physical/data/api_client.dart';
import 'package:physical/data/habit_verify.dart';
import 'package:physical/data/habits.dart';
import 'package:physical/data/repository.dart';
import 'package:physical/data/workout.dart';
import 'package:physical/engine/rank_engine.dart' show Log;

class _FakeVerifyApi extends ApiClient {
  Map<String, dynamic>? sent;
  List<Map<String, dynamic>>? verdicts;
  _FakeVerifyApi(this.verdicts) : super(baseUrl: 'http://test');

  @override
  Future<List<Map<String, dynamic>>?> verifyHabits({
    required String day,
    required List<Map<String, dynamic>> habits,
    List<Map<String, dynamic>> workouts = const [],
    List<Map<String, dynamic>> food = const [],
    Map<String, dynamic> metrics = const {},
  }) async {
    sent = {'day': day, 'habits': habits, 'workouts': workouts,
            'food': food, 'metrics': metrics};
    return verdicts;
  }
}

void main() {
  final today = DateTime.now();
  final day = dateKey(today);

  Habit h(String id, String title, {String verify = 'workout', String description = ''}) => Habit(
      id: id, title: title, section: 'exercise', verify: verify,
      description: description, createdAt: today.toIso8601String());

  test('habitPayload carries the free-text description for the verifier', () {
    final p = habitPayload(h('t1', 'Cardio',
        description: 'Evening makiwara punching, 20+ min — a walk does not count'));
    expect(p['description'], contains('makiwara'));
    // Empty descriptions are omitted, not sent as ''.
    expect(habitPayload(h('t2', 'Train')).containsKey('description'), isFalse);
  });

  test('aiVerdict overrides the rule-based check in habitDoneOn', () {
    final train = h('t1', 'Train');
    final session = WorkoutSession(
        id: 'w', type: 'Weightlifting', start: '${day}T10:00:00',
        sets: const [WorkoutSet(name: 'Bench', mode: SetMode.weightReps, weight: 80, reps: 5)]);
    // Rule-based: any session that day → done.
    expect(habitDoneOn(train, day, logs: const {}, food: const [], workouts: [session]), isTrue);
    // The AI judged it NOT done (e.g. the session was claimed by another habit).
    expect(habitDoneOn(train, day, logs: const {}, food: const [], workouts: [session],
        aiVerdict: false), isFalse);
    // And can also confirm a habit the rules can't see evidence for.
    expect(habitDoneOn(train, day, logs: const {}, food: const [], workouts: const [],
        aiVerdict: true), isTrue);
    // STRICT: a manual tick can never satisfy a data-verifiable habit — real
    // evidence (watch session / sets / food) is the only way it counts.
    expect(habitDoneOn(train, day, logs: const {}, food: const [], workouts: const [],
        ticked: {day}, aiVerdict: false), isFalse);
    expect(habitDoneOn(train, day, logs: const {}, food: const [], workouts: const [],
        ticked: {day}), isFalse);
    // Manual habits are never judged by the AI.
    final manual = h('m1', 'Journal', verify: 'manual');
    expect(habitDoneOn(manual, day, logs: const {}, food: const [], workouts: const [],
        ticked: {day}, aiVerdict: false), isTrue);
  });

  test('AI verdict is authoritative for WORKOUT habits only; the exact rule wins '
      'for deterministic metric/diet habits', () {
    // A metric habit whose target IS met by the data.
    const sleep = Habit(id: 's1', title: 'Sleep 8h', section: 'sleep',
        verify: 'metric', linkedMetricId: 'sleep_score', target: 80, createdAt: 'x');
    final logs = {'sleep_score': [Log('sleep_score', 88, ts: '${day}T07:00:00')]};
    // A wrong/contradicting AI verdict must NOT override the exact computation.
    expect(habitDoneOn(sleep, day, logs: logs, food: const [], workouts: const [],
        aiVerdict: false), isTrue);
    // And a false AI "done" can't fake an unmet target either.
    final low = {'sleep_score': [Log('sleep_score', 60, ts: '${day}T07:00:00')]};
    expect(habitDoneOn(sleep, day, logs: low, food: const [], workouts: const [],
        aiVerdict: true), isFalse);
    // Workout habits DO honour the verdict (exclusivity / custom-activity match).
    final train = h('t1', 'Train');
    final session = WorkoutSession(id: 'w', type: 'Weightlifting', start: '${day}T10:00:00');
    expect(habitDoneOn(train, day, logs: const {}, food: const [], workouts: [session],
        aiVerdict: false), isFalse);
  });

  test('only WORKOUT habits are sent to the AI verifier', () {
    final habits = [
      h('t1', 'Train'), // workout → sent
      const Habit(id: 'm1', title: 'Sleep', section: 'sleep', verify: 'metric',
          linkedMetricId: 'sleep_score', createdAt: 'x'), // deterministic → not sent
      const Habit(id: 'd1', title: 'Protein', section: 'diet', verify: 'diet',
          goalKey: 'protein', createdAt: 'x'), // deterministic → not sent
      const Habit(id: 'r1', title: 'Rank check-in', section: 'misc',
          verify: 'rank_log', createdAt: 'x'), // deterministic → not sent
    ];
    expect(verifiableHabitsOn(habits, today).map((x) => x.id), ['t1']);
  });

  test('runAiVerification sends the day evidence and stores verdicts', () async {
    final repo = InMemoryRepository();
    repo.saveHabit(h('t1', 'Train'));
    repo.saveHabit(h('t2', 'Cardio session'));
    repo.saveHabit(h('m1', 'Journal', verify: 'manual')); // never sent
    repo.saveWorkout(WorkoutSession(
        id: 'w', type: 'Weightlifting', start: '${day}T10:00:00',
        sets: const [WorkoutSet(name: 'Bench', mode: SetMode.weightReps, weight: 80, reps: 5)]));
    repo.saveLog('steps', Log('steps', 9000, ts: '${day}T00:00:00'));

    final api = _FakeVerifyApi([
      {'id': 't1', 'done': true, 'reason': 'weights session'},
      {'id': 't2', 'done': false, 'reason': 'no separate cardio evidence'},
      {'id': 'zzz', 'done': true, 'reason': 'unknown id — dropped'},
    ]);
    final judged = await runAiVerification(api, repo, date: today);
    expect(judged, 2);
    // Only the non-manual habits were submitted, with the day's evidence.
    final sentHabits = (api.sent!['habits'] as List).map((h) => h['id']).toList();
    expect(sentHabits, ['t1', 't2']);
    expect((api.sent!['workouts'] as List).single['sets'], isNotEmpty);
    expect((api.sent!['metrics'] as Map)['steps'], 9000);
    // Verdicts stored per habit+day; unknown ids ignored.
    expect(repo.loadAiVerdicts()['t1']![day], isTrue);
    expect(repo.loadAiVerdicts()['t2']![day], isFalse);
    expect(repo.loadAiVerdicts().containsKey('zzz'), isFalse);
  });

  test('runAiVerification returns null when the API is unavailable', () async {
    final repo = InMemoryRepository();
    repo.saveHabit(h('t1', 'Train'));
    expect(await runAiVerification(_FakeVerifyApi(null), repo, date: today), isNull);
    expect(repo.loadAiVerdicts(), isEmpty);
  });

  test('deleting a habit clears its AI verdicts', () {
    final repo = InMemoryRepository();
    repo.saveHabit(h('t1', 'Train'));
    repo.setAiVerdict('t1', day, true);
    repo.deleteHabit('t1');
    expect(repo.loadAiVerdicts(), isEmpty);
  });
}
