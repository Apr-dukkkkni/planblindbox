import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/stats_api.dart';
import '../data/today_api.dart';
import '../theme/app_theme.dart';

/// 第四个底部一级导航页面；加载时复用 TodayApi 的 baseUrl/userId。
class StatsPage extends StatefulWidget {
  const StatsPage({super.key, required this.api, this.refreshToken = 0});

  final TodayApi api;
  final int refreshToken;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  late StatsApi _statsApi;
  StatsData? _data;
  int _days = 7;
  int _requestSequence = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _statsApi = StatsApi(baseUrl: widget.api.baseUrl, userId: widget.api.userId);
    _load();
  }

  @override
  void didUpdateWidget(covariant StatsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api) {
      _statsApi.dispose();
      _statsApi = StatsApi(baseUrl: widget.api.baseUrl, userId: widget.api.userId);
      _data = null;
      _load();
    } else if (oldWidget.refreshToken != widget.refreshToken) {
      _load();
    }
  }

  @override
  void dispose() {
    _statsApi.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final current = ++_requestSequence;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _statsApi.getStats(days: _days);
      if (!mounted || current != _requestSequence) return;
      setState(() => _data = result);
    } catch (error) {
      if (!mounted || current != _requestSequence) return;
      setState(() => _error = '$error');
    } finally {
      if (mounted && current == _requestSequence) {
        setState(() => _loading = false);
      }
    }
  }

  void _selectDays(int days) {
    if (_days == days) return;
    setState(() => _days = days);
    _load();
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
            onPressed: _loading ? null : _load,
            tooltip: '刷新统计',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('我的成长记录',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 7, label: Text('7天')),
                    ButtonSegment(value: 30, label: Text('30天')),
                  ],
                  selected: {_days},
                  onSelectionChanged: (v) => _selectDays(v.first),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loading && data != null)
              const LinearProgressIndicator(minHeight: 2),
            if (_loading && data == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 110),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (data == null)
              _panel(Text(_error ?? '暂无统计数据'))
            else ...[
              if (_error != null) _panel(Text('刷新失败，显示上次数据：$_error')),
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text('${data.startDate} 至 ${data.endDate} · 每天凌晨 5 点换日',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              ),
              _summary(data.summary),
              const SizedBox(height: 18),
              _panel(Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('任务完成与习惯打卡', Icons.bar_chart_rounded),
                  const SizedBox(height: 8),
                  const Row(children: [
                    _LegendDot(color: AppColors.forest, text: '完成任务'),
                    SizedBox(width: 14),
                    _LegendDot(color: Color(0xFFC9A05B), text: '习惯打卡'),
                  ]),
                  const SizedBox(height: 12),
                  _DailyBars(days: data.daily),
                ],
              )),
              const SizedBox(height: 16),
              _panel(Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('金币余额趋势', Icons.monetization_on_outlined),
                  const SizedBox(height: 5),
                  Text('当前 ${data.summary.coinBalance} 金币 · 期间获得 ${data.summary.coinEarned}，消费 ${data.summary.coinSpent}',
                      style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  const SizedBox(height: 10),
                  _BalanceLine(days: data.daily, getValue: (d) => d.coinBalance,
                      color: AppColors.forest),
                ],
              )),
              const SizedBox(height: 16),
              _panel(Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('经验累计趋势', Icons.bolt_outlined),
                  const SizedBox(height: 5),
                  Text('当前 ${data.summary.expBalance} EXP · 期间新增 ${data.summary.expEarned}',
                      style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  const SizedBox(height: 10),
                  _BalanceLine(days: data.daily, getValue: (d) => d.expBalance,
                      color: const Color(0xFF8B79BC)),
                ],
              )),
              const SizedBox(height: 16),
              _panel(Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('最近记录', Icons.history_rounded),
                  const SizedBox(height: 8),
                  ...data.daily.reversed.take(7).map((d) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(children: [
                      SizedBox(width: 58, child: Text(_shortDate(d.date),
                        style: const TextStyle(color: AppColors.muted, fontSize: 12))),
                      Expanded(child: Text('任务 ${d.completedTasks} · 习惯 ${d.habitCheckIns}',
                        style: const TextStyle(fontSize: 12))),
                      Text('+${d.coinEarned} / -${d.coinSpent} 金币',
                        style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                    ]),
                  )),
                ],
              )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _summary(StatsSummary s) => Column(children: [
    Row(children: [
      Expanded(child: _kpi('完成任务', '${s.completedTasks}', Icons.check_circle_outline, AppColors.forest)),
      const SizedBox(width: 10),
      Expanded(child: _kpi('习惯打卡', '${s.habitCheckIns}', Icons.spa_outlined, const Color(0xFFC9A05B))),
    ]),
    const SizedBox(height: 10),
    Row(children: [
      Expanded(child: _kpi('金币余额', '${s.coinBalance}', Icons.monetization_on_outlined, AppColors.forest)),
      const SizedBox(width: 10),
      Expanded(child: _kpi('累计经验', '${s.expBalance}', Icons.bolt_outlined, const Color(0xFF8B79BC))),
    ]),
  ]);

  Widget _kpi(String label, String value, IconData icon, Color color) => _panel(
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(icon, size: 17, color: color), const SizedBox(width: 5),
        Flexible(child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)))]),
      const SizedBox(height: 8),
      FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
        child: Text(value, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800))),
    ]),
  );

  Widget _panel(Widget child) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border),
    ),
    child: child,
  );

  Widget _sectionTitle(String label, IconData icon) => Row(children: [
    Icon(icon, size: 20, color: AppColors.forest),
    const SizedBox(width: 7),
    Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
  ]);
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.text});
  final Color color;
  final String text;
  @override
  Widget build(BuildContext context) => Row(children: [
    CircleAvatar(radius: 4, backgroundColor: color),
    const SizedBox(width: 5),
    Text(text, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
  ]);
}

class _DailyBars extends StatelessWidget {
  const _DailyBars({required this.days});
  final List<StatsDay> days;

  @override
  Widget build(BuildContext context) {
    int maxCount = 1;
    for (final day in days) {
      maxCount = math.max(maxCount, math.max(day.completedTasks, day.habitCheckIns));
    }
    return SizedBox(
      height: 155,
      child: LayoutBuilder(builder: (context, constraints) {
        final perDay = days.length == 7 ? 44.0 : 36.0;
        final fullWidth = math.max(constraints.maxWidth, perDay * days.length);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: fullWidth,
            child: Row(
              children: days.map((day) => Expanded(
                child: Column(children: [
                  Expanded(child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _bar(day.completedTasks, maxCount, AppColors.forest),
                      const SizedBox(width: 3),
                      _bar(day.habitCheckIns, maxCount, const Color(0xFFC9A05B)),
                    ],
                  )),
                  const SizedBox(height: 8),
                  Text(_shortDate(day.date),
                    style: const TextStyle(fontSize: 9, color: AppColors.muted)),
                ]),
              )).toList(),
            ),
          ),
        );
      }),
    );
  }

  Widget _bar(int value, int maximum, Color color) => Container(
    width: 11,
    height: math.max(2.0, 112.0 * value / maximum),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
  );
}

class _BalanceLine extends StatelessWidget {
  const _BalanceLine({required this.days, required this.getValue, required this.color});

  final List<StatsDay> days;
  final int Function(StatsDay) getValue;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const Text('暂无数据');
    final values = days.map((d) => getValue(d).toDouble()).toList();
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
      if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
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
