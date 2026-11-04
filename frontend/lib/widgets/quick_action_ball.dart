import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 只叠加在 PlanBlindBox 内部的快捷悬浮球，不请求 Android 系统悬浮窗权限。
/// 点击球展开/收起；展开状态点击页面任何非菜单位置也会收起。
class QuickActionBall extends StatefulWidget {
  const QuickActionBall({super.key,
    required this.onMood,
    required this.onTask,
    required this.onHabit,
    required this.onFishing,
    required this.onPeriod,
    required this.showPeriod,
    this.closeToken = 0,
  });

  final Future<void> Function() onMood;
  final Future<void> Function() onTask;
  final Future<void> Function() onHabit;
  final Future<void> Function() onFishing;
  final Future<void> Function() onPeriod;
  final bool showPeriod;
  final int closeToken;

  @override
  State<QuickActionBall> createState() => _QuickActionBallState();
}

class _QuickActionBallState extends State<QuickActionBall> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant QuickActionBall oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.closeToken != widget.closeToken && _expanded) {
      _expanded = false;
    }
  }

  void _toggle() => setState(() => _expanded = !_expanded);

  void _invoke(Future<void> Function() action) {
    setState(() => _expanded = false);
    // 执行操作由外层 Shell 负责捕获异常并提示。
    action();
  }

  @override
  Widget build(BuildContext context) => Stack(children: [
    if (_expanded)
      Positioned.fill(child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _expanded = false),
        child: Container(color: Colors.black.withOpacity(0.12)),
      )),
    Positioned(
      left: 16,
      bottom: 12,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min, children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, animation) => FadeTransition(opacity: animation,
              child: ScaleTransition(scale: animation,
                alignment: Alignment.bottomLeft, child: child)),
            child: _expanded
              ? Material(
                  key: const ValueKey('menu'),
                  elevation: 8,
                  color: const Color(0xFFF8FFF8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 240),
                    child: Padding(
                      padding: const EdgeInsets.all(13),
                      child: Wrap(spacing: 9, runSpacing: 9, children: [
                        if (widget.showPeriod)
                          _item(Icons.nightlight_round, '月经', widget.onPeriod,
                            const Color(0xFFFFE9F0)),
                        _item(Icons.emoji_emotions_outlined, '情绪', widget.onMood,
                          const Color(0xFFFFF2CB)),
                        _item(Icons.add_task_rounded, '新建任务', widget.onTask,
                          const Color(0xFFE3F4E4)),
                        _item(Icons.spa_outlined, '新建习惯', widget.onHabit,
                          const Color(0xFFE3F4E4)),
                        _item(Icons.phishing_rounded, '钓鱼', widget.onFishing,
                          const Color(0xFFE1F3FC)),
                      ]),
                    ),
                  ),
                )
              : const SizedBox(key: ValueKey('collapsed'), height: 0),
          ),
          if (_expanded) const SizedBox(height: 10),
          FloatingActionButton.small(
            heroTag: 'planblindbox-quick-action-ball',
            tooltip: _expanded ? '收起悬浮球' : '展开快捷菜单',
            backgroundColor: const Color(0xFFFFECA8),
            foregroundColor: AppColors.forest,
            onPressed: _toggle,
            child: AnimatedRotation(
              turns: _expanded ? 0.125 : 0,
              duration: const Duration(milliseconds: 180),
              child: Icon(_expanded ? Icons.close_rounded : Icons.add_rounded, size: 26),
            ),
          ),
        ],
      ),
    ),
  ]);

  Widget _item(IconData icon, String title,
      Future<void> Function() action, Color color) => InkWell(
    borderRadius: BorderRadius.circular(15),
    onTap: () => _invoke(action),
    child: Container(
      width: 99,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(15)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 25, color: AppColors.forest),
        const SizedBox(height: 4),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11)),
      ]),
    ),
  );
}
