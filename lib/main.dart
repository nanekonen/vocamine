import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
import 'services/app_messenger.dart';
import 'services/supabase_auth_service.dart';
import 'services/vocamine_api_client.dart';
import 'screens/learned_words_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  await SupabaseAuthService.initialize();
  runApp(const ProviderScope(child: GlossalyzeApp()));
}

final routerProvider = Provider<GoRouter>((ref) {
  late final GoRouter router;
  router = GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final session = ref.read(appSessionProvider);
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
      GoRoute(path: '/', builder: (context, state) => const _RootScreen()),
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
          final extra = state.extra is Map<String, dynamic>
              ? state.extra! as Map<String, dynamic>
              : const <String, dynamic>{};
          final folderId =
              state.uri.queryParameters['folderId'] ??
              extra['folderId'] as String?;
          if (folderId == null || folderId.isEmpty) {
            return const _InvalidRouteScreen(message: '教材フォルダが指定されていません');
          }
          return MaterialsScreen(
            folderId: folderId,
            title:
                state.uri.queryParameters['title'] ??
                extra['title'] as String? ??
                '教材フォルダ',
          );
        },
      ),
      GoRoute(
        path: '/materials/detail',
        builder: (context, state) {
          final extra = state.extra is Map<String, dynamic>
              ? state.extra! as Map<String, dynamic>
              : const <String, dynamic>{};
          final materialId =
              state.uri.queryParameters['materialId'] ??
              extra['materialId'] as String?;
          if (materialId == null || materialId.isEmpty) {
            return const _InvalidRouteScreen(message: '教材が指定されていません');
          }
          return MaterialDetailScreen(
            materialId: materialId,
            title:
                state.uri.queryParameters['title'] ??
                extra['title'] as String? ??
                '教材',
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
          final extra = state.extra is Map<String, dynamic>
              ? state.extra! as Map<String, dynamic>
              : const <String, dynamic>{};
          final folderId =
              state.uri.queryParameters['folderId'] ??
              extra['folderId'] as String?;
          if (folderId == null || folderId.isEmpty) {
            return const _InvalidRouteScreen(message: '単語帳フォルダが指定されていません');
          }
          return WordbookListScreen(
            folderId: folderId,
            title:
                state.uri.queryParameters['title'] ??
                extra['title'] as String? ??
                '単語帳フォルダ',
          );
        },
      ),
      GoRoute(
        path: '/wordbook/detail',
        builder: (context, state) {
          final extra = state.extra is Map<String, dynamic>
              ? state.extra! as Map<String, dynamic>
              : const <String, dynamic>{};
          final wordbookId =
              state.uri.queryParameters['wordbookId'] ??
              extra['wordbookId'] as String?;
          if (wordbookId == null || wordbookId.isEmpty) {
            return const _InvalidRouteScreen(message: '単語帳が指定されていません');
          }
          return WordbookScreen(
            wordbookId: wordbookId,
            title:
                state.uri.queryParameters['title'] ??
                extra['title'] as String? ??
                '単語帳',
          );
        },
      ),
    ],
  );
  ref.listen<AppSession>(appSessionProvider, (previous, next) {
    final routingStateChanged =
        previous?.isLoaded != next.isLoaded ||
        previous?.isLoggedIn != next.isLoggedIn ||
        previous?.setupCompleted != next.setupCompleted;
    if (routingStateChanged) router.refresh();
  });
  ref.onDispose(router.dispose);
  return router;
});

class _RootScreen extends ConsumerWidget {
  const _RootScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(appSessionProvider);
    if (!session.isLoaded) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('ログイン情報を読み込み中…'),
            ],
          ),
        ),
      );
    }
    if (!session.isLoggedIn) return const LoginScreen();
    if (!session.setupCompleted) return const LevelSetupScreen();
    return const MainTabScreen();
  }
}

class _InvalidRouteScreen extends StatelessWidget {
  final String message;

  const _InvalidRouteScreen({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(child: Text(message)),
    );
  }
}

class GlossalyzeApp extends ConsumerStatefulWidget {
  const GlossalyzeApp({super.key});

  @override
  ConsumerState<GlossalyzeApp> createState() => _GlossalyzeAppState();
}

class _GlossalyzeAppState extends ConsumerState<GlossalyzeApp> {
  final _api = VocamineApiClient();
  final _appLinks = AppLinks();
  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<Uri>? _deepLinkSubscription;
  String? _lastSyncedAccessToken;
  bool _handlingAuthCallback = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_initializeSession);
  }

  Future<void> _initializeSession() async {
    await ref.read(appSessionProvider.notifier).load();
    if (!SupabaseAuthService.isConfigured) return;

    _authSubscription = SupabaseAuthService.auth.onAuthStateChange.listen((
      state,
    ) {
      if (state.event == AuthChangeEvent.signedOut) {
        _lastSyncedAccessToken = null;
        unawaited(ref.read(appSessionProvider.notifier).signOut());
        return;
      }
      final accessToken = state.session?.accessToken;
      if (accessToken != null && accessToken.isNotEmpty) {
        unawaited(_syncAuthenticatedSession(accessToken));
      }
    });

    if (!kIsWeb) {
      _deepLinkSubscription = _appLinks.uriLinkStream.listen(
        (uri) => unawaited(_handleNativeAuthCallback(uri)),
        onError: (Object error) {
          AppMessenger.show('ログイン画面からアプリへ戻れませんでした: $error');
        },
      );
      final initialLink = await _appLinks.getInitialLink();
      if (initialLink != null) {
        await _handleNativeAuthCallback(initialLink);
      }
    }

    final accessToken = SupabaseAuthService.auth.currentSession?.accessToken;
    if (accessToken != null && accessToken.isNotEmpty) {
      await _syncAuthenticatedSession(accessToken);
    }
  }

  Future<void> _handleNativeAuthCallback(Uri uri) async {
    final isLoginCallback =
        uri.scheme == 'com.example.vacamine' && uri.host == 'login-callback';
    if (!isLoginCallback || _handlingAuthCallback) return;

    final callbackError =
        uri.queryParameters['error_description'] ??
        uri.queryParameters['error'];
    if (callbackError != null && callbackError.isNotEmpty) {
      AppMessenger.show('Googleログインに失敗しました: $callbackError');
      return;
    }
    if (!uri.queryParameters.containsKey('code') &&
        !uri.fragment.contains('access_token=')) {
      return;
    }

    _handlingAuthCallback = true;
    AppMessenger.show('Googleログインを確認中…');
    try {
      await SupabaseAuthService.auth
          .getSessionFromUrl(uri)
          .timeout(const Duration(seconds: 30));
      final accessToken = SupabaseAuthService.auth.currentSession?.accessToken;
      if (accessToken == null || accessToken.isEmpty) {
        throw Exception('Supabaseセッションを取得できませんでした');
      }
      await _syncAuthenticatedSession(accessToken);
    } on TimeoutException {
      AppMessenger.show('Googleログインの確認がタイムアウトしました');
    } catch (error) {
      AppMessenger.show('Googleログインの確認に失敗しました: $error');
    } finally {
      _handlingAuthCallback = false;
    }
  }

  Future<void> _syncAuthenticatedSession(String accessToken) async {
    if (_lastSyncedAccessToken == accessToken) return;
    _lastSyncedAccessToken = accessToken;
    try {
      final session = await _api.resolveAuthSession(accessToken: accessToken);
      await ref
          .read(appSessionProvider.notifier)
          .save(
            userId: session.userId,
            email: session.email,
            username: session.username,
            level: session.level,
            setupCompleted: session.setupCompleted,
          );
    } catch (error) {
      _lastSyncedAccessToken = null;
      AppMessenger.show('ログイン情報の取得に失敗しました: $error');
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _deepLinkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Glossalyze',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: AppMessenger.key,
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
