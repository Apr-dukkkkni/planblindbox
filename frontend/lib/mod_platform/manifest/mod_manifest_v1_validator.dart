import 'dart:convert';

/// Strict parser and semantic validator for PlanBlindBox MOD Manifest V1.
///
/// This class validates untrusted metadata only. It does not verify package
/// hashes, Publisher signatures, Store Attestations, platform approval, user
/// grants, or Runtime support. Those checks belong to the package installer
/// and Capability Broker.
class ModManifestV1Validator {

  static const int maxManifestBytes = 64 * 1024;//64kb
  static const int maxPermissions = 30;//申请30条权限
  static const int maxDependencies = 50;//最多依赖

  static const Set<String> capabilities = {  //系统给MOD开放的全部能力白名单
    'storage.local',  //MOD 独立隔离的本地键值存储
    'storage.files',  //文件级沙箱存储
    'network.fetch',   //发起网络 HTTP/HTTPS 请求
    //获取信息
    'host.data.tasks.read',//读宿主任务
    'host.data.habits.read',
    'host.data.checkins.read',
    'host.data.time_records.read',
    'host.data.diary.read',
    'host.data.mood.read',
    //写或者修改
    'host.tasks.create',
    'host.tasks.update_limited',
    'host.habits.create',
    'host.habits.check_in',//给习惯打卡
    //UI、跳转、通知
    'host.external_link.open',//打开外部链接，浏览器跳转
    'host.ui.notification',   //弹出宿主/系统内通知
    'host.ui.home_widget',    //宿主主页小组件
    //MOD 之间通信（跨模组消息）
    'mods.message.send',      //发消息给其他MOD
    'mods.message.subscribe',//订阅、接收其他 MOD 发出来的消息
  };

  static const Set<String> _hostBusinessCapabilities = {  //宿主业务数据
    'host.data.tasks.read',
    'host.data.habits.read',
    'host.data.checkins.read',
    'host.data.time_records.read',
    'host.data.diary.read',
    'host.data.mood.read',
    'host.tasks.create',
    'host.tasks.update_limited',
    'host.habits.create',
    'host.habits.check_in',
  };

  static const Set<String> _egressCapabilities = {   //外发能力
    //网络外发
    'network.fetch',//**必须带 scope，锁定域名、HTTP 方法、路径前缀**，不能随便全网爬。就是 MOD 里的 fetch /http 请求权限
    'host.external_link.open',
    'host.ui.notification',
    'host.ui.home_widget',
    'mods.message.send',
    'mods.message.subscribe',
  };

  static const Set<String> _hostReadCapabilities = {  //宿主只读数据
    'host.data.tasks.read',
    'host.data.habits.read',
    'host.data.checkins.read',
    'host.data.time_records.read',
    'host.data.diary.read',
    'host.data.mood.read',
  };

  static const Set<String> _platforms = { //声明平台
    'android', 'ios', 'web', 'windows', 'macos', 'linux'
  };
  static const Set<String> _uiModes = { //弹窗模式
    'full_screen', 'modal', 'overlay'
  };
  static const Set<String> _contentKinds = {  //内容类型MOD
    'task_template', 'theme', 'shop_resource_pack', 'reward_rules', 'link_hub'
  };
  static const Set<String> _httpMethods = {
    //**探测资源是否存在、看文件大小、看最后修改时间**，不下载内容。比如 MOD 想判断一张远程图片链接还能不能访问、文件多大，不需要把图片拉下来。缓存校验（看 `ETag` / `Last-Modified`）
    //put是替换整条资源，patch是部分修改
    'GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE'
  };
  static const Set<String> _scopeKeys = {
    'domains',
    'methods',
    'pathPrefixes',
    'fields',
    'maxRecordsPerRequest',
    'maxRequestsPerMinute',
    'maxRequestBytes',
    'maxResponseBytes',
    'timeoutMs',
    'operations',
  };

  static final RegExp _idPattern =
      RegExp(r'^[a-z][a-z0-9]*(\.[a-z][a-z0-9-]*)+$');
  static final RegExp _semVerPattern = RegExp(
    r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)'
    r'(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?'
    r'(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$',
  );
  static final RegExp _domainPattern = RegExp(
    r'^(?=.{1,253}$)[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?'
    r'(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)*$',
  );
  static final RegExp _localePattern =
      RegExp(r'^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$');
  static final RegExp _fieldPattern = RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,79}$');


  Map<String, dynamic> parse(String raw) {
    if (utf8.encode(raw).length > maxManifestBytes) {
      throw const FormatException('Manifest 超过 64 KiB');
    }
    final decoded = parseStrictJson(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Manifest 根节点必须是 JSON 对象');
    }
    _validateManifest(decoded);
    return decoded;
  }

  /// Parses JSON while rejecting duplicate keys, malformed Unicode and
  /// trailing data. Package metadata and content documents share this parser.
  static Object? parseStrictJson(String raw) => _StrictJsonReader(raw).parse();

  void _validateManifest(Map<String, dynamic> manifest) {
    // 校验顶层字段：只允许清单定义内的 key，拦截多余、未知字段
    _checkKeys(manifest, const {
      'manifestVersion',
      'id',
      'version',
      'name',
      'description',
      'publisher',
      'type',
      'contentKind',
      'runtime',
      'compatibility',
      'ui',
      'storage',
      'permissions',
      'dependencies',
      'assets',
    }, 'Manifest');

    // ========== 基础版本 & MOD 身份校验 ==========
    // 当前校验器只支持 V1 版本清单
    if (manifest['manifestVersion'] != 1 || manifest['manifestVersion'] is! int) {
      throw const FormatException('仅支持 manifestVersion = 1');
    }

    // MOD 唯一标识：反向域名格式，限制最长 100 字符
    final id = _requiredString(manifest, 'id', 100);
    if (!_idPattern.hasMatch(id)) {
      throw const FormatException('id 必须为小写反向域名格式');
    }

    // MOD 版本，强制符合 SemVer 2.0 规范
    _validateSemVer(_requiredString(manifest, 'version', 64), 'version');

    // 多语言名称校验（本地化名称对象）
    _validateLocalizedName(manifest['name']);

    // 简介：可选字段，长度上限 1000
    if (manifest.containsKey('description')) {
      _string(manifest['description'], 'description', 0, 1000);
    }

    // ========== 发布者信息校验 ==========
    final publisher = _object(manifest['publisher'], 'publisher');
    // publisher 对象只允许 id 字段
    _checkKeys(publisher, const {'id'}, 'publisher');
    final publisherId = _requiredString(publisher, 'id', 100);
    if (!_idPattern.hasMatch(publisherId)) {
      throw const FormatException('publisher.id 必须为小写反向域名格式');
    }

    // ========== MOD 类型分支控制 ==========
    // MOD 只能二选一：content（内容包） / app（可运行模组）
    final type = manifest['type'];
    if (type != 'content' && type != 'app') {
      throw const FormatException('type 只能是 content 或 app');
    }
    final contentKind = manifest['contentKind'];
    if (type == 'content') {
      // 内容包：必须指定合法的内容分类
      if (contentKind is! String || !_contentKinds.contains(contentKind)) {
        throw const FormatException('content 类型必须声明有效的 contentKind');
      }
    } else if (manifest.containsKey('contentKind')) {
      // App 类型：禁止携带 contentKind
      throw const FormatException('app 类型不得声明 contentKind');
    }

    // ========== Runtime 运行时约束（强绑定） ==========
    final runtime = _object(manifest['runtime'], 'runtime');
    _checkKeys(runtime, const {'type', 'apiVersion', 'entrypoint'}, 'runtime');
    final runtimeType = runtime['type'];
    // 仅支持三种运行时：声明式 / Web / Wasm
    if (runtimeType != 'declarative' && runtimeType != 'web' && runtimeType != 'wasm') {
      throw const FormatException('runtime.type 不受支持');
    }
    // 业务绑定规则：content 只能用 declarative
    if (type == 'content' && runtimeType != 'declarative') {
      throw const FormatException('content 必须使用 declarative Runtime');
    }
    // App 不能用 declarative，必须是可执行运行时
    if (type == 'app' && runtimeType == 'declarative') {
      throw const FormatException('app 必须使用可执行 Runtime');
    }
    // 宿主 API 版本号：非负整数字符串
    final apiVersion = _requiredString(runtime, 'apiVersion', 32);
    if (!RegExp(r'^(0|[1-9]\d*)$').hasMatch(apiVersion)) {
      throw const FormatException('runtime.apiVersion 必须为非负整数版本字符串');
    }
    // 入口文件路径，先校验是安全相对路径（防穿越）
    final entrypoint = _requiredString(runtime, 'entrypoint', 240);
    _validatePackagePath(entrypoint, 'runtime.entrypoint');
    // 根据 runtime 强制入口文件放在指定根目录下
    final expectedPrefix = switch (runtimeType) {
      'declarative' => 'content/',
      'web' => 'web/',
      'wasm' => 'wasm/',
      _ => '',
    };
    if (!entrypoint.startsWith(expectedPrefix)) {
      throw FormatException('runtime.entrypoint 必须位于 $expectedPrefix 目录');
    }

    // ========== 宿主兼容性 & 平台声明 ==========
    final compatibility = _object(manifest['compatibility'], 'compatibility');
    _checkKeys(compatibility, const {'hostApi', 'platforms'}, 'compatibility');
    // 宿主 API 版本范围（^ / ~ / 固定版本）
    _validateSemVerRange(_requiredString(compatibility, 'hostApi', 100), 'compatibility.hostApi');
    // 支持平台列表，至少一个、最多 6 个，只能是白名单内平台
    _stringList(compatibility['platforms'], 'compatibility.platforms',
        minItems: 1, maxItems: 6, allowed: _platforms);

    // ========== UI 展示模式配置 ==========
    final ui = _object(manifest['ui'], 'ui');
    _checkKeys(ui, const {'allowedModes', 'defaultMode'}, 'ui');
    // 允许的弹窗/展示模式，1~3 种，只能取自白名单
    final allowedModes = _stringList(ui['allowedModes'], 'ui.allowedModes',
        minItems: 1, maxItems: 3, allowed: _uiModes);
    final defaultMode = _requiredString(ui, 'defaultMode', 32);
    // 默认模式必须在允许列表里面
    if (!_uiModes.contains(defaultMode) || !allowedModes.contains(defaultMode)) {
      throw const FormatException('ui.defaultMode 必须包含在 ui.allowedModes 中');
    }

    // ========== 沙箱隔离存储 storage.local ==========
    final storage = _object(manifest['storage'], 'storage');
    _checkKeys(storage, const {'local'}, 'storage');
    final local = _object(storage['local'], 'storage.local');
    _checkKeys(local, const {'enabled', 'quotaMiB', 'persistent'}, 'storage.local');
    final storageEnabled = local['enabled'];
    final persistent = local['persistent'];
    // 开关、持久化标记只能是布尔
    if (storageEnabled is! bool || persistent is! bool) {
      throw const FormatException('storage.local.enabled/persistent 必须为布尔值');
    }
    // 存储配额：0 ~ 2048 MiB
    final quotaMiB = _integer(local['quotaMiB'], 'storage.local.quotaMiB', 0, 2048);
    // 如果开启存储，配额必须 >0
    if (storageEnabled && quotaMiB < 1) {
      throw const FormatException('启用 storage.local 时 quotaMiB 必须大于 0');
    }
    // 如果关闭存储：配额必须是 0，并且不能开启持久化
    if (!storageEnabled && (quotaMiB != 0 || persistent)) {
      throw const FormatException('禁用 storage.local 时 quotaMiB 必须为 0 且 persistent 必须为 false');
    }

    // ========== 权限校验 + 核心安全隔离规则 ==========
    // 进入权限子校验，返回权限 Map
    final permissions = _validatePermissions(manifest['permissions']);
    final permissionNames = permissions.keys.toSet();
    // 存储开关 和 storage.local 权限必须保持一致，不能一边开一边不申请权限
    if (storageEnabled != permissionNames.contains('storage.local')) {
      throw const FormatException('storage.local.enabled 必须与 storage.local 权限声明一致');
    }

    // V1 最重要隔离：不能同时持有宿主业务数据权限 + 外发（网络/跨模组）权限
    final hasHostBusiness = permissionNames.any(_hostBusinessCapabilities.contains);
    final hasEgress = permissionNames.any(_egressCapabilities.contains);
    if (hasHostBusiness && hasEgress) {
      throw const FormatException(
        'V1 禁止同一 MOD 同时申请宿主业务 API 与网络/外发/跨 MOD 能力',
      );
    }

    // 业务强制权限：特定 contentKind 必须携带指定权限
    if (contentKind == 'task_template' && !permissionNames.contains('host.tasks.create')) {
      throw const FormatException('task_template 必须声明 host.tasks.create');
    }
    if (contentKind == 'link_hub' && !permissionNames.contains('host.external_link.open')) {
      throw const FormatException('link_hub 必须声明 host.external_link.open');
    }

    // ========== MOD 依赖校验 ==========
    // dependencies 可选；不传则是空数组
    final dependencies = manifest.containsKey('dependencies')
        ? manifest['dependencies']
        : const <dynamic>[];
    _validateDependencies(dependencies, id);

    // ========== 静态资源（图标）校验，可选 ==========
    if (manifest.containsKey('assets')) {
      final assets = _object(manifest['assets'], 'assets');
      _checkKeys(assets, const {'icon'}, 'assets');
      if (assets.containsKey('icon')) {
        final icon = _requiredString(assets, 'icon', 240);
        _validatePackagePath(icon, 'assets.icon');
        // 图标文件强制放在 assets/ 目录下
        if (!icon.startsWith('assets/')) {
          throw const FormatException('assets.icon 必须位于 assets/ 目录');
        }
      }
    }
  }


  Map<String, Map<String, dynamic>> _validatePermissions(Object? value) {
    if (value is! List || value.length > maxPermissions) {
      throw const FormatException('permissions 必须为数组，最多 30 项');
    }
    final result = <String, Map<String, dynamic>>{};
    for (var i = 0; i < value.length; i++) {
      final permission = _object(value[i], 'permissions[$i]');
      _checkKeys(permission, const {'capability', 'required', 'reason', 'scope'},
          'permissions[$i]');
      final capability = _requiredString(permission, 'capability', 80);
      if (!capabilities.contains(capability)) {
        throw FormatException('不支持的 capability：$capability');
      }
      if (result.containsKey(capability)) {
        throw FormatException('permissions 中 capability 重复：$capability');
      }
      if (permission['required'] is! bool) {
        throw FormatException('permissions[$i].required 必须为布尔值');
      }
      _requiredString(permission, 'reason', 500);
      if (permission.containsKey('scope')) {
        _validateScope(capability, permission['scope']);
      }
      if (capability == 'network.fetch' && !permission.containsKey('scope')) {
        throw const FormatException('network.fetch 必须声明 scope');
      }
      if (_hostReadCapabilities.contains(capability) && !permission.containsKey('scope')) {
        throw FormatException('$capability 必须声明 scope');
      }
      result[capability] = permission;
    }
    return result;
  }

  void _validateScope(String capability, Object? value) {
    final scope = _object(value, 'permissions[$capability].scope');
    _checkKeys(scope, _scopeKeys, 'permissions[$capability].scope');
    if (scope.isEmpty) throw FormatException('$capability 的 scope 不能为空');

    if (scope.containsKey('domains')) {
      final domains = _stringList(scope['domains'], '$capability.scope.domains',
          minItems: 1, maxItems: 20);
      for (final domain in domains) {
        if (!_domainPattern.hasMatch(domain)) {
          throw FormatException('network.fetch 域名必须是小写 DNS 主机名：$domain');
        }
      }
    }
    if (scope.containsKey('methods')) {
      _stringList(scope['methods'], '$capability.scope.methods',
          minItems: 1, maxItems: 6, allowed: _httpMethods);
    }
    if (scope.containsKey('pathPrefixes')) {
      final paths = _stringList(scope['pathPrefixes'], '$capability.scope.pathPrefixes',
          minItems: 1, maxItems: 30);
      for (final path in paths) {
        _validatePathPrefix(path);
      }
    }
    if (scope.containsKey('fields')) {
      final fields = _stringList(scope['fields'], '$capability.scope.fields',
          minItems: 1, maxItems: 50);
      for (final field in fields) {
        if (!_fieldPattern.hasMatch(field)) {
          throw FormatException('scope.fields 包含无效字段名：$field');
        }
      }
    }
    if (scope.containsKey('maxRecordsPerRequest')) {
      _integer(scope['maxRecordsPerRequest'], '$capability.scope.maxRecordsPerRequest', 1, 500);
    }
    if (scope.containsKey('maxRequestsPerMinute')) {
      _integer(scope['maxRequestsPerMinute'], '$capability.scope.maxRequestsPerMinute', 1, 600);
    }
    if (scope.containsKey('maxRequestBytes')) {
      _integer(scope['maxRequestBytes'], '$capability.scope.maxRequestBytes', 0, 10485760);
    }
    if (scope.containsKey('maxResponseBytes')) {
      _integer(scope['maxResponseBytes'], '$capability.scope.maxResponseBytes', 0, 10485760);
    }
    if (scope.containsKey('timeoutMs')) {
      _integer(scope['timeoutMs'], '$capability.scope.timeoutMs', 100, 60000);
    }
    if (scope.containsKey('operations')) {
      final operations = _stringList(scope['operations'], '$capability.scope.operations',
          minItems: 1, maxItems: 20);
      if (operations.any((operation) => operation.length > 80)) {
        throw FormatException('$capability.scope.operations 单项最长 80 个字符');
      }
    }

    if (capability == 'network.fetch') {
      for (final key in const {'domains', 'methods', 'pathPrefixes'}) {
        if (!scope.containsKey(key)) {
          throw FormatException('network.fetch.scope 缺少 $key');
        }
      }
    }
    if (_hostReadCapabilities.contains(capability)) {
      for (final key in const {'fields', 'maxRecordsPerRequest'}) {
        if (!scope.containsKey(key)) {
          throw FormatException('$capability.scope 缺少 $key');
        }
      }
    }
  }

  void _validateDependencies(Object? value, String ownId) {
    if (value == null) return;
    if (value is! List || value.length > maxDependencies) {
      throw const FormatException('dependencies 必须是数组，最多 50 项');
    }
    final ids = <String>{};
    for (var i = 0; i < value.length; i++) {
      final dependency = _object(value[i], 'dependencies[$i]');
      _checkKeys(dependency, const {'id', 'versionRange', 'optional'}, 'dependencies[$i]');
      final id = _requiredString(dependency, 'id', 100);
      if (!_idPattern.hasMatch(id) || id == ownId || !ids.add(id)) {
        throw FormatException('dependencies[$i].id 无效、指向自身或重复');
      }
      _validateSemVerRange(_requiredString(dependency, 'versionRange', 100),
          'dependencies[$i].versionRange');
      if (dependency.containsKey('optional') && dependency['optional'] is! bool) {
        throw FormatException('dependencies[$i].optional 必须为布尔值');
      }
    }
  }

  void _validateLocalizedName(Object? value) {
    final name = _object(value, 'name');
    if (name.isEmpty || name.length > 10) {
      throw const FormatException('name 必须包含 1 到 10 个语言版本');
    }
    for (final entry in name.entries) {
      if (!_localePattern.hasMatch(entry.key)) {
        throw FormatException('name 包含无效语言标签：${entry.key}');
      }
      _string(entry.value, 'name.${entry.key}', 1, 60, trimNonEmpty: true);
    }
  }

  static void _validateSemVer(String value, String field) {   //校验**精确版本号**
    if (value.length > 64) throw FormatException('$field 最长 64 个字符');
    final match = _semVerPattern.firstMatch(value);
    if (match == null) throw FormatException('$field 必须符合 SemVer 2.0.0');
    final prerelease = match.group(4);
    if (prerelease != null) {
      for (final identifier in prerelease.split('.')) {
        if (RegExp(r'^\d+$').hasMatch(identifier) &&
            identifier.length > 1 && identifier.startsWith('0')) {
          throw FormatException('$field 的数字预发布标识符不得有前导零');
        }
      }
    }
  }

  /// V1 supports exact, caret and tilde ranges; full npm range syntax is not
  /// accepted until a resolver with matching Dart/Java semantics is shipped.
  static void _validateSemVerRange(String value, String field) {
    if (value.length > 66) throw FormatException('$field 最长 66 个字符');
    var version = value;
    if (version.startsWith('^') || version.startsWith('~')) {
      version = version.substring(1);
    }
    _validateSemVer(version, field);
  }

  static int compareSemVer(String left, String right) {
    _validateSemVer(left, 'left version');
    _validateSemVer(right, 'right version');
    final a = _semVerPattern.firstMatch(left)!;
    final b = _semVerPattern.firstMatch(right)!;
    for (var i = 1; i <= 3; i++) {
      final comparison = BigInt.parse(a.group(i)!).compareTo(BigInt.parse(b.group(i)!));
      if (comparison != 0) return comparison;
    }
    final aPre = a.group(4);
    final bPre = b.group(4);
    if (aPre == null && bPre == null) return 0;
    if (aPre == null) return 1;
    if (bPre == null) return -1;
    final aa = aPre.split('.');
    final bb = bPre.split('.');
    for (var i = 0; i < aa.length && i < bb.length; i++) {
      final an = RegExp(r'^\d+$').hasMatch(aa[i]);
      final bn = RegExp(r'^\d+$').hasMatch(bb[i]);
      int comparison;
      if (an && bn) {
        comparison = BigInt.parse(aa[i]).compareTo(BigInt.parse(bb[i]));
      } else if (an != bn) {
        comparison = an ? -1 : 1;
      } else {
        comparison = aa[i].compareTo(bb[i]);
      }
      if (comparison != 0) return comparison;
    }
    return aa.length.compareTo(bb.length);
  }

  static void _validatePackagePath(String value, String field) {
    if (value.isEmpty || value.startsWith('/') || value.contains('\\') ||
        value.contains('\u0000') || value.contains(':') || value.contains('//')) {
      throw FormatException('$field 必须是安全的相对 POSIX 路径');
    }
    final segments = value.split('/');
    if (segments.any((segment) => segment.isEmpty || segment == '.' || segment == '..')) {
      throw FormatException('$field 不得包含空路径段、. 或 ..');
    }
  }

  static void _validatePathPrefix(String value) {
    if (value.isEmpty || value.length > 240 || !value.startsWith('/') || value.startsWith('//') ||
        value.contains('\\') || value.contains('?') || value.contains('#') ||
        RegExp(r'%2e|%2f|%5c', caseSensitive: false).hasMatch(value)) {
      throw FormatException('network.fetch pathPrefix 不是安全路径：$value');
    }
    final segments = value.split('/');
    if (segments.any((segment) => segment == '.' || segment == '..')) {
      throw FormatException('network.fetch pathPrefix 不得包含 . 或 ..：$value');
    }
  }

  static Map<String, dynamic> _object(Object? value, String field) {
    if (value is! Map<String, dynamic>) {
      throw FormatException('$field 必须是 JSON 对象');
    }
    return value;
  }

  static void _checkKeys(Map<String, dynamic> value, Set<String> allowed, String field) {
    final unknown = value.keys.where((key) => !allowed.contains(key)).toList();
    if (unknown.isNotEmpty) {
      throw FormatException('$field 包含未知字段：${unknown.join(', ')}');
    }
  }

  static String _requiredString(Map<String, dynamic> object, String key, int max) {
    return _string(object[key], key, 1, max, trimNonEmpty: true);
  }

  static String _string(Object? value, String field, int min, int max,
      {bool trimNonEmpty = false}) {
    if (value is! String || value.length < min || value.length > max ||
        (trimNonEmpty && value.trim().isEmpty)) {
      throw FormatException('$field 必须是长度为 $min 至 $max 的字符串');
    }
    return value;
  }

  static int _integer(Object? value, String field, int min, int max) {
    if (value is! int || value < min || value > max) {
      throw FormatException('$field 必须是 $min 至 $max 的整数');
    }
    return value;
  }

  static List<String> _stringList(Object? value, String field,
      {required int minItems, required int maxItems, Set<String>? allowed}) {
    if (value is! List || value.length < minItems || value.length > maxItems) {
      throw FormatException('$field 必须包含 $minItems 至 $maxItems 项');
    }
    final result = <String>[];
    final seen = <String>{};
    for (final item in value) {
      if (item is! String || item.isEmpty || (allowed != null && !allowed.contains(item)) ||
          !seen.add(item)) {
        throw FormatException('$field 包含无效或重复项目');
      }
      result.add(item);
    }
    return result;
  }
}

/// Small RFC 8259 reader that rejects duplicate object keys before Dart's
/// ordinary jsonDecode can silently overwrite them.
/// 严格 JSON 读取器：递归下降解析器
/// 在标准 JSON 基础上增加安全与合规约束，专门用于解析模组 manifest，
/// 拦截畸形 JSON、JSON 深度炸弹、重复 key、非法 Unicode、尾随脏数据等问题。
class _StrictJsonReader {
  /// 传入原始 JSON 字符串
  _StrictJsonReader(this.source);

  /// JSON 原始文本
  final String source;

  /// 当前读取游标位置，从左向右逐个消费字符
  int _index = 0;

  /// JSON 数字正则，匹配标准 JSON 数字格式，不允许 NaN / Infinity / 前导零
  static final RegExp _number =
  RegExp(r'-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?');

  /// 解析入口：对外唯一调用方法
  /// 整体校验：首尾空白跳过，解析完成后不能存在多余尾随字符
  Object? parse() {
    _space();
    final value = _value(0);
    _space();
    if (_index != source.length) {
      throw const FormatException('JSON 包含尾随内容');
    }
    return value;
  }

  /// 解析一个 JSON 值（对象 / 数组 / 字符串 / 数字 / true / false / null）
  /// [depth] 当前递归深度，用于限制最大嵌套层数，防栈溢出
  Object? _value(int depth) {
    if (depth > 32) throw const FormatException('JSON 嵌套层级超过 32');
    _space();
    if (_index >= source.length) throw const FormatException('JSON 意外结束');
    final char = source[_index];
    if (char == '{') return _object(depth + 1);
    if (char == '[') return _array(depth + 1);
    if (char == '"') return _string();
    if (char == 't') return _literal('true', true);
    if (char == 'f') return _literal('false', false);
    if (char == 'n') return _literal('null', null);
    return _numeric();
  }

  /// 解析 JSON 对象 { ... }
  /// 强制：key 必须是字符串，不允许同一个对象内出现重复 key
  Map<String, dynamic> _object(int depth) {
    _index++; // 消费 '{'
    _space();
    final result = <String, dynamic>{};
    final keys = <String>{};
    if (_take('}')) return result;
    while (true) {
      _space();
      if (_index >= source.length || source[_index] != '"') {
        throw const FormatException('JSON 对象的键必须是字符串');
      }
      final key = _string();
      if (!keys.add(key)) throw FormatException('JSON 存在重复字段：$key');
      _space();
      _expect(':');
      result[key] = _value(depth);
      _space();
      if (_take('}')) return result;
      _expect(',');
    }
  }

  /// 解析 JSON 数组 [ ... ]
  List<dynamic> _array(int depth) {
    _index++; // 消费 '['
    _space();
    final result = <dynamic>[];
    if (_take(']')) return result;
    while (true) {
      result.add(_value(depth));
      _space();
      if (_take(']')) return result;
      _expect(',');
    }
  }

  /// 解析 JSON 字符串 "..."
  /// 严格校验：控制字符、转义序列、\u 四位十六进制、非法代理对
  String _string() {
    final start = _index;
    _expect('"');
    while (_index < source.length) {
      final code = source.codeUnitAt(_index);
      if (code == 0x22) {
        _index++;
        final decoded = jsonDecode(source.substring(start, _index));
        if (decoded is! String || _hasUnpairedSurrogate(decoded)) {
          throw const FormatException('JSON 字符串包含非法 Unicode');
        }
        return decoded;
      }
      if (code < 0x20) throw const FormatException('JSON 字符串包含未转义控制字符');
      if (code == 0x5c) {
        _index++;
        if (_index >= source.length) throw const FormatException('JSON 转义不完整');
        final escaped = source[_index];
        if ('"\\/bfnrt'.contains(escaped)) {
          _index++;
        } else if (escaped == 'u') {
          if (_index + 4 >= source.length) throw const FormatException('JSON Unicode 转义不完整');
          final hex = source.substring(_index + 1, _index + 5);
          if (!RegExp(r'^[0-9A-Fa-f]{4}$').hasMatch(hex)) {
            throw const FormatException('JSON Unicode 转义无效');
          }
          _index += 5;
        } else {
          throw const FormatException('JSON 字符串转义无效');
        }
      } else {
        _index++;
      }
    }
    throw const FormatException('JSON 字符串未闭合');
  }

  /// 检测字符串是否存在孤立、不配对的 UTF-16 代理项
  /// 单独的高代理 / 单独的低代理属于非法 Unicode
  bool _hasUnpairedSurrogate(String value) {
    for (var i = 0; i < value.length; i++) {
      final unit = value.codeUnitAt(i);
      if (unit >= 0xD800 && unit <= 0xDBFF) {
        if (i + 1 >= value.length) return true;
        final next = value.codeUnitAt(i + 1);
        if (next < 0xDC00 || next > 0xDFFF) return true;
        i++;
      } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
        return true;
      }
    }
    return false;
  }

  /// 解析 JSON 数字
  Object? _numeric() {
    final match = _number.matchAsPrefix(source, _index);
    if (match == null) throw const FormatException('JSON 值无效');
    final token = match.group(0)!;
    _index = match.end;
    return jsonDecode(token) as num;
  }

  /// 解析字面量 true / false / null，大小写严格匹配
  Object? _literal(String token, Object? value) {
    if (!source.startsWith(token, _index)) throw const FormatException('JSON 字面量无效');
    _index += token.length;
    return value;
  }

  /// 跳过标准空白字符：空格、制表符、换行、回车
  void _space() {
    while (_index < source.length) {
      final code = source.codeUnitAt(_index);
      if (code == 0x20 || code == 0x09 || code == 0x0A || code == 0x0D) {
        _index++;
      } else {
        break;
      }
    }
  }

  /// 尝试消费指定单个字符；成功则游标前进，返回 true
  bool _take(String char) {
    if (_index < source.length && source[_index] == char) {
      _index++;
      return true;
    }
    return false;
  }

  /// 必须消费指定字符，如果不是预期字符直接抛异常
  void _expect(String char) {
    if (!_take(char)) throw FormatException('JSON 预期字符：$char');
  }
}

