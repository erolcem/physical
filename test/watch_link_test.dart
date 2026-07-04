// Watch anchoring: manual set-logging sessions link to the real tracked Google
// exercise covering the same window (two-step verification — sets can't be
// fabricated free-floating).
import 'package:flutter_test/flutter_test.dart';
import 'package:physical/data/workout.dart';

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

  test('a session hours away or on another day stays unverified', () {
    expect(
        linkSessionsToWatch([
          manual('m1', '2026-07-01T08:00:00', dur: 45),
          google('gid1', '2026-07-01T19:00:00', dur: 60), // 11h later
        ]),
        isEmpty);
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
}
