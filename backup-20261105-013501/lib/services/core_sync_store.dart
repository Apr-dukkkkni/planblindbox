import 'dart:convert';
import 'dart:math';

import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common/sqlite_api.dart' show DatabaseExecutor;

import '../data/local/local_database.dart';

/// Durable record-level sync for TASK / HABIT, independent of view lifecycle.
/// This class never changes the trusted server water wallet.
class CoreSyncStore {
  CoreSyncStore(this.userId, {LocalDatabase? database})
      : _database = database ?? LocalDatabase.instance {
    if (userId > -1000001) {
      throw ArgumentError('云同步只允许已登录账号的本地分区');
    }
  }

  final int userId;
  final LocalDatabase _database;
  Future<Database> get _db => _database.database;

  static const _taskFields = <String>[
    'title', 'note', 'start_time', 'end_time', 'target_count',
    'recurrence_type', 'repeat_interval_days', 'repeat_days', 'cycle_days',
    'recurrence_end_date', 'status', 'importance', 'urgency', 'difficulty',
    'priority_score', 'estimated_minutes', 'record_rule', 'create_time',
    'update_time',
  ];
  static const _habitFields = <String>[
    'name', 'note', 'start_date', 'end_date', 'repeat_rule', 'status',
    'importance', 'difficulty', 'create_time', 'update_time',
  ];
  static const _recordFields = <String>[
    'record_date', 'status', 'finish_time', 'actual_count',
    'create_time', 'update_time',
  ];
  static const _cycleFields = <String>[
    'cycle_start_date', 'cycle_end_date', 'target_count', 'actual_count',
    'status', 'reward_granted', 'completed_at', 'create_time', 'update_time',
  ];

  static String _uuid() {
    final random = Random.secure();
    final b = List<int>.generate(16, (_) => random.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  String _table(String type) => switch (type) {
    'task' => 'tasks',
    'habit' => 'habits',
    _ => throw const FormatException('不支持的同步记录类型'),
  };
  String _pk(String type) => type == 'task' ? 'task_id' : 'habit_id';
  int _asInt(Object? value) => value is num ? value.toInt() : int.parse('$value');
  Map<String, Object?> _pick(Map<String, Object?> row, List<String> fields) =>
      {for (final field in fields) field: row[field]};

  Future<int> cursor() async {
    final db = await _db;
    final rows = await db.query('core_sync_cursor',
        where: 'user_id=?', whereArgs: [userId], limit: 1);
    return rows.isEmpty ? 0 : _asInt(rows.first['cursor']);
  }

  Future<void> bootstrap() async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.insert('core_sync_cursor',
          {'user_id': userId, 'cursor': 0, 'bootstrapped': 0},
          conflictAlgorithm: ConflictAlgorithm.ignore);
      final rows = await txn.query('core_sync_cursor',
          where: 'user_id=?', whereArgs: [userId]);
      if (_asInt(rows.first['bootstrapped']) != 0) return;
      // Remote-imported UUIDs have a revision; do not upload them again.
      for (final type in const ['task', 'habit']) {
        final table = _table(type);
        final pk = _pk(type);
        await txn.rawInsert('''INSERT OR IGNORE INTO core_sync_dirty
            (user_id,record_type,record_uuid,local_id,deleted)
          SELECT p.user_id,?,p.sync_uuid,p.$pk,0 FROM $table p
          WHERE p.user_id=? AND p.sync_uuid IS NOT NULL
            AND NOT EXISTS (
              SELECT 1 FROM core_sync_state s WHERE s.user_id=p.user_id
                AND s.record_type=? AND s.record_uuid=p.sync_uuid)
        ''', [type, userId, type]);
      }
      await txn.update('core_sync_cursor', {'bootstrapped': 1},
          where: 'user_id=?', whereArgs: [userId]);
    });
  }

  Future<Map<String, dynamic>?> _snapshot(
      DatabaseExecutor txn, String type, String uuid) async {
    final table = _table(type);
    final pk = _pk(type);
    final rows = await txn.query(table,
        where: 'user_id=? AND sync_uuid=?',
        whereArgs: [userId, uuid], limit: 1);
    if (rows.isEmpty) return null;
    final row = rows.first;
    final id = row[pk];
    final entity = _pick(row, type == 'task' ? _taskFields : _habitFields);
    if (type == 'task') {
      Map<String, Object?>? category;
      if (row['category_id'] != null) {
        final categories = await txn.query('task_categories',
            where: 'user_id=? AND category_id=?',
            whereArgs: [userId, row['category_id']], limit: 1);
        if (categories.isNotEmpty) {
          category = _pick(categories.first,
              const ['name', 'color', 'icon', 'enabled']);
        }
      }
      final records = await txn.query('task_records',
          where: 'task_id=?', whereArgs: [id], orderBy: 'record_date');
      final cycles = await txn.query('task_cycle_records',
          where: 'task_id=?', whereArgs: [id], orderBy: 'cycle_start_date');
      return {
        'entity': entity,
        'category': category,
        'records': records.map((r) => _pick(r, _recordFields)).toList(),
        'cycles': cycles.map((r) => _pick(r, _cycleFields)).toList(),
      };
    }
    final records = await txn.query('habit_records',
        where: 'habit_id=?', whereArgs: [id], orderBy: 'record_date');
    return {
      'entity': entity,
      'records': records.map((r) => _pick(r, _recordFields)).toList(),
    };
  }

  Future<CorePendingMutation?> existingMutation() async {
    final db = await _db;
    final rows = await db.rawQuery('''SELECT o.* FROM core_sync_outbox o
      WHERE o.user_id=? AND NOT EXISTS (
        SELECT 1 FROM core_sync_conflict c WHERE c.user_id=o.user_id
          AND c.record_type=o.record_type AND c.record_uuid=o.record_uuid)
      ORDER BY o.rowid LIMIT 1''', [userId]);
    return rows.isEmpty ? null : CorePendingMutation.fromRow(rows.first);
  }

  Future<CorePendingMutation?> nextMutation() async {
    final db = await _db;
    return db.transaction((txn) async {
      final existing = await txn.rawQuery('''SELECT o.* FROM core_sync_outbox o
        WHERE o.user_id=? AND NOT EXISTS (
          SELECT 1 FROM core_sync_conflict c WHERE c.user_id=o.user_id
            AND c.record_type=o.record_type AND c.record_uuid=o.record_uuid)
        ORDER BY o.rowid LIMIT 1''', [userId]);
      if (existing.isNotEmpty) return CorePendingMutation.fromRow(existing.first);
      final dirty = await txn.rawQuery('''SELECT d.* FROM core_sync_dirty d
        WHERE d.user_id=? AND NOT EXISTS (
          SELECT 1 FROM core_sync_conflict c WHERE c.user_id=d.user_id
            AND c.record_type=d.record_type AND c.record_uuid=d.record_uuid)
        ORDER BY d.rowid LIMIT 1''', [userId]);
      if (dirty.isEmpty) return null;
      final row = dirty.first;
      final type = row['record_type']! as String;
      final uuid = row['record_uuid']! as String;
      final data = await _snapshot(txn, type, uuid);
      final deleted = data == null;
      final states = await txn.query('core_sync_state',
        where: 'user_id=? AND record_type=? AND record_uuid=?',
        whereArgs: [userId, type, uuid], limit: 1);
      final revision = states.isEmpty ? 0 : _asInt(states.first['revision']);
      if (deleted && revision == 0) {
        // A record created and deleted offline, never visible on server.
        await txn.delete('core_sync_dirty',
            where: 'user_id=? AND record_type=? AND record_uuid=?',
            whereArgs: [userId, type, uuid]);
        return null;
      }
      final json = deleted ? null : jsonEncode(data);
      if (json != null && utf8.encode(json).length > 65536) {
        throw StateError('$type 记录超过服务器 64KiB 同步上限，已保留本地记录');
      }
      final message = CorePendingMutation(
          type: type, uuid: uuid, operationId: _uuid(),
          expectedRevision: revision, deleted: deleted,
          payloadJson: json, generation: _asInt(row['generation']));
      await txn.insert('core_sync_outbox', {
        'user_id': userId, 'record_type': type, 'record_uuid': uuid,
        'operation_id': message.operationId,
        'expected_revision': revision, 'deleted': deleted ? 1 : 0,
        'payload': json, 'source_generation': message.generation,
      });
      return message;
    });
  }

  Future<void> acknowledge(CorePendingMutation mutation, int revision) async {
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.query('core_sync_outbox',
          where: 'user_id=? AND record_type=? AND record_uuid=? AND operation_id=?',
          whereArgs: [userId, mutation.type, mutation.uuid, mutation.operationId]);
      if (rows.isEmpty) return;
      await _putState(txn, mutation.type, mutation.uuid, revision);
      await txn.delete('core_sync_outbox',
          where: 'user_id=? AND record_type=? AND record_uuid=?',
          whereArgs: [userId, mutation.type, mutation.uuid]);
      await txn.delete('core_sync_dirty',
          where: 'user_id=? AND record_type=? AND record_uuid=? AND generation=?',
          whereArgs: [userId, mutation.type, mutation.uuid, mutation.generation]);
    });
  }

  Future<void> _putState(DatabaseExecutor txn,
      String type, String uuid, int revision) async {
    await txn.insert('core_sync_state', {
      'user_id': userId, 'record_type': type,
      'record_uuid': uuid, 'revision': revision,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Applies exactly one server page and persists its cursor atomically.
  /// Data from another account cannot be used as a local SQLite owner ID.
  Future<int> applyPage(List<dynamic> changes, int nextCursor) async {
    final db = await _db;
    return db.transaction((txn) async {
      int applied = 0;
      await txn.update('core_sync_runtime', {'enabled': 0}, where: 'id=1');
      for (final item in changes) {
        if (item is! Map) throw const FormatException('云同步变更格式错误');
        final type = item['type']?.toString() ?? '';
        final uuid = item['id']?.toString() ?? '';
        final revision = _asInt(item['revision']);
        final deleted = item['deleted'] == true;
        final payload = item['payload'];
        if (revision < 1 || uuid.length != 36) {
          throw const FormatException('云同步记录标识无效');
        }
        if (type != 'task' && type != 'habit') {
          // Do not lose future encrypted record types when advancing cursor.
          await txn.insert('core_sync_deferred', {
            'user_id': userId, 'record_type': type, 'record_uuid': uuid,
            'revision': revision, 'deleted': deleted ? 1 : 0,
            'payload': payload == null ? null : jsonEncode(payload),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
          continue;
        }
        final states = await txn.query('core_sync_state',
            where: 'user_id=? AND record_type=? AND record_uuid=?',
            whereArgs: [userId, type, uuid], limit: 1);
        final oldRevision = states.isEmpty ? 0 : _asInt(states.first['revision']);
        if (oldRevision >= revision) continue;
        final dirty = await txn.query('core_sync_dirty',
            where: 'user_id=? AND record_type=? AND record_uuid=?',
            whereArgs: [userId, type, uuid], limit: 1);
        if (dirty.isNotEmpty) {
          await txn.insert('core_sync_conflict', {
            'user_id': userId, 'record_type': type, 'record_uuid': uuid,
            'remote_revision': revision, 'remote_deleted': deleted ? 1 : 0,
            'remote_payload': payload == null ? null : jsonEncode(payload),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        } else {
          await _applyRemote(txn, type, uuid, deleted, payload);
          applied++;
        }
        await _putState(txn, type, uuid, revision);
      }
      await txn.insert('core_sync_cursor', {
        'user_id': userId, 'cursor': nextCursor,
        'bootstrapped': 0,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await txn.update('core_sync_cursor', {'cursor': nextCursor},
          where: 'user_id=? AND cursor<=?', whereArgs: [userId, nextCursor]);
      await txn.update('core_sync_runtime', {'enabled': 1}, where: 'id=1');
      return applied;
    });
  }

  Future<void> _applyRemote(DatabaseExecutor txn,
      String type, String uuid, bool deleted, Object? payload) async {
    final table = _table(type);
    final pk = _pk(type);
    final existing = await txn.query(table,
        columns: [pk], where: 'user_id=? AND sync_uuid=?',
        whereArgs: [userId, uuid], limit: 1);
    if (deleted) {
      if (existing.isNotEmpty) {
        await txn.delete(table, where: 'user_id=? AND sync_uuid=?',
            whereArgs: [userId, uuid]);
      }
      return;
    }
    if (payload is! Map || payload['entity'] is! Map ||
        payload['records'] is! List) {
      throw const FormatException('远端任务或习惯数据格式错误');
    }
    final entityRaw = Map<String, Object?>.from(payload['entity'] as Map);
    if (type == 'task' && (entityRaw['title'] is! String ||
        (entityRaw['title'] as String).trim().isEmpty)) {
      throw const FormatException('远端任务标题错误');
    }
    if (type == 'habit' && (entityRaw['name'] is! String ||
        (entityRaw['name'] as String).trim().isEmpty)) {
      throw const FormatException('远端习惯名称错误');
    }
    final values = _pick(entityRaw,
        type == 'task' ? _taskFields : _habitFields);
    values['user_id'] = userId;
    values['sync_uuid'] = uuid;
    if (type == 'task') {
      int? categoryId;
      final categoryRaw = payload['category'];
      if (categoryRaw is Map && categoryRaw['name'] is String) {
        final name = (categoryRaw['name'] as String).trim();
        if (name.isNotEmpty) {
          final cats = await txn.query('task_categories',
              where: 'user_id=? AND name=?', whereArgs: [userId, name], limit: 1);
          if (cats.isNotEmpty) {
            categoryId = _asInt(cats.first['category_id']);
          } else {
            categoryId = await txn.insert('task_categories', {
              'user_id': userId, 'name': name,
              'color': categoryRaw['color'] is String ? categoryRaw['color'] : '#607D8B',
              'icon': categoryRaw['icon'] is String ? categoryRaw['icon'] : null,
              'is_default': 0,
              'enabled': 1,
              'create_time': DateTime.now().toIso8601String(),
              'update_time': DateTime.now().toIso8601String(),
            });
          }
        }
      }
      values['category_id'] = categoryId;
    }
    final int localId;
    if (existing.isEmpty) {
      localId = await txn.insert(table, values);
    } else {
      localId = _asInt(existing.first[pk]);
      await txn.update(table, values, where: '$pk=? AND user_id=?',
          whereArgs: [localId, userId]);
    }
    final recordTable = type == 'task' ? 'task_records' : 'habit_records';
    await txn.delete(recordTable, where: '$pk=?', whereArgs: [localId]);
    for (final raw in payload['records'] as List) {
      if (raw is! Map) throw const FormatException('远端打卡记录格式错误');
      final row = _pick(Map<String, Object?>.from(raw), _recordFields);
      if (row['record_date'] is! String) {
        throw const FormatException('远端打卡日期错误');
      }
      await txn.insert(recordTable, {...row, pk: localId});
    }
    if (type == 'task') {
      if (payload['cycles'] is! List) {
        throw const FormatException('远端周期记录格式错误');
      }
      await txn.delete('task_cycle_records',
          where: 'task_id=?', whereArgs: [localId]);
      for (final raw in payload['cycles'] as List) {
        if (raw is! Map) throw const FormatException('远端周期记录格式错误');
        await txn.insert('task_cycle_records', {
          ..._pick(Map<String, Object?>.from(raw), _cycleFields),
          'task_id': localId,
        });
      }
    }
  }

  Future<List<CoreSyncConflict>> conflicts() async {
    final db = await _db;
    final rows = await db.query('core_sync_conflict',
        where: 'user_id=?', whereArgs: [userId], orderBy: 'record_type,record_uuid');
    return rows.map((r) => CoreSyncConflict(
        type: r['record_type']! as String,
        uuid: r['record_uuid']! as String,
        remoteRevision: _asInt(r['remote_revision']))).toList();
  }

  Future<int> pendingCount() async {
    final db = await _db;
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM core_sync_dirty WHERE user_id=?', [userId]);
    return _asInt(rows.first['c']);
  }

  Future<void> resolve(String type, String uuid, {required bool keepLocal}) async {
    final db = await _db;
    await db.transaction((txn) async {
      _table(type);
      final conflicts = await txn.query('core_sync_conflict',
          where: 'user_id=? AND record_type=? AND record_uuid=?',
          whereArgs: [userId, type, uuid]);
      if (conflicts.isEmpty) return;
      // Preserve the rejected version of BOTH sides for a later rescue.
      // Resolving a conflict is never an irreversible silent discard.
      final localCopy = await _snapshot(txn, type, uuid);
      await txn.insert('core_sync_rescue', {
        'user_id': userId, 'record_type': type, 'record_uuid': uuid,
        'remote_revision': conflicts.first['remote_revision'],
        'local_payload': localCopy == null ? null : jsonEncode(localCopy),
        'remote_payload': conflicts.first['remote_payload'],
        'chosen': keepLocal ? 'local' : 'remote',
        'resolved_at': DateTime.now().toUtc().toIso8601String(),
      });
      if (!keepLocal) {
        final row = conflicts.first;
        await txn.update('core_sync_runtime', {'enabled': 0}, where: 'id=1');
        await _applyRemote(txn, type, uuid, _asInt(row['remote_deleted']) == 1,
            row['remote_payload'] == null ? null : jsonDecode(row['remote_payload'] as String));
        await txn.update('core_sync_runtime', {'enabled': 1}, where: 'id=1');
        await txn.delete('core_sync_dirty',
            where: 'user_id=? AND record_type=? AND record_uuid=?',
            whereArgs: [userId, type, uuid]);
      } else {
        final table = _table(type);
        final id = _pk(type);
        final data = await txn.query(table, columns: [id],
            where: 'user_id=? AND sync_uuid=?', whereArgs: [userId, uuid]);
        await txn.rawInsert('''INSERT INTO core_sync_dirty
          (user_id,record_type,record_uuid,local_id,deleted)
          VALUES(?,?,?,?,?)
          ON CONFLICT(user_id,record_type,record_uuid) DO UPDATE SET
            local_id=excluded.local_id,deleted=excluded.deleted,generation=generation+1''',
          [userId, type, uuid, data.isEmpty ? null : data.first[id], data.isEmpty ? 1 : 0]);
      }
      await txn.delete('core_sync_outbox',
          where: 'user_id=? AND record_type=? AND record_uuid=?',
          whereArgs: [userId, type, uuid]);
      await txn.delete('core_sync_conflict',
          where: 'user_id=? AND record_type=? AND record_uuid=?',
          whereArgs: [userId, type, uuid]);
    });
  }
}

class CorePendingMutation {
  const CorePendingMutation({required this.type, required this.uuid,
    required this.operationId, required this.expectedRevision,
    required this.deleted, required this.payloadJson, required this.generation});
  final String type;
  final String uuid;
  final String operationId;
  final int expectedRevision;
  final bool deleted;
  final String? payloadJson;
  final int generation;

  factory CorePendingMutation.fromRow(Map<String, Object?> row) => CorePendingMutation(
      type: row['record_type']! as String,
      uuid: row['record_uuid']! as String,
      operationId: row['operation_id']! as String,
      expectedRevision: (row['expected_revision'] as num).toInt(),
      deleted: (row['deleted'] as num).toInt() != 0,
      payloadJson: row['payload'] as String?,
      generation: (row['source_generation'] as num).toInt());
}

class CoreSyncConflict {
  const CoreSyncConflict({required this.type, required this.uuid,
      required this.remoteRevision});
  final String type;
  final String uuid;
  final int remoteRevision;
}
