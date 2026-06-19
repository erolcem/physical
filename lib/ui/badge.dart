// ui/badge.dart — procedural tier medallion (no asset/dependency). A faceted
// hexagon filled and glowing by tier color, with the subrank numeral. Swap for
// your own SVGs later if you want the prototype look back.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../data/metrics.dart' show tierColor;

class RankBadge extends StatelessWidget {
  final String tier;
  final String? sub;
  final double size;
  const RankBadge({required this.tier, this.sub, this.size = 56, super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _BadgePainter(tier, sub, _tierIndex(tier))),
      );

  static int _tierIndex(String t) {
    const order = ['Wood', 'Bronze', 'Silver', 'Gold', 'Platinum',
      'Diamond', 'Champion', 'Titan', 'Glory'];
    final i = order.indexOf(t);
    return i < 0 ? 0 : i;
  }
}

class _BadgePainter extends CustomPainter {
  final String tier;
  final String? sub;
  final int tierIdx;
  _BadgePainter(this.tier, this.sub, this.tierIdx);

  Path _hex(Offset c, double r) {
    final p = Path();
    for (var i = 0; i < 6; i++) {
      final a = (-90 + 60 * i) * math.pi / 180;
      final pt = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
      i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
    }
    return p..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final base = tierColor(tier);
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.42;
    final hex = _hex(center, r);

    // Glow behind (stronger for higher tiers)
    final glow = 3.0 + tierIdx * 1.4;
    canvas.drawPath(
      hex,
      Paint()
        ..color = base.withOpacity(0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, glow),
    );

    // Faceted fill: light top-left -> base -> darker edge
    final light = Color.lerp(base, Colors.white, 0.45)!;
    final dark = Color.lerp(base, Colors.black, 0.40)!;
    canvas.drawPath(
      hex,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.45),
          radius: 1.0,
          colors: [light, base, dark],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: r)),
    );

    // Top bevel highlight
    final topHi = Path()
      ..moveTo(center.dx, center.dy - r)
      ..lineTo(center.dx + r * 0.5, center.dy - r * 0.28)
      ..lineTo(center.dx, center.dy - r * 0.1)
      ..lineTo(center.dx - r * 0.5, center.dy - r * 0.28)
      ..close();
    canvas.drawPath(topHi, Paint()..color = Colors.white.withOpacity(0.18));

    // Rim
    canvas.drawPath(
      hex,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.03
        ..color = light.withOpacity(0.9),
    );

    // Subrank numeral
    if (sub != null && sub!.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(
          text: sub,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: size.width * 0.30,
            shadows: const [Shadow(color: Colors.black54, blurRadius: 2)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _BadgePainter old) =>
      old.tier != tier || old.sub != sub;
}
