class Word {
  final String id;
  final String wordbookId;
  final String headword;
  final String meaningJa;
  final String partOfSpeech;
  final bool isLearned;

  const Word({
    required this.id,
    required this.wordbookId,
    required this.headword,
    required this.meaningJa,
    required this.partOfSpeech,
    this.isLearned = false,
  });

  Word copyWith({bool? isLearned}) {
    return Word(
      id: id,
      wordbookId: wordbookId,
      headword: headword,
      meaningJa: meaningJa,
      partOfSpeech: partOfSpeech,
      isLearned: isLearned ?? this.isLearned,
    );
  }
}