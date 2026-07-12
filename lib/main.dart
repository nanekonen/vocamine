import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
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
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF041627),
          onPrimary: Colors.white,
          primaryContainer: Color(0xFF1A2B3C),
          onPrimaryContainer: Color(0xFFD2E4FB),
          secondary: Color(0xFF0060AC),
          onSecondary: Colors.white,
          secondaryContainer: Color(0xFF68ABFF),
          onSecondaryContainer: Color(0xFF003E73),
          tertiary: Color(0xFF705D00),
          tertiaryContainer: Color(0xFFC9A900),
          error: Color(0xFFBA1A1A),
          surface: Color(0xFFF7F9FB),
          onSurface: Color(0xFF191C1E),
          onSurfaceVariant: Color(0xFF44474C),
          outline: Color(0xFF74777D),
          outlineVariant: Color(0xFFC4C6CD),
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7F9FB),
        fontFamily: GoogleFonts.inter().fontFamily,
        visualDensity: VisualDensity.standard,
        textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme)
            .copyWith(
              displaySmall: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 40,
                height: 1.2,
                letterSpacing: -0.8,
                fontWeight: FontWeight.w700,
                color: Color(0xFF041627),
              ),
              headlineSmall: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 24,
                height: 1.3,
                letterSpacing: -0.3,
                fontWeight: FontWeight.w600,
                color: Color(0xFF041627),
              ),
              titleLarge: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF041627),
              ),
              titleMedium: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF191C1E),
              ),
              bodyLarge: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 16,
                height: 1.5,
                color: Color(0xFF191C1E),
              ),
              bodyMedium: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: Color(0xFF44474C),
                height: 1.45,
              ),
              labelLarge: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
          toolbarHeight: 72,
          backgroundColor: Color(0xFFF7F9FB),
          foregroundColor: Color(0xFF041627),
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            fontFamily: 'Inter',
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: Color(0xFF041627),
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 1,
          shadowColor: const Color(0x141A2B3C),
          color: Colors.white,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
            side: const BorderSide(color: Color(0xFFDDE3EA)),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFFF2F4F6),
          selectedColor: const Color(0xFFD4E3FF),
          side: const BorderSide(color: Color(0xFFDDE3EA)),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          labelStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 12,
            letterSpacing: 0.3,
            color: Color(0xFF041627),
            fontWeight: FontWeight.w600,
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFFDDE3EA),
          thickness: 1,
          space: 1,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFF0060AC),
          foregroundColor: Colors.white,
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF041627),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            textStyle: const TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF0060AC),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            side: const BorderSide(color: Color(0xFF0060AC)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            textStyle: const TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFFFFFFF),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: const BorderSide(color: Color(0xFFC4C6CD)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: const BorderSide(color: Color(0xFFC4C6CD)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: const BorderSide(color: Color(0xFF0060AC), width: 2),
          ),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Color(0xFFF2F4F6),
          indicatorColor: Color(0xFFFFE16D),
          elevation: 0,
          height: 72,
        ),
        listTileTheme: const ListTileThemeData(
          iconColor: Color(0xFF44474C),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          titleTextStyle: TextStyle(
            fontFamily: 'Inter',
            color: Color(0xFF191C1E),
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          subtitleTextStyle: TextStyle(color: Color(0xFF74777D)),
        ),
      ),
      routerConfig: router,
    );
  }
}
