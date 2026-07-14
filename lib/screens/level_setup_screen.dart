import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../services/app_session.dart';
import '../services/app_messenger.dart';
import '../services/vocamine_api_client.dart';

class SelectedLevelNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? level) => state = level;
}

final selectedLevelProvider = NotifierProvider<SelectedLevelNotifier, String?>(
  SelectedLevelNotifier.new,
);

class LevelSetupScreen extends ConsumerStatefulWidget {
  const LevelSetupScreen({super.key});

  static const levels = [
    '中学卒業程度',
    '高校卒業程度',
    '英検3級',
    '英検準2級',
    '英検2級',
    '英検準1級',
    '英検1級',
    'TOEIC 400点',
    'TOEIC 600点',
    'TOEIC 730点',
    'TOEIC 860点',
    'TOEIC 990点',
  ];

  @override
  ConsumerState<LevelSetupScreen> createState() => _LevelSetupScreenState();
}

class _LevelSetupScreenState extends ConsumerState<LevelSetupScreen> {
  final _api = VocamineApiClient();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadCurrentLevel);
  }

  Future<void> _loadCurrentLevel() async {
    final session = ref.read(appSessionProvider);
    var level = session.level;
    if (level == null && session.isLoggedIn && session.setupCompleted) {
      try {
        level = await _api.fetchUserLevel(userId: session.userId);
      } catch (_) {
        return;
      }
    }
    if (level != null) {
      ref.read(selectedLevelProvider.notifier).select(level);
    }
  }

  Future<void> _saveLevel(String level) async {
    setState(() => _isSaving = true);
    try {
      await _api.setupLevel(
        userId: ref.read(appSessionProvider).userId,
        level: level,
        username: ref.read(appSessionProvider).username ?? 'User',
      );
      if (!mounted) return;
      await ref
          .read(appSessionProvider.notifier)
          .markSetupCompleted(level: level);
      if (!mounted) return;
      context.go('/');
      AppMessenger.show('あなたのレベルに合わせて単語登録中');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('レベル設定に失敗しました: $error')));
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(selectedLevelProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('レベル設定')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        children: [
          Text(
            '現在の英語レベルを選択してください',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          ...LevelSetupScreen.levels.map((level) {
            final isSelected = selected == level;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                color: isSelected ? const Color(0xFFD4E3FF) : Colors.white,
                child: ListTile(
                  leading: Icon(
                    isSelected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  title: Text(level),
                  selected: isSelected,
                  onTap: () =>
                      ref.read(selectedLevelProvider.notifier).select(level),
                ),
              ),
            );
          }),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: selected == null
                ? null
                : _isSaving
                ? null
                : () => _saveLevel(selected),
            child: _isSaving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('このレベルで始める'),
          ),
        ],
      ),
    );
  }
}
