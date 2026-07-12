class AppFolder {
  final String id;
  final String name;
  final String? parentId;

  const AppFolder({required this.id, required this.name, this.parentId});

  AppFolder copyWith({
    String? name,
    String? parentId,
    bool clearParent = false,
  }) {
    return AppFolder(
      id: id,
      name: name ?? this.name,
      parentId: clearParent ? null : parentId ?? this.parentId,
    );
  }

  factory AppFolder.fromJson(Map<String, dynamic> json) {
    return AppFolder(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      parentId: json['parent_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'parent_id': parentId};
  }
}
