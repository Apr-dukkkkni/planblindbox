import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plan_blind_box/services/cloud_archive_service.dart';

void main() {
  const credentials = WebDavCredentials(
    account: 'test@example.com',
    appPassword: 'unit-test-password',
  );

  test('WebDAV upload -> verify -> latest download roundtrip', () async {
    final remoteFiles = <String, String>{};
    final client = MockClient((request) async {
      final path = request.url.path;
      switch (request.method) {
        case 'PROPFIND':
          return http.Response('', 207);
        case 'MKCOL':
          return http.Response('', 201);
        case 'PUT':
          remoteFiles[path] = request.body;
          return http.Response('', 201);
        case 'GET':
          if (!remoteFiles.containsKey(path)) {
            return http.Response('', 404);
          }
          return http.Response(remoteFiles[path]!, 200);
        default:
          return http.Response('', 405);
      }
    });
    final dav = JianguoyunWebDav(client: client);
    await dav.testConnection(credentials);

    const original = '{"tasks":[{"title":"读书"}],"coins":30}';
    await dav.upload(credentials, original);
    final downloaded = await dav.downloadLatest(credentials);
    expect(jsonDecode(downloaded.backupJson), jsonDecode(original));
    expect(remoteFiles.keys.any((p) => p.endsWith('/latest.json')), isTrue);
    dav.dispose();
  });

  test('Tampered archive must be rejected before restore', () async {
    final remoteFiles = <String, String>{};
    final client = MockClient((request) async {
      final path = request.url.path;
      if (request.method == 'MKCOL') return http.Response('', 201);
      if (request.method == 'PUT') {
        remoteFiles[path] = request.body;
        return http.Response('', 201);
      }
      if (request.method == 'GET') {
        final found = remoteFiles[path];
        return found == null ? http.Response('', 404) : http.Response(found, 200);
      }
      return http.Response('', 405);
    });
    final dav = JianguoyunWebDav(client: client);
    await dav.upload(credentials, '{"some":"data"}');
    final fileKey = remoteFiles.keys.firstWhere((p) =>
        p.endsWith('.json') && !p.endsWith('/latest.json'));
    remoteFiles[fileKey] = '{"tampered":true}';
    await expectLater(
      dav.downloadLatest(credentials),
      throwsA(isA<FormatException>()),
    );
    dav.dispose();
  });
}
