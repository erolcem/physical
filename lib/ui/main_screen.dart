import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import '../data/ai_verify.dart' show runAiVerification;
import '../data/habits.dart' show Habit;
import '../data/notifications.dart';
import '../data/profile.dart' show syncAgeFromDob;
import '../data/sync.dart' show apiClientProvider, cloudSync;
import '../state/habit_providers.dart';
import '../state/log_providers.dart' show dietProvider, workoutProvider;
import '../state/providers.dart' show logsProvider, repositoryProvider;
import 'cloud_sheet.dart';
import 'coach_screen.dart';
import 'guide_sheet.dart';
import 'habits_screen.dart';
import 'home_screen.dart';
import 'progress_screen.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _autoSynced = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    // Auto-sync once on launch (best-effort, silent) so the app opens up to date.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Age derives from DOB — refresh on launch so birthdays auto-correct.
      if (syncAgeFromDob(ref.read(repositoryProvider)) != null) {
        ref.read(logsProvider.notifier).reload();
      }
      _autoSync();
    });
  }

  Future<void> _autoSync() async {
    if (_autoSynced) return;
    _autoSynced = true;
    try {
      final api = ref.read(apiClientProvider);
      await api.loadPersistedToken();
      if (!api.isSignedIn || !mounted) return;
      await cloudSync(ref); // pulls Google + merges/pushes the backup, refreshing providers
    } catch (_) {/* launch sync is best-effort — the ☁ button is always there */}
  }

  // ── Automatic Google Calendar mirror: whenever the habit LIST changes (add /
  // edit / remove — not check-offs), push the roster to Calendar. Debounced so a
  // burst of edits becomes one push; silent + best-effort (the Habits tab's
  // Calendar button and each sync remain the visible/retry paths). ──
  Timer? _calendarDebounce;
  String _habitsFingerprint(List<Habit> habits) =>
      [for (final h in habits) h.toJson().toString()].join('|');

  void _scheduleCalendarPush(List<Habit> habits) {
    _calendarDebounce?.cancel();
    _calendarDebounce = Timer(const Duration(seconds: 4), () async {
      try {
        final api = ref.read(apiClientProvider);
        await api.loadPersistedToken();
        if (!api.isSignedIn) return;
        String? tz;
        try {
          tz = await FlutterTimezone.getLocalTimezone();
        } catch (_) {/* floating times */}
        await api.pushCalendar([for (final h in habits) h.toJson()], tz);
      } catch (_) {/* best-effort — sync + the Calendar button retry it */}
    });
  }

  // ── Verdict freshness: the AI check runs at sync time (often morning) and can
  // store done=false for "Train"; logging the workout that afternoon would then
  // sit UNDER the stale verdict until the next sync. Whenever local evidence
  // changes (a set logged, food imported), re-run the verification for today —
  // debounced so a burst of set-logging becomes a single verification call. ──
  Timer? _verifyDebounce;
  bool _verifyInFlight = false;

  void _scheduleReverify() {
    _verifyDebounce?.cancel();
    _verifyDebounce = Timer(const Duration(seconds: 25), () async {
      if (_verifyInFlight) return;
      _verifyInFlight = true;
      try {
        final api = ref.read(apiClientProvider);
        await api.loadPersistedToken();
        if (!api.isSignedIn) return;
        final judged =
            await runAiVerification(api, ref.read(repositoryProvider));
        if (judged != null && judged > 0 && mounted) {
          ref.read(habitsProvider.notifier).reload();
        }
      } catch (_) {/* best-effort — the sync-time check remains */} finally {
        _verifyInFlight = false;
      }
    });
  }

  @override
  void dispose() {
    _verifyDebounce?.cancel();
    _calendarDebounce?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keep daily habit reminders in sync as habits change (no-op off-device),
    // and mirror habit add/edit/remove into Google Calendar automatically.
    ref.listen<HabitsState>(habitsProvider, (prev, next) {
      NotificationService.instance.syncHabitReminders(next.habits);
      if (prev != null &&
          _habitsFingerprint(prev.habits) != _habitsFingerprint(next.habits)) {
        _scheduleCalendarPush(next.habits);
      }
    });
    // Fresh evidence → fresh verdicts (see _scheduleReverify).
    ref.listen(workoutProvider, (prev, next) {
      if (prev != null && !identical(prev, next)) _scheduleReverify();
    });
    ref.listen(dietProvider, (prev, next) {
      if (prev != null && !identical(prev, next)) _scheduleReverify();
    });
    return Scaffold(
      backgroundColor: const Color(0xFF08091A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF08091A),
        centerTitle: true,
        toolbarHeight: 64,
        leading: IconButton(
          tooltip: 'Guide',
          onPressed: () => openGuideSheet(context),
          icon: const Icon(Icons.help_outline),
        ),
        // Centred logo that fits the toolbar — sits cleanly above the page tabs without
        // overflowing onto them or pushing the body content down.
        title: Image.asset('assets/brand/header.png',
            height: 56, fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Text('Physical',
                style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 3))),
        actions: [
          IconButton(
            tooltip: 'Cloud sync',
            onPressed: () => openCloudSheet(context),
            icon: const Icon(Icons.cloud_sync_outlined),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: false,
          indicatorColor: const Color(0xFF5B6AF8),
          labelPadding: const EdgeInsets.symmetric(horizontal: 2),
          tabs: const [
            Tab(icon: Icon(Icons.dashboard), text: 'Home'),
            Tab(icon: Icon(Icons.show_chart), text: 'Progress'),
            Tab(icon: Icon(Icons.checklist), text: 'Habits'),
            Tab(icon: Icon(Icons.auto_awesome), text: 'Coach'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          HomeTab(),
          ProgressTab(),
          HabitsTab(),
          CoachTab(),
        ],
      ),
      // No global "Log" FAB: metrics are logged from their front-page cards, and
      // exercise + diet are reached from the Progress tab (auto-imported where possible).
    );
  }
}
