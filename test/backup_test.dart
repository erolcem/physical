// Full-data backup: repoExport → repoImport must round-trip every entity.
import 'package:flutter_test/flutter_test.dart';
import 'package:physical/data/repository.dart';
import 'package:physical/data/diet.dart';
import 'package:physical/data/workout.dart';
import 'package:physical/data/habits.dart';
import 'package:physical/data/correlation.dart';
import 'package:physical/engine/rank_engine.dart' show Log;

void main() {
  _mergeTests();
  test('repoExport/repoImport round-trips all entities', () {
    final a = InMemoryRepository();
    a.saveLog('bench', Log('bench', 100, bodyweight: 80, ts: '2026-06-27T10:00:00'));
    a.saveLog('eye', Log('eye', -0.1, ts: '2026-06-27T10:00:00'));
    a.saveHabit(const Habit(id: 'h1', title: 'Train', section: 'exercise',
        verify: 'workout', createdAt: '2026-06-01T00:00:00'));
    a.setCompletion('h1', '2026-06-27', true);
    a.saveFood(const FoodEntry(id: 'f1', dateKey: '2026-06-27', name: 'Eggs',
        calories: 200, protein: 18, health: {'fibre': 20}));
    a.saveWorkout(const WorkoutSession(id: 'w1', type: 'Run', start: '2026-06-27T07:00:00',
        source: 'google', summary: {'calories': 400}));
    a.addPin(const PinnedCorrelation('sleep_score', 'hrv'));

    final snapshot = repoExport(a);

    final b = InMemoryRepository();
    b.saveLog('junk', Log('junk', 1)); // pre-existing data must be wiped on import
    repoImport(b, snapshot);

    expect(b.loadLogs()['junk'], isNull);
    expect(b.loadLogs()['bench']!.single.value, 100);
    expect(b.loadLogs()['bench']!.single.bodyweight, 80);
    expect(b.loadLogs()['eye']!.single.value, -0.1);
    expect(b.loadHabits().single.title, 'Train');
    expect(b.loadCompletions()['h1']!.contains('2026-06-27'), isTrue);
    expect(b.loadFood().single.name, 'Eggs');
    expect(b.loadFood().single.health['fibre'], 20);
    expect(b.loadWorkouts().single.summary['calories'], 400);
    expect(b.loadPins().single.a, 'sleep_score');
  });

  test('AI verdict backup is bounded to recent days (recomputable, pushed every sync)', () {
    final a = InMemoryRepository();
    final today = DateTime.now();
    String k(int daysAgo) {
      final d = today.subtract(Duration(days: daysAgo));
      return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }
    a.setAiVerdict('h1', k(3), true);     // recent — kept
    a.setAiVerdict('h1', k(400), true);   // ancient — dropped from the blob
    final snap = repoExport(a);
    final verdicts = (snap['aiVerdicts'] as Map)['h1'] as Map;
    expect(verdicts.containsKey(k(3)), isTrue);
    expect(verdicts.containsKey(k(400)), isFalse);
    // Local storage still has both — only the exported blob is trimmed.
    expect(a.loadAiVerdicts()['h1']!.length, 2);
  });
}

void _mergeTests() {
  test('repoMerge unions without clobbering or duplicating', () {
    // Device A (cloud snapshot): bench@t1 + food fA.
    final a = InMemoryRepository();
    a.saveLog('bench', Log('bench', 100, ts: 't1'));
    a.saveFood(const FoodEntry(id: 'fA', dateKey: 'd', name: 'A'));
    final cloud = repoExport(a);

    // Device B (local): bench@t1 (same) + bench@t2 (new) + food fB.
    final b = InMemoryRepository();
    b.saveLog('bench', Log('bench', 100, ts: 't1'));
    b.saveLog('bench', Log('bench', 120, ts: 't2'));
    b.saveFood(const FoodEntry(id: 'fB', dateKey: 'd', name: 'B'));

    repoMerge(b, cloud);

    // bench has t1 (deduped, not doubled) + t2; both foods survive.
    expect(b.loadLogs()['bench']!.length, 2);
    expect(b.loadFood().map((f) => f.id).toSet(), {'fA', 'fB'});
  });
}
