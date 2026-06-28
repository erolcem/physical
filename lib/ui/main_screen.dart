import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/notifications.dart';
import '../data/sync.dart' show apiClientProvider, cloudSync;
import '../state/habit_providers.dart';
import 'cloud_sheet.dart';
import 'coach_screen.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoSync());
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

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keep daily habit reminders in sync as habits change (no-op off-device).
    ref.listen<HabitsState>(habitsProvider, (_, next) {
      NotificationService.instance.syncHabitReminders(next.habits);
    });
    return Scaffold(
      backgroundColor: const Color(0xFF08091A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF08091A),
        centerTitle: true,
        toolbarHeight: 64,
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
