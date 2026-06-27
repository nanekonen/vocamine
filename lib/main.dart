import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'screens/main_tab_screen.dart';
import 'screens/materials_screen.dart';
import 'screens/material_detail_screen.dart';
import 'screens/wordbook_list_screen.dart';
import 'screens/wordbook_screen.dart';
import 'screens/level_setup_screen.dart';
import 'screens/mypage_screen.dart';

void main() {
  runApp(const ProviderScope(child: VocamineApp()));
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const MainTabScreen()),
      GoRoute(path: '/setup', builder: (context, state) => const LevelSetupScreen()),
      GoRoute(path: '/mypage', builder: (context, state) => const MyPageScreen()),

      // 教材（フォルダ階層あり）
      GoRoute(path: '/materials', builder: (context, state) => const MaterialsScreen()),
      GoRoute(
        path: '/materials/folder',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return MaterialsScreen(
            folderId: extra['folderId'] as String,
            title: extra['title'] as String,
          );
        },
      ),
      GoRoute(
        path: '/materials/detail',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return MaterialDetailScreen(
            materialId: extra['materialId'] as String,
            title: extra['title'] as String,
          );
        },
      ),

      // 単語帳（フォルダ階層あり）
      GoRoute(path: '/wordbook', builder: (context, state) => const WordbookListScreen()),
      GoRoute(
        path: '/wordbook/folder',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return WordbookListScreen(
            folderId: extra['folderId'] as String,
            title: extra['title'] as String,
          );
        },
      ),
      GoRoute(
        path: '/wordbook/detail',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return WordbookScreen(
            wordbookId: extra['wordbookId'] as String,
            title: extra['title'] as String,
          );
        },
      ),
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