import 'package:flutter/material.dart';

import '../data/today_api.dart';
import '../theme/app_theme.dart';

class DailySignInCalendarPage extends StatefulWidget {
  const DailySignInCalendarPage({
    super.key,
    required this.api,
    this.initialDate,
  });

  final TodayApi api;
  final String? initialDate;

  @override
  State<DailySignInCalendarPage> createState() =>
      _DailySignInCalendarPageState();
}

class _DailySignInCalendarPageState
    extends State<DailySignInCalendarPage> {
  late DateTime _month;
  late DateTime _selected;

  Map<DateTime, Map<String, dynamic>> _records = {};

  bool _loading = false;
  String? _error;
  int _requestSequence = 0;

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  bool _sameDay(DateTime? a, DateTime? b) =>
      a != null &&
      b != null &&
      a.year == b.year &&
      a.month == b.month &&
      a.day == b.day;

  @override
  void initState() {
    super.initState();

    final initial =
        DateTime.tryParse(widget.initialDate ?? '') ??
            DateTime.now();

    _month = DateTime(initial.year, initial.month, 1);
    _selected = _dateOnly(initial);

    _load();
  }

  Future<void> _load() async {
    final sequence = ++_requestSequence;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final items = await widget.api.getDailySignInRecords(
        year: _month.year,
        month: _month.month,
      );

      final records = <DateTime, Map<String, dynamic>>{};

      for (final item in items) {
        final value = DateTime.tryParse(
          item['businessDate']?.toString() ?? '',
        );

        if (value != null) {
          records[_dateOnly(value)] = item;
        }
      }

      if (!mounted || sequence != _requestSequence) return;

      setState(() {
        _records = records;
      });
    } catch (error) {
      if (!mounted || sequence != _requestSequence) return;

      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted && sequence == _requestSequence) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _changeMonth(int offset) {
    final next = DateTime(
      _month.year,
      _month.month + offset,
      1,
    );

    setState(() {
      _month = next;
      _selected = next;
      _records = {};
    });

    _load();
  }

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(_month.year, _month.month, 1);
    final daysInMonth =
        DateTime(_month.year, _month.month + 1, 0).day;

    // 周一为第一列
    final offset = firstDay.weekday - 1;
    final cellCount = ((offset + daysInMonth + 6) ~/ 7) * 7;

    final selectedRecord = _records[_dateOnly(_selected)];

    final totalWater = _records.values.fold<int>(
      0,
      (sum, item) =>
          sum + ((item['totalWater'] as num?)?.toInt() ?? 0),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('每日签到'),
        actions: [
          IconButton(
            tooltip: '刷新签到记录',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.forest,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '签到足迹',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      Expanded(
                        child: _summary(
                          '本月签到',
                          '${_records.length} 天',
                        ),
                      ),
                      Expanded(
                        child: _summary(
                          '累计奖励',
                          '$totalWater 水滴',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            Row(
              children: [
                IconButton(
                  onPressed: () => _changeMonth(-1),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      '${_month.year}年${_month.month}月',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _changeMonth(1),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),

            if (_loading)
              const LinearProgressIndicator(
                minHeight: 2,
                color: AppColors.forest,
              ),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  '签到记录加载失败：$_error',
                  style: const TextStyle(color: AppColors.rose),
                ),
              ),

            const SizedBox(height: 12),

            Row(
              children: ['一', '二', '三', '四', '五', '六', '日']
                  .map(
                    (day) => Expanded(
                      child: Center(
                        child: Text(
                          day,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),

            const SizedBox(height: 8),

            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisExtent: 58,
              ),
              itemCount: cellCount,
              itemBuilder: (context, index) {
                final dayNumber = index - offset + 1;

                if (dayNumber < 1 || dayNumber > daysInMonth) {
                  return const SizedBox.shrink();
                }

                final date = DateTime(
                  _month.year,
                  _month.month,
                  dayNumber,
                );

                final record = _records[_dateOnly(date)];
                final selected = _sameDay(date, _selected);

                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    setState(() {
                      _selected = date;
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.paleGreen
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? AppColors.forest
                            : Colors.transparent,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$dayNumber',
                          style: TextStyle(
                            fontWeight: record != null
                                ? FontWeight.w800
                                : FontWeight.w500,
                            color: record != null
                                ? AppColors.forest
                                : AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Icon(
                          record != null
                              ? Icons.water_drop_rounded
                              : Icons.circle,
                          size: record != null ? 11 : 3,
                          color: record != null
                              ? AppColors.forest
                              : AppColors.border,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 20),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_selected.year}年${_selected.month}月${_selected.day}日',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 10),

                  if (selectedRecord == null)
                    const Text(
                      '当天暂无签到记录',
                      style: TextStyle(color: AppColors.muted),
                    )
                  else ...[
                    Text(
                      '连续签到第 ${selectedRecord['streakDay'] ?? '-'} 天',
                      style: const TextStyle(
                        color: AppColors.forest,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '基础奖励：${selectedRecord['baseWater'] ?? 0} 水滴',
                    ),
                    Text(
                      '阶梯奖励：${selectedRecord['bonusWater'] ?? 0} 水滴',
                    ),
                    const Divider(height: 22),
                    Text(
                      '合计获得：${selectedRecord['totalWater'] ?? 0} 水滴',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.forest,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summary(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 19,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}