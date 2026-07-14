import 'dart:typed_data';

class SourceWordBox {
  final String text;
  final int pageIndex;
  final int? start;
  final int? end;
  final double left;
  final double top;
  final double width;
  final double height;

  const SourceWordBox({
    required this.text,
    required this.pageIndex,
    this.start,
    this.end,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  factory SourceWordBox.fromJson(Map<String, dynamic> json) {
    return SourceWordBox(
      text: json['text'] as String? ?? '',
      pageIndex: json['page_index'] as int? ?? 0,
      start: json['start'] as int?,
      end: json['end'] as int?,
      left: (json['left'] as num?)?.toDouble() ?? 0,
      top: (json['top'] as num?)?.toDouble() ?? 0,
      width: (json['width'] as num?)?.toDouble() ?? 0,
      height: (json['height'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'page_index': pageIndex,
      'start': start,
      'end': end,
      'left': left,
      'top': top,
      'width': width,
      'height': height,
    };
  }
}

class MaterialItem {
  final String id;
  final String title;
  final String ocrText;
  final Uint8List? sourceBytes;
  final String? sourceMimeType;
  final List<Uint8List> sourcePageImages;
  final List<SourceWordBox> sourceWordBoxes;
  final String? folderId;
  final String? defaultWordbookId;
  final String? sourceObjectStorageKey;
  final String? readablePdfObjectStorageKey;
  final String? thumbnailObjectStorageKey;
  final int? analysisTotalWords;
  final int? analysisKnownCount;
  final int? analysisUnknownCount;
  final int? analysisUntranslatedCount;
  final double? analysisCoverageRate;
  final DateTime? analysisUpdatedAt;
  final DateTime createdAt;

  const MaterialItem({
    required this.id,
    required this.title,
    required this.ocrText,
    this.sourceBytes,
    this.sourceMimeType,
    this.sourcePageImages = const [],
    this.sourceWordBoxes = const [],
    this.folderId,
    this.defaultWordbookId,
    this.sourceObjectStorageKey,
    this.readablePdfObjectStorageKey,
    this.thumbnailObjectStorageKey,
    this.analysisTotalWords,
    this.analysisKnownCount,
    this.analysisUnknownCount,
    this.analysisUntranslatedCount,
    this.analysisCoverageRate,
    this.analysisUpdatedAt,
    required this.createdAt,
  });

  MaterialItem copyWith({
    String? title,
    String? folderId,
    bool clearFolder = false,
    String? defaultWordbookId,
    String? ocrText,
    Uint8List? sourceBytes,
    String? sourceMimeType,
    List<Uint8List>? sourcePageImages,
    List<SourceWordBox>? sourceWordBoxes,
    int? analysisTotalWords,
    int? analysisKnownCount,
    int? analysisUnknownCount,
    int? analysisUntranslatedCount,
    double? analysisCoverageRate,
    DateTime? analysisUpdatedAt,
  }) {
    return MaterialItem(
      id: id,
      title: title ?? this.title,
      ocrText: ocrText ?? this.ocrText,
      sourceBytes: sourceBytes ?? this.sourceBytes,
      sourceMimeType: sourceMimeType ?? this.sourceMimeType,
      sourcePageImages: sourcePageImages ?? this.sourcePageImages,
      sourceWordBoxes: sourceWordBoxes ?? this.sourceWordBoxes,
      folderId: clearFolder ? null : folderId ?? this.folderId,
      defaultWordbookId: defaultWordbookId ?? this.defaultWordbookId,
      sourceObjectStorageKey: sourceObjectStorageKey,
      readablePdfObjectStorageKey: readablePdfObjectStorageKey,
      thumbnailObjectStorageKey: thumbnailObjectStorageKey,
      analysisTotalWords: analysisTotalWords ?? this.analysisTotalWords,
      analysisKnownCount: analysisKnownCount ?? this.analysisKnownCount,
      analysisUnknownCount: analysisUnknownCount ?? this.analysisUnknownCount,
      analysisUntranslatedCount:
          analysisUntranslatedCount ?? this.analysisUntranslatedCount,
      analysisCoverageRate: analysisCoverageRate ?? this.analysisCoverageRate,
      analysisUpdatedAt: analysisUpdatedAt ?? this.analysisUpdatedAt,
      createdAt: createdAt,
    );
  }

  factory MaterialItem.fromJson(Map<String, dynamic> json) {
    final analysis = json['analysis_summary'] as Map<String, dynamic>?;
    return MaterialItem(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      ocrText:
          json['extracted_text'] as String? ??
          json['ocr_text'] as String? ??
          '',
      sourcePageImages: (json['page_images'] as List<dynamic>? ?? [])
          .whereType<String>()
          .map(_decodeDataUrlBytes)
          .whereType<Uint8List>()
          .toList(),
      sourceMimeType: json['source_mime_type'] as String?,
      sourceWordBoxes: (json['word_boxes'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(SourceWordBox.fromJson)
          .toList(),
      folderId: json['folder_id'] as String?,
      defaultWordbookId: json['default_wordbook_id'] as String?,
      sourceObjectStorageKey: json['source_object_storage_key'] as String?,
      readablePdfObjectStorageKey:
          json['readable_pdf_object_storage_key'] as String?,
      thumbnailObjectStorageKey:
          json['thumbnail_object_storage_key'] as String?,
      analysisTotalWords: analysis?['total_words'] as int?,
      analysisKnownCount: analysis?['known_count'] as int?,
      analysisUnknownCount: analysis?['unknown_count'] as int?,
      analysisUntranslatedCount: analysis?['untranslated_count'] as int?,
      analysisCoverageRate: (analysis?['coverage_rate'] as num?)?.toDouble(),
      analysisUpdatedAt: DateTime.tryParse(
        analysis?['updated_at'] as String? ?? '',
      ),
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

Uint8List? _decodeDataUrlBytes(String dataUrl) {
  final commaIndex = dataUrl.indexOf(',');
  final raw = commaIndex >= 0 ? dataUrl.substring(commaIndex + 1) : dataUrl;
  try {
    return UriData.parse(
      'data:application/octet-stream;base64,$raw',
    ).contentAsBytes();
  } catch (_) {
    return null;
  }
}
