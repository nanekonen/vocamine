import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../models/material_item.dart';
import '../providers/material_library_provider.dart';
import '../services/vocamine_api_client.dart';

class MaterialsScreen extends ConsumerStatefulWidget {
  final String? folderId;
  final String title;

  const MaterialsScreen({super.key, this.folderId, this.title = '教材'});

  @override
  ConsumerState<MaterialsScreen> createState() => _MaterialsScreenState();
}

class _MaterialsScreenState extends ConsumerState<MaterialsScreen> {
  final _api = VocamineApiClient();
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(materialLibraryProvider.notifier).load();
    });
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

    setState(() => _isImporting = true);
    try {
      final bytes = await image.readAsBytes();
      final extraction = await _api.extractTextFromImage(
        bytes: bytes,
        filename: image.name,
      );
      if (!context.mounted) return;
      final materialId = await ref
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
      if (!context.mounted) return;
      context.push(
        '/materials/detail',
        extra: {'materialId': materialId, 'title': title},
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('OCRに失敗しました: $error')));
    } finally {
      if (mounted) {
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

    setState(() => _isImporting = true);
    try {
      final extraction = await _api.extractTextFromPdf(
        bytes: bytes,
        filename: file.name,
      );
      if (!context.mounted) return;
      final materialId = await ref
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
      if (!context.mounted) return;
      context.push(
        '/materials/detail',
        extra: {'materialId': materialId, 'title': title},
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('PDFの読み込みに失敗しました: $error')));
    } finally {
      if (mounted) {
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
        final percent = (result.coverageRate * 100).round();
        return '$date  カバー率 $percent%  未知 ${result.unknownCount}';
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(materialLibraryProvider);
    final folders = library.folders
        .where((f) => f.parentId == widget.folderId)
        .toList();
    final materials = library.materials
        .where((m) => m.folderId == widget.folderId)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
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
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 96),
              children: [
                _SectionHeader(
                  icon: Icons.library_books_outlined,
                  title: 'Materials Repository',
                  subtitle: '読み込んだ教材',
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    ...folders.map(
                      (folder) => _LibraryTile(
                        icon: Icons.folder_outlined,
                        title: folder.name,
                        subtitle: 'フォルダ',
                        accentColor: const Color(0xFFC4934E),
                        onTap: () => context.push(
                          '/materials/folder',
                          extra: {'folderId': folder.id, 'title': folder.name},
                        ),
                      ),
                    ),
                    ...materials.map(
                      (material) => _LibraryTile(
                        icon: Icons.description_outlined,
                        title: material.title,
                        subtitle: _materialSubtitle(material, library),
                        accentColor: Theme.of(context).colorScheme.primary,
                        onTap: () => context.push(
                          '/materials/detail',
                          extra: {
                            'materialId': material.id,
                            'title': material.title,
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isImporting ? null : () => _showImportMenu(context, ref),
        icon: _isImporting
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.photo_library),
        label: Text(_isImporting ? '読み込み中' : '教材を読み込む'),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LibraryTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;
  final VoidCallback onTap;

  const _LibraryTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.onTap,
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
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.26),
                    ),
                  ),
                  child: Icon(icon, color: accentColor, size: 22),
                ),
                const SizedBox(width: 14),
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
                      const SizedBox(height: 8),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
