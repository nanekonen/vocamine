// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;

import '../models/word.dart';

class WordSpeech {
  Future<html.SpeechSynthesisVoice?>? _voiceFuture;
  int _requestId = 0;

  WordSpeech() {
    // Chrome系では初回のgetVoices()だけ空配列になることがあるため、
    // インスタンス生成時点から音声一覧の準備を始める。
    _voiceFuture = _resolveVoice();
  }

  Future<void> speak(Word word) async {
    final synthesis = html.window.speechSynthesis;
    if (synthesis == null) return;
    final requestId = ++_requestId;
    synthesis.cancel();
    final voice = await (_voiceFuture ??= _resolveVoice());
    // 音声一覧を待っている間に次の単語へ移った場合、古い発話は行わない。
    if (requestId != _requestId) return;
    synthesis.cancel();
    final utterance = html.SpeechSynthesisUtterance(word.headword)
      ..lang = 'en-US'
      ..rate = 0.9
      ..pitch = 1.0
      ..volume = 1.0;
    if (voice != null) utterance.voice = voice;
    synthesis.speak(utterance);
  }

  Future<html.SpeechSynthesisVoice?> _resolveVoice() async {
    final synthesis = html.window.speechSynthesis;
    if (synthesis == null) return null;
    var voices = synthesis.getVoices();
    // voiceschangedの発火タイミングはブラウザごとに異なるので、短い間隔で
    // 再取得する。空のまま既定音声で読み上げる初回だけの音質差を防ぐ。
    for (var attempt = 0; voices.isEmpty && attempt < 40; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      voices = synthesis.getVoices();
    }
    final englishVoices = voices
        .where((voice) => (voice.lang ?? '').toLowerCase().startsWith('en-us'))
        .toList();
    if (englishVoices.isEmpty) return null;
    const preferredNames = [
      'Google US English',
      'Microsoft Aria',
      'Microsoft Jenny',
      'Samantha',
      'Alex',
    ];
    for (final preferred in preferredNames) {
      for (final voice in englishVoices) {
        if ((voice.name ?? '').toLowerCase().contains(
          preferred.toLowerCase(),
        )) {
          return voice;
        }
      }
    }
    return englishVoices.first;
  }

  Future<void> stop() async {
    _requestId++;
    html.window.speechSynthesis?.cancel();
  }
}
