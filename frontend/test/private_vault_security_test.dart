import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plan_blind_box/data/local/local_database.dart';
import 'package:plan_blind_box/services/account_master_key_envelope.dart';
import 'package:plan_blind_box/services/core_sync_store.dart';
import 'package:plan_blind_box/services/private_sync_vault.dart';
import 'package:plan_blind_box/services/private_vault_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const int _accountId = 5;
const int _vaultOwnerId = -1000005;
const String _diaryUuid = '123e4567-e89b-42d3-a456-426614174000';
const String _secondDiaryUuid = '123e4567-e89b-42d3-a456-426614174001';

final List<int> _amk = List<int>.generate(32, (index) => index + 1);
final String _exportKey = base64UrlEncode(
  List<int>.generate(32, (index) => 200 - index),
);

void main() {
  final vault = PrivateSyncVault.instance;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    vault.lock();
    await vault.activate(_vaultOwnerId, _amk, persist: false);
  });

  tearDown(() {
    vault.lock();
  });

  group('AccountMasterKeyEnvelope', () {
    test('wrap and unwrap restores the same 256-bit AMK without storing it in clear', () async {
      final envelope = await AccountMasterKeyEnvelope.wrap(
        exportKey: _exportKey,
        masterKey: _amk,
        accountIdentifier: 'User@Example.com',
      );

      expect(envelope.keys.toSet(), {
        'version', 'kdf', 'alg', 'salt', 'nonce', 'ciphertext', 'tag',
      });
      expect(envelope['version'], 2);
      expect(envelope['kdf'], 'hkdf-sha256');
      expect(envelope['alg'], 'aes-256-gcm');
      expect(jsonEncode(envelope), isNot(contains(base64Encode(_amk))));

      final restored = await AccountMasterKeyEnvelope.unwrap(
        exportKey: _exportKey,
        envelope: envelope,
        accountIdentifier: 'user@example.com',
      );
      expect(restored, _amk);
    });

    test('wrong export key and wrong account identifier cannot unwrap the AMK', () async {
      final envelope = await AccountMasterKeyEnvelope.wrap(
        exportKey: _exportKey,
        masterKey: _amk,
        accountIdentifier: 'user@example.com',
      );

      await expectLater(
        AccountMasterKeyEnvelope.unwrap(
          exportKey: base64UrlEncode(List<int>.filled(32, 7)),
          envelope: envelope,
          accountIdentifier: 'user@example.com',
        ),
        throwsA(anything),
      );
      await expectLater(
        AccountMasterKeyEnvelope.unwrap(
          exportKey: _exportKey,
          envelope: envelope,
          accountIdentifier: 'another@example.com',
        ),
        throwsA(anything),
      );
    });

    test('tampered ciphertext and unsupported envelope fields are rejected', () async {
      final envelope = await AccountMasterKeyEnvelope.wrap(
        exportKey: _exportKey,
        masterKey: _amk,
        accountIdentifier: 'user@example.com',
      );
      final tampered = Map<String, dynamic>.from(envelope);
      final ciphertext = base64Decode(tampered['ciphertext'] as String);
      ciphertext[0] ^= 1;
      tampered['ciphertext'] = base64Encode(ciphertext);

      await expectLater(
        AccountMasterKeyEnvelope.unwrap(
          exportKey: _exportKey,
          envelope: tampered,
          accountIdentifier: 'user@example.com',
        ),
        throwsA(anything),
      );
      await expectLater(
        AccountMasterKeyEnvelope.unwrap(
          exportKey: _exportKey,
          envelope: {...envelope, 'unexpected': true},
          accountIdentifier: 'user@example.com',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('each wrapping operation uses fresh salt and nonce', () async {
      final first = await AccountMasterKeyEnvelope.wrap(
        exportKey: _exportKey,
        masterKey: _amk,
        accountIdentifier: 'user@example.com',
      );
      final second = await AccountMasterKeyEnvelope.wrap(
        exportKey: _exportKey,
        masterKey: _amk,
        accountIdentifier: 'user@example.com',
      );

      expect(first['salt'], isNot(second['salt']));
      expect(first['nonce'], isNot(second['nonce']));
    });
  });

  group('PrivateSyncVault', () {
    test('diary and custom mood roundtrip while plaintext remains outside the envelope', () async {
      const diary = {
        'business_date': '2026-11-06',
        'diary': '这是一段只应保存在客户端可解密的私密日记',
        'mood_name': '平静',
        'mood_emoji': '🌙',
        'period': 1,
      };
      final diaryEnvelope = await vault.encryptRecord(
        _vaultOwnerId, _diaryUuid, diary, type: 'diary',
      );
      final encodedDiaryEnvelope = jsonEncode(diaryEnvelope);
      expect(encodedDiaryEnvelope, isNot(contains('只应保存在')));
      expect(encodedDiaryEnvelope, isNot(contains('2026-11-06')));
      expect(encodedDiaryEnvelope, isNot(contains('business_date')));
      expect(diaryEnvelope.keys.toSet(), {
        'alg', 'keyVersion', 'nonce', 'ciphertext', 'tag',
      });
      expect(
        await vault.decryptRecord(_vaultOwnerId, _diaryUuid, diaryEnvelope, type: 'diary'),
        diary,
      );

      const moods = {
        'moods': [
          {'name': '有点疲惫', 'emoji': '🥱'},
          {'name': '开心', 'emoji': '🌻'},
        ],
      };
      final moodEnvelope = await vault.encryptRecord(
        _vaultOwnerId, PrivateVaultStore.customMoodUuid, moods, type: 'mood_custom',
      );
      expect(jsonEncode(moodEnvelope), isNot(contains('有点疲惫')));
      expect(
        await vault.decryptRecord(
          _vaultOwnerId,
          PrivateVaultStore.customMoodUuid,
          moodEnvelope,
          type: 'mood_custom',
        ),
        moods,
      );
    });

    test('same content gets a fresh AES-GCM nonce and ciphertext', () async {
      const content = {'diary': '同一段内容'};
      final first = await vault.encryptRecord(_vaultOwnerId, _diaryUuid, content);
      final second = await vault.encryptRecord(_vaultOwnerId, _diaryUuid, content);

      expect(first['nonce'], isNot(second['nonce']));
      expect(first['ciphertext'], isNot(second['ciphertext']));
    });

    test('wrong UUID, wrong account scope, wrong key and wrong record type are rejected', () async {
      final envelope = await vault.encryptRecord(
        _vaultOwnerId, _diaryUuid, const {'diary': 'account-bound'}, type: 'diary',
      );

      await expectLater(
        vault.decryptRecord(_vaultOwnerId, _secondDiaryUuid, envelope, type: 'diary'),
        throwsA(anything),
      );
      await expectLater(
        vault.decryptRecord(_vaultOwnerId, _diaryUuid, envelope, type: 'mood_custom'),
        throwsA(isA<FormatException>()),
      );

      vault.lock();
      await vault.activate(-1000006, _amk, persist: false);
      await expectLater(
        vault.decryptRecord(-1000006, _diaryUuid, envelope, type: 'diary'),
        throwsA(anything),
      );

      vault.lock();
      await vault.activate(_vaultOwnerId, List<int>.filled(32, 99), persist: false);
      await expectLater(
        vault.decryptRecord(_vaultOwnerId, _diaryUuid, envelope, type: 'diary'),
        throwsA(anything),
      );
    });

    test('ciphertext tampering and malformed envelopes are rejected', () async {
      final envelope = await vault.encryptRecord(
        _vaultOwnerId, _diaryUuid, const {'diary': 'tamper target'},
      );
      final tampered = Map<String, dynamic>.from(envelope);
      final ciphertext = base64Decode(tampered['ciphertext'] as String);
      ciphertext[0] ^= 1;
      tampered['ciphertext'] = base64Encode(ciphertext);

      await expectLater(
        vault.decryptRecord(_vaultOwnerId, _diaryUuid, tampered),
        throwsA(anything),
      );
      await expectLater(
        vault.decryptRecord(_vaultOwnerId, _diaryUuid, {...envelope, 'extra': 'field'}),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        vault.decryptRecord(_vaultOwnerId, _diaryUuid, {...envelope, 'nonce': base64Encode([1, 2])}),
        throwsA(isA<FormatException>()),
      );
    });

    test('day identifier is deterministic but does not contain the date', () async {
      const day = '2026-11-06';
      final first = vault.idForDay(_vaultOwnerId, day);
      final second = vault.idForDay(_vaultOwnerId, day);
      final nextDay = vault.idForDay(_vaultOwnerId, '2026-11-07');

      expect(first, second);
      expect(first, isNot(contains(day)));
      expect(first, isNot(nextDay));
      expect(first, matches(RegExp(r'^[0-9a-f-]{36}$')));
    });

    test('locked vault and unsupported private record types cannot encrypt', () async {
      vault.lock();
      await expectLater(
        vault.encryptRecord(_vaultOwnerId, _diaryUuid, const {'diary': 'x'}),
        throwsA(isA<StateError>()),
      );
      await vault.activate(_vaultOwnerId, _amk, persist: false);
      await expectLater(
        vault.encryptRecord(_vaultOwnerId, _diaryUuid, const {'title': 'not private'}, type: 'task'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('PrivateVaultStore and CoreSyncStore', () {
    test('SQLite stores only the encrypted envelope and decrypts on read', () async {
      final database = LocalDatabase.forTesting(factory: databaseFactoryFfi);
      await database.initialize();
      addTearDown(database.close);

      final privateStore = PrivateVaultStore(userId: _accountId, database: database);
      const content = {
        'business_date': '2026-11-06',
        'diary': 'SQLite 中不应该出现这段日记明文',
        'period': 0,
      };
      await privateStore.putRecord('diary', _diaryUuid, content);

      final db = await database.database;
      final rows = await db.query(
        'private_vault_records',
        columns: ['user_id', 'record_type', 'record_uuid', 'envelope_json'],
        where: 'user_id=? AND record_uuid=?',
        whereArgs: [_accountId, _diaryUuid],
      );
      expect(rows, hasLength(1));
      final storedEnvelope = rows.single['envelope_json'] as String;
      expect(storedEnvelope, isNot(contains('SQLite 中不应该出现')));
      expect(storedEnvelope, isNot(contains('2026-11-06')));
      expect(storedEnvelope, contains('aes-256-gcm'));
      expect(await privateStore.readRecord('diary', _diaryUuid), content);
    });

    test('legacy plaintext wellbeing rows migrate into encrypted vault records', () async {
      final database = LocalDatabase.forTesting(factory: databaseFactoryFfi);
      await database.initialize();
      addTearDown(database.close);

      final db = await database.database;
      await db.insert('wellbeing_entries', {
        'user_id': _accountId,
        'business_date': '2026-11-05',
        'mood_name': '旧版平静心情',
        'mood_emoji': '🌙',
        'period': 1,
        'diary': '旧版明文日记迁移测试内容',
        'update_time': '2026-11-05T21:00:00',
      });
      await db.insert('wellbeing_moods', {
        'user_id': _accountId,
        'name': '旧版自定义心情',
        'emoji': '🌧️',
        'created_at': '2026-11-05T20:00:00',
      });

      final privateStore = PrivateVaultStore(userId: _accountId, database: database);
      final migrated = await privateStore.migrateLegacyPlaintext();

      expect(migrated, 2);
      expect(await db.query('wellbeing_entries', where: 'user_id=?', whereArgs: [_accountId]), isEmpty);
      expect(await db.query('wellbeing_moods', where: 'user_id=?', whereArgs: [_accountId]), isEmpty);

      final diaryUuid = vault.idForDay(_vaultOwnerId, '2026-11-05');
      final diary = await privateStore.readRecord('diary', diaryUuid);
      expect(diary?['diary'], '旧版明文日记迁移测试内容');
      expect(diary?['business_date'], '2026-11-05');

      final moods = await privateStore.readRecord(
        'mood_custom', PrivateVaultStore.customMoodUuid,
      );
      expect(moods?['moods'], [
        {'name': '旧版自定义心情', 'emoji': '🌧️', 'created_at': '2026-11-05T20:00:00'},
      ]);

      final encryptedRows = await db.query('private_vault_records', where: 'user_id=?', whereArgs: [_accountId]);
      expect(encryptedRows, hasLength(2));
      final storedText = encryptedRows.map((row) => row['envelope_json']).join('|');
      expect(storedText, isNot(contains('旧版明文日记迁移测试内容')));
      expect(storedText, isNot(contains('旧版自定义心情')));

      final dirtyRows = await db.query(
        'core_sync_dirty', where: 'user_id=?', whereArgs: [_vaultOwnerId],
      );
      expect(dirtyRows, hasLength(2));
    });

    test('legacy migration failure leaves the original plaintext row intact', () async {
      final database = LocalDatabase.forTesting(factory: databaseFactoryFfi);
      await database.initialize();
      addTearDown(database.close);

      final db = await database.database;
      await db.insert('wellbeing_entries', {
        'user_id': _accountId,
        'business_date': 'not-a-date',
        'mood_name': '迁移失败保护',
        'mood_emoji': '🧪',
        'period': 0,
        'diary': '原始数据必须保留',
        'update_time': '2026-11-05T21:00:00',
      });

      final privateStore = PrivateVaultStore(userId: _accountId, database: database);
      await expectLater(
        privateStore.migrateLegacyPlaintext(),
        throwsA(isA<FormatException>()),
      );

      expect(
        await db.query('wellbeing_entries', where: 'user_id=?', whereArgs: [_accountId]),
        hasLength(1),
      );
      expect(
        await db.query('private_vault_records', where: 'user_id=?', whereArgs: [_accountId]),
        isEmpty,
      );
    });

    test('private sync outbox contains ciphertext, not diary plaintext', () async {
      final database = LocalDatabase.forTesting(factory: databaseFactoryFfi);
      await database.initialize();
      addTearDown(database.close);

      final privateStore = PrivateVaultStore(userId: _accountId, database: database);
      const content = {
        'business_date': '2026-11-06',
        'diary': '同步队列也不能包含日记明文',
        'period': 1,
      };
      await privateStore.putRecord('diary', _diaryUuid, content);

      final syncStore = CoreSyncStore(_vaultOwnerId, database: database);
      await syncStore.bootstrap();
      final mutation = await syncStore.nextMutation();

      expect(mutation, isNotNull);
      expect(mutation!.type, 'diary');
      expect(mutation.uuid, _diaryUuid);
      expect(mutation.payloadJson, isNot(contains('同步队列也不能')));
      expect(mutation.payloadJson, isNot(contains('2026-11-06')));
      final envelope = jsonDecode(mutation.payloadJson!) as Map<String, dynamic>;
      expect(envelope.keys.toSet(), {'alg', 'keyVersion', 'nonce', 'ciphertext', 'tag'});

      final db = await database.database;
      final outbox = await db.query('core_sync_outbox', where: 'user_id=?', whereArgs: [_vaultOwnerId]);
      expect(outbox, hasLength(1));
      expect(outbox.single['payload'], isNot(contains('同步队列也不能')));
    });

    test('task titles, task notes and habit content remain ordinary sync payloads', () async {
      final database = LocalDatabase.forTesting(factory: databaseFactoryFfi);
      await database.initialize();
      addTearDown(database.close);

      final db = await database.database;
      await db.insert('tasks', {
        'user_id': _vaultOwnerId,
        'title': '普通任务标题',
        'note': '普通任务备注',
        'create_time': '2026-11-06T10:00:00',
        'update_time': '2026-11-06T10:00:00',
      });
      await db.insert('habits', {
        'user_id': _vaultOwnerId,
        'name': '普通习惯名称',
        'note': '普通习惯备注',
        'start_date': '2026-11-06',
        'repeat_rule': 'DAILY',
        'create_time': '2026-11-06T10:00:00',
        'update_time': '2026-11-06T10:00:00',
      });

      final syncStore = CoreSyncStore(_vaultOwnerId, database: database);
      await syncStore.bootstrap();
      final taskMutation = await syncStore.nextMutation();
      expect(taskMutation, isNotNull);
      expect(taskMutation!.type, 'task');
      expect(taskMutation.payloadJson, contains('普通任务标题'));
      expect(taskMutation.payloadJson, contains('普通任务备注'));
      await syncStore.acknowledge(taskMutation, 1);

      final habitMutation = await syncStore.nextMutation();
      expect(habitMutation, isNotNull);
      expect(habitMutation!.type, 'habit');
      expect(habitMutation.payloadJson, contains('普通习惯名称'));
      expect(habitMutation.payloadJson, contains('普通习惯备注'));
    });
  });
}
