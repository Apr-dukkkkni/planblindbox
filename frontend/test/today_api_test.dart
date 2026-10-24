import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plan_blind_box/data/today_api.dart';

void main() {
  test('首页排序参数与统一 Result 解包', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/today');
      expect(request.url.queryParameters['userId'], '1');
      expect(request.url.queryParameters['sort'], 'importance');
      return http.Response(jsonEncode({
        'code': 200, 'message': 'success',
        'data': {'date': '2026-10-23', 'tasks': [], 'habits': [],
          'assets': {'coin': 20, 'exp': 40, 'water': 0},
          'summary': {'taskTotal': 0, 'taskCompleted': 0,
            'habitTotal': 0, 'habitCheckedIn': 0, 'completionRate': 0}},
      }), 200, headers: {'content-type': 'application/json'});
    });
    final api = TodayApi(baseUrl: 'http://localhost:8080', userId: 1, client: client);
    final today = await api.getToday(sort: 'importance');
    expect(today.assets.coin, 20);
    expect(today.tasks, isEmpty);
    api.dispose();
  });

  test('任务完成提交的 actualCount 是本次增量', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/tasks/19/complete');
      expect(request.url.queryParameters['userId'], '1');
      expect(jsonDecode(request.body)['actualCount'], 2);
      return http.Response(jsonEncode({
        'code': 200, 'message': 'success',
        'data': {'reward': {'granted': true, 'coin': 10, 'exp': 20, 'water': 0}},
      }), 200);
    });
    final api = TodayApi(baseUrl: 'http://localhost:8080', userId: 1, client: client);
    final reward = await api.completeTask(taskId: 19, actualCount: 2);
    expect(reward.granted, true);
    expect(reward.coin, 10);
    api.dispose();
  });

  test('全局异常 409 保留后端业务提示', () async {
    final client = MockClient((request) async => http.Response(
      jsonEncode({'code': 409, 'message': '今天已经打过卡了', 'data': null}), 409));
    final api = TodayApi(baseUrl: 'http://localhost:8080', userId: 1, client: client);
    await expectLater(api.checkInHabit(7), throwsA(
        isA<ApiException>().having((error) => error.statusCode, 'statusCode', 409)));
    api.dispose();
  });
}
