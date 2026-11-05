import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plan_blind_box/data/local/local_database.dart';
import 'package:plan_blind_box/data/local/local_plan_repository.dart';
import 'package:plan_blind_box/services/mod_registry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

String manifest(String id, {String version = '1.0.0', List<String> dependencies = const [],
    bool template = false}) => jsonEncode({
  'schemaVersion': 1,
  'id': id,
  'name': '测试扩展',
  'version': version,
  'description': '测试',
  'dependencies': dependencies,
  'permissions': template ? ['tasks.create'] : <String>[],
  'taskTemplates': template ? [{'title': '阅读十页', 'targetCount': 10, 'importance': 3,
    'difficulty': 2}] : <dynamic>[],
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
    expect(registry.parseManifest(manifest('com.example.study'))['version'], '1.0.0');
    expect(() => registry.parseManifest(manifest('bad-id')), throwsFormatException);
    final unsafe = jsonDecode(manifest('com.example.unsafe')) as Map<String, dynamic>;
    unsafe['permissions'] = ['files.delete'];
    expect(() => registry.parseManifest(jsonEncode(unsafe)), throwsFormatException);
    unsafe['permissions'] = [];
    unsafe['entrypoint'] = 'malicious.dart';
    expect(() => registry.parseManifest(jsonEncode(unsafe)), throwsFormatException);
  });

  test('兼容性声明：旧版可用，高版本拒绝安装', () async {
    final old = manifest('com.example.compat');
    expect(registry.parseManifest(old)['id'], 'com.example.compat');
    final incompatible = jsonDecode(old) as Map<String, dynamic>;
    incompatible['minHostVersion'] = '999.0.0';
    expect(() => registry.parseManifest(jsonEncode(incompatible)), throwsFormatException);
    await expectLater(registry.install(jsonEncode(incompatible), grantedPermissions: {}),
        throwsFormatException);
    incompatible['minHostVersion'] = '0.1.0';
    await registry.install(jsonEncode(incompatible), grantedPermissions: {});
    expect((await registry.list()).single['minHostVersion'], '0.1.0');
  });

  test('安装、启停、卸载并记录审计', () async {
    await registry.install(manifest('com.example.a'), grantedPermissions: {});
    expect((await registry.list()).single['enabled'], true);
    await registry.setEnabled('com.example.a', false);
    expect((await registry.list()).single['enabled'], false);
    await registry.setEnabled('com.example.a', true);
    await registry.uninstall('com.example.a');
    expect(await registry.list(), isEmpty);
    expect((await registry.audit()).map((e) => e['action']),
        ['uninstall', 'enable', 'disable', 'install']);
  });

  test('依赖保护以及版本升级检查', () async {
    await registry.install(manifest('com.example.a'), grantedPermissions: {});
    await registry.install(manifest('com.example.b', dependencies: ['com.example.a']), grantedPermissions: {});
    await expectLater(registry.uninstall('com.example.a'), throwsStateError);
    await expectLater(registry.setEnabled('com.example.a', false), throwsStateError);
    await expectLater(registry.install(manifest('com.example.a'), grantedPermissions: {}), throwsFormatException);
    await registry.install(manifest('com.example.a', version: '1.1.0'), grantedPermissions: {});
    expect((await registry.list()).firstWhere((m) => m['id'] == 'com.example.a')['version'], '1.1.0');
    await expectLater(
      registry.install(manifest('com.example.a', version: '1.2.0',
        dependencies: ['com.example.b']), grantedPermissions: {}),
      throwsFormatException,
    );
  });

  test('任务模板必须授权且停用后不可用', () async {
    final source = manifest('com.example.study', template: true);
    await registry.install(source, grantedPermissions: {});
    expect(await registry.taskTemplates(), isEmpty);
    await registry.install(manifest('com.example.study', version: '1.0.1', template: true),
        grantedPermissions: {'tasks.create'});
    // The user explicitly granted new permissions during the upgrade.
    expect(await registry.taskTemplates(), hasLength(1));
    await registry.uninstall('com.example.study');
    await registry.install(source, grantedPermissions: {'tasks.create'});
    expect(await registry.taskTemplates(), hasLength(1));
    await registry.setEnabled('com.example.study', false);
    expect(await registry.taskTemplates(), isEmpty);
  });

  test('Mod 注册表随备份恢复、数据重置而变化', () async {
    await registry.install(manifest('com.example.a'), grantedPermissions: {});
    final backup = await repository.exportBackupJson();
    await repository.resetLocalData(resetPreferences: true);
    expect(await ModRegistry(repository).list(), isEmpty);
    await repository.restoreBackupJson(backup);
    expect(await ModRegistry(repository).list(), hasLength(1));
  });
}
