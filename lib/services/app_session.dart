import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSession {
  final String userId;
  final String? email;
  final bool isLoaded;
  final bool setupCompleted;

  const AppSession({
    required this.userId,
    this.email,
    this.isLoaded = false,
    this.setupCompleted = false,
  });

  bool get isLoggedIn => isLoaded && userId != 'guest';
}

class AppSessionNotifier extends Notifier<AppSession> {
  static const _userIdKey = 'user_id';
  static const _emailKey = 'email';
  static const _setupCompletedKey = 'setup_completed';

  @override
  AppSession build() {
    return const AppSession(userId: 'guest');
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    state = AppSession(
      userId: prefs.getString(_userIdKey) ?? 'guest',
      email: prefs.getString(_emailKey),
      isLoaded: true,
      setupCompleted: prefs.getBool(_setupCompletedKey) ?? false,
    );
  }

  Future<void> save({
    required String userId,
    required String? email,
    required bool setupCompleted,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userIdKey, userId);
    await prefs.setBool(_setupCompletedKey, setupCompleted);
    if (email == null || email.isEmpty) {
      await prefs.remove(_emailKey);
    } else {
      await prefs.setString(_emailKey, email);
    }
    state = AppSession(
      userId: userId,
      email: email,
      isLoaded: true,
      setupCompleted: setupCompleted,
    );
  }

  Future<void> markSetupCompleted() async {
    if (!state.isLoggedIn) return;
    await save(userId: state.userId, email: state.email, setupCompleted: true);
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userIdKey);
    await prefs.remove(_emailKey);
    await prefs.remove(_setupCompletedKey);
    state = const AppSession(userId: 'guest', isLoaded: true);
  }
}

final appSessionProvider = NotifierProvider<AppSessionNotifier, AppSession>(
  AppSessionNotifier.new,
);
