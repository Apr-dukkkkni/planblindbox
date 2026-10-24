import 'package:flutter/foundation.dart';

/// 可在启动时通过 --dart-define=API_BASE_URL=http://... 覆盖。
/// Android 模拟器通过 10.0.2.2 访问电脑 localhost，Windows/macOS 桌面使用 localhost。
class ApiConfig {
  static const configuredBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const userId = int.fromEnvironment('USER_ID', defaultValue: 1);

  static String get baseUrl {
    if (configuredBaseUrl.trim().isNotEmpty) {
      return configuredBaseUrl.replaceAll(RegExp(r'/$'), '');
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8080';
    }
    return 'http://localhost:8080';
  }
}
