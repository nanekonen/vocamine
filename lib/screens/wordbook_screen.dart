import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/words_provider.dart';
import '../utils/part_of_speech_label.dart';

class WordbookScreen extends ConsumerStatefulWidget {
  final String wordbookId;
  final String title;

  const WordbookScreen({
    super.key,
    required this.wordbookId,
    required this.title,
  });

  @override
  ConsumerState<WordbookScreen> createState() => _WordbookScreenState();
}

class _WordbookScreenState extends ConsumerState<WordbookScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      _loadWords();
    });
  }

  @override
  void didUpdateWidget(covariant WordbookScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.wordbookId != widget.wordbookId) {
      Future.microtask(_loadWords);
    }
  }

  void _loadWords() {
    bool? isLearned = false;
    String? sourceType;
    String? sourceMaterialId;
    String? sourceFolderId;

    switch (widget.wordbookId) {
      case 'unlearned_all':
        isLearned = false;
        break;
      case 'learned_all':
        isLearned = true;
        break;
      case 'initial_level':
        isLearned = true;
        sourceType = 'initial_level';
        break;
      default:
        if (widget.wordbookId.startsWith('material:')) {
          isLearned = false;
          sourceMaterialId = widget.wordbookId.substring('material:'.length);
        } else if (widget.wordbookId.startsWith('folder:')) {
          isLearned = false;
          sourceFolderId = widget.wordbookId.substring('folder:'.length);
        } else {
          isLearned = false;
        }
    }

    ref.read(wordsProvider.notifier).load(
      isLearned: isLearned,
      sourceType: sourceType,
      sourceMaterialId: sourceMaterialId,
      sourceFolderId: sourceFolderId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final wordsState = ref.watch(wordsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: '更新',
            icon: const Icon(Icons.refresh),
            onPressed: _loadWords,
          ),
        ],
      ),
      body: wordsState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('単語帳の取得に失敗しました: $error')),
        data: (words) {
          if (words.isEmpty) {
            return const Center(child: Text('単語がまだありません'));
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            itemCount: words.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final word = words[index];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              word.headword,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              word.meaningJa,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 8),
                            Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text(partOfSpeechLabel(word.partOfSpeech)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: () {
                          ref
                              .read(wordsProvider.notifier)
                              .toggleLearned(word.id);
                        },
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: const Text('覚えた'),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
