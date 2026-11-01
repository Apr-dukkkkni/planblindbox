import 'package:flutter/material.dart';

import '../data/today_api.dart';
import '../services/mod_registry.dart';

/// Declarative V1 Mod manager. No untrusted code is executed.
class ModManagementPage extends StatefulWidget {
  const ModManagementPage({super.key, required this.api});
  final TodayApi api;

  @override
  State<ModManagementPage> createState() => _ModManagementPageState();
}

class _ModManagementPageState extends State<ModManagementPage> {
  late final ModRegistry _registry = ModRegistry(widget.api.repository);
  List<Map<String, dynamic>> _mods = [];
  List<Map<String, dynamic>> _templates = [];
  List<Map<String, dynamic>> _audit = [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final mods = await _registry.list();
      final templates = await _registry.taskTemplates();
      final audit = await _registry.audit();
      if (!mounted) return;
      setState(() {
        _mods = mods;
        _templates = templates;
        _audit = audit;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认')),
          ],
        ),
      ) ?? false;

  Future<void> _createFromTemplate(Map<String, dynamic> template) async {
    final title = template['title'] as String;
    final globalSetting = await widget.api.repository.getAppSetting('mods.enabled.v1');
    if (globalSetting == 'false') {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mod 功能已在设置中关闭，请先开启')),
      );
      return;
    }
    final accepted = await _confirm('使用任务模板？',
        '来自 ${template['modName']} 的模板将新建任务「$title」。只有确认后才会写入本地 SQLite。');
    if (!accepted || !mounted) return;
    await _run(() async {
      // Re-check both global switch and per-Mod permissions before creating a task.
      if (await widget.api.repository.getAppSetting('mods.enabled.v1') == 'false') {
        throw StateError('Mod 功能已关闭');
      }
      final current = await _registry.taskTemplates();
      if (!current.any((e) => e['modId'] == template['modId'] &&
          e['title'] == title && e['targetCount'] == template['targetCount'])) {
        throw StateError('模板已被禁用或权限已撤回');
      }
      await widget.api.createTask(
        title: title,
        note: template['note'] as String,
        targetCount: template['targetCount'] as int,
        importance: template['importance'] as int,
        difficulty: template['difficulty'] as int,
        categoryId: 0,
        recordRule: const {'mode': 'DEFAULT'},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已创建任务：$title')));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mod 管理'),
        actions: [
          IconButton(onPressed: _busy ? null : _reload, tooltip: '刷新', icon: const Icon(Icons.refresh)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 108),
        children: [
          const Text('这里管理已安装 Mod 的启停、卸载和任务模板。新 Mod 请从「今日」页面左上角叶子打开侧边栏导入或前往在线市场。'),
          const SizedBox(height: 12),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) Text('读取失败：$_error', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          Text('已安装 (${_mods.length})', style: Theme.of(context).textTheme.titleLarge),
          if (_mods.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('暂无 Mod。可以导入示例 JSON 试用任务模板扩展。')),
          for (final mod in _mods)
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: Text('${mod['name']}  v${mod['version']}'),
                    subtitle: Text('${mod['id']}\n${mod['description']}'),
                    isThreeLine: true,
                    value: mod['enabled'] == true,
                    onChanged: _busy ? null : (value) => _run(() => _registry.setEnabled(mod['id'] as String, value)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('授权：${(mod['grantedPermissions'] as List).isEmpty ? '无' : (mod['grantedPermissions'] as List).join(', ')}'),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('卸载'),
                      onPressed: _busy ? null : () async {
                        final ok = await _confirm('卸载 ${mod['name']}？', '卸载会移除此 Mod 的模板和授权，不会删除已经创建的任务。');
                        if (ok) await _run(() => _registry.uninstall(mod['id'] as String));
                      },
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 18),
          Text('可用任务模板 (${_templates.length})', style: Theme.of(context).textTheme.titleLarge),
          for (final template in _templates)
            Card(
              child: ListTile(
                title: Text(template['title'] as String),
                subtitle: Text('来自 ${template['modName']} · 目标 ${template['targetCount']} 次'),
                trailing: const Icon(Icons.add_task_outlined),
                onTap: _busy ? null : () => _createFromTemplate(template),
              ),
            ),
          const SizedBox(height: 18),
          Text('最近操作', style: Theme.of(context).textTheme.titleLarge),
          for (final event in _audit.take(10))
            ListTile(
              dense: true,
              title: Text('${event['action']} · ${event['id']}'),
              subtitle: Text('${event['at']}'),
            ),
        ],
      ),
    );
  }
}
