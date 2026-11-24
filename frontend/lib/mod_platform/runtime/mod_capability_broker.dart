import 'dart:convert';
import 'dart:math';

import '../../data/local/local_plan_repository.dart';
import 'mod_permission_policy.dart';
import '../storage/mod_platform_store.dart';
import 'mod_runtime_session.dart';

export 'mod_permission_policy.dart' show DenyAllModApprovalProvider, ModApprovalProvider, ModApprovalRequest;

class ModCapabilityDeniedException extends StateError {
  ModCapabilityDeniedException(super.message);
}

class ModUserConsent {
  const ModUserConsent._({
    required this.nonce,
    required this.sessionId,
    required this.installationId,
    required this.capability,
    required this.payloadFingerprint,
    required this.expiresAt,
  });

  final String nonce;
  final String sessionId;
  final String installationId;
  final String capability;
  final String payloadFingerprint;
  final DateTime expiresAt;
}

class ModHostApiResult {
  const ModHostApiResult({required this.requestId, required this.status});

  final String requestId;
  final String status;
}

/// The only Host API operation implemented in P0-3/H1.
/// It returns no task row, database ID, or other host record.
class ModHostApi {
  ModHostApi._(this._repository, this._random, this._sessionManager);

  final LocalPlanRepository _repository;
  final Random _random;
  final ModRuntimeSessionManager _sessionManager;

  Future<ModHostApiResult> createTask({
    required ModRuntimeSession session,
    required Map<String, dynamic> payload,
  }) async {
    const allowedKeys = {
      'title',
      'note',
      'targetCount',
      'importance',
      'difficulty',
    };
    if (payload.keys.any((key) => !allowedKeys.contains(key))) {
      throw const FormatException('host.tasks.create 包含未允许的字段');
    }

    final title = payload['title'];
    final note = payload['note'] ?? '';
    final targetCount = payload['targetCount'];
    final importance = payload['importance'];
    final difficulty = payload['difficulty'];
    if (title is! String || title.trim().isEmpty || title.trim().length > 100 ||
        note is! String || note.length > 500 ||
        targetCount is! int || targetCount < 1 || targetCount > 999 ||
        importance is! int || importance < 1 || importance > 5 ||
        difficulty is! int || difficulty < 1 || difficulty > 5) {
      throw const FormatException('host.tasks.create 参数不合法');
    }

    await _repository.createTaskFromMod(
      installationId: session.installationId,
      modId: session.modId,
      isSessionActive: () => _sessionManager.isActive(session),
      title: title,
      note: note,
      targetCount: targetCount,
      importance: importance,
      difficulty: difficulty,
    );

    return ModHostApiResult(
      requestId: _randomToken(),
      status: 'created',
    );
  }

  String _randomToken() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }
}

/// All MOD-to-host calls pass through this broker. It re-reads local authority
/// for every operation and asks the trusted approval provider on every call.
class ModCapabilityBroker {
  ModCapabilityBroker.forRepository(
    LocalPlanRepository repository, {
    ModApprovalProvider approvalProvider = const DenyAllModApprovalProvider(),
    ModRuntimeSessionManager? sessionManager,
    Future<bool> Function()? globalModsEnabled,
    DateTime Function()? clock,
    Random? random,
  }) : _store = ModPlatformStore(
         database: repository.localDatabase,
         ownerId: repository.modOwnerId,
       ),
       _sessionManager = sessionManager ?? ModRuntimeSessionManager.instance,
       _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure() {
    final enabled = globalModsEnabled ??
        (() async => await repository.getAppSetting('mods.enabled.v1') != 'false');
    _policy = ModPermissionPolicy(
      store: _store,
      approvalProvider: approvalProvider,
      sessionManager: _sessionManager,
      globalModsEnabled: enabled,
    );
    _hostApi = ModHostApi._(repository, _random, _sessionManager);
  }

  final ModPlatformStore _store;
  final ModRuntimeSessionManager _sessionManager;
  late final ModPermissionPolicy _policy;
  final DateTime Function() _clock;
  final Random _random;
  late final ModHostApi _hostApi;
  final Map<String, ModUserConsent> _pendingConsents = {};

  Future<ModRuntimeSession> openSession(String modId) async {
    if (!await _policy.isGloballyEnabled()) {
      throw ModCapabilityDeniedException('MOD 功能已关闭');
    }
    final installation = await _policy.findInstallation(modId);
    if (installation == null ||
        installation['installedModId'] != modId ||
        installation['status'] != 'installed' ||
        installation['enabled'] != true ||
        installation['effectiveProfile'] != 'host_integrated_offline') {
      throw ModCapabilityDeniedException('MOD 未安装、未启用或需要重新授权');
    }
    if (!_policy.supportsDeclarativeRuntime(installation)) {
      throw ModCapabilityDeniedException('当前平台尚未支持此 MOD Runtime');
    }
    if (installation['isV1Package'] == true) {
      throw ModCapabilityDeniedException(
        'V1 Host API Session 必须由已验证的 Declarative Runtime 创建',
      );
    }
    return _sessionManager.open(
      ownerId: _store.ownerId,
      installationId: installation['installationId'] as String,
      modId: modId,
    );
  }

  /// Called by trusted host UI only after the user confirms the operation.
  /// The resulting one-shot token is bound to one session, capability and exact payload.
  Future<ModUserConsent> issueUserConsent({
    required ModRuntimeSession session,
    required String capability,
    required Map<String, dynamic> payload,
  }) async {
    final decision = await _policy.authorize(session, capability, payload);
    if (!decision.isAllowed) {
      await _recordDenied(session, capability);
      throw ModCapabilityDeniedException(decision.reason ?? '权限检查失败');
    }
    final now = _clock().toUtc();
    _pendingConsents.removeWhere((_, value) => !value.expiresAt.isAfter(now));
    final consent = ModUserConsent._(
      nonce: _randomToken(),
      sessionId: session.sessionId,
      installationId: session.installationId,
      capability: capability,
      payloadFingerprint: _fingerprintPayload(payload),
      expiresAt: now.add(const Duration(seconds: 30)),
    );
    _pendingConsents[consent.nonce] = consent;
    return consent;
  }

  Future<ModHostApiResult> invoke({
    required ModRuntimeSession session,
    required String capability,
    required Map<String, dynamic> payload,
    required ModUserConsent consent,
  }) async {
    final pending = _pendingConsents.remove(consent.nonce);
    if (pending == null ||
        pending.sessionId != session.sessionId ||
        pending.installationId != session.installationId ||
        pending.capability != capability ||
        pending.payloadFingerprint != _fingerprintPayload(payload) ||
        consent.sessionId != session.sessionId ||
        consent.installationId != session.installationId ||
        consent.capability != capability ||
        consent.payloadFingerprint != _fingerprintPayload(payload) ||
        !consent.expiresAt.isAfter(_clock().toUtc())) {
      await _recordDenied(session, capability);
      throw ModCapabilityDeniedException('用户确认凭据无效、过期或已经使用');
    }

    final decision = await _policy.authorize(session, capability, payload);
    if (!decision.isAllowed) {
      await _recordDenied(session, capability);
      throw ModCapabilityDeniedException(decision.reason ?? '权限检查失败');
    }

    if (capability != 'host.tasks.create') {
      await _recordDenied(session, capability);
      throw ModCapabilityDeniedException('当前仅开放 host.tasks.create');
    }

    try {
      return await _hostApi.createTask(session: session, payload: payload);
    } catch (_) {
      await _recordFailure(session, capability);
      rethrow;
    }
  }

  Future<void> _recordDenied(ModRuntimeSession session, String capability) async {
    try {
      await _store.recordCapabilityInvocation(
        modId: session.modId,
        installationId: session.installationId,
        capability: capability,
        result: 'denied',
      );
    } catch (_) {
      // Authorization denial must not be reversed by an audit-store failure.
    }
  }

  Future<void> _recordFailure(ModRuntimeSession session, String capability) async {
    try {
      await _store.recordCapabilityInvocation(
        modId: session.modId,
        installationId: session.installationId,
        capability: capability,
        result: 'error',
      );
    } catch (_) {
      // Do not leak request data into logs or change the Host API result.
    }
  }

  String _fingerprintPayload(Map<String, dynamic> payload) {
    final entries = payload.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    return jsonEncode({for (final entry in entries) entry.key: entry.value});
  }

  String _randomToken() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }
}
