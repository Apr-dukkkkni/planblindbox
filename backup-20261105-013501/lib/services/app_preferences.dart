import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../data/local/local_database.dart';

/// 本地应用偏好设置。设置保存在 SQLite 的 app_settings 表中。
class AppPreferences extends ChangeNotifier {
  AppPreferences._();

  static final AppPreferences instance = AppPreferences._();

  static const Map<String, String> availableTabs = {
    'today': '今日',
    'time': '时间',
    'store': '商店',
    'stats': '统计',
    'mine': '我的',
  };

  static const String _defaultTabKey = 'default_tab';
  static const String _showSignInNoticeKey = 'show_daily_sign_in_notice';

  String _defaultTab = 'today';
  bool _showDailySignInNotice = true;
  bool _loaded = false;

  String get defaultTab => _defaultTab;
  int get defaultTabIndex => availableTabs.keys.toList().indexOf(_defaultTab);
  bool get showDailySignInNotice => _showDailySignInNotice;
  bool get isLoaded => _loaded;

  Future<void> load() => reload();

  /// 备份恢复或重置数据后重新从数据库读取偏好设置。
  Future<void> reload() async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.query(
      'app_settings',
      columns: ['setting_key', 'setting_value'],
      where: 'setting_key IN (?, ?)',
      whereArgs: [_defaultTabKey, _showSignInNoticeKey],
    );
    final values = <String, String>{
      for (final row in rows)
        row['setting_key'].toString(): row['setting_value'].toString(),
    };

    final savedTab = values[_defaultTabKey];
    _defaultTab = availableTabs.containsKey(savedTab) ? savedTab! : 'today';
    _showDailySignInNotice = values[_showSignInNoticeKey] != 'false';
    _loaded = true;
    notifyListeners();
  }

  Future<void> setDefaultTab(String value) async {
    if (!availableTabs.containsKey(value)) {
      throw ArgumentError.value(value, 'value', '不支持的默认首页');
    }
    await _write(_defaultTabKey, value);
    _defaultTab = value;
    notifyListeners();
  }

  Future<void> setShowDailySignInNotice(bool value) async {
    await _write(_showSignInNoticeKey, value.toString());
    _showDailySignInNotice = value;
    notifyListeners();
  }

  Future<void> _write(String key, String value) async {
    final db = await LocalDatabase.instance.database;
    await db.insert(
      'app_settings',
      {
        'setting_key': key,
        'setting_value': value,
        'update_time': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
