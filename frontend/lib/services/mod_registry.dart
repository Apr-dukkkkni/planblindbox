import 'dart:convert';

import '../data/local/local_plan_repository.dart';

/// V1 declarative Mod manifest. This is data, NEVER executable Dart code.
/// The registry is stored in a single app_settings value so backup and reset work.
class ModRegistry {
  ModRegistry(this.repository);

  final LocalPlanRepository repository;
  // 必须与 frontend/pubspec.yaml 的主版本同步；当前应用版本 0.1.0+1。
  static const hostVersion = '0.1.0';
  static const storageKey = 'mods.registry.v1';
  static const allowedPermissions = {'tasks.create'};
  static const maxMods = 30;
  static const maxManifestBytes = 64 * 1024;

  Map<String, dynamic>? _cached;

  Future<Map<String, dynamic>> _read() async {
    if (_cached != null) return _cached!;
    final raw = await repository.getAppSetting(storageKey);
    if (raw == null) {
      return _cached = {'formatVersion': 1, 'mods': <dynamic>[], 'audit': <dynamic>[]};
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded['formatVersion'] != 1 ||
        decoded['mods'] is! List || decoded['audit'] is! List) {
      throw const FormatException('本地 Mod 注册表版本不受支持');
    }
    return _cached = Map<String, dynamic>.from(decoded);
  }

  Future<void> _write(Map<String, dynamic> next) async {
    await repository.setAppSetting(storageKey, jsonEncode(next));
    _cached = next;
  }

  Future<List<Map<String, dynamic>>> list() async {
    final store = await _read();
    return (store['mods'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> audit() async {
    final store = await _read();
    return (store['audit'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  /// No code loading; only a host-defined task-template contribution is supported.
  Map<String, dynamic> parseManifest(String raw) {
    if (utf8.encode(raw).length > maxManifestBytes) {
      throw const FormatException('清单不能超过 64 KB');
    }
    final value = jsonDecode(raw);
    if (value is! Map) throw const FormatException('清单必须是 JSON 对象');
    final manifest = Map<String, dynamic>.from(value);
    const keys = {'schemaVersion', 'id', 'name', 'version', 'description',
      'permissions', 'dependencies', 'taskTemplates', 'minHostVersion'};
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
        throw FormatException('此 Mod 需要应用版本 $minHostVersion 或更高，当前为 $hostVersion');
      }
    }
    final description = manifest['description'] ?? '';
    if (description is! String || description.length > 300) {
      throw const FormatException('描述最长 300 字符');
    }
    final perms = manifest['permissions'] ?? <dynamic>[];
    final deps = manifest['dependencies'] ?? <dynamic>[];
    final templates = manifest['taskTemplates'] ?? <dynamic>[];
    if (perms is! List || perms.length > 10 ||
        perms.any((p) => p is! String || !allowedPermissions.contains(p)) ||
        perms.toSet().length != perms.length) {
      throw const FormatException('包含不支持或重复的权限');
    }
    if (deps is! List || deps.length > 10 ||
        deps.any((d) => d is! String || d == id ||
          !RegExp(r'^[a-z][a-z0-9]*(\.[a-z][a-z0-9-]*)+$').hasMatch(d)) ||
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
      if (item.keys.any((k) => !{'title', 'note', 'targetCount', 'importance', 'difficulty'}.contains(k))) {
        throw const FormatException('任务模板存在未知字段');
      }
      final title = item['title'];
      final note = item['note'] ?? '';
      final target = item['targetCount'] ?? 1;
      final importance = item['importance'] ?? 3;
      final difficulty = item['difficulty'] ?? 3;
      if (title is! String || title.trim().isEmpty || title.length > 100 ||
          note is! String || note.length > 500 || target is! int || target < 1 || target > 999 ||
          importance is! int || importance < 1 || importance > 5 ||
          difficulty is! int || difficulty < 1 || difficulty > 5) {
        throw const FormatException('任务模板参数不合法');
      }
      cleanTemplates.add({'title': title.trim(), 'note': note, 'targetCount': target,
        'importance': importance, 'difficulty': difficulty});
    }
    return {'schemaVersion': 1, 'id': id, 'name': name.trim(), 'version': version,
      'description': description,
      if (minHostVersion != null) 'minHostVersion': minHostVersion,
      'permissions': List<String>.from(perms),
      'dependencies': List<String>.from(deps), 'taskTemplates': cleanTemplates};
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

  void _log(Map<String, dynamic> store, String action, String id) {
    final events = List<dynamic>.from(store['audit'] as List);
    events.insert(0, {'at': DateTime.now().toIso8601String(), 'action': action, 'id': id});
    store['audit'] = events.take(100).toList();
  }

  Future<void> install(String raw, {required Set<String> grantedPermissions}) async {
    final manifest = parseManifest(raw);
    final declared = (manifest['permissions'] as List).cast<String>().toSet();
    if (!declared.containsAll(grantedPermissions)) {
      throw const FormatException('授权不能超出声明权限');
    }
    final old = await list();
    final id = manifest['id'] as String;
    final current = old.where((m) => m['id'] == id).toList();
    if (current.isEmpty && old.length >= maxMods) throw const FormatException('最多安装 30 个 Mod');
    if (current.isNotEmpty &&
        _compareVersions(manifest['version'] as String, current.first['version'] as String) <= 0) {
      throw const FormatException('升级版本必须高于当前已安装版本');
    }
    for (final dep in (manifest['dependencies'] as List).cast<String>()) {
      if (!old.any((m) => m['id'] == dep && m['enabled'] == true)) {
        throw FormatException('缺少已启用的依赖：$dep');
      }
    }
    // Grants come only from the user's installation confirmation dialog.
    // Updating a Mod never auto-inherits undeclared permissions.
    final retainedGrants = grantedPermissions.intersection(declared);
    // Reject an upgrade that would introduce a dependency cycle.
    final graph = <String, List<String>>{
      for (final m in old) m['id'] as String: (m['dependencies'] as List).cast<String>(),
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
    final record = {...manifest, 'enabled': current.isEmpty ? true : current.first['enabled'],
      'grantedPermissions': retainedGrants.toList()..sort(),
      'installedAt': DateTime.now().toIso8601String()};
    final next = Map<String, dynamic>.from(await _read());
    next['mods'] = [...old.where((m) => m['id'] != id), record];
    _log(next, current.isEmpty ? 'install' : 'upgrade', id);
    await _write(next);
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final mods = await list();
    final index = mods.indexWhere((m) => m['id'] == id);
    if (index == -1) throw StateError('Mod 未安装');
    if (!enabled && mods.any((m) => m['enabled'] == true && m['id'] != id &&
        (m['dependencies'] as List).contains(id))) {
      throw StateError('其他已启用 Mod 依赖此 Mod，不能禁用');
    }
    if (enabled) {
      for (final dep in (mods[index]['dependencies'] as List).cast<String>()) {
        if (!mods.any((m) => m['id'] == dep && m['enabled'] == true)) {
          throw StateError('依赖 $dep 未启用');
        }
      }
    }
    mods[index]['enabled'] = enabled;
    final next = Map<String, dynamic>.from(await _read());
    next['mods'] = mods;
    _log(next, enabled ? 'enable' : 'disable', id);
    await _write(next);
  }

  Future<void> uninstall(String id) async {
    final mods = await list();
    if (!mods.any((m) => m['id'] == id)) throw StateError('Mod 未安装');
    if (mods.any((m) => m['id'] != id && (m['dependencies'] as List).contains(id))) {
      throw StateError('仍有 Mod 依赖此 Mod，不能卸载');
    }
    final next = Map<String, dynamic>.from(await _read());
    next['mods'] = mods.where((m) => m['id'] != id).toList();
    _log(next, 'uninstall', id);
    await _write(next);
  }

  Future<List<Map<String, dynamic>>> taskTemplates() async {
    final result = <Map<String, dynamic>>[];
    for (final mod in await list()) {
      if (mod['enabled'] != true ||
          !(mod['grantedPermissions'] as List).contains('tasks.create')) continue;
      for (final template in mod['taskTemplates'] as List) {
        result.add({...Map<String, dynamic>.from(template as Map),
          'modId': mod['id'], 'modName': mod['name']});
      }
    }
    return result;
  }
}
