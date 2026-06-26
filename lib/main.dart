import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'screens/home_screen.dart';
import 'screens/material_reader_screen.dart';
import 'screens/wordbook_screen.dart';
import 'screens/level_setup_screen.dart';

void main() {
  runApp(const ProviderScope(child: VocamineApp()));
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
      GoRoute(path: '/setup', builder: (context, state) => const LevelSetupScreen()),
      GoRoute(path: '/reader', builder: (context, state) => const MaterialReaderScreen()),
      GoRoute(path: '/wordbook', builder: (context, state) => const WordbookScreen()),
    ],
  );
});

class VocamineApp extends ConsumerWidget {
  const VocamineApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Vocamine',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D6B)),
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}