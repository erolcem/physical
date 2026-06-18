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
  const MetricDef(this.id, this.label, this.category, this.tier, this.unit,
      {this.bodyweightScaled = false, this.input = 'score', this.exercise = ''});

  bool get isStrength => input == 'weight_reps';
}

// Only `ranked` metrics with a matching Standard in the engine get a tier.
// `tracked` (aesthetics) and `background` are shown/used but never ranked.
const List<MetricDef> metrics = [
  // ── RANKED · strength (bodyweight-scaled) ──
  MetricDef('bench', 'Chest (Bench)', 'strength', MetricTier.ranked, 'kg',
      bodyweightScaled: true, input: 'weight_reps', exercise: 'Bench Press'),
  MetricDef('squat', 'Legs (Squat)', 'strength', MetricTier.ranked, 'kg',
      bodyweightScaled: true, input: 'weight_reps', exercise: 'Back Squat'),
  MetricDef('deadlift', 'Posterior (Deadlift)', 'strength', MetricTier.ranked, 'kg',
      bodyweightScaled: true, input: 'weight_reps', exercise: 'Deadlift'),
  MetricDef('ohp', 'Shoulders (OHP)', 'strength', MetricTier.ranked, 'kg',
      bodyweightScaled: true, input: 'weight_reps', exercise: 'Overhead Press'),
  // ── RANKED · performance / recovery (score metrics) ──
  MetricDef('vo2max', 'VO₂ Max', 'recovery', MetricTier.ranked, 'ml/kg/min',
      exercise: 'Lab test or watch estimate'),
  MetricDef('resting_hr', 'Resting HR', 'recovery', MetricTier.ranked, 'bpm',
      exercise: 'Morning resting heart rate'),
  MetricDef('plank', 'Plank', 'performance', MetricTier.ranked, 'sec',
      exercise: 'Max forearm plank hold'),
  MetricDef('vert', 'Vertical Jump', 'performance', MetricTier.ranked, 'cm',
      exercise: 'Max vertical jump'),
  MetricDef('run5k_kmh', '5k Speed', 'performance', MetricTier.ranked, 'km/h',
      exercise: 'Avg speed over 5 km'),
  // ── TRACKED · foreground, NOT ranked (aesthetics) ──
  MetricDef('skin', 'Skin Health', 'aesthetics', MetricTier.tracked, '/100',
      exercise: 'Tracked score — no rank'),
  MetricDef('hair', 'Hair Density', 'aesthetics', MetricTier.tracked, '/cm²',
      exercise: 'Tracked score — no rank'),
  // ── BACKGROUND · AI context, never surfaced as a score ──
  MetricDef('steps', 'Steps', 'context', MetricTier.background, 'count'),
  MetricDef('bodyweight', 'Bodyweight', 'context', MetricTier.background, 'kg',
      exercise: 'Scales every strength rank'),
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
