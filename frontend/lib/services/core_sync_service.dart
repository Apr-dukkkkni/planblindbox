import 'dart:convert';
import 'package:http/http.dart' as http;

/// The transport protocol for server-side record sync.
/// The local outbox, UUID migration and encrypted diary adapter are deliberately
/// NOT enabled until their persistence and conflict-rescue tests are complete.
/// Never call upload with a SQLite database snapshot.
class CoreSyncClient {
  CoreSyncClient({required String baseUrl, http.Client? client})
      : _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  final String _baseUrl;
  final http.Client _client;
  final bool _ownsClient;

  Uri _path(String path) => Uri.parse('$_baseUrl/api/v1/me/sync$path');
  Map<String, String> _headers(String token) => {
    'Authorization': 'Bearer $token',
    'Accept': 'application/json',
    'Content-Type': 'application/json; charset=utf-8',
  };

  Future<Map<String, dynamic>> _read(http.Response response) async {
    Map<String, dynamic>? data;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {}
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = data?['message'] ?? data?['detail'] ??
          '服务器错误 HTTP ${response.statusCode}';
      throw CoreSyncException(response.statusCode, message.toString());
    }
    if (data == null) throw const FormatException('同步响应格式无效');
    return data;
  }

  Future<Map<String, dynamic>> entitlement(String token) async => _read(
    await _client.get(_path('/entitlement'), headers: _headers(token))
        .timeout(const Duration(seconds: 15)),
  );

  /// Pull from a persisted per-account cursor. Apply changes to SQLite in a
  /// transaction before persisting the returned cursor; otherwise data can be lost.
  Future<Map<String, dynamic>> changes(String token, {
    required int cursor,
    int limit = 100,
  }) async => _read(
    await _client.get(_path('/changes?cursor=$cursor&limit=$limit'),
        headers: _headers(token)).timeout(const Duration(seconds: 20)),
  );

  /// On 409, fetch the remote revision and show/resolve a conflict; never
  /// blindly retry with the server revision or silently overwrite a diary.
  Future<Map<String, dynamic>> mutate(String token, {
    required String operationId,
    required String type,
    required String id,
    required int expectedRevision,
    required bool deleted,
    Map<String, dynamic>? payload,
  }) async => _read(
    await _client.put(_path('/records'), headers: _headers(token), body: jsonEncode({
      'operationId': operationId,
      'type': type,
      'id': id,
      'expectedRevision': expectedRevision,
      'deleted': deleted,
      'payload': deleted ? null : payload,
    })).timeout(const Duration(seconds: 20)),
  );

  void dispose() { if (_ownsClient) _client.close(); }
}

class CoreSyncException implements Exception {
  const CoreSyncException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}
