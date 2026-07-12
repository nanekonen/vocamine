import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/lexical_analysis.dart';
import '../models/folder.dart';
import '../models/material_item.dart';
import '../services/app_session.dart';
import '../services/vocamine_api_client.dart';

class MaterialLibraryState {
  final List<AppFolder> folders;
  final List<MaterialItem> materials;
  final Map<String, AsyncValue<ExtractWordsResult>> analyses;
  final Set<String> movingMaterialIds;

  const MaterialLibraryState({
    required this.folders,
    required this.materials,
    this.analyses = const {},
    this.movingMaterialIds = const {},
  });

  MaterialLibraryState copyWith({
    List<AppFolder>? folders,
    List<MaterialItem>? materials,
    Map<String, AsyncValue<ExtractWordsResult>>? analyses,
    Set<String>? movingMaterialIds,
  }) {
    return MaterialLibraryState(
      folders: folders ?? this.folders,
      materials: materials ?? this.materials,
      analyses: analyses ?? this.analyses,
      movingMaterialIds: movingMaterialIds ?? this.movingMaterialIds,
    );
  }
}

class MaterialLibraryNotifier extends Notifier<MaterialLibraryState> {
  final _api = VocamineApiClient();
  bool _loaded = false;
  String? _loadedUserId;

  @override
  MaterialLibraryState build() {
    final session = ref.watch(appSessionProvider);
    if (_loadedUserId != null && _loadedUserId != session.userId) {
      _loaded = false;
      _loadedUserId = null;
      return const MaterialLibraryState(folders: [], materials: []);
    }
    return const MaterialLibraryState(folders: [], materials: []);
  }

  Future<void> load({bool force = false}) async {
    if (_loaded && !force) return;

    final userId = ref.read(appSessionProvider).userId;
    if (userId.isEmpty || userId == 'guest') return;

    if (_loadedUserId != null && _loadedUserId != userId) {
      _loaded = false;
      state = const MaterialLibraryState(folders: [], materials: []);
    }

    try {
      final library = await _api.fetchMaterialLibrary(userId: userId);

      state = state.copyWith(
        folders: library.folders,
        materials: library.materials,
      );

      _loadedUserId = userId;
      _loaded = true; // 成功したときだけtrue
      for (final material in library.materials) {
        if (material.ocrText.trim().isNotEmpty) {
          unawaited(analyzeMaterial(material.id));
        }
      }
    } catch (_) {
      _loaded = false; // 念のため明示
    }
  }

  Future<void> createFolder(String name, {String? parentId}) async {
    final userId = ref.read(appSessionProvider).userId;
    final folder = await _api.createMaterialFolder(
      userId: userId,
      name: name,
      parentId: parentId,
    );
    state = state.copyWith(folders: [...state.folders, folder]);
  }

  Future<void> renameFolder(String folderId, String name) async {
    final updated = await _api.updateMaterialFolder(
      userId: ref.read(appSessionProvider).userId,
      folderId: folderId,
      name: name,
    );
    _replaceFolder(updated);
  }

  Future<void> moveFolder(String folderId, String? parentId) async {
    final updated = await _api.updateMaterialFolder(
      userId: ref.read(appSessionProvider).userId,
      folderId: folderId,
      parentId: parentId,
      updateParent: true,
    );
    _replaceFolder(updated);
  }

  Future<void> deleteFolder(String folderId) async {
    await _api.deleteMaterialFolder(
      userId: ref.read(appSessionProvider).userId,
      folderId: folderId,
    );
    await load(force: true);
  }

  void _replaceFolder(AppFolder updated) {
    state = state.copyWith(
      folders: [
        for (final folder in state.folders)
          if (folder.id == updated.id) updated else folder,
      ],
    );
  }

  Future<String> addMaterial(
    String title,
    String ocrText, {
    Uint8List? sourceBytes,
    String? sourceMimeType,
    List<Uint8List> sourcePageImages = const [],
    List<SourceWordBox> sourceWordBoxes = const [],
    String? folderId,
    bool analyzeImmediately = false,
  }) async {
    final userId = ref.read(appSessionProvider).userId;
    final material = await _api.createMaterial(
      userId: userId,
      title: title,
      ocrText: ocrText,
      sourceBytes: sourceBytes,
      sourceMimeType: sourceMimeType,
      sourcePageImages: sourcePageImages,
      sourceWordBoxes: sourceWordBoxes,
      folderId: folderId,
    );
    state = state.copyWith(materials: [...state.materials, material]);
    if (analyzeImmediately) {
      unawaited(analyzeMaterial(material.id));
    }
    return material.id;
  }

  Future<void> analyzeMaterial(
    String materialId, {
    String? userId,
    bool force = false,
  }) async {
    final existing = state.analyses[materialId];
    if (!force && (existing is AsyncData || existing is AsyncLoading)) {
      return;
    }

    MaterialItem? material;
    for (final item in state.materials) {
      if (item.id == materialId) {
        material = item;
        break;
      }
    }
    if (material == null) {
      return;
    }
    final analysisText = _analysisTextForMaterial(material);
    if (analysisText.trim().isEmpty) {
      state = state.copyWith(
        analyses: {
          ...state.analyses,
          materialId: AsyncValue.error(
            Exception('解析できる英語テキストを取得できませんでした'),
            StackTrace.current,
          ),
        },
      );
      return;
    }

    state = state.copyWith(
      analyses: {...state.analyses, materialId: const AsyncValue.loading()},
    );

    try {
      final result = await _api.extractWords(
        text: analysisText,
        userId: userId ?? ref.read(appSessionProvider).userId,
        enrichMeanings: false,
        backgroundEnrichMeanings: true,
      );
      state = state.copyWith(
        analyses: {...state.analyses, materialId: AsyncValue.data(result)},
      );
    } catch (error, stackTrace) {
      state = state.copyWith(
        analyses: {
          ...state.analyses,
          materialId: AsyncValue.error(error, stackTrace),
        },
      );
    }
  }

  Future<void> deleteMaterial(String materialId) async {
    final userId = ref.read(appSessionProvider).userId;
    await _api.deleteMaterial(userId: userId, materialId: materialId);
    final analyses = {...state.analyses}..remove(materialId);
    state = state.copyWith(
      materials: state.materials
          .where((material) => material.id != materialId)
          .toList(),
      analyses: analyses,
    );
  }

  Future<void> renameMaterial(String materialId, String title) async {
    final updated = await _api.updateMaterial(
      userId: ref.read(appSessionProvider).userId,
      materialId: materialId,
      title: title,
    );
    _replaceMaterial(updated);
  }

  Future<void> moveMaterial(String materialId, String? folderId) async {
    final index = state.materials.indexWhere(
      (material) => material.id == materialId,
    );
    if (index < 0) return;
    final original = state.materials[index];
    final optimistic = original.copyWith(
      folderId: folderId,
      clearFolder: folderId == null,
    );
    state = state.copyWith(
      materials: [
        for (final material in state.materials)
          if (material.id == materialId) optimistic else material,
      ],
      movingMaterialIds: {...state.movingMaterialIds, materialId},
    );
    try {
      final updated = await _api.updateMaterial(
        userId: ref.read(appSessionProvider).userId,
        materialId: materialId,
        folderId: folderId,
        updateFolder: true,
      );
      _replaceMaterial(updated);
    } catch (_) {
      _replaceMaterial(original);
      rethrow;
    } finally {
      state = state.copyWith(
        movingMaterialIds: {...state.movingMaterialIds}..remove(materialId),
      );
    }
  }

  Future<void> appendPages(
    String materialId, {
    required String extractedText,
    required List<Uint8List> pageImages,
    required List<SourceWordBox> wordBoxes,
  }) async {
    final updated = await _api.appendMaterialPages(
      userId: ref.read(appSessionProvider).userId,
      materialId: materialId,
      extractedText: extractedText,
      pageImages: pageImages,
      wordBoxes: wordBoxes,
    );
    _replaceMaterial(updated);
    await analyzeMaterial(materialId, force: true);
  }

  void _replaceMaterial(MaterialItem updated) {
    state = state.copyWith(
      materials: [
        for (final material in state.materials)
          if (material.id == updated.id) updated else material,
      ],
    );
  }

  String _analysisTextForMaterial(MaterialItem material) {
    // 登録時にreadable PDF（画像の場合は登録時OCR）から確定して保存した本文だけを使う。
    // 詳細表示や一覧取得のたびにOCR・box再構築は行わない。
    return material.ocrText.trim();
  }
}

final materialLibraryProvider =
    NotifierProvider<MaterialLibraryNotifier, MaterialLibraryState>(
      MaterialLibraryNotifier.new,
    );
