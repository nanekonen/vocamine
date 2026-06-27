import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/words_provider.dart';

class MyPageScreen extends ConsumerWidget {
  const MyPageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final learnedWords = ref.watch(wordsProvider).where((w) => w.isLearned).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('マイページ')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ユーザー情報（ダミー）
          const Row(
            children: [
              CircleAvatar(radius: 28, child: Icon(Icons.person, size: 28)),
              SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ゲストユーザー', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text('未ログイン', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              // TODO: Googleログイン処理
            },
            icon: const Icon(Icons.login),
            label: const Text('Googleでログイン'),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('レベル設定'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/setup'),
          ),
          const Divider(height: 32),

          // 学習済み単語
          Text('学習済みの単語 (${learnedWords.length})',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (learnedWords.isEmpty)
            const Text('まだ学習済みの単語はありません')
          else
            ...learnedWords.map((w) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.check_circle, color: Colors.green, size: 20),
                  title: Text(w.headword),
                  subtitle: Text(w.meaningJa),
                )),
        ],
      ),
    );
  }
}