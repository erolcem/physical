// main.dart — app entry. Loads the persistent repository before the app starts,
// then overrides the provider so all state reads from on-device storage.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/persistent_repository.dart';
import 'state/providers.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repo = await PersistentRepository.create();
  runApp(ProviderScope(
    overrides: [repositoryProvider.overrideWithValue(repo)],
    child: const PhysicalApp(),
  ));
}

class PhysicalApp extends StatelessWidget {
  const PhysicalApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Physical',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF08091A),
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF5B6AF8), brightness: Brightness.dark),
        cardTheme: CardThemeData(
          color: const Color(0xFF12152E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          margin: const EdgeInsets.symmetric(vertical: 5),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
