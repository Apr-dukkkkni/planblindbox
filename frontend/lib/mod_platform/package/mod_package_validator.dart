import 'dart:convert';

import '../manifest/mod_manifest_v1_validator.dart';
import 'mod_package_integrity.dart';
import 'mod_package_models.dart';

/// Validates a decoded package file map. ZIP decoding and streaming limits are
/// deliberately separate so the installer can enforce limits before allocating
/// the full expanded archive in memory.
class ModPackageValidator {
  ModPackageValidator({
    ModManifestV1Validator? manifestValidator,
    ModPackageIntegrity? integrity,
  }) : _manifestValidator = manifestValidator ?? ModManifestV1Validator(),
       _integrity = integrity ?? ModPackageIntegrity();

  final ModManifestV1Validator _manifestValidator;
  final ModPackageIntegrity _integrity;

  /// Exposes the same path rules to the installed-directory loader.
  static void validatePackagePath(String path) =>
      ModPackageIntegrity.validatePath(path);

  ModValidatedPackage validate(Map<String, List<int>> files) {
    if (files.isEmpty || files.length > ModPackageLimits.maxFiles) {
      throw const FormatException('内容包文件数量无效');
    }
    var expandedBytes = 0;
    for (final entry in files.entries) {
      ModPackageIntegrity.validatePath(entry.key);
      if (entry.value.length > ModPackageLimits.maxFileBytes) {
        throw FormatException('文件超过 20 MiB：${entry.key}');
      }
      expandedBytes += entry.value.length;
      if (expandedBytes > ModPackageLimits.maxExpandedBytes) {
        throw const FormatException('内容包解压后总大小超过 100 MiB');
      }
    }

    final manifestBytes = files['manifest.json'];
    final integrityBytes = files['integrity.json'];
    if (manifestBytes == null || integrityBytes == null) {
      throw const FormatException('内容包必须包含 manifest.json 和 integrity.json');
    }
    if (manifestBytes.length > ModPackageLimits.maxManifestBytes) {
      throw const FormatException('manifest.json 超过 64 KiB');
    }
    if (integrityBytes.length > ModPackageLimits.maxIntegrityBytes) {
      throw const FormatException('integrity.json 超过 64 KiB');
    }

    final fileDigests = _integrity.verify(
      files: files,
      integrityJson: utf8.decode(integrityBytes, allowMalformed: false),
    );
    final manifestRaw = utf8.decode(manifestBytes, allowMalformed: false);
    final manifest = _manifestValidator.parse(manifestRaw);
    if (manifest['type'] != 'content' || manifest['contentKind'] != 'task_template') {
      throw const FormatException('当前安装器仅支持 task_template 内容包');
    }
    final runtime = manifest['runtime'];
    if (runtime is! Map || runtime['type'] != 'declarative' ||
        runtime['entrypoint'] != 'content/task-templates.json') {
      throw const FormatException('task_template 必须使用指定的声明式入口');
    }
    final allowedPaths = <String>{
      'manifest.json',
      'integrity.json',
      'content/task-templates.json',
    };
    final assets = manifest['assets'];
    if (assets is Map && assets['icon'] is String) {
      allowedPaths.add(assets['icon'] as String);
    }
    if (files.keys.toSet().difference(allowedPaths).isNotEmpty ||
        !files.keys.toSet().containsAll(allowedPaths)) {
      throw const FormatException('内容包包含未声明文件或缺少必需文件');
    }
    final templateBytes = files['content/task-templates.json'];
    if (templateBytes == null) {
      throw const FormatException('缺少 content/task-templates.json');
    }
    final templates = _parseTaskTemplates(
      utf8.decode(templateBytes, allowMalformed: false),
    );
    return ModValidatedPackage(
      manifest: Map<String, dynamic>.unmodifiable(manifest),
      taskTemplates: templates,
      fileDigests: fileDigests,
    );
  }

  ModTaskTemplateDocument _parseTaskTemplates(String raw) {
    final bytes = utf8.encode(raw);
    if (bytes.length > ModPackageLimits.maxFileBytes) {
      throw const FormatException('任务模板文件超过 20 MiB');
    }
    final decoded = ModManifestV1Validator.parseStrictJson(raw);
    if (decoded is! Map<String, dynamic> ||
        decoded.keys.toSet().difference({'schemaVersion', 'templates'}).isNotEmpty ||
        decoded['schemaVersion'] != 1) {
      throw const FormatException('任务模板文档格式无效');
    }
    final rawTemplates = decoded['templates'];
    if (rawTemplates is! List || rawTemplates.length > ModPackageLimits.maxTaskTemplates) {
      throw const FormatException('任务模板最多只能包含 20 项');
    }
    final templates = <Map<String, dynamic>>[];
    for (final rawTemplate in rawTemplates) {
      if (rawTemplate is! Map<String, dynamic> ||
          rawTemplate.keys.toSet().difference({
            'title', 'note', 'targetCount', 'importance', 'difficulty',
          }).isNotEmpty) {
        throw const FormatException('任务模板字段无效');
      }
      final title = rawTemplate['title'];
      final note = rawTemplate['note'] ?? '';
      final targetCount = rawTemplate['targetCount'] ?? 1;
      final importance = rawTemplate['importance'] ?? 3;
      final difficulty = rawTemplate['difficulty'] ?? 3;
      if (title is! String || title.trim().isEmpty || title.length > 100 ||
          note is! String || note.length > 500 ||
          targetCount is! int || targetCount < 1 || targetCount > 999 ||
          importance is! int || importance < 1 || importance > 5 ||
          difficulty is! int || difficulty < 1 || difficulty > 5) {
        throw const FormatException('任务模板参数不合法');
      }
      templates.add({
        'title': title.trim(),
        'note': note,
        'targetCount': targetCount,
        'importance': importance,
        'difficulty': difficulty,
      });
    }
    return ModTaskTemplateDocument(templates: templates);
  }
}
