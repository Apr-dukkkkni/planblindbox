import 'package:flutter/material.dart';

import '../mod_platform/runtime/mod_capability_broker.dart';
import '../mod_platform/runtime/mod_runtime_manager.dart';
import '../mod_platform/runtime/platform_proof_approval_provider.dart';
import '../mod_platform/ui/mod_ui_panel.dart';
import '../mod_platform/ui/mod_ui_surface.dart';

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
import '../services/core_auto_sync.dart';
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

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final ModRuntimeManager _uiRuntime =
      ModRuntimeManager.forRepository(widget.api.repository);
  late final PlatformProofApprovalProvider _platformApproval =
      PlatformProofApprovalProvider(auth: widget.auth);
  late final ModCapabilityBroker _uiBroker = ModCapabilityBroker.forRepository(
    widget.api.repository,
    approvalProvider: _platformApproval,
  );
  ModRuntimeInstance? _openModInstance;
  ModUiPresentation _presentation = ModUiPresentation.dialog;
  bool _openingMod = false;

  Future<void> _launchMod(String modId, ModUiPresentation mode) async {
    if (_openingMod || !mounted) return;
    _openingMod = true;
    try {
      _dismissMod(returnHome: false);
      final instance = await _uiRuntime.start(modId);
      if (!mounted) {
        _uiRuntime.stop(instance);
        return;
      }
      setState(() {
        _openModInstance = instance;
        _presentation = mode;
        _selectedIndex = 0;
        _todayVersion++;
        _closeBallToken++;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开 MOD：$error')),
        );
      }
    } finally {
      _openingMod = false;
    }
  }

  void _dismissMod({bool returnHome = true}) {
    final previous = _openModInstance;
    if (previous != null) _uiRuntime.stop(previous);
    if (!mounted) return;
    setState(() {
      _openModInstance = null;
      if (returnHome) {
        _selectedIndex = 0;
        _todayVersion++;
        _closeBallToken++;
      }
    });
  }

  int _selectedIndex = AppPreferences.instance.defaultTabIndex;
  int _todayVersion = 0;
  int _timeVersion = 0;
  int _storeVersion = 0;
  int _statsVersion = 0;
  int _myVersion = 0;
  int _closeBallToken = 0;
  int _seenSyncGeneration = CoreAutoSync.instance.appliedGeneration;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.auth.addListener(_onAccountChanged);
    CoreAutoSync.instance.addListener(_onSyncApplied);

    // 首次显示应用页面后，自动尝试每日签到。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _signInDaily();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // No MOD UI keeps a privileged session alive after app suspension.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      if (_openModInstance != null) _dismissMod();
    }
  }

  void _onAccountChanged() {
    // Never carry a MOD surface or Session into another account.
    if (_openModInstance != null) {
      _dismissMod();
    } else if (mounted) {
      setState(() => _todayVersion++);
    }
  }

  void _onSyncApplied() {
    final current = CoreAutoSync.instance.appliedGeneration;
    if (!mounted || current == _seenSyncGeneration) return;
    _seenSyncGeneration = current;
    setState(() {
      _todayVersion++;
      _statsVersion++;
      _myVersion++;
    });
  }

  bool get _isFemale {
    if (!widget.auth.isSignedIn) return false;
    final gender = widget.auth.user?.gender.toUpperCase() ?? '';
    return gender == 'FEMALE' || gender == 'F' || gender == '女';
  }

  // 生理期/日记按当前登录账号隔离；游客使用单独的负数 ID。
  int get _wellbeingUserId =>
      widget.auth.isSignedIn ? (widget.auth.user?.userId ?? -1) : -1;

  WellbeingRepository get _wellbeing => WellbeingRepository(
    userId: _wellbeingUserId,
    signInUserId: widget.api.userId,
  );

  Future<void> _safeAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('操作失败：$e')));
      }
    }
  }

  Future<void> _quickTask() => _safeAction(() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => TaskComposer(api: widget.api),
    );
    if (created == true && mounted) setState(() => _todayVersion++);
  });

  Future<void> _quickHabit() => _safeAction(() async {
    final today = await widget.api.getToday();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HabitManagementPage(
          api: widget.api,
          businessDate: today.date,
          autoCreate: true,
        ),
      ),
    );
    if (mounted) setState(() => _todayVersion++);
  });

  Future<void> _quickFishing() => _safeAction(() async {
    final stats = StatsApi(
      baseUrl: widget.api.baseUrl,
      userId: widget.api.userId,
    );
    try {
      await showDialog<int>(
        context: context,
        barrierDismissible: false,
        builder: (_) => FishingSessionDialog(api: stats),
      );
      if (mounted) {
        setState(() {
          _timeVersion++;
          _statsVersion++;
        });
      }
    } finally {
      stats.dispose();
    }
  });

  Future<void> _quickMood() => _safeAction(() async {
    final mood = await showMoodPicker(context, _wellbeing);
    if (mood == null) return;
    await _wellbeing.saveMood(DateTime.now(), mood);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已记录今天的心情：${mood.emoji} ${mood.name}')),
      );
    }
  });

  Future<void> _quickPeriod() => _safeAction(() async {
    if (!_isFemale) return;
    await showPeriodRecorder(context, _wellbeing);
  });

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.auth.removeListener(_onAccountChanged);
    CoreAutoSync.instance.removeListener(_onSyncApplied);
    _uiRuntime.shutdown();
    _platformApproval.dispose();
    super.dispose();
  }

  Future<void> _signInDaily() async {
    if (!widget.auth.isSignedIn) return; // 游客不产生可信水滴
    final token = widget.auth.token;
    if (token == null) return;
    try {
      final result = await widget.auth.api.claimWater(token);
      if (!mounted || widget.auth.token != token) return;
      final businessDate = result['businessDate']?.toString() ?? '';
      final streak = (result['streakDay'] as num).toInt();
      final rewarded = (result['totalWater'] as num).toInt();
      // 仅保存一个只读的日历标记，不触碰 SQLite 本地资产水滴字段。
      await widget.api.repository.recordServerSignIn(
        businessDate: businessDate,
        streakDay: streak,
        totalWater: rewarded,
      );
      if (!mounted || widget.auth.token != token) return;
      setState(() {
        _todayVersion++;
        _myVersion++;
      });
      if (result['granted'] != true ||
          !AppPreferences.instance.showDailySignInNotice) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('服务器签到成功！连续第 $streak 天，获得 $rewarded 滴水滴。'),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (error) {
      if (!mounted || widget.auth.token != token) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('服务器签到未成功：$error（本地任务可继续使用）'),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _selectTab(int nextIndex) {
    // A floating panel may stay visible while using the host navigation, but
    // full-screen/modal screens do not permit navigation behind the panel.
    if (_openModInstance != null &&
        _presentation != ModUiPresentation.floating) {
      return;
    }
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
    final activeMod = _openModInstance;
    final isModal = activeMod != null &&
        _presentation != ModUiPresentation.floating;
    return PopScope(
      canPop: activeMod == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _openModInstance != null) _dismissMod();
      },
      child: Scaffold(
        key: _scaffoldKey,
        drawer: ModHubDrawer(
          api: widget.api,
          auth: widget.auth,
          onLaunchMod: _launchMod,
        ),
        body: Stack(
          children: [
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
                StorePage(api: widget.api, refreshToken: _storeVersion),
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
            if (activeMod == null)
              QuickActionBall(
                closeToken: _closeBallToken,
                showPeriod: _isFemale,
                onPeriod: _quickPeriod,
                onMood: _quickMood,
                onTask: _quickTask,
                onHabit: _quickHabit,
                onFishing: _quickFishing,
              ),
            if (activeMod != null)
              Positioned.fill(
                child: ModUiSurface(
                  key: ValueKey('mod-ui-${activeMod.installationId}-${_presentation.name}'),
                  presentation: _presentation,
                  onClose: () => _dismissMod(),
                  child: ModUiPanel(
                    instance: activeMod,
                    runtime: _uiRuntime,
                    broker: _uiBroker,
                    onTaskCreated: () {
                      if (mounted) setState(() => _todayVersion++);
                    },
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: isModal
            ? null
            : NavigationBar(
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
      ),
    );
  }
}
