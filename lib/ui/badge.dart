// ui/badge.dart — polished tier medallions. Faithful port of the prototype's
// metallic SVG badges (crisp white facets + dimensional white→dark shading),
// wrapped with a radial halo + tight glow so the badge reads as a hero element
// on the dark mobile background.
//
// The sub-rank (I/II/III) is intentionally NOT drawn on the medallion face:
// every place a badge appears, the UI already shows "Tier Sub" as text beside
// it, so painting it on the gem only clutters it. `sub` is kept for API
// compatibility.
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../data/metrics.dart' show tierColor;

class RankBadge extends StatelessWidget {
  final String tier;
  final String? sub; // kept for API compatibility; not drawn on the face
  final double size;
  const RankBadge({required this.tier, this.sub, this.size = 64, super.key});

  @override
  Widget build(BuildContext context) {
    final idx = _tierIndex(tier);
    final c = tierColor(tier);
    final colorHex = _colorToHex(c);
    final svgString =
        '<svg viewBox="0 0 80 80" xmlns="http://www.w3.org/2000/svg" style="overflow:visible">'
        '${_shapes[idx].replaceAll('{c}', colorHex)}</svg>';

    // Render the medallion slightly inset so the halo has room inside the box.
    final inner = size * 0.82;
    // Higher tiers glow brighter and wider — earns the prestige.
    final haloAlpha = (0.26 + idx * 0.05).clamp(0.0, 0.62);
    final glowSigma = 4.0 + idx * 1.4;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // 1. Soft radial halo aura.
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [c.withValues(alpha: haloAlpha), c.withValues(alpha: 0.0)],
                stops: const [0.12, 1.0],
              ),
            ),
          ),
          // 2. Tight tinted glow hugging the medallion silhouette.
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: glowSigma, sigmaY: glowSigma),
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(c, BlendMode.srcIn),
              child: SvgPicture.string(svgString,
                  width: inner, height: inner, allowDrawingOutsideViewBox: true),
            ),
          ),
          // 3. The medallion itself.
          SvgPicture.string(svgString,
              width: inner, height: inner, allowDrawingOutsideViewBox: true),
        ],
      ),
    );
  }

  static int _tierIndex(String t) {
    const order = ['Wood', 'Bronze', 'Silver', 'Gold', 'Platinum',
      'Diamond', 'Champion', 'Titan', 'Glory'];
    final i = order.indexOf(t);
    return i < 0 ? 0 : i;
  }

  static String _colorToHex(Color c) {
    return '#${(c.r * 255).toInt().toRadixString(16).padLeft(2, '0')}'
           '${(c.g * 255).toInt().toRadixString(16).padLeft(2, '0')}'
           '${(c.b * 255).toInt().toRadixString(16).padLeft(2, '0')}';
  }
}

// Prototype-faithful medallion shapes (white→dark radial shading + bright white
// facets). `{c}` is substituted with the tier colour at render time.
const List<String> _shapes = [
  // 0: Wood
  '''
  <defs><radialGradient id="g0" cx="40%" cy="30%"><stop offset="0%" stop-color="rgba(255,255,255,.25)"/><stop offset="100%" stop-color="rgba(0,0,0,.2)"/></radialGradient></defs>
  <polygon points="40,4 67,20 67,52 40,68 13,52 13,20" fill="{c}"/>
  <polygon points="40,4 67,20 67,52 40,68 13,52 13,20" fill="url(#g0)"/>
  <polygon points="40,9 62,22 62,50 40,63 18,50 18,22" fill="none" stroke="rgba(255,210,140,.4)" stroke-width="1.5"/>
  <path d="M40 20Q53 24 52 39Q47 48 38 44Q28 38 31 26Q35 18 40 20Z" fill="rgba(255,255,255,.88)"/>
  <path d="M40 20L37 45" stroke="rgba(255,255,255,.4)" stroke-width="1.2" fill="none"/>
  ''',

  // 1: Bronze
  '''
  <defs><radialGradient id="g1" cx="40%" cy="30%"><stop offset="0%" stop-color="rgba(255,255,255,.22)"/><stop offset="100%" stop-color="rgba(0,0,0,.22)"/></radialGradient></defs>
  <polygon points="40,4 67,20 67,52 40,68 13,52 13,20" fill="{c}"/>
  <polygon points="40,4 67,20 67,52 40,68 13,52 13,20" fill="url(#g1)"/>
  <polygon points="40,9 62,22 62,50 40,63 18,50 18,22" fill="none" stroke="rgba(255,200,110,.4)" stroke-width="1.5"/>
  <polygon points="40,20 56,32 40,54 24,32" fill="rgba(255,255,255,.1)"/>
  <polygon points="40,20 56,32 40,32" fill="rgba(255,255,255,.78)"/>
  <polygon points="40,20 24,32 40,32" fill="rgba(255,255,255,.5)"/>
  <polygon points="40,54 56,32 40,32" fill="rgba(255,255,255,.18)"/>
  <polygon points="40,54 24,32 40,32" fill="rgba(255,255,255,.28)"/>
  <polygon points="40,20 56,32 40,54 24,32" fill="none" stroke="rgba(255,255,255,.55)" stroke-width=".8"/>
  ''',

  // 2: Silver
  '''
  <defs><radialGradient id="g2" cx="40%" cy="30%"><stop offset="0%" stop-color="rgba(255,255,255,.28)"/><stop offset="100%" stop-color="rgba(0,0,0,.18)"/></radialGradient></defs>
  <path d="M13 34Q5 41 9 54L17 48L15 37Z" fill="{c}" opacity=".75"/>
  <path d="M67 34Q75 41 71 54L63 48L65 37Z" fill="{c}" opacity=".75"/>
  <path d="M40 5L67 18L67 43Q67 62 40 74Q13 62 13 43L13 18Z" fill="{c}"/>
  <path d="M40 5L67 18L67 43Q67 62 40 74Q13 62 13 43L13 18Z" fill="url(#g2)"/>
  <path d="M40 11L61 22L61 43Q61 57 40 67Q19 57 19 43L19 22Z" fill="rgba(0,0,0,.2)"/>
  <path d="M40 11L61 22L61 43Q61 57 40 67Q19 57 19 43L19 22Z" fill="none" stroke="rgba(210,230,255,.38)" stroke-width="1"/>
  <polygon points="40,22 55,33 40,53 25,33" fill="rgba(255,255,255,.1)"/>
  <polygon points="40,22 55,33 40,33" fill="rgba(255,255,255,.82)"/>
  <polygon points="40,22 25,33 40,33" fill="rgba(255,255,255,.55)"/>
  <polygon points="40,53 55,33 40,33" fill="rgba(255,255,255,.18)"/>
  <polygon points="40,53 25,33 40,33" fill="rgba(255,255,255,.28)"/>
  <polygon points="40,22 55,33 40,53 25,33" fill="none" stroke="rgba(255,255,255,.55)" stroke-width=".8"/>
  ''',

  // 3: Gold
  '''
  <defs><radialGradient id="g3" cx="40%" cy="30%"><stop offset="0%" stop-color="rgba(255,255,255,.3)"/><stop offset="100%" stop-color="rgba(0,0,0,.18)"/></radialGradient></defs>
  <path d="M11 23Q1 37 7 55L19 45L17 27Z" fill="{c}" opacity=".85"/>
  <path d="M5 27Q-1 39 5 53L13 47L9 31Z" fill="{c}" opacity=".5"/>
  <path d="M69 23Q79 37 73 55L61 45L63 27Z" fill="{c}" opacity=".85"/>
  <path d="M75 27Q81 39 75 53L67 47L71 31Z" fill="{c}" opacity=".5"/>
  <path d="M40 4L66 16L66 42Q66 62 40 74Q14 62 14 42L14 16Z" fill="{c}"/>
  <path d="M40 4L66 16L66 42Q66 62 40 74Q14 62 14 42L14 16Z" fill="url(#g3)"/>
  <path d="M40 10L60 20L60 42Q60 57 40 67Q20 57 20 42L20 20Z" fill="rgba(0,0,0,.18)"/>
  <path d="M40 10L60 20L60 42Q60 57 40 67Q20 57 20 42L20 20Z" fill="none" stroke="rgba(255,245,160,.45)" stroke-width="1"/>
  <polygon points="40,21 58,33 40,57 22,33" fill="rgba(255,255,255,.08)"/>
  <polygon points="40,21 58,33 40,33" fill="rgba(255,255,255,.85)"/>
  <polygon points="40,21 22,33 40,33" fill="rgba(255,255,255,.58)"/>
  <polygon points="40,57 58,33 40,33" fill="rgba(255,255,255,.18)"/>
  <polygon points="40,57 22,33 40,33" fill="rgba(255,255,255,.3)"/>
  <polygon points="40,21 58,33 40,57 22,33" fill="none" stroke="rgba(255,255,255,.55)" stroke-width=".9"/>
  ''',

  // 4: Platinum
  '''
  <defs><radialGradient id="g4" cx="40%" cy="30%"><stop offset="0%" stop-color="rgba(255,255,255,.3)"/><stop offset="100%" stop-color="rgba(0,0,0,.2)"/></radialGradient></defs>
  <path d="M9 26Q1 35 3 50L13 44L11 30Z" fill="{c}" opacity=".75"/>
  <path d="M13 19Q3 30 5 45L17 38L15 22Z" fill="{c}" opacity=".55"/>
  <path d="M5 33Q1 40 3 47L9 43Z" fill="{c}" opacity=".35"/>
  <path d="M71 26Q79 35 77 50L67 44L69 30Z" fill="{c}" opacity=".75"/>
  <path d="M67 19Q77 30 75 45L63 38L65 22Z" fill="{c}" opacity=".55"/>
  <path d="M75 33Q79 40 77 47L71 43Z" fill="{c}" opacity=".35"/>
  <polygon points="40,3 69,23 59,61 21,61 11,23" fill="{c}"/>
  <polygon points="40,3 69,23 59,61 21,61 11,23" fill="url(#g4)"/>
  <polygon points="40,9 64,26 55,57 25,57 16,26" fill="rgba(0,0,0,.2)"/>
  <polygon points="40,9 64,26 55,57 25,57 16,26" fill="none" stroke="rgba(120,255,220,.42)" stroke-width="1.2"/>
  <circle cx="40" cy="37" r="15" fill="rgba(0,0,0,.35)"/>
  <circle cx="40" cy="37" r="15" fill="none" stroke="rgba(255,255,255,.32)" stroke-width="2"/>
  <polygon points="40,22 52,31 40,31" fill="rgba(255,255,255,.85)"/>
  <polygon points="40,22 28,31 40,31" fill="rgba(255,255,255,.6)"/>
  <circle cx="40" cy="39" r="5" fill="{c}" opacity=".8"/>
  <circle cx="40" cy="39" r="3" fill="rgba(255,255,255,.7)"/>
  ''',

  // 5: Diamond
  '''
  <defs><radialGradient id="g5" cx="40%" cy="30%"><stop offset="0%" stop-color="rgba(255,255,255,.3)"/><stop offset="100%" stop-color="rgba(0,0,0,.18)"/></radialGradient></defs>
  <path d="M7 24Q-1 35 1 52L13 44L9 27Z" fill="{c}" opacity=".8"/>
  <path d="M11 16Q1 29 3 46L17 37L13 19Z" fill="{c}" opacity=".58"/>
  <path d="M3 31Q-1 40 1 49L7 45Z" fill="{c}" opacity=".38"/>
  <path d="M73 24Q81 35 79 52L67 44L71 27Z" fill="{c}" opacity=".8"/>
  <path d="M69 16Q79 29 77 46L63 37L67 19Z" fill="{c}" opacity=".58"/>
  <path d="M77 31Q81 40 79 49L73 45Z" fill="{c}" opacity=".38"/>
  <polygon points="40,2 71,22 61,64 19,64 9,22" fill="{c}"/>
  <polygon points="40,2 71,22 61,64 19,64 9,22" fill="url(#g5)"/>
  <polygon points="40,8 66,25 57,59 23,59 14,25" fill="rgba(0,0,0,.18)"/>
  <polygon points="40,8 66,25 57,59 23,59 14,25" fill="none" stroke="rgba(160,210,255,.5)" stroke-width="1.2"/>
  <path d="M40 16L44 28L57 28L47 36L51 50L40 42L29 50L33 36L23 28L36 28Z" fill="rgba(255,255,255,.92)"/>
  <path d="M40 20L43 28L51 28L45 33L48 42L40 37L32 42L35 33L29 28L37 28Z" fill="{c}" opacity=".4"/>
  ''',

  // 6: Champion
  '''
  <defs><radialGradient id="g6" cx="40%" cy="30%"><stop offset="0%" stop-color="rgba(255,255,255,.28)"/><stop offset="100%" stop-color="rgba(0,0,0,.25)"/></radialGradient></defs>
  <path d="M7 52L20 22L32 44L40 10L48 44L60 22L73 52Z" fill="{c}"/>
  <path d="M7 52L20 22L32 44L40 10L48 44L60 22L73 52Z" fill="url(#g6)"/>
  <rect x="7" y="50" width="66" height="17" rx="5" fill="{c}"/>
  <rect x="7" y="50" width="66" height="17" rx="5" fill="url(#g6)"/>
  <rect x="7" y="61" width="66" height="8" rx="3" fill="{c}" opacity=".7"/>
  <path d="M11 52L22 25L33 45L40 14L47 45L58 25L69 52Z" fill="rgba(0,0,0,.22)"/>
  <circle cx="40" cy="14" r="5.5" fill="rgba(255,255,255,.92)"/>
  <circle cx="40" cy="14" r="3.5" fill="{c}"/>
  <circle cx="20" cy="23" r="4" fill="rgba(255,255,255,.8)"/>
  <circle cx="20" cy="23" r="2.5" fill="{c}"/>
  <circle cx="60" cy="23" r="4" fill="rgba(255,255,255,.8)"/>
  <circle cx="60" cy="23" r="2.5" fill="{c}"/>
  <circle cx="40" cy="56" r="4.5" fill="rgba(255,255,255,.4)"/>
  ''',

  // 7: Titan
  '''
  <polygon points="40,1 43,17 51,7 49,21 59,13 53,25 65,21 57,31 71,31 61,39 73,43 61,45 69,55 57,51 59,63 49,55 47,67 40,59 33,67 31,55 21,63 23,51 11,55 19,45 7,43 19,39 9,31 23,31 15,21 27,25 21,13 31,21 29,7 37,17" fill="{c}" opacity=".65"/>
  <circle cx="40" cy="40" r="27" fill="{c}"/>
  <defs><radialGradient id="g7" cx="35%" cy="30%"><stop offset="0%" stop-color="rgba(255,255,255,.25)"/><stop offset="100%" stop-color="rgba(0,0,0,.25)"/></radialGradient></defs>
  <circle cx="40" cy="40" r="27" fill="url(#g7)"/>
  <circle cx="40" cy="40" r="21" fill="rgba(0,0,0,.35)"/>
  <circle cx="40" cy="40" r="21" fill="none" stroke="rgba(255,170,90,.55)" stroke-width="1.8"/>
  <circle cx="40" cy="40" r="15" fill="rgba(0,0,0,.45)"/>
  <circle cx="40" cy="40" r="15" fill="none" stroke="rgba(255,190,100,.5)" stroke-width="1.2"/>
  <circle cx="40" cy="40" r="10" fill="rgba(220,80,30,.85)"/>
  <circle cx="40" cy="40" r="10" fill="none" stroke="rgba(255,255,255,.45)" stroke-width="1"/>
  <circle cx="36" cy="36" r="4" fill="rgba(255,255,255,.65)"/>
  ''',

  // 8: Glory (reuses the Titan starburst; rendered in the Glory colour)
  '''
  <polygon points="40,1 43,17 51,7 49,21 59,13 53,25 65,21 57,31 71,31 61,39 73,43 61,45 69,55 57,51 59,63 49,55 47,67 40,59 33,67 31,55 21,63 23,51 11,55 19,45 7,43 19,39 9,31 23,31 15,21 27,25 21,13 31,21 29,7 37,17" fill="{c}" opacity=".7"/>
  <circle cx="40" cy="40" r="27" fill="{c}"/>
  <defs><radialGradient id="g8" cx="35%" cy="30%"><stop offset="0%" stop-color="rgba(255,255,255,.5)"/><stop offset="100%" stop-color="rgba(0,0,0,.25)"/></radialGradient></defs>
  <circle cx="40" cy="40" r="27" fill="url(#g8)"/>
  <circle cx="40" cy="40" r="21" fill="rgba(0,0,0,.3)"/>
  <circle cx="40" cy="40" r="21" fill="none" stroke="rgba(255,255,255,.7)" stroke-width="1.8"/>
  <circle cx="40" cy="40" r="15" fill="rgba(0,0,0,.35)"/>
  <circle cx="40" cy="40" r="15" fill="none" stroke="rgba(255,255,255,.6)" stroke-width="1.2"/>
  <circle cx="40" cy="40" r="9" fill="rgba(255,255,255,.95)"/>
  <circle cx="36" cy="36" r="3.5" fill="rgba(255,255,255,.8)"/>
  '''
];
