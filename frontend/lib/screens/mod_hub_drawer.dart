import 'package:flutter/material.dart';

import '../data/today_api.dart';
import '../services/mod_registry.dart';
import '../services/mod_import_flow.dart';
import 'mod_marketplace_page.dart';

/// Leaf drawer: discovery/import at top-right, installed template shortcuts below.
/// Enable/disable and installed-Mod administration belong exclusively to Settings.
class ModHubDrawer extends StatefulWidget {
  const ModHubDrawer({super.key, required this.api});

  final TodayApi api;

  @override
  State<ModHubDrawer> createState() => _ModHubDrawerState();
}

class _ModHubDrawerState extends State<ModHubDrawer> {
  late final ModRegistry _registry = ModRegistry(widget.api.repository);
  bool _enabled = true;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _templates = [];
  List<Map<String, dynamic>> _installed = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final setting = await widget.api.repository.getAppSetting('mods.enabled.v1');
      final installed = await _registry.list();
      final templates = await _registry.taskTemplates();
      if (!mounted) return;
      setState(() {
        _enabled = setting != 'false';
        _installed = installed;
        _templates = _enabled ? templates : [];
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _openMarket() async {
    final navigator = Navigator.of(context);
    navigator.pop(); // close drawer before opening a route
    await navigator.push<void>(
      MaterialPageRoute<void>(builder: (_) => ModMarketplacePage(api: widget.api)),
    );
    if (mounted) await _reload();
  }

  Future<void> _import() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ModImportFlow.import(context, widget.api);
      if (mounted) await _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _applyTemplate(Map<String, dynamic> template) async {
    if (_busy || !_enabled) return;
    final title = template['title'] as String;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('创建任务？'),
        content: Text('使用 ${template['modName']} 的模板新建「$title」？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('创建')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      // Recheck the global switch and the registry before modifying user data.
      final enabled = await widget.api.repository.getAppSetting('mods.enabled.v1') != 'false';
      final available = await _registry.taskTemplates();
      if (!enabled || !available.any((item) =>
          item['modId'] == template['modId'] &&
          item['title'] == template['title'] &&
          item['targetCount'] == template['targetCount'])) {
        throw StateError('Mod 已被关闭、权限撤回或模板已更新');
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已创建任务：$title')));
      Navigator.of(context).pop(); // return to Today; refresh by pulling down
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('创建失败：$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
              child: Row(
                children: [
                  const Icon(Icons.eco_rounded, color: Colors.green),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Mod 扩展', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19))),
                  IconButton(
                    tooltip: '在线 Mod 市场',
                    icon: const Icon(Icons.storefront_outlined),
                    onPressed: _openMarket,
                  ),
                  IconButton(
                    tooltip: '导入 Mod',
                    icon: const Icon(Icons.file_open_outlined),
                    onPressed: _busy ? null : _import,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (_loading) const LinearProgressIndicator(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null) Text('读取 Mod 失败：$_error'),
                  if (!_enabled)
                    const Card(child: ListTile(
                      leading: Icon(Icons.block_outlined),
                      title: Text('Mod 功能已关闭'),
                      subtitle: Text('可前往「我的 → 设置」开启，已安装的 Mod 不会被删除。'),
                    ))
                  else ...[
                    Text('已安装 ${_installed.length} 个 Mod', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 10),
                    Text('可用任务模板', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    if (_templates.isEmpty)
                      const Text('暂无可用模板。点击右上角的市场或导入图标来添加 Mod。')
                    else
                      for (final item in _templates)
                        Card(child: ListTile(
                          title: Text(item['title'] as String),
                          subtitle: Text('来自 ${item['modName']}'),
                          trailing: const Icon(Icons.add_task_outlined),
                          enabled: !_busy,
                          onTap: () => _applyTemplate(item),
                        )),
                  ],
                  const SizedBox(height: 20),
                  const Text('启停和卸载已安装 Mod，请前往「我的 → 设置 → Mod 管理」。',
                      style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
