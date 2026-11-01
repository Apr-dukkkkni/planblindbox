import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/today_api.dart';
import 'mod_registry.dart';

/// Single entry for importing a local JSON Mod manifest from the leaf drawer.
/// The permission dialog is mandatory and no third-party code is executed.
class ModImportFlow {
  static Future<bool> import(BuildContext context, TodayApi api) async {
    final registry = ModRegistry(api.repository);
    try {
      final selection = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
        allowMultiple: false,
      );
      if (!context.mounted || selection == null || selection.files.isEmpty) {
        return false;
      }
      final bytes = selection.files.single.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw const FormatException('无法读取 Mod 文件');
      }
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
                      title: Text(permission == 'tasks.create' ? '创建任务' : permission),
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
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入 Mod 失败：$e')),
        );
      }
      return false;
    }
  }
}
