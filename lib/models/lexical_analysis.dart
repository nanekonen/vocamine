class LexicalOccurrence {
  final String form;
  final int start;
  final int end;

  const LexicalOccurrence({
    required this.form,
    required this.start,
    required this.end,
  });

  factory LexicalOccurrence.fromJson(Map<String, dynamic> json) {
    return LexicalOccurrence(
      form: json['form'] as String? ?? '',
      start: json['start'] as int? ?? -1,
      end: json['end'] as int? ?? -1,
    );
  }
}

class LexicalItemResult {
  final String text;
  final String partOfSpeech;
  final String? partOfSpeechDetail;
  final List<String> surfaceForms;
  final List<LexicalOccurrence> occurrences;
  final String kind;
  final bool isLearned;
  final bool hasMeaning;
  final int occurrenceCount;

  const LexicalItemResult({
    required this.text,
    required this.partOfSpeech,
    this.partOfSpeechDetail,
    this.surfaceForms = const [],
    this.occurrences = const [],
    required this.kind,
    required this.isLearned,
    required this.hasMeaning,
    this.occurrenceCount = 1,
  });

  factory LexicalItemResult.fromJson(Map<String, dynamic> json) {
    return LexicalItemResult(
      text: json['text'] as String? ?? '',
      partOfSpeech: json['part_of_speech'] as String? ?? '',
      partOfSpeechDetail: json['part_of_speech_detail'] as String?,
      surfaceForms: (json['surface_forms'] as List<dynamic>? ?? [])
          .whereType<String>()
          .toList(),
      occurrences: (json['occurrences'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(LexicalOccurrence.fromJson)
          .toList(),
      kind: json['kind'] as String? ?? 'word',
      isLearned: json['is_learned'] as bool? ?? false,
      hasMeaning: json['has_meaning'] as bool? ?? false,
      occurrenceCount: json['occurrence_count'] as int? ?? 1,
    );
  }
}

class ExtractWordsResult {
  final List<String> unknownWords;
  final int totalWords;
  final int unknownCount;
  final int knownCount;
  final double coverageRate;
  final List<LexicalItemResult> items;
  final List<LexicalItemResult> unknownItems;

  const ExtractWordsResult({
    required this.unknownWords,
    required this.totalWords,
    required this.unknownCount,
    required this.knownCount,
    required this.coverageRate,
    required this.items,
    required this.unknownItems,
  });

  factory ExtractWordsResult.empty() {
    return const ExtractWordsResult(
      unknownWords: [],
      totalWords: 0,
      unknownCount: 0,
      knownCount: 0,
      coverageRate: 0,
      items: [],
      unknownItems: [],
    );
  }

  factory ExtractWordsResult.fromJson(Map<String, dynamic> json) {
    final itemsJson = json['items'] as List<dynamic>? ?? [];
    final unknownItemsJson = json['unknown_items'] as List<dynamic>? ?? [];
    return ExtractWordsResult(
      unknownWords: (json['unknown_words'] as List<dynamic>? ?? [])
          .whereType<String>()
          .toList(),
      totalWords: json['total_words'] as int? ?? 0,
      unknownCount: json['unknown_count'] as int? ?? 0,
      knownCount: json['known_count'] as int? ?? 0,
      coverageRate: (json['coverage_rate'] as num?)?.toDouble() ?? 0,
      items: itemsJson
          .whereType<Map<String, dynamic>>()
          .map(LexicalItemResult.fromJson)
          .toList(),
      unknownItems: unknownItemsJson
          .whereType<Map<String, dynamic>>()
          .map(LexicalItemResult.fromJson)
          .toList(),
    );
  }
}
