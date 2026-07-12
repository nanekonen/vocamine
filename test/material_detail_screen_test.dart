import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
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

  test('English words are treated as lexical targets while Japanese is not', () {
    expect(shouldTreatTextAsLexicalTarget('texts'), isTrue);
    expect(shouldTreatTextAsLexicalTarget('lemma'), isTrue);
    expect(shouldTreatTextAsLexicalTarget('日本語'), isFalse);
  });
}
