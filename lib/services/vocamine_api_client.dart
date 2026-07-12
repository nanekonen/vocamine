import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../models/lexical_analysis.dart';
import '../models/folder.dart';
import '../models/material_item.dart';
import '../models/word.dart';
import '../models/word_lookup.dart';
import '../models/wordbook.dart';
import 'app_session.dart';

class PdfExtractionResult {
  final String text;
  final List<Uint8List> pageImages;
  final List<SourceWordBox> wordBoxes;

  const PdfExtractionResult({
    required this.text,
    required this.pageImages,
    required this.wordBoxes,
  });
}

class ImageExtractionResult {
  final String text;
  final List<SourceWordBox> wordBoxes;

  const ImageExtractionResult({required this.text, required this.wordBoxes});
}

class VocamineApiClient {
  static const String baseUrl = String.fromEnvironment(
    'VOCAMINE_API_BASE_URL',
    defaultValue: 'http://localhost:8000/api/v1',
  );

  final http.Client _client;

  VocamineApiClient({http.Client? client}) : _client = client ?? http.Client();

  Future<ImageExtractionResult> extractTextFromImage({
    required Uint8List bytes,
    required String filename,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/ocr/image'),
    );
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: filename,
        contentType: _contentTypeForFilename(filename),
      ),
    );

    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessage(response));
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return ImageExtractionResult(
      text: json['text'] as String? ?? '',
      wordBoxes: _parseWordBoxes(json),
    );
  }

  Future<PdfExtractionResult> extractTextFromPdf({
    required Uint8List bytes,
    required String filename,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/ocr/pdf'),
    );
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: filename,
        contentType: MediaType('application', 'pdf'),
      ),
    );

    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessage(response));
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final pageImages = (json['page_images'] as List<dynamic>? ?? [])
        .whereType<String>()
        .map(_decodeDataUrlBytes)
        .whereType<Uint8List>()
        .toList();
    return PdfExtractionResult(
      text: json['text'] as String? ?? '',
      pageImages: pageImages,
      wordBoxes: _parseWordBoxes(json),
    );
  }

  List<SourceWordBox> _parseWordBoxes(Map<String, dynamic> json) {
    return (json['word_boxes'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(SourceWordBox.fromJson)
        .where((box) => box.text.isNotEmpty && box.width > 0 && box.height > 0)
        .toList();
  }

  Uint8List? _decodeDataUrlBytes(String dataUrl) {
    final commaIndex = dataUrl.indexOf(',');
    if (commaIndex < 0) return null;
    try {
      return base64Decode(dataUrl.substring(commaIndex + 1));
    } catch (_) {
      return null;
    }
  }

  Future<ExtractWordsResult> extractWords({
    required String text,
    required String userId,
    bool enrichMeanings = false,
    bool backgroundEnrichMeanings = true,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/words/extract'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'text': text,
        'user_id': userId,
        'enrich_meanings': enrichMeanings,
        'background_enrich_meanings': backgroundEnrichMeanings,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessage(response));
    }

    return ExtractWordsResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<WordLookupResult> lookupWord({
    required String word,
    required String partOfSpeech,
    bool enrichMeanings = true,
  }) async {
    final uri = Uri.parse('$baseUrl/words/lookup').replace(
      queryParameters: {
        'word': word,
        'part_of_speech': partOfSpeech,
        'enrich_meanings': enrichMeanings.toString(),
      },
    );
    final response = await _client.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessage(response));
    }

    return WordLookupResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<List<WordLookupResult>> fetchStoredMeanings(
    List<LexicalItemResult> items,
  ) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/words/stored-meanings'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'items': items
            .map(
              (item) => {
                'text': item.text,
                'part_of_speech': item.partOfSpeech,
                'part_of_speech_detail': item.partOfSpeechDetail,
                'surface_forms': item.surfaceForms,
                'occurrences': item.occurrences
                    .map(
                      (occurrence) => {
                        'form': occurrence.form,
                        'start': occurrence.start,
                        'end': occurrence.end,
                      },
                    )
                    .toList(),
                'kind': item.kind,
              },
            )
            .toList(),
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessage(response));
    }
    return (jsonDecode(response.body) as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map(WordLookupResult.fromJson)
        .toList();
  }

  Future<void> addMeaningToWordbook({
    required String userId,
    required int meaningId,
    String sourceType = 'manual',
    String? sourceMaterialId,
    String? sourceFolderId,
    String? sourceLabel,
    String? wordbookId,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/words/wordbook',
    ).replace(queryParameters: {'user_id': userId});
    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'meaning_id': meaningId,
        'source_type': sourceType,
        'source_material_id': sourceMaterialId,
        'source_folder_id': sourceFolderId,
        'source_label': sourceLabel,
        'wordbook_id': wordbookId,
      }),
    );
    if (response.statusCode == 409) {
      return;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessage(response));
    }
  }

  Future<void> addItemsToWordbook({
    required String userId,
    required List<LexicalItemResult> items,
    bool enrichMeanings = true,
    String sourceType = 'manual',
    String? sourceMaterialId,
    String? sourceFolderId,
    String? sourceLabel,
    bool isLearned = false,
    String? wordbookId,
  }) async {
    final payloadItems = items
        .map(
          (item) => {
            'text': item.text,
            'part_of_speech': item.partOfSpeech,
            'part_of_speech_detail': item.partOfSpeechDetail,
            'surface_forms': item.surfaceForms,
            'occurrences': item.occurrences
                .map(
                  (occurrence) => {
                    'form': occurrence.form,
                    'start': occurrence.start,
                    'end': occurrence.end,
                  },
                )
                .toList(),
            'kind': item.kind,
          },
        )
        .toList();
    final response = await _client.post(
      Uri.parse('$baseUrl/words/batch'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'items': payloadItems,
        'enrich_meanings': enrichMeanings,
        'source_type': sourceType,
        'source_material_id': sourceMaterialId,
        'source_folder_id': sourceFolderId,
        'source_label': sourceLabel,
        'is_learned': isLearned,
        'wordbook_id': wordbookId,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessage(response));
    }
  }

  Future<List<Word>> fetchWordbook({
    required String userId,
    bool? isLearned,
    String? sourceType,
    String? sourceMaterialId,
    String? sourceFolderId,
    String? wordbookId,
  }) async {
    final queryParameters = <String, String>{};
    if (isLearned != null) {
      queryParameters['is_learned'] = isLearned.toString();
    }
    if (sourceType != null) queryParameters['source_type'] = sourceType;
    if (sourceMaterialId != null) {
      queryParameters['source_material_id'] = sourceMaterialId;
    }
    if (sourceFolderId != null) {
      queryParameters['source_folder_id'] = sourceFolderId;
    }
    if (wordbookId != null) queryParameters['wordbook_id'] = wordbookId;
    final uri = Uri.parse('$baseUrl/words/wordbook/$userId').replace(
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
    final response = await _client.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessage(response));
    }

    final json = jsonDecode(response.body) as List<dynamic>;
    return json
        .whereType<Map<String, dynamic>>()
        .map(Word.fromWordbookJson)
        .where((word) => word.headword.isNotEmpty)
        .toList();
  }

  Future<List<Word>> fetchDistractors({
    required String partOfSpeech,
    required Iterable<int> excludeMeaningIds,
    int limit = 20,
  }) async {
    final uri = Uri.parse('$baseUrl/words/distractors').replace(
      queryParameters: {
        'part_of_speech': partOfSpeech,
        'exclude_meaning_ids': excludeMeaningIds.join(','),
        'limit': limit.toString(),
      },
    );
    final response = await _client.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessage(response));
    }
    return (jsonDecode(response.body) as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map(Word.fromMeaningJson)
        .where((word) => word.headword.isNotEmpty)
        .toList();
  }

  Future<int> regenerateMissingJapanese(Iterable<int> meaningIds) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/words/regenerate-missing-japanese'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'meaning_ids': meaningIds.toSet().toList()}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessage(response));
    }
    return (jsonDecode(response.body) as Map<String, dynamic>)['updated']
            as int? ??
        0;
  }

  Future<({List<AppFolder> folders, List<Wordbook> wordbooks})>
  fetchIndependentWordbooks({required String userId}) async {
    final uri = Uri.parse(
      '$baseUrl/wordbooks',
    ).replace(queryParameters: {'user_id': userId});
    final response = await _client.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessage(response));
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return (
      folders: (json['folders'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(AppFolder.fromJson)
          .toList(),
      wordbooks: (json['wordbooks'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(Wordbook.fromJson)
          .toList(),
    );
  }

  Future<Wordbook> createIndependentWordbook({
    required String userId,
    required String name,
    String? folderId,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/wordbooks'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'name': name,
        'folder_id': folderId,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessage(response));
    }
    return Wordbook.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> updateIndependentWordbook({
    required String userId,
    required String wordbookId,
    String? name,
    String? folderId,
    bool updateFolder = false,
  }) async {
    final response = await _client.patch(
      Uri.parse('$baseUrl/wordbooks/$wordbookId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'name': name,
        'folder_id': folderId,
        'update_folder': updateFolder,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessage(response));
    }
  }

  Future<void> deleteIndependentWordbook({
    required String userId,
    required String wordbookId,
  }) async {
    final response = await _client.delete(
      Uri.parse(
        '$baseUrl/wordbooks/$wordbookId',
      ).replace(queryParameters: {'user_id': userId}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessage(response));
    }
  }

  Future<AppFolder> createIndependentWordbookFolder({
    required String userId,
    required String name,
    String? parentId,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/wordbooks/folders'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'name': name,
        'parent_id': parentId,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessage(response));
    }
    return AppFolder.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> updateIndependentWordbookFolder({
    required String userId,
    required String folderId,
    String? name,
    String? parentId,
    bool updateParent = false,
  }) async {
    final response = await _client.patch(
      Uri.parse('$baseUrl/wordbooks/folders/$folderId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'name': name,
        'parent_id': parentId,
        'update_parent': updateParent,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessage(response));
    }
  }

  Future<void> deleteIndependentWordbookFolder({
    required String userId,
    required String folderId,
  }) async {
    final response = await _client.delete(
      Uri.parse(
        '$baseUrl/wordbooks/folders/$folderId',
      ).replace(queryParameters: {'user_id': userId}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessage(response));
    }
  }

  Future<String?> getMaterialDefaultWordbook({
    required String userId,
    required String materialId,
  }) async {
    final response = await _client.get(
      Uri.parse(
        '$baseUrl/wordbooks/materials/$materialId/default',
      ).replace(queryParameters: {'user_id': userId}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessage(response));
    }
    return (jsonDecode(response.body) as Map<String, dynamic>)['wordbook_id']
        as String?;
  }

  Future<void> setMaterialDefaultWordbook({
    required String userId,
    required String materialId,
    required String wordbookId,
  }) async {
    final response = await _client.put(
      Uri.parse('$baseUrl/wordbooks/materials/$materialId/default'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': userId, 'wordbook_id': wordbookId}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessage(response));
    }
  }

  Future<void> updateWordbookEntry({
    required String entryId,
    required bool isLearned,
  }) async {
    final response = await _client.patch(
      Uri.parse('$baseUrl/words/wordbook/$entryId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'is_learned': isLearned}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessage(response));
    }
  }

  Future<int> setupLevel({
    required String userId,
    required String level,
    required String username,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/users/$userId/setup'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'level': level, 'username': username}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessage(response));
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['registered_words'] as int? ?? 0;
  }

  Future<String?> fetchUserLevel({required String userId}) async {
    final response = await _client.get(Uri.parse('$baseUrl/users/$userId'));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessage(response));
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['level'] as String?;
  }

  Future<AppSession> resolveAuthSession({required String accessToken}) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/auth/session'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'access_token': accessToken}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessage(response));
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return AppSession(
      userId: json['user_id'] as String,
      email: json['email'] as String?,
      username: json['username'] as String?,
      level: json['level'] as String?,
      isLoaded: true,
      setupCompleted: json['setup_completed'] as bool? ?? false,
    );
  }

  Future<({List<AppFolder> folders, List<MaterialItem> materials})>
  fetchMaterialLibrary({required String userId}) async {
    final uri = Uri.parse(
      '$baseUrl/materials',
    ).replace(queryParameters: {'user_id': userId});
    final response = await _client.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessage(response));
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final folders = (json['folders'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(AppFolder.fromJson)
        .toList();
    final materials = (json['materials'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(MaterialItem.fromJson)
        .toList();
    return (folders: folders, materials: materials);
  }

  Future<void> deleteMaterial({
    required String userId,
    required String materialId,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/materials/$materialId',
    ).replace(queryParameters: {'user_id': userId});
    final response = await _client.delete(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessage(response));
    }
  }

  Future<MaterialItem> updateMaterial({
    required String userId,
    required String materialId,
    String? title,
    String? folderId,
    bool updateFolder = false,
  }) async {
    final response = await _client.patch(
      Uri.parse('$baseUrl/materials/$materialId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'title': title,
        'folder_id': folderId,
        'update_folder': updateFolder,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessage(response));
    }
    return MaterialItem.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<MaterialItem> appendMaterialPages({
    required String userId,
    required String materialId,
    required String extractedText,
    required List<Uint8List> pageImages,
    required List<SourceWordBox> wordBoxes,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/materials/$materialId/pages'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'extracted_text': extractedText,
        'page_images_base64': pageImages.map(base64Encode).toList(),
        'word_boxes': wordBoxes.map((box) => box.toJson()).toList(),
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessage(response));
    }
    return MaterialItem.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<AppFolder> createMaterialFolder({
    required String userId,
    required String name,
    String? parentId,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/materials/folders'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'name': name,
        'parent_id': parentId,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessage(response));
    }
    return AppFolder.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<AppFolder> updateMaterialFolder({
    required String userId,
    required String folderId,
    String? name,
    String? parentId,
    bool updateParent = false,
  }) async {
    final response = await _client.patch(
      Uri.parse('$baseUrl/materials/folders/$folderId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'name': name,
        'parent_id': parentId,
        'update_parent': updateParent,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessage(response));
    }
    return AppFolder.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> deleteMaterialFolder({
    required String userId,
    required String folderId,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/materials/folders/$folderId',
    ).replace(queryParameters: {'user_id': userId});
    final response = await _client.delete(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessage(response));
    }
  }

  Future<MaterialItem> createMaterial({
    required String userId,
    required String title,
    required String ocrText,
    Uint8List? sourceBytes,
    String? sourceMimeType,
    List<Uint8List> sourcePageImages = const [],
    List<SourceWordBox> sourceWordBoxes = const [],
    String? folderId,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/materials'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'title': title,
        'extracted_text': ocrText,
        'folder_id': folderId,
        'source_mime_type': sourceMimeType,
        'source_base64': sourceBytes == null ? null : base64Encode(sourceBytes),
        'page_images_base64': sourcePageImages
            .map((bytes) => base64Encode(bytes))
            .toList(),
        'word_boxes': sourceWordBoxes.map((box) => box.toJson()).toList(),
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessage(response));
    }
    final saved = MaterialItem.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    return MaterialItem(
      id: saved.id,
      title: saved.title,
      ocrText: saved.ocrText,
      sourceBytes: sourceBytes,
      sourceMimeType: saved.sourceMimeType ?? sourceMimeType,
      sourcePageImages: saved.sourcePageImages.isNotEmpty
          ? saved.sourcePageImages
          : sourcePageImages,
      sourceWordBoxes: saved.sourceWordBoxes.isNotEmpty
          ? saved.sourceWordBoxes
          : sourceWordBoxes,
      folderId: saved.folderId,
      defaultWordbookId: saved.defaultWordbookId,
      sourceObjectStorageKey: saved.sourceObjectStorageKey,
      readablePdfObjectStorageKey: saved.readablePdfObjectStorageKey,
      thumbnailObjectStorageKey: saved.thumbnailObjectStorageKey,
      createdAt: saved.createdAt,
    );
  }

  String _extractErrorMessage(http.Response response) {
    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return json['detail']?.toString() ?? response.body;
    } catch (_) {
      return response.body;
    }
  }

  MediaType _contentTypeForFilename(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) {
      return MediaType('image', 'png');
    }
    if (lower.endsWith('.webp')) {
      return MediaType('image', 'webp');
    }
    if (lower.endsWith('.gif')) {
      return MediaType('image', 'gif');
    }
    return MediaType('image', 'jpeg');
  }
}
