import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plan_blind_box/data/local/local_database.dart';
import 'package:plan_blind_box/data/local/local_plan_repository.dart';
import 'package:plan_blind_box/mod_platform/runtime/mod_capability_broker.dart';
import 'package:plan_blind_box/mod_platform/runtime/mod_permission_policy.dart';
import 'package:plan_blind_box/mod_platform/manifest/mod_manifest_v1_validator.dart';
import 'package:plan_blind_box/mod_platform/runtime/mod_runtime_session.dart';
import 'package:plan_blind_box/services/mod_registry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _ApprovedProvider implements ModApprovalProvider {
  @override
  Future<Set<String>> approvedCapabilities(ModApprovalRequest request) async =>
      request.publisherId == 'publisher.example'
          ? const {'host.tasks.create'}
          : const <String>{};
}


class _ProofProvider implements ModCapabilityProofApprovalProvider {
  bool allowExistingProof;
  int issueCount = 0;
  int verifyCount = 0;

  _ProofProvider({this.allowExistingProof = true});

  @override
  Future<Set<String>> approvedCapabilities(ModApprovalRequest request) async =>
      const <String>{};

  @override
  Future<VerifiedModCapabilityProof?> issueAndVerifyProof(
    ModApprovalRequest request,
  ) async {
    issueCount++;
    return VerifiedModCapabilityProof(
      token: 'test-platform-jws',
      keyId: ''.padLeft(64, 'c'),
      jti: 'test-jti',
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
      ownerId: request.ownerId,
      installationId: request.installationId,
      sessionId: request.sessionId,
      modId: request.modId,
      publisherId: request.publisherId,
      version: request.version,
      packageSha256: request.packageSha256,
      manifestSha256: request.manifestSha256!,
      capability: request.capability,
    );
  }

  @override
  Future<bool> verifyExistingProof(
    ModApprovalRequest request,
    VerifiedModCapabilityProof proof,
  ) async {
    verifyCount++;
    return allowExistingProof && proof.matches(request);
  }
}

void main() {
  late LocalDatabase database;
  late LocalPlanRepository repository;
  late ModRegistry registry;
  late ModRuntimeSessionManager sessions;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    database = LocalDatabase.forTesting(factory: databaseFactoryFfi);
    await database.initialize();
    repository = LocalPlanRepository(userId: 1, localDatabase: database);
    await repository.ensureReady();
    sessions = ModRuntimeSessionManager();
    registry = ModRegistry(repository, sessionManager: sessions);
  });

  tearDown(() => database.close());

  Future<void> installV1() async {
    final manifest = {
      'manifestVersion': 1,
      'id': 'com.example.v1permission',
      'version': '1.0.0',
      'name': {'zh-CN': 'V1 任务模板'},
      'description': 'permission flow test',
      'publisher': {'id': 'publisher.example'},
      'type': 'content',
      'contentKind': 'task_template',
      'runtime': {
        'type': 'declarative',
        'apiVersion': '1',
        'entrypoint': 'content/task-templates.json',
      },
      'compatibility': {
        'hostApi': '^1.0.0',
        'platforms': ['android'],
      },
      'ui': {
        'allowedModes': ['modal'],
        'defaultMode': 'modal',
      },
      'storage': {
        'local': {
          'enabled': false,
          'quotaMiB': 0,
          'persistent': false,
        },
      },
      'permissions': [
        {
          'capability': 'host.tasks.create',
          'required': true,
          'reason': '创建任务',
        },
      ],
      'dependencies': <String>[],
    };
    // Fail at fixture setup if this test ever drifts from the strict V1 schema.
    ModManifestV1Validator().parse(jsonEncode(manifest));
    final store = registry;
    // Persist the same host-owned projection produced by installV1Package.
    final db = await repository.localDatabase.database;
    final ownerId = repository.modOwnerId;
    final storageNamespace = 'test-v1-namespace';
    await db.insert('mod_storage_metadata', {
      'storage_namespace': storageNamespace,
      'owner_id': ownerId,
      'mod_id': 'com.example.v1permission',
      'publisher_id': 'publisher.example',
      'effective_profile': 'host_integrated_offline',
      'quota_bytes': 0,
      'used_bytes': 0,
      'data_format_version': 1,
      'retained': 0,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    final projection = <String, dynamic>{
      'schemaVersion': 1,
      'manifestVersion': 1,
      'isV1Package': true,
      'runtimeReady': false,
      'id': manifest['id'],
      'name': 'V1 任务模板',
      'nameLocales': manifest['name'],
      'version': manifest['version'],
      'description': manifest['description'],
      'publisher': manifest['publisher'],
      'permissions': manifest['permissions'],
      'declaredPermissions': ['host.tasks.create'],
      'dependencies': <String>[],
      'taskTemplates': [
        {
          'title': '阅读十页',
          'note': '由 V1 模板声明',
          'targetCount': 10,
          'importance': 3,
          'difficulty': 2,
        },
      ],
      'contentKind': manifest['contentKind'],
      'runtime': manifest['runtime'],
      'packageDirectory': '/test/com.example.v1permission',
      'packageSha256': ''.padLeft(64, 'b'),
      'fileDigests': <String, String>{'manifest.json': ''.padLeft(64, 'a')},
      'sourceManifest': manifest,
    };
    await db.insert('mod_installations', {
      'installation_id': 'test-v1-installation',
      'owner_id': ownerId,
      'mod_id': 'com.example.v1permission',
      'publisher_id': 'publisher.example',
      'version': '1.0.0',
      'manifest_json': jsonEncode(projection),
      'package_sha256': ''.padLeft(64, 'b'),
      'effective_profile': 'host_integrated_offline',
      'status': 'installed',
      'enabled': 0,
      'storage_namespace': storageNamespace,
      'installed_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    // Keep the local variable meaningful so this helper follows the same
    // account-scoped registry used by the production flow.
    expect(store.ownerId, ownerId);
  }

  test('V1 用户授权后可启用；管理员审批和二次确认仍是独立关卡', () async {
    await installV1();
    await registry.grantPermission(
      'com.example.v1permission',
      'host.tasks.create',
    );

    final broker = ModCapabilityBroker.forRepository(
      repository,
      approvalProvider: _ApprovedProvider(),
      sessionManager: sessions,
    );
    final session = sessions.open(
      ownerId: repository.modOwnerId,
      installationId: 'test-v1-installation',
      modId: 'com.example.v1permission',
      verifiedRuntime: true,
    );
    final payload = const {
      'title': '阅读十页',
      'note': '由 V1 模板声明',
      'targetCount': 10,
      'importance': 3,
      'difficulty': 2,
    };

    final consent = await broker.issueUserConsent(
      session: session,
      capability: 'host.tasks.create',
      payload: payload,
    );
    final result = await broker.invoke(
      session: session,
      capability: 'host.tasks.create',
      payload: payload,
      consent: consent,
    );

    expect(result.status, 'created');
    expect((await repository.getAllTasks()).single['title'], '阅读十页');
  });


  test('V1 即使用户已授权，缺少平台管理员审批也不能创建任务', () async {
    await installV1();
    await registry.grantPermission(
      'com.example.v1permission',
      'host.tasks.create',
    );

    final broker = ModCapabilityBroker.forRepository(
      repository,
      sessionManager: sessions,
    );
    final session = sessions.open(
      ownerId: repository.modOwnerId,
      installationId: 'test-v1-installation',
      modId: 'com.example.v1permission',
      verifiedRuntime: true,
    );

    await expectLater(
      broker.issueUserConsent(
        session: session,
        capability: 'host.tasks.create',
        payload: const {
          'title': '阅读十页',
          'note': '由 V1 模板声明',
          'targetCount': 10,
          'importance': 3,
          'difficulty': 2,
        },
      ),
      throwsA(isA<ModCapabilityDeniedException>()),
    );
    expect(await repository.getAllTasks(), isEmpty);
  });

  test('V1 未经验证的 Session 不能绕过 Declarative Runtime 调用 Host API', () async {
    await installV1();
    await registry.grantPermission(
      'com.example.v1permission',
      'host.tasks.create',
    );

    final broker = ModCapabilityBroker.forRepository(
      repository,
      approvalProvider: _ApprovedProvider(),
      sessionManager: sessions,
    );
    final session = sessions.open(
      ownerId: repository.modOwnerId,
      installationId: 'test-v1-installation',
      modId: 'com.example.v1permission',
    );

    await expectLater(
      broker.issueUserConsent(
        session: session,
        capability: 'host.tasks.create',
        payload: const {
          'title': '阅读十页',
          'note': '由 V1 模板声明',
          'targetCount': 10,
          'importance': 3,
          'difficulty': 2,
        },
      ),
      throwsA(isA<ModCapabilityDeniedException>()),
    );
    expect(await repository.getAllTasks(), isEmpty);
  });


  test('V1 撤销用户授权后立即终止 Session，旧凭据不能继续调用', () async {
    await installV1();
    await registry.grantPermission(
      'com.example.v1permission',
      'host.tasks.create',
    );
    final broker = ModCapabilityBroker.forRepository(
      repository,
      approvalProvider: _ApprovedProvider(),
      sessionManager: sessions,
    );
    final session = sessions.open(
      ownerId: repository.modOwnerId,
      installationId: 'test-v1-installation',
      modId: 'com.example.v1permission',
      verifiedRuntime: true,
    );
    final payload = const {
      'title': '阅读十页',
      'note': '由 V1 模板声明',
      'targetCount': 10,
      'importance': 3,
      'difficulty': 2,
    };
    final consent = await broker.issueUserConsent(
      session: session,
      capability: 'host.tasks.create',
      payload: payload,
    );
    await registry.revokePermission(
      'com.example.v1permission',
      'host.tasks.create',
    );
    expect(sessions.isActive(session), isFalse);
    await expectLater(
      broker.invoke(
        session: session,
        capability: 'host.tasks.create',
        payload: payload,
        consent: consent,
      ),
      throwsA(isA<ModCapabilityDeniedException>()),
    );
    expect(await repository.getAllTasks(), isEmpty);
  });

  test('V1 Host API 只能创建包内声明的模板，不能自由编造任务', () async {
    await installV1();
    await registry.grantPermission(
      'com.example.v1permission',
      'host.tasks.create',
    );

    final broker = ModCapabilityBroker.forRepository(
      repository,
      approvalProvider: _ApprovedProvider(),
      sessionManager: sessions,
    );
    final session = sessions.open(
      ownerId: repository.modOwnerId,
      installationId: 'test-v1-installation',
      modId: 'com.example.v1permission',
      verifiedRuntime: true,
    );

    await expectLater(
      broker.issueUserConsent(
        session: session,
        capability: 'host.tasks.create',
        payload: const {
          'title': '偷偷创建的任务',
          'note': '',
          'targetCount': 1,
          'importance': 1,
          'difficulty': 1,
        },
      ),
      throwsA(isA<ModCapabilityDeniedException>()),
    );
    expect(await repository.getAllTasks(), isEmpty);
  });

  test('V1 Host API 在确认时签发 Session 绑定证明，执行前再次在线验证', () async {
    await installV1();
    await registry.grantPermission(
      'com.example.v1permission',
      'host.tasks.create',
    );
    final proofProvider = _ProofProvider();
    final broker = ModCapabilityBroker.forRepository(
      repository,
      approvalProvider: proofProvider,
      sessionManager: sessions,
    );
    final session = sessions.open(
      ownerId: repository.modOwnerId,
      installationId: 'test-v1-installation',
      modId: 'com.example.v1permission',
      verifiedRuntime: true,
    );
    const payload = {
      'title': '阅读十页',
      'note': '由 V1 模板声明',
      'targetCount': 10,
      'importance': 3,
      'difficulty': 2,
    };

    final consent = await broker.issueUserConsent(
      session: session,
      capability: 'host.tasks.create',
      payload: payload,
    );
    expect(consent.proof, isNotNull);
    expect(proofProvider.issueCount, 1);
    expect(proofProvider.verifyCount, 0);

    final result = await broker.invoke(
      session: session,
      capability: 'host.tasks.create',
      payload: payload,
      consent: consent,
    );
    expect(result.status, 'created');
    expect(proofProvider.issueCount, 1);
    expect(proofProvider.verifyCount, 1);
    expect(await repository.getAllTasks(), hasLength(1));
  });

  test('确认后若平台在线复核发现撤权，Host API 不写入本地任务', () async {
    await installV1();
    await registry.grantPermission(
      'com.example.v1permission',
      'host.tasks.create',
    );
    final proofProvider = _ProofProvider();
    final broker = ModCapabilityBroker.forRepository(
      repository,
      approvalProvider: proofProvider,
      sessionManager: sessions,
    );
    final session = sessions.open(
      ownerId: repository.modOwnerId,
      installationId: 'test-v1-installation',
      modId: 'com.example.v1permission',
      verifiedRuntime: true,
    );
    const payload = {
      'title': '阅读十页',
      'note': '由 V1 模板声明',
      'targetCount': 10,
      'importance': 3,
      'difficulty': 2,
    };
    final consent = await broker.issueUserConsent(
      session: session,
      capability: 'host.tasks.create',
      payload: payload,
    );
    proofProvider.allowExistingProof = false;

    await expectLater(
      broker.invoke(
        session: session,
        capability: 'host.tasks.create',
        payload: payload,
        consent: consent,
      ),
      throwsA(isA<ModCapabilityDeniedException>()),
    );
    expect(proofProvider.issueCount, 1);
    expect(proofProvider.verifyCount, 1);
    expect(await repository.getAllTasks(), isEmpty);
  });

}
