import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/word.dart';

class WordsNotifier extends Notifier<List<Word>> {
  int _seq = 100;

  @override
  List<Word> build() {
    // ダミーデータ（すべて 'default' 単語帳に所属）
    return const [
      Word(id: '1', wordbookId: 'default', headword: 'ubiquitous', meaningJa: 'どこにでもある', partOfSpeech: 'adj'),
      Word(id: '2', wordbookId: 'default', headword: 'meticulous', meaningJa: '細心の', partOfSpeech: 'adj'),
      Word(id: '3', wordbookId: 'default', headword: 'pay attention to', meaningJa: '〜に注意を払う', partOfSpeech: 'phrase'),
      Word(id: '4', wordbookId: 'default', headword: 'reluctant', meaningJa: '気が進まない', partOfSpeech: 'adj'),
      Word(id: '5', wordbookId: 'default', headword: 'apple', meaningJa: 'りんご', partOfSpeech: 'noun', isLearned: true),
      Word(id: '6', wordbookId: 'default', headword: 'beautiful', meaningJa: '美しい', partOfSpeech: 'adj', isLearned: true),
    ];
  }

  void toggleLearned(String wordId) {
    state = [
      for (final w in state)
        if (w.id == wordId) w.copyWith(isLearned: !w.isLearned) else w,
    ];
  }

  void addWord({
    required String wordbookId,
    required String headword,
    required String meaningJa,
    required String partOfSpeech,
  }) {
    _seq++;
    state = [
      ...state,
      Word(
        id: 'w_$_seq',
        wordbookId: wordbookId,
        headword: headword,
        meaningJa: meaningJa,
        partOfSpeech: partOfSpeech,
      ),
    ];
  }
}

final wordsProvider = NotifierProvider<WordsNotifier, List<Word>>(WordsNotifier.new);