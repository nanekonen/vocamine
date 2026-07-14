import 'package:flutter/services.dart';

import '../models/word.dart';

class WordSpeech {
  static const _channel = MethodChannel('glossalyze/text_to_speech');

  Future<void> speak(Word word) async {
    final text = word.headword.trim();
    if (text.isEmpty) return;
    await _channel.invokeMethod<void>('speak', {
      'text': text,
      'language': 'en-US',
      'rate': 0.9,
    });
  }

  Future<void> stop() => _channel.invokeMethod<void>('stop');
}
