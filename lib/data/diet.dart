// data/diet.dart — diet/food logging (PDF Part 1: "Food logs" = name + macros →
// energy + protein, micro scores in-app). A food entry per item; daily totals are
// the AI- and UI-facing rollup. Each entry carries macros (incl. fibre) and a map
// of micronutrients (Gemini-inferred at log time; canonical unit-suffixed keys like
// sodium_mg / vitamin_d_ug). Pure model + logic, unit-tested.
import 'habits.dart' show lastNDays, todayKey;

// Canonical micronutrients + display labels (units are baked into the key, matching
// the backend's nutrition.MICRO_UNITS so values sum cleanly across foods).
const Map<String, String> microLabels = {
  'sodium_mg': 'Sodium',
  'potassium_mg': 'Potassium',
  'calcium_mg': 'Calcium',
  'iron_mg': 'Iron',
  'magnesium_mg': 'Magnesium',
  'zinc_mg': 'Zinc',
  'vitamin_c_mg': 'Vitamin C',
  'vitamin_d_ug': 'Vitamin D',
};

String microUnit(String key) => key.endsWith('_ug') ? 'µg' : 'mg';

// Diet-health radar axes (keys match the backend nutrition.HEALTH_AXES). Each food
// contributes 0–100 points per axis (portion-scaled, AI-inferred); points ACCUMULATE
// across the day and cap at 100, and the overall diet-health score averages all axes.
const Map<String, String> healthAxisLabels = {
  'micronutrients': 'Micronutrients',
  'fibre': 'Fibre',
  'gut_health': 'Gut Health',
  'antioxidants': 'Antioxidants',
  'healthy_fats': 'Healthy Fats',
  'whole_food': 'Whole-food',
};

class FoodEntry {
  final String id;
  final String dateKey; // YYYY-MM-DD
  final String name;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final double fibre;
  final Map<String, double> micros;
  final Map<String, double> health; // diet-health axis points (0–100 per axis)
  final String source; // 'manual' | 'google'
  final String? googleId; // nutrition-log datapoint id (dedupe imports)

  const FoodEntry({
    required this.id,
    required this.dateKey,
    required this.name,
    this.calories = 0,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
    this.fibre = 0,
    this.micros = const {},
    this.health = const {},
    this.source = 'manual',
    this.googleId,
  });

  bool get fromGoogle => source == 'google';

  /// Build from a parsed Google nutrition-log food dict (macros only; no health axes).
  factory FoodEntry.fromGoogle(Map<String, dynamic> g) => FoodEntry(
        id: 'g:${g['google_id']}',
        dateKey: g['day'] as String,
        name: (g['name'] as String?) ?? 'Food',
        calories: (g['calories'] as num?)?.toDouble() ?? 0,
        protein: (g['protein'] as num?)?.toDouble() ?? 0,
        carbs: (g['carbs'] as num?)?.toDouble() ?? 0,
        fat: (g['fat'] as num?)?.toDouble() ?? 0,
        fibre: (g['fibre'] as num?)?.toDouble() ?? 0,
        source: 'google',
        googleId: g['google_id'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'day': dateKey, 'name': name,
        'kcal': calories, 'p': protein, 'c': carbs, 'f': fat, 'fib': fibre,
        if (micros.isNotEmpty) 'mic': micros,
        if (health.isNotEmpty) 'hl': health,
        if (source != 'manual') 'src': source,
        if (googleId != null) 'gid': googleId,
      };

  factory FoodEntry.fromJson(Map<String, dynamic> j) => FoodEntry(
        id: j['id'] as String,
        dateKey: j['day'] as String,
        name: j['name'] as String,
        calories: (j['kcal'] as num?)?.toDouble() ?? 0,
        protein: (j['p'] as num?)?.toDouble() ?? 0,
        carbs: (j['c'] as num?)?.toDouble() ?? 0,
        fat: (j['f'] as num?)?.toDouble() ?? 0,
        fibre: (j['fib'] as num?)?.toDouble() ?? 0,
        micros: {
          for (final e in ((j['mic'] as Map?) ?? const {}).entries)
            e.key as String: (e.value as num).toDouble()
        },
        health: {
          for (final e in ((j['hl'] as Map?) ?? const {}).entries)
            e.key as String: (e.value as num).toDouble()
        },
        source: j['src'] as String? ?? 'manual',
        googleId: j['gid'] as String?,
      );
}

class DietTotals {
  final double calories, protein, carbs, fat, fibre;
  final int items;
  final Map<String, double> micros;
  final Map<String, double> health; // accumulated axis points, capped 100 each
  const DietTotals(this.calories, this.protein, this.carbs, this.fat, this.fibre,
      this.items, {this.micros = const {}, this.health = const {}});
  static const zero = DietTotals(0, 0, 0, 0, 0, 0);

  /// Macro split of total energy (4/4/9 kcal per g of P/C/F), for the breakdown bar.
  double get proteinKcal => protein * 4;
  double get carbsKcal => carbs * 4;
  double get fatKcal => fat * 9;

  /// Overall diet-health score (0–100): the average across ALL radar axes of the
  /// day's accumulated (capped) points — so a balanced, whole-food day scores high.
  double get healthScore {
    final keys = healthAxisLabels.keys;
    final sum = keys.fold(0.0, (a, k) => a + (health[k] ?? 0).clamp(0.0, 100.0));
    return keys.isEmpty ? 0 : sum / keys.length;
  }
}

/// Mifflin–St Jeor basal metabolic rate (kcal/day) for a male.
double bmrMifflin(double weightKg, double heightCm, int age) =>
    10 * weightKg + 6.25 * heightCm - 5 * age + 5;

DietTotals dietTotals(List<FoodEntry> entries, String day) {
  var c = 0.0, p = 0.0, cb = 0.0, f = 0.0, fib = 0.0, n = 0;
  final mic = <String, double>{};
  final hl = <String, double>{};
  for (final e in entries) {
    if (e.dateKey != day) continue;
    c += e.calories;
    p += e.protein;
    cb += e.carbs;
    f += e.fat;
    fib += e.fibre;
    e.micros.forEach((k, v) => mic[k] = (mic[k] ?? 0) + v);
    // Health axis points accumulate across the day, capped at 100 per axis.
    e.health.forEach((k, v) => hl[k] = ((hl[k] ?? 0) + v).clamp(0.0, 100.0));
    n++;
  }
  return DietTotals(c, p, cb, f, fib, n, micros: mic, health: hl);
}

DietTotals todayDiet(List<FoodEntry> entries) => dietTotals(entries, todayKey());

List<FoodEntry> entriesFor(List<FoodEntry> entries, String day) =>
    [for (final e in entries) if (e.dateKey == day) e];

/// Calories per day over the last [n] days (oldest first) — the diet trend chart.
List<double> caloriesLastNDays(List<FoodEntry> entries, {int n = 7, DateTime? today}) =>
    [for (final day in lastNDays(n, today: today)) dietTotals(entries, day).calories];
