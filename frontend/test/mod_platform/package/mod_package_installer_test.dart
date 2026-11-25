import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plan_blind_box/mod_platform/package/mod_package_installer.dart';
import 'package:plan_blind_box/mod_platform/package/mod_package_models.dart';

void main() {
  late Directory temp;
  late Directory installRoot;
  late ModPackageInstaller installer;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pb-mod-installer-test-');
    installRoot = Directory('${temp.path}${Platform.pathSeparator}installed');
    installer = ModPackageInstaller(installationRoot: installRoot);
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('validateBytes previews a valid package without writing files', () async {
    final package = installer.validateBytes(_zip(_validFiles()));
    expect(package.manifest['id'], 'com.example.reading');
    expect(package.taskTemplates.templates, hasLength(1));
    expect(await installRoot.exists(), isFalse);
  });

  test('installs a valid task-template ZIP into its own directory', () async {
    final result = await installer.installBytes(_zip(_validFiles()));
    expect(result.modId, 'com.example.reading');
    expect(result.version, '1.0.0');
    expect(await File('${result.installDirectoryPath}/manifest.json').exists(), isTrue);
    expect(await File(
      '${result.installDirectoryPath}/content/task-templates.json',
    ).exists(), isTrue);
    expect(result.archiveSha256, hasLength(64));
  });

  test('rejects path traversal before creating an installation', () async {
    final files = _validFiles()..['../outside.txt'] = <int>[1, 2, 3];
    await expectLater(
      installer.installBytes(_zip(files)),
      throwsA(isA<FormatException>()),
    );
    expect(await Directory('${installRoot.path}/com.example.reading').exists(), isFalse);
    expect(await File('${temp.path}/outside.txt').exists(), isFalse);
  });

  test('rejects duplicate case-insensitive ZIP entry names', () async {
    final archive = _archive(_validFiles());
    archive.addFile(ArchiveFile('MANIFEST.JSON', 1, <int>[0]));
    await expectLater(
      installer.installBytes(ZipEncoder().encodeBytes(archive)),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects symbolic links', () async {
    final archive = _archive(_validFiles());
    archive.addFile(ArchiveFile.symlink('assets/link', '../../outside.txt'));
    await expectLater(
      installer.installBytes(ZipEncoder().encodeBytes(archive)),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects a ZIP entry whose CRC does not match its payload', () async {
    final bytes = _zip(_validFiles());
    final corrupted = List<int>.from(bytes);
    final view = ByteData.sublistView(Uint8List.fromList(corrupted));
    var centralOffset = -1;
    for (var i = corrupted.length - 22; i >= 0; i--) {
      if (view.getUint32(i, Endian.little) == 0x02014b50) {
        centralOffset = i;
        break;
      }
    }
    expect(centralOffset, greaterThanOrEqualTo(0));
    corrupted[centralOffset + 16] ^= 0x01;
    await expectLater(
      installer.installBytes(corrupted),
      throwsA(anything),
    );
  });

  test('rejects a declared expanded file over the per-file limit', () async {
    final files = _validFiles();
    files['assets/large.bin'] = List<int>.filled(
      ModPackageLimits.maxFileBytes + 1,
      0,
    );
    await expectLater(
      installer.installBytes(_zip(files)),
      throwsA(isA<FormatException>()),
    );
  });

  test('successful upgrade atomically replaces the previous version', () async {
    final first = await installer.installBytes(_zip(_validFiles(version: '1.0.0')));
    final second = await installer.installBytes(_zip(_validFiles(version: '1.1.0')));
    expect(second.installDirectoryPath, first.installDirectoryPath);
    expect(second.version, '1.1.0');
    final manifest = jsonDecode(await File(
      '${second.installDirectoryPath}/manifest.json',
    ).readAsString()) as Map<String, dynamic>;
    expect(manifest['version'], '1.1.0');
    final leftovers = await installRoot.list().toList();
    expect(leftovers.where((entity) => pBasename(entity.path).startsWith('.staging-')), isEmpty);
    expect(leftovers.where((entity) => pBasename(entity.path).startsWith('.backup-')), isEmpty);
  });

  test('invalid replacement leaves the existing installation untouched', () async {
    final first = await installer.installBytes(_zip(_validFiles()));
    final original = await File(
      '${first.installDirectoryPath}/manifest.json',
    ).readAsString();
    await expectLater(
      installer.installBytes(<int>[0, 1, 2, 3, 4]),
      throwsA(isA<FormatException>()),
    );
    expect(await File(
      '${first.installDirectoryPath}/manifest.json',
    ).readAsString(), original);
  });
}

String pBasename(String path) => path.split(Platform.pathSeparator).last;

Map<String, List<int>> _validFiles({String version = '1.0.0'}) {
  final manifest = <String, dynamic>{
    'manifestVersion': 1,
    'id': 'com.example.reading',
    'version': version,
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
        'reason': 'Allow the user to create a task from a selected template.',
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

Archive _archive(Map<String, List<int>> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  return archive;
}

List<int> _zip(Map<String, List<int>> files) =>
    ZipEncoder().encodeBytes(_archive(files));
