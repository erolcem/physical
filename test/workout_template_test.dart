// Workout templates (Hevy-style fast logging): model round-trip, repository
// storage, and backup export/import.
import 'package:flutter_test/flutter_test.dart';
import 'package:physical/data/habits.dart' show Habit;
import 'package:physical/data/repository.dart';
import 'package:physical/data/workout.dart';

void main() {
  const sets = [
    WorkoutSet(name: 'Bench', mode: SetMode.weightReps, weight: 80, reps: 5),
    WorkoutSet(name: 'Bench', mode: SetMode.weightReps, weight: 80, reps: 5),
    WorkoutSet(name: 'OHP', mode: SetMode.weightReps, weight: 45, reps: 8),
  ];

  test('template json round-trip + fromSession snapshot', () {
    const s = WorkoutSession(
        id: 'w1', type: 'Weightlifting', title: 'Push day',
        start: '2026-07-01T10:00:00', sets: sets);
    final t = WorkoutTemplate.fromSession(s, name: 'Push day');
    expect(t.type, 'Weightlifting');
    expect(t.setCount, 3);
    expect(t.exercises, {'Bench', 'OHP'});
    // A template captures STRUCTURE only — exercises + set counts, no loads (you
    // can't predict a future workout's weights). The values are stripped.
    expect(t.sets.every((x) => x.isBlank), isTrue);
    final back = WorkoutTemplate.fromJson(t.toJson());
    expect(back.name, 'Push day');
    expect(back.sets.length, 3);
    expect(back.sets.first.weight, isNull);
    expect(back.sets.last.name, 'OHP');
    // blankSets always yields empty slots even from a legacy template with values.
    const legacy = WorkoutTemplate(id: 'x', name: 'L', sets: sets);
    expect(legacy.blankSets.every((x) => x.isBlank), isTrue);
    expect(legacy.blankSets.map((x) => x.name).toList(), ['Bench', 'Bench', 'OHP']);
  });

  test('repository stores templates (upsert by id) and deletes them', () {
    final repo = InMemoryRepository();
    const t = WorkoutTemplate(id: 'tp1', name: 'Push', sets: sets);
    repo.saveTemplate(t);
    expect(repo.loadTemplates().single.name, 'Push');
    repo.saveTemplate(const WorkoutTemplate(id: 'tp1', name: 'Push v2', sets: sets));
    expect(repo.loadTemplates().single.name, 'Push v2'); // upsert, no dupe
    repo.deleteTemplate('tp1');
    expect(repo.loadTemplates(), isEmpty);
  });

  test('templates + AI verdicts survive export/import and merge', () {
    final a = InMemoryRepository();
    a.saveTemplate(const WorkoutTemplate(id: 'tp1', name: 'Push', sets: sets));
    a.setAiVerdict('h1', '2026-07-01', true);
    final b = InMemoryRepository();
    repoImport(b, repoExport(a));
    expect(b.loadTemplates().single.name, 'Push');
    expect(b.loadAiVerdicts()['h1']!['2026-07-01'], isTrue);
    // Merge unions without duplicating.
    repoMerge(b, repoExport(a));
    expect(b.loadTemplates().length, 1);
  });

  test('habit carries its workout plan: templateId round-trips', () {
    // The habit IS the plan: an exercise habit links the template it starts.
    const h = Habit(id: 'h1', title: 'Push day', section: 'exercise',
        verify: 'workout', templateId: 'tp1', cadence: 'weekly', days: [1, 4],
        createdAt: '2026-07-01T00:00:00');
    final back = Habit.fromJson(h.toJson());
    expect(back.templateId, 'tp1');
    expect(back.days, [1, 4]);
    // And a habit without a plan stays without one.
    const plain = Habit(id: 'h2', title: 'Read', createdAt: '2026-07-01T00:00:00');
    expect(Habit.fromJson(plain.toJson()).templateId, isNull);
  });
}
