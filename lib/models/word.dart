class Word {
  final String id;
  final String wordbookId;
  final String headword;
  final String meaningJa;
  final String partOfSpeech;
  final bool isLearned;
  final int? meaningId;
  final List<String> sourceMaterialIds;
  final List<String> sourceFolderIds;

  const Word({
    required this.id,
    required this.wordbookId,
    required this.headword,
    required this.meaningJa,
    required this.partOfSpeech,
    this.isLearned = false,
    this.meaningId,
    this.sourceMaterialIds = const [],
    this.sourceFolderIds = const [],
  });

  Word copyWith({bool? isLearned}) {
    return Word(
      id: id,
      wordbookId: wordbookId,
      headword: headword,
      meaningJa: meaningJa,
      partOfSpeech: partOfSpeech,
      isLearned: isLearned ?? this.isLearned,
      meaningId: meaningId,
      sourceMaterialIds: sourceMaterialIds,
      sourceFolderIds: sourceFolderIds,
    );
  }

  factory Word.fromWordbookJson(Map<String, dynamic> json) {
    final meaning =
        (json['meaning'] ?? json['meanings']) as Map<String, dynamic>? ?? {};
    final word = meaning['words'] as Map<String, dynamic>? ?? {};
    final definitionJa = meaning['definition_ja'] as String?;
    final sources = json['sources'] as List<dynamic>? ?? const [];
    final parsedSources = sources.whereType<Map<String, dynamic>>().toList();
    final firstSource = parsedSources.isEmpty
        ? null
        : parsedSources.first;
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
    return Word(
      id: (json['id'] ?? '').toString(),
      wordbookId: firstSource?['material_id'] as String? ?? 'default',
      headword: word['word'] as String? ?? '',
      meaningJa: definitionJa?.trim().isNotEmpty == true
          ? definitionJa!.trim()
          : '日本語訳が得られませんでした',
      partOfSpeech: meaning['part_of_speech'] as String? ?? '',
      isLearned: json['is_learned'] as bool? ?? false,
      meaningId: json['meaning_id'] as int?,
      sourceMaterialIds: sourceMaterialIds,
      sourceFolderIds: sourceFolderIds,
    );
  }
}
