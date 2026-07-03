import 'package:flutter_test/flutter_test.dart';
import 'package:physical/data/diet.dart' show FoodEntry;
import 'package:physical/data/habits.dart' show Habit;
import 'package:physical/data/repository.dart';
import 'package:physical/data/sync.dart' show mergeSamples;
import 'package:physical/data/workout.dart' show WorkoutSession, WorkoutTemplate;
import 'package:physical/engine/rank_engine.dart' show Log;

void main() {
  test('deleting a log tombstones it; Google re-sync cannot resurrect it', () {
    final repo = InMemoryRepository();
    repo.saveLog('resting_hr', Log('resting_hr', 55, ts: '2026-06-28T08:00:00'));
    repo.deleteLog('resting_hr', 0);
    expect(repo.loadLogs()['resting_hr'] ?? const [], isEmpty);
    expect(repo.loadTombstones(), contains('resting_hr@2026-06-28T08:00:00'));
    // The same sample comes back from Google → must be skipped.
    final added = mergeSamples(repo, [
      {'metric_id': 'resting_hr', 'ts': '2026-06-28T08:00:00', 'value': 55},
    ]);
    expect(added, 0);
    expect(repo.loadLogs()['resting_hr'] ?? const [], isEmpty);
  });

  test('backup merge does not resurrect a tombstoned log', () {
    final repo = InMemoryRepository();
    repo.saveLog('bench', Log('bench', 100, bodyweight: 80, ts: '2026-06-01T10:00:00'));
    repo.deleteLog('bench', 0);
    // A cloud snapshot still containing the deleted log.
    repoMerge(repo, {
      'logs': {'bench': [{'v': 100, 'bw': 80, 'ts': '2026-06-01T10:00:00'}]},
    });
    expect(repo.loadLogs()['bench'] ?? const [], isEmpty);
  });

  test('tombstones round-trip through export/import + propagate via merge', () {
    final a = InMemoryRepository();
    a.saveLog('hrv', Log('hrv', 50, ts: '2026-06-10T08:00:00'));
    a.deleteLog('hrv', 0);
    final snap = repoExport(a);
    expect((snap['tombstones'] as List), contains('hrv@2026-06-10T08:00:00'));
    // Device B has the log; merging A's snapshot (with the tombstone) deletes it.
    final b = InMemoryRepository();
    b.saveLog('hrv', Log('hrv', 50, ts: '2026-06-10T08:00:00'));
    repoMerge(b, snap);
    expect(b.loadLogs()['hrv'] ?? const [], isEmpty);
  });

  // ── Entity tombstones: deletes must survive the cloud-backup merge ────────
  // (Deleted habits used to ride back in on every sync from the backup blob.)
  test('a deleted habit cannot be resurrected by the backup merge', () {
    final repo = InMemoryRepository();
    repo.saveHabit(const Habit(id: 'h1', title: 'Train', section: 'exercise',
        verify: 'workout', createdAt: '2026-07-01T00:00:00'));
    // The cloud snapshot was taken while the habit still existed.
    final cloud = repoExport(repo);
    repo.deleteHabit('h1');
    expect(repo.loadTombstones(), contains('habit:h1'));
    // The sync merge (which used to union the habit back in) now respects it.
    repoMerge(repo, cloud);
    expect(repo.loadHabits(), isEmpty);
  });

  test('entity deletes propagate across devices via merge', () {
    final a = InMemoryRepository();
    a.saveHabit(const Habit(id: 'h1', title: 'Train', createdAt: 'c'));
    a.saveFood(const FoodEntry(id: 'f1', dateKey: '2026-07-01', name: 'Oats'));
    a.saveWorkout(const WorkoutSession(id: 'w1', type: 'Run', start: '2026-07-01T07:00:00'));
    a.saveTemplate(const WorkoutTemplate(id: 't1', name: 'Push'));
    a.deleteHabit('h1');
    a.deleteFood('f1');
    a.deleteWorkout('w1');
    a.deleteTemplate('t1');
    // Device B still holds all four; merging A's snapshot deletes them there too.
    final b = InMemoryRepository();
    b.saveHabit(const Habit(id: 'h1', title: 'Train', createdAt: 'c'));
    b.saveFood(const FoodEntry(id: 'f1', dateKey: '2026-07-01', name: 'Oats'));
    b.saveWorkout(const WorkoutSession(id: 'w1', type: 'Run', start: '2026-07-01T07:00:00'));
    b.saveTemplate(const WorkoutTemplate(id: 't1', name: 'Push'));
    repoMerge(b, repoExport(a));
    expect(b.loadHabits(), isEmpty);
    expect(b.loadFood(), isEmpty);
    expect(b.loadWorkouts(), isEmpty);
    expect(b.loadTemplates(), isEmpty);
    // And a restore (full import) doesn't bring them back either.
    final c = InMemoryRepository();
    repoImport(c, repoExport(a));
    expect(c.loadHabits(), isEmpty);
  });
}
