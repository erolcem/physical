// Grooming weighted self-rating math.
import 'package:flutter_test/flutter_test.dart';
import 'package:physical/ui/grooming_checklist.dart';

void main() {
  test('all-equal ratings return that value (weights sum to 1)', () {
    final r = {for (final it in groomingItems) it.$1: 80.0};
    expect(groomingScore(r), closeTo(80.0, 1e-9));
  });

  test('weights bias the score toward heavier domains', () {
    // Perfect on the two 25% domains (haircut + facial hair), zero elsewhere → 50.
    final r = {for (final it in groomingItems) it.$1: 0.0};
    r['Haircut freshness'] = 100;
    r['Facial hair'] = 100;
    expect(groomingScore(r), closeTo(50.0, 1e-9)); // 0.25 + 0.25
  });

  test('missing domains count as 0', () {
    expect(groomingScore({'Nails': 100}), closeTo(15.0, 1e-9)); // nails weight 0.15
  });
}
