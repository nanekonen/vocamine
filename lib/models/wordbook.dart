class Wordbook {
  final String id;
  final String name;
  final String? folderId;
  final bool? isLearned;
  final String? sourceType;
  final String? sourceMaterialId;
  final String? sourceFolderId;

  const Wordbook({
    required this.id,
    required this.name,
    this.folderId,
    this.isLearned,
    this.sourceType,
    this.sourceMaterialId,
    this.sourceFolderId,
  });
}
