import 'dart:convert';

import 'package:http/http.dart' as http;

import 'today_api.dart';

/// 复用后端现有 /habits API。这个类只负责 HTTP，不操作本地缓存或奖励。
class HabitApi {
  HabitApi({required this.baseUrl, required this.userId, http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final int userId;
  final http.Client _client;

  Uri _url(String path, {bool includeUser = false}) =>
      Uri.parse('$baseUrl$path').replace(
        queryParameters: includeUser ? {'userId': '$userId'} : null,
      );

  Future<dynamic> _request(String method, Uri uri, {Object? body}) async {
    try {
      final headers = <String, String>{'Accept': 'application/json'};
      if (body != null) {
        headers['Content-Type'] = 'application/json; charset=utf-8';
      }

      late final http.Response response;
      switch (method) {
        case 'GET':
          response = await _client.get(uri, headers: headers)
              .timeout(const Duration(seconds: 12));
        case 'POST':
          response = await _client.post(uri, headers: headers,
              body: body == null ? null : jsonEncode(body))
              .timeout(const Duration(seconds: 12));
        case 'PUT':
          response = await _client.put(uri, headers: headers,
              body: body == null ? null : jsonEncode(body))
              .timeout(const Duration(seconds: 12));
        case 'DELETE':
          response = await _client.delete(uri, headers: headers)
              .timeout(const Duration(seconds: 12));
        default:
          throw ApiException('不支持的请求方法：$method');
      }

      final dynamic decoded;
      try {
        decoded = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {
        throw ApiException('服务端返回了无法解析的 JSON（HTTP ${response.statusCode}）',
            statusCode: response.statusCode);
      }
      if (decoded is! Map) {
        throw ApiException('服务端响应格式错误', statusCode: response.statusCode);
      }
      final envelope = Map<String, dynamic>.from(decoded);
      final code = (envelope['code'] as num?)?.toInt();
      if (response.statusCode < 200 || response.statusCode >= 300 || code != 200) {
        final message = envelope['message']?.toString() ?? '';
        throw ApiException(message.isNotEmpty
            ? message
            : '请求失败（HTTP ${response.statusCode}）',
            statusCode: response.statusCode);
      }
      return envelope['data'];
    } on ApiException {
      rethrow;
    } on Exception catch (error) {
      throw ApiException('请求习惯接口失败：$error');
    }
  }

  Future<List<HabitInfo>> getAll() async {
    final data = await _request('GET', _url('/habits', includeUser: true));
    if (data is! List) throw ApiException('习惯列表格式错误');
    return data.map((item) => HabitInfo.fromJson(_asMap(item))).toList();
  }

  Future<HabitInfo> create({
    required String name,
    required String note,
    required String startDate,
    required Map<String, dynamic> repeatRule,
    required int importance,
    required int difficulty,
  }) async {
    final data = await _request('POST', _url('/habits'), body: {
      'userId': userId,
      'name': name,
      'note': note,
      'startDate': startDate,
      'repeatRule': repeatRule,
      'importance': importance,
      'difficulty': difficulty,
    });

    return HabitInfo.fromJson(_asMap(data));
  }

  Future<HabitInfo> update(
      int habitId, {
        required String name,
        required String note,
        required Map<String, dynamic> repeatRule,
        required int importance,
        required int difficulty,
      }) async {
    final data = await _request(
      'PUT',
      _url('/habits/$habitId', includeUser: true),
      body: {
        'name': name,
        'note': note,
        'repeatRule': repeatRule,
        'importance': importance,
        'difficulty': difficulty,
      },
    );

    return HabitInfo.fromJson(_asMap(data));
  }

  Future<void> setPaused(int habitId, {required bool paused}) async {
    await _request(
      'PUT',
      _url('/habits/$habitId', includeUser: true),
      body: {'status': paused ? 'PAUSED' : 'ACTIVE'},
    );
  }

  Future<void> archive(int habitId) async {
    await _request('DELETE', _url('/habits/$habitId', includeUser: true));
  }

  Future<HabitCheckInStats> getCheckInStats(int habitId) async {
    final data = await _request(
      'GET',
      _url('/habits/$habitId/check-in-status', includeUser: true),
    );
    return HabitCheckInStats.fromJson(_asMap(data));
  }

  void dispose() => _client.close();
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is! Map) throw ApiException('服务端返回的数据不是 JSON 对象');
  return Map<String, dynamic>.from(value);
}

class HabitInfo {
  HabitInfo({
    required this.id,
    required this.name,
    required this.note,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.repeatRule,
    required this.importance,
    required this.difficulty,
  });

  final int id;
  final String name;
  final String note;
  final String startDate;
  final String? endDate;
  final String status;
  final int importance;
  final int difficulty;
  final Map<String, dynamic> repeatRule;

  factory HabitInfo.fromJson(Map<String, dynamic> json) {
    final id = (json['habitId'] as num?)?.toInt();
    if (id == null) throw ApiException('Habit 缺少 habitId');
    return HabitInfo(
      id: id,
      name: json['name']?.toString() ?? '',
      note: json['note']?.toString() ?? '',
      startDate: json['startDate']?.toString() ?? '',
      endDate: json['endDate']?.toString(),
      status: json['status']?.toString() ?? 'ACTIVE',
      repeatRule: json['repeatRule'] is Map
          ? Map<String, dynamic>.from(json['repeatRule'] as Map)
          : {'type': 'DAILY'},
      importance: (json['importance'] as num?)?.toInt() ?? 3,
      difficulty: (json['difficulty'] as num?)?.toInt() ?? 3,
    );
  }

  String get repeatLabel {
    if (repeatRule['type'] != 'WEEKLY') return '每天';
    const labels = ['一', '二', '三', '四', '五', '六', '日'];
    final days = repeatRule['daysOfWeek'];
    if (days is! List) return '每周';
    final selected = days.whereType<num>().map((d) => d.toInt())
        .where((d) => d >= 1 && d <= 7).toList()..sort();
    return '每周${selected.map((d) => labels[d - 1]).join('、')}';
  }
}

class HabitCheckInStats {
  HabitCheckInStats({
    required this.currentStreak,
    required this.totalCheckInDays,
    required this.checkedInToday,
  });

  final int currentStreak;
  final int totalCheckInDays;
  final bool checkedInToday;

  factory HabitCheckInStats.fromJson(Map<String, dynamic> json) =>
      HabitCheckInStats(
        currentStreak: (json['currentStreak'] as num?)?.toInt() ?? 0,
        totalCheckInDays: (json['totalCheckInDays'] as num?)?.toInt() ?? 0,
        checkedInToday: json['checkedInToday'] == true,
      );
}
