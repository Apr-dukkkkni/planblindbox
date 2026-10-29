import 'package:flutter/material.dart';

import '../data/habit_api.dart';
import '../data/today_api.dart';

/// 「今日」的二级页面，不占用底部导航名额。
class HabitManagementPage extends StatefulWidget {
  const HabitManagementPage({
    super.key,
    required this.api,
    required this.businessDate,
    this.autoCreate = false,
  });

  final bool autoCreate;
  final TodayApi api;
  /// 从 /today 返回的业务日 YYYY-MM-DD，避免凌晨 5 点前使用自然日。
  final String businessDate;

  @override
  State<HabitManagementPage> createState() => _HabitManagementPageState();
}

class _HabitManagementPageState extends State<HabitManagementPage> {
  late final HabitApi _api;                  // 只声明，**这里不初始化**，延迟赋值
  List<HabitInfo> _habits = [];              // 声明 + 就地初始化
  Map<int, HabitCheckInStats> _checkInStats = {}; // 声明 + 就地初始化
  final Set<int> _workingIds = {};           // 声明 + 就地初始化
  bool _loading = true;                       // 声明 + 就地初始化
  String? _error;                            // 只声明，默认初始值 null
  String _filter = 'ALL';                     // 声明 + 就地初始化

  @override
  void initState() {
    super.initState();

    _api = HabitApi(
      baseUrl: widget.api.baseUrl,
      userId: widget.api.userId,
    );

    _load();

    if (widget.autoCreate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showForm();
      });
    }
  }
  //`HabitApi` 持有 `http.Client`，Client 如果不 close，会一直占用连接；多个页面反复打开关闭，会堆积连接，出现隐性资源泄漏。
  @override  //重写父类 `State` 里的 `dispose` 生命周期方法
  void dispose() {
    _api.dispose();
    super.dispose();//调用父类 `State` 的 dispose
  }

  Future<void> _load() async {
    if (!mounted) return;  //确认当前state挂载在树上
    setState(() { //打开加载转圈标记，清空上次的错误信息
      _loading = true;
      _error = null;
    });

    try {
      final habits = await _api.getAll();//先拉全部习惯基础列表，拉取失败直接跳到外层catch
      // 统计接口不可用时仍展示习惯信息，不让一个失败状态影响整页。
      final entries = await Future.wait(habits.map((habit) async {
        try {
          final stats = await _api.getCheckInStats(habit.id);
          return MapEntry<int, HabitCheckInStats?>(habit.id, stats);
        } catch (_) {
          return MapEntry<int, HabitCheckInStats?>(habit.id, null);
        }
      }));

      if (!mounted) return;//主列表必须成功；单条统计挂了，页面照样展示习惯，只是这条统计显示「—」，不整页翻车
      setState(() {
        _habits = habits;
        _checkInStats = {
          for (final entry in entries)
            if (entry.value != null) entry.key: entry.value!,
        };
      });


    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _message(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      //`ScaffoldMessenger` 是 Flutter 提供的组件，依附页面的 Scaffold，用来展示 SnackBar（底部短时提示条）
      content: Text(message),
      backgroundColor: error ? Colors.red.shade700 : null,
    ));
  }

  //创建习惯
  Future<void> _showForm([HabitInfo? habit]) async {
    final changed = await showModalBottomSheet<bool>(  //等待一个异步 Future 任务执行完成，拿到结果，再继续往下跑后面代码
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
      if (mounted) setState(() => _workingIds.remove(habit.id));
    }
  }

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
    if (confirmed != true || !mounted || _workingIds.contains(habit.id)) return;
    setState(() => _workingIds.add(habit.id));
    try {
      await _api.archive(habit.id);
      if (!mounted) return;
      _message('已归档，历史打卡记录保留');
      await _load();
    } catch (error) {
      _message('归档失败：$error', error: true);
    } finally {
      if (mounted) setState(() => _workingIds.remove(habit.id));
    }
  }

  Widget _habitCard(HabitInfo habit) {   //局部 UI 组件函数
    final stats = _checkInStats[habit.id];
    final isPaused = habit.status == 'PAUSED';
    final working = _workingIds.contains(habit.id);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),  //间距
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(                 //标题行
              children: [
                Expanded(
                  child: Text(habit.name,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ),
                Chip(label: Text(isPaused ? '已暂停' : '进行中')),
              ],
            ),
            if (habit.note.trim().isNotEmpty) ...[ //备注不为空才渲染备注文字；`...` 是展开运算符，把里面的 widget 列表摊开进外层 children
              const SizedBox(height: 5),
              Text(habit.note, style: TextStyle(color: scheme.onSurfaceVariant)),
            ],
            const SizedBox(height: 9),
            Text('重复：${habit.repeatLabel}  ·  开始：${habit.startDate}',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            if (habit.endDate != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text('结束：${habit.endDate}',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              ),
            const SizedBox(height: 12),

            //打卡统计
            Wrap(spacing: 14, runSpacing: 6, children: [
              Text(stats == null ? '连续次数：—' : '连续 ${stats.currentStreak} 次'),
              Text(stats == null ? '累计天数：—' : '累计 ${stats.totalCheckInDays} 天'),
              if (stats?.checkedInToday == true)
                Text('今日已打卡', style: TextStyle(color: scheme.primary)),
            ]),
            const SizedBox(height: 8),

            //三个按钮
            Wrap(spacing: 8, runSpacing: 6, children: [
              OutlinedButton.icon(
                onPressed: working ? null : () => _showForm(habit),
                icon: const Icon(Icons.edit_outlined, size: 17),
                label: const Text('编辑'),
              ),
              OutlinedButton.icon(
                onPressed: working ? null : () => _setPaused(habit),
                icon: Icon(isPaused ? Icons.play_arrow : Icons.pause_outlined, size: 17),
                label: Text(isPaused ? '恢复' : '暂停'),
              ),
              TextButton.icon(
                onPressed: working ? null : () => _archive(habit),
                icon: const Icon(Icons.archive_outlined, size: 17),
                label: const Text('归档'),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    final visible = _habits         //从全部习惯里过滤出**要展示在列表上的数据**
        .where((habit) => _filter == 'ALL' || habit.status == _filter)
        .toList();

    return Scaffold(    //页面根布局脚手架，AppBar、悬浮按钮、body 都放在这里
      //顶部导航栏，右上角刷新
      appBar: AppBar(
        title: const Text('习惯管理'),
        actions: [
          IconButton(
            tooltip: '刷新习惯',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      //右下角悬浮按钮
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showForm(),
        icon: const Icon(Icons.add),
        label: const Text('新建习惯'),
      ),
      //筛选标签栏
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Wrap(spacing: 8, children: [
              for (final filter in const [
                ('ALL', '全部'),
                ('ACTIVE', '进行中'),
                ('PAUSED', '已暂停'),
              ])
                ChoiceChip(
                  label: Text(filter.$2),
                  selected: _filter == filter.$1,
                  onSelected: (_) => setState(() => _filter = filter.$1),
                ),
            ]),
          ),
          //条件渲染
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('获取习惯失败：$_error',
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),

          //在 Column 里占满剩下所有空间
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
  int _importance = 3;
  int _difficulty = 3;
  String? _error;

  @override
  void initState() {
    super.initState();
    final habit = widget.original;
    if (habit == null) return;
    _name.text = habit.name;
    _note.text = habit.note;
    _importance = habit.importance;
    _difficulty = habit.difficulty;
    if (habit.repeatRule['type'] == 'WEEKLY') {
      _type = 'WEEKLY';
      final days = habit.repeatRule['daysOfWeek'];
      if (days is List) {
        _weekdays.addAll(days.whereType<num>()
            .map((day) => day.toInt()).where((day) => day >= 1 && day <= 7));
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
      setState(() => _error = '请输入不超过 100 字的习惯名称');
      return;
    }
    if (_type == 'WEEKLY' && _weekdays.isEmpty) {
      setState(() => _error = '每周重复至少选择一天');
      return;
    }
    final rule = _type == 'DAILY'
        ? <String, dynamic>{'type': 'DAILY'}
        : <String, dynamic>{
      'type': 'WEEKLY',
      'daysOfWeek': _weekdays.toList()
        ..sort(),
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
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final editing = widget.original != null;
    const days = ['一', '二', '三', '四', '五', '六', '日'];
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            22, 10, 22, 24 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(editing ? '编辑习惯' : '创建习惯',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              maxLength: 100,
              decoration: const InputDecoration(labelText: '习惯名称 *'),
            ),
            const SizedBox(height: 5),
            TextField(
              controller: _note,
              maxLines: 1,
              decoration: const InputDecoration(labelText: '备注（可选）'),
            ),
            const SizedBox(height: 12),
            // 重要程度
            DropdownButtonFormField<int>(
              value: _importance,
              decoration: const InputDecoration(
                labelText: '重要程度（1～5）',
              ),
              items: List.generate(5, (index) {
                final value = index + 1;
                return DropdownMenuItem<int>(
                  value: value,
                  child: Text('$value'),
                );
              }),
              onChanged: _saving
                  ? null
                  : (value) {
                if (value != null) {
                  setState(() => _importance = value);
                }
              },
            ),

            const SizedBox(height: 12),

// 困难程度
            DropdownButtonFormField<int>(
              value: _difficulty,
              decoration: const InputDecoration(
                labelText: '困难程度（1～5）',
              ),
              items: List.generate(5, (index) {
                final value = index + 1;
                return DropdownMenuItem<int>(
                  value: value,
                  child: Text('$value'),
                );
              }),
              onChanged: _saving
                  ? null
                  : (value) {
                if (value != null) {
                  setState(() => _difficulty = value);
                }
              },
            ),
            const SizedBox(height: 14),
            const SizedBox(height: 14),
            const Text('重复规则', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              ChoiceChip(
                label: const Text('每天'),
                selected: _type == 'DAILY',
                onSelected: (_) => setState(() => _type = 'DAILY'),
              ),
              ChoiceChip(
                label: const Text('每周指定日期'),
                selected: _type == 'WEEKLY',
                onSelected: (_) => setState(() => _type = 'WEEKLY'),
              ),
            ]),
            if (_type == 'WEEKLY') ...[
              const SizedBox(height: 8),
              Wrap(spacing: 7, runSpacing: 5, children: [
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
            Text(
              editing
                  ? '原开始日期：${widget.original!.startDate}（保持不变）'
                  : '开始日期：${widget.businessDate}（按凌晨 5 点业务日计算）',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (editing && widget.original!.endDate != null)
              Text('原结束日期：${widget.original!.endDate}（保持不变）',
                  style: Theme.of(context).textTheme.bodySmall),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving
                    ? '正在保存…'
                    : editing ? '保存修改' : '创建习惯'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
