import '../../data/local/local_plan_repository.dart';
import '../../services/mod_registry.dart';
import '../storage/mod_platform_store.dart';
import 'declarative_mod_runtime.dart';
import 'mod_runtime_session.dart';

class ModRuntimeUnavailable extends StateError {
  ModRuntimeUnavailable(super.message);
}

enum ModExecutionState { running, suspended, stopped }

/// Host-owned handle; no third-party code receives a Dart object or SQL handle.
class ModRuntimeInstance {
  ModRuntimeInstance._(this.definition, this._session);

  final DeclarativeModDefinition definition;
  ModRuntimeSession _session;
  ModExecutionState _state = ModExecutionState.running;

  ModExecutionState get state => _state;
  ModRuntimeSession get session => _session;
  String get modId => definition.modId;
  String get installationId => definition.installationId;
}

/// Declarative runtime for legacy templates and verified V1 task-template
/// packages. V1 content is reloaded and revalidated from disk before use. This
/// runtime interprets data only; it has no third-party code execution engine,
/// network client, WebView or WASM runtime.
///
/// Creating a runtime session is NOT permission approval. Host calls continue
/// through ModCapabilityBroker. Production host surfaces inject the online
/// platform-proof provider; the broker itself still defaults to deny-all.
class ModRuntimeManager {
  ModRuntimeManager.forRepository(
    LocalPlanRepository repository, {
    ModRuntimeSessionManager? sessionManager,
    Future<bool> Function()? globalModsEnabled,
  }) : _store = ModPlatformStore(
         database: repository.localDatabase,
         ownerId: repository.modOwnerId,
       ),
       _sessionManager = sessionManager ?? ModRuntimeSessionManager.instance,
       _registry = ModRegistry(
         repository,
         sessionManager: sessionManager ?? ModRuntimeSessionManager.instance,
       ),
       _globalModsEnabled = globalModsEnabled ??
           (() async =>
               await repository.getAppSetting('mods.enabled.v1') != 'false');

  final ModPlatformStore _store;
  final ModRuntimeSessionManager _sessionManager;
  final ModRegistry _registry;
  final Future<bool> Function() _globalModsEnabled;
  final Map<String, ModRuntimeInstance> _active = {};
  bool _closed = false;

  bool isRunning(ModRuntimeInstance instance) =>
      !_closed &&
      identical(_active[instance.installationId], instance) &&
      instance.state == ModExecutionState.running &&
      _sessionManager.isActive(instance.session);

  /// Discover only templates already granted by the user. No session or host
  /// capability is created during discovery, and invalid installs are skipped.
  Future<List<Map<String, dynamic>>> listAvailableTaskTemplates() async {
    if (_closed || !await _isGloballyEnabled()) return const [];
    final installs = await _store.listInstallations();
    final results = <Map<String, dynamic>>[];
    for (final installation in installs) {
      if (installation['enabled'] != true ||
          installation['status'] != 'installed') {
        continue;
      }
      final grants = (installation['grantedPermissions'] as List? ?? const [])
          .whereType<String>()
          .toSet();
      final requiredCapability = installation['isV1Package'] == true
          ? 'host.tasks.create'
          : 'tasks.create';
      if (!grants.contains(requiredCapability)) continue;
      try {
        final definition = await DeclarativeModDefinition.loadFromInstallation(
          installation,
          _registry,
        );
        if (!_dependenciesReady(definition, installs)) continue;
        for (final template in definition.taskTemplates) {
          results.add({
            ...template.payload,
            'templateIndex': template.index,
            'modId': definition.modId,
            'modName': definition.name,
            'installationId': definition.installationId,
            'publisherId': definition.publisherId,
            'effectiveProfile': definition.effectiveProfile,
          });
        }
      } on FormatException {
        // Corrupt/mismatched installs never become executable.
      } on UnsupportedError {
        // Bare or unsupported V1 metadata never enters the Runtime.
      } on Exception {
        // Missing, unreadable or mismatched package files fail closed.
      }
    }
    return results;
  }

  Future<ModRuntimeInstance> start(String modId) async {
    _ensureOpen();
    final installs = await _store.listInstallations();
    if (!await _isGloballyEnabled()) {
      throw ModRuntimeUnavailable('MOD 总开关已关闭');
    }
    final installation = _findInstalled(installs, modId);
    final definition = await DeclarativeModDefinition.loadFromInstallation(
      installation,
      _registry,
    );
    if (!_dependenciesReady(definition, installs)) {
      throw ModRuntimeUnavailable('MOD 依赖未安装或未启用');
    }
    // End the prior invocation of the same installation only after all checks.
    final previous = _active.remove(definition.installationId);
    if (previous != null) {
      previous._state = ModExecutionState.stopped;
      _sessionManager.terminateInstallation(previous.installationId);
    }
    final session = _sessionManager.open(
      ownerId: _store.ownerId,
      installationId: definition.installationId,
      modId: definition.modId,
      verifiedRuntime: true,
    );
    final instance = ModRuntimeInstance._(definition, session);
    _active[definition.installationId] = instance;
    try {
      // A disable, account switch or upgrade may race with startup.
      await _requireRunning(instance);
      return instance;
    } catch (_) {
      stop(instance);
      rethrow;
    }
  }

  /// Revalidate every operation against the persisted installation, including
  /// its exact Manifest and version. A same-installation upgrade cannot silently
  /// change the task that was confirmed in an already-open runtime.
  Future<Map<String, dynamic>> taskPayload(
    ModRuntimeInstance instance,
    int templateIndex,
  ) async {
    final installation = await _requireRunning(instance);
    final grants = (installation['grantedPermissions'] as List? ?? const [])
        .whereType<String>()
        .toSet();
    final requiredCapability = installation['isV1Package'] == true
        ? 'host.tasks.create'
        : 'tasks.create';
    if (!grants.contains(requiredCapability)) {
      throw ModRuntimeUnavailable('用户未授权创建任务');
    }
    final templates = instance.definition.taskTemplates;
    if (templateIndex < 0 || templateIndex >= templates.length) {
      throw RangeError.index(templateIndex, templates, 'templateIndex');
    }
    return Map<String, dynamic>.unmodifiable(templates[templateIndex].payload);
  }

  /// Optional self-contained storage, never host records. The store separately
  /// checks the storage.local grant, quota and owner namespace for each call.
  Future<Object?> readStorage(ModRuntimeInstance instance, String key) async {
    await _requireRunning(instance);
    final result = await _store.readStorageValue(instance.modId, key);
    await _requireRunning(instance);
    return result;
  }

  Future<void> writeStorage(
    ModRuntimeInstance instance,
    String key,
    Object? value,
  ) async {
    await _requireRunning(instance);
    await _store.writeStorageValue(instance.modId, key, value);
    await _requireRunning(instance);
  }

  Future<void> deleteStorage(ModRuntimeInstance instance, String key) async {
    await _requireRunning(instance);
    await _store.deleteStorageValue(instance.modId, key);
    await _requireRunning(instance);
  }

  void suspend(ModRuntimeInstance instance) {
    if (!isRunning(instance)) {
      throw ModRuntimeUnavailable('MOD Runtime 已失效');
    }
    _sessionManager.terminateInstallation(instance.installationId);
    instance._state = ModExecutionState.suspended;
  }

  Future<void> resume(ModRuntimeInstance instance) async {
    _ensureOpen();
    if (instance.state != ModExecutionState.suspended ||
        !identical(_active[instance.installationId], instance)) {
      throw ModRuntimeUnavailable('MOD Runtime 不可恢复');
    }
    await _validateInstallation(instance);
    instance._session = _sessionManager.open(
      ownerId: _store.ownerId,
      installationId: instance.installationId,
      modId: instance.modId,
      verifiedRuntime: true,
    );
    instance._state = ModExecutionState.running;
  }

  /// Releases only a runtime owned by this manager. Stale handles cannot kill
  /// newer sessions created for the same installation.
  void stop(ModRuntimeInstance instance) {
    if (!identical(_active[instance.installationId], instance)) {
      instance._state = ModExecutionState.stopped;
      return;
    }
    _active.remove(instance.installationId);
    // Another host surface may have opened a newer session for the same MOD.
    // Never invalidate that different session from a stale UI handle.
    if (_sessionManager.isActive(instance.session)) {
      _sessionManager.terminateInstallation(instance.installationId);
    }
    instance._state = ModExecutionState.stopped;
  }

  /// To be called when the host UI is disposed or the active account changes.
  void shutdown() {
    if (_closed) return;
    for (final instance in _active.values.toList()) {
      stop(instance);
    }
    _closed = true;
  }

  Future<Map<String, dynamic>> _requireRunning(
    ModRuntimeInstance instance,
  ) async {
    if (!isRunning(instance)) {
      throw ModRuntimeUnavailable('MOD Runtime Session 已过期或失效');
    }
    final installation = await _validateInstallation(instance);
    if (!isRunning(instance)) {
      throw ModRuntimeUnavailable('MOD Runtime Session 已在操作期间失效');
    }
    return installation;
  }

  Future<Map<String, dynamic>> _validateInstallation(
    ModRuntimeInstance instance,
  ) async {
    _ensureOpen();
    if (!await _isGloballyEnabled()) {
      throw ModRuntimeUnavailable('MOD 总开关已关闭');
    }
    final installs = await _store.listInstallations();
    final installation = _findInstalled(installs, instance.modId);
    final definition = await DeclarativeModDefinition.loadFromInstallation(
      installation,
      _registry,
    );
    if (definition.installationId != instance.installationId ||
        definition.version != instance.definition.version ||
        definition.manifestJson != instance.definition.manifestJson ||
        definition.effectiveProfile != instance.definition.effectiveProfile ||
        !_dependenciesReady(definition, installs)) {
      throw ModRuntimeUnavailable('MOD 安装版本、权限边界或依赖已变化');
    }
    return installation;
  }

  Map<String, dynamic> _findInstalled(
    List<Map<String, dynamic>> installations,
    String modId,
  ) {
    for (final installation in installations) {
      if (installation['installedModId'] == modId &&
          installation['enabled'] == true &&
          installation['status'] == 'installed') {
        return installation;
      }
    }
    throw ModRuntimeUnavailable('MOD 未安装、已禁用或需要重新授权');
  }

  bool _dependenciesReady(
    DeclarativeModDefinition definition,
    List<Map<String, dynamic>> installations,
  ) {
    for (final dependencyId in definition.dependencies) {
      if (!installations.any((installed) =>
          installed['installedModId'] == dependencyId &&
          installed['enabled'] == true &&
          installed['status'] == 'installed')) {
        return false;
      }
    }
    return true;
  }

  Future<bool> _isGloballyEnabled() async {
    try {
      return await _globalModsEnabled();
    } catch (_) {
      return false;
    }
  }

  void _ensureOpen() {
    if (_closed) throw ModRuntimeUnavailable('Runtime Manager 已关闭');
  }
}
