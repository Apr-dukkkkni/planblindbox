import 'package:flutter/material.dart';
import '../data/today_api.dart';
import 'task_category_page.dart';

class TaskLibraryPage extends StatefulWidget {
  const TaskLibraryPage({
    super.key,
    required this.api,
    this.onEditTask,
  });

  final TodayApi api;
  final Future<bool> Function(int taskId)? onEditTask;

  @override
  State<TaskLibraryPage> createState() => _TaskLibraryPageState();
}

class _TaskLibraryPageState extends State<TaskLibraryPage> {
  List<Map<String, dynamic>> _tasks = [];
  List<Map<String, dynamic>> _categories = [];
  String _filter = 'ALL';
  bool _loading = true;
  String? _error;

  final Map<String, String> _filters = const {
    'ALL': '全部',
    'ACTIVE': '进行中',
    'COMPLETED': '已完成',
    'OVERDUE': '已逾期',
    'OTHER': '其他',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final tasks = await widget.api.getAllTasks();
      final categories = await widget.api.getTaskCategories(includeDisabled: true);

      if (!mounted) return;

      setState(() {
        _tasks = tasks;
        _categories = categories;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _category(Map<String, dynamic> task) {
    final status = task['status']?.toString() ?? '';
    final endTime = DateTime.tryParse(
      task['endTime']?.toString() ?? '',
    );

    if (status == 'COMPLETED') return 'COMPLETED';

    if (status == 'CANCELLED' || status == 'ARCHIVED') {
      return 'OTHER';
    }

    if (endTime != null &&
        !endTime.isAfter(DateTime.now())) {
      return 'OVERDUE';
    }

    return 'ACTIVE';
  }

  String _categoryName(Map<String, dynamic> task) {
    final id = (task['categoryId'] as num?)?.toInt() ?? 0;
    if (id == 0) return '未分类';
    for (final category in _categories) {
      if ((category['categoryId'] as num).toInt() == id) {
        final name = category['name']?.toString() ?? '未命名分类';
        return category['enabled'] == true ? name : '$name（已停用）';
      }
    }
    return '历史分类';
  }

  String _statusText(Map<String, dynamic> task) {
    final category = _category(task);

    switch (category) {
      case 'COMPLETED':
        return '已完成';
      case 'OVERDUE':
        return '已逾期';
      case 'OTHER':
        return task['status'] == 'ARCHIVED'
            ? '已归档'
            : '已取消';
      default:
        return task['status'] == 'IN_PROGRESS'
            ? '执行中'
            : '待执行';
    }
  }

  String _formatTime(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    if (date == null) return '未设置';

    String pad(int n) => n.toString().padLeft(2, '0');

    return '${date.year}-${pad(date.month)}-${pad(date.day)} '
        '${pad(date.hour)}:${pad(date.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final visibleTasks = _tasks.where((task) {
      return _filter == 'ALL' || _category(task) == _filter;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的任务库'),
        actions: [
          IconButton(
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => TaskCategoryPage(api: widget.api)),
              );
              if (mounted) await _load();
            },
            tooltip: '管理分类',
            icon: const Icon(Icons.category_outlined),
          ),
          IconButton(
            onPressed: _loading ? null : _load,
            tooltip: '刷新任务',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 60,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: _filters.entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(entry.value),
                    selected: _filter == entry.key,
                    onSelected: (_) {
                      setState(() => _filter = entry.key);
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
              child: CircularProgressIndicator(),
            )
                : _error != null
                ? Center(child: Text(_error!))
                : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                physics:
                const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: visibleTasks.length,
                itemBuilder: (context, index) {
                  final task = visibleTasks[index];

                  final taskId = (task['taskId'] as num?)?.toInt();
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: widget.onEditTask == null || taskId == null
                          ? null
                          : () async {
                              final saved = await widget.onEditTask!(taskId);
                              if (saved && mounted) await _load();
                            },
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    task['title']?.toString() ?? '',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const Icon(Icons.edit_outlined, size: 18),
                                const SizedBox(width: 8),
                                Chip(
                                  label: Text(_statusText(task)),
                                ),
                              ],
                            ),
                            if ((task['note']?.toString() ?? '').isNotEmpty)
                              Text(task['note'].toString()),
                            const SizedBox(height: 6),
                            Text('分类：${_categoryName(task)}',
                                style: const TextStyle(color: Colors.grey)),
                            const SizedBox(height: 8),
                            Text('目标次数：${task['targetCount'] ?? 0}'),
                            Text('截止时间：${_formatTime(task['endTime'])}'),
                            if (widget.onEditTask != null)
                              const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Text(
                                  '点击卡片编辑',
                                  style: TextStyle(color: Colors.grey, fontSize: 12),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
