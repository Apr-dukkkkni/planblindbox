import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

import '../../auth/auth_session.dart';
import 'mod_permission_policy.dart';

class ModPlatformAuthorizationException implements Exception {
  const ModPlatformAuthorizationException(this.message, [this.statusCode]);

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Connects the local declarative Runtime to the authenticated MOD platform.
/// It never treats a successful HTTP response as proof by itself: the compact
/// JWS is verified locally with the platform Ed25519 public key and then
/// introspected online against the current server-side authorization state.
class PlatformProofApprovalProvider
    implements ModCapabilityProofApprovalProvider {
  PlatformProofApprovalProvider({
    required this.auth,
    http.Client? client,
    this.issuer = const String.fromEnvironment(
      'MOD_PLATFORM_PROOF_ISSUER',
      defaultValue: 'planblindbox-mod-server',
    ),
    DateTime Function()? clock,
  }) : _client = client ?? http.Client(),
       _clock = clock ?? DateTime.now;

  final AuthSession auth;
  final http.Client _client;
  final String issuer;
  final DateTime Function() _clock;
  bool _disposed = false;

  Future<void> grantCapability({
    required int ownerId,
    required String modId,
    required String version,
    required String capability,
    required String manifestSha256,
  }) async {
    _assertOwner(ownerId);
    _validateManifestDigest(manifestSha256);
    final response = await _send(
      'PUT',
      _capabilityPath(modId, version, capability),
      body: const {'granted': true},
    );
    _assertResponseContext(response, modId, version, capability);
    if (response['manifestSha256'] != manifestSha256) {
      throw const ModPlatformAuthorizationException('服务器授权记录与本地 Manifest 摘要不匹配');
    }
    if (response['userGranted'] != true) {
      throw const ModPlatformAuthorizationException('服务器未确认用户授权');
    }
  }

  Future<void> revokeCapability({
    required int ownerId,
    required String modId,
    required String version,
    required String capability,
    required String manifestSha256,
  }) async {
    _assertOwner(ownerId);
    _validateManifestDigest(manifestSha256);
    final response = await _send(
      'DELETE',
      _capabilityPath(modId, version, capability),
    );
    _assertResponseContext(response, modId, version, capability);
    if (response['manifestSha256'] != manifestSha256) {
      throw const ModPlatformAuthorizationException('服务器授权记录与本地 Manifest 摘要不匹配');
    }
    if (response['userGranted'] != false) {
      throw const ModPlatformAuthorizationException('服务器未确认撤销用户授权');
    }
  }

  @override
  Future<Set<String>> approvedCapabilities(ModApprovalRequest request) async {
    final proof = await issueAndVerifyProof(request);
    return proof == null ? const <String>{} : {request.capability};
  }

  @override
  Future<VerifiedModCapabilityProof?> issueAndVerifyProof(
    ModApprovalRequest request,
  ) async {
    _assertRequestOwner(request);
    final manifestSha256 = request.manifestSha256;
    if (manifestSha256 == null ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(manifestSha256)) {
      throw const ModPlatformAuthorizationException('本地安装缺少有效的 Manifest SHA-256');
    }

    final issued = await _send(
      'POST',
      '${_capabilityPath(request.modId, request.version, request.capability)}/proof',
      body: const <String, dynamic>{},
    );
    if (issued['proofType'] != 'MOD_CAPABILITY_AUTHORIZATION' ||
        issued['algorithm'] != 'EdDSA' ||
        issued['token'] is! String ||
        issued['keyId'] is! String ||
        issued['issuedAt'] is! num ||
        issued['expiresAt'] is! num) {
      throw const ModPlatformAuthorizationException('平台授权证明响应格式无效');
    }

    final token = issued['token'] as String;
    final claims = await _verifyCompactJws(token, request);
    final keyId = claims['kid'] as String;
    final issuedAt = _requiredInt(claims, 'iat');
    final expiresAt = _requiredInt(claims, 'exp');
    if (issued['keyId'] != keyId ||
        (issued['issuedAt'] as num).toInt() != issuedAt ||
        (issued['expiresAt'] as num).toInt() != expiresAt) {
      throw const ModPlatformAuthorizationException('授权证明响应元数据与 JWS 不一致');
    }

    await _verifyOnline(token, request, claims);
    return VerifiedModCapabilityProof(
      token: token,
      keyId: keyId,
      jti: claims['jti'] as String,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000, isUtc: true),
      ownerId: request.ownerId,
      installationId: request.installationId,
      sessionId: request.sessionId,
      modId: request.modId,
      publisherId: request.publisherId,
      version: request.version,
      packageSha256: request.packageSha256,
      manifestSha256: manifestSha256,
      capability: request.capability,
    );
  }

  @override
  Future<bool> verifyExistingProof(
    ModApprovalRequest request,
    VerifiedModCapabilityProof proof,
  ) async {
    _assertRequestOwner(request);
    if (!proof.matches(request) || !proof.expiresAt.isAfter(_clock().toUtc())) {
      return false;
    }
    final claims = await _verifyCompactJws(proof.token, request);
    if (claims['kid'] != proof.keyId || claims['jti'] != proof.jti ||
        _requiredInt(claims, 'exp') != proof.expiresAt.millisecondsSinceEpoch ~/ 1000) {
      return false;
    }
    await _verifyOnline(proof.token, request, claims);
    return true;
  }

  Future<Map<String, dynamic>> _verifyCompactJws(
    String token,
    ModApprovalRequest request,
  ) async {
    if (token.isEmpty || token.length > 16384) {
      throw const ModPlatformAuthorizationException('授权证明缺失或长度无效');
    }
    final parts = token.split('.');
    if (parts.length != 3 || parts.any((part) => part.isEmpty)) {
      throw const ModPlatformAuthorizationException('授权证明不是有效的 Compact JWS');
    }

    final header = _decodeObject(parts[0], 'JWS Header');
    if (header['alg'] != 'EdDSA' || header['typ'] != 'JWT' ||
        header['kid'] is! String ||
        header.keys.toSet().difference({'alg', 'typ', 'kid'}).isNotEmpty) {
      throw const ModPlatformAuthorizationException('授权证明签名头不受支持');
    }
    final keyId = header['kid'] as String;
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(keyId)) {
      throw const ModPlatformAuthorizationException('授权证明 kid 格式无效');
    }

    // Fetch key metadata every time. This deliberately avoids stale local key
    // caches when the platform performs an emergency key revocation.
    final metadata = await _send(
      'GET',
      '/api/v1/mod-platform/keys/${Uri.encodeComponent(keyId)}',
      authenticated: false,
    );
    if (metadata['keyId'] != keyId ||
        metadata['algorithm'] != 'Ed25519' ||
        metadata['format'] != 'X.509 SubjectPublicKeyInfo' ||
        metadata['canVerify'] != true ||
        !(const <String>{'ACTIVE', 'VERIFY_ONLY'}).contains(metadata['status']) ||
        metadata['publicKeyX509Base64'] is! String) {
      throw const ModPlatformAuthorizationException('平台签名公钥不可用于验证');
    }

    final der = base64.decode(metadata['publicKeyX509Base64'] as String);
    // Java's Ed25519 X.509 SubjectPublicKeyInfo encoding is the fixed
    // 12-byte ASN.1 prefix followed by the 32-byte raw Ed25519 public key.
    const x509Prefix = <int>[
      0x30, 0x2a, 0x30, 0x05, 0x06, 0x03,
      0x2b, 0x65, 0x70, 0x03, 0x21, 0x00,
    ];
    if (der.length != 44 ||
        !_startsWithBytes(der, x509Prefix) ||
        crypto.sha256.convert(der).toString() != keyId) {
      throw const ModPlatformAuthorizationException('平台公钥编码或 SHA-256 指纹无效');
    }

    final rawPublicKey = SimplePublicKey(
      Uint8List.fromList(der.sublist(x509Prefix.length)),
      type: KeyPairType.ed25519,
    );
    final signatureBytes = _decodeBase64Url(parts[2]);
    if (signatureBytes.length != 64) {
      throw const ModPlatformAuthorizationException('Ed25519 签名长度无效');
    }
    final signature = Signature(signatureBytes, publicKey: rawPublicKey);
    final signingInput = ascii.encode('${parts[0]}.${parts[1]}');
    final valid = await Ed25519().verify(
      signingInput,
      signature: signature,
    );
    if (!valid) {
      throw const ModPlatformAuthorizationException('平台授权证明签名验证失败');
    }

    final claims = _decodeObject(parts[1], 'JWS Payload');
    if (claims['iss'] != issuer ||
        claims['aud'] != 'planblindbox-mod-capability' ||
        claims['proofType'] != 'MOD_CAPABILITY_AUTHORIZATION' ||
        claims['proofVersion'] != 1 ||
        claims['sub'] != _userId.toString() ||
        claims['modId'] != request.modId ||
        claims['version'] != request.version ||
        claims['publisherId'] != request.publisherId ||
        claims['manifestSha256'] != request.manifestSha256 ||
        claims['capability'] != request.capability ||
        claims['adminApproved'] != true ||
        claims['userGranted'] != true ||
        claims['packageEnabled'] != true) {
      throw const ModPlatformAuthorizationException('授权证明与当前用户、安装版本或权限范围不匹配');
    }
    final publisherKeyId = claims['publisherKeyId'];
    if (publisherKeyId is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(publisherKeyId)) {
      throw const ModPlatformAuthorizationException('授权证明缺少有效 Publisher Key ID');
    }
    for (final revision in const [
      'approvalRevision', 'grantRevision', 'packageRevision',
    ]) {
      if (_requiredInt(claims, revision) < 1) {
        throw ModPlatformAuthorizationException('授权证明版本字段无效：$revision');
      }
    }

    final issuedAt = _requiredInt(claims, 'iat');
    final notBefore = _requiredInt(claims, 'nbf');
    final expiresAt = _requiredInt(claims, 'exp');
    final now = _clock().toUtc().millisecondsSinceEpoch ~/ 1000;
    if (issuedAt > now + 30 || notBefore > now + 30 ||
        expiresAt <= now || expiresAt <= issuedAt ||
        expiresAt - issuedAt > 900) {
      throw const ModPlatformAuthorizationException('授权证明尚未生效、已经过期或有效期异常');
    }
    final jti = claims['jti'];
    if (jti is! String || jti.isEmpty || jti.length > 128) {
      throw const ModPlatformAuthorizationException('授权证明缺少有效 jti');
    }
    claims['kid'] = keyId;
    return claims;
  }

  Future<void> _verifyOnline(
    String token,
    ModApprovalRequest request,
    Map<String, dynamic> claims,
  ) async {
    final result = await _send(
      'POST',
      '/api/v1/me/mod-capability-proofs/verify',
      body: {
        'token': token,
        'modId': request.modId,
        'version': request.version,
        'capability': request.capability,
      },
    );
    if (result['active'] != true ||
        result['proofType'] != 'MOD_CAPABILITY_AUTHORIZATION' ||
        result['modId'] != request.modId ||
        result['version'] != request.version ||
        result['capability'] != request.capability ||
        result['manifestSha256'] != request.manifestSha256 ||
        result['publisherId'] != request.publisherId ||
        result['jti'] != claims['jti'] ||
        (result['expiresAt'] as num?)?.toInt() != _requiredInt(claims, 'exp')) {
      throw const ModPlatformAuthorizationException('服务端当前授权状态验证失败');
    }
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = true,
  }) async {
    if (_disposed) throw const ModPlatformAuthorizationException('授权客户端已关闭');
    final uri = _uri(path);
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
      if (authenticated) 'Authorization': 'Bearer ${_requireToken()}',
    };
    late http.Response response;
    final encodedBody = body == null ? null : jsonEncode(body);
    try {
      switch (method) {
        case 'GET':
          response = await _client.get(uri, headers: headers)
              .timeout(const Duration(seconds: 12));
          break;
        case 'POST':
          response = await _client.post(uri, headers: headers, body: encodedBody ?? '{}')
              .timeout(const Duration(seconds: 12));
          break;
        case 'PUT':
          response = await _client.put(uri, headers: headers, body: encodedBody ?? '{}')
              .timeout(const Duration(seconds: 12));
          break;
        case 'DELETE':
          response = await _client.delete(uri, headers: headers)
              .timeout(const Duration(seconds: 12));
          break;
        default:
          throw ArgumentError.value(method, 'method', 'Unsupported HTTP method');
      }
    } on ModPlatformAuthorizationException {
      rethrow;
    } catch (_) {
      throw const ModPlatformAuthorizationException('MOD 平台连接失败，已按拒绝处理');
    }

    Object? decoded;
    if (response.bodyBytes.isNotEmpty) {
      try {
        decoded = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {
        decoded = null;
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map
          ? (decoded['message'] ?? decoded['detail'] ?? decoded['error'])?.toString()
          : null;
      throw ModPlatformAuthorizationException(
        message?.isNotEmpty == true
            ? message!
            : 'MOD 平台请求失败：HTTP ${response.statusCode}',
        response.statusCode,
      );
    }
    if (decoded is! Map) {
      throw const ModPlatformAuthorizationException('MOD 平台响应不是 JSON 对象');
    }
    return Map<String, dynamic>.from(decoded);
  }

  Uri _uri(String path) {
    final base = Uri.tryParse(auth.api.baseUrl);
    if (base == null || !base.hasScheme ||
        (base.scheme != 'http' && base.scheme != 'https') || base.host.isEmpty) {
      throw const ModPlatformAuthorizationException('未配置有效的 MOD 平台 API 地址');
    }
    final normalizedBase = auth.api.baseUrl.replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$normalizedBase$path');
  }

  String _capabilityPath(String modId, String version, String capability) =>
      '/api/v1/me/mods/${Uri.encodeComponent(modId)}/versions/'
      '${Uri.encodeComponent(version)}/capabilities/${Uri.encodeComponent(capability)}';

  String _requireToken() {
    final token = auth.token;
    if (!auth.isSignedIn || token == null || token.isEmpty || auth.user == null) {
      throw const ModPlatformAuthorizationException('使用宿主在线能力需要先登录 PlanBlindBox 账号', 401);
    }
    return token;
  }

  int get _userId {
    _requireToken();
    return auth.user!.userId;
  }

  void _validateManifestDigest(String value) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
      throw const ModPlatformAuthorizationException('本地 Manifest SHA-256 格式无效');
    }
  }

  void _assertOwner(int ownerId) {
    final expectedOwnerId = -1000000 - _userId;
    if (ownerId != expectedOwnerId) {
      throw const ModPlatformAuthorizationException('当前登录账号与本地 MOD 数据分区不匹配');
    }
  }

  void _assertRequestOwner(ModApprovalRequest request) {
    _assertOwner(request.ownerId);
    if (request.sessionId.isEmpty || request.installationId.isEmpty ||
        request.publisherId.isEmpty || request.modId.isEmpty ||
        request.version.isEmpty || request.capability.isEmpty) {
      throw const ModPlatformAuthorizationException('MOD 授权请求上下文不完整');
    }
  }

  void _assertResponseContext(
    Map<String, dynamic> response,
    String modId,
    String version,
    String capability,
  ) {
    if (response['modId'] != modId || response['version'] != version ||
        response['capability'] != capability) {
      throw const ModPlatformAuthorizationException('服务端授权状态与本地 MOD 上下文不匹配');
    }
  }

  Map<String, dynamic> _decodeObject(String encoded, String label) {
    try {
      final bytes = _decodeBase64Url(encoded);
      final value = jsonDecode(utf8.decode(bytes));
      if (value is! Map) throw const FormatException('not an object');
      return Map<String, dynamic>.from(value);
    } catch (_) {
      throw ModPlatformAuthorizationException('$label 格式无效');
    }
  }

  Uint8List _decodeBase64Url(String value) => Uint8List.fromList(
    base64Url.decode(base64Url.normalize(value)),
  );

  bool _startsWithBytes(List<int> bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) return false;
    }
    return true;
  }

  int _requiredInt(Map<String, dynamic> claims, String key) {
    final value = claims[key];
    if (value is! num || value.toInt() != value) {
      throw ModPlatformAuthorizationException('授权证明字段无效：$key');
    }
    return value.toInt();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _client.close();
  }
}
