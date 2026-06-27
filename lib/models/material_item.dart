class MaterialItem {
  final String id;
  final String title;
  final String ocrText;
  final String? folderId;
  final DateTime createdAt;

  const MaterialItem({
    required this.id,
    required this.title,
    required this.ocrText,
    this.folderId,
    required this.createdAt,
  });
}