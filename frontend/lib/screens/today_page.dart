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
import '../services/cloud_archive_service.dart';
import 'cloud_archive_pages.dart';
import '../data/wellbeing_repository.dart';
import 'wellbeing_pages.dart';


class TodayPage extends StatefulWidget {
  const TodayPage({
    super.key,
    required this.api,
    this.onOpenModDrawer,
    this.archiveController,
    this.isFemale = false,
    this.wellbeingUserId = -1,
  });

  final TodayApi api;
  final VoidCallback? onOpenModDrawer;
  final CloudArchiveController? archiveController;
  final bool isFemale;
  final int wellbeingUserId;

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
    // 3. 用户点了取消（count==null） / 页面已经销毁，直接返回，不写入本地数据
    if (count == null || !mounted) return;
    // 4. 调用封装好的 _execute 函数：上锁 → 调用本地 Repository 的 completeTask，参数 taskId + 用户填的数量count
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

    // 3. 通过现有执行流程提交到本地数据库
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


  Future<void> _openTaskLibrary() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TaskLibraryPage(
          api: widget.api,
          onEditTask: _editTaskFromLibrary,
        ),
      ),
    );

    // 从任务库返回后，重新读取首页数据
    if (mounted) {
      await _load();
    }
  }




  Future<void> _openArchive() async {
    final archive = widget.archiveController;

    if (archive == null) {
      _message('云存档控制器尚未初始化', error: true);
      return;
    }

    try {
      final restored = await openCloudArchive(
        context,
        archive,
      );

      if (restored && mounted) {
        await _load();
      }
    } catch (error) {
      if (mounted) {
        _message('打开存档失败：$error', error: true);
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

  Future<void> _openCalendar() async {
    await showDialog<void>(
      context: context,
      builder: (_) => WellbeingCalendarDialog(
        repository: WellbeingRepository(
          userId: widget.wellbeingUserId, signInUserId: widget.api.userId),
        isFemale: widget.isFemale,
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
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              children: [
                // 固定顶部导航：滚动仅发生在下方 ListView。
                Container(
                  width: double.infinity,
                  color: const Color(0xFFEAF2EC),
                  padding: const EdgeInsets.fromLTRB(20, 15, 20, 15),
                  child: _topBar(),
                ),
                Expanded(child: RefreshIndicator(
              color: AppColors.forest,
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 136),
                children: [

                  // ==========================
                  // 首页主体内容
                  // ==========================
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      20, 18, 20, 0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                        // 加载进度
                        if (_loading && data != null)
                          const LinearProgressIndicator(
                            minHeight: 2,
                            color: AppColors.leaf,
                          ),

                        // 加载状态 / 错误状态 / 正常内容
                        if (_loading && data == null)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 100),
                            child: Center(
                              child: CircularProgressIndicator(),
                            ),
                          )
                        else if (data == null)
                          _failure(_error ?? '尚未获取到今日数据')
                        else ...[

                            // 错误提示
                            if (_error != null) ...[
                              _errorBanner(_error!),
                              const SizedBox(height: 12),
                            ],

                            // 今日成长概览
                            DashboardHero(data: data, onCalendar: _openCalendar),

                            // 原资产展示已从首页移除
                            // 不删除资产组件及相关业务逻辑

                            const SizedBox(height: 17),

                            // ==========================
                            // 今日任务
                            // ==========================
                            Row(children: [
                              const Expanded(child: Text('今日任务',
                                style: TextStyle(color: AppColors.ink,
                                  fontSize: 20, fontWeight: FontWeight.w800))),
                              _sortChips(),
                            ]),

                            const SizedBox(height: 10),

                            if (data.tasks.isEmpty)
                              const SizedBox(
                                width: double.infinity,
                                child: EmptySection(
                                  message: '今天还没有任务，添加一个小目标吧',
                                  icon: Icons.task_alt_rounded,
                                ),
                              )
                            else
                              ...data.tasks.map(
                                    (task) => Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: 11,
                                  ),
                                  child: TaskTile(
                                    task: task,
                                    todayDate: data.date,
                                    busy: _busy.contains(
                                      'task-${task.id}',
                                    ),
                                    onComplete: () => _recordTask(task),
                                    onEdit: () => _editTask(task),
                                  ),
                                ),
                              ),

                            const SizedBox(height: 18),

                            // ==========================
                            // 每日习惯
                            // ==========================
                            Row(children: [
                              const Expanded(child: Text('每日习惯',
                                style: TextStyle(color: AppColors.ink,
                                  fontSize: 20, fontWeight: FontWeight.w800))),
                              IconButton.outlined(
                                tooltip: '管理习惯',
                                onPressed: _openHabitManagement,
                                icon: const Icon(Icons.tune_rounded,
                                  color: AppColors.forest),
                              ),

                            ]),

                            const SizedBox(height: 13),

                            if (data.habits.isEmpty)
                              const SizedBox(
                                width: double.infinity,
                                child: EmptySection(
                                  message: '今天没有计划打卡的习惯',
                                  icon: Icons.spa_outlined,
                                ),
                              )
                            else
                              ...data.habits.map(
                                    (habit) => Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: 11,
                                  ),
                                  child: HabitTile(
                                    habit: habit,
                                    busy: _busy.contains(
                                      'habit-${habit.id}',
                                    ),
                                    onCheckIn: () => _checkIn(habit),
                                  ),
                                ),
                              ),

                            const SizedBox(height: 14),

                            const Center(
                              child: Text(
                                '今天也比昨天更进一步 ✨',
                                style: TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                      ],
                    ),
                  ),
                ],
              ),
            )),
              ],
            ),
          ),
        ),
      ),
    );
  }



  Widget _topBar() => Row(
    children: [
      Material(
        color: AppColors.paleGreen,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: widget.onOpenModDrawer,
          child: const SizedBox(
            width: 45,
            height: 45,
            child: Icon(
              Icons.eco_rounded,
              color: AppColors.forest,
              size: 27,
            ),
          ),
        ),
      ),

      const SizedBox(width: 11),

      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PlanBlindBox',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
                fontSize: 19,
              ),
            ),
            Text(
              '让成长变得看得见',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),

      // 原刷新按钮 -> 存档
      IconButton(
        tooltip: '云端存档',
        onPressed: _openArchive,
        icon: const Icon(
          Icons.cloud_upload_outlined,
          color: AppColors.forest,
        ),
      ),

      // 任务库放到存档右侧
      IconButton(
        tooltip: '我的任务库',
        onPressed: _openTaskLibrary,
        icon: const Icon(
          Icons.folder_open_outlined,
          color: AppColors.forest,
        ),
      ),
    ],
  );


  Widget _sortChips() => PopupMenuButton<String>(
    tooltip: '任务排序',
    initialValue: _sort,
    onSelected: (value) {
      if (_sort == value) return;
      setState(() => _sort = value);
      _load();
    },
    itemBuilder: (context) => const [
      PopupMenuItem(value: 'time', child: Text('按时间')),
      PopupMenuItem(value: 'importance', child: Text('按优先级')),
    ],
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border), color: Colors.white),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.sort_rounded, size: 17, color: AppColors.forest),
        const SizedBox(width: 4),
        Text(_sort == 'time' ? '时间' : '优先级',
          style: const TextStyle(fontSize: 12, color: AppColors.forest)),
        const Icon(Icons.arrow_drop_down, size: 18, color: AppColors.forest),
      ]),
    ),
  );

  Widget _failure(String error) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 72),
        child: Column(children: [
          const Icon(Icons.storage_rounded, size: 50, color: AppColors.muted),
          const SizedBox(height: 16),
          const Text('本地数据暂不可用',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: 9),
          Text(error, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 16),
          FilledButton(onPressed: _load, child: const Text('重新加载')),
          const SizedBox(height: 14),
          const Text('核心功能使用本机 SQLite 保存，无需启动 Spring Boot。',
              style: TextStyle(fontSize: 11, color: AppColors.muted)),
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
  bool _expanded = false; // 创建时只显示标题和创建按钮
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
    _expanded = true; // 编辑时展开，以便看见已有配置
    _categoryId = (detail['categoryId'] as num?)?.toInt() ?? 0;
    _loadCategories();

    // 1. 初始化基础信息
    _title.text = detail['title']?.toString() ?? '';
    _note.text = detail['note']?.toString() ?? '';
    _target.text = detail['targetCount']?.toString() ?? '1';

    // 2. 初始化重要程度和难度
    _importance = (detail['importance'] as num?)?.toInt() ?? 3;
    _difficulty = (detail['difficulty'] as num?)?.toInt() ?? 3;

    // 编辑时保留当前截止时间；新建任务默认不指定，由本地业务规则设置为下一个凌晨 05:00。
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
    title: widget.isEditing ? '编辑任务' : '新建任务',
    children: [
      TextField(
        controller: _title,
        maxLength: 100,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          labelText: '任务标题 *', hintText: '例如：复习 Java 集合',
        ),
      ),
      if (_expanded) ...[
        const SizedBox(height: 6),
        TextField(controller: _note, maxLines: 2,
          decoration: const InputDecoration(labelText: '备注（可选）')),
        const SizedBox(height: 12),
        TextField(
          controller: _target,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: '目标次数 *'),
        ),
        const SizedBox(height: 13),
        const Text('记录方式', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(spacing: 7, runSpacing: 5, children: [
          for (final option in const [
            ('DEFAULT','默认 +1'), ('FIXED','固定数量'), ('MANUAL','手动输入')
          ])
            ChoiceChip(
              showCheckmark: false,
              label: Text(option.$2),
              selected: _recordMode == option.$1,
              onSelected: (_) => setState(() => _recordMode = option.$1),
            ),
        ]),
        if (_recordMode == 'FIXED') ...[
          const SizedBox(height: 8),
          TextField(controller: _fixedCount,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: '每次记录数量 *')),
        ],
        const SizedBox(height: 14),
        _rating('重要程度', _importance,
          (value) => setState(() => _importance = value)),
        const SizedBox(height: 9),
        _rating('困难程度', _difficulty,
          (value) => setState(() => _difficulty = value)),
        const SizedBox(height: 13),
        Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: _saving ? null : _pickEnd,
            icon: const Icon(Icons.event_available_rounded, size: 18),
            label: Text(_end == null ? '截止时间' : _formatEnd(_end!),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          )),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(
            onPressed: _saving ? null : _manageCategories,
            icon: const Icon(Icons.category_outlined, size: 18),
            label: const Text('管理分类'),
          )),
        ]),
        if (!widget.isEditing && _end != null)
          Align(alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _saving ? null : () => setState(() => _end = null),
              child: const Text('恢复默认截止时间（次日 05:00）'),
            )),
        const SizedBox(height: 12),
        Row(children: [
          const Text('任务分类', style: TextStyle(fontWeight: FontWeight.w700)),
          if (_categoriesLoading) ...[
            const SizedBox(width: 8),
            const SizedBox(width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ]),
        const SizedBox(height: 7),
        if (_categoryError != null)
          Text('分类加载失败：$_categoryError',
            style: const TextStyle(fontSize: 12, color: AppColors.rose)),
        Wrap(spacing: 7, runSpacing: 5, children: [
          ChoiceChip(
            showCheckmark: false,
            label: const Text('未分类'),
            selected: _categoryId == 0,
            onSelected: (_) => setState(() => _categoryId = 0),
          ),
          for (final category in _categories)
            if (category['enabled'] == true ||
                (category['categoryId'] as num).toInt() == _categoryId)
              ChoiceChip(
                showCheckmark: false,
                label: Text('${category['name']}${category['enabled'] == true ? '' : '（已停用）'}'),
                selected: _categoryId == (category['categoryId'] as num).toInt(),
                onSelected: category['enabled'] == true
                    ? (_) => setState(() =>
                        _categoryId = (category['categoryId'] as num).toInt())
                    : null,
              ),
        ]),
      ],
      if (!widget.isEditing)
        Center(child: TextButton.icon(
          onPressed: _saving ? null : () => setState(() => _expanded = !_expanded),
          icon: Icon(_expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
          label: Text(_expanded ? '收起选项' : '展开更多'),
        )),
      if (_error != null)
        Padding(padding: const EdgeInsets.only(bottom: 8),
          child: Text(_error!,
            style: const TextStyle(color: AppColors.rose, fontSize: 12))),
      const SizedBox(height: 9),
      SizedBox(width: double.infinity, child: FilledButton(
        onPressed: _saving ? null : _save,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.forest,
          minimumSize: const Size.fromHeight(50)),
        child: Text(_saving
          ? (widget.isEditing ? '正在保存…' : '正在创建…')
          : (widget.isEditing ? '保存修改' : '创建任务')),
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

/// 重要程度与困难程度采用紧凑标签，点击立即切换选中值。
Widget _rating(String label, int selected, ValueChanged<int> change) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(label, style: const TextStyle(fontSize: 13,
      fontWeight: FontWeight.w600, color: AppColors.ink)),
    const SizedBox(height: 7),
    Row(children: [
      for (var number = 1; number <= 5; number++)
        Expanded(child: Padding(
          padding: const EdgeInsets.only(right: 5),
          child: ChoiceChip(
            showCheckmark: false,
            label: SizedBox(width: double.infinity,
              child: Text('$number', textAlign: TextAlign.center,
                style: TextStyle(color: selected == number
                  ? AppColors.deepForest : AppColors.muted))),
            selected: selected == number,
            onSelected: (_) => change(number),
            labelPadding: EdgeInsets.zero,
          ),
        )),
    ]),
  ],
);
