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
  final bool autoSync; // true if logged automatically via HealthKit/Fitbit
  final bool provisional; // rank comes from a weak/estimated standard — flag it in the UI

  const MetricDef(this.id, this.label, this.category, this.tier, this.unit,
      {this.bodyweightScaled = false, this.input = 'score', this.exercise = '', this.autoSync = false, this.provisional = false});

  bool get isStrength => input == 'weight_reps';
}

// Only `ranked` metrics with a matching Standard in the engine get a tier.
// `tracked` (aesthetics) and `background` are shown/used but never ranked.
const List<MetricDef> metrics = [
  // ── RANKED · strength (bodyweight-scaled) ──
  MetricDef('bench', 'Chest (Bench)', 'strength', MetricTier.ranked, 'kg',
      bodyweightScaled: true, input: 'weight_reps', exercise: 'Bench Press'),
  MetricDef('ohp', 'Front Shoulder (OHP)', 'strength', MetricTier.ranked, 'kg',
      bodyweightScaled: true, input: 'weight_reps', exercise: 'Overhead Press'),
  // Isolation lifts: ranked on rep-volume-at-load (weight × reps), not an
  // unreliable estimated 1RM (STANDARDS_METHODOLOGY §2). Still flagged provisional.
  MetricDef('lateral_raise', 'Medial Shoulder', 'strength', MetricTier.ranked, 'kg·reps',
      bodyweightScaled: true, input: 'weight_reps', exercise: 'Lateral Raise', provisional: true),
  MetricDef('curl', 'Bicep', 'strength', MetricTier.ranked, 'kg·reps',
      bodyweightScaled: true, input: 'weight_reps', exercise: 'Bicep Curl', provisional: true),
  MetricDef('skull_crusher', 'Tricep', 'strength', MetricTier.ranked, 'kg·reps',
      bodyweightScaled: true, input: 'weight_reps', exercise: 'Skull Crusher', provisional: true),
  MetricDef('forearm_curl', 'Forearm', 'strength', MetricTier.ranked, 'kg·reps',
      bodyweightScaled: true, input: 'weight_reps', exercise: 'Forearm Curl', provisional: true),
  MetricDef('pullup', 'Lats (Pullup)', 'strength', MetricTier.ranked, 'kg',
      bodyweightScaled: true, input: 'weight_reps', exercise: 'Weighted Pullup'),
  MetricDef('hip_thrust', 'Glute', 'strength', MetricTier.ranked, 'kg',
      bodyweightScaled: true, input: 'weight_reps', exercise: 'Hip Thrust'),
  MetricDef('squat', 'Quads (Squat)', 'strength', MetricTier.ranked, 'kg',
      bodyweightScaled: true, input: 'weight_reps', exercise: 'Back Squat'),

  MetricDef('rdl', 'Hamstrings (RDL)', 'strength', MetricTier.ranked, 'kg',
      bodyweightScaled: true, input: 'weight_reps', exercise: 'Romanian Deadlift'),
  MetricDef('calf_raise', 'Calves', 'strength', MetricTier.ranked, 'kg',
      bodyweightScaled: true, input: 'weight_reps', exercise: 'Standing Calf Raise', provisional: true),
  MetricDef('crunch', 'Abs', 'strength', MetricTier.ranked, 'kg',
      bodyweightScaled: true, input: 'weight_reps', exercise: 'Abs Crunch', provisional: true),

  // ── RANKED · performance (per PDF Table 1: VO₂max, 5k, vert, plank, deadhang,
  //    mobility, body-fat all sit under Performance) ──
  MetricDef('vo2max', 'VO₂ Max', 'performance', MetricTier.ranked, 'ml/kg/min',
      exercise: 'Lab test or watch estimate'),
  MetricDef('plank', 'Plank', 'performance', MetricTier.ranked, 'sec',
      exercise: 'Max forearm plank hold'),
  MetricDef('vert', 'Vertical Jump', 'performance', MetricTier.ranked, 'cm',
      exercise: 'Max vertical jump'),
  MetricDef('run5k_kmh', '5k Speed', 'performance', MetricTier.ranked, 'km/h',
      exercise: 'Avg speed over 5 km'),
  MetricDef('deadhang', 'Deadhang', 'performance', MetricTier.ranked, 'sec',
      exercise: 'Max deadhang time'),
  MetricDef('hamstring_mobility', 'Hamstring Mobility', 'performance', MetricTier.ranked, 'cm',
      exercise: 'Sit and reach'),
  MetricDef('pushups', 'Push-ups (1 min)', 'performance', MetricTier.ranked, 'reps',
      exercise: 'Max push-ups in 60 s'),
  MetricDef('sprint_100m', '100m Sprint', 'performance', MetricTier.ranked, 'sec',
      exercise: 'Timed 100 m sprint'),
  MetricDef('body_fat_pct', 'Body Fat %', 'recovery', MetricTier.ranked, '%',
      exercise: 'Caliper / DEXA / smart scale'),

  // ── RANKED · recovery (per PDF Table 1: Sleep score, HRV, Resting HR) ──
  MetricDef('resting_hr', 'Resting HR', 'recovery', MetricTier.ranked, 'bpm',
      exercise: 'Morning resting heart rate'),
  MetricDef('hrv', 'HRV', 'recovery', MetricTier.ranked, 'ms',
      exercise: 'Heart rate variability'),
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
  MetricDef('hair', 'Hair Density', 'aesthetics', MetricTier.ranked, '/100',
      exercise: 'Scalp photo (coverage)', provisional: true),
  MetricDef('grooming', 'Grooming', 'aesthetics', MetricTier.ranked, '/100',
      exercise: 'Self-checklist', provisional: true),
  MetricDef('voice', 'Voice Quality', 'aesthetics', MetricTier.ranked, 'AVQI',
      exercise: 'Mic recording (Praat)', provisional: true),

  // ── BACKGROUND · health (automatically logged via API) ──
  MetricDef('heart_rate', 'Heart Rate', 'health', MetricTier.background, 'bpm', autoSync: true),
  MetricDef('daily_readiness', 'Daily Readiness', 'health', MetricTier.background, 'score', autoSync: true),
  MetricDef('steps', 'Steps', 'health', MetricTier.background, 'count', autoSync: true),
  MetricDef('active_zone', 'Active Zone Mins', 'health', MetricTier.background, 'min', autoSync: true),

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
  MetricDef('energy_burned', 'Total Energy Burned', 'diet', MetricTier.background, 'kcal', autoSync: true),
  MetricDef('food_logs', 'Food Logs', 'diet', MetricTier.background, 'kcal', autoSync: true),

  // ── BACKGROUND · general / profile ──
  MetricDef('bodyweight', 'Bodyweight', 'general', MetricTier.background, 'kg',
      exercise: 'Scales every strength rank'),
  MetricDef('height', 'Height', 'general', MetricTier.background, 'cm', autoSync: true),
  MetricDef('age', 'Age', 'general', MetricTier.background, 'yr', autoSync: true),
];

MetricDef metricById(String id) => metrics.firstWhere((m) => m.id == id);
List<MetricDef> get rankedMetrics =>
    metrics.where((m) => m.tier == MetricTier.ranked).toList();

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
