import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plan_blind_box/mod_platform/package/mod_package_directory_loader.dart';
import 'package:plan_blind_box/mod_platform/package/mod_package_validator.dart';

void main() {
  late Directory temp;
  late Directory root;
  late Directory packageDirectory;
  late Map<String, List<int>> files;
  late Map<String, dynamic> installation;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pb-package-loader-');
    root = Directory('${temp.path}${Platform.pathSeparator}owner_7');
    packageDirectory = Directory(
      '${root.path}${Platform.pathSeparator}com.example.reading',
    );
    files = _validFiles();
    await _writePackage();
    installation = _installation();
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('loads and revalidates installed package bytes', () async {
    final loaded = await ModPackageDirectoryLoader(
      installationRoot: root,
    ).load(installation);
    expect(loaded.manifest['id'], 'com.example.reading');
    expect(loaded.taskTemplates.templates.single['title'], '每天阅读');
  });

  test('rejects changed content even if database cache is unchanged', () async {
    await File('${packageDirectory.path}/content/task-templates.json')
        .writeAsString('{"schemaVersion":1,"templates":[]}');
    await expectLater(
      ModPackageDirectoryLoader(installationRoot: root).load(installation),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects a package directory outside the owner-scoped root', () async {
    installation['packageDirectory'] = temp.path;
    await expectLater(
      ModPackageDirectoryLoader(installationRoot: root).load(installation),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects a changed registry digest projection', () async {
    installation['fileDigests'] = <String, String>{'manifest.json': '0' * 64};
    await expectLater(
      ModPackageDirectoryLoader(installationRoot: root).load(installation),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects symlinks in installed package directory', () async {
    final outside = File('${temp.path}/outside.txt')..writeAsStringSync('x');
    final link = Link('${packageDirectory.path}/content/link.txt');
    try {
      await link.create(outside.path);
    } on FileSystemException {
      // Some Windows environments do not allow creating symlinks without
      // Developer Mode or elevated privileges.
      markTestSkipped('当前 Windows 环境不允许创建符号链接');
    }
    await expectLater(
      ModPackageDirectoryLoader(installationRoot: root).load(installation),
      throwsA(isA<FormatException>()),
    );
  });

  Future<void> _writePackage() async {
    for (final entry in files.entries) {
      final output = File(
        '${packageDirectory.path}${Platform.pathSeparator}${entry.key.replaceAll('/', Platform.pathSeparator)}',
      );
      await output.parent.create(recursive: true);
      await output.writeAsBytes(entry.value, flush: true);
    }
  }

  Map<String, dynamic> _installation() => {
    'isV1Package': true,
    'manifestVersion': 1,
    'contentKind': 'task_template',
    'installedModId': 'com.example.reading',
    'installedVersion': '1.0.0',
    'publisherId': 'com.example.publisher',
    'packageDirectory': packageDirectory.path,
    'fileDigests': {
      for (final entry in files.entries)
        if (entry.key != 'integrity.json')
          entry.key: sha256.convert(entry.value).toString(),
    },
    'sourceManifest': jsonDecode(utf8.decode(files['manifest.json']!)),
  };
}

Map<String, List<int>> _validFiles() {
  final manifest = <String, dynamic>{
    'manifestVersion': 1,
    'id': 'com.example.reading',
    'version': '1.0.0',
    'name': {'en': 'Reading templates'},
    'publisher': {'id': 'com.example.publisher'},
    'type': 'content',
    'contentKind': 'task_template',
    'runtime': {
      'type': 'declarative',
      'apiVersion': '1',
      'entrypoint': 'content/task-templates.json',
    },
    'compatibility': {'hostApi': '^1.0.0', 'platforms': ['android']},
    'ui': {'allowedModes': ['modal'], 'defaultMode': 'modal'},
    'storage': {
      'local': {'enabled': false, 'quotaMiB': 0, 'persistent': false},
    },
    'permissions': [
      {
        'capability': 'host.tasks.create',
        'required': false,
        'reason': 'Allow task creation from a selected template.',
      },
    ],
  };
  final content = utf8.encode(jsonEncode({
    'schemaVersion': 1,
    'templates': [
      {
        'title': '每天阅读',
        'note': '阅读一本书',
        'targetCount': 30,
        'importance': 4,
        'difficulty': 3,
      },
    ],
  }));
  final files = <String, List<int>>{
    'manifest.json': utf8.encode(jsonEncode(manifest)),
    'content/task-templates.json': content,
  };
  files['integrity.json'] = utf8.encode(jsonEncode({
    'algorithm': 'SHA-256',
    'files': {
      for (final entry in files.entries)
        entry.key: sha256.convert(entry.value).toString(),
    },
  }));
  return files;
}
