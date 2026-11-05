import 'package:sqflite/sqflite.dart';

import 'local/local_database.dart';
import '../services/private_sync_vault.dart';

/// 情绪、经期和日记只保存在当前设备的 SQLite 中；与注册账号资料分开。
class MoodChoice {
  const MoodChoice(this.name, this.emoji, {this.custom = false});
  final String name;
  final String emoji;
  final bool custom;

  static const defaults = <MoodChoice>[
    MoodChoice('开心', '😊'),
    MoodChoice('难过', '😢'),
    MoodChoice('烦闷', '😣'),
    MoodChoice('平静', '😌'),
  ];
}

class WellbeingEntry {
  const WellbeingEntry({
    required this.date,
    this.mood,
    this.emoji,
    this.period = false,
    this.diary = '',
    this.signedIn = false,
  });

  final String date;
  final String? mood;
  final String? emoji;
  final bool period;
  final String diary;
  final bool signedIn;
  bool get hasDiary => diary.trim().isNotEmpty;

  factory WellbeingEntry.fromRow(Map<String, Object?> row) => WellbeingEntry(
    date: row['business_date'] as String,
    mood: row['mood_name'] as String?,
    emoji: row['mood_emoji'] as String?,
    period: row['period'] == 1,
    diary: (row['diary'] as String?) ?? '',
    signedIn: row['signed_in'] == 1,
  );
}

class WellbeingRepository {
  WellbeingRepository({required this.userId, int? signInUserId,
      this.fetchServerCheckIns, LocalDatabase? database})
      : signInUserId = signInUserId ?? userId,
        _database = database ?? LocalDatabase.instance;

  final int userId;
  final int signInUserId;
  final Future<List<Map<String, dynamic>>> Function(int year, int month)? fetchServerCheckIns;
  final LocalDatabase _database;

  static String dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<WellbeingEntry> getDay(DateTime day) async {
    final db = await _database.database;
    final key = dateKey(day);
    final records = await db.rawQuery('''
      SELECT e.business_date, e.mood_name, e.mood_emoji, e.period, e.diary,
             CASE WHEN s.sign_in_id IS NOT NULL THEN 1 ELSE 0 END AS signed_in
      FROM (SELECT ? AS business_date) d
      LEFT JOIN wellbeing_entries e ON e.business_date = d.business_date AND e.user_id = ?
      LEFT JOIN daily_sign_ins s ON s.business_date = d.business_date AND s.user_id = ?
    ''', [key, userId, signInUserId]);
    // 无记录时，左连接行中的 e.business_date 是 null。
    final row = Map<String, Object?>.from(records.first);
    row['business_date'] = key;
    return WellbeingEntry.fromRow(row);
  }

  Future<Map<String, WellbeingEntry>> getMonth(DateTime month) async {
    final db = await _database.database;
    final first = dateKey(DateTime(month.year, month.month, 1));
    final next = dateKey(DateTime(month.year, month.month + 1, 1));
    final result = <String, WellbeingEntry>{};
    final rows = await db.rawQuery('''
      SELECT e.business_date, e.mood_name, e.mood_emoji, e.period, e.diary,
        CASE WHEN s.sign_in_id IS NOT NULL THEN 1 ELSE 0 END AS signed_in
      FROM wellbeing_entries e
      LEFT JOIN daily_sign_ins s ON s.user_id = ? AND s.business_date = e.business_date
      WHERE e.user_id = ? AND e.business_date >= ? AND e.business_date < ?
      UNION ALL
      SELECT s.business_date, NULL AS mood_name, NULL AS mood_emoji,
        0 AS period, '' AS diary, 1 AS signed_in
      FROM daily_sign_ins s
      WHERE s.user_id = ? AND s.business_date >= ? AND s.business_date < ?
        AND NOT EXISTS (SELECT 1 FROM wellbeing_entries e
          WHERE e.user_id = ? AND e.business_date = s.business_date)
    ''', [signInUserId, userId, first, next, signInUserId, first, next, userId]);
    for (final row in rows) {
      final entry = WellbeingEntry.fromRow(row);
      result[entry.date] = entry;
    }
    // 免费模式仍可展示本机已记录的签到；联网时以服务端记录为准。
    if (fetchServerCheckIns != null) {
      try {
        final remote = await fetchServerCheckIns!(month.year, month.month);
        // 有认证响应后重建该月的签到标记，不信任旧设备上的签到缓存。
        for (final key in result.keys.toList()) {
          final old = result[key]!;
          result[key] = WellbeingEntry(date: old.date, mood: old.mood,
            emoji: old.emoji, period: old.period, diary: old.diary);
        }
        for (final checkin in remote) {
          final key = checkin['businessDate']?.toString();
          if (key == null) continue;
          final old = result[key];
          result[key] = WellbeingEntry(date: key, mood: old?.mood,
            emoji: old?.emoji, period: old?.period ?? false,
            diary: old?.diary ?? '', signedIn: true);
        }
      } catch (_) { // 离线显示最近一次本机缓存；不补发任何奖励。
      }
    }
    return result;
  }

  Future<void> _updateDay(DateTime day, Map<String, Object?> changes) async {
    final db = await _database.database;
    final key = dateKey(day);
    await db.transaction((txn) async {
      await txn.insert('wellbeing_entries', {
        'user_id': userId,
        'business_date': key,
        'sync_uuid': userId > 0 && PrivateSyncVault.instance.unlocked(-1000000 - userId)
            ? PrivateSyncVault.instance.idForDay(-1000000 - userId, key) : null,
        'update_time': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await txn.update('wellbeing_entries', {
        ...changes,
        'update_time': DateTime.now().toIso8601String(),
      }, where: 'user_id = ? AND business_date = ?', whereArgs: [userId, key]);
    });
  }

  Future<void> saveMood(DateTime day, MoodChoice mood) async {
    final choices = await getMoods();
    if (!choices.any((item) => item.emoji == mood.emoji && item.name == mood.name)) {
      throw StateError('该情绪图标或名称不存在，请重新选择');
    }
    await _updateDay(day, {'mood_name': mood.name, 'mood_emoji': mood.emoji});
  }

  Future<void> setPeriod(DateTime day, bool value) async =>
      _updateDay(day, {'period': value ? 1 : 0});

  Future<void> saveDiary(DateTime day, String content) async =>
      _updateDay(day, {'diary': content});

  Future<List<MoodChoice>> getMoods() async {
    final db = await _database.database;
    final rows = await db.query('wellbeing_moods',
      columns: ['name', 'emoji'], where: 'user_id = ?', whereArgs: [userId],
      orderBy: 'created_at ASC');
    return [...MoodChoice.defaults,
      ...rows.map((row) => MoodChoice(row['name'] as String,
          row['emoji'] as String, custom: true))];
  }

  Future<void> addCustomMood(String name, String emoji) async {
    final normalized = name.trim();
    if (normalized.isEmpty || normalized.length > 12) {
      throw ArgumentError('情绪名称长度须为 1～12 个字');
    }
    final existing = await getMoods();
    if (existing.any((item) => item.emoji == emoji)) {
      throw StateError('该表情已经被使用，请换一个图标');
    }
    if (existing.any((item) => item.name == normalized)) {
      throw StateError('情绪名称已存在，请换个名称');
    }
    final db = await _database.database;
    try {
      await db.insert('wellbeing_moods', {
        'user_id': userId,
        'name': normalized,
        'emoji': emoji,
        'created_at': DateTime.now().toIso8601String(),
      });
    } on DatabaseException {
      throw StateError('该名称或表情已使用，请重新选择');
    }
  }

  Future<List<WellbeingEntry>> getDiaries({String query = ''}) async {
    final db = await _database.database;
    final keyword = query.trim();
    final rows = await db.query('wellbeing_entries',
      where: keyword.isEmpty
          ? 'user_id = ? AND LENGTH(TRIM(diary)) > 0'
          : 'user_id = ? AND LENGTH(TRIM(diary)) > 0 AND (diary LIKE ? OR business_date LIKE ? OR mood_name LIKE ?)',
      whereArgs: keyword.isEmpty ? [userId] : [userId, '%$keyword%', '%$keyword%', '%$keyword%'],
      orderBy: 'business_date DESC');
    return rows.map((row) => WellbeingEntry.fromRow(row)).toList();
  }
}
