import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'auth_api.dart';
import 'auth_session.dart';
import 'validators.dart';

void showAuthError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(error is AuthApiException ? error.message : '操作失败，请稍后重试'),
  ));
}

class AuthShell extends StatelessWidget {
  final AuthSession session;
  final Widget Function(BuildContext context, AuthSession session) homeBuilder;
  const AuthShell({super.key, required this.session, required this.homeBuilder});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) => session.state == LoginState.loading
      ? const Scaffold(body: Center(child: CircularProgressIndicator()))
      : homeBuilder(context, session),
  );
}

class LoginPage extends StatefulWidget {
  final AuthSession session;
  final String initialEmail;
  final VoidCallback? onGuest;
  final VoidCallback? onLoggedIn;
  const LoginPage({super.key, required this.session, this.initialEmail = '',
    this.onGuest, this.onLoggedIn});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _email;
  final _password = TextEditingController();
  bool _busy = false, _showPassword = false;
  @override
  void initState() { super.initState(); _email = TextEditingController(text: widget.initialEmail); }
  @override
  void dispose() { _email.dispose(); _password.dispose(); super.dispose(); }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate() || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.session.login(_email.text, _password.text);
      if (!mounted) return;
      if (widget.onLoggedIn != null) widget.onLoggedIn!();
      else if (Navigator.of(context).canPop()) Navigator.of(context).pop(true);
    } catch (e) { if (mounted) showAuthError(context, e); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _register() async {
    final email = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => RegisterPage(api: widget.session.api)));
    if (!mounted) return;
    if (email != null) { _email.text = email; _password.clear(); }
  }

  Future<void> _forgot() async {
    final email = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => ForgotPasswordPage(api: widget.session.api, initialEmail: _email.text)));
    if (!mounted) return;
    if (email != null) { _email.text = email; _password.clear(); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('邮箱登录')),
    body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 430),
        child: Form(key: _formKey, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Icon(Icons.lock_outline_rounded, size: 64),
          const SizedBox(height: 18),
          Text('欢迎使用 PlanBlindBox', style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 28),
          TextFormField(controller: _email, enabled: !_busy, keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next, autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: '邮箱', prefixIcon: Icon(Icons.email_outlined), border: OutlineInputBorder()),
            validator: emailError),
          const SizedBox(height: 14),
          TextFormField(controller: _password, enabled: !_busy, obscureText: !_showPassword,
            onFieldSubmitted: (_) => _login(),
            decoration: InputDecoration(labelText: '密码', prefixIcon: const Icon(Icons.lock_outline),
              border: const OutlineInputBorder(), suffixIcon: IconButton(
                onPressed: () => setState(() => _showPassword = !_showPassword),
                icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility))),
            validator: (v) => (v == null || v.isEmpty) ? '请输入密码' : null),
          const SizedBox(height: 18),
          FilledButton(onPressed: _busy ? null : _login, child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(_busy ? '正在登录…' : '登录'))),
          Wrap(alignment: WrapAlignment.spaceBetween, children: [
            TextButton(onPressed: _busy ? null : _register, child: const Text('注册账号')),
            TextButton(onPressed: _busy ? null : _forgot, child: const Text('忘记密码？')),
          ]),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: _busy ? null : () {
            if (widget.onGuest != null) widget.onGuest!();
            else if (Navigator.of(context).canPop()) Navigator.of(context).pop(false);
          }, icon: const Icon(Icons.explore_outlined), label: const Text('游客进入（本地计划继续可用）')),
        ]))))),
  );
}

class RegisterPage extends StatefulWidget {
  final AuthApi api;
  const RegisterPage({super.key, required this.api});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _key = GlobalKey<FormState>();
  final _name = TextEditingController(), _email = TextEditingController(), _pass = TextEditingController();
  String? _gender;
  bool _busy = false, _obscure = true;
  @override
  void dispose() { _name.dispose(); _email.dispose(); _pass.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (!_key.currentState!.validate() || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.api.register(username: _name.text, email: _email.text,
        password: _pass.text, gender: _gender!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('注册成功，请使用邮箱登录')));
      Navigator.of(context).pop(normalizedEmail(_email.text));
    } catch (e) { if (mounted) showAuthError(context, e); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('注册账号')),
    body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 430),
        child: Form(key: _key, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('创建 PlanBlindBox 账号', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 20),
          TextFormField(controller: _name, enabled: !_busy, decoration: const InputDecoration(
            labelText: '名称（可与其他人重名）', border: OutlineInputBorder()), validator: usernameError),
          const SizedBox(height: 14),
          TextFormField(controller: _email, enabled: !_busy, keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: '邮箱（登录账号）', border: OutlineInputBorder()), validator: emailError),
          const SizedBox(height: 14),
          TextFormField(controller: _pass, enabled: !_busy, obscureText: _obscure,
            decoration: InputDecoration(labelText: '密码（8～64 字符且不超过 72 字节）',
              border: const OutlineInputBorder(), suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure))), validator: passwordError),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(value: _gender,
            decoration: const InputDecoration(labelText: '性别（必选）', border: OutlineInputBorder()),
            items: genderOptions.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
            onChanged: _busy ? null : (v) => setState(() => _gender = v),
            validator: (v) => v == null ? '请选择性别' : null),
          const SizedBox(height: 22),
          FilledButton(onPressed: _busy ? null : _submit, child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12), child: Text(_busy ? '注册中…' : '注册'))),
          const SizedBox(height: 8),
          const Text('注册成功后返回邮箱登录。头像稍后可以在“我的资料”中设置。', textAlign: TextAlign.center),
        ]))))),
  );
}

class ForgotPasswordPage extends StatefulWidget {
  final AuthApi api;
  final String initialEmail;
  const ForgotPasswordPage({super.key, required this.api, this.initialEmail = ''});
  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _key = GlobalKey<FormState>();
  late final TextEditingController _email;
  bool _busy = false;
  @override
  void initState() { super.initState(); _email = TextEditingController(text: widget.initialEmail); }
  @override
  void dispose() { _email.dispose(); super.dispose(); }
  Future<void> _submit() async {
    if (!_key.currentState!.validate() || _busy) return;
    setState(() => _busy = true);
    try {
      final res = await widget.api.forgotPassword(_email.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:
        Text('如果邮箱已注册，验证码会发送至该邮箱。请检查收件箱和垃圾邮件。')));
      final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => ResetPasswordPage(
        api: widget.api, email: normalizedEmail(_email.text), challengeId: res.challengeId)));
      if (!mounted) return;
      if (ok == true) Navigator.of(context).pop(normalizedEmail(_email.text));
    } catch (e) { if (mounted) showAuthError(context, e); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('找回密码')),
    body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 430),
        child: Form(key: _key, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Icon(Icons.mark_email_read_outlined, size: 60),
          const SizedBox(height: 16),
          const Text('输入注册邮箱，获取 6 位验证码。验证码有效期 10 分钟。'),
          const SizedBox(height: 20),
          TextFormField(controller: _email, keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: '邮箱', border: OutlineInputBorder()), validator: emailError),
          const SizedBox(height: 20),
          FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? '提交中…' : '发送验证码')),
        ]))))),
  );
}

class ResetPasswordPage extends StatefulWidget {
  final AuthApi api;
  final String email;
  final String challengeId;
  const ResetPasswordPage({super.key, required this.api, required this.email, required this.challengeId});
  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _key = GlobalKey<FormState>();
  final _code = TextEditingController(), _password = TextEditingController(), _confirm = TextEditingController();
  bool _busy = false;
  @override
  void dispose() { _code.dispose(); _password.dispose(); _confirm.dispose(); super.dispose(); }
  Future<void> _submit() async {
    if (!_key.currentState!.validate() || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.api.resetPassword(email: widget.email, challengeId: widget.challengeId,
        code: _code.text, newPassword: _password.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('密码修改成功，请重新登录')));
      Navigator.of(context).pop(true);
    } catch (e) { if (mounted) showAuthError(context, e); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('设置新密码')),
    body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 430),
        child: Form(key: _key, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('验证码已发送至 ${widget.email}（如果该邮箱存在）'),
          const SizedBox(height: 16),
          TextFormField(controller: _code, keyboardType: TextInputType.number, maxLength: 6,
            decoration: const InputDecoration(labelText: '6 位邮箱验证码', border: OutlineInputBorder()),
            validator: (v) => RegExp(r'^\d{6}$').hasMatch(v ?? '') ? null : '请输入 6 位数字验证码'),
          const SizedBox(height: 12),
          TextFormField(controller: _password, obscureText: true,
            decoration: const InputDecoration(labelText: '新密码', border: OutlineInputBorder()), validator: passwordError),
          const SizedBox(height: 12),
          TextFormField(controller: _confirm, obscureText: true,
            decoration: const InputDecoration(labelText: '确认新密码', border: OutlineInputBorder()),
            validator: (v) => v == _password.text ? null : '两次密码不一致'),
          const SizedBox(height: 22),
          FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? '修改中…' : '重置密码并返回登录')),
        ]))))),
  );
}

class ProfilePage extends StatefulWidget {
  final AuthSession session;
  const ProfilePage({super.key, required this.session});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _key = GlobalKey<FormState>();
  late final TextEditingController _name;
  late String _gender;
  DateTime? _birthday;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.session.user?.username ?? '');
    _gender = widget.session.user?.gender ?? 'UNDISCLOSED';
    _birthday = DateTime.tryParse(widget.session.user?.birthday ?? '');
  }
  @override
  void dispose() { _name.dispose(); super.dispose(); }
  String? get _birthdayString => _birthday == null ? null :
    '${_birthday!.year.toString().padLeft(4,'0')}-${_birthday!.month.toString().padLeft(2,'0')}-${_birthday!.day.toString().padLeft(2,'0')}';

  Future<void> _save() async {
    if (!_key.currentState!.validate() || _busy) return;
    final token = widget.session.token;
    if (token == null) { showAuthError(context, const AuthApiException('请重新登录')); return; }
    setState(() => _busy = true);
    try {
      final user = await widget.session.api.updateProfile(token, username: _name.text,
        gender: _gender, birthday: _birthdayString);
      await widget.session.setProfile(user);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('资料已保存')));
    } on AuthApiException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) await widget.session.expireSession();
      if (mounted) showAuthError(context, e);
    } catch (e) { if (mounted) showAuthError(context, e); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _avatarAction(bool delete) async {
    final token = widget.session.token;
    if (token == null || _busy) return;
    XFile? picked;
    if (!delete) {
      try { picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1024, maxHeight: 1024); }
      catch (e) { if (mounted) showAuthError(context, e); return; }
      if (picked == null) return;
    }
    setState(() => _busy = true);
    try {
      final profile = delete ? await widget.session.api.deleteAvatar(token)
        : await widget.session.api.uploadAvatar(token, picked!);
      await widget.session.setProfile(profile);
    } on AuthApiException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) await widget.session.expireSession();
      if (mounted) showAuthError(context, e);
    } catch (e) { if (mounted) showAuthError(context, e); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _logout({required bool localOnly}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.session.logout(localOnly: localOnly);
      if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
    } catch (e) { if (mounted) showAuthError(context, e); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.session.user;
    if (user == null) return Scaffold(appBar: AppBar(title: const Text('我的资料')),
      body: Center(child: FilledButton(onPressed: () => Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => LoginPage(session: widget.session))),
        child: const Text('请登录'))));
    final avatarUrl = widget.session.api.absoluteAvatarUrl(user.avatar);
    return Scaffold(appBar: AppBar(title: const Text('我的资料')),
      body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 430),
          child: Form(key: _key, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: CircleAvatar(radius: 44,
              backgroundImage: avatarUrl == null ? null : NetworkImage(avatarUrl),
              child: avatarUrl == null ? const Icon(Icons.person, size: 48) : null)),
            const SizedBox(height: 10),
            Wrap(alignment: WrapAlignment.center, children: [
              TextButton(onPressed: _busy ? null : () => _avatarAction(false), child: const Text('更换头像')),
              TextButton(onPressed: _busy || user.avatar == null ? null : () => _avatarAction(true),
                child: const Text('清除头像')),
            ]),
            const SizedBox(height: 20),
            TextFormField(initialValue: user.email, readOnly: true, enabled: false,
              decoration: const InputDecoration(labelText: '邮箱（不可修改）', border: OutlineInputBorder())),
            const SizedBox(height: 14),
            TextFormField(controller: _name, decoration: const InputDecoration(
              labelText: '名称', border: OutlineInputBorder()), validator: usernameError),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(value: genderOptions.containsKey(_gender) ? _gender : 'UNDISCLOSED',
              decoration: const InputDecoration(labelText: '性别', border: OutlineInputBorder()),
              items: genderOptions.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
              onChanged: _busy ? null : (v) { if (v != null) setState(() => _gender = v); }),
            const SizedBox(height: 14),
            ListTile(title: Text(_birthdayString == null ? '生日（未设置）' : '生日：$_birthdayString'),
              subtitle: const Text('可选，可以清空'),
              trailing: Wrap(children: [
                IconButton(tooltip: '选择生日', icon: const Icon(Icons.calendar_month), onPressed: _busy ? null : () async {
                  final picked = await showDatePicker(context: context, firstDate: DateTime(1900),
                    lastDate: DateTime.now(), initialDate: _birthday ?? DateTime(2000));
                  if (mounted && picked != null) setState(() => _birthday = picked);
                }),
                IconButton(tooltip: '清空生日', icon: const Icon(Icons.clear),
                  onPressed: _busy ? null : () => setState(() => _birthday = null)),
              ])),
            const SizedBox(height: 18),
            FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? '处理中…' : '保存资料')),
            const Divider(height: 32),
            OutlinedButton(onPressed: _busy ? null : () => _logout(localOnly: false),
              child: const Text('退出登录（撤销所有设备凭证）')),
            TextButton(onPressed: _busy ? null : () async {
              final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
                title: const Text('仅退出此设备？'),
                content: const Text('服务器可能仍认为旧凭证有效，直到凭证过期。不会删除本地 SQLite 数据。'),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('继续'))]));
              if (confirm == true) await _logout(localOnly: true);
            }, child: const Text('仅退出此设备')),
          ]))))),
    );
  }
}
