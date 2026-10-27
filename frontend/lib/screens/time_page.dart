import 'package:flutter/material.dart';

import '../data/stats_api.dart';
import '../data/today_api.dart';
import '../theme/app_theme.dart';
import 'fishing_session_dialog.dart';

/// 时间管理：负责钓鱼计时与时间记录的新增、编辑和删除。
/// 历史数据的综合回顾仍由 StatsPage 负责。
class TimePage extends StatefulWidget {
  const TimePage({super.key, required this.api, this.refreshToken = 0});

  final TodayApi api;
  final int refreshToken;

  @override
  State<TimePage> createState() => _TimePageState();
}

class _TimePageState extends State<TimePage> {
  late StatsApi _statsApi;
  late DateTime _selectedDate;
  CalendarDayDetail? _dayDetail;
  int _dayRequestSequence = 0;
  bool _loadingDay = true;
  String? _dayError;

  @override
  void initState() {
    super.initState();
    _selectedDate = _businessDate(DateTime.now());
    _statsApi = StatsApi(baseUrl: widget.api.baseUrl, userId: widget.api.userId);
    _loadDay(_selectedDate);
  }

  @override
  void didUpdateWidget(covariant TimePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api) {
      _statsApi.dispose();
      _statsApi = StatsApi(baseUrl: widget.api.baseUrl, userId: widget.api.userId);
      _dayDetail = null;
      _loadDay(_selectedDate);
    } else if (oldWidget.refreshToken != widget.refreshToken) {
      _loadDay(_selectedDate);
    }
  }

  @override
  void dispose() {
    _statsApi.dispose();
    super.dispose();
  }

  Future<void> _loadDay(DateTime date) async {
    final request = ++_dayRequestSequence;
    setState(() {
      _loadingDay = true;
      _dayError = null;
    });
    try {
      final result = await _statsApi.getCalendarDay(date: _dateKey(date));
      if (!mounted || request != _dayRequestSequence) return;
      setState(() => _dayDetail = result);
    } catch (error) {
      if (!mounted || request != _dayRequestSequence) return;
      setState(() => _dayError = '$error');
    } finally {
      if (mounted && request == _dayRequestSequence) {
        setState(() => _loadingDay = false);
      }
    }
  }

  void _changeDate(int delta) {
    final next = _selectedDate.add(Duration(days: delta));
    final today = _businessDate(DateTime.now());
    if (next.isAfter(today)) return;
    setState(() => _selectedDate = next);
    _loadDay(next);
  }

  Future<void> _pickDate() async {
    final today = _businessDate(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: today,
      helpText: '选择要查看或管理的业务日期',
    );
    if (picked == null || !mounted) return;
    final normalized = DateTime(picked.year, picked.month, picked.day);
    setState(() => _selectedDate = normalized);
    await _loadDay(normalized);
  }

  Future<void> _refresh() => _loadDay(_selectedDate);

  bool get _selectedDateIsToday => _sameDate(_selectedDate, _businessDate(DateTime.now()));

  Future<void> _openFishing() async {
    if (!_selectedDateIsToday || !mounted) return;
    await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FishingSessionDialog(api: _statsApi),
    );
    if (!mounted) return;
    await _loadDay(_selectedDate);
  }

  @override
  Widget build(BuildContext context) {
    final detail = _dayDetail;
    final totalMinutes = detail?.timeRecords.fold<int>(
          0, (sum, record) => sum + record.durationMinutes) ?? 0;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F5),
      appBar: AppBar(
        title: const Text('时间管理'),
        backgroundColor: const Color(0xFFF6F8F5),
        actions: [
          IconButton(
            onPressed: _loadingDay ? null : _refresh,
            tooltip: '刷新时间记录',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
          children: [
            _fishingPanel(),
            const SizedBox(height: 12),
            _panel(Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.timelapse_rounded, color: AppColors.forest, size: 20),
                  const SizedBox(width: 7),
                  const Expanded(child: Text('时间记录', style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800))),
                  Text('${detail?.timeRecords.length ?? 0} 条 · ${_formatDuration(totalMinutes)}',
                    style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: '添加时间记录',
                    onPressed: _loadingDay ? null : () => _openTimeRecordEditor(),
                    icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.forest),
                  ),
                ]),
                Row(children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: '前一天',
                    onPressed: () => _changeDate(-1),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Expanded(child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _pickDate,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.calendar_today_rounded, size: 15, color: AppColors.forest),
                        const SizedBox(width: 7),
                        Text('${_dateLabel(_selectedDate)}${_selectedDateIsToday ? ' · 今天' : ''}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_drop_down_rounded, size: 18),
                      ]),
                    ),
                  )),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: '后一天',
                    onPressed: _selectedDateIsToday ? null : () => _changeDate(1),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ]),
                const Divider(height: 12, color: AppColors.border),
                if (_loadingDay && detail == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_dayError != null && detail == null)
                  Text('时间记录加载失败：$_dayError', style: const TextStyle(
                    color: AppColors.rose, fontSize: 12))
                else if (detail == null || detail.timeRecords.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Center(child: Text('当天还没有时间记录，点击 + 添加，或开始钓鱼。',
                      style: TextStyle(color: AppColors.muted, fontSize: 12))),
                  )
                else
                  ...detail.timeRecords.map(_timeRecordRow),
                if (_dayError != null && detail != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('刷新失败，当前显示上次数据：$_dayError',
                      style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                  ),
              ],
            )),
            const SizedBox(height: 8),
            const Text('业务日期每天凌晨 05:00 换日。钓鱼只在应用前台计时；切到后台或离开页面，当前鱼会逃走。',
              style: TextStyle(fontSize: 11, color: AppColors.muted),
              textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _fishingPanel() => _panel(Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: const Color(0xFFE3EFE3),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.set_meal_rounded, color: AppColors.forest, size: 27),
        ),
        const SizedBox(width: 11),
        const Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('静静等待鱼儿上钩', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            SizedBox(height: 4),
            Text('每连续钓鱼 30 分钟获得一条鱼。保持手机稳定，不要切到后台。',
              style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.4)),
          ],
        )),
      ]),
      const SizedBox(height: 14),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _loadingDay || !_selectedDateIsToday ? null : _openFishing,
          icon: const Icon(Icons.set_meal_rounded),
          label: Text(_selectedDateIsToday ? '开始钓鱼' : '仅今天可以开始钓鱼'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.forest,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
      const SizedBox(height: 6),
      const Text('陀螺仪检测暂未启用；当前版本不会持续监听手机传感器。',
        style: TextStyle(fontSize: 10, color: AppColors.muted)),
    ],
  ));

  Widget _timeRecordRow(CalendarTimeRecordItem record) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: EdgeInsets.only(top: 2),
        child: Icon(Icons.schedule_rounded, size: 18, color: AppColors.forest),
      ),
      const SizedBox(width: 8),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(record.title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text('${record.category} · ${_formatClock(record.startTime)}–${_formatClock(record.endTime)} · ${_formatDuration(record.durationMinutes)}',
          style: const TextStyle(fontSize: 10, color: AppColors.muted)),
        if (record.note != null && record.note!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(record.note!, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
          ),
      ])),
      IconButton(
        visualDensity: VisualDensity.compact,
        tooltip: '编辑时间记录',
        onPressed: () => _openTimeRecordEditor(record: record),
        icon: const Icon(Icons.edit_outlined, size: 17),
      ),
      IconButton(
        visualDensity: VisualDensity.compact,
        tooltip: '删除时间记录',
        onPressed: () => _deleteTimeRecord(record),
        icon: const Icon(Icons.delete_outline_rounded, size: 17, color: AppColors.rose),
      ),
    ]),
  );


  Future<void> _openTimeRecordEditor({CalendarTimeRecordItem? record}) async {
    final titleController = TextEditingController(text: record?.title ?? '');
    final noteController = TextEditingController(text: record?.note ?? '');
    const presetCategories = ['学习', '工作', '娱乐', '运动', '休息', '其他'];
    final categories = <String>[
      ...presetCategories,
      if (record != null && !presetCategories.contains(record.category)) record.category,
    ];
    var category = categories.contains(record?.category) ? record!.category : '学习';
    final baseDate = _selectedDate;
    var startTime = record?.startTime ?? DateTime(baseDate.year, baseDate.month, baseDate.day, 9);
    var endTime = record?.endTime ?? DateTime(baseDate.year, baseDate.month, baseDate.day, 10);
    var saving = false;
    String? formError;

    Future<DateTime?> pickDateTime(DateTime initial) async {
      final date = await showDatePicker(
        context: context,
        initialDate: DateTime(initial.year, initial.month, initial.day),
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
      if (date == null || !mounted) return null;
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(initial),
      );
      if (time == null) return null;
      return DateTime(date.year, date.month, date.day, time.hour, time.minute);
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(record == null ? '添加时间记录' : '编辑时间记录'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: titleController,
                autofocus: true,
                maxLength: 100,
                decoration: const InputDecoration(labelText: '事项名称', hintText: '例如：学习 Java'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(labelText: '分类'),
                items: categories.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
                onChanged: (value) { if (value != null) setDialogState(() => category = value); },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.play_arrow_rounded),
                title: const Text('开始时间', style: TextStyle(fontSize: 12)),
                subtitle: Text(_formatDateTime(startTime)),
                onTap: () async {
                  final picked = await pickDateTime(startTime);
                  if (picked != null) setDialogState(() { startTime = picked; formError = null; });
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.stop_rounded),
                title: const Text('结束时间', style: TextStyle(fontSize: 12)),
                subtitle: Text(_formatDateTime(endTime)),
                onTap: () async {
                  final picked = await pickDateTime(endTime);
                  if (picked != null) setDialogState(() { endTime = picked; formError = null; });
                },
              ),
              TextField(
                controller: noteController,
                maxLength: 500,
                maxLines: 2,
                decoration: const InputDecoration(labelText: '备注（可选）'),
              ),
              if (formError != null) ...[
                const SizedBox(height: 6),
                Align(alignment: Alignment.centerLeft,
                  child: Text(formError!, style: const TextStyle(color: AppColors.rose, fontSize: 12))),
              ],
              const SizedBox(height: 4),
              const Align(alignment: Alignment.centerLeft,
                child: Text('一条记录不能跨越凌晨 05:00 的业务日边界。',
                    style: TextStyle(color: AppColors.muted, fontSize: 11))),
            ])),
          ),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消')),
            FilledButton(
              onPressed: saving ? null : () async {
                if (titleController.text.trim().isEmpty) {
                  setDialogState(() => formError = '请填写事项名称');
                  return;
                }
                if (!endTime.isAfter(startTime)) {
                  setDialogState(() => formError = '结束时间必须晚于开始时间');
                  return;
                }
                if (endTime.isAfter(DateTime.now())) {
                  setDialogState(() => formError = '时间记录不能包含未来时间');
                  return;
                }
                final startBusinessDate = _businessDate(startTime);
                final endBusinessDate = _businessDate(endTime.subtract(const Duration(microseconds: 1)));
                if (!_sameDate(startBusinessDate, baseDate) || !_sameDate(endBusinessDate, baseDate)) {
                  setDialogState(() => formError = '开始和结束时间都必须属于所选业务日期（05:00 换日）');
                  return;
                }
                if (endTime.difference(startTime).inMinutes < 1) {
                  setDialogState(() => formError = '时间记录至少为 1 分钟');
                  return;
                }
                setDialogState(() { saving = true; formError = null; });
                try {
                  if (record == null) {
                    await _statsApi.createTimeRecord(
                      title: titleController.text.trim(), category: category,
                      startTime: startTime, endTime: endTime, note: noteController.text,
                    );
                  } else {
                    await _statsApi.updateTimeRecord(
                      recordId: record.timeRecordId, title: titleController.text.trim(),
                      category: category, startTime: startTime, endTime: endTime,
                      taskId: record.taskId, note: noteController.text,
                    );
                  }
                  if (dialogContext.mounted) Navigator.of(dialogContext).pop(true);
                } catch (error) {
                  setDialogState(() { saving = false; formError = '$error'; });
                }
              },
              child: saving ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)) : const Text('保存'),
            ),
          ],
        ),
      ),
    );
    titleController.dispose();
    noteController.dispose();
    if (saved == true && mounted) {
      await _loadDay(_selectedDate);
    }
  }

  Future<void> _deleteTimeRecord(CalendarTimeRecordItem record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除时间记录？'),
        content: Text('确定删除“${record.title}”这条记录吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _statsApi.deleteTimeRecord(recordId: record.timeRecordId);
      await _loadDay(_selectedDate);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败：$error')));
    }
  }



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

String _formatDateTime(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} ${_formatClock(value)}';

String _formatDuration(int minutes) {
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) return '$rest 分钟';
  if (rest == 0) return '$hours 小时';
  return '$hours 小时 $rest 分钟';
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
