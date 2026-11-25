import 'dart:convert';
import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../../data/local/local_database.dart';

/// Account-scoped persistence for MOD installation state, grants, audit and
/// namespaced local data. This store never exposes the host database handle.
class ModPlatformStore {
  ModPlatformStore({
    required LocalDatabase database,
    required this.ownerId,
    DateTime Function()? clock,
    Random? random,
  }) : _database = database,
       _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  final LocalDatabase _database;
  final int ownerId;
  final DateTime Function() _clock;
  final Random _random;

  Future<Database> get _db => _database.database;

  static const profiles = <String>{
    'standalone_networked',
    'standalone_offline',
    'host_integrated_offline',
  };
  static const _hostBusinessCapabilities = <String>{
    'tasks.create', // Transitional capability used by the existing template MOD.
    'host.data.tasks.read',
    'host.data.habits.read',
    'host.data.checkins.read',
    'host.data.time_records.read',
    'host.data.diary.read',
    'host.data.mood.read',
    'host.tasks.create',
    'host.tasks.update_limited',
    'host.habits.create',
    'host.habits.check_in',
  };
  static const _egressCapabilities = <String>{
    'network.fetch',
    'mods.message.send',
    'mods.message.subscribe',
    'host.external_link.open',
    'host.ui.notification',
    'host.ui.home_widget',
  };

  String _now() => _clock().toUtc().toIso8601String();

  String _newUuidV4() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<List<Map<String, dynamic>>> listInstallations() async {
    final db = await _db;
    final rows = await db.query(
      'mod_installations',
      where: 'owner_id=? AND status IN (?,?)',
      whereArgs: [ownerId, 'installed', 'requires_reauthorization'],
      orderBy: 'updated_at DESC, mod_id ASC',
    );
    final result = <Map<String, dynamic>>[];
    for (final row in rows) {
      final decoded = jsonDecode(row['manifest_json']! as String);
      if (decoded is! Map) {
        throw const FormatException('本地 MOD Manifest 数据损坏');
      }
      final installationId = row['installation_id']! as String;
      final grants = await db.query(
        'mod_permission_grants',
        columns: ['capability'],
        where: 'installation_id=? AND revoked_at IS NULL',
        whereArgs: [installationId],
        orderBy: 'capability ASC',
      );
      result.add({
        ...Map<String, dynamic>.from(decoded),
        'manifestJson': row['manifest_json'],
        'installationId': installationId,
        'installedModId': row['mod_id'],
        'installedVersion': row['version'],
        'publisherId': row['publisher_id'],
        'packageSha256': row['package_sha256'],
        'effectiveProfile': row['effective_profile'],
        'storageNamespace': row['storage_namespace'],
        'status': row['status'],
        'enabled': row['enabled'] == 1,
        'grantedPermissions': grants
            .map((grant) => grant['capability'] as String)
            .toList(growable: false),
        'installedAt': row['installed_at'],
        'updatedAt': row['updated_at'],
      });
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> auditEvents({int limit = 100}) async {
    final db = await _db;
    final rows = await db.query(
      'mod_audit_events',
      where: 'owner_id=?',
      whereArgs: [ownerId],
      orderBy: 'event_id DESC',
      limit: limit.clamp(1, 500).toInt(),
    );
    return rows.map((row) => <String, dynamic>{
      'at': row['created_at'],
      'action': row['action'],
      'id': row['mod_id'],
      if (row['capability'] != null) 'capability': row['capability'],
      'result': row['result'],
    }).toList(growable: false);
  }

  Future<void> _audit(
    DatabaseExecutor executor, {
    required String modId,
    String? installationId,
    required String action,
    String? capability,
    String result = 'success',
  }) async {
    await executor.insert('mod_audit_events', {
      'owner_id': ownerId,
      'installation_id': installationId,
      'mod_id': modId,
      'action': action,
      'capability': capability,
      'result': result,
      'created_at': _now(),
      // Never place task, diary, mood, token, key or other host data here.
      'detail_json': '{}',
    });
    await executor.rawDelete(
      '''DELETE FROM mod_audit_events
         WHERE owner_id=? AND event_id NOT IN (
           SELECT event_id FROM mod_audit_events
           WHERE owner_id=? ORDER BY event_id DESC LIMIT 500
         )''',
      [ownerId, ownerId],
    );
  }

  /// Installs or upgrades one MOD. Grants are replaced by the explicitly
  /// confirmed set; they are never inherited implicitly.
  Future<void> installOrUpgrade({
    required String modId,
    required String publisherId,
    required String version,
    required String manifestJson,
    required String effectiveProfile,
    required Set<String> grantedPermissions,
    String? packageSha256,
    int storageQuotaBytes = 0,
    String policyVersion = '1',
    bool enabledAfterInstall = true,
  }) async {
    if (!profiles.contains(effectiveProfile)) {
      throw ArgumentError.value(effectiveProfile, 'effectiveProfile');
    }
    if (storageQuotaBytes < 0 || storageQuotaBytes > 2 * 1024 * 1024 * 1024) {
      throw ArgumentError.value(storageQuotaBytes, 'storageQuotaBytes');
    }
    final hasHostBusiness = grantedPermissions.any(_hostBusinessCapabilities.contains);
    final hasEgress = grantedPermissions.any(_egressCapabilities.contains);
    if ((hasHostBusiness && effectiveProfile != 'host_integrated_offline') ||
        (hasEgress && effectiveProfile != 'standalone_networked') ||
        (effectiveProfile == 'host_integrated_offline' && hasEgress) ||
        (effectiveProfile == 'standalone_networked' && hasHostBusiness) ||
        (effectiveProfile == 'standalone_offline' &&
            (hasHostBusiness || hasEgress))) {
      throw const FormatException('MOD 权限与平台计算的安全 Profile 不匹配');
    }
    final decoded = jsonDecode(manifestJson);
    if (decoded is! Map || decoded['id'] != modId || decoded['version'] != version) {
      throw const FormatException('安装记录与 Manifest 身份不匹配');
    }

    final db = await _db;
    await db.transaction((txn) async {
      final existingRows = await txn.query(
        'mod_installations',
        where: 'owner_id=? AND mod_id=?',
        whereArgs: [ownerId, modId],
        limit: 1,
      );
      final existing = existingRows.isEmpty ? null : existingRows.first;
      final sameTrustDomain = existing != null &&
          existing['publisher_id'] == publisherId &&
          existing['effective_profile'] == effectiveProfile;

      String installationId;
      String storageNamespace;
      String installedAt;

      if (sameTrustDomain) {
        final current = existing;
        installationId = current['installation_id']! as String;
        storageNamespace = current['storage_namespace']! as String;
        installedAt = current['installed_at']! as String;
        await txn.update(
          'mod_storage_metadata',
          {
            'quota_bytes': storageQuotaBytes,
            'retained': 0,
            'updated_at': _now(),
          },
          where: 'owner_id=? AND storage_namespace=?',
          whereArgs: [ownerId, storageNamespace],
        );
        await txn.delete(
          'mod_permission_grants',
          where: 'installation_id=?',
          whereArgs: [installationId],
        );
      } else {
        if (existing != null) {
          final oldNamespace = existing['storage_namespace']! as String;
          await txn.update(
            'mod_storage_metadata',
            {'retained': 1, 'updated_at': _now()},
            where: 'owner_id=? AND storage_namespace=?',
            whereArgs: [ownerId, oldNamespace],
          );
          await txn.delete(
            'mod_installations',
            where: 'installation_id=?',
            whereArgs: [existing['installation_id']],
          );
        }

        final retainedRows = await txn.query(
          'mod_storage_metadata',
          where: '''owner_id=? AND mod_id=? AND publisher_id=?
                    AND effective_profile=? AND retained=1''',
          whereArgs: [ownerId, modId, publisherId, effectiveProfile],
          orderBy: 'updated_at DESC',
          limit: 1,
        );
        if (retainedRows.isNotEmpty) {
          storageNamespace = retainedRows.first['storage_namespace']! as String;
          await txn.update(
            'mod_storage_metadata',
            {
              'quota_bytes': storageQuotaBytes,
              'retained': 0,
              'updated_at': _now(),
            },
            where: 'storage_namespace=? AND owner_id=?',
            whereArgs: [storageNamespace, ownerId],
          );
        } else {
          storageNamespace = _newUuidV4();
          await txn.insert('mod_storage_metadata', {
            'storage_namespace': storageNamespace,
            'owner_id': ownerId,
            'mod_id': modId,
            'publisher_id': publisherId,
            'effective_profile': effectiveProfile,
            'quota_bytes': storageQuotaBytes,
            'used_bytes': 0,
            'data_format_version': 1,
            'retained': 0,
            'created_at': _now(),
            'updated_at': _now(),
          });
        }
        installationId = _newUuidV4();
        installedAt = _now();
      }

      final values = <String, Object?>{
        'installation_id': installationId,
        'owner_id': ownerId,
        'mod_id': modId,
        'publisher_id': publisherId,
        'version': version,
        'manifest_json': manifestJson,
        'package_sha256': packageSha256,
        'effective_profile': effectiveProfile,
        'status': 'installed',
        'enabled': enabledAfterInstall ? 1 : 0,
        'storage_namespace': storageNamespace,
        'installed_at': installedAt,
        'updated_at': _now(),
      };
      if (sameTrustDomain) {
        values.remove('installation_id');
        values.remove('installed_at');
        await txn.update(
          'mod_installations',
          values,
          where: 'installation_id=? AND owner_id=?',
          whereArgs: [installationId, ownerId],
        );
      } else {
        await txn.insert('mod_installations', values);
      }

      for (final capability in grantedPermissions.toList()..sort()) {
        await txn.insert('mod_permission_grants', {
          'installation_id': installationId,
          'capability': capability,
          'scope_json': '{}',
          'granted_at': _now(),
          'revoked_at': null,
          'policy_version': policyVersion,
        });
      }

      await _audit(
        txn,
        modId: modId,
        installationId: installationId,
        action: existing == null ? 'install' : 'upgrade',
      );
    });
  }

  /// Records only capability metadata. Request payloads and host data are never logged.
  Future<void> recordCapabilityInvocation({
    required String modId,
    required String installationId,
    required String capability,
    required String result,
  }) async {
    if (!const {'success', 'denied', 'error'}.contains(result)) {
      throw ArgumentError.value(result, 'result');
    }
    final db = await _db;
    await db.transaction((txn) async {
      await _audit(
        txn,
        modId: modId,
        installationId: installationId,
        action: 'capability_invoke',
        capability: capability,
        result: result,
      );
    });
  }

  Future<void> setEnabled(String modId, bool enabled) async {
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'mod_installations',
        where: 'owner_id=? AND mod_id=? AND status=?',
        whereArgs: [ownerId, modId, 'installed'],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('MOD 未安装或需要重新授权');
      final row = rows.first;
      await txn.update(
        'mod_installations',
        {'enabled': enabled ? 1 : 0, 'updated_at': _now()},
        where: 'installation_id=?',
        whereArgs: [row['installation_id']],
      );
      await _audit(
        txn,
        modId: modId,
        installationId: row['installation_id'] as String,
        action: enabled ? 'enable' : 'disable',
      );
    });
  }

  /// Records an explicit user authorization for one declared capability.
  /// This does not imply platform/admin approval; the Runtime Broker checks
  /// both authorities independently on every Host API call.
  Future<void> grantPermission(String modId, String capability) async {
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'mod_installations',
        where: 'owner_id=? AND mod_id=? AND status=?',
        whereArgs: [ownerId, modId, 'installed'],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('MOD 未安装');
      final installation = rows.first;
      final installationId = installation['installation_id']! as String;
      final manifest = jsonDecode(installation['manifest_json']! as String);
      if (manifest is! Map) {
        throw const FormatException('MOD Manifest 数据损坏');
      }

      final permissions = manifest['permissions'];
      bool declared = false;
      if (permissions is List) {
        for (final item in permissions) {
          if (item == capability) {
            declared = true;
            break;
          }
          if (item is Map && item['capability'] == capability) {
            declared = true;
            break;
          }
        }
      }
      if (!declared) {
        throw StateError('MOD 未声明此 capability');
      }

      final existing = await txn.query(
        'mod_permission_grants',
        where: 'installation_id=? AND capability=? AND revoked_at IS NULL',
        whereArgs: [installationId, capability],
        limit: 1,
      );
      if (existing.isNotEmpty) return;

      await txn.insert('mod_permission_grants', {
        'installation_id': installationId,
        'capability': capability,
        'scope_json': '{}',
        'granted_at': _now(),
        'revoked_at': null,
        'policy_version': '1',
      });
      await _audit(
        txn,
        modId: modId,
        installationId: installationId,
        action: 'permission_grant',
        capability: capability,
      );
    });
  }

  Future<void> revokePermission(String modId, String capability) async {
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'mod_installations',
        where: 'owner_id=? AND mod_id=? AND status=?',
        whereArgs: [ownerId, modId, 'installed'],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('MOD 未安装');
      final installationId = rows.first['installation_id']! as String;
      final now = _now();
      final changed = await txn.update(
        'mod_permission_grants',
        {'revoked_at': now},
        where: 'installation_id=? AND capability=? AND revoked_at IS NULL',
        whereArgs: [installationId, capability],
      );
      if (changed == 0) return;
      // Revoking a Host capability immediately disables the installation as a
      // fail-closed response; the Registry also terminates the active session.
      await txn.update(
        'mod_installations',
        {'enabled': 0, 'updated_at': now},
        where: 'installation_id=?',
        whereArgs: [installationId],
      );
      await _audit(
        txn,
        modId: modId,
        installationId: installationId,
        action: 'permission_revoke',
        capability: capability,
      );
    });
  }

  /// Uninstall deletes data by default. keepData=true retains only this
  /// Publisher/Profile namespace; a later install must grant permissions again.
  Future<void> uninstall(String modId, {bool keepData = false}) async {
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'mod_installations',
        where: 'owner_id=? AND mod_id=?',
        whereArgs: [ownerId, modId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('MOD 未安装');
      final row = rows.first;
      final installationId = row['installation_id']! as String;
      final storageNamespace = row['storage_namespace']! as String;
      await _audit(
        txn,
        modId: modId,
        installationId: installationId,
        action: keepData ? 'uninstall_keep_data' : 'uninstall_delete_data',
      );
      if (keepData) {
        await txn.update(
          'mod_storage_metadata',
          {'retained': 1, 'updated_at': _now()},
          where: 'owner_id=? AND storage_namespace=?',
          whereArgs: [ownerId, storageNamespace],
        );
        await txn.delete(
          'mod_installations',
          where: 'installation_id=?',
          whereArgs: [installationId],
        );
      } else {
        // Deleting metadata cascades to storage entries, installation and grants.
        await txn.delete(
          'mod_storage_metadata',
          where: 'owner_id=? AND storage_namespace=?',
          whereArgs: [ownerId, storageNamespace],
        );
      }
    });
  }

  Future<Object?> readStorageValue(String modId, String key) async {
    _validateStorageKey(key);
    final db = await _db;
    final installation = await _activeInstallation(db, modId);
    await _ensureStorageGranted(db, installation);
    final rows = await db.query(
      'mod_storage_entries',
      columns: ['value_json'],
      where: 'owner_id=? AND storage_namespace=? AND entry_key=?',
      whereArgs: [ownerId, installation['storage_namespace'], key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return jsonDecode(rows.first['value_json']! as String);
  }

  Future<void> writeStorageValue(String modId, String key, Object? value) async {
    _validateStorageKey(key);
    final encoded = jsonEncode(value);
    final db = await _db;
    await db.transaction((txn) async {
      final installation = await _activeInstallation(txn, modId);
      await _ensureStorageGranted(txn, installation);
      final namespace = installation['storage_namespace']! as String;
      final metadataRows = await txn.query(
        'mod_storage_metadata',
        where: 'owner_id=? AND storage_namespace=?',
        whereArgs: [ownerId, namespace],
        limit: 1,
      );
      if (metadataRows.isEmpty) throw StateError('MOD 存储空间不存在');
      final metadata = metadataRows.first;
      final quota = metadata['quota_bytes'] as int;
      if (quota <= 0) throw StateError('此 MOD 未获准使用本地持久化存储');

      final entries = await txn.query(
        'mod_storage_entries',
        columns: ['entry_key', 'value_json'],
        where: 'owner_id=? AND storage_namespace=?',
        whereArgs: [ownerId, namespace],
      );
      var used = 0;
      String? oldValue;
      for (final entry in entries) {
        final entryKey = entry['entry_key']! as String;
        final entryValue = entry['value_json']! as String;
        used += utf8.encode(entryKey).length + utf8.encode(entryValue).length;
        if (entryKey == key) oldValue = entryValue;
      }
      final oldBytes = oldValue == null
          ? 0
          : utf8.encode(key).length + utf8.encode(oldValue).length;
      final newBytes = utf8.encode(key).length + utf8.encode(encoded).length;
      final nextUsed = used - oldBytes + newBytes;
      if (nextUsed > quota) throw StateError('MOD 本地存储空间已达到配额上限');

      await txn.insert('mod_storage_entries', {
        'owner_id': ownerId,
        'storage_namespace': namespace,
        'entry_key': key,
        'value_json': encoded,
        'updated_at': _now(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.update(
        'mod_storage_metadata',
        {'used_bytes': nextUsed, 'updated_at': _now()},
        where: 'owner_id=? AND storage_namespace=?',
        whereArgs: [ownerId, namespace],
      );
    });
  }

  Future<void> deleteStorageValue(String modId, String key) async {
    _validateStorageKey(key);
    final db = await _db;
    await db.transaction((txn) async {
      final installation = await _activeInstallation(txn, modId);
      await _ensureStorageGranted(txn, installation);
      final namespace = installation['storage_namespace']! as String;
      final rows = await txn.query(
        'mod_storage_entries',
        columns: ['value_json'],
        where: 'owner_id=? AND storage_namespace=? AND entry_key=?',
        whereArgs: [ownerId, namespace, key],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final bytes = utf8.encode(key).length +
          utf8.encode(rows.first['value_json']! as String).length;
      await txn.delete(
        'mod_storage_entries',
        where: 'owner_id=? AND storage_namespace=? AND entry_key=?',
        whereArgs: [ownerId, namespace, key],
      );
      await txn.rawUpdate(
        '''UPDATE mod_storage_metadata
           SET used_bytes=MAX(0,used_bytes-?),updated_at=?
           WHERE owner_id=? AND storage_namespace=?''',
        [bytes, _now(), ownerId, namespace],
      );
    });
  }

  Future<void> _ensureStorageGranted(
    DatabaseExecutor executor,
    Map<String, Object?> installation,
  ) async {
    final installationId = installation['installation_id']! as String;
    final grants = await executor.query(
      'mod_permission_grants',
      columns: ['grant_id'],
      where: 'installation_id=? AND capability=? AND revoked_at IS NULL',
      whereArgs: [installationId, 'storage.local'],
      limit: 1,
    );
    if (grants.isEmpty) throw StateError('MOD 未获准使用本地持久化存储');
    final metadata = await executor.query(
      'mod_storage_metadata',
      columns: ['quota_bytes'],
      where: 'owner_id=? AND storage_namespace=?',
      whereArgs: [ownerId, installation['storage_namespace']],
      limit: 1,
    );
    if (metadata.isEmpty || (metadata.first['quota_bytes'] as int) <= 0) {
      throw StateError('MOD 未获准使用本地持久化存储');
    }
  }

  Future<Map<String, Object?>> _activeInstallation(
    DatabaseExecutor executor,
    String modId,
  ) async {
    final rows = await executor.query(
      'mod_installations',
      where: 'owner_id=? AND mod_id=? AND status=? AND enabled=1',
      whereArgs: [ownerId, modId, 'installed'],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('MOD 未启用或需要重新授权');
    return rows.first;
  }

  static void _validateStorageKey(String key) {
    if (key.isEmpty ||
        key.length > 200 ||
        !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(key)) {
      throw ArgumentError.value(key, 'key', '存储键必须为 1-200 位安全字符');
    }
  }
}
