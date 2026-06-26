// ui/badge.dart — tier medallions rendered from the handmade asset art
// (assets/badges/<tier>.png — borderless, consistent placement), wrapped with a
// soft tier-coloured aura so they pop on the dark background. The sub-rank (I/II/III)
// is shown as text beside the badge wherever it appears, so it isn't drawn on the art;
// `sub` is kept for API compatibility.
import 'package:flutter/material.dart';
import '../data/metrics.dart' show tierColor;

class RankBadge extends StatelessWidget {
  final String tier;
  final String? sub;
  final double size;
  final bool animated; // hero badges get a stronger aura
  const RankBadge({required this.tier, this.sub, this.size = 64, this.animated = false, super.key});

  @override
  Widget build(BuildContext context) {
    final c = tierColor(tier);
    final glow = animated ? 0.30 : 0.18;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Soft tier-coloured aura behind the art.
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [c.withValues(alpha: glow), c.withValues(alpha: 0.0)],
                stops: const [0.1, 0.75],
              ),
            ),
            child: SizedBox(width: size, height: size),
          ),
          Image.asset(
            'assets/badges/${tier.toLowerCase()}.png',
            width: size,
            height: size,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            // Unknown tier → no art; render nothing rather than throw.
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
