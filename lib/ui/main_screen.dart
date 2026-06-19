import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'progress_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08091A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF08091A),
        centerTitle: true,
        title: const Text('Physical',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 3)),
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
