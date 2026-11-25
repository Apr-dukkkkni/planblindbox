import 'dart:convert';

import '../data/local/local_plan_repository.dart';
import '../mod_platform/storage/mod_platform_store.dart';
import '../mod_platform/runtime/mod_runtime_session.dart';
import '../mod_platform/package/mod_package_models.dart';
import '../mod_platform/package/mod_package_importer_stub.dart'
    if (dart.library.io) '../mod_platform/package/mod_package_importer_io.dart'
    as package_importer;

/// Transitional declaration-only registry backed by normalized, account-scoped
/// MOD tables. It does not load or execute third-party code.
class ModRegistry {
  ModRegistry(
    LocalPlanRepository repository, {
    ModRuntimeSessionManager? sessionManager,
  }) : _store = ModPlatformStore(
         database: repository.localDatabase,
         ownerId: repository.modOwnerId,
       ),
       _sessionManager = sessionManager ?? ModRuntimeSessionManager.instance;

  final ModPlatformStore _store;
  final ModRuntimeSessionManager _sessionManager;
  // 必须与 frontend/pubspec.yaml 的主版本同步；当前应用版本 0.1.0+1。
  static const hostVersion = '0.1.0';
  static const allowedPermissions = {'tasks.create'};
  static const maxMods = 30;
  static const maxManifestBytes = 64 * 1024;

  Future<List<Map<String, dynamic>>> list() => _store.listInstallations();

  int get ownerId => _store.ownerId;

  Future<List<Map<String, dynamic>>> audit() => _store.auditEvents();

  /// Checks registry policy before the ZIP installer replaces an on-disk package.
  /// V1 packages are catalogued but remain disabled and receive no grants.
  Future<void> validateV1PackageInstall(ModValidatedPackage package) async {
    final manifest = package.manifest;
    if (manifest['manifestVersion'] != 1 ||
        manifest['type'] != 'content' ||
        manifest['contentKind'] != 'task_template') {
      throw const FormatException('当前只允许安装 V1 task_template 内容包');
    }
    final id = manifest['id'] as String;
    final version = manifest['version'] as String;
    final publisherId =
        (manifest['publisher'] as Map<String, dynamic>)['id'] as String;
    final installed = await list();
    final current = installed.where((item) => item['id'] == id).toList();
    if (current.isEmpty && installed.length >= maxMods) {
      throw const FormatException('最多安装 30 个 Mod');
    }
    if (current.isNotEmpty && current.first['publisherId'] != publisherId) {
      throw const FormatException('Publisher ID 与当前安装不一致；请先卸载旧 MOD 再安装');
    }
    if (current.isNotEmpty &&
        _compareSemVer(version, current.first['version'] as String) <= 0) {
      throw const FormatException('升级版本必须高于当前已安装版本');
    }
  }

  /// Re-reads the installed V1 package from disk and verifies every file.
  /// The returned templates are fresh validated bytes, not cached DB content.
  Future<ModValidatedPackage> loadV1PackageContents(
    Map<String, dynamic> installation,
  ) async {
    if (installation['isV1Package'] != true) {
      throw const FormatException('指定安装记录不是 V1 内容包');
    }
    return package_importer.loadV1PackageContents(
      ownerId: ownerId,
      installation: installation,
    );
  }

  /// Persists a validated V1 package as a disabled catalog entry. The stored
  /// manifest is a host-owned registry projection; sourceManifest preserves
  /// the exact validated V1 fields without coercing them into the legacy schema.
  Future<void> installV1Package({
    required ModValidatedPackage package,
    required String modId,
    required String version,
    required String packageDirectory,
    required String archiveSha256,
  }) async {
    if (package.manifest['id'] != modId ||
        package.manifest['version'] != version ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(archiveSha256)) {
      throw const FormatException('安装结果与 V1 Manifest 身份或摘要不匹配');
    }
    await validateV1PackageInstall(package);
    final manifest = package.manifest;
    final localizedNames = Map<String, dynamic>.from(manifest['name'] as Map);
    final name = _selectLocalizedName(localizedNames);
    final permissionObjects = (manifest['permissions'] as List)
        .cast<Map<String, dynamic>>();
    final declaredPermissions = permissionObjects
        .map((permission) => permission['capability'] as String)
        .toList(growable: false);
    final dependencies = (manifest['dependencies'] as List? ?? const [])
        .cast<String>();
    final internalRecord = <String, dynamic>{
      'schemaVersion': 1,
      'manifestVersion': 1,
      'isV1Package': true,
      'runtimeReady': false,
      'id': modId,
      'name': name,
      'nameLocales': localizedNames,
      'version': version,
      'description': manifest['description'] ?? '',
      'publisher': Map<String, dynamic>.from(manifest['publisher'] as Map),
      // Keep the full V1 permission objects. The scope/required metadata is
      // part of the authorization contract and must not be flattened away.
      'permissions': permissionObjects,
      'declaredPermissions': declaredPermissions,
      'dependencies': dependencies,
      'taskTemplates': package.taskTemplates.templates,
      'contentKind': manifest['contentKind'],
      'runtime': Map<String, dynamic>.from(manifest['runtime'] as Map),
      'packageDirectory': packageDirectory,
      'packageSha256': archiveSha256,
      'fileDigests': package.fileDigests,
      'sourceManifest': manifest,
    };
    final publisherId =
        (manifest['publisher'] as Map<String, dynamic>)['id'] as String;
    final profile = declaredPermissions.any((capability) =>
            capability.startsWith('host.'))
        ? 'host_integrated_offline'
        : declaredPermissions.any((capability) =>
                capability == 'network.fetch' ||
                capability.startsWith('mods.message.'))
            ? 'standalone_networked'
            : 'standalone_offline';

    await _store.installOrUpgrade(
      modId: modId,
      publisherId: publisherId,
      version: version,
      manifestJson: jsonEncode(internalRecord),
      effectiveProfile: profile,
      grantedPermissions: const <String>{},
      packageSha256: archiveSha256,
      storageQuotaBytes: 0,
      enabledAfterInstall: false,
    );
  }

  static String _selectLocalizedName(Map<String, dynamic> names) {
    for (final locale in const ['zh-CN', 'zh-Hans', 'zh', 'en']) {
      final value = names[locale];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    for (final value in names.values) {
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    throw const FormatException('V1 Manifest 缺少可用名称');
  }

  static int _compareSemVer(String left, String right) {
    String withoutBuild(String value) => value.split('+').first;
    final a = withoutBuild(left).split('-');
    final b = withoutBuild(right).split('-');
    final av = a.first.split('.').map(int.parse).toList();
    final bv = b.first.split('.').map(int.parse).toList();
    for (var i = 0; i < 3; i++) {
      final comparison = av[i].compareTo(bv[i]);
      if (comparison != 0) return comparison;
    }
    if (a.length == 1 && b.length > 1) return 1;
    if (a.length > 1 && b.length == 1) return -1;
    if (a.length == 1 && b.length == 1) return 0;
    final ap = a[1].split('.');
    final bp = b[1].split('.');
    for (var i = 0; i < ap.length && i < bp.length; i++) {
      final an = int.tryParse(ap[i]);
      final bn = int.tryParse(bp[i]);
      final comparison = an != null && bn != null
          ? an.compareTo(bn)
          : an != null
              ? -1
              : bn != null
                  ? 1
                  : ap[i].compareTo(bp[i]);
      if (comparison != 0) return comparison;
    }
    return ap.length.compareTo(bp.length);
  }

  /// No code loading; only a host-defined task-template contribution is supported.
  Map<String, dynamic> parseManifest(String raw) {
    if (utf8.encode(raw).length > maxManifestBytes) {
      throw const FormatException('清单不能超过 64 KB');
    }
    final value = jsonDecode(raw);
    if (value is! Map) throw const FormatException('清单必须是 JSON 对象');
    final manifest = Map<String, dynamic>.from(value);
    const keys = {
      'schemaVersion',
      'id',
      'name',
      'version',
      'description',
      'permissions',
      'dependencies',
      'taskTemplates',
      'minHostVersion',
    };
    if (manifest.keys.any((k) => !keys.contains(k))) {
      throw const FormatException('存在未知字段或不受支持的扩展能力');
    }
    if (manifest['schemaVersion'] != 1) {
      throw const FormatException('仅支持 schemaVersion = 1');
    }
    final id = manifest['id'];
    final name = manifest['name'];
    final version = manifest['version'];
    if (id is! String ||
        !RegExp(r'^[a-z][a-z0-9]*(\.[a-z][a-z0-9-]*)+$').hasMatch(id) ||
        id.length > 100) {
      throw const FormatException('id 必须使用反向域名格式，例如 com.example.study');
    }
    if (name is! String || name.trim().isEmpty || name.length > 60) {
      throw const FormatException('名称不能为空且最长 60 字符');
    }
    if (version is! String ||
        !RegExp(r'^\d{1,6}\.\d{1,6}\.\d{1,6}$').hasMatch(version)) {
      throw const FormatException('版本必须为 major.minor.patch');
    }
    final minHostVersion = manifest['minHostVersion'];
    if (minHostVersion != null) {
      if (minHostVersion is! String ||
          !RegExp(r'^\d{1,6}\.\d{1,6}\.\d{1,6}$').hasMatch(minHostVersion)) {
        throw const FormatException('minHostVersion 必须为 x.y.z，且每段最多 6 位');
      }
      if (_compareVersions(hostVersion, minHostVersion) < 0) {
        throw FormatException(
          '此 Mod 需要应用版本 $minHostVersion 或更高，当前为 $hostVersion',
        );
      }
    }
    final description = manifest['description'] ?? '';
    if (description is! String || description.length > 300) {
      throw const FormatException('描述最长 300 字符');
    }
    final perms = manifest['permissions'] ?? <dynamic>[];
    final deps = manifest['dependencies'] ?? <dynamic>[];
    final templates = manifest['taskTemplates'] ?? <dynamic>[];
    if (perms is! List ||
        perms.length > 10 ||
        perms.any((p) => p is! String || !allowedPermissions.contains(p)) ||
        perms.toSet().length != perms.length) {
      throw const FormatException('包含不支持或重复的权限');
    }
    if (deps is! List ||
        deps.length > 10 ||
        deps.any(
          (d) =>
              d is! String ||
              d == id ||
              !RegExp(r'^[a-z][a-z0-9]*(\.[a-z][a-z0-9-]*)+$').hasMatch(d),
        ) ||
        deps.toSet().length != deps.length) {
      throw const FormatException('依赖必须是其他 Mod 的 ID，不得重复');
    }
    if (templates is! List || templates.length > 20) {
      throw const FormatException('最多只能声明 20 个任务模板');
    }
    if (templates.isNotEmpty && !perms.contains('tasks.create')) {
      throw const FormatException('任务模板必须声明 tasks.create 权限');
    }
    final cleanTemplates = <Map<String, dynamic>>[];
    for (final rawTemplate in templates) {
      if (rawTemplate is! Map) throw const FormatException('模板应为对象');
      final item = Map<String, dynamic>.from(rawTemplate);
      if (item.keys.any(
        (k) => !{
          'title',
          'note',
          'targetCount',
          'importance',
          'difficulty',
        }.contains(k),
      )) {
        throw const FormatException('任务模板存在未知字段');
      }
      final title = item['title'];
      final note = item['note'] ?? '';
      final target = item['targetCount'] ?? 1;
      final importance = item['importance'] ?? 3;
      final difficulty = item['difficulty'] ?? 3;
      if (title is! String ||
          title.trim().isEmpty ||
          title.length > 100 ||
          note is! String ||
          note.length > 500 ||
          target is! int ||
          target < 1 ||
          target > 999 ||
          importance is! int ||
          importance < 1 ||
          importance > 5 ||
          difficulty is! int ||
          difficulty < 1 ||
          difficulty > 5) {
        throw const FormatException('任务模板参数不合法');
      }
      cleanTemplates.add({
        'title': title.trim(),
        'note': note,
        'targetCount': target,
        'importance': importance,
        'difficulty': difficulty,
      });
    }
    return {
      'schemaVersion': 1,
      'id': id,
      'name': name.trim(),
      'version': version,
      'description': description,
      if (minHostVersion != null) 'minHostVersion': minHostVersion,
      'permissions': List<String>.from(perms),
      'dependencies': List<String>.from(deps),
      'taskTemplates': cleanTemplates,
    };
  }

  static int _compareVersions(String x, String y) {
    final a = x.split('.').map(int.parse).toList();
    final b = y.split('.').map(int.parse).toList();
    for (var i = 0; i < 3; i++) {
      final c = a[i].compareTo(b[i]);
      if (c != 0) return c;
    }
    return 0;
  }

  Future<void> install(
    String raw, {
    required Set<String> grantedPermissions,
  }) async {
    final manifest = parseManifest(raw);
    final declared = (manifest['permissions'] as List).cast<String>().toSet();
    if (!declared.containsAll(grantedPermissions)) {
      throw const FormatException('授权不能超出声明权限');
    }
    final old = await list();
    final id = manifest['id'] as String;
    final current = old.where((m) => m['id'] == id).toList();
    if (current.isEmpty && old.length >= maxMods) {
      throw const FormatException('最多安装 30 个 Mod');
    }
    if (current.isNotEmpty && current.first['isV1Package'] == true) {
      throw const FormatException('不能使用旧版 JSON 清单覆盖 V1 内容包；请先卸载 V1 包');
    }
    if (current.isNotEmpty) {
      final comparison = _compareVersions(
        manifest['version'] as String,
        current.first['version'] as String,
      );
      final restored = current.first['status'] == 'requires_reauthorization';
      if (comparison < 0 || (comparison == 0 && !restored)) {
        throw const FormatException('升级版本必须高于当前已安装版本');
      }
    }
    for (final dep in (manifest['dependencies'] as List).cast<String>()) {
      if (!old.any((m) => m['id'] == dep && m['enabled'] == true)) {
        throw FormatException('缺少已启用的依赖：$dep');
      }
    }

    // Reject an upgrade that would introduce a dependency cycle.
    final graph = <String, List<String>>{
      for (final m in old)
        m['id'] as String: (m['dependencies'] as List).cast<String>(),
      id: (manifest['dependencies'] as List).cast<String>(),
    };
    bool reaches(String start, String target, Set<String> seen) {
      if (start == target) return true;
      if (!seen.add(start)) return false;
      for (final dep in graph[start] ?? const <String>[]) {
        if (reaches(dep, target, seen)) return true;
      }
      return false;
    }

    for (final dep in graph[id]!) {
      if (reaches(dep, id, <String>{})) {
        throw const FormatException('依赖关系形成循环');
      }
    }

    // An upgrade must never leave a previous Runtime Session alive.
    if (current.isNotEmpty) {
      _sessionManager.terminateInstallation(
        current.first['installationId'] as String,
      );
    }

    // Legacy task creation is a host business operation, so it is offline-only.
    final profile = declared.contains('tasks.create')
        ? 'host_integrated_offline'
        : 'standalone_offline';
    await _store.installOrUpgrade(
      modId: id,
      publisherId: 'local.legacy',
      version: manifest['version'] as String,
      manifestJson: jsonEncode(manifest),
      effectiveProfile: profile,
      grantedPermissions: grantedPermissions.intersection(declared),
      storageQuotaBytes: 0,
    );
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final mods = await list();
    final index = mods.indexWhere((m) => m['id'] == id);
    if (index == -1) throw StateError('Mod 未安装');
    if (enabled && mods[index]['isV1Package'] == true) {
      final grants = (mods[index]['grantedPermissions'] as List? ?? const [])
          .whereType<String>()
          .toSet();
      if (!grants.contains('host.tasks.create')) {
        throw StateError('启用 V1 任务模板前必须先授权 host.tasks.create');
      }
    }
    if (!enabled &&
        mods.any(
          (m) =>
              m['enabled'] == true &&
              m['id'] != id &&
              (m['dependencies'] as List).contains(id),
        )) {
      throw StateError('其他已启用 Mod 依赖此 Mod，不能禁用');
    }
    if (enabled) {
      for (final dep in (mods[index]['dependencies'] as List).cast<String>()) {
        if (!mods.any((m) => m['id'] == dep && m['enabled'] == true)) {
          throw StateError('依赖 $dep 未启用');
        }
      }
    }
    if (!enabled) {
      final installation = mods[index];
      _sessionManager.terminateInstallation(
        installation['installationId'] as String,
      );
    }
    await _store.setEnabled(id, enabled);
  }

  Future<void> uninstall(String id, {bool keepData = false}) async {
    final mods = await list();
    if (!mods.any((m) => m['id'] == id)) throw StateError('Mod 未安装');
    if (mods.any(
      (m) => m['id'] != id && (m['dependencies'] as List).contains(id),
    )) {
      throw StateError('仍有 Mod 依赖此 Mod，不能卸载');
    }
    final installation = mods.firstWhere((mod) => mod['id'] == id);
    _sessionManager.terminateInstallation(
      installation['installationId'] as String,
    );
    await _store.uninstall(id, keepData: keepData);
    if (installation['isV1Package'] == true) {
      await package_importer.deleteV1PackageDirectory(
        ownerId: ownerId,
        modId: id,
        packageDirectory: installation['packageDirectory'] as String,
      );
    }
  }

  /// Explicit user authorization. Platform/admin approval is intentionally
  /// separate and is checked by ModPermissionPolicy at Host API invocation.
  Future<void> grantPermission(String id, String capability) async {
    final mods = await list();
    final matches = mods.where((mod) => mod['id'] == id);
    if (matches.isEmpty) throw StateError('Mod 未安装');
    final mod = matches.single;
    final permissions = mod['permissions'];
    var declared = false;
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
    if (!declared) throw StateError('Mod 未声明此 capability');

    await _store.grantPermission(id, capability);
    // V1 task_template packages are installed disabled. Granting the
    // required Host capability is the explicit user opt-in that makes the
    // declarative Runtime discoverable; admin approval is still required for
    // the eventual Host API call.
    if (mod['isV1Package'] == true && capability == 'host.tasks.create') {
      await setEnabled(id, true);
    }
  }

  Future<void> revokePermission(String id, String capability) async {
    final installation = (await list()).where((mod) => mod['id'] == id);
    if (installation.isNotEmpty) {
      _sessionManager.terminateInstallation(
        installation.first['installationId'] as String,
      );
    }
    await _store.revokePermission(id, capability);
  }

  Future<List<Map<String, dynamic>>> taskTemplates() async {
    final result = <Map<String, dynamic>>[];
    for (final mod in await list()) {
      if (mod['enabled'] != true ||
          !(mod['grantedPermissions'] as List).contains('tasks.create')) {
        continue;
      }
      for (final template in mod['taskTemplates'] as List) {
        result.add({
          ...Map<String, dynamic>.from(template as Map),
          'modId': mod['id'],
          'modName': mod['name'],
          'installationId': mod['installationId'],
          'publisherId': mod['publisherId'],
          'effectiveProfile': mod['effectiveProfile'],
        });
      }
    }
    return result;
  }
}
