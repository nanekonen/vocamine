class Wordbook {
  final String id;
  final String name;
  final String? folderId;
  final bool? isLearned;
  final String? sourceType;
  final String? sourceMaterialId;
  final String? sourceFolderId;
  final int wordCount;

  const Wordbook({
    required this.id,
    required this.name,
    this.folderId,
    this.isLearned,
    this.sourceType,
    this.sourceMaterialId,
    this.sourceFolderId,
    this.wordCount = 0,
  });

  Wordbook copyWith({
    String? name,
    String? folderId,
    bool clearFolder = false,
  }) {
    return Wordbook(
      id: id,
      name: name ?? this.name,
      folderId: clearFolder ? null : folderId ?? this.folderId,
      isLearned: isLearned,
      sourceType: sourceType,
      sourceMaterialId: sourceMaterialId,
      sourceFolderId: sourceFolderId,
      wordCount: wordCount,
    );
  }

  factory Wordbook.fromJson(Map<String, dynamic> json) {
    return Wordbook(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      folderId: json['folder_id'] as String?,
      wordCount: json['word_count'] as int? ?? 0,
    );
  }
}
