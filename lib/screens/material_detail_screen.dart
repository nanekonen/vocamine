import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/lexical_analysis.dart';
import '../models/material_item.dart';
import '../models/word_lookup.dart';
import '../providers/material_library_provider.dart';
import '../providers/words_provider.dart';
import '../providers/wordbook_library_provider.dart';
import '../services/app_session.dart';
import '../services/app_messenger.dart';
import '../services/vocamine_api_client.dart';
import '../utils/part_of_speech_label.dart';
import '../widgets/square_progress_indicator.dart';
import '../widgets/academic_tag.dart';

enum _MaterialDisplayMode { original, text }

enum _SidePanelMode { selection, unknown, untranslated, known, all }

final Map<String, String?> _materialDefaultWordbookCache = {};
final Map<String, Set<int>> _registeredMeaningIdsByMaterial = {};
final Map<String, Future<String?>> _materialDefaultWordbookLoads = {};

String _wordbookName(BuildContext context, String wordbookId) {
  final library = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(wordbookLibraryProvider);
  for (final wordbook in library.wordbooks) {
    if (wordbook.id == wordbookId) return wordbook.name;
  }
  return '選択した単語帳';
}

Future<String?> _preloadMaterialDefaultWordbook(
  MaterialItem material,
  String userId,
) {
  if (material.defaultWordbookId != null) {
    _materialDefaultWordbookCache[material.id] = material.defaultWordbookId;
    return Future.value(material.defaultWordbookId);
  }
  return _materialDefaultWordbookLoads.putIfAbsent(material.id, () async {
    try {
      final value = await VocamineApiClient().getMaterialDefaultWordbook(
        userId: userId,
        materialId: material.id,
      );
      _materialDefaultWordbookCache[material.id] = value;
      return value;
    } catch (_) {
      return null;
    }
  });
}

final _englishWordPattern = RegExp(r"[A-Za-z]+(?:['’-][A-Za-z]+)*");

bool shouldTreatTextAsLexicalTarget(String text) {
  return _englishWordPattern.hasMatch(text) &&
      _englishWordPattern.firstMatch(text)?.group(0) == text;
}

bool canDisplayOriginalSource(MaterialItem material) {
  return material.sourceMimeType != null &&
      (material.sourceBytes != null || material.sourcePageImages.isNotEmpty);
}

Future<String?> _selectWordbookForMaterial(
  BuildContext context,
  MaterialItem material, {
  bool forceSelection = false,
  Rect? anchorRect,
  Object? tapRegionGroupId,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final userId = container.read(appSessionProvider).userId;
  final api = VocamineApiClient();
  if (!forceSelection) {
    final saved = _materialDefaultWordbookCache.containsKey(material.id)
        ? _materialDefaultWordbookCache[material.id]
        : material.defaultWordbookId;
    if (saved != null) {
      return saved;
    }
    final preloaded = await _preloadMaterialDefaultWordbook(material, userId);
    if (preloaded != null) return preloaded;
  }
  if (!context.mounted) return null;
  Widget actionDialog(BuildContext dialogContext) => AlertDialog(
    title: const Text('単語帳への登録'),
    content: const Text('この教材から単語を登録する単語帳を選んでください。'),
    actions: [
      OutlinedButton.icon(
        onPressed: () => Navigator.pop(dialogContext, 'existing'),
        icon: const Icon(Icons.menu_book_outlined),
        label: const Text('既存の単語帳を選択'),
      ),
      FilledButton.icon(
        onPressed: () => Navigator.pop(dialogContext, 'create'),
        icon: const Icon(Icons.add),
        label: const Text('新しい単語帳を作成'),
      ),
    ],
  );
  final action = anchorRect == null
      ? await showDialog<String>(context: context, builder: actionDialog)
      : await _showAnchoredPanel<String>(
          context,
          anchorRect: anchorRect,
          builder: actionDialog,
          tapRegionGroupId: tapRegionGroupId,
        );
  if (action == null || !context.mounted) return null;
  String? wordbookId;
  if (action == 'existing') {
    await container.read(wordbookLibraryProvider.notifier).load();
    final library = container.read(wordbookLibraryProvider);
    if (!context.mounted) return null;
    Widget existingDialog(BuildContext dialogContext) => SimpleDialog(
      title: const Text('既存の単語帳を選択'),
      children: [
        if (library.wordbooks.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('単語帳がまだありません'),
          ),
        for (final book in library.wordbooks)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, book.id),
            child: ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: Text(book.name),
            ),
          ),
      ],
    );
    wordbookId = anchorRect == null
        ? await showDialog<String>(context: context, builder: existingDialog)
        : await _showAnchoredPanel<String>(
            context,
            anchorRect: anchorRect,
            builder: existingDialog,
            tapRegionGroupId: tapRegionGroupId,
          );
    if (wordbookId == null || !context.mounted) return null;
  } else {
    final controller = TextEditingController(text: material.title);
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
    Widget createDialog(BuildContext dialogContext) => AlertDialog(
      title: const Text('新しい単語帳'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: '単語帳名'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
          child: const Text('作成'),
        ),
      ],
    );
    final name = anchorRect == null
        ? await showDialog<String>(context: context, builder: createDialog)
        : await _showAnchoredPanel<String>(
            context,
            anchorRect: anchorRect,
            builder: createDialog,
            tapRegionGroupId: tapRegionGroupId,
          );
    controller.dispose();
    if (name == null || name.isEmpty || !context.mounted) return null;
    final book = await container
        .read(wordbookLibraryProvider.notifier)
        .createWordbook(name);
    wordbookId = book.id;
  }
  // 「別の単語帳に登録」は今回の登録先だけを変更し、教材の既定先は
  // 変更しない。通常の初回選択時だけ既定の単語帳として保存する。
  if (!forceSelection) {
    await api.setMaterialDefaultWordbook(
      userId: userId,
      materialId: material.id,
      wordbookId: wordbookId,
    );
    _materialDefaultWordbookCache[material.id] = wordbookId;
  }
  return wordbookId;
}

Future<T?> _showAnchoredPanel<T>(
  BuildContext context, {
  required Rect anchorRect,
  required WidgetBuilder builder,
  Object? tapRegionGroupId,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '閉じる',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 100),
    pageBuilder: (dialogContext, _, _) {
      final screen = MediaQuery.sizeOf(dialogContext);
      const panelWidth = 340.0;
      const gap = 12.0;
      final hasRoomRight = anchorRect.right + gap + panelWidth <= screen.width;
      final left = hasRoomRight
          ? anchorRect.right + gap
          : math.max(gap, anchorRect.left - gap - panelWidth);
      final top = anchorRect.top
          .clamp(gap, math.max(gap, screen.height - 480.0))
          .toDouble();
      return Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            width: panelWidth,
            child: TapRegion(
              groupId: tapRegionGroupId,
              child: builder(dialogContext),
            ),
          ),
        ],
      );
    },
    transitionBuilder: (_, animation, _, child) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween(begin: 0.98, end: 1.0).animate(animation),
        child: child,
      ),
    ),
  );
}

class _WordLookupCache {
  final Map<String, WordLookupResult> _results = {};
  Future<void>? _storedLoading;
  Future<void>? _loading;
  int revision = 0;

  String _normalizedWord(String value) =>
      value.trim().toLowerCase().replaceAll('’', "'");

  Future<void> loadStoredMeanings(
    Iterable<LexicalItemResult> items, {
    required String userId,
    VoidCallback? onStoredLoaded,
  }) {
    final current = _loading;
    if (current != null) return current;

    final itemList = items.toList();
    final storedLoading = _fetchAndReplace(
      itemList,
      userId: userId,
      enrichMissing: false,
    );
    _storedLoading = storedLoading;
    final loading = _finishInitialLoad(
      itemList,
      storedLoading,
      userId,
      onStoredLoaded,
    );
    _loading = loading;
    return loading;
  }

  Future<void> reloadStoredMeanings(
    Iterable<LexicalItemResult> items, {
    required String userId,
  }) {
    _results.clear();
    _loading = null;
    final loading = _fetchAndReplace(
      items.toList(),
      userId: userId,
      enrichMissing: false,
    );
    _storedLoading = loading;
    _loading = loading;
    return loading;
  }

  Set<int> get missingJapaneseMeaningIds => _results.values
      .expand((result) => result.meanings)
      .where((meaning) => meaning.definitionJa?.trim().isNotEmpty != true)
      .map((meaning) => meaning.id)
      .where((id) => id > 0)
      .toSet();

  bool hasJapaneseMeaningFor(LexicalItemResult item) {
    final result = _results[_normalizedWord(item.text)];
    if (result == null) return false;
    return result.meanings.any(
      (meaning) =>
          _meaningMatchesItemPartOfSpeech(
            item.partOfSpeech,
            meaning.partOfSpeech,
          ) &&
          _hasJapaneseDefinition(meaning),
    );
  }

  bool hasStoredResultFor(LexicalItemResult item) =>
      _results.containsKey(_normalizedWord(item.text));

  bool matchesSearch(LexicalItemResult item, String query) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return true;
    final result = _results[_normalizedWord(item.text)];
    final values = <String>[
      item.text,
      item.partOfSpeech,
      if (item.partOfSpeechDetail != null) item.partOfSpeechDetail!,
      ...item.surfaceForms,
      if (result != null)
        for (final meaning in result.meanings) ...[
          meaning.definitionEn ?? '',
          meaning.definitionJa ?? '',
        ],
    ];
    return values.any((value) => value.toLowerCase().contains(normalizedQuery));
  }

  Future<void> _finishInitialLoad(
    List<LexicalItemResult> itemList,
    Future<void> storedLoading,
    String userId,
    VoidCallback? onStoredLoaded,
  ) async {
    // 既存語を押したときはこの時点までだけ待つ。後続のGemini全件生成を
    // 待機先に含めない。
    await storedLoading;
    onStoredLoaded?.call();
    await _fetchAndReplace(itemList, userId: userId, enrichMissing: true);
  }

  Future<void> _fetchAndReplace(
    List<LexicalItemResult> itemList, {
    required String userId,
    required bool enrichMissing,
  }) async {
    final results = await VocamineApiClient().fetchStoredMeanings(
      itemList,
      userId: userId,
      enrichMissing: enrichMissing,
    );
    _replaceResults(results);
  }

  void _replaceResults(Iterable<WordLookupResult> results) {
    for (final result in results) {
      _results[_normalizedWord(result.word)] = result;
    }
    revision++;
  }

  Future<WordLookupResult> cachedLookup(LexicalItemResult item) {
    final key = _normalizedWord(item.text);
    final cached = _results[key];
    if (cached != null) return SynchronousFuture(cached);
    final loading = _storedLoading ?? _loading;
    if (loading != null) {
      return loading.then(
        (_) =>
            _results[key] ??
            WordLookupResult(id: 0, word: item.text, meanings: const []),
      );
    }
    // 教材詳細を開く／操作するだけでは lookup API を呼ばない。
    // 意味の生成は教材の新規読み込み・解析時だけ行う。
    return SynchronousFuture(
      WordLookupResult(id: 0, word: item.text, meanings: const []),
    );
  }
}

bool _hasJapaneseDefinition(MeaningInfo meaning) =>
    meaning.definitionJa?.trim().isNotEmpty == true;

bool _meaningMatchesItemPartOfSpeech(
  String itemPartOfSpeech,
  String meaningPartOfSpeech,
) {
  final itemPos = itemPartOfSpeech.trim().toLowerCase();
  final meaningPos = meaningPartOfSpeech.trim().toLowerCase();
  if (itemPos == meaningPos) return true;
  return switch (itemPos) {
    'article' => meaningPos == 'determiner',
    'noun' => const {'pronoun', 'abbreviation'}.contains(meaningPos),
    'verb' => meaningPos == 'auxiliary',
    'adjective' => meaningPos == 'determiner',
    'determiner' => const {
      'article',
      'pronoun',
      'adjective',
      'numeral',
    }.contains(meaningPos),
    'pronoun' => const {'noun', 'determiner'}.contains(meaningPos),
    'auxiliary' => meaningPos == 'verb',
    'numeral' => meaningPos == 'determiner',
    'abbreviation' => meaningPos == 'noun',
    _ => false,
  };
}

String _normalizeLookupWord(String word) {
  return word.toLowerCase().replaceAll('’', "'");
}

int _compareMeaningForContext(
  MeaningInfo a,
  MeaningInfo b,
  String contextPartOfSpeech,
) {
  final aMatch = a.partOfSpeech == contextPartOfSpeech;
  final bMatch = b.partOfSpeech == contextPartOfSpeech;
  if (aMatch != bMatch) {
    return aMatch ? -1 : 1;
  }
  final aHasJapanese = _hasJapaneseDefinition(a);
  final bHasJapanese = _hasJapaneseDefinition(b);
  if (aHasJapanese != bHasJapanese) {
    return aHasJapanese ? -1 : 1;
  }
  return 0;
}

String? _transitivityLabel(String? value) {
  switch (value) {
    case 'transitive':
      return '他動詞';
    case 'intransitive':
      return '自動詞';
    case 'both':
      return '自動詞・他動詞';
    default:
      return null;
  }
}

String? _countabilityLabel(String? value) {
  switch (value) {
    case 'countable':
      return '可算';
    case 'uncountable':
      return '不可算';
    case 'both':
      return '可算・不可算';
    default:
      return null;
  }
}

class MaterialDetailScreen extends ConsumerStatefulWidget {
  final String materialId;
  final String title;

  const MaterialDetailScreen({
    super.key,
    required this.materialId,
    required this.title,
  });

  @override
  ConsumerState<MaterialDetailScreen> createState() =>
      _MaterialDetailScreenState();
}

class _MaterialDetailScreenState extends ConsumerState<MaterialDetailScreen> {
  _MaterialDisplayMode _displayMode = _MaterialDisplayMode.original;
  _SidePanelMode? _sidePanelMode;
  double _zoom = 1.0;
  bool _mobileAppBarCollapsed = false;
  final _lookupCache = _WordLookupCache();
  final Set<String> _autoAnalysisRequested = {};
  bool _registeredMeaningsRequested = false;
  bool _storedMeaningsRequested = false;
  bool _generatingMeanings = false;
  bool _meaningGenerationFailed = false;
  bool _regeneratingJapanese = false;
  List<LexicalItemResult> _materialItems = const [];

  Future<void> _regenerateMissingJapanese() async {
    final ids = _lookupCache.missingJapaneseMeaningIds;
    if (ids.isEmpty || _regeneratingJapanese) return;
    setState(() => _regeneratingJapanese = true);
    try {
      final updated = await VocamineApiClient().regenerateMissingJapanese(ids);
      await _lookupCache.reloadStoredMeanings(
        _materialItems,
        userId: ref.read(appSessionProvider).userId,
      );
      AppMessenger.show('$updated件の日本語訳を再生成しました');
      if (!mounted) return;
      setState(() {});
    } catch (error) {
      AppMessenger.show('日本語訳の再生成に失敗しました: $error');
    } finally {
      if (mounted) setState(() => _regeneratingJapanese = false);
    }
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      ref.read(materialLibraryProvider.notifier).load();
      ref.read(wordbookLibraryProvider.notifier).load();
    });
  }

  Future<void> _loadRegisteredMeanings(MaterialItem material) async {
    if (_registeredMeaningsRequested) return;
    _registeredMeaningsRequested = true;
    final wordbookId = await _preloadMaterialDefaultWordbook(
      material,
      ref.read(appSessionProvider).userId,
    );
    if (wordbookId == null) {
      _registeredMeaningIdsByMaterial[material.id] = {};
      return;
    }
    try {
      final words = await VocamineApiClient().fetchWordbook(
        userId: ref.read(appSessionProvider).userId,
        wordbookId: wordbookId,
      );
      _registeredMeaningIdsByMaterial[material.id] = words
          .map((word) => word.meaningId)
          .whereType<int>()
          .toSet();
      if (mounted) setState(() {});
    } catch (_) {
      _registeredMeaningsRequested = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(materialLibraryProvider);
    MaterialItem? material;
    for (final item in library.materials) {
      if (item.id == widget.materialId) {
        material = item;
        break;
      }
    }
    if (material == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final resolvedMaterial = material;
    if (!_registeredMeaningsRequested) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadRegisteredMeanings(resolvedMaterial);
      });
    }
    _preloadMaterialDefaultWordbook(
      material,
      ref.read(appSessionProvider).userId,
    );
    final analysis = library.analyses[widget.materialId];
    if (analysis == null && _autoAnalysisRequested.add(widget.materialId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref
            .read(materialLibraryProvider.notifier)
            .analyzeMaterial(widget.materialId);
      });
    }
    analysis?.whenOrNull(
      data: (result) {
        _materialItems = result.items;
        if (_storedMeaningsRequested) return;
        _storedMeaningsRequested = true;
        _generatingMeanings = true;
        _meaningGenerationFailed = false;
        _lookupCache
            .loadStoredMeanings(
              result.items,
              userId: ref.read(appSessionProvider).userId,
              onStoredLoaded: () {
                if (mounted) setState(() {});
              },
            )
            .then((_) {
              if (mounted) {
                setState(() => _generatingMeanings = false);
              }
            })
            .catchError((_) {
              if (mounted) {
                setState(() {
                  _generatingMeanings = false;
                  _meaningGenerationFailed = true;
                });
              }
            });
      },
    );
    final hasSource = canDisplayOriginalSource(material);
    final effectiveMode = hasSource ? _displayMode : _MaterialDisplayMode.text;
    final isNarrow = MediaQuery.sizeOf(context).width < 760;
    final appBarCollapsed = isNarrow && _mobileAppBarCollapsed;

    return Scaffold(
      appBar: appBarCollapsed
          ? null
          : AppBar(
              toolbarHeight: 52,
              actionsPadding: MediaQuery.sizeOf(context).width >= 900
                  ? const EdgeInsets.only(right: 356)
                  : EdgeInsets.zero,
              title: Text(material.title),
              actions: [
                if (isNarrow)
                  IconButton(
                    tooltip: '操作バーと進捗を折りたたむ',
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        setState(() => _mobileAppBarCollapsed = true),
                    icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                  ),
                if (isNarrow) ...[
                  IconButton(
                    tooltip: 'オリジナル',
                    onPressed: hasSource
                        ? () => setState(
                            () => _displayMode = _MaterialDisplayMode.original,
                          )
                        : null,
                    icon: Icon(
                      Icons.description_outlined,
                      color: effectiveMode == _MaterialDisplayMode.original
                          ? Theme.of(context).colorScheme.secondary
                          : null,
                    ),
                  ),
                  IconButton(
                    tooltip: 'テキスト',
                    onPressed: () => setState(
                      () => _displayMode = _MaterialDisplayMode.text,
                    ),
                    icon: Icon(
                      Icons.text_fields,
                      color: effectiveMode == _MaterialDisplayMode.text
                          ? Theme.of(context).colorScheme.secondary
                          : null,
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: '表示設定',
                    onSelected: (action) {
                      switch (action) {
                        case 'zoom_out':
                          setState(
                            () => _zoom = (_zoom - 0.1).clamp(0.75, 3.0),
                          );
                          return;
                        case 'zoom_reset':
                          setState(() => _zoom = 1.0);
                          return;
                        case 'zoom_in':
                          setState(
                            () => _zoom = (_zoom + 0.1).clamp(0.75, 3.0),
                          );
                          return;
                        case 'regenerate':
                          _regenerateMissingJapanese();
                          return;
                        case 'reanalyze':
                          ref
                              .read(materialLibraryProvider.notifier)
                              .analyzeMaterial(widget.materialId, force: true);
                          return;
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'zoom_out',
                        enabled: _zoom > 0.75,
                        child: const ListTile(
                          dense: true,
                          leading: Icon(Icons.zoom_out),
                          title: Text('縮小'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'zoom_reset',
                        child: ListTile(
                          dense: true,
                          leading: const Icon(Icons.center_focus_strong),
                          title: Text('100%に戻す（${(_zoom * 100).round()}%）'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'zoom_in',
                        enabled: _zoom < 3.0,
                        child: const ListTile(
                          dense: true,
                          leading: Icon(Icons.zoom_in),
                          title: Text('拡大'),
                        ),
                      ),
                      if (_lookupCache.missingJapaneseMeaningIds.isNotEmpty)
                        const PopupMenuItem(
                          value: 'regenerate',
                          child: ListTile(
                            dense: true,
                            leading: Icon(Icons.auto_fix_high),
                            title: Text('日本語訳を再生成'),
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'reanalyze',
                        child: ListTile(
                          dense: true,
                          leading: Icon(Icons.refresh),
                          title: Text('再解析'),
                        ),
                      ),
                    ],
                  ),
                ],
                if (!isNarrow) ...[
                  IconButton(
                    tooltip: 'オリジナル',
                    onPressed: hasSource
                        ? () => setState(
                            () => _displayMode = _MaterialDisplayMode.original,
                          )
                        : null,
                    icon: Icon(
                      Icons.description_outlined,
                      color: effectiveMode == _MaterialDisplayMode.original
                          ? Theme.of(context).colorScheme.secondary
                          : null,
                    ),
                  ),
                  IconButton(
                    tooltip: 'テキスト',
                    onPressed: () => setState(
                      () => _displayMode = _MaterialDisplayMode.text,
                    ),
                    icon: Icon(
                      Icons.text_fields,
                      color: effectiveMode == _MaterialDisplayMode.text
                          ? Theme.of(context).colorScheme.secondary
                          : null,
                    ),
                  ),
                  const VerticalDivider(indent: 10, endIndent: 10),
                  _ToolbarIconButton(
                    tooltip: '縮小',
                    onPressed: _zoom <= 0.75
                        ? null
                        : () => setState(() => _zoom -= 0.1),
                    icon: Icons.zoom_out,
                  ),
                  Tooltip(
                    message: '表示倍率を100%に戻す',
                    child: InkWell(
                      onTap: _zoom == 1.0
                          ? null
                          : () => setState(() => _zoom = 1.0),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            '${(_zoom * 100).round()}%',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      ),
                    ),
                  ),
                  _ToolbarIconButton(
                    tooltip: '拡大',
                    onPressed: _zoom >= 3.0
                        ? null
                        : () => setState(
                            () => _zoom = (_zoom + 0.1).clamp(0.75, 3.0),
                          ),
                    icon: Icons.zoom_in,
                  ),
                  if (_lookupCache.missingJapaneseMeaningIds.isNotEmpty)
                    IconButton(
                      tooltip:
                          '日本語訳がない${_lookupCache.missingJapaneseMeaningIds.length}件を再生成',
                      onPressed: _regeneratingJapanese
                          ? null
                          : _regenerateMissingJapanese,
                      icon: _regeneratingJapanese
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_fix_high),
                    ),
                  IconButton(
                    tooltip: '再解析',
                    onPressed: () => ref
                        .read(materialLibraryProvider.notifier)
                        .analyzeMaterial(widget.materialId, force: true),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ],
            ),
      body: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: const Color(0xFFF7F9FB),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: _MaterialContentView(
                  material: material,
                  mode: effectiveMode,
                  analysis: analysis,
                  lookupCache: _lookupCache,
                  zoom: _zoom,
                  onZoomChanged: (zoom) => setState(() => _zoom = zoom),
                  mobileAppBarCollapsed: appBarCollapsed,
                  sidePanelMode: _sidePanelMode,
                  onSidePanelModeChanged: (mode) =>
                      setState(() => _sidePanelMode = mode),
                ),
              ),
            ),
          ),
          if (appBarCollapsed) ...[
            Positioned(
              top: MediaQuery.paddingOf(context).top + 4,
              left: 4,
              width: 40,
              height: 40,
              child: _CollapsedAppBarButton(
                tooltip: '戻る',
                icon: Icons.arrow_back,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 4,
              right: 4,
              width: 40,
              height: 40,
              child: _CollapsedAppBarButton(
                tooltip: '操作バーを表示',
                icon: Icons.keyboard_arrow_down,
                onPressed: () => setState(() => _mobileAppBarCollapsed = false),
              ),
            ),
          ],
          if (_generatingMeanings)
            Positioned(
              top: appBarCollapsed ? MediaQuery.paddingOf(context).top + 50 : 8,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: Material(
                    color: Theme.of(context).colorScheme.surface,
                    elevation: 3,
                    borderRadius: BorderRadius.circular(18),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 9),
                          Text('意味を生成中'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (_meaningGenerationFailed)
            Positioned(
              top: appBarCollapsed ? MediaQuery.paddingOf(context).top + 50 : 8,
              left: 0,
              right: 0,
              child: Center(
                child: Material(
                  color: Theme.of(context).colorScheme.errorContainer,
                  elevation: 3,
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('意味の生成に失敗しました'),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _storedMeaningsRequested = false;
                              _meaningGenerationFailed = false;
                            });
                          },
                          child: const Text('再試行'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CollapsedAppBarButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  const _CollapsedAppBarButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
      elevation: 2,
      borderRadius: BorderRadius.circular(20),
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
      ),
    );
  }
}

class _ToolbarIconButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback? onPressed;
  final IconData icon;

  const _ToolbarIconButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 19),
      style: IconButton.styleFrom(
        minimumSize: const Size(36, 36),
        maximumSize: const Size(36, 36),
        padding: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        foregroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

class _MaterialContentView extends ConsumerStatefulWidget {
  final MaterialItem material;
  final _MaterialDisplayMode mode;
  final AsyncValue<ExtractWordsResult>? analysis;
  final _WordLookupCache lookupCache;
  final double zoom;
  final ValueChanged<double> onZoomChanged;
  final bool mobileAppBarCollapsed;
  final _SidePanelMode? sidePanelMode;
  final ValueChanged<_SidePanelMode?> onSidePanelModeChanged;

  const _MaterialContentView({
    required this.material,
    required this.mode,
    required this.analysis,
    required this.lookupCache,
    required this.zoom,
    required this.onZoomChanged,
    required this.mobileAppBarCollapsed,
    required this.sidePanelMode,
    required this.onSidePanelModeChanged,
  });

  @override
  ConsumerState<_MaterialContentView> createState() =>
      _MaterialContentViewState();
}

class _MaterialContentViewState extends ConsumerState<_MaterialContentView> {
  final GlobalKey _textKey = GlobalKey();
  final GlobalKey _zoomViewportKey = GlobalKey();
  final ScrollController _textScrollController = ScrollController();
  final ScrollController _sourceScrollController = ScrollController();
  final ScrollController _sourceHorizontalScrollController = ScrollController();
  final List<GlobalKey> _sourcePageKeys = [];
  final Map<String, GlobalKey> _sourceRangeKeys = {};
  final Map<String, int> _focusedOccurrenceIndexes = {};
  OverlayEntry? _popoverEntry;
  final Object _popoverTapRegionGroup = Object();
  String? _hoveredRangeKey;
  int? _selectionStart;
  int? _selectionEnd;
  int? _longPressWordStart;
  int? _longPressWordEnd;
  Offset? _longPressStartPosition;
  bool _longPressRangeSelection = false;
  Timer? _textLongPressTimer;
  int? _textTouchPointer;
  Offset? _textTouchStartLocal;
  Offset? _textTouchStartGlobal;
  bool _textLongPressActive = false;
  int? _mouseSelectionPointer;
  int? _mouseSelectionPage;
  int? _mouseSelectionAnchor;
  Offset? _mouseSelectionStartPosition;
  final Map<int, Offset> _sourceTouchPositions = {};
  double? _pinchStartDistance;
  double? _pinchStartZoom;
  Offset? _pinchFocalPoint;
  double? _pinchContentX;
  double? _pinchContentY;
  bool _mobileOverviewCollapsed = false;
  double _mobilePanelHeight = 260;
  DateTime? _lastPointerDownAt;
  Offset? _lastPointerDownPosition;
  DateTime? _suppressSelectionUntil;

  ExtractWordsResult? get _result =>
      widget.analysis?.maybeWhen(data: (value) => value, orElse: () => null);

  _LearningTextState get _learningTextState => _LearningTextState(
    text: widget.material.ocrText,
    result: _result,
    selectionStart: _selectionStart,
    selectionEnd: _selectionEnd,
  );

  List<Uint8List> get _sourcePages {
    if (widget.material.sourcePageImages.isNotEmpty) {
      return widget.material.sourcePageImages;
    }
    final bytes = widget.material.sourceBytes;
    return bytes == null ? const [] : [bytes];
  }

  @override
  void dispose() {
    _popoverEntry?.remove();
    _textLongPressTimer?.cancel();
    _textScrollController.dispose();
    _sourceScrollController.dispose();
    _sourceHorizontalScrollController.dispose();
    super.dispose();
  }

  void _hideMeaningPopover() {
    _popoverEntry?.remove();
    _popoverEntry = null;
  }

  void _showMeaningPopover(
    LexicalItemResult item,
    Offset globalPosition, {
    bool focusOccurrence = true,
  }) {
    _hideMeaningPopover();
    if (focusOccurrence) {
      _focusItemOccurrence(item);
    }
    final hostContext = context;
    final overlay = Overlay.of(context);
    final screenSize = MediaQuery.sizeOf(context);
    const width = 340.0;
    final preferredLeft = globalPosition.dx > screenSize.width * 0.65
        ? globalPosition.dx - width - 24
        : globalPosition.dx - 28;
    final left = preferredLeft.clamp(
      12.0,
      (screenSize.width - width - 12).clamp(12.0, screenSize.width),
    );
    final belowTop = globalPosition.dy + 18;
    const popoverMaxHeight = 460.0;
    final maxTop = (screenSize.height - popoverMaxHeight - 12).clamp(
      12.0,
      screenSize.height,
    );
    final top = belowTop > maxTop
        ? (globalPosition.dy - popoverMaxHeight - 16).clamp(12.0, maxTop)
        : belowTop;

    _popoverEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              width: width,
              child: TapRegion(
                groupId: _popoverTapRegionGroup,
                onTapOutside: (_) => _hideMeaningPopover(),
                child: _MeaningPopover(
                  item: item,
                  future: widget.lookupCache.cachedLookup(item),
                  hostContext: hostContext,
                  anchorRect: Rect.fromLTWH(
                    left.toDouble(),
                    top.toDouble(),
                    width,
                    popoverMaxHeight,
                  ),
                  userId: ref.read(appSessionProvider).userId,
                  material: widget.material,
                  onAdded: () =>
                      ref.read(wordsProvider.notifier).load(isLearned: false),
                  tapRegionGroupId: _popoverTapRegionGroup,
                  onClose: _hideMeaningPopover,
                ),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_popoverEntry!);
  }

  void _focusItemOccurrence(LexicalItemResult item) {
    final ranges = item.kind == 'phrase'
        ? <_TextRange>[]
        : _learningTextState
              .rangesForItem(item)
              .map((range) => _TextRange(range.start, range.end))
              .toList();
    if (ranges.isEmpty) {
      ranges.addAll(
        item.occurrences
            .where(
              (occurrence) =>
                  occurrence.start >= 0 &&
                  occurrence.end > occurrence.start &&
                  occurrence.end <= widget.material.ocrText.length,
            )
            .map((occurrence) => _TextRange(occurrence.start, occurrence.end)),
      );
    }
    if (ranges.isEmpty) return;
    ranges.sort((left, right) => left.start.compareTo(right.start));
    final itemKey = '${item.text}:${item.partOfSpeech}:${item.kind}';
    final nextIndex =
        ((_focusedOccurrenceIndexes[itemKey] ?? -1) + 1) % ranges.length;
    _focusedOccurrenceIndexes[itemKey] = nextIndex;
    final focusedRange = ranges[nextIndex];
    final rangeKey = _markedRangeKey(focusedRange.start, focusedRange.end);
    setState(() {
      _hoveredRangeKey = rangeKey;
      // hoverだけでなく選択範囲としても保持し、原文・テキストの双方で
      // 確実にマーカーを描画する。
      _selectionStart = focusedRange.start;
      _selectionEnd = focusedRange.end;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.mode == _MaterialDisplayMode.original) {
        final rangeContext = _sourceRangeKeys[rangeKey]?.currentContext;
        if (rangeContext != null) {
          Scrollable.ensureVisible(
            rangeContext,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
            alignment: 0.4,
          );
          return;
        }
        final sourceBoxes = _resolveSourceBoxes(
          widget.material.sourceWordBoxes,
          widget.material.ocrText,
        );
        final matching = sourceBoxes.where(
          (resolved) =>
              resolved.textRange.end > focusedRange.start &&
              resolved.textRange.start < focusedRange.end,
        );
        final pageIndex = matching.isEmpty
            ? null
            : matching.first.box.pageIndex;
        if (pageIndex != null && pageIndex < _sourcePageKeys.length) {
          final pageContext = _sourcePageKeys[pageIndex].currentContext;
          if (pageContext != null) {
            Scrollable.ensureVisible(
              pageContext,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOut,
              alignment: 0.35,
            );
          }
        }
      } else {
        final textContext = _textKey.currentContext;
        if (textContext != null) {
          final textBox = textContext.findRenderObject() as RenderBox?;
          final scrollable = Scrollable.maybeOf(textContext);
          final viewportBox =
              scrollable?.context.findRenderObject() as RenderBox?;
          if (textBox != null && scrollable != null && viewportBox != null) {
            final painter = TextPainter(
              text: TextSpan(
                text: widget.material.ocrText,
                style: _textStyle(context),
              ),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            )..layout(maxWidth: textBox.size.width);
            final caret = painter.getOffsetForCaret(
              TextPosition(offset: focusedRange.start),
              Rect.zero,
            );
            final targetGlobalY = textBox.localToGlobal(caret).dy;
            final viewportTop = viewportBox.localToGlobal(Offset.zero).dy;
            final position = _textScrollController.position;
            final target =
                (position.pixels +
                        targetGlobalY -
                        viewportTop -
                        viewportBox.size.height * 0.2)
                    .clamp(position.minScrollExtent, position.maxScrollExtent)
                    .toDouble();
            position.animateTo(
              target,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOut,
            );
          }
        }
      }
    });
  }

  void _setHoveredRange(String? key) {
    if (_hoveredRangeKey == key) return;
    setState(() => _hoveredRangeKey = key);
  }

  void _clearSelection() {
    if (_selectionStart == null && _selectionEnd == null) {
      return;
    }
    setState(() {
      _selectionStart = null;
      _selectionEnd = null;
    });
    if (widget.sidePanelMode == _SidePanelMode.selection) {
      widget.onSidePanelModeChanged(null);
    }
  }

  String get _selectedText {
    final start = _selectionStart;
    final end = _selectionEnd;
    final text = widget.material.ocrText;
    if (start == null || end == null || start == end || text.isEmpty) return '';
    final lower = math.min(start, end).clamp(0, text.length);
    final upper = math.max(start, end).clamp(0, text.length);
    return text.substring(lower, upper).trim();
  }

  Future<void> _copySelection() async {
    final text = _selectedText;
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    AppMessenger.show('選択範囲をコピーしました');
  }

  TextStyle? _textStyle(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyLarge;
    return GoogleFonts.sourceSerif4(textStyle: base).copyWith(
      height: 1.8,
      color: const Color(0xFF2D3133),
      fontSize: (base?.fontSize ?? 16) * widget.zoom,
    );
  }

  List<InlineSpan> _buildTextSpans(_LearningTextState state) {
    final baseStyle = _textStyle(context);
    final spans = <InlineSpan>[];
    for (final segment in state.segmentsForRange(
      0,
      state.text.length,
      hoveredRangeKey: _hoveredRangeKey,
    )) {
      final range = segment.range;
      final rangeKey = range != null && range.kind == _MarkedRangeKind.word
          ? _markedRangeKey(range.start, range.end)
          : null;
      final color = segment.visual.backgroundColor;
      spans.add(
        TextSpan(
          text: state.text.substring(segment.start, segment.end),
          style: color == null
              ? baseStyle
              : baseStyle?.copyWith(backgroundColor: color),
          mouseCursor: rangeKey == null ? null : SystemMouseCursors.click,
          onEnter: rangeKey == null ? null : (_) => _setHoveredRange(rangeKey),
          onExit: rangeKey == null
              ? null
              : (_) {
                  if (_hoveredRangeKey == rangeKey) {
                    _setHoveredRange(null);
                  }
                },
        ),
      );
    }
    return [TextSpan(style: baseStyle, children: spans)];
  }

  LexicalItemResult? _itemAtTextPosition(
    Offset localPosition,
    double maxWidth,
  ) {
    final text = widget.material.ocrText;
    final painter = TextPainter(
      text: TextSpan(text: text, style: _textStyle(context)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      textHeightBehavior: DefaultTextStyle.of(context).textHeightBehavior,
    )..layout(maxWidth: maxWidth);
    final offset = painter
        .getPositionForOffset(localPosition)
        .offset
        .clamp(0, text.length)
        .toInt();
    if (offset >= text.length) return null;
    return _learningTextState.wordRangeAtOffset(offset)?.item;
  }

  int? _textOffsetAtPosition(Offset localPosition, double maxWidth) {
    final text = widget.material.ocrText;
    if (text.isEmpty) return null;
    final painter = TextPainter(
      text: TextSpan(text: text, style: _textStyle(context)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      textHeightBehavior: DefaultTextStyle.of(context).textHeightBehavior,
    )..layout(maxWidth: maxWidth);
    return painter
        .getPositionForOffset(localPosition)
        .offset
        .clamp(0, text.length)
        .toInt();
  }

  _MarkedRange? _wordRangeAtTextPosition(
    Offset localPosition,
    double maxWidth,
  ) {
    final text = widget.material.ocrText;
    final offset = _textOffsetAtPosition(localPosition, maxWidth);
    if (offset == null || text.isEmpty) return null;
    final safeOffset = math.min(offset, text.length - 1);
    return _learningTextState.wordRangeAtOffset(safeOffset) ??
        (safeOffset > 0
            ? _learningTextState.wordRangeAtOffset(safeOffset - 1)
            : null);
  }

  void _selectWholeWord(_MarkedRange range) {
    setState(() {
      _selectionStart = range.start;
      _selectionEnd = range.end;
      _longPressWordStart = range.start;
      _longPressWordEnd = range.end;
      _longPressRangeSelection = false;
    });
  }

  void _extendLongPressSelection(int currentOffset) {
    final wordStart = _longPressWordStart;
    final wordEnd = _longPressWordEnd;
    if (wordStart == null || wordEnd == null) return;
    setState(() {
      _selectionStart = math.min(currentOffset, wordStart);
      _selectionEnd = math.max(currentOffset, wordEnd);
      _longPressRangeSelection = true;
    });
    widget.onSidePanelModeChanged(_SidePanelMode.selection);
  }

  bool _isTouchPointer(PointerEvent event) =>
      event.kind == PointerDeviceKind.touch ||
      event.kind == PointerDeviceKind.stylus ||
      event.kind == PointerDeviceKind.invertedStylus;

  void _handleTextTouchDown(PointerDownEvent event, double maxWidth) {
    _handleSourcePointerDown(event);
    _handleTextPointerDown(event, maxWidth);
    if (!_isTouchPointer(event) || _textTouchPointer != null) return;
    _textTouchPointer = event.pointer;
    _textTouchStartLocal = event.localPosition;
    _textTouchStartGlobal = event.position;
    _textLongPressActive = false;
    _textLongPressTimer?.cancel();
    _textLongPressTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted || _textTouchPointer != event.pointer) return;
      final local = _textTouchStartLocal;
      final global = _textTouchStartGlobal;
      if (local == null || global == null) return;
      final textBox = _textKey.currentContext?.findRenderObject() as RenderBox?;
      final range = _wordRangeAtTextPosition(
        local,
        textBox?.size.width ?? maxWidth,
      );
      if (range == null) return;
      _textLongPressActive = true;
      _longPressStartPosition = global;
      _suppressSelectionUntil = DateTime.now().add(const Duration(seconds: 2));
      _selectWholeWord(range);
      _showMeaningPopover(range.item, global, focusOccurrence: false);
    });
  }

  void _handleTextTouchMove(PointerMoveEvent event, double maxWidth) {
    _handleSourcePointerMove(event);
    if (_textTouchPointer != event.pointer) return;
    final start = _textTouchStartGlobal;
    if (start == null) return;
    final distance = (event.position - start).distance;
    if (!_textLongPressActive) {
      if (distance > 10) _textLongPressTimer?.cancel();
      return;
    }
    if (distance <= 6) return;
    if (!_longPressRangeSelection) _hideMeaningPopover();
    final textBox = _textKey.currentContext?.findRenderObject() as RenderBox?;
    if (textBox == null) return;
    final offset = _textOffsetAtPosition(
      textBox.globalToLocal(event.position),
      textBox.size.width,
    );
    if (offset != null) _extendLongPressSelection(offset);
  }

  void _finishTextTouch(PointerEvent event) {
    _handleSourcePointerEnd(event);
    if (_textTouchPointer != event.pointer) return;
    _textLongPressTimer?.cancel();
    _textTouchPointer = null;
    _textTouchStartLocal = null;
    _textTouchStartGlobal = null;
    _textLongPressActive = false;
    _longPressWordStart = null;
    _longPressWordEnd = null;
    _longPressStartPosition = null;
    _longPressRangeSelection = false;
    _suppressSelectionUntil = DateTime.now().add(
      const Duration(milliseconds: 250),
    );
  }

  void _handleTextPointerDown(PointerDownEvent event, double maxWidth) {
    final now = DateTime.now();
    final previousTime = _lastPointerDownAt;
    final previousPosition = _lastPointerDownPosition;
    _lastPointerDownAt = now;
    _lastPointerDownPosition = event.position;
    if (previousTime == null || previousPosition == null) return;

    final isDoubleClick =
        now.difference(previousTime) <= const Duration(milliseconds: 360) &&
        (event.position - previousPosition).distance <= 8;
    if (!isDoubleClick) return;

    final renderBox = _textKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final state = _learningTextState;
    final hoveredItem = _hoveredRangeKey == null
        ? null
        : state.rangeForKey(_hoveredRangeKey!)?.item;
    final item =
        hoveredItem ??
        _itemAtTextPosition(renderBox.globalToLocal(event.position), maxWidth);
    if (item == null) return;

    _suppressSelectionUntil = DateTime.now().add(
      const Duration(milliseconds: 500),
    );
    setState(() {
      _selectionStart = null;
      _selectionEnd = null;
    });
    _showMeaningPopover(item, event.position, focusOccurrence: false);
  }

  int? _textOffsetAtSourcePosition(
    int pageIndex,
    Offset position,
    Size pageSize,
    List<_ResolvedSourceBox> sourceBoxes,
  ) {
    for (final resolved in sourceBoxes.where(
      (resolved) => resolved.box.pageIndex == pageIndex,
    )) {
      final box = resolved.box;
      final rect = Rect.fromLTWH(
        box.left * pageSize.width,
        box.top * pageSize.height,
        box.width * pageSize.width,
        box.height * pageSize.height,
      );
      if (!rect.contains(position)) {
        continue;
      }
      return _offsetWithinSourceRange(rect, position, (
        start: resolved.textRange.start,
        end: resolved.textRange.end,
      ));
    }
    return null;
  }

  int _offsetWithinSourceRange(
    Rect rect,
    Offset position,
    ({int start, int end}) range,
  ) {
    if (range.end <= range.start || rect.width <= 0) return range.start;
    final ratio = ((position.dx - rect.left) / rect.width).clamp(0.0, 1.0);
    return range.start + ((range.end - range.start) * ratio).round();
  }

  int? _sourceOffsetAt(
    int pageIndex,
    Offset position,
    Size pageSize,
    List<_ResolvedSourceBox> sourceBoxes,
  ) {
    return _textOffsetAtSourcePosition(
      pageIndex,
      position,
      pageSize,
      sourceBoxes,
    );
  }

  int? _nearestSourceOffsetAt(
    int pageIndex,
    Offset position,
    Size pageSize,
    List<_ResolvedSourceBox> sourceBoxes,
  ) {
    final direct = _sourceOffsetAt(pageIndex, position, pageSize, sourceBoxes);
    if (direct != null) return direct;
    _ResolvedSourceBox? nearest;
    Rect? nearestRect;
    var nearestDistance = double.infinity;
    for (final resolved in sourceBoxes.where(
      (resolved) => resolved.box.pageIndex == pageIndex,
    )) {
      final box = resolved.box;
      final rect = Rect.fromLTWH(
        box.left * pageSize.width,
        box.top * pageSize.height,
        box.width * pageSize.width,
        box.height * pageSize.height,
      );
      final dx = position.dx < rect.left
          ? rect.left - position.dx
          : position.dx > rect.right
          ? position.dx - rect.right
          : 0.0;
      final dy = position.dy < rect.top
          ? rect.top - position.dy
          : position.dy > rect.bottom
          ? position.dy - rect.bottom
          : 0.0;
      final distance = dx * dx + dy * dy;
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = resolved;
        nearestRect = rect;
      }
    }
    if (nearest == null || nearestRect == null) return null;
    return _offsetWithinSourceRange(nearestRect, position, (
      start: nearest.textRange.start,
      end: nearest.textRange.end,
    ));
  }

  _MarkedRange? _sourceWordRangeAt(
    int pageIndex,
    Offset position,
    Size pageSize,
    List<_ResolvedSourceBox> sourceBoxes,
  ) {
    final text = widget.material.ocrText;
    final offset = _sourceOffsetAt(pageIndex, position, pageSize, sourceBoxes);
    if (offset == null || text.isEmpty) return null;
    final safeOffset = math.min(offset, text.length - 1);
    return _learningTextState.wordRangeAtOffset(safeOffset) ??
        (safeOffset > 0
            ? _learningTextState.wordRangeAtOffset(safeOffset - 1)
            : null);
  }

  void _handleSourceMouseDown(
    PointerDownEvent event,
    int pageIndex,
    Size pageSize,
    List<_ResolvedSourceBox> sourceBoxes,
  ) {
    if (event.kind != PointerDeviceKind.mouse || event.buttons != 1) return;
    final anchor = _nearestSourceOffsetAt(
      pageIndex,
      event.localPosition,
      pageSize,
      sourceBoxes,
    );
    if (anchor == null) return;
    _mouseSelectionPointer = event.pointer;
    _mouseSelectionPage = pageIndex;
    _mouseSelectionAnchor = anchor;
    _mouseSelectionStartPosition = event.localPosition;
  }

  void _handleSourceMouseMove(
    PointerMoveEvent event,
    int pageIndex,
    Size pageSize,
    List<_ResolvedSourceBox> sourceBoxes,
  ) {
    if (_mouseSelectionPointer != event.pointer ||
        _mouseSelectionPage != pageIndex ||
        event.kind != PointerDeviceKind.mouse) {
      return;
    }
    final startPosition = _mouseSelectionStartPosition;
    final anchor = _mouseSelectionAnchor;
    if (startPosition == null ||
        anchor == null ||
        (event.localPosition - startPosition).distance < 3) {
      return;
    }
    final current = _nearestSourceOffsetAt(
      pageIndex,
      event.localPosition,
      pageSize,
      sourceBoxes,
    );
    if (current == null) return;
    setState(() {
      _selectionStart = anchor;
      _selectionEnd = current;
    });
    widget.onSidePanelModeChanged(_SidePanelMode.selection);
  }

  void _finishSourceMouseSelection(PointerEvent event) {
    if (_mouseSelectionPointer != event.pointer) return;
    _mouseSelectionPointer = null;
    _mouseSelectionPage = null;
    _mouseSelectionAnchor = null;
    _mouseSelectionStartPosition = null;
  }

  Rect _sourceSegmentRect(
    SourceWordBox box,
    Size pageSize,
    _TextRange boxRange,
    _LearningTextSegment segment,
  ) {
    final boxWidth = box.width * pageSize.width;
    final local = _selectionRectWithinBox(
      boxRange,
      _TextRange(segment.start, segment.end),
      boxWidth,
    );
    return Rect.fromLTWH(
      box.left * pageSize.width + local.left,
      box.top * pageSize.height,
      math.max(0.5, local.width).toDouble(),
      box.height * pageSize.height,
    );
  }

  Widget _buildSourceSegment(
    SourceWordBox box,
    Size pageSize,
    _TextRange boxRange,
    _LearningTextSegment segment,
  ) {
    final range = segment.range;
    final isLexicalRange =
        range?.kind == _MarkedRangeKind.word ||
        range?.kind == _MarkedRangeKind.phrase;
    final rangeKey = isLexicalRange
        ? _markedRangeKey(range!.start, range.end)
        : null;
    final color = segment.visual.backgroundColor;

    final markerKey = rangeKey != null && segment.start == range?.start
        ? _sourceRangeKeys.putIfAbsent(rangeKey, () => GlobalKey())
        : null;
    return Positioned.fromRect(
      rect: _sourceSegmentRect(box, pageSize, boxRange, segment),
      child: MouseRegion(
        key: markerKey,
        cursor: isLexicalRange
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: rangeKey == null ? null : (_) => _setHoveredRange(rangeKey),
        onExit: rangeKey == null
            ? null
            : (_) {
                if (_hoveredRangeKey == rangeKey) {
                  _setHoveredRange(null);
                }
              },
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onDoubleTapDown: !isLexicalRange
              ? null
              : (details) => _showMeaningPopover(
                  range!.item,
                  details.globalPosition,
                  focusOccurrence: false,
                ),
          child: color == null
              ? const SizedBox.expand()
              : DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.zero,
                  ),
                ),
        ),
      ),
    );
  }

  List<Widget> _buildSourceSegments(
    _ResolvedSourceBox resolved,
    Size pageSize,
    _LearningTextState state,
  ) {
    final boxRange = resolved.textRange;
    return [
      for (final segment in state.segmentsForRange(
        boxRange.start,
        boxRange.end,
        hoveredRangeKey: _hoveredRangeKey,
      ))
        _buildSourceSegment(resolved.box, pageSize, boxRange, segment),
    ];
  }

  Widget _buildSourcePage(
    Uint8List imageBytes,
    int pageIndex,
    _LearningTextState state,
    List<_ResolvedSourceBox> sourceBoxes,
  ) {
    final pageBoxes = sourceBoxes
        .where((resolved) => resolved.box.pageIndex == pageIndex)
        .toList();

    return Stack(
      fit: StackFit.passthrough,
      children: [
        Image.memory(imageBytes, width: double.infinity, fit: BoxFit.fitWidth),
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final pageSize = Size(
                constraints.maxWidth,
                constraints.maxHeight,
              );
              return Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (event) => _handleSourceMouseDown(
                  event,
                  pageIndex,
                  pageSize,
                  sourceBoxes,
                ),
                onPointerMove: (event) => _handleSourceMouseMove(
                  event,
                  pageIndex,
                  pageSize,
                  sourceBoxes,
                ),
                onPointerUp: _finishSourceMouseSelection,
                onPointerCancel: _finishSourceMouseSelection,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _clearSelection,
                  onLongPressStart: (details) {
                    if (_sourceTouchPositions.length > 1) return;
                    final range = _sourceWordRangeAt(
                      pageIndex,
                      details.localPosition,
                      pageSize,
                      sourceBoxes,
                    );
                    if (range == null) return;
                    _longPressStartPosition = details.globalPosition;
                    _selectWholeWord(range);
                    _showMeaningPopover(
                      range.item,
                      details.globalPosition,
                      focusOccurrence: false,
                    );
                  },
                  onLongPressMoveUpdate: (details) {
                    if (_sourceTouchPositions.length > 1) return;
                    final start = _longPressStartPosition;
                    if (start == null ||
                        (details.globalPosition - start).distance <= 6) {
                      return;
                    }
                    if (!_longPressRangeSelection) _hideMeaningPopover();
                    final current = _nearestSourceOffsetAt(
                      pageIndex,
                      details.localPosition,
                      pageSize,
                      sourceBoxes,
                    );
                    if (current != null) _extendLongPressSelection(current);
                  },
                  onLongPressEnd: (_) {
                    setState(() {
                      _longPressWordStart = null;
                      _longPressWordEnd = null;
                      _longPressStartPosition = null;
                      _longPressRangeSelection = false;
                    });
                  },
                  child: Stack(
                    children: [
                      for (final resolved in pageBoxes)
                        ..._buildSourceSegments(resolved, pageSize, state),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _handleSourcePointerDown(PointerDownEvent event) {
    if (!_isTouchPointer(event)) return;
    _sourceTouchPositions[event.pointer] = event.position;
    if (_sourceTouchPositions.length == 2) {
      final positions = _sourceTouchPositions.values.toList();
      _pinchStartDistance = (positions[0] - positions[1]).distance;
      _pinchStartZoom = widget.zoom;
      final viewportBox =
          _zoomViewportKey.currentContext?.findRenderObject() as RenderBox?;
      if (viewportBox != null) {
        final globalFocal = Offset(
          (positions[0].dx + positions[1].dx) / 2,
          (positions[0].dy + positions[1].dy) / 2,
        );
        final focal = viewportBox.globalToLocal(globalFocal);
        _pinchFocalPoint = focal;
        final showingSource =
            widget.mode == _MaterialDisplayMode.original &&
            canDisplayOriginalSource(widget.material);
        final horizontalOffset =
            showingSource && _sourceHorizontalScrollController.hasClients
            ? _sourceHorizontalScrollController.offset
            : 0.0;
        final verticalController = showingSource
            ? _sourceScrollController
            : _textScrollController;
        final verticalOffset = verticalController.hasClients
            ? verticalController.offset
            : 0.0;
        _pinchContentX = (horizontalOffset + focal.dx) / widget.zoom;
        _pinchContentY = (verticalOffset + focal.dy) / widget.zoom;
      }
      _hideMeaningPopover();
      _textLongPressTimer?.cancel();
    }
  }

  void _handleSourcePointerMove(PointerMoveEvent event) {
    if (!_sourceTouchPositions.containsKey(event.pointer)) return;
    _sourceTouchPositions[event.pointer] = event.position;
    final startDistance = _pinchStartDistance;
    final startZoom = _pinchStartZoom;
    if (_sourceTouchPositions.length < 2 ||
        startDistance == null ||
        startDistance <= 0 ||
        startZoom == null) {
      return;
    }
    final positions = _sourceTouchPositions.values.take(2).toList();
    final distance = (positions[0] - positions[1]).distance;
    final viewportBox =
        _zoomViewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (viewportBox != null) {
      final globalFocal = Offset(
        (positions[0].dx + positions[1].dx) / 2,
        (positions[0].dy + positions[1].dy) / 2,
      );
      _pinchFocalPoint = viewportBox.globalToLocal(globalFocal);
    }
    final zoom = (startZoom * distance / startDistance)
        .clamp(0.75, 3.0)
        .toDouble();
    if ((zoom - widget.zoom).abs() >= 0.01) {
      widget.onZoomChanged(zoom);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _restorePinchFocalPoint(zoom);
      });
    }
  }

  void _restorePinchFocalPoint(double zoom) {
    final focal = _pinchFocalPoint;
    final contentX = _pinchContentX;
    final contentY = _pinchContentY;
    if (focal == null || contentY == null) return;
    final showingSource =
        widget.mode == _MaterialDisplayMode.original &&
        canDisplayOriginalSource(widget.material);
    if (showingSource &&
        contentX != null &&
        _sourceHorizontalScrollController.hasClients) {
      final position = _sourceHorizontalScrollController.position;
      final target = (contentX * zoom - focal.dx)
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      _sourceHorizontalScrollController.jumpTo(target);
    }
    final verticalController = showingSource
        ? _sourceScrollController
        : _textScrollController;
    if (verticalController.hasClients) {
      final position = verticalController.position;
      final target = (contentY * zoom - focal.dy)
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      verticalController.jumpTo(target);
    }
  }

  void _handleSourcePointerEnd(PointerEvent event) {
    _sourceTouchPositions.remove(event.pointer);
    if (_sourceTouchPositions.length < 2) {
      _pinchStartDistance = null;
      _pinchStartZoom = null;
    }
  }

  Widget _buildSourceContent(_LearningTextState state) {
    final pages = _sourcePages;
    if (pages.isEmpty) {
      return const Center(child: Text('原本プレビューを生成できませんでした'));
    }
    final sourceBoxes = _resolveSourceBoxes(
      widget.material.sourceWordBoxes,
      state.text,
    );
    while (_sourcePageKeys.length < pages.length) {
      _sourcePageKeys.add(GlobalKey());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final scaledWidth = constraints.maxWidth * widget.zoom;
        return Listener(
          key: _zoomViewportKey,
          behavior: HitTestBehavior.translucent,
          onPointerDown: _handleSourcePointerDown,
          onPointerMove: _handleSourcePointerMove,
          onPointerUp: _handleSourcePointerEnd,
          onPointerCancel: _handleSourcePointerEnd,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.zero,
            ),
            child: Scrollbar(
              controller: _sourceHorizontalScrollController,
              thumbVisibility: widget.zoom > 1,
              notificationPredicate: (notification) => notification.depth == 0,
              child: SingleChildScrollView(
                controller: _sourceHorizontalScrollController,
                scrollDirection: Axis.horizontal,
                primary: false,
                child: SizedBox(
                  width: scaledWidth,
                  height: constraints.maxHeight,
                  child: Scrollbar(
                    controller: _sourceScrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _sourceScrollController,
                      padding: const EdgeInsets.all(12),
                      primary: false,
                      child: Column(
                        children: [
                          for (
                            var index = 0;
                            index < pages.length;
                            index++
                          ) ...[
                            if (index > 0) const SizedBox(height: 12),
                            DecoratedBox(
                              key: _sourcePageKeys[index],
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(color: Colors.grey.shade300),
                                boxShadow: const [
                                  BoxShadow(
                                    blurRadius: 8,
                                    color: Color(0x1F000000),
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: _buildSourcePage(
                                pages[index],
                                index,
                                state,
                                sourceBoxes,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTextContent(_LearningTextState state, double maxWidth) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFDDE3EA)),
        borderRadius: BorderRadius.zero,
      ),
      child: Listener(
        key: _zoomViewportKey,
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) => _handleTextTouchDown(event, maxWidth),
        onPointerMove: (event) => _handleTextTouchMove(event, maxWidth),
        onPointerUp: _finishTextTouch,
        onPointerCancel: _finishTextTouch,
        child: SelectableText.rich(
          TextSpan(children: _buildTextSpans(state)),
          key: _textKey,
          onSelectionChanged: (selection, cause) {
            final suppressUntil = _suppressSelectionUntil;
            if (suppressUntil != null &&
                DateTime.now().isBefore(suppressUntil)) {
              return;
            }
            if (selection.isCollapsed) {
              _clearSelection();
              return;
            }
            widget.onSidePanelModeChanged(_SidePanelMode.selection);
            setState(() {
              _selectionStart = selection.start;
              _selectionEnd = selection.end;
            });
          },
        ),
      ),
    );
  }

  bool _itemHasJapaneseMeaning(LexicalItemResult item) {
    // 未知語への分類は現在DBから取得できた日本語訳だけを正とする。
    // 解析レスポンスのhasMeaningは生成前の古い状態になり得るため使わない。
    return widget.lookupCache.hasJapaneseMeaningFor(item);
  }

  @override
  Widget build(BuildContext context) {
    final state = _learningTextState;
    final result = _result;
    final panelItems = switch (widget.sidePanelMode) {
      _SidePanelMode.unknown =>
        result?.items
                .where(
                  (item) => !item.isLearned && _itemHasJapaneseMeaning(item),
                )
                .toList() ??
            const [],
      _SidePanelMode.untranslated =>
        result?.items
                .where(
                  (item) => !item.isLearned && !_itemHasJapaneseMeaning(item),
                )
                .toList() ??
            const [],
      _SidePanelMode.known =>
        result?.items.where((item) => item.isLearned).toList() ?? const [],
      _SidePanelMode.all => result?.items ?? const [],
      _ => state.selectedItems(),
    };
    final panelTitle = switch (widget.sidePanelMode) {
      _SidePanelMode.unknown => '未知語',
      _SidePanelMode.untranslated => '訳なし',
      _SidePanelMode.known => '既知語',
      _SidePanelMode.all => '全体',
      _ => '選択範囲',
    };
    final sidePanel = _SelectionMeaningPanel(
      title: panelTitle,
      items: panelItems,
      onCopy:
          widget.sidePanelMode == _SidePanelMode.selection &&
              _selectedText.isNotEmpty
          ? _copySelection
          : null,
      userId: ref.read(appSessionProvider).userId,
      material: widget.material,
      onAdded: () {
        ref.read(wordsProvider.notifier).load(isLearned: false);
        ref.read(wordbookLibraryProvider.notifier).load(force: true);
        ref
            .read(materialLibraryProvider.notifier)
            .analyzeMaterial(widget.material.id, force: true);
      },
      onShowDetails: (item, position) =>
          _showMeaningPopover(item, position, focusOccurrence: true),
      lookupCache: widget.lookupCache,
    );
    final overview = _AnalysisHeader(
      analysis: widget.analysis,
      hasJapaneseMeaning: _itemHasJapaneseMeaning,
      compact: MediaQuery.sizeOf(context).width < 760,
      onCollapse: MediaQuery.sizeOf(context).width < 760
          ? () => setState(() => _mobileOverviewCollapsed = true)
          : null,
      onShowItems: (mode) => widget.onSidePanelModeChanged(
        widget.sidePanelMode == mode ? null : mode,
      ),
    );
    final showSource =
        widget.mode == _MaterialDisplayMode.original &&
        canDisplayOriginalSource(widget.material);

    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = constraints.maxWidth < 760
            ? constraints.maxWidth
            : constraints.maxWidth - 356;
        final rawContent = showSource
            ? _buildSourceContent(state)
            : _buildTextContent(state, contentWidth);
        final content = showSource
            ? rawContent
            : Scrollbar(
                controller: _textScrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _textScrollController,
                  primary: false,
                  child: rawContent,
                ),
              );

        if (constraints.maxWidth < 760) {
          final maxPanelHeight = math.max(120.0, constraints.maxHeight * 0.7);
          final panelHeight = _mobilePanelHeight
              .clamp(120.0, maxPanelHeight)
              .toDouble();
          final mobileContent = _mobileOverviewCollapsed
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    content,
                    Positioned(
                      top: widget.mobileAppBarCollapsed
                          ? MediaQuery.paddingOf(context).top + 48
                          : 4,
                      right: 4,
                      width: 40,
                      height: 40,
                      child: _CollapsedAppBarButton(
                        tooltip: 'Progress Overviewを表示',
                        icon: Icons.analytics_outlined,
                        onPressed: () =>
                            setState(() => _mobileOverviewCollapsed = false),
                      ),
                    ),
                  ],
                )
              : content;
          return Column(
            children: [
              if (!_mobileOverviewCollapsed) ...[
                overview,
                const SizedBox(height: 8),
              ],
              Expanded(child: mobileContent),
              if (widget.sidePanelMode != null)
                SizedBox(
                  height: panelHeight,
                  child: Column(
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragUpdate: (details) {
                          setState(() {
                            _mobilePanelHeight =
                                (_mobilePanelHeight - details.delta.dy)
                                    .clamp(120.0, maxPanelHeight)
                                    .toDouble();
                          });
                        },
                        child: SizedBox(
                          height: 22,
                          child: Center(
                            child: Container(
                              width: 44,
                              height: 4,
                              decoration: BoxDecoration(
                                color: const Color(0xFF9AA7B2),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(child: sidePanel),
                    ],
                  ),
                ),
            ],
          );
        }

        final row = Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: content),
            const SizedBox(width: 12),
            SizedBox(
              width: 344,
              child: Column(
                children: [
                  overview,
                  const SizedBox(height: 8),
                  Expanded(child: sidePanel),
                ],
              ),
            ),
          ],
        );
        return row;
      },
    );
  }
}

String _sourceTypeForMaterial(MaterialItem material) {
  return material.sourceMimeType == 'application/pdf'
      ? 'pdf_material'
      : 'image_material';
}

class _LearningTextState {
  final String text;
  final ExtractWordsResult? result;
  final int? selectionStart;
  final int? selectionEnd;
  late final List<_MarkedRange> ranges = _markedRangesForText(
    text: text,
    result: result,
    selectionStart: selectionStart,
    selectionEnd: selectionEnd,
  );

  _LearningTextState({
    required this.text,
    required this.result,
    required this.selectionStart,
    required this.selectionEnd,
  });

  List<LexicalItemResult> selectedItems() {
    final selected = <LexicalItemResult>[];
    final seen = <String>{};
    for (final range in ranges.where((range) => range.isSelected)) {
      final item = range.item;
      final key =
          '${item.text}:${item.partOfSpeech}:${item.partOfSpeechDetail}';
      if (seen.add(key)) {
        selected.add(item);
      }
    }
    return selected;
  }

  List<_LearningTextSegment> segmentsForRange(
    int start,
    int end, {
    String? hoveredRangeKey,
  }) {
    if (start >= end) {
      return const [];
    }
    final boundaries = <int>{start, end};
    final selection = _normalizedSelection;
    if (selection != null && start < selection.end && end > selection.start) {
      boundaries
        ..add(math.max(start, selection.start))
        ..add(math.min(end, selection.end));
    }
    for (final range in ranges) {
      if (start >= range.end || end <= range.start) {
        continue;
      }
      boundaries
        ..add(math.max(start, range.start))
        ..add(math.min(end, range.end));
    }

    final sorted = boundaries.toList()..sort();
    final segments = <_LearningTextSegment>[];
    for (var index = 0; index < sorted.length - 1; index++) {
      final segmentStart = sorted[index];
      final segmentEnd = sorted[index + 1];
      if (segmentStart >= segmentEnd) {
        continue;
      }
      final range = _rangeCoveringSegment(ranges, segmentStart, segmentEnd);
      final isHovered =
          range != null &&
          range.kind == _MarkedRangeKind.word &&
          hoveredRangeKey == _markedRangeKey(range.start, range.end);
      segments.add(
        _LearningTextSegment(
          start: segmentStart,
          end: segmentEnd,
          range: range,
          visual: markerForRange(
            segmentStart,
            segmentEnd,
            isHovered: isHovered,
          ),
        ),
      );
    }
    return segments;
  }

  _MarkedRange? wordRangeAtOffset(int offset) {
    for (final range in ranges.where(
      (range) => range.kind == _MarkedRangeKind.word,
    )) {
      if (offset >= range.start && offset < range.end) {
        return range;
      }
    }
    return null;
  }

  _MarkedRange? rangeForKey(String key) {
    for (final range in ranges) {
      if (_markedRangeKey(range.start, range.end) == key) {
        return range;
      }
    }
    return null;
  }

  _MarkedRange? firstRangeForItem(LexicalItemResult item) {
    final matches = rangesForItem(item);
    return matches.isEmpty ? null : matches.first;
  }

  List<_MarkedRange> rangesForItem(LexicalItemResult item) {
    return ranges
        .where(
          (range) =>
              range.kind == _MarkedRangeKind.word &&
              range.item.text == item.text &&
              range.item.partOfSpeech == item.partOfSpeech,
        )
        .toList()
      ..sort((left, right) => left.start.compareTo(right.start));
  }

  _MarkerVisual markerForRange(int start, int end, {bool isHovered = false}) {
    final range = _rangeCoveringSegment(ranges, start, end);
    return _MarkerVisual(
      kind: range?.kind,
      isCompleteSelection: range?.isSelected ?? false,
      isHovered: isHovered,
      touchesSelection: _selectionOverlaps(start, end),
    );
  }

  _TextRange? get _normalizedSelection {
    final rawStart = selectionStart;
    final rawEnd = selectionEnd;
    if (rawStart == null || rawEnd == null || rawStart == rawEnd) {
      return null;
    }
    return _TextRange(math.min(rawStart, rawEnd), math.max(rawStart, rawEnd));
  }

  bool _selectionOverlaps(int start, int end) {
    final selection = _normalizedSelection;
    if (selection == null) {
      return false;
    }
    return start < selection.end && end > selection.start;
  }
}

class _LearningTextSegment {
  final int start;
  final int end;
  final _MarkedRange? range;
  final _MarkerVisual visual;

  const _LearningTextSegment({
    required this.start,
    required this.end,
    required this.range,
    required this.visual,
  });
}

class _MarkerVisual {
  final _MarkedRangeKind? kind;
  final bool isCompleteSelection;
  final bool isHovered;
  final bool touchesSelection;

  const _MarkerVisual({
    required this.kind,
    required this.isCompleteSelection,
    required this.isHovered,
    required this.touchesSelection,
  });

  Color? get backgroundColor => _markerBackgroundColor(
    kind: kind,
    isCompleteSelection: isCompleteSelection,
    isHovered: isHovered,
    touchesSelection: touchesSelection,
  );
}

List<_MarkedRange> _markedRangesForText({
  required String text,
  required ExtractWordsResult? result,
  required int? selectionStart,
  required int? selectionEnd,
}) {
  final items = result?.items ?? const <LexicalItemResult>[];
  final hasSelection =
      selectionStart != null &&
      selectionEnd != null &&
      selectionStart != selectionEnd;
  final start = hasSelection ? math.min(selectionStart, selectionEnd) : -1;
  final end = hasSelection ? math.max(selectionStart, selectionEnd) : -1;
  final ranges = <_MarkedRange>[];

  // 熟語は範囲選択された場合だけ表示する。壊れたoffsetは使用しない。
  for (final item in items.where((item) => item.kind == 'phrase')) {
    for (final occurrence in item.occurrences) {
      if (!_isValidTextRange(text, occurrence.start, occurrence.end)) {
        continue;
      }
      final isSelected =
          hasSelection && occurrence.start >= start && occurrence.end <= end;
      if (!isSelected) {
        continue;
      }
      ranges.add(
        _MarkedRange(
          start: occurrence.start,
          end: occurrence.end,
          item: item,
          kind: _MarkedRangeKind.phrase,
          isSelected: true,
        ),
      );
    }
  }

  // spaCyが英単語として解析した正確なoccurrenceだけをマーカーにする。
  // ASCIIらしい文字列をUI側で推測しないため、日本語や記号のboxに誤った
  // 英語の意味が紐づかない。複数形もoccurrence.endを使うため末尾sを含む。
  for (final item in items.where((item) => item.kind == 'word')) {
    for (final occurrence in item.occurrences) {
      if (!_isValidTextRange(text, occurrence.start, occurrence.end)) {
        continue;
      }
      final surface = text.substring(occurrence.start, occurrence.end);
      if (!shouldTreatTextAsLexicalTarget(surface)) {
        continue;
      }
      final normalizedSurface = _normalizeLookupWord(surface);
      final normalizedForms = <String>{
        _normalizeLookupWord(item.text),
        ...item.surfaceForms.map(_normalizeLookupWord),
      };
      if (!normalizedForms.contains(normalizedSurface)) {
        continue;
      }
      final overlapsSelectedPhrase = ranges.any(
        (range) =>
            range.kind == _MarkedRangeKind.phrase &&
            occurrence.start >= range.start &&
            occurrence.end <= range.end,
      );
      if (overlapsSelectedPhrase) {
        continue;
      }
      ranges.add(
        _MarkedRange(
          start: occurrence.start,
          end: occurrence.end,
          item: item,
          kind: _MarkedRangeKind.word,
          isSelected:
              hasSelection &&
              occurrence.start >= start &&
              occurrence.end <= end,
        ),
      );
    }
  }

  ranges.sort((a, b) {
    final startCompare = a.start.compareTo(b.start);
    if (startCompare != 0) return startCompare;
    return b.end.compareTo(a.end);
  });
  return ranges;
}

bool _isValidTextRange(String text, int start, int end) {
  return start >= 0 && end > start && end <= text.length;
}

class _ResolvedSourceBox {
  final SourceWordBox box;
  final _TextRange textRange;

  const _ResolvedSourceBox({required this.box, required this.textRange});
}

List<_ResolvedSourceBox> _resolveSourceBoxes(
  List<SourceWordBox> boxes,
  String text,
) {
  if (boxes.isEmpty || text.isEmpty) {
    return const [];
  }

  final resolved = <_ResolvedSourceBox>[];
  for (final box in boxes) {
    final range = _validatedExplicitSourceRange(box, text);
    if (range == null) {
      continue;
    }
    resolved.add(_ResolvedSourceBox(box: box, textRange: range));
  }
  resolved.sort((a, b) {
    final pageCompare = a.box.pageIndex.compareTo(b.box.pageIndex);
    if (pageCompare != 0) {
      return pageCompare;
    }
    return a.textRange.start.compareTo(b.textRange.start);
  });
  return resolved;
}

_TextRange? _validatedExplicitSourceRange(SourceWordBox box, String text) {
  final start = box.start;
  final end = box.end;
  if (start == null ||
      end == null ||
      start < 0 ||
      end <= start ||
      end > text.length) {
    return null;
  }

  // 原本側で文字位置を検索・推測し直さない。
  // OCR時に同じ word_boxes から生成された start/end が、
  // 本文中の同じ文字列を指している場合だけ使用する。
  final source = _normalizeSourceText(box.text);
  final target = _normalizeSourceText(text.substring(start, end));
  if (source.isEmpty || source != target) {
    return null;
  }
  return _TextRange(start, end);
}

String _normalizeSourceText(String value) {
  return value.replaceAll('’', "'").replaceAll(RegExp(r'\s+'), ' ').trim();
}

Rect _selectionRectWithinBox(
  _TextRange boxRange,
  _TextRange overlap,
  double boxWidth,
) {
  final length = math.max(1, boxRange.end - boxRange.start);
  final leftRatio = (overlap.start - boxRange.start) / length;
  final rightRatio = (overlap.end - boxRange.start) / length;
  return Rect.fromLTWH(
    leftRatio * boxWidth,
    0,
    (rightRatio - leftRatio) * boxWidth,
    1,
  );
}

class _TextRange {
  final int start;
  final int end;

  const _TextRange(this.start, this.end);
}

class _AnalysisHeader extends StatelessWidget {
  final AsyncValue<ExtractWordsResult>? analysis;
  final bool Function(LexicalItemResult item) hasJapaneseMeaning;
  final ValueChanged<_SidePanelMode> onShowItems;
  final VoidCallback? onCollapse;
  final bool compact;

  const _AnalysisHeader({
    required this.analysis,
    required this.hasJapaneseMeaning,
    required this.onShowItems,
    this.onCollapse,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (analysis == null) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 18),
            SizedBox(width: 8),
            Expanded(child: Text('まだ解析されていません')),
          ],
        ),
      );
    }
    if (analysis is AsyncLoading) {
      return const LinearProgressIndicator(minHeight: 3);
    }

    return analysis!.when(
      loading: () => const LinearProgressIndicator(minHeight: 3),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.error_outline, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('解析に失敗しました: $error')),
          ],
        ),
      ),
      data: (result) {
        final knownCount = result.items.where((item) => item.isLearned).length;
        final untranslatedCount = result.items
            .where((item) => !item.isLearned && !hasJapaneseMeaning(item))
            .length;
        final translatedUnknownCount = result.items
            .where((item) => !item.isLearned && hasJapaneseMeaning(item))
            .length;
        final translatedTotal = knownCount + translatedUnknownCount;
        final coverageRate = translatedTotal == 0
            ? 0.0
            : knownCount / translatedTotal;
        final percent = (coverageRate * 100).round();
        return Container(
          width: double.infinity,
          color: Colors.white,
          padding: compact
              ? const EdgeInsets.all(6)
              : const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(compact ? 10 : 16),
              child: Row(
                children: [
                  SquareProgressIndicator(
                    value: coverageRate,
                    size: compact ? 52 : 62,
                    strokeWidth: compact ? 5 : 6,
                    color: theme.colorScheme.secondary,
                    backgroundColor: const Color(0xFFDDE3EA),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '$percent',
                            style: TextStyle(
                              color: theme.colorScheme.secondary,
                              fontSize: compact ? 19 : 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const TextSpan(
                            text: '%',
                            style: TextStyle(color: Colors.black, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: compact ? 10 : 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Progress Overview',
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                            if (onCollapse != null)
                              IconButton(
                                tooltip: '操作バーと進捗を折りたたむ',
                                visualDensity: VisualDensity.compact,
                                constraints: const BoxConstraints.tightFor(
                                  width: 32,
                                  height: 32,
                                ),
                                padding: EdgeInsets.zero,
                                onPressed: onCollapse,
                                icon: const Icon(
                                  Icons.keyboard_arrow_up,
                                  size: 20,
                                ),
                              ),
                          ],
                        ),
                        SizedBox(height: compact ? 5 : 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _AnalysisFilterButton(
                              onPressed: () => onShowItems(_SidePanelMode.all),
                              icon: Icons.format_list_bulleted,
                              backgroundColor: const Color(0xFFD4E3FF),
                              foregroundColor: const Color(0xFF004883),
                              label: Text('全体 ${result.items.length}'),
                            ),
                            _AnalysisFilterButton(
                              onPressed: () =>
                                  onShowItems(_SidePanelMode.known),
                              icon: Icons.check_circle_outline,
                              backgroundColor: const Color(0xFFD4E3FF),
                              foregroundColor: const Color(0xFF004883),
                              label: Text('既知 $knownCount'),
                            ),
                            _AnalysisFilterButton(
                              icon: Icons.radio_button_unchecked,
                              backgroundColor: const Color(0xFFD4E3FF),
                              foregroundColor: const Color(0xFF004883),
                              label: Text('未知 $translatedUnknownCount'),
                              onPressed: () =>
                                  onShowItems(_SidePanelMode.unknown),
                            ),
                            _AnalysisFilterButton(
                              icon: Icons.translate_outlined,
                              backgroundColor: const Color(0xFFD4E3FF),
                              foregroundColor: const Color(0xFF004883),
                              label: Text('訳なし $untranslatedCount'),
                              onPressed: () =>
                                  onShowItems(_SidePanelMode.untranslated),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AnalysisFilterButton extends StatelessWidget {
  final IconData icon;
  final Widget label;
  final VoidCallback onPressed;
  final Color backgroundColor;
  final Color foregroundColor;

  const _AnalysisFilterButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.zero,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: foregroundColor),
              const SizedBox(width: 5),
              DefaultTextStyle(
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                  color: foregroundColor,
                  fontWeight: FontWeight.w700,
                ),
                child: label,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectionMeaningPanel extends StatefulWidget {
  final String title;
  final List<LexicalItemResult> items;
  final VoidCallback? onCopy;
  final String userId;
  final MaterialItem material;
  final VoidCallback onAdded;
  final void Function(LexicalItemResult item, Offset globalPosition)
  onShowDetails;
  final _WordLookupCache lookupCache;

  const _SelectionMeaningPanel({
    this.title = '選択範囲',
    required this.items,
    this.onCopy,
    required this.userId,
    required this.material,
    required this.onAdded,
    required this.onShowDetails,
    required this.lookupCache,
  });

  @override
  State<_SelectionMeaningPanel> createState() => _SelectionMeaningPanelState();
}

class _SelectionMeaningPanelState extends State<_SelectionMeaningPanel> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final visibleItems = widget.items
        .where((item) => widget.lookupCache.matchesSearch(item, _query))
        .toList();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFDDE3EA)),
        borderRadius: BorderRadius.zero,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: const Color(0xFF041627),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 34,
                    child: TextField(
                      onChanged: (value) => setState(() => _query = value),
                      textInputAction: TextInputAction.search,
                      decoration: const InputDecoration(
                        hintText: '検索',
                        isDense: true,
                        prefixIcon: Icon(Icons.search, size: 17),
                        prefixIconConstraints: BoxConstraints(minWidth: 30),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                if (widget.onCopy != null)
                  IconButton.outlined(
                    tooltip: '選択範囲をコピー',
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.onCopy,
                    icon: const Icon(Icons.copy, size: 18),
                  ),
                _BatchAddButton(
                  items: visibleItems,
                  userId: widget.userId,
                  material: widget.material,
                  onAdded: widget.onAdded,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: visibleItems.isEmpty
                  ? const Center(child: Text('該当する単語はありません'))
                  : ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: visibleItems.length,
                      itemBuilder: (context, index) {
                        final item = visibleItems[index];
                        return _SelectionMeaningTile(
                          item: item,
                          userId: widget.userId,
                          material: widget.material,
                          onAdded: widget.onAdded,
                          onShowDetails: widget.onShowDetails,
                          lookupCache: widget.lookupCache,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BatchAddButton extends StatefulWidget {
  final List<LexicalItemResult> items;
  final String userId;
  final MaterialItem material;
  final VoidCallback onAdded;

  const _BatchAddButton({
    required this.items,
    required this.userId,
    required this.material,
    required this.onAdded,
  });

  @override
  State<_BatchAddButton> createState() => _BatchAddButtonState();
}

class _BatchAddButtonState extends State<_BatchAddButton> {
  bool _isAdding = false;

  Future<void> _addAll({bool forceWordbook = false}) async {
    if (_isAdding || widget.items.isEmpty) return;
    final wordbookId = await _selectWordbookForMaterial(
      context,
      widget.material,
      forceSelection: forceWordbook,
    );
    if (!mounted) return;
    if (wordbookId == null) return;
    final wordbookName = _wordbookName(context, wordbookId);
    setState(() => _isAdding = true);
    try {
      await VocamineApiClient().addItemsToWordbook(
        userId: widget.userId,
        items: widget.items,
        sourceType: _sourceTypeForMaterial(widget.material),
        sourceMaterialId: widget.material.id,
        sourceFolderId: widget.material.folderId,
        sourceLabel: widget.material.title,
        wordbookId: wordbookId,
      );
      AppMessenger.show('「$wordbookName」に一括登録しました');
      if (!mounted) return;
      widget.onAdded();
    } catch (error) {
      AppMessenger.show('一括登録に失敗しました: $error');
    } finally {
      if (mounted) {
        setState(() => _isAdding = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filled(
          tooltip: '表示中の単語を一括登録',
          onPressed: _isAdding || widget.items.isEmpty ? null : () => _addAll(),
          icon: _isAdding
              ? const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.playlist_add_check, size: 18),
        ),
        IconButton.outlined(
          tooltip: '別の単語帳へ一括登録',
          onPressed: _isAdding || widget.items.isEmpty
              ? null
              : () => _addAll(forceWordbook: true),
          icon: const Icon(Icons.drive_file_move_outline, size: 18),
        ),
      ],
    );
  }
}

enum _MarkedRangeKind { word, phrase }

Color? _markerBackgroundColor({
  required _MarkedRangeKind? kind,
  required bool isCompleteSelection,
  required bool isHovered,
  required bool touchesSelection,
}) {
  if (isCompleteSelection && kind == _MarkedRangeKind.phrase) {
    return const Color(0xFF86C77A).withValues(alpha: 0.48);
  }
  if (isCompleteSelection && kind == _MarkedRangeKind.word) {
    return const Color(0xFFFFE16D).withValues(alpha: 0.62);
  }
  if (touchesSelection) {
    return const Color(0xFFA4C9FF).withValues(alpha: 0.42);
  }
  if (isHovered && kind == _MarkedRangeKind.word) {
    return const Color(0xFFFFE16D).withValues(alpha: 0.42);
  }
  return null;
}

String _markedRangeKey(int start, int end) => '$start:$end';

class _MarkedRange {
  final int start;
  final int end;
  final LexicalItemResult item;
  final _MarkedRangeKind kind;
  final bool isSelected;

  const _MarkedRange({
    required this.start,
    required this.end,
    required this.item,
    required this.kind,
    required this.isSelected,
  });
}

_MarkedRange? _rangeCoveringSegment(
  List<_MarkedRange> ranges,
  int start,
  int end,
) {
  _MarkedRange? best;
  for (final range in ranges) {
    if (start < range.start || end > range.end) {
      continue;
    }
    if (best == null || (range.end - range.start) < (best.end - best.start)) {
      best = range;
    }
  }
  return best;
}

class _MeaningPopover extends StatefulWidget {
  final LexicalItemResult item;
  final Future<WordLookupResult> future;
  final BuildContext hostContext;
  final Rect anchorRect;
  final String userId;
  final MaterialItem material;
  final VoidCallback onAdded;
  final Object tapRegionGroupId;
  final VoidCallback onClose;

  const _MeaningPopover({
    required this.item,
    required this.future,
    required this.hostContext,
    required this.anchorRect,
    required this.userId,
    required this.material,
    required this.onAdded,
    required this.tapRegionGroupId,
    required this.onClose,
  });

  @override
  State<_MeaningPopover> createState() => _MeaningPopoverState();
}

class _MeaningPopoverState extends State<_MeaningPopover> {
  final _api = VocamineApiClient();
  final Set<int> _adding = {};
  final Set<int> _added = {};
  bool _isMarkingKnown = false;
  late bool _isKnown;

  @override
  void initState() {
    super.initState();
    _isKnown = widget.item.isLearned;
  }

  Future<void> _markKnown() async {
    if (_isMarkingKnown || _isKnown) return;
    setState(() => _isMarkingKnown = true);
    try {
      await _api.addItemsToWordbook(
        userId: widget.userId,
        items: [widget.item],
        isLearned: true,
        sourceType: _sourceTypeForMaterial(widget.material),
        sourceMaterialId: widget.material.id,
        sourceFolderId: widget.material.folderId,
        sourceLabel: widget.material.title,
      );
      AppMessenger.show('学習済み単語に追加しました');
      if (!mounted) return;
      setState(() => _isKnown = true);
      widget.onAdded();
    } catch (error) {
      AppMessenger.show('学習済みへの追加に失敗しました: $error');
    } finally {
      if (mounted) setState(() => _isMarkingKnown = false);
    }
  }

  Future<void> _addMeaning(int meaningId, {bool forceWordbook = false}) async {
    final hostContext = widget.hostContext;
    final material = widget.material;
    final userId = widget.userId;
    final onAdded = widget.onAdded;
    if (!hostContext.mounted) return;
    if (_adding.contains(meaningId) ||
        (!forceWordbook && _added.contains(meaningId))) {
      return;
    }
    setState(() => _adding.add(meaningId));
    String? wordbookId;
    try {
      // このカード自体が OverlayEntry なので、その上からダイアログを
      // 開く前に閉じる。これで登録先選択がポップアップの背面に隠れない。
      if (forceWordbook) widget.onClose();
      wordbookId = await _selectWordbookForMaterial(
        hostContext,
        material,
        forceSelection: forceWordbook,
        anchorRect: forceWordbook ? null : widget.anchorRect,
        tapRegionGroupId: forceWordbook ? null : widget.tapRegionGroupId,
      );
      if (!mounted || !hostContext.mounted) return;
    } catch (error) {
      if (mounted) setState(() => _adding.remove(meaningId));
      AppMessenger.show('登録先の取得に失敗しました: $error');
      return;
    }
    if (wordbookId == null) {
      if (mounted) setState(() => _adding.remove(meaningId));
      widget.onClose();
      return;
    }
    final wordbookName = _wordbookName(hostContext, wordbookId);
    if (mounted) setState(() => _added.add(meaningId));
    try {
      await _api.addMeaningToWordbook(
        userId: userId,
        meaningId: meaningId,
        sourceType: _sourceTypeForMaterial(material),
        sourceMaterialId: material.id,
        sourceFolderId: material.folderId,
        sourceLabel: material.title,
        wordbookId: wordbookId,
      );
      AppMessenger.show('「$wordbookName」に追加しました');
      if (!mounted || !hostContext.mounted) return;
      _registeredMeaningIdsByMaterial
          .putIfAbsent(material.id, () => <int>{})
          .add(meaningId);
      onAdded();
    } catch (error) {
      if (mounted) setState(() => _added.remove(meaningId));
      AppMessenger.show('追加に失敗しました: $error');
    } finally {
      if (mounted) setState(() => _adding.remove(meaningId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.zero,
      color: Theme.of(context).colorScheme.surface,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 460),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.zero,
          border: Border.all(color: const Color(0xFFDDE3EA)),
        ),
        child: FutureBuilder<WordLookupResult>(
          future: widget.future,
          builder: (context, snapshot) {
            final meanings = _sortMeaningsForContext(
              snapshot.data?.meanings ?? const [],
            );
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.item.text,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: '閉じる',
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
                Text(
                  _contextPartOfSpeechLabel(widget.item),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (!_isKnown) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 7,
                        ),
                      ),
                      onPressed: _isMarkingKnown ? null : _markKnown,
                      icon: _isMarkingKnown
                          ? const SizedBox.square(
                              dimension: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check, size: 16),
                      label: const Text('知っている'),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                if (snapshot.connectionState != ConnectionState.done)
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('意味を取得中…'),
                      SizedBox(height: 6),
                      LinearProgressIndicator(minHeight: 2),
                    ],
                  )
                else if (meanings.isEmpty)
                  const Text('意味がまだ見つかりませんでした')
                else
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (final meaning in meanings)
                            _PopoverMeaningCard(
                              meaning: meaning,
                              isContextPos:
                                  meaning.partOfSpeech ==
                                  widget.item.partOfSpeech,
                              isAdding: _adding.contains(meaning.id),
                              isAdded:
                                  _added.contains(meaning.id) ||
                                  (_registeredMeaningIdsByMaterial[widget
                                              .material
                                              .id]
                                          ?.contains(meaning.id) ??
                                      false),
                              onAdd: () => _addMeaning(meaning.id),
                              onAddElsewhere: () =>
                                  _addMeaning(meaning.id, forceWordbook: true),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  List<MeaningInfo> _sortMeaningsForContext(List<MeaningInfo> meanings) {
    final sorted = [...meanings];
    sorted.sort(
      (a, b) => _compareMeaningForContext(a, b, widget.item.partOfSpeech),
    );
    return sorted;
  }

  String _contextPartOfSpeechLabel(LexicalItemResult item) {
    final base = partOfSpeechLabel(item.partOfSpeech);
    final detail = partOfSpeechDetailLabel(item.partOfSpeechDetail);
    if (detail == null) {
      return base;
    }
    return '$base（$detail）';
  }
}

class _PopoverMeaningCard extends StatelessWidget {
  final MeaningInfo meaning;
  final bool isContextPos;
  final bool isAdding;
  final bool isAdded;
  final VoidCallback onAdd;
  final VoidCallback onAddElsewhere;

  const _PopoverMeaningCard({
    required this.meaning,
    required this.isContextPos,
    required this.isAdding,
    required this.isAdded,
    required this.onAdd,
    required this.onAddElsewhere,
  });

  @override
  Widget build(BuildContext context) {
    final example = _firstExample(meaning);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isContextPos ? const Color(0xFFD4E3FF) : const Color(0xFFF7F9FB),
        borderRadius: BorderRadius.zero,
        border: Border.all(
          color: isContextPos
              ? const Color(0xFF68ABFF)
              : const Color(0xFFDDE3EA),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              AcademicTag(label: partOfSpeechLabel(meaning.partOfSpeech)),
              if (isContextPos)
                const AcademicTag(
                  emphasized: true,
                  icon: Icons.check,
                  label: 'この文の品詞',
                ),
              if (meaning.source.isNotEmpty)
                AcademicTag(label: _sourceLabel(meaning.source)),
              if (_transitivityLabel(meaning.transitivity) != null)
                AcademicTag(label: _transitivityLabel(meaning.transitivity)!),
              if (_countabilityLabel(meaning.countability) != null)
                AcademicTag(label: _countabilityLabel(meaning.countability)!),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            meaning.definitionJa?.trim().isNotEmpty == true
                ? meaning.definitionJa!
                : '日本語訳が得られませんでした',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (meaning.definitionEn?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Text(
              meaning.definitionEn!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
          if (example != null) ...[
            const SizedBox(height: 8),
            _ExampleView(example: example),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: _WordbookAddIconButton(
              isAdding: isAdding,
              isAdded: isAdded,
              onAdd: onAdd,
              onAddElsewhere: onAddElsewhere,
            ),
          ),
        ],
      ),
    );
  }

  ExampleSentenceInfo? _firstExample(MeaningInfo meaning) {
    for (final example in meaning.exampleSentences) {
      if (example.sentence.trim().isNotEmpty) {
        return example;
      }
    }
    return null;
  }

  static String _sourceLabel(String source) {
    switch (source) {
      case 'wiktionary':
        return 'Wiktionary';
      case 'grammar':
        return 'Grammar';
      case 'gemini':
        return 'Gemini';
      case 'cefr_j':
        return 'CEFR-J';
      case 'phave_list':
        return 'PHaVE List';
      case 'phrase_list':
        return 'Phrase List';
      case 'academic_collocation_list':
        return 'Academic Collocation List';
      case 'manual':
        return 'Manual';
      default:
        return source;
    }
  }
}

class _WordbookAddIconButton extends StatelessWidget {
  final bool isAdding;
  final bool isAdded;
  final VoidCallback? onAdd;
  final VoidCallback? onAddElsewhere;

  const _WordbookAddIconButton({
    required this.isAdding,
    required this.isAdded,
    required this.onAdd,
    required this.onAddElsewhere,
  });

  Future<void> _showContextMenu(
    BuildContext context,
    TapDownDetails details,
  ) async {
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        details.globalPosition.dx,
        details.globalPosition.dy,
        details.globalPosition.dx,
        details.globalPosition.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'default',
          enabled: onAdd != null && !isAdding && !isAdded,
          child: const ListTile(
            leading: Icon(Icons.playlist_add),
            title: Text('単語帳に追加'),
          ),
        ),
        PopupMenuItem(
          value: 'other',
          enabled: onAddElsewhere != null && !isAdding,
          child: const ListTile(
            leading: Icon(Icons.drive_file_move_outline),
            title: Text('別の単語帳に追加'),
          ),
        ),
      ],
    );
    if (action == 'default') onAdd?.call();
    if (action == 'other') onAddElsewhere?.call();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) => _showContextMenu(context, details),
      child: IconButton.filled(
        tooltip: isAdded ? '単語帳に追加済み（右クリックで登録先を選択）' : '単語帳に追加',
        visualDensity: VisualDensity.compact,
        onPressed: isAdding || isAdded ? null : onAdd,
        icon: isAdding
            ? const SizedBox.square(
                dimension: 15,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(isAdded ? Icons.check : Icons.playlist_add, size: 18),
      ),
    );
  }
}

class _SelectionMeaningTile extends StatefulWidget {
  final LexicalItemResult item;
  final String userId;
  final MaterialItem material;
  final VoidCallback onAdded;
  final void Function(LexicalItemResult item, Offset globalPosition)
  onShowDetails;
  final _WordLookupCache lookupCache;

  const _SelectionMeaningTile({
    required this.item,
    required this.userId,
    required this.material,
    required this.onAdded,
    required this.onShowDetails,
    required this.lookupCache,
  });

  @override
  State<_SelectionMeaningTile> createState() => _SelectionMeaningTileState();
}

class _SelectionMeaningTileState extends State<_SelectionMeaningTile> {
  final Set<int> _adding = {};
  final Set<int> _added = {};
  late Future<WordLookupResult> _future;
  late int _lookupRevision;
  bool _isMarkingKnown = false;
  bool _isKnown = false;

  @override
  void initState() {
    super.initState();
    _future = _createFuture();
    _lookupRevision = widget.lookupCache.revision;
    _isKnown = widget.item.isLearned;
  }

  @override
  void didUpdateWidget(covariant _SelectionMeaningTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.text != widget.item.text ||
        oldWidget.item.partOfSpeech != widget.item.partOfSpeech ||
        _lookupRevision != widget.lookupCache.revision) {
      _future = _createFuture();
      _lookupRevision = widget.lookupCache.revision;
      _isKnown = widget.item.isLearned;
    }
  }

  Future<WordLookupResult> _createFuture() {
    return widget.lookupCache.cachedLookup(widget.item);
  }

  Future<void> _addMeaning(int meaningId, {bool forceWordbook = false}) async {
    final wordbookId = await _selectWordbookForMaterial(
      context,
      widget.material,
      forceSelection: forceWordbook,
    );
    if (!mounted) return;
    if (wordbookId == null) return;
    final wordbookName = _wordbookName(context, wordbookId);
    setState(() => _adding.add(meaningId));
    try {
      await VocamineApiClient().addMeaningToWordbook(
        userId: widget.userId,
        meaningId: meaningId,
        sourceType: _sourceTypeForMaterial(widget.material),
        sourceMaterialId: widget.material.id,
        sourceFolderId: widget.material.folderId,
        sourceLabel: widget.material.title,
        wordbookId: wordbookId,
      );
      AppMessenger.show('「$wordbookName」に追加しました');
      if (!mounted) return;
      _registeredMeaningIdsByMaterial
          .putIfAbsent(widget.material.id, () => <int>{})
          .add(meaningId);
      if (!mounted) return;
      setState(() => _added.add(meaningId));
      widget.onAdded();
    } catch (error) {
      AppMessenger.show('追加に失敗しました: $error');
    } finally {
      if (mounted) {
        setState(() => _adding.remove(meaningId));
      }
    }
  }

  Future<void> _markKnown() async {
    if (_isMarkingKnown || _isKnown) return;
    setState(() => _isMarkingKnown = true);
    try {
      await VocamineApiClient().addItemsToWordbook(
        userId: widget.userId,
        items: [widget.item],
        isLearned: true,
        sourceType: _sourceTypeForMaterial(widget.material),
        sourceMaterialId: widget.material.id,
        sourceFolderId: widget.material.folderId,
        sourceLabel: widget.material.title,
      );
      AppMessenger.show('学習済み単語に追加しました');
      if (!mounted) return;
      setState(() => _isKnown = true);
      widget.onAdded();
    } catch (error) {
      AppMessenger.show('学習済みへの追加に失敗しました: $error');
    } finally {
      if (mounted) setState(() => _isMarkingKnown = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WordLookupResult>(
      future: _future,
      builder: (context, snapshot) {
        final meaning = _firstMeaning(snapshot.data?.meanings ?? const []);
        final isAdding = meaning != null && _adding.contains(meaning.id);
        final isAdded =
            meaning != null &&
            (_added.contains(meaning.id) ||
                (_registeredMeaningIdsByMaterial[widget.material.id]?.contains(
                      meaning.id,
                    ) ??
                    false));
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) =>
              widget.onShowDetails(widget.item, details.globalPosition),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      widget.item.text,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      _contextPartOfSpeechLabel(widget.item),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (snapshot.connectionState != ConnectionState.done)
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('意味を取得中…'),
                      SizedBox(height: 6),
                      LinearProgressIndicator(minHeight: 2),
                    ],
                  )
                else
                  Text(
                    meaning?.definitionJa?.trim().isNotEmpty == true
                        ? meaning!.definitionJa!
                        : '日本語訳が得られませんでした',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (!_isKnown)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 7,
                          ),
                        ),
                        onPressed: _isMarkingKnown ? null : _markKnown,
                        icon: _isMarkingKnown
                            ? const SizedBox.square(
                                dimension: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check, size: 18),
                        label: const Text('知っている'),
                      ),
                    const Spacer(),
                    _WordbookAddIconButton(
                      isAdding: isAdding,
                      isAdded: isAdded,
                      onAdd: meaning == null
                          ? null
                          : () => _addMeaning(meaning.id),
                      onAddElsewhere: meaning == null
                          ? null
                          : () => _addMeaning(meaning.id, forceWordbook: true),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  MeaningInfo? _firstMeaning(List<MeaningInfo> meanings) {
    final matching = meanings
        .where(
          (meaning) => _meaningMatchesItemPartOfSpeech(
            widget.item.partOfSpeech,
            meaning.partOfSpeech,
          ),
        )
        .toList();
    for (final meaning in matching) {
      if (_hasJapaneseDefinition(meaning)) return meaning;
    }
    if (matching.isNotEmpty) return matching.first;
    return null;
  }

  String _contextPartOfSpeechLabel(LexicalItemResult item) {
    final base = partOfSpeechLabel(item.partOfSpeech);
    final detail = partOfSpeechDetailLabel(item.partOfSpeechDetail);
    if (detail == null) {
      return base;
    }
    return '$base（$detail）';
  }
}

class _MeaningSheet extends StatefulWidget {
  final LexicalItemResult item;
  final Future<WordLookupResult> future;
  final String userId;
  final VoidCallback onAdded;

  const _MeaningSheet({
    required this.item,
    required this.future,
    required this.userId,
    required this.onAdded,
  });

  @override
  State<_MeaningSheet> createState() => _MeaningSheetState();
}

class _MeaningSheetState extends State<_MeaningSheet> {
  final _api = VocamineApiClient();
  final Set<int> _adding = {};
  final Set<int> _added = {};

  Future<void> _addMeaning(int meaningId) async {
    setState(() => _adding.add(meaningId));
    try {
      await _api.addMeaningToWordbook(
        userId: widget.userId,
        meaningId: meaningId,
      );
      AppMessenger.show('単語帳に追加しました');
      if (!mounted) return;
      setState(() => _added.add(meaningId));
      widget.onAdded();
    } catch (error) {
      AppMessenger.show('追加に失敗しました: $error');
    } finally {
      if (mounted) {
        setState(() => _adding.remove(meaningId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return FutureBuilder<WordLookupResult>(
          future: widget.future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('意味を取得中…'),
                  ],
                ),
              );
            }
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.all(20),
                child: Text('意味の取得に失敗しました: ${snapshot.error}'),
              );
            }

            final result = snapshot.data;
            final meanings = result?.meanings ?? [];
            final sortedMeanings = _sortMeaningsForContext(meanings);
            final contextPos = widget.item.partOfSpeech;
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                Row(
                  children: [
                    Icon(
                      widget.item.kind == 'phrase'
                          ? Icons.link
                          : Icons.text_fields,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.item.text,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                  ],
                ),
                if (contextPos.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'この文では ${_contextPartOfSpeechLabel(widget.item)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                if (meanings.isEmpty)
                  const Text('意味がまだ見つかりませんでした')
                else
                  ...sortedMeanings.map((meaning) {
                    final isAdding = _adding.contains(meaning.id);
                    final isAdded = _added.contains(meaning.id);
                    final isContextPos =
                        contextPos.isNotEmpty &&
                        meaning.partOfSpeech == contextPos;
                    return Card(
                      color: isContextPos
                          ? Theme.of(context).colorScheme.secondaryContainer
                          : null,
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                AcademicTag(
                                  label: _partOfSpeechLabel(
                                    meaning.partOfSpeech,
                                  ),
                                ),
                                if (isContextPos)
                                  const AcademicTag(
                                    emphasized: true,
                                    icon: Icons.check,
                                    label: 'この文の品詞',
                                  ),
                                if (meaning.source.isNotEmpty)
                                  AcademicTag(
                                    label: _sourceLabel(meaning.source),
                                  ),
                                if (_transitivityLabel(meaning.transitivity) !=
                                    null)
                                  AcademicTag(
                                    label: _transitivityLabel(
                                      meaning.transitivity,
                                    )!,
                                  ),
                                if (_countabilityLabel(meaning.countability) !=
                                    null)
                                  AcademicTag(
                                    label: _countabilityLabel(
                                      meaning.countability,
                                    )!,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            if (meaning.definitionJa?.isNotEmpty == true)
                              Text(
                                meaning.definitionJa!,
                                style: Theme.of(context).textTheme.titleMedium,
                              )
                            else
                              Text(
                                '日本語訳が得られませんでした',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            if (meaning.definitionEn?.isNotEmpty == true) ...[
                              const SizedBox(height: 8),
                              Text(
                                meaning.definitionEn!,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                      height: 1.45,
                                    ),
                              ),
                            ],
                            firstExample(meaning) == null
                                ? const SizedBox.shrink()
                                : Padding(
                                    padding: const EdgeInsets.only(top: 10),
                                    child: _ExampleView(
                                      example: firstExample(meaning)!,
                                    ),
                                  ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.icon(
                                onPressed: isAdding || isAdded
                                    ? null
                                    : () => _addMeaning(meaning.id),
                                icon: isAdding
                                    ? const SizedBox.square(
                                        dimension: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Icon(
                                        isAdded
                                            ? Icons.check
                                            : Icons.playlist_add,
                                      ),
                                label: Text(isAdded ? '追加済み' : '単語帳に追加'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            );
          },
        );
      },
    );
  }

  List<MeaningInfo> _sortMeaningsForContext(List<MeaningInfo> meanings) {
    final contextPos = widget.item.partOfSpeech;
    final sorted = [...meanings];
    if (contextPos.isEmpty) {
      return sorted;
    }
    sorted.sort((a, b) {
      return _compareMeaningForContext(a, b, contextPos);
    });
    return sorted;
  }

  ExampleSentenceInfo? firstExample(MeaningInfo meaning) {
    for (final example in meaning.exampleSentences) {
      if (example.sentence.trim().isNotEmpty) {
        return example;
      }
    }
    return null;
  }

  String _sourceLabel(String source) {
    switch (source) {
      case 'wiktionary':
        return 'Wiktionary';
      case 'grammar':
        return 'Grammar';
      case 'gemini':
        return 'Gemini';
      case 'cefr_j':
        return 'CEFR-J';
      case 'phave_list':
        return 'PHaVE List';
      case 'phrase_list':
        return 'Phrase List';
      case 'academic_collocation_list':
        return 'Academic Collocation List';
      case 'manual':
        return 'Manual';
      default:
        return source;
    }
  }

  String _partOfSpeechLabel(String partOfSpeech) =>
      partOfSpeechLabel(partOfSpeech);

  String _contextPartOfSpeechLabel(LexicalItemResult item) {
    final base = partOfSpeechLabel(item.partOfSpeech);
    final detail = partOfSpeechDetailLabel(item.partOfSpeechDetail);
    if (detail == null) {
      return base;
    }
    return '$base（$detail）';
  }
}

class _ExampleView extends StatelessWidget {
  final ExampleSentenceInfo example;

  const _ExampleView({required this.example});

  @override
  Widget build(BuildContext context) {
    final translated = example.translatedSentence?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(example.sentence),
        if (translated?.isNotEmpty == true) ...[
          const SizedBox(height: 4),
          Text(
            translated!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }
}
