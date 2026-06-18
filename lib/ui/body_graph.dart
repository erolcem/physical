// ui/body_graph.dart — paints a front or back figure, colouring each muscle by
// its metric's tier (inert grey if no metric/data), and routes taps back to the
// metric via point-in-polygon hit testing. Wrap in AspectRatio(148/420).
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
  const BodyGraph({required this.regions, required this.onTapMetric, super.key});

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
        if (log != null && eng.standards.containsKey(metricId)) {
          c = tierColor(eng.scoreLog(log).tier);
          isRanked = true;
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
          painter: _BodyPainter(regions, colors, ranked),
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
  _BodyPainter(this.regions, this.colors, this.ranked);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 148.0;
    Path path(List<Offset> pts) {
      final p = Path()..moveTo(pts[0].dx * scale, pts[0].dy * scale);
      for (var i = 1; i < pts.length; i++) {
        p.lineTo(pts[i].dx * scale, pts[i].dy * scale);
      }
      return p..close();
    }

    canvas.drawPath(path(parsePoly(silhouette)),
        Paint()..color = const Color(0xFF1C1E3A));
    canvas.drawPath(path(parsePoly(neck)), Paint()..color = const Color(0xFF3A3F58));

    for (final r in regions) {
      final c = colors[r.muscle] ?? _inert;
      final isRanked = ranked[r.muscle] ?? false;
      for (final ps in r.polys) {
        final pth = path(parsePoly(ps));
        if (isRanked) {
          canvas.drawPath(
              pth,
              Paint()
                ..color = c.withOpacity(0.5)
                ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
        }
        canvas.drawPath(pth, Paint()..color = c.withOpacity(isRanked ? 0.9 : 0.18));
        canvas.drawPath(
            pth,
            Paint()
              ..color = c.withOpacity(isRanked ? 0.9 : 0.3)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.6);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BodyPainter old) => true;
}
