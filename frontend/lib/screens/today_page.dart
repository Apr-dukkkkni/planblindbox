import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/today_api.dart';
import '../models/today_models.dart';
import '../theme/app_theme.dart';
import '../widgets/dashboard_cards.dart';
import 'dart:math';
import 'task_library_page.dart';
import 'task_category_page.dart';
import 'habit_management_page.dart';
import 'daily_sign_in_calendar_page.dart';

class TodayPage extends StatefulWidget {
  const TodayPage({super.key, required this.api});
  final TodayApi api;

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  TodayData? _data;
  String _sort = 'time';
  String? _error;
  bool _loading = false;
  int _requestSequence = 0;
  final Set<String> _busy = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sequence = ++_requestSequence;
    setState(() { _loading = true; _error = null; });
    try {
      final data = await widget.api.getToday(sort: _sort);
      if (!mounted || sequence != _requestSequence) return;
      setState(() { _data = data; _error = null; });
    } catch (error) {
      if (!mounted || sequence != _requestSequence) return;
      setState(() { _error = error.toString(); });
    } finally {
      if (mounted && sequence == _requestSequence) {
        setState(() { _loading = false; });
      }
    }
  }

  Future<void> _execute(String key, Future<EarnedReward> Function() operation) async {
    if (_busy.contains(key)) return;
    setState(() => _busy.add(key));
    try {
      final reward = await operation();
      if (!mounted) return;
      _message(reward.message);
      await _load();
    } catch (error) {
      if (!mounted) return;
      _message('$error。请刷新首页核对状态，勿直接重复提交。', error: true);
      await _load();
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  Future<void> _completeTask(TodayTask task) async {
    if (task.remainingCount <= 0) return;//如果这个任务剩余可打卡次数已经是0，直接退出，什么都不做
    // 2. 弹出底部弹窗（bottomSheet），让用户输入本次要提交多少数量
    //    等待用户关闭弹窗，拿到用户输入的 count（int? 类型，用户取消就是 null）
    final count = await showModalBottomSheet<int>(
    //弹出一个**底部抽屉弹窗**，等待用户操作，弹窗关闭后把用户选 / 填的数字返回给变量 `count`。
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _RecordCountSheet(task: task),
    );
    // 3. 用户点了取消（count==null） / 页面已经销毁，直接返回，不发请求
    if (count == null || !mounted) return;
    // 4. 调用封装好的 _execute 函数：上锁 → 调用后端接口 completeTask，参数 taskId + 用户填的数量count
    await _execute('task-${task.id}', () => widget.api.completeTask(
          taskId: task.id, actualCount: count));
  }

  Future<void> _quickCompleteTask(TodayTask task) async {
    // 1. 判断是否可以继续记录
    if (task.completedToday || task.remainingCount <= 0) {
      return;
    }

    // 2. 计算本次预计记录数量
    final actualCount = min(
      task.recordCount,
      task.remainingCount,
    );

    // 3. 通过现有执行流程提交后端
    await _execute(
      'task-${task.id}',
          () => widget.api.completeTask(
        taskId: task.id,
        actualCount: actualCount,
      ),
    );
  }

  Future<void> _recordTask(TodayTask task) async {
    if (task.overdue ||
        task.completedToday ||
        task.remainingCount <= 0) {
      return;
    }

    if (task.recordMode == 'MANUAL') {
      await _completeTask(task);
    } else {
      await _quickCompleteTask(task);
    }
  }

  Future<void> _checkIn(TodayHabit habit) async {
    await _execute('habit-${habit.id}', () => widget.api.checkInHabit(habit.id));
  }

  Future<void> _createTask() async {
    final succeeded = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => TaskComposer(api: widget.api),
    );
    if (succeeded == true && mounted) {
      _message('新任务创建成功');
      await _load();
    }
  }

  Future<void> _editTask(TodayTask task) async {
    if (task.overdue) {
      _message('任务已逾期，请使用重新安排功能');
      return;
    }

    try {
      final detail = await widget.api.getTask(task.id);

      if (!mounted) return;

      final succeeded = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => TaskComposer(
          api: widget.api,
          taskDetail: detail,
        ),
      );

      if (succeeded == true && mounted) {
        _message('任务修改成功');
        await _load();
      }
    } catch (error) {
      if (mounted) {
        _message('编辑任务失败：$error');
      }
    }
  }



  Future<bool> _editTaskFromLibrary(int taskId) async {
    try {
      final detail = await widget.api.getTask(taskId);
      if (!mounted) return false;

      final succeeded = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => TaskComposer(
          api: widget.api,
          taskDetail: detail,
        ),
      );

      if (succeeded == true && mounted) {
        _message('任务修改成功');
        await _load();
        return true;
      }
      return false;
    } catch (error) {
      if (mounted) {
        _message('编辑任务失败：$error', error: true);
      }
      return false;
    }
  }

  Future<void> _openHabitManagement() async {
    final businessDate = _data?.date;

    if (businessDate == null) {
      _message('今日数据尚未加载，请刷新后重试', error: true);
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => HabitManagementPage(
          api: widget.api,
          businessDate: businessDate,
        ),
      ),
    );

    if (mounted) {
      await _load();
    }
  }

  Future<void> _openHabitCreate() async {
    final businessDate = _data?.date;

    if (businessDate == null) {
      _message('今日数据尚未加载', error: true);
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => HabitManagementPage(
          api: widget.api,
          businessDate: businessDate,
          autoCreate: true,
        ),
      ),
    );

    if (mounted) {
      await _load();
    }
  }

  Future<void> _openDailySignInCalendar() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DailySignInCalendarPage(
          api: widget.api,
          initialDate: _data?.date,
        ),
      ),
    );
  }


  void _message(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? AppColors.rose : AppColors.forest,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      body: SafeArea(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: RefreshIndicator(
          color: AppColors.forest,
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 15, 20, 35),
            children: [
              _topBar(),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.folder_outlined),
                  label: const Text('我的任务库'),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TaskLibraryPage(
                          api: widget.api,
                          onEditTask: _editTaskFromLibrary,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 18),
              if (_loading && data != null)
                const LinearProgressIndicator(minHeight: 2, color: AppColors.leaf),
              if (_loading && data == null)
                const Padding(padding: EdgeInsets.symmetric(vertical: 100),
                    child: Center(child: CircularProgressIndicator()))
              else if (data == null)
                _failure(_error ?? '尚未获取到今日数据')
              else ...[
                if (_error != null) ...[
                  _errorBanner(_error!),
                  const SizedBox(height: 12),
                ],
                  Stack(
                    children: [
                      DashboardHero(data: data),
                      Positioned(
                        top: 4,
                        right: 38,
                        child: IconButton(
                          tooltip: '签到日历',
                          onPressed: _openDailySignInCalendar,
                          icon: const Icon(
                            Icons.calendar_month_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 14),
                AssetStrip(assets: data.assets),
                const SizedBox(height: 29),
                SectionHeading(title: '今日任务',
                    subtitle: '按计划前进，积累每一次进步',
                    actionLabel: '新建任务', onAction: _createTask),
                const SizedBox(height: 11),
                _sortChips(),
                const SizedBox(height: 14),
                if (data.tasks.isEmpty)
                  const EmptySection(message: '今天还没有任务，添加一个小目标吧',
                      icon: Icons.task_alt_rounded)
                else
                  ...data.tasks.map((task) => Padding(
                    //遍历任务列表，**每一个 task 生成一个 Padding + TaskTile**
                    padding: const EdgeInsets.only(bottom: 11),  //卡片间距
                    child: TaskTile(task: task,
                      todayDate: data.date,
                      busy: _busy.contains('task-${task.id}'),//按任务 ID 单独加锁，而不是全局一把锁
                      onComplete: () => _recordTask(task),
                      onEdit: () => _editTask(task),
                    ),//点击卡片触发 `_completeTask(task)`
                  )),
                const SizedBox(height: 18),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 左侧：管理习惯
                      IconButton(
                        tooltip: '管理习惯',
                        onPressed: _openHabitManagement,
                        icon: const Icon(Icons.settings_outlined),
                      ),

                      // 中间：标题和副标题
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '每日习惯',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              '持续行动，比偶尔冲刺更重要',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),

                      // 右侧：新建习惯
                      IconButton(
                        tooltip: '新建习惯',
                        onPressed: _openHabitCreate,
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                const SizedBox(height: 13),
                if (data.habits.isEmpty)
                  const EmptySection(message: '今天没有计划打卡的习惯', icon: Icons.spa_outlined)
                else
                  ...data.habits.map((habit) => Padding(
                    padding: const EdgeInsets.only(bottom: 11),
                    child: HabitTile(habit: habit,
                      busy: _busy.contains('habit-${habit.id}'),
                      onCheckIn: () => _checkIn(habit)),
                  )),
                const SizedBox(height: 14),
                const Center(child: Text('今天也比昨天更进一步 ✨',
                    style: TextStyle(color: AppColors.muted, fontSize: 12))),
              ],
            ],
          ),
        ),
      ))),
    );
  }

  Widget _topBar() => Row(children: [
        Container(width: 45, height: 45,
          decoration: BoxDecoration(color: AppColors.paleGreen,
              borderRadius: BorderRadius.circular(15)),
          child: const Icon(Icons.eco_rounded, color: AppColors.forest, size: 27)),
        const SizedBox(width: 11),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('PlanBlindBox', style: TextStyle(fontWeight: FontWeight.w900,
              color: AppColors.ink, fontSize: 19)),
          Text('让成长变得看得见', style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ])),
        IconButton(onPressed: _loading ? null : _load,
          tooltip: '刷新今日数据',
          icon: const Icon(Icons.refresh_rounded, color: AppColors.forest)),
        Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(color: Colors.white,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(12)),
          child: Text('用户 ${widget.api.userId}',
              style: const TextStyle(fontSize: 12, color: AppColors.muted))),
      ]);

  Widget _sortChips() => Row(children: [
        const Icon(Icons.swap_vert_rounded, color: AppColors.muted, size: 18),
        const SizedBox(width: 6),
        const Text('排序', style: TextStyle(color: AppColors.muted, fontSize: 12)),
        const SizedBox(width: 12),
        _chip('time', '按时间'),
        const SizedBox(width: 8),
    _chip('importance', '按优先级'),
      ]);

  Widget _chip(String value, String label) {
    final selected = _sort == value;
    return ChoiceChip(
      selected: selected,
      showCheckmark: false,
      label: Text(label, style: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        fontSize: 12, color: selected ? Colors.white : AppColors.forest)),
      selectedColor: AppColors.forest,
      backgroundColor: Colors.white,
      side: BorderSide(color: selected ? AppColors.forest : AppColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onSelected: (_) {
        if (_sort == value) return;
        setState(() => _sort = value);
        _load();
      },
    );
  }

  Widget _failure(String error) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 72),
        child: Column(children: [
          const Icon(Icons.wifi_off_rounded, size: 50, color: AppColors.muted),
          const SizedBox(height: 16),
          const Text('还没连接上你的计划',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: 9),
          Text(error, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 16),
          FilledButton(onPressed: _load, child: const Text('重新连接')),
          const SizedBox(height: 14),
          Text('接口地址：${widget.api.baseUrl}',
              style: const TextStyle(fontSize: 11, color: AppColors.muted)),
        ]),
      );

  Widget _errorBanner(String error) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.paleRose,
            borderRadius: BorderRadius.circular(12)),
        child: Text('刷新失败，展示上次数据：$error',
            style: const TextStyle(color: AppColors.rose, fontSize: 12)),
      );
}

class _RecordCountSheet extends StatefulWidget {
  const _RecordCountSheet({required this.task});
  final TodayTask task;

  @override
  State<_RecordCountSheet> createState() => _RecordCountSheetState();
}

class _RecordCountSheetState extends State<_RecordCountSheet> {
  final _controller = TextEditingController(text: '1');
  String? _error;
  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(22, 8, 22, MediaQuery.of(context).viewInsets.bottom + 28),
    child: Column(mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('记录任务进度', style: TextStyle(fontWeight: FontWeight.w800,
          color: AppColors.ink, fontSize: 21)),
      const SizedBox(height: 6),
      Text(widget.task.title, style: const TextStyle(color: AppColors.muted)),
      const SizedBox(height: 6),
      Text('当前累计 ${widget.task.totalActualCount}/${widget.task.targetCount}，剩余 ${widget.task.remainingCount}',
          style: const TextStyle(color: AppColors.muted, fontSize: 12)),
      const SizedBox(height: 18),
      TextField(controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(labelText: '本次新增完成数量'),
      ),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 7),
          child: Text(_error!, style: const TextStyle(color: AppColors.rose))),
      const SizedBox(height: 15),
      SizedBox(width: double.infinity, child: FilledButton(
        onPressed: () {
          final count = int.tryParse(_controller.text.trim());
          if (count == null || count <= 0 || count > widget.task.remainingCount) {
            setState(() => _error = '请输入 1～${widget.task.remainingCount} 之间的数量');
            return;
          }
          Navigator.of(context).pop(count);
        },
        style: FilledButton.styleFrom(backgroundColor: AppColors.forest,
            minimumSize: const Size.fromHeight(50)),
        child: const Text('确认记录'),
      )),
    ]),
  );
}

class TaskComposer extends StatefulWidget {
  const TaskComposer({
    super.key,
    required this.api,
    this.taskDetail,
  });

  final TodayApi api;

  // 编辑时传入完整任务信息；创建时为 null
  final Map<String, dynamic>? taskDetail;

  bool get isEditing => taskDetail != null;

  @override
  State<TaskComposer> createState() => _TaskComposerState();
}

class _TaskComposerState extends State<TaskComposer> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  final _target = TextEditingController(text: '1');
  String _recordMode = 'DEFAULT';
  final TextEditingController _fixedCount =
  TextEditingController(text: '5');
  int _importance = 3;
  int _difficulty = 3;
  DateTime? _end;
  List<Map<String, dynamic>> _categories = [];
  int _categoryId = 0;
  bool _categoriesLoading = true;
  String? _categoryError;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();

    // 创建模式继续使用原来的默认值
    final detail = widget.taskDetail;
    if (detail == null) {
      _loadCategories();
      return;
    }
    _categoryId = (detail['categoryId'] as num?)?.toInt() ?? 0;
    _loadCategories();

    // 1. 初始化基础信息
    _title.text = detail['title']?.toString() ?? '';
    _note.text = detail['note']?.toString() ?? '';
    _target.text = detail['targetCount']?.toString() ?? '1';

    // 2. 初始化重要程度和难度
    _importance = (detail['importance'] as num?)?.toInt() ?? 3;
    _difficulty = (detail['difficulty'] as num?)?.toInt() ?? 3;

    // 编辑时保留当前截止时间；新建任务默认不指定，交由后端设置为下一个凌晨 05:00。
    _end = DateTime.tryParse(detail['endTime']?.toString() ?? '');

    // 4. 初始化记录规则
    final rule = detail['recordRule'];

    if (rule is Map) {
      final mode = rule['mode'];

      if (mode == 'DEFAULT' ||
          mode == 'FIXED' ||
          mode == 'MANUAL') {
        _recordMode = mode as String;
      }

      if (_recordMode == 'FIXED') {
        _fixedCount.text = rule['count']?.toString() ?? '';
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _target.dispose();
    _fixedCount.dispose();
    super.dispose();
  }


  Future<void> _loadCategories() async {
    try {
      final categories = await widget.api.getTaskCategories(includeDisabled: true);
      if (!mounted) return;
      final active = categories.where((item) => item['enabled'] == true).toList();
      setState(() {
        _categories = categories;
        _categoriesLoading = false;
        _categoryError = null;
        if (!widget.isEditing && _categoryId == 0) {
          final other = active.where((item) => item['name'] == '其他').toList();
          if (other.isNotEmpty) {
            _categoryId = (other.first['categoryId'] as num).toInt();
          } else if (active.isNotEmpty) {
            _categoryId = (active.first['categoryId'] as num).toInt();
          }
        }
        if (_categoryId != 0 &&
            !categories.any((item) => (item['categoryId'] as num).toInt() == _categoryId)) {
          _categoryId = 0;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _categoriesLoading = false;
        _categoryError = error.toString();
      });
    }
  }

  Future<void> _manageCategories() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TaskCategoryPage(api: widget.api)),
    );
    if (mounted) await _loadCategories();
  }

  Future<void> _pickEnd() async {
    final now = DateTime.now();
    final initial = _end != null && _end!.isAfter(now)
        ? _end!
        : now.add(const Duration(hours: 2));

    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5, now.month, now.day),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;

    final selected = DateTime(
      date.year, date.month, date.day, time.hour, time.minute,
    );
    if (!selected.isAfter(DateTime.now())) {
      setState(() => _error = '自定义截止时间必须晚于当前时间');
      return;
    }
    setState(() {
      _end = selected;
      _error = null;
    });
  }

  String _formatEnd(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final count = int.tryParse(_target.text.trim());
    final originalEnd = DateTime.tryParse(
      widget.taskDetail?['endTime']?.toString() ?? '',
    );
    final unchangedHistoricalEnd = widget.isEditing &&
        _end != null &&
        originalEnd != null &&
        _end!.isAtSameMomentAs(originalEnd);
    final invalidEnd = _end != null &&
        !_end!.isAfter(DateTime.now()) &&
        !unchangedHistoricalEnd;

    if (title.isEmpty || count == null || count < 1 || invalidEnd) {
      setState(() => _error = '请填写标题、正整数目标次数，并确保新设置的截止时间在未来');
      return;
    }
    // 根据用户选择，生成任务记录规则
    final Map<String, dynamic> recordRule;

    if (_recordMode == 'FIXED') {
      final fixedCount = int.tryParse(_fixedCount.text.trim());

      if (fixedCount == null || fixedCount <= 0) {
        setState(() => _error = '每次记录数量必须是正整数');
        return;
      }

      recordRule = {
        'mode': 'FIXED',
        'count': fixedCount,
      };
    } else {
      recordRule = {
        'mode': _recordMode,
      };
    }
    setState(() { _saving = true; _error = null; });
    try {
      if (widget.isEditing) {
        final detail = widget.taskDetail!;
        final taskId = (detail['taskId'] as num).toInt();

        await widget.api.updateTask(
          taskId: taskId,
          title: title,
          note: _note.text.trim(),
          targetCount: count,
          importance: _importance,
          difficulty: _difficulty,
          categoryId: _categoryId,
          endTime: _end,
          recordRule: recordRule,
        );
      } else {
        await widget.api.createTask(
          title: title,
          note: _note.text.trim(),
          targetCount: count,
          importance: _importance,
          difficulty: _difficulty,
          categoryId: _categoryId,
          endTime: _end,
          recordRule: recordRule,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => _sheetLayout(context,
    title: widget.isEditing ? '编辑任务' : '创建新任务',
    children: [
      TextField(controller: _title, maxLength: 100,
          decoration: const InputDecoration(labelText: '任务标题 *', hintText: '例如：复习 Java 集合')),
      const SizedBox(height: 10),
      TextField(controller: _note, maxLines: 2,
          decoration: const InputDecoration(labelText: '备注（可选）')),
      const SizedBox(height: 13),
      DropdownButtonFormField<int>(
        value: _categoryId,
        decoration: InputDecoration(
          labelText: '任务分类',
          helperText: _categoryError == null ? '分类可在任务库中自定义' : '分类加载失败，可重试',
        ),
        items: [
          const DropdownMenuItem<int>(value: 0, child: Text('未分类')),
          if (_categoryId != 0 &&
              !_categories.any((item) =>
                  (item['categoryId'] as num).toInt() == _categoryId))
            DropdownMenuItem<int>(
              value: _categoryId,
              child: const Text('当前分类（暂不可用）'),
            ),
          ..._categories.map((category) {
            final id = (category['categoryId'] as num).toInt();
            final enabled = category['enabled'] == true;
            final selected = id == _categoryId;
            return DropdownMenuItem<int>(
              value: id,
              enabled: enabled || selected,
              child: Text('${category['name'] ?? ''}${enabled ? '' : '（已停用）'}'),
            );
          }),
        ],
        onChanged: _categoriesLoading ? null : (value) {
          if (value != null) setState(() => _categoryId = value);
        },
      ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: _manageCategories,
          icon: const Icon(Icons.category_outlined, size: 18),
          label: const Text('管理分类'),
        ),
      ),
      const SizedBox(height: 13),
      TextField(controller: _target, keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: '目标次数 *')),

  const SizedBox(height: 15),

  const Align(
  alignment: Alignment.centerLeft,
  child: Text(
  '记录方式',
  style: TextStyle(fontWeight: FontWeight.w600),
  ),
  ),

  const SizedBox(height: 8),

  Wrap(
  spacing: 8,
  runSpacing: 8,
  children: [
  ChoiceChip(
  label: const Text('默认 +1'),
  selected: _recordMode == 'DEFAULT',
  onSelected: (_) {
  setState(() => _recordMode = 'DEFAULT');
  },
  ),
  ChoiceChip(
  label: const Text('固定数量'),
  selected: _recordMode == 'FIXED',
  onSelected: (_) {
  setState(() => _recordMode = 'FIXED');
  },
  ),
  ChoiceChip(
  label: const Text('手动输入'),
  selected: _recordMode == 'MANUAL',
  onSelected: (_) {
  setState(() => _recordMode = 'MANUAL');
  },
  ),
  ],
  ),

  if (_recordMode == 'FIXED') ...[
  const SizedBox(height: 10),
  TextField(
  controller: _fixedCount,
  keyboardType: TextInputType.number,
  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
  decoration: const InputDecoration(
  labelText: '每次记录数量 *',
  hintText: '例如：5',
  ),
  ),
  ],

  const SizedBox(height: 15),

      const SizedBox(height: 15),
      _rating('重要程度（参与优先级计算）', _importance, (n) => setState(() => _importance = n)),
      const SizedBox(height: 9),
      _rating('任务难度（奖励算法后续接入）', _difficulty, (n) => setState(() => _difficulty = n)),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _saving ? null : _pickEnd,
        icon: const Icon(Icons.event_available_rounded),
        label: Text(_end == null
            ? '设置自定义截止时间（可选）'
            : '截止时间：${_formatEnd(_end!)}'),
      ),
      if (!widget.isEditing && _end != null)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _saving ? null : () => setState(() { _end = null; _error = null; }),
            child: const Text('恢复默认截止时间（下一个凌晨 05:00）'),
          ),
        ),
      const SizedBox(height: 12),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.paleGreen,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(children: [
          Icon(Icons.schedule_rounded, size: 18, color: AppColors.forest),
          SizedBox(width: 8),
          Expanded(child: Text(
            '默认截止时间为下一个凌晨 05:00；长期任务可设置自定义截止时间。',
            style: TextStyle(fontSize: 12, color: AppColors.forest),
          )),
        ]),
      ),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 10),
          child: Text(_error!, style: const TextStyle(color: AppColors.rose, fontSize: 12))),
      const SizedBox(height: 16),
      SizedBox(width: double.infinity, child: FilledButton(
        onPressed: (_saving || _categoriesLoading) ? null : _save,
        style: FilledButton.styleFrom(backgroundColor: AppColors.forest,
          minimumSize: const Size.fromHeight(50)),
        child: Text(_saving ? (widget.isEditing ? '正在保存…' : '正在创建…') : (widget.isEditing ? '保存修改' : '创建任务')),
      )),
    ],
  );
}

class HabitComposer extends StatefulWidget {
  const HabitComposer({super.key, required this.api, required this.startDate});
  final TodayApi api;
  final String startDate;
  @override
  State<HabitComposer> createState() => _HabitComposerState();
}

class _HabitComposerState extends State<HabitComposer> {
  final _name = TextEditingController();
  final _note = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() { _name.dispose(); _note.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = '请输入习惯名称');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await widget.api.createDailyHabit(name: _name.text.trim(),
          note: _note.text.trim(), startDate: widget.startDate);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => _sheetLayout(context,
    title: '养成一个好习惯',
    children: [
      TextField(controller: _name, maxLength: 100,
          decoration: const InputDecoration(labelText: '习惯名称 *', hintText: '例如：每天阅读30分钟')),
      const SizedBox(height: 10),
      TextField(controller: _note, maxLines: 2,
          decoration: const InputDecoration(labelText: '备注（可选）')),
      const SizedBox(height: 14),
      const Chip(avatar: Icon(Icons.repeat_rounded, size: 18), label: Text('每日重复 · V0.1')),
      const SizedBox(height: 10),
      const Text('每周指定日期的习惯后续在习惯管理页开放。',
          style: TextStyle(color: AppColors.muted, fontSize: 12)),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 10),
          child: Text(_error!, style: const TextStyle(color: AppColors.rose, fontSize: 12))),
      const SizedBox(height: 17),
      SizedBox(width: double.infinity, child: FilledButton(
        onPressed: _saving ? null : _save,
        style: FilledButton.styleFrom(backgroundColor: AppColors.forest,
          minimumSize: const Size.fromHeight(50)),
        child: Text(_saving ? '正在创建…' : '创建每日习惯'),
      )),
    ],
  );
}

Widget _sheetLayout(BuildContext context, {required String title,
    required List<Widget> children}) => SafeArea(child: SingleChildScrollView(
  padding: EdgeInsets.fromLTRB(22, 6, 22, 22 + MediaQuery.of(context).viewInsets.bottom),
  child: Column(mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
        color: AppColors.ink)),
    const SizedBox(height: 19),
    ...children,
  ]),
));

Widget _rating(String label, int selected, ValueChanged<int> change) => Column(
  crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(fontSize: 13,
        fontWeight: FontWeight.w600, color: AppColors.ink)),
    const SizedBox(height: 7),
    Row(children: [1, 2, 3, 4, 5].map((number) => Expanded(
      child: Padding(padding: const EdgeInsets.only(right: 5),
        child: OutlinedButton(
          onPressed: () => change(number),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(36, 40), padding: EdgeInsets.zero,
            foregroundColor: selected == number ? Colors.white : AppColors.forest,
            backgroundColor: selected == number ? AppColors.forest : Colors.white,
            side: BorderSide(color: selected == number ? AppColors.forest : AppColors.border)),
          child: Text('$number'),
        ),
      ),
    )).toList()),
  ],
);


