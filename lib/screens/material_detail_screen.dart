import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/lexical_analysis.dart';
import '../models/material_item.dart';
import '../models/word_lookup.dart';
import '../providers/material_library_provider.dart';
import '../providers/words_provider.dart';
import '../providers/wordbook_library_provider.dart';
import '../services/app_session.dart';
import '../services/vocamine_api_client.dart';
import '../utils/part_of_speech_label.dart';

enum _MaterialDisplayMode { original, text }

enum _SidePanelMode { selection, unknown, known, all }

final Map<String, String?> _materialDefaultWordbookCache = {};
final Map<String, Set<int>> _registeredMeaningIdsByMaterial = {};
final Map<String, Future<String?>> _materialDefaultWordbookLoads = {};

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
  await api.setMaterialDefaultWordbook(
    userId: userId,
    materialId: material.id,
    wordbookId: wordbookId,
  );
  _materialDefaultWordbookCache[material.id] = wordbookId;
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
  Future<void>? _loading;

  String _normalizedWord(String value) =>
      value.trim().toLowerCase().replaceAll('’', "'");

  Future<void> loadStoredMeanings(Iterable<LexicalItemResult> items) {
    return _loading ??= _loadStoredMeanings(items);
  }

  Future<void> _loadStoredMeanings(Iterable<LexicalItemResult> items) async {
    final itemList = items.toList();
    final results = await VocamineApiClient().fetchStoredMeanings(itemList);
    for (final result in results) {
      _results[_normalizedWord(result.word)] = result;
    }
  }

  Future<WordLookupResult> cachedLookup(LexicalItemResult item) {
    final key = _normalizedWord(item.text);
    final cached = _results[key];
    if (cached != null) return SynchronousFuture(cached);
    final loading = _loading;
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

LexicalItemResult _fallbackLexicalItem(String word) {
  final cleaned = _cleanLookupWord(word);
  return LexicalItemResult(
    text: cleaned.toLowerCase().replaceAll('’', "'"),
    partOfSpeech: '',
    partOfSpeechDetail: null,
    surfaceForms: [cleaned.toLowerCase().replaceAll('’', "'")],
    occurrences: const [],
    kind: 'word',
    isLearned: false,
    hasMeaning: false,
  );
}

bool _hasJapaneseDefinition(MeaningInfo meaning) =>
    meaning.definitionJa?.trim().isNotEmpty == true;

String _normalizeLookupWord(String word) {
  return word.toLowerCase().replaceAll('’', "'");
}

String _cleanLookupWord(String word) {
  final match = _englishWordPattern.firstMatch(word);
  return match?.group(0) ?? word.trim();
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
  final _lookupCache = _WordLookupCache();
  final Set<String> _autoAnalysisRequested = {};
  bool _registeredMeaningsRequested = false;
  bool _storedMeaningsRequested = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
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
    final material = library.materials.firstWhere(
      (m) => m.id == widget.materialId,
    );
    if (!_registeredMeaningsRequested) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadRegisteredMeanings(material);
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
        if (_storedMeaningsRequested) return;
        _storedMeaningsRequested = true;
        _lookupCache
            .loadStoredMeanings(result.items)
            .then((_) {
              if (mounted) setState(() {});
            })
            .catchError((_) {
              _storedMeaningsRequested = false;
            });
      },
    );
    final hasSource = canDisplayOriginalSource(material);
    final effectiveMode = hasSource ? _displayMode : _MaterialDisplayMode.text;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: '再解析',
            onPressed: () => ref
                .read(materialLibraryProvider.notifier)
                .analyzeMaterial(widget.materialId, force: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ColoredBox(
        color: const Color(0xFFFCFAF6),
        child: Column(
          children: [
            _AnalysisHeader(
              analysis: analysis,
              onShowItems: (mode) => setState(() {
                _sidePanelMode = _sidePanelMode == mode ? null : mode;
              }),
            ),
            const Divider(height: 1),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Color(0xFFE3DED3))),
              ),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedButton<_MaterialDisplayMode>(
                    style: ButtonStyle(
                      shape: WidgetStatePropertyAll(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    segments: const [
                      ButtonSegment(
                        value: _MaterialDisplayMode.original,
                        icon: Icon(Icons.description_outlined),
                        label: Text('原本'),
                      ),
                      ButtonSegment(
                        value: _MaterialDisplayMode.text,
                        icon: Icon(Icons.text_fields),
                        label: Text('テキスト'),
                      ),
                    ],
                    selected: {effectiveMode},
                    onSelectionChanged: hasSource
                        ? (selection) {
                            setState(() => _displayMode = selection.single);
                          }
                        : null,
                  ),
                  _ToolbarIconButton(
                    tooltip: '縮小',
                    onPressed: _zoom <= 0.75
                        ? null
                        : () => setState(() => _zoom -= 0.1),
                    icon: Icons.zoom_out,
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2EFE8),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE3DED3)),
                    ),
                    child: Text(
                      '${(_zoom * 100).round()}%',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  _ToolbarIconButton(
                    tooltip: '拡大',
                    onPressed: _zoom >= 2.0
                        ? null
                        : () => setState(() => _zoom += 0.1),
                    icon: Icons.zoom_in,
                  ),
                  _ToolbarIconButton(
                    tooltip: '倍率を戻す',
                    onPressed: _zoom == 1.0
                        ? null
                        : () => setState(() => _zoom = 1.0),
                    icon: Icons.center_focus_strong,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _MaterialContentView(
                    material: material,
                    mode: effectiveMode,
                    analysis: analysis,
                    lookupCache: _lookupCache,
                    zoom: _zoom,
                    sidePanelMode: _sidePanelMode,
                    onSidePanelModeChanged: (mode) =>
                        setState(() => _sidePanelMode = mode),
                  ),
                ],
              ),
            ),
          ],
        ),
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
    return IconButton.outlined(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: const BorderSide(color: Color(0xFFE3DED3)),
        backgroundColor: Colors.white,
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
  final _SidePanelMode? sidePanelMode;
  final ValueChanged<_SidePanelMode?> onSidePanelModeChanged;

  const _MaterialContentView({
    required this.material,
    required this.mode,
    required this.analysis,
    required this.lookupCache,
    required this.zoom,
    required this.sidePanelMode,
    required this.onSidePanelModeChanged,
  });

  @override
  ConsumerState<_MaterialContentView> createState() =>
      _MaterialContentViewState();
}

class _MaterialContentViewState extends ConsumerState<_MaterialContentView> {
  final GlobalKey _textKey = GlobalKey();
  OverlayEntry? _popoverEntry;
  final Object _popoverTapRegionGroup = Object();
  String? _hoveredRangeKey;
  int? _selectionStart;
  int? _selectionEnd;
  int? _dragPageIndex;
  int? _dragSelectionAnchor;
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
    super.dispose();
  }

  void _hideMeaningPopover() {
    _popoverEntry?.remove();
    _popoverEntry = null;
  }

  void _showMeaningPopover(LexicalItemResult item, Offset globalPosition) {
    _hideMeaningPopover();
    final hostContext = context;
    final overlay = Overlay.of(context);
    final screenSize = MediaQuery.sizeOf(context);
    const width = 340.0;
    final left = (globalPosition.dx - 28).clamp(
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

  void _setHoveredRange(String? key) {
    if (_hoveredRangeKey == key) return;
    setState(() => _hoveredRangeKey = key);
  }

  void _clearSelection() {
    if (_selectionStart == null &&
        _selectionEnd == null &&
        _dragPageIndex == null &&
        _dragSelectionAnchor == null) {
      return;
    }
    setState(() {
      _selectionStart = null;
      _selectionEnd = null;
      _dragPageIndex = null;
      _dragSelectionAnchor = null;
    });
    if (widget.sidePanelMode == _SidePanelMode.selection) {
      widget.onSidePanelModeChanged(null);
    }
  }

  TextStyle? _textStyle(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyLarge;
    return base?.copyWith(
      height: 1.8,
      fontSize: (base.fontSize ?? 16) * widget.zoom,
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
      final rangeKey = range?.kind == _MarkedRangeKind.word
          ? _markedRangeKey(range!.start, range!.end)
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
    _showMeaningPopover(item, event.position);
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
    final isWord = range?.kind == _MarkedRangeKind.word;
    final rangeKey = isWord ? _markedRangeKey(range!.start, range!.end) : null;
    final color = segment.visual.backgroundColor;

    return Positioned.fromRect(
      rect: _sourceSegmentRect(box, pageSize, boxRange, segment),
      child: MouseRegion(
        cursor: isWord ? SystemMouseCursors.click : SystemMouseCursors.basic,
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
          onDoubleTapDown: !isWord
              ? null
              : (details) =>
                    _showMeaningPopover(range!.item, details.globalPosition),
          onLongPressStart: !isWord
              ? null
              : (details) =>
                    _showMeaningPopover(range!.item, details.globalPosition),
          child: color == null
              ? const SizedBox.expand()
              : DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
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

    return FractionallySizedBox(
      widthFactor: widget.zoom,
      alignment: Alignment.topLeft,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Image.memory(
            imageBytes,
            width: double.infinity,
            fit: BoxFit.fitWidth,
          ),
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final pageSize = Size(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                return Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (_) {
                    if (_selectionStart != null || _selectionEnd != null) {
                      _clearSelection();
                    }
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _clearSelection,
                    onPanStart: (details) {
                      final anchor = _sourceOffsetAt(
                        pageIndex,
                        details.localPosition,
                        pageSize,
                        sourceBoxes,
                      );
                      if (anchor == null) {
                        return;
                      }
                      setState(() {
                        _dragPageIndex = pageIndex;
                        _dragSelectionAnchor = anchor;
                        _selectionStart = anchor;
                        _selectionEnd = anchor;
                      });
                      widget.onSidePanelModeChanged(_SidePanelMode.selection);
                    },
                    onPanUpdate: (details) {
                      final anchor = _dragSelectionAnchor;
                      if (_dragPageIndex != pageIndex || anchor == null) {
                        return;
                      }
                      final current = _sourceOffsetAt(
                        pageIndex,
                        details.localPosition,
                        pageSize,
                        sourceBoxes,
                      );
                      if (current == null) {
                        return;
                      }
                      setState(() {
                        _selectionStart = anchor;
                        _selectionEnd = current;
                      });
                    },
                    onPanEnd: (_) {
                      setState(() {
                        _dragPageIndex = null;
                        _dragSelectionAnchor = null;
                      });
                    },
                    onPanCancel: () {
                      setState(() {
                        _dragPageIndex = null;
                        _dragSelectionAnchor = null;
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
      ),
    );
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

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: pages.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            return DecoratedBox(
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
              child: _buildSourcePage(pages[index], index, state, sourceBoxes),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTextContent(_LearningTextState state, double maxWidth) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE3DED3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) => _handleTextPointerDown(event, maxWidth),
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

  @override
  Widget build(BuildContext context) {
    final state = _learningTextState;
    final result = _result;
    final panelItems = switch (widget.sidePanelMode) {
      _SidePanelMode.unknown =>
        result?.items.where((item) => !item.isLearned).toList() ?? const [],
      _SidePanelMode.known =>
        result?.items.where((item) => item.isLearned).toList() ?? const [],
      _SidePanelMode.all => result?.items ?? const [],
      _ => state.selectedItems(),
    };
    final panelTitle = switch (widget.sidePanelMode) {
      _SidePanelMode.unknown => '未知語',
      _SidePanelMode.known => '既知語',
      _SidePanelMode.all => '全体',
      _ => '選択範囲',
    };
    final sidePanel = _SelectionMeaningPanel(
      title: panelTitle,
      items: panelItems,
      userId: ref.read(appSessionProvider).userId,
      material: widget.material,
      onAdded: () {
        ref.read(wordsProvider.notifier).load(isLearned: false);
        ref
            .read(materialLibraryProvider.notifier)
            .analyzeMaterial(widget.material.id, force: true);
      },
      onShowDetails: _showMeaningPopover,
      lookupCache: widget.lookupCache,
    );
    final showSource =
        widget.mode == _MaterialDisplayMode.original &&
        canDisplayOriginalSource(widget.material);
    final showSidePanel = widget.sidePanelMode != null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = constraints.maxWidth < 760
            ? constraints.maxWidth
            : constraints.maxWidth - 340;
        final content = showSource
            ? _buildSourceContent(state)
            : _buildTextContent(state, contentWidth);

        if (constraints.maxWidth < 760) {
          if (showSource) {
            return SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.68,
              child: Column(
                children: [
                  Expanded(child: content),
                  if (showSidePanel) ...[
                    const SizedBox(height: 12),
                    SizedBox(height: 260, child: sidePanel),
                  ],
                ],
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              content,
              if (showSidePanel) ...[const SizedBox(height: 16), sidePanel],
            ],
          );
        }

        final row = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: content),
            if (showSidePanel) ...[
              const SizedBox(width: 20),
              SizedBox(width: 320, child: sidePanel),
            ],
          ],
        );
        return showSource
            ? SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.68,
                child: row,
              )
            : row;
      },
    );
  }
}

String _sourceTypeForMaterial(MaterialItem material) {
  return material.sourceMimeType == 'application/pdf'
      ? 'pdf_material'
      : 'image_material';
}

LexicalItemResult _lexicalItemForWordInResult(
  String word,
  ExtractWordsResult? result, {
  int? start,
  int? end,
}) {
  final cleaned = _cleanLookupWord(word);
  final normalized = _normalizeLookupWord(cleaned);
  final items = result?.items ?? const <LexicalItemResult>[];

  // 表示中の文字範囲と解析結果の occurrence が完全一致するときだけ、
  // その解析項目を使用する。UI側で複数形・活用形・別の出現位置を推測しない。
  if (start != null && end != null) {
    for (final item in items.where((item) => item.kind == 'word')) {
      final hasExactOccurrence = item.occurrences.any(
        (occurrence) => occurrence.start == start && occurrence.end == end,
      );
      if (!hasExactOccurrence) {
        continue;
      }
      final normalizedForms = <String>{
        _normalizeLookupWord(item.text),
        ...item.surfaceForms.map(_normalizeLookupWord),
      };
      if (normalizedForms.contains(normalized)) {
        return item;
      }
    }
  }

  // occurrence がない解析結果に限り、見出し語そのものの完全一致だけ許可する。
  for (final item in items.where((item) => item.kind == 'word')) {
    if (_normalizeLookupWord(item.text) == normalized) {
      return item;
    }
  }
  return _fallbackLexicalItem(cleaned);
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

bool _isLikelyEnglishFallbackWord(RegExpMatch match) {
  final word = match.group(0) ?? '';
  final normalized = _normalizeLookupWord(word);
  if (normalized.length == 1) {
    return word == 'I' || normalized == 'a' && word == 'a';
  }
  return !{
    'http',
    'https',
    'www',
    'com',
    'org',
    'net',
    'pdf',
  }.contains(normalized);
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
  final ValueChanged<_SidePanelMode> onShowItems;

  const _AnalysisHeader({required this.analysis, required this.onShowItems});

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
        final percent = (result.coverageRate * 100).round();
        return Container(
          width: double.infinity,
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 54,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CircularProgressIndicator(
                          value: result.coverageRate.clamp(0.0, 1.0).toDouble(),
                          strokeWidth: 5,
                          backgroundColor: const Color(0xFFF2EFE8),
                        ),
                        Center(
                          child: Text(
                            '$percent%',
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Progress Overview',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ActionChip(
                              onPressed: () => onShowItems(_SidePanelMode.all),
                              avatar: const Icon(
                                Icons.format_list_bulleted,
                                size: 16,
                              ),
                              label: Text('全体 ${result.totalWords}'),
                            ),
                            ActionChip(
                              onPressed: () =>
                                  onShowItems(_SidePanelMode.known),
                              avatar: const Icon(
                                Icons.check_circle_outline,
                                size: 16,
                              ),
                              label: Text('既知 ${result.knownCount}'),
                            ),
                            ActionChip(
                              avatar: const Icon(
                                Icons.radio_button_unchecked,
                                size: 16,
                              ),
                              label: Text('未知 ${result.unknownCount}'),
                              onPressed: () =>
                                  onShowItems(_SidePanelMode.unknown),
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

class _SelectionMeaningPanel extends StatelessWidget {
  final String title;
  final List<LexicalItemResult> items;
  final String userId;
  final MaterialItem material;
  final VoidCallback onAdded;
  final void Function(LexicalItemResult item, Offset globalPosition)
  onShowDetails;
  final _WordLookupCache lookupCache;

  const _SelectionMeaningPanel({
    this.title = '選択範囲',
    required this.items,
    required this.userId,
    required this.material,
    required this.onAdded,
    required this.onShowDetails,
    required this.lookupCache,
  });

  @override
  Widget build(BuildContext context) {
    final visibleItems = items;
    final maxHeight = math.min(MediaQuery.sizeOf(context).height * 0.56, 440.0);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE3DED3)),
          borderRadius: BorderRadius.circular(8),
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
                      title,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  _BatchAddButton(
                    items: visibleItems,
                    userId: userId,
                    material: material,
                    onAdded: onAdded,
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
                            userId: userId,
                            material: material,
                            onAdded: onAdded,
                            onShowDetails: onShowDetails,
                            lookupCache: lookupCache,
                          );
                        },
                      ),
              ),
            ],
          ),
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
    if (wordbookId == null) return;
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
      if (!mounted) return;
      widget.onAdded();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('一括登録しました')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('一括登録に失敗しました: $error')));
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
        FilledButton.icon(
          onPressed: _isAdding || widget.items.isEmpty ? null : () => _addAll(),
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          icon: _isAdding
              ? const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.playlist_add_check, size: 18),
          label: const Text('一括登録'),
        ),
        PopupMenuButton<String>(
          tooltip: '別の単語帳へ一括登録',
          onSelected: (_) => _addAll(forceWordbook: true),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'other', child: Text('別の単語帳に登録')),
          ],
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
    return Colors.lightGreenAccent.withValues(alpha: 0.36);
  }
  if (isCompleteSelection && kind == _MarkedRangeKind.word) {
    return Colors.amber.withValues(alpha: 0.36);
  }
  if (touchesSelection) {
    return Colors.lightBlueAccent.withValues(alpha: 0.36);
  }
  if (isHovered && kind == _MarkedRangeKind.word) {
    return Colors.amber.withValues(alpha: 0.30);
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

  Future<void> _addMeaning(int meaningId, {bool forceWordbook = false}) async {
    final hostContext = widget.hostContext;
    final material = widget.material;
    final userId = widget.userId;
    final onAdded = widget.onAdded;
    if (!hostContext.mounted) return;
    if (_adding.contains(meaningId) || _added.contains(meaningId)) return;
    setState(() => _adding.add(meaningId));
    String? wordbookId;
    try {
      wordbookId = await _selectWordbookForMaterial(
        hostContext,
        material,
        forceSelection: forceWordbook,
        anchorRect: widget.anchorRect,
        tapRegionGroupId: widget.tapRegionGroupId,
      );
    } catch (error) {
      if (mounted) setState(() => _adding.remove(meaningId));
      if (hostContext.mounted) {
        ScaffoldMessenger.of(
          hostContext,
        ).showSnackBar(SnackBar(content: Text('登録先の取得に失敗しました: $error')));
      }
      return;
    }
    if (wordbookId == null) {
      if (mounted) setState(() => _adding.remove(meaningId));
      widget.onClose();
      return;
    }
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
      _registeredMeaningIdsByMaterial
          .putIfAbsent(material.id, () => <int>{})
          .add(meaningId);
      onAdded();
      if (!hostContext.mounted) return;
      ScaffoldMessenger.of(
        hostContext,
      ).showSnackBar(const SnackBar(content: Text('単語帳に追加しました')));
    } catch (error) {
      if (mounted) setState(() => _added.remove(meaningId));
      if (!hostContext.mounted) return;
      ScaffoldMessenger.of(
        hostContext,
      ).showSnackBar(SnackBar(content: Text('追加に失敗しました: $error')));
    } finally {
      if (mounted) setState(() => _adding.remove(meaningId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(8),
      color: Theme.of(context).colorScheme.surface,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 460),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE3DED3)),
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
        color: isContextPos ? const Color(0xFFE0ECE8) : const Color(0xFFF8F6F0),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isContextPos
              ? const Color(0xFFB7C8C2)
              : const Color(0xFFE3DED3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Chip(
                visualDensity: VisualDensity.compact,
                label: Text(partOfSpeechLabel(meaning.partOfSpeech)),
              ),
              if (isContextPos)
                const Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(Icons.check, size: 16),
                  label: Text('この文の品詞'),
                ),
              if (meaning.source.isNotEmpty)
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(_sourceLabel(meaning.source)),
                ),
              if (_transitivityLabel(meaning.transitivity) != null)
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(_transitivityLabel(meaning.transitivity)!),
                ),
              if (_countabilityLabel(meaning.countability) != null)
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(_countabilityLabel(meaning.countability)!),
                ),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FilledButton.icon(
                onPressed: isAdding || isAdded ? null : onAdd,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                icon: isAdding
                    ? const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        isAdded ? Icons.check : Icons.playlist_add,
                        size: 18,
                      ),
                label: Text(isAdded ? '追加済み' : '単語帳に追加'),
              ),
              PopupMenuButton<String>(
                tooltip: '別の単語帳へ登録',
                onSelected: (_) => onAddElsewhere(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'other', child: Text('別の単語帳に登録')),
                ],
              ),
            ],
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
  bool _isMarkingKnown = false;
  bool _isKnown = false;

  @override
  void initState() {
    super.initState();
    _future = _createFuture();
    _isKnown = widget.item.isLearned;
  }

  @override
  void didUpdateWidget(covariant _SelectionMeaningTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.text != widget.item.text ||
        oldWidget.item.partOfSpeech != widget.item.partOfSpeech) {
      _future = _createFuture();
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
    if (wordbookId == null) return;
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
      _registeredMeaningIdsByMaterial
          .putIfAbsent(widget.material.id, () => <int>{})
          .add(meaningId);
      if (!mounted) return;
      setState(() => _added.add(meaningId));
      widget.onAdded();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('単語帳に追加しました')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('追加に失敗しました: $error')));
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
      if (!mounted) return;
      setState(() => _isKnown = true);
      widget.onAdded();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('学習済み単語に追加しました')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('学習済みへの追加に失敗しました: $error')));
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
          behavior: HitTestBehavior.deferToChild,
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
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (!_isKnown)
                      OutlinedButton.icon(
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
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: meaning == null || isAdding || isAdded
                            ? null
                            : () => _addMeaning(meaning.id),
                        icon: isAdding
                            ? const SizedBox.square(
                                dimension: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                isAdded ? Icons.check : Icons.playlist_add,
                                size: 18,
                              ),
                        label: Text(isAdded ? '追加済み' : '単語帳に追加'),
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: '別の単語帳へ登録',
                      onSelected: meaning == null
                          ? null
                          : (_) => _addMeaning(meaning.id, forceWordbook: true),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'other', child: Text('別の単語帳に登録')),
                      ],
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
    final sorted = [...meanings]
      ..sort(
        (a, b) => _compareMeaningForContext(a, b, widget.item.partOfSpeech),
      );
    return sorted.isEmpty ? null : sorted.first;
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
      if (!mounted) return;
      setState(() => _added.add(meaningId));
      widget.onAdded();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('単語帳に追加しました')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('追加に失敗しました: $error')));
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
                                Chip(
                                  label: Text(
                                    _partOfSpeechLabel(meaning.partOfSpeech),
                                  ),
                                ),
                                if (isContextPos)
                                  Chip(
                                    avatar: const Icon(Icons.check, size: 18),
                                    label: const Text('この文の品詞'),
                                  ),
                                if (meaning.source.isNotEmpty)
                                  Chip(
                                    label: Text(_sourceLabel(meaning.source)),
                                  ),
                                if (_transitivityLabel(meaning.transitivity) !=
                                    null)
                                  Chip(
                                    label: Text(
                                      _transitivityLabel(meaning.transitivity)!,
                                    ),
                                  ),
                                if (_countabilityLabel(meaning.countability) !=
                                    null)
                                  Chip(
                                    label: Text(
                                      _countabilityLabel(meaning.countability)!,
                                    ),
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
