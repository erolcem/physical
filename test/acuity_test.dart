// Pure acuity math: optotype sizing (physical-angle correct) + Snellen conversion.
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:physical/ui/acuity_test.dart';

void main() {
  test('snellen maps logMAR to 20/xx', () {
    expect(snellen(0.0), '20/20');
    expect(snellen(1.0), '20/200'); // 20 × 10^1
    expect(snellen(-0.3), '20/10'); // 20 × 10^-0.3 ≈ 10
    expect(snellen(0.3), '20/40'); // 20 × 10^0.3 ≈ 40
  });

  test('optotype grows 10× per +1 logMAR and scales with distance + px/mm', () {
    final a = optotypePx(0.0, 400, 5.0); // 20/20 at 40cm
    final b = optotypePx(1.0, 400, 5.0); // 20/200 at 40cm — 10× taller
    expect(b / a, closeTo(10.0, 0.05));
    // Doubling distance doubles the physical size (small-angle linear).
    expect(optotypePx(0.0, 800, 5.0) / a, closeTo(2.0, 0.02));
    // Doubling px/mm doubles the rendered px.
    expect(optotypePx(0.0, 400, 10.0) / a, closeTo(2.0, 1e-9));
  });

  test('20/20 letter subtends ~5 arcmin (physically correct)', () {
    // At 1 m, px/mm = 1 → height in mm. 5 arcmin → ~1.454 mm.
    final mm = optotypePx(0.0, 1000, 1.0);
    final expectedMm = 2 * 1000 * math.tan(5 * (math.pi / 180 / 60) / 2);
    expect(mm, closeTo(expectedMm, 1e-6));
    expect(mm, closeTo(1.454, 0.01));
  });
}
