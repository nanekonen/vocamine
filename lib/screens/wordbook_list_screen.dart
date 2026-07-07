import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/word.dart';
import '../providers/material_library_provider.dart';
import '../providers/wordbook_library_provider.dart';
import '../providers/words_provider.dart';
import '../services/app_session.dart';
import '../utils/part_of_speech_label.dart';

class WordbookListScreen extends ConsumerStatefulWidget {
  final String? folderId;
  final String title;

  const WordbookListScreen({super.key, this.folderId, this.title = '単語帳'});

  @override
  ConsumerState<WordbookListScreen> createState() => _WordbookListScreenState();
}

class _WordbookListScreenState extends ConsumerState<WordbookListScreen> {
  bool get _isRoot => widget.folderId == null;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void didUpdateWidget(covariant WordbookListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.folderId != widget.folderId) {
      Future.microtask(_load);
    }
  }

  void _load() {
    ref.read(materialLibraryProvider.notifier).load();
    if (_isRoot) {
      ref.read(wordsProvider.notifier).load(isLearned: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(appSessionProvider, (previous, next) {
      if (previous?.userId != next.userId && next.isLoggedIn) {
        Future.microtask(_load);
      }
    });
    final library = ref.watch(wordbookLibraryProvider);
    final wordbooks = library.wordbooks
        .where((book) => book.folderId == widget.folderId)
        .toList();
    final wordsState = _isRoot
        ? ref.watch(wordsProvider)
        : const AsyncValue<List<Word>>.data([]);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: '更新',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _load(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_stories_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Text(
                  _isRoot ? '単語帳' : widget.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (_isRoot) ...[
              _UnlearnedWordsList(wordsState: wordsState),
              const SizedBox(height: 28),
              Text(
                '教材別',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
            ],
            if (wordbooks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  _isRoot ? '教材別の単語帳はまだありません' : 'このフォルダには教材がありません',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  ...wordbooks.map(
                    (book) => _WordbookTile(
                      icon: book.sourceFolderId != null
                          ? Icons.folder_outlined
                          : Icons.menu_book_outlined,
                      title: book.name,
                      subtitle: book.sourceFolderId != null ? '教材フォルダ' : '教材',
                      accentColor: book.sourceFolderId != null
                          ? const Color(0xFFC4934E)
                          : Theme.of(context).colorScheme.primary,
                      onTap: () {
                        if (book.sourceFolderId != null) {
                          context.push(
                            '/wordbook/folder',
                            extra: {
                              'folderId': book.sourceFolderId,
                              'title': book.name,
                            },
                          );
                          return;
                        }
                        context.push(
                          '/wordbook/detail',
                          extra: {'wordbookId': book.id, 'title': book.name},
                        );
                      },
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _UnlearnedWordsList extends ConsumerWidget {
  final AsyncValue<List<Word>> wordsState;

  const _UnlearnedWordsList({required this.wordsState});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return wordsState.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text('単語帳の取得に失敗しました: $error'),
      ),
      data: (words) {
        if (words.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              '未学習単語はまだありません',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        return Column(
          children: [
            for (final word in words)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _WordCard(word: word),
              ),
          ],
        );
      },
    );
  }
}

class _WordCard extends ConsumerWidget {
  final Word word;

  const _WordCard({required this.word});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                  Text(word.meaningJa),
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
                ref.read(wordsProvider.notifier).toggleLearned(word.id);
              },
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: const Text('覚えた'),
            ),
          ],
        ),
      ),
    );
  }
}

class _WordbookTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;
  final VoidCallback onTap;

  const _WordbookTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final tileWidth = width >= 1180
        ? 330.0
        : width >= 760
        ? 300.0
        : width - 48;
    return SizedBox(
      width: tileWidth,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.26),
                    ),
                  ),
                  child: Icon(icon, color: accentColor, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
