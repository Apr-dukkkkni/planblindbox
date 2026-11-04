import 'package:flutter/material.dart';

import '../data/habit_api.dart';
import '../data/today_api.dart';

/// 「今日」的二级页面，不占用底部导航名额。
///
/// 页面外部继续接收 TodayApi，以兼容 today_page.dart 和 stats_page.dart
/// 现有的调用方式；习惯管理的增删改、归档和恢复统一交给 HabitApi。
class HabitManagementPage extends StatefulWidget {
  const HabitManagementPage({
    super.key,
    required this.api,
    required this.businessDate,
    this.autoCreate = false,
    this.initialFilter = 'ALL',
  });

  final bool autoCreate;
  final TodayApi api;
  final String businessDate;
  final String initialFilter;

  @override
  State<HabitManagementPage> createState() => _HabitManagementPageState();
}

class _HabitManagementPageState extends State<HabitManagementPage> {
  late final HabitApi _api;

  List<HabitInfo> _habits = [];
  Map<int, HabitCheckInStats> _checkInStats = {};
  final Set<int> _workingIds = {};

  bool _loading = true;
  String? _error;
  String _filter = 'ALL';

  @override
  void initState() {
    super.initState();

    _filter = widget.initialFilter;

    _api = HabitApi(baseUrl: widget.api.baseUrl, userId: widget.api.userId);

    _load();

    if (widget.autoCreate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showForm();
      });
    }
  }

  // 释放 HabitApi 自己持有的资源；共享 SQLite 数据库连接由 LocalDatabase 管理。
  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 获取全部习惯，包括已归档的习惯。
      final habits = await _api.getAll(includeArchived: true);

      // 单条统计读取失败不影响其他习惯展示。
      final entries = await Future.wait(
        habits.map((habit) async {
          try {
            final stats = await _api.getCheckInStats(habit.id);
            return MapEntry<int, HabitCheckInStats?>(habit.id, stats);
          } catch (_) {
            return MapEntry<int, HabitCheckInStats?>(habit.id, null);
          }
        }),
      );

      if (!mounted) return;

      setState(() {
        _habits = habits;
        _checkInStats = {
          for (final entry in entries)
            if (entry.value != null) entry.key: entry.value!,
        };
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

  void _message(String message, {bool error = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade700 : null,
      ),
    );
  }

  // 创建或编辑习惯。
  Future<void> _showForm([HabitInfo? habit]) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _HabitForm(
        api: _api,
        businessDate: widget.businessDate,
        original: habit,
      ),
    );

    if (changed == true && mounted) {
      _message(habit == null ? '习惯创建成功' : '习惯修改成功');
      await _load();
    }
  }

  // 暂停或恢复习惯。
  Future<void> _setPaused(HabitInfo habit) async {
    if (_workingIds.contains(habit.id)) return;

    setState(() => _workingIds.add(habit.id));

    try {
      final pause = habit.status == 'ACTIVE';

      await _api.setPaused(habit.id, paused: pause);

      if (!mounted) return;

      _message(pause ? '习惯已暂停' : '习惯已恢复');
      await _load();
    } catch (error) {
      _message('操作失败：$error', error: true);
    } finally {
      if (mounted) {
        setState(() => _workingIds.remove(habit.id));
      }
    }
  }

  // 归档习惯。
  Future<void> _archive(HabitInfo habit) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('归档习惯？'),
        content: Text('「${habit.name}」将从习惯列表移除。已有打卡记录不会删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认归档'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted || _workingIds.contains(habit.id)) {
      return;
    }

    setState(() => _workingIds.add(habit.id));

    try {
      await _api.archive(habit.id);

      if (!mounted) return;

      _message('已归档，历史打卡记录保留');
      await _load();
    } catch (error) {
      _message('归档失败：$error', error: true);
    } finally {
      if (mounted) {
        setState(() => _workingIds.remove(habit.id));
      }
    }
  }

  // 恢复已经归档的习惯。
  Future<void> _restore(HabitInfo habit) async {
    if (_workingIds.contains(habit.id)) return;

    setState(() => _workingIds.add(habit.id));

    try {
      await _api.restore(habit.id);

      if (!mounted) return;

      _message('习惯已恢复，历史打卡记录已保留');
      await _load();
    } catch (error) {
      _message('恢复失败：$error', error: true);
    } finally {
      if (mounted) {
        setState(() => _workingIds.remove(habit.id));
      }
    }
  }

  // 单个习惯卡片。
  Widget _habitCard(HabitInfo habit) {
    final stats = _checkInStats[habit.id];
    final isPaused = habit.status == 'PAUSED';
    final isArchived = habit.status == 'ARCHIVED';
    final working = _workingIds.contains(habit.id);
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    habit.name,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Chip(
                  label: Text(
                    isArchived
                        ? '已归档'
                        : isPaused
                        ? '已暂停'
                        : '进行中',
                  ),
                ),
              ],
            ),

            if (habit.note.trim().isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                habit.note,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],

            const SizedBox(height: 9),

            Text(
              '重复：${habit.repeatLabel}  ·  开始：${habit.startDate}',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),

            if (habit.endDate != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  '结束：${habit.endDate}',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),

            const SizedBox(height: 12),

            // 打卡统计。
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                Text(stats == null ? '连续次数：—' : '连续 ${stats.currentStreak} 次'),
                Text(
                  stats == null ? '累计天数：—' : '累计 ${stats.totalCheckInDays} 天',
                ),
                if (stats?.checkedInToday == true)
                  Text('今日已打卡', style: TextStyle(color: scheme.primary)),
              ],
            ),

            const SizedBox(height: 8),

            // 操作按钮。
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (isArchived)
                  OutlinedButton.icon(
                    onPressed: working ? null : () => _restore(habit),
                    icon: const Icon(Icons.unarchive_outlined, size: 17),
                    label: const Text('恢复习惯'),
                  )
                else ...[
                  OutlinedButton.icon(
                    onPressed: working ? null : () => _showForm(habit),
                    icon: const Icon(Icons.edit_outlined, size: 17),
                    label: const Text('编辑'),
                  ),
                  OutlinedButton.icon(
                    onPressed: working ? null : () => _setPaused(habit),
                    icon: Icon(
                      isPaused ? Icons.play_arrow : Icons.pause_outlined,
                      size: 17,
                    ),
                    label: Text(isPaused ? '恢复' : '暂停'),
                  ),
                  TextButton.icon(
                    onPressed: working ? null : () => _archive(habit),
                    icon: const Icon(Icons.archive_outlined, size: 17),
                    label: const Text('归档'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _habits
        .where((habit) => _filter == 'ALL' || habit.status == _filter)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_filter == 'ARCHIVED' ? '已归档习惯' : '习惯管理'),
        actions: [
          // 刷新按钮。
          IconButton(
            tooltip: '刷新习惯',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),

          // 归档入口：放在刷新按钮右边。
          IconButton(
            tooltip: _filter == 'ARCHIVED' ? '返回全部习惯' : '查看已归档习惯',
            onPressed: () {
              setState(() {
                _filter = _filter == 'ARCHIVED' ? 'ALL' : 'ARCHIVED';
              });
            },
            icon: Icon(
              _filter == 'ARCHIVED'
                  ? Icons.unarchive_outlined
                  : Icons.archive_outlined,
            ),
          ),
        ],
      ),

      floatingActionButton: _filter == 'ARCHIVED'
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showForm(),
              icon: const Icon(Icons.add),
              label: const Text('新建习惯'),
            ),

      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Wrap(
              spacing: 8,
              children: [
                for (final filter in const [
                  ('ALL', '全部'),
                  ('ACTIVE', '进行中'),
                  ('PAUSED', '已暂停'),
                  ('ARCHIVED', '已归档'),
                ])
                  ChoiceChip(
                    label: Text(filter.$2),
                    selected: _filter == filter.$1,
                    onSelected: (_) {
                      setState(() => _filter = filter.$1);
                    },
                  ),
              ],
            ),
          ),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                '获取习惯失败：$_error',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),

          Expanded(
            child: _loading && _habits.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
                      itemCount: visible.isEmpty ? 1 : visible.length,
                      itemBuilder: (context, index) {
                        if (visible.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.only(top: 90),
                            child: Center(child: Text('当前筛选下没有习惯')),
                          );
                        }

                        return _habitCard(visible[index]);
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 习惯新建与编辑表单
// -----------------------------------------------------------------------------

class _HabitForm extends StatefulWidget {
  const _HabitForm({
    required this.api,
    required this.businessDate,
    this.original,
  });

  final HabitApi api;
  final String businessDate;
  final HabitInfo? original;

  @override
  State<_HabitForm> createState() => _HabitFormState();
}

class _HabitFormState extends State<_HabitForm> {
  final _name = TextEditingController();
  final _note = TextEditingController();

  String _type = 'DAILY';
  final Set<int> _weekdays = {};

  bool _saving = false;
  bool _expanded = false; // 新建习惯只显示名称与创建按钮
  int _importance = 3;
  int _difficulty = 3;
  String? _error;

  @override
  void initState() {
    super.initState();

    final habit = widget.original;
    if (habit == null) return;
    _expanded = true;

    _name.text = habit.name;
    _note.text = habit.note;
    _importance = habit.importance;
    _difficulty = habit.difficulty;

    if (habit.repeatRule['type'] == 'WEEKLY') {
      _type = 'WEEKLY';

      final days = habit.repeatRule['daysOfWeek'];

      if (days is List) {
        _weekdays.addAll(
          days
              .whereType<num>()
              .map((day) => day.toInt())
              .where((day) => day >= 1 && day <= 7),
        );
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();

    if (name.isEmpty || name.length > 100) {
      setState(() {
        _error = '请输入不超过 100 字的习惯名称';
      });
      return;
    }

    if (_type == 'WEEKLY' && _weekdays.isEmpty) {
      setState(() {
        _error = '每周重复至少选择一天';
      });
      return;
    }

    final rule = _type == 'DAILY'
        ? <String, dynamic>{'type': 'DAILY'}
        : <String, dynamic>{
            'type': 'WEEKLY',
            'daysOfWeek': _weekdays.toList()..sort(),
          };

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final habit = widget.original;

      if (habit == null) {
        await widget.api.create(
          name: name,
          note: _note.text.trim(),
          startDate: widget.businessDate,
          repeatRule: rule,
          importance: _importance,
          difficulty: _difficulty,
        );
      } else {
        await widget.api.update(
          habit.id,
          name: name,
          note: _note.text.trim(),
          repeatRule: rule,
          importance: _importance,
          difficulty: _difficulty,
        );
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Widget _scoreChips(String label, int value, ValueChanged<int> onChanged) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Row(children: [
        for (var number = 1; number <= 5; number++)
          Expanded(child: Padding(
            padding: const EdgeInsets.only(right: 5),
            child: ChoiceChip(
              showCheckmark: false,
              label: SizedBox(width: double.infinity,
                child: Text('$number', textAlign: TextAlign.center)),
              selected: value == number,
              onSelected: (_) => onChanged(number),
              labelPadding: EdgeInsets.zero,
            ),
          )),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.original != null;
    const days = ['一', '二', '三', '四', '五', '六', '日'];

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          22,
          10,
          22,
          24 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              editing ? '编辑习惯' : '创建习惯',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22),
            ),

            const SizedBox(height: 16),

            TextField(
              controller: _name,
              maxLength: 100,
              decoration: const InputDecoration(labelText: '习惯名称 *'),
            ),

            if (_expanded) ...[
              const SizedBox(height: 6),
              TextField(controller: _note, maxLines: 2,
                decoration: const InputDecoration(labelText: '备注（可选）')),
              const SizedBox(height: 12),
              _scoreChips('重要程度', _importance,
                (value) => setState(() => _importance = value)),
              const SizedBox(height: 10),
              _scoreChips('困难程度', _difficulty,
                (value) => setState(() => _difficulty = value)),
              const SizedBox(height: 12),
              const Text('重复规则', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 6, children: [
                ChoiceChip(label: const Text('每天'),
                  selected: _type == 'DAILY',
                  onSelected: (_) => setState(() => _type = 'DAILY')),
                ChoiceChip(label: const Text('每周指定日期'),
                  selected: _type == 'WEEKLY',
                  onSelected: (_) => setState(() => _type = 'WEEKLY')),
              ]),
              if (_type == 'WEEKLY') ...[
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (var index = 0; index < days.length; index++)
                    FilterChip(
                      label: Text('周${days[index]}'),
                      selected: _weekdays.contains(index + 1),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          _weekdays.add(index + 1);
                        } else {
                          _weekdays.remove(index + 1);
                        }
                      }),
                    ),
                ]),
              ],
              const SizedBox(height: 10),
              Text(editing
                    ? '原开始日期：${widget.original!.startDate}（保持不变）'
                    : '开始日期：${widget.businessDate}（05:00 业务日）',
                style: Theme.of(context).textTheme.bodySmall),
              if (editing && widget.original!.endDate != null)
                Text('原结束日期：${widget.original!.endDate}（保持不变）',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
            if (!editing)
              Center(child: TextButton.icon(
                onPressed: _saving ? null : () => setState(() => _expanded = !_expanded),
                icon: Icon(_expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
                label: Text(_expanded ? '收起选项' : '展开更多'),
              )),

            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],

            const SizedBox(height: 18),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(
                  _saving
                      ? '正在保存…'
                      : editing
                      ? '保存修改'
                      : '创建习惯',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
