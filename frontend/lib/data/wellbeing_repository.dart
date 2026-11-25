import '../services/private_sync_vault.dart';
import '../services/private_vault_store.dart';
import 'local/local_database.dart';

/// 情绪、经期和日记只通过 V2 PrivateVaultStore 保存；普通 SQLite 表不再
/// 保存这些字段的明文。账号登录后自动恢复 AMK，游客使用设备专属密钥。
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

  factory WellbeingEntry.fromPrivate(
    Map<String, dynamic> data, {
    bool signedIn = false,
  }) => WellbeingEntry(
    date: data['business_date'] as String,
    mood: data['mood_name'] as String?,
    emoji: data['mood_emoji'] as String?,
    period: data['period'] == 1 || data['period'] == true,
    diary: (data['diary'] as String?) ?? '',
    signedIn: signedIn,
  );
}

class WellbeingRepository {
  WellbeingRepository({
    required this.userId,
    int? signInUserId,
    this.fetchServerCheckIns,
    LocalDatabase? database,
  }) : signInUserId = signInUserId ?? userId,
       _database = database ?? LocalDatabase.instance,
       _vault = PrivateVaultStore(
         userId: userId,
         database: database ?? LocalDatabase.instance,
       );

  /// Public account ID; -1 denotes guest/local-only data.
  final int userId;
  final int signInUserId;
  final Future<List<Map<String, dynamic>>> Function(int year, int month)?
  fetchServerCheckIns;
  final LocalDatabase _database;
  final PrivateVaultStore _vault;

  static String dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> _prepare() => _vault.migrateLegacyPlaintext();

  Future<bool> _signedInOn(String day) async {
    final db = await _database.database;
    final rows = await db.query(
      'daily_sign_ins',
      columns: ['sign_in_id'],
      where: 'user_id=? AND business_date=?',
      whereArgs: [signInUserId, day],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<WellbeingEntry> getDay(DateTime day) async {
    await _prepare();
    final key = dateKey(day);
    final uuid = PrivateSyncVault.instance.idForDay(_vault.localOwnerId, key);
    final data = await _vault.readRecord('diary', uuid);
    return data == null
        ? WellbeingEntry(date: key, signedIn: await _signedInOn(key))
        : WellbeingEntry.fromPrivate(data, signedIn: await _signedInOn(key));
  }

  Future<Map<String, WellbeingEntry>> getMonth(DateTime month) async {
    await _prepare();
    final first = dateKey(DateTime(month.year, month.month, 1));
    final next = dateKey(DateTime(month.year, month.month + 1, 1));
    final result = <String, WellbeingEntry>{};
    for (final item in await _vault.listRecords('diary')) {
      final data = item.data;
      final date = data['business_date'];
      if (date is! String ||
          date.compareTo(first) < 0 ||
          date.compareTo(next) >= 0) {
        continue;
      }
      result[date] = WellbeingEntry.fromPrivate(data);
    }

    final db = await _database.database;
    final signIns = await db.query(
      'daily_sign_ins',
      columns: ['business_date'],
      where: 'user_id=? AND business_date>=? AND business_date<?',
      whereArgs: [signInUserId, first, next],
    );
    for (final row in signIns) {
      final date = row['business_date'] as String;
      final old = result[date];
      result[date] = WellbeingEntry(
        date: date,
        mood: old?.mood,
        emoji: old?.emoji,
        period: old?.period ?? false,
        diary: old?.diary ?? '',
        signedIn: true,
      );
    }

    if (fetchServerCheckIns != null) {
      try {
        final remote = await fetchServerCheckIns!(month.year, month.month);
        for (final checkin in remote) {
          final key = checkin['businessDate']?.toString();
          if (key == null) continue;
          final old = result[key];
          result[key] = WellbeingEntry(
            date: key,
            mood: old?.mood,
            emoji: old?.emoji,
            period: old?.period ?? false,
            diary: old?.diary ?? '',
            signedIn: true,
          );
        }
      } catch (_) {
        // 离线时保留最近一次本机签到缓存，不补发奖励。
      }
    }
    return result;
  }

  Future<void> _updateDay(DateTime day, Map<String, Object?> changes) async {
    await _prepare();
    final key = dateKey(day);
    final uuid = PrivateSyncVault.instance.idForDay(_vault.localOwnerId, key);
    final old =
        await _vault.readRecord('diary', uuid) ??
        <String, dynamic>{
          'business_date': key,
          'mood_name': null,
          'mood_emoji': null,
          'period': 0,
          'diary': '',
        };
    old.addAll(changes);
    old['business_date'] = key;
    old['update_time'] = DateTime.now().toUtc().toIso8601String();
    await _vault.putRecord('diary', uuid, old);
  }

  Future<void> saveMood(DateTime day, MoodChoice mood) async {
    final choices = await getMoods();
    if (!choices.any(
      (item) => item.emoji == mood.emoji && item.name == mood.name,
    )) {
      throw StateError('该情绪图标或名称不存在，请重新选择');
    }
    await _updateDay(day, {'mood_name': mood.name, 'mood_emoji': mood.emoji});
  }

  Future<void> setPeriod(DateTime day, bool value) async =>
      _updateDay(day, {'period': value ? 1 : 0});

  Future<void> saveDiary(DateTime day, String content) async =>
      _updateDay(day, {'diary': content});

  Future<List<MoodChoice>> getMoods() async {
    await _prepare();
    final data = await _vault.readRecord(
      'mood_custom',
      PrivateVaultStore.customMoodUuid,
    );
    final raw = data?['moods'];
    if (raw is! List) return MoodChoice.defaults;
    return [
      ...MoodChoice.defaults,
      ...raw.whereType<Map>().map(
        (row) => MoodChoice(
          row['name'] as String,
          row['emoji'] as String,
          custom: true,
        ),
      ),
    ];
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
    final current =
        await _vault.readRecord(
          'mood_custom',
          PrivateVaultStore.customMoodUuid,
        ) ??
        {'moods': <dynamic>[]};
    final moods = List<Map<String, dynamic>>.from(
      (current['moods'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
    moods.add({
      'name': normalized,
      'emoji': emoji,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
    await _vault.putRecord('mood_custom', PrivateVaultStore.customMoodUuid, {
      'moods': moods,
    });
  }

  Future<List<WellbeingEntry>> getDiaries({String query = ''}) async {
    await _prepare();
    final keyword = query.trim().toLowerCase();
    final rows = <WellbeingEntry>[];
    for (final item in await _vault.listRecords('diary')) {
      final entry = WellbeingEntry.fromPrivate(item.data);
      if (!entry.hasDiary) continue;
      if (keyword.isNotEmpty &&
          !entry.diary.toLowerCase().contains(keyword) &&
          !entry.date.contains(keyword) &&
          !(entry.mood ?? '').toLowerCase().contains(keyword)) {
        continue;
      }
      rows.add(entry);
    }
    rows.sort((a, b) => b.date.compareTo(a.date));
    return rows;
  }
}
