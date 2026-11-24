import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plan_blind_box/data/local/local_database.dart';
import 'package:plan_blind_box/data/local/local_plan_repository.dart';
import 'package:plan_blind_box/mod_platform/runtime/mod_capability_broker.dart';
import 'package:plan_blind_box/mod_platform/runtime/mod_runtime_manager.dart';
import 'package:plan_blind_box/mod_platform/runtime/mod_runtime_session.dart';
import 'package:plan_blind_box/mod_platform/storage/mod_platform_store.dart';
import 'package:plan_blind_box/services/mod_registry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

String _legacy({
  String id = 'com.example.study',
  String version = '1.0.0',
  bool template = true,
  List<String> dependencies = const [],
}) => jsonEncode({
  'schemaVersion': 1,
  'id': id,
  'name': '阅读挑战',
  'version': version,
  'description': '仅声明式任务模板',
  'permissions': template ? ['tasks.create'] : <String>[],
  'dependencies': dependencies,
  'taskTemplates': template
      ? [
          {
            'title': '今日阅读十页',
            'note': '复盘',
            'targetCount': 10,
            'importance': 3,
            'difficulty': 2,
          },
        ]
      : <Map<String, dynamic>>[],
});

void main() {
  late LocalDatabase db;
  late LocalPlanRepository repo;
  late ModRuntimeSessionManager sessions;
  late ModRegistry registry;
  late ModRuntimeManager runtime;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = LocalDatabase.forTesting(factory: databaseFactoryFfi);
    await db.initialize();
    repo = LocalPlanRepository(userId: 1, localDatabase: db);
    await repo.ensureReady();
    sessions = ModRuntimeSessionManager();
    registry = ModRegistry(repo, sessionManager: sessions);
    runtime = ModRuntimeManager.forRepository(repo, sessionManager: sessions);
  });
  tearDown(() async {
    runtime.shutdown();
    await db.close();
  });

  Future<void> install({bool grant = true}) => registry.install(
        _legacy(),
        grantedPermissions: grant ? {'tasks.create'} : <String>{},
      );

  test('声明式 Runtime 从安装记录加载任务模板，不执行 Host API', () async {
    await install();
    final templates = await runtime.listAvailableTaskTemplates();
    expect(templates, hasLength(1));
    expect(templates.single['title'], '今日阅读十页');
    expect(templates.single['templateIndex'], 0);
    final instance = await runtime.start('com.example.study');
    expect(runtime.isRunning(instance), isTrue);
    expect(instance.state, ModExecutionState.running);
    expect(instance.session.verifiedRuntime, isTrue);
    final payload = await runtime.taskPayload(instance, 0);
    expect(payload, {
      'title': '今日阅读十页',
      'note': '复盘',
      'targetCount': 10,
      'importance': 3,
      'difficulty': 2,
    });
    expect(await repo.getAllTasks(), isEmpty);
    runtime.stop(instance);
    expect(instance.state, ModExecutionState.stopped);
    expect(sessions.isActive(instance.session), isFalse);
  });

  test('没有平台管理员审核时 Runtime 不得直接创建宿主任务', () async {
    await install();
    final instance = await runtime.start('com.example.study');
    final broker = ModCapabilityBroker.forRepository(
      repo,
      sessionManager: sessions,
    );
    await expectLater(
      broker.issueUserConsent(
        session: instance.session,
        capability: 'host.tasks.create',
        payload: await runtime.taskPayload(instance, 0),
      ),
      throwsA(isA<ModCapabilityDeniedException>()),
    );
    expect(await repo.getAllTasks(), isEmpty);
  });

  test('撤销用户授权，正在运行的 Runtime 立刻失效', () async {
    await install();
    final instance = await runtime.start('com.example.study');
    await registry.revokePermission('com.example.study', 'tasks.create');
    expect(runtime.isRunning(instance), isFalse);
    await expectLater(runtime.taskPayload(instance, 0),
        throwsA(isA<ModRuntimeUnavailable>()));
    expect(await runtime.listAvailableTaskTemplates(), isEmpty);
  });

  test('暂停会立即回收 Session，恢复则必须重新验证安装', () async {
    await install();
    final instance = await runtime.start('com.example.study');
    final oldSession = instance.session;
    runtime.suspend(instance);
    expect(instance.state, ModExecutionState.suspended);
    expect(sessions.isActive(oldSession), isFalse);
    await expectLater(runtime.taskPayload(instance, 0),
        throwsA(isA<ModRuntimeUnavailable>()));
    await runtime.resume(instance);
    expect(instance.state, ModExecutionState.running);
    expect(sessions.isActive(instance.session), isTrue);
    expect(sessions.isActive(oldSession), isFalse);
    expect((await runtime.taskPayload(instance, 0))['title'], '今日阅读十页');
  });

  test('全局开关关闭时拒绝启动且不展示模板', () async {
    await install();
    await repo.setAppSetting('mods.enabled.v1', 'false');
    expect(await runtime.listAvailableTaskTemplates(), isEmpty);
    await expectLater(runtime.start('com.example.study'),
        throwsA(isA<ModRuntimeUnavailable>()));
  });

  test('旧版无授权时不展示可执行任务，不能获取创建任务内容', () async {
    await install(grant: false);
    expect(await runtime.listAvailableTaskTemplates(), isEmpty);
    final instance = await runtime.start('com.example.study');
    await expectLater(runtime.taskPayload(instance, 0),
        throwsA(isA<ModRuntimeUnavailable>()));
  });

  test('安装升级后旧版本 Runtime 内容不能再执行', () async {
    await install();
    final instance = await runtime.start('com.example.study');
    await registry.install(_legacy(version: '1.0.1'),
        grantedPermissions: {'tasks.create'});
    expect(runtime.isRunning(instance), isFalse);
    await expectLater(runtime.taskPayload(instance, 0),
        throwsA(isA<ModRuntimeUnavailable>()));
  });

  test('运行中禁用安装实例导致会话失效', () async {
    await install();
    final instance = await runtime.start('com.example.study');
    await registry.setEnabled('com.example.study', false);
    expect(runtime.isRunning(instance), isFalse);
    await expectLater(runtime.taskPayload(instance, 0),
        throwsA(isA<ModRuntimeUnavailable>()));
  });

  test('登录账号切换导致旧 Runtime 无法继续执行', () async {
    await install();
    final instance = await runtime.start('com.example.study');
    sessions.terminateOwner(repo.modOwnerId);
    expect(runtime.isRunning(instance), isFalse);
    await expectLater(runtime.taskPayload(instance, 0),
        throwsA(isA<ModRuntimeUnavailable>()));
  });

  test('依赖未启用则拒绝启动', () async {
    await registry.install(_legacy(id: 'com.example.base', template: false),
        grantedPermissions: {});
    await registry.install(_legacy(dependencies: ['com.example.base']),
        grantedPermissions: {'tasks.create'});
    final store = ModPlatformStore(database: db, ownerId: repo.modOwnerId);
    await store.setEnabled('com.example.base', false);
    expect(await runtime.listAvailableTaskTemplates(), isEmpty);
    await expectLater(runtime.start('com.example.study'),
        throwsA(isA<ModRuntimeUnavailable>()));
  });

  test('未经验证的 Manifest V1 content/ 不能仅凭 Manifest 启动', () async {
    final store = ModPlatformStore(database: db, ownerId: repo.modOwnerId);
    const raw = '{"manifestVersion":1,"id":"com.example.v1",'
        '"version":"1.0.0","runtime":{"type":"declarative",'
        '"entrypoint":"content/main.json"}}';
    await store.installOrUpgrade(
      modId: 'com.example.v1',
      publisherId: 'com.example.publisher',
      version: '1.0.0',
      manifestJson: raw,
      effectiveProfile: 'standalone_offline',
      grantedPermissions: {},
    );
    await expectLater(runtime.start('com.example.v1'),
        throwsA(isA<UnsupportedError>()));
  });

  test('Web/WASM 和混合运行时均不能执行', () async {
    final store = ModPlatformStore(database: db, ownerId: repo.modOwnerId);
    for (final kind in ['web', 'wasm']) {
      final id = 'com.example.$kind';
      final raw = jsonEncode({
        'manifestVersion': 1,
        'id': id,
        'version': '1.0.0',
        'type': 'app',
        'runtime': {'type': kind, 'entrypoint': '$kind/main'},
      });
      await store.installOrUpgrade(
        modId: id,
        publisherId: 'com.example.publisher',
        version: '1.0.0',
        manifestJson: raw,
        effectiveProfile: 'standalone_offline',
        grantedPermissions: {},
      );
      await expectLater(runtime.start(id), throwsA(isA<UnsupportedError>()));
    }
  });

  test('未声明 storage.local 的模板 Runtime 无法访问存储', () async {
    await install();
    final instance = await runtime.start('com.example.study');
    await expectLater(runtime.writeStorage(instance, 'state', {'coins': 1}),
        throwsStateError);
    await expectLater(runtime.readStorage(instance, 'state'), throwsStateError);
  });

  test('停止后不能复活同一个 Runtime，旧 handle 也不能关闭新实例', () async {
    await install();
    final old = await runtime.start('com.example.study');
    final current = await runtime.start('com.example.study');
    expect(runtime.isRunning(old), isFalse);
    runtime.stop(old);
    expect(runtime.isRunning(current), isTrue);
    runtime.shutdown();
    expect(runtime.isRunning(current), isFalse);
    await expectLater(runtime.start('com.example.study'),
        throwsA(isA<ModRuntimeUnavailable>()));
  });
}
