import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/folder.dart';
import '../models/wordbook.dart';
import 'material_library_provider.dart';

class WordbookLibraryState {
  final List<AppFolder> folders;
  final List<Wordbook> wordbooks;

  const WordbookLibraryState({
    required this.folders,
    required this.wordbooks,
  });
}

class WordbookLibraryNotifier extends Notifier<WordbookLibraryState> {
  @override
  WordbookLibraryState build() {
    final materialLibrary = ref.watch(materialLibraryProvider);
    return WordbookLibraryState(
      folders: materialLibrary.folders,
      wordbooks: [
        ...materialLibrary.folders.map(
          (folder) => Wordbook(
            id: 'folder:${folder.id}',
            name: folder.name,
            folderId: folder.parentId,
            sourceFolderId: folder.id,
          ),
        ),
        ...materialLibrary.materials.map(
          (material) => Wordbook(
            id: 'material:${material.id}',
            name: material.title,
            folderId: material.folderId,
            isLearned: false,
            sourceMaterialId: material.id,
          ),
        ),
      ],
    );
  }

  void createFolder(String name, {String? parentId}) {}

  void createWordbook(String name, {String? folderId}) {}
}

final wordbookLibraryProvider =
    NotifierProvider<WordbookLibraryNotifier, WordbookLibraryState>(
  WordbookLibraryNotifier.new,
);
