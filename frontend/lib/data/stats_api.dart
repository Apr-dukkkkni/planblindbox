import 'api_exception.dart';
import 'local/local_database.dart';
import 'local/local_plan_repository.dart';

/// 统计、日历和时间记录全部从本地 SQLite 聚合。
class StatsApi {
  StatsApi({required this.baseUrl, required this.userId, LocalPlanRepository? repository})
      : _repository = repository ?? LocalPlanRepository(
          userId: userId,
          localDatabase: LocalDatabase.instance,
        );

  final String baseUrl;
  final int userId;
  final LocalPlanRepository _repository;

  Future<StatsData> getStats({int days = 7}) async =>
      StatsData.fromJson(await _repository.getStats(days: days));

  Future<CalendarMonthData> getCalendarMonth({required DateTime month}) async =>
      CalendarMonthData.fromJson(await _repository.getCalendarMonth(month));

  Future<CalendarDayDetail> getCalendarDay({required String date}) async =>
      CalendarDayDetail.fromJson(await _repository.getCalendarDay(date));

  Future<void> createTimeRecord({
    required String title,
    required String category,
    required DateTime startTime,
    required DateTime endTime,
    String? note,
  }) =>
      _repository.createTimeRecord(
        title: title,
        category: category,
        startTime: startTime,
        endTime: endTime,
        note: note,
      );

  Future<void> updateTimeRecord({
    required int recordId,
    required String title,
    required String category,
    required DateTime startTime,
    required DateTime endTime,
    int? taskId,
    String? note,
  }) =>
      _repository.updateTimeRecord(
        recordId: recordId,
        title: title,
        category: category,
        startTime: startTime,
        endTime: endTime,
        taskId: taskId,
        note: note,
      );

  Future<void> deleteTimeRecord({required int recordId}) =>
      _repository.deleteTimeRecord(recordId: recordId);

  void dispose() {}
}

int _asInt(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

class StatsSummary {
  const StatsSummary({
    required this.completedTasks,
    required this.habitCheckIns,
    required this.coinEarned,
    required this.coinSpent,
    required this.expEarned,
    required this.coinBalance,
    required this.expBalance,
    required this.waterBalance,
  });

  final int completedTasks;
  final int habitCheckIns;
  final int coinEarned;
  final int coinSpent;
  final int expEarned;
  final int coinBalance;
  final int expBalance;
  final int waterBalance;

  factory StatsSummary.fromJson(Map<String, dynamic> json) => StatsSummary(
        completedTasks: _asInt(json['completedTasks']),
        habitCheckIns: _asInt(json['habitCheckIns']),
        coinEarned: _asInt(json['coinEarned']),
        coinSpent: _asInt(json['coinSpent']),
        expEarned: _asInt(json['expEarned']),
        coinBalance: _asInt(json['coinBalance']),
        expBalance: _asInt(json['expBalance']),
        waterBalance: _asInt(json['waterBalance']),
      );
}

class StatsDay {
  const StatsDay({
    required this.date,
    required this.completedTasks,
    required this.habitCheckIns,
    required this.coinEarned,
    required this.coinSpent,
    required this.expEarned,
    required this.coinBalance,
    required this.expBalance,
  });

  final String date;
  final int completedTasks;
  final int habitCheckIns;
  final int coinEarned;
  final int coinSpent;
  final int expEarned;
  final int coinBalance;
  final int expBalance;

  factory StatsDay.fromJson(Map<String, dynamic> json) => StatsDay(
        date: json['date']?.toString() ?? '',
        completedTasks: _asInt(json['completedTasks']),
        habitCheckIns: _asInt(json['habitCheckIns']),
        coinEarned: _asInt(json['coinEarned']),
        coinSpent: _asInt(json['coinSpent']),
        expEarned: _asInt(json['expEarned']),
        coinBalance: _asInt(json['coinBalance']),
        expBalance: _asInt(json['expBalance']),
      );
}

class StatsData {
  const StatsData({required this.days, required this.startDate,
    required this.endDate, required this.summary, required this.daily});

  final int days;
  final String startDate;
  final String endDate;
  final StatsSummary summary;
  final List<StatsDay> daily;

  factory StatsData.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'];
    final daily = json['daily'];
    if (summary is! Map || daily is! List) {
      throw ApiException('统计接口缺少 summary 或 daily');
    }
    return StatsData(
      days: _asInt(json['days']),
      startDate: json['startDate']?.toString() ?? '',
      endDate: json['endDate']?.toString() ?? '',
      summary: StatsSummary.fromJson(Map<String, dynamic>.from(summary)),
      daily: daily.map((item) =>
        StatsDay.fromJson(Map<String, dynamic>.from(item as Map))).toList(),
    );
  }
}


class CalendarMonthData {
  const CalendarMonthData({required this.month, required this.days});
  final String month;
  final List<CalendarDaySummary> days;

  Map<String, CalendarDaySummary> get byDate => {
    for (final day in days) day.date: day,
  };

  factory CalendarMonthData.fromJson(Map<String, dynamic> json) {
    final rawDays = json['days'];
    return CalendarMonthData(
      month: json['month']?.toString() ?? '',
      days: rawDays is List
          ? rawDays.whereType<Map>().map((item) => CalendarDaySummary.fromJson(
              Map<String, dynamic>.from(item))).toList()
          : const <CalendarDaySummary>[],
    );
  }
}


class CalendarDaySummary {
  const CalendarDaySummary({
    required this.date,
    required this.completedTasks,
    required this.habitCheckIns,
    required this.timeRecordCount,
    required this.timeMinutes,
    this.requiredTasks = 0,
    this.requiredHabits = 0,
  });

  final String date;

  // 已完成数量
  final int completedTasks;
  final int habitCheckIns;

  // 当天计划数量
  final int requiredTasks;
  final int requiredHabits;

  // 时间统计
  final int timeRecordCount;
  final int timeMinutes;

  // 总计划数量
  int get totalRequired =>
      requiredTasks + requiredHabits;

  // 总完成数量
  int get totalCompleted =>
      completedTasks + habitCheckIns;

  // 每日计划完成率，返回 0.0 ~ 1.0
  double get completionRate {
    if (totalRequired == 0) return 0.0;

    return (totalCompleted / totalRequired)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  int get activityCount =>
      completedTasks + habitCheckIns + timeRecordCount;

  factory CalendarDaySummary.fromJson(
      Map<String, dynamic> json) {
    return CalendarDaySummary(
      date: json['date']?.toString() ?? '',

      completedTasks: _asInt(json['completedTasks']),
      habitCheckIns: _asInt(json['habitCheckIns']),

      requiredTasks: _asInt(json['requiredTasks']),
      requiredHabits: _asInt(json['requiredHabits']),

      timeRecordCount: _asInt(json['timeRecordCount']),
      timeMinutes: _asInt(json['timeMinutes']),
    );
  }
}


class CalendarDayDetail {
  const CalendarDayDetail({required this.date, required this.tasks, required this.habits,
    required this.timeRecords});
  final String date;
  final List<CalendarTaskItem> tasks;
  final List<CalendarHabitItem> habits;
  final List<CalendarTimeRecordItem> timeRecords;

  factory CalendarDayDetail.fromJson(Map<String, dynamic> json) => CalendarDayDetail(
    date: json['date']?.toString() ?? '',
    tasks: json['tasks'] is List
        ? (json['tasks'] as List).whereType<Map>().map((item) =>
            CalendarTaskItem.fromJson(Map<String, dynamic>.from(item))).toList()
        : const <CalendarTaskItem>[],
    habits: json['habits'] is List
        ? (json['habits'] as List).whereType<Map>().map((item) =>
            CalendarHabitItem.fromJson(Map<String, dynamic>.from(item))).toList()
        : const <CalendarHabitItem>[],
    timeRecords: json['timeRecords'] is List
        ? (json['timeRecords'] as List).whereType<Map>().map((item) =>
            CalendarTimeRecordItem.fromJson(Map<String, dynamic>.from(item))).toList()
        : const <CalendarTimeRecordItem>[],
  );
}

class CalendarTimeRecordItem {
  const CalendarTimeRecordItem({required this.timeRecordId, required this.title,
    required this.category, required this.startTime, required this.endTime,
    required this.durationMinutes, this.note, this.taskId});
  final int timeRecordId;
  final String title;
  final String category;
  final DateTime startTime;
  final DateTime endTime;
  final int durationMinutes;
  final String? note;
  final int? taskId;

  factory CalendarTimeRecordItem.fromJson(Map<String, dynamic> json) => CalendarTimeRecordItem(
    timeRecordId: _asInt(json['timeRecordId']),
    title: json['title']?.toString() ?? '未命名记录',
    category: json['category']?.toString() ?? '其他',
    startTime: DateTime.tryParse(json['startTime']?.toString() ?? '') ?? DateTime(2000),
    endTime: DateTime.tryParse(json['endTime']?.toString() ?? '') ?? DateTime(2000),
    durationMinutes: _asInt(json['durationMinutes']),
    note: json['note']?.toString(),
    taskId: json['taskId'] == null ? null : _asInt(json['taskId']),
  );
}

class CalendarTaskItem {
  const CalendarTaskItem({
    required this.taskId,
    required this.title,
    required this.status,
    this.overdue = false,
    required this.actualCount,
    required this.targetCount,
    this.finishTime,
  });
  final int taskId;
  final String title;
  final String status;
  final bool overdue;
  final int actualCount;
  final int targetCount;
  final DateTime? finishTime;

  factory CalendarTaskItem.fromJson(Map<String, dynamic> json) => CalendarTaskItem(
    taskId: _asInt(json['taskId']),
    title: json['title']?.toString() ?? '未命名任务',
    status: json['status']?.toString() ?? 'PENDING',
    overdue: json['overdue'] == true,
    actualCount: _asInt(json['actualCount']),
    targetCount: _asInt(json['targetCount']),
    finishTime: DateTime.tryParse(json['finishTime']?.toString() ?? ''),
  );
}

class CalendarHabitItem {
  const CalendarHabitItem({
    required this.habitId,
    required this.name,
    required this.checkedIn,
    required this.actualCount,
  });
  final int habitId;
  final String name;
  final bool checkedIn;
  final int actualCount;

  factory CalendarHabitItem.fromJson(Map<String, dynamic> json) => CalendarHabitItem(
    habitId: _asInt(json['habitId']),
    name: json['name']?.toString() ?? '未命名习惯',
    checkedIn: json['checkedIn'] == true,
    actualCount: _asInt(json['actualCount']),
  );
}

