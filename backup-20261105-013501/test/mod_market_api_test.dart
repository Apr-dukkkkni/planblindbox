import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart' as crypto;
import 'package:http/testing.dart';
import 'package:plan_blind_box/data/mod_market_api.dart';

void main() {
  test('在线市场只查询 Mod 元数据并解析响应', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/v1/mods');
      return http.Response(jsonEncode([
        {'id': 'com.example.reading', 'name': '阅读模板', 'latestVersion': '1.0.0', 'downloads': 3}
      ]), 200, headers: {'content-type': 'application/json'});
    });
    final api = ModMarketApi(client: client);
    final mods = await api.catalog(search: '阅读');
    expect(mods.single['downloads'], 3);
    api.dispose();
  });

  test('下载清单使用请求唯一键且仅解析为文本', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/mods/com.example.reading/versions/1.0.0/download');
      expect(jsonDecode(request.body)['requestId'], '123e4567-e89b-42d3-a456-426614174000');
      final raw = '{"schemaVersion":1}';
      return http.Response(jsonEncode({'manifest': raw, 'manifestSha256': crypto.sha256.convert(utf8.encode(raw)).toString(), 'counted': true}), 200);
    });
    final api = ModMarketApi(client: client);
    final raw = await api.download('com.example.reading', '1.0.0',
      requestId: '123e4567-e89b-42d3-a456-426614174000');
    expect(raw, '{"schemaVersion":1}');
    api.dispose();
  });

  test('拒绝损坏清单和缺失摘要的响应', () async {
    final responses = [
      {'manifest': '{"schemaVersion":2}', 'manifestSha256': crypto.sha256.convert(utf8.encode('{"schemaVersion":1}')).toString()},
      {'manifest': '{"schemaVersion":1}'},
    ];
    var index = 0;
    final client = MockClient((request) async => http.Response(jsonEncode(responses[index++]), 200));
    final api = ModMarketApi(client: client);
    await expectLater(api.download('com.example.reading', '1.0.0'), throwsFormatException);
    await expectLater(api.download('com.example.reading', '1.0.0'), throwsFormatException);
    api.dispose();
  });
}
