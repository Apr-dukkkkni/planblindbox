import 'package:flutter/material.dart';
import '../data/today_api.dart';

const _categoryColors = <String>[
  '#4F7CAC', '#7A6F9B', '#E07A5F', '#5B8E7D',
  '#C89F5D', '#607D8B', '#D1495B', '#2A9D8F',
];

Color _parseColor(dynamic value) {
  final hex = (value?.toString() ?? '#607D8B').replaceFirst('#', '');
  final rgb = int.tryParse(hex, radix: 16) ?? 0x607D8B;
  return Color(0xFF000000 | rgb);
}

class TaskCategoryPage extends StatefulWidget {
  const TaskCategoryPage({super.key, required this.api});
  final TodayApi api;

  @override
  State<TaskCategoryPage> createState() => _TaskCategoryPageState();
}

class _TaskCategoryPageState extends State<TaskCategoryPage> {
  List<Map<String, dynamic>> _categories = [];
  bool _loading = true;
  String? _error;
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final result = await widget.api.getTaskCategories(includeDisabled: true);
      if (!mounted) return;
      setState(() => _categories = result);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openEditor([Map<String, dynamic>? category]) async {
    final nameController = TextEditingController(
      text: category?['name']?.toString() ?? '',
    );
    String color = category?['color']?.toString() ?? _categoryColors.first;
    String? dialogError;

    final draft = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(category == null ? '新建分类' : '编辑分类'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  maxLength: 50,
                  decoration: const InputDecoration(labelText: '分类名称'),
                ),
                const SizedBox(height: 12),
                const Text('分类颜色'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _categoryColors.map((candidate) => InkWell(
                    onTap: () => setDialogState(() => color = candidate),
                    borderRadius: BorderRadius.circular(22),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: _parseColor(candidate),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: color == candidate ? Colors.black : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: color == candidate
                          ? const Icon(Icons.check, color: Colors.white, size: 18)
                          : null,
                    ),
                  )).toList(),
                ),
                if (dialogError != null) ...[
                  const SizedBox(height: 8),
                  Text(dialogError!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  setDialogState(() => dialogError = '请输入分类名称');
                  return;
                }
                Navigator.pop(dialogContext, {'name': name, 'color': color});
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();

    if (draft == null || !mounted) return;
    try {
      if (category == null) {
        await widget.api.createTaskCategory(
          name: draft['name']!,
          color: draft['color']!,
        );
      } else {
        await widget.api.updateTaskCategory(
          categoryId: (category['categoryId'] as num).toInt(),
          name: draft['name']!,
          color: draft['color']!,
        );
      }
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存分类失败：$error')),
        );
      }
    }
  }

  Future<void> _setEnabled(Map<String, dynamic> category, bool enabled) async {
    final id = (category['categoryId'] as num).toInt();
    setState(() => _busy.add(id));
    try {
      await widget.api.updateTaskCategory(categoryId: id, enabled: enabled);
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('更新分类状态失败：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('任务分类'),
      actions: [
        IconButton(
          onPressed: _loading ? null : _load,
          tooltip: '刷新',
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          onPressed: () => _openEditor(),
          tooltip: '新建分类',
          icon: const Icon(Icons.add),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? Center(child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!),
                  const SizedBox(height: 8),
                  FilledButton(onPressed: _load, child: const Text('重试')),
                ],
              ))
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text(
                      '分类停用后不会删除已有任务的分类关联，历史数据仍然保留。',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    if (_categories.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('暂无分类，点击右上角添加')),
                      ),
                    ..._categories.map((category) {
                      final id = (category['categoryId'] as num).toInt();
                      final enabled = category['enabled'] == true;
                      final isDefault = category['defaultCategory'] == true;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _parseColor(category['color']),
                            child: const Icon(Icons.label_outline, color: Colors.white),
                          ),
                          title: Text(category['name']?.toString() ?? ''),
                          subtitle: Text(
                            '${isDefault ? '预设分类' : '自定义分类'} · ${enabled ? '已启用' : '已停用'}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: '编辑分类',
                                onPressed: () => _openEditor(category),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              if (_busy.contains(id))
                                const SizedBox(
                                  width: 44,
                                  child: Center(
                                    child: SizedBox(
                                      width: 18, height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  ),
                                )
                              else
                                Switch(
                                  value: enabled,
                                  onChanged: (value) => _setEnabled(category, value),
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
  );
}
