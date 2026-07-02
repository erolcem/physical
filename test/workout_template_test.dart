// Workout templates (Hevy-style fast logging): model round-trip, repository
// storage, and backup export/import.
import 'package:flutter_test/flutter_test.dart';
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
    final back = WorkoutTemplate.fromJson(t.toJson());
    expect(back.name, 'Push day');
    expect(back.sets.length, 3);
    expect(back.sets.first.weight, 80);
    expect(back.sets.last.name, 'OHP');
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
}
