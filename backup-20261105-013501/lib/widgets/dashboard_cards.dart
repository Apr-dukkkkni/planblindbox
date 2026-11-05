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

/// 紧凑的今日双进度卡：数据来自当日任务/习惯与本机 24 小时时钟。
class DashboardHero extends StatefulWidget {
  const DashboardHero({super.key, required this.data, this.onCalendar});
  final TodayData data;
  final VoidCallback? onCalendar;

  @override
  State<DashboardHero> createState() => _DashboardHeroState();
}

class _DashboardHeroState extends State<DashboardHero> {
  late final Stream<int> _clock;

  @override
  void initState() {
    super.initState();
    // 每分钟更新一次时钟；进度每完成一个整点前进一步。
    _clock = Stream<int>.periodic(const Duration(minutes: 1), (i) => i);
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<int>(
    stream: _clock,
    builder: (context, _) {
      final summary = widget.data.summary;
      final total = summary.taskTotal + summary.habitTotal;
      final done = summary.taskCompleted + summary.habitCheckedIn;
      final completion = total <= 0 ? 0.0 : (done / total).clamp(0.0, 1.0).toDouble();
      final now = DateTime.now();
      final hourProgress = now.hour / 24.0;
      return Container(
        padding: const EdgeInsets.fromLTRB(17, 13, 17, 15),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [AppColors.forest, AppColors.deepForest],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('每一步，都算数。',
              style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800))),
            IconButton(
              tooltip: '签到日历与日记',
              onPressed: widget.onCalendar,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.calendar_month_outlined, color: Colors.white70, size: 23),
            ),
          ]),
          const SizedBox(height: 5),
          _progress('今日总完成进度 · 任务 + 习惯', completion, '🏃',
            '${(completion * 100).round()}%', const Color(0xFFBCE9C3)),
          const SizedBox(height: 13),
          _progress('今日时间 · 24 小时', hourProgress, '🕊️',
            '${now.hour.toString().padLeft(2, '0')}:00', const Color(0xFFA5D6F5)),
          const SizedBox(height: 4),
          const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('00:00', style: TextStyle(color: Colors.white70, fontSize: 10)),
            Text('24:00', style: TextStyle(color: Colors.white70, fontSize: 10)),
          ]),
        ]),
      );
    },
  );

  Widget _progress(String label, double progress, String character,
      String percentage, Color color) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(label,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12))),
        Text(percentage, style: const TextStyle(color: Colors.white, fontSize: 12)),
      ]),
      const SizedBox(height: 4),
      SizedBox(height: 31, child: LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth;
        const markerWidth = 30.0;
        final safeProgress = progress.clamp(0.0, 1.0).toDouble();
        return Stack(children: [
          Positioned(left: 0, right: 0, bottom: 3,
            child: ClipRRect(borderRadius: BorderRadius.circular(20),
              child: LinearProgressIndicator(value: safeProgress,
                minHeight: 9, backgroundColor: Colors.white24,
                valueColor: AlwaysStoppedAnimation<Color>(color)))),
          Positioned(left: (width - markerWidth) * safeProgress, top: 0,
            child: SizedBox(width: markerWidth, child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.diagonal3Values(-1, 1, 1),
              child: Text(character, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 23))))),
        ]);
      })),
    ]);
  }
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
  //满足下面任意一条就放：
  //
  // 1. **渲染 UI 要用到**
  // 比如：是否置顶标签、优先级文字、截止时间、打卡次数、任务颜色、图标。
  //
  // >
  // > 例子：你后面想展示「记录方式：默认 / 固定 / 手动」，就加 `final String recordMode;`
  //
  // 2. **点击交互回调，由外层处理**
  // 卡片里有新按钮（删除、延期、分享），点击逻辑不在 TaskTile 内部写，交给上层 `today_page` 处理
  // 3. **状态锁、标记位**
  // 控制交互可用性：是否加载中、是否已完成、是否只读。。
  const TaskTile({
    //1. 对象在编译的时候就确定，运行时不再变，内存只创建一份，复用实例。
    // 2. 要求：类里所有成员都必须是 `final`，构造参数全部是常量。
    super.key,
    required this.task,
    required this.todayDate,
    required this.busy,
    required this.onComplete,
    required this.onEdit,
  });

  final TodayTask task;       // 单条任务实体
  final String todayDate;     // 今天日期，用来判断逾期是否是今天逾期
  final bool busy;            // 忙标记：接口请求中，防止重复点击
  final VoidCallback onEdit;
  final VoidCallback onComplete; // 点击完成的回调（提交到本地 Repository）

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

    // 距离截止时间小于5小时
    final dueSoon = !task.completedToday &&
        !task.overdue &&
        remaining != null &&
        !remaining.isNegative &&
        remaining < const Duration(hours: 5);

    // 今天到期并且已经逾期
    final overdueToday =
        task.overdue && due != null && _date(due) == todayDate;

    final alert = dueSoon || task.overdue;
    final titleColor = alert ? AppColors.rose : AppColors.ink;
    final progress = task.progress;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,

      // 保留原来的任务完成逻辑
      onTap: task.completedToday ||
          task.remainingCount <= 0 ||
          busy
          ? null
          : onComplete,

      child: SurfaceCard(
        // 收起时缩小内边距，展开时保持原样
        padding: EdgeInsets.all(isExpanded ? 18 : 8),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // =========================
            // 第一部分：始终显示的标题行
            // =========================
            Row(
              crossAxisAlignment: isExpanded
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [

                Container(
                  width: isExpanded ? 40 : 30,
                  height: isExpanded ? 40 : 30,
                  decoration: BoxDecoration(
                    color: task.completedToday
                        ? AppColors.paleGreen
                        : AppColors.paleAmber,
                    borderRadius: BorderRadius.circular(
                      isExpanded ? 13 : 9,
                    ),
                  ),
                  child: Icon(
                    task.completedToday
                        ? Icons.check_rounded
                        : Icons.assignment_outlined,
                    size: isExpanded ? 24 : 18,
                    color: task.completedToday
                        ? AppColors.forest
                        : const Color(0xFFBE8640),
                  ),
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      Text(
                        task.title,
                        maxLines: isExpanded ? null : 1,
                        overflow: isExpanded
                            ? null
                            : TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: isExpanded ? 16 : 14,
                          fontWeight: FontWeight.w700,
                          color: titleColor,
                          decoration: overdueToday
                              ? TextDecoration.lineThrough
                              : null,
                          decorationColor: AppColors.rose,
                        ),
                      ),

                      // 备注只在展开时显示
                      if (isExpanded &&
                          task.note != null &&
                          task.note!.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          task.note!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                if (task.completedToday)
                  const Icon(
                    Icons.verified_rounded,
                    color: AppColors.leaf,
                    size: 19,
                  )
                else if (alert)
                  const Icon(
                    Icons.access_time_filled_rounded,
                    color: AppColors.rose,
                    size: 19,
                  ),

                const SizedBox(width: 4),

                // 展开 / 收起按钮
                IconButton(
                  constraints: isExpanded
                      ? const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  )
                      : const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  padding: isExpanded
                      ? const EdgeInsets.all(8)
                      : EdgeInsets.zero,
                  visualDensity: isExpanded
                      ? VisualDensity.standard
                      : VisualDensity.compact,
                  icon: Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 22,
                  ),
                  tooltip: isExpanded ? '收起任务' : '展开任务',
                  onPressed: () {
                    setState(() {
                      isExpanded = !isExpanded;
                    });
                  },
                ),
              ],
            ),

            // =========================
            // 第二部分：只在展开时显示
            // =========================
            if (isExpanded) ...[

              const SizedBox(height: 14),

              // 重要程度、难度、截止时间
              Wrap(
                spacing: 7,
                runSpacing: 6,
                children: [
                  _tag(
                    Icons.flag_outlined,
                    '重要 ${task.importance ?? 3}',
                    AppColors.paleGreen,
                    AppColors.forest,
                  ),

                  _tag(
                    Icons.local_fire_department_outlined,
                    '难度 ${task.difficulty ?? 3}',
                    AppColors.paleAmber,
                    const Color(0xFFA76C31),
                  ),

                  if (due != null)
                    _tag(
                      Icons.schedule_outlined,
                      _dateTime(due),
                      task.overdue || dueSoon
                          ? AppColors.paleRose
                          : const Color(0xFFF0F1EE),
                      task.overdue || dueSoon
                          ? AppColors.rose
                          : AppColors.muted,
                    ),

                  if (task.overdue)
                    _tag(
                      Icons.warning_amber_rounded,
                      overdueToday ? '今日已逾期' : '已逾期',
                      AppColors.paleRose,
                      AppColors.rose,
                    ),
                ],
              ),

              const SizedBox(height: 17),

              // 累计进度
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '累计进度 ${task.totalActualCount}/${task.targetCount}',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    '今日 +${task.todayActualCount}',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 7),

              // 进度条
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 7,
                  backgroundColor: AppColors.paleGreen,
                  valueColor:
                  const AlwaysStoppedAnimation<Color>(
                    AppColors.leaf,
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // 原来的任务详情和编辑功能
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),

              Material(
                color: AppColors.paleGreen,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: busy ? null : widget.onEdit,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                        const Row(
                          children: [
                            Expanded(
                              child: Text(
                                '任务详情',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Icon(Icons.edit_outlined, size: 17),
                            SizedBox(width: 5),
                            Text(
                              '点击编辑',
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        Text(
                          '任务说明：${task.note ?? '暂无备注'}',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),

                        const SizedBox(height: 8),

                        Text(
                          '累计进度：${task.totalActualCount}/${task.targetCount}',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
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
