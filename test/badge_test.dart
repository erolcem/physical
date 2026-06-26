// Every tier medallion must compose into valid SVG that flutter_svg can render.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:physical/ui/badge.dart';

void main() {
  testWidgets('every tier badge renders without throwing', (tester) async {
    const tiers = ['Wood', 'Bronze', 'Silver', 'Gold', 'Platinum',
      'Diamond', 'Champion', 'Titan', 'Glory'];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Wrap(children: [for (final t in tiers) RankBadge(tier: t, size: 60)]),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(RankBadge), findsNWidgets(9));
    expect(tester.takeException(), isNull);
  });
}
