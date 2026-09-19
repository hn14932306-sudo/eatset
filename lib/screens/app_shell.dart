import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'history_screen.dart';
import 'preferences_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(
      index: _index,
      children: [
        const HomeScreen(),
        HistoryScreen(
          active: _index == 1,
          initialFavorites: true,
          showTabs: false,
        ),
        HistoryScreen(active: _index == 2, showTabs: false),
        const PreferencesScreen(),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _index,
      onDestinationSelected: (value) => setState(() => _index = value),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.restaurant_outlined),
          selectedIcon: Icon(Icons.restaurant),
          label: '這餐',
        ),
        NavigationDestination(
          icon: Icon(Icons.bookmark_outline),
          selectedIcon: Icon(Icons.bookmark),
          label: '收藏',
        ),
        NavigationDestination(icon: Icon(Icons.history), label: '紀錄'),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: '我的',
        ),
      ],
    ),
  );
}
