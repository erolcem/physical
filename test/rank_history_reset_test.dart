// Live rank history: backfills REPLACE stale day values when underlying data
// changes, and resetDerivedHistory rebuilds the series from current data only.
import 'package:flutter_test/flutter_test.dart';
import 'package:physical/data/rank_history.dart';
import 'package:physical/data/readiness.dart';
import 'package:physical/data/repository.dart';
import 'package:physical/engine/rank_engine.dart' show Log;

void main() {
  test('backfillRankLogs replaces a stale day when data changed', () {
    final repo = InMemoryRepository();
    repo.saveLog('bench', Log('bench', 80, bodyweight: 80, ts: '2026-06-01T08:00:00'));
    expect(backfillRankLogs(repo), greaterThan(0));
    final before = repo.loadLogs()['overall_rank']!
        .firstWhere((l) => l.ts.startsWith('2026-06-01')).value;
    // A much stronger bench logged ON THE SAME DAY changes that day's rank.
    repo.saveLog('bench', Log('bench', 140, bodyweight: 80, ts: '2026-06-01T18:00:00'));
    expect(backfillRankLogs(repo), greaterThan(0));
    final after = repo.loadLogs()['overall_rank']!
        .firstWhere((l) => l.ts.startsWith('2026-06-01')).value;
    expect(after, greaterThan(before)); // replaced in place, not frozen
    expect(
        repo.loadLogs()['overall_rank']!
            .where((l) => l.ts.startsWith('2026-06-01'))
            .length,
        1);
  });

  test('resetDerivedHistory rebuilds the series from current data only', () {
    final repo = InMemoryRepository();
    repo.saveLog('bench', Log('bench', 100, bodyweight: 80, ts: '2026-06-01T08:00:00'));
    backfillRankLogs(repo);
    expect(repo.loadLogs()['overall_rank'], isNotEmpty);
    expect(repo.loadLogs()['strength_rank'], isNotEmpty);
    // Delete the only underlying log — the old rank history must NOT survive a reset.
    repo.deleteLog('bench', 0);
    final rebuilt = resetDerivedHistory(repo, readinessBackfill: backfillReadinessLogs);
    expect(rebuilt, 0); // nothing left to derive from
    expect(repo.loadLogs()['overall_rank'] ?? const <Log>[], isEmpty);
    expect(repo.loadLogs()['strength_rank'] ?? const <Log>[], isEmpty);
    // And it can rebuild again after new data arrives (no tombstone blockage).
    repo.saveLog('bench', Log('bench', 90, bodyweight: 80, ts: '2026-06-02T08:00:00'));
    expect(backfillRankLogs(repo), greaterThan(0));
    expect(repo.loadLogs()['overall_rank'], isNotEmpty);
  });

  test('derived series never ride the backup — a sync cannot undo a reset', () {
    // The bug: rank history was reset locally, but old *_rank logs in the cloud
    // backup snapshot merged straight back in on the next sync.
    final repo = InMemoryRepository();
    repo.saveLog('bench', Log('bench', 140, bodyweight: 80, ts: '2026-06-01T08:00:00'));
    backfillRankLogs(repo);
    final cloud = repoExport(repo); // snapshot taken while rank history existed
    expect((cloud['logs'] as Map).containsKey('overall_rank'), isFalse); // excluded
    expect((cloud['logs'] as Map).containsKey('bench'), isTrue);
    // Even a LEGACY snapshot that still carries derived logs can't reinfect.
    final legacy = repoExport(repo);
    (legacy['logs'] as Map)['overall_rank'] = [
      {'v': 7.5, 'ts': '2026-05-01T12:00:00'}
    ];
    resetDerivedHistory(repo, readinessBackfill: backfillReadinessLogs);
    repoMerge(repo, legacy);
    final ranks = repo.loadLogs()['overall_rank'] ?? const <Log>[];
    expect(ranks.where((l) => l.ts.startsWith('2026-05-01')), isEmpty);
    final restored = InMemoryRepository();
    repoImport(restored, legacy);
    expect(restored.loadLogs()['overall_rank'] ?? const <Log>[], isEmpty);
  });
}
