import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../manifest/mod_manifest_v1_validator.dart';

/// Verifies the package's internal SHA-256 inventory.
/// This is corruption/tamper consistency checking, NOT publisher authenticity:
/// an attacker able to replace the ZIP can replace integrity.json too.
class ModPackageIntegrity {
  static const algorithm = 'SHA-256';

  Map<String, String> verify({
    required Map<String, List<int>> files,
    required String integrityJson,
  }) {
    if (utf8.encode(integrityJson).length > 64 * 1024) {
      throw const FormatException('integrity.json 超过 64 KiB');
    }
    final decoded = ModManifestV1Validator.parseStrictJson(integrityJson);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('integrity.json 根节点必须是 JSON 对象');
    }
    if (decoded.keys.toSet().difference({'algorithm', 'files'}).isNotEmpty) {
      throw const FormatException('integrity.json 包含未知字段');
    }
    if (decoded['algorithm'] != algorithm) {
      throw const FormatException('仅支持 SHA-256');
    }
    final rawEntries = decoded['files'];
    if (rawEntries is! Map<String, dynamic> || rawEntries.isEmpty) {
      throw const FormatException('integrity.files 必须是非空对象');
    }

    final packagePaths = files.keys.toSet()..remove('integrity.json');
    final declaredPaths = rawEntries.keys.toSet();
    if (packagePaths.length != declaredPaths.length ||
        !packagePaths.containsAll(declaredPaths)) {
      throw const FormatException('integrity.files 必须与内容包文件清单完全一致');
    }

    final verified = <String, String>{};
    for (final entry in rawEntries.entries) {
      final path = entry.key;
      validatePath(path);
      final expected = entry.value;
      if (expected is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(expected)) {
        throw FormatException('文件摘要格式无效：$path');
      }
      final bytes = files[path];
      if (bytes == null) throw FormatException('完整性清单引用了缺失文件：$path');
      final actual = sha256.convert(bytes).toString();
      if (actual != expected) throw FormatException('文件摘要不匹配：$path');
      verified[path] = actual;
    }
    return Map<String, String>.unmodifiable(verified);
  }

  static void validatePath(String path) {
    if (path.isEmpty || path.startsWith('/') || path.contains('\\') ||
        path.contains(':') || path.contains('\u0000')) {
      throw FormatException('内容包路径不安全：$path');
    }
    final segments = path.split('/');
    if (segments.any((part) => part.isEmpty || part == '.' || part == '..')) {
      throw FormatException('内容包路径不安全：$path');
    }
  }
}
