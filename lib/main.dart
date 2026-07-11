// main.dart — app entry. Loads the persistent repository before the app starts,
// then overrides the provider so all state reads from on-device storage.
// The full dark theme lives HERE (buildPhysicalTheme): every Material surface —
// dialogs, sheets, pickers, inputs, chips, snackbars — is themed once, so no
// stock-purple M3 widget can leak into the app's near-black look.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/habits.dart' show activeHabits;
import 'data/notifications.dart';
import 'data/persistent_repository.dart';
import 'data/rank_history.dart' show backfillRankLogs;
import 'data/readiness.dart' show backfillReadinessLogs;
import 'state/providers.dart';
import 'ui/main_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Edge-to-edge with light icons over the near-black background — the system
  // bars belong to the theme, not to the OS default grey.
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark, // iOS
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  final repo = await PersistentRepository.create();
  backfillReadinessLogs(repo); // ensure Daily Readiness has graphable history
  backfillRankLogs(repo); // ensure Overall + category ranks have graphable history
  // Proactive habit reminders (no-op on desktop/web; iOS/Android only).
  // Fire-and-forget so the iOS permission prompt never blocks first render.
  unawaited(NotificationService.instance.init().then(
      (_) => NotificationService.instance
          .syncHabitReminders(activeHabits(repo.loadHabits()))));
  runApp(ProviderScope(
    overrides: [repositoryProvider.overrideWithValue(repo)],
    child: const PhysicalApp(),
  ));
}

// ── Design tokens (single source for the Material layer; screens share the
// same values via their local consts) ──
const _bg = Color(0xFF04050C); // near-black screen
const _sheet = Color(0xFF090B18); // bottom sheets
const _card = Color(0xFF0D1024); // cards / dialogs
const _raised = Color(0xFF181B33); // snackbars / tooltips
const _accent = Color(0xFF5B6AF8);
const _muted = Color(0xFF7880A8);
const _border = Color(0x14FFFFFF);

/// The whole app's dark theme. Notable choices:
/// - surfaceTint is DISABLED everywhere: Material 3 washes elevated dark
///   surfaces with the seed colour (the purple sheen that makes dark apps look
///   cheap); our depth comes from explicit colours and glows instead.
/// - Every popup surface (dialog / sheet / date & time picker / menu /
///   snackbar) gets the card palette + 16-20px radii, so system-triggered UI
///   matches the hand-built screens.
/// - Inputs are themed once (rounded, faint border, accent focus) so every
///   dialog TextField in the app renders identically.
ThemeData buildPhysicalTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: _accent,
    brightness: Brightness.dark,
    surface: _card,
    onSurface: Colors.white,
  );
  final round12 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: _bg,
    colorScheme: scheme,
    splashColor: _accent.withValues(alpha: 0.08),
    highlightColor: Colors.white.withValues(alpha: 0.04),
    dividerTheme: const DividerThemeData(color: Color(0x0FFFFFFF), thickness: 1),
    appBarTheme: const AppBarTheme(
      backgroundColor: _bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0, // no tint flash when content scrolls under
      centerTitle: false,
      titleTextStyle: TextStyle(
          fontSize: 19, fontWeight: FontWeight.w900, letterSpacing: 0.5, color: Colors.white),
    ),
    cardTheme: CardThemeData(
      color: _card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: _border),
      ),
      margin: const EdgeInsets.symmetric(vertical: 5),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: _card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: _sheet,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: _sheet,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      dragHandleColor: Color(0x21FFFFFF),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: _raised,
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13.5),
      behavior: SnackBarBehavior.floating,
      shape: round12,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0x1FFFFFFF))),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0x1FFFFFFF))),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _accent, width: 1.4)),
      labelStyle: const TextStyle(color: _muted, fontSize: 13.5),
      hintStyle: TextStyle(color: _muted.withValues(alpha: 0.6), fontSize: 13.5),
      helperStyle: const TextStyle(color: _muted, fontSize: 11),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: _bg,
      surfaceTintColor: Colors.transparent,
      side: const BorderSide(color: _border),
      labelStyle: const TextStyle(fontSize: 12.5, color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      showCheckmark: false,
      selectedColor: _accent.withValues(alpha: 0.25),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: Colors.white,
      unselectedLabelColor: Color(0xFF525878),
      indicatorColor: _accent,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: Colors.transparent, // M3's full-width hairline reads as clutter
      labelStyle: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
      unselectedLabelStyle: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
        shape: round12,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: _muted,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
        shape: round12,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
        shape: round12,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    // The DOB + habit-time pickers: without this they render stock M3 purple.
    datePickerTheme: DatePickerThemeData(
      backgroundColor: _card,
      surfaceTintColor: Colors.transparent,
      headerBackgroundColor: _sheet,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    timePickerTheme: TimePickerThemeData(
      backgroundColor: _card,
      dialBackgroundColor: _sheet,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: _raised,
      surfaceTintColor: Colors.transparent,
      shape: round12,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: _accent),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: _accent,
      selectionColor: _accent.withValues(alpha: 0.3),
      selectionHandleColor: _accent,
    ),
  );
}

class PhysicalApp extends StatelessWidget {
  const PhysicalApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Physical',
      debugShowCheckedModeBanner: false,
      theme: buildPhysicalTheme(),
      home: const MainScreen(),
    );
  }
}
