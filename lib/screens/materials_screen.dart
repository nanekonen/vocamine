import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../models/material_item.dart';
import '../models/folder.dart';
import '../providers/material_library_provider.dart';
import '../services/browser_context_menu_lease.dart';
import '../services/app_session.dart';
import '../services/vocamine_api_client.dart';
import '../widgets/square_progress_indicator.dart';

class _PendingMaterialImport {
  final String title;
  final String? folderId;

  const _PendingMaterialImport({required this.title, required this.folderId});
}

Set<String> _materialDescendantFolderIds(
  String folderId,
  List<AppFolder> folders,
) {
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

int _materialFolderCount(String folderId, MaterialLibraryState library) {
  final folderIds = _materialDescendantFolderIds(folderId, library.folders);
  return library.materials
      .where((material) => folderIds.contains(material.folderId))
      .length;
}

class MaterialsScreen extends ConsumerStatefulWidget {
  final String? folderId;
  final String title;
  final int importRequest;

  const MaterialsScreen({
    super.key,
    this.folderId,
    this.title = '教材',
    this.importRequest = 0,
  });

  @override
  ConsumerState<MaterialsScreen> createState() => _MaterialsScreenState();
}

class _MaterialsScreenState extends ConsumerState<MaterialsScreen> {
  final _api = VocamineApiClient();
  bool _isImporting = false;
  final Map<int, _PendingMaterialImport> _pendingImports = {};
  int _nextPendingImportId = 0;

  int _showPendingImport(String title) {
    final id = _nextPendingImportId++;
    setState(() {
      _pendingImports[id] = _PendingMaterialImport(
        title: title,
        folderId: widget.folderId,
      );
    });
    return id;
  }

  void _hidePendingImport(int id) {
    if (!mounted) return;
    setState(() => _pendingImports.remove(id));
  }

  @override
  void initState() {
    super.initState();
    BrowserContextMenuLease.acquire();
    Future.microtask(() {
      ref.read(materialLibraryProvider.notifier).load();
    });
  }

  @override
  void didUpdateWidget(covariant MaterialsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.importRequest != oldWidget.importRequest) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showImportMenu(context, ref);
      });
    }
  }

  @override
  void dispose() {
    BrowserContextMenuLease.release();
    super.dispose();
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
      items: const [
        PopupMenuItem(
          value: 'import',
          child: ListTile(
            leading: Icon(Icons.upload_file_outlined),
            title: Text('教材を読み込む'),
          ),
        ),
        PopupMenuItem(
          value: 'create_folder',
          child: ListTile(
            leading: Icon(Icons.create_new_folder_outlined),
            title: Text('フォルダを作成'),
          ),
        ),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case 'import':
        await _showImportMenu(context, ref);
      case 'create_folder':
        _createFolder(context, ref);
    }
  }

  String _mimeTypeForName(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  bool _titleExists(String title) {
    final normalized = title.trim().toLowerCase();
    return ref
        .read(materialLibraryProvider)
        .materials
        .any((material) => material.title.trim().toLowerCase() == normalized);
  }

  Future<String?> _askMaterialTitle(String defaultTitle) async {
    final controller = TextEditingController(text: defaultTitle);
    String? errorText;
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('教材名を入力'),
              content: TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: '教材名',
                  errorText: errorText,
                ),
                onSubmitted: (_) {
                  final title = controller.text.trim();
                  if (title.isEmpty) {
                    setDialogState(() => errorText = '教材名を入力してください');
                    return;
                  }
                  if (_titleExists(title)) {
                    setDialogState(() => errorText = '同じ名前の教材は登録できません');
                    return;
                  }
                  Navigator.pop(dialogContext, title);
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('キャンセル'),
                ),
                FilledButton(
                  onPressed: () {
                    final title = controller.text.trim();
                    if (title.isEmpty) {
                      setDialogState(() => errorText = '教材名を入力してください');
                      return;
                    }
                    if (_titleExists(title)) {
                      setDialogState(() => errorText = '同じ名前の教材は登録できません');
                      return;
                    }
                    Navigator.pop(dialogContext, title);
                  },
                  child: const Text('登録'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _addImageMaterial(BuildContext context, WidgetRef ref) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;
    final title = await _askMaterialTitle(image.name);
    if (title == null) return;

    final pendingId = _showPendingImport(title);
    setState(() => _isImporting = true);
    try {
      final bytes = await image.readAsBytes();
      final extraction = await _api.extractTextFromImage(
        bytes: bytes,
        filename: image.name,
      );
      if (!context.mounted) return;
      await ref
          .read(materialLibraryProvider.notifier)
          .addMaterial(
            title,
            extraction.text,
            sourceBytes: bytes,
            sourceMimeType: image.mimeType ?? _mimeTypeForName(image.name),
            sourceWordBoxes: extraction.wordBoxes,
            folderId: widget.folderId,
            analyzeImmediately: true,
          );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('OCRに失敗しました: $error')));
    } finally {
      if (mounted) {
        _hidePendingImport(pendingId);
        setState(() => _isImporting = false);
      }
    }
  }

  Future<void> _addPdfMaterial(BuildContext context, WidgetRef ref) async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    final file = picked?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;
    final title = await _askMaterialTitle(file.name);
    if (title == null) return;

    final pendingId = _showPendingImport(title);
    setState(() => _isImporting = true);
    try {
      final extraction = await _api.extractTextFromPdf(
        bytes: bytes,
        filename: file.name,
      );
      if (!context.mounted) return;
      await ref
          .read(materialLibraryProvider.notifier)
          .addMaterial(
            title,
            extraction.text,
            sourceBytes: bytes,
            sourceMimeType: _mimeTypeForName(file.name),
            sourcePageImages: extraction.pageImages,
            sourceWordBoxes: extraction.wordBoxes,
            folderId: widget.folderId,
            analyzeImmediately: true,
          );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('PDFの読み込みに失敗しました: $error')));
    } finally {
      if (mounted) {
        _hidePendingImport(pendingId);
        setState(() => _isImporting = false);
      }
    }
  }

  Future<void> _showImportMenu(BuildContext context, WidgetRef ref) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.image),
                title: const Text('画像を読み込む'),
                onTap: () => Navigator.pop(context, 'image'),
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf),
                title: const Text('PDFを読み込む'),
                onTap: () => Navigator.pop(context, 'pdf'),
              ),
            ],
          ),
        );
      },
    );
    if (!context.mounted || choice == null) return;
    if (choice == 'image') {
      await _addImageMaterial(context, ref);
    } else if (choice == 'pdf') {
      await _addPdfMaterial(context, ref);
    }
  }

  Future<void> _deleteMaterial(MaterialItem material) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('教材を削除しますか？'),
        content: Text(
          '「${material.title}」を削除します。\n'
          'この教材から登録した単語は「削除した教材」に残ります。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(materialLibraryProvider.notifier)
          .deleteMaterial(material.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('教材を削除しました')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('教材の削除に失敗しました: $error')));
    }
  }

  Future<void> _renameMaterial(MaterialItem material) async {
    final controller = TextEditingController(text: material.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('名前の変更'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '教材名'),
        ),
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
    if (title == null || title.isEmpty || title == material.title || !mounted) {
      return;
    }
    try {
      await ref
          .read(materialLibraryProvider.notifier)
          .renameMaterial(material.id, title);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('名前の変更に失敗しました: $error')));
      }
    }
  }

  Future<void> _moveMaterial(MaterialItem material) async {
    final library = ref.read(materialLibraryProvider);
    final folderId = await showDialog<String?>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('移動先のフォルダ'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, '__root__'),
            child: const ListTile(
              leading: Icon(Icons.home_outlined),
              title: Text('教材トップ'),
            ),
          ),
          for (final folder in library.folders)
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
    if (folderId == null || !mounted) return;
    try {
      await ref
          .read(materialLibraryProvider.notifier)
          .moveMaterial(material.id, folderId == '__root__' ? null : folderId);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('移動に失敗しました: $error')));
      }
    }
  }

  Future<void> _addPages(MaterialItem material) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('画像を追加'),
              onTap: () => Navigator.pop(context, 'image'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('PDFを追加'),
              onTap: () => Navigator.pop(context, 'pdf'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    setState(() => _isImporting = true);
    try {
      var text = '';
      final images = <Uint8List>[];
      final boxes = <SourceWordBox>[];
      if (choice == 'pdf') {
        final picked = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf'],
          withData: true,
        );
        final file = picked?.files.single;
        if (file?.bytes == null) return;
        final extraction = await _api.extractTextFromPdf(
          bytes: file!.bytes!,
          filename: file.name,
        );
        text = extraction.text;
        images.addAll(extraction.pageImages);
        boxes.addAll(extraction.wordBoxes);
      } else {
        final picked = await ImagePicker().pickMultiImage();
        if (picked.isEmpty) return;
        for (var index = 0; index < picked.length; index++) {
          final file = picked[index];
          final bytes = await file.readAsBytes();
          final extraction = await _api.extractTextFromImage(
            bytes: bytes,
            filename: file.name,
          );
          final textOffset = text.isEmpty ? 0 : text.length + 2;
          text += '${text.isEmpty ? '' : '\n\n'}${extraction.text}';
          images.add(bytes);
          boxes.addAll(
            extraction.wordBoxes.map(
              (box) => SourceWordBox(
                text: box.text,
                pageIndex: index,
                start: box.start == null ? null : box.start! + textOffset,
                end: box.end == null ? null : box.end! + textOffset,
                left: box.left,
                top: box.top,
                width: box.width,
                height: box.height,
              ),
            ),
          );
        }
      }
      if (!mounted) return;
      await ref
          .read(materialLibraryProvider.notifier)
          .appendPages(
            material.id,
            extractedText: text,
            pageImages: images,
            wordBoxes: boxes,
          );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('ページを追加しました')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ページの追加に失敗しました: $error')));
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  void _handleMaterialAction(String action, MaterialItem material) {
    switch (action) {
      case 'rename':
        _renameMaterial(material);
        return;
      case 'move':
        _moveMaterial(material);
        return;
      case 'pages':
        _addPages(material);
        return;
      case 'delete':
        _deleteMaterial(material);
        return;
    }
  }

  Future<void> _renameFolder(AppFolder folder) async {
    final controller = TextEditingController(text: folder.name);
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
    if (name == null || name.isEmpty || name == folder.name || !mounted) return;
    try {
      await ref
          .read(materialLibraryProvider.notifier)
          .renameFolder(folder.id, name);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('名前の変更に失敗しました: $error')));
      }
    }
  }

  Future<void> _moveFolder(AppFolder folder) async {
    final folders = ref.read(materialLibraryProvider).folders;
    final parentId = await showDialog<String?>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('移動先のフォルダ'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, '__root__'),
            child: const ListTile(
              leading: Icon(Icons.home_outlined),
              title: Text('教材トップ'),
            ),
          ),
          for (final candidate in folders.where((item) => item.id != folder.id))
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, candidate.id),
              child: ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(candidate.name),
              ),
            ),
        ],
      ),
    );
    if (parentId == null || !mounted) return;
    try {
      await ref
          .read(materialLibraryProvider.notifier)
          .moveFolder(folder.id, parentId == '__root__' ? null : parentId);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('移動に失敗しました: $error')));
      }
    }
  }

  Future<void> _deleteFolder(AppFolder folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('フォルダを削除しますか？'),
        content: const Text('フォルダ内の教材は教材トップへ移動します。'),
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
    try {
      await ref.read(materialLibraryProvider.notifier).deleteFolder(folder.id);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('フォルダの削除に失敗しました: $error')));
      }
    }
  }

  void _handleFolderAction(String action, AppFolder folder) {
    switch (action) {
      case 'rename':
        _renameFolder(folder);
        return;
      case 'move':
        _moveFolder(folder);
        return;
      case 'delete':
        _deleteFolder(folder);
        return;
    }
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
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                await ref
                    .read(materialLibraryProvider.notifier)
                    .createFolder(
                      controller.text.trim(),
                      parentId: widget.folderId,
                    );
              }
              if (!context.mounted) return;
              Navigator.pop(context);
            },
            child: const Text('作成'),
          ),
        ],
      ),
    );
  }

  String _materialSubtitle(
    MaterialItem material,
    MaterialLibraryState library,
  ) {
    final date =
        '${material.createdAt.year}/${material.createdAt.month}/${material.createdAt.day}';
    final analysis = library.analyses[material.id];
    if (analysis == null) {
      return date;
    }
    return analysis.when(
      loading: () => '$date  解析中',
      error: (_, _) => '$date  解析エラー',
      data: (result) {
        return date;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(materialLibraryProvider);
    final horizontalPadding = MediaQuery.sizeOf(context).width >= 900
        ? 40.0
        : 16.0;
    final folders = library.folders
        .where((f) => f.parentId == widget.folderId)
        .toList();
    final materials = library.materials
        .where((m) => m.folderId == widget.folderId)
        .toList();
    final pendingImports = _pendingImports.values
        .where((pending) => pending.folderId == widget.folderId)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('教材を読み込む'),
            onPressed: _isImporting
                ? null
                : () => _showImportMenu(context, ref),
          ),
          TextButton.icon(
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Text('フォルダを作成'),
            onPressed: () => _createFolder(context, ref),
          ),
        ],
      ),
      body: ColoredBox(
        color: const Color(0xFFF7F9FB),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onSecondaryTapDown: (details) =>
              _showBackgroundMenu(details.globalPosition),
          child:
              (folders.isEmpty && materials.isEmpty && pendingImports.isEmpty)
              ? const Center(child: Text('教材がまだありません'))
              : ListView(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    24,
                    horizontalPadding,
                    96,
                  ),
                  children: [
                    Wrap(
                      spacing: 24,
                      runSpacing: 24,
                      children: [
                        ...folders.map(
                          (folder) => GestureDetector(
                            onSecondaryTapDown: (_) {},
                            child: _LibraryTile(
                              icon: Icons.folder_outlined,
                              title: folder.name,
                              subtitle: 'フォルダ',
                              accentColor: const Color(0xFFC9A900),
                              onTap: () => context.push(
                                '/materials/folder',
                                extra: {
                                  'folderId': folder.id,
                                  'title': folder.name,
                                },
                              ),
                              onMenuSelected: (action) =>
                                  _handleFolderAction(action, folder),
                              isFolder: true,
                              itemCount: _materialFolderCount(
                                folder.id,
                                library,
                              ),
                            ),
                          ),
                        ),
                        ...pendingImports.map(
                          (pending) => _LibraryTile(
                            icon: Icons.hourglass_top,
                            title: pending.title,
                            subtitle: '教材読み込み中…',
                            accentColor: Theme.of(
                              context,
                            ).colorScheme.secondary,
                            onTap: () {},
                            isLoading: true,
                            itemCount: 0,
                          ),
                        ),
                        ...materials.map(
                          (material) => GestureDetector(
                            onSecondaryTapDown: (_) {},
                            child: _LibraryTile(
                              icon:
                                  library.movingMaterialIds.contains(
                                    material.id,
                                  )
                                  ? Icons.drive_file_move_outline
                                  : Icons.description_outlined,
                              title: material.title,
                              subtitle:
                                  library.movingMaterialIds.contains(
                                    material.id,
                                  )
                                  ? '移動中…'
                                  : _materialSubtitle(material, library),
                              accentColor:
                                  library.analyses[material.id] is AsyncError
                                  ? Theme.of(context).colorScheme.error
                                  : Theme.of(context).colorScheme.secondary,
                              onTap:
                                  library.movingMaterialIds.contains(
                                    material.id,
                                  )
                                  ? () {}
                                  : () {
                                      final userId = ref
                                          .read(appSessionProvider)
                                          .userId;
                                      unawaited(
                                        _api.updateRecentMaterial(
                                          userId: userId,
                                          materialId: material.id,
                                        ),
                                      );
                                      context.push(
                                        '/materials/detail',
                                        extra: {
                                          'materialId': material.id,
                                          'title': material.title,
                                        },
                                      );
                                    },
                              onMenuSelected:
                                  library.movingMaterialIds.contains(
                                    material.id,
                                  )
                                  ? null
                                  : (action) =>
                                        _handleMaterialAction(action, material),
                              showPageAction: true,
                              isLoading: library.movingMaterialIds.contains(
                                material.id,
                              ),
                              coveragePercent:
                                  library.analyses[material.id]?.value == null
                                  ? null
                                  : (library
                                                .analyses[material.id]!
                                                .value!
                                                .coverageRate *
                                            100)
                                        .round(),
                              unknownCount: library
                                  .analyses[material.id]
                                  ?.value
                                  ?.unknownCount,
                              itemCount: 1,
                              previewBytes: material.sourcePageImages.isNotEmpty
                                  ? material.sourcePageImages.first
                                  : null,
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

class _LibraryTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;
  final VoidCallback onTap;
  final ValueChanged<String>? onMenuSelected;
  final bool showPageAction;
  final bool isLoading;
  final int? coveragePercent;
  final int? unknownCount;
  final bool isFolder;
  final int itemCount;
  final Uint8List? previewBytes;

  const _LibraryTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.onTap,
    this.onMenuSelected,
    this.showPageAction = false,
    this.isLoading = false,
    this.coveragePercent,
    this.unknownCount,
    this.isFolder = false,
    this.itemCount = 0,
    this.previewBytes,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final tileWidth = width >= 1180
        ? 360.0
        : width >= 760
        ? 330.0
        : width - 48;
    if (isFolder) {
      return SizedBox(
        width: tileWidth,
        height: 210,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (itemCount > 0)
              Positioned(
                left: 10,
                right: 10,
                top: 8,
                child: Container(
                  height: 180,
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
                clipper: const _MaterialFolderClipper(),
                color: const Color(0xFFD4E3FF),
                shadowColor: const Color(0x990B1C2C),
                elevation: 10,
                child: CustomPaint(
                  foregroundPainter: const _MaterialFolderOutlinePainter(),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onTap,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 38, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                ),
                                if (onMenuSelected != null)
                                  PopupMenuButton<String>(
                                    tooltip: '教材の操作',
                                    onSelected: onMenuSelected,
                                    itemBuilder: _materialMenuItems,
                                  ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              '$itemCount件の教材',
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return SizedBox(
      width: tileWidth,
      height: 210,
      child: Card(
        color: Colors.white,
        shadowColor: const Color(0x520B1C2C),
        elevation: 7,
        child: InkWell(
          borderRadius: BorderRadius.zero,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 104,
                      height: 76,
                      child: Transform.translate(
                        offset: const Offset(0, -24),
                        child: OverflowBox(
                          minWidth: 128,
                          maxWidth: 128,
                          minHeight: 210,
                          maxHeight: 210,
                          alignment: Alignment.topRight,
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF2F4F6),
                              borderRadius: BorderRadius.zero,
                              border: Border.all(
                                color: const Color(0xFFDDE3EA),
                              ),
                            ),
                            child: isLoading
                                ? Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: accentColor,
                                    ),
                                  )
                                : previewBytes != null
                                ? ClipRect(
                                    child: Transform.scale(
                                      scale: 1.75,
                                      alignment: Alignment.topLeft,
                                      child: Image.memory(
                                        previewBytes!,
                                        width: 128,
                                        height: 210,
                                        fit: BoxFit.cover,
                                        alignment: Alignment.topLeft,
                                      ),
                                    ),
                                  )
                                : const Center(
                                    child: Text(
                                      'MATERIAL',
                                      style: TextStyle(
                                        letterSpacing: 1.1,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF38485A),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
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
                        color: Colors.white,
                        iconColor: const Color(0xFF44474C),
                        tooltip: '教材の操作',
                        onSelected: onMenuSelected,
                        itemBuilder: _materialMenuItems,
                      ),
                  ],
                ),
                const Spacer(),
                const Padding(
                  padding: EdgeInsets.only(left: 112),
                  child: Divider(color: Color(0xFFDDE3EA)),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(left: 112),
                  child: Row(
                    children: [
                      SquareProgressIndicator(
                        value: (coveragePercent ?? 0) / 100,
                        size: 64,
                        strokeWidth: 6,
                        color: const Color(0xFF0060AC),
                        backgroundColor: const Color(0xFFDDE3EA),
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: coveragePercent == null
                                    ? '--'
                                    : '$coveragePercent',
                                style: const TextStyle(
                                  color: Color(0xFF0060AC),
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const TextSpan(
                                text: '%',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '習得語彙率: ${coveragePercent ?? '--'}%',
                              style: const TextStyle(
                                color: Color(0xFF041627),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '未知語数: ${unknownCount ?? '--'}',
                              style: const TextStyle(color: Color(0xFF44474C)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<PopupMenuEntry<String>> _materialMenuItems(BuildContext context) => [
    const PopupMenuItem(
      value: 'rename',
      child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('名前の変更')),
    ),
    const PopupMenuItem(
      value: 'move',
      child: ListTile(
        leading: Icon(Icons.drive_file_move_outline),
        title: Text('移動'),
      ),
    ),
    if (showPageAction)
      const PopupMenuItem(
        value: 'pages',
        child: ListTile(
          leading: Icon(Icons.note_add_outlined),
          title: Text('ページの追加'),
        ),
      ),
    const PopupMenuDivider(),
    const PopupMenuItem(
      value: 'delete',
      child: ListTile(leading: Icon(Icons.delete_outline), title: Text('削除')),
    ),
  ];
}

class _MaterialFolderClipper extends CustomClipper<Path> {
  const _MaterialFolderClipper();

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

class _MaterialFolderOutlinePainter extends CustomPainter {
  const _MaterialFolderOutlinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = const _MaterialFolderClipper().getClip(size);
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF68ABFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
