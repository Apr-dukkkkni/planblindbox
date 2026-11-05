import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/wellbeing_repository.dart';
import '../theme/app_theme.dart';

const _emojiPalette = <String>[
  '😄', '😃', '😁', '🥳', '🤩', '😍', '🥰', '🤗', '😎', '😇',
  '🙂', '🙃', '🥲', '😭', '😞', '😔', '😫', '😤', '😠', '🤯',
  '😱', '😴', '🥱', '🤔', '😶', '🫠', '🤒', '🤧', '🤢', '🥹',
  '💪', '❤️', '💖', '🌈', '🌻', '🌸', '🍀', '⭐', '☀️', '🌙',
];

/// 点击悬浮球“情绪”，弹出四种常用情绪和用户自定义表情。
Future<MoodChoice?> showMoodPicker(
    BuildContext context, WellbeingRepository repository) {
  return showModalBottomSheet<MoodChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _MoodPickerSheet(repository: repository),
  );
}

class _MoodPickerSheet extends StatefulWidget {
  const _MoodPickerSheet({required this.repository});
  final WellbeingRepository repository;

  @override
  State<_MoodPickerSheet> createState() => _MoodPickerSheetState();
}

class _MoodPickerSheetState extends State<_MoodPickerSheet> {
  late Future<List<MoodChoice>> _moods;

  @override
  void initState() {
    super.initState();
    _moods = widget.repository.getMoods();
  }

  Future<void> _addMood() async {
    final controller = TextEditingController();
    String? chosen;
    String? error;
    try {
      final added = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('自定义情绪'),
            content: SizedBox(
              width: 350,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(controller: controller, maxLength: 12,
                    decoration: const InputDecoration(labelText: '情绪名称', hintText: '例如：充满期待')),
                  const SizedBox(height: 8),
                  const Align(alignment: Alignment.centerLeft,
                    child: Text('选择专属表情（使用过的图标不能重复）')),
                  const SizedBox(height: 10),
                  FutureBuilder<List<MoodChoice>>(
                    future: _moods,
                    builder: (context, snapshot) {
                      final used = (snapshot.data ?? MoodChoice.defaults)
                        .map((choice) => choice.emoji).toSet();
                      return Wrap(spacing: 5, runSpacing: 5, children: [
                        for (final emoji in _emojiPalette)
                          ChoiceChip(
                            label: Text(emoji, style: const TextStyle(fontSize: 22)),
                            selected: chosen == emoji,
                            onSelected: used.contains(emoji)
                                ? null : (_) => setDialogState(() => chosen = emoji),
                          ),
                      ]);
                    },
                  ),
                  if (error != null) Padding(
                    padding: const EdgeInsets.only(top: 9),
                    child: Text(error!, style: const TextStyle(color: Colors.red)),
                  ),
                ]),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消')),
              FilledButton(onPressed: () async {
                if (chosen == null) {
                  setDialogState(() => error = '请选择尚未使用的表情');
                  return;
                }
                try {
                  await widget.repository.addCustomMood(controller.text, chosen!);
                  if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                } catch (e) {
                  setDialogState(() => error = '$e');
                }
              }, child: const Text('保存')),
            ],
          ),
        ),
      );
      if (added == true && mounted) {
        setState(() => _moods = widget.repository.getMoods());
      }
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('记录今天的情绪', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
          const SizedBox(height: 6),
          const Text('选择一种心情，稍后可在签到日历中查看。',
            style: TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 14),
          SizedBox(height: 185, child: FutureBuilder<List<MoodChoice>>(
            future: _moods,
            builder: (context, snapshot) {
              if (snapshot.hasError) return Text('加载情绪失败：${snapshot.error}');
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              return SingleChildScrollView(child: Wrap(spacing: 9, runSpacing: 9,
                children: [
                  for (final mood in snapshot.data!)
                    ActionChip(
                      avatar: Text(mood.emoji, style: const TextStyle(fontSize: 21)),
                      label: Text(mood.name),
                      onPressed: () => Navigator.pop(context, mood),
                    ),
                ]));
            },
          )),
          const SizedBox(height: 10),
          OutlinedButton.icon(onPressed: _addMood,
            icon: const Icon(Icons.add_rounded), label: const Text('自定义情绪和表情')),
        ],
      ),
    ),
  );
}

/// 选择今日是否经期：不预测周期，不修改登录签到或水滴奖励。
Future<void> showPeriodRecorder(BuildContext context,
    WellbeingRepository repository) async {
  final entry = await repository.getDay(DateTime.now());
  if (!context.mounted) return;
  bool current = entry.period;
  await showDialog<void>(context: context,
    builder: (dialogContext) => StatefulBuilder(builder: (context, setState) => AlertDialog(
      title: const Text('记录今天的生理期'),
      content: SwitchListTile(
        title: const Text('今天处于生理期'),
        subtitle: const Text('仅保存在此设备中，可在签到日历修改其他日期。'),
        value: current,
        onChanged: (value) => setState(() => current = value),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消')),
        FilledButton(onPressed: () async {
          await repository.setPeriod(DateTime.now(), current);
          if (dialogContext.mounted) Navigator.pop(dialogContext);
        }, child: const Text('保存')),
      ],
    )));
}

/// 日历：绿色=当日登录签到；粉色=女性用户记录了生理期；
/// 圆圈里的表情=当日情绪；右下角的笔=存在日记。
class WellbeingCalendarDialog extends StatefulWidget {
  const WellbeingCalendarDialog({super.key,
    required this.repository, required this.isFemale,
    this.initialDate, this.openDiary = false});
  final WellbeingRepository repository;
  final bool isFemale;
  final DateTime? initialDate;
  final bool openDiary;

  @override
  State<WellbeingCalendarDialog> createState() => _WellbeingCalendarDialogState();
}

class _WellbeingCalendarDialogState extends State<WellbeingCalendarDialog> {
  late DateTime _visibleMonth;
  late DateTime _selected;
  late bool _diarySide;
  Map<String, WellbeingEntry> _days = {};
  WellbeingEntry? _selectedEntry;
  final TextEditingController _journal = TextEditingController();
  bool _loading = true;
  int _monthSequence = 0;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialDate ?? DateTime.now();
    _visibleMonth = DateTime(_selected.year, _selected.month);
    _diarySide = widget.openDiary;
    _loadMonth();
    if (_diarySide) _loadSelected();
  }

  @override
  void dispose() {
    _journal.dispose();
    super.dispose();
  }

  Future<void> _loadMonth() async {
    final sequence = ++_monthSequence;
    setState(() { _loading = true; _error = null; });
    try {
      final result = await widget.repository.getMonth(_visibleMonth);
      if (mounted && sequence == _monthSequence) setState(() => _days = result);
    } catch (e) {
      if (mounted && sequence == _monthSequence) setState(() => _error = '$e');
    } finally {
      if (mounted && sequence == _monthSequence) setState(() => _loading = false);
    }
  }

  Future<void> _loadSelected() async {
    final date = _selected;
    try {
      final entry = await widget.repository.getDay(date);
      if (!mounted || date != _selected) return;
      setState(() => _selectedEntry = entry);
      _journal.text = entry.diary;
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _selectDay(DateTime date) {
    setState(() {
      _selected = date;
      _selectedEntry = null;
      _diarySide = true;
    });
    _journal.clear();
    _loadSelected();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.repository.saveDiary(_selected, _journal.text);
      await _loadSelected();
      await _loadMonth();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('日记已保存到本地')));
      }
    } catch (e) {
      if (mounted) setState(() => _error = '保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _selectMood() async {
    final mood = await showMoodPicker(context, widget.repository);
    if (mood == null) return;
    await widget.repository.saveMood(_selected, mood);
    await _loadSelected();
    await _loadMonth();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 28),
    child: SizedBox(
      width: 410,
      height: math.max(250, math.min(
          MediaQuery.sizeOf(context).height -
          MediaQuery.viewInsetsOf(context).bottom - 80, 550.0)).toDouble(),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: _diarySide ? 1.0 : 0.0),
        duration: const Duration(milliseconds: 430),
        curve: Curves.easeInOut,
        builder: (context, flip, _) {
          final showBack = flip > 0.5;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()..setEntry(3, 2, 0.001)..rotateY(math.pi * flip),
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.rotationY(showBack ? math.pi : 0),
              child: showBack ? _diaryView() : _calendarView(),
            ),
          );
        },
      ),
    ),
  );

  Widget _calendarView() {
    final first = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final offset = first.weekday - 1;
    final count = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
    return SingleChildScrollView(child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          const Expanded(child: Text('签到日历', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18))),
          IconButton(icon: const Icon(Icons.close), tooltip: '关闭',
            onPressed: () => Navigator.pop(context)),
        ]),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(onPressed: () {
            _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1);
            _loadMonth();
          }, icon: const Icon(Icons.chevron_left)),
          Expanded(child: Text('${_visibleMonth.year} 年 ${_visibleMonth.month} 月',
            textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
          IconButton(onPressed: () {
            _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1);
            _loadMonth();
          }, icon: const Icon(Icons.chevron_right)),
        ]),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 11)),
        Row(children: [
          for (final label in const ['一', '二', '三', '四', '五', '六', '日'])
            Expanded(child: Center(child: Text(label,
              style: const TextStyle(color: AppColors.muted, fontSize: 12)))),
        ]),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: offset + count,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7, childAspectRatio: 0.96),
          itemBuilder: (context, index) {
            if (index < offset) return const SizedBox.shrink();
            final day = index - offset + 1;
            final date = DateTime(_visibleMonth.year, _visibleMonth.month, day);
            final data = _days[WellbeingRepository.dateKey(date)];
            final marked = data?.signedIn == true ||
                (widget.isFemale && data?.period == true);
            final circle = widget.isFemale && data?.period == true
                ? const Color(0xFFF7C5D8)
                : const Color(0xFFC9EFD1);
            return InkWell(
              borderRadius: BorderRadius.circular(28),
              onTap: () => _selectDay(date),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Container(
                  decoration: BoxDecoration(shape: BoxShape.circle,
                    color: marked ? circle : null,
                    border: WellbeingRepository.dateKey(date) ==
                        WellbeingRepository.dateKey(DateTime.now())
                      ? Border.all(color: AppColors.forest) : null),
                  child: Stack(alignment: Alignment.center, children: [
                    Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text('$day', style: const TextStyle(fontSize: 12)),
                      if (data?.emoji != null)
                        Text(data!.emoji!, style: const TextStyle(fontSize: 15)),
                    ]),
                    if (data?.hasDiary == true)
                      const Positioned(bottom: 1, right: 2,
                        child: Icon(Icons.edit_rounded, size: 10, color: AppColors.forest)),
                  ]),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 8, alignment: WrapAlignment.center, children: [
          const _CalendarLegend(color: Color(0xFFC9EFD1), label: '已签到'),
          if (widget.isFemale) const _CalendarLegend(
            color: Color(0xFFF7C5D8), label: '生理期'),
          const _CalendarLegend(color: Colors.transparent, label: '有日记', pencil: true),
        ]),
      ]),
    ));
  }

  Widget _diaryView() {
    final entry = _selectedEntry;
    final key = WellbeingRepository.dateKey(_selected);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          IconButton(onPressed: () {
            FocusScope.of(context).unfocus();
            setState(() => _diarySide = false);
            _loadMonth();
          }, icon: const Icon(Icons.arrow_back), tooltip: '返回日历'),
          Expanded(child: Text(key, style: const TextStyle(fontWeight: FontWeight.w700),
            textAlign: TextAlign.center)),
          IconButton(onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close), tooltip: '关闭'),
        ]),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Text(entry?.emoji ?? '🙂', style: const TextStyle(fontSize: 29)),
          title: Text(entry?.mood ?? '记录当天的心情'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _selectMood,
        ),
        if (widget.isFemale)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('当天处于生理期'),
            value: entry?.period ?? false,
            onChanged: (value) async {
              await widget.repository.setPeriod(_selected, value);
              await _loadSelected();
              await _loadMonth();
            },
          ),
        const Align(alignment: Alignment.centerLeft,
          child: Text('今日感受', style: TextStyle(fontWeight: FontWeight.w700))),
        const SizedBox(height: 8),
        Expanded(child: TextField(
          controller: _journal,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          decoration: const InputDecoration(
            hintText: '今天发生了什么？有什么想记录的心情……',
            border: OutlineInputBorder(),
          ),
        )),
        if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: Text(_saving ? '保存中…' : '保存日记'),
        )),
      ]),
    );
  }
}

class _CalendarLegend extends StatelessWidget {
  const _CalendarLegend({required this.color, required this.label, this.pencil = false});
  final Color color;
  final String label;
  final bool pencil;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    if (pencil) const Icon(Icons.edit_outlined, size: 13, color: AppColors.forest)
    else Container(width: 13, height: 13,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 4),
    Text(label, style: const TextStyle(fontSize: 11)),
  ]);
}

/// 成长统计页的独立日记目录：倒序展示并支持关键词搜索。
class DiaryListPage extends StatefulWidget {
  const DiaryListPage({super.key, required this.repository, required this.isFemale});
  final WellbeingRepository repository;
  final bool isFemale;

  @override
  State<DiaryListPage> createState() => _DiaryListPageState();
}

class _DiaryListPageState extends State<DiaryListPage> {
  final TextEditingController _search = TextEditingController();
  List<WellbeingEntry> _entries = [];
  bool _loading = true;
  int _request = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final request = ++_request;
    setState(() { _loading = true; _error = null; });
    try {
      final result = await widget.repository.getDiaries(query: _search.text);
      if (mounted && request == _request) setState(() => _entries = result);
    } catch (e) {
      if (mounted && request == _request) setState(() => _error = '$e');
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _open(WellbeingEntry entry) async {
    await showDialog<void>(context: context, builder: (_) => WellbeingCalendarDialog(
      repository: widget.repository,
      isFemale: widget.isFemale,
      initialDate: DateTime.parse(entry.date),
      openDiary: true,
    ));
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('全部日记')),
    body: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: TextField(
          controller: _search,
          onChanged: (_) => _refresh(),
          decoration: InputDecoration(
            hintText: '搜索日记关键词或日期',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(onPressed: () {
              _search.clear();
              _refresh();
            }, icon: const Icon(Icons.close)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
      if (_loading) const LinearProgressIndicator(minHeight: 2),
      if (_error != null) Padding(padding: const EdgeInsets.all(12),
        child: Text(_error!, style: const TextStyle(color: Colors.red))),
      Expanded(child: RefreshIndicator(
        onRefresh: _refresh,
        child: _entries.isEmpty
          ? ListView(children: const [SizedBox(height: 110),
              Center(child: Text('还没有匹配的日记记录'))])
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 30),
              itemCount: _entries.length,
              itemBuilder: (context, index) {
                final entry = _entries[index];
                return Card(child: ListTile(
                  leading: Text(entry.emoji ?? '📖', style: const TextStyle(fontSize: 26)),
                  title: Text(entry.date, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(entry.diary, maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(entry),
                ));
              },
            ),
      )),
    ]),
  );
}
