
import 'package:flutter/material.dart';
import 'config/api_config.dart';
import 'data/mod_market_api.dart';
import 'auth/planblindbox_auth.dart';
import 'data/local/local_database.dart';
import 'data/today_api.dart';
import 'theme/app_theme.dart';
import 'screens/app_shell.dart';
import 'services/app_preferences.dart';
import 'services/cloud_archive_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalDatabase.instance.initialize();
  await AppPreferences.instance.load();
  runApp(const PlanBlindBoxApp());
}

class PlanBlindBoxApp extends StatefulWidget {
  const PlanBlindBoxApp({super.key});

  @override
  State<PlanBlindBoxApp> createState() => _PlanBlindBoxAppState();
}

class _PlanBlindBoxAppState extends State<PlanBlindBoxApp> {
  late final AuthSession _auth = AuthSession(AuthApi(baseUrl: ModMarketApi.baseUrl));
  bool _firstLoginScreen = true;
  late TodayApi _api = _newApi(ApiConfig.userId);
  int _activeLocalUserId = ApiConfig.userId;

  TodayApi _newApi(int localId) => TodayApi(
    baseUrl: ApiConfig.baseUrl,
    userId: localId,
  );

  void _selectLocalAccount() {
    // 保留旧版 user_id=1 作为游客/旧数据分区；不自动绑定到登录账号。
    // 新账号使用负数分区，避免与历史本地 ID 冲突。
    final int? accountId = _auth.localAccountUserId;
    final int target = accountId == null
        ? ApiConfig.userId
        : -1000000 - accountId;
    if (target == _activeLocalUserId) return;
    _api.dispose();
    _api = _newApi(target);
    _activeLocalUserId = target;
  }

  @override
  void initState() {
    super.initState();
    _auth.restore();
  }


  late final CloudArchiveController _archive =
  CloudArchiveController(
    currentOwner: () => _api.userId,
    bridge: ArchiveDataBridge(
      exportJson: () async {
        return await _api.repository.exportBackupJson();
      },

      restoreJson: (backupJson) async {
        await _api.repository.restoreBackupJson(backupJson);
      },
    ),
  );


  @override
  void dispose() {
    _api.dispose();
    _auth.dispose();
    _auth.api.dispose();
    super.dispose();
    _archive.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PlanBlindBox · 每天一点成长',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth > 600;

          final appHeight = constraints.maxHeight > 860
              ? 860.0
              : constraints.maxHeight;

          return ColoredBox(
            color: isDesktop
                ? const Color(0xFFEFF2EF)
                : Colors.white,
            child: Center(
              child: Container(
                width: isDesktop ? 430 : constraints.maxWidth,
                height: isDesktop
                    ? appHeight
                    : constraints.maxHeight,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(
                    isDesktop ? 24 : 0,
                  ),
                  boxShadow: isDesktop
                      ? const [
                    BoxShadow(
                      color: Color(0x22000000),
                      blurRadius: 24,
                      offset: Offset(0, 8),
                    ),
                  ]
                      : const [],
                ),
                // 注意：使用已经定义好的 _api
                child: ListenableBuilder(
                  listenable: _auth,
                  builder: (context, _) {
                    if (_auth.state == LoginState.loading) {
                      return const Scaffold(body: Center(child: CircularProgressIndicator()));
                    }
                    _selectLocalAccount();
                    if (_firstLoginScreen && !_auth.isSignedIn &&
                        _auth.localAccountUserId == null) {
                      return LoginPage(
                        session: _auth,
                        onGuest: () => setState(() => _firstLoginScreen = false),
                        onLoggedIn: () => setState(() => _firstLoginScreen = false),
                      );
                    }
                    return AppShell(
                      key: ValueKey('account-$_activeLocalUserId'),
                      api: _api, auth: _auth, archiveController: _archive);
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
