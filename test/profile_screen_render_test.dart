// Profile = NUMERIC ENTRIES (age/height/weight/body fat), not graphs — and
// weight/body-fat are manually loggable in-app, not import-only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:physical/data/repository.dart';
import 'package:physical/engine/rank_engine.dart' show Log;
import 'package:physical/state/providers.dart';
import 'package:physical/ui/profile_screen.dart';

void main() {
  testWidgets('profile shows plain numbers with manual-entry rows', (tester) async {
    tester.view.physicalSize = const Size(440, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = InMemoryRepository();
    repo.saveLog('age', Log('age', 28, ts: '2026-07-01T08:00:00'));
    repo.saveLog('height', Log('height', 180, ts: '2026-07-01T08:00:00'));
    repo.saveLog('bodyweight', Log('bodyweight', 78.4, ts: '2026-07-01T08:00:00'));
    repo.saveLog('body_fat_pct', Log('body_fat_pct', 15.2, ts: '2026-07-01T08:00:00'));
    await tester.pumpWidget(ProviderScope(
      overrides: [repositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: ProfileScreen()),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Numeric entries, present and plain — no chart widgets on this screen.
    expect(find.text('28 yr'), findsOneWidget);
    expect(find.text('180 cm'), findsOneWidget);
    expect(find.text('78.4 kg'), findsOneWidget);
    expect(find.text('15.2 %'), findsOneWidget);
    expect(find.text('Male'), findsOneWidget);
  });

  testWidgets('weight is manually loggable via the quick-log dialog', (tester) async {
    tester.view.physicalSize = const Size(440, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = InMemoryRepository();
    await tester.pumpWidget(ProviderScope(
      overrides: [repositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: ProfileScreen()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weight'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '79.5');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    // Saved as a real bodyweight log — the value every strength rank scales by.
    expect(repo.loadLogs()['bodyweight']!.single.value, 79.5);
    expect(find.text('79.5 kg'), findsOneWidget);
  });
}
