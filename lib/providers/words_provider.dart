import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/word.dart';
import '../services/app_session.dart';
import '../services/vocamine_api_client.dart';

class WordsNotifier extends Notifier<AsyncValue<List<Word>>> {
  final _api = VocamineApiClient();
  bool? _lastIsLearned;
  String? _lastSourceType;
  String? _lastSourceMaterialId;
  String? _lastSourceFolderId;
  String? _loadedUserId;

  @override
  AsyncValue<List<Word>> build() {
    final session = ref.watch(appSessionProvider);
    if (_loadedUserId != null && _loadedUserId != session.userId) {
      _lastIsLearned = null;
      _lastSourceType = null;
      _lastSourceMaterialId = null;
      _lastSourceFolderId = null;
      _loadedUserId = null;
    }
    return const AsyncValue.data([]);
  }

  Future<void> load({
    bool? isLearned,
    String? sourceType,
    String? sourceMaterialId,
    String? sourceFolderId,
  }) async {
    _lastIsLearned = isLearned;
    _lastSourceType = sourceType;
    _lastSourceMaterialId = sourceMaterialId;
    _lastSourceFolderId = sourceFolderId;
    state = const AsyncValue.loading();
    try {
      final userId = ref.read(appSessionProvider).userId;
      final words = await _api.fetchWordbook(
        userId: userId,
        isLearned: isLearned,
        sourceType: sourceType,
        sourceMaterialId: sourceMaterialId,
        sourceFolderId: sourceFolderId,
      );
      _loadedUserId = userId;
      state = AsyncValue.data(words);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> reload() async {
    await load(
      isLearned: _lastIsLearned,
      sourceType: _lastSourceType,
      sourceMaterialId: _lastSourceMaterialId,
      sourceFolderId: _lastSourceFolderId,
    );
  }

  Future<void> toggleLearned(String wordId) async {
    final current = state.maybeWhen(
      data: (words) => words,
      orElse: () => <Word>[],
    );
    Word? target;
    for (final word in current) {
      if (word.id == wordId) {
        target = word;
        break;
      }
    }
    if (target == null) return;

    final nextLearned = !target.isLearned;
    state = AsyncValue.data([
      for (final word in current)
        if (word.id == wordId) word.copyWith(isLearned: nextLearned) else word,
    ]);

    try {
      await _api.updateWordbookEntry(entryId: wordId, isLearned: nextLearned);
      await reload();
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }
}

final wordsProvider = NotifierProvider<WordsNotifier, AsyncValue<List<Word>>>(
  WordsNotifier.new,
);

class LearnedWordsNotifier extends Notifier<AsyncValue<List<Word>>> {
  final _api = VocamineApiClient();
  String? _loadedUserId;

  @override
  AsyncValue<List<Word>> build() {
    final session = ref.watch(appSessionProvider);
    if (_loadedUserId != null && _loadedUserId != session.userId) {
      _loadedUserId = null;
    }
    return const AsyncValue.data([]);
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final userId = ref.read(appSessionProvider).userId;
      final words = await _api.fetchWordbook(
        userId: userId,
        isLearned: true,
      );
      _loadedUserId = userId;
      state = AsyncValue.data(words);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }
}

final learnedWordsProvider =
    NotifierProvider<LearnedWordsNotifier, AsyncValue<List<Word>>>(
      LearnedWordsNotifier.new,
    );
