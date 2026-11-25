import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plan_blind_box/auth/auth_api.dart';
import 'package:plan_blind_box/auth/auth_session.dart';
import 'package:plan_blind_box/mod_platform/runtime/mod_permission_policy.dart';
import 'package:plan_blind_box/mod_platform/runtime/platform_proof_approval_provider.dart';

class _TestAuthSession extends AuthSession {
  _TestAuthSession()
      : super(
          AuthApi(
            baseUrl: 'https://mods.example',
            client: MockClient((_) async => http.Response('{}', 200)),
          ),
        ) {
    state = LoginState.signedIn;
    user = const UserProfile(
      userId: 42,
      username: 'test-user',
      email: 'test@example.invalid',
      gender: 'UNKNOWN',
    );
  }

  @override
  String? get token => 'test-access-token';

  @override
  bool get isSignedIn => true;
}

void main() {
  const issuer = 'planblindbox-mod-server';
  const modId = 'com.example.proof';
  const version = '1.2.3';
  const publisherId = 'publisher.example';
  const capability = 'host.tasks.create';
  const manifestSha256 = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const packageSha256 = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  const userId = 42;
  const ownerId = -1000042;
  const x509Prefix = <int>[
    0x30, 0x2a, 0x30, 0x05, 0x06, 0x03,
    0x2b, 0x65, 0x70, 0x03, 0x21, 0x00,
  ];

  late _TestAuthSession auth;
  late Ed25519 algorithm;
  late KeyPair keyPair;
  late String keyId;
  late String publicKeyX509Base64;
  late String token;
  late int issuedAt;
  late int expiresAt;
  late DateTime clockNow;
  late ModApprovalRequest request;

  Future<String> makeToken({bool tamperSignature = false}) async {
    final header = {
      'alg': 'EdDSA',
      'typ': 'JWT',
      'kid': keyId,
    };
    final payload = {
      'iss': issuer,
      'aud': 'planblindbox-mod-capability',
      'proofType': 'MOD_CAPABILITY_AUTHORIZATION',
      'proofVersion': 1,
      'sub': '$userId',
      'modId': modId,
      'version': version,
      'manifestSha256': manifestSha256,
      'publisherId': publisherId,
      'publisherKeyId': 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
      'capability': capability,
      'adminApproved': true,
      'userGranted': true,
      'packageEnabled': true,
      'approvalRevision': 1,
      'grantRevision': 2,
      'packageRevision': 3,
      'iat': issuedAt,
      'nbf': issuedAt,
      'exp': expiresAt,
      'jti': 'test-proof-jti',
    };
    String encode(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final encodedHeader = encode(header);
    final encodedPayload = encode(payload);
    final signingInput = '$encodedHeader.$encodedPayload';
    final signature = await algorithm.sign(
      ascii.encode(signingInput),
      keyPair: keyPair,
    );
    final signatureBytes = signature.bytes.toList();
    if (tamperSignature) signatureBytes[0] ^= 0x01;
    final encodedSignature =
        base64Url.encode(signatureBytes).replaceAll('=', '');
    return '$signingInput.$encodedSignature';
  }

  Map<String, dynamic> keyMetadata({String status = 'ACTIVE'}) => {
        'keyId': keyId,
        'algorithm': 'Ed25519',
        'format': 'X.509 SubjectPublicKeyInfo',
        'publicKeyX509Base64': publicKeyX509Base64,
        'status': status,
        'canVerify': status != 'REVOKED',
        'canSign': status == 'ACTIVE',
      };

  http.Response jsonResponse(Map<String, dynamic> body, [int status = 200]) =>
      http.Response(
        jsonEncode(body),
        status,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );

  setUp(() async {
    auth = _TestAuthSession();
    algorithm = Ed25519();
    keyPair = await algorithm.newKeyPair();
    final publicKey =
    await keyPair.extractPublicKey() as SimplePublicKey;
    final der = <int>[...x509Prefix, ...publicKey.bytes];
    keyId = crypto.sha256.convert(der).toString();
    publicKeyX509Base64 = base64.encode(der);
    clockNow = DateTime.utc(2026, 11, 20, 12);
    issuedAt = clockNow.millisecondsSinceEpoch ~/ 1000;
    expiresAt = issuedAt + 300;
    token = await makeToken();
    request = const ModApprovalRequest(
      ownerId: ownerId,
      installationId: 'install-1',
      sessionId: 'session-1',
      modId: modId,
      publisherId: publisherId,
      version: version,
      packageSha256: packageSha256,
      manifestSha256: manifestSha256,
      capability: capability,
    );
  });

  tearDown(() {
    auth.api.dispose();
    auth.dispose();
  });

  test('签发证明后本地 Ed25519 验签并在线复核，证明绑定当前 Session', () async {
    var keyFetches = 0;
    var onlineVerifications = 0;
    final client = MockClient((http.Request req) async {
      if (req.method != 'GET') {
        expect(req.headers['authorization'], 'Bearer test-access-token');
      } else {
        expect(req.headers.containsKey('authorization'), isFalse);
      }
      if (req.method == 'POST' && req.url.path.endsWith('/proof')) {
        return jsonResponse({
          'proofType': 'MOD_CAPABILITY_AUTHORIZATION',
          'algorithm': 'EdDSA',
          'keyId': keyId,
          'token': token,
          'issuedAt': issuedAt,
          'expiresAt': expiresAt,
        });
      }
      if (req.method == 'GET' && req.url.path.endsWith('/$keyId')) {
        keyFetches++;
        return jsonResponse(keyMetadata(status: 'VERIFY_ONLY'));
      }
      if (req.method == 'POST' &&
          req.url.path == '/api/v1/me/mod-capability-proofs/verify') {
        onlineVerifications++;
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['token'], token);
        expect(body['modId'], modId);
        expect(body['version'], version);
        expect(body['capability'], capability);
        return jsonResponse({
          'active': true,
          'proofType': 'MOD_CAPABILITY_AUTHORIZATION',
          'modId': modId,
          'version': version,
          'capability': capability,
          'manifestSha256': manifestSha256,
          'publisherId': publisherId,
          'expiresAt': expiresAt,
          'jti': 'test-proof-jti',
        });
      }
      return jsonResponse({'message': 'unexpected request'}, 404);
    });
    final provider = PlatformProofApprovalProvider(
      auth: auth,
      client: client,
      clock: () => clockNow,
    );
    addTearDown(provider.dispose);

    final proof = await provider.issueAndVerifyProof(request);
    expect(proof, isNotNull);
    expect(proof!.sessionId, 'session-1');
    expect(proof.installationId, 'install-1');
    expect(proof.manifestSha256, manifestSha256);
    expect(keyFetches, 1);
    expect(onlineVerifications, 1);

    expect(await provider.verifyExistingProof(request, proof), isTrue);
    expect(keyFetches, 2);
    expect(onlineVerifications, 2);

    final otherSession = ModApprovalRequest(
      ownerId: request.ownerId,
      installationId: request.installationId,
      sessionId: 'session-2',
      modId: request.modId,
      publisherId: request.publisherId,
      version: request.version,
      packageSha256: request.packageSha256,
      manifestSha256: request.manifestSha256,
      capability: request.capability,
    );
    expect(await provider.verifyExistingProof(otherSession, proof), isFalse);
    expect(onlineVerifications, 2);
  });

  test('篡改 JWS 签名时拒绝，不调用在线验证接口', () async {
    final tampered = await makeToken(tamperSignature: true);
    final client = MockClient((http.Request req) async {
      if (req.method == 'POST' && req.url.path.endsWith('/proof')) {
        return jsonResponse({
          'proofType': 'MOD_CAPABILITY_AUTHORIZATION',
          'algorithm': 'EdDSA',
          'keyId': keyId,
          'token': tampered,
          'issuedAt': issuedAt,
          'expiresAt': expiresAt,
        });
      }
      if (req.method == 'GET' && req.url.path.endsWith('/$keyId')) {
        return jsonResponse(keyMetadata());
      }
      fail('invalid JWS must not reach online verification');
    });
    final provider = PlatformProofApprovalProvider(
      auth: auth,
      client: client,
      clock: () => clockNow,
    );
    addTearDown(provider.dispose);

    await expectLater(
      provider.issueAndVerifyProof(request),
      throwsA(isA<ModPlatformAuthorizationException>()),
    );
  });

  test('平台密钥吊销或服务端实时授权失效时拒绝证明', () async {
    final revokedKeyClient = MockClient((http.Request req) async {
      if (req.method == 'POST' && req.url.path.endsWith('/proof')) {
        return jsonResponse({
          'proofType': 'MOD_CAPABILITY_AUTHORIZATION',
          'algorithm': 'EdDSA',
          'keyId': keyId,
          'token': token,
          'issuedAt': issuedAt,
          'expiresAt': expiresAt,
        });
      }
      if (req.method == 'GET') {
        return jsonResponse({'message': 'revoked'}, 410);
      }
      fail('revoked key must stop verification');
    });
    final revokedProvider = PlatformProofApprovalProvider(
      auth: auth,
      client: revokedKeyClient,
      clock: () => clockNow,
    );
    addTearDown(revokedProvider.dispose);
    await expectLater(
      revokedProvider.issueAndVerifyProof(request),
      throwsA(isA<ModPlatformAuthorizationException>()),
    );

    final inactiveClient = MockClient((http.Request req) async {
      if (req.method == 'POST' && req.url.path.endsWith('/proof')) {
        return jsonResponse({
          'proofType': 'MOD_CAPABILITY_AUTHORIZATION',
          'algorithm': 'EdDSA',
          'keyId': keyId,
          'token': token,
          'issuedAt': issuedAt,
          'expiresAt': expiresAt,
        });
      }
      if (req.method == 'GET') return jsonResponse(keyMetadata());
      if (req.method == 'POST' &&
          req.url.path == '/api/v1/me/mod-capability-proofs/verify') {
        return jsonResponse({'active': false, 'message': 'revoked'}, 403);
      }
      fail('unexpected request');
    });
    final inactiveProvider = PlatformProofApprovalProvider(
      auth: auth,
      client: inactiveClient,
      clock: () => clockNow,
    );
    addTearDown(inactiveProvider.dispose);
    await expectLater(
      inactiveProvider.issueAndVerifyProof(request),
      throwsA(isA<ModPlatformAuthorizationException>()),
    );
  });

  test('用户授权和撤权都使用当前登录账号的 Bearer Token', () async {
    final methods = <String>[];
    final client = MockClient((http.Request req) async {
      methods.add(req.method);
      expect(req.headers['authorization'], 'Bearer test-access-token');
      if (req.method == 'PUT') {
        expect(jsonDecode(req.body), {'granted': true});
        return jsonResponse({
          'modId': modId,
          'version': version,
          'capability': capability,
          'manifestSha256': manifestSha256,
          'userGranted': true,
        });
      }
      if (req.method == 'DELETE') {
        return jsonResponse({
          'modId': modId,
          'version': version,
          'capability': capability,
          'manifestSha256': manifestSha256,
          'userGranted': false,
        });
      }
      fail('unexpected request method');
    });
    final provider = PlatformProofApprovalProvider(auth: auth, client: client);
    addTearDown(provider.dispose);

    await provider.grantCapability(
      ownerId: ownerId,
      modId: modId,
      version: version,
      capability: capability,
      manifestSha256: manifestSha256,
    );
    await provider.revokeCapability(
      ownerId: ownerId,
      modId: modId,
      version: version,
      capability: capability,
      manifestSha256: manifestSha256,
    );
    expect(methods, ['PUT', 'DELETE']);

    await expectLater(
      provider.grantCapability(
        ownerId: -1,
        modId: modId,
        version: version,
        capability: capability,
        manifestSha256: manifestSha256,
      ),
      throwsA(isA<ModPlatformAuthorizationException>()),
    );
  });
}
