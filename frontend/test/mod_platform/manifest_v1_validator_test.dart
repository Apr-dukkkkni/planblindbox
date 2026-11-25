import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plan_blind_box/mod_platform/manifest/mod_manifest_v1_validator.dart';

void main() {
  final validator = ModManifestV1Validator();

  test('accepts every shared valid Manifest V1 vector', () {
    final vectors = jsonDecode(_readVectors()) as Map<String, dynamic>;
    for (final vector in vectors['valid'] as List) {
      final item = Map<String, dynamic>.from(vector as Map);
      final manifest = validator.parse(item['raw'] as String);
      expect(manifest['manifestVersion'], 1, reason: item['id'] as String);
    }
  });

  test('rejects every shared invalid Manifest V1 vector', () {
    final vectors = jsonDecode(_readVectors()) as Map<String, dynamic>;
    for (final vector in vectors['invalid'] as List) {
      final item = Map<String, dynamic>.from(vector as Map);
      expect(
        () => validator.parse(item['raw'] as String),
        throwsFormatException,
        reason: '${item['id']}: ${item['reason']}',
      );
    }
  });

  test('rejects duplicate keys after JSON escape decoding', () {
    const raw = '{"manifestVersion":1,"manifest\\u0056ersion":1}';
    expect(() => validator.parse(raw), throwsFormatException);
  });

  test('implements SemVer 2.0.0 precedence', () {
    expect(ModManifestV1Validator.compareSemVer('1.0.0-alpha.1', '1.0.0-alpha.beta'), lessThan(0));
    expect(ModManifestV1Validator.compareSemVer('1.0.0-rc.1', '1.0.0'), lessThan(0));
    expect(ModManifestV1Validator.compareSemVer('1.0.0+build.1', '1.0.0+build.2'), 0);
    expect(ModManifestV1Validator.compareSemVer('1.10.0', '1.9.0'), greaterThan(0));
  });
}

String _readVectors() {
  var directory = Directory.current.absolute;
  while (true) {
    final candidate = File('${directory.path}${Platform.pathSeparator}'
        'mod-spec${Platform.pathSeparator}conformance${Platform.pathSeparator}'
        'manifest-v1-vectors.json');
    if (candidate.existsSync()) return candidate.readAsStringSync();
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('Cannot locate shared Manifest V1 conformance vectors');
    }
    directory = parent;
  }
}
