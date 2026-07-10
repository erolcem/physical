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
// contributes points per axis = its AI-rated quality DENSITY (0–100, portion-
// independent) × its share of a 2000-kcal reference day; points ACCUMULATE across
// the day and cap at 100, and the overall diet-health score averages all axes.
// The FIBRE and MICRONUTRIENT axes don't rely on the AI at all — they're computed
// EXACTLY from the day's logged grams vs the daily targets below, so those two
// spokes of the web are real measurements, not estimates.
const Map<String, String> healthAxisLabels = {
  'micronutrients': 'Micronutrients',
  'fibre': 'Fibre',
  'gut_health': 'Gut Health',
  'antioxidants': 'Antioxidants',
  'healthy_fats': 'Healthy Fats',
  'whole_food': 'Whole-food',
};

/// Daily fibre target (g) — the axis hits 100 at this intake (AHA/NHS guidance ~30 g).
const double fibreTargetG = 30.0;

/// Daily reference intakes for the tracked "more is better" micronutrients
/// (young-male RDA/AI values; sodium excluded — it's an upper-limit nutrient).
const Map<String, double> microDailyTarget = {
  'potassium_mg': 3400,
  'calcium_mg': 1000,
  'iron_mg': 8,
  'magnesium_mg': 400,
  'zinc_mg': 11,
  'vitamin_c_mg': 90,
  'vitamin_d_ug': 15,
};

/// Micronutrient adequacy 0–100: the mean of each tracked micro's intake vs its
/// daily target (capped at 100% each, so megadosing one vitamin can't carry the
/// score). This is the exact math behind the radar's Micronutrients spoke.
double microAdequacy(Map<String, double> micros) {
  var s = 0.0;
  microDailyTarget.forEach((k, target) {
    s += ((micros[k] ?? 0) / target).clamp(0.0, 1.0);
  });
  return s / microDailyTarget.length * 100;
}

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

  FoodEntry copyWith({Map<String, double>? micros, Map<String, double>? health}) =>
      FoodEntry(
        id: id, dateKey: dateKey, name: name, calories: calories, protein: protein,
        carbs: carbs, fat: fat, fibre: fibre, micros: micros ?? this.micros,
        health: health ?? this.health, source: source, googleId: googleId,
      );

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

/// Sedentary TDEE multiplier: basal + everyday non-exercise activity (walking
/// around, digestion, fidgeting). The standard 1.2 factor; tracked workouts are
/// added separately on top.
const double sedentaryFactor = 1.2;

/// Estimated TOTAL daily energy burn (kcal/day): BMR × 1.2 + tracked workout
/// calories. Raw BMR under-reads a real day by ~20% (it excludes all movement),
/// which made the energy balance show a phantom surplus on every unsynced day —
/// the estimate must be honest or the surplus/deficit readout misleads.
double estimatedDailyBurn(double weightKg, double heightCm, int age,
        {double activeKcal = 0}) =>
    bmrMifflin(weightKg, heightCm, age) * sedentaryFactor + activeKcal;

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
  if (n > 0) {
    // Exact axes override the AI estimates where the quantity is measured:
    // fibre from logged grams vs the 30 g/day target, micronutrients from the
    // summed micros vs their daily targets (when any have been inferred).
    hl['fibre'] = (fib / fibreTargetG * 100).clamp(0.0, 100.0);
    if (mic.values.any((v) => v > 0)) hl['micronutrients'] = microAdequacy(mic);
  }
  return DietTotals(c, p, cb, f, fib, n, micros: mic, health: hl);
}

DietTotals todayDiet(List<FoodEntry> entries) => dietTotals(entries, todayKey());

List<FoodEntry> entriesFor(List<FoodEntry> entries, String day) =>
    [for (final e in entries) if (e.dateKey == day) e];

/// Calories per day over the last [n] days (oldest first) — the diet trend chart.
List<double> caloriesLastNDays(List<FoodEntry> entries, {int n = 7, DateTime? today}) =>
    [for (final day in lastNDays(n, today: today)) dietTotals(entries, day).calories];
