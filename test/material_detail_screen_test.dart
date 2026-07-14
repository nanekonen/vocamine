import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vacamine/models/lexical_analysis.dart';
import 'package:vacamine/models/material_item.dart';
import 'package:vacamine/screens/material_detail_screen.dart';

void main() {
  test('PDFs can be shown from page images after reload', () {
    final material = MaterialItem(
      id: 'material-1',
      title: 'Sample PDF',
      ocrText: 'sample text',
      sourceMimeType: 'application/pdf',
      sourcePageImages: [Uint8List(1)],
      createdAt: DateTime.now(),
    );

    expect(canDisplayOriginalSource(material), isTrue);
  });

  test('original view is unavailable without source bytes or page images', () {
    final material = MaterialItem(
      id: 'material-2',
      title: 'No source',
      ocrText: 'sample text',
      sourceMimeType: 'application/pdf',
      createdAt: DateTime.now(),
    );

    expect(canDisplayOriginalSource(material), isFalse);
  });

  test(
    'English words are treated as lexical targets while Japanese is not',
    () {
      expect(shouldTreatTextAsLexicalTarget('texts'), isTrue);
      expect(shouldTreatTextAsLexicalTarget('lemma'), isTrue);
      expect(shouldTreatTextAsLexicalTarget('日本語'), isFalse);
    },
  );

  test('a word in a discontinuous phrase resolves all phrase components', () {
    const text = 'She paid close attention to details.';
    final result = _analysisResult([
      _word('pay', 'paid', 4, 8),
      _word('attention', 'attention', 15, 24),
      _phrase('pay attention', 'paid close attention', 4, 24),
    ]);

    final related = findRelatedPhraseForWordForTesting(
      text: text,
      result: result,
      wordStart: 4,
      wordEnd: 8,
    );

    expect(related?.phrase, 'pay attention');
    expect(related?.components, [(start: 4, end: 8), (start: 15, end: 24)]);
  });

  test('single click is enabled only for a selected word marker', () {
    const text = 'A sample word.';
    final result = _analysisResult([_word('sample', 'sample', 2, 8)]);

    expect(
      isWordSingleClickMarkerForTesting(
        text: text,
        result: result,
        wordStart: 2,
        wordEnd: 8,
      ),
      isFalse,
    );
    expect(
      isWordSingleClickMarkerForTesting(
        text: text,
        result: result,
        wordStart: 2,
        wordEnd: 8,
        selectionStart: 2,
        selectionEnd: 8,
      ),
      isTrue,
    );
  });

  test('a three-word phrase resolves every remaining marker target', () {
    const text = 'They take great care of it.';
    final result = _analysisResult([
      _word('take', 'take', 5, 9),
      _word('care', 'care', 16, 20),
      _word('of', 'of', 21, 23),
      _phrase('take care of', 'take great care of', 5, 23),
    ]);

    final related = findRelatedPhraseForWordForTesting(
      text: text,
      result: result,
      wordStart: 16,
      wordEnd: 20,
    );

    expect(related?.phrase, 'take care of');
    expect(related?.components, [
      (start: 5, end: 9),
      (start: 16, end: 20),
      (start: 21, end: 23),
    ]);
  });
}

ExtractWordsResult _analysisResult(List<LexicalItemResult> items) {
  return ExtractWordsResult(
    unknownWords: const [],
    totalWords: items.length,
    unknownCount: 0,
    knownCount: 0,
    coverageRate: 0,
    items: items,
    unknownItems: const [],
  );
}

LexicalItemResult _word(String text, String surface, int start, int end) {
  return LexicalItemResult(
    text: text,
    partOfSpeech: 'noun',
    surfaceForms: [surface],
    occurrences: [LexicalOccurrence(form: surface, start: start, end: end)],
    kind: 'word',
    isLearned: false,
    hasMeaning: true,
  );
}

LexicalItemResult _phrase(String text, String surface, int start, int end) {
  return LexicalItemResult(
    text: text,
    partOfSpeech: 'phrase',
    surfaceForms: [surface],
    occurrences: [LexicalOccurrence(form: surface, start: start, end: end)],
    kind: 'phrase',
    isLearned: false,
    hasMeaning: true,
  );
}
