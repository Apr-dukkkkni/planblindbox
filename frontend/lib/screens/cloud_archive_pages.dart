import 'package:flutter/material.dart';

import '../services/cloud_archive_service.dart';
import '../services/core_auto_sync.dart';
import 'dart:convert';

/// Entry used by Today's cloud icon.
/// Returns true only if a cloud archive was restored successfully.
Future<bool> openCloudArchive(
  BuildContext context,
  CloudArchiveController controller,
) async {
  final credentials = await controller.store.read();
  if (!context.mounted) return false;
  if (credentials == null) {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CloudArchiveSettingsPage(controller: controller),
      ),
    );
    return false;
  }
  return await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => CloudArchiveOperationsPage(controller: controller),
        ),
      ) ??
      false;
}

class CloudArchiveSettingsPage extends StatefulWidget {
  const CloudArchiveSettingsPage({super.key, required this.controller});

  final CloudArchiveController controller;

  @override
  State<CloudArchiveSettingsPage> createState() => _CloudArchiveSettingsPageState();
}

class _CloudArchiveSettingsPageState extends State<CloudArchiveSettingsPage> {
  final _account = TextEditingController();
  final _appPassword = TextEditingController();
  bool _saving = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final saved = await widget.controller.store.read();
      if (!mounted || saved == null) return;
      _account.text = saved.account;
      _appPassword.text = saved.appPassword;
    } catch (error) {
      if (mounted) _message('读取账号配置失败：$error');
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _save() async {
    if (_saving) return;
    final account = _account.text.trim();
    final password = _appPassword.text.trim();
    if (account.isEmpty || password.isEmpty) {
      _message('请输入坚果云账号和第三方应用密码');
      return;
    }
    setState(() => _saving = true);
    try {
      final credentials = WebDavCredentials(
        account: account,
        appPassword: password,
      );
      // Do not save the credentials until the server accepts them.
      await widget.controller.webDav.testConnection(credentials);
      await widget.controller.store.save(credentials);
      if (!mounted) return;
      _message('坚果云配置成功');
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) _message('连接测试未通过：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clear() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.controller.store.clear();
      if (!mounted) return;
      _account.clear();
      _appPassword.clear();
      _message('已清除本机坚果云配置');
    } catch (error) {
      if (mounted) _message('清除失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _account.dispose();
    _appPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('坚果云存档设置')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('WebDAV 服务器：https://dav.jianguoyun.com/dav/'),
          const SizedBox(height: 12),
          const Text('请使用坚果云“第三方应用管理”生成的应用密码，不是网页登录密码。'),
          const SizedBox(height: 24),
          TextField(
            controller: _account,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: '坚果云账号'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _appPassword,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: '第三方应用密码',
              suffixIcon: IconButton(
                tooltip: _obscure ? '显示密码' : '隐藏密码',
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.cloud_done_outlined),
            label: Text(_saving ? '正在连接...' : '测试连接并保存'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _saving ? null : _clear,
            child: const Text('清除本机配置'),
          ),
          const SizedBox(height: 20),
          const Text(
            '提示：Web 端可能受坚果云跨域 CORS 策略限制。'
            '即使账号正确，浏览器也可能无法直接访问 WebDAV。'
            '不要通过关闭浏览器安全限制解决。',
          ),
        ],
      ),
    );
  }
}

class CloudArchiveOperationsPage extends StatefulWidget {
  const CloudArchiveOperationsPage({super.key, required this.controller});

  final CloudArchiveController controller;

  @override
  State<CloudArchiveOperationsPage> createState() =>
      _CloudArchiveOperationsPageState();
}

class _CloudArchiveOperationsPageState extends State<CloudArchiveOperationsPage> {
  bool _busy = false;

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<String?> _askBackupPassword({required bool confirm}) async {
    final first = TextEditingController();
    final again = TextEditingController();
    try {
      return await showDialog<String>(context: context, builder: (ctx) =>
        StatefulBuilder(builder: (ctx, redraw) => AlertDialog(
          title: Text(confirm ? '设置本次加密备份密码' : '输入加密备份密码'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('备份密码不会上传或保存。丢失密码将无法恢复该备份。'
              '建议使用至少10位、独立于账号密码的口令。'),
            const SizedBox(height: 12),
            TextField(controller: first, obscureText: true,
              decoration: const InputDecoration(labelText: '备份密码')),
            if (confirm) TextField(controller: again, obscureText: true,
              decoration: const InputDecoration(labelText: '再次输入备份密码')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('取消')),
            FilledButton(onPressed: () {
              if (first.text.length < 10 || (confirm && first.text != again.text)) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                  content: Text('密码至少10位，且两次输入必须一致')));
                return;
              }
              Navigator.pop(ctx, first.text);
            }, child: const Text('继续')),
          ],
        )));
    } finally {
      first.dispose();
      again.dispose();
    }
  }

  Future<void> _upload() async {
    if (_busy) return;
    final backupPassword = await _askBackupPassword(confirm: true);
    if (backupPassword == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await widget.controller.upload(backupPassword);
      if (mounted) _message('AES-GCM 加密备份成功：${result.createdAt.toLocal()}');
    } catch (error) {
      if (mounted) _message('上传失败（本地数据未被修改）：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadAndConfirm() async {
    if (_busy) return;
    final backupPassword = await _askBackupPassword(confirm: false);
    if (backupPassword == null || !mounted) return;
    setState(() => _busy = true);
    try {
      // Verify SHA-256 and the AES-GCM tag before touching local SQLite.
      DownloadedArchive archive;
      try {
        archive = await widget.controller.downloadLatest(backupPassword);
      } on LegacyPlaintextArchiveException {
        if (!mounted) return;
        final accepted = await showDialog<bool>(context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('旧版未加密备份'),
            content: const Text('检测到旧版明文备份。仅允许本次明确确认后读取。'
              '恢复后建议立即创建新的加密备份。'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true),
                child: const Text('明确同意读取旧备份')),
            ]));
        if (accepted != true) return;
        archive = await widget.controller.downloadLatest(backupPassword,
            allowLegacyPlaintext: true);
      }
      if (!mounted) return;
      final preview = jsonDecode(archive.backupJson);
      final tableMap = preview is Map ? preview['tables'] : null;
      int count(String key) => tableMap is Map && tableMap[key] is List
          ? (tableMap[key] as List).length : 0;
      final summary = '任务 ${count('tasks')} 项、习惯 ${count('habits')} 项、'
          '日记/情绪/经期 ${count('wellbeing_entries')} 天';
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('恢复云端存档？'),
          content: Text(
            '存档时间：${archive.info.createdAt.toLocal()}\n'
            '内容预览：$summary\n'
            '恢复将替换当前设备的个人业务数据。'
            '请先确认本地已有独立备份。是否继续？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('确认恢复'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await CoreAutoSync.instance.withSyncPaused(
          () => widget.controller.restore(archive));
      if (!mounted) return;
      // The caller reloads Today's data only after successful restore.
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) _message('恢复失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('云端存档'), actions: [
        IconButton(
          tooltip: '配置坚果云',
          onPressed: _busy
              ? null
              : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CloudArchiveSettingsPage(
                        controller: widget.controller,
                      ),
                    ),
                  ),
          icon: const Icon(Icons.settings_outlined),
        ),
      ]),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Text('存档是手动操作，不会在日常打卡时自动上传。'),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _busy ? null : _upload,
          icon: const Icon(Icons.cloud_upload_outlined),
          label: const Text('上传当前设备存档'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : _downloadAndConfirm,
          icon: const Icon(Icons.cloud_download_outlined),
          label: const Text('下载最近云端存档并恢复'),
        ),
        const SizedBox(height: 16),
        if (_busy) const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 24),
        const Text(
          '新存档已使用 AES-256-GCM 客户端加密，恢复前会验证 SHA-256、口令和密文完整性。'
          '恢复采用本地 SQLite 事务，并且只作用于当前账号。'
          '请先保留一份独立备份；忘记密码无法恢复加密存档。',
        ),
      ]),
    );
  }
}
