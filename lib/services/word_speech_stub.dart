import 'package:audioplayers/audioplayers.dart';

import '../models/word.dart';
import 'vocamine_api_client.dart';

class WordSpeech {
  final AudioPlayer _player = AudioPlayer();

  Future<void> speak(Word word) async {
    await _player.stop();
    final uri = Uri.parse('${VocamineApiClient.baseUrl}/words/pronunciation')
        .replace(
          queryParameters: {
            'word': word.headword,
            if (word.ipa?.trim().isNotEmpty == true) 'ipa': word.ipa!,
          },
        );
    await _player.play(UrlSource(uri.toString()));
  }

  Future<void> stop() => _player.stop();
}
