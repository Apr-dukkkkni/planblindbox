import 'api_exception.dart';
import 'local/local_database.dart';
import 'local/local_plan_repository.dart';

/// 习惯本地数据门面：只操作 SQLite，不依赖 Spring Boot。
class HabitApi {
  HabitApi({required this.baseUrl, required this.userId, LocalPlanRepository? repository})
      : _repository = repository ?? LocalPlanRepository(
          userId: userId,
          localDatabase: LocalDatabase.instance,
        );

  final String baseUrl;
  final int userId;
  final LocalPlanRepository _repository;

  Future<List<HabitInfo>> getAll({bool includeArchived = false}) async {
    final rows = await _repository.getHabits(includeArchived: includeArchived);
    return rows.map(HabitInfo.fromJson).toList();
  }

  Future<HabitInfo> create({
    required String name,
    required String note,
    required String startDate,
    required Map<String, dynamic> repeatRule,
    required int importance,
    required int difficulty,
  }) async {
    final row = await _repository.createHabit(
      name: name,
      note: note,
      startDate: startDate,
      repeatRule: repeatRule,
      importance: importance,
      difficulty: difficulty,
    );
    return HabitInfo.fromJson(row);
  }

  Future<HabitInfo> update(
    int habitId, {
    required String name,
    required String note,
    required Map<String, dynamic> repeatRule,
    required int importance,
    required int difficulty,
  }) async {
    final row = await _repository.updateHabit(
      habitId,
      name: name,
      note: note,
      repeatRule: repeatRule,
      importance: importance,
      difficulty: difficulty,
    );
    return HabitInfo.fromJson(row);
  }

  Future<void> setPaused(int habitId, {required bool paused}) =>
      _repository.setHabitPaused(habitId, paused: paused);

  Future<void> archive(int habitId) => _repository.archiveHabit(habitId);

  Future<void> restore(int habitId) => _repository.restoreHabit(habitId);

  Future<HabitCheckInStats> getCheckInStats(int habitId) async =>
      HabitCheckInStats.fromJson(await _repository.getHabitCheckInStats(habitId));

  void dispose() {}
}

class HabitInfo {
  HabitInfo({
    required this.id,
    required this.name,
    required this.note,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.repeatRule,
    required this.importance,
    required this.difficulty,
  });

  final int id;
  final String name;
  final String note;
  final String startDate;
  final String? endDate;
  final String status;
  final int importance;
  final int difficulty;
  final Map<String, dynamic> repeatRule;

  factory HabitInfo.fromJson(Map<String, dynamic> json) {
    final id = (json['habitId'] as num?)?.toInt();
    if (id == null) throw ApiException('Habit 缺少 habitId');
    return HabitInfo(
      id: id,
      name: json['name']?.toString() ?? '',
      note: json['note']?.toString() ?? '',
      startDate: json['startDate']?.toString() ?? '',
      endDate: json['endDate']?.toString(),
      status: json['status']?.toString() ?? 'ACTIVE',
      repeatRule: json['repeatRule'] is Map
          ? Map<String, dynamic>.from(json['repeatRule'] as Map)
          : {'type': 'DAILY'},
      importance: (json['importance'] as num?)?.toInt() ?? 3,
      difficulty: (json['difficulty'] as num?)?.toInt() ?? 3,
    );
  }

  String get repeatLabel {
    if (repeatRule['type'] != 'WEEKLY') return '每天';
    const labels = ['一', '二', '三', '四', '五', '六', '日'];
    final days = repeatRule['daysOfWeek'];
    if (days is! List) return '每周';
    final selected = days.whereType<num>().map((d) => d.toInt())
        .where((d) => d >= 1 && d <= 7).toList()..sort();
    return '每周${selected.map((d) => labels[d - 1]).join('、')}';
  }
}

class HabitCheckInStats {
  HabitCheckInStats({
    required this.currentStreak,
    required this.totalCheckInDays,
    required this.checkedInToday,
  });

  final int currentStreak;
  final int totalCheckInDays;
  final bool checkedInToday;

  factory HabitCheckInStats.fromJson(Map<String, dynamic> json) =>
      HabitCheckInStats(
        currentStreak: (json['currentStreak'] as num?)?.toInt() ?? 0,
        totalCheckInDays: (json['totalCheckInDays'] as num?)?.toInt() ?? 0,
        checkedInToday: json['checkedInToday'] == true,
      );
}
