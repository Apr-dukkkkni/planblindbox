import 'package:sqflite_common/sqlite_api.dart';

/// 非 Web 平台占位；实际 Web 实现由 conditional import 加载。
DatabaseFactory? get databaseFactoryFfiWeb => null;
