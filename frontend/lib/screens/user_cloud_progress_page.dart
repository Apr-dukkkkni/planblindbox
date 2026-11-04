import 'dart:convert';
import 'package:flutter/material.dart';
import '../auth/auth_api.dart';
import '../auth/auth_session.dart';
import '../data/today_api.dart';
import '../services/core_sync_service.dart';

/// Manual cloud snapshots; this does not replace the existing WebDAV archive UI.
class UserCloudProgressPage extends StatefulWidget {
  const UserCloudProgressPage({super.key, required this.api, required this.auth});
  final TodayApi api;
  final AuthSession auth;
  @override
  State<UserCloudProgressPage> createState() => _UserCloudProgressPageState();
}
class _UserCloudProgressPageState extends State<UserCloudProgressPage> {
  bool _busy = false;
  CloudSnapshot? _remote;
  bool _entitled = false;
  String? _error;
  @override
  void initState() { super.initState(); _refresh(); }
  Future<void> _refresh() async {
    final token = widget.auth.token;
    if(token == null) return;
    setState(() {_busy = true;_error=null;});
    try {
      final client = CoreSyncClient(baseUrl: widget.auth.api.baseUrl);
      Map<String, dynamic> status;
      try { status = await client.entitlement(token); }
      finally { client.dispose(); }
      if (!mounted || widget.auth.token != token) return;
      final active = status['active'] == true;
      setState(() => _entitled = active);
      if (!active) {
        setState(() { _remote = null; _error = '当前没有有效云同步订阅。坚果云免费备份不受影响。'; });
        return;
      }
      final remote = await widget.auth.api.getProgress(token);
      if(mounted) setState(() => _remote = remote);
    } on AuthApiException catch(e) {
      if(e.statusCode == 404) {
        if(mounted) setState(() => _remote = null);
      } else {
        if(e.statusCode == 401) await widget.auth.expireSession();
        if(mounted) setState(() => _error = e.message);
      }
    } catch(e) {if(mounted) setState(() => _error = e.toString());}
    finally {if(mounted) setState(() => _busy = false);}
  }
  Future<bool> _confirm(String title, String content) async =>
      await showDialog<bool>(context: context,builder:(ctx)=>AlertDialog(
        title: Text(title),content: Text(content),actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('取消')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('确认')),
        ]))??false;
  void _message(String text){if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));}
  Future<void> _upload() async {
    if(_busy || !_entitled || widget.auth.token==null) return;
    final user = widget.auth.user!;
    final owner = await widget.api.repository.getAppSetting('account_snapshot_owner_v1_${widget.api.userId}');
    if(!mounted) return;
    if(owner != null && owner.isNotEmpty && owner != user.userId.toString()) {
      _message('本机进度已关联其他账号。请先备份并恢复正确账号的数据，禁止直接跨账号上传。');
      return;
    }
    final proceed=await _confirm('上传本机进度？',
      '将本机任务、习惯等 SQLite 快照上传到账号 ${user.email}。'
      '${_remote == null ? '云端目前没有快照。' : '此操作会覆盖云端旧快照。'}'
      '这是手动备份，不会自动合并。');
    if(!proceed || !mounted)return;
    setState(() => _busy=true);
    try {
      final raw=await widget.api.repository.exportBackupJson();
      if(utf8.encode(raw).length>5*1024*1024) throw const AuthApiException('本机进度超过5MiB，请使用本地备份');
      final parsed=jsonDecode(raw);
      if(parsed is! Map<String,dynamic>) throw const FormatException('备份内容不是JSON对象');
      await widget.auth.api.putProgress(widget.auth.token!,_remote?.revision??0,parsed);
      await widget.api.repository.setAppSetting('account_snapshot_owner_v1_${widget.api.userId}',user.userId.toString());
      if(mounted) _message('云端上传成功');
    } on AuthApiException catch(e) {
      if(e.statusCode==401) await widget.auth.expireSession();
      _message('上传失败：${e.message}');
    } catch(e) {_message('上传失败：$e');}
    finally {if(mounted) setState(() => _busy=false);}
    if(mounted) await _refresh();
  }
  Future<void> _restore() async {
    if(_busy || _remote==null || widget.auth.token==null) return;
    final proceed=await _confirm('恢复云端进度？',
      '恢复将清空并替换本机任务、习惯、记录等数据！请先在“设置”导出本地备份。'
      '不会自动合并，也不会修改其他设备的云端数据。确定继续？');
    if(!proceed || !mounted) return;
    setState(() => _busy=true);
    try {
      // Fetch latest before applying, not a previously cached copy.
      final current=await widget.auth.api.getProgress(widget.auth.token!);
      if(current==null)throw const AuthApiException('云端还没有快照');
      if(_remote!.revision != current.revision)throw const AuthApiException('云端快照已更新，请刷新后确认');
      await widget.api.repository.restoreBackupJson(jsonEncode(current.payload));
      await widget.api.repository.setAppSetting('account_snapshot_owner_v1_${widget.api.userId}',widget.auth.user!.userId.toString());
      _message('云端恢复成功，返回页面后刷新内容');
    } on AuthApiException catch(e) {
      if(e.statusCode==401) await widget.auth.expireSession();
      _message('恢复失败：${e.message}');
    } catch(e){_message('恢复失败：$e');}
    finally {if(mounted) setState(() => _busy=false);}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('账号云端进度'),actions:[IconButton(
      onPressed:_busy?null:_refresh,icon:const Icon(Icons.refresh))]),
    body:ListView(padding:const EdgeInsets.all(20),children:[
      const Icon(Icons.cloud_sync_outlined,size:58),
      const SizedBox(height:16),
      Text(widget.auth.user?.email??'',textAlign:TextAlign.center),
      const SizedBox(height:16),
      Text(!_entitled?'云同步订阅：未生效':(_remote==null?'当前账号尚无云端快照':'云端快照修订版本：${_remote!.revision}')),
      const SizedBox(height:10),
      const Text('此处为兼容旧数据的手动快照入口，不等于多设备自动同步。敏感明文记录禁止上传到服务器；坚果云独立备份不受影响。'),
      const SizedBox(height:12),
      if(_busy) const LinearProgressIndicator(),
      if(_error!=null) Text(_error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
      const SizedBox(height:20),
      FilledButton.icon(onPressed:_busy || !_entitled?null:_upload,icon:const Icon(Icons.cloud_upload_outlined),label:const Text('上传本机进度')),
      const SizedBox(height:12),
      OutlinedButton.icon(onPressed:_busy || _remote==null?null:_restore,
        icon:const Icon(Icons.cloud_download_outlined),label:const Text('从云端恢复到本机')),
      const SizedBox(height:18),
      const Text('提示：切换账号不会自动删除本机 SQLite 数据；上传时会检查已关联的账号，避免误把其他账号的数据上传。'),
    ]));
}
