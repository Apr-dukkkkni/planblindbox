/// 后端 TodayResponse 的精简强类型映射；后端新增字段不影响旧客户端。
class TodayData {
  const TodayData({
    required this.date,
    required this.tasks,
    required this.habits,
    required this.assets,
    required this.summary,
  });

  final String date;
  final List<TodayTask> tasks;
  final List<TodayHabit> habits;
  final TodayAssets assets;
  final TodaySummary summary;

  factory TodayData.fromJson(Map<String, dynamic> json) {
    return TodayData(
      date: json['date']?.toString() ?? '',
      tasks: _maps(json['tasks']).map(TodayTask.fromJson).toList(),
      habits: _maps(json['habits']).map(TodayHabit.fromJson).toList(),
      assets: TodayAssets.fromJson(_map(json['assets'])),
      summary: TodaySummary.fromJson(_map(json['summary'])),
    );
  }
}

Map<String, dynamic> _map(dynamic value) => value is Map
    ? Map<String, dynamic>.from(value)
    : <String, dynamic>{};

Iterable<Map<String, dynamic>> _maps(dynamic value) => value is List
    ? value.whereType<Map>().map((item) => Map<String, dynamic>.from(item))
    : const <Map<String, dynamic>>[];

int _int(dynamic value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;

double _double(dynamic value) => value is num
    ? value.toDouble()
    : double.tryParse('$value') ?? 0;

class TodayTask {
  const TodayTask({
    required this.id,
    required this.title,
    required this.note,
    required this.endTime,
    required this.importance,
    required this.difficulty,
    required this.status,
    required this.targetCount,
    required this.todayActualCount,
    required this.totalActualCount,
    required this.remainingCount,
    required this.completedToday,
    required this.overdue,
  });

  final int id;
  final String title;
  final String? note;
  final DateTime? endTime;
  final int? importance;
  final int? difficulty;
  final String status;
  final int targetCount;
  final int todayActualCount;
  final int totalActualCount;
  final int remainingCount;
  final bool completedToday;
  final bool overdue;

  factory TodayTask.fromJson(Map<String, dynamic> json) => TodayTask(
        id: _int(json['taskId']),
        title: json['title']?.toString() ?? '未命名任务',
        note: json['note']?.toString(),
        endTime: DateTime.tryParse(json['endTime']?.toString() ?? ''),
        importance: json['importance'] == null ? null : _int(json['importance']),
        difficulty: json['difficulty'] == null ? null : _int(json['difficulty']),
        status: json['status']?.toString() ?? 'PENDING',
        targetCount: _int(json['targetCount']),
        todayActualCount: _int(json['todayActualCount']),
        totalActualCount: _int(json['totalActualCount']),
        remainingCount: _int(json['remainingCount']),
        completedToday: json['completedToday'] == true,
        overdue: json['overdue'] == true,
      );

  double get progress => targetCount <= 0
      ? 0
      : (totalActualCount / targetCount).clamp(0.0, 1.0).toDouble();
}

class TodayHabit {
  const TodayHabit({
    required this.id,
    required this.name,
    required this.note,
    required this.checkedInToday,
    required this.currentStreak,
    required this.totalCheckInDays,
  });

  final int id;
  final String name;
  final String? note;
  final bool checkedInToday;
  final int currentStreak;
  final int totalCheckInDays;

  factory TodayHabit.fromJson(Map<String, dynamic> json) => TodayHabit(
        id: _int(json['habitId']),
        name: json['name']?.toString() ?? '未命名习惯',
        note: json['note']?.toString(),
        checkedInToday: json['checkedInToday'] == true,
        currentStreak: _int(json['currentStreak']),
        totalCheckInDays: _int(json['totalCheckInDays']),
      );
}

class TodayAssets {
  const TodayAssets({required this.coin, required this.exp, required this.water});

  final int coin;
  final int exp;
  final int water;

  factory TodayAssets.fromJson(Map<String, dynamic> json) => TodayAssets(
        coin: _int(json['coin']),
        exp: _int(json['exp']),
        water: _int(json['water']),
      );
}

class TodaySummary {
  const TodaySummary({
    required this.taskTotal,
    required this.taskCompleted,
    required this.habitTotal,
    required this.habitCheckedIn,
    required this.completionRate,
  });

  final int taskTotal;
  final int taskCompleted;
  final int habitTotal;
  final int habitCheckedIn;
  final double completionRate;

  int get completed => taskCompleted + habitCheckedIn;
  int get total => taskTotal + habitTotal;

  factory TodaySummary.fromJson(Map<String, dynamic> json) => TodaySummary(
        taskTotal: _int(json['taskTotal']),
        taskCompleted: _int(json['taskCompleted']),
        habitTotal: _int(json['habitTotal']),
        habitCheckedIn: _int(json['habitCheckedIn']),
        completionRate: _double(json['completionRate']),
      );
}

class EarnedReward {
  const EarnedReward({
    required this.granted,
    required this.coin,
    required this.exp,
    required this.water,
  });

  final bool granted;
  final int coin;
  final int exp;
  final int water;

  factory EarnedReward.fromResponse(Map<String, dynamic> data) {
    final reward = _map(data['reward']);
    return EarnedReward(
      granted: reward['granted'] == true,
      coin: _int(reward['coin']),
      exp: _int(reward['exp']),
      water: _int(reward['water']),
    );
  }

  String get message => !granted
      ? '进度已记录'
      : '奖励到账：金币 +$coin  经验 +$exp  水滴 +$water';
}
