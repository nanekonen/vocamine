class WordExample {
  final String sentence;
  final String? translatedSentence;
  const WordExample({required this.sentence, this.translatedSentence});
}

class Word {
  final String id;
  final String studyKey;
  final String wordbookId;
  final String headword;
  final String meaningJa;
  final bool hasJapaneseDefinition;
  final String partOfSpeech;
  final String? definitionEn;
  final String? ipa;
  final String dictionarySource;
  final bool isLearned;
  final int? meaningId;
  final int? tier;
  final List<String> sourceMaterialIds;
  final List<String> sourceFolderIds;
  final List<String> sourceLabels;
  final List<String> sourceTypes;
  final List<WordExample> examples;

  const Word({
    required this.id,
    String? studyKey,
    required this.wordbookId,
    required this.headword,
    required this.meaningJa,
    this.hasJapaneseDefinition = true,
    required this.partOfSpeech,
    this.definitionEn,
    this.ipa,
    this.dictionarySource = '',
    this.isLearned = false,
    this.meaningId,
    this.tier,
    this.sourceMaterialIds = const [],
    this.sourceFolderIds = const [],
    this.sourceLabels = const [],
    this.sourceTypes = const [],
    this.examples = const [],
  }) : studyKey = studyKey ?? id;

  Word copyWith({bool? isLearned, String? studyKey}) {
    return Word(
      id: id,
      studyKey: studyKey ?? this.studyKey,
      wordbookId: wordbookId,
      headword: headword,
      meaningJa: meaningJa,
      hasJapaneseDefinition: hasJapaneseDefinition,
      partOfSpeech: partOfSpeech,
      definitionEn: definitionEn,
      ipa: ipa,
      dictionarySource: dictionarySource,
      isLearned: isLearned ?? this.isLearned,
      meaningId: meaningId,
      tier: tier,
      sourceMaterialIds: sourceMaterialIds,
      sourceFolderIds: sourceFolderIds,
      sourceLabels: sourceLabels,
      sourceTypes: sourceTypes,
      examples: examples,
    );
  }

  factory Word.fromWordbookJson(Map<String, dynamic> json) {
    final meaning =
        (json['meaning'] ?? json['meanings']) as Map<String, dynamic>? ?? {};
    final word = meaning['words'] as Map<String, dynamic>? ?? {};
    final definitionJa = meaning['definition_ja'] as String?;
    final sources = json['sources'] as List<dynamic>? ?? const [];
    final parsedSources = sources.whereType<Map<String, dynamic>>().toList();
    final firstSource = parsedSources.isEmpty ? null : parsedSources.first;
    final sourceMaterialIds = parsedSources
        .map((source) => source['material_id'])
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    final sourceFolderIds = parsedSources
        .map((source) => source['folder_id'])
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    final sourceLabels = parsedSources
        .map((source) => source['label'])
        .whereType<String>()
        .where((label) => label.trim().isNotEmpty)
        .toSet()
        .toList();
    final sourceTypes = parsedSources
        .map((source) => source['source_type'])
        .whereType<String>()
        .toSet()
        .toList();
    final examples =
        (meaning['example_sentences'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(
              (example) => WordExample(
                sentence: example['sentence'] as String? ?? '',
                translatedSentence: example['translated_sentence'] as String?,
              ),
            )
            .where((example) => example.sentence.isNotEmpty)
            .toList();
    return Word(
      id: (json['id'] ?? '').toString(),
      wordbookId: firstSource?['material_id'] as String? ?? 'default',
      headword: word['word'] as String? ?? '',
      meaningJa: definitionJa?.trim().isNotEmpty == true
          ? definitionJa!.trim()
          : '日本語訳が得られませんでした',
      hasJapaneseDefinition: definitionJa?.trim().isNotEmpty == true,
      partOfSpeech: meaning['part_of_speech'] as String? ?? '',
      definitionEn: meaning['definition_en'] as String?,
      ipa: meaning['ipa'] as String?,
      dictionarySource: meaning['source'] as String? ?? '',
      isLearned: json['is_learned'] as bool? ?? false,
      meaningId: json['meaning_id'] as int?,
      tier: meaning['tier'] as int?,
      sourceMaterialIds: sourceMaterialIds,
      sourceFolderIds: sourceFolderIds,
      sourceLabels: sourceLabels,
      sourceTypes: sourceTypes,
      examples: examples,
    );
  }

  factory Word.fromMeaningJson(Map<String, dynamic> meaning) {
    return Word.fromWordbookJson({
      'id': 'meaning:${meaning['id']}',
      'meaning_id': meaning['id'],
      'is_learned': false,
      'meanings': meaning,
      'sources': const <dynamic>[],
    });
  }
}
