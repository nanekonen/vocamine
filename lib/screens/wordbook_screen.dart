import 'package:flutter/material.dart';

class WordbookScreen extends StatelessWidget {
  const WordbookScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('単語帳'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '未学習'),
              Tab(text: '学習済み'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _WordList(isLearned: false),
            _WordList(isLearned: true),
          ],
        ),
      ),
    );
  }
}

class _WordList extends StatelessWidget {
  final bool isLearned;
  const _WordList({required this.isLearned});

  @override
  Widget build(BuildContext context) {
    // TODO: DBから単語リストを取得
    return const Center(child: Text('単語がまだありません'));
  }
}