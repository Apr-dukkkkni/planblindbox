import 'package:flutter/material.dart';

import '../data/today_api.dart';
import 'today_page.dart';
import 'store_page.dart';
import 'stats_page.dart';
import 'time_page.dart';
import 'my_page.dart';

/// 一级导航容器：今日、时间、商店、统计、我的处于同一层级。
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
  int _timeVersion = 0;
  int _storeVersion = 0;
  int _statsVersion = 0;
  int _myVersion = 0;

  void _selectTab(int nextIndex) {
    if (nextIndex == _selectedIndex) return;
    setState(() {
      _selectedIndex = nextIndex;
      // 页面再次打开时刷新，避免今日、时间、商店、统计和我的显示旧数据。
      if (nextIndex == 0) _todayVersion++;
      if (nextIndex == 1) _timeVersion++;
      if (nextIndex == 2) _storeVersion++;
      if (nextIndex == 3) _statsVersion++;
      if (nextIndex == 4) _myVersion++;
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
          TimePage(
            key: ValueKey('time-$_timeVersion'),
            api: widget.api,
            refreshToken: _timeVersion,
          ),
          StorePage(
            api: widget.api,
            refreshToken: _storeVersion,
          ),
          StatsPage(
            api: widget.api,
            refreshToken: _statsVersion,
          ),
          MyPage(
            api: widget.api,
            refreshToken: _myVersion,
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
            icon: Icon(Icons.timer_outlined),
            selectedIcon: Icon(Icons.timer),
            label: '时间',
          ),
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: '商店',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: '统计',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
