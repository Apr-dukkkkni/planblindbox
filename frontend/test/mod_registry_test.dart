import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plan_blind_box/data/local/local_database.dart';
import 'package:plan_blind_box/data/local/local_plan_repository.dart';
import 'package:plan_blind_box/mod_platform/storage/mod_platform_store.dart';
import 'package:plan_blind_box/services/mod_registry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

String manifest(
  String id, {
  String version = '1.0.0',
  List<String> dependencies = const [],
  bool template = false,
}) => jsonEncode({
  'schemaVersion': 1,
  'id': id,
  'name': '测试扩展',
  'version': version,
  'description': '测试',
  'dependencies': dependencies,
  'permissions': template ? ['tasks.create'] : <String>[],
  'taskTemplates': template
      ? [
          {
            'title': '阅读十页',
            'targetCount': 10,
            'importance': 3,
            'difficulty': 2,
          }
        ]
      : <dynamic>[],
});

void main() {
  late LocalDatabase database;
  late LocalPlanRepository repository;
  late ModRegistry registry;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    database = LocalDatabase.forTesting(factory: databaseFactoryFfi);
    await database.initialize();
    repository = LocalPlanRepository(userId: 1, localDatabase: database);
    await repository.ensureReady();
    registry = ModRegistry(repository);
  });
  tearDown(() async => database.close());

  test('清单参数校验和权限白名单', () {
    expect(
      registry.parseManifest(manifest('com.example.study'))['version'],
      '1.0.0',
    );
    expect(
      () => registry.parseManifest(manifest('bad-id')),
      throwsFormatException,
    );
    final unsafe = jsonDecode(manifest('com.example.unsafe'))
        as Map<String, dynamic>;
    unsafe['permissions'] = ['files.delete'];
    expect(
      () => registry.parseManifest(jsonEncode(unsafe)),
      throwsFormatException,
    );
    unsafe['permissions'] = [];
    unsafe['entrypoint'] = 'malicious.dart';
    expect(
      () => registry.parseManifest(jsonEncode(unsafe)),
      throwsFormatException,
    );
  });

  test('兼容性声明：旧版可用，高版本拒绝安装', () async {
    final old = manifest('com.example.compat');
    expect(registry.parseManifest(old)['id'], 'com.example.compat');
    final incompatible =
        jsonDecode(old) as Map<String, dynamic>;
    incompatible['minHostVersion'] = '999.0.0';
    expect(
      () => registry.parseManifest(jsonEncode(incompatible)),
      throwsFormatException,
    );
    await expectLater(
      registry.install(jsonEncode(incompatible), grantedPermissions: {}),
      throwsFormatException,
    );
    incompatible['minHostVersion'] = '0.1.0';
    await registry.install(
      jsonEncode(incompatible),
      grantedPermissions: {},
    );
    expect(
      (await registry.list()).single['minHostVersion'],
      '0.1.0',
    );
  });

  test('安装、启停、卸载并记录审计', () async {
    await registry.install(
      manifest('com.example.a'),
      grantedPermissions: {},
    );
    expect((await registry.list()).single['enabled'], true);
    await registry.setEnabled('com.example.a', false);
    expect((await registry.list()).single['enabled'], false);
    await registry.setEnabled('com.example.a', true);
    await registry.uninstall('com.example.a');
    expect(await registry.list(), isEmpty);
    expect(
      (await registry.audit()).map((e) => e['action']),
      ['uninstall_delete_data', 'enable', 'disable', 'install'],
    );
  });

  test('依赖保护以及版本升级检查', () async {
    await registry.install(
      manifest('com.example.a'),
      grantedPermissions: {},
    );
    await registry.install(
      manifest('com.example.b', dependencies: ['com.example.a']),
      grantedPermissions: {},
    );
    await expectLater(
      registry.uninstall('com.example.a'),
      throwsStateError,
    );
    await expectLater(
      registry.setEnabled('com.example.a', false),
      throwsStateError,
    );
    await expectLater(
      registry.install(
        manifest('com.example.a'),
        grantedPermissions: {},
      ),
      throwsFormatException,
    );
    await registry.install(
      manifest('com.example.a', version: '1.1.0'),
      grantedPermissions: {},
    );
    expect(
      (await registry.list())
          .firstWhere((m) => m['id'] == 'com.example.a')['version'],
      '1.1.0',
    );
    await expectLater(
      registry.install(
        manifest(
          'com.example.a',
          version: '1.2.0',
          dependencies: ['com.example.b'],
        ),
        grantedPermissions: {},
      ),
      throwsFormatException,
    );
  });

  test('升级时不会隐式继承旧权限', () async {
    await registry.install(
      manifest('com.example.study', template: true),
      grantedPermissions: {'tasks.create'},
    );
    expect(
      (await registry.list()).single['grantedPermissions'],
      ['tasks.create'],
    );

    await registry.install(
      manifest(
        'com.example.study',
        version: '1.0.1',
        template: true,
      ),
      grantedPermissions: {},
    );

    final installed = (await registry.list()).single;
    expect(installed['grantedPermissions'], isEmpty);
    expect(installed['enabled'], true);
    expect(await registry.taskTemplates(), isEmpty);
  });

  test('任务模板必须授权且停用后不可用', () async {
    final source = manifest('com.example.study', template: true);
    await registry.install(source, grantedPermissions: {});
    expect(await registry.taskTemplates(), isEmpty);

    await registry.install(
      manifest(
        'com.example.study',
        version: '1.0.1',
        template: true,
      ),
      grantedPermissions: {'tasks.create'},
    );
    expect(await registry.taskTemplates(), hasLength(1));

    await registry.uninstall('com.example.study');
    await registry.install(
      source,
      grantedPermissions: {'tasks.create'},
    );
    expect(await registry.taskTemplates(), hasLength(1));

    await registry.setEnabled('com.example.study', false);
    expect(await registry.taskTemplates(), isEmpty);
  });

  test('撤销权限会禁用 MOD 并立即移除有效授权', () async {
    await registry.install(
      manifest('com.example.study', template: true),
      grantedPermissions: {'tasks.create'},
    );
    await registry.revokePermission('com.example.study', 'tasks.create');

    final installed = (await registry.list()).single;
    expect(installed['enabled'], false);
    expect(installed['grantedPermissions'], isEmpty);
    expect(await registry.taskTemplates(), isEmpty);
    expect(
      (await registry.audit()).first['action'],
      'permission_revoke',
    );
  });

  test('备份恢复保留 MOD 数据但不恢复安装授权', () async {
    await registry.install(
      manifest('com.example.backup'),
      grantedPermissions: {},
    );
    final backup = await repository.exportBackupJson();
    final decoded = jsonDecode(backup) as Map<String, dynamic>;
    final tables = decoded['tables'] as Map<String, dynamic>;

    expect(tables.containsKey('mod_installations'), true);
    expect(tables.containsKey('mod_permission_grants'), false);
    expect(tables.containsKey('mod_audit_events'), false);
    expect(
      (tables['app_settings'] as List)
          .where((row) => (row as Map)['setting_key'] == 'mods.registry.v1'),
      isEmpty,
    );

    await repository.resetLocalData(resetPreferences: true);
    expect(await registry.list(), isEmpty);

    await repository.restoreBackupJson(backup);
    final restored = (await registry.list()).single;
    expect(restored['status'], 'requires_reauthorization');
    expect(restored['enabled'], false);
    expect(restored['grantedPermissions'], isEmpty);
    expect(await registry.taskTemplates(), isEmpty);

    await expectLater(
      registry.setEnabled('com.example.backup', true),
      throwsStateError,
    );

    // Reinstalling the restored version is treated as a fresh authorization.
    await registry.install(
      manifest('com.example.backup'),
      grantedPermissions: {},
    );
    final reinstalled = (await registry.list()).single;
    expect(reinstalled['status'], 'installed');
    expect(reinstalled['enabled'], true);
  });

  test('安装记录与 MOD 存储按账号隔离，重置不影响其他账号', () async {
    final secondRepository = LocalPlanRepository(
      userId: 2,
      localDatabase: database,
    );
    await secondRepository.ensureReady();
    final secondRegistry = ModRegistry(secondRepository);

    await registry.install(
      manifest('com.example.shared'),
      grantedPermissions: {},
    );
    await secondRegistry.install(
      manifest('com.example.shared'),
      grantedPermissions: {},
    );

    expect(await registry.list(), hasLength(1));
    expect(await secondRegistry.list(), hasLength(1));
    expect(
      (await registry.list()).single['storageNamespace'],
      isNot((await secondRegistry.list()).single['storageNamespace']),
    );

    await repository.resetLocalData(resetPreferences: true);
    expect(await registry.list(), isEmpty);
    expect(await secondRegistry.list(), hasLength(1));
  });

  test('卸载保留数据后，同 Publisher/Profile 重新安装可恢复 MOD 自有数据', () async {
    final store = ModPlatformStore(database: database, ownerId: 1);
    const raw = '{"id":"com.example.farm","version":"1.0.0"}';

    await store.installOrUpgrade(
      modId: 'com.example.farm',
      publisherId: 'com.example.publisher',
      version: '1.0.0',
      manifestJson: raw,
      effectiveProfile: 'standalone_offline',
      grantedPermissions: {'storage.local'},
      storageQuotaBytes: 4096,
    );
    await store.writeStorageValue(
      'com.example.farm',
      'farm.state',
      {'coins': 42, 'crop': 'carrot'},
    );

    await store.uninstall('com.example.farm', keepData: true);
    expect(await store.listInstallations(), isEmpty);

    await store.installOrUpgrade(
      modId: 'com.example.farm',
      publisherId: 'com.example.publisher',
      version: '1.0.0',
      manifestJson: raw,
      effectiveProfile: 'standalone_offline',
      grantedPermissions: {'storage.local'},
      storageQuotaBytes: 4096,
    );

    expect(
      await store.readStorageValue('com.example.farm', 'farm.state'),
      {'coins': 42, 'crop': 'carrot'},
    );
    expect(
      (await store.listInstallations()).single['grantedPermissions'],
      ['storage.local'],
    );
  });

  test('Profile 改变时创建新存储空间，不跨 Profile 读取旧数据', () async {
    final store = ModPlatformStore(database: database, ownerId: 1);
    const rawOffline = '{"id":"com.example.farm","version":"1.0.0"}';
    const rawIntegrated = '{"id":"com.example.farm","version":"1.1.0"}';

    await store.installOrUpgrade(
      modId: 'com.example.farm',
      publisherId: 'com.example.publisher',
      version: '1.0.0',
      manifestJson: rawOffline,
      effectiveProfile: 'standalone_offline',
      grantedPermissions: {'storage.local'},
      storageQuotaBytes: 4096,
    );
    await store.writeStorageValue(
      'com.example.farm',
      'farm.state',
      {'coins': 42},
    );

    await store.installOrUpgrade(
      modId: 'com.example.farm',
      publisherId: 'com.example.publisher',
      version: '1.1.0',
      manifestJson: rawIntegrated,
      effectiveProfile: 'host_integrated_offline',
      grantedPermissions: {'host.tasks.create', 'storage.local'},
      storageQuotaBytes: 4096,
    );

    expect(
      await store.readStorageValue('com.example.farm', 'farm.state'),
      isNull,
    );
  });

  test('MOD 本地存储配额按 UTF-8 字节数执行', () async {
    final store = ModPlatformStore(database: database, ownerId: 1);
    const raw = '{"id":"com.example.storage","version":"1.0.0"}';
    await store.installOrUpgrade(
      modId: 'com.example.storage',
      publisherId: 'com.example.publisher',
      version: '1.0.0',
      manifestJson: raw,
      effectiveProfile: 'standalone_offline',
      grantedPermissions: {'storage.local'},
      storageQuotaBytes: 12,
    );
    await store.writeStorageValue('com.example.storage', 'a', '123');
    await expectLater(
      store.writeStorageValue('com.example.storage', 'b', '超过配额'),
      throwsStateError,
    );
  });
  test('备份恢复 standalone MOD 自有数据，但授权必须重新授予', () async {
    final store = ModPlatformStore(database: database, ownerId: repository.modOwnerId);
    const raw = '{"id":"com.example.localdata","version":"1.0.0"}';
    await store.installOrUpgrade(
      modId: 'com.example.localdata',
      publisherId: 'com.example.publisher',
      version: '1.0.0',
      manifestJson: raw,
      effectiveProfile: 'standalone_offline',
      grantedPermissions: {'storage.local'},
      storageQuotaBytes: 4096,
    );
    await store.writeStorageValue(
      'com.example.localdata',
      'state',
      {'score': 9},
    );

    final backup = await repository.exportBackupJson();
    await repository.resetLocalData(resetPreferences: true);
    await repository.restoreBackupJson(backup);

    final restoredStore = ModPlatformStore(database: database, ownerId: repository.modOwnerId);
    final restored = (await restoredStore.listInstallations()).single;
    expect(restored['status'], 'requires_reauthorization');
    expect(restored['enabled'], false);
    expect(restored['grantedPermissions'], isEmpty);
    await expectLater(
      restoredStore.readStorageValue('com.example.localdata', 'state'),
      throwsStateError,
    );

    await restoredStore.installOrUpgrade(
      modId: 'com.example.localdata',
      publisherId: 'com.example.publisher',
      version: '1.0.0',
      manifestJson: raw,
      effectiveProfile: 'standalone_offline',
      grantedPermissions: {'storage.local'},
      storageQuotaBytes: 4096,
    );
    expect(
      await restoredStore.readStorageValue('com.example.localdata', 'state'),
      {'score': 9},
    );
  });

  test('host_integrated_offline 的 MOD 本地存储不会进入用户备份', () async {
    final store = ModPlatformStore(database: database, ownerId: repository.modOwnerId);
    const raw = '{"id":"com.example.hostbound","version":"1.0.0"}';
    await store.installOrUpgrade(
      modId: 'com.example.hostbound',
      publisherId: 'com.example.publisher',
      version: '1.0.0',
      manifestJson: raw,
      effectiveProfile: 'host_integrated_offline',
      grantedPermissions: {'storage.local', 'host.tasks.create'},
      storageQuotaBytes: 4096,
    );
    await store.writeStorageValue(
      'com.example.hostbound',
      'cached',
      {'possiblyCopiedHostData': 'not-exported'},
    );

    final backup = jsonDecode(await repository.exportBackupJson())
        as Map<String, dynamic>;
    final tables = backup['tables'] as Map<String, dynamic>;
    expect(tables['mod_storage_entries'], isEmpty);
    final metadata = (tables['mod_storage_metadata'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((row) => row['mod_id'] == 'com.example.hostbound');
    expect(metadata['used_bytes'], 0);
  });

  test('v7 备份可恢复到 v8，缺失的 MOD 表按空数据处理', () async {
    final backup = jsonDecode(await repository.exportBackupJson())
        as Map<String, dynamic>;
    backup['databaseVersion'] = 7;
    final tables = backup['tables'] as Map<String, dynamic>;
    tables.remove('mod_storage_metadata');
    tables.remove('mod_storage_entries');
    tables.remove('mod_installations');

    await expectLater(
      repository.restoreBackupJson(jsonEncode(backup)),
      completes,
    );
    expect(await database.database.then((db) => db.getVersion()), 8);
  });

  test('持久化边界拒绝宿主业务权限与外发权限混用', () async {
    final store = ModPlatformStore(database: database, ownerId: 1);
    const raw = '{"id":"com.example.policy","version":"1.0.0"}';

    await expectLater(
      store.installOrUpgrade(
        modId: 'com.example.policy',
        publisherId: 'com.example.publisher',
        version: '1.0.0',
        manifestJson: raw,
        effectiveProfile: 'host_integrated_offline',
        grantedPermissions: {'host.tasks.create', 'network.fetch'},
      ),
      throwsFormatException,
    );
    await expectLater(
      store.installOrUpgrade(
        modId: 'com.example.policy',
        publisherId: 'com.example.publisher',
        version: '1.0.0',
        manifestJson: raw,
        effectiveProfile: 'standalone_networked',
        grantedPermissions: {'host.tasks.create'},
      ),
      throwsFormatException,
    );
    await expectLater(
      store.installOrUpgrade(
        modId: 'com.example.policy',
        publisherId: 'com.example.publisher',
        version: '1.0.0',
        manifestJson: raw,
        effectiveProfile: 'standalone_offline',
        grantedPermissions: {'host.tasks.create'},
      ),
      throwsFormatException,
    );
    expect(await store.listInstallations(), isEmpty);
  });

}
