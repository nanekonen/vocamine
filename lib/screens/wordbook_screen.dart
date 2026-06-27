import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/words_provider.dart';

class WordbookScreen extends ConsumerWidget {
  final String wordbookId;
  final String title;

  const WordbookScreen({super.key, required this.wordbookId, required this.title});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = ref
        .watch(wordsProvider)
        .where((w) => w.wordbookId == wordbookId && !w.isLearned)
        .toList();

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: words.isEmpty
          ? const Center(child: Text('単語がまだありません'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: words.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, index) {
                final word = words[index];
                return ListTile(
                  title: Text(word.headword, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${word.meaningJa}　(${word.partOfSpeech})'),
                  trailing: OutlinedButton(
                    onPressed: () {
                      ref.read(wordsProvider.notifier).toggleLearned(word.id);
                    },
                    child: const Text('覚えた'),
                  ),
                );
              },
            ),
    );
  }
}