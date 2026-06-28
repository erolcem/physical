// data/body_figure_data.dart — front, back & inner body figures ported verbatim
// from the prototype SVG (viewBox 0 0 148 420). Each region groups the polygons
// that belong to one muscle; the muscle maps to an engine metric (or is inert).
import 'dart:ui';

class BodyRegion {
  final String muscle; // chest, shoulders, quads, brain, heart, ...
  final List<String> polys; // raw "x,y x,y ..." strings (parsed on demand)
  const BodyRegion(this.muscle, this.polys);
}

List<Offset> parsePoly(String s) => s
    .trim()
    .split(RegExp(r'\s+'))
    .map((p) {
      final xy = p.split(',');
      return Offset(double.parse(xy[0]), double.parse(xy[1]));
    })
    .toList();

// Shared silhouette + neck (non-interactive background).
const String silhouette =
    '64,15 84,15 90,45 136,65 140,190 120,200 130,110 100,100 100,170 '
    '120,265 110,360 85,360 74,200 63,360 38,360 28,265 48,170 48,100 '
    '18,110 28,200 8,190 12,65 58,45';
const String neck = '66,15 82,15 86,35 62,35';

const List<BodyRegion> frontRegions = [
  BodyRegion('shoulders', [
    '44,54 28,59 22,85 30,105 42,90 40,68',
    '104,54 120,59 126,85 118,105 106,90 108,68',
  ]),
  BodyRegion('shoulders_m', [
    '28,59 18,64 12,85 22,85',
    '120,59 130,64 136,85 126,85',
  ]),
  BodyRegion('chest', [
    '72,50 46,54 32,75 44,100 72,102',
    '76,50 102,54 116,75 104,100 76,102',
  ]),
  BodyRegion('biceps', [
    '30,110 16,118 14,142 24,152 36,138',
    '118,110 132,118 134,142 124,152 112,138',
  ]),
  BodyRegion('forearms', [
    '22,156 10,166 8,190 16,200 28,185',
    '126,156 138,166 140,190 132,200 120,185',
  ]),
  BodyRegion('abs', [
    '72,106 46,104 52,122 72,124',
    '76,106 102,104 96,122 76,124',
    '72,128 54,126 58,144 72,146',
    '76,128 94,126 90,144 76,146',
    '72,150 60,148 64,166 72,170',
    '76,150 88,148 84,166 76,170',
  ]),
  BodyRegion('quads', [
    '54,170 34,180 24,220 30,265 46,260 50,220',
    '70,174 56,172 52,220 48,260 62,260 70,220',
    '94,170 114,180 124,220 118,265 102,260 98,220',
    '78,174 92,172 96,220 100,260 86,260 78,220',
  ]),
  BodyRegion('calves', [
    '58,275 36,275 28,310 36,350 50,350 56,310',
    '90,275 112,275 120,310 112,350 98,350 92,310',
  ]),
];

const List<BodyRegion> backRegions = [
  BodyRegion('shoulders', [
    '58,45 44,54 28,59 22,85 30,105 42,90 44,65',
    '90,45 104,54 120,59 126,85 118,105 106,90 104,65',
  ]),
  BodyRegion('shoulders_m', [
    '28,59 18,64 12,85 22,85',
    '120,59 130,64 136,85 126,85',
  ]),
  BodyRegion('lats', [
    '44,65 32,85 40,125 54,140 58,90',
    '104,65 116,85 108,125 94,140 90,90',
    // Mid-upper back (spine corridor) so the lats also light the centre, not just the sides.
    '58,70 90,70 87,104 74,114 61,104',
  ]),
  BodyRegion('lower_back', [
    '74,85 90,90 94,140 74,160 54,140 58,90',
    '74,160 94,140 86,170 74,175 62,170 54,140',
  ]),
  BodyRegion('triceps', [
    '30,110 16,118 14,142 24,152 36,138',
    '118,110 132,118 134,142 124,152 112,138',
  ]),
  BodyRegion('forearms', [
    '22,156 10,166 8,190 16,200 28,185',
    '126,156 138,166 140,190 132,200 120,185',
  ]),
  BodyRegion('glutes', [
    '74,175 62,170 42,175 34,195 48,220 72,215',
    '74,175 86,170 106,175 114,195 100,220 76,215',
  ]),
  BodyRegion('hamstrings', [
    '48,220 34,225 30,265 46,260 50,240',
    '72,215 48,220 50,240 48,260 62,260 70,230',
    '100,220 114,225 118,265 102,260 98,240',
    '76,215 100,220 98,240 100,260 86,260 78,230',
  ]),
  BodyRegion('calves', [
    '58,275 36,275 28,310 36,350 50,350 56,310',
    '90,275 112,275 120,310 112,350 98,350 92,310',
  ]),
];

// ── INNER FIGURE — ported from old reference _innerSVG() ──────────────────
// Every shape (ellipse, rect, path) is converted to polygon point strings.

const List<BodyRegion> innerRegions = [
  // Brain (ellipse cx=74 cy=22 rx=12 ry=9 → 12-point polygon approximation)
  BodyRegion('brain', [
    '86,22 85.46,25.39 83.04,28.19 79.18,30 74,31 68.82,30 '
    '64.96,28.19 62.54,25.39 62,22 62.54,18.61 64.96,15.81 '
    '68.82,14 74,13 79.18,14 83.04,15.81 85.46,18.61',
  ]),

  // Heart (path: M62 63 Q58 57 62 53 Q66 49 70 55 Q74 49 78 53 Q82 57 78 63 L70 73 Z)
  BodyRegion('heart', [
    '62,63 60,58 62,53 66,50 70,55 74,50 78,53 80,58 78,63 70,73',
  ]),

  // Left lung (path: M52 57 Q46 61 46 76 Q46 91 54 96 Q60 99 64 91 L64 59 Q58 55 52 57)
  BodyRegion('lung_l', [
    '52,57 48,60 46,68 46,76 46,84 50,92 54,96 58,98 64,91 64,59 58,56',
  ]),

  // Right lung (path: M96 57 Q102 61 102 76 Q102 91 94 96 Q88 99 84 91 L84 59 Q90 55 96 57)
  BodyRegion('lung_r', [
    '96,57 100,60 102,68 102,76 102,84 98,92 94,96 90,98 84,91 84,59 90,56',
  ]),

  // Core / abs (rect x=55 y=104 w=38 h=58 rx=6 → polygon with rounded-ish corners)
  BodyRegion('core', [
    '61,104 87,104 93,110 93,156 87,162 61,162 55,156 55,110',
  ]),

  // Body Fat % (Semicircle under the core/abs)
  BodyRegion('full_body', [
    '42,166 54,192 74,205 94,192 106,166 94,176 74,182 54,176',
  ]),

  // Left hand — 5 rects merged into one polygon approximation
  // (palm rect + 4 finger rects simplified to a single hand shape)
  BodyRegion('hand_l', [
    '4,181 7,178 11,178 15,179 19,182 19,190 19,200 4,200 4,190',
  ]),

  // Right hand — mirror of left
  BodyRegion('hand_r', [
    '129,182 132,179 136,178 140,178 144,181 144,190 144,200 129,200 129,190',
  ]),

  // Left thigh (path: M63 173 Q55 178 53 212 Q53 242 59 258 L67 256 ...)
  BodyRegion('thigh_l', [
    '63,173 58,176 55,190 53,212 53,230 56,248 59,258 67,256 67,234 67,212 67,190 67,173',
  ]),

  // Right thigh (path: M85 173 Q93 178 95 212 Q95 242 89 258 L81 256 ...)
  BodyRegion('thigh_r', [
    '85,173 90,176 93,190 95,212 95,230 92,248 89,258 81,256 81,234 81,212 81,190 81,173',
  ]),

  // Left tibia / shin (rect x=41 y=270 w=16 h=78 rx=5 → polygon)
  BodyRegion('tibia_l', [
    '46,270 52,270 57,275 57,343 52,348 46,348 41,343 41,275',
  ]),

  // Right tibia / shin (rect x=91 y=270 w=16 h=78 rx=5 → polygon)
  BodyRegion('tibia_r', [
    '96,270 102,270 107,275 107,343 102,348 96,348 91,343 91,275',
  ]),

  // Left foot (path: M34 356 Q34 366 38 369 Q50 373 58 369 Q62 365 58 358 L50 356)
  BodyRegion('foot_l', [
    '34,356 34,362 36,367 38,369 44,372 50,373 55,371 58,369 61,365 58,358 50,356',
  ]),

  // Right foot (path: M114 356 Q114 366 110 369 Q98 373 90 369 Q86 365 90 358 L98 356)
  BodyRegion('foot_r', [
    '114,356 114,362 112,367 110,369 104,372 98,373 93,371 90,369 87,365 90,358 98,356',
  ]),

  // Platform (rect x=22 y=376 w=104 h=9 rx=4 → polygon)
  BodyRegion('platform', [
    '26,376 122,376 126,380 126,381 122,385 26,385 22,381 22,380',
  ]),
];

// ── HEAD FIGURE (Aesthetics) ─────────────────────────────────────────────
// Abstract facial features drawn into the standard 148x420 viewBox.
// Scaled and positioned so it fills a nice upper proportion (e.g. y: 20 to 180).

const List<BodyRegion> headRegions = [
  // Hair (top dome)
  BodyRegion('hair', [
    '40,70 44,40 60,20 88,20 104,40 108,70 114,90 106,94 94,84 74,74 54,84 42,94 34,90',
  ]),
  // Skin (face base / cheeks / forehead)
  BodyRegion('skin', [
    '40,70 108,70 114,90 112,120 94,160 74,170 54,160 36,120 34,90',
  ]),
  // Eyes
  BodyRegion('eye', [
    '50,96 56,92 64,96 56,100', // Left eye
    '84,96 92,92 98,96 92,100', // Right eye
  ]),
  // Oral (mouth/teeth)
  BodyRegion('oral', [
    '60,136 74,132 88,136 74,142',
  ]),
  // Grooming (eyebrows + beard/jawline trim)
  BodyRegion('grooming', [
    '46,86 56,80 66,86', // Left brow
    '82,86 92,80 102,86', // Right brow
    '48,140 56,154 74,164 92,154 100,140', // Jawline trim
  ]),
  // Voice (neck / vocal cords)
  BodyRegion('voice', [
    '60,166 88,166 90,200 58,200',
  ]),
];

// Muscle -> engine metric. Muscles absent here render inert (no metric yet).

const Map<String, String> muscleToMetric = {
  // Front
  'chest': 'bench',
  'shoulders': 'ohp',
  'shoulders_m': 'lateral_raise',
  'biceps': 'curl',
  'forearms': 'forearm_curl',
  'abs': 'crunch',
  'quads': 'squat',
  'calves': 'calf_raise',
  // Back
  'lats': 'pullup',
  'triceps': 'skull_crusher',
  'glutes': 'hip_thrust',
  'hamstrings': 'rdl',
  // Inner
  'full_body': 'body_fat_pct',
  'brain': 'sleep_score',
  'heart': 'resting_hr',
  'lung_l': 'vo2max',
  'lung_r': 'vo2max',
  'core': 'plank',
  'hand_l': 'hrv',
  'hand_r': 'hrv',
  'thigh_l': 'hamstring_mobility',
  'thigh_r': 'hamstring_mobility',
  'tibia_l': 'run5k_kmh',
  'tibia_r': 'run5k_kmh',
  'foot_l': 'vert',
  'foot_r': 'vert',
  'platform': 'deadhang',
  // Head / Aesthetics
  'hair': 'hair',
  'skin': 'skin',
  'eye': 'eye',
  'oral': 'oral',
  'grooming': 'grooming',
  'voice': 'voice',
};
