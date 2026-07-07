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
              width: 248,
              decoration: const BoxDecoration(
                color: Color(0xFFFCFAF6),
                border: Border(right: BorderSide(color: Color(0xFFE3DED3))),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.school_outlined,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Vocamine',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      ...List.generate(_destinations.length, (i) {
                        final destination = _destinations[i];
                        final selected = _index == i;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
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
    final primary = Theme.of(context).colorScheme.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE0ECE8) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? const Color(0xFFB7C8C2) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: selected ? primary : null),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: selected ? primary : const Color(0xFF4A504B),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
