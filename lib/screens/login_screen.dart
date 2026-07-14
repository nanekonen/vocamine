import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/app_session.dart';
import '../services/supabase_auth_service.dart';
import '../services/vocamine_api_client.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _api = VocamineApiClient();
  bool _isLoading = false;
  bool _isSignUp = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _completeLogin(String accessToken) async {
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
    if (!mounted) return;
    context.go(session.setupCompleted ? '/' : '/setup');
  }

  Future<void> _submitEmail() async {
    if (_isLoading || !_formKey.currentState!.validate()) return;
    if (!SupabaseAuthService.isConfigured) {
      _showMessage('SUPABASE_PUBLISHABLE_KEY が設定されていません');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      if (_isSignUp) {
        final response = await SupabaseAuthService.auth.signUp(
          email: email,
          password: password,
          data: {'display_name': _usernameController.text.trim()},
          emailRedirectTo: '${Uri.base.origin}/auth/callback',
        );
        final accessToken = response.session?.accessToken;
        if (accessToken == null || accessToken.isEmpty) {
          if (!mounted) return;
          _showMessage('確認メールを送信しました。メール内のリンクを開いて登録を完了してください。');
          setState(() => _isSignUp = false);
          return;
        }
        await _completeLogin(accessToken);
      } else {
        final response = await SupabaseAuthService.auth.signInWithPassword(
          email: email,
          password: password,
        );
        final accessToken = response.session?.accessToken;
        if (accessToken == null || accessToken.isEmpty) {
          throw Exception('ログインセッションを取得できませんでした');
        }
        await _completeLogin(accessToken);
      }
    } on AuthException catch (error) {
      if (!mounted) return;
      _showMessage(_authErrorMessage(error));
    } catch (error) {
      if (!mounted) return;
      _showMessage('${_isSignUp ? '登録' : 'ログイン'}に失敗しました: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_isLoading) return;
    if (!SupabaseAuthService.isConfigured) {
      _showMessage('SUPABASE_PUBLISHABLE_KEY が設定されていません');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final launched = await SupabaseAuthService.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: '${Uri.base.origin}/auth/callback',
        queryParams: const {'prompt': 'select_account'},
      );
      if (!launched && mounted) {
        _showMessage('Googleログインを開けませんでした');
      }
    } catch (error) {
      if (mounted) _showMessage('Googleログインに失敗しました: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _authErrorMessage(AuthException error) {
    final message = error.message.toLowerCase();
    if (message.contains('invalid login credentials')) {
      return 'メールアドレスまたはパスワードが正しくありません';
    }
    if (message.contains('email not confirmed')) {
      return 'メールアドレスの確認が完了していません';
    }
    if (message.contains('user already registered')) {
      return 'このメールアドレスはすでに登録されています';
    }
    if (message.contains('password')) {
      return 'パスワードは6文字以上で入力してください';
    }
    return error.message;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF7F9FB), Color(0xFFE8EEF4)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Glossalyze',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 32),
                        Text(
                          _isSignUp ? 'アカウントを作成' : 'ログインして始める',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 24),
                        if (_isSignUp) ...[
                          TextFormField(
                            controller: _usernameController,
                            enabled: !_isLoading,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'ユーザー名',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            validator: (value) {
                              if (!_isSignUp) return null;
                              if ((value ?? '').trim().isEmpty) {
                                return 'ユーザー名を入力してください';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                        ],
                        TextFormField(
                          controller: _emailController,
                          enabled: !_isLoading,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'メールアドレス',
                            prefixIcon: Icon(Icons.mail_outline),
                          ),
                          validator: (value) {
                            final email = value?.trim() ?? '';
                            if (email.isEmpty || !email.contains('@')) {
                              return '有効なメールアドレスを入力してください';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _passwordController,
                          enabled: !_isLoading,
                          obscureText: _obscurePassword,
                          autofillHints: [
                            _isSignUp
                                ? AutofillHints.newPassword
                                : AutofillHints.password,
                          ],
                          onFieldSubmitted: (_) => _submitEmail(),
                          decoration: InputDecoration(
                            labelText: 'パスワード',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip: _obscurePassword
                                  ? 'パスワードを表示'
                                  : 'パスワードを隠す',
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (value) {
                            if ((value ?? '').length < 6) {
                              return '6文字以上で入力してください';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _isLoading ? null : _submitEmail,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: _isLoading
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(_isSignUp ? 'メールアドレスで登録' : 'ログイン'),
                          ),
                        ),
                        TextButton(
                          onPressed: _isLoading
                              ? null
                              : () => setState(() => _isSignUp = !_isSignUp),
                          child: Text(
                            _isSignUp ? 'アカウントをお持ちの方はログイン' : 'メールアドレスで新規登録',
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Row(
                          children: [
                            Expanded(child: Divider()),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Text('または'),
                            ),
                            Expanded(child: Divider()),
                          ],
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _isLoading ? null : _signInWithGoogle,
                          icon: const Icon(Icons.login),
                          label: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text('Googleでログイン'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
