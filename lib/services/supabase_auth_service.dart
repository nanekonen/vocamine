import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseAuthService {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://qkmwthzihgvcbxdqvvay.supabase.co',
  );
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  static bool get isConfigured => supabasePublishableKey.trim().isNotEmpty;

  static String get authRedirectUrl => kIsWeb
      ? '${Uri.base.origin}/auth/callback'
      : 'com.example.vacamine://login-callback/';

  static Future<void> initialize() async {
    if (!isConfigured) return;
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabasePublishableKey,
      authOptions: FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        detectSessionInUri: kIsWeb,
      ),
    );
  }

  static GoTrueClient get auth => Supabase.instance.client.auth;
}
