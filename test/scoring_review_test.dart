import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:physical/data/repository.dart';
import 'package:physical/engine/rank_engine.dart' show Log;
import 'package:physical/state/providers.dart';

void main() {
  test('partial logging yields a low overall; full strong logging is high', () {
    // Only 2 strong metrics logged of the whole roster → overall should be low (Wood/Bronze).
    final partial = InMemoryRepository();
    partial.saveLog('bench', Log('bench', 140, bodyweight: 80, ts: '2026-06-28T10:00:00'));
    partial.saveLog('vo2max', Log('vo2max', 60, ts: '2026-06-28T10:00:00'));
    final cp = ProviderContainer(overrides: [repositoryProvider.overrideWithValue(partial)]);
    addTearDown(cp.dispose);
    final ovPartial = cp.read(overallProvider);
    expect(ovPartial.rankValue, lessThan(3.0), reason: 'mostly-unlogged roster floors the rank');
    expect(cp.read(categoryRanksProvider).length, 4, reason: 'all ranked categories present');

    // A blank repo → Wood (everything unrated = worst).
    final blank = ProviderContainer(overrides: [repositoryProvider.overrideWithValue(InMemoryRepository())]);
    addTearDown(blank.dispose);
    expect(blank.read(overallProvider).tier, 'Wood');
  });
}
