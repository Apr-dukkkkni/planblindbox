import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// PlanBlindBox 本地优先数据库。
///
/// V1 从空库开始，不导入旧 MySQL 数据。所有核心业务表都属于本地数据库；
/// 后续云备份应基于一致性快照，而不是直接复制正在使用的 db 文件。
class LocalDatabase {
  LocalDatabase._();

  static final LocalDatabase instance = LocalDatabase._();
  static const int schemaVersion = 1;
  static const String databaseName = 'plan_blind_box_local.db';

  Database? _database;

  Future<Database> get database async {
    final opened = _database;
    if (opened != null && opened.isOpen) return opened;

    final root = await getDatabasesPath();
    final db = await openDatabase(
      p.join(root, databaseName),
      version: schemaVersion,
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
        await database.execute('PRAGMA busy_timeout = 5000');
      },
      onCreate: _createSchema,
      onUpgrade: _upgradeSchema,
    );
    _database = db;
    return db;
  }

  Future<void> close() async {
    final db = _database;
    _database = null;
    if (db != null && db.isOpen) await db.close();
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.transaction((txn) async {
      await txn.execute('''
        CREATE TABLE app_meta (
          meta_key TEXT PRIMARY KEY,
          meta_value TEXT NOT NULL,
          update_time TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      ''');

      await txn.execute('''
        CREATE TABLE task_category (
          category_id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          color TEXT NOT NULL DEFAULT '#7A9E7E',
          enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
          sort_order INTEGER NOT NULL DEFAULT 0,
          create_time TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          update_time TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      ''');

      await txn.execute('''
        CREATE TABLE task (
          task_id INTEGER PRIMARY KEY AUTOINCREMENT,
          category_id INTEGER,
          title TEXT NOT NULL,
          note TEXT,
          start_time TEXT,
          end_time TEXT,
          target_count INTEGER NOT NULL DEFAULT 1 CHECK (target_count > 0),
          recurrence_type TEXT NOT NULL DEFAULT 'ONCE',
          repeat_interval_days INTEGER,
          repeat_days TEXT,
          cycle_days INTEGER,
          recurrence_end_date TEXT,
          status TEXT NOT NULL DEFAULT 'PENDING',
          importance INTEGER CHECK (importance BETWEEN 1 AND 5),
          urgency INTEGER CHECK (urgency BETWEEN 1 AND 5),
          difficulty INTEGER CHECK (difficulty BETWEEN 1 AND 5),
          priority_score REAL,
          estimated_minutes INTEGER,
          record_rule TEXT,
          create_time TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          update_time TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (category_id) REFERENCES task_category(category_id) ON DELETE SET NULL
        )
      ''');
      await txn.execute('CREATE INDEX idx_task_status_end_time ON task(status, end_time)');
      await txn.execute('CREATE INDEX idx_task_category ON task(category_id)');

      await txn.execute('''
        CREATE TABLE task_record (
          record_id INTEGER PRIMARY KEY AUTOINCREMENT,
          task_id INTEGER NOT NULL,
          record_date TEXT NOT NULL,
          actual_count INTEGER NOT NULL DEFAULT 1 CHECK (actual_count > 0),
          note TEXT,
          create_time TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (task_id) REFERENCES task(task_id) ON DELETE CASCADE
        )
      ''');
      await txn.execute('CREATE INDEX idx_task_record_date ON task_record(record_date, task_id)');

      await txn.execute('''
        CREATE TABLE habit (
          habit_id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          note TEXT,
          start_date TEXT NOT NULL,
          end_date TEXT,
          repeat_rule TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'ACTIVE',
          importance INTEGER NOT NULL DEFAULT 3 CHECK (importance BETWEEN 1 AND 5),
          difficulty INTEGER NOT NULL DEFAULT 3 CHECK (difficulty BETWEEN 1 AND 5),
          create_time TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          update_time TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      ''');
      await txn.execute('CREATE INDEX idx_habit_status ON habit(status)');

      await txn.execute('''
        CREATE TABLE habit_check_in (
          check_in_id INTEGER PRIMARY KEY AUTOINCREMENT,
          habit_id INTEGER NOT NULL,
          business_date TEXT NOT NULL,
          note TEXT,
          create_time TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          UNIQUE(habit_id, business_date),
          FOREIGN KEY (habit_id) REFERENCES habit(habit_id) ON DELETE CASCADE
        )
      ''');
      await txn.execute('CREATE INDEX idx_habit_check_in_date ON habit_check_in(business_date)');

      await txn.execute('''
        CREATE TABLE user_asset (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          coin INTEGER NOT NULL DEFAULT 0 CHECK (coin >= 0),
          exp INTEGER NOT NULL DEFAULT 0 CHECK (exp >= 0),
          water INTEGER NOT NULL DEFAULT 0 CHECK (water >= 0),
          update_time TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      ''');
      await txn.insert('user_asset', {'id': 1, 'coin': 0, 'exp': 0, 'water': 0});

      await txn.execute('''
        CREATE TABLE asset_record (
          record_id INTEGER PRIMARY KEY AUTOINCREMENT,
          action TEXT NOT NULL,
          asset_type TEXT NOT NULL CHECK (asset_type IN ('COIN', 'EXP', 'WATER')),
          amount INTEGER NOT NULL CHECK (amount <> 0),
          source TEXT NOT NULL,
          source_id TEXT NOT NULL,
          create_time TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          UNIQUE(action, asset_type, source, source_id)
        )
      ''');
      await txn.execute('CREATE INDEX idx_asset_record_time ON asset_record(create_time DESC)');

      await txn.execute('''
        CREATE TABLE daily_sign_in (
          sign_in_id INTEGER PRIMARY KEY AUTOINCREMENT,
          business_date TEXT NOT NULL UNIQUE,
          streak_day INTEGER NOT NULL CHECK (streak_day > 0),
          base_water INTEGER NOT NULL,
          bonus_water INTEGER NOT NULL,
          total_water INTEGER NOT NULL,
          create_time TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      ''');

      await txn.execute('''
        CREATE TABLE shop_box (
          box_id INTEGER PRIMARY KEY AUTOINCREMENT,
          code TEXT NOT NULL UNIQUE,
          name TEXT NOT NULL,
          description TEXT,
          price_coin INTEGER NOT NULL CHECK (price_coin > 0),
          enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
          sort_order INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await txn.execute('''
        CREATE TABLE shop_reward (
          reward_id INTEGER PRIMARY KEY AUTOINCREMENT,
          box_id INTEGER NOT NULL,
          code TEXT NOT NULL,
          asset_type TEXT NOT NULL,
          amount INTEGER NOT NULL CHECK (amount > 0),
          item_id INTEGER,
          weight INTEGER NOT NULL CHECK (weight > 0),
          enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
          FOREIGN KEY (box_id) REFERENCES shop_box(box_id) ON DELETE CASCADE
        )
      ''');
      await txn.execute('CREATE INDEX idx_shop_reward_enabled ON shop_reward(box_id, enabled)');
      await txn.execute('''
        CREATE TABLE collectible_item (
          item_id INTEGER PRIMARY KEY AUTOINCREMENT,
          code TEXT NOT NULL UNIQUE,
          name TEXT NOT NULL,
          rarity TEXT NOT NULL,
          description TEXT,
          image_path TEXT
        )
      ''');
      await txn.execute('''
        CREATE TABLE collectible_inventory (
          item_id INTEGER PRIMARY KEY,
          quantity INTEGER NOT NULL DEFAULT 0 CHECK (quantity >= 0),
          FOREIGN KEY (item_id) REFERENCES collectible_item(item_id) ON DELETE RESTRICT
        )
      ''');
      await txn.execute('''
        CREATE TABLE shop_open_record (
          open_id INTEGER PRIMARY KEY AUTOINCREMENT,
          box_id INTEGER NOT NULL,
          box_name TEXT NOT NULL,
          reward_id INTEGER NOT NULL,
          reward_type TEXT NOT NULL,
          reward_amount INTEGER NOT NULL,
          item_id INTEGER,
          item_name TEXT,
          price_coin INTEGER NOT NULL,
          create_time TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      ''');

      await txn.execute('''
        CREATE TABLE time_record (
          record_id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          category TEXT NOT NULL,
          start_time TEXT NOT NULL,
          end_time TEXT NOT NULL,
          task_id INTEGER,
          note TEXT,
          create_time TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          CHECK (end_time > start_time),
          FOREIGN KEY (task_id) REFERENCES task(task_id) ON DELETE SET NULL
        )
      ''');
      await txn.execute('CREATE INDEX idx_time_record_start ON time_record(start_time DESC)');

      await txn.insert('task_category', {
        'name': '默认', 'color': '#7A9E7E', 'enabled': 1, 'sort_order': 0,
      });
      await txn.insert('app_meta', {
        'meta_key': 'data_generation',
        'meta_value': 'local-first-v1',
      });
      await txn.insert('app_meta', {
        'meta_key': 'created_from_empty_install',
        'meta_value': 'true',
      });
    });
  }

  Future<void> _upgradeSchema(Database db, int oldVersion, int newVersion) async {
    // 每个正式版本在此增加显式迁移脚本；禁止通过删除数据库升级。
    if (oldVersion < 1) {
      throw StateError('不支持从未知数据库版本升级：$oldVersion');
    }
  }

  /// 用于业务服务把“业务记录、资产余额、资产流水”放进同一个事务。
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) async {
    final db = await database;
    return db.transaction(action);
  }
}
