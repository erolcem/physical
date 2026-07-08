// DOB-derived age: the 'age' log refreshes itself on birthdays instead of
// freezing at whatever was typed, and DOB rides the backup.
import 'package:flutter_test/flutter_test.dart';
import 'package:physical/data/pins.dart';
import 'package:physical/data/profile.dart';
import 'package:physical/data/repository.dart';
import 'package:physical/engine/rank_engine.dart' show Log;

void main() {
  group('ageOn', () {
    final dob = DateTime(2000, 6, 15);
    test('birthday not yet reached this year', () =>
        expect(ageOn(dob, today: DateTime(2026, 6, 14)), 25));
    test('on the birthday itself', () =>
        expect(ageOn(dob, today: DateTime(2026, 6, 15)), 26));
    test('after the birthday', () =>
        expect(ageOn(dob, today: DateTime(2026, 12, 1)), 26));
  });

  group('syncAgeFromDob', () {
    test('no DOB → no-op', () {
      final repo = InMemoryRepository();
      expect(syncAgeFromDob(repo), isNull);
      expect(repo.loadLogs()['age'], isNull);
    });

    test('logs the derived age once, then stays quiet until it changes', () {
      final repo = InMemoryRepository()..saveDob('2000-06-15');
      expect(syncAgeFromDob(repo, today: DateTime(2026, 7, 7)), 26);
      // Same day / same age → nothing new appended.
      expect(syncAgeFromDob(repo, today: DateTime(2026, 7, 8)), isNull);
      expect(repo.loadLogs()['age'], hasLength(1));
      // A birthday passes → the age auto-corrects with a fresh log.
      expect(syncAgeFromDob(repo, today: DateTime(2027, 6, 15)), 27);
      expect(repo.loadLogs()['age'], hasLength(2));
      expect(repo.loadLogs()['age']!.last.value, 27);
    });

    test('overrides a stale typed age', () {
      final repo = InMemoryRepository()
        ..saveLog('age', Log('age', 23, ts: '2024-01-01T00:00:00'))
        ..saveDob('2000-06-15');
      expect(syncAgeFromDob(repo, today: DateTime(2026, 7, 7)), 26);
    });
  });

  group('backup carries profile facts', () {
    test('dob + AI pins ride export/import/merge; pin deletes stick', () {
      final a = InMemoryRepository()..saveDob('2000-06-15');
      a.saveAiPin(const AiPin(id: 'p1', text: 'Cutting to 78 kg', createdAt: 'x'));
      a.saveAiPin(const AiPin(id: 'p2', text: 'Knee rehab — no deep squats', createdAt: 'x'));
      final snap = repoExport(a);

      final b = InMemoryRepository();
      repoImport(b, snap);
      expect(b.loadDob(), '2000-06-15');
      expect(b.loadAiPins().map((p) => p.id), containsAll(['p1', 'p2']));

      // Delete p1 on device B — the tombstone must beat A's copy on merge.
      b.deleteAiPin('p1');
      repoMerge(b, snap);
      expect(b.loadAiPins().map((p) => p.id), ['p2']);
      // And merging B's state into a third device propagates the delete.
      final c = InMemoryRepository();
      repoMerge(c, repoExport(b));
      expect(c.loadAiPins().map((p) => p.id), ['p2']);
      expect(c.loadDob(), '2000-06-15');
      // Merge never clobbers a locally-set DOB.
      final d = InMemoryRepository()..saveDob('1999-01-01');
      repoMerge(d, snap);
      expect(d.loadDob(), '1999-01-01');
    });
  });

  group('daily AI briefing times', () {
    test('default 8/20, saved, clamped to 0..23, and stay a LOCAL preference', () {
      final repo = InMemoryRepository();
      expect(repo.loadMorningNudgeHour(), 8);
      expect(repo.loadEveningNudgeHour(), 20);
      repo.saveNudgeHours(6, 22);
      expect(repo.loadMorningNudgeHour(), 6);
      expect(repo.loadEveningNudgeHour(), 22);
      repo.saveNudgeHours(-3, 99);
      expect(repo.loadMorningNudgeHour(), 0);
      expect(repo.loadEveningNudgeHour(), 23);
      // Device notification times don't ride the cloud backup.
      expect(repoExport(repo).containsKey('morningNudge'), isFalse);
      final restored = InMemoryRepository();
      repoImport(restored, repoExport(repo));
      expect(restored.loadMorningNudgeHour(), 8); // its own default, not synced
    });
  });
}
