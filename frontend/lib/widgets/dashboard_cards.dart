import 'package:flutter/material.dart';
import '../models/today_models.dart';
import '../theme/app_theme.dart';

class SurfaceCard extends StatelessWidget {
  //基础卡片容器
  const SurfaceCard({super.key, required this.child, this.padding = const EdgeInsets.all(18)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      );
}

class SectionHeading extends StatelessWidget {
  //分区标题栏
  const SectionHeading({super.key, required this.title, required this.subtitle,
      this.actionLabel, this.onAction});
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800,
              fontSize: 20)),
          const SizedBox(height: 3),
          Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        ])),
        if (onAction != null)
          TextButton.icon(onPressed: onAction, icon: const Icon(Icons.add_rounded, size: 19),
              label: Text(actionLabel ?? '添加')),
      ]);
}

class DashboardHero extends StatelessWidget {
  //首页顶部渐变头部卡片
  const DashboardHero({super.key, required this.data});
  final TodayData data;

  @override
  Widget build(BuildContext context) {
    final summary = data.summary;
    final dateParts = data.date.split('-');
    final dateLabel = dateParts.length == 3
        ? '${dateParts[1]}月${dateParts[2]}日'
        : data.date;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.forest, AppColors.deepForest],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha:0.13),
                  borderRadius: BorderRadius.circular(20)),
              child: Text('🌿  $dateLabel · 今日计划',
                  style: const TextStyle(color: Colors.white, fontSize: 12))),
          const Spacer(),
          const Icon(Icons.auto_awesome_rounded, color: Color(0xFFF7D28B), size: 24),
        ]),
        const SizedBox(height: 24),
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('每一步，都算数。',
                style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 9),
            Text('今天已完成 ${summary.completed} / ${summary.total} 项',
                style: const TextStyle(color: Color(0xFFCEDDD5), fontSize: 14)),
            const SizedBox(height: 16),
            Row(children: [
              _heroPill(Icons.check_circle_outline_rounded,
                  '任务 ${summary.taskCompleted}/${summary.taskTotal}'),
              const SizedBox(width: 8),
              _heroPill(Icons.spa_outlined,
                  '习惯 ${summary.habitCheckedIn}/${summary.habitTotal}'),
            ]),
          ])),
          const SizedBox(width: 12),
          SizedBox(width: 104, height: 104,
              child: Stack(alignment: Alignment.center, children: [
                SizedBox(width: 102, height: 102,
                    child: CircularProgressIndicator(
                      value: (summary.completionRate / 100).clamp(0.0, 1.0),
                      strokeWidth: 9,
                      strokeCap: StrokeCap.round,
                      backgroundColor: const Color(0xFF47685E),
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFE8C985)),
                    )),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('${summary.completionRate.toStringAsFixed(0)}%',
                    style: const TextStyle(color: Colors.white, fontSize: 24,
                        fontWeight: FontWeight.w800)),
                  const Text('完成率', style: TextStyle(color: Color(0xFFCEDDD5), fontSize: 11)),
                ])
              ])),
        ])
      ]),
    );
  }

  Widget _heroPill(IconData icon, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha:0.12),
            borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: const Color(0xFFE5EEDC), size: 14),
          const SizedBox(width: 5),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 11)),
        ]),
      );
}

class AssetStrip extends StatelessWidget {
  //资产信息栏
  const AssetStrip({super.key, required this.assets});
  final TodayAssets assets;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 17),
        child: Row(children: [
          _asset(Icons.monetization_on_outlined, '金币', assets.coin.toString(),
              AppColors.amber, const Color(0xFFFFF5E3)),
          _divider(),
          _asset(Icons.bolt_rounded, '经验', assets.exp.toString(),
              const Color(0xFF8B79BC), const Color(0xFFF1ECFA)),
          _divider(),
          _asset(Icons.water_drop_outlined, '水滴', assets.water.toString(),
              const Color(0xFF629CA8), const Color(0xFFE8F4F4)),
        ]),
      );

  Widget _divider() => Container(height: 36, width: 1, color: AppColors.border);

  Widget _asset(IconData icon, String label, String value,
          Color foreground, Color background) => Expanded(
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(width: 28, height: 28,
                decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(9)),
                child: Icon(icon, size: 17, color: foreground)),
            const SizedBox(width: 7),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800,
                color: AppColors.ink, fontSize: 19)),
          ]),
          const SizedBox(height: 5),
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
        ]),
      );
}

class TaskTile extends StatefulWidget {
  //任务卡片
  const TaskTile({super.key, required this.task, required this.todayDate,
    required this.busy, required this.onComplete});

  final TodayTask task;       // 单条任务实体
  final String todayDate;     // 今天日期，用来判断逾期是否是今天逾期
  final bool busy;            // 忙标记：接口请求中，防止重复点击
  final VoidCallback onComplete; // 点击完成的回调（提交给后端）

  @override
  State<TaskTile> createState() => _TaskTileState();
}

class _TaskTileState extends State<TaskTile> {
  bool isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final busy = widget.busy;
    final todayDate = widget.todayDate;
    final onComplete = widget.onComplete;
    final due = task.endTime;
    final now = DateTime.now();
    final remaining = due?.difference(now);
    //距离截止时间小于5小时
    final dueSoon = !task.completedToday && !task.overdue && remaining != null &&
        !remaining.isNegative && remaining < const Duration(hours: 5);
    //今天到期并且已经逾期
    final overdueToday = task.overdue && due != null && _date(due) == todayDate;
    //是否警告
    final alert = dueSoon || task.overdue;
    final titleColor = alert ? AppColors.rose : AppColors.ink;
    final progress = task.progress;


    return GestureDetector(
      //`GestureDetector` 点击卡片触发完成；**已经完成 / 次数耗尽 / 请求中 busy → 点击无效**
        behavior: HitTestBehavior.opaque,

        onTap: task.completedToday ||
            task.remainingCount <= 0 ||
            busy
            ? null
            : onComplete,

        child: SurfaceCard(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 40, height: 40,
            decoration: BoxDecoration(color: task.completedToday
                ? AppColors.paleGreen : AppColors.paleAmber,
                borderRadius: BorderRadius.circular(13)),
            child: Icon(task.completedToday ? Icons.check_rounded : Icons.assignment_outlined,
                color: task.completedToday ? AppColors.forest : const Color(0xFFBE8640))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(task.title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
              color: titleColor,
              decoration: overdueToday ? TextDecoration.lineThrough : null,
              decorationColor: AppColors.rose)),
          if (task.note != null && task.note!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(task.note!, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ],
        ])),
        if (task.completedToday)
          const Icon(Icons.verified_rounded, color: AppColors.leaf)
        else if (alert)
          const Icon(Icons.access_time_filled_rounded, color: AppColors.rose, size: 20),
        const SizedBox(width: 6),

        IconButton(
          icon: const Icon(Icons.more_horiz_rounded),
          tooltip: '任务详情',
          onPressed: () {
            setState((){
              isExpanded = !isExpanded;
            });
          },
        )
      ]),

      const SizedBox(height: 14),
      Wrap(spacing: 7, runSpacing: 6, children: [
        _tag(Icons.flag_outlined, '重要 ${task.importance ?? 3}', AppColors.paleGreen, AppColors.forest),
        _tag(Icons.local_fire_department_outlined, '难度 ${task.difficulty ?? 3}',
            AppColors.paleAmber, const Color(0xFFA76C31)),
        if (due != null) _tag(Icons.schedule_outlined, _dateTime(due),
            task.overdue || dueSoon ? AppColors.paleRose : const Color(0xFFF0F1EE),
            task.overdue || dueSoon ? AppColors.rose : AppColors.muted),
        if (task.overdue) _tag(Icons.warning_amber_rounded,
            overdueToday ? '今日已逾期' : '已逾期', AppColors.paleRose, AppColors.rose),
      ]),
      const SizedBox(height: 17),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('累计进度 ${task.totalActualCount}/${task.targetCount}',
            style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        Text('今日 +${task.todayActualCount}',
            style: const TextStyle(color: AppColors.muted, fontSize: 12)),
      ]),
      const SizedBox(height: 7),
      ClipRRect(borderRadius: BorderRadius.circular(12),
          child: LinearProgressIndicator(value: progress, minHeight: 7,
              backgroundColor: AppColors.paleGreen,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.leaf))),
      const SizedBox(height: 14),

      if (isExpanded) ...[
        const SizedBox(height: 16),
        const Divider(),
        Text(
          '任务说明：${task.note ?? '暂无备注'}',
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Text(
          '累计进度：${task.totalActualCount}/${task.targetCount}',
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
      ],

    ])));
  }

  Widget _tag(IconData icon, String label, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: fg, size: 13),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
      );
}

class HabitTile extends StatelessWidget {
  //习惯打卡卡片
  const HabitTile({super.key, required this.habit, required this.busy, required this.onCheckIn});
  final TodayHabit habit;
  final bool busy;
  final VoidCallback onCheckIn;

  @override
  Widget build(BuildContext context) => SurfaceCard(child: Row(children: [
        Container(width: 49, height: 49,
            decoration: BoxDecoration(color: AppColors.paleGreen,
                borderRadius: BorderRadius.circular(15)),
            child: const Icon(Icons.spa_rounded, size: 25, color: AppColors.leaf)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(habit.name, style: const TextStyle(color: AppColors.ink,
              fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('连续 ${habit.currentStreak} 次 · 累计 ${habit.totalCheckInDays} 天',
              style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        ])),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: habit.checkedInToday || busy ? null : onCheckIn,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.forest,
            side: const BorderSide(color: AppColors.paleGreen, width: 2),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10)),
          icon: busy
              ? const SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(habit.checkedInToday ? Icons.check_circle : Icons.check_circle_outline,
                  size: 18),
          label: Text(habit.checkedInToday ? '已打卡' : '打卡'),
        ),
      ]));
}

class EmptySection extends StatelessWidget {
  //空状态占位卡片
  const EmptySection({super.key, required this.message, required this.icon});
  final String message;
  final IconData icon;
  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Padding(padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(children: [
          Icon(icon, size: 34, color: AppColors.leaf),
          const SizedBox(height: 8),
          Text(message, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
        ])));
}

String _date(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _dateTime(DateTime d) => '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
