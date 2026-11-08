import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../data/local/local_database.dart';
import 'private_sync_vault.dart';

/// Local encrypted storage for diary, mood and period data.
///
/// userId is the public account ID (positive) or -1 for the local guest.
/// The account ID, record type and opaque UUID are metadata; actual dates and
/// all user-authored fields remain inside the AES-GCM ciphertext.
class PrivateVaultStore {
  PrivateVaultStore({required this.userId, LocalDatabase? database})
      : _database = database ?? LocalDatabase.instance;

  static const customMoodUuid = '8e8a9e42-7d25-4d1b-a6c7-2f3f5f90a2c1';

  final int userId;
  final LocalDatabase _database;
  Future<Database> get _db => _database.database;

  int get localOwnerId => userId > 0 ? -1000000 - userId : userId;

  Future<void> ensureKey() async {
    if (PrivateSyncVault.instance.unlocked(localOwnerId)) return;
    if (userId <= 0) {
      await PrivateSyncVault.instance.ensureGuestKey();
      return;
    }
    final restored = await PrivateSyncVault.instance.tryRestore(localOwnerId);
    if (!restored) {
      throw StateError('账号私密密钥尚未恢复，请重新登录账号后再访问日记');
    }
  }

  Future<Map<String, dynamic>?> readRecord(String type, String uuid) async {
    await ensureKey();
    final db = await _db;
    final rows = await db.query('private_vault_records',
      where: 'user_id=? AND record_type=? AND record_uuid=?',
      whereArgs: [userId, type, uuid], limit: 1);
    if (rows.isEmpty) return null;
    final envelope = Map<String, dynamic>.from(
        jsonDecode(rows.first['envelope_json'] as String) as Map);
    return PrivateSyncVault.instance.decryptRecord(
      localOwnerId, uuid, envelope, type: type);
  }

  Future<List<({String uuid, Map<String, dynamic> data})>> listRecords(
      String type) async {
    await ensureKey();
    final db = await _db;
    final rows = await db.query('private_vault_records',
      where: 'user_id=? AND record_type=?',
      whereArgs: [userId, type], orderBy: 'update_time DESC');
    final result = <({String uuid, Map<String, dynamic> data})>[];
    for (final row in rows) {
      final uuid = row['record_uuid'] as String;
      final envelope = Map<String, dynamic>.from(
          jsonDecode(row['envelope_json'] as String) as Map);
      final data = await PrivateSyncVault.instance.decryptRecord(
          localOwnerId, uuid, envelope, type: type);
      result.add((uuid: uuid, data: data));
    }
    return result;
  }

  Future<void> putRecord(String type, String uuid,
      Map<String, dynamic> contents) async {
    await ensureKey();
    final envelope = await PrivateSyncVault.instance.encryptRecord(
      localOwnerId, uuid, contents, type: type);
    await putEnvelope(type, uuid, envelope);
  }

  /// Stores a ciphertext envelope received from cloud sync without decrypting
  /// or re-encrypting it. The server and local SQLite both see ciphertext only.
  Future<void> putEnvelope(String type, String uuid,
      Map<String, dynamic> envelope) async {
    if (type != 'diary' && type != 'mood_custom') {
      throw const FormatException('不支持的私密记录类型');
    }
    final db = await _db;
    await db.insert('private_vault_records', {
      'user_id': userId,
      'record_type': type,
      'record_uuid': uuid,
      'envelope_json': jsonEncode(envelope),
      'update_time': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> readEnvelope(String type, String uuid) async {
    final db = await _db;
    final rows = await db.query('private_vault_records',
      columns: ['envelope_json'],
      where: 'user_id=? AND record_type=? AND record_uuid=?',
      whereArgs: [userId, type, uuid], limit: 1);
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(
        jsonDecode(rows.first['envelope_json'] as String) as Map);
  }

  Future<void> deleteRecord(String type, String uuid) async {
    final db = await _db;
    await db.delete('private_vault_records',
      where: 'user_id=? AND record_type=? AND record_uuid=?',
      whereArgs: [userId, type, uuid]);
  }

  /// One-time migration from V1 plaintext wellbeing tables into the V2 vault.
  /// It is performed only after the account AMK has been restored. The legacy
  /// plaintext rows are deleted in the same SQLite transaction after every
  /// ciphertext row has been prepared successfully.
  Future<int> migrateLegacyPlaintext() async {
    await ensureKey();
    final db = await _db;
    // Ask SQLite to overwrite deleted plaintext pages before migrating legacy
    // rows. This is best-effort on Web/IndexedDB and cannot guarantee physical
    // erasure on flash storage.
    try { await db.execute('PRAGMA secure_delete=ON'); } catch (_) {}
    final legacyEntries = await db.query('wellbeing_entries',
      where: 'user_id=?', whereArgs: [userId], orderBy: 'business_date ASC');
    final legacyMoods = await db.query('wellbeing_moods',
      where: 'user_id=?', whereArgs: [userId], orderBy: 'created_at ASC');
    if (legacyEntries.isEmpty && legacyMoods.isEmpty) return 0;

    final prepared = <({String uuid, Map<String, dynamic> envelope})>[];
    for (final row in legacyEntries) {
      final date = row['business_date'] as String;
      final uuid = PrivateSyncVault.instance.idForDay(localOwnerId, date);
      final contents = <String, dynamic>{
        'business_date': date,
        'mood_name': row['mood_name'],
        'mood_emoji': row['mood_emoji'],
        'period': row['period'],
        'diary': row['diary'] ?? '',
        'update_time': row['update_time'],
      };
      prepared.add((uuid: uuid, envelope: await PrivateSyncVault.instance.encryptRecord(
        localOwnerId, uuid, contents, type: 'diary')));
    }
    Map<String, dynamic>? moodEnvelope;
    if (legacyMoods.isNotEmpty) {
      final moods = legacyMoods.map((row) => <String, dynamic>{
        'name': row['name'], 'emoji': row['emoji'], 'created_at': row['created_at'],
      }).toList();
      moodEnvelope = await PrivateSyncVault.instance.encryptRecord(
        localOwnerId, customMoodUuid, {'moods': moods}, type: 'mood_custom');
    }

    await db.transaction((txn) async {
      await txn.update('core_sync_runtime', {'enabled': 0}, where: 'id=1');
      for (final item in prepared) {
        await txn.insert('private_vault_records', {
          'user_id': userId, 'record_type': 'diary', 'record_uuid': item.uuid,
          'envelope_json': jsonEncode(item.envelope),
          'update_time': DateTime.now().toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      if (moodEnvelope != null) {
        await txn.insert('private_vault_records', {
          'user_id': userId, 'record_type': 'mood_custom',
          'record_uuid': customMoodUuid,
          'envelope_json': jsonEncode(moodEnvelope),
          'update_time': DateTime.now().toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await txn.delete('wellbeing_entries', where: 'user_id=?', whereArgs: [userId]);
      await txn.delete('wellbeing_moods', where: 'user_id=?', whereArgs: [userId]);
      await txn.update('core_sync_runtime', {'enabled': 1}, where: 'id=1');

      // V1 private sync state is intentionally reset: V2 UUIDs and envelopes
      // use a new key version and must be uploaded as new records.
      for (final type in const ['diary', 'mood_custom']) {
        await txn.delete('core_sync_state',
          where: 'user_id=? AND record_type=?', whereArgs: [localOwnerId, type]);
        await txn.delete('core_sync_outbox',
          where: 'user_id=? AND record_type=?', whereArgs: [localOwnerId, type]);
        await txn.delete('core_sync_conflict',
          where: 'user_id=? AND record_type=?', whereArgs: [localOwnerId, type]);
        await txn.delete('core_sync_deferred',
          where: 'user_id=? AND record_type=?', whereArgs: [localOwnerId, type]);
        await txn.delete('core_sync_dirty',
          where: 'user_id=? AND record_type=?', whereArgs: [localOwnerId, type]);
      }
      for (final item in prepared) {
        await txn.insert('core_sync_dirty', {
          'user_id': localOwnerId, 'record_type': 'diary',
          'record_uuid': item.uuid, 'local_id': null, 'deleted': 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      if (moodEnvelope != null) {
        await txn.insert('core_sync_dirty', {
          'user_id': localOwnerId, 'record_type': 'mood_custom',
          'record_uuid': customMoodUuid, 'local_id': null, 'deleted': 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    // Compact the old plaintext pages after the transaction has committed.
    try {
      await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      await db.execute('VACUUM');
    } catch (_) {
      // Some browser-backed SQLite implementations do not support VACUUM.
    }
    return prepared.length + (moodEnvelope == null ? 0 : 1);
  }
}
