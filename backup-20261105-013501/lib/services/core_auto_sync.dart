import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'core_sync_service.dart';
import 'core_sync_store.dart';

/// A single in-process scheduler. SQLite carries the durable queue/cursor,
/// so killing the app never loses a pending write.
class CoreAutoSync extends ChangeNotifier {
  CoreAutoSync._();
  static final CoreAutoSync instance = CoreAutoSync._();

  Timer? _timer;
  CoreSyncClient? _client;
  CoreSyncStore? _store;
  String? _token;
  String? _baseUrl;
  int? _userId;
  int _epoch = 0;
  bool _busy = false;
  bool _active = false;
  int _pending = 0;
  int _conflicts = 0;
  int _appliedGeneration = 0;
  String _message = '尚未连接云同步';

  bool get busy => _busy;
  bool get active => _active;
  int get pending => _pending;
  int get conflictCount => _conflicts;
  int get appliedGeneration => _appliedGeneration;
  String get message => _message;
  int? get accountUserId => _userId;

  void bind({required int localUserId, required String? token,
      required String baseUrl}) {
    final valid = localUserId < -1000000 && token != null &&
        token.isNotEmpty && baseUrl.startsWith('http');
    final nextId = valid ? localUserId : null;
    final nextToken = valid ? token : null;
    if (_userId == nextId && _token == nextToken && _baseUrl == baseUrl) return;
    _epoch++;
    _timer?.cancel();
    _timer = null;
    _client?.dispose();
    _client = null;
    _store = null;
    _userId = nextId;
    _token = nextToken;
    _baseUrl = baseUrl;
    _active = false;
    _pending = 0;
    _conflicts = 0;
    _message = valid ? '正在连接云同步' : '登录后可使用付费云同步';
    notifyListeners();
    if (!valid) return;
    _store = CoreSyncStore(nextId!);
    _client = CoreSyncClient(baseUrl: baseUrl);
    // Polling also covers offline reconnection and changes made by any widget.
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => syncNow());
    Future<void>.delayed(Duration.zero, syncNow);
  }

  Future<List<CoreSyncConflict>> conflicts() async =>
      _store?.conflicts() ?? <CoreSyncConflict>[];

  Future<void> resolveConflict(String type, String uuid,
      {required bool keepLocal}) async {
    final store = _store;
    if (store == null || _busy) return;
    await store.resolve(type, uuid, keepLocal: keepLocal);
    _conflicts = (await store.conflicts()).length;
    if (!keepLocal) _appliedGeneration++;
    notifyListeners();
    syncNow();
  }

  Future<bool> _push(CorePendingMutation mutation, CoreSyncClient client,
      CoreSyncStore store, String token, int epoch) async {
    try {
      final result = await client.mutate(token,
        operationId: mutation.operationId, type: mutation.type,
        id: mutation.uuid, expectedRevision: mutation.expectedRevision,
        deleted: mutation.deleted,
        payload: mutation.payloadJson == null ? null :
            Map<String, dynamic>.from(jsonDecode(mutation.payloadJson!) as Map),
      );
      if (epoch != _epoch) return false;
      await store.acknowledge(mutation, (result['revision'] as num).toInt());
      return true;
    } on CoreSyncException catch (error) {
      if (error.status == 409) {
        // Pulling the new remote revision will preserve both copies in SQLite.
        _message = '检测到冲突，正在保存双方版本';
        return false;
      }
      rethrow;
    }
  }

  Future<int> _pull(CoreSyncClient client, CoreSyncStore store,
      String token, int epoch) async {
    int count = 0;
    for (var page = 0; page < 100; page++) {
      if (epoch != _epoch) return count;
      final cursor = await store.cursor();
      final result = await client.changes(token, cursor: cursor, limit: 100);
      if (epoch != _epoch) return count;
      final changed = result['changes'];
      if (changed is! List || result['cursor'] is! num) {
        throw const FormatException('服务器同步分页格式无效');
      }
      final nextCursor = (result['cursor'] as num).toInt();
      if (nextCursor < cursor || (result['hasMore'] == true && nextCursor == cursor)) {
        throw const FormatException('同步游标未推进');
      }
      count += await store.applyPage(changed, nextCursor);
      if (result['hasMore'] != true) break;
      if (page == 99) throw StateError('单次同步超过最大分页限制，请再试');
    }
    return count;
  }

  Future<void> syncNow() async {
    if (_busy || _store == null || _client == null || _token == null) return;
    final store = _store!;
    final client = _client!;
    final token = _token!;
    final epoch = _epoch;
    _busy = true;
    _message = '同步中…';
    notifyListeners();
    try {
      final entitlement = await client.entitlement(token);
      if (epoch != _epoch) return;
      _active = entitlement['active'] == true;
      // Retry any already-sent operation *before* pulling its own change.
      // This prevents a timeout after server commit becoming a false conflict.
      if (_active) {
        final alreadySent = await store.existingMutation();
        if (alreadySent != null) {
          await _push(alreadySent, client, store, token, epoch);
        }
      }
      if (epoch != _epoch) return;
      // Protect pre-existing local records before the first remote pull.
      // Otherwise a UUID restored from backup could be silently overwritten.
      await store.bootstrap();
      final changed = await _pull(client, store, token, epoch);
      if (epoch != _epoch) return;
      if (changed > 0) _appliedGeneration++;
      if (_active) {
        for (var i = 0; i < 40 && epoch == _epoch; i++) {
          final next = await store.nextMutation();
          if (next == null) break;
          if (!await _push(next, client, store, token, epoch)) break;
        }
        if (epoch != _epoch) return;
        final after = await _pull(client, store, token, epoch);
        if (after > 0) _appliedGeneration++;
      }
      if (epoch != _epoch) return;
      _pending = await store.pendingCount();
      _conflicts = (await store.conflicts()).length;
      _message = !_active
          ? '订阅未生效：本地数据正常，云端已有数据仍可下载'
          : _conflicts > 0
              ? '有 $_conflicts 条同步冲突，需手动选择保留版本'
              : _pending > 0
                  ? '剩余 $_pending 条待同步数据，稍后自动重试'
                  : '已同步 · 任务与习惯';
    } catch (error) {
      if (epoch != _epoch) return;
      _message = '同步暂不可用（本地修改已保留）：$error';
    } finally {
      if (epoch == _epoch) {
        _busy = false;
        notifyListeners();
      } else {
        // Account changed while a request was in flight. Never apply its result.
        _busy = false;
        Future<void>.delayed(Duration.zero, syncNow);
      }
    }
  }

  void stop() {
    _epoch++;
    _timer?.cancel();
    _timer = null;
    _client?.dispose();
    _client = null;
    _store = null;
    _token = null;
    _userId = null;
    _active = false;
    _busy = false;
  }
}
