import 'package:flutter/material.dart';

import '../data/habit_api.dart';
import '../data/today_api.dart';

class ArchiveHabitsPage extends StatefulWidget {
  const ArchiveHabitsPage({
    super.key,
    required this.api,
  });

  final TodayApi api;

  @override
  State<ArchiveHabitsPage> createState() =>
      _ArchiveHabitsPageState();
}

class _ArchiveHabitsPageState
    extends State<ArchiveHabitsPage> {

  late final HabitApi _habitApi;

  bool _loading = true;
  String? _error;

  List<_ArchivedHabitItem> _items = [];

  @override
  void initState() {
    super.initState();

    _habitApi = HabitApi(
      baseUrl: widget.api.baseUrl,
      userId: widget.api.userId,
    );

    _load();
  }

  @override
  void dispose() {
    _habitApi.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final habits = await _habitApi.getArchived();

      /*
       * 继续查询每个习惯原来的打卡进度。
       *
       * habit_record 没有被删除，因此：
       * currentStreak
       * totalCheckInDays
       * checkedInToday
       *
       * 都还是原来的历史数据。
       */
      final items = await Future.wait(
        habits.map((habit) async {
          HabitCheckInStats? stats;

          try {
            stats =
            await _habitApi.getCheckInStats(habit.id);
          } catch (_) {
            /*
             * 某个进度查询失败，不影响整个归档列表显示。
             */
          }

          return _ArchivedHabitItem(
            habit: habit,
            stats: stats,
          );
        }),
      );

      if (!mounted) return;

      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _restore(
      _ArchivedHabitItem item,
      ) async {

    final habit = item.habit;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('恢复习惯'),
          content: Text(
            '确定恢复「${habit.name}」吗？\n\n'
                '以前的打卡记录不会删除，恢复后可以继续打卡。',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, true),
              child: const Text('恢复'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await _habitApi.restore(habit.id);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已恢复「${habit.name}」，历史打卡记录已保留。',
          ),
        ),
      );

      /*
       * 恢复成功后重新查询数据库。
       * 因为它已经变为 ACTIVE，
       * 所以自然不会再出现在归档列表里。
       */
      await _load();
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('恢复失败：$error'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('归档习惯'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const Icon(
              Icons.refresh_rounded,
            ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(
                  Icons.refresh_rounded,
                ),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (_items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 60,
            ),
            SizedBox(height: 12),
            Text(
              '暂无归档习惯',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics:
        const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _items.length,
        separatorBuilder: (_, __) =>
        const SizedBox(height: 10),
        itemBuilder: (context, index) {
          return _habitCard(_items[index]);
        },
      ),
    );
  }

  Widget _habitCard(
      _ArchivedHabitItem item,
      ) {

    final habit = item.habit;
    final stats = item.stats;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.archive_outlined,
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: Text(
                    habit.name,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight:
                      FontWeight.w700,
                    ),
                  ),
                ),

                FilledButton.tonalIcon(
                  onPressed: () =>
                      _restore(item),
                  icon: const Icon(
                    Icons.restore_rounded,
                    size: 18,
                  ),
                  label: const Text('恢复'),
                ),
              ],
            ),

            if (habit.note.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(habit.note),
            ],

            const SizedBox(height: 12),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _tag(
                  '重要 ${habit.importance}',
                ),
                _tag(
                  '困难 ${habit.difficulty}',
                ),
                _tag(
                  habit.repeatLabel,
                ),
              ],
            ),

            const Divider(height: 24),

            if (stats == null)
              const Text(
                '暂时无法读取打卡进度',
              )
            else
              Row(
                children: [
                  Expanded(
                    child: _progress(
                      '累计打卡',
                      '${stats.totalCheckInDays} 天',
                    ),
                  ),

                  Expanded(
                    child: _progress(
                      '连续记录',
                      '${stats.currentStreak} 天',
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _tag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest,
        borderRadius:
        BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _progress(
      String title,
      String value,
      ) {
    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .bodySmall,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ArchivedHabitItem {
  const _ArchivedHabitItem({
    required this.habit,
    required this.stats,
  });

  final HabitInfo habit;
  final HabitCheckInStats? stats;
}