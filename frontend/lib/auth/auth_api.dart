import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'validators.dart';

class AuthApiException implements Exception {
  final int? statusCode;
  final String message;
  const AuthApiException(this.message, [this.statusCode]);
  @override
  String toString() => message;
}

class UserProfile {
  final int userId;
  final String username;
  final String email;
  final String gender;
  final String? avatar;
  final String? birthday;
  const UserProfile({required this.userId, required this.username,
    required this.email, required this.gender, this.avatar, this.birthday});
  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    userId: (json['userId'] as num).toInt(),
    username: json['username'] as String,
    email: json['email'] as String,
    gender: json['gender'] as String,
    avatar: json['avatar'] as String?,
    birthday: json['birthday'] as String?,
  );
}

class LoginResult {
  final String accessToken;
  final int expiresIn;
  final UserProfile user;
  const LoginResult(this.accessToken, this.expiresIn, this.user);
  factory LoginResult.fromJson(Map<String, dynamic> json) => LoginResult(
    json['accessToken'] as String,
    (json['expiresIn'] as num).toInt(),
    UserProfile.fromJson(json['user'] as Map<String, dynamic>),
  );
}

class ForgotResult {
  final String challengeId;
  const ForgotResult(this.challengeId);
}

class CloudSnapshot {
  final int revision;
  final int schemaVersion;
  final Map<String,dynamic> payload;
  CloudSnapshot(this.revision,this.schemaVersion,this.payload);
  factory CloudSnapshot.fromJson(Map<String,dynamic> json)=>CloudSnapshot(
    (json['revision'] as num).toInt(),(json['schemaVersion'] as num).toInt(),
    Map<String,dynamic>.from(json['payload'] as Map));
}

class AuthApi {
  /// Set by --dart-define=API_BASE_URL=https://your-host (no trailing slash).
  final String baseUrl;
  final http.Client _client;
  AuthApi({required String baseUrl, http.Client? client})
      : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        _client = client ?? http.Client();

  Uri _uri(String path) {
    if (baseUrl.isEmpty || !baseUrl.startsWith('http')) {
      throw const AuthApiException('未配置 API_BASE_URL，请在打包时指定服务端地址');
    }
    return Uri.parse('$baseUrl$path');
  }

  String? absoluteAvatarUrl(String? url) {
    if (url == null || url.trim().isEmpty) return null;
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    if (uri.hasScheme && uri.scheme == 'https') return uri.toString();
    if (uri.hasScheme) return null; // Do not render insecure or arbitrary schemes.
    return _uri(url.startsWith('/') ? url : '/$url').toString();
  }

  Map<String, String> _headers([String? token]) => {
    'Accept': 'application/json',
    'Content-Type': 'application/json; charset=utf-8',
    if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
  };

  Future<http.Response> _call(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(const Duration(seconds: 15));
    } on AuthApiException { rethrow; }
    catch (_) { throw const AuthApiException('网络连接失败，请检查网络和服务器地址'); }
  }

  Object? _parse(http.Response response) {
    if (response.bodyBytes.isEmpty) return null;
    try { return jsonDecode(utf8.decode(response.bodyBytes)); }
    catch (_) { return null; }
  }

  Map<String, dynamic> _requireObject(Object? body) {
    if (body is Map<String, dynamic>) return body;
    throw const AuthApiException('服务器响应格式不正确');
  }

  void _ensure(http.Response res, Set<int> allowed) {
    if (allowed.contains(res.statusCode)) return;
    final body = _parse(res);
    final serverMessage = body is Map
        ? (body['message'] ?? body['detail'] ?? body['error'])
        : null;
    String fallback;
    switch (res.statusCode) {
      case 400: fallback = '提交数据不符合要求'; break;
      case 401: fallback = '邮箱或密码错误，或登录已过期'; break;
      case 403: fallback = '没有操作权限'; break;
      case 404: fallback = '接口不存在，请确认服务端已部署账号功能'; break;
      case 409: fallback = '邮箱已经注册或数据存在冲突'; break;
      case 413: fallback = '上传文件过大'; break;
      case 429: fallback = '操作过于频繁，请稍后再试'; break;
      case 503: fallback = '服务暂时不可用'; break;
      default: fallback = '请求失败（HTTP ${res.statusCode}）';
    }
    throw AuthApiException(
      serverMessage is String && serverMessage.isNotEmpty ? serverMessage : fallback,
      res.statusCode,
    );
  }

  Future<void> register({required String username, required String email,
    required String password, required String gender}) async {
    final res = await _call(() => _client.post(_uri('/api/v1/auth/register'),
      headers: _headers(), body: jsonEncode({
        'username': normalizedUsername(username), 'email': normalizedEmail(email),
        'password': password, 'gender': gender,
      })));
    _ensure(res, {201});
  }

  Future<LoginResult> login(String email, String password) async {
    final res = await _call(() => _client.post(_uri('/api/v1/auth/login'),
      headers: _headers(), body: jsonEncode({
        'email': normalizedEmail(email), 'password': password,
      })));
    _ensure(res, {200});
    return LoginResult.fromJson(_requireObject(_parse(res)));
  }

  Future<ForgotResult> forgotPassword(String email) async {
    final res = await _call(() => _client.post(_uri('/api/v1/auth/password/forgot'),
      headers: _headers(), body: jsonEncode({'email': normalizedEmail(email)})));
    _ensure(res, {202});
    return ForgotResult(_requireObject(_parse(res))['challengeId'] as String);
  }

  Future<void> resetPassword({required String email, required String challengeId,
    required String code, required String newPassword}) async {
    final res = await _call(() => _client.post(_uri('/api/v1/auth/password/reset'),
      headers: _headers(), body: jsonEncode({
        'email': normalizedEmail(email), 'challengeId': challengeId,
        'code': code, 'newPassword': newPassword,
      })));
    _ensure(res, {204});
  }

  Future<UserProfile> me(String token) async {
    final res = await _call(() => _client.get(_uri('/api/v1/me'), headers: _headers(token)));
    _ensure(res, {200});
    return UserProfile.fromJson(_requireObject(_parse(res)));
  }

  Future<UserProfile> updateProfile(String token, {required String username,
    required String gender, String? birthday}) async {
    final res = await _call(() => _client.put(_uri('/api/v1/me'),
      headers: _headers(token), body: jsonEncode({
        'username': normalizedUsername(username), 'gender': gender,
        'birthday': birthday,
      })));
    _ensure(res, {200});
    return UserProfile.fromJson(_requireObject(_parse(res)));
  }

  Future<UserProfile> uploadAvatar(String token, XFile picked) async {
    final bytes = await picked.readAsBytes();
    if (bytes.isEmpty || bytes.length > 2 * 1024 * 1024) {
      throw const AuthApiException('头像大小必须在 0～2 MiB 之间');
    }
    final request = http.MultipartRequest('POST', _uri('/api/v1/me/avatar'));
    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: picked.name));
    try {
      final streamed = await _client.send(request).timeout(const Duration(seconds: 20));
      final res = await http.Response.fromStream(streamed);
      _ensure(res, {200});
      // Avatar endpoint returns {avatar: "..."}; re-fetch canonical profile.
      return me(token);
    } on AuthApiException { rethrow; }
    catch (_) { throw const AuthApiException('头像上传失败，请检查网络'); }
  }

  Future<UserProfile> deleteAvatar(String token) async {
    final res = await _call(() => _client.delete(_uri('/api/v1/me/avatar'), headers: _headers(token)));
    _ensure(res, {204});
    return me(token);
  }

  Future<void> logout(String token) async {
    final res = await _call(() => _client.post(_uri('/api/v1/auth/logout'), headers: _headers(token)));
    _ensure(res, {204});
  }

  /// Use for a Mod download route after login. If 401, ask the caller to sign in again.
  Future<http.Response> getWithToken(String path, String token) async {
    final res = await _call(() => _client.get(_uri(path), headers: _headers(token)));
    _ensure(res, {200});
    return res;
  }
  Future<CloudSnapshot?> getProgress(String token) async {
    final res=await _call(()=>_client.get(_uri('/api/v1/me/progress'),headers:_headers(token)));
    if(res.statusCode==404)return null;
    _ensure(res,{200});
    return CloudSnapshot.fromJson(_requireObject(_parse(res)));
  }

  Future<int> putProgress(String token,int expectedRevision,Map<String,dynamic> payload) async {
    final res=await _call(()=>_client.put(_uri('/api/v1/me/progress'),
      headers:_headers(token),body:jsonEncode({'expectedRevision':expectedRevision,
        'schemaVersion':1,'payload':payload})));
    _ensure(res,{200});
    return (_requireObject(_parse(res))['revision'] as num).toInt();
  }

  void dispose() => _client.close();
}
