import 'package:flutter/material.dart';
import '../auth/auth_api.dart';
import '../auth/auth_session.dart';
import '../data/today_api.dart';
import '../services/core_sync_service.dart';
import '../services/core_auto_sync.dart';
import '../services/core_sync_store.dart';
import '../services/private_sync_vault.dart';

/// Account sync status page. Legacy whole-database snapshots are disabled.
class UserCloudProgressPage extends StatefulWidget {
  const UserCloudProgressPage({
    super.key,
    required this.api,
    required this.auth,
  });
  final TodayApi api;
  final AuthSession auth;
  @override
  State<UserCloudProgressPage> createState() => _UserCloudProgressPageState();
}

class _UserCloudProgressPageState extends State<UserCloudProgressPage> {
  bool _busy = false;
  bool _entitled = false;
  String _expiresAt = '';
  String? _error;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final token = widget.auth.token;
    if (token == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final client = CoreSyncClient(baseUrl: widget.auth.api.baseUrl);
      Map<String, dynamic> status;
      try {
        status = await client.entitlement(token);
      } finally {
        client.dispose();
      }
      if (!mounted || widget.auth.token != token) return;
      final active = status['active'] == true;
      setState(() {
        _entitled = active;
        _expiresAt = status['expiresAt']?.toString() ?? '';
        if (!active) {
          _error = '当前没有有效云同步订阅。坚果云免费备份不受影响。';
        }
      });
    } on AuthApiException catch (e) {
      if (e.statusCode == 401) await widget.auth.expireSession();
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String content) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认'),
            ),
          ],
        ),
      ) ??
      false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('账号云端进度'),
      actions: [
        IconButton(
          onPressed: _busy ? null : _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        AnimatedBuilder(
          animation: CoreAutoSync.instance,
          builder: (context, _) {
            final sync = CoreAutoSync.instance;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '任务与习惯 · 自动双向同步',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(sync.message),
                const SizedBox(height: 6),
                Text('待上传：${sync.pending} 条 · 冲突：${sync.conflictCount} 条'),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: sync.busy || widget.auth.token == null
                      ? null
                      : () => sync.syncNow(),
                  icon: const Icon(Icons.sync),
                  label: const Text('立即同步'),
                ),
                const SizedBox(height: 10),
                Text(
                  PrivateSyncVault.instance.unlocked(widget.api.userId)
                      ? '私密同步：已解锁（AES-256-GCM）'
                      : '私密同步：账号密钥尚未恢复，请重新登录后访问私密记录',
                ),
                const SizedBox(height: 8),
                const SizedBox(height: 6),
                const Text(
                  'V2 私密数据仓库：账号登录后自动恢复密钥并同步。'
                  '日记正文、情绪和生理期字段在本地与云端均只保存密文；新设备登录时通过 OPAQUE 自动解包密钥。',
                ),
                if (sync.conflictCount > 0)
                  FutureBuilder<List<CoreSyncConflict>>(
                    future: sync.conflicts(),
                    builder: (context, snapshot) {
                      final conflicts = snapshot.data ?? <CoreSyncConflict>[];
                      return Column(
                        children: [
                          for (final conflict in conflicts)
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${conflict.type == 'task'
                                          ? '任务'
                                          : conflict.type == 'diary'
                                          ? '日记/情绪/经期'
                                          : '习惯'}冲突 · ${conflict.uuid.substring(0, 8)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const Text(
                                      '两台设备都修改过此记录。选择保留哪一版；另一版不会自动覆盖。',
                                    ),
                                    Wrap(
                                      spacing: 8,
                                      children: [
                                        OutlinedButton(
                                          onPressed: sync.busy
                                              ? null
                                              : () async {
                                                  final accepted = await _confirm(
                                                    '保留云端版本？',
                                                    '本机对该记录的未上传修改将被替换，两个版本会留存在本地冲突救援记录中。',
                                                  );
                                                  if (!accepted) return;
                                                  await sync.resolveConflict(
                                                    conflict.type,
                                                    conflict.uuid,
                                                    keepLocal: false,
                                                  );
                                                  if (mounted) setState(() {});
                                                },
                                          child: const Text('保留云端版本'),
                                        ),
                                        OutlinedButton(
                                          onPressed: sync.busy
                                              ? null
                                              : () async {
                                                  final accepted = await _confirm(
                                                    '保留本机版本？',
                                                    '将按最新服务器版本重新上传本机记录；两个版本会留存在本地冲突救援记录中。',
                                                  );
                                                  if (!accepted) return;
                                                  await sync.resolveConflict(
                                                    conflict.type,
                                                    conflict.uuid,
                                                    keepLocal: true,
                                                  );
                                                  if (mounted) setState(() {});
                                                },
                                          child: const Text('保留本机版本'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                const Divider(height: 28),
              ],
            );
          },
        ),
        const Icon(Icons.cloud_sync_outlined, size: 58),
        const SizedBox(height: 16),
        Text(widget.auth.user?.email ?? '', textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Text(
          '核心云同步：¥9.9/年 · ${_entitled ? '内测权益有效' : '尚未开通或已过期'}'
          '${_expiresAt.isEmpty ? '' : ' · 到期时间 $_expiresAt'}',
        ),
        const SizedBox(height: 10),
        const Text(
          '当前尚未接入正式支付渠道，内测订阅由后台授权。到期后停止上传，但仍可取回云端已存数据。旧版整库明文上传已停用；坚果云使用独立备份密码。',
        ),
        const SizedBox(height: 12),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 20),
        Card(
          child: ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('旧版整库云端快照已停用'),
            subtitle: const Text(
              '为避免未经端到端加密的私密数据进入服务器，旧版整库上传与恢复接口均已关闭。任务和习惯使用上方自动同步；日记、情绪和生理期使用 V2 私密数据仓库。完整备份请使用坚果云加密备份。',
            ),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          '切换账号不会自动删除本机 SQLite 数据。切换账号前，请确认本机数据所属账号，避免将一个账号的数据误认为另一个账号的数据。',
        ),
      ],
    ),
  );
}
