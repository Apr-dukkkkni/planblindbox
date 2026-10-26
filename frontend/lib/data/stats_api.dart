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
