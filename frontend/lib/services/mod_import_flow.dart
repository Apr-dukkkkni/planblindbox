import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/today_api.dart';
import '../mod_platform/package/mod_package_importer_stub.dart'
    if (dart.library.io) '../mod_platform/package/mod_package_importer_io.dart'
    as package_importer;
import 'mod_registry.dart';

/// Imports legacy JSON manifests and V1 declarative task-template ZIP packages.
/// V1 packages are installed with no grant; the user must explicitly authorize
/// host.tasks.create before the declarative Runtime becomes discoverable.
class ModImportFlow {
  static Future<bool> import(BuildContext context, TodayApi api) async {
    final registry = ModRegistry(api.repository);
    try {
      final selection = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json', 'zip'],
        withData: true,
        allowMultiple: false,
      );
      if (!context.mounted || selection == null || selection.files.isEmpty) {
        return false;
      }
      final selected = selection.files.single;
      final bytes = selected.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw const FormatException('无法读取 Mod 文件');
      }
      if (selected.extension?.toLowerCase() == 'zip') {
        return _importV1Package(context, registry, bytes);
      }
      return _importLegacyJson(context, registry, bytes);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入 Mod 失败：$e')),
        );
      }
      return false;
    }
  }

  static Future<bool> _importLegacyJson(
    BuildContext context,
    ModRegistry registry,
    List<int> bytes,
  ) async {
    if (bytes.length > ModRegistry.maxManifestBytes) {
      throw const FormatException('Mod 清单不能超过 64 KB');
    }
    final raw = utf8.decode(bytes, allowMalformed: false);
    final manifest = registry.parseManifest(raw);
    final permissions = (manifest['permissions'] as List).cast<String>();
    final granted = <String>{};
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text('导入 ${manifest['name']}？'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${manifest['id']} · v${manifest['version']}'),
                const SizedBox(height: 8),
                Text(manifest['description'] as String),
                const SizedBox(height: 10),
                const Text('以下权限必须由你主动授权；模板不会自动创建任务。'),
                for (final permission in permissions)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: granted.contains(permission),
                    title: Text(
                      permission == 'tasks.create' ? '创建任务' : permission,
                    ),
                    onChanged: (checked) => update(() {
                      if (checked == true) {
                        granted.add(permission);
                      } else {
                        granted.remove(permission);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('确认导入'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return false;
    await registry.install(raw, grantedPermissions: granted);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已安装：${manifest['name']}')),
      );
    }
    return true;
  }

  static Future<bool> _importV1Package(
    BuildContext context,
    ModRegistry registry,
    List<int> bytes,
  ) async {
    // Native platforms use the dart:io installer; Web uses a fail-closed stub.
    if (!package_importer.supportsV1ZipInstall) {
      throw UnsupportedError('当前平台暂不支持安装 ZIP 内容包');
    }
    final importSession = await package_importer.prepareV1PackageImport(
      bytes: bytes,
      ownerId: registry.ownerId,
    );
    final preview = importSession.preview;
    await registry.validateV1PackageInstall(preview);
    if (!context.mounted) return false;
    final manifest = preview.manifest;
    final names = Map<String, dynamic>.from(manifest['name'] as Map);
    final displayName = _localizedName(names);
    final publisherId =
        (manifest['publisher'] as Map<String, dynamic>)['id'] as String;
    final permissions = (manifest['permissions'] as List)
        .cast<Map<String, dynamic>>()
        .map((permission) => permission['capability'] as String)
        .toList(growable: false);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('安装 $displayName？'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${manifest['id']} · v${manifest['version']}'),
              const SizedBox(height: 8),
              Text('Publisher 声明：$publisherId（尚未验证发布者签名身份）'),
              Text(manifest['description'] as String? ?? ''),
              const SizedBox(height: 12),
              const Text(
                '这是 Manifest V1 声明式内容包。当前只安装并登记内容，不启动 Runtime。',
              ),
              const SizedBox(height: 8),
              Text('声明的权限（本次不会授予）：${permissions.isEmpty ? '无' : permissions.join(', ')}'),
              const SizedBox(height: 8),
              const Text('安装后保持禁用；后续必须由用户明确授权任务创建权限才能启用。'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('仅安装内容包'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return false;

    final result = await importSession.install();
    await registry.installV1Package(
      package: result.package,
      modId: result.modId,
      version: result.version,
      packageDirectory: result.installDirectoryPath,
      archiveSha256: result.archiveSha256,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已安装并保持禁用：$displayName')),
      );
    }
    return true;
  }

  static String _localizedName(Map<String, dynamic> names) {
    for (final locale in const ['zh-CN', 'zh-Hans', 'zh', 'en']) {
      final value = names[locale];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    for (final value in names.values) {
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return '未命名 MOD';
  }
}
