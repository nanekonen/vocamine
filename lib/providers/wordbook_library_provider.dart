import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/folder.dart';
import '../models/wordbook.dart';

class WordbookLibraryState {
  final List<AppFolder> folders;
  final List<Wordbook> wordbooks;

  const WordbookLibraryState({
    required this.folders,
    required this.wordbooks,
  });
}

class WordbookLibraryNotifier extends Notifier<WordbookLibraryState> {
  int _folderSeq = 0;
  int _bookSeq = 0;

  @override
  WordbookLibraryState build() {
    // ダミーデータ：デフォルトの単語帳を1つ用意
    return const WordbookLibraryState(
      folders: [],
      wordbooks: [
        Wordbook(id: 'default', name: '未学習単語帳'),
      ],
    );
  }

  void createFolder(String name, {String? parentId}) {
    _folderSeq++;
    final folder = AppFolder(id: 'wf_$_folderSeq', name: name, parentId: parentId);
    state = WordbookLibraryState(
      folders: [...state.folders, folder],
      wordbooks: state.wordbooks,
    );
  }

  void createWordbook(String name, {String? folderId}) {
    _bookSeq++;
    final book = Wordbook(id: 'wb_$_bookSeq', name: name, folderId: folderId);
    state = WordbookLibraryState(
      folders: state.folders,
      wordbooks: [...state.wordbooks, book],
    );
  }
}

final wordbookLibraryProvider =
    NotifierProvider<WordbookLibraryNotifier, WordbookLibraryState>(
  WordbookLibraryNotifier.new,
);