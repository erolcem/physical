// Watch anchoring: manual set-logging sessions link to the real tracked Google
// exercise covering the same window (two-step verification — sets can't be
// fabricated free-floating).
import 'package:flutter_test/flutter_test.dart';
import 'package:physical/data/repository.dart';
import 'package:physical/data/workout.dart';
import 'package:physical/state/log_providers.dart' show WorkoutNotifier;

void main() {
  WorkoutSession manual(String id, String start, {int? dur}) => WorkoutSession(
      id: id, type: 'Weightlifting', start: start, durationMins: dur,
      sets: const [WorkoutSet(name: 'Bench', mode: SetMode.weightReps, weight: 80, reps: 5)]);
  WorkoutSession google(String gid, String start, {int? dur}) => WorkoutSession(
      id: 'g:$gid', type: 'Weightlifting', start: start, durationMins: dur,
      source: 'google', googleId: gid);

  test('overlapping manual session links to the watch exercise', () {
    final linked = linkSessionsToWatch([
      manual('m1', '2026-07-01T18:05:00', dur: 60),
      google('gid1', '2026-07-01T18:00:00', dur: 55),
    ]);
    expect(linked.single.id, 'm1');
    expect(linked.single.linkedGoogleId, 'gid1');
    expect(linked.single.watchVerified, isTrue);
  });

  test('no overlap but SAME DAY still links (nearest tracked exercise) — the '
      'holder timestamp is when you TYPED the sets, hours after training', () {
    final linked = linkSessionsToWatch([
      manual('m1', '2026-07-01T21:30:00', dur: 45), // typed 2.5h after the workout
      google('gid1', '2026-07-01T18:00:00', dur: 60),
    ]);
    expect(linked.single.linkedGoogleId, 'gid1');
    // Several same-day exercises → the NEAREST in time wins.
    final nearest = linkSessionsToWatch([
      manual('m1', '2026-07-01T21:00:00', dur: 45),
      google('gmorning', '2026-07-01T07:00:00', dur: 40),
      google('gevening', '2026-07-01T18:00:00', dur: 60),
    ]);
    expect(nearest.single.linkedGoogleId, 'gevening');
  });

  test('another day never links', () {
    expect(
        linkSessionsToWatch([
          manual('m1', '2026-07-02T18:00:00'),
          google('gid1', '2026-07-01T18:00:00'),
        ]),
        isEmpty);
    expect(manual('m1', '2026-07-01T08:00:00').watchVerified, isFalse);
  });

  test('slack tolerates logging shortly before/after the watch window', () {
    final linked = linkSessionsToWatch([
      manual('m1', '2026-07-01T17:30:00', dur: 30), // ends 18:00; watch starts 18:20
      google('gid1', '2026-07-01T18:20:00', dur: 40),
    ]);
    expect(linked, hasLength(1)); // within the 45-min slack
  });

  test('linked manual sessions are ABSORBED into the parent watch exercise', () {
    // The sets become children of the real tracked exercise; the manual
    // container disappears — one workout, one entry.
    final m = manual('m1', '2026-07-01T18:05:00', dur: 60)
        .copyWith(title: 'Push day', linkedGoogleId: 'gid1');
    final g = google('gid1', '2026-07-01T18:00:00', dur: 55);
    final (parents, removed) = absorbLinkedSessions([m, g]);
    expect(removed, ['m1']);
    final parent = parents.single;
    expect(parent.googleId, 'gid1');
    expect(parent.sets, hasLength(1)); // the manual sets migrated in
    expect(parent.sets.single.name, 'Bench');
    expect(parent.label, 'Push day'); // custom title carried onto the parent
    expect(parent.watchVerified, isTrue);
    // Unlinked manual sessions are never absorbed.
    expect(absorbLinkedSessions([manual('m2', '2026-07-01T09:00:00'), g]).$2, isEmpty);
  });

  test('google sessions and already-linked sessions are untouched; link round-trips', () {
    final pre = manual('m1', '2026-07-01T18:00:00')
        .copyWith(linkedGoogleId: 'existing');
    expect(
        linkSessionsToWatch([pre, google('gid1', '2026-07-01T18:00:00')]), isEmpty);
    final back = WorkoutSession.fromJson(pre.toJson());
    expect(back.linkedGoogleId, 'existing');
    expect(back.watchVerified, isTrue);
  });

  test('absorption records the trail (absorbedIds) and it round-trips json', () {
    final m = manual('m1', '2026-07-01T18:05:00', dur: 60)
        .copyWith(linkedGoogleId: 'gid1');
    final g = google('gid1', '2026-07-01T18:00:00', dur: 55);
    final parent = absorbLinkedSessions([m, g]).$1.single;
    expect(parent.absorbedIds, contains('m1'));
    expect(WorkoutSession.fromJson(parent.toJson()).absorbedIds, contains('m1'));
  });

  test('sets are CHILDREN: a new session absorbs into a covering watch exercise '
      'instantly — no separate instance is ever visible', () {
    final repo = InMemoryRepository();
    final now = DateTime.now();
    repo.saveWorkout(WorkoutSession(
        id: 'g:live', type: 'Weightlifting',
        start: now.subtract(const Duration(minutes: 30)).toIso8601String(),
        durationMins: 60, source: 'google', googleId: 'live'));
    final n = WorkoutNotifier(repo);
    final s = n.createFromTemplate(const WorkoutTemplate(
        id: 't1', name: 'Push day',
        sets: [WorkoutSet(name: 'Bench', mode: SetMode.weightReps, weight: 80, reps: 5)]));
    // The returned session IS the watch parent, already holding the sets.
    expect(s.googleId, 'live');
    expect(s.watchVerified, isTrue);
    expect(s.sets.single.name, 'Bench');
    expect(n.state, hasLength(1)); // one workout, one entry
    // Adding a set through the old holder id lands in the parent too.
    final holderId = s.absorbedIds.single;
    n.addSet(holderId, const WorkoutSet(name: 'Fly', mode: SetMode.weightReps, weight: 20, reps: 12));
    expect(n.resolve(holderId)!.sets, hasLength(2));
  });

  test('a template drops EMPTY slots you fill in with updateSet', () {
    final repo = InMemoryRepository();
    repo.saveWorkout(google('live', DateTime.now().toIso8601String(), dur: 60));
    final n = WorkoutNotifier(repo);
    // Even a template that carries values yields blank slots (can't predict loads).
    n.applyTemplateToSession('g:live', const WorkoutTemplate(
        id: 't1', name: 'Push', sets: [
      WorkoutSet(name: 'Bench', mode: SetMode.weightReps, weight: 999, reps: 9),
    ]));
    final g = n.state.single;
    expect(g.sets.single.isBlank, isTrue); // no phantom loads
    expect(g.sets.single.name, 'Bench');
    // Fill the slot in with what you actually lifted.
    n.updateSet(g.id, 0, const WorkoutSet(name: 'Bench', mode: SetMode.weightReps, weight: 100, reps: 5));
    expect(n.state.single.sets.single.weight, 100);
    expect(n.state.single.sets.single.isBlank, isFalse);
  });

  test('pre-logged sets typed HOURS after the watch exercise absorb into it '
      'when it syncs in (the whole point of pre-logging)', () {
    final repo = InMemoryRepository();
    final n = WorkoutNotifier(repo);
    final today = DateTime.now();
    // 1) User types sets before the watch session has synced — a holder.
    final holder = n.createSession(type: 'Weightlifting', title: 'Push day');
    n.addSet(holder.id, const WorkoutSet(name: 'Bench', mode: SetMode.weightReps, weight: 80, reps: 5));
    expect(n.state.single.watchVerified, isFalse);
    // 2) The watch exercise from EARLIER TODAY (no window overlap) syncs in.
    final morning = DateTime(today.year, today.month, today.day, 0, 5);
    n.importGoogle([
      {'google_id': 'gwatch', 'type': 'Weightlifting',
       'start': morning.toIso8601String(), 'duration_mins': 60},
    ]);
    // The holder absorbed: one workout, the watch exercise, holding the sets.
    expect(n.state, hasLength(1));
    final parent = n.state.single;
    expect(parent.googleId, 'gwatch');
    expect(parent.sets.single.name, 'Bench');
    expect(parent.watchVerified, isTrue);
    expect(parent.label, 'Push day');
  });

  test('updateSetRef/removeSetRef survive absorption mid-edit (never corrupt '
      'a different set)', () {
    final repo = InMemoryRepository();
    final n = WorkoutNotifier(repo);
    // Watch parent already has a set of its own.
    final now = DateTime.now();
    repo.saveWorkout(WorkoutSession(
        id: 'g:live', type: 'Weightlifting',
        start: now.subtract(const Duration(minutes: 30)).toIso8601String(),
        durationMins: 120, source: 'google', googleId: 'live',
        sets: const [WorkoutSet(name: 'Squat', mode: SetMode.weightReps, weight: 100, reps: 5)]));
    final holder = n.createSession(type: 'Weightlifting');
    // The holder absorbed instantly (covering watch exercise exists) — but the
    // UI may still hold the pre-absorption set instance. Simulate: grab the
    // set AFTER absorption, then edit through the STALE holder id.
    n.addSet(holder.id, const WorkoutSet(name: 'Bench', mode: SetMode.weightReps, weight: 60, reps: 8));
    final live = n.resolve(holder.id)!;
    expect(live.googleId, 'live');
    final benchSet = live.sets.firstWhere((s) => s.name == 'Bench');
    n.updateSetRef(holder.id, benchSet,
        const WorkoutSet(name: 'Bench', mode: SetMode.weightReps, weight: 65, reps: 8));
    final after = n.resolve(holder.id)!;
    // The BENCH set changed; the parent's own Squat set is untouched.
    expect(after.sets.firstWhere((s) => s.name == 'Bench').weight, 65);
    expect(after.sets.firstWhere((s) => s.name == 'Squat').weight, 100);
    // A value-identical stale copy still resolves (identity fallback → values).
    n.removeSetRef(holder.id,
        const WorkoutSet(name: 'Bench', mode: SetMode.weightReps, weight: 65, reps: 8));
    expect(n.resolve(holder.id)!.sets.map((s) => s.name), ['Squat']);
    // A set that no longer exists is a NO-OP, not a positional guess.
    n.removeSetRef(holder.id,
        const WorkoutSet(name: 'Ghost', mode: SetMode.weightReps, weight: 1, reps: 1));
    expect(n.resolve(holder.id)!.sets, hasLength(1));
  });

  test('repoMerge adopts the RICHER set record for the same workout id '
      '(sets typed on another device propagate)', () {
    final repo = InMemoryRepository();
    repo.saveWorkout(google('gid1', '2026-07-01T18:00:00', dur: 60));
    // The other device's snapshot has the SAME Google exercise + typed sets.
    final other = google('gid1', '2026-07-01T18:00:00', dur: 60).copyWith(
      sets: const [
        WorkoutSet(name: 'Bench', mode: SetMode.weightReps, weight: 80, reps: 5),
        WorkoutSet(name: 'Fly', mode: SetMode.weightReps, weight: 20, reps: 12),
      ],
      title: 'Push day',
    );
    repoMerge(repo, {
      'workouts': [other.toJson()],
    });
    final merged = repo.loadWorkouts().single;
    expect(merged.sets, hasLength(2));
    expect(merged.label, 'Push day');
    // Local already richer → merge never downgrades.
    repoMerge(repo, {
      'workouts': [google('gid1', '2026-07-01T18:00:00', dur: 60).toJson()],
    });
    expect(repo.loadWorkouts().single.sets, hasLength(2));
  });

  test('applyTemplateToSession appends a plan INTO a Google exercise (children, '
      'not a new entity)', () {
    final repo = InMemoryRepository();
    repo.saveWorkout(google('live', DateTime.now().toIso8601String(), dur: 60));
    final n = WorkoutNotifier(repo);
    n.applyTemplateToSession('g:live', const WorkoutTemplate(
        id: 't1', name: 'Push day',
        sets: [WorkoutSet(name: 'Bench', mode: SetMode.weightReps, weight: 80, reps: 5),
               WorkoutSet(name: 'Fly', mode: SetMode.weightReps, weight: 20, reps: 12)]));
    expect(n.state, hasLength(1)); // still ONE workout — the Google exercise
    final g = n.state.single;
    expect(g.googleId, 'live');
    expect(g.sets.map((s) => s.name), ['Bench', 'Fly']);
    expect(g.watchVerified, isTrue);
  });
}
