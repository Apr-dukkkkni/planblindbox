import 'dart:convert';

import '../../services/mod_registry.dart';
import '../package/mod_package_models.dart';

/// A *data-only* task template. Nothing in this object executes developer code.
class ModDeclaredTaskTemplate {
  ModDeclaredTaskTemplate({
    required this.index,
    required Map<String, dynamic> payload,
  }) : payload = Map<String, dynamic>.unmodifiable(payload);

  final int index;
  final Map<String, dynamic> payload;
}

/// An installed, validated declarative contribution bound to its installation.
///
/// Legacy manifests are parsed by the existing strict registry parser. V1
/// manifests are accepted only through [loadFromInstallation], which reloads
/// the owner-scoped package directory and verifies all package digests before
/// constructing this data-only definition. A bare V1 Manifest is never enough.
class DeclarativeModDefinition {
  DeclarativeModDefinition._({
    required this.modId,
    required this.name,
    required this.version,
    required this.publisherId,
    required this.installationId,
    required this.manifestJson,
    required this.effectiveProfile,
    required this.dependencies,
    required this.taskTemplates,
  });

  final String modId;
  final String name;
  final String version;
  final String publisherId;
  final String installationId;
  final String manifestJson;
  final String effectiveProfile;
  final List<String> dependencies;
  final List<ModDeclaredTaskTemplate> taskTemplates;

  /// Loads a definition from the installed package. Legacy MODs keep their
  /// synchronous parser; V1 packages must be reloaded from disk and fully
  /// revalidated before their declarative data can enter the Runtime model.
  static Future<DeclarativeModDefinition> loadFromInstallation(
    Map<String, dynamic> installation,
    ModRegistry registry,
  ) async {
    if (installation['isV1Package'] == true) {
      final package = await registry.loadV1PackageContents(installation);
      return fromValidatedV1Package(installation, package);
    }
    if (installation['manifestVersion'] == 1) {
      throw UnsupportedError('Manifest V1 尚未作为已验证内容包安装');
    }
    return fromInstallation(installation, registry);
  }

  /// Converts only a package that has already passed the on-disk package
  /// loader. This method does not grant permissions or enable the installation.
  static DeclarativeModDefinition fromValidatedV1Package(
    Map<String, dynamic> installation,
    ModValidatedPackage package,
  ) {
    final manifest = package.manifest;
    if (installation['isV1Package'] != true ||
        installation['manifestVersion'] != 1 ||
        manifest['manifestVersion'] != 1 ||
        manifest['type'] != 'content' ||
        manifest['contentKind'] != 'task_template') {
      throw const FormatException('不是经过验证的 V1 task_template 内容包');
    }
    final runtime = manifest['runtime'];
    if (runtime is! Map ||
        runtime['type'] != 'declarative' ||
        runtime['apiVersion'] != '1' ||
        runtime['entrypoint'] != 'content/task-templates.json') {
      throw const FormatException('V1 声明式 Runtime 入口不受支持');
    }
    final publisher = manifest['publisher'];
    final publisherId = publisher is Map ? publisher['id'] : null;
    final modId = manifest['id'];
    final version = manifest['version'];
    final installationId = installation['installationId'];
    if (modId is! String ||
        version is! String ||
        publisherId is! String ||
        installation['installedModId'] != modId ||
        installation['installedVersion'] != version ||
        installation['publisherId'] != publisherId ||
        installationId is! String ||
        installationId.isEmpty) {
      throw const FormatException('V1 安装身份、版本或 Publisher 不匹配');
    }

    final permissions = (manifest['permissions'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => item['capability'])
        .whereType<String>()
        .toSet();
    final requiredProfile = permissions.any((capability) =>
            capability.startsWith('host.'))
        ? 'host_integrated_offline'
        : permissions.any((capability) =>
                capability == 'network.fetch' ||
                capability.startsWith('mods.message.'))
            ? 'standalone_networked'
            : 'standalone_offline';
    if (installation['effectiveProfile'] != requiredProfile) {
      throw const FormatException('V1 MOD Profile 与声明的宿主能力不匹配');
    }

    final localizedNames = manifest['name'];
    if (localizedNames is! Map) {
      throw const FormatException('V1 Manifest 名称格式无效');
    }
    String? name;
    for (final locale in const ['zh-CN', 'zh-Hans', 'zh', 'en']) {
      final candidate = localizedNames[locale];
      if (candidate is String && candidate.trim().isNotEmpty) {
        name = candidate.trim();
        break;
      }
    }
    final selectedName = name ??
        localizedNames.values
            .whereType<String>()
            .map((value) => value.trim())
            .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    if (selectedName.isEmpty) {
      throw const FormatException('V1 Manifest 缺少可用名称');
    }

    return DeclarativeModDefinition._(
      modId: modId,
      name: selectedName,
      version: version,
      publisherId: publisherId,
      installationId: installationId,
      manifestJson: jsonEncode(manifest),
      effectiveProfile: requiredProfile,
      dependencies: List<String>.unmodifiable(
        (manifest['dependencies'] as List? ?? const []).cast<String>(),
      ),
      taskTemplates: List<ModDeclaredTaskTemplate>.unmodifiable([
        for (var i = 0; i < package.taskTemplates.templates.length; i++)
          ModDeclaredTaskTemplate(
            index: i,
            payload: package.taskTemplates.templates[i],
          ),
      ]),
    );
  }

  static DeclarativeModDefinition fromInstallation(
    Map<String, dynamic> installation,
    ModRegistry registry,
  ) {
    final raw = installation['manifestJson'];
    if (raw is! String) {
      throw const FormatException('MOD 安装记录缺少 Manifest');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('MOD Manifest 根节点不是对象');
    }
    if (decoded.containsKey('manifestVersion')) {
      throw UnsupportedError('Manifest V1 内容包尚未验证和加载，不能启动');
    }
    // The legacy parser checks all allowed fields, data types, size limits,
    // version compatibility and all task-template payloads.
    final manifest = registry.parseManifest(raw);
    if (manifest['schemaVersion'] != 1 ||
        installation['installedModId'] != manifest['id'] ||
        installation['installedVersion'] != manifest['version'] ||
        installation['publisherId'] != 'local.legacy') {
      throw const FormatException('MOD 安装身份、版本或 Publisher 不匹配');
    }
    final permissions = (manifest['permissions'] as List).cast<String>();
    final requiredProfile = permissions.contains('tasks.create')
        ? 'host_integrated_offline'
        : 'standalone_offline';
    if (installation['effectiveProfile'] != requiredProfile) {
      throw const FormatException('MOD Profile 与声明的宿主能力不匹配');
    }
    final installationId = installation['installationId'];
    if (installationId is! String || installationId.isEmpty) {
      throw const FormatException('MOD 安装实例 ID 无效');
    }
    final rawTemplates = (manifest['taskTemplates'] as List)
        .cast<Map<String, dynamic>>();
    return DeclarativeModDefinition._(
      modId: manifest['id'] as String,
      name: manifest['name'] as String,
      version: manifest['version'] as String,
      publisherId: 'local.legacy',
      installationId: installationId,
      manifestJson: raw,
      effectiveProfile: requiredProfile,
      dependencies: List<String>.unmodifiable(
        (manifest['dependencies'] as List).cast<String>(),
      ),
      taskTemplates: List<ModDeclaredTaskTemplate>.unmodifiable([
        for (var i = 0; i < rawTemplates.length; i++)
          ModDeclaredTaskTemplate(index: i, payload: rawTemplates[i]),
      ]),
    );
  }
}
