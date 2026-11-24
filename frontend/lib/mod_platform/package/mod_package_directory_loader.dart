import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'mod_package_models.dart';
import 'mod_package_validator.dart';

/// Reloads an installed V1 package from disk and re-validates its complete
/// contents. Database-cached taskTemplates are deliberately not trusted.
class ModPackageDirectoryLoader {
  ModPackageDirectoryLoader({
    required Directory installationRoot,
    ModPackageValidator? validator,
  }) : _requestedRoot = installationRoot,
       _validator = validator ?? ModPackageValidator();

  final Directory _requestedRoot;
  final ModPackageValidator _validator;

  Future<ModValidatedPackage> load(Map<String, dynamic> installation) async {
    if (installation['isV1Package'] != true ||
        installation['manifestVersion'] != 1 ||
        installation['contentKind'] != 'task_template') {
      throw const FormatException('安装记录不是受支持的 V1 task_template 内容包');
    }

    final modId = installation['installedModId'];
    final version = installation['installedVersion'];
    final publisherId = installation['publisherId'];
    final recordedDirectory = installation['packageDirectory'];
    if (modId is! String ||
        !RegExp(r'^[a-z][a-z0-9]*(\.[a-z][a-z0-9-]*)+$').hasMatch(modId) ||
        version is! String || publisherId is! String ||
        recordedDirectory is! String || recordedDirectory.isEmpty) {
      throw const FormatException('V1 安装记录身份或目录字段无效');
    }

    if (!await _requestedRoot.exists()) {
      throw const FormatException('V1 内容包安装根目录不存在');
    }
    final canonicalRoot = await _requestedRoot.resolveSymbolicLinks();
    final expectedDirectory = p.normalize(p.join(canonicalRoot, modId));
    final recordedNormalized = p.normalize(p.absolute(recordedDirectory));
    if (recordedNormalized != expectedDirectory) {
      throw const FormatException('V1 安装目录与账号或 MOD 身份不匹配');
    }

    final directoryType = await FileSystemEntity.type(
      expectedDirectory,
      followLinks: false,
    );
    if (directoryType != FileSystemEntityType.directory) {
      throw const FormatException('V1 安装目录不存在或不是普通目录');
    }
    final canonicalDirectory = await Directory(expectedDirectory).resolveSymbolicLinks();
    if (p.normalize(canonicalDirectory) != expectedDirectory) {
      throw const FormatException('V1 安装目录解析后越出预期位置');
    }

    final files = <String, List<int>>{};
    var expandedBytes = 0;
    await for (final entity in Directory(expectedDirectory).list(
      recursive: true,
      followLinks: false,
    )) {
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw FormatException('安装目录包含符号链接：${entity.path}');
      }
      if (type == FileSystemEntityType.directory) continue;
      if (type != FileSystemEntityType.file) {
        throw FormatException('安装目录包含非普通文件：${entity.path}');
      }

      final relative = p.relative(entity.path, from: expectedDirectory)
          .split(p.separator).join('/');
      ModPackageValidator.validatePackagePath(relative);
      if (files.containsKey(relative)) {
        throw FormatException('安装目录存在重复文件路径：$relative');
      }
      if (files.length >= ModPackageLimits.maxFiles) {
        throw const FormatException('安装目录文件数量超过限制');
      }
      final file = File(entity.path);
      final length = await file.length();
      if (length > ModPackageLimits.maxFileBytes) {
        throw FormatException('安装文件超过单文件大小限制：$relative');
      }
      expandedBytes += length;
      if (expandedBytes > ModPackageLimits.maxExpandedBytes) {
        throw const FormatException('安装目录总大小超过限制');
      }
      // Re-check immediately before reading to avoid following a replaced link.
      if (await FileSystemEntity.type(entity.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw FormatException('安装文件类型在读取前发生变化：$relative');
      }
      files[relative] = await file.readAsBytes();
    }

    final validated = _validator.validate(files);
    final manifest = validated.manifest;
    final manifestPublisher = (manifest['publisher'] as Map)['id'];
    if (manifest['id'] != modId || manifest['version'] != version ||
        manifestPublisher != publisherId) {
      throw const FormatException('磁盘 Manifest 与安装记录身份不一致');
    }

    final storedDigests = installation['fileDigests'];
    if (storedDigests is! Map) {
      throw const FormatException('安装记录缺少文件摘要');
    }
    final normalizedStoredDigests = <String, String>{};
    for (final entry in storedDigests.entries) {
      if (entry.key is! String || entry.value is! String) {
        throw const FormatException('安装记录中的文件摘要格式无效');
      }
      normalizedStoredDigests[entry.key as String] = entry.value as String;
    }
    if (!_sameStringMap(normalizedStoredDigests, validated.fileDigests)) {
      throw const FormatException('磁盘文件摘要与安装记录不一致');
    }

    final storedSourceManifest = installation['sourceManifest'];
    if (storedSourceManifest is! Map ||
        !_deepJsonEquals(storedSourceManifest, manifest)) {
      throw const FormatException('磁盘 Manifest 与安装时记录的原始 Manifest 不一致');
    }

    return validated;
  }

  bool _sameStringMap(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  bool _deepJsonEquals(Object? a, Object? b) =>
      jsonEncode(_canonicalize(a)) == jsonEncode(_canonicalize(b));

  Object? _canonicalize(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: _canonicalize(value[key]),
      };
    }
    if (value is List) return value.map(_canonicalize).toList();
    return value;
  }
}
