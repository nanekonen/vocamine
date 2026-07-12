import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/folder.dart';
import '../models/wordbook.dart';
import '../services/app_session.dart';
import '../services/vocamine_api_client.dart';

class WordbookLibraryState {
  final List<AppFolder> folders;
  final List<Wordbook> wordbooks;
  final bool isLoading;

  const WordbookLibraryState({
    this.folders = const [],
    this.wordbooks = const [],
    this.isLoading = false,
  });

  WordbookLibraryState copyWith({
    List<AppFolder>? folders,
    List<Wordbook>? wordbooks,
    bool? isLoading,
  }) => WordbookLibraryState(
    folders: folders ?? this.folders,
    wordbooks: wordbooks ?? this.wordbooks,
    isLoading: isLoading ?? this.isLoading,
  );
}

class WordbookLibraryNotifier extends Notifier<WordbookLibraryState> {
  final _api = VocamineApiClient();
  String? _loadedUserId;

  @override
  WordbookLibraryState build() => const WordbookLibraryState();

  Future<void> load({bool force = false}) async {
    final userId = ref.read(appSessionProvider).userId;
    if (!force && _loadedUserId == userId) return;
    state = state.copyWith(isLoading: true);
    try {
      final result = await _api.fetchIndependentWordbooks(userId: userId);
      state = WordbookLibraryState(
        folders: result.folders,
        wordbooks: result.wordbooks,
      );
      _loadedUserId = userId;
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<Wordbook> createWordbook(String name, {String? folderId}) async {
    final book = await _api.createIndependentWordbook(
      userId: ref.read(appSessionProvider).userId,
      name: name,
      folderId: folderId,
    );
    state = state.copyWith(wordbooks: [...state.wordbooks, book]);
    return book;
  }

  Future<void> renameWordbook(String id, String name) async {
    await _api.updateIndependentWordbook(
      userId: ref.read(appSessionProvider).userId,
      wordbookId: id,
      name: name,
    );
    await load();
  }

  Future<void> moveWordbook(String id, String? folderId) async {
    await _api.updateIndependentWordbook(
      userId: ref.read(appSessionProvider).userId,
      wordbookId: id,
      folderId: folderId,
      updateFolder: true,
    );
    await load();
  }

  Future<void> deleteWordbook(String id) async {
    await _api.deleteIndependentWordbook(
      userId: ref.read(appSessionProvider).userId,
      wordbookId: id,
    );
    state = state.copyWith(
      wordbooks: state.wordbooks.where((book) => book.id != id).toList(),
    );
  }

  Future<void> createFolder(String name, {String? parentId}) async {
    final folder = await _api.createIndependentWordbookFolder(
      userId: ref.read(appSessionProvider).userId,
      name: name,
      parentId: parentId,
    );
    state = state.copyWith(folders: [...state.folders, folder]);
  }

  Future<void> renameFolder(String id, String name) async {
    await _api.updateIndependentWordbookFolder(
      userId: ref.read(appSessionProvider).userId,
      folderId: id,
      name: name,
    );
    await load();
  }

  Future<void> moveFolder(String id, String? parentId) async {
    await _api.updateIndependentWordbookFolder(
      userId: ref.read(appSessionProvider).userId,
      folderId: id,
      parentId: parentId,
      updateParent: true,
    );
    await load();
  }

  Future<void> deleteFolder(String id) async {
    await _api.deleteIndependentWordbookFolder(
      userId: ref.read(appSessionProvider).userId,
      folderId: id,
    );
    await load();
  }
}

final wordbookLibraryProvider =
    NotifierProvider<WordbookLibraryNotifier, WordbookLibraryState>(
      WordbookLibraryNotifier.new,
    );
