// data/body_figure_data.dart — front, back & inner body figures (viewBox
// 0 0 148 420). Redrawn from the blocky prototype port into an athletic male
// outline: real neck/trap slope, deltoid caps, arms hanging with a gap from
// the V-tapered torso, narrow waist, hip flare, knee/calf taper and feet.
// Coordinates are authored right-side and mirrored exactly about x=74
// (scratch generator: gen_body.py), so the figure is perfectly symmetric.
// Each region groups the polygons that belong to one muscle; the muscle maps
// to an engine metric (or is inert anatomy — traps/obliques/lower back).
// The painter smooths every polygon with Catmull-Rom, so shapes are authored
// as sparse hulls, not pixel outlines.
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

// Shared silhouette (head → right arm/leg → crotch → mirrored left side) +
// a neck/throat strip for depth. Non-interactive background.
const String silhouette =
    '74,4 85,7 91,16 91,28 86,38 84,46 92,51 106,56 120,61 129,70 133,82 '
    '136,100 138,118 137,132 140,148 142,164 140,182 137,196 140,206 139,218 '
    '133,226 127,220 125,208 124,196 122,178 121,160 119,142 117,124 113,104 '
    '107,92 103,108 98,130 96,148 99,162 105,178 108,194 107,216 103,244 '
    '99,268 98,280 102,298 101,318 95,340 91,356 99,368 98,377 83,377 81,364 '
    '83,350 84,322 83,296 81,280 79,258 77,234 75,214 74,204 73,214 71,234 '
    '69,258 67,280 65,296 64,322 65,350 67,364 65,377 50,377 49,368 57,356 '
    '53,340 47,318 46,298 50,280 49,268 45,244 41,216 40,194 43,178 49,162 '
    '52,148 50,130 45,108 41,92 35,104 31,124 29,142 27,160 26,178 24,196 '
    '23,208 21,220 15,226 9,218 8,206 11,196 8,182 6,164 8,148 11,132 10,118 '
    '12,100 15,82 19,70 28,61 42,56 56,51 64,46 62,38 57,28 57,16 63,7';
const String neck = '68,38 80,38 82,52 66,52';

// Deltoid cap (ohp) + the lateral-head sliver (lateral_raise) hugging its
// outside — shared by the front and back figures.
const List<String> _deltCaps = [
  '106,60 118,62 127,70 129,82 123,92 112,88 106,72',
  '42,72 36,88 25,92 19,82 21,70 30,62 42,60',
];
const List<String> _deltLateral = [
  '126,70 132,80 135,96 128,104 123,92 129,82',
  '19,82 25,92 20,104 13,96 16,80 22,70',
];
const List<String> _forearms = [
  '121,148 132,142 139,156 140,176 132,190 124,172',
  '24,172 16,190 8,176 9,156 16,142 27,148',
];
const List<String> _upperArms = [
  '112,106 123,100 129,112 128,130 120,140 113,126',
  '35,126 28,140 20,130 19,112 25,100 36,106',
];

const List<BodyRegion> frontRegions = [
  BodyRegion('shoulders', _deltCaps),
  BodyRegion('shoulders_m', _deltLateral),
  BodyRegion('chest', [
    '76,66 96,66 103,75 102,90 95,100 78,102',
    '70,102 53,100 46,90 45,75 52,66 72,66',
  ]),
  BodyRegion('biceps', _upperArms),
  BodyRegion('forearms', _forearms),
  BodyRegion('abs', [
    '60,108 72,110 72,126 60,124',
    '76,110 88,108 88,124 76,126',
    '61,129 72,131 72,147 61,145',
    '76,131 87,129 87,145 76,147',
    '62,150 72,152 72,172 63,168',
    '76,152 86,150 85,168 76,172',
  ]),
  // Obliques frame the six-pack — inert anatomy (no isolated metric).
  BodyRegion('obliques', [
    '90,128 96,124 95,148 89,160 88,140',
    '60,140 59,160 53,148 52,124 58,128',
  ]),
  BodyRegion('quads', [
    '92,206 103,216 104,244 99,268 91,262 88,234',
    '60,234 57,262 49,268 44,244 45,216 56,206',
    '78,208 88,214 86,244 90,262 81,270 76,242',
    '72,242 67,270 58,262 62,244 60,214 70,208',
  ]),
  BodyRegion('calves', [
    '85,292 98,296 99,318 93,340 86,342 83,316',
    '65,316 62,342 55,340 49,318 50,296 63,292',
  ]),
];

const List<BodyRegion> backRegions = [
  BodyRegion('shoulders', _deltCaps),
  BodyRegion('shoulders_m', _deltLateral),
  // Trapezius kite down the spine — inert anatomy (no shrug metric).
  BodyRegion('traps', [
    '74,54 90,58 96,68 88,84 78,112 74,122',
    '74,122 70,112 60,84 52,68 58,58 74,54',
  ]),
  BodyRegion('lats', [
    '78,100 90,96 104,100 100,126 91,148 79,142',
    '69,142 57,148 48,126 44,100 58,96 70,100',
  ]),
  BodyRegion('lower_back', [
    '75,148 86,156 84,176 75,182',
    '73,182 64,176 62,156 73,148',
  ]),
  BodyRegion('triceps', _upperArms),
  BodyRegion('forearms', _forearms),
  BodyRegion('glutes', [
    '76,180 96,178 106,190 103,210 88,218 77,214',
    '71,214 60,218 45,210 42,190 52,178 72,180',
  ]),
  BodyRegion('hamstrings', [
    '88,224 102,222 101,248 95,274 86,266 84,242',
    '64,242 62,266 53,274 47,248 46,222 60,224',
  ]),
  BodyRegion('calves', [
    '85,290 99,292 101,316 94,342 86,340 82,312',
    '66,312 62,340 54,342 47,316 49,292 63,290',
  ]),
];

// ── INNER FIGURE — stylised organ/system map on the same silhouette. ──────

const List<BodyRegion> innerRegions = [
  // Brain (ellipse approximation inside the head oval)
  BodyRegion('brain', [
    '86,22 85.46,25.39 83.04,28.19 79.18,30 74,31 68.82,30 '
    '64.96,28.19 62.54,25.39 62,22 62.54,18.61 64.96,15.81 '
    '68.82,14 74,13 79.18,14 83.04,15.81 85.46,18.61',
  ]),

  // Heart
  BodyRegion('heart', [
    '62,63 60,58 62,53 66,50 70,55 74,50 78,53 80,58 78,63 70,73',
  ]),

  // Lungs
  BodyRegion('lung_l', [
    '52,57 48,60 46,68 46,76 46,84 50,92 54,96 58,98 64,91 64,59 58,56',
  ]),
  BodyRegion('lung_r', [
    '96,57 100,60 102,68 102,76 102,84 98,92 94,96 90,98 84,91 84,59 90,56',
  ]),

  // Core / plank (rounded rect)
  BodyRegion('core', [
    '61,104 87,104 93,110 93,156 87,162 61,162 55,156 55,110',
  ]),

  // Body Fat % (waist-to-hip band under the core)
  BodyRegion('full_body', [
    '42,166 54,192 74,205 94,192 106,166 94,176 74,182 54,176',
  ]),

  // Hands (HRV) — sit where the new arms end.
  BodyRegion('hand_l', [
    '20,218 13,224 8,210 11,198 22,200',
  ]),
  BodyRegion('hand_r', [
    '126,200 137,198 140,210 135,224 128,218',
  ]),

  // Thighs (hamstring mobility)
  BodyRegion('thigh_l', [
    '63,173 58,176 55,190 53,212 53,230 56,248 59,258 67,256 67,234 67,212 67,190 67,173',
  ]),
  BodyRegion('thigh_r', [
    '85,173 90,176 93,190 95,212 95,230 92,248 89,258 81,256 81,234 81,212 81,190 81,173',
  ]),

  // Shins (5k) — inside the redrawn calves.
  BodyRegion('tibia_l', [
    '52,270 58,270 62,275 62,343 58,348 52,348 48,343 48,275',
  ]),
  BodyRegion('tibia_r', [
    '90,270 96,270 100,275 100,343 96,348 90,348 86,343 86,275',
  ]),

  // Feet (vertical jump) — match the new foot outline.
  BodyRegion('foot_l', [
    '50,364 64,362 66,369 64,375 52,375 49,370',
  ]),
  BodyRegion('foot_r', [
    '84,362 98,364 99,370 96,375 84,375 82,369',
  ]),

  // Platform (deadhang)
  BodyRegion('platform', [
    '26,382 122,382 126,386 126,387 122,391 26,391 22,387 22,386',
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

// Muscle -> engine metric. Muscles absent here render inert (no metric yet):
// traps / obliques / lower_back are honest anatomy without their own lift.

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
