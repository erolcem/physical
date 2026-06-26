// ui/badge.dart — polished tier medallions. Faithful port of the prototype's
// metallic SVG badges (crisp white facets + dimensional white→dark shading),
// wrapped with a radial halo + tight glow + a specular light-catch sheen so the
// badge reads as a hero element on the dark mobile background. The sheen is masked
// to the medallion silhouette (so only the metal lights up) and grows lustier with
// tier — Glory catches the most light.
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
  // Hero badges (the big overall medallion) set this for a slow shine sweep.
  // Left off for list/inline badges so many-on-screen stays cheap.
  final bool animated;
  const RankBadge({required this.tier, this.sub, this.size = 64, this.animated = false, super.key});

  @override
  Widget build(BuildContext context) {
    final idx = _tierIndex(tier);
    final c = tierColor(tier);
    final colorHex = _colorToHex(c);
    final svgString =
        '<svg viewBox="0 0 80 80" xmlns="http://www.w3.org/2000/svg" style="overflow:visible">'
        '${_medallion(idx).replaceAll('{c}', colorHex)}</svg>';

    // Render the medallion slightly inset so the halo has room inside the box.
    final inner = size * 0.82;
    // Higher tiers glow brighter and wider — earns the prestige.
    final haloAlpha = (0.26 + idx * 0.05).clamp(0.0, 0.62);
    final glowSigma = 4.0 + idx * 1.4;
    // A touch more specular lustre for higher tiers (prestige reads as polish).
    final sheenAlpha = (0.30 + idx * 0.025).clamp(0.0, 0.52);

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
          // 4. Specular sheen — a soft top-left light-catch, masked to the
          //    medallion silhouette so only the metal lights up (not the
          //    transparent surround).
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (rect) => RadialGradient(
              center: const Alignment(-0.45, -0.65),
              radius: 0.95,
              colors: [
                Colors.white.withValues(alpha: sheenAlpha),
                Colors.white.withValues(alpha: 0.0),
              ],
            ).createShader(rect),
            child: ColorFiltered(
              colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
              child: SvgPicture.string(svgString,
                  width: inner, height: inner, allowDrawingOutsideViewBox: true),
            ),
          ),
          // 5. Optional shine sweep for hero badges.
          if (animated) _Shimmer(svgString: svgString, size: inner),
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

// A diagonal white highlight that sweeps across the medallion (masked to its
// silhouette), giving the hero badge a living, "epic" shine.
class _Shimmer extends StatefulWidget {
  final String svgString;
  final double size;
  const _Shimmer({required this.svgString, required this.size});
  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value; // band centre travels 0→1, then wraps
          return ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (rect) => LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.0),
                Colors.white.withValues(alpha: 0.55),
                Colors.white.withValues(alpha: 0.0),
              ],
              stops: [
                (t - 0.18).clamp(0.0, 1.0),
                t.clamp(0.0, 1.0),
                (t + 0.18).clamp(0.0, 1.0),
              ],
            ).createShader(rect),
            child: ColorFiltered(
              colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
              child: SvgPicture.string(widget.svgString,
                  width: widget.size, height: widget.size, allowDrawingOutsideViewBox: true),
            ),
          );
        },
      ),
    );
  }
}

// Medallion crest (inspired by tiered game ranks): a beveled frame + a faceted
// central GEM, with WINGS that escalate on higher tiers and a STAR + radiant RAYS
// at the top. `{c}` is substituted with the tier colour at render time.
String _medallion(int idx) {
  final b = StringBuffer(_defs);
  if (idx == 8) b.write(_rays);                 // Glory: radiant burst
  // Wings grow with prestige: none (Wood/Bronze) → small (Silver/Gold/Platinum)
  // → large (Diamond/Champion/Titan) → grand (Glory).
  final wl = idx >= 8 ? 3 : (idx >= 5 ? 2 : (idx >= 2 ? 1 : 0));
  if (wl > 0) b.write(_wings(wl));
  b..write(_frame)..write(_gem);
  if (idx >= 6) b.write(_star);                 // Champion / Titan / Glory: crown star
  return b.toString();
}

const String _defs =
    '<defs><radialGradient id="bvl" cx="42%" cy="30%">'
    '<stop offset="0%" stop-color="rgba(255,255,255,.34)"/>'
    '<stop offset="55%" stop-color="rgba(255,255,255,0)"/>'
    '<stop offset="100%" stop-color="rgba(0,0,0,.32)"/></radialGradient></defs>';

// Beveled hexagonal crest.
const String _frame =
    '<polygon points="40,7 63,20 63,47 40,62 17,47 17,20" fill="{c}"/>'
    '<polygon points="40,7 63,20 63,47 40,62 17,47 17,20" fill="url(#bvl)"/>'
    '<polygon points="40,12 58,22 58,45 40,55 22,45 22,22" fill="none" stroke="rgba(255,255,255,.5)" stroke-width="1.3"/>';

// Faceted central gem: white body with colour-shaded facets + a top highlight.
const String _gem =
    '<polygon points="40,21 54,35 40,53 26,35" fill="rgba(0,0,0,.22)"/>'
    '<polygon points="40,23 52,35 40,51 28,35" fill="rgba(255,255,255,.95)"/>'
    '<polygon points="40,23 52,35 40,35" fill="{c}" opacity=".50"/>'
    '<polygon points="40,23 28,35 40,35" fill="{c}" opacity=".28"/>'
    '<polygon points="40,51 52,35 40,35" fill="{c}" opacity=".68"/>'
    '<polygon points="40,51 28,35 40,35" fill="{c}" opacity=".44"/>'
    '<line x1="28" y1="35" x2="52" y2="35" stroke="rgba(255,255,255,.55)" stroke-width=".8"/>'
    '<polygon points="40,23 46,29 40,32 34,29" fill="rgba(255,255,255,.85)"/>';

// Five-point crown star above the crest.
const String _star =
    '<path d="M40,-3 L43.2,7 L53.5,7 L45.2,13.2 L48.4,23 L40,17 L31.6,23 L34.8,13.2 L26.5,7 L36.8,7 Z" fill="rgba(255,255,255,.95)"/>'
    '<path d="M40,1 L42,7 L48.5,7 L43.3,11 L45,17 L40,13.4 L35,17 L36.7,11 L31.5,7 L38,7 Z" fill="{c}" opacity=".55"/>';

// Upswept feather wings flanking the crest (extend outside the viewBox; allowed).
// Level 1 = small, 2 = large, 3 = grand. Feathers fan from a high outer tip down.
String _wings(int level) {
  switch (level) {
    case 3: // Glory — grand
      return '<g fill="{c}" opacity=".95">'
          '<path d="M19,30 Q-4,20 -24,8 Q-8,25 19,33 Z"/>'
          '<path d="M19,34 Q-2,27 -20,19 Q-5,31 19,37 Z"/>'
          '<path d="M19,38 Q-1,33 -14,29 Q-3,36 19,40 Z"/>'
          '<path d="M19,41 Q1,40 -8,38 Q-2,41 19,43 Z"/>'
          '<path d="M61,30 Q84,20 104,8 Q88,25 61,33 Z"/>'
          '<path d="M61,34 Q82,27 100,19 Q85,31 61,37 Z"/>'
          '<path d="M61,38 Q81,33 94,29 Q83,36 61,40 Z"/>'
          '<path d="M61,41 Q79,40 88,38 Q82,41 61,43 Z"/>'
          '</g>';
    case 2: // Diamond / Champion / Titan — large
      return '<g fill="{c}" opacity=".95">'
          '<path d="M19,30 Q-2,22 -18,12 Q-6,26 19,33 Z"/>'
          '<path d="M19,34 Q-1,28 -15,22 Q-4,31 19,37 Z"/>'
          '<path d="M19,38 Q0,34 -10,31 Q-2,35 19,40 Z"/>'
          '<path d="M19,41 Q2,40 -5,39 Q0,41 19,43 Z"/>'
          '<path d="M61,30 Q82,22 98,12 Q86,26 61,33 Z"/>'
          '<path d="M61,34 Q81,28 95,22 Q84,31 61,37 Z"/>'
          '<path d="M61,38 Q80,34 90,31 Q82,35 61,40 Z"/>'
          '<path d="M61,41 Q78,40 85,39 Q80,41 61,43 Z"/>'
          '</g>';
    default: // Silver / Gold / Platinum — small
      return '<g fill="{c}" opacity=".92">'
          '<path d="M19,29 Q4,23 -8,18 Q1,27 19,32 Z"/>'
          '<path d="M19,33 Q5,30 -6,27 Q2,32 19,36 Z"/>'
          '<path d="M19,37 Q6,36 -3,35 Q3,37 19,39 Z"/>'
          '<path d="M61,29 Q76,23 88,18 Q79,27 61,32 Z"/>'
          '<path d="M61,33 Q75,30 86,27 Q78,32 61,36 Z"/>'
          '<path d="M61,37 Q74,36 83,35 Q77,37 61,39 Z"/>'
          '</g>';
  }
}

// Radiant 16-point burst behind the crest (Glory only).
const String _rays =
    '<polygon points="40,-6 45,20 56,2 53,24 70,12 60,30 82,30 62,38 80,52 58,44 64,66 46,50 48,76 40,56 32,76 34,50 16,66 22,44 0,52 18,38 -2,30 20,30 10,12 27,24 24,2 35,20" fill="{c}" opacity=".35"/>';
