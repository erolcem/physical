import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:physical/ui/guide_sheet.dart';

void main() {
  testWidgets('guide sheet renders headings + body', (tester) async {
    tester.view.physicalSize = const Size(440, 1700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (ctx) => Scaffold(
      body: Center(child: ElevatedButton(
          onPressed: () => openGuideSheet(ctx), child: const Text('open'))),
    ))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Guide'), findsOneWidget);
    expect(find.text('HOME'), findsOneWidget); // a heading rendered
  });
}
