// data/diet.dart — diet/food logging (PDF Part 1: "Food logs" = name + macros →
// energy requirement; micro scores computed in-app). A food entry per item;
// daily totals are the AI- and UI-facing rollup. Pure model + logic, unit-tested.
import 'habits.dart' show todayKey;

class FoodEntry {
  final String id;
  final String dateKey; // YYYY-MM-DD
  final String name;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;

  const FoodEntry({
    required this.id,
    required this.dateKey,
    required this.name,
    this.calories = 0,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id, 'day': dateKey, 'name': name,
        'kcal': calories, 'p': protein, 'c': carbs, 'f': fat,
      };

  factory FoodEntry.fromJson(Map<String, dynamic> j) => FoodEntry(
        id: j['id'] as String,
        dateKey: j['day'] as String,
        name: j['name'] as String,
        calories: (j['kcal'] as num?)?.toDouble() ?? 0,
        protein: (j['p'] as num?)?.toDouble() ?? 0,
        carbs: (j['c'] as num?)?.toDouble() ?? 0,
        fat: (j['f'] as num?)?.toDouble() ?? 0,
      );
}

class DietTotals {
  final double calories, protein, carbs, fat;
  final int items;
  const DietTotals(this.calories, this.protein, this.carbs, this.fat, this.items);
  static const zero = DietTotals(0, 0, 0, 0, 0);
}

DietTotals dietTotals(List<FoodEntry> entries, String day) {
  var c = 0.0, p = 0.0, cb = 0.0, f = 0.0, n = 0;
  for (final e in entries) {
    if (e.dateKey != day) continue;
    c += e.calories;
    p += e.protein;
    cb += e.carbs;
    f += e.fat;
    n++;
  }
  return DietTotals(c, p, cb, f, n);
}

DietTotals todayDiet(List<FoodEntry> entries) => dietTotals(entries, todayKey());

List<FoodEntry> entriesFor(List<FoodEntry> entries, String day) =>
    [for (final e in entries) if (e.dateKey == day) e];
