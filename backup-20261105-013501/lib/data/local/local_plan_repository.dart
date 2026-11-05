import 'dart:convert';
import 'dart:math';

import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common/sqlite_api.dart' show DatabaseExecutor;

import '../api_exception.dart';
import 'local_database.dart';

/// 本地业务仓储。所有核心业务的读写、事务和统计均在本地完成。
/// userId 仅用于给本机的本地数据分区，当前单机版默认使用 1。
class LocalPlanRepository {
  LocalPlanRepository({
    required this.userId,
    LocalDatabase? localDatabase,
    DateTime Function()? clock,
  })  : _localDatabase = localDatabase ?? LocalDatabase.instance,
        _clock = clock ?? DateTime.now;

  final int userId;
  // 兼容上一版情绪/日记数据分区：游客 -1；登录用户为服务器正数 ID。
  int _ownerForTable(String table) {
    if (table == 'wellbeing_entries' || table == 'wellbeing_moods') {
      return userId == 1 ? -1 : -1000000 - userId;
    }
    return userId;
  }
  final LocalDatabase _localDatabase;
  final DateTime Function() _clock;
  final Random _random = Random.secure();

  Future<Database> get _db => _localDatabase.database;

  static const _defaultCategories = <Map<String, String>>[
    {'name': '学习', 'color': '#4F7CAC', 'icon': 'book'},
    {'name': '工作', 'color': '#7A6F9B', 'icon': 'briefcase'},
    {'name': '运动', 'color': '#E07A5F', 'icon': 'fitness'},
    {'name': '健康', 'color': '#5B8E7D', 'icon': 'heart'},
    {'name': '生活', 'color': '#C89F5D', 'icon': 'home'},
    {'name': '其他', 'color': '#607D8B', 'icon': 'more'},
  ];

  /// 备份中包含全部业务表和静态内容目录，确保恢复后不丢失外键关联。
  static const _backupTables = <String>[
    'user_assets',
    'tasks',
    'task_records',
    'task_cycle_records',
    'habits',
    'habit_records',
    'task_categories',
    'time_records',
    'asset_records',
    'daily_sign_ins',
    'wellbeing_entries',
    'wellbeing_moods',
    'content_packs',
    'collectible_items',
    'user_collectibles',
    'collectible_acquisition_records',
    'shop_boxes',
    'shop_rewards',
    'shop_open_records',
    'custom_product_categories',
    'custom_products',
    'custom_inventory',
    'custom_purchase_records',
    'custom_use_records',
    'app_settings',
    'core_sync_rescue',
  ];

  static const _restoreDeleteOrder = <String>[
    'wellbeing_entries',
    'wellbeing_moods',
    'custom_use_records',
    'custom_purchase_records',
    'custom_inventory',
    'custom_products',
    'custom_product_categories',
    'shop_open_records',
    'collectible_acquisition_records',
    'user_collectibles',
    'shop_rewards',
    'shop_boxes',
    'collectible_items',
    'content_packs',
    'task_records',
    'task_cycle_records',
    'time_records',
    'habit_records',
    'habits',
    'tasks',
    'task_categories',
    'asset_records',
    'daily_sign_ins',
    'user_assets',
    'app_settings',
    'core_sync_rescue',
  ];

  static const _restoreInsertOrder = <String>[
    'content_packs',
    'collectible_items',
    'shop_boxes',
    'shop_rewards',
    'tasks',
    'task_records',
    'task_cycle_records',
    'habits',
    'habit_records',
    'task_categories',
    'user_assets',
    'daily_sign_ins',
    'wellbeing_moods',
    'wellbeing_entries',
    'time_records',
    'asset_records',
    'user_collectibles',
    'collectible_acquisition_records',
    'shop_open_records',
    'custom_product_categories',
    'custom_products',
    'custom_inventory',
    'custom_purchase_records',
    'custom_use_records',
    'app_settings',
    'core_sync_rescue',
  ];

  static const _statusTables = <String, String>{
    '用户资产': 'user_assets',
    '任务': 'tasks',
    '任务记录': 'task_records',
    '任务周期记录': 'task_cycle_records',
    '任务分类': 'task_categories',
    '习惯': 'habits',
    '习惯打卡': 'habit_records',
    '每日签到': 'daily_sign_ins',
    '心情及日记': 'wellbeing_entries',
    '自定义情绪': 'wellbeing_moods',
    '时间记录': 'time_records',
    '资产流水': 'asset_records',
    '收藏内容包': 'content_packs',
    '收藏品目录': 'collectible_items',
    '收藏品持有记录': 'user_collectibles',
    '收藏品获取记录': 'collectible_acquisition_records',
    '盲盒商品': 'shop_boxes',
    '盲盒奖励池': 'shop_rewards',
    '盲盒记录': 'shop_open_records',
    '自定义商品种类': 'custom_product_categories',
    '自定义商品': 'custom_products',
    '自定义商品仓库': 'custom_inventory',
    '自定义购买记录': 'custom_purchase_records',
    '自定义商品使用记录': 'custom_use_records',
    '应用偏好': 'app_settings',
  };

  Future<void> ensureReady() async {
    final db = await _db;
    await _ensureAssets(db);
    await _ensureCategories(db);
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  String _dateTime(DateTime value) =>
      '${_date(value)}T${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}:${value.second.toString().padLeft(2, '0')}';

  DateTime _businessDate(DateTime value) {
    final date = DateTime(value.year, value.month, value.day);
    return value.hour < 5 ? date.subtract(const Duration(days: 1)) : date;
  }

  DateTime _nextReset(DateTime value) =>
      DateTime(value.year, value.month, value.day + 1, 5);

  DateTime? _parseDateTime(Object? value) =>
      value == null ? null : DateTime.tryParse(value.toString());

  DateTime? _effectiveDeadline(Map<String, Object?> task) {
    final end = _parseDateTime(task['end_time']);
    if (end != null) return end;
    final start = _parseDateTime(task['start_time']);
    final created = _parseDateTime(task['create_time']);
    final anchor = start == null || (created != null && !start.isAfter(created))
        ? created
        : start;
    return anchor == null ? null : _nextReset(anchor);
  }

  Future<void> _ensureAssets(DatabaseExecutor db) async {
    final now = _dateTime(DateTime.now());
    await db.insert('user_assets', {
      'user_id': userId,
      'coin': 0,
      'exp': 0,
      'water': 0,
      'update_time': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> _ensureCategories(DatabaseExecutor db) async {
    final count = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM task_categories WHERE user_id = ?',
          [userId],
        )) ??
        0;
    if (count > 0) return;
    final now = _dateTime(DateTime.now());
    for (final item in _defaultCategories) {
      await db.insert('task_categories', {
        'user_id': userId,
        'name': item['name'],
        'color': item['color'],
        'icon': item['icon'],
        'is_default': 1,
        'enabled': 1,
        'create_time': now,
        'update_time': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<Map<String, Object?>> _assets(DatabaseExecutor db) async {
    await _ensureAssets(db);
    final rows = await db.query('user_assets',
        where: 'user_id = ?', whereArgs: [userId], limit: 1);
    if (rows.isEmpty) return {'coin': 0, 'exp': 0, 'water': 0};
    return {
      'coin': _int(rows.first['coin']),
      'exp': _int(rows.first['exp']),
      // 旧水滴字段只作为历史存档保留，不再作为可信余额。
      'water': 0,
    };
  }

  int _int(Object? value, [int fallback = 0]) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? fallback;

  Future<void> _addAssets(
    DatabaseExecutor db, {
    required int coin,
    required int exp,
    required int water,
    required String action,
    required String source,
    required int sourceId,
  }) async {
    if (water != 0) {
      throw StateError('本地业务无权增加或扣除水滴');
    }
    await _ensureAssets(db);
    final now = _dateTime(DateTime.now());
    await db.rawUpdate(
      'UPDATE user_assets SET coin = coin + ?, exp = exp + ?, water = water + ?, update_time = ? WHERE user_id = ?',
      [coin, exp, water, now, userId],
    );
    for (final entry in <String, int>{
      'COIN': coin,
      'EXP': exp,
      'WATER': water,
    }.entries) {
      if (entry.value == 0) continue;
      await db.insert('asset_records', {
        'user_id': userId,
        'action': action,
        'asset_type': entry.key,
        'amount': entry.value,
        'source': source,
        'source_id': sourceId,
        'create_time': now,
      });
    }
  }

  Future<void> _recordLedger(
    DatabaseExecutor db, {
    required String action,
    required String assetType,
    required int amount,
    required String source,
    required int sourceId,
  }) async {
    if (amount == 0) return;
    await db.insert('asset_records', {
      'user_id': userId,
      'action': action,
      'asset_type': assetType,
      'amount': amount,
      'source': source,
      'source_id': sourceId,
      'create_time': _dateTime(DateTime.now()),
    });
  }

  // ---------------------------------------------------------------------------
  // 今日 / 任务
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> getToday({String sort = 'time'}) async {
    if (sort != 'time' && sort != 'importance') {
      throw ApiException('sort 仅支持 time 或 importance', statusCode: 400);
    }
    final db = await _db;
    await ensureReady();
    final now = DateTime.now();
    final businessDate = _businessDate(now);
    final dateText = _date(businessDate);
    final businessDayStart = DateTime(
      businessDate.year,
      businessDate.month,
      businessDate.day,
      5,
    );

    final taskRows = await db.query(
      'tasks',
      where: 'user_id = ? AND status NOT IN (?, ?)',
      whereArgs: [userId, 'CANCELLED', 'ARCHIVED'],
    );
    final tasks = <Map<String, dynamic>>[];
    for (final raw in taskRows) {
      final task = Map<String, Object?>.from(raw);
      final start = _parseDateTime(task['start_time']);
      if (start != null && start.isAfter(now)) continue;
      final deadline = _effectiveDeadline(task);
      if (deadline != null && !deadline.isAfter(businessDayStart)) continue;

      final todayRecords = await db.query('task_records',
          where: 'task_id = ? AND record_date = ?',
          whereArgs: [task['task_id'], dateText], limit: 1);
      final todayRecord = todayRecords.isEmpty ? null : todayRecords.first;
      final completedToday = task['status'] == 'COMPLETED' &&
          todayRecord != null && todayRecord['status'] == 'COMPLETED';
      if (task['status'] == 'COMPLETED' && !completedToday) continue;
      if (!['PENDING', 'IN_PROGRESS', 'COMPLETED'].contains(task['status'])) {
        continue;
      }

      final sumRows = await db.rawQuery(
        'SELECT COALESCE(SUM(actual_count), 0) AS total FROM task_records WHERE task_id = ?',
        [task['task_id']],
      );
      final total = _int(sumRows.first['total']);
      final todayCount = _int(todayRecord?['actual_count']);
      final importance = _int(task['importance'], 3);
      final difficulty = _int(task['difficulty'], 3);
      final ruleText = task['record_rule']?.toString();
      tasks.add({
        'taskId': _int(task['task_id']),
        'title': task['title']?.toString() ?? '未命名任务',
        'note': task['note'],
        'startTime': task['start_time'],
        'endTime': deadline == null ? null : _dateTime(deadline),
        'importance': task['importance'],
        'difficulty': task['difficulty'],
        'priorityScore': task['priority_score'] ?? importance * difficulty,
        'status': task['status'],
        'targetCount': _int(task['target_count'], 1),
        'recordRule': ruleText == null ? null : jsonDecode(ruleText),
        'todayActualCount': todayCount,
        'totalActualCount': total,
        'remainingCount': max(0, _int(task['target_count'], 1) - total),
        'completedToday': completedToday,
        'overdue': !completedToday && deadline != null && !now.isBefore(deadline),
      });
    }

    int compareNullableDate(Map<String, dynamic> a, Map<String, dynamic> b) {
      final da = _parseDateTime(a['endTime']);
      final db = _parseDateTime(b['endTime']);
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    }

    tasks.sort((a, b) {
      final completedCompare = (a['completedToday'] == true ? 1 : 0)
          .compareTo(b['completedToday'] == true ? 1 : 0);
      if (completedCompare != 0) return completedCompare;
      if (sort == 'importance') {
        final priority = _double(b['priorityScore'])
            .compareTo(_double(a['priorityScore']));
        if (priority != 0) return priority;
      }
      final timeCompare = compareNullableDate(a, b);
      if (timeCompare != 0) return timeCompare;
      if (sort == 'time') {
        final priority = _double(b['priorityScore'])
            .compareTo(_double(a['priorityScore']));
        if (priority != 0) return priority;
      }
      return _int(a['taskId']).compareTo(_int(b['taskId']));
    });

    final habitRows = await db.query('habits',
        where: 'user_id = ? AND status = ?', whereArgs: [userId, 'ACTIVE']);
    final habits = <Map<String, dynamic>>[];
    for (final habit in habitRows) {
      if (!_isHabitScheduled(habit, businessDate)) continue;
      final stats = await getHabitCheckInStats(_int(habit['habit_id']));
      habits.add({
        'habitId': _int(habit['habit_id']),
        'name': habit['name'],
        'note': habit['note'],
        'checkedInToday': stats['checkedInToday'],
        'currentStreak': stats['currentStreak'],
        'totalCheckInDays': stats['totalCheckInDays'],
      });
    }

    final assets = await _assets(db);
    final completedTasks = tasks.where((e) => e['completedToday'] == true).length;
    final checkedHabits = habits.where((e) => e['checkedInToday'] == true).length;
    final total = tasks.length + habits.length;
    final completed = completedTasks + checkedHabits;
    return {
      'date': dateText,
      'tasks': tasks,
      'habits': habits,
      'assets': assets,
      'summary': {
        'taskTotal': tasks.length,
        'taskCompleted': completedTasks,
        'habitTotal': habits.length,
        'habitCheckedIn': checkedHabits,
        'completionRate': total == 0 ? 0.0 : completed * 100.0 / total,
      },
    };
  }

  double _double(Object? value) =>
      value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '') ?? 0;

  Future<List<Map<String, dynamic>>> getAllTasks() async {
    final db = await _db;
    final rows = await db.query('tasks', where: 'user_id = ?', whereArgs: [userId],
        orderBy: 'create_time DESC, task_id DESC');
    final result = <Map<String, dynamic>>[];
    for (final raw in rows) {
      final task = Map<String, Object?>.from(raw);
      final sum = await db.rawQuery(
          'SELECT COALESCE(SUM(actual_count), 0) AS total FROM task_records WHERE task_id = ?',
          [task['task_id']]);
      final rule = task['record_rule']?.toString();
      result.add({
        'taskId': _int(task['task_id']),
        'title': task['title'],
        'note': task['note'],
        'startTime': task['start_time'],
        'endTime': _effectiveDeadline(task) == null
            ? null
            : _dateTime(_effectiveDeadline(task)!),
        'targetCount': _int(task['target_count'], 1),
        'actualCount': _int(sum.first['total']),
        'status': task['status'],
        'importance': task['importance'],
        'urgency': task['urgency'],
        'difficulty': task['difficulty'],
        'priorityScore': task['priority_score'],
        'estimatedMinutes': task['estimated_minutes'],
        'categoryId': task['category_id'],
        'recordRule': rule == null ? null : jsonDecode(rule),
        'recurrenceType': task['recurrence_type'],
        'createTime': task['create_time'],
        'updateTime': task['update_time'],
      });
    }
    return result;
  }

  Future<Map<String, dynamic>> getTask(int taskId) async {
    final db = await _db;
    final rows = await db.query('tasks',
        where: 'task_id = ? AND user_id = ?', whereArgs: [taskId, userId], limit: 1);
    if (rows.isEmpty) throw ApiException('任务不存在', statusCode: 404);
    final task = Map<String, Object?>.from(rows.first);
    final rule = task['record_rule']?.toString();
    return {
      'taskId': taskId,
      'title': task['title'],
      'note': task['note'],
      'startTime': task['start_time'],
      'endTime': _effectiveDeadline(task) == null
          ? null
          : _dateTime(_effectiveDeadline(task)!),
      'targetCount': _int(task['target_count'], 1),
      'status': task['status'],
      'importance': task['importance'],
      'urgency': task['urgency'],
      'difficulty': task['difficulty'],
      'categoryId': task['category_id'],
      'recordRule': rule == null ? null : jsonDecode(rule),
      'estimatedMinutes': task['estimated_minutes'],
    };
  }

  Future<void> createTask({
    required String title,
    required String note,
    required int targetCount,
    required int importance,
    required int difficulty,
    required int categoryId,
    DateTime? endTime,
    Map<String, dynamic>? recordRule,
  }) async {
    if (title.trim().isEmpty) throw ApiException('任务名称不能为空', statusCode: 400);
    if (targetCount < 1) throw ApiException('目标数量必须大于 0', statusCode: 400);
    _validateLevel(importance, '重要程度');
    _validateLevel(difficulty, '难度');
    _validateRecordRule(recordRule);
    final db = await _db;
    await ensureReady();
    final now = DateTime.now();
    final deadline = endTime ?? _nextReset(now);
    if (!deadline.isAfter(now)) {
      throw ApiException('截止时间必须晚于当前时间', statusCode: 400);
    }
    await db.transaction((txn) async {
      final resolvedCategory = await _resolveCategory(txn, categoryId, allowDisabled: false);
      await txn.insert('tasks', {
        'user_id': userId,
        'category_id': resolvedCategory,
        'title': title.trim(),
        'note': note.trim().isEmpty ? null : note.trim(),
        'start_time': _dateTime(now),
        'end_time': _dateTime(deadline),
        'target_count': targetCount,
        'recurrence_type': 'ONCE',
        'status': 'PENDING',
        'importance': importance,
        'urgency': 3,
        'difficulty': difficulty,
        'priority_score': importance * difficulty,
        'record_rule': recordRule == null ? null : jsonEncode(recordRule),
        'create_time': _dateTime(now),
        'update_time': _dateTime(now),
      });
    });
  }

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
  }) async {
    if (title.trim().isEmpty) throw ApiException('任务名称不能为空', statusCode: 400);
    if (targetCount < 1) throw ApiException('目标数量必须大于 0', statusCode: 400);
    _validateLevel(importance, '重要程度');
    _validateLevel(difficulty, '难度');
    _validateRecordRule(recordRule);
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.query('tasks',
          where: 'task_id = ? AND user_id = ?', whereArgs: [taskId, userId], limit: 1);
      if (rows.isEmpty) throw ApiException('任务不存在', statusCode: 404);
      final task = Map<String, Object?>.from(rows.first);
      if (task['status'] == 'COMPLETED') {
        throw ApiException('已完成的任务不能修改', statusCode: 409);
      }
      final sum = await txn.rawQuery(
          'SELECT COALESCE(SUM(actual_count), 0) AS total FROM task_records WHERE task_id = ?',
          [taskId]);
      final actual = _int(sum.first['total']);
      if (targetCount < actual || (actual > 0 && targetCount == actual)) {
        throw ApiException('新目标必须大于已有进度', statusCode: 409);
      }
      final resolvedCategory = await _resolveCategory(txn, categoryId,
          allowDisabled: true);
      final now = DateTime.now();
      await txn.update('tasks', {
        'title': title.trim(),
        'note': note.trim().isEmpty ? null : note.trim(),
        'target_count': targetCount,
        'category_id': resolvedCategory,
        if (endTime != null) 'end_time': _dateTime(endTime),
        'importance': importance,
        'difficulty': difficulty,
        'priority_score': importance * difficulty,
        'record_rule': jsonEncode(recordRule),
        'update_time': _dateTime(now),
      }, where: 'task_id = ? AND user_id = ?', whereArgs: [taskId, userId]);
    });
  }

  Future<void> archiveTask(int taskId) async {
    final db = await _db;
    final count = await db.update('tasks', {
      'status': 'ARCHIVED',
      'update_time': _dateTime(DateTime.now()),
    }, where: 'task_id = ? AND user_id = ? AND status NOT IN (?, ?)',
        whereArgs: [taskId, userId, 'COMPLETED', 'ARCHIVED']);
    if (count != 1) throw ApiException('任务不存在、已完成或已归档', statusCode: 409);
  }

  Future<int?> _resolveCategory(DatabaseExecutor db, int categoryId,
      {required bool allowDisabled}) async {
    if (categoryId <= 0) return null;
    final rows = await db.query('task_categories',
        where: 'category_id = ? AND user_id = ?', whereArgs: [categoryId, userId], limit: 1);
    if (rows.isEmpty) throw ApiException('任务分类不存在', statusCode: 400);
    if (!allowDisabled && _int(rows.first['enabled']) != 1) {
      throw ApiException('该任务分类已停用，不能用于新任务', statusCode: 409);
    }
    return categoryId;
  }

  void _validateLevel(int value, String label) {
    if (value < 1 || value > 5) {
      throw ApiException('$label必须在 1～5 之间', statusCode: 400);
    }
  }

  void _validateRecordRule(Map<String, dynamic>? rule) {
    if (rule == null) return;
    final mode = rule['mode'];
    if (mode == 'DEFAULT' || mode == 'MANUAL') {
      if (rule.length != 1) throw ApiException('$mode 模式只允许 mode 字段', statusCode: 400);
      return;
    }
    if (mode == 'FIXED' && rule.length == 2 && rule['count'] is int && (rule['count'] as int) > 0) {
      return;
    }
    throw ApiException('任务记录规则不合法', statusCode: 400);
  }

  Future<Map<String, dynamic>> completeTask({
    required int taskId,
    required int actualCount,
  }) async {
    if (actualCount <= 0) throw ApiException('actualCount 必须为正整数', statusCode: 400);
    final db = await _db;
    return db.transaction((txn) async {
      final rows = await txn.query('tasks',
          where: 'task_id = ? AND user_id = ?', whereArgs: [taskId, userId], limit: 1);
      if (rows.isEmpty) throw ApiException('任务不存在', statusCode: 404);
      final task = Map<String, Object?>.from(rows.first);
      if (!['PENDING', 'IN_PROGRESS'].contains(task['status'])) {
        throw ApiException('当前任务状态不允许继续完成', statusCode: 409);
      }
      final target = _int(task['target_count'], 1);
      if (target <= 0) throw ApiException('任务目标数量不合法');
      final now = DateTime.now();
      final deadline = _effectiveDeadline(task);
      if (deadline != null && !now.isBefore(deadline)) {
        throw ApiException('任务已经过期，请重新安排任务', statusCode: 409);
      }
      final businessDate = _date(_businessDate(now));
      final totalRows = await txn.rawQuery(
          'SELECT COALESCE(SUM(actual_count), 0) AS total FROM task_records WHERE task_id = ?',
          [taskId]);
      final before = _int(totalRows.first['total']);
      if (before >= target) throw ApiException('历史数量已达到目标，请检查任务状态', statusCode: 409);
      final increment = min(actualCount, target - before).toInt();
      final after = before + increment;
      final completed = after == target;
      final existing = await txn.query('task_records',
          where: 'task_id = ? AND record_date = ?', whereArgs: [taskId, businessDate], limit: 1);
      int todayCount;
      if (existing.isEmpty) {
        todayCount = increment;
        await txn.insert('task_records', {
          'task_id': taskId,
          'record_date': businessDate,
          'status': completed ? 'COMPLETED' : 'IN_PROGRESS',
          'finish_time': completed ? _dateTime(now) : null,
          'actual_count': increment,
          'create_time': _dateTime(now),
          'update_time': _dateTime(now),
        });
      } else {
        todayCount = _int(existing.first['actual_count']) + increment;
        await txn.update('task_records', {
          'actual_count': todayCount,
          'status': completed ? 'COMPLETED' : 'IN_PROGRESS',
          'finish_time': completed ? _dateTime(now) : existing.first['finish_time'],
          'update_time': _dateTime(now),
        }, where: 'task_record_id = ?', whereArgs: [existing.first['task_record_id']]);
      }
      await txn.update('tasks', {
        'status': completed ? 'COMPLETED' : 'IN_PROGRESS',
        'update_time': _dateTime(now),
      }, where: 'task_id = ? AND user_id = ?', whereArgs: [taskId, userId]);

      var reward = <String, dynamic>{'granted': false, 'coin': 0, 'exp': 0, 'water': 0};
      if (completed) {
        final importance = _int(task['importance'], 3);
        final difficulty = _int(task['difficulty'], 3);
        final coin = _coinForLevel(importance) + _coinForLevel(difficulty);
        final exp = _expForLevel(importance) + _expForLevel(difficulty);
        await _addAssets(txn,
            coin: coin,
            exp: exp,
            water: 0,
            action: 'TASK_COMPLETE',
            source: 'TASK',
            sourceId: taskId);
        reward = {'granted': true, 'coin': coin, 'exp': exp, 'water': 0};
      }
      return {
        'taskId': taskId,
        'recordDate': businessDate,
        'incrementCount': increment,
        'todayActualCount': todayCount,
        'totalActualCount': after,
        'targetCount': target,
        'remainingCount': max(0, target - after),
        'status': completed ? 'COMPLETED' : 'IN_PROGRESS',
        'reward': reward,
      };
    });
  }

  int _coinForLevel(int level) => const [0, 1, 2, 4, 8, 16][level];
  int _expForLevel(int level) => const [0, 10, 20, 40, 80, 160][level];

  // ---------------------------------------------------------------------------
  // 习惯
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> getHabits({bool includeArchived = false}) async {
    final db = await _db;
    final rows = await db.query('habits',
        where: includeArchived
            ? 'user_id = ?'
            : 'user_id = ? AND status <> ?',
        whereArgs: includeArchived ? [userId] : [userId, 'ARCHIVED'],
        orderBy: 'create_time DESC, habit_id DESC');
    return rows.map((row) => {
      'habitId': _int(row['habit_id']),
      'name': row['name'],
      'note': row['note'],
      'startDate': row['start_date'],
      'endDate': row['end_date'],
      'repeatRule': jsonDecode(row['repeat_rule'].toString()),
      'status': row['status'],
      'importance': _int(row['importance'], 3),
      'difficulty': _int(row['difficulty'], 3),
    }).toList();
  }

  Future<Map<String, dynamic>> createHabit({
    required String name,
    required String note,
    required String startDate,
    String? endDate,
    required Map<String, dynamic> repeatRule,
    required int importance,
    required int difficulty,
  }) async {
    if (name.trim().isEmpty) throw ApiException('习惯名称不能为空', statusCode: 400);
    _validateLevel(importance, '重要程度');
    _validateLevel(difficulty, '难度');
    _validateHabitRule(repeatRule);
    final start = DateTime.tryParse(startDate);
    final end = endDate == null ? null : DateTime.tryParse(endDate);
    if (start == null || (end != null && end.isBefore(start))) {
      throw ApiException('习惯日期不合法', statusCode: 400);
    }
    final db = await _db;
    final now = _dateTime(DateTime.now());
    final id = await db.insert('habits', {
      'user_id': userId,
      'name': name.trim(),
      'note': note.trim().isEmpty ? null : note.trim(),
      'start_date': _date(start),
      'end_date': end == null ? null : _date(end),
      'repeat_rule': jsonEncode(repeatRule),
      'status': 'ACTIVE',
      'importance': importance,
      'difficulty': difficulty,
      'create_time': now,
      'update_time': now,
    });
    return (await getHabits(includeArchived: true)).firstWhere((e) => e['habitId'] == id);
  }

  Future<Map<String, dynamic>> updateHabit(
    int habitId, {
    required String name,
    required String note,
    required Map<String, dynamic> repeatRule,
    required int importance,
    required int difficulty,
  }) async {
    if (name.trim().isEmpty) throw ApiException('习惯名称不能为空', statusCode: 400);
    _validateLevel(importance, '重要程度');
    _validateLevel(difficulty, '难度');
    _validateHabitRule(repeatRule);
    final db = await _db;
    final rows = await db.query('habits',
        where: 'habit_id = ? AND user_id = ?', whereArgs: [habitId, userId], limit: 1);
    if (rows.isEmpty) throw ApiException('习惯不存在', statusCode: 404);
    if (rows.first['status'] == 'ARCHIVED') throw ApiException('已归档习惯不能修改', statusCode: 409);
    await db.update('habits', {
      'name': name.trim(),
      'note': note.trim().isEmpty ? null : note.trim(),
      'repeat_rule': jsonEncode(repeatRule),
      'importance': importance,
      'difficulty': difficulty,
      'update_time': _dateTime(DateTime.now()),
    }, where: 'habit_id = ? AND user_id = ?', whereArgs: [habitId, userId]);
    return (await getHabits(includeArchived: true)).firstWhere((e) => e['habitId'] == habitId);
  }

  void _validateHabitRule(Map<String, dynamic> rule) {
    final type = rule['type'];
    if (type == 'DAILY') return;
    if (type == 'WEEKLY') {
      final days = rule['daysOfWeek'];
      if (days is List && days.isNotEmpty && days.every((d) => d is int && d >= 1 && d <= 7)) return;
    }
    throw ApiException('习惯重复规则不合法', statusCode: 400);
  }

  bool _isHabitScheduled(Map<String, Object?> habit, DateTime date) {
    final start = DateTime.tryParse(habit['start_date']?.toString() ?? '');
    final end = DateTime.tryParse(habit['end_date']?.toString() ?? '');
    if (start == null || date.isBefore(DateTime(start.year, start.month, start.day))) return false;
    if (end != null && date.isAfter(DateTime(end.year, end.month, end.day))) return false;
    final ruleText = habit['repeat_rule']?.toString() ?? '{"type":"DAILY"}';
    final rule = jsonDecode(ruleText) as Map<String, dynamic>;
    if (rule['type'] == 'DAILY') return true;
    if (rule['type'] == 'WEEKLY') {
      final days = rule['daysOfWeek'];
      return days is List && days.any((day) => _int(day) == date.weekday);
    }
    return false;
  }

  Future<Map<String, dynamic>> getHabitCheckInStats(int habitId) async {
    final db = await _db;
    final rows = await db.query('habits',
        where: 'habit_id = ? AND user_id = ?', whereArgs: [habitId, userId], limit: 1);
    if (rows.isEmpty) throw ApiException('习惯不存在', statusCode: 404);
    final habit = Map<String, Object?>.from(rows.first);
    final records = await db.query('habit_records',
        columns: ['record_date'],
        where: 'habit_id = ? AND status = ?',
        whereArgs: [habitId, 'COMPLETED'],
        orderBy: 'record_date DESC');
    final completed = records.map((r) => DateTime.parse(r['record_date'].toString())).toSet();
    final today = _businessDate(DateTime.now());
    final checkedToday = completed.contains(today);
    var cursor = checkedToday ? today : today.subtract(const Duration(days: 1));
    final start = DateTime.parse(habit['start_date'].toString());
    var streak = 0;
    while (!cursor.isBefore(start)) {
      if (_isHabitScheduled(habit, cursor)) {
        if (!completed.contains(cursor)) break;
        streak++;
      }
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return {
      'currentStreak': streak,
      'totalCheckInDays': completed.length,
      'checkedInToday': checkedToday,
    };
  }

  Future<Map<String, dynamic>> checkInHabit(int habitId) async {
    final db = await _db;
    return db.transaction((txn) async {
      final rows = await txn.query('habits',
          where: 'habit_id = ? AND user_id = ?', whereArgs: [habitId, userId], limit: 1);
      if (rows.isEmpty) throw ApiException('习惯不存在', statusCode: 404);
      final habit = Map<String, Object?>.from(rows.first);
      if (habit['status'] != 'ACTIVE') throw ApiException('仅 ACTIVE 习惯可打卡', statusCode: 409);
      final now = DateTime.now();
      final today = _businessDate(now);
      if (!_isHabitScheduled(habit, today)) {
        throw ApiException('今天不是此习惯的执行日', statusCode: 409);
      }
      final dateText = _date(today);
      final existing = await txn.query('habit_records',
          where: 'habit_id = ? AND record_date = ?', whereArgs: [habitId, dateText], limit: 1);
      if (existing.isNotEmpty) throw ApiException('今天已经打过卡了', statusCode: 409);
      final recordId = await txn.insert('habit_records', {
        'habit_id': habitId,
        'record_date': dateText,
        'status': 'COMPLETED',
        'finish_time': _dateTime(now),
        'actual_count': 1,
        'create_time': _dateTime(now),
        'update_time': _dateTime(now),
      });
      const coin = 2;
      const exp = 5;
      await _addAssets(txn,
          coin: coin,
          exp: exp,
          water: 0,
          action: 'HABIT_CHECK_IN',
          source: 'HABIT_RECORD',
          sourceId: recordId);
      return {
        'habitId': habitId,
        'recordDate': dateText,
        'reward': {'granted': true, 'coin': coin, 'exp': exp, 'water': 0},
      };
    });
  }

  Future<void> setHabitPaused(int habitId, {required bool paused}) async {
    final db = await _db;
    final count = await db.update('habits', {
      'status': paused ? 'PAUSED' : 'ACTIVE',
      'update_time': _dateTime(DateTime.now()),
    }, where: 'habit_id = ? AND user_id = ? AND status <> ?',
        whereArgs: [habitId, userId, 'ARCHIVED']);
    if (count != 1) throw ApiException('习惯不存在或已归档', statusCode: 404);
  }

  Future<void> archiveHabit(int habitId) async {
    final db = await _db;
    final count = await db.update('habits', {
      'status': 'ARCHIVED',
      'update_time': _dateTime(DateTime.now()),
    }, where: 'habit_id = ? AND user_id = ? AND status <> ?',
        whereArgs: [habitId, userId, 'ARCHIVED']);
    if (count != 1) throw ApiException('习惯不存在或已归档', statusCode: 404);
  }

  Future<void> restoreHabit(int habitId) async {
    final db = await _db;
    final count = await db.update('habits', {
      'status': 'ACTIVE',
      'update_time': _dateTime(DateTime.now()),
    }, where: 'habit_id = ? AND user_id = ? AND status = ?',
        whereArgs: [habitId, userId, 'ARCHIVED']);
    if (count != 1) throw ApiException('归档习惯不存在', statusCode: 404);
  }

  // ---------------------------------------------------------------------------
  // 每日签到
  // ---------------------------------------------------------------------------

  Future<Map<String, int>> _getSignInMetrics(
    DatabaseExecutor db,
    DateTime businessDate,
  ) async {
    final rows = await db.query(
      'daily_sign_ins',
      columns: ['business_date'],
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'business_date DESC',
    );
    final dates = rows
        .map((row) => DateTime.tryParse(row['business_date']?.toString() ?? ''))
        .whereType<DateTime>()
        .map((date) => DateTime(date.year, date.month, date.day))
        .toList();

    final today = DateTime(businessDate.year, businessDate.month, businessDate.day);
    final yesterday = today.subtract(const Duration(days: 1));
    var currentAllTimeStreak = 0;
    var currentMonthStreak = 0;

    if (dates.isNotEmpty && (dates.first == today || dates.first == yesterday)) {
      var expected = dates.first;
      for (final date in dates) {
        if (date != expected) break;
        currentAllTimeStreak++;
        expected = expected.subtract(const Duration(days: 1));
      }

      expected = dates.first;
      for (final date in dates) {
        if (date != expected || date.year != today.year || date.month != today.month) {
          break;
        }
        currentMonthStreak++;
        expected = expected.subtract(const Duration(days: 1));
      }
    }

    var longestStreak = 0;
    var runningStreak = 0;
    DateTime? previous;
    for (final date in dates.reversed) {
      if (previous != null && date.difference(previous).inDays == 1) {
        runningStreak++;
      } else {
        runningStreak = 1;
      }
      if (runningStreak > longestStreak) longestStreak = runningStreak;
      previous = date;
    }

    final monthlySignInDays = dates
        .where((date) => date.year == today.year && date.month == today.month)
        .length;

    return {
      'monthlyStreakDay': currentMonthStreak,
      'allTimeStreakDay': currentAllTimeStreak,
      'longestStreakDay': longestStreak,
      'totalSignInDays': dates.length,
      'monthlySignInDays': monthlySignInDays,
    };
  }

  Future<Map<String, dynamic>> getDailySignInStats() async {
    final db = await _db;
    final today = _businessDate(_clock());
    final metrics = await _getSignInMetrics(db, today);
    return {
      'businessDate': _date(today),
      'month': '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}',
      ...metrics,
    };
  }

  /// 从已验证的服务端签到响应维护日历标记，不改动任何本地水滴余额。
  Future<void> recordServerSignIn({
    required String businessDate,
    required int streakDay,
    required int totalWater,
  }) async {
    // 不从前端计算日期或水滴，服务端返回值仅用于当前用户的展示缓存。
    final day = DateTime.tryParse(businessDate);
    if (day == null || businessDate.length != 10 ||
        _date(day) != businessDate || streakDay < 1 || totalWater < 0) {
      throw FormatException('服务端签到数据格式错误');
    }
    final db = await _db;
    await db.insert('daily_sign_ins', {
      'user_id': userId,
      'business_date': businessDate,
      'streak_day': streakDay,
      'base_water': 0,
      'bonus_water': 0,
      'total_water': totalWater,
      'create_time': _dateTime(DateTime.now()),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  @Deprecated('水滴签到已迁移到 mod-server')
  Future<Map<String, dynamic>> dailySignIn() async =>
      throw StateError('本地水滴签到已停用，请调用服务器水滴接口');

  // ---------------------------------------------------------------------------
  // 任务分类
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> getTaskCategories({bool includeDisabled = false}) async {
    final db = await _db;
    await _ensureCategories(db);
    final rows = await db.query('task_categories',
        where: includeDisabled ? 'user_id = ?' : 'user_id = ? AND enabled = 1',
        whereArgs: [userId], orderBy: 'is_default DESC, category_id ASC');
    return rows.map((row) => {
      'categoryId': _int(row['category_id']),
      'name': row['name'],
      'color': row['color'],
      'icon': row['icon'],
      'defaultCategory': _int(row['is_default']) == 1,
      'enabled': _int(row['enabled']) == 1,
    }).toList();
  }

  Future<void> createTaskCategory({required String name, required String color}) async {
    final normalized = name.trim();
    if (normalized.isEmpty || normalized.length > 50) {
      throw ApiException('分类名称不能为空且不能超过 50 个字符', statusCode: 400);
    }
    if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(color)) {
      throw ApiException('颜色必须是 #RRGGBB 格式', statusCode: 400);
    }
    final db = await _db;
    await _ensureCategories(db);
    try {
      await db.insert('task_categories', {
        'user_id': userId,
        'name': normalized,
        'color': color.toUpperCase(),
        'is_default': 0,
        'enabled': 1,
        'create_time': _dateTime(DateTime.now()),
        'update_time': _dateTime(DateTime.now()),
      });
    } on DatabaseException {
      throw ApiException('该分类名称已存在', statusCode: 409);
    }
  }

  Future<void> updateTaskCategory({
    required int categoryId,
    String? name,
    String? color,
    bool? enabled,
  }) async {
    if (name != null && (name.trim().isEmpty || name.trim().length > 50)) {
      throw ApiException('分类名称不能为空且不能超过 50 个字符', statusCode: 400);
    }
    if (color != null && !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(color)) {
      throw ApiException('颜色必须是 #RRGGBB 格式', statusCode: 400);
    }
    final db = await _db;
    final values = <String, Object?>{'update_time': _dateTime(DateTime.now())};
    if (name != null) values['name'] = name.trim();
    if (color != null) values['color'] = color.toUpperCase();
    if (enabled != null) values['enabled'] = enabled ? 1 : 0;
    try {
      final count = await db.update('task_categories', values,
          where: 'category_id = ? AND user_id = ?', whereArgs: [categoryId, userId]);
      if (count != 1) throw ApiException('任务分类不存在', statusCode: 404);
    } on DatabaseException {
      throw ApiException('该分类名称已存在', statusCode: 409);
    }
  }

  // ---------------------------------------------------------------------------
  // 商店 / 盲盒 / 收藏品
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> getShopBoxes() async {
    final db = await _db;
    final rows = await db.query('shop_boxes', where: 'enabled = 1', orderBy: 'box_id');
    return rows.map((row) => {
      'boxId': _int(row['box_id']),
      'name': row['name'],
      'description': row['description'],
      'priceCoin': _int(row['price_coin']),
    }).toList();
  }

  Future<Map<String, dynamic>> getShopBalance() async => _assets(await _db);

  Future<List<Map<String, dynamic>>> getShopHistory({int limit = 20}) async {
    if (limit < 1 || limit > 100) throw ApiException('limit 必须在 1~100 之间', statusCode: 400);
    final db = await _db;
    final rows = await db.query('shop_open_records',
        where: 'user_id = ?', whereArgs: [userId],
        orderBy: 'open_id DESC', limit: limit);
    return rows.map(_shopOpenMap).toList();
  }

  Map<String, dynamic> _shopOpenMap(Map<String, Object?> row) => {
    'openId': _int(row['open_id']),
    'requestId': row['request_id']?.toString() ?? '',
    'boxId': _int(row['box_id']),
    'boxName': row['box_name']?.toString() ?? '盲盒',
    'priceCoin': _int(row['price_coin']),
    'rewardType': row['reward_type']?.toString() ?? '',
    'rewardAmount': _int(row['reward_amount']),
    'coinBalance': _int(row['coin_balance_after']),
    'expBalance': _int(row['exp_balance_after']),
    'waterBalance': _int(row['water_balance_after']),
    'itemId': row['collectible_item_id'],
    'itemName': row['item_name'],
    'itemRarity': row['item_rarity'],
    'itemImagePath': row['item_image_path'],
    'itemDescription': row['item_description'],
  };

  Future<Map<String, dynamic>> openBox({
    required int boxId,
    required String requestId,
  }) async {
    final normalized = requestId.toLowerCase();
    if (!RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
        .hasMatch(normalized)) {
      throw ApiException('requestId 必须是标准 UUID 格式', statusCode: 400);
    }
    final db = await _db;
    return db.transaction((txn) async {
      final existing = await txn.query('shop_open_records',
          where: 'user_id = ? AND request_id = ?',
          whereArgs: [userId, normalized], limit: 1);
      if (existing.isNotEmpty) {
        if (_int(existing.first['box_id']) != boxId) {
          throw ApiException('同一 requestId 不能用于不同商品', statusCode: 409);
        }
        return _shopOpenMap(Map<String, Object?>.from(existing.first));
      }
      final boxes = await txn.query('shop_boxes',
          where: 'box_id = ? AND enabled = 1', whereArgs: [boxId], limit: 1);
      if (boxes.isEmpty) throw ApiException('盲盒不存在或已下架', statusCode: 404);
      final box = boxes.first;
      final rewards = await txn.rawQuery('''
        SELECT r.*, i.name AS item_name, i.rarity AS item_rarity,
               i.description AS item_description, i.image_path AS item_image_path,
               i.enabled AS item_enabled, p.status AS pack_status
        FROM shop_rewards r
        LEFT JOIN collectible_items i ON i.item_id = r.item_id
        LEFT JOIN content_packs p ON p.pack_id = i.pack_id
        WHERE r.box_id = ? AND r.enabled = 1
        ORDER BY r.reward_id
      ''', [boxId]);
      if (rewards.isEmpty) throw ApiException('盲盒尚未配置可用奖励', statusCode: 409);
      final totalWeight = rewards.fold<int>(0, (sum, item) => sum + _int(item['weight']));
      if (totalWeight <= 0) throw ApiException('盲盒奖励权重配置异常');
      var ticket = _random.nextInt(totalWeight);
      Map<String, Object?>? chosen;
      for (final item in rewards) {
        ticket -= _int(item['weight']);
        if (ticket < 0) {
          chosen = Map<String, Object?>.from(item);
          break;
        }
      }
      final reward = chosen ?? Map<String, Object?>.from(rewards.last);
      final type = reward['asset_type']?.toString() ?? '';
      final amount = _int(reward['amount']);
      final itemId = reward['item_id'] == null ? null : _int(reward['item_id']);
      if (amount <= 0 || !['COIN', 'EXP', 'COLLECTIBLE'].contains(type)) {
        throw ApiException('奖励池配置异常');
      }
      if (type == 'COLLECTIBLE' &&
          (itemId == null || _int(reward['item_enabled']) != 1 || reward['pack_status'] != 'PUBLISHED')) {
        throw ApiException('收藏品奖励配置异常');
      }
      final price = _int(box['price_coin']);
      await _ensureAssets(txn);
      final now = _dateTime(DateTime.now());
      final deducted = await txn.rawUpdate(
          'UPDATE user_assets SET coin = coin - ?, update_time = ? WHERE user_id = ? AND coin >= ?',
          [price, now, userId, price]);
      if (deducted != 1) throw ApiException('金币不足，无法开盒', statusCode: 409);
      final openId = await txn.insert('shop_open_records', {
        'user_id': userId,
        'box_id': boxId,
        'request_id': normalized,
        'reward_id': _int(reward['reward_id']),
        'collectible_item_id': type == 'COLLECTIBLE' ? itemId : null,
        'box_name': box['name'],
        'item_name': reward['item_name'],
        'item_rarity': reward['item_rarity'],
        'item_image_path': reward['item_image_path'],
        'item_description': reward['item_description'],
        'price_coin': price,
        'reward_type': type,
        'reward_amount': amount,
        'created_at': now,
      });
      await _recordLedger(txn,
          action: 'SHOP_OPEN_COST',
          assetType: 'COIN',
          amount: -price,
          source: 'SHOP_OPEN',
          sourceId: openId);

      if (type == 'COIN') {
        await _addAssets(txn,
            coin: amount,
            exp: 0,
            water: 0,
            action: 'SHOP_OPEN_REWARD',
            source: 'SHOP_OPEN',
            sourceId: openId);
      } else if (type == 'EXP') {
        await _addAssets(txn,
            coin: 0,
            exp: amount,
            water: 0,
            action: 'SHOP_OPEN_REWARD',
            source: 'SHOP_OPEN',
            sourceId: openId);
      } else {
        final old = await txn.query('user_collectibles',
            where: 'user_id = ? AND item_id = ?', whereArgs: [userId, itemId], limit: 1);
        if (old.isEmpty) {
          await txn.insert('user_collectibles', {
            'user_id': userId,
            'item_id': itemId,
            'owned_count': amount,
            'first_obtained_time': now,
            'last_obtained_time': now,
          });
        } else {
          await txn.update('user_collectibles', {
            'owned_count': _int(old.first['owned_count']) + amount,
            'last_obtained_time': now,
          }, where: 'user_id = ? AND item_id = ?', whereArgs: [userId, itemId]);
        }
        await txn.insert('collectible_acquisition_records', {
          'user_id': userId,
          'item_id': itemId,
          'quantity': amount,
          'source_type': 'SHOP_BOX',
          'source_id': openId,
          'create_time': now,
        });
      }
      final balance = await _assets(txn);
      await txn.update('shop_open_records', {
        'coin_balance_after': balance['coin'],
        'exp_balance_after': balance['exp'],
        'water_balance_after': balance['water'],
      }, where: 'open_id = ?', whereArgs: [openId]);
      return _shopOpenMap({
        'open_id': openId,
        'request_id': normalized,
        'box_id': boxId,
        'box_name': box['name'],
        'price_coin': price,
        'reward_type': type,
        'reward_amount': amount,
        'coin_balance_after': balance['coin'],
        'exp_balance_after': balance['exp'],
        'water_balance_after': balance['water'],
        'collectible_item_id': type == 'COLLECTIBLE' ? itemId : null,
        'item_name': reward['item_name'],
        'item_rarity': reward['item_rarity'],
        'item_image_path': reward['item_image_path'],
        'item_description': reward['item_description'],
      });
    });
  }

  Future<List<Map<String, dynamic>>> getCollectionPacks() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT p.pack_id, p.pack_key, p.name, p.description, p.version, p.unlock_level,
             COUNT(i.item_id) AS total_items,
             COUNT(DISTINCT CASE WHEN COALESCE(uc.owned_count, 0) > 0 THEN i.item_id END) AS owned_items
      FROM content_packs p
      LEFT JOIN collectible_items i ON i.pack_id = p.pack_id AND i.enabled = 1
      LEFT JOIN user_collectibles uc ON uc.item_id = i.item_id AND uc.user_id = ?
      WHERE p.status = 'PUBLISHED'
      GROUP BY p.pack_id
      ORDER BY p.pack_id
    ''', [userId]);
    return rows.map((row) => {
      'packId': _int(row['pack_id']),
      'packKey': row['pack_key'],
      'name': row['name'],
      'description': row['description'],
      'version': row['version'],
      'unlockLevel': _int(row['unlock_level']),
      'totalItems': _int(row['total_items']),
      'ownedItems': _int(row['owned_items']),
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getCollectionItems(int packId) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT i.item_id, i.pack_id, i.item_key, i.name, i.rarity, i.description,
             i.image_path, i.sort_order, COALESCE(uc.owned_count, 0) AS owned_count
      FROM collectible_items i
      JOIN content_packs p ON p.pack_id = i.pack_id
      LEFT JOIN user_collectibles uc ON uc.item_id = i.item_id AND uc.user_id = ?
      WHERE i.pack_id = ? AND i.enabled = 1 AND p.status = 'PUBLISHED'
      ORDER BY i.sort_order, i.item_id
    ''', [userId, packId]);
    return rows.map((row) {
      final count = _int(row['owned_count']);
      return {
        'itemId': _int(row['item_id']),
        'packId': _int(row['pack_id']),
        'itemKey': row['item_key'],
        'name': row['name'],
        'rarity': row['rarity'],
        'description': row['description'],
        'imagePath': row['image_path'],
        'sortOrder': _int(row['sort_order']),
        'ownedCount': count,
        'owned': count > 0,
      };
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // 统计 / 日历 / 时间记录
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> getStats({int days = 7}) async {
    if (days != 7 && days != 30) throw ApiException('统计周期只支持 7 天或 30 天', statusCode: 400);
    final db = await _db;
    final endDate = _businessDate(DateTime.now());
    final startDate = endDate.subtract(Duration(days: days - 1));
    final taskCounts = <String, int>{};
    final habitCounts = <String, int>{};
    final assetsByDay = <String, Map<String, int>>{};

    final taskRows = await db.rawQuery('''
      SELECT tr.record_date, COUNT(*) AS count
      FROM task_records tr JOIN tasks t ON t.task_id = tr.task_id
      WHERE t.user_id = ? AND tr.status = 'COMPLETED'
        AND tr.record_date BETWEEN ? AND ?
      GROUP BY tr.record_date
    ''', [userId, _date(startDate), _date(endDate)]);
    for (final row in taskRows) taskCounts[row['record_date'].toString()] = _int(row['count']);

    final habitRows = await db.rawQuery('''
      SELECT hr.record_date, COUNT(*) AS count
      FROM habit_records hr JOIN habits h ON h.habit_id = hr.habit_id
      WHERE h.user_id = ? AND hr.status = 'COMPLETED'
        AND hr.record_date BETWEEN ? AND ?
      GROUP BY hr.record_date
    ''', [userId, _date(startDate), _date(endDate)]);
    for (final row in habitRows) habitCounts[row['record_date'].toString()] = _int(row['count']);

    final ledgerRows = await db.query('asset_records',
        where: 'user_id = ?', whereArgs: [userId]);
    for (final row in ledgerRows) {
      final created = _parseDateTime(row['create_time']);
      if (created == null) continue;
      final business = _date(_businessDate(created));
      if (business.compareTo(_date(startDate)) < 0 || business.compareTo(_date(endDate)) > 0) continue;
      final bucket = assetsByDay.putIfAbsent(business, () => {
        'coinEarned': 0, 'coinSpent': 0, 'coinNet': 0, 'expEarned': 0, 'expNet': 0,
      });
      final amount = _int(row['amount']);
      if (row['asset_type'] == 'COIN') {
        if (amount > 0) bucket['coinEarned'] = bucket['coinEarned']! + amount;
        if (amount < 0) bucket['coinSpent'] = bucket['coinSpent']! + -amount;
        bucket['coinNet'] = bucket['coinNet']! + amount;
      } else if (row['asset_type'] == 'EXP') {
        if (amount > 0) bucket['expEarned'] = bucket['expEarned']! + amount;
        bucket['expNet'] = bucket['expNet']! + amount;
      }
    }

    final balance = await _assets(db);
    var runningCoin = _int(balance['coin']);
    var runningExp = _int(balance['exp']);
    var completedTasks = 0;
    var habitCheckIns = 0;
    var coinEarned = 0;
    var coinSpent = 0;
    var expEarned = 0;
    final reversed = <Map<String, dynamic>>[];
    for (var i = days - 1; i >= 0; i--) {
      final date = _date(endDate.subtract(Duration(days: days - 1 - i)));
      final taskCount = taskCounts[date] ?? 0;
      final habitCount = habitCounts[date] ?? 0;
      final asset = assetsByDay[date] ?? const <String, int>{};
      final dayCoinEarned = asset['coinEarned'] ?? 0;
      final dayCoinSpent = asset['coinSpent'] ?? 0;
      final dayExpEarned = asset['expEarned'] ?? 0;
      final netCoin = asset['coinNet'] ?? 0;
      final netExp = asset['expNet'] ?? 0;
      completedTasks += taskCount;
      habitCheckIns += habitCount;
      coinEarned += dayCoinEarned;
      coinSpent += dayCoinSpent;
      expEarned += dayExpEarned;
      reversed.add({
        'date': date,
        'completedTasks': taskCount,
        'habitCheckIns': habitCount,
        'coinEarned': dayCoinEarned,
        'coinSpent': dayCoinSpent,
        'expEarned': dayExpEarned,
        'coinBalance': runningCoin,
        'expBalance': runningExp,
      });
      runningCoin -= netCoin;
      runningExp -= netExp;
    }
    final daily = reversed.reversed.toList();
    return {
      'days': days,
      'startDate': _date(startDate),
      'endDate': _date(endDate),
      'summary': {
        'completedTasks': completedTasks,
        'habitCheckIns': habitCheckIns,
        'coinEarned': coinEarned,
        'coinSpent': coinSpent,
        'expEarned': expEarned,
        'coinBalance': _int(balance['coin']),
        'expBalance': _int(balance['exp']),
        'waterBalance': _int(balance['water']),
      },
      'daily': daily,
    };
  }


  Future<Map<String, dynamic>> getCalendarMonth(DateTime month) async {
    final db = await _db;
    final first = DateTime(month.year, month.month, 1);
    final last = DateTime(month.year, month.month + 1, 0);

    // 1. 获取用户的全部任务和习惯
    final taskRows = await db.query(
      'tasks',
      where: 'user_id = ?',
      whereArgs: [userId],
    );

    final habitRows = await db.query(
      'habits',
      where: 'user_id = ?',
      whereArgs: [userId],
    );

    // 2. 一次性查询本月任务执行记录
    final taskRecordRows = await db.rawQuery('''
    SELECT tr.record_date, tr.task_id, tr.status
    FROM task_records tr
    JOIN tasks t ON t.task_id = tr.task_id
    WHERE t.user_id = ?
      AND tr.record_date BETWEEN ? AND ?
  ''', [userId, _date(first), _date(last)]);

    // 3. 一次性查询本月习惯打卡记录
    final habitRecordRows = await db.rawQuery('''
    SELECT hr.record_date, hr.habit_id, hr.status
    FROM habit_records hr
    JOIN habits h ON h.habit_id = hr.habit_id
    WHERE h.user_id = ?
      AND hr.record_date BETWEEN ? AND ?
  ''', [userId, _date(first), _date(last)]);

    // 4. 按日期记录已经存在的任务记录
    final taskRecordMap = <String, Set<int>>{};
    final completedTaskMap = <String, Set<int>>{};

    for (final row in taskRecordRows) {
      final key = row['record_date'].toString();
      final id = _int(row['task_id']);

      taskRecordMap.putIfAbsent(key, () => <int>{}).add(id);

      if (row['status'] == 'COMPLETED') {
        completedTaskMap.putIfAbsent(key, () => <int>{}).add(id);
      }
    }

    // 5. 按日期记录已经存在的习惯记录
    final habitRecordMap = <String, Set<int>>{};
    final completedHabitMap = <String, Set<int>>{};

    for (final row in habitRecordRows) {
      final key = row['record_date'].toString();
      final id = _int(row['habit_id']);

      habitRecordMap.putIfAbsent(key, () => <int>{}).add(id);

      if (row['status'] == 'COMPLETED') {
        completedHabitMap.putIfAbsent(key, () => <int>{}).add(id);
      }
    }

    // 6. 查询时间记录
    final timeRows = await db.rawQuery('''
    SELECT record_date,
           COUNT(*) AS count,
           COALESCE(SUM(duration_minutes), 0) AS minutes
    FROM time_records
    WHERE user_id = ?
      AND record_date BETWEEN ? AND ?
    GROUP BY record_date
  ''', [userId, _date(first), _date(last)]);

    final timeMap = {
      for (final r in timeRows)
        r['record_date'].toString(): r
    };

    // 7. 逐日计算统计数据
    final days = <Map<String, dynamic>>[];

    for (var date = first;
    !date.isAfter(last);
    date = date.add(const Duration(days: 1))) {

      final key = _date(date);

      // 与 getCalendarDay 保持相同的业务日定义
      final dayStart = DateTime(
        date.year,
        date.month,
        date.day,
        5,
      );
      final dayEnd = dayStart.add(const Duration(days: 1));

      final dayTaskRecords =
          taskRecordMap[key] ?? const <int>{};

      final dayHabitRecords =
          habitRecordMap[key] ?? const <int>{};

      // 8. 计算当天应完成的任务数
      final requiredTasks = taskRows.where((raw) {
        final task = Map<String, Object?>.from(raw);
        final id = _int(task['task_id']);

        // 有执行记录，或者当天符合任务周期
        return dayTaskRecords.contains(id) ||
            _isTaskScheduledForBusinessDay(
              task,
              dayStart,
              dayEnd,
            );
      }).length;

      // 9. 计算当天应打卡的习惯数
      final requiredHabits = habitRows.where((raw) {
        final habit = Map<String, Object?>.from(raw);
        final id = _int(habit['habit_id']);

        // 有历史记录的归档习惯也保留
        return dayHabitRecords.contains(id) ||
            (habit['status'] != 'ARCHIVED' &&
                _isHabitScheduled(habit, date));
      }).length;

      final time = timeMap[key];

      // 10. 生成当天统计结果
      days.add({
        'date': key,

        // 已完成数量
        'completedTasks':
        completedTaskMap[key]?.length ?? 0,

        'habitCheckIns':
        completedHabitMap[key]?.length ?? 0,

        // 当天计划数量：新增字段
        'requiredTasks': requiredTasks,
        'requiredHabits': requiredHabits,

        // 时间记录保持原有逻辑
        'timeRecordCount': _int(time?['count']),
        'timeMinutes': _int(time?['minutes']),
      });
    }

    return {
      'month':
      '${month.year.toString().padLeft(4, '0')}-'
          '${month.month.toString().padLeft(2, '0')}',
      'days': days,
    };
  }


  Future<Map<String, dynamic>> getCalendarDay(String date) async {
    final parsed = DateTime.tryParse(date);
    if (parsed == null) throw ApiException('日期格式不正确', statusCode: 400);
    final db = await _db;
    final dateText = _date(parsed);
    final dayStart = DateTime(parsed.year, parsed.month, parsed.day, 5);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final taskRows = await db.query('tasks', where: 'user_id = ?', whereArgs: [userId]);
    final taskRecords = await db.query('task_records', where: 'record_date = ?', whereArgs: [dateText]);
    final taskRecordMap = {for (final r in taskRecords) _int(r['task_id']): r};
    final tasks = <Map<String, dynamic>>[];
    final now = DateTime.now();
    for (final raw in taskRows) {
      final task = Map<String, Object?>.from(raw);
      final id = _int(task['task_id']);
      final record = taskRecordMap[id];
      if (record == null && !_isTaskScheduledForBusinessDay(task, dayStart, dayEnd)) continue;
      final status = record?['status']?.toString() ?? task['status']?.toString() ?? 'PENDING';
      final deadline = _effectiveDeadline(task);
      final terminal = ['COMPLETED', 'CANCELLED', 'ARCHIVED'].contains(task['status']);
      tasks.add({
        'taskId': id,
        'title': task['title'],
        'status': status,
        'overdue': !terminal && deadline != null && !deadline.isAfter(now),
        'actualCount': _int(record?['actual_count']),
        'targetCount': _int(task['target_count'], 1),
        'finishTime': record?['finish_time'],
      });
    }
    tasks.sort((a, b) => (a['status'] as String).compareTo(b['status'] as String));

    final habitRows = await db.query('habits', where: 'user_id = ?', whereArgs: [userId]);
    final habitRecords = await db.query('habit_records', where: 'record_date = ?', whereArgs: [dateText]);
    final habitRecordMap = {for (final r in habitRecords) _int(r['habit_id']): r};
    final habits = <Map<String, dynamic>>[];
    for (final raw in habitRows) {
      final habit = Map<String, Object?>.from(raw);
      final id = _int(habit['habit_id']);
      final record = habitRecordMap[id];
      if (record == null && (habit['status'] == 'ARCHIVED' || !_isHabitScheduled(habit, parsed))) continue;
      habits.add({
        'habitId': id,
        'name': habit['name'],
        'checkedIn': record != null && record['status'] == 'COMPLETED',
        'actualCount': _int(record?['actual_count']),
      });
    }
    habits.sort((a, b) => a['name'].toString().compareTo(b['name'].toString()));

    final timeRows = await db.query('time_records',
        where: 'user_id = ? AND record_date = ?',
        whereArgs: [userId, dateText], orderBy: 'start_time, time_record_id');
    final timeRecords = timeRows.map((row) => {
      'timeRecordId': _int(row['time_record_id']),
      'taskId': row['task_id'],
      'title': row['title'],
      'category': row['category'],
      'startTime': row['start_time'],
      'endTime': row['end_time'],
      'durationMinutes': _int(row['duration_minutes']),
      'note': row['note'],
    }).toList();
    return {'date': dateText, 'tasks': tasks, 'habits': habits, 'timeRecords': timeRecords};
  }

  bool _isTaskScheduledForBusinessDay(
      Map<String, Object?> task, DateTime dayStart, DateTime dayEnd) {
    if (!['PENDING', 'IN_PROGRESS'].contains(task['status'])) return false;
    final start = _parseDateTime(task['start_time']) ?? _parseDateTime(task['create_time']);
    final deadline = _effectiveDeadline(task);
    final startsOnDay = start != null && !start.isBefore(dayStart) && start.isBefore(dayEnd);
    final dueOnDay = deadline != null && deadline.isAfter(dayStart) && !deadline.isAfter(dayEnd);
    return startsOnDay || dueOnDay;
  }

  Future<void> createTimeRecord({
    required String title,
    required String category,
    required DateTime startTime,
    required DateTime endTime,
    String? note,
  }) async {
    await _saveTimeRecord(
      title: title,
      category: category,
      startTime: startTime,
      endTime: endTime,
      note: note,
    );
  }

  Future<void> updateTimeRecord({
    required int recordId,
    required String title,
    required String category,
    required DateTime startTime,
    required DateTime endTime,
    int? taskId,
    String? note,
  }) async {
    await _saveTimeRecord(
      recordId: recordId,
      title: title,
      category: category,
      startTime: startTime,
      endTime: endTime,
      taskId: taskId,
      note: note,
    );
  }

  Future<void> _saveTimeRecord({
    int? recordId,
    required String title,
    required String category,
    required DateTime startTime,
    required DateTime endTime,
    int? taskId,
    String? note,
  }) async {
    if (title.trim().isEmpty || category.trim().isEmpty) {
      throw ApiException('时间记录名称和分类不能为空', statusCode: 400);
    }
    if (!endTime.isAfter(startTime)) throw ApiException('结束时间必须晚于开始时间', statusCode: 400);
    if (endTime.isAfter(DateTime.now())) throw ApiException('时间记录不能包含未来时间', statusCode: 400);
    final startBusiness = _businessDate(startTime);
    final endBusiness = _businessDate(endTime.subtract(const Duration(microseconds: 1)));
    if (_date(startBusiness) != _date(endBusiness)) {
      throw ApiException('单条时间记录不能跨越凌晨 05:00 的业务日边界，请拆分记录', statusCode: 400);
    }
    final duration = endTime.difference(startTime).inMinutes;
    if (duration < 1) throw ApiException('时间记录至少为 1 分钟', statusCode: 400);
    final db = await _db;
    if (taskId != null) {
      final task = await db.query('tasks', where: 'task_id = ? AND user_id = ?', whereArgs: [taskId, userId], limit: 1);
      if (task.isEmpty) throw ApiException('关联任务不存在或不属于该用户', statusCode: 404);
    }
    final values = <String, Object?>{
      'user_id': userId,
      'task_id': taskId,
      'title': title.trim(),
      'category': category.trim(),
      'start_time': _dateTime(startTime),
      'end_time': _dateTime(endTime),
      'duration_minutes': duration,
      'record_date': _date(startBusiness),
      'note': note == null || note.trim().isEmpty ? null : note.trim(),
      'update_time': _dateTime(DateTime.now()),
    };
    if (recordId == null) {
      values['create_time'] = _dateTime(DateTime.now());
      await db.insert('time_records', values);
    } else {
      final count = await db.update('time_records', values,
          where: 'time_record_id = ? AND user_id = ?', whereArgs: [recordId, userId]);
      if (count != 1) throw ApiException('时间记录不存在', statusCode: 404);
    }
  }

  Future<void> deleteTimeRecord({required int recordId}) async {
    final db = await _db;
    final count = await db.delete('time_records',
        where: 'time_record_id = ? AND user_id = ?', whereArgs: [recordId, userId]);
    if (count != 1) throw ApiException('时间记录不存在', statusCode: 404);
  }

  // ---------------------------------------------------------------------------
  // 本地设置、备份恢复与存储状态
  // ---------------------------------------------------------------------------

  Future<String?> getAppSetting(String key) async {
    final db = await _db;
    final rows = await db.query(
      'app_settings',
      columns: ['setting_value'],
      where: 'setting_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['setting_value']?.toString();
  }

  Future<void> setAppSetting(String key, String value) async {
    final db = await _db;
    await db.insert(
      'app_settings',
      {
        'setting_key': key,
        'setting_value': value,
        'update_time': _dateTime(DateTime.now()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 导出当前分区：账号切换后不得把其他账号的数据装入备份。
  Future<String> exportBackupJson() async {
    final db = await _db;
    await ensureReady();
    final tables = <String, List<Map<String, Object?>>>{};
    for (final table in _backupTables) {
      final rows = switch (table) {
        'task_records' || 'task_cycle_records' =>
          await db.rawQuery('SELECT r.* FROM $table r JOIN tasks t ON r.task_id=t.task_id WHERE t.user_id=?', [userId]),
        'habit_records' =>
          await db.rawQuery('SELECT r.* FROM habit_records r JOIN habits h ON r.habit_id=h.habit_id WHERE h.user_id=?', [userId]),
        'app_settings' => <Map<String, Object?>>[], // 全局设置不跟随账号导出
        _ => await _exportTableForAccount(db, table),
      };
      tables[table] = rows.map((row) => Map<String, Object?>.from(row)).toList();
    }
    return const JsonEncoder.withIndent('  ').convert({
      'format': 'planblindbox-local-backup',
      'formatVersion': 1,
      'databaseVersion': await db.getVersion(),
      'backupUserId': userId,
      'exportedAt': DateTime.now().toIso8601String(),
      'tables': tables,
    });
  }

  Future<List<Map<String, Object?>>> _exportTableForAccount(Database db,String table) async {
    if (table == 'core_sync_rescue') {
      final rows = await db.query(table, where: 'user_id=?', whereArgs: [userId]);
      return rows.map((item) => Map<String, Object?>.from(item)
        ..remove('rescue_id')).toList();
    }
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    if (cols.any((col) => col['name']=='user_id')) {
      return db.query(table, where:'user_id=?', whereArgs:[_ownerForTable(table)]);
    }
    return db.query(table); // 全局只读目录，如盲盒定义与收藏品目录
  }

  Future<void> restoreBackupJson(String content) async {
    if (content.length > 50 * 1024 * 1024) {
      throw ApiException('备份文件超过 50 MB，无法安全导入', statusCode: 400);
    }

    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != 'planblindbox-local-backup' ||
        decoded['formatVersion'] != 1) {
      throw ApiException('备份文件格式不正确或版本不受支持', statusCode: 400);
    }

    final db = await _db;
    // 只接受当前账号签名的快照；恢复操作随后严格按 user_id 删除，
    // 不会覆盖同设备其他账号。旧匿名快照仍只允许游客恢复。
    final backupOwner = decoded['backupUserId'];
    if (backupOwner != null && _int(backupOwner, -99999999) != userId) {
      throw ApiException('备份属于其他账号，禁止跨账号覆盖恢复', statusCode: 403);
    }
    if (backupOwner == null && userId != 1) {
      throw ApiException('旧版备份未声明账号，不能直接恢复到登录账号', statusCode: 403);
    }
    final backupDatabaseVersion = _int(decoded['databaseVersion'], -1);
    final currentDatabaseVersion = await db.getVersion();
    final restoreLegacyV1 = backupDatabaseVersion == 1 && (currentDatabaseVersion == 4 || currentDatabaseVersion == 5);
    final restoreLegacyV2 = backupDatabaseVersion == 2 && (currentDatabaseVersion == 4 || currentDatabaseVersion == 5);
    final restoreLegacyV3 = backupDatabaseVersion == 3 && (currentDatabaseVersion == 4 || currentDatabaseVersion == 5);
    final restoreLegacyV4 = backupDatabaseVersion == 4 && currentDatabaseVersion == 5;
    if (backupDatabaseVersion != currentDatabaseVersion &&
        !restoreLegacyV1 && !restoreLegacyV2 && !restoreLegacyV3 && !restoreLegacyV4) {
      throw ApiException(
        '备份数据库版本为 $backupDatabaseVersion，当前版本为 $currentDatabaseVersion，暂不支持跨版本恢复',
        statusCode: 400,
      );
    }

    final rawTables = decoded['tables'];
    if (rawTables is! Map) throw ApiException('备份文件缺少数据表内容', statusCode: 400);

    final prepared = <String, List<Map<String, Object?>>>{};
    for (final table in _backupTables) {
      final rawRows = rawTables[table];
      if (rawRows is! List && !((restoreLegacyV1 || restoreLegacyV2 || restoreLegacyV3 || restoreLegacyV4) && table == 'core_sync_rescue') && !((restoreLegacyV1 || restoreLegacyV2) &&
          table == 'custom_product_categories') && !((restoreLegacyV1 || restoreLegacyV2 || restoreLegacyV3) &&
          const {'wellbeing_entries', 'wellbeing_moods'}.contains(table)) && !(restoreLegacyV1 &&
          const {'custom_products', 'custom_inventory',
            'custom_purchase_records', 'custom_use_records'}.contains(table))) {
        throw ApiException('备份文件缺少数据表：$table', statusCode: 400);
      }
      final columnRows = await db.rawQuery('PRAGMA table_info($table)');
      final allowedColumns = columnRows.map((row) => row['name'].toString()).toSet();
      final rows = <Map<String, Object?>>[];
      for (final rawRow in (rawRows is List ? rawRows : const [])) {
        if (rawRow is! Map) throw ApiException('数据表 $table 中存在无效记录', statusCode: 400);
        final row = <String, Object?>{};
        for (final entry in rawRow.entries) {
          final key = entry.key.toString();
          if (!allowedColumns.contains(key)) {
            throw ApiException('数据表 $table 包含未知字段：$key', statusCode: 400);
          }
          row[key] = entry.value;
        }
        rows.add(row);
      }
      for (final row in rows) {
        if (row.containsKey('user_id') && _int(row['user_id'], -99999999) != _ownerForTable(table)) {
          throw ApiException('备份内存在其他账号的数据：$table', statusCode: 403);
        }
      }
      prepared[table] = rows;
    }

    await db.transaction((txn) async {
      // 关系表没有 user_id，必须使用父记录的 user_id 过滤。
      await txn.rawDelete('DELETE FROM task_records WHERE task_id IN (SELECT task_id FROM tasks WHERE user_id=?)',[userId]);
      await txn.rawDelete('DELETE FROM task_cycle_records WHERE task_id IN (SELECT task_id FROM tasks WHERE user_id=?)',[userId]);
      await txn.rawDelete('DELETE FROM habit_records WHERE habit_id IN (SELECT habit_id FROM habits WHERE user_id=?)',[userId]);
      const globalCatalogs = <String>{
        'content_packs','collectible_items','shop_boxes','shop_rewards',
      };
      for (final table in _restoreDeleteOrder) {
        if (table == 'app_settings' || globalCatalogs.contains(table) ||
            const {'task_records','task_cycle_records','habit_records'}.contains(table)) continue;
        await txn.delete(table, where: 'user_id=?', whereArgs: [_ownerForTable(table)]);
      }
      for (final table in _restoreInsertOrder) {
        if (table == 'app_settings') continue;
        for (final row in prepared[table]!) {
          if (globalCatalogs.contains(table)) {
            // 静态目录可能已存在；不覆盖其他用户共享的定义。
            await txn.insert(table, row, conflictAlgorithm: ConflictAlgorithm.ignore);
          } else {
            await txn.insert(table, row);
          }
        }
      }
      // A previous frozen network request must never replay pre-restore data.
      // Keep transactional dirty markers; the new snapshot will be sent later.
      await txn.delete('core_sync_outbox', where: 'user_id=?',
          whereArgs: [userId]);
      await txn.insert(
        'app_settings',
        {
          'setting_key': 'last_restore_at',
          'setting_value': DateTime.now().toIso8601String(),
          'update_time': _dateTime(DateTime.now()),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  /// 清空个人业务数据并重新初始化资产、默认分类。
  /// 静态盲盒目录和收藏品内容包保留，避免重置后商店无法使用。
  /// 仅清除当前账号的本地数据，不影响同一设备上的其他账号。
  Future<void> resetLocalData({bool resetPreferences = true}) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.rawDelete('DELETE FROM task_records WHERE task_id IN (SELECT task_id FROM tasks WHERE user_id=?)',[userId]);
      await txn.rawDelete('DELETE FROM task_cycle_records WHERE task_id IN (SELECT task_id FROM tasks WHERE user_id=?)',[userId]);
      await txn.rawDelete('DELETE FROM habit_records WHERE habit_id IN (SELECT habit_id FROM habits WHERE user_id=?)',[userId]);
      const tables = <String>[
        'wellbeing_entries','wellbeing_moods',
        'custom_use_records','custom_purchase_records','custom_inventory',
        'custom_products','custom_product_categories',
        'shop_open_records','collectible_acquisition_records','user_collectibles',
        'time_records','habits','tasks','task_categories',
        'asset_records','daily_sign_ins','user_assets','core_sync_rescue',
      ];
      for (final table in tables) {
        await txn.delete(table,where:'user_id=?',whereArgs:[_ownerForTable(table)]);
      }
      // app_settings 属于设备级配置，不允许因为某个账号重置而清除。
    });
    await ensureReady();
  }

  Future<List<Map<String, Object?>>> _countTableForAccount(Database db,String table) async {
    final cols=await db.rawQuery('PRAGMA table_info($table)');
    return db.rawQuery(cols.any((c)=>c['name']=='user_id')
      ? 'SELECT COUNT(*) AS total FROM $table WHERE user_id=?'
      : 'SELECT COUNT(*) AS total FROM $table',
      cols.any((c)=>c['name']=='user_id') ? [_ownerForTable(table)] : []);
  }

  Future<Map<String, dynamic>> getStorageStatus() async {
    final db = await _db;
    await ensureReady();
    final storage = await _localDatabase.getStorageInfo();
    final counts = <String, int>{};
    for (final entry in _statusTables.entries) {
      final table = entry.value;
      final rows = switch (table) {
        'task_records' || 'task_cycle_records' => await db.rawQuery(
            'SELECT COUNT(*) AS total FROM $table r JOIN tasks t ON r.task_id=t.task_id WHERE t.user_id=?', [userId]),
        'habit_records' => await db.rawQuery(
            'SELECT COUNT(*) AS total FROM habit_records r JOIN habits h ON r.habit_id=h.habit_id WHERE h.user_id=?', [userId]),
        'app_settings' => <Map<String, Object?>>[{'total': 0}],
        _ => await _countTableForAccount(db, table),
      };
      counts[entry.key] = _int(rows.first['total']);
    }

    String? latestUpdate;
    const latestQueries = <(String, String)>[
      ('tasks', 'update_time'),
      ('habits', 'update_time'),
      ('task_categories', 'update_time'),
      ('time_records', 'update_time'),
      ('user_assets', 'update_time'),
      ('daily_sign_ins', 'create_time'),
      ('asset_records', 'create_time'),
      ('shop_open_records', 'created_at'),
      ('custom_products', 'update_time'),
      ('custom_inventory', 'update_time'),
      ('custom_purchase_records', 'create_time'),
      ('custom_use_records', 'create_time'),
    ];
    for (final query in latestQueries) {
      final rows = await db.rawQuery(
        'SELECT MAX(${query.$2}) AS latest FROM ${query.$1} WHERE user_id = ?',
        [userId],
      );
      final value = rows.first['latest']?.toString();
      if (value != null && (latestUpdate == null || value.compareTo(latestUpdate) > 0)) {
        latestUpdate = value;
      }
    }

    final lastBackupAt = await getAppSetting('last_backup_at');
    final lastRestoreAt = await getAppSetting('last_restore_at');
    return {
      ...storage,
      'counts': counts,
      'totalRecords': counts.values.fold<int>(0, (sum, count) => sum + count),
      'lastUpdatedAt': latestUpdate,
      'lastBackupAt': lastBackupAt,
      'lastRestoreAt': lastRestoreAt,
    };
  }

}
