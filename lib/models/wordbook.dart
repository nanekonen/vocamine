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

  factory Wordbook.fromJson(Map<String, dynamic> json) {
    return Wordbook(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      folderId: json['folder_id'] as String?,
    );
  }
}
