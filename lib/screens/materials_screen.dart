import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/material_library_provider.dart';

class MaterialsScreen extends ConsumerWidget {
  final String? folderId;
  final String title;

  const MaterialsScreen({super.key, this.folderId, this.title = '教材'});

  Future<void> _addMaterial(BuildContext context, WidgetRef ref) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    // TODO: Google Cloud Vision で OCR してテキストを取得する
    await Future.delayed(const Duration(seconds: 1)); // 仮の処理時間
    ref.read(materialLibraryProvider.notifier).addMaterial(
          image.name,
          '（ここにOCR結果が表示されます）',
          folderId: folderId,
        );
  }

  void _createFolder(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('フォルダを作成'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '名前を入力'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                ref.read(materialLibraryProvider.notifier).createFolder(
                      controller.text.trim(),
                      parentId: folderId,
                    );
              }
              Navigator.pop(context);
            },
            child: const Text('作成'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(materialLibraryProvider);
    final folders = library.folders.where((f) => f.parentId == folderId).toList();
    final materials = library.materials.where((m) => m.folderId == folderId).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.create_new_folder),
            tooltip: 'フォルダを作成',
            onPressed: () => _createFolder(context, ref),
          ),
        ],
      ),
      body: (folders.isEmpty && materials.isEmpty)
          ? const Center(child: Text('教材がまだありません'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ...folders.map(
                  (folder) => ListTile(
                    leading: const Icon(Icons.folder),
                    title: Text(folder.name),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(
                      '/materials/folder',
                      extra: {'folderId': folder.id, 'title': folder.name},
                    ),
                  ),
                ),
                ...materials.map(
                  (material) => ListTile(
                    leading: const Icon(Icons.description),
                    title: Text(material.title),
                    subtitle: Text(
                      '${material.createdAt.year}/${material.createdAt.month}/${material.createdAt.day}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(
                      '/materials/detail',
                      extra: {'materialId': material.id, 'title': material.title},
                    ),
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addMaterial(context, ref),
        icon: const Icon(Icons.photo_library),
        label: const Text('教材を読み込む'),
      ),
    );
  }
}