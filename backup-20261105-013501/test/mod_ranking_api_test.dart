import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plan_blind_box/data/mod_market_api.dart';

void main() {
  test('排行榜接口获取排序数据，不修改本地任务数据', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/v1/mods/ranking');
      expect(request.url.queryParameters['limit'], '20');
      return http.Response(jsonEncode([
        {
          'id': 'com.example.reading', 'name': '阅读模板',
          'description': '阅读任务', 'latestVersion': '1.0.0', 'downloads': 8,
        },
      ]), 200, headers: {'content-type': 'application/json'});
    });
    final api = ModMarketApi(client: client);
    final rank = await api.ranking();
    expect(rank.single['downloads'], 8);
    api.dispose();
  });
}
