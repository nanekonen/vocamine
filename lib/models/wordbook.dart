class Wordbook {
  final String id;
  final String name;
  final String? folderId;

  const Wordbook({
    required this.id,
    required this.name,
    this.folderId,
  });
}