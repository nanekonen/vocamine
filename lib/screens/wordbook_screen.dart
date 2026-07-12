import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/word.dart';
import '../models/word_lookup.dart';
import '../providers/words_provider.dart';
import '../services/app_session.dart';
import '../services/vocamine_api_client.dart';
import '../utils/part_of_speech_label.dart';
import 'word_study_screen.dart';

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
  String _query = '';
  String? _partOfSpeechFilter;

  Future<void> _startStudy(List<Word> words, WordStudyMode mode) async {
    if (words.isEmpty) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => WordStudyScreen(words: words, mode: mode),
      ),
    );
    if (changed == true) _loadWords();
  }

  String? get _independentWordbookId {
    const specialIds = {
      'unlearned_all',
      'learned_all',
      'initial_level',
      'deleted_materials',
    };
    if (specialIds.contains(widget.wordbookId) ||
        widget.wordbookId.startsWith('material:') ||
        widget.wordbookId.startsWith('folder:')) {
      return null;
    }
    return widget.wordbookId;
  }

  Future<void> _showManualAddDialog() async {
    final added = await showDialog<bool>(
      context: context,
      builder: (_) => _ManualWordAddDialog(
        userId: ref.read(appSessionProvider).userId,
        wordbookId: _independentWordbookId,
      ),
    );
    if (added == true) _loadWords();
  }

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
    String? independentWordbookId;

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
      case 'deleted_materials':
        isLearned = false;
        sourceType = 'deleted_material';
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
          independentWordbookId = widget.wordbookId;
        }
    }

    ref
        .read(wordsProvider.notifier)
        .load(
          isLearned: isLearned,
          sourceType: sourceType,
          sourceMaterialId: sourceMaterialId,
          sourceFolderId: sourceFolderId,
          wordbookId: independentWordbookId,
        );
  }

  @override
  Widget build(BuildContext context) {
    final wordsState = ref.watch(wordsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          PopupMenuButton<WordStudyMode>(
            tooltip: '学習モード',
            onSelected: (mode) {
              final words = ref.read(wordsProvider).value ?? const <Word>[];
              _startStudy(words, mode);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: WordStudyMode.flashcards,
                child: Text('フラッシュカード'),
              ),
              PopupMenuItem(value: WordStudyMode.quiz, child: Text('4択問題')),
              PopupMenuItem(value: WordStudyMode.test, child: Text('テスト')),
            ],
            icon: const Icon(Icons.school),
          ),
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
          final partOfSpeechValues =
              words
                  .map((word) => word.partOfSpeech)
                  .where((value) => value.isNotEmpty)
                  .toSet()
                  .toList()
                ..sort();
          final filtered = words.where((word) {
            final query = _query.trim().toLowerCase();
            final matchesQuery =
                query.isEmpty ||
                word.headword.toLowerCase().contains(query) ||
                word.meaningJa.toLowerCase().contains(query);
            return matchesQuery &&
                (_partOfSpeechFilter == null ||
                    word.partOfSpeech == _partOfSpeechFilter);
          }).toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: '単語・意味を検索',
                        ),
                        onChanged: (value) => setState(() => _query = value),
                      ),
                    ),
                    const SizedBox(width: 12),
                    DropdownButton<String?>(
                      value: _partOfSpeechFilter,
                      hint: const Text('すべての品詞'),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('すべての品詞'),
                        ),
                        for (final value in partOfSpeechValues)
                          DropdownMenuItem<String?>(
                            value: value,
                            child: Text(partOfSpeechLabel(value)),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _partOfSpeechFilter = value),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    Text('${filtered.length}語'),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: filtered.isEmpty
                          ? null
                          : () =>
                                _startStudy(filtered, WordStudyMode.flashcards),
                      icon: const Icon(Icons.style),
                      label: const Text('カード'),
                    ),
                    TextButton.icon(
                      onPressed: filtered.isEmpty
                          ? null
                          : () => _startStudy(filtered, WordStudyMode.quiz),
                      icon: const Icon(Icons.quiz),
                      label: const Text('4択'),
                    ),
                    FilledButton.icon(
                      onPressed: filtered.isEmpty
                          ? null
                          : () => _startStudy(filtered, WordStudyMode.test),
                      icon: const Icon(Icons.fact_check),
                      label: const Text('テスト'),
                    ),
                  ],
                ),
              ),
              if (filtered.isEmpty)
                const Expanded(child: Center(child: Text('条件に一致する単語がありません')))
              else
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 100),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final word = filtered[index];
                      return Card(
                        clipBehavior: Clip.antiAlias,
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
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    if (word.ipa?.trim().isNotEmpty == true)
                                      Text(
                                        word.ipa!,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    const SizedBox(height: 8),
                                    Text(
                                      word.meaningJa,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium,
                                    ),
                                    const SizedBox(height: 8),
                                    Chip(
                                      visualDensity: VisualDensity.compact,
                                      label: Text(
                                        partOfSpeechLabel(word.partOfSpeech),
                                      ),
                                    ),
                                    if (word.dictionarySource.isNotEmpty)
                                      Text(
                                        '出典: ${dictionarySourceLabel(word.dictionarySource)}',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelSmall,
                                      ),
                                    if (word.examples.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        word.examples.first.sentence,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: '詳細',
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        WordDetailScreen(word: word),
                                  ),
                                ),
                                icon: const Icon(Icons.chevron_right),
                              ),
                              const SizedBox(width: 12),
                              OutlinedButton.icon(
                                onPressed: () {
                                  ref
                                      .read(wordsProvider.notifier)
                                      .toggleLearned(word.id);
                                },
                                icon: const Icon(
                                  Icons.check_circle_outline,
                                  size: 18,
                                ),
                                label: const Text('覚えた'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showManualAddDialog,
        icon: const Icon(Icons.add),
        label: const Text('単語を追加'),
      ),
    );
  }
}

class _ManualWordAddDialog extends StatefulWidget {
  final String userId;
  final String? wordbookId;

  const _ManualWordAddDialog({required this.userId, this.wordbookId});

  @override
  State<_ManualWordAddDialog> createState() => _ManualWordAddDialogState();
}

class _ManualWordAddDialogState extends State<_ManualWordAddDialog> {
  final _wordController = TextEditingController();
  final _api = VocamineApiClient();
  String _partOfSpeech = 'noun';
  WordLookupResult? _result;
  bool _searching = false;
  int? _addingMeaningId;
  String? _error;

  static const _partsOfSpeech = [
    'noun',
    'verb',
    'adjective',
    'adverb',
    'preposition',
    'conjunction',
    'pronoun',
    'determiner',
    'article',
    'auxiliary',
    'phrase',
  ];

  @override
  void dispose() {
    _wordController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final word = _wordController.text.trim();
    if (word.isEmpty || _searching) return;
    setState(() {
      _searching = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await _api.lookupWord(
        word: word,
        partOfSpeech: _partOfSpeech,
      );
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted) setState(() => _error = '意味の検索に失敗しました: $error');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _add(MeaningInfo meaning) async {
    if (_addingMeaningId != null) return;
    setState(() {
      _addingMeaningId = meaning.id;
      _error = null;
    });
    try {
      await _api.addMeaningToWordbook(
        userId: widget.userId,
        meaningId: meaning.id,
        sourceType: 'manual',
        sourceLabel: '手動追加',
        wordbookId: widget.wordbookId,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = '単語帳への追加に失敗しました: $error');
    } finally {
      if (mounted) setState(() => _addingMeaningId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final meanings =
        _result?.meanings
            .where((meaning) => meaning.partOfSpeech == _partOfSpeech)
            .toList() ??
        const <MeaningInfo>[];
    return AlertDialog(
      title: const Text('単語を手動追加'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _wordController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                decoration: const InputDecoration(
                  labelText: '英単語・熟語',
                  hintText: '例: accomplish',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _partOfSpeech,
                decoration: const InputDecoration(labelText: '品詞'),
                items: [
                  for (final value in _partsOfSpeech)
                    DropdownMenuItem(
                      value: value,
                      child: Text(partOfSpeechLabel(value)),
                    ),
                ],
                onChanged: _searching
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _partOfSpeech = value);
                        }
                      },
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _searching ? null : _search,
                icon: _searching
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                label: Text(_searching ? '検索中…' : '意味を検索'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (_result != null && meanings.isEmpty) ...[
                const SizedBox(height: 16),
                const Text('選択した品詞の意味が見つかりませんでした'),
              ],
              for (final meaning in meanings) ...[
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    title: Text(
                      meaning.definitionJa?.trim().isNotEmpty == true
                          ? meaning.definitionJa!
                          : meaning.definitionEn ?? '意味なし',
                    ),
                    subtitle: meaning.definitionEn?.trim().isNotEmpty == true
                        ? Text(meaning.definitionEn!)
                        : null,
                    trailing: _addingMeaningId == meaning.id
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            tooltip: 'この意味を追加',
                            onPressed: _addingMeaningId == null
                                ? () => _add(meaning)
                                : null,
                            icon: const Icon(Icons.add_circle),
                          ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _addingMeaningId == null
              ? () => Navigator.of(context).pop(false)
              : null,
          child: const Text('閉じる'),
        ),
      ],
    );
  }
}
