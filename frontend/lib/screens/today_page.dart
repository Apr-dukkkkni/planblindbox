import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/today_api.dart';
import '../models/today_models.dart';
import '../theme/app_theme.dart';
import '../widgets/dashboard_cards.dart';

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
    if (task.remainingCount <= 0) return;
    final count = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _RecordCountSheet(task: task),
    );
    if (count == null || !mounted) return;
    await _execute('task-${task.id}', () => widget.api.completeTask(
          taskId: task.id, actualCount: count));
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

  Future<void> _createHabit() async {
    final succeeded = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => HabitComposer(api: widget.api,
          startDate: _data?.date ?? _todayString()),
    );
    if (succeeded == true && mounted) {
      _message('每日习惯创建成功');
      await _load();
    }
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
                DashboardHero(data: data),
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
                    padding: const EdgeInsets.only(bottom: 11),
                    child: TaskTile(task: task, todayDate: data.date,
                      busy: _busy.contains('task-${task.id}'),
                      onComplete: () => _completeTask(task)),
                  )),
                const SizedBox(height: 18),
                SectionHeading(title: '每日习惯',
                    subtitle: '持续行动，比偶尔冲刺更重要',
                    actionLabel: '新建习惯', onAction: _createHabit),
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
        _chip('importance', '按重要程度'),
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
  const TaskComposer({super.key, required this.api});
  final TodayApi api;
  @override
  State<TaskComposer> createState() => _TaskComposerState();
}

class _TaskComposerState extends State<TaskComposer> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  final _target = TextEditingController(text: '1');
  int _importance = 3;
  int _difficulty = 3;
  DateTime _end = DateTime.now().add(const Duration(hours: 2));
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose(); _note.dispose(); _target.dispose(); super.dispose();
  }

  Future<void> _pickEnd() async {
    final date = await showDatePicker(context: context,
        initialDate: _end,
        firstDate: DateTime.now().subtract(const Duration(days: 1)),
        lastDate: DateTime.now().add(const Duration(days: 365 * 5)));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context,
        initialTime: TimeOfDay.fromDateTime(_end));
    if (time == null || !mounted) return;
    setState(() => _end = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final count = int.tryParse(_target.text.trim());
    if (title.isEmpty || count == null || count < 1 || _end.isBefore(DateTime.now())) {
      setState(() => _error = '请填写标题、正整数目标次数以及未来的截止时间');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await widget.api.createTask(title: title, note: _note.text.trim(),
          targetCount: count, importance: _importance,
          difficulty: _difficulty, endTime: _end);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => _sheetLayout(context,
    title: '创建新任务',
    children: [
      TextField(controller: _title, maxLength: 100,
          decoration: const InputDecoration(labelText: '任务标题 *', hintText: '例如：复习 Java 集合')),
      const SizedBox(height: 10),
      TextField(controller: _note, maxLines: 2,
          decoration: const InputDecoration(labelText: '备注（可选）')),
      const SizedBox(height: 13),
      TextField(controller: _target, keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: '目标次数 *')),
      const SizedBox(height: 15),
      _rating('重要程度（决定排序）', _importance, (n) => setState(() => _importance = n)),
      const SizedBox(height: 9),
      _rating('任务难度（奖励算法后续接入）', _difficulty, (n) => setState(() => _difficulty = n)),
      const SizedBox(height: 12),
      OutlinedButton.icon(onPressed: _pickEnd, icon: const Icon(Icons.event_outlined),
          label: Text('截止：${_end.month}/${_end.day} ${_end.hour.toString().padLeft(2, '0')}:${_end.minute.toString().padLeft(2, '0')}')),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 10),
          child: Text(_error!, style: const TextStyle(color: AppColors.rose, fontSize: 12))),
      const SizedBox(height: 16),
      SizedBox(width: double.infinity, child: FilledButton(
        onPressed: _saving ? null : _save,
        style: FilledButton.styleFrom(backgroundColor: AppColors.forest,
          minimumSize: const Size.fromHeight(50)),
        child: Text(_saving ? '正在创建…' : '创建任务'),
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

String _todayString() {
  final now = DateTime.now();
  String pad(int value) => value.toString().padLeft(2, '0');
  return '${now.year}-${pad(now.month)}-${pad(now.day)}';
}
