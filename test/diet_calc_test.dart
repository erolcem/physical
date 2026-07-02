import 'package:flutter_test/flutter_test.dart';
import 'package:physical/data/diet.dart';

void main() {
  const day = '2026-06-28';
  test('health axes accumulate (capped 100/axis); score = mean of all axes', () {
    final food = [
      const FoodEntry(id: 'a', dateKey: day, name: 'x', calories: 500, protein: 40,
          fibre: 12, health: {'micronutrients': 60, 'fibre': 40}),
      const FoodEntry(id: 'b', dateKey: day, name: 'y', calories: 400, protein: 30,
          fibre: 3, health: {'micronutrients': 60, 'gut_health': 50}),
    ];
    final t = dietTotals(food, day);
    // AI-estimated axes accumulate, capped at 100 — no micros were logged, so
    // the micronutrient axis stays the accumulated AI estimate (60+60 capped).
    expect(t.health['micronutrients'], 100);
    expect(t.health['gut_health'], 50);
    // The FIBRE axis is EXACT — logged grams vs the 30 g/day target overrides
    // the AI points: (12+3)/30 = 50.
    expect(t.health['fibre'], closeTo(50, 1e-9));
    // score = (100 + 50 + 50 + 0 + 0 + 0) / 6 axes
    expect(t.healthScore, closeTo(200 / 6, 0.01));
  });

  test('micronutrient axis is exact when micros are logged (mean vs targets)', () {
    final food = [
      const FoodEntry(id: 'a', dateKey: day, name: 'x', calories: 500,
          micros: {'vitamin_c_mg': 90, 'zinc_mg': 5.5}, // 100% + 50% of targets
          health: {'micronutrients': 5}), // the AI estimate is overridden
    ];
    final t = dietTotals(food, day);
    // (1.0 + 0.5 + five micros at 0) / 7 targets = 21.43
    expect(t.health['micronutrients'], closeTo(100 * 1.5 / 7, 0.01));
  });

  test('macros + energy split are correct', () {
    final food = [
      const FoodEntry(id: 'a', dateKey: day, name: 'x', calories: 600, protein: 40, carbs: 50, fat: 20, fibre: 8),
    ];
    final t = dietTotals(food, day);
    expect(t.calories, 600);
    expect(t.protein, 40);
    expect(t.proteinKcal, 160); // 40*4
    expect(t.carbsKcal, 200);   // 50*4
    expect(t.fatKcal, 180);     // 20*9
  });

  test('Mifflin BMR matches the formula', () {
    // 10*80 + 6.25*180 - 5*28 + 5 = 800 + 1125 - 140 + 5 = 1790
    expect(bmrMifflin(80, 180, 28), closeTo(1790, 0.01));
  });
}
