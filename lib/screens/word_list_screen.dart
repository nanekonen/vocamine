import 'package:flutter/material.dart';

import '../models/word.dart';
import '../utils/part_of_speech_label.dart';
import '../widgets/academic_tag.dart';

class WordListScreen extends StatefulWidget {
  final String title;
  final Future<List<Word>> Function() loadWords;

  const WordListScreen({
    super.key,
    required this.title,
    required this.loadWords,
  });

  @override
  State<WordListScreen> createState() => _WordListScreenState();
}

class _WordListScreenState extends State<WordListScreen> {
  late Future<List<Word>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.loadWords();
  }

  void _reload() {
    setState(() => _future = widget.loadWords());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: '更新',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      body: FutureBuilder<List<Word>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('取得に失敗しました: ${snapshot.error}'));
          }
          final words = snapshot.data ?? const [];
          if (words.isEmpty) {
            return const Center(child: Text('単語がまだありません'));
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            itemCount: words.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final word = words[index];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        word.headword,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        word.meaningJa,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      if (word.partOfSpeech.isNotEmpty)
                        AcademicTag(
                          label: partOfSpeechLabel(word.partOfSpeech),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
