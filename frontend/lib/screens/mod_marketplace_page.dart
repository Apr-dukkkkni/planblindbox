import 'package:flutter/material.dart';

import '../data/mod_market_api.dart';
import '../data/today_api.dart';
import '../services/mod_registry.dart';
import '../auth/auth_session.dart';
import '../auth/auth_pages.dart';

/// 在线 Mod 浏览与授权安装；服务不可用时不影响任何离线功能。
class ModMarketplacePage extends StatefulWidget {
  const ModMarketplacePage({super.key, required this.api, required this.auth});
  final TodayApi api;
  final AuthSession auth;
  @override
  State<ModMarketplacePage> createState() => _ModMarketplacePageState();
}

class _ModMarketplacePageState extends State<ModMarketplacePage> {
  late final ModMarketApi _market = ModMarketApi(session: widget.auth);
  late final ModRegistry _registry = ModRegistry(widget.api.repository);
  final TextEditingController _search = TextEditingController();
  List<Map<String, dynamic>> _mods = [];
  bool _loading = false;
  bool _ranking = false;
  String? _error;
  String? _downloading;

  @override
  void initState() { super.initState(); _refresh(); }
  @override
  void dispose() { _market.dispose(); _search.dispose(); super.dispose(); }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() { _loading = true; _error = null; });
    try {
      final result = _ranking
          ? await _market.ranking()
          : await _market.catalog(search: _search.text.trim());
      if (mounted) setState(() => _mods = result);
    } catch (e) {
      if (mounted) setState(() => _error = '在线市场暂不可用：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openDetail(Map<String, dynamic> item) async {
    try {
      final detail=await _market.detail(item['id'] as String);
      if (!mounted) return;
      final versions = detail['versions'] is List ? detail['versions'] as List : const [];
      await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
        title: Text(detail['name']?.toString() ?? 'Mod 详情'),
        content: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,
          children:[
            Text('标识：${detail['id']}'),
            const SizedBox(height:8),
            Text('最新版本：${detail['latestVersion']}'),
            const SizedBox(height:8),
            Text(detail['description']?.toString() ?? ''),
            const SizedBox(height:8),
            Text('下载次数：${detail['downloads']}'),
            const SizedBox(height:8),
            Text('已发布版本：${versions.map((v)=> v is Map ? v['version'] : v).join('、')}'),
            const SizedBox(height:12),
            const Text('浏览详情无需登录；下载需登录账号。'),
          ],
        )),
        actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('关闭'))],
      ));
    } catch(e){
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('读取 Mod 详情失败：$e')));
    }
  }

  Future<void> _install(Map<String, dynamic> item) async {
    if (_downloading != null) return;
    if (!widget.auth.isSignedIn) {
      await Navigator.of(context).push<bool>(MaterialPageRoute(
          builder: (_) => LoginPage(session: widget.auth)));
      if (!mounted || !widget.auth.isSignedIn) return;
    }
    final id = item['id'] as String;
    final version = item['latestVersion'] as String;
    setState(() => _downloading = id);
    try {
      final raw = await _market.download(id, version);
      final manifest = _registry.parseManifest(raw);
      if (manifest['id'] != id || manifest['version'] != version) {
        throw const FormatException('下载清单与市场条目不匹配');
      }
      final permissions = (manifest['permissions'] as List).cast<String>();
      final granted = <String>{};
      if (!mounted) return;
      final approved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (_, setDialog) => AlertDialog(
            title: Text('安装 ${manifest['name']}？'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${manifest['id']} · v${manifest['version']}'),
                  const SizedBox(height: 8),
                  Text(manifest['description'] as String),
                  const SizedBox(height: 10),
                  const Text('仅在你主动点击模板时创建任务。请确认权限：'),
                  for (final permission in permissions)
                    CheckboxListTile(
                      title: Text(permission == 'tasks.create' ? '创建任务' : permission),
                      value: granted.contains(permission),
                      onChanged: (checked) => setDialog(() {
                        if (checked == true) { granted.add(permission); }
                        else { granted.remove(permission); }
                      }),
                    ),
                ]),
              ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('安装')),
            ],
          ),
        ),
      );
      if (approved != true) return;
      await _registry.install(raw, grantedPermissions: granted);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mod 安装成功，可返回管理器查看模板')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('安装失败：$e')));
    } finally {
      if (mounted) setState(() => _downloading = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_ranking ? 'Mod 下载排行榜' : '在线 Mod 市场'),
      actions: [
        IconButton(
          tooltip: _ranking ? '返回在线市场' : '下载排行榜',
          onPressed: _loading ? null : () {
            setState(() => _ranking = !_ranking);
            _refresh();
          },
          icon: Icon(_ranking ? Icons.storefront_outlined : Icons.leaderboard_outlined),
        ),
        IconButton(onPressed: _loading ? null : _refresh, icon: const Icon(Icons.refresh), tooltip: '刷新'),
      ]),
    body: Column(children: [
      if (!_ranking) Padding(padding: const EdgeInsets.all(12), child: TextField(
        controller: _search,
        onSubmitted: (_) => _refresh(),
        decoration: InputDecoration(labelText: '搜索 Mod', prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(onPressed: _refresh, icon: const Icon(Icons.arrow_forward))),
      )),
      if (_loading) const LinearProgressIndicator(),
      if (_error != null) Padding(padding: const EdgeInsets.all(12),
        child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      Expanded(child: ListView.builder(
        itemCount: _mods.length,
        itemBuilder: (context, index) {
          final mod = _mods[index];
          return Card(child: ListTile(
            onTap: () => _openDetail(mod),
            leading: _ranking ? CircleAvatar(child: Text('${index + 1}')) : null,
            title: Text('${mod['name']} · v${mod['latestVersion']}'),
            subtitle: Text('${mod['id']}\n${mod['description']}\n下载次数：${mod['downloads']}'),
            isThreeLine: true,
            trailing: FilledButton(
              onPressed: _downloading == null ? () => _install(mod) : null,
              child: Text(_downloading == mod['id'] ? '下载中' : '下载并安装'),
            ),
          ));
        },
      )),
    ]),
  );
}
