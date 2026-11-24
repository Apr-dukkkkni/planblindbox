import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plan_blind_box/data/local/local_database.dart';
import 'package:plan_blind_box/data/local/local_plan_repository.dart';
import 'package:plan_blind_box/mod_platform/runtime/mod_capability_broker.dart';
import 'package:plan_blind_box/mod_platform/runtime/mod_runtime_session.dart';
import 'package:plan_blind_box/mod_platform/storage/mod_platform_store.dart';
import 'package:plan_blind_box/services/mod_registry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FailingApprovalProvider implements ModApprovalProvider {
  @override
  Future<Set<String>> approvedCapabilities(ModApprovalRequest request) async {
    throw StateError('approval service unavailable');
  }
}

class _ApprovedHostTaskProvider implements ModApprovalProvider {
  @override
  Future<Set<String>> approvedCapabilities(ModApprovalRequest request) async {
    if (request.publisherId != 'local.legacy' &&
        request.publisherId != 'publisher.example') {
      return const <String>{};
    }
    return const {'host.tasks.create'};
  }
}

String _legacyManifest({String id = 'com.example.template', String version = '1.0.0'}) => jsonEncode({
  'schemaVersion': 1,
  'id': id,
  'name': '测试任务模板',
  'version': version,
  'description': '用于 Broker 测试',
  'permissions': ['tasks.create'],
  'dependencies': <String>[],
  'taskTemplates': [
    {
      'title': '阅读十页',
      'note': '由模板创建',
      'targetCount': 10,
      'importance': 3,
      'difficulty': 2,
    }
  ],
});

void main() {
  late LocalDatabase database;
  late LocalPlanRepository repository;
  late ModRuntimeSessionManager sessions;
  late ModRegistry registry;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    database = LocalDatabase.forTesting(factory: databaseFactoryFfi);
    await database.initialize();
    repository = LocalPlanRepository(userId: 1, localDatabase: database);
    await repository.ensureReady();
    sessions = ModRuntimeSessionManager();
    registry = ModRegistry(repository, sessionManager: sessions);
    await registry.install(
      _legacyManifest(),
      grantedPermissions: {'tasks.create'},
    );
  });

  tearDown(() async => database.close());

  ModCapabilityBroker broker({
    ModApprovalProvider approvalProvider = const DenyAllModApprovalProvider(),
    Future<bool> Function()? globalModsEnabled,
  }) => ModCapabilityBroker.forRepository(
    repository,
    approvalProvider: approvalProvider,
    sessionManager: sessions,
    globalModsEnabled: globalModsEnabled,
  );

  test('任务创建必须通过 Broker，返回最小结果并记录元数据审计', () async {
    final capabilityBroker = broker(
      approvalProvider: _ApprovedHostTaskProvider(),
    );
    final session = await capabilityBroker.openSession('com.example.template');
    final payload = const {
      'title': '阅读十页',
      'note': '由模板创建',
      'targetCount': 10,
      'importance': 3,
      'difficulty': 2,
    };
    final consent = await capabilityBroker.issueUserConsent(
      session: session,
      capability: 'host.tasks.create',
      payload: payload,
    );
    final result = await capabilityBroker.invoke(
      session: session,
      capability: 'host.tasks.create',
      payload: payload,
      consent: consent,
    );

    expect(result.status, 'created');
    expect(result.requestId.length, 32);
    final tasks = await repository.getAllTasks();
    expect(tasks, hasLength(1));
    expect(tasks.single['title'], '阅读十页');

    final audit = await registry.audit();
    expect(audit.first['action'], 'capability_invoke');
    expect(audit.first['capability'], 'host.tasks.create');
    expect(audit.first['result'], 'success');

    final db = await database.database;
    final rawAudit = await db.query('mod_audit_events', limit: 1);
    expect(rawAudit.single['detail_json'], '{}');
    expect(rawAudit.single.containsKey('task_title'), false);
  });

  test('没有平台管理员审批时默认拒绝，即使用户已经授权', () async {
    final capabilityBroker = broker();
    final session = await capabilityBroker.openSession('com.example.template');

    await expectLater(
      capabilityBroker.issueUserConsent(
        session: session,
        capability: 'host.tasks.create',
        payload: const {
          'title': '阅读十页', 'note': '由模板创建', 'targetCount': 10,
          'importance': 3, 'difficulty': 2,
        },
      ),
      throwsA(isA<ModCapabilityDeniedException>()),
    );
    expect(await repository.getAllTasks(), isEmpty);
    expect((await registry.audit()).first['result'], 'denied');
  });

  test('管理员审批服务不可用时按拒绝处理', () async {
    final capabilityBroker = broker(
      approvalProvider: _FailingApprovalProvider(),
    );
    final session = await capabilityBroker.openSession('com.example.template');
    await expectLater(
      capabilityBroker.issueUserConsent(
        session: session,
        capability: 'host.tasks.create',
        payload: const {
          'title': '阅读十页', 'note': '由模板创建', 'targetCount': 10,
          'importance': 3, 'difficulty': 2,
        },
      ),
      throwsA(isA<ModCapabilityDeniedException>()),
    );
    expect(await repository.getAllTasks(), isEmpty);
  });

  test('用户确认凭据只能使用一次', () async {
    final capabilityBroker = broker(
      approvalProvider: _ApprovedHostTaskProvider(),
    );
    final session = await capabilityBroker.openSession('com.example.template');
    final payload = const {
      'title': '阅读十页',
      'note': '由模板创建',
      'targetCount': 10,
      'importance': 3,
      'difficulty': 2,
    };
    final consent = await capabilityBroker.issueUserConsent(
      session: session,
      capability: 'host.tasks.create',
      payload: payload,
    );

    await capabilityBroker.invoke(
      session: session,
      capability: 'host.tasks.create',
      payload: payload,
      consent: consent,
    );
    await expectLater(
      capabilityBroker.invoke(
        session: session,
        capability: 'host.tasks.create',
        payload: payload,
        consent: consent,
      ),
      throwsA(isA<ModCapabilityDeniedException>()),
    );
    expect(await repository.getAllTasks(), hasLength(1));
  });

  test('禁用 MOD 会立即终止 Runtime Session', () async {
    final capabilityBroker = broker(
      approvalProvider: _ApprovedHostTaskProvider(),
    );
    final session = await capabilityBroker.openSession('com.example.template');
    await registry.setEnabled('com.example.template', false);

    await expectLater(
      capabilityBroker.issueUserConsent(
        session: session,
        capability: 'host.tasks.create',
        payload: const {
          'title': '阅读十页', 'note': '由模板创建', 'targetCount': 10,
          'importance': 3, 'difficulty': 2,
        },
      ),
      throwsA(isA<ModCapabilityDeniedException>()),
    );
    expect(await repository.getAllTasks(), isEmpty);
  });

  test('账号切换/登出清理所有进程内 Session', () async {
    final capabilityBroker = broker(
      approvalProvider: _ApprovedHostTaskProvider(),
    );
    final session = await capabilityBroker.openSession('com.example.template');
    sessions.terminateAll();

    await expectLater(
      capabilityBroker.issueUserConsent(
        session: session,
        capability: 'host.tasks.create',
        payload: const {
          'title': '阅读十页', 'note': '由模板创建', 'targetCount': 10,
          'importance': 3, 'difficulty': 2,
        },
      ),
      throwsA(isA<ModCapabilityDeniedException>()),
    );
  });

  test('全局 MOD 开关关闭时不能创建 Session', () async {
    final capabilityBroker = broker(
      approvalProvider: _ApprovedHostTaskProvider(),
      globalModsEnabled: () async => false,
    );
    await expectLater(
      capabilityBroker.openSession('com.example.template'),
      throwsA(isA<ModCapabilityDeniedException>()),
    );
  });

  test('Host API 严格拒绝额外字段，不允许传入 categoryId 或 recordRule', () async {
    final capabilityBroker = broker(
      approvalProvider: _ApprovedHostTaskProvider(),
    );
    final session = await capabilityBroker.openSession('com.example.template');
    final payload = const {
      'title': '阅读十页',
      'note': '由模板创建',
      'targetCount': 10,
      'importance': 3,
      'difficulty': 2,
      'categoryId': 999,
    };
    final consent = await capabilityBroker.issueUserConsent(
      session: session,
      capability: 'host.tasks.create',
      payload: payload,
    );

    await expectLater(
      capabilityBroker.invoke(
        session: session,
        capability: 'host.tasks.create',
        payload: payload,
        consent: consent,
      ),
      throwsFormatException,
    );
    expect(await repository.getAllTasks(), isEmpty);
  });

  test('只允许声明式 Runtime；web/wasm Runtime 当前拒绝启动', () async {
    final store = ModPlatformStore(
      database: database,
      ownerId: repository.modOwnerId,
    );
    const raw = '''{
      "manifestVersion":1,
      "id":"com.example.webapp",
      "version":"1.0.0",
      "name":{"zh-CN":"网页扩展"},
      "publisher":{"id":"publisher.example"},
      "type":"content",
      "contentKind":"task_template",
      "runtime":{"type":"web","apiVersion":"1","entrypoint":"web/index.html"},
      "permissions":[{"capability":"host.tasks.create","required":true,"reason":"测试"}]
    }''';
    await store.installOrUpgrade(
      modId: 'com.example.webapp',
      publisherId: 'publisher.example',
      version: '1.0.0',
      manifestJson: raw,
      effectiveProfile: 'host_integrated_offline',
      grantedPermissions: {'host.tasks.create'},
    );

    final capabilityBroker = broker(
      approvalProvider: _ApprovedHostTaskProvider(),
    );
    await expectLater(
      capabilityBroker.openSession('com.example.webapp'),
      throwsA(isA<ModCapabilityDeniedException>()),
    );
  });

  test('Host API 原子复核安装启用状态和用户授权', () async {
    final db = await database.database;
    final installation = (await registry.list()).single;
    await db.update(
      'mod_permission_grants',
      {'revoked_at': DateTime.now().toUtc().toIso8601String()},
      where: 'installation_id=?',
      whereArgs: [installation['installationId']],
    );

    // The repository-side transaction guard independently rejects a stale
    // authorization even if a caller bypasses the in-memory policy check.
    await expectLater(
      repository.createTaskFromMod(
        installationId: installation['installationId'] as String,
        modId: 'com.example.template',
        isSessionActive: () => true,
        title: '不应创建',
        note: '',
        targetCount: 1,
        importance: 3,
        difficulty: 3,
      ),
      throwsStateError,
    );
    expect(await repository.getAllTasks(), isEmpty);
  });
  test('用户确认的模板不能被替换成 MOD 自行编造的任务', () async {
    final capabilityBroker = broker(
      approvalProvider: _ApprovedHostTaskProvider(),
    );
    final session = await capabilityBroker.openSession('com.example.template');
    final confirmedPayload = const {
      'title': '阅读十页',
      'note': '由模板创建',
      'targetCount': 10,
      'importance': 3,
      'difficulty': 2,
    };
    final consent = await capabilityBroker.issueUserConsent(
      session: session,
      capability: 'host.tasks.create',
      payload: confirmedPayload,
    );
    await expectLater(
      capabilityBroker.invoke(
        session: session,
        capability: 'host.tasks.create',
        payload: const {
          'title': '偷偷创建的其他任务',
          'note': '不是已声明模板',
          'targetCount': 1,
          'importance': 3,
          'difficulty': 3,
        },
        consent: consent,
      ),
      throwsA(isA<ModCapabilityDeniedException>()),
    );
    expect(await repository.getAllTasks(), isEmpty);
  });

  test('Broker 不会为 Manifest 未声明的任务内容签发用户确认凭据', () async {
    final capabilityBroker = broker(
      approvalProvider: _ApprovedHostTaskProvider(),
    );
    final session = await capabilityBroker.openSession('com.example.template');
    await expectLater(
      capabilityBroker.issueUserConsent(
        session: session,
        capability: 'host.tasks.create',
        payload: const {
          'title': '任意新增任务',
          'note': '',
          'targetCount': 1,
          'importance': 3,
          'difficulty': 3,
        },
      ),
      throwsA(isA<ModCapabilityDeniedException>()),
    );
    expect(await repository.getAllTasks(), isEmpty);
  });

  test('SQLite 写入事务内再次检查 Session，有效期失效时回滚', () async {
    final installation = (await registry.list()).single;
    await expectLater(
      repository.createTaskFromMod(
        installationId: installation['installationId'] as String,
        modId: 'com.example.template',
        isSessionActive: () => false,
        title: '阅读十页',
        note: '由模板创建',
        targetCount: 10,
        importance: 3,
        difficulty: 2,
      ),
      throwsStateError,
    );
    expect(await repository.getAllTasks(), isEmpty);
  });

  test('SQLite 写入事务内再次检查全局 MOD 开关', () async {
    final installation = (await registry.list()).single;
    await repository.setAppSetting('mods.enabled.v1', 'false');
    await expectLater(
      repository.createTaskFromMod(
        installationId: installation['installationId'] as String,
        modId: 'com.example.template',
        isSessionActive: () => true,
        title: '阅读十页',
        note: '由模板创建',
        targetCount: 10,
        importance: 3,
        difficulty: 2,
      ),
      throwsStateError,
    );
    expect(await repository.getAllTasks(), isEmpty);
  });

  test('撤权、升级和卸载都会终止旧 Runtime Session', () async {
    final capabilityBroker = broker(
      approvalProvider: _ApprovedHostTaskProvider(),
    );
    final revokeSession = await capabilityBroker.openSession('com.example.template');
    await registry.revokePermission('com.example.template', 'tasks.create');
    expect(sessions.isActive(revokeSession), isFalse);

    // Reinstall/upgrade with explicit grant, then prove upgrade kills old session.
    await registry.install(
      _legacyManifest(version: '1.0.1'),
      grantedPermissions: {'tasks.create'},
    );
    final upgradeSession = await capabilityBroker.openSession('com.example.template');
    await registry.install(
      _legacyManifest(version: '1.0.2'),
      grantedPermissions: {'tasks.create'},
    );
    expect(sessions.isActive(upgradeSession), isFalse);

    final uninstallSession = await capabilityBroker.openSession('com.example.template');
    await registry.uninstall('com.example.template');
    expect(sessions.isActive(uninstallSession), isFalse);
  });

}
