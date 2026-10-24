import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/today_models.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

/// 只处理已在 PlanBlindBox 后端实际实现的 HTTP 接口。
class TodayApi {
  TodayApi({required this.baseUrl, required this.userId, http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final int userId;
  final http.Client _client;

  Uri _url(String path, [Map<String, String>? params]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: params);

  Future<Map<String, dynamic>> _request(String method, Uri uri, {Object? body}) async {
    try {
      final headers = <String, String>{'Accept': 'application/json'};
      if (body != null) headers['Content-Type'] = 'application/json; charset=utf-8';
      late final http.Response response;
      switch (method) {
        case 'GET':
          response = await _client.get(uri, headers: headers).timeout(const Duration(seconds: 12));
        case 'POST':
          response = await _client.post(uri, headers: headers,
              body: body == null ? null : jsonEncode(body)).timeout(const Duration(seconds: 12));
        default:
          throw ApiException('不支持的请求方法：$method');
      }

      Map<String, dynamic> envelope;
      try {
        envelope = Map<String, dynamic>.from(jsonDecode(utf8.decode(response.bodyBytes)) as Map);
      } catch (_) {
        throw ApiException('服务器返回了无法解析的数据（HTTP ${response.statusCode}）',
            statusCode: response.statusCode);
      }
      final code = (envelope['code'] as num?)?.toInt();
      if (response.statusCode < 200 || response.statusCode >= 300 || code != 200) {
        throw ApiException(
          (envelope['message']?.toString().isNotEmpty ?? false)
              ? envelope['message'].toString()
              : '请求失败（HTTP ${response.statusCode}）',
          statusCode: response.statusCode,
        );
      }
      final payload = envelope['data'];
      return payload is Map ? Map<String, dynamic>.from(payload) : <String, dynamic>{};
    } on ApiException {
      rethrow;
    } on Exception catch (error) {
      throw ApiException('无法连接后端，请检查 Spring Boot、网络地址与端口：$error');
    }
  }

  Future<TodayData> getToday({String sort = 'time'}) async {
    final data = await _request('GET', _url('/today', {
      'userId': '$userId', 'sort': sort,
    }));
    return TodayData.fromJson(data);
  }

  Future<EarnedReward> completeTask({required int taskId, required int actualCount}) async {
    final result = await _request('POST', _url('/tasks/$taskId/complete', {
      'userId': '$userId',
    }), body: {'actualCount': actualCount});
    return EarnedReward.fromResponse(result);
  }

  Future<EarnedReward> checkInHabit(int habitId) async {
    final result = await _request('POST', _url('/habits/$habitId/check-in', {
      'userId': '$userId',
    }));
    return EarnedReward.fromResponse(result);
  }

  Future<void> createTask({
    required String title,
    required String note,
    required int targetCount,
    required int importance,
    required int difficulty,
    required DateTime endTime,
  }) async {
    await _request('POST', _url('/tasks'), body: {
      'userId': userId,
      'title': title,
      'note': note,
      'startTime': _localDateTime(DateTime.now()),
      'endTime': _localDateTime(endTime),
      'targetCount': targetCount,
      'importance': importance,
      'difficulty': difficulty,
    });
  }

  Future<void> createDailyHabit({required String name, required String note, required String startDate}) async {
    await _request('POST', _url('/habits'), body: {
      'userId': userId,
      'name': name,
      'note': note,
      'startDate': startDate,
      'repeatRule': {'type': 'DAILY'},
    });
  }

  void dispose() => _client.close();
}

String _localDateTime(DateTime date) {
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${date.year}-${pad(date.month)}-${pad(date.day)}T${pad(date.hour)}:${pad(date.minute)}:${pad(date.second)}';
}
