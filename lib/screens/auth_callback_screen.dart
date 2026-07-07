import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../services/app_session.dart';
import '../services/supabase_auth_service.dart';
import '../services/vocamine_api_client.dart';

class AuthCallbackScreen extends ConsumerStatefulWidget {
  final Uri callbackUri;

  const AuthCallbackScreen({super.key, required this.callbackUri});

  @override
  ConsumerState<AuthCallbackScreen> createState() => _AuthCallbackScreenState();
}

class _AuthCallbackScreenState extends ConsumerState<AuthCallbackScreen> {
  final _api = VocamineApiClient();
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_completeLogin);
  }

  Future<void> _completeLogin() async {
    try {
      final callbackParams = _callbackParams();
      final callbackError =
          callbackParams['error_description'] ?? callbackParams['error'];
      if (callbackError != null && callbackError.isNotEmpty) {
        throw Exception(callbackError);
      }
      if (!SupabaseAuthService.isConfigured) {
        throw Exception('SUPABASE_PUBLISHABLE_KEY が設定されていません');
      }
      var accessToken = SupabaseAuthService.auth.currentSession?.accessToken;
      if (accessToken == null || accessToken.isEmpty) {
        if (callbackParams.containsKey('code') ||
            callbackParams.containsKey('access_token')) {
          try {
            await SupabaseAuthService.auth.getSessionFromUrl(
              _effectiveCallbackUri(),
            );
          } catch (error) {
            accessToken = SupabaseAuthService.auth.currentSession?.accessToken;
            if (accessToken == null || accessToken.isEmpty) {
              final message = error.toString();
              if (message.contains('flow_state_not_found') ||
                  message.contains('invalid flow state')) {
                throw Exception('ログイン状態の確認に失敗しました。もう一度Googleログインを開始してください。');
              }
              rethrow;
            }
          }
          accessToken = SupabaseAuthService.auth.currentSession?.accessToken;
        }
      }
      if (accessToken == null || accessToken.isEmpty) {
        throw Exception(
          'Supabaseセッションを取得できませんでした\n'
          'callbackUri: ${widget.callbackUri}\n'
          'baseUri: ${Uri.base}\n'
          'params: ${callbackParams.keys.join(', ')}',
        );
      }
      final session = await _api.resolveAuthSession(accessToken: accessToken);
      await ref
          .read(appSessionProvider.notifier)
          .save(
            userId: session.userId,
            email: session.email,
            setupCompleted: session.setupCompleted,
          );
      if (!mounted) return;
      context.go(session.setupCompleted ? '/' : '/setup');
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  Map<String, String> _callbackParams() {
    final params = <String, String>{};
    for (final uri in [widget.callbackUri, Uri.base]) {
      params.addAll(uri.queryParameters);
      params.addAll(_paramsFromFragment(uri.fragment));
    }
    return params;
  }

  Map<String, String> _paramsFromFragment(String fragment) {
    if (fragment.isEmpty) return const {};
    final withoutRoute = fragment.startsWith('/auth/callback')
        ? fragment.substring('/auth/callback'.length)
        : fragment;
    final queryStart = withoutRoute.indexOf('?');
    final raw = queryStart >= 0
        ? withoutRoute.substring(queryStart + 1)
        : withoutRoute;
    if (raw.isEmpty) return const {};
    return Uri.splitQueryString(raw);
  }

  Uri _effectiveCallbackUri() {
    if (widget.callbackUri.hasQuery || widget.callbackUri.hasFragment) {
      return Uri.base.replace(
        path: widget.callbackUri.path,
        query: widget.callbackUri.query,
        fragment: widget.callbackUri.fragment,
      );
    }
    return Uri.base;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ログイン')),
      body: Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 36),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => context.go('/mypage'),
                      child: const Text('戻る'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
