import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'validators.dart';
import '../services/account_master_key_envelope.dart';
import '../services/opaque_client/opaque_client.dart';

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
  const UserProfile({
    required this.userId,
    required this.username,
    required this.email,
    required this.gender,
    this.avatar,
    this.birthday,
  });
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
  final List<int> accountMasterKey;
  final String opaqueClientIdentifier;
  final String credentialChangeTicket;
  const LoginResult(
    this.accessToken,
    this.expiresIn,
    this.user,
    this.accountMasterKey,
    this.opaqueClientIdentifier,
    this.credentialChangeTicket,
  );
}

class CredentialChangeResult {
  final String accessToken;
  final int expiresIn;
  const CredentialChangeResult(this.accessToken, this.expiresIn);
}

class ForgotResult {
  final String challengeId;
  const ForgotResult(this.challengeId);
}

class AuthApi {
  /// Set by --dart-define=API_BASE_URL=https://your-host (no trailing slash).
  final String baseUrl;
  final http.Client _client;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
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
    if (uri.hasScheme)
      return null; // Do not render insecure or arbitrary schemes.
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
    } on AuthApiException {
      rethrow;
    } catch (_) {
      throw const AuthApiException('网络连接失败，请检查网络和服务器地址');
    }
  }

  Object? _parse(http.Response response) {
    if (response.bodyBytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      return null;
    }
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
      case 400:
        fallback = '提交数据不符合要求';
        break;
      case 401:
        fallback = '邮箱或密码错误，或登录已过期';
        break;
      case 403:
        fallback = '没有操作权限';
        break;
      case 404:
        fallback = '接口不存在，请确认服务端已部署账号功能';
        break;
      case 409:
        fallback = '邮箱已经注册或数据存在冲突';
        break;
      case 413:
        fallback = '上传文件过大';
        break;
      case 410:
        fallback = '该功能已停用，请升级客户端';
        break;
      case 429:
        fallback = '操作过于频繁，请稍后再试';
        break;
      case 503:
        fallback = '服务暂时不可用';
        break;
      default:
        fallback = '请求失败（HTTP ${res.statusCode}）';
    }
    throw AuthApiException(
      serverMessage is String && serverMessage.isNotEmpty
          ? serverMessage
          : fallback,
      res.statusCode,
    );
  }

  Future<void> register({
    required String username,
    required String email,
    required String password,
    required String gender,
  }) async {
    final normalized = normalizedEmail(email);
    final started = await opaqueInvoke('registration.start', {
      'email': normalized,
      'password': password,
    });
    final startResponse = await _call(
      () => _client.post(
        _uri('/api/v2/auth/register/start'),
        headers: _headers(),
        body: jsonEncode({
          'username': normalizedUsername(username),
          'email': normalized,
          'gender': gender,
          'registrationRequest': started['registrationRequest'],
        }),
      ),
    );
    _ensure(startResponse, {200});
    final serverStart = _requireObject(_parse(startResponse));
    final existingPin = await _secureStorage.read(key: _opaquePinKey);
    if ((existingPin != null &&
            existingPin != serverStart['serverStaticPublicKey']) ||
        (_buildOpaqueServerPublicKey.isNotEmpty &&
            _buildOpaqueServerPublicKey !=
                serverStart['serverStaticPublicKey'])) {
      throw const AuthApiException('OPAQUE 服务端公钥不匹配，已拒绝注册');
    }
    final finished = await opaqueInvoke('registration.finish', {
      'flowId': started['flowId'],
      'clientIdentifier': serverStart['clientIdentifier'],
      'registrationResponse': serverStart['registrationResponse'],
    });
    if (finished['serverStaticPublicKey'] !=
            serverStart['serverStaticPublicKey'] ||
        (_buildOpaqueServerPublicKey.isNotEmpty &&
            finished['serverStaticPublicKey'] != _buildOpaqueServerPublicKey)) {
      throw const AuthApiException('OPAQUE 服务端公钥不一致，已拒绝注册');
    }
    final random = Random.secure();
    final amk = List<int>.generate(32, (_) => random.nextInt(256));
    final wrapped = await AccountMasterKeyEnvelope.wrap(
      exportKey: finished['exportKey'] as String,
      masterKey: amk,
      accountIdentifier: serverStart['clientIdentifier'] as String,
    );
    final finishResponse = await _call(
      () => _client.post(
        _uri('/api/v2/auth/register/finish'),
        headers: _headers(),
        body: jsonEncode({
          'username': normalizedUsername(username),
          'email': normalized,
          'gender': gender,
          'challengeId': serverStart['challengeId'],
          'registrationRecord': finished['registrationRecord'],
          'serverStaticPublicKey': finished['serverStaticPublicKey'],
          'wrappedAmk': wrapped,
        }),
      ),
    );
    _ensure(finishResponse, {200});
    await _secureStorage.write(
      key: _opaquePinKey,
      value: finished['serverStaticPublicKey'] as String,
    );
  }

  static const _buildOpaqueServerPublicKey = String.fromEnvironment(
    'OPAQUE_SERVER_PUBLIC_KEY',
  );

  String get _opaquePinKey =>
      'pbb.opaque.server_static_key.${Uri.encodeComponent(baseUrl)}';

  Future<LoginResult> login(String email, String password) async {
    final normalized = normalizedEmail(email);
    final started = await opaqueInvoke('login.start', {
      'email': normalized,
      'password': password,
    });
    final startResponse = await _call(
      () => _client.post(
        _uri('/api/v2/auth/login/start'),
        headers: _headers(),
        body: jsonEncode({
          'email': normalized,
          'startLoginRequest': started['startLoginRequest'],
        }),
      ),
    );
    _ensure(startResponse, {200});
    final serverStart = _requireObject(_parse(startResponse));
    final pinnedKey = await _secureStorage.read(key: _opaquePinKey);
    if ((pinnedKey != null &&
            pinnedKey != serverStart['serverStaticPublicKey']) ||
        (_buildOpaqueServerPublicKey.isNotEmpty &&
            _buildOpaqueServerPublicKey !=
                serverStart['serverStaticPublicKey'])) {
      throw const AuthApiException('OPAQUE 服务端公钥已变化，可能存在服务器身份异常，已拒绝登录');
    }
    final finished = await opaqueInvoke('login.finish', {
      'flowId': started['flowId'],
      'clientIdentifier': serverStart['clientIdentifier'],
      'loginResponse': serverStart['loginResponse'],
    });
    if (finished['serverStaticPublicKey'] !=
        serverStart['serverStaticPublicKey']) {
      throw const AuthApiException('OPAQUE 服务端公钥不一致，已拒绝登录');
    }
    final finishResponse = await _call(
      () => _client.post(
        _uri('/api/v2/auth/login/finish'),
        headers: _headers(),
        body: jsonEncode({
          'challengeId': serverStart['challengeId'],
          'finishLoginRequest': finished['finishLoginRequest'],
        }),
      ),
    );
    _ensure(finishResponse, {200});
    final result = _requireObject(_parse(finishResponse));
    final user = UserProfile.fromJson(result['user'] as Map<String, dynamic>);
    final masterKey = await AccountMasterKeyEnvelope.unwrap(
      exportKey: finished['exportKey'] as String,
      envelope: Map<String, dynamic>.from(result['wrappedAmk'] as Map),
      accountIdentifier: serverStart['clientIdentifier'] as String,
    );
    await _secureStorage.write(
      key: _opaquePinKey,
      value: finished['serverStaticPublicKey'] as String,
    );
    return LoginResult(
      result['accessToken'] as String,
      (result['expiresIn'] as num).toInt(),
      user,
      masterKey,
      serverStart['clientIdentifier'] as String,
      result['credentialChangeTicket'] as String,
    );
  }

  /// Re-enrolls the OPAQUE credential with a new password while keeping the
  /// existing AMK unchanged. Only its export-key wrapping is replaced.
  Future<CredentialChangeResult> changePassword({
    required String email,
    required String currentPassword,
    required String newPassword,
  }) async {
    if (currentPassword.isEmpty) {
      throw const AuthApiException('请输入当前密码');
    }
    final passwordValidation = passwordError(newPassword);
    if (passwordValidation != null) {
      throw AuthApiException(passwordValidation);
    }
    if (currentPassword == newPassword) {
      throw const AuthApiException('新密码不能与当前密码相同');
    }
    final normalized = normalizedEmail(email);

    // This fresh OPAQUE login verifies the current password, unwraps the
    // existing AMK locally, and returns a one-time credential-change ticket.
    // The ticket is kept only in this in-memory flow and is consumed by start.
    final current = await login(normalized, currentPassword);
    final started = await opaqueInvoke('registration.start', {
      'email': normalized,
      'password': newPassword,
    });

    final startResponse = await _call(
      () => _client.post(
        _uri('/api/v2/auth/credential/change/start'),
        headers: _headers(current.accessToken),
        body: jsonEncode({
          'registrationRequest': started['registrationRequest'],
          'credentialChangeTicket': current.credentialChangeTicket,
        }),
      ),
    );
    _ensure(startResponse, {200});
    final serverStart = _requireObject(_parse(startResponse));

    final pinnedKey = await _secureStorage.read(key: _opaquePinKey);
    if (serverStart['clientIdentifier'] != current.opaqueClientIdentifier) {
      throw const AuthApiException('账号 OPAQUE 标识发生变化，已拒绝修改密码');
    }
    if ((pinnedKey != null &&
            pinnedKey != serverStart['serverStaticPublicKey']) ||
        (_buildOpaqueServerPublicKey.isNotEmpty &&
            _buildOpaqueServerPublicKey != serverStart['serverStaticPublicKey'])) {
      throw const AuthApiException('OPAQUE 服务端公钥不匹配，已拒绝修改密码');
    }

    final finished = await opaqueInvoke('registration.finish', {
      'flowId': started['flowId'],
      'clientIdentifier': serverStart['clientIdentifier'],
      'registrationResponse': serverStart['registrationResponse'],
    });
    if (finished['serverStaticPublicKey'] != serverStart['serverStaticPublicKey'] ||
        (_buildOpaqueServerPublicKey.isNotEmpty &&
            finished['serverStaticPublicKey'] != _buildOpaqueServerPublicKey)) {
      throw const AuthApiException('OPAQUE 服务端公钥不一致，已拒绝修改密码');
    }

    final wrapped = await AccountMasterKeyEnvelope.wrap(
      exportKey: finished['exportKey'] as String,
      masterKey: current.accountMasterKey,
      accountIdentifier: current.opaqueClientIdentifier,
    );
    try {
      final finishResponse = await _call(
        () => _client.post(
          _uri('/api/v2/auth/credential/change/finish'),
          headers: _headers(current.accessToken),
          body: jsonEncode({
            'challengeId': serverStart['challengeId'],
            'registrationRecord': finished['registrationRecord'],
            'serverStaticPublicKey': finished['serverStaticPublicKey'],
            'wrappedAmk': wrapped,
          }),
        ),
      );
      _ensure(finishResponse, {200});
      final result = _requireObject(_parse(finishResponse));
      final accessToken = result['accessToken'];
      final expiresIn = result['expiresIn'];
      if (accessToken is! String || accessToken.isEmpty || expiresIn is! num) {
        throw const AuthApiException('密码修改响应格式不正确');
      }
      return CredentialChangeResult(accessToken, expiresIn.toInt());
    } catch (error, stackTrace) {
      // If the server committed the transaction but the response was lost,
      // verify the new password and recover a fresh token. If it did not
      // commit, this login fails and the original error is preserved.
      try {
        final recovered = await login(normalized, newPassword);
        return CredentialChangeResult(
          recovered.accessToken,
          recovered.expiresIn,
        );
      } catch (_) {
        Error.throwWithStackTrace(error, stackTrace);
      }
    }
  }

  Future<ForgotResult> forgotPassword(String email) async {
    throw const AuthApiException('V2 端到端加密账号需要可信设备或恢复材料才能重置密码；旧式邮件重置已停用');
  }

  Future<void> resetPassword({
    required String email,
    required String challengeId,
    required String code,
    required String newPassword,
  }) async {
    throw const AuthApiException('V2 端到端加密账号需要可信设备或恢复材料才能重置密码；旧式邮件重置已停用');
  }

  Future<UserProfile> me(String token) async {
    final res = await _call(
      () => _client.get(_uri('/api/v1/me'), headers: _headers(token)),
    );
    _ensure(res, {200});
    return UserProfile.fromJson(_requireObject(_parse(res)));
  }

  Future<UserProfile> updateProfile(
    String token, {
    required String username,
    required String gender,
    String? birthday,
  }) async {
    final res = await _call(
      () => _client.put(
        _uri('/api/v1/me'),
        headers: _headers(token),
        body: jsonEncode({
          'username': normalizedUsername(username),
          'gender': gender,
          'birthday': birthday,
        }),
      ),
    );
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
    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: picked.name),
    );
    try {
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 20));
      final res = await http.Response.fromStream(streamed);
      _ensure(res, {200});
      // Avatar endpoint returns {avatar: "..."}; re-fetch canonical profile.
      return await me(token);
    } on AuthApiException {
      rethrow;
    } catch (_) {
      throw const AuthApiException('头像上传失败，请检查网络');
    }
  }

  Future<UserProfile> deleteAvatar(String token) async {
    final res = await _call(
      () => _client.delete(_uri('/api/v1/me/avatar'), headers: _headers(token)),
    );
    _ensure(res, {204});
    return me(token);
  }

  Future<void> logout(String token) async {
    final res = await _call(
      () => _client.post(_uri('/api/v1/auth/logout'), headers: _headers(token)),
    );
    _ensure(res, {204});
  }

  /// Use for a Mod download route after login. If 401, ask the caller to sign in again.
  Future<http.Response> getWithToken(String path, String token) async {
    final res = await _call(
      () => _client.get(_uri(path), headers: _headers(token)),
    );
    _ensure(res, {200});
    return res;
  }

  /// 后端权威水滴：客户端不上传 userId、余额或奖励金额。
  Future<Map<String, dynamic>> getWaterStatus(String token) async {
    final res = await _call(
      () => _client.get(_uri('/api/v1/me/water'), headers: _headers(token)),
    );
    _ensure(res, {200});
    return _requireObject(_parse(res));
  }

  Future<Map<String, dynamic>> claimWater(String token) async {
    final res = await _call(
      () => _client.post(
        _uri('/api/v1/me/water/check-in'),
        headers: _headers(token),
      ),
    );
    _ensure(res, {200});
    return _requireObject(_parse(res));
  }

  Future<List<Map<String, dynamic>>> getWaterMonth(
    String token,
    int year,
    int month,
  ) async {
    final res = await _call(
      () => _client.get(
        _uri('/api/v1/me/water/check-ins?year=$year&month=$month'),
        headers: _headers(token),
      ),
    );
    _ensure(res, {200});
    final body = _parse(res);
    if (body is! List) throw const AuthApiException('签到列表格式不正确');
    return body.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  void dispose() => _client.close();
}
