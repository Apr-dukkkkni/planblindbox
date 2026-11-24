import 'dart:convert';

import '../manifest/mod_manifest_v1_validator.dart';
import '../storage/mod_platform_store.dart';
import 'mod_runtime_session.dart';

/// Approval data must come from a trusted, signature-verified platform source.
/// The production default denies all capabilities until that integration exists.
abstract interface class ModApprovalProvider {
  Future<Set<String>> approvedCapabilities(ModApprovalRequest request);
}

class DenyAllModApprovalProvider implements ModApprovalProvider {
  const DenyAllModApprovalProvider();

  @override
  Future<Set<String>> approvedCapabilities(ModApprovalRequest request) async =>
      const <String>{};
}

class ModApprovalRequest {
  const ModApprovalRequest({
    required this.ownerId,
    required this.installationId,
    required this.modId,
    required this.publisherId,
    required this.version,
    required this.packageSha256,
    required this.capability,
  });

  final int ownerId;
  final String installationId;
  final String modId;
  final String publisherId;
  final String version;
  final String? packageSha256;
  final String capability;
}

class ModPermissionDecision {
  const ModPermissionDecision.allowed(this.installation)
      : reason = null;
  const ModPermissionDecision.denied(this.reason) : installation = null;

  final Map<String, dynamic>? installation;
  final String? reason;
  bool get isAllowed => installation != null;
}


/// Central policy engine. This is the only place that combines the platform
/// approval, Manifest declaration, user grant, account, Profile and Runtime checks.
class ModPermissionPolicy {
  ModPermissionPolicy({
    required ModPlatformStore store,
    required ModApprovalProvider approvalProvider,
    required ModRuntimeSessionManager sessionManager,
    required Future<bool> Function() globalModsEnabled,
  }) : _store = store,
       _approvalProvider = approvalProvider,
       _sessionManager = sessionManager,
       _globalModsEnabled = globalModsEnabled;

  final ModPlatformStore _store;
  final ModApprovalProvider _approvalProvider;
  final ModRuntimeSessionManager _sessionManager;
  final Future<bool> Function() _globalModsEnabled;

  Future<ModPermissionDecision> authorize(
    ModRuntimeSession session,
    String capability,
    Map<String, dynamic> payload,
  ) async {
    if (!_sessionManager.isActive(session)) {
      return const ModPermissionDecision.denied('Runtime Session 已失效');
    }
    if (session.ownerId != _store.ownerId) {
      return const ModPermissionDecision.denied('当前账号与 Runtime Session 不匹配');
    }
    if (!await isGloballyEnabled()) {
      return const ModPermissionDecision.denied('MOD 功能已关闭');
    }
    if (capability != 'host.tasks.create') {
      return const ModPermissionDecision.denied('当前 Host API 未开放此 capability');
    }

    final installation = await findInstallation(session.modId);
    if (installation == null ||
        installation['installationId'] != session.installationId ||
        installation['installedModId'] != session.modId ||
        installation['status'] != 'installed' ||
        installation['enabled'] != true) {
      return const ModPermissionDecision.denied('MOD 安装状态已变化');
    }
    if (installation['effectiveProfile'] != 'host_integrated_offline') {
      return const ModPermissionDecision.denied('当前安全 Profile 不允许访问宿主业务 API');
    }
    if (!supportsDeclarativeRuntime(installation)) {
      return const ModPermissionDecision.denied('Runtime 未通过平台支持检查');
    }

    final manifestJson = installation['manifestJson'];
    if (manifestJson is! String) {
      return const ModPermissionDecision.denied('安装记录缺少原始 Manifest');
    }
    Map<String, dynamic> manifest;
    try {
      final decoded = jsonDecode(manifestJson);
      if (decoded is! Map) throw const FormatException('Manifest 根节点无效');
      manifest = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return const ModPermissionDecision.denied('Manifest 数据损坏');
    }
    if (manifest['id'] != session.modId ||
        manifest['version'] != installation['installedVersion']) {
      return const ModPermissionDecision.denied('Manifest 身份或版本与安装记录不一致');
    }
    final manifestVersion = manifest['manifestVersion'];
    final isLegacy = manifest['manifestVersion'] != 1;
    if (isLegacy && manifest.keys.any((key) => !const {
      'schemaVersion', 'id', 'name', 'version', 'description',
      'permissions', 'dependencies', 'taskTemplates', 'minHostVersion',
    }.contains(key))) {
      return const ModPermissionDecision.denied('旧版 Manifest 不允许混入 V1 或未知字段');
    }
    if (!isLegacy && manifestVersion != 1) {
      return const ModPermissionDecision.denied('Manifest 版本不受支持');
    }

    // V1 installations store a host-owned registry projection in
    // manifestJson. Validate and authorize against the original validated
    // sourceManifest, while keeping taskTemplates from the projection for the
    // final payload membership check.
    final authorizationManifest = <String, dynamic>{};
    if (!isLegacy) {
      final sourceManifest = manifest['sourceManifest'];
      if (sourceManifest is! Map) {
        return const ModPermissionDecision.denied('安装记录缺少原始 V1 Manifest');
      }
      authorizationManifest.addAll(Map<String, dynamic>.from(sourceManifest));
      try {
        ModManifestV1Validator().parse(jsonEncode(authorizationManifest));
      } catch (_) {
        return const ModPermissionDecision.denied('Manifest V1 校验失败');
      }
    } else {
      authorizationManifest.addAll(manifest);
    }

    if (!isLegacy && authorizationManifest['contentKind'] != 'task_template') {
      return const ModPermissionDecision.denied('只有 task_template 可以请求任务创建 API');
    }

    final publisher = authorizationManifest['publisher'];
    if (!isLegacy &&
        (publisher is! Map || publisher['id'] != installation['publisherId'])) {
      return const ModPermissionDecision.denied('Manifest Publisher 与安装记录不一致');
    }
    if (isLegacy && installation['publisherId'] != 'local.legacy') {
      return const ModPermissionDecision.denied('旧版 Manifest 只能由本地兼容 Publisher 使用');
    }

    if (!isLegacy) {
      const hostCapabilities = {
        'host.data.tasks.read', 'host.data.habits.read',
        'host.data.checkins.read', 'host.data.time_records.read',
        'host.data.diary.read', 'host.data.mood.read',
        'host.tasks.create', 'host.tasks.update_limited',
        'host.habits.create', 'host.habits.check_in',
      };
      const egressCapabilities = {
        'network.fetch', 'host.external_link.open',
        'host.ui.notification', 'host.ui.home_widget',
        'mods.message.send', 'mods.message.subscribe',
      };
      final permissions = authorizationManifest['permissions'];
      final requested = permissions is List
          ? permissions
              .whereType<Map>()
              .map((item) => item['capability'])
              .whereType<String>()
              .toSet()
          : <String>{};
      if (requested.any(hostCapabilities.contains) &&
          requested.any(egressCapabilities.contains)) {
        return const ModPermissionDecision.denied('宿主能力与外发能力不能混合');
      }
    }

    final declared = _declaredPermission(authorizationManifest, capability, isLegacy);
    if (declared == null) {
      return const ModPermissionDecision.denied('Manifest 未声明此 capability');
    }
    if (payload.isNotEmpty && !_matchesTaskTemplate(manifest, payload)) {
      return const ModPermissionDecision.denied('请求内容不属于此 MOD 声明的任务模板');
    }

    final grants = (installation['grantedPermissions'] as List? ?? const [])
        .whereType<String>()
        .toSet();
    final hasUserGrant = grants.contains(capability) ||
        (isLegacy && capability == 'host.tasks.create' && grants.contains('tasks.create'));
    if (!hasUserGrant) {
      return const ModPermissionDecision.denied('用户尚未授予此权限');
    }

    final approvalRequest = ModApprovalRequest(
      ownerId: _store.ownerId,
      installationId: session.installationId,
      modId: session.modId,
      publisherId: installation['publisherId'] as String,
      version: installation['installedVersion'] as String,
      packageSha256: installation['packageSha256'] as String?,
      capability: capability,
    );
    Set<String> approved;
    try {
      approved = await _approvalProvider.approvedCapabilities(approvalRequest);
    } catch (_) {
      return const ModPermissionDecision.denied('平台审批状态不可用，已按拒绝处理');
    }
    if (!approved.contains(capability)) {
      return const ModPermissionDecision.denied('此 capability 尚未获得平台管理员审批');
    }

    final scope = declared['scope'];
    if (scope is Map) {
      final operations = scope['operations'];
      if (operations is List && !operations.contains('create')) {
        return const ModPermissionDecision.denied('管理员或用户授权范围不包含 create 操作');
      }
      final fields = scope['fields'];
      if (fields is List && !fields.whereType<String>().toSet().containsAll(payload.keys)) {
        return const ModPermissionDecision.denied('请求字段超出授权 Scope');
      }
    }
    if (!isLegacy && !session.verifiedRuntime) {
      return const ModPermissionDecision.denied(
        'V1 Host API Session 必须来自已验证的 Declarative Runtime',
      );
    }
    return ModPermissionDecision.allowed(installation);
  }

  bool _matchesTaskTemplate(
    Map<String, dynamic> manifest,
    Map<String, dynamic> payload,
  ) {
    final templates = manifest['taskTemplates'];
    if (templates is! List) return false;
    return templates.any((item) {
      if (item is! Map) return false;
      return item['title'] == payload['title'] &&
          (item['note'] ?? '').toString() == (payload['note'] ?? '').toString() &&
          item['targetCount'] == payload['targetCount'] &&
          item['importance'] == payload['importance'] &&
          item['difficulty'] == payload['difficulty'];
    });
  }

  Map<String, dynamic>? _declaredPermission(
    Map<String, dynamic> manifest,
    String capability,
    bool isLegacy,
  ) {
    final permissions = manifest['permissions'];
    if (permissions is! List) return null;
    if (isLegacy) {
      if (capability == 'host.tasks.create' && permissions.contains('tasks.create')) {
        return const <String, dynamic>{};
      }
      return null;
    }
    for (final item in permissions) {
      if (item is Map && item['capability'] == capability) {
        return Map<String, dynamic>.from(item);
      }
    }
    return null;
  }

  bool supportsDeclarativeRuntime(Map<String, dynamic> installation) {
    final runtime = installation['runtime'];
    if (runtime is Map) return runtime['type'] == 'declarative';
    // Temporary compatibility only for the pre-V1 task-template registry.
    return installation['schemaVersion'] == 1 &&
        installation['taskTemplates'] is List;
  }

  Future<Map<String, dynamic>?> findInstallation(String modId) async {
    final installations = await _store.listInstallations();
    for (final installation in installations) {
      if (installation['installedModId'] == modId) return installation;
    }
    return null;
  }

  Future<bool> isGloballyEnabled() async {
    try {
      return await _globalModsEnabled();
    } catch (_) {
      return false;
    }
  }

}
