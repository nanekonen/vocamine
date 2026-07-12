import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/word.dart';
import '../services/vocamine_api_client.dart';
import '../services/word_speech.dart';
import '../utils/part_of_speech_label.dart';
import '../widgets/academic_tag.dart';

enum WordStudyMode { flashcards, quiz, test }

enum _FinishAction { close, retryWrong, markLearned }

String dictionarySourceLabel(String source) {
  const labels = {
    'wiktionary': 'Wiktionary',
    'grammar': '文法データ',
    'gemini': 'Gemini',
    'cefr_j': 'CEFR-J',
    'phave_list': 'PHaVE List',
    'phrase_list': 'Phrase List',
    'academic_collocation_list': 'Academic Collocation List',
    'collins': 'Collins',
    'cambridge': 'Cambridge',
    'oxford': 'Oxford',
    'manual': '手動登録',
  };
  return labels[source] ?? source;
}

class WordSpeaker {
  WordSpeaker._();
  static final instance = WordSpeaker._();
  final WordSpeech _speech = WordSpeech();

  Future<void> speak(Word word) async {
    await _speech.speak(word);
  }
}

class AnswerFeedbackPlayer {
  AnswerFeedbackPlayer._();
  static final instance = AnswerFeedbackPlayer._();
  final AudioPlayer _player = AudioPlayer();

  Uint8List _tone({required bool correct}) {
    const sampleRate = 22050;
    const durationMs = 240;
    final sampleCount = sampleRate * durationMs ~/ 1000;
    final dataSize = sampleCount * 2;
    final bytes = ByteData(44 + dataSize);
    void text(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        bytes.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    text(0, 'RIFF');
    bytes.setUint32(4, 36 + dataSize, Endian.little);
    text(8, 'WAVEfmt ');
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little);
    bytes.setUint16(22, 1, Endian.little);
    bytes.setUint32(24, sampleRate, Endian.little);
    bytes.setUint32(28, sampleRate * 2, Endian.little);
    bytes.setUint16(32, 2, Endian.little);
    bytes.setUint16(34, 16, Endian.little);
    text(36, 'data');
    bytes.setUint32(40, dataSize, Endian.little);
    for (var i = 0; i < sampleCount; i++) {
      final progress = i / sampleCount;
      final frequency = correct
          ? (progress < .5 ? 660.0 : 880.0)
          : (progress < .5 ? 260.0 : 180.0);
      final envelope = min(1.0, (1 - progress) * 5);
      final sample =
          (sin(2 * pi * frequency * i / sampleRate) * envelope * 10000).round();
      bytes.setInt16(44 + i * 2, sample, Endian.little);
    }
    return bytes.buffer.asUint8List();
  }

  Future<void> play(bool correct) async {
    await _player.stop();
    await _player.play(BytesSource(_tone(correct: correct)));
  }
}

class WordDetailScreen extends StatefulWidget {
  final Word word;
  const WordDetailScreen({super.key, required this.word});

  @override
  State<WordDetailScreen> createState() => _WordDetailScreenState();
}

class _WordDetailScreenState extends State<WordDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => WordSpeaker.instance.speak(widget.word),
    );
  }

  @override
  Widget build(BuildContext context) {
    final word = widget.word;
    return Scaffold(
      appBar: AppBar(title: const Text('単語詳細')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  word.headword,
                  style: Theme.of(context).textTheme.displaySmall,
                ),
              ),
              IconButton.filledTonal(
                tooltip: '発音を再生',
                onPressed: () => WordSpeaker.instance.speak(word),
                icon: const Icon(Icons.volume_up),
              ),
            ],
          ),
          if (word.ipa?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(word.ipa!, style: Theme.of(context).textTheme.titleMedium),
          ],
          const SizedBox(height: 16),
          AcademicTag(label: partOfSpeechLabel(word.partOfSpeech)),
          const SizedBox(height: 24),
          Text('日本語', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Text(
            word.meaningJa,
            style: GoogleFonts.sourceSerif4(
              textStyle: Theme.of(context).textTheme.titleLarge,
              height: 1.55,
            ),
          ),
          if (word.definitionEn?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 24),
            Text('English', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Text(
              word.definitionEn!,
              style: GoogleFonts.sourceSerif4(fontSize: 17, height: 1.65),
            ),
          ],
          if (word.examples.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('例文', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            for (final example in word.examples)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        example.sentence,
                        style: GoogleFonts.sourceSerif4(
                          fontSize: 17,
                          height: 1.6,
                        ),
                      ),
                      if (example.translatedSentence?.trim().isNotEmpty ==
                          true) ...[
                        const SizedBox(height: 6),
                        Text(
                          example.translatedSentence!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
          const SizedBox(height: 24),
          Text('辞書・意味の出典', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Text(
            word.dictionarySource.isEmpty
                ? '出典情報なし'
                : dictionarySourceLabel(word.dictionarySource),
          ),
          const SizedBox(height: 24),
          Text('登録元教材', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          if (word.sourceLabels.isEmpty)
            const Text('教材からの登録ではありません')
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final source in word.sourceLabels)
                  AcademicTag(label: source),
              ],
            ),
          if (word.tier != null) ...[
            const SizedBox(height: 16),
            Text('語彙レベル: Tier ${word.tier}'),
          ],
        ],
      ),
    );
  }
}

class WordStudyScreen extends StatefulWidget {
  final List<Word> words;
  final WordStudyMode mode;
  const WordStudyScreen({super.key, required this.words, required this.mode});

  @override
  State<WordStudyScreen> createState() => _WordStudyScreenState();
}

class _WordStudyScreenState extends State<WordStudyScreen> {
  late final List<Word> _words;
  final Map<String, List<Word>> _distractors = {};
  final TextEditingController _answerController = TextEditingController();
  int _index = 0;
  bool _revealed = false;
  int? _selected;
  bool _loadingDistractors = false;
  Color? _feedbackColor;
  final Set<String> _correct = {};
  final Set<String> _mastered = {};

  Word get _current => _words[_index];

  @override
  void initState() {
    super.initState();
    _words = [...widget.words]..shuffle();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _speak();
      if (widget.mode == WordStudyMode.quiz) _loadDistractors();
    });
  }

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  Future<void> _loadDistractors() async {
    setState(() => _loadingDistractors = true);
    final ids = _words.map((word) => word.meaningId).whereType<int>().toSet();
    for (final pos in _words.map((word) => word.partOfSpeech).toSet()) {
      final local = _words.where((word) => word.partOfSpeech == pos).toList();
      if (local.length < 4) {
        try {
          local.addAll(
            await VocamineApiClient().fetchDistractors(
              partOfSpeech: pos,
              excludeMeaningIds: ids,
              limit: 12,
            ),
          );
        } catch (_) {}
      }
      _distractors[pos] = local;
    }
    if (mounted) setState(() => _loadingDistractors = false);
  }

  void _speak() => WordSpeaker.instance.speak(_current);

  List<Word> get _choices {
    final pool =
        _distractors[_current.partOfSpeech] ??
        _words
            .where((word) => word.partOfSpeech == _current.partOfSpeech)
            .toList();
    final others =
        pool.where((word) => word.meaningId != _current.meaningId).toList()
          ..shuffle(Random(_index));
    return <Word>[_current, ...others.take(3)].toList()
      ..shuffle(Random(_index));
  }

  void _answer(Word choice) {
    if (_selected != null) return;
    final correct = choice.studyKey == _current.studyKey;
    setState(() {
      _selected = choice.studyKey.hashCode;
      if (correct) {
        _correct.add(_current.studyKey);
        _mastered.add(_current.studyKey);
      }
    });
    _showFeedback(correct);
  }

  void _decideTypedAnswer() {
    if (_revealed) return;
    final typed = _answerController.text.trim().toLowerCase();
    final answers = _current.meaningJa
        .split(RegExp(r'[/,、;；]'))
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty);
    final correct =
        typed.isNotEmpty && answers.any((answer) => answer == typed);
    setState(() {
      _revealed = true;
      if (correct) {
        _correct.add(_current.studyKey);
        _mastered.add(_current.studyKey);
      }
    });
    _showFeedback(correct);
  }

  void _markCurrentCorrect() {
    setState(() {
      _correct.add(_current.studyKey);
      _mastered.add(_current.studyKey);
    });
    _showFeedback(true);
  }

  void _showFeedback(bool correct) {
    AnswerFeedbackPlayer.instance.play(correct);
    final color = correct
        ? const Color(0xFF68ABFF).withValues(alpha: .18)
        : const Color(0xFFBA1A1A).withValues(alpha: .14);
    setState(() => _feedbackColor = color);
    Future<void>.delayed(const Duration(milliseconds: 420), () {
      if (mounted && _feedbackColor == color) {
        setState(() => _feedbackColor = null);
      }
    });
  }

  Future<void> _next() async {
    if (_index + 1 >= _words.length) {
      await _finish();
      return;
    }
    setState(() {
      _index++;
      _revealed = false;
      _selected = null;
      _answerController.clear();
    });
    _speak();
  }

  Future<void> _finish() async {
    final wrong = _words
        .where((word) => !_correct.contains(word.studyKey))
        .toList();
    final action = await showDialog<_FinishAction>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(widget.mode == WordStudyMode.test ? 'テスト結果' : '学習結果'),
        content: Text(
          '${_words.length}問中 ${_correct.length}問正解'
          '${wrong.isEmpty ? '\n全問正解です！' : '\n${wrong.length}問を間違えました。'}'
          '${widget.mode == WordStudyMode.test ? '\n\n正解した単語を学習済みにすることもできます。' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _FinishAction.close),
            child: const Text('終了'),
          ),
          if (wrong.isNotEmpty)
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context, _FinishAction.retryWrong),
              icon: const Icon(Icons.replay),
              label: const Text('間違えた問題だけやり直す'),
            ),
          if (widget.mode == WordStudyMode.test)
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, _FinishAction.markLearned),
              child: const Text('正解した単語を学習済みにする'),
            ),
        ],
      ),
    );
    if (action == _FinishAction.retryWrong) {
      setState(() {
        _words
          ..clear()
          ..addAll(wrong)
          ..shuffle();
        _index = 0;
        _correct.clear();
        _selected = null;
        _revealed = false;
        _answerController.clear();
      });
      _speak();
      return;
    }
    if (action == _FinishAction.markLearned) {
      for (final word in widget.words.where(
        (word) => _mastered.contains(word.studyKey),
      )) {
        await VocamineApiClient().updateWordbookEntry(
          entryId: word.id,
          isLearned: true,
        );
      }
    }
    if (mounted) {
      Navigator.of(context).pop(action == _FinishAction.markLearned);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_words.isEmpty) {
      return const Scaffold(body: Center(child: Text('学習する単語がありません')));
    }
    final isFlash = widget.mode == WordStudyMode.flashcards;
    final isQuiz = widget.mode == WordStudyMode.quiz;
    final isTest = widget.mode == WordStudyMode.test;
    final choices = isQuiz ? _choices : const <Word>[];
    final displayedIndex = _index;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.mode == WordStudyMode.flashcards
              ? 'フラッシュカード'
              : widget.mode == WordStudyMode.quiz
              ? '4択問題'
              : 'テスト',
        ),
      ),
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        color: _feedbackColor,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: isFlash && !_revealed
              ? () {
                  if (_index == displayedIndex && !_revealed) {
                    setState(() => _revealed = true);
                  }
                }
              : null,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LinearProgressIndicator(value: (_index + 1) / _words.length),
                const SizedBox(height: 8),
                Text(
                  '${_index + 1} / ${_words.length}',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 20),
                        Text(
                          _current.headword,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.displaySmall,
                        ),
                        if (_current.ipa?.trim().isNotEmpty == true)
                          Text(_current.ipa!, textAlign: TextAlign.center),
                        IconButton(
                          onPressed: _speak,
                          icon: const Icon(Icons.volume_up),
                        ),
                        const SizedBox(height: 24),
                        if (isFlash) ...[
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: _revealed
                                ? Text(
                                    _current.meaningJa,
                                    key: const ValueKey('answer'),
                                    textAlign: TextAlign.center,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.headlineSmall,
                                  )
                                : const Text(
                                    '画面をクリックして答えを表示',
                                    textAlign: TextAlign.center,
                                  ),
                          ),
                        ] else if (isQuiz) ...[
                          if (_loadingDistractors)
                            const Center(child: CircularProgressIndicator())
                          else
                            for (final choice in choices)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: OutlinedButton(
                                  style: _selected == null
                                      ? null
                                      : OutlinedButton.styleFrom(
                                          backgroundColor:
                                              choice.studyKey ==
                                                  _current.studyKey
                                              ? const Color(
                                                  0xFF68ABFF,
                                                ).withValues(alpha: .16)
                                              : ((_selected ==
                                                        choice
                                                            .studyKey
                                                            .hashCode)
                                                    ? const Color(
                                                        0xFFBA1A1A,
                                                      ).withValues(alpha: .12)
                                                    : null),
                                        ),
                                  onPressed: () => _answer(choice),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Text(choice.meaningJa),
                                  ),
                                ),
                              ),
                        ] else if (isTest) ...[
                          TextField(
                            controller: _answerController,
                            enabled: !_revealed,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _decideTypedAnswer(),
                            decoration: const InputDecoration(
                              labelText: '日本語の意味を入力',
                              hintText: '完全一致でなくても後から正解にできます',
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _revealed ? null : _decideTypedAnswer,
                            child: const Text('決定して答え合わせ'),
                          ),
                        ],
                        if ((_selected != null && isQuiz) ||
                            (_revealed && isTest)) ...[
                          const SizedBox(height: 20),
                          _AnswerDetail(word: _current),
                          if (isTest && !_correct.contains(_current.studyKey))
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: _markCurrentCorrect,
                                icon: const Icon(Icons.check),
                                label: const Text('正解にする'),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (isFlash)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _next,
                          icon: const Icon(Icons.close),
                          label: const Text('わからない'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () {
                            _correct.add(_current.studyKey);
                            _mastered.add(_current.studyKey);
                            _next();
                          },
                          icon: const Icon(Icons.check),
                          label: const Text('わかる'),
                        ),
                      ),
                    ],
                  )
                else if ((isQuiz && _selected != null) || (isTest && _revealed))
                  FilledButton(
                    onPressed: _next,
                    child: Text(_index + 1 == _words.length ? '結果を見る' : '次へ'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnswerDetail extends StatelessWidget {
  final Word word;
  const _AnswerDetail({required this.word});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('答え', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Card(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  word.meaningJa,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (word.definitionEn?.trim().isNotEmpty == true)
                  Text(word.definitionEn!),
                const SizedBox(height: 6),
                Text(
                  '${partOfSpeechLabel(word.partOfSpeech)} ・ ${dictionarySourceLabel(word.dictionarySource)}',
                ),
                if (word.ipa?.trim().isNotEmpty == true)
                  Text('IPA: ${word.ipa}'),
                if (word.tier != null) Text('語彙レベル: Tier ${word.tier}'),
                if (word.sourceLabels.isNotEmpty)
                  Text('登録元教材: ${word.sourceLabels.join('、')}'),
                if (word.examples.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('例: ${word.examples.first.sentence}'),
                  if (word.examples.first.translatedSentence
                          ?.trim()
                          .isNotEmpty ==
                      true)
                    Text(word.examples.first.translatedSentence!),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
