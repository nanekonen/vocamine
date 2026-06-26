import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vocamine')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('英語学習をはじめよう', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => context.push('/reader'),
              icon: const Icon(Icons.upload_file),
              label: const Text('教材を読み込む'),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => context.push('/wordbook'),
              icon: const Icon(Icons.book),
              label: const Text('単語帳を見る'),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => context.push('/setup'),
              icon: const Icon(Icons.settings),
              label: const Text('レベル設定'),
            ),
          ],
        ),
      ),
    );
  }
}