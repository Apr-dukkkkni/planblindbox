import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../runtime/declarative_mod_runtime.dart';
import '../runtime/mod_capability_broker.dart';
import '../runtime/mod_runtime_manager.dart';

/// A host-rendered view of a validated declarative definition. No MOD-defined
/// Dart widgets, JavaScript, WebViews, URLs or filesystem APIs are loaded here.
/// All host mutations are delegated to the P0-3 Capability Broker.
class ModUiPanel extends StatefulWidget {
  const ModUiPanel({
    super.key,
    required this.instance,
    required this.runtime,
    required this.broker,
    this.onTaskCreated,
  });

  final ModRuntimeInstance instance;
  final ModRuntimeManager runtime;
  final ModCapabilityBroker broker;
  final VoidCallback? onTaskCreated;

  @override
  State<ModUiPanel> createState() => _ModUiPanelState();
}

class _ModUiPanelState extends State<ModUiPanel> {
  bool _busy = false;
  String? _message;

  Future<void> _createTask(ModDeclaredTaskTemplate template) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // Check the persisted install, grants, dependency and active session
      // BEFORE asking the user to confirm anything.
      final proposed = await widget.runtime.taskPayload(
        widget.instance,
        template.index,
      );
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('创建宿主任务？'),
          content: Text('使用「${proposed['title']}」创建任务？操作仍需平台审核及用户授权。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const Key('mod-ui-confirm-create'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('确认'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      // Prevent TOCTOU: a newer install must not silently alter the template
      // between the confirmation dialog and the capability invocation.
      final current = await widget.runtime.taskPayload(
        widget.instance,
        template.index,
      );
      if (!mapEquals(proposed, current)) {
        throw ModRuntimeUnavailable('任务模板已变化，请重新打开 MOD');
      }
      final consent = await widget.broker.issueUserConsent(
        session: widget.instance.session,
        capability: 'host.tasks.create',
        payload: current,
      );
      final result = await widget.broker.invoke(
        session: widget.instance.session,
        capability: 'host.tasks.create',
        payload: current,
        consent: consent,
      );
      if (!mounted) return;
      widget.onTaskCreated?.call();
      setState(
        () => _message = '任务已创建（请求 ${result.requestId.substring(0, 8)}）',
      );
    } catch (error) {
      if (mounted) setState(() => _message = '操作已拒绝：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final definition = widget.instance.definition;
    final active = widget.runtime.isRunning(widget.instance);
    return ListView(
      key: const Key('mod-ui-panel'),
      padding: const EdgeInsets.all(14),
      children: [
        Text(definition.name, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          '版本 ${definition.version} · ${definition.effectiveProfile}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        const Text('此页面由 PlanBlindBox 安全渲染，仅展示已验证的声明式数据，不运行第三方代码。'),
        const SizedBox(height: 10),
        if (!active)
          const Card(
            child: ListTile(
              leading: Icon(Icons.block),
              title: Text('MOD 会话已失效'),
              subtitle: Text('可能已停用、撤权或超时。请关闭后重新打开。'),
            ),
          ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(_message!, key: const Key('mod-ui-result')),
          ),
        if (definition.taskTemplates.isEmpty) const Text('此 MOD 暂无可展示的任务模板。'),
        for (final template in definition.taskTemplates)
          Card(
            child: ListTile(
              title: Text(template.payload['title'] as String),
              subtitle: Text('目标 ${template.payload['targetCount']} 次'),
              trailing: const Icon(Icons.add_task_outlined),
              enabled: !_busy && active,
              onTap: !_busy && active ? () => _createTask(template) : null,
            ),
          ),
        if (_busy) const LinearProgressIndicator(),
        const SizedBox(height: 12),
        Text(
          '宿主任务创建需要登录、平台签名证明、实时授权复核和本次操作确认。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
