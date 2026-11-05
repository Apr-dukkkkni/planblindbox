/// Mobile V1 核心功能不再使用 HTTP 后端。
/// userId 暂时作为本机数据分区标识，登录/多用户以后再接入在线扩展层。
class ApiConfig {
  static const userId = int.fromEnvironment('USER_ID', defaultValue: 1);
  static const baseUrl = 'local://sqlite';
}
