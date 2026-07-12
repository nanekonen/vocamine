import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'screens/main_tab_screen.dart';
import 'screens/materials_screen.dart';
import 'screens/material_detail_screen.dart';
import 'screens/wordbook_list_screen.dart';
import 'screens/wordbook_screen.dart';
import 'screens/level_setup_screen.dart';
import 'screens/mypage_screen.dart';
import 'screens/auth_callback_screen.dart';
import 'screens/login_screen.dart';
import 'services/app_session.dart';
import 'services/supabase_auth_service.dart';
import 'screens/learned_words_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  await SupabaseAuthService.initialize();
  runApp(const ProviderScope(child: VocamineApp()));
}

final routerProvider = Provider<GoRouter>((ref) {
  final session = ref.watch(appSessionProvider);
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final path = state.uri.path;
      if (path == '/auth/callback') {
        return null;
      }
      if (!session.isLoaded) {
        return null;
      }
      if (!session.isLoggedIn) {
        return path == '/' ? null : '/';
      }
      if (!session.setupCompleted && path != '/setup') {
        return '/setup';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) {
          if (!session.isLoaded) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (!session.isLoggedIn) {
            return const LoginScreen();
          }
          if (!session.setupCompleted) {
            return const LevelSetupScreen();
          }
          return const MainTabScreen();
        },
      ),
      GoRoute(
        path: '/auth/callback',
        builder: (context, state) => AuthCallbackScreen(callbackUri: state.uri),
      ),
      GoRoute(
        path: '/setup',
        builder: (context, state) => const LevelSetupScreen(),
      ),
      GoRoute(
        path: '/mypage',
        builder: (context, state) => const MyPageScreen(),
      ),
      GoRoute(
        path: '/mypage/learned',
        builder: (context, state) => const LearnedWordsScreen(),
      ),
      // 教材（フォルダ階層あり）
      GoRoute(
        path: '/materials',
        builder: (context, state) => const MaterialsScreen(),
      ),
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
      GoRoute(
        path: '/wordbook',
        builder: (context, state) => const WordbookListScreen(),
      ),
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

class VocamineApp extends ConsumerStatefulWidget {
  const VocamineApp({super.key});

  @override
  ConsumerState<VocamineApp> createState() => _VocamineAppState();
}

class _VocamineAppState extends ConsumerState<VocamineApp> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(appSessionProvider.notifier).load());
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Vocamine',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3C6F64),
          brightness: Brightness.light,
          surface: const Color(0xFFFCFAF6),
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFFCFAF6),
        fontFamily: 'Roboto',
        textTheme: ThemeData.light().textTheme.copyWith(
          headlineSmall: const TextStyle(
            fontFamily: 'Georgia',
            fontWeight: FontWeight.w700,
            color: Color(0xFF232824),
          ),
          titleLarge: const TextStyle(
            fontFamily: 'Georgia',
            fontWeight: FontWeight.w700,
            color: Color(0xFF232824),
          ),
          titleMedium: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF232824),
          ),
          bodyMedium: const TextStyle(color: Color(0xFF353A36), height: 1.45),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Color(0xFFFCFAF6),
          foregroundColor: Color(0xFF232824),
          titleTextStyle: TextStyle(
            fontFamily: 'Georgia',
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Color(0xFF232824),
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xFFE3DED3)),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFFF2EFE8),
          selectedColor: const Color(0xFFE0ECE8),
          side: const BorderSide(color: Color(0xFFE3DED3)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          labelStyle: const TextStyle(
            color: Color(0xFF4A504B),
            fontWeight: FontWeight.w600,
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFFE3DED3),
          thickness: 1,
          space: 1,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFF4D756C),
          foregroundColor: Colors.white,
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF4D756C),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF3C6F64),
            side: const BorderSide(color: Color(0xFFB7C8C2)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        listTileTheme: const ListTileThemeData(
          iconColor: Color(0xFF5D645F),
          titleTextStyle: TextStyle(
            color: Color(0xFF232824),
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
          subtitleTextStyle: TextStyle(color: Color(0xFF6E756F)),
        ),
      ),
      routerConfig: router,
    );
  }
}
