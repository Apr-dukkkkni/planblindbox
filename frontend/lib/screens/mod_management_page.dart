import 'package:flutter/material.dart';

import '../data/today_api.dart';
import '../auth/auth_session.dart';
import '../services/mod_registry.dart';
import '../mod_platform/runtime/mod_capability_broker.dart';
import '../mod_platform/runtime/mod_runtime_manager.dart';
import '../mod_platform/runtime/platform_proof_approval_provider.dart';

/// Transitional declaration-only MOD manager. No untrusted code is executed.
class ModManagementPage extends StatefulWidget {
  const ModManagementPage({
    super.key,
    required this.api,
    required this.auth,
  });
  final TodayApi api;
  final AuthSession auth;

  @override
  State<ModManagementPage> createState() => _ModManagementPageState();
}

class _ModManagementPageState extends State<ModManagementPage> {
  late final ModRegistry _registry = ModRegistry(widget.api.repository);
  late final PlatformProofApprovalProvider _platformApproval =
      PlatformProofApprovalProvider(auth: widget.auth);
  late final ModCapabilityBroker _broker = ModCapabilityBroker.forRepository(
    widget.api.repository,
    approvalProvider: _platformApproval,
  );
  late final ModRuntimeManager _runtime =
      ModRuntimeManager.forRepository(widget.api.repository);
  List<Map<String, dynamic>> _mods = [];
  List<Map<String, dynamic>> _templates = [];
  List<Map<String, dynamic>> _audit = [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _runtime.shutdown();
    _platformApproval.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final mods = await _registry.list();
      final templates = await _runtime.listAvailableTaskTemplates();
      final audit = await _registry.audit();
      if (!mounted) return;
      setState(() {
        _mods = mods;
        _templates = templates;
        _audit = audit;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('操作失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(message),
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

  String _manifestSha256(Map<String, dynamic> mod) {
    final fileDigests = mod['fileDigests'];
    final digest = fileDigests is Map ? fileDigests['manifest.json'] : null;
    if (digest is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      throw StateError('本地 MOD 安装记录缺少有效的 Manifest SHA-256');
    }
    return digest;
  }

  Future<void> _grantV1Capability(Map<String, dynamic> mod) async {
    final modId = mod['id'] as String;
    final version = mod['installedVersion'] as String;
    const capability = 'host.tasks.create';
    final manifestSha256 = _manifestSha256(mod);
    await _platformApproval.grantCapability(
      ownerId: widget.api.repository.modOwnerId,
      modId: modId,
      version: version,
      capability: capability,
      manifestSha256: manifestSha256,
    );
    try {
      await _registry.grantPermission(modId, capability);
    } catch (_) {
      // Compensate both sides if the local install mutation fails part-way.
      try {
        await _registry.revokePermission(modId, capability);
      } catch (_) {
        // A missing local grant is already fail-closed.
      }
      try {
        await _platformApproval.revokeCapability(
          ownerId: widget.api.repository.modOwnerId,
          modId: modId,
          version: version,
          capability: capability,
          manifestSha256: manifestSha256,
        );
      } catch (_) {
        // Local state remains ungranted, so the Host API stays closed.
      }
      rethrow;
    }
  }

  Future<void> _syncV1Capability(Map<String, dynamic> mod) async {
    await _platformApproval.grantCapability(
      ownerId: widget.api.repository.modOwnerId,
      modId: mod['id'] as String,
      version: mod['installedVersion'] as String,
      capability: 'host.tasks.create',
      manifestSha256: _manifestSha256(mod),
    );
  }

  Future<void> _revokeV1Capability(Map<String, dynamic> mod) async {
    final modId = mod['id'] as String;
    final version = mod['installedVersion'] as String;
    const capability = 'host.tasks.create';
    // The server grant is authoritative for cross-device proof verification.
    // Revoke it first; once confirmed, immediately terminate the local Session.
    await _platformApproval.revokeCapability(
      ownerId: widget.api.repository.modOwnerId,
      modId: modId,
      version: version,
      capability: capability,
      manifestSha256: _manifestSha256(mod),
    );
    await _registry.revokePermission(modId, capability);
  }

  Future<void> _createFromTemplate(Map<String, dynamic> template) async {
    final title = template['title'] as String;
    final accepted = await _confirm(
      '使用任务模板？',
      '来自 ${template['modName']} 的模板将新建任务「$title」。只有确认后才会写入本地 SQLite。',
    );
    if (!accepted || !mounted) return;
    await _run(() async {
      ModRuntimeInstance? runtime;
      try {
        runtime = await _runtime.start(template['modId'] as String);
        if (runtime.installationId != template['installationId']) {
          throw StateError('MOD 安装实例已变化，请刷新后重试');
        }
        final payload = await _runtime.taskPayload(
          runtime,
          template['templateIndex'] as int,
        );
        for (final field in const ['title', 'note', 'targetCount', 'importance', 'difficulty']) {
          if (template[field] != payload[field]) {
            throw StateError('任务模板内容已发生变化，请重新确认');
          }
        }
        // A validated declarative Runtime still needs admin + user grants.
        final consent = await _broker.issueUserConsent(
          session: runtime.session,
          capability: 'host.tasks.create',
          payload: payload,
        );
        final result = await _broker.invoke(
          session: runtime.session,
          capability: 'host.tasks.create',
          payload: payload,
          consent: consent,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已创建任务：$title（请求 ${result.requestId.substring(0, 8)}）')),
          );
        }
      } finally {
        if (runtime != null) _runtime.stop(runtime);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mod 管理'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _reload,
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 108),
        children: [
          const Text(
            '这里管理已安装 Mod 的启停、卸载和任务模板。新 Mod 请从「今日」页面左上角叶子打开侧边栏导入或前往在线市场。',
          ),
          const SizedBox(height: 12),
          const Card(
            child: ListTile(
              leading: Icon(Icons.verified_user_outlined),
              title: Text('宿主能力采用双重授权'),
              subtitle: Text('任务创建需要平台管理员审批、用户授权和每次操作的确认。每次调用前都会验证平台签名证明并在线复核。'),
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Text(
              '读取失败：$_error',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          Text(
            '已安装 (${_mods.length})',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (_mods.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('暂无 Mod。可以导入旧版 JSON 或 V1 ZIP 任务模板内容包。'),
            ),
          for (final mod in _mods)
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: Text('${mod['name']}  v${mod['version']}'),
                    subtitle: Text(
                      '${mod['id']}\n${mod['description']}\n'
                      '${mod['isV1Package'] == true ? 'V1 内容包 · 声明式 Runtime；Host API 仍需管理员审批' : mod['status'] == 'requires_reauthorization' ? '备份恢复后需要重新安装并授权' : mod['effectiveProfile']}',
                    ),
                    isThreeLine: true,
                    value: mod['enabled'] == true,
                    onChanged: _busy ||
                            mod['status'] == 'requires_reauthorization' ||
                            (mod['isV1Package'] == true &&
                                !(mod['grantedPermissions'] as List)
                                    .contains('host.tasks.create'))
                        ? null
                        : (value) => _run(
                            () => _registry.setEnabled(
                              mod['id'] as String,
                              value,
                            ),
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '授权：${(mod['grantedPermissions'] as List).isEmpty ? '无' : (mod['grantedPermissions'] as List).join(', ')}',
                      ),
                    ),
                  ),
                  if (mod['isV1Package'] == true &&
                      !(mod['grantedPermissions'] as List).contains('host.tasks.create'))
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        icon: const Icon(Icons.lock_open_outlined),
                        label: const Text('授权并启用任务创建'),
                        onPressed: _busy
                            ? null
                            : () async {
                                final ok = await _confirm(
                                  '授权此 Mod 创建任务？',
                                  '这会先向服务器同步当前账号对 host.tasks.create 的授权，再保存本地授权并启用声明式 Runtime。需要登录且保持网络可用；平台管理员审批仍然独立生效。',
                                );
                                if (ok) {
                                  await _run(
                                    () => _grantV1Capability(mod),
                                  );
                                }
                              },
                      ),
                    ),
                  if (mod['isV1Package'] == true &&
                      (mod['grantedPermissions'] as List).contains('host.tasks.create'))
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        icon: const Icon(Icons.sync),
                        label: const Text('同步服务器授权'),
                        onPressed: _busy
                            ? null
                            : () => _run(() => _syncV1Capability(mod)),
                      ),
                    ),
                  if (mod['isV1Package'] == true &&
                      (mod['grantedPermissions'] as List).contains('host.tasks.create'))
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        icon: const Icon(Icons.lock_outline),
                        label: const Text('撤销任务创建权限'),
                        onPressed: _busy
                            ? null
                            : () async {
                                final ok = await _confirm(
                                  '撤销此 Mod 的任务创建权限？',
                                  '撤销后会立即禁用此 Mod，并终止现有 Runtime Session。之后需要重新授权才能恢复。',
                                );
                                if (ok) {
                                  await _run(
                                    () => _revokeV1Capability(mod),
                                  );
                                }
                              },
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('卸载'),
                      onPressed: _busy
                          ? null
                          : () async {
                              final ok = await _confirm(
                                '卸载 ${mod['name']}？',
                                '卸载会移除此 Mod 的模板和授权，不会删除已经创建的任务。',
                              );
                              if (ok) {
                                await _run(
                                  () =>
                                      _registry.uninstall(mod['id'] as String),
                                );
                              }
                            },
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 18),
          Text(
            '可用任务模板 (${_templates.length})',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          for (final template in _templates)
            Card(
              child: ListTile(
                title: Text(template['title'] as String),
                subtitle: Text(
                  '来自 ${template['modName']} · 目标 ${template['targetCount']} 次',
                ),
                trailing: const Icon(Icons.add_task_outlined),
                onTap: _busy ? null : () => _createFromTemplate(template),
              ),
            ),
          const SizedBox(height: 18),
          Text('最近操作', style: Theme.of(context).textTheme.titleLarge),
          for (final event in _audit.take(10))
            ListTile(
              dense: true,
              title: Text('${event['action']} · ${event['id']}'),
              subtitle: Text('${event['at']}'),
            ),
        ],
      ),
    );
  }
}
