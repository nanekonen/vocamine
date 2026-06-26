import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SelectedLevelNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? level) => state = level;
}

final selectedLevelProvider = NotifierProvider<SelectedLevelNotifier, String?>(
  SelectedLevelNotifier.new,
);

class LevelSetupScreen extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedLevelProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('レベル設定')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('現在の英語レベルを選択してください', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 16),
          ...levels.map((level) => RadioListTile<String>(
            title: Text(level),
            value: level,
            groupValue: selected,
            onChanged: (val) => ref.read(selectedLevelProvider.notifier).select(val),
          )),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: selected == null ? null : () {
              // TODO: レベルに応じた単語を学習済み単語帳に一括登録
              Navigator.pop(context);
            },
            child: const Text('このレベルで始める'),
          ),
        ],
      ),
    );
  }
}