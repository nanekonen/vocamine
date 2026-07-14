import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/app_session.dart';
import '../services/supabase_auth_service.dart';

class MyPageScreen extends ConsumerStatefulWidget {
  const MyPageScreen({super.key});

  @override
  ConsumerState<MyPageScreen> createState() => _MyPageScreenState();
}

class _MyPageScreenState extends ConsumerState<MyPageScreen> {
  @override
  Widget build(BuildContext context) {
    final session = ref.watch(appSessionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('マイページ')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    color: const Color(0xFFECEEF0),
                    alignment: Alignment.center,
                    child: const Icon(Icons.person_outline, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.isLoggedIn
                              ? session.username ?? 'ユーザー名未設定'
                              : 'ゲストユーザー',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          session.email ?? '未ログイン',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: session.isLoggedIn
                        ? _signOut
                        : _signInWithGoogle,
                    icon: Icon(session.isLoggedIn ? Icons.logout : Icons.login),
                    label: Text(session.isLoggedIn ? 'ログアウト' : 'Googleでログイン'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.tune_outlined),
              title: const Text('レベル設定'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/setup'),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('学習済みの単語'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/mypage/learned'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _signInWithGoogle() async {
    try {
      if (!SupabaseAuthService.isConfigured) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SUPABASE_PUBLISHABLE_KEY が設定されていません')),
        );
        return;
      }
      final launched = await SupabaseAuthService.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: SupabaseAuthService.authRedirectUrl,
        queryParams: const {'prompt': 'select_account'},
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Googleログインを開けませんでした')));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Googleログインに失敗しました: $error')));
    }
  }

  Future<void> _signOut() async {
    if (SupabaseAuthService.isConfigured) {
      await SupabaseAuthService.auth.signOut();
    }
    await ref.read(appSessionProvider.notifier).signOut();
    if (mounted) {
      context.go('/login');
    }
  }
}
