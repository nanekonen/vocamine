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
  bool _analysisBackfillAttempted = false;

  @override
  MaterialLibraryState build() {
    ref.listen<AppSession>(appSessionProvider, (previous, next) {
      if (previous == null || previous.userId == next.userId) return;
      _loaded = false;
      _loadedUserId = null;
      _analysisBackfillAttempted = false;
      state = const MaterialLibraryState(folders: [], materials: []);
      if (next.isLoggedIn) unawaited(load());
    });
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
      var library = await _api.fetchMaterialLibrary(userId: userId);
      if (!_analysisBackfillAttempted &&
          library.materials.any(
            (material) => material.analysisCoverageRate == null,
          )) {
        _analysisBackfillAttempted = true;
        try {
          await _api.refreshMaterialAnalyses(userId: userId);
          library = await _api.fetchMaterialLibrary(userId: userId);
        } catch (_) {
          // DBマイグレーション適用前でも教材一覧自体は表示する。
        }
      }

      state = state.copyWith(
        folders: library.folders,
        materials: library.materials,
      );

      _loadedUserId = userId;
      _loaded = true; // 成功したときだけtrue
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
    // 読み込み中カードと同じ末尾位置へ完成した教材を追加する。
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

    // 既に解析結果を表示できている場合、強制再解析中もその結果を残す。
    // 「知っている」などの操作後に右側の意味一覧全体がローディングへ
    // 切り替わるのを防ぎ、完了した結果だけを差し替える。
    if (existing is! AsyncData<ExtractWordsResult>) {
      state = state.copyWith(
        analyses: {...state.analyses, materialId: const AsyncValue.loading()},
      );
    }

    try {
      final result = await _api.extractWords(
        text: analysisText,
        userId: userId ?? ref.read(appSessionProvider).userId,
        enrichMeanings: false,
        // 意味生成は教材詳細の「意味を生成中」リクエストに一本化する。
        // ここでも開始すると同じ教材の生成が二重になり、画面側がロック待ちになる。
        backgroundEnrichMeanings: false,
      );
      state = state.copyWith(
        analyses: {...state.analyses, materialId: AsyncValue.data(result)},
        materials: [
          for (final item in state.materials)
            if (item.id == materialId)
              item.copyWith(
                analysisTotalWords: result.totalWords,
                analysisKnownCount: result.knownCount,
                analysisUnknownCount: result.unknownCount,
                analysisCoverageRate: result.coverageRate,
                analysisUpdatedAt: DateTime.now(),
              )
            else
              item,
        ],
      );
    } catch (error, stackTrace) {
      // バックグラウンド再解析の失敗で、表示できていた解析結果まで
      // エラー表示に置き換えない。
      if (existing is! AsyncData<ExtractWordsResult>) {
        state = state.copyWith(
          analyses: {
            ...state.analyses,
            materialId: AsyncValue.error(error, stackTrace),
          },
        );
      }
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
