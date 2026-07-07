import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/lexical_analysis.dart';
import '../models/material_item.dart';
import '../models/word_lookup.dart';
import '../providers/material_library_provider.dart';
import '../providers/words_provider.dart';
import '../services/app_session.dart';
import '../services/vocamine_api_client.dart';
import '../utils/part_of_speech_label.dart';

enum _MaterialDisplayMode { original, text }

enum _SidePanelMode { selection, unknown }

final _englishWordPattern = RegExp(r"[A-Za-z]+(?:['’-][A-Za-z]+)*");

class _WordLookupCache {
  final _api = VocamineApiClient();
  final Map<String, Future<WordLookupResult>> _futures = {};
  final Map<String, WordLookupResult> _results = {};

  String _keyFor(LexicalItemResult item) {
    return '${item.text.toLowerCase().replaceAll('’', "'")}:${item.partOfSpeech}';
  }

  Future<WordLookupResult> lookup(
    LexicalItemResult item, {
    bool enrichMeanings = true,
  }) {
    final key = _keyFor(item);
    final cached = _results[key];
    if (cached != null) {
      return SynchronousFuture(cached);
    }
    return _futures.putIfAbsent(
      key,
      () => _api
          .lookupWord(
            word: item.text,
            partOfSpeech: item.partOfSpeech,
            enrichMeanings: enrichMeanings,
          )
          .then((result) {
            _results[key] = result;
            return result;
          }),
    );
  }

  void primeExistingMeanings(Iterable<LexicalItemResult> items) {
    for (final item in items) {
      if (item.text.isEmpty || item.partOfSpeech.isEmpty) {
        continue;
      }
      lookup(item, enrichMeanings: false);
    }
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

List<String> _lookupKeysForWord(String word) {
  final normalized = _normalizeLookupWord(_cleanLookupWord(word));
  final keys = <String>[normalized];
  if (normalized.endsWith("'s") && normalized.length > 2) {
    keys.add(normalized.substring(0, normalized.length - 2));
  }
  if (normalized.endsWith('ies') && normalized.length > 4) {
    keys.add('${normalized.substring(0, normalized.length - 3)}y');
  }
  if (normalized.endsWith('ing') && normalized.length > 5) {
    final stem = normalized.substring(0, normalized.length - 3);
    keys.add(stem);
    keys.add('${stem}e');
  }
  if (normalized.endsWith('ed') && normalized.length > 4) {
    final stem = normalized.substring(0, normalized.length - 2);
    keys.add(stem);
    keys.add('${stem}e');
  }
  if (normalized.endsWith('es') && normalized.length > 4) {
    keys.add(normalized.substring(0, normalized.length - 2));
  }
  if (normalized.endsWith('s') && normalized.length > 3) {
    keys.add(normalized.substring(0, normalized.length - 1));
  }
  return keys.toSet().toList();
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

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(materialLibraryProvider);
    final material = library.materials.firstWhere(
      (m) => m.id == widget.materialId,
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
      data: (result) => _lookupCache.primeExistingMeanings(result.items),
    );
    final hasSource =
        material.sourceMimeType != null &&
        (material.sourceBytes != null || material.sourcePageImages.isNotEmpty);
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
              onShowUnknown: () => setState(() {
                _sidePanelMode = _sidePanelMode == _SidePanelMode.unknown
                    ? null
                    : _SidePanelMode.unknown;
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

class _MaterialContentView extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    if (mode == _MaterialDisplayMode.original &&
        material.sourceBytes != null &&
        material.sourceMimeType != null) {
      return SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.68,
        child: _OriginalSourceLearningView(
          material: material,
          analysis: analysis,
          lookupCache: lookupCache,
          zoom: zoom,
          sidePanelMode: sidePanelMode,
          onSidePanelModeChanged: onSidePanelModeChanged,
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE3DED3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: _InteractiveTextView(
        material: material,
        text: material.ocrText,
        analysis: analysis,
        lookupCache: lookupCache,
        zoom: zoom,
        sidePanelMode: sidePanelMode,
        onSidePanelModeChanged: onSidePanelModeChanged,
      ),
    );
  }
}

String _sourceTypeForMaterial(MaterialItem material) {
  return material.sourceMimeType == 'application/pdf' ? 'pdf_material' : 'image_material';
}

LexicalItemResult _lexicalItemForWord(
  String word,
  AsyncValue<ExtractWordsResult>? analysis,
) {
  return _lexicalItemForWordInResult(
    word,
    analysis?.whenOrNull(data: (result) => result),
  );
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
  if (start != null && end != null) {
    for (final item in items.where((item) => item.kind == 'word')) {
      for (final occurrence in item.occurrences) {
        if (occurrence.start == start && occurrence.end == end) {
          return item;
        }
      }
    }
  }
  final wordItems = {
    for (final item in items.where((item) => item.kind == 'word'))
      _normalizeLookupWord(item.text): item,
  };
  final surfaceItems = <String, LexicalItemResult>{};
  for (final item in items) {
    final forms = [item.text, ...item.surfaceForms].map(_normalizeLookupWord);
    if (forms.contains(normalized)) {
      return item;
    }
    if (item.kind == 'word') {
      for (final form in forms) {
        surfaceItems[form] = item;
      }
    }
  }
  for (final key in _lookupKeysForWord(cleaned)) {
    final item = surfaceItems[key] ?? wordItems[key];
    if (item != null) {
      return item;
    }
  }
  return _fallbackLexicalItem(cleaned);
}

List<LexicalItemResult> _itemsFullyContainedInRange(
  ExtractWordsResult? result,
  int? selectionStart,
  int? selectionEnd,
) {
  if (result == null || selectionStart == null || selectionEnd == null) {
    return const [];
  }
  final start = selectionStart < selectionEnd ? selectionStart : selectionEnd;
  final end = selectionStart < selectionEnd ? selectionEnd : selectionStart;
  if (start == end) {
    return const [];
  }

  final selectedItems = <LexicalItemResult>[];
  final seen = <String>{};
  for (final item in result.items) {
    final isIncluded = item.occurrences.any(
      (occurrence) => occurrence.start >= start && occurrence.end <= end,
    );
    if (!isIncluded) {
      continue;
    }
    final key = '${item.text}:${item.partOfSpeech}:${item.partOfSpeechDetail}';
    if (seen.add(key)) {
      selectedItems.add(item);
    }
  }
  return selectedItems;
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
    return _itemsFullyContainedInRange(result, selectionStart, selectionEnd);
  }

  LexicalItemResult itemForWordRange(String word, int start, int end) {
    return _lexicalItemForWordInResult(word, result, start: start, end: end);
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

  _TextRange? selectionOverlapForRange(int start, int end) {
    final selection = _normalizedSelection;
    if (selection == null) {
      return null;
    }
    final overlapStart = math.max(start, selection.start);
    final overlapEnd = math.min(end, selection.end);
    if (overlapStart >= overlapEnd) {
      return null;
    }
    return _TextRange(overlapStart, overlapEnd);
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
  if (result == null) {
    return const [];
  }
  final hasSelection =
      selectionStart != null &&
      selectionEnd != null &&
      selectionStart != selectionEnd;
  final start = hasSelection ? math.min(selectionStart, selectionEnd) : -1;
  final end = hasSelection ? math.max(selectionStart, selectionEnd) : -1;
  final ranges = <_MarkedRange>[];
  for (final item in result.items.where((item) => item.kind == 'phrase')) {
    for (final occurrence in item.occurrences) {
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
  for (final item in result.items.where((item) => item.kind == 'word')) {
    for (final occurrence in item.occurrences) {
      final overlapsPhrase = ranges.any(
        (range) =>
            range.kind == _MarkedRangeKind.phrase &&
            occurrence.start >= range.start &&
            occurrence.end <= range.end,
      );
      if (overlapsPhrase) {
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
  for (final match in _englishWordPattern.allMatches(text)) {
    if (!_isLikelyEnglishFallbackWord(match)) {
      continue;
    }
    final alreadyMarked = ranges.any(
      (range) =>
          range.kind == _MarkedRangeKind.word &&
          range.start == match.start &&
          range.end == match.end,
    );
    if (alreadyMarked) {
      continue;
    }
    final word = text.substring(match.start, match.end);
    final item = _lexicalItemForWordInResult(
      word,
      result,
      start: match.start,
      end: match.end,
    );
    if (item.kind != 'word') {
      continue;
    }
    final overlapsPhrase = ranges.any(
      (range) =>
          range.kind == _MarkedRangeKind.phrase &&
          match.start >= range.start &&
          match.end <= range.end,
    );
    if (overlapsPhrase) {
      continue;
    }
    ranges.add(
      _MarkedRange(
        start: match.start,
        end: match.end,
        item: item,
        kind: _MarkedRangeKind.word,
        isSelected: hasSelection && match.start >= start && match.end <= end,
      ),
    );
  }
  ranges.sort((a, b) {
    final startCompare = a.start.compareTo(b.start);
    if (startCompare != 0) return startCompare;
    return b.end.compareTo(a.end);
  });
  return ranges;
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

class _OriginalSourceLearningView extends ConsumerStatefulWidget {
  final MaterialItem material;
  final AsyncValue<ExtractWordsResult>? analysis;
  final _WordLookupCache lookupCache;
  final double zoom;
  final _SidePanelMode? sidePanelMode;
  final ValueChanged<_SidePanelMode?> onSidePanelModeChanged;

  const _OriginalSourceLearningView({
    required this.material,
    required this.analysis,
    required this.lookupCache,
    required this.zoom,
    required this.sidePanelMode,
    required this.onSidePanelModeChanged,
  });

  @override
  ConsumerState<_OriginalSourceLearningView> createState() =>
      _OriginalSourceLearningViewState();
}

class _OriginalSourceLearningViewState
    extends ConsumerState<_OriginalSourceLearningView> {
  String? _hoveredBoxKey;
  int? _selectionStart;
  int? _selectionEnd;
  int? _dragPageIndex;
  Offset? _dragStart;

  ExtractWordsResult? get _result =>
      widget.analysis?.maybeWhen(data: (value) => value, orElse: () => null);

  List<Uint8List> get _pages {
    if (widget.material.sourceMimeType == 'application/pdf') {
      return widget.material.sourcePageImages;
    }
    final bytes = widget.material.sourceBytes;
    return bytes == null ? const [] : [bytes];
  }

  LexicalItemResult _lexicalItemForBox(SourceWordBox box) {
    final range = _boxTextRange(box);
    final result = _result;
    if (range != null && result != null) {
      return _lexicalItemForWordInResult(
        _cleanLookupWord(box.text),
        result,
        start: range.start,
        end: range.end,
      );
    }
    return _lexicalItemForWord(box.text, widget.analysis);
  }

  void _showMeaningPopover(LexicalItemResult item, Offset globalPosition) {
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

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => entry.remove(),
              ),
            ),
            Positioned(
              left: left,
              top: top,
              width: width,
              child: _MeaningPopover(
                item: item,
                future: widget.lookupCache.lookup(item),
                userId: ref.read(appSessionProvider).userId,
                material: widget.material,
                onAdded: () => ref.read(wordsProvider.notifier).load(isLearned: false),
                onClose: () => entry.remove(),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(entry);
  }

  int? _textOffsetAtPosition(int pageIndex, Offset position, Size pageSize) {
    SourceWordBox? nearest;
    var nearestDistance = double.infinity;
    Rect? nearestRect;
    for (final box
        in widget.material.sourceWordBoxes
            .where((box) => box.pageIndex == pageIndex)
            .where((box) => box.start != null && box.end != null)) {
      final boxRect = Rect.fromLTWH(
        box.left * pageSize.width,
        box.top * pageSize.height,
        box.width * pageSize.width,
        box.height * pageSize.height,
      );
      if (boxRect.inflate(4).contains(position)) {
        return _offsetWithinBox(box, boxRect, position);
      }
      final distance = (boxRect.center - position).distance;
      if (distance < nearestDistance) {
        nearest = box;
        nearestRect = boxRect;
        nearestDistance = distance;
      }
    }
    if (nearest == null || nearestRect == null) {
      return null;
    }
    return position.dx < nearestRect.center.dx ? nearest.start : nearest.end;
  }

  int _offsetWithinBox(SourceWordBox box, Rect boxRect, Offset position) {
    final start = box.start;
    final end = box.end;
    if (start == null || end == null || end <= start) {
      return start ?? 0;
    }
    final ratio = ((position.dx - boxRect.left) / boxRect.width).clamp(
      0.0,
      1.0,
    );
    return start + ((end - start) * ratio).round();
  }

  void _updateSelectionFromTextOffsets(
    int pageIndex,
    Offset start,
    Offset current,
    Size pageSize,
  ) {
    final startOffset = _textOffsetAtPosition(pageIndex, start, pageSize);
    final endOffset = _textOffsetAtPosition(pageIndex, current, pageSize);
    if (startOffset == null || endOffset == null) {
      setState(() {
        _selectionStart = null;
        _selectionEnd = null;
      });
      return;
    }
    setState(() {
      _selectionStart = startOffset;
      _selectionEnd = endOffset;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    if (pages.isEmpty) {
      return const Center(child: Text('PDFプレビューを生成できませんでした'));
    }

    final result = _result;
    final learningTextState = _LearningTextState(
      text: widget.material.ocrText,
      result: result,
      selectionStart: _selectionStart,
      selectionEnd: _selectionEnd,
    );
    final selectedItems = learningTextState.selectedItems();
    final panelItems = widget.sidePanelMode == _SidePanelMode.unknown
        ? (result?.unknownItems ?? const <LexicalItemResult>[])
        : selectedItems;
    final preview = DecoratedBox(
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
            final pageBoxes = widget.material.sourceWordBoxes
                .where((box) => box.pageIndex == index)
                .toList();
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
              child: _OriginalPreviewPage(
                imageBytes: pages[index],
                zoom: widget.zoom,
                pageIndex: index,
                boxes: pageBoxes,
                hoveredBoxKey: _hoveredBoxKey,
                learningTextState: learningTextState,
                dragPageIndex: _dragPageIndex,
                dragStart: _dragStart,
                lexicalItemForBox: _lexicalItemForBox,
                onHover: (key) => setState(() => _hoveredBoxKey = key),
                onClearHover: (key) => setState(() {
                  if (_hoveredBoxKey == key) {
                    _hoveredBoxKey = null;
                  }
                }),
                onShowMeaning: _showMeaningPopover,
                onDragStart: (position, size) {
                  setState(() {
                    _dragPageIndex = index;
                    _dragStart = position;
                    _selectionStart = null;
                    _selectionEnd = null;
                  });
                  widget.onSidePanelModeChanged(_SidePanelMode.selection);
                  _updateSelectionFromTextOffsets(
                    index,
                    position,
                    position,
                    size,
                  );
                },
                onDragUpdate: (position, size) {
                  final start = _dragStart;
                  if (_dragPageIndex != index || start == null) return;
                  _updateSelectionFromTextOffsets(index, start, position, size);
                },
                onDragEnd: () => setState(() {
                  _dragPageIndex = null;
                  _dragStart = null;
                }),
              ),
            );
          },
        ),
      ),
    );

    final sidePanel = _SelectionMeaningPanel(
      title: widget.sidePanelMode == _SidePanelMode.unknown ? '未知語' : '選択範囲',
      items: panelItems,
      userId: ref.read(appSessionProvider).userId,
      material: widget.material,
      onAdded: () => ref.read(wordsProvider.notifier).load(isLearned: false),
      onShowDetails: _showMeaningPopover,
      lookupCache: widget.lookupCache,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            children: [
              Expanded(child: preview),
              if (panelItems.isNotEmpty) ...[
                const SizedBox(height: 12),
                SizedBox(height: 260, child: sidePanel),
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: preview),
            const SizedBox(width: 20),
            SizedBox(width: 320, child: sidePanel),
          ],
        );
      },
    );
  }
}

class _OriginalPreviewPage extends StatelessWidget {
  final Uint8List imageBytes;
  final double zoom;
  final int pageIndex;
  final List<SourceWordBox> boxes;
  final String? hoveredBoxKey;
  final _LearningTextState learningTextState;
  final int? dragPageIndex;
  final Offset? dragStart;
  final LexicalItemResult Function(SourceWordBox box) lexicalItemForBox;
  final ValueChanged<String> onHover;
  final ValueChanged<String> onClearHover;
  final void Function(LexicalItemResult item, Offset globalPosition)
  onShowMeaning;
  final void Function(Offset position, Size size) onDragStart;
  final void Function(Offset position, Size size) onDragUpdate;
  final VoidCallback onDragEnd;

  const _OriginalPreviewPage({
    required this.imageBytes,
    required this.zoom,
    required this.pageIndex,
    required this.boxes,
    required this.hoveredBoxKey,
    required this.learningTextState,
    required this.dragPageIndex,
    required this.dragStart,
    required this.lexicalItemForBox,
    required this.onHover,
    required this.onClearHover,
    required this.onShowMeaning,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: zoom,
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
                return GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onPanStart: (details) =>
                      onDragStart(details.localPosition, pageSize),
                  onPanUpdate: (details) =>
                      onDragUpdate(details.localPosition, pageSize),
                  onPanEnd: (_) => onDragEnd(),
                  child: Stack(
                    children: [
                      for (final box in boxes)
                        _OriginalWordHotspot(
                          box: box,
                          pageSize: pageSize,
                          isHovered: hoveredBoxKey == _boxKey(box),
                          learningTextState: learningTextState,
                          item: lexicalItemForBox(box),
                          onHover: onHover,
                          onClearHover: onClearHover,
                          onShowMeaning: onShowMeaning,
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _OriginalWordHotspot extends StatelessWidget {
  final SourceWordBox box;
  final Size pageSize;
  final bool isHovered;
  final _LearningTextState learningTextState;
  final LexicalItemResult item;
  final ValueChanged<String> onHover;
  final ValueChanged<String> onClearHover;
  final void Function(LexicalItemResult item, Offset globalPosition)
  onShowMeaning;

  const _OriginalWordHotspot({
    required this.box,
    required this.pageSize,
    required this.isHovered,
    required this.learningTextState,
    required this.item,
    required this.onHover,
    required this.onClearHover,
    required this.onShowMeaning,
  });

  @override
  Widget build(BuildContext context) {
    final key = _boxKey(box);
    final boxRange = _boxTextRange(box);
    final visual = boxRange == null
        ? _MarkerVisual(
            kind: null,
            isCompleteSelection: false,
            isHovered: isHovered,
            touchesSelection: false,
          )
        : learningTextState.markerForRange(
            boxRange.start,
            boxRange.end,
            isHovered: isHovered,
          );
    final fullBackgroundColor = visual.backgroundColor;
    final boxWidth = box.width * pageSize.width;
    final selectionOverlap = boxRange == null
        ? null
        : learningTextState.selectionOverlapForRange(
            boxRange.start,
            boxRange.end,
          );
    final blueRect =
        !visual.isCompleteSelection &&
            boxRange != null &&
            selectionOverlap != null
        ? _selectionRectWithinBox(boxRange, selectionOverlap, boxWidth)
        : null;
    return Positioned(
      left: box.left * pageSize.width,
      top: box.top * pageSize.height,
      width: box.width * pageSize.width,
      height: box.height * pageSize.height,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => onHover(key),
        onExit: (_) => onClearHover(key),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onDoubleTapDown: (details) =>
              onShowMeaning(item, details.globalPosition),
          onLongPressStart: (details) =>
              onShowMeaning(item, details.globalPosition),
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: fullBackgroundColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (blueRect != null)
                Positioned(
                  left: blueRect.left,
                  top: 0,
                  width: blueRect.width,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _markerBackgroundColor(
                        kind: null,
                        isCompleteSelection: false,
                        isHovered: false,
                        touchesSelection: true,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _boxKey(SourceWordBox box) =>
    '${box.pageIndex}:${box.left}:${box.top}:${box.width}:${box.height}:${box.text}';

_TextRange? _boxTextRange(SourceWordBox box) {
  final start = box.start;
  final end = box.end;
  if (start == null || end == null || end <= start) {
    return null;
  }
  final match = _englishWordPattern.firstMatch(box.text);
  if (match == null) {
    return _TextRange(start, end);
  }
  return _TextRange(start + match.start, start + match.end);
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
  final VoidCallback onShowUnknown;

  const _AnalysisHeader({required this.analysis, required this.onShowUnknown});

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
                            _MetricChip(
                              icon: Icons.format_list_bulleted,
                              label: '全体 ${result.totalWords}',
                            ),
                            _MetricChip(
                              icon: Icons.check_circle_outline,
                              label: '既知 ${result.knownCount}',
                            ),
                            ActionChip(
                              avatar: const Icon(
                                Icons.radio_button_unchecked,
                                size: 16,
                              ),
                              label: Text('未知 ${result.unknownCount}'),
                              onPressed: onShowUnknown,
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

class _MetricChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetricChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _InteractiveTextView extends ConsumerStatefulWidget {
  final MaterialItem material;
  final String text;
  final AsyncValue<ExtractWordsResult>? analysis;
  final _WordLookupCache lookupCache;
  final double zoom;
  final _SidePanelMode? sidePanelMode;
  final ValueChanged<_SidePanelMode?> onSidePanelModeChanged;

  const _InteractiveTextView({
    required this.material,
    required this.text,
    required this.analysis,
    required this.lookupCache,
    required this.zoom,
    required this.sidePanelMode,
    required this.onSidePanelModeChanged,
  });

  @override
  ConsumerState<_InteractiveTextView> createState() =>
      _InteractiveTextViewState();
}

class _InteractiveTextViewState extends ConsumerState<_InteractiveTextView> {
  final GlobalKey _textKey = GlobalKey();
  OverlayEntry? _popoverEntry;
  String? _hoveredRange;
  TextSelection? _selection;
  DateTime? _lastPointerDownAt;
  Offset? _lastPointerDownPosition;
  DateTime? _suppressSelectionUntil;

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
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _hideMeaningPopover,
              ),
            ),
            Positioned(
              left: left,
              top: top,
              width: width,
              child: _MeaningPopover(
                item: item,
                future: widget.lookupCache.lookup(item),
                userId: ref.read(appSessionProvider).userId,
                material: widget.material,
                onAdded: () => ref.read(wordsProvider.notifier).load(isLearned: false),
                onClose: _hideMeaningPopover,
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_popoverEntry!);
  }

  LexicalItemResult? _itemForWord(
    String word,
    ExtractWordsResult? result,
    int start,
    int end,
  ) {
    return _lexicalItemForWordInResult(word, result, start: start, end: end);
  }

  String _rangeKey(int start, int end) => '$start:$end';

  TextStyle? _textStyle(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyLarge;
    return base?.copyWith(
      height: 1.8,
      fontSize: (base.fontSize ?? 16) * widget.zoom,
    );
  }

  List<InlineSpan> _buildSpans(
    BuildContext context,
    ExtractWordsResult? result,
  ) {
    final baseStyle = _textStyle(context);
    final spans = <InlineSpan>[];
    final learningTextState = _LearningTextState(
      text: widget.text,
      result: result,
      selectionStart: _selection?.start,
      selectionEnd: _selection?.end,
    );
    final ranges = learningTextState.ranges;
    final boundaries = <int>{0, widget.text.length};
    final selection = _selection;
    final hasSelection = selection != null && !selection.isCollapsed;
    final selectionStart = hasSelection
        ? math.min(selection.start, selection.end)
        : -1;
    final selectionEnd = hasSelection
        ? math.max(selection.start, selection.end)
        : -1;
    if (hasSelection) {
      boundaries
        ..add(selectionStart)
        ..add(selectionEnd);
    }
    for (final range in ranges) {
      boundaries
        ..add(range.start)
        ..add(range.end);
    }
    final sortedBoundaries = boundaries.toList()..sort();

    for (var i = 0; i < sortedBoundaries.length - 1; i++) {
      final start = sortedBoundaries[i];
      final end = sortedBoundaries[i + 1];
      if (start == end) continue;
      final range = _rangeCoveringSegment(ranges, start, end);
      final rangeKey = range == null ? null : _rangeKey(range.start, range.end);
      final isHovered = rangeKey != null && _hoveredRange == rangeKey;
      final markerColor = learningTextState
          .markerForRange(start, end, isHovered: isHovered)
          .backgroundColor;
      final style = markerColor == null
          ? baseStyle
          : baseStyle?.copyWith(backgroundColor: markerColor);
      spans.add(
        TextSpan(
          text: widget.text.substring(start, end),
          style: style,
          mouseCursor: range == null ? null : SystemMouseCursors.click,
          onEnter: rangeKey == null
              ? null
              : (_) => setState(() => _hoveredRange = rangeKey),
          onExit: rangeKey == null
              ? null
              : (_) => setState(() {
                  if (_hoveredRange == rangeKey) {
                    _hoveredRange = null;
                  }
                }),
        ),
      );
    }
    return [TextSpan(style: baseStyle, children: spans)];
  }

  LexicalItemResult? _itemAtOffset(
    Offset localPosition,
    ExtractWordsResult? result,
    double maxWidth,
  ) {
    if (result == null) {
      return null;
    }
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: _textStyle(context)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      textHeightBehavior: DefaultTextStyle.of(context).textHeightBehavior,
    )..layout(maxWidth: maxWidth);
    final position = painter.getPositionForOffset(localPosition);
    final offset = position.offset.clamp(0, widget.text.length);
    if (offset >= widget.text.length) {
      return null;
    }
    for (final match in _englishWordPattern.allMatches(widget.text)) {
      if (offset < match.start || offset >= match.end) {
        continue;
      }
      if (!_isLikelyEnglishFallbackWord(match)) {
        return null;
      }
      final word = widget.text.substring(match.start, match.end);
      final item = _itemForWord(word, result, match.start, match.end);
      if (item != null) {
        return item;
      }
    }
    for (final item in result.items.where((item) => item.kind == 'phrase')) {
      for (final occurrence in item.occurrences) {
        if (offset >= occurrence.start && offset < occurrence.end) {
          return item;
        }
      }
    }
    return null;
  }

  LexicalItemResult? _itemForHoveredRange(ExtractWordsResult? result) {
    final hoveredRange = _hoveredRange;
    if (result == null || hoveredRange == null) {
      return null;
    }
    for (final range in _markedRangesForText(
      text: widget.text,
      result: result,
      selectionStart: _selection?.start,
      selectionEnd: _selection?.end,
    )) {
      if (_rangeKey(range.start, range.end) == hoveredRange) {
        return range.item;
      }
    }
    return null;
  }

  void _handlePointerDown(
    PointerDownEvent event,
    ExtractWordsResult? result,
    double maxWidth,
  ) {
    final now = DateTime.now();
    final previousTime = _lastPointerDownAt;
    final previousPosition = _lastPointerDownPosition;
    _lastPointerDownAt = now;
    _lastPointerDownPosition = event.position;

    if (previousTime == null || previousPosition == null) {
      return;
    }
    final isDoubleClick =
        now.difference(previousTime) <= const Duration(milliseconds: 360) &&
        (event.position - previousPosition).distance <= 8;
    if (!isDoubleClick) {
      return;
    }

    final renderBox = _textKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      return;
    }
    final localPosition = renderBox.globalToLocal(event.position);
    final item =
        _itemForHoveredRange(result) ??
        _itemAtOffset(localPosition, result, maxWidth);
    if (item != null) {
      _suppressSelectionUntil = DateTime.now().add(
        const Duration(milliseconds: 500),
      );
      setState(() => _selection = null);
      _showMeaningPopover(item, event.position);
    }
  }

  List<LexicalItemResult> _selectedItems(ExtractWordsResult? result) {
    final selection = _selection;
    if (selection == null || selection.isCollapsed) {
      return const [];
    }
    return _itemsFullyContainedInRange(result, selection.start, selection.end);
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.analysis?.maybeWhen(
      data: (value) => value,
      orElse: () => null,
    );
    final selectedItems = _selectedItems(result);
    final panelItems = widget.sidePanelMode == _SidePanelMode.unknown
        ? (result?.unknownItems ?? const <LexicalItemResult>[])
        : selectedItems;
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableTextWidth = constraints.maxWidth < 760
            ? constraints.maxWidth
            : constraints.maxWidth - 340;
        final textView = Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (event) =>
              _handlePointerDown(event, result, availableTextWidth),
          child: SelectableText.rich(
            TextSpan(children: _buildSpans(context, result)),
            key: _textKey,
            onSelectionChanged: (selection, cause) {
              final suppressUntil = _suppressSelectionUntil;
              if (suppressUntil != null &&
                  DateTime.now().isBefore(suppressUntil)) {
                return;
              }
              widget.onSidePanelModeChanged(_SidePanelMode.selection);
              setState(() => _selection = selection);
            },
          ),
        );
        final sidePanel = _SelectionMeaningPanel(
          title: widget.sidePanelMode == _SidePanelMode.unknown
              ? '未知語'
              : '選択範囲',
          items: panelItems,
          userId: ref.read(appSessionProvider).userId,
          material: widget.material,
          onAdded: () => ref.read(wordsProvider.notifier).load(isLearned: false),
          onShowDetails: _showMeaningPopover,
          lookupCache: widget.lookupCache,
        );
        if (constraints.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              textView,
              if (panelItems.isNotEmpty) ...[
                const SizedBox(height: 16),
                sidePanel,
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: textView),
            const SizedBox(width: 20),
            SizedBox(width: 320, child: sidePanel),
          ],
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
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
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
                child: ListView.builder(
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

  Future<void> _addAll() async {
    if (_isAdding || widget.items.isEmpty) return;
    setState(() => _isAdding = true);
    try {
      await VocamineApiClient().addItemsToWordbook(
        userId: widget.userId,
        items: widget.items,
        sourceType: _sourceTypeForMaterial(widget.material),
        sourceMaterialId: widget.material.id,
        sourceFolderId: widget.material.folderId,
        sourceLabel: widget.material.title,
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
    return FilledButton.icon(
      onPressed: _isAdding || widget.items.isEmpty ? null : _addAll,
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
  if (isHovered && kind == _MarkedRangeKind.phrase) {
    return Colors.lightGreenAccent.withValues(alpha: 0.36);
  }
  if (isHovered) {
    return Colors.amber.withValues(alpha: 0.36);
  }
  if (touchesSelection) {
    return Colors.lightBlueAccent.withValues(alpha: 0.36);
  }
  return null;
}

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
  final String userId;
  final MaterialItem material;
  final VoidCallback onAdded;
  final VoidCallback onClose;

  const _MeaningPopover({
    required this.item,
    required this.future,
    required this.userId,
    required this.material,
    required this.onAdded,
    required this.onClose,
  });

  @override
  State<_MeaningPopover> createState() => _MeaningPopoverState();
}

class _MeaningPopoverState extends State<_MeaningPopover> {
  final _api = VocamineApiClient();
  final Set<int> _adding = {};
  final Set<int> _added = {};

  Future<void> _addMeaning(int meaningId) async {
    setState(() => _adding.add(meaningId));
    try {
      await _api.addMeaningToWordbook(
        userId: widget.userId,
        meaningId: meaningId,
        sourceType: _sourceTypeForMaterial(widget.material),
        sourceMaterialId: widget.material.id,
        sourceFolderId: widget.material.folderId,
        sourceLabel: widget.material.title,
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
                  const LinearProgressIndicator(minHeight: 2)
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
                              isAdded: _added.contains(meaning.id),
                              onAdd: () => _addMeaning(meaning.id),
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

  const _PopoverMeaningCard({
    required this.meaning,
    required this.isContextPos,
    required this.isAdding,
    required this.isAdded,
    required this.onAdd,
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
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
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
                  : Icon(isAdded ? Icons.check : Icons.playlist_add, size: 18),
              label: Text(isAdded ? '追加済み' : '単語帳に追加'),
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

  @override
  void initState() {
    super.initState();
    _future = _createFuture();
  }

  @override
  void didUpdateWidget(covariant _SelectionMeaningTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.text != widget.item.text ||
        oldWidget.item.partOfSpeech != widget.item.partOfSpeech) {
      _future = _createFuture();
    }
  }

  Future<WordLookupResult> _createFuture() {
    return widget.lookupCache.lookup(widget.item);
  }

  Future<void> _addMeaning(int meaningId) async {
    setState(() => _adding.add(meaningId));
    try {
      await VocamineApiClient().addMeaningToWordbook(
        userId: widget.userId,
        meaningId: meaningId,
        sourceType: _sourceTypeForMaterial(widget.material),
        sourceMaterialId: widget.material.id,
        sourceFolderId: widget.material.folderId,
        sourceLabel: widget.material.title,
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
    return FutureBuilder<WordLookupResult>(
      future: _future,
      builder: (context, snapshot) {
        final meaning = _firstMeaning(snapshot.data?.meanings ?? const []);
        final isAdding = meaning != null && _adding.contains(meaning.id);
        final isAdded = meaning != null && _added.contains(meaning.id);
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTapDown: (details) =>
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
                  const LinearProgressIndicator(minHeight: 2)
                else
                  Text(
                    meaning?.definitionJa?.trim().isNotEmpty == true
                        ? meaning!.definitionJa!
                        : '日本語訳が得られませんでした',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: meaning == null || isAdding || isAdded
                        ? null
                        : () => _addMeaning(meaning.id),
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
              return const Center(child: CircularProgressIndicator());
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
