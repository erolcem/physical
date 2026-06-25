// Strategic correlations: Pearson math, day-alignment, pin model, and repo pins.
import 'package:flutter_test/flutter_test.dart';
import 'package:physical/data/correlation.dart';
import 'package:physical/data/repository.dart';
import 'package:physical/engine/rank_engine.dart' show Log;

void main() {
  group('pearson', () {
    test('perfect positive = 1, perfect negative = -1', () {
      expect(pearson([1, 2, 3], [2, 4, 6]), closeTo(1.0, 1e-9));
      expect(pearson([1, 2, 3], [3, 2, 1]), closeTo(-1.0, 1e-9));
    });
    test('guards: <2 points or flat series → 0', () {
      expect(pearson([1], [1]), 0);
      expect(pearson([5, 5, 5], [1, 2, 3]), 0);
    });
  });

  group('alignByDay / correlationOf', () {
    List<Log> mk(Map<String, double> byDay) =>
        [for (final e in byDay.entries) Log('m', e.value, ts: '${e.key}T00:00:00')];

    test('aligns on shared days only', () {
      final (xs, ys) = alignByDay(
        mk({'2026-06-21': 1, '2026-06-22': 2, '2026-06-23': 3}),
        mk({'2026-06-22': 20, '2026-06-23': 30, '2026-06-24': 99}),
      );
      expect(xs, [2, 3]); // 22 & 23 overlap
      expect(ys, [20, 30]);
    });

    test('correlationOf needs ≥3 overlapping days', () {
      final a = mk({'d1': 1, 'd2': 2});
      expect(correlationOf(a, a), isNull); // only 2 points
    });
  });

  group('PinnedCorrelation', () {
    test('key is order-independent', () {
      expect(const PinnedCorrelation('a', 'b').key, const PinnedCorrelation('b', 'a').key);
    });
    test('correlationLabel buckets by strength + sign', () {
      expect(correlationLabel(0.8), 'strong positive');
      expect(correlationLabel(-0.5), 'moderate negative');
      expect(correlationLabel(0.05), 'no clear');
    });
  });

  group('repository pins', () {
    test('add dedupes by pair, remove + clear work', () {
      final r = InMemoryRepository();
      r.addPin(const PinnedCorrelation('sleep_score', 'bench'));
      r.addPin(const PinnedCorrelation('bench', 'sleep_score')); // same pair → no dupe
      expect(r.loadPins().length, 1);
      r.removePin(const PinnedCorrelation('sleep_score', 'bench').key);
      expect(r.loadPins(), isEmpty);
    });
  });
}
