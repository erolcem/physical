// ui/badge.dart — tier medallions rendered from the handmade asset art
// (assets/badges/<tier>.png — borderless, consistent placement), wrapped with a
// tier-scaled glow + shine behind the art so higher ranks visibly radiate more.
// The sub-rank (I/II/III) is shown as text beside the badge wherever it appears,
// so it isn't drawn on the art; `sub` is kept for API compatibility.
import 'package:flutter/material.dart';
import '../data/metrics.dart' show tierColor;

const List<String> _tierOrder = [
  'Wood', 'Bronze', 'Silver', 'Gold', 'Platinum', 'Diamond', 'Champion', 'Titan', 'Glory'
];

class RankBadge extends StatelessWidget {
  final String tier;
  final String? sub;
  final double size;
  final bool animated; // hero badges get a stronger aura
  const RankBadge({required this.tier, this.sub, this.size = 64, this.animated = false, super.key});

  @override
  Widget build(BuildContext context) {
    final c = tierColor(tier);
    final i = _tierOrder.indexOf(tier);
    final t = (i < 0 ? 0 : i) / 8.0; // 0 (Wood) … 1 (Glory)
    // Glow + halo size scale with the rank; the hero adds a little extra.
    final auraA = ((0.16 + t * 0.5) * (animated ? 1.2 : 1.0)).clamp(0.0, 0.72);
    final auraSize = size * (1.18 + t * 0.32);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Tier-coloured glow that extends beyond the medallion, stronger by rank.
          SizedBox(
            width: auraSize,
            height: auraSize,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    c.withValues(alpha: auraA),
                    c.withValues(alpha: auraA * 0.45),
                    c.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 0.42, 0.95],
                ),
              ),
            ),
          ),
          // A soft white shine core for extra lustre on higher tiers.
          SizedBox(
            width: size * 0.85,
            height: size * 0.85,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.10 + t * 0.16),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 0.6],
                ),
              ),
            ),
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
