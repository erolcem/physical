// ui/body_graph.dart — paints a front, back, or inner figure, colouring each
// muscle by its metric's tier (inert grey if no metric/data), and routes taps
// back to the metric via point-in-polygon hit testing.
// Wrap in AspectRatio(148/420).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/body_figure_data.dart';
import '../data/metrics.dart' show tierColor;
import '../engine/rank_engine.dart' as eng;
import '../state/providers.dart';

const Color _inert = Color(0xFF5A6072);

class BodyGraph extends ConsumerWidget {
  final List<BodyRegion> regions;
  final void Function(String metricId) onTapMetric;
  final bool isHeadOnly;
  const BodyGraph({required this.regions, required this.onTapMetric, this.isHeadOnly = false, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latest = ref.watch(latestLogsProvider);
    final colors = <String, Color>{};
    final ranked = <String, bool>{};
    for (final r in regions) {
      final metricId = muscleToMetric[r.muscle];
      var c = _inert;
      var isRanked = false;
      if (metricId != null) {
        final log = latest[metricId];
        if (log != null) {
          if (eng.standards.containsKey(metricId)) {
            c = tierColor(eng.scoreLog(log).tier);
            isRanked = true;
          } else {
            // Tracked/Aesthetics metric with data
            c = const Color(0xFF4CE0C3);
            isRanked = true; // trigger glow
          }
        }
      }
      colors[r.muscle] = c;
      ranked[r.muscle] = isRanked;
    }

    return LayoutBuilder(builder: (ctx, cons) {
      final w = cons.maxWidth;
      final scale = w / 148.0;
      return GestureDetector(
        onTapUp: (d) {
          final vb = Offset(d.localPosition.dx / scale, d.localPosition.dy / scale);
          for (final r in regions) {
            final metricId = muscleToMetric[r.muscle];
            if (metricId == null) continue;
            for (final ps in r.polys) {
              if (_inPoly(vb, parsePoly(ps))) {
                onTapMetric(metricId);
                return;
              }
            }
          }
        },
        child: CustomPaint(
          size: Size(w, w * 420 / 148),
          painter: _BodyPainter(regions, colors, ranked, isHeadOnly: isHeadOnly),
        ),
      );
    });
  }
}

bool _inPoly(Offset p, List<Offset> poly) {
  var inside = false;
  for (int i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final a = poly[i], b = poly[j];
    if (((a.dy > p.dy) != (b.dy > p.dy)) &&
        (p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx)) {
      inside = !inside;
    }
  }
  return inside;
}

class _BodyPainter extends CustomPainter {
  final List<BodyRegion> regions;
  final Map<String, Color> colors;
  final Map<String, bool> ranked;
  final bool isHeadOnly;
  _BodyPainter(this.regions, this.colors, this.ranked, {this.isHeadOnly = false});

  @override
  void paint(Canvas canvas, Size size) {
    if (isHeadOnly) {
      canvas.scale(2.5, 2.5);
      canvas.translate(-size.width * 0.3, -size.height * 0.01);
    }
    final scale = size.width / 148.0;
    final center = Offset(size.width / 2, size.height * 0.4);

    Path path(List<Offset> pts) {
      final p = Path()..moveTo(pts[0].dx * scale, pts[0].dy * scale);
      for (var i = 1; i < pts.length; i++) {
        p.lineTo(pts[i].dx * scale, pts[i].dy * scale);
      }
      return p..close();
    }

    // ── Radial gradient background glow (from old .bodygraph-section::before)
    final bgGlowPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 0.8,
        colors: [
          const Color(0xFF3ECAB4).withValues(alpha: 0.06),
          const Color(0xFF3ECAB4).withValues(alpha: 0.0),
        ],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCenter(
        center: center,
        width: size.width * 1.6,
        height: size.height * 1.2,
      ));
    canvas.drawRect(Offset.zero & size, bgGlowPaint);

    // ── Silhouette + neck (subtle vertical gradient + faint rim for definition)
    final silPath = path(parsePoly(silhouette));
    canvas.drawPath(
      silPath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0xFF272C52), Color(0xFF141631)],
        ).createShader(silPath.getBounds()),
    );
    canvas.drawPath(
      silPath,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(path(parsePoly(neck)),
        Paint()..color = const Color(0xFF3A3F58));

    // ── Muscle / organ regions
    for (final r in regions) {
      final c = colors[r.muscle] ?? _inert;
      final isRanked = ranked[r.muscle] ?? false;
      for (final ps in r.polys) {
        final pth = path(parsePoly(ps));

        if (isRanked) {
          // Drop-shadow glow behind ranked muscle
          canvas.drawPath(
            pth,
            Paint()
              ..color = c.withValues(alpha: 0.45)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
          );
          // Stronger inner glow
          canvas.drawPath(
            pth,
            Paint()
              ..color = c.withValues(alpha: 0.25)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
          );
        }

        // Fill — glossy top-lit gradient for lit muscles; faint for the rest.
        if (isRanked) {
          canvas.drawPath(
            pth,
            Paint()
              ..shader = LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Color.lerp(c, Colors.white, 0.42)!, c],
              ).createShader(pth.getBounds()),
          );
        } else {
          canvas.drawPath(pth, Paint()..color = c.withValues(alpha: 0.15));
        }

        // Stroke — brighter and slightly thicker for ranked muscles
        canvas.drawPath(
          pth,
          Paint()
            ..color = c.withValues(alpha: isRanked ? 1.0 : 0.3)
            ..style = PaintingStyle.stroke
            ..strokeJoin = StrokeJoin.round
            ..strokeCap = StrokeCap.round
            ..strokeWidth = isRanked ? 1.0 : 0.6,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BodyPainter old) => true;
}
