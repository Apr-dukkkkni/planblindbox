import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/stats_api.dart';
import '../data/today_api.dart';
import '../theme/app_theme.dart';

/// 统计页：月历优先，点击日期查看当天任务和习惯；资产趋势放在指标卡片的弹窗中。
class StatsPage extends StatefulWidget {
  const StatsPage({super.key, required this.api, this.refreshToken = 0});

  final TodayApi api;
  final int refreshToken;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  late StatsApi _statsApi;
  late DateTime _selectedDate;
  late DateTime _visibleMonth;

  StatsData? _data;
  CalendarMonthData? _calendar;
  CalendarDayDetail? _dayDetail;

  int _statsRequestSequence = 0;
  int _monthRequestSequence = 0;
  int _dayRequestSequence = 0;
  bool _loadingStats = true;
  bool _loadingCalendar = true;
  bool _loadingDay = true;
  String? _statsError;
  String? _calendarError;
  String? _dayError;

  @override
  void initState() {
    super.initState();
    final today = _businessDate(DateTime.now());
    _selectedDate = today;
    _visibleMonth = DateTime(today.year, today.month);
    _statsApi = StatsApi(baseUrl: widget.api.baseUrl, userId: widget.api.userId);
    _refreshAll();
  }

  @override
  void didUpdateWidget(covariant StatsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api) {
      _statsApi.dispose();
      _statsApi = StatsApi(baseUrl: widget.api.baseUrl, userId: widget.api.userId);
      _data = null;
      _calendar = null;
      _dayDetail = null;
      _refreshAll();
    } else if (oldWidget.refreshToken != widget.refreshToken) {
      _refreshAll();
    }
  }

  @override
  void dispose() {
    _statsApi.dispose();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    await Future.wait<void>([
      _loadStats(),
      _loadCalendarMonth(),
      _loadDay(_selectedDate),
    ]);
  }

  Future<void> _loadStats() async {
    final current = ++_statsRequestSequence;
    setState(() {
      _loadingStats = true;
      _statsError = null;
    });
    try {
      // 资产弹窗使用最近 30 天数据；页面不再显示独立趋势图。
      final result = await _statsApi.getStats(days: 30);
      if (!mounted || current != _statsRequestSequence) return;
      setState(() => _data = result);
    } catch (error) {
      if (!mounted || current != _statsRequestSequence) return;
      setState(() => _statsError = '$error');
    } finally {
      if (mounted && current == _statsRequestSequence) {
        setState(() => _loadingStats = false);
      }
    }
  }

  Future<void> _loadCalendarMonth() async {
    final current = ++_monthRequestSequence;
    final month = _visibleMonth;
    setState(() {
      _loadingCalendar = true;
      _calendarError = null;
    });
    try {
      final result = await _statsApi.getCalendarMonth(month: month);
      if (!mounted || current != _monthRequestSequence) return;
      setState(() => _calendar = result);
    } catch (error) {
      if (!mounted || current != _monthRequestSequence) return;
      setState(() => _calendarError = '$error');
    } finally {
      if (mounted && current == _monthRequestSequence) {
        setState(() => _loadingCalendar = false);
      }
    }
  }

  Future<void> _loadDay(DateTime date) async {
    final current = ++_dayRequestSequence;
    final dateText = _dateKey(date);
    setState(() {
      _loadingDay = true;
      _dayError = null;
    });
    try {
      final result = await _statsApi.getCalendarDay(date: dateText);
      if (!mounted || current != _dayRequestSequence) return;
      setState(() => _dayDetail = result);
    } catch (error) {
      if (!mounted || current != _dayRequestSequence) return;
      setState(() => _dayError = '$error');
    } finally {
      if (mounted && current == _dayRequestSequence) {
        setState(() => _loadingDay = false);
      }
    }
  }

  void _selectDate(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    final monthChanged = normalized.year != _visibleMonth.year ||
        normalized.month != _visibleMonth.month;
    setState(() {
      _selectedDate = normalized;
      if (monthChanged) _visibleMonth = DateTime(normalized.year, normalized.month);
    });
    if (monthChanged) _loadCalendarMonth();
    _loadDay(normalized);
  }

  void _changeMonth(int delta) {
    final nextMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
    final today = _businessDate(DateTime.now());
    final nextSelected = nextMonth.year == today.year && nextMonth.month == today.month
        ? today
        : DateTime(nextMonth.year, nextMonth.month, 1);
    setState(() {
      _visibleMonth = nextMonth;
      _selectedDate = nextSelected;
    });
    _loadCalendarMonth();
    _loadDay(nextSelected);
  }

  Future<void> _openTrend(StatsData data, {required bool coins}) async {
    final summary = data.summary;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(coins ? '金币余额趋势' : '累计经验趋势'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(coins
                  ? '当前 ${summary.coinBalance} 金币 · 近30天获得 ${summary.coinEarned}，消费 ${summary.coinSpent}'
                  : '当前 ${summary.expBalance} EXP · 近30天新增 ${summary.expEarned}'),
              const SizedBox(height: 14),
              _BalanceLine(
                days: data.daily,
                getValue: (day) => coins ? day.coinBalance : day.expBalance,
                color: coins ? AppColors.forest : const Color(0xFF8B79BC),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F5),
      appBar: AppBar(
        title: const Text('成长统计'),
        backgroundColor: const Color(0xFFF6F8F5),
        actions: [
          IconButton(
            onPressed: _loadingStats || _loadingCalendar || _loadingDay
                ? null : _refreshAll,
            tooltip: '刷新统计',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
          children: [
            _calendarPanel(),
            if (_calendarError != null) ...[
              const SizedBox(height: 8),
              _panel(Text('日历加载失败：$_calendarError')),
            ],
            const SizedBox(height: 10),
            _dayDetailPanel(),
            const SizedBox(height: 10),
            if (_loadingStats && data == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (data == null)
              _panel(Text(_statsError ?? '暂无统计数据'))
            else ...[
              _summary(data),
              const SizedBox(height: 7),
              Text(
                '任务与习惯为近30天累计；金币和经验显示当前余额。',
                style: const TextStyle(fontSize: 11, color: AppColors.muted),
                textAlign: TextAlign.center,
              ),
              if (_statsError != null) ...[
                const SizedBox(height: 6),
                Text('统计刷新失败，显示上次数据：$_statsError',
                    style: const TextStyle(fontSize: 11, color: AppColors.muted)),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _calendarPanel() {
    final monthStart = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final daysInMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
    final firstOffset = monthStart.weekday - 1;
    final cellCount = ((firstOffset + daysInMonth + 6) ~/ 7) * 7;
    final summaries = _calendar?.byDate ?? const <String, CalendarDaySummary>{};
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];

    return _panel(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.calendar_month_rounded, color: AppColors.forest, size: 21),
          const SizedBox(width: 7),
          const Expanded(
            child: Text('成长日历', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '上个月',
            onPressed: () => _changeMonth(-1),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Text('${_visibleMonth.year}年${_visibleMonth.month}月',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '下个月',
            onPressed: () => _changeMonth(1),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ]),
        if (_loadingCalendar) const LinearProgressIndicator(minHeight: 2),
        const SizedBox(height: 8),
        Row(children: weekdays.map((day) => Expanded(
          child: Center(
            child: Text(day, style: const TextStyle(
              color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        )).toList()),
        const SizedBox(height: 6),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cellCount,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
            childAspectRatio: 1.18,
          ),
          itemBuilder: (context, index) {
            final date = monthStart.add(Duration(days: index - firstOffset));
            final inMonth = date.month == _visibleMonth.month;
            final selected = _sameDate(date, _selectedDate);
            final summary = summaries[_dateKey(date)];
            final activity = summary?.activityCount ?? 0;
            final background = selected ? AppColors.forest : _activityColor(activity, inMonth);
            final foreground = selected
                ? Colors.white
                : (inMonth ? const Color(0xFF28342C) : const Color(0xFFB8C0B9));
            return Material(
              color: background,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _selectDate(date),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected ? AppColors.forest : const Color(0xFFE8EDE7),
                      width: selected ? 1.5 : 0.7,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('${date.day}', style: TextStyle(
                        color: foreground, fontSize: 12, fontWeight: selected
                            ? FontWeight.w800 : FontWeight.w500)),
                      const SizedBox(height: 2),
                      if (activity > 0)
                        Text('$activity', style: TextStyle(
                          color: selected ? Colors.white : (activity >= 4 ? Colors.white : AppColors.forest),
                          fontSize: 8, height: 1, fontWeight: FontWeight.w700,
                        ))
                      else
                        const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 9),
        Row(children: [
          const Text('少', style: TextStyle(fontSize: 10, color: AppColors.muted)),
          const SizedBox(width: 5),
          ...[
            const Color(0xFFF0F4EF),
            const Color(0xFFDCEBDD),
            const Color(0xFFB6D5B9),
            const Color(0xFF78AE80),
            AppColors.forest,
          ].map((color) => Container(
            margin: const EdgeInsets.only(right: 4),
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
          )),
          const Text('多', style: TextStyle(fontSize: 10, color: AppColors.muted)),
          const Spacer(),
          Text('05:00 换日', style: const TextStyle(fontSize: 10, color: AppColors.muted)),
        ]),
      ],
    ));
  }

  Widget _dayDetailPanel() {
    final detail = _dayDetail;
    return _panel(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.event_note_rounded, color: AppColors.forest, size: 19),
          const SizedBox(width: 7),
          Expanded(child: Text('${_dateLabel(_selectedDate)} · 历史记录',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
          if (_loadingDay) const SizedBox(
            width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
        if (_dayError != null) ...[
          const SizedBox(height: 8),
          Text('记录加载失败：$_dayError',
              style: const TextStyle(color: AppColors.rose, fontSize: 12)),
        ] else if (detail == null && _loadingDay) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(minHeight: 2),
        ] else if (detail == null) ...[
          const SizedBox(height: 8),
          const Text('暂无当日记录', style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ] else ...[
          const SizedBox(height: 10),
          _detailHeading('任务', detail.tasks.length),
          if (detail.tasks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 7),
              child: Text('当天没有任务安排', style: TextStyle(color: AppColors.muted, fontSize: 12)),
            )
          else
            ...detail.tasks.map(_taskRow),
          const Divider(height: 18, color: AppColors.border),
          _detailHeading('习惯', detail.habits.length),
          if (detail.habits.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 7),
              child: Text('当天没有需要打卡的习惯', style: TextStyle(color: AppColors.muted, fontSize: 12)),
            )
          else
            ...detail.habits.map(_habitRow),
          const Divider(height: 18, color: AppColors.border),
          _detailHeading('时间记录', detail.timeRecords.length),
          if (detail.timeRecords.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 7),
              child: Text('当天暂无时间记录',
                  style: TextStyle(color: AppColors.muted, fontSize: 12)),
            )
          else
            ...detail.timeRecords.map(_timeRecordRow),
        ],
      ],
    ));
  }

  Widget _timeRecordRow(CalendarTimeRecordItem record) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      const Icon(Icons.timelapse_rounded, size: 18, color: AppColors.forest),
      const SizedBox(width: 8),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(record.title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        Text('${record.category} · ${_formatClock(record.startTime)}–${_formatClock(record.endTime)} · ${_formatDuration(record.durationMinutes)}',
            style: const TextStyle(fontSize: 10, color: AppColors.muted)),
        if (record.note != null && record.note!.isNotEmpty)
          Text(record.note!, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
      ])),
    ]),
  );

  Widget _detailHeading(String label, int count) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(children: [
      Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      const SizedBox(width: 5),
      Text('$count', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
    ]),
  );

  Widget _taskRow(CalendarTaskItem task) {
    final completed = task.status == 'COMPLETED';
    final inProgress = task.status == 'IN_PROGRESS';
    final overdue = task.overdue && !completed;
    final label = completed
        ? '已完成'
        : (overdue ? '未完成' : (inProgress ? '进行中' : '未完成'));

    final Color statusColor = completed
        ? AppColors.forest
        : (overdue ? AppColors.rose : AppColors.muted);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(
          completed ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
          size: 18,
          color: statusColor,
        ),
        const SizedBox(width: 8),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 已完成状态由绿色对勾和状态文字表达，不再给标题加删除线。
            Text(task.title, style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF28342C),
            )),
            Text(
              '当日进度 ${task.actualCount}/${task.targetCount}',
              style: const TextStyle(fontSize: 10, color: AppColors.muted),
            ),
          ],
        )),
        Text(label, style: TextStyle(
          fontSize: 10,
          color: statusColor,
          fontWeight: FontWeight.w600,
        )),
      ]),
    );
  }

  Widget _habitRow(CalendarHabitItem habit) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Icon(habit.checkedIn ? Icons.check_circle_rounded : Icons.spa_outlined,
          size: 18, color: habit.checkedIn ? const Color(0xFFC9A05B) : AppColors.muted),
      const SizedBox(width: 8),
      Expanded(child: Text(habit.name, style: const TextStyle(fontSize: 12))),
      Text(habit.checkedIn ? '已打卡' : '未打卡', style: TextStyle(
        fontSize: 10,
        color: habit.checkedIn ? const Color(0xFF9A742F) : AppColors.muted,
        fontWeight: FontWeight.w600,
      )),
    ]),
  );

  Widget _summary(StatsData data) => Column(children: [
    Row(children: [
      Expanded(child: _kpi('完成任务', '${data.summary.completedTasks}',
          Icons.check_circle_outline_rounded, AppColors.forest)),
      const SizedBox(width: 8),
      Expanded(child: _kpi('习惯打卡', '${data.summary.habitCheckIns}',
          Icons.spa_outlined, const Color(0xFFC9A05B))),
    ]),
    const SizedBox(height: 8),
    Row(children: [
      Expanded(child: _kpi('金币余额', '${data.summary.coinBalance}',
          Icons.monetization_on_outlined, AppColors.forest,
          onTap: () => _openTrend(data, coins: true))),
      const SizedBox(width: 8),
      Expanded(child: _kpi('累计经验', '${data.summary.expBalance}',
          Icons.bolt_outlined, const Color(0xFF8B79BC),
          onTap: () => _openTrend(data, coins: false))),
    ]),
  ]);

  Widget _kpi(String label, String value, IconData icon, Color color,
      {VoidCallback? onTap}) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
            const SizedBox(height: 2),
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          ])),
          if (onTap != null)
            const Icon(Icons.open_in_new_rounded, size: 13, color: AppColors.muted),
        ]),
      ),
    ),
  );

  Widget _panel(Widget child) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.border),
    ),
    child: child,
  );
}

String _formatClock(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

String _formatDuration(int minutes) {
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) return '$rest 分钟';
  if (rest == 0) return '$hours 小时';
  return '$hours 小时 $rest 分钟';
}

Color _activityColor(int count, bool inMonth) {
  if (!inMonth) return const Color(0xFFFAFBF9);
  if (count <= 0) return const Color(0xFFF4F6F2);
  if (count == 1) return const Color(0xFFE2EEE2);
  if (count == 2) return const Color(0xFFC6E0C8);
  if (count <= 4) return const Color(0xFF8FBE95);
  return AppColors.forest;
}

DateTime _businessDate(DateTime dateTime) {
  final date = DateTime(dateTime.year, dateTime.month, dateTime.day);
  return dateTime.hour < 5 ? date.subtract(const Duration(days: 1)) : date;
}

bool _sameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _dateLabel(DateTime date) => '${date.year}年${date.month}月${date.day}日';

class _BalanceLine extends StatelessWidget {
  const _BalanceLine({required this.days, required this.getValue, required this.color});

  final List<StatsDay> days;
  final int Function(StatsDay) getValue;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const Text('暂无数据');
    final values = days.map((day) => getValue(day).toDouble()).toList();
    return Column(children: [
      SizedBox(height: 110, width: double.infinity,
          child: CustomPaint(painter: _TrendPainter(values: values, color: color))),
      const SizedBox(height: 4),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(_shortDate(days.first.date), style: const TextStyle(fontSize: 10, color: AppColors.muted)),
        Text(_shortDate(days.last.date), style: const TextStyle(fontSize: 10, color: AppColors.muted)),
      ]),
    ]);
  }
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final span = maxV == minV ? 1.0 : maxV - minV;
    final h = size.height - 16;
    final w = size.width - 8;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final grid = Paint()
      ..color = const Color(0xFFE6EBE5)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(4, h + 2), Offset(size.width - 4, h + 2), grid);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = 4 + w * (values.length == 1 ? 0 : i / (values.length - 1));
      final y = 6 + (h - 10) * (1 - (values[i] - minV) / span);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
    final lastX = 4 + w;
    final lastY = 6 + (h - 10) * (1 - (values.last - minV) / span);
    canvas.drawCircle(Offset(lastX, lastY), 3.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}

String _shortDate(String date) {
  if (date.length < 10) return date;
  return '${date.substring(5, 7)}/${date.substring(8, 10)}';
}
