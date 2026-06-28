import 'package:flutter_test/flutter_test.dart';
import 'package:physical/data/achievements.dart';
import 'package:physical/engine/rank_engine.dart' show Log;

void main() {
  test('records one trophy per new overall-rank personal best', () {
    final logs = [
      Log('overall_rank', 1.2, ts: '2026-01-01T12:00:00'), // Bronze I  (level 3)
      Log('overall_rank', 1.5, ts: '2026-01-02T12:00:00'), // Bronze II (level 4)
      Log('overall_rank', 1.4, ts: '2026-01-03T12:00:00'), // dip — no new trophy
      Log('overall_rank', 3.7, ts: '2026-01-04T12:00:00'), // Gold III (level 11)
    ];
    final a = overallAchievements(logs);
    expect(a.length, 3);
    expect(a.first.date, '2026-01-01');
    expect(a.last.tier, 'Gold');
    expect(a.last.sub, 'III');
    // levels strictly increasing
    for (var i = 1; i < a.length; i++) {
      expect(a[i].level > a[i - 1].level, isTrue);
    }
  });

  test('empty history → no trophies', () {
    expect(overallAchievements(const []), isEmpty);
  });
}
