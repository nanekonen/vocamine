class ExampleSentenceInfo {
  final int id;
  final String sentence;
  final String? translatedSentence;

  const ExampleSentenceInfo({
    required this.id,
    required this.sentence,
    this.translatedSentence,
  });

  factory ExampleSentenceInfo.fromJson(Map<String, dynamic> json) {
    return ExampleSentenceInfo(
      id: json['id'] as int? ?? 0,
      sentence: json['sentence'] as String? ?? '',
      translatedSentence: json['translated_sentence'] as String?,
    );
  }
}

class MeaningInfo {
  final int id;
  final String partOfSpeech;
  final String? definitionEn;
  final String? definitionJa;
  final String source;
  final String? transitivity;
  final String? countability;
  final List<ExampleSentenceInfo> exampleSentences;

  const MeaningInfo({
    required this.id,
    required this.partOfSpeech,
    required this.source,
    this.definitionEn,
    this.definitionJa,
    this.transitivity,
    this.countability,
    required this.exampleSentences,
  });

  factory MeaningInfo.fromJson(Map<String, dynamic> json) {
    final examplesJson = json['example_sentences'] as List<dynamic>? ?? [];
    return MeaningInfo(
      id: json['id'] as int? ?? 0,
      partOfSpeech: json['part_of_speech'] as String? ?? '',
      source: json['source'] as String? ?? '',
      definitionEn: json['definition_en'] as String?,
      definitionJa: json['definition_ja'] as String?,
      transitivity: json['transitivity'] as String?,
      countability: json['countability'] as String?,
      exampleSentences: examplesJson
          .whereType<Map<String, dynamic>>()
          .map(ExampleSentenceInfo.fromJson)
          .toList(),
    );
  }
}

class WordLookupResult {
  final int id;
  final String word;
  final List<MeaningInfo> meanings;

  const WordLookupResult({
    required this.id,
    required this.word,
    required this.meanings,
  });

  factory WordLookupResult.fromJson(Map<String, dynamic> json) {
    final meaningsJson = json['meanings'] as List<dynamic>? ?? [];
    return WordLookupResult(
      id: json['id'] as int? ?? 0,
      word: json['word'] as String? ?? '',
      meanings: meaningsJson
          .whereType<Map<String, dynamic>>()
          .map(MeaningInfo.fromJson)
          .toList(),
    );
  }
}
