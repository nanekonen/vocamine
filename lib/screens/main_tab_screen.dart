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

  static const _destinations = [
    NavigationDestination(icon: Icon(Icons.description_outlined), label: '教材'),
    NavigationDestination(icon: Icon(Icons.menu_book_outlined), label: '単語帳'),
    NavigationDestination(
      icon: Icon(Icons.account_circle_outlined),
      label: 'マイページ',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            Container(
              width: 280,
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(right: BorderSide(color: Color(0xFFDDE3EA))),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 32, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Vocamine',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 48),
                      ...List.generate(_destinations.length, (i) {
                        final destination = _destinations[i];
                        final selected = _index == i;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _SideNavItem(
                            icon: (destination.icon as Icon).icon!,
                            label: destination.label,
                            selected: selected,
                            onTap: () => setState(() => _index = i),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: IndexedStack(index: _index, children: _tabs),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: _destinations,
      ),
    );
  }
}

class _SideNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SideNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.zero,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFE16D) : Colors.transparent,
          borderRadius: BorderRadius.zero,
          border: Border(
            left: BorderSide(
              color: selected ? const Color(0xFF0060AC) : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 22,
              color: selected
                  ? const Color(0xFF041627)
                  : const Color(0xFF5B6570),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? const Color(0xFF041627)
                    : const Color(0xFF44474C),
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
