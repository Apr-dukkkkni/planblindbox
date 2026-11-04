import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import '../auth/auth_session.dart';
import '../auth/auth_api.dart';

/// 独立在线 Mod 市场客户端。绝不用于个人任务、习惯、资产读写。
class ModMarketApi {
  ModMarketApi({this.session, http.Client? client}) : _client = client ?? http.Client();
  final AuthSession? session;
  final http.Client _client;

  static const String baseUrl = String.fromEnvironment(
    'MOD_MARKET_URL',
    defaultValue: 'http://localhost:8091',
  );

  Uri _url(String path, [Map<String, String>? query]) {
    final base = Uri.parse(baseUrl);
    return base.replace(
      path: '${base.path.replaceFirst(RegExp(r'/$'), '')}$path',
      queryParameters: query,
    );
  }

  Future<List<Map<String, dynamic>>> catalog({String search = ''}) async {
    final response = await _client
        .get(_url('/api/v1/mods', {'search': search, 'size': '30'}))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw StateError('在线市场返回 HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! List) throw const FormatException('市场数据格式异常');
    return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Mod detail is public; manifest content requires login.
  Future<Map<String, dynamic>> detail(String id) async {
    final response=await _client.get(_url('/api/v1/mods/${Uri.encodeComponent(id)}'))
        .timeout(const Duration(seconds: 12));
    if(response.statusCode!=200) throw StateError('获取 Mod 详情失败：HTTP ${response.statusCode}');
    final decoded=jsonDecode(utf8.decode(response.bodyBytes));
    if(decoded is! Map) throw const FormatException('Mod 详情格式错误');
    return Map<String,dynamic>.from(decoded);
  }

  /// 下载排行榜：有 Redis 时读缓存，关闭排行榜或 Redis 故障时由后端回退 MySQL。
  Future<List<Map<String, dynamic>>> ranking({int limit = 20}) async {
    final response = await _client
        .get(_url('/api/v1/mods/ranking', {'limit': '$limit'}))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw StateError('排行榜返回 HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! List) throw const FormatException('排行榜数据格式异常');
    return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  String _requestId() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int i) => bytes[i].toRadixString(16).padLeft(2, '0');
    final s = List.generate(16, hex).join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-'
        '${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
  }

  /// 仅在用户点击下载时产生一次事件；重试可复用 requestId。
  Future<String> download(String id, String version, {String? requestId}) async {
    final uri = _url('/api/v1/mods/${Uri.encodeComponent(id)}/versions/'
        '${Uri.encodeComponent(version)}/download');
    final token = session?.token;
    if (token == null) throw const AuthApiException('请先登录再下载 Mod', 401);
    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode({'requestId': requestId ?? _requestId()}),
    ).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      if (response.statusCode == 401) {
        final activeSession = session;
        if (activeSession != null) {
          await activeSession.expireSession();
        }
        throw const AuthApiException('登录已过期，请重新登录', 401);
      }
      throw StateError('下载失败：HTTP ${response.statusCode}');
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (body is! Map || body['manifest'] is! String ||
        body['manifestSha256'] is! String) {
      throw const FormatException('下载响应缺少清单或 SHA-256 校验值');
    }
    final raw = body['manifest'] as String;
    final expected = body['manifestSha256'] as String;
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(expected)) {
      throw const FormatException('服务器返回的 SHA-256 校验值格式错误');
    }
    final actual = crypto.sha256.convert(utf8.encode(raw)).toString();
    if (actual != expected) {
      throw const FormatException('Mod 清单完整性校验失败，已拒绝安装');
    }
    return raw;
  }

  void dispose() => _client.close();
}
