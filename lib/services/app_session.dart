import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSession {
  final String userId;
  final String? email;
  final String? username;
  final String? level;
  final bool isLoaded;
  final bool setupCompleted;

  const AppSession({
    required this.userId,
    this.email,
    this.username,
    this.level,
    this.isLoaded = false,
    this.setupCompleted = false,
  });

  bool get isLoggedIn => isLoaded && userId != 'guest';
}

class AppSessionNotifier extends Notifier<AppSession> {
  static const _userIdKey = 'user_id';
  static const _emailKey = 'email';
  static const _usernameKey = 'username';
  static const _levelKey = 'level';
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
      username: prefs.getString(_usernameKey),
      level: prefs.getString(_levelKey),
      isLoaded: true,
      setupCompleted: prefs.getBool(_setupCompletedKey) ?? false,
    );
  }

  Future<void> save({
    required String userId,
    required String? email,
    required bool setupCompleted,
    String? username,
    String? level,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userIdKey, userId);
    await prefs.setBool(_setupCompletedKey, setupCompleted);
    if (username?.trim().isNotEmpty == true) {
      await prefs.setString(_usernameKey, username!.trim());
    }
    if (level?.trim().isNotEmpty == true) {
      await prefs.setString(_levelKey, level!.trim());
    }
    if (email == null || email.isEmpty) {
      await prefs.remove(_emailKey);
    } else {
      await prefs.setString(_emailKey, email);
    }
    final next = AppSession(
      userId: userId,
      email: email,
      username: username ?? state.username,
      level: level ?? state.level,
      isLoaded: true,
      setupCompleted: setupCompleted,
    );
    final unchanged =
        state.userId == next.userId &&
        state.email == next.email &&
        state.username == next.username &&
        state.level == next.level &&
        state.isLoaded == next.isLoaded &&
        state.setupCompleted == next.setupCompleted;
    if (!unchanged) state = next;
  }

  Future<void> markSetupCompleted({String? level}) async {
    if (!state.isLoggedIn) return;
    await save(
      userId: state.userId,
      email: state.email,
      username: state.username,
      level: level ?? state.level,
      setupCompleted: true,
    );
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userIdKey);
    await prefs.remove(_emailKey);
    await prefs.remove(_usernameKey);
    await prefs.remove(_levelKey);
    await prefs.remove(_setupCompletedKey);
    state = const AppSession(userId: 'guest', isLoaded: true);
  }
}

final appSessionProvider = NotifierProvider<AppSessionNotifier, AppSession>(
  AppSessionNotifier.new,
);
