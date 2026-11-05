import '../config/api_config.dart';
import '../data/local/local_database.dart';
import '../data/local/local_plan_repository.dart';

/// 兼容旧代码的任务管理门面。底层已切换为本地 Repository，不再发送 HTTP 请求。
class TaskManageApi {
  static const int userId = ApiConfig.userId;
  static final LocalPlanRepository _repository = LocalPlanRepository(
    userId: userId,
    localDatabase: LocalDatabase.instance,
  );

  static Future<Map<String, dynamic>> getTask(int taskId) =>
      _repository.getTask(taskId);

  static Future<void> updateTask(int taskId, Map<String, dynamic> request) async {
    final current = await _repository.getTask(taskId);
    final recordRule = request['recordRule'] is Map
        ? Map<String, dynamic>.from(request['recordRule'] as Map)
        : current['recordRule'] is Map
            ? Map<String, dynamic>.from(current['recordRule'] as Map)
            : <String, dynamic>{'mode': 'DEFAULT'};
    final endTimeText = request['endTime']?.toString();
    await _repository.updateTask(
      taskId: taskId,
      title: request['title']?.toString() ?? current['title']?.toString() ?? '',
      note: request['note']?.toString() ?? current['note']?.toString() ?? '',
      targetCount: (request['targetCount'] as num?)?.toInt() ??
          (current['targetCount'] as num?)?.toInt() ?? 1,
      importance: (request['importance'] as num?)?.toInt() ??
          (current['importance'] as num?)?.toInt() ?? 3,
      difficulty: (request['difficulty'] as num?)?.toInt() ??
          (current['difficulty'] as num?)?.toInt() ?? 3,
      categoryId: (request['categoryId'] as num?)?.toInt() ??
          (current['categoryId'] as num?)?.toInt() ?? 0,
      endTime: endTimeText == null ? null : DateTime.tryParse(endTimeText),
      recordRule: recordRule,
    );
  }

  static Future<void> archiveTask(int taskId) => _repository.archiveTask(taskId);
}
