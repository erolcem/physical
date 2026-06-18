// data/body_figure_data.dart — front & back body figures ported verbatim from
// the prototype SVG (viewBox 0 0 148 420). Each region groups the polygons that
// belong to one muscle; the muscle maps to an engine metric (or is inert).
import 'dart:ui';

class BodyRegion {
  final String muscle; // chest, shoulders, quads, ...
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
    '64,15 84,15 90,45 130,65 140,190 120,200 130,110 100,100 100,170 '
    '120,265 110,360 85,360 74,200 63,360 38,360 28,265 48,170 48,100 '
    '18,110 28,200 8,190 18,65 58,45';
const String neck = '66,15 82,15 86,35 62,35';

const List<BodyRegion> frontRegions = [
  BodyRegion('traps', ['62,40 86,40 102,52 80,48 68,48 46,52']),
  BodyRegion('shoulders', [
    '44,54 24,64 18,85 30,105 42,90 40,68',
    '104,54 124,64 130,85 118,105 106,90 108,68',
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
  BodyRegion('traps', ['74,35 90,45 74,85 58,45']),
  BodyRegion('shoulders', [
    '58,45 44,54 24,64 18,85 30,105 42,90 44,65',
    '90,45 104,54 124,64 130,85 118,105 106,90 104,65',
  ]),
  BodyRegion('lats', [
    '44,65 32,85 40,125 54,140 58,90',
    '104,65 116,85 108,125 94,140 90,90',
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

// Muscle -> engine metric. Muscles absent here render inert (no metric yet).
const Map<String, String> muscleToMetric = {
  'chest': 'bench',
  'shoulders': 'ohp',
  'quads': 'squat',
  'hamstrings': 'deadlift',
  'glutes': 'deadlift',
  'lats': 'deadlift',
  'traps': 'deadlift',
};
