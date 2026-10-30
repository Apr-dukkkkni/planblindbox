import 'dart:convert';

import 'package:http/http.dart' as http;

import 'today_api.dart';

class StatsApi {
  StatsApi({required this.baseUrl, required this.userId, http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final int userId;
  final http.Client _client;

  Future<StatsData> getStats({int days = 7}) async {
    if (days != 7 && days != 30) {
      throw ApiException('统计周期只支持 7 天或 30 天');
    }
    final uri = Uri.parse('$baseUrl/stats').replace(queryParameters: {
      'userId': '$userId',
      'days': '$days',
    });
    try {
      final response = await _client.get(uri, headers: {
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 12));
      final dynamic parsed;
      try {
        parsed = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {
        throw ApiException('统计接口响应不是合法 JSON（HTTP ${response.statusCode}）');
      }
      if (parsed is! Map) throw ApiException('统计接口响应格式错误');
      final body = Map<String, dynamic>.from(parsed);
      if (response.statusCode < 200 || response.statusCode >= 300 ||
          (body['code'] as num?)?.toInt() != 200) {
        throw ApiException(body['message']?.toString() ?? '统计数据加载失败');
      }
      if (body['data'] is! Map) throw ApiException('统计接口缺少 data 对象');
      return StatsData.fromJson(Map<String, dynamic>.from(body['data'] as Map));
    } on ApiException {
      rethrow;
    } on Exception catch (error) {
      throw ApiException('统计接口连接失败：$error');
    }
  }

  Future<CalendarMonthData> getCalendarMonth({required DateTime month}) async {
    final monthText = '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}';
    final uri = Uri.parse('$baseUrl/stats/calendar').replace(queryParameters: {
      'userId': '$userId',
      'month': monthText,
    });
    final data = await _getMap(uri, '日历月度数据');
    return CalendarMonthData.fromJson(data);
  }

  Future<CalendarDayDetail> getCalendarDay({required String date}) async {
    final uri = Uri.parse('$baseUrl/stats/calendar/day').replace(queryParameters: {
      'userId': '$userId',
      'date': date,
    });
    final data = await _getMap(uri, '日期详情');
    return CalendarDayDetail.fromJson(data);
  }

  Future<void> createTimeRecord({
    required String title,
    required String category,
    required DateTime startTime,
    required DateTime endTime,
    String? note,
  }) async {
    final uri = Uri.parse('$baseUrl/time-records').replace(queryParameters: {
      'userId': '$userId',
    });
    await _mutate(uri, 'POST', {
      'title': title,
      'category': category,
      'startTime': _formatLocalDateTime(startTime),
      'endTime': _formatLocalDateTime(endTime),
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    }, '创建时间记录');
  }

  Future<void> updateTimeRecord({
    required int recordId,
    required String title,
    required String category,
    required DateTime startTime,
    required DateTime endTime,
    int? taskId,
    String? note,
  }) async {
    final uri = Uri.parse('$baseUrl/time-records/$recordId').replace(queryParameters: {
      'userId': '$userId',
    });
    await _mutate(uri, 'PUT', {
      'title': title,
      'category': category,
      'startTime': _formatLocalDateTime(startTime),
      'endTime': _formatLocalDateTime(endTime),
      if (taskId != null) 'taskId': taskId,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    }, '更新时间记录');
  }

  Future<void> deleteTimeRecord({required int recordId}) async {
    final uri = Uri.parse('$baseUrl/time-records/$recordId').replace(queryParameters: {
      'userId': '$userId',
    });
    await _mutate(uri, 'DELETE', null, '删除时间记录');
  }

  Future<void> _mutate(Uri uri, String method, Map<String, dynamic>? body, String label) async {
    try {
      final headers = <String, String>{'Accept': 'application/json'};
      if (body != null) headers['Content-Type'] = 'application/json; charset=utf-8';
      late final http.Response response;
      switch (method) {
        case 'POST':
          response = await _client.post(uri, headers: headers, body: jsonEncode(body))
              .timeout(const Duration(seconds: 12));
        case 'PUT':
          response = await _client.put(uri, headers: headers, body: jsonEncode(body))
              .timeout(const Duration(seconds: 12));
        case 'DELETE':
          response = await _client.delete(uri, headers: headers)
              .timeout(const Duration(seconds: 12));
        default:
          throw ApiException('不支持的请求方法：$method');
      }
      final dynamic parsed;
      try {
        parsed = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {
        throw ApiException('$label接口响应不是合法 JSON（HTTP ${response.statusCode}）');
      }
      if (parsed is! Map) throw ApiException('$label接口响应格式错误');
      final envelope = Map<String, dynamic>.from(parsed);
      if (response.statusCode < 200 || response.statusCode >= 300 ||
          (envelope['code'] as num?)?.toInt() != 200) {
        throw ApiException(envelope['message']?.toString() ?? '$label失败');
      }
    } on ApiException {
      rethrow;
    } on Exception catch (error) {
      throw ApiException('$label失败：$error');
    }
  }

  Future<Map<String, dynamic>> _getMap(Uri uri, String label) async {
    try {
      final response = await _client.get(uri, headers: {
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 12));
      final dynamic parsed;
      try {
        parsed = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {
        throw ApiException('$label接口响应不是合法 JSON（HTTP ${response.statusCode}）');
      }
      if (parsed is! Map) throw ApiException('$label接口响应格式错误');
      final body = Map<String, dynamic>.from(parsed);
      if (response.statusCode < 200 || response.statusCode >= 300 ||
          (body['code'] as num?)?.toInt() != 200) {
        throw ApiException(body['message']?.toString() ?? '$label加载失败');
      }
      if (body['data'] is! Map) throw ApiException('$label接口缺少 data 对象');
      return Map<String, dynamic>.from(body['data'] as Map);
    } on ApiException {
      rethrow;
    } on Exception catch (error) {
      throw ApiException('$label接口连接失败：$error');
    }
  }

  void dispose() => _client.close();
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
    required this.totalTasks,
    required this.totalHabits,
    required this.completionRate,
    required this.timeRecordCount,
    required this.timeMinutes,
  });

  final String date;

  final int completedTasks;
  final int habitCheckIns;

  final int totalTasks;
  final int totalHabits;

  final double completionRate;

  final int timeRecordCount;
  final int timeMinutes;

  // 时间记录不再参与热力图统计
  int get activityCount =>
      completedTasks + habitCheckIns;

  factory CalendarDaySummary.fromJson(
      Map<String, dynamic> json) {

    final completedTasks =
    _asInt(json['completedTasks']);

    final habitCheckIns =
    _asInt(json['habitCheckIns']);

    final totalTasks =
    _asInt(json['totalTasks']);

    final totalHabits =
    _asInt(json['totalHabits']);

    final total = totalTasks + totalHabits;
    final completed = completedTasks + habitCheckIns;

    final rawRate = json['completionRate'];

    final rate = rawRate is num
        ? rawRate.toDouble()
        : (total == 0 ? 0.0 : completed / total);

    return CalendarDaySummary(
      date: json['date']?.toString() ?? '',
      completedTasks: completedTasks,
      habitCheckIns: habitCheckIns,
      totalTasks: totalTasks,
      totalHabits: totalHabits,
      completionRate: rate.clamp(0.0, 1.0),
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

String _formatLocalDateTime(DateTime value) {
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${value.year}-${pad(value.month)}-${pad(value.day)}T'
      '${pad(value.hour)}:${pad(value.minute)}:${pad(value.second)}';
}
