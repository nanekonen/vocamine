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

  const MaterialLibraryState({
    required this.folders,
    required this.materials,
    this.analyses = const {},
  });

  MaterialLibraryState copyWith({
    List<AppFolder>? folders,
    List<MaterialItem>? materials,
    Map<String, AsyncValue<ExtractWordsResult>>? analyses,
  }) {
    return MaterialLibraryState(
      folders: folders ?? this.folders,
      materials: materials ?? this.materials,
      analyses: analyses ?? this.analyses,
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
    } catch (_) {
      // Materials persistence may not be migrated yet. Keep the local library
      // usable so vocabulary notebooks are not hidden by that failure.
    } finally {
      _loaded = true;
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

  String _analysisTextForMaterial(MaterialItem material) {
    final text = material.ocrText.trim();
    if (text.isNotEmpty) {
      return text;
    }

    final boxes = [...material.sourceWordBoxes]
      ..sort((a, b) {
        final pageCompare = a.pageIndex.compareTo(b.pageIndex);
        if (pageCompare != 0) return pageCompare;
        final lineCompare = (a.top * 100).round().compareTo(
          (b.top * 100).round(),
        );
        if (lineCompare != 0) return lineCompare;
        return a.left.compareTo(b.left);
      });
    return boxes
        .map((box) => box.text.trim())
        .where((text) => text.isNotEmpty)
        .join(' ');
  }
}

final materialLibraryProvider =
    NotifierProvider<MaterialLibraryNotifier, MaterialLibraryState>(
      MaterialLibraryNotifier.new,
    );
