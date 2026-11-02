import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

// Connect ONLY to the local backup export/restore code that your project
// already uses. Never replace this with ad-hoc SQL DELETE/INSERT statements.
typedef ExportBackupJson = Future<String> Function();
typedef RestoreBackupJson = Future<void> Function(String backupJson);

class ArchiveDataBridge {
  const ArchiveDataBridge({
    required this.exportJson,
    required this.restoreJson,
  });

  final ExportBackupJson exportJson;
  final RestoreBackupJson restoreJson;
}

class WebDavCredentials {
  const WebDavCredentials({required this.account, required this.appPassword});

  final String account;
  final String appPassword;
}

class ArchiveCredentialStore {
  ArchiveCredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _accountKey = 'pbb.webdav.account';
  static const _passwordKey = 'pbb.webdav.appPassword';

  Future<WebDavCredentials?> read() async {
    final account = await _storage.read(key: _accountKey);
    final password = await _storage.read(key: _passwordKey);
    if (account == null || account.isEmpty ||
        password == null || password.isEmpty) {
      return null;
    }
    return WebDavCredentials(account: account, appPassword: password);
  }

  Future<void> save(WebDavCredentials credentials) async {
    await _storage.write(key: _accountKey, value: credentials.account);
    await _storage.write(key: _passwordKey, value: credentials.appPassword);
  }

  Future<void> clear() async {
    await _storage.delete(key: _accountKey);
    await _storage.delete(key: _passwordKey);
  }
}

class CloudArchiveInfo {
  const CloudArchiveInfo({required this.createdAt, required this.fileName});

  final DateTime createdAt;
  final String fileName;
}

class DownloadedArchive {
  const DownloadedArchive({required this.info, required this.backupJson});

  final CloudArchiveInfo info;
  final String backupJson;
}

class JianguoyunWebDav {
  JianguoyunWebDav({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;
  static final Uri _root = Uri.parse('https://dav.jianguoyun.com/dav/');
  static final Uri _folder = _root.resolve('PlanBlindBox/');
  static final Uri _latest = _folder.resolve('latest.json');

  Future<http.Response> _send(
    String method,
    Uri uri,
    WebDavCredentials credentials, {
    String? body,
    Map<String, String> headers = const {},
  }) async {
    final request = http.Request(method, uri);
    request.headers.addAll(headers);
    request.headers['Authorization'] =
        'Basic ${base64Encode(utf8.encode('${credentials.account}:${credentials.appPassword}'))}';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json; charset=utf-8';
      request.body = body;
    }
    final response = await _client.send(request).timeout(
      const Duration(seconds: 30),
    );
    return http.Response.fromStream(response);
  }

  void _require(http.Response response, List<int> allowed, String action) {
    if (!allowed.contains(response.statusCode)) {
      throw StateError('$action失败：HTTP ${response.statusCode}');
    }
  }

  Future<void> testConnection(WebDavCredentials credentials) async {
    final response = await _send(
      'PROPFIND', _root, credentials, headers: const {'Depth': '0'},
    );
    _require(response, [207], 'WebDAV 连接测试');
  }

  Future<void> _ensureFolder(WebDavCredentials credentials) async {
    final response = await _send('MKCOL', _folder, credentials);
    // 405 means the collection already exists in common WebDAV implementations.
    _require(response, [201, 405], '创建存档目录');
  }

  Future<CloudArchiveInfo> upload(
    WebDavCredentials credentials,
    String backupJson,
  ) async {
    final payload = jsonDecode(backupJson); // Validate before any network write.
    final created = DateTime.now().toUtc();
    final random = Random.secure().nextInt(0x7fffffff);
    final timestamp = created.toIso8601String()
        .replaceAll(':', '').replaceAll('.', '').replaceAll('-', '');
    final fileName = 'pbb_${timestamp}_$random.json';
    final envelope = jsonEncode({
      'app': 'PlanBlindBox',
      'archiveVersion': 1,
      'createdAt': created.toIso8601String(),
      'payload': payload,
    });
    final digest = sha256.convert(utf8.encode(envelope)).toString();

    await _ensureFolder(credentials);
    final target = _folder.resolve(fileName);
    final uploaded = await _send('PUT', target, credentials, body: envelope);
    _require(uploaded, [200, 201, 204], '上传存档');

    // Verify file contents before moving the latest pointer.
    final verify = await _send('GET', target, credentials);
    _require(verify, [200], '校验云端存档');
    if (sha256.convert(verify.bodyBytes).toString() != digest) {
      throw StateError('上传后校验失败：云端存档内容不一致');
    }

    // Update pointer last, so a failed upload cannot overwrite the previous one.
    final pointer = jsonEncode({
      'fileName': fileName,
      'createdAt': created.toIso8601String(),
      'sha256': digest,
    });
    final updated = await _send('PUT', _latest, credentials, body: pointer);
    _require(updated, [200, 201, 204], '更新最新存档索引');

    return CloudArchiveInfo(createdAt: created, fileName: fileName);
  }

  Future<DownloadedArchive> downloadLatest(
    WebDavCredentials credentials,
  ) async {
    final pointerResponse = await _send('GET', _latest, credentials);
    if (pointerResponse.statusCode == 404) {
      throw StateError('云端暂无存档');
    }
    _require(pointerResponse, [200], '读取最新存档索引');
    final pointer = jsonDecode(pointerResponse.body);
    if (pointer is! Map<String, dynamic>) {
      throw const FormatException('云端索引格式错误');
    }
    final fileName = pointer['fileName'];
    final digest = pointer['sha256'];
    if (fileName is! String ||
        !RegExp(r'^pbb_[A-Za-z0-9_]+\.json$').hasMatch(fileName) ||
        digest is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      throw const FormatException('云端索引存在非法文件名或摘要');
    }

    final response = await _send('GET', _folder.resolve(fileName), credentials);
    _require(response, [200], '下载存档');
    if (sha256.convert(response.bodyBytes).toString() != digest) {
      throw const FormatException('存档 SHA-256 校验失败，未执行恢复');
    }
    final envelope = jsonDecode(utf8.decode(response.bodyBytes));
    if (envelope is! Map<String, dynamic> ||
        envelope['app'] != 'PlanBlindBox' ||
        envelope['archiveVersion'] != 1 ||
        envelope['createdAt'] is! String ||
        !envelope.containsKey('payload')) {
      throw const FormatException('存档格式或版本不支持，未执行恢复');
    }
    final createdAt = DateTime.tryParse(envelope['createdAt'] as String);
    if (createdAt == null) {
      throw const FormatException('存档时间无效');
    }
    return DownloadedArchive(
      info: CloudArchiveInfo(createdAt: createdAt, fileName: fileName),
      backupJson: jsonEncode(envelope['payload']),
    );
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}

class CloudArchiveController {
  CloudArchiveController({
    required this.bridge,
    ArchiveCredentialStore? store,
    JianguoyunWebDav? webDav,
  })  : store = store ?? ArchiveCredentialStore(),
        webDav = webDav ?? JianguoyunWebDav();

  final ArchiveDataBridge bridge;
  final ArchiveCredentialStore store;
  final JianguoyunWebDav webDav;

  Future<CloudArchiveInfo> upload() async {
    final credentials = await store.read();
    if (credentials == null) throw StateError('请先配置坚果云');
    final data = await bridge.exportJson();
    return webDav.upload(credentials, data);
  }

  Future<DownloadedArchive> downloadLatest() async {
    final credentials = await store.read();
    if (credentials == null) throw StateError('请先配置坚果云');
    return webDav.downloadLatest(credentials);
  }

  // Restore MUST be atomic in the existing local backup implementation.
  // This method does not write directly to SQLite or bypass its validation.
  Future<void> restore(DownloadedArchive archive) async {
    await bridge.restoreJson(archive.backupJson);
  }

  void dispose() => webDav.dispose();
}
