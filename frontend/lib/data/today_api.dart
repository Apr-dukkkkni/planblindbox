import '../models/today_models.dart';
import 'local/local_database.dart';
import 'local/local_plan_repository.dart';

export 'api_exception.dart';

/// 核心业务的本地门面。保留 TodayApi 名称和原有方法签名，减少 UI 改动；
/// 内部不再发 HTTP 请求，所有数据由 SQLite Repository 提供。
class TodayApi {
  TodayApi({
    required String baseUrl,
    required this.userId,
    LocalPlanRepository? repository,
  })  : _baseUrl = 'local://sqlite',
        repository = repository ??
            LocalPlanRepository(userId: userId, localDatabase: LocalDatabase.instance);

  final String _baseUrl;
  final int userId;
  final LocalPlanRepository repository;

  String get baseUrl => _baseUrl;

  Future<List<Map<String, dynamic>>> getAllTasks() => repository.getAllTasks();

  Future<TodayData> getToday({String sort = 'time'}) async =>
      TodayData.fromJson(await repository.getToday(sort: sort));

  Future<Map<String, dynamic>> getTask(int taskId) => repository.getTask(taskId);

  Future<EarnedReward> completeTask({
    required int taskId,
    required int actualCount,
  }) async =>
      EarnedReward.fromResponse(await repository.completeTask(
        taskId: taskId,
        actualCount: actualCount,
      ));

  Future<EarnedReward> checkInHabit(int habitId) async =>
      EarnedReward.fromResponse(await repository.checkInHabit(habitId));

  Future<Map<String, dynamic>> dailySignIn() => repository.dailySignIn();

  Future<List<Map<String, dynamic>>> getTaskCategories({
    bool includeDisabled = false,
  }) =>
      repository.getTaskCategories(includeDisabled: includeDisabled);

  Future<void> createTaskCategory({
    required String name,
    required String color,
  }) =>
      repository.createTaskCategory(name: name, color: color);

  Future<void> updateTaskCategory({
    required int categoryId,
    String? name,
    String? color,
    bool? enabled,
  }) =>
      repository.updateTaskCategory(
        categoryId: categoryId,
        name: name,
        color: color,
        enabled: enabled,
      );

  Future<void> createTask({
    required String title,
    required String note,
    required int targetCount,
    required int importance,
    required int difficulty,
    required int categoryId,
    DateTime? endTime,
    Map<String, dynamic>? recordRule,
  }) =>
      repository.createTask(
        title: title,
        note: note,
        targetCount: targetCount,
        importance: importance,
        difficulty: difficulty,
        categoryId: categoryId,
        endTime: endTime,
        recordRule: recordRule,
      );

  Future<void> updateTask({
    required int taskId,
    required String title,
    required String note,
    required int targetCount,
    required int importance,
    required int difficulty,
    required int categoryId,
    DateTime? endTime,
    required Map<String, dynamic> recordRule,
  }) =>
      repository.updateTask(
        taskId: taskId,
        title: title,
        note: note,
        targetCount: targetCount,
        importance: importance,
        difficulty: difficulty,
        categoryId: categoryId,
        endTime: endTime,
        recordRule: recordRule,
      );

  Future<void> createDailyHabit({
    required String name,
    required String note,
    required String startDate,
  }) async {
    await repository.createHabit(
      name: name,
      note: note,
      startDate: startDate,
      repeatRule: const {'type': 'DAILY'},
      importance: 3,
      difficulty: 3,
    );
  }

  /// 本地数据库由应用生命周期统一管理，不在页面 dispose 时关闭。
  void dispose() {}
}
