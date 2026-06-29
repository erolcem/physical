import 'package:flutter_test/flutter_test.dart';
import 'package:physical/data/repository.dart';
import 'package:physical/data/diet.dart';

void main() {
  test('saveFood upserts by id — re-saving an enriched food does not duplicate it', () {
    final repo = InMemoryRepository();
    repo.saveFood(const FoodEntry(id: 'g:1', dateKey: '2026-06-28', name: 'Eggs',
        calories: 200, protein: 18));
    // enrichFoodHealth re-saves the SAME id with health axes added.
    repo.saveFood(const FoodEntry(id: 'g:1', dateKey: '2026-06-28', name: 'Eggs',
        calories: 200, protein: 18, health: {'micronutrients': 30}));
    final food = repo.loadFood();
    expect(food.length, 1, reason: 'must replace, not append');
    expect(food.single.health['micronutrients'], 30);
    // Day totals reflect ONE serving, not two.
    expect(dietTotals(food, '2026-06-28').calories, 200);
  });
}
