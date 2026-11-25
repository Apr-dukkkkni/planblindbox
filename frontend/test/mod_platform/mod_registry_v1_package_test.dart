import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plan_blind_box/data/local/local_database.dart';
import 'package:plan_blind_box/data/local/local_plan_repository.dart';
import 'package:plan_blind_box/mod_platform/package/mod_package_models.dart';
import 'package:plan_blind_box/mod_platform/runtime/mod_runtime_manager.dart';
import 'package:plan_blind_box/mod_platform/runtime/mod_runtime_session.dart';
import 'package:plan_blind_box/services/mod_registry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late LocalDatabase database;
  late LocalPlanRepository repository;
  late ModRegistry registry;
  late ModRuntimeManager runtime;
  late ModRuntimeSessionManager sessions;
  late Directory temp;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    database = LocalDatabase.forTesting(factory: databaseFactoryFfi);
    await database.initialize();
    repository = LocalPlanRepository(userId: 1, localDatabase: database);
    await repository.ensureReady();
    sessions = ModRuntimeSessionManager();
    registry = ModRegistry(repository, sessionManager: sessions);
    runtime = ModRuntimeManager.forRepository(
      repository,
      sessionManager: sessions,
    );
    temp = await Directory.systemTemp.createTemp('pb-v1-registry-');
  });

  tearDown(() async {
    runtime.shutdown();
    await database.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  ModPackageInstallResult result({String version = '1.0.0'}) {
    final manifest = <String, dynamic>{
      'manifestVersion': 1,
      'id': 'com.example.v1reading',
      'version': version,
      'name': {'zh-CN': '阅读模板', 'en': 'Reading templates'},
      'description': 'V1 declarative package',
      'publisher': {'id': 'publisher.example'},
      'type': 'content',
      'contentKind': 'task_template',
      'runtime': {
        'type': 'declarative',
        'apiVersion': '1',
        'entrypoint': 'content/task-templates.json',
      },
      'permissions': [
        {
          'capability': 'host.tasks.create',
          'required': true,
          'reason': 'Create a task from a selected template',
        },
      ],
      'dependencies': <String>[],
    };
    final package = ModValidatedPackage(
      manifest: manifest,
      taskTemplates: ModTaskTemplateDocument(
        templates: [
          {
            'title': '阅读十页',
            'note': '',
            'targetCount': 10,
            'importance': 3,
            'difficulty': 2,
          },
        ],
      ),
      fileDigests: {'manifest.json': ''.padLeft(64, 'a')},
    );
    return ModPackageInstallResult(
      modId: 'com.example.v1reading',
      version: version,
      installDirectoryPath: '${temp.path}/com.example.v1reading',
      archiveSha256: ''.padLeft(64, 'b'),
      package: package,
    );
  }

  test('V1 package is recorded with localized name, disabled and no grants', () async {
    final installedPackage = result();
    await registry.installV1Package(
      package: installedPackage.package,
      modId: installedPackage.modId,
      version: installedPackage.version,
      packageDirectory: installedPackage.installDirectoryPath,
      archiveSha256: installedPackage.archiveSha256,
    );
    final installed = (await registry.list()).single;
    expect(installed['name'], '阅读模板');
    expect(installed['nameLocales'], {'zh-CN': '阅读模板', 'en': 'Reading templates'});
    expect(installed['isV1Package'], isTrue);
    expect(installed['runtimeReady'], isFalse);
    expect(installed['enabled'], isFalse);
    expect(installed['grantedPermissions'], isEmpty);
    expect(installed['packageSha256'], ''.padLeft(64, 'b'));
    expect(installed['packageDirectory'], contains('com.example.v1reading'));
    expect(await runtime.listAvailableTaskTemplates(), isEmpty);
    await expectLater(
      runtime.start('com.example.v1reading'),
      throwsA(anything),
    );
  });

  test('V1 package must receive explicit user grant before it can be enabled', () async {
    final installedPackage = result();
    await registry.installV1Package(
      package: installedPackage.package,
      modId: installedPackage.modId,
      version: installedPackage.version,
      packageDirectory: installedPackage.installDirectoryPath,
      archiveSha256: installedPackage.archiveSha256,
    );

    await expectLater(
      registry.setEnabled('com.example.v1reading', true),
      throwsA(isA<StateError>()),
    );
    expect((await registry.list()).single['enabled'], isFalse);

    await registry.grantPermission(
      'com.example.v1reading',
      'host.tasks.create',
    );
    final installed = (await registry.list()).single;
    expect(installed['grantedPermissions'], ['host.tasks.create']);
    expect(installed['enabled'], isTrue);
    expect((installed['permissions'] as List).single, isA<Map>());
  });

  test('V1 package upgrades require a higher SemVer and remain disabled', () async {
    final installedPackage = result();
    await registry.installV1Package(
      package: installedPackage.package,
      modId: installedPackage.modId,
      version: installedPackage.version,
      packageDirectory: installedPackage.installDirectoryPath,
      archiveSha256: installedPackage.archiveSha256,
    );
    await expectLater(
      registry.validateV1PackageInstall(result(version: '0.9.9').package),
      throwsA(isA<FormatException>()),
    );
    final upgradedPackage = result(version: '1.1.0');
    await registry.installV1Package(
      package: upgradedPackage.package,
      modId: upgradedPackage.modId,
      version: upgradedPackage.version,
      packageDirectory: upgradedPackage.installDirectoryPath,
      archiveSha256: upgradedPackage.archiveSha256,
    );
    final installed = (await registry.list()).single;
    expect(installed['version'], '1.1.0');
    expect(installed['enabled'], isFalse);
    expect(installed['grantedPermissions'], isEmpty);
  });

  test('V1 package cannot silently take over an ID owned by another publisher', () async {
    final legacy = jsonEncode({
      'schemaVersion': 1,
      'id': 'com.example.v1reading',
      'name': '旧版任务模板',
      'version': '1.0.0',
      'description': '',
      'permissions': <String>[],
      'dependencies': <String>[],
      'taskTemplates': <Map<String, dynamic>>[],
    });
    await registry.install(legacy, grantedPermissions: const <String>{});
    final package = result(version: '1.1.0');
    await expectLater(
      registry.validateV1PackageInstall(package.package),
      throwsA(isA<FormatException>()),
    );
    expect((await registry.list()).single['publisherId'], 'local.legacy');
  });

  test('legacy JSON cannot replace an installed V1 package with the same ID', () async {
    final installedPackage = result();
    await registry.installV1Package(
      package: installedPackage.package,
      modId: installedPackage.modId,
      version: installedPackage.version,
      packageDirectory: installedPackage.installDirectoryPath,
      archiveSha256: installedPackage.archiveSha256,
    );
    final legacy = jsonEncode({
      'schemaVersion': 1,
      'id': 'com.example.v1reading',
      'name': '冒名旧版清单',
      'version': '2.0.0',
      'description': '',
      'permissions': <String>[],
      'dependencies': <String>[],
      'taskTemplates': <Map<String, dynamic>>[],
    });
    await expectLater(
      registry.install(legacy, grantedPermissions: const <String>{}),
      throwsA(isA<FormatException>()),
    );
    final installed = (await registry.list()).single;
    expect(installed['isV1Package'], isTrue);
    expect(installed['enabled'], isFalse);
  });

  test('legacy JSON install retains its original enabled behavior', () async {
    final legacy = jsonEncode({
      'schemaVersion': 1,
      'id': 'com.example.legacy',
      'name': '旧版任务模板',
      'version': '1.0.0',
      'description': '',
      'permissions': <String>[],
      'dependencies': <String>[],
      'taskTemplates': <Map<String, dynamic>>[],
    });
    await registry.install(legacy, grantedPermissions: const <String>{});
    final installed = (await registry.list()).single;
    expect(installed['isV1Package'], isNull);
    expect(installed['enabled'], isTrue);
  });
}
