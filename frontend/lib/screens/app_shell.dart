import 'package:flutter/material.dart';

import '../data/today_api.dart';
import 'today_page.dart';
import 'store_page.dart';
import 'stats_page.dart';
import 'time_page.dart';
import 'my_page.dart';
import 'mod_hub_drawer.dart';
import '../services/app_preferences.dart';
import '../services/cloud_archive_service.dart';
import '../auth/auth_session.dart';
import '../data/stats_api.dart';
import '../data/wellbeing_repository.dart';
import '../widgets/quick_action_ball.dart';
import 'habit_management_page.dart';
import 'fishing_session_dialog.dart';
import 'wellbeing_pages.dart';

/// 一级导航容器：今日、时间、商店、统计、我的处于同一层级。
/// 复用同一个 TodayApi 作为本地核心业务入口。
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.api,
    required this.auth,
    this.archiveController,
  });

  final TodayApi api;
  final AuthSession auth;
  final CloudArchiveController? archiveController;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _selectedIndex = AppPreferences.instance.defaultTabIndex;
  int _todayVersion = 0;
  int _timeVersion = 0;
  int _storeVersion = 0;
  int _statsVersion = 0;
  int _myVersion = 0;
  int _closeBallToken = 0;

  @override
  void initState() {
    super.initState();
    widget.auth.addListener(_onAccountChanged);

    // 首次显示应用页面后，自动尝试每日签到。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _signInDaily();
    });
  }

  void _onAccountChanged() {
    if (mounted) setState(() => _todayVersion++);
  }

  bool get _isFemale {
    if (!widget.auth.isSignedIn) return false;
    final gender = widget.auth.user?.gender.toUpperCase() ?? '';
    return gender == 'FEMALE' || gender == 'F' || gender == '女';
  }

  // 生理期/日记按当前登录账号隔离；游客使用单独的负数 ID。
  int get _wellbeingUserId => widget.auth.isSignedIn
      ? (widget.auth.user?.userId ?? -1) : -1;

  WellbeingRepository get _wellbeing => WellbeingRepository(
    userId: _wellbeingUserId,
    signInUserId: widget.api.userId,
  );

  Future<void> _safeAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作失败：$e')));
    }
  }

  Future<void> _quickTask() => _safeAction(() async {
    final created = await showModalBottomSheet<bool>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (_) => TaskComposer(api: widget.api));
    if (created == true && mounted) setState(() => _todayVersion++);
  });

  Future<void> _quickHabit() => _safeAction(() async {
    final today = await widget.api.getToday();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => HabitManagementPage(
        api: widget.api, businessDate: today.date, autoCreate: true)));
    if (mounted) setState(() => _todayVersion++);
  });

  Future<void> _quickFishing() => _safeAction(() async {
    final stats = StatsApi(baseUrl: widget.api.baseUrl, userId: widget.api.userId);
    try {
      await showDialog<int>(context: context, barrierDismissible: false,
        builder: (_) => FishingSessionDialog(api: stats));
      if (mounted) setState(() { _timeVersion++; _statsVersion++; });
    } finally {
      stats.dispose();
    }
  });

  Future<void> _quickMood() => _safeAction(() async {
    final mood = await showMoodPicker(context, _wellbeing);
    if (mood == null) return;
    await _wellbeing.saveMood(DateTime.now(), mood);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已记录今天的心情：${mood.emoji} ${mood.name}')));
  });

  Future<void> _quickPeriod() => _safeAction(() async {
    if (!_isFemale) return;
    await showPeriodRecorder(context, _wellbeing);
  });

  @override
  void dispose() {
    widget.auth.removeListener(_onAccountChanged);
    super.dispose();
  }

  Future<void> _signInDaily() async {
    try {
      final result = await widget.api.dailySignIn();

      if (!mounted) return;

      // 偏好设置只控制提示，不影响自动签到与奖励发放。
      if (!AppPreferences.instance.showDailySignInNotice) return;

      if (result['granted'] == true) {
        setState(() {
          _todayVersion++;
        });
      }

      // 今天已经领取过，不重复提示。
      if (result['granted'] != true) return;

      final totalWater = (result['totalWater'] as num?)?.toInt() ?? 0;

      final streakDay = (result['monthlyStreakDay'] as num?)?.toInt() ??
          (result['streakDay'] as num?)?.toInt() ??
          1;
      final allTimeStreak =
          (result['allTimeStreakDay'] as num?)?.toInt() ?? streakDay;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '每日签到成功！本月连续第 $streakDay 天，历史连续 $allTimeStreak 天，获得 $totalWater 滴水滴。',
          ),
          duration: const Duration(seconds: 4),
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
    if (nextIndex == _selectedIndex) {
      setState(() => _closeBallToken++);
      return;
    }
    setState(() {
      _closeBallToken++;
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
      key: _scaffoldKey,
      drawer: ModHubDrawer(api: widget.api, auth: widget.auth),
      body: Stack(children: [
        IndexedStack(
          index: _selectedIndex,
          children: [
          TodayPage(
            key: ValueKey('today-$_todayVersion'),
            api: widget.api,
            archiveController: widget.archiveController,
            isFemale: _isFemale,
            wellbeingUserId: _wellbeingUserId,
            onOpenModDrawer: () => _scaffoldKey.currentState?.openDrawer(),
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
            isFemale: _isFemale,
            wellbeingUserId: _wellbeingUserId,
            refreshToken: _statsVersion,
          ),
          MyPage(
            api: widget.api,
            auth: widget.auth,
            refreshToken: _myVersion,
          ),
          ],
        ),
        QuickActionBall(
          closeToken: _closeBallToken,
          showPeriod: _isFemale,
          onPeriod: _quickPeriod,
          onMood: _quickMood,
          onTask: _quickTask,
          onHabit: _quickHabit,
          onFishing: _quickFishing,
        ),
      ]),
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
