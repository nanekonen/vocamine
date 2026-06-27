class AppFolder {
  final String id;
  final String name;
  final String? parentId;

  const AppFolder({
    required this.id,
    required this.name,
    this.parentId,
  });
}