import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/folder.dart';
import '../models/material_item.dart';

class MaterialLibraryState {
  final List<AppFolder> folders;
  final List<MaterialItem> materials;

  const MaterialLibraryState({
    required this.folders,
    required this.materials,
  });
}

class MaterialLibraryNotifier extends Notifier<MaterialLibraryState> {
  int _folderSeq = 0;
  int _matSeq = 0;

  @override
  MaterialLibraryState build() {
    return const MaterialLibraryState(folders: [], materials: []);
  }

  void createFolder(String name, {String? parentId}) {
    _folderSeq++;
    final folder = AppFolder(id: 'mf_$_folderSeq', name: name, parentId: parentId);
    state = MaterialLibraryState(
      folders: [...state.folders, folder],
      materials: state.materials,
    );
  }

  void addMaterial(String title, String ocrText, {String? folderId}) {
    _matSeq++;
    final material = MaterialItem(
      id: 'mat_$_matSeq',
      title: title,
      ocrText: ocrText,
      folderId: folderId,
      createdAt: DateTime.now(),
    );
    state = MaterialLibraryState(
      folders: state.folders,
      materials: [...state.materials, material],
    );
  }
}

final materialLibraryProvider =
    NotifierProvider<MaterialLibraryNotifier, MaterialLibraryState>(
  MaterialLibraryNotifier.new,
);