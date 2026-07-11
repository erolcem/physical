// data/metrics.dart — the metric registry. The rest of the app is generated
// from this list (same pattern as the prototype's MUSCLES array), now enriched
// with the three-tier model from the design doc.
import 'package:flutter/material.dart';

enum MetricTier { ranked, tracked, background }

class MetricDef {
  final String id;
  final String label;
  final String category; // strength | performance | recovery | aesthetics | context
  final MetricTier tier;
  final String unit;
  final bool bodyweightScaled; // strength lifts only
  final String input; // 'weight_reps' | 'score'
  final String exercise; // example movement / how to measure
  final String howTo; // one-line logging instructions, shown in the detail sheet
  final bool autoSync; // true if logged automatically via HealthKit/Fitbit
  final bool provisional; // rank comes from a weak/estimated standard — flag it in the UI

  const MetricDef(this.id, this.label, this.category, this.tier, this.unit,
      {this.bodyweightScaled = false, this.input = 'score', this.exercise = '',
      this.howTo = '', this.autoSync = false, this.provisional = false});

  bool get isStrength => input == 'weight_reps';
}

// Only `ranked` metrics with a matching Standard in the engine get a tier.
// `tracked` (aesthetics) and `background` are shown/used but never ranked.
const List<MetricDef> metrics = [
  // ── RANKED · strength (bodyweight-scaled) ──
  MetricDef('bench', 'Chest (Bench)', 'strength', MetricTier.ranked, 'kg',
      bodyweightScaled: true, input: 'weight_reps', exercise: 'Bench Press',
      howTo: 'Barbell bench press. Enter your best set — weight × reps '
          '(reps beyond 12 don\'t add; the app computes an estimated 1RM).'),
  MetricDef('ohp', 'Front Shoulder (OHP)', 'strength', MetricTier.ranked, 'kg',
      bodyweightScaled: true, input: 'weight_reps', exercise: 'Overhead Press',
      howTo: 'Standing barbell press, no leg drive. Enter your best set — weight × reps.'),
  // Isolation lifts: ranked on capped est-1RM from a working set; flagged provisional.
  MetricDef('lateral_raise', 'Medial Shoulder', 'strength', MetricTier.ranked, 'kg·reps',
      bodyweightScaled: true, input: 'weight_reps', exercise: 'Lateral Raise', provisional: true,
      howTo: 'Strict dumbbell lateral raise — ONE dumbbell\'s weight × reps of a working set.'),
  MetricDef('curl', 'Bicep', 'strength', MetricTier.ranked, 'kg·reps',
      bodyweightScaled: true, input: 'weight_reps', exercise: 'Bicep Curl', provisional: true,
      howTo: 'Barbell or single-dumbbell curl, no swing. Working set — weight × reps.'),
  MetricDef('skull_crusher', 'Tricep', 'strength', MetricTier.ranked, 'kg·reps',
      bodyweightScaled: true, input: 'weight_reps', exercise: 'Skull Crusher', provisional: true,
      howTo: 'Lying EZ-bar skull crusher (total bar weight). Working set — weight × reps.'),
  MetricDef('forearm_curl', 'Forearm', 'strength', MetricTier.ranked, 'kg·reps',
      bodyweightScaled: true, input: 'weight_reps', exercise: 'Forearm Curl', provisional: true,
      howTo: 'Seated wrist curl, forearms on thighs. Working set — weight × reps.'),
  MetricDef('pullup', 'Lats (Pullup)', 'strength', MetricTier.ranked, 'kg',
      bodyweightScaled: true, input: 'weight_reps',
      exercise: 'Pullup — total weight: bodyweight + added load',
      howTo: 'Strict pullups. Weight = your bodyweight PLUS any added load '
          '(bodyweight-only → enter your bodyweight), × reps.'),
  MetricDef('hip_thrust', 'Glute', 'strength', MetricTier.ranked, 'kg',
      bodyweightScaled: true, input: 'weight_reps', exercise: 'Hip Thrust',
      howTo: 'Barbell hip thrust, shoulders on a bench, full lockout. Best set — weight × reps.'),
  MetricDef('squat', 'Quads (Squat)', 'strength', MetricTier.ranked, 'kg',
      bodyweightScaled: true, input: 'weight_reps', exercise: 'Back Squat',
      howTo: 'Barbell back squat to at least parallel. Best set — weight × reps.'),

  MetricDef('rdl', 'Hamstrings (RDL)', 'strength', MetricTier.ranked, 'kg',
      bodyweightScaled: true, input: 'weight_reps', exercise: 'Romanian Deadlift',
      howTo: 'Romanian deadlift — hinge to mid-shin, flat back. Best set — weight × reps.'),
  MetricDef('calf_raise', 'Calves', 'strength', MetricTier.ranked, 'kg',
      bodyweightScaled: true, input: 'weight_reps', exercise: 'Standing Calf Raise', provisional: true,
      howTo: 'Standing calf raise (machine/smith — the loaded weight). Working set — weight × reps.'),
  MetricDef('crunch', 'Abs', 'strength', MetricTier.ranked, 'kg',
      bodyweightScaled: true, input: 'weight_reps', exercise: 'Abs Crunch', provisional: true,
      howTo: 'Weighted crunch, plate held at your chest. Working set — plate weight × reps.'),

  // ── RANKED · performance (per PDF Table 1: VO₂max, 5k, vert, plank, deadhang,
  //    mobility, body-fat all sit under Performance) ──
  MetricDef('vo2max', 'VO₂ Max', 'performance', MetricTier.ranked, 'ml/kg/min',
      exercise: 'Lab test or watch estimate',
      howTo: 'Use your watch\'s estimate (syncs in), or a 12-min all-out Cooper '
          'test: VO₂max ≈ 22.35 × km − 11.29.'),
  MetricDef('plank', 'Plank', 'performance', MetricTier.ranked, 'sec',
      exercise: 'Max forearm plank hold',
      howTo: 'One max forearm plank — straight line ear-to-ankle; stop when the '
          'hips sag. Enter total seconds.'),
  MetricDef('vert', 'Vertical Jump', 'performance', MetricTier.ranked, 'cm',
      exercise: 'Max vertical jump',
      howTo: 'Chalk a wall: standing reach, then max touch from a standing jump '
          '(arm swing allowed). Enter the difference in cm.'),
  MetricDef('run5k_kmh', '5k Speed', 'performance', MetricTier.ranked, 'km/h',
      exercise: 'Avg speed over 5 km',
      howTo: 'Run 5 km for time. Speed = 300 ÷ minutes (27:30 → 10.9 km/h). '
          'From watch pace: 60 ÷ (min/km).'),
  MetricDef('deadhang', 'Deadhang', 'performance', MetricTier.ranked, 'sec',
      exercise: 'Max deadhang time',
      howTo: 'Hang from a pullup bar, both hands, arms straight, until grip fails. '
          'Enter total seconds.'),
  MetricDef('hamstring_mobility', 'Hamstring Mobility', 'performance', MetricTier.ranked, 'cm',
      exercise: 'Sit & reach — cm past your toes (0 = touch, negative if short)',
      howTo: 'Sit, legs straight, reach slowly past your toes and hold 2 s. Enter '
          'cm PAST the toes — 0 if you just touch them, negative if short.'),
  MetricDef('pushups', 'Push-ups (1 min)', 'performance', MetricTier.ranked, 'reps',
      exercise: 'Max push-ups in 60 s',
      howTo: 'As many strict push-ups as you can in 60 s — chest to a fist off the '
          'floor, full lockout; resting in plank is allowed. Enter reps.'),
  MetricDef('sprint_100m', '100m Sprint', 'performance', MetricTier.ranked, 'sec',
      exercise: 'Timed 100 m sprint',
      howTo: 'All-out 100 m on a track (or GPS-measured flat stretch), from a '
          'standing start. Enter seconds.'),
  MetricDef('body_fat_pct', 'Body Fat %', 'recovery', MetricTier.ranked, '%',
      exercise: 'Caliper / DEXA / smart scale',
      howTo: 'Smart scale (same time each day), calipers or a DEXA scan. Enter %. '
          'Also syncs from Google Health.'),

  // ── RANKED · recovery (per PDF Table 1: Sleep score, HRV, Resting HR) ──
  MetricDef('resting_hr', 'Resting HR', 'recovery', MetricTier.ranked, 'bpm',
      exercise: 'Morning resting heart rate',
      howTo: 'Your watch\'s overnight resting HR (syncs in), or count your pulse '
          'for 60 s before getting out of bed. Enter bpm.'),
  MetricDef('hrv', 'HRV', 'recovery', MetricTier.ranked, 'ms',
      exercise: 'Heart rate variability',
      howTo: 'Overnight HRV (RMSSD) from your watch — syncs in automatically. '
          'Enter ms if logging by hand.'),
  MetricDef('blood_pressure', 'Blood Pressure', 'recovery', MetricTier.ranked, 'mmHg',
      exercise: 'Systolic (cuff) — optimal ≤105', provisional: true,
      howTo: 'Home cuff, seated and rested 5 min, arm at heart height. Enter the '
          'SYSTOLIC (top) number in mmHg.'),
  MetricDef('hrr', 'HR Recovery', 'recovery', MetricTier.ranked, 'bpm',
      exercise: 'HR drop 1 min after peak effort', provisional: true,
      howTo: 'Right after a hard effort: note your HR, rest standing for exactly '
          '60 s, note it again. Enter the DROP in bpm.'),
  // Sleep score: auto-derived on sync — the Fitbit/Google vendor score when the
  // payload carries one, else a transparent composite of the night's readings
  // (duration / efficiency / deep+REM). Ranked as recovery; also loggable by hand.
  MetricDef('sleep_score', 'Sleep Score', 'recovery', MetricTier.ranked, '/100',
      autoSync: true, exercise: 'Nightly sleep score (Google Health / Fitbit)'),

  // ── TRACKED · Aesthetics (unranked by design — no defensible population
  //    distribution; ranking appearance is a wellbeing risk. Graphs only.) ──
  MetricDef('skin', 'Skin Health', 'aesthetics', MetricTier.ranked, '/100',
      exercise: 'Selfie skin analysis', provisional: true),
  MetricDef('oral', 'Oral Health', 'aesthetics', MetricTier.ranked, '/100',
      exercise: 'Smile photo analysis', provisional: true),
  MetricDef('eye', 'Eye Health', 'aesthetics', MetricTier.ranked, 'logMAR',
      exercise: 'In-app acuity test', provisional: true),
  MetricDef('hair', 'Hair Density', 'aesthetics', MetricTier.ranked, 'hairs/cm²',
      exercise: 'Macro-lens scalp photo', provisional: true),
  MetricDef('grooming', 'Grooming', 'aesthetics', MetricTier.ranked, '/100',
      exercise: 'Self-checklist', provisional: true),
  MetricDef('voice', 'Voice Quality', 'aesthetics', MetricTier.ranked, 'AVQI',
      exercise: 'Mic recording (Praat)', provisional: true),
  MetricDef('ear', 'Hearing', 'aesthetics', MetricTier.ranked, '/100',
      exercise: 'In-app tone hearing test', provisional: true),

  // ── BACKGROUND · health (automatically logged via API) ──
  MetricDef('heart_rate', 'Heart Rate', 'health', MetricTier.background, 'bpm', autoSync: true),
  MetricDef('daily_readiness', 'Daily Readiness', 'health', MetricTier.background, 'score', autoSync: true),
  MetricDef('steps', 'Steps', 'health', MetricTier.background, 'count', autoSync: true),
  MetricDef('active_zone', 'Active Zone Mins', 'health', MetricTier.background, 'min', autoSync: true),
  MetricDef('spo2', 'Blood Oxygen', 'health', MetricTier.background, '%', autoSync: true),

  // ── BACKGROUND · sleep sub-metrics (all from API) ──
  MetricDef('sleep_duration', 'Sleep Duration', 'sleep', MetricTier.background, 'hrs', autoSync: true),
  MetricDef('sleep_schedule', 'Sleep Schedule', 'sleep', MetricTier.background, 'time', autoSync: true),
  MetricDef('rem_sleep', 'REM Sleep', 'sleep', MetricTier.background, 'min', autoSync: true),
  MetricDef('deep_sleep', 'Deep Sleep', 'sleep', MetricTier.background, 'min', autoSync: true),
  MetricDef('sleep_efficiency', 'Sleep Efficiency', 'sleep', MetricTier.background, '%', autoSync: true),
  MetricDef('time_to_sleep', 'Time to Sound Sleep', 'sleep', MetricTier.background, 'min', autoSync: true),
  MetricDef('full_awakenings', 'Full Awakenings', 'sleep', MetricTier.background, 'count', autoSync: true),
  MetricDef('sleep_interruptions', 'Interruptions', 'sleep', MetricTier.background, 'count', autoSync: true),

  // ── BACKGROUND · diet ──
  // Bodyweight lives with diet (not Profile) so weight change reads against the diet
  // that drives it — for both the user (diet graph) and the AI coach.
  MetricDef('energy_burned', 'Total Energy Burned', 'diet', MetricTier.background, 'kcal', autoSync: true),
  MetricDef('food_logs', 'Food Logs', 'diet', MetricTier.background, 'kcal', autoSync: true),
  MetricDef('bodyweight', 'Bodyweight', 'diet', MetricTier.background, 'kg',
      exercise: 'Scales every strength rank',
      howTo: 'Weigh first thing in the morning, after the bathroom, before food. '
          'Enter kg — new lifts snapshot this value.'),

  // ── BACKGROUND · general / profile ──
  MetricDef('height', 'Height', 'general', MetricTier.background, 'cm', autoSync: true,
      howTo: 'Stand flat against a wall, mark under a level book, measure in cm.'),
  MetricDef('age', 'Age', 'general', MetricTier.background, 'yr', autoSync: true),

  // ── Rank-over-time (category 'rank' = hidden from every grid; graphable only).
  // Backfilled per day by rank_history.dart from the metric logs — the stored value
  // IS the rank (0–9 tier scale), so these carry no engine standard.
  MetricDef('overall_rank', 'Overall Rank', 'rank', MetricTier.background, '/8'),
  MetricDef('strength_rank', 'Strength Rank', 'rank', MetricTier.background, '/8'),
  MetricDef('performance_rank', 'Performance Rank', 'rank', MetricTier.background, '/8'),
  MetricDef('recovery_rank', 'Recovery Rank', 'rank', MetricTier.background, '/8'),
  MetricDef('aesthetics_rank', 'Aesthetics Rank', 'rank', MetricTier.background, '/8'),
];

// Ranked categories that get a plottable rank-over-time series.
const List<String> rankSeriesCategories = ['strength', 'performance', 'recovery', 'aesthetics'];

MetricDef metricById(String id) => metrics.firstWhere((m) => m.id == id);
List<MetricDef> get rankedMetrics =>
    metrics.where((m) => m.tier == MetricTier.ranked).toList();

/// How many ranked metrics each category has — the denominator for "unrated = worst"
/// scoring, so a category/overall rank reflects the FULL roster, not just what's logged.
Map<String, int> get rankedCountByCategory {
  final out = <String, int>{};
  for (final m in rankedMetrics) {
    out[m.category] = (out[m.category] ?? 0) + 1;
  }
  return out;
}

// Tier colours (from the prototype's rank palette).
const Map<String, Color> tierColors = {
  'Wood': Color(0xFF9E643A),
  'Bronze': Color(0xFFC28A67),
  'Silver': Color(0xFFB9C6D4),
  'Gold': Color(0xFFF6CF3E),
  'Platinum': Color(0xFF4CE0C3),
  'Diamond': Color(0xFF8E8EFF),
  'Champion': Color(0xFFE67BE6),
  'Titan': Color(0xFFFA3737),
  'Glory': Color(0xFFFFFFFF),
};
Color tierColor(String tier) => tierColors[tier] ?? const Color(0xFF7880A8);
