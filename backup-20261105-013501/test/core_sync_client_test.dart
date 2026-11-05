import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plan_blind_box/services/core_sync_service.dart';

void main() {
  test('上传时带登录令牌、幂等操作ID和记录版本', () async {
    final client = CoreSyncClient(baseUrl: 'https://example.test', client: MockClient((request) async {
      expect(request.url.path, '/api/v1/me/sync/records');
      expect(request.method, 'PUT');
      expect(request.headers['Authorization'], 'Bearer testing-token');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['expectedRevision'], 2);
      expect(body['operationId'], '123e4567-e89b-42d3-a456-426614174000');
      expect(body['payload'], {'entity': {'title': '今天看书'}, 'records': []});
      return http.Response('{"revision":3,"cursor":8,"replayed":false}', 200);
    }));
    final result = await client.mutate('testing-token',
      operationId: '123e4567-e89b-42d3-a456-426614174000',
      type: 'task', id: '123e4567-e89b-42d3-a456-426614174001',
      expectedRevision: 2, deleted: false,
      payload: {'entity': {'title': '今天看书'}, 'records': []});
    expect(result['revision'], 3);
    client.dispose();
  });

  test('409 版本冲突不被伪装成成功', () async {
    final client = CoreSyncClient(baseUrl: 'https://example.test', client: MockClient((_) async =>
      http.Response('{"message":"记录版本冲突"}', 409)));
    await expectLater(client.mutate('token',
      operationId: '123e4567-e89b-42d3-a456-426614174000',
      type: 'habit', id: '123e4567-e89b-42d3-a456-426614174001',
      expectedRevision: 0, deleted: true),
      throwsA(isA<CoreSyncException>().having((e) => e.status, 'status', 409)));
    client.dispose();
  });

  test('游标分页必须保留服务端返回值', () async {
    final client = CoreSyncClient(baseUrl: 'https://example.test', client: MockClient((request) async {
      expect(request.url.queryParameters['cursor'], '15');
      expect(request.url.queryParameters['limit'], '100');
      return http.Response('{"cursor":20,"hasMore":false,"changes":[]}', 200);
    }));
    final page = await client.changes('token', cursor: 15);
    expect(page['cursor'], 20);
    client.dispose();
  });
}
