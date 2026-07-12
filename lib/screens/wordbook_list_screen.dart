import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/wordbook_library_provider.dart';
import '../models/word.dart';
import '../models/wordbook.dart';
import '../models/folder.dart';
import '../services/app_session.dart';
import '../services/browser_context_menu_lease.dart';
import '../services/vocamine_api_client.dart';
import 'wordbook_screen.dart';

class WordbookListScreen extends ConsumerStatefulWidget {
  final String? folderId;
  final String title;

  const WordbookListScreen({super.key, this.folderId, this.title = '単語帳'});

  @override
  ConsumerState<WordbookListScreen> createState() => _WordbookListScreenState();
}

class _WordbookListScreenState extends ConsumerState<WordbookListScreen> {
  bool get _isRoot => widget.folderId == null;
  bool _loadingFolderStudy = false;

  Set<String> _descendantFolderIds(String rootId) {
    final folders = ref.read(wordbookLibraryProvider).folders;
    final ids = <String>{rootId};
    var changed = true;
    while (changed) {
      changed = false;
      for (final folder in folders) {
        if (folder.parentId != null &&
            ids.contains(folder.parentId) &&
            ids.add(folder.id)) {
          changed = true;
        }
      }
    }
    return ids;
  }

  Future<void> _studyFolder() async {
    final folderId = widget.folderId;
    if (folderId == null || _loadingFolderStudy) return;
    final library = ref.read(wordbookLibraryProvider);
    final folderIds = _descendantFolderIds(folderId);
    final books = library.wordbooks
        .where((book) => folderIds.contains(book.folderId))
        .toList();
    if (books.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('学習できる単語帳がありません')));
      return;
    }
    setState(() => _loadingFolderStudy = true);
    try {
      final userId = ref.read(appSessionProvider).userId;
      final lists = await Future.wait([
        for (final book in books)
          VocamineApiClient().fetchWordbook(
            userId: userId,
            isLearned: false,
            wordbookId: book.id,
          ),
      ]);
      final combined = <Word>[];
      for (var index = 0; index < books.length; index++) {
        final book = books[index];
        for (final word in lists[index]) {
          combined.add(word.copyWith(studyKey: '${book.id}:${word.id}'));
        }
      }
      if (!mounted) return;
      if (combined.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('未学習の単語がありません')));
        return;
      }
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => WordbookScreen(
            wordbookId: 'folder-combined:$folderId',
            title: widget.title,
            combinedWords: combined,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('フォルダの読み込みに失敗しました: $error')));
    } finally {
      if (mounted) setState(() => _loadingFolderStudy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    BrowserContextMenuLease.acquire();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    BrowserContextMenuLease.release();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant WordbookListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.folderId != widget.folderId) {
      Future.microtask(_load);
    }
  }

  void _load() {
    ref.read(wordbookLibraryProvider.notifier).load(force: true);
  }

  Future<void> _showBackgroundMenu(Offset position) async {
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        const PopupMenuItem(
          value: 'create_wordbook',
          child: ListTile(
            leading: Icon(Icons.library_add_outlined),
            title: Text('単語帳を作成'),
          ),
        ),
        const PopupMenuItem(
          value: 'create_folder',
          child: ListTile(
            leading: Icon(Icons.create_new_folder_outlined),
            title: Text('フォルダを作成'),
          ),
        ),
        if (!_isRoot)
          const PopupMenuItem(
            value: 'study_folder',
            child: ListTile(
              leading: Icon(Icons.school_outlined),
              title: Text('フォルダ内をまとめて学習'),
            ),
          ),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case 'create_wordbook':
        await _createWordbook();
      case 'create_folder':
        await _createFolder();
      case 'study_folder':
        await _studyFolder();
    }
  }

  Future<void> _createWordbook() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('単語帳を作成'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('作成'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    await ref
        .read(wordbookLibraryProvider.notifier)
        .createWordbook(name, folderId: widget.folderId);
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('フォルダを作成'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('作成'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    await ref
        .read(wordbookLibraryProvider.notifier)
        .createFolder(name, parentId: widget.folderId);
  }

  Future<void> _rename(Wordbook book) async {
    final controller = TextEditingController(text: book.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('名前の変更'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('変更'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == book.name || !mounted) return;
    final notifier = ref.read(wordbookLibraryProvider.notifier);
    try {
      if (book.sourceFolderId != null) {
        await notifier.renameFolder(book.sourceFolderId!, name);
      } else if (book.sourceMaterialId != null) {
        await notifier.renameWordbook(book.id, name);
      } else {
        await notifier.renameWordbook(book.id, name);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('名前の変更に失敗しました: $error')));
      }
    }
  }

  Future<void> _move(Wordbook book) async {
    final folders = ref.read(wordbookLibraryProvider).folders;
    final destination = await showDialog<String?>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('移動先のフォルダ'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, '__root__'),
            child: const ListTile(
              leading: Icon(Icons.home_outlined),
              title: Text('単語帳トップ'),
            ),
          ),
          for (final folder in folders.where(
            (folder) => folder.id != book.sourceFolderId,
          ))
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, folder.id),
              child: ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(folder.name),
              ),
            ),
        ],
      ),
    );
    if (destination == null || !mounted) return;
    final parentId = destination == '__root__' ? null : destination;
    final notifier = ref.read(wordbookLibraryProvider.notifier);
    try {
      if (book.sourceFolderId != null) {
        await notifier.moveFolder(book.sourceFolderId!, parentId);
      } else if (book.sourceMaterialId != null) {
        await notifier.moveWordbook(book.id, parentId);
      } else {
        await notifier.moveWordbook(book.id, parentId);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('移動に失敗しました: $error')));
      }
    }
  }

  Future<void> _delete(Wordbook book) async {
    final isFolder = book.sourceFolderId != null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isFolder ? 'フォルダを削除しますか？' : '単語帳を削除しますか？'),
        content: Text(
          isFolder ? '中の単語帳はトップへ移動します。' : '単語帳だけを削除します。教材と学習状態は削除されません。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final notifier = ref.read(wordbookLibraryProvider.notifier);
    try {
      if (book.sourceFolderId != null) {
        await notifier.deleteFolder(book.sourceFolderId!);
      } else if (book.sourceMaterialId != null) {
        await notifier.deleteWordbook(book.id);
      } else {
        await notifier.deleteWordbook(book.id);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('削除に失敗しました: $error')));
      }
    }
  }

  void _handleAction(String action, Wordbook book) {
    switch (action) {
      case 'rename':
        _rename(book);
        return;
      case 'move':
        _move(book);
        return;
      case 'delete':
        _delete(book);
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(appSessionProvider, (previous, next) {
      if (previous?.userId != next.userId && next.isLoggedIn) {
        Future.microtask(_load);
      }
    });
    final library = ref.watch(wordbookLibraryProvider);
    final horizontalPadding = MediaQuery.sizeOf(context).width >= 900
        ? 40.0
        : 16.0;
    final wordbooks = <Wordbook>[
      ...library.folders
          .where((folder) => folder.parentId == widget.folderId)
          .map(
            (folder) => Wordbook(
              id: 'folder:${folder.id}',
              name: folder.name,
              folderId: folder.parentId,
              sourceFolderId: folder.id,
            ),
          ),
      ...library.wordbooks.where((book) => book.folderId == widget.folderId),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton.icon(
            onPressed: _createWordbook,
            icon: const Icon(Icons.library_add_outlined),
            label: const Text('単語帳を作成'),
          ),
          TextButton.icon(
            onPressed: _createFolder,
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Text('フォルダを作成'),
          ),
          IconButton(
            tooltip: '更新',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapDown: (details) =>
            _showBackgroundMenu(details.globalPosition),
        child: RefreshIndicator(
          onRefresh: () async => _load(),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              24,
              horizontalPadding,
              32,
            ),
            children: [
              if (!_isRoot)
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 16,
                      ),
                      textStyle: Theme.of(context).textTheme.titleSmall,
                    ),
                    onPressed: _loadingFolderStudy ? null : _studyFolder,
                    icon: _loadingFolderStudy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.school_outlined),
                    label: const Text('フォルダ内をまとめて学習'),
                  ),
                ),
              if (!_isRoot) const SizedBox(height: 24),
              if (wordbooks.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    _isRoot ? '単語帳はまだありません' : 'このフォルダには教材がありません',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                Wrap(
                  spacing: 24,
                  runSpacing: 24,
                  children: [
                    ...wordbooks.map(
                      (book) => GestureDetector(
                        onSecondaryTapDown: (_) {},
                        child: _WordbookTile(
                          icon: book.sourceFolderId != null
                              ? Icons.folder_outlined
                              : book.sourceType == 'deleted_material'
                              ? Icons.delete_outline
                              : Icons.menu_book_outlined,
                          title: book.name,
                          subtitle: library.movingWordbookIds.contains(book.id)
                              ? '移動中…'
                              : book.sourceFolderId != null
                              ? '単語帳フォルダ'
                              : book.sourceType == 'deleted_material'
                              ? '削除後も単語を保持'
                              : '単語帳',
                          accentColor: book.sourceFolderId != null
                              ? const Color(0xFFC9A900)
                              : book.sourceType == 'deleted_material'
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.primary,
                          onTap: () {
                            if (library.movingWordbookIds.contains(book.id)) {
                              return;
                            }
                            if (book.sourceFolderId != null) {
                              context.push(
                                '/wordbook/folder',
                                extra: {
                                  'folderId': book.sourceFolderId,
                                  'title': book.name,
                                },
                              );
                              return;
                            }
                            context.push(
                              '/wordbook/detail',
                              extra: {
                                'wordbookId': book.id,
                                'title': book.name,
                              },
                            );
                          },
                          onMenuSelected:
                              library.movingWordbookIds.contains(book.id)
                              ? null
                              : (action) => _handleAction(action, book),
                          isLoading: library.movingWordbookIds.contains(
                            book.id,
                          ),
                          isFolder: book.sourceFolderId != null,
                          itemCount: book.sourceFolderId != null
                              ? _folderWordCount(book.sourceFolderId!, library)
                              : book.wordCount,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WordbookTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;
  final VoidCallback onTap;
  final ValueChanged<String>? onMenuSelected;
  final bool isLoading;
  final bool isFolder;
  final int itemCount;

  const _WordbookTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.onTap,
    this.onMenuSelected,
    this.isLoading = false,
    this.isFolder = false,
    this.itemCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final tileWidth = width >= 1180
        ? 330.0
        : width >= 760
        ? 300.0
        : width - 48;
    return SizedBox(
      width: tileWidth,
      height: 180,
      child: isFolder
          ? Stack(
              clipBehavior: Clip.none,
              children: [
                if (itemCount > 0)
                  Positioned(
                    left: 10,
                    right: 10,
                    top: 8,
                    child: Container(
                      height: 152,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: const Color(0xFFC4C6CD)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x180B1C2C),
                            blurRadius: 20,
                            offset: Offset(0, 7),
                          ),
                        ],
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: PhysicalShape(
                    clipper: const _FolderCardClipper(),
                    color: const Color(0xFFD4E3FF),
                    shadowColor: const Color(0x990B1C2C),
                    elevation: 10,
                    child: Material(
                      type: MaterialType.transparency,
                      child: CustomPaint(
                        foregroundPainter: const _FolderOutlinePainter(),
                        child: _buildCardContent(context),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : Card(
              color: isFolder ? const Color(0xFFD4E3FF) : Colors.white,
              shadowColor: const Color(0x520B1C2C),
              elevation: 7,
              child: _buildCardContent(context),
            ),
    );
  }

  Widget _buildCardContent(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.zero,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          isFolder ? 20 : 0,
          isFolder ? 38 : 0,
          isFolder ? 16 : 0,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isFolder)
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (onMenuSelected != null)
                      PopupMenuButton<String>(
                        tooltip: '単語帳の操作',
                        onSelected: onMenuSelected,
                        itemBuilder: _wordbookMenuItems,
                      ),
                  ],
                ),
              )
            else
              Expanded(
                child: Row(
                  children: [
                    SizedBox(
                      width: 104,
                      child: OverflowBox(
                        minHeight: 180,
                        maxHeight: 180,
                        alignment: Alignment.topCenter,
                        child: Container(
                          width: 104,
                          height: 180,
                          color: const Color(0xFF1A2B3C),
                          alignment: Alignment.center,
                          child: const Text(
                            'WORD BOOK',
                            style: TextStyle(
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFD2E4FB),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            subtitle,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                    if (onMenuSelected != null)
                      PopupMenuButton<String>(
                        tooltip: '単語帳の操作',
                        onSelected: onMenuSelected,
                        itemBuilder: _wordbookMenuItems,
                      ),
                  ],
                ),
              ),
            const Divider(height: 1),
            Padding(
              padding: EdgeInsets.fromLTRB(isFolder ? 20 : 124, 12, 20, 12),
              child: Text(
                isFolder ? '$itemCount語' : '$itemCount語',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: const Color(0xFF44474C),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<PopupMenuEntry<String>> _wordbookMenuItems(
    BuildContext context,
  ) => const [
    PopupMenuItem(
      value: 'rename',
      child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('名前の変更')),
    ),
    PopupMenuItem(
      value: 'move',
      child: ListTile(
        leading: Icon(Icons.drive_file_move_outline),
        title: Text('移動'),
      ),
    ),
    PopupMenuDivider(),
    PopupMenuItem(
      value: 'delete',
      child: ListTile(leading: Icon(Icons.delete_outline), title: Text('削除')),
    ),
  ];
}

class _FolderCardClipper extends CustomClipper<Path> {
  const _FolderCardClipper();

  @override
  Path getClip(Size size) => Path()
    ..moveTo(0, 24)
    ..lineTo(size.width * .38, 24)
    ..lineTo(size.width * .46, 0)
    ..lineTo(size.width, 0)
    ..lineTo(size.width, size.height)
    ..lineTo(0, size.height)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _FolderOutlinePainter extends CustomPainter {
  const _FolderOutlinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      const _FolderCardClipper().getClip(size),
      Paint()
        ..color = const Color(0xFF68ABFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Set<String> _descendantFolderIds(String folderId, List<AppFolder> folders) {
  final ids = <String>{folderId};
  var changed = true;
  while (changed) {
    changed = false;
    for (final folder in folders) {
      if (folder.parentId != null &&
          ids.contains(folder.parentId) &&
          ids.add(folder.id)) {
        changed = true;
      }
    }
  }
  return ids;
}

int _folderWordCount(String folderId, WordbookLibraryState library) {
  final folderIds = _descendantFolderIds(folderId, library.folders);
  return library.wordbooks
      .where((book) => folderIds.contains(book.folderId))
      .fold(0, (total, book) => total + book.wordCount);
}
