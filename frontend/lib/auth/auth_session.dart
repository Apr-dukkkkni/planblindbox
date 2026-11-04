import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'auth_api.dart';

enum LoginState { loading, guest, signedIn, offline }

class AuthSession extends ChangeNotifier {
  final AuthApi api;
  final FlutterSecureStorage storage;
  LoginState state = LoginState.loading;
  UserProfile? user;
  String? _accessToken;
  int? _lastKnownUserId;

  /// 断网时继续保留已登录用户的本地数据分区，不授予在线水滴权限。
  int? get localAccountUserId => user?.userId ??
      (state == LoginState.offline ? _lastKnownUserId : null);
  AuthSession(this.api, {FlutterSecureStorage? storage})
      : storage = storage ?? const FlutterSecureStorage();

  String? get token => state == LoginState.signedIn ? _accessToken : null;
  bool get isSignedIn => state == LoginState.signedIn;

  Future<void> restore() async {
    state = LoginState.loading; notifyListeners();
    try {
      _accessToken = await storage.read(key: 'pbb_access_token');
      _lastKnownUserId = int.tryParse(await storage.read(key: 'pbb_last_user_id') ?? '');
      if (_accessToken == null) { state = LoginState.guest; notifyListeners(); return; }
      user = await api.me(_accessToken!);
      _lastKnownUserId = user!.userId;
      await storage.write(key: 'pbb_last_user_id', value: '${user!.userId}');
      state = LoginState.signedIn;
    } on AuthApiException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) {
        await _clearLocal();
        state = LoginState.guest;
      } else {
        // Do not delete SQLite progress or clear credentials on network failure.
        state = LoginState.offline;
      }
    } catch (_) {
      state = LoginState.offline;
    }
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    final data = await api.login(email, password);
    await storage.write(key: 'pbb_access_token', value: data.accessToken);
    _accessToken = data.accessToken;
    user = data.user;
    _lastKnownUserId = user!.userId;
    await storage.write(key: 'pbb_last_user_id', value: '${user!.userId}');
    state = LoginState.signedIn;
    notifyListeners();
  }

  Future<void> refreshProfile() async {
    final t = token;
    if (t == null) throw const AuthApiException('请先登录');
    try {
      user = await api.me(t);
      notifyListeners();
    } on AuthApiException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) await expireSession();
      rethrow;
    }
  }

  Future<void> setProfile(UserProfile profile) async {
    user = profile;
    notifyListeners();
  }

  Future<void> expireSession() async {
    await _clearLocal();
    state = LoginState.guest;
    notifyListeners();
  }

  /// Normal logout is server-confirmed (revokes all devices per contract).
  /// localOnly is an explicit fallback; remote token might remain valid.
  Future<void> logout({bool localOnly = false}) async {
    if (!localOnly && _accessToken != null) await api.logout(_accessToken!);
    await _clearLocal();
    state = LoginState.guest;
    notifyListeners();
  }

  Future<void> _clearLocal() async {
    await storage.delete(key: 'pbb_access_token');
    await storage.delete(key: 'pbb_last_user_id');
    _lastKnownUserId = null;
    _accessToken = null;
    user = null;
  }
}
