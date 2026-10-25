import 'package:flutter/material.dart';

import '../data/today_api.dart';
import 'task_library_page.dart';
import 'today_page.dart';
import 'store_page.dart';

/// 一级导航容器：今日、任务库和商店是同一层级的页面。
/// 复用同一个 TodayApi，不重复创建 HTTP Client。
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.api});

  final TodayApi api;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  int _todayVersion = 0;
  int _libraryVersion = 0;
  int _storeVersion = 0;

  void _selectTab(int nextIndex) {
    if (nextIndex == _selectedIndex) return;
    setState(() {
      _selectedIndex = nextIndex;
      // 页面再次打开时刷新数据，避免今日与任务库、商店展示旧余额。
      if (nextIndex == 0) _todayVersion++;
      if (nextIndex == 1) _libraryVersion++;
      if (nextIndex == 2) _storeVersion++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          TodayPage(
            key: ValueKey('today-$_todayVersion'),
            api: widget.api,
          ),
          TaskLibraryPage(
            key: ValueKey('library-$_libraryVersion'),
            api: widget.api,
          ),
          StorePage(
            api: widget.api,
            refreshToken: _storeVersion,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: '今日',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_open_outlined),
            selectedIcon: Icon(Icons.folder_open),
            label: '任务库',
          ),
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: '商店',
          ),
        ],
      ),
    );
  }
}
