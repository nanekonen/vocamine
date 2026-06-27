import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/wordbook_library_provider.dart';

class WordbookListScreen extends ConsumerWidget {
  final String? folderId;
  final String title;

  const WordbookListScreen({super.key, this.folderId, this.title = '単語帳'});

  void _showCreateMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.create_new_folder),
                title: const Text('フォルダを作成'),
                onTap: () {
                  Navigator.pop(context);
                  _showNameDialog(context, 'フォルダを作成', (name) {
                    ref.read(wordbookLibraryProvider.notifier).createFolder(name, parentId: folderId);
                  });
                },
              ),
              ListTile(
                leading: const Icon(Icons.menu_book),
                title: const Text('単語帳を作成'),
                onTap: () {
                  Navigator.pop(context);
                  _showNameDialog(context, '単語帳を作成', (name) {
                    ref.read(wordbookLibraryProvider.notifier).createWordbook(name, folderId: folderId);
                  });
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showNameDialog(BuildContext context, String title, void Function(String) onSubmit) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
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
                onSubmit(controller.text.trim());
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
    final library = ref.watch(wordbookLibraryProvider);
    final folders = library.folders.where((f) => f.parentId == folderId).toList();
    final wordbooks = library.wordbooks.where((b) => b.folderId == folderId).toList();

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: (folders.isEmpty && wordbooks.isEmpty)
          ? const Center(child: Text('まだ単語帳がありません'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ...folders.map(
                  (folder) => ListTile(
                    leading: const Icon(Icons.folder),
                    title: Text(folder.name),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(
                      '/wordbook/folder',
                      extra: {'folderId': folder.id, 'title': folder.name},
                    ),
                  ),
                ),
                ...wordbooks.map(
                  (book) => ListTile(
                    leading: const Icon(Icons.menu_book),
                    title: Text(book.name),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(
                      '/wordbook/detail',
                      extra: {'wordbookId': book.id, 'title': book.name},
                    ),
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateMenu(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }
}