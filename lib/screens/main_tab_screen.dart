import 'package:flutter/material.dart';
import 'materials_screen.dart';
import 'wordbook_list_screen.dart';
import 'mypage_screen.dart';

class MainTabScreen extends StatefulWidget {
  const MainTabScreen({super.key});

  @override
  State<MainTabScreen> createState() => _MainTabScreenState();
}

class _MainTabScreenState extends State<MainTabScreen> {
  int _index = 0;

  static const _tabs = [
    MaterialsScreen(),
    WordbookListScreen(),
    MyPageScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: _tabs,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.upload_file), label: '教材'),
          NavigationDestination(icon: Icon(Icons.book), label: '単語帳'),
          NavigationDestination(icon: Icon(Icons.account_circle), label: 'マイページ'),
        ],
      ),
    );
  }
}