import 'package:flutter_test/flutter_test.dart';
import 'package:physical/data/repository.dart';
import 'package:physical/data/sync.dart' show mergeSamples;
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
}
