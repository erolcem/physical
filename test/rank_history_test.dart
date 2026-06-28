import 'package:flutter_test/flutter_test.dart';
import 'package:physical/data/repository.dart';
import 'package:physical/data/rank_history.dart';
import 'package:physical/engine/rank_engine.dart' show Log;

void main() {
  test('rankSeries produces overall + category ranks per day', () {
    final logs = {
      'bench': [Log('bench', 100, bodyweight: 80, ts: '2026-06-26T10:00:00'),
                Log('bench', 120, bodyweight: 80, ts: '2026-06-27T10:00:00')],
      'vo2max': [Log('vo2max', 52, ts: '2026-06-27T10:00:00')],
      'eye': [Log('eye', -0.1, ts: '2026-06-27T10:00:00')],
    };
    final s = rankSeries(logs);
    expect(s.containsKey('overall_rank'), isTrue);
    expect(s.containsKey('strength_rank'), isTrue);
    expect(s.containsKey('performance_rank'), isTrue);
    expect(s.containsKey('aesthetics_rank'), isTrue);
    // strength rank should rise from the 26th (100kg) to the 27th (120kg)
    expect(s['strength_rank']!['2026-06-27']! >= s['strength_rank']!['2026-06-26']!, isTrue);
  });

  test('backfillRankLogs persists rank logs, idempotently', () {
    final repo = InMemoryRepository();
    repo.saveLog('bench', Log('bench', 100, bodyweight: 80, ts: '2026-06-27T10:00:00'));
    repo.saveLog('vo2max', Log('vo2max', 52, ts: '2026-06-27T10:00:00'));
    final added = backfillRankLogs(repo);
    expect(added, greaterThan(0));
    expect(repo.loadLogs()['overall_rank']!.single.ts.startsWith('2026-06-27'), isTrue);
    // running again adds nothing (idempotent)
    expect(backfillRankLogs(repo), 0);
  });
}
