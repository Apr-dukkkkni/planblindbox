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

  @override
  void initState() {
    super.initState();

    // 首次显示应用页面后，自动尝试每日签到。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _signInDaily();
    });
  }

  Future<void> _signInDaily() async {
    try {
      final result = await widget.api.dailySignIn();

      if (!mounted) return;

      // 今天已经领取过，不重复提示。
      if (result['granted'] != true) return;

      final totalWater = (result['totalWater'] as num?)?.toInt() ?? 0;

      final streakDay = (result['streakDay'] as num?)?.toInt() ?? 1;

      final baseWater =
          (result['baseWater'] as num?)?.toInt() ?? totalWater;

      final bonusWater =
          (result['bonusWater'] as num?)?.toInt() ?? 0;

      final waterBalance =
          (result['waterBalance'] as num?)?.toInt() ?? 0;

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: Icon(
            Icons.water_drop_rounded,
            size: 42,
            color: Theme.of(dialogContext).colorScheme.primary,
          ),
          title: const Text(
            '每日签到成功！',
            textAlign: TextAlign.center,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('连续签到第 $streakDay 天'),
              const SizedBox(height: 14),
              Text('基础奖励  +$baseWater 水滴'),
              Text('阶梯奖励  +$bonusWater 水滴'),
              const Divider(height: 24),
              Text(
                '+$totalWater 水滴',
                style: const TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text('当前余额：$waterBalance 水滴'),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('收下奖励'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('每日签到失败：$error'),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

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
