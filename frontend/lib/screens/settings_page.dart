import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';

import '../data/today_api.dart';
import '../services/app_preferences.dart';
import 'mod_management_page.dart';

/// 本地设置：偏好设置、数据备份恢复、重置和存储状态。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.api});

  final TodayApi api;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _loading = true;
  bool _busy = false;
  bool _modsEnabled = true;
  String? _error;
  Map<String, dynamic>? _storageStatus;
  Map<String, dynamic>? _signInStats;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      await AppPreferences.instance.reload();
      final modsEnabledSetting = await widget.api.repository.getAppSetting('mods.enabled.v1');
      final results = await Future.wait([
        widget.api.repository.getStorageStatus(),
        widget.api.repository.getDailySignInStats(),
      ]);
      if (!mounted) return;
      setState(() {
        _storageStatus = results[0];
        _signInStats = results[1];
        _modsEnabled = modsEnabledSetting != 'false';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _backup() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final json = await widget.api.repository.exportBackupJson();
      final bytes = Uint8List.fromList(utf8.encode(json));
      final now = DateTime.now();
      final stamp = '${now.year.toString().padLeft(4, '0')}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}_'
          '${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}'
          '${now.second.toString().padLeft(2, '0')}';

      await FileSaver.instance.saveAs(
        name: 'PlanBlindBox_backup_$stamp',
        bytes: bytes,
        fileExtension: 'json',
        mimeType: MimeType.custom,
        customMimeType: 'application/json',
      );
      await widget.api.repository.setAppSetting(
        'last_backup_at',
        DateTime.now().toIso8601String(),
      );
      await _load();
      if (mounted) _showMessage('备份文件已生成，请妥善保存。');
    } catch (error) {
      if (mounted) _showMessage('备份失败：$error', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        _showMessage('无法读取所选文件内容，请重新选择备份文件。', isError: true);
        return;
      }
      final confirmed = await _confirm(
        title: '确认恢复本地数据？',
        content: '将使用「${file.name}」替换当前设备上的全部本地数据，包括任务、习惯、打卡记录、资产、盲盒记录、收藏品和偏好设置。此操作不能撤销，建议先备份当前数据。',
        confirmText: '替换并恢复',
      );
      if (!confirmed || !mounted) return;

      setState(() => _busy = true);
      final content = utf8.decode(bytes, allowMalformed: false);
      await widget.api.repository.restoreBackupJson(content);
      await AppPreferences.instance.reload();
      await _load();
      if (mounted) _showMessage('本地数据恢复成功。');
    } catch (error) {
      if (mounted) _showMessage('恢复失败：$error', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (_busy) return;
    final confirmed = await _confirm(
      title: '确认重置 PlanBlindBox？',
      content: '这将清空当前设备上的任务、习惯、打卡、资产、奖励流水、盲盒记录和收藏进度，并恢复默认分类及偏好设置。内置盲盒和收藏品目录会保留。此操作不能撤销。',
      confirmText: '清空并重置',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    try {
      await widget.api.repository.resetLocalData(resetPreferences: true);
      await AppPreferences.instance.reload();
      await _load();
      if (mounted) _showMessage('本地数据已重置。');
    } catch (error) {
      if (mounted) _showMessage('重置失败：$error', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String content,
    required String confirmText,
    bool destructive = false,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(content),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                style: destructive
                    ? FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                      )
                    : null,
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(confirmText),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  String _dateText(Object? value) {
    if (value == null || value.toString().isEmpty) return '暂无';
    final date = DateTime.tryParse(value.toString());
    if (date == null) return value.toString();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final preferences = AppPreferences.instance;
    final status = _storageStatus;
    final counts = status?['counts'] is Map
        ? Map<String, dynamic>.from(status!['counts'] as Map)
        : <String, dynamic>{};

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        actions: [
          IconButton(
            tooltip: '刷新存储状态',
            onPressed: _loading || _busy ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _sectionTitle('基础偏好', '这些选项保存在本地设备中'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('默认首页', style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: preferences.defaultTab,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          items: AppPreferences.availableTabs.entries
                              .map((entry) => DropdownMenuItem<String>(
                                    value: entry.key,
                                    child: Text(entry.value),
                                  ))
                              .toList(),
                          onChanged: _busy
                              ? null
                              : (value) async {
                                  if (value == null) return;
                                  await preferences.setDefaultTab(value);
                                  if (mounted) setState(() {});
                                  if (mounted) {
                                    _showMessage('默认首页已保存，下次启动应用时生效。');
                                  }
                                },
                        ),
                        const Divider(height: 24),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('显示每日签到成功提示'),
                          subtitle: const Text('关闭后仍会自动签到和领取水滴，只是不再弹出提示。'),
                          value: preferences.showDailySignInNotice,
                          onChanged: _busy
                              ? null
                              : (value) async {
                                  await preferences.setShowDailySignInNotice(value);
                                  if (mounted) setState(() {});
                                },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _sectionTitle('Mod 扩展', '安装入口在今日页左上角叶子，启停和管理在这里'),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.extension_outlined),
                        title: const Text('启用 Mod 功能'),
                        subtitle: const Text('关闭后暂停使用所有 Mod 扩展，不会删除已安装内容及授权。'),
                        value: _modsEnabled,
                        onChanged: _busy ? null : (enabled) async {
                          try {
                            await widget.api.repository.setAppSetting('mods.enabled.v1', enabled.toString());
                            if (mounted) setState(() => _modsEnabled = enabled);
                          } catch (error) {
                            if (mounted) _showMessage('切换 Mod 失败：$error', isError: true);
                          }
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.inventory_2_outlined),
                        title: const Text('已安装 Mod 管理'),
                        subtitle: const Text('查看已安装插件、逐个启停、卸载、授权和任务模板'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _busy ? null : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ModManagementPage(api: widget.api),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _sectionTitle('签到统计', '月度奖励连续天数与历史坚持情况分开计算'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _signInStats == null
                        ? const Text('暂无签到统计')
                        : Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: _statValue(
                                      '本月连续',
                                      '${_signInStats!['monthlyStreakDay'] ?? 0} 天',
                                      Icons.calendar_month_outlined,
                                    ),
                                  ),
                                  Expanded(
                                    child: _statValue(
                                      '跨月当前连续',
                                      '${_signInStats!['allTimeStreakDay'] ?? 0} 天',
                                      Icons.local_fire_department_outlined,
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(height: 24),
                              Row(
                                children: [
                                  Expanded(
                                    child: _statValue(
                                      '历史最长连续',
                                      '${_signInStats!['longestStreakDay'] ?? 0} 天',
                                      Icons.emoji_events_outlined,
                                    ),
                                  ),
                                  Expanded(
                                    child: _statValue(
                                      '累计签到',
                                      '${_signInStats!['totalSignInDays'] ?? 0} 天',
                                      Icons.check_circle_outline,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '统计截至：${_signInStats!['businessDate'] ?? '—'}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 20),
                _sectionTitle('本地数据备份', '备份文件可以用于换设备或重新安装后的数据恢复'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.backup_outlined),
                            SizedBox(width: 9),
                            Text('导出完整备份', style: TextStyle(fontWeight: FontWeight.w700)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '导出 JSON 文件，包含任务、习惯、打卡记录、资产流水、盲盒记录、收藏品、分类及偏好设置。建议定期备份并将文件保存到设备以外的位置。',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _busy ? null : _backup,
                            icon: const Icon(Icons.download_outlined),
                            label: const Text('立即备份'),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '上次备份：${_dateText(status?['lastBackupAt'])}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.restore_outlined),
                            SizedBox(width: 9),
                            Text('从备份恢复', style: TextStyle(fontWeight: FontWeight.w700)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '选择 PlanBlindBox 导出的 JSON 备份文件。恢复会整体替换当前本地数据，不会与现有数据合并。',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : _restore,
                            icon: const Icon(Icons.file_open_outlined),
                            label: const Text('选择备份文件并恢复'),
                          ),
                        ),
                        Text(
                          '上次恢复：${_dateText(status?['lastRestoreAt'])}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _sectionTitle('数据清理与重置', '清空个人数据，保留软件内置内容目录'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '重置本地数据',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          '清空任务、习惯、打卡、资产、奖励流水、盲盒记录和收藏进度；恢复默认任务分类及偏好设置。内置盲盒和收藏品目录不会删除。',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Theme.of(context).colorScheme.error,
                            ),
                            onPressed: _busy ? null : _reset,
                            icon: const Icon(Icons.delete_forever_outlined),
                            label: const Text('清空并恢复初始状态'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _sectionTitle('数据存储状态', '核心数据保存在当前设备，不依赖后端服务器'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_loading && status == null)
                          const LinearProgressIndicator(minHeight: 2)
                        else ...[
                          _infoRow('存储引擎', status?['engine']?.toString() ?? '—'),
                          _infoRow('存储位置', status?['location']?.toString() ?? '—'),
                          _infoRow('数据库标识', status?['databaseName']?.toString() ?? '—'),
                          _infoRow('数据库版本', 'V${status?['schemaVersion'] ?? '—'}'),
                          _infoRow('本地记录总数', '${status?['totalRecords'] ?? 0} 条'),
                          _infoRow('最近数据变更', _dateText(status?['lastUpdatedAt'])),
                          const Divider(height: 22),
                          const Text('业务数据分布', style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: counts.entries
                                .map((entry) => Chip(
                                      label: Text('${entry.key} ${entry.value}'),
                                      visualDensity: VisualDensity.compact,
                                    ))
                                .toList(),
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            '状态读取失败：$_error',
                            style: TextStyle(color: Theme.of(context).colorScheme.error),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          'Edge 网页版使用浏览器 IndexedDB 保存 SQLite 数据；清理浏览器站点数据可能导致本地数据丢失。手机端使用应用私有目录。请定期导出备份。',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_busy)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.08),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, String subtitle) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 92,
              child: Text(label, style: Theme.of(context).textTheme.bodySmall),
            ),
            Expanded(
              child: SelectableText(
                value,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ),
      );

  Widget _statValue(String label, String value, IconData icon) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 5),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
        ],
      );
}
