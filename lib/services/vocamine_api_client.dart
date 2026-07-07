import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../models/lexical_analysis.dart';
import '../models/folder.dart';
import '../models/material_item.dart';
import '../models/word.dart';
import '../models/word_lookup.dart';
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

  Future<void> addMeaningToWordbook({
    required String userId,
    required int meaningId,
    String sourceType = 'manual',
    String? sourceMaterialId,
    String? sourceFolderId,
    String? sourceLabel,
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
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/users/$userId/setup'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'level': level}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractErrorMessage(response));
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['registered_words'] as int? ?? 0;
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
    return AppFolder.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
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
