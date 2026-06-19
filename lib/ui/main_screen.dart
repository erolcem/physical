import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/api_client.dart';
import '../data/sync.dart';
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
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _sync() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await syncNow(ref);
      final parity = r.backendOverall != null
          ? ' · backend overall ${r.backendOverall}'
          : '';
      messenger.showSnackBar(SnackBar(
        content: Text('Synced ${r.total} samples '
            '(${r.ingested} new, ${r.skipped} already there)$parity'),
      ));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Sync failed: ${e.message}')));
    } catch (_) {
      messenger.showSnackBar(SnackBar(
        content: Text("Couldn't reach the backend at $kBackendUrl — is it running?"),
      ));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08091A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF08091A),
        centerTitle: true,
        title: const Text('Physical',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 3)),
        actions: [
          IconButton(
            tooltip: 'Sync to backend',
            onPressed: _syncing ? null : _sync,
            icon: _syncing
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cloud_upload_outlined),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF5B6AF8),
          tabs: const [
            Tab(icon: Icon(Icons.dashboard), text: 'Dashboard'),
            Tab(icon: Icon(Icons.show_chart), text: 'Progress'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          HomeTab(),
          ProgressTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openLogSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Log'),
        backgroundColor: const Color(0xFF5B6AF8),
      ),
    );
  }
}
