import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plan_blind_box/mod_platform/package/mod_package_validator.dart';

void main() {
  test('validates a task-template package and its SHA-256 inventory', () {
    final files = _validFiles();
    final result = ModPackageValidator().validate(files);
    expect(result.manifest['id'], 'com.example.reading');
    expect(result.taskTemplates.templates, hasLength(1));
    expect(result.taskTemplates.templates.single['title'], '每天阅读');
  });

  test('rejects a changed content file', () {
    final files = _validFiles();
    files['content/task-templates.json'] = utf8.encode(
      '{"schemaVersion":1,"templates":[]}',
    );
    expect(() => ModPackageValidator().validate(files), throwsFormatException);
  });

  test('rejects an unsafe package path', () {
    final files = _validFiles();
    files['../outside.txt'] = <int>[1];
    expect(() => ModPackageValidator().validate(files), throwsFormatException);
  });

  test('rejects duplicate keys in task-template JSON', () {
    final files = _validFiles();
    final content = utf8.encode(
      '{"schemaVersion":1,"schemaVersion":1,"templates":[]}',
    );
    files['content/task-templates.json'] = content;
    _refreshIntegrity(files);
    expect(() => ModPackageValidator().validate(files), throwsFormatException);
  });
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
  _refreshIntegrity(files);
  return files;
}

void _refreshIntegrity(Map<String, List<int>> files) {
  files['integrity.json'] = utf8.encode(jsonEncode({
    'algorithm': 'SHA-256',
    'files': {
      for (final entry in files.entries)
        if (entry.key != 'integrity.json')
          entry.key: sha256.convert(entry.value).toString(),
    },
  }));
}
