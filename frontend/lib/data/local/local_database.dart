import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common/sqlite_api.dart' show DatabaseFactory, DatabaseExecutor;
import 'sqflite_web_factory_stub.dart'
    if (dart.library.js_interop) 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart' as ffi_web;

/// PlanBlindBox 本地数据库入口。
/// Android/iOS 使用 sqflite；Flutter Web 使用 SQLite WASM + IndexedDB。
class LocalDatabase {
  LocalDatabase._({DatabaseFactory? testFactory, String? testPath})
      : _testFactory = testFactory,
        _testPath = testPath;

  static final LocalDatabase instance = LocalDatabase._();

  /// 测试专用构造器：传入 sqflite_common_ffi 的 databaseFactoryFfi。
  factory LocalDatabase.forTesting({
    required DatabaseFactory factory,
    String path = ':memory:',
  }) =>
      LocalDatabase._(testFactory: factory, testPath: path);

  final DatabaseFactory? _testFactory;
  final String? _testPath;
  Future<Database>? _opening;
  String? _openedPath;

  Future<Database> get database => _opening ??= _open();

  /// 当前数据库的存储位置。Web 返回数据库标识，不暴露浏览器真实文件路径。
  Future<Map<String, dynamic>> getStorageInfo() async {
    final db = await database;
    return {
      'engine': kIsWeb ? 'SQLite WASM + IndexedDB' : 'SQLite（sqflite）',
      'location': kIsWeb ? '浏览器当前站点的 IndexedDB 本地存储' : (_openedPath ?? '本机应用数据库目录'),
      'databaseName': p.basename(_openedPath ?? 'plan_blind_box_v1.db'),
      'schemaVersion': await db.getVersion(),
      'platform': kIsWeb ? 'Web' : 'Native',
    };
  }

  Future<void> initialize() async {
    await database;
  }

  Future<Database> _open() async {
    final DatabaseFactory factory;
    final String path;

    if (_testFactory != null) {
      factory = _testFactory!;
      path = _testPath ?? ':memory:';
    } else if (kIsWeb) {
      final webFactory = ffi_web.databaseFactoryFfiWeb;
      if (webFactory == null) {
        throw StateError('Web SQLite 驱动未加载，请检查 sqflite_common_ffi_web 依赖。');
      }
      factory = webFactory;
      path = 'plan_blind_box_v1.db';
    } else {
      factory = databaseFactory;
      final directory = await getDatabasesPath();
      path = p.join(directory, 'plan_blind_box_v1.db');
    }

    _openedPath = path;
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 4,
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) await _createCustomShopSchema(db);
          if (oldVersion < 3) await _upgradeProductCategories(db);
          if (oldVersion < 4) await _createWellbeingSchema(db);
        },
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _createSchema,
      ),
    );
  }

  Future<void> close() async {
    final db = await _opening;
    if (db != null) await db.close();
    _opening = null;
  }

  Future<void> _createSchema(Database db, int version) async {
    final statements = <String>[
      '''CREATE TABLE user_assets (
        user_id INTEGER PRIMARY KEY,
        coin INTEGER NOT NULL DEFAULT 0,
        exp INTEGER NOT NULL DEFAULT 0,
        water INTEGER NOT NULL DEFAULT 0,
        update_time TEXT NOT NULL
      )''',
      '''CREATE TABLE tasks (
        task_id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        category_id INTEGER,
        title TEXT NOT NULL,
        note TEXT,
        start_time TEXT,
        end_time TEXT,
        target_count INTEGER NOT NULL DEFAULT 1,
        recurrence_type TEXT NOT NULL DEFAULT 'ONCE',
        repeat_interval_days INTEGER,
        repeat_days TEXT,
        cycle_days INTEGER,
        recurrence_end_date TEXT,
        status TEXT NOT NULL DEFAULT 'PENDING',
        importance INTEGER,
        urgency INTEGER,
        difficulty INTEGER,
        priority_score REAL,
        estimated_minutes INTEGER,
        record_rule TEXT,
        create_time TEXT NOT NULL,
        update_time TEXT NOT NULL
      )''',
      '''CREATE TABLE task_records (
        task_record_id INTEGER PRIMARY KEY AUTOINCREMENT,
        task_id INTEGER NOT NULL,
        record_date TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'IN_PROGRESS',
        finish_time TEXT,
        actual_count INTEGER NOT NULL DEFAULT 0,
        create_time TEXT NOT NULL,
        update_time TEXT NOT NULL,
        UNIQUE(task_id, record_date),
        FOREIGN KEY(task_id) REFERENCES tasks(task_id) ON DELETE CASCADE
      )''',
      '''CREATE TABLE task_cycle_records (
        cycle_record_id INTEGER PRIMARY KEY AUTOINCREMENT,
        task_id INTEGER NOT NULL,
        cycle_start_date TEXT NOT NULL,
        cycle_end_date TEXT NOT NULL,
        target_count INTEGER NOT NULL,
        actual_count INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'IN_PROGRESS',
        reward_granted INTEGER NOT NULL DEFAULT 0,
        completed_at TEXT,
        create_time TEXT NOT NULL,
        update_time TEXT NOT NULL,
        UNIQUE(task_id, cycle_start_date),
        FOREIGN KEY(task_id) REFERENCES tasks(task_id) ON DELETE CASCADE
      )''',
      '''CREATE TABLE habits (
        habit_id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        note TEXT,
        start_date TEXT NOT NULL,
        end_date TEXT,
        repeat_rule TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'ACTIVE',
        importance INTEGER NOT NULL DEFAULT 3,
        difficulty INTEGER NOT NULL DEFAULT 3,
        create_time TEXT NOT NULL,
        update_time TEXT NOT NULL
      )''',
      '''CREATE TABLE habit_records (
        habit_record_id INTEGER PRIMARY KEY AUTOINCREMENT,
        habit_id INTEGER NOT NULL,
        record_date TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'PENDING',
        finish_time TEXT,
        actual_count INTEGER NOT NULL DEFAULT 0,
        create_time TEXT NOT NULL,
        update_time TEXT NOT NULL,
        UNIQUE(habit_id, record_date),
        FOREIGN KEY(habit_id) REFERENCES habits(habit_id) ON DELETE CASCADE
      )''',
      '''CREATE TABLE task_categories (
        category_id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        color TEXT NOT NULL DEFAULT '#607D8B',
        icon TEXT,
        is_default INTEGER NOT NULL DEFAULT 0,
        enabled INTEGER NOT NULL DEFAULT 1,
        create_time TEXT NOT NULL,
        update_time TEXT NOT NULL,
        UNIQUE(user_id, name)
      )''',
      '''CREATE TABLE time_records (
        time_record_id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        task_id INTEGER,
        title TEXT NOT NULL,
        category TEXT NOT NULL DEFAULT '其他',
        start_time TEXT NOT NULL,
        end_time TEXT NOT NULL,
        duration_minutes INTEGER NOT NULL,
        record_date TEXT NOT NULL,
        note TEXT,
        create_time TEXT NOT NULL,
        update_time TEXT NOT NULL,
        FOREIGN KEY(task_id) REFERENCES tasks(task_id) ON DELETE SET NULL
      )''',
      '''CREATE TABLE asset_records (
        record_id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        action TEXT NOT NULL,
        asset_type TEXT NOT NULL,
        amount INTEGER NOT NULL,
        source TEXT,
        source_id INTEGER,
        create_time TEXT NOT NULL
      )''',
      '''CREATE TABLE daily_sign_ins (
        sign_in_id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        business_date TEXT NOT NULL,
        streak_day INTEGER NOT NULL,
        base_water INTEGER NOT NULL DEFAULT 5,
        bonus_water INTEGER NOT NULL DEFAULT 0,
        total_water INTEGER NOT NULL,
        create_time TEXT NOT NULL,
        UNIQUE(user_id, business_date)
      )''',
      '''CREATE TABLE content_packs (
        pack_id INTEGER PRIMARY KEY AUTOINCREMENT,
        pack_key TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        version TEXT NOT NULL DEFAULT '1.0.0',
        unlock_level INTEGER NOT NULL DEFAULT 1,
        status TEXT NOT NULL DEFAULT 'PUBLISHED'
      )''',
      '''CREATE TABLE collectible_items (
        item_id INTEGER PRIMARY KEY AUTOINCREMENT,
        pack_id INTEGER NOT NULL,
        item_key TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        rarity TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        image_path TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        enabled INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY(pack_id) REFERENCES content_packs(pack_id)
      )''',
      '''CREATE TABLE user_collectibles (
        user_id INTEGER NOT NULL,
        item_id INTEGER NOT NULL,
        owned_count INTEGER NOT NULL DEFAULT 0,
        first_obtained_time TEXT NOT NULL,
        last_obtained_time TEXT NOT NULL,
        PRIMARY KEY(user_id, item_id),
        FOREIGN KEY(item_id) REFERENCES collectible_items(item_id)
      )''',
      '''CREATE TABLE collectible_acquisition_records (
        acquisition_record_id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        item_id INTEGER NOT NULL,
        quantity INTEGER NOT NULL,
        source_type TEXT NOT NULL,
        source_id INTEGER,
        create_time TEXT NOT NULL,
        FOREIGN KEY(item_id) REFERENCES collectible_items(item_id)
      )''',
      '''CREATE TABLE shop_boxes (
        box_id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        price_coin INTEGER NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 1
      )''',
      '''CREATE TABLE shop_rewards (
        reward_id INTEGER PRIMARY KEY AUTOINCREMENT,
        box_id INTEGER NOT NULL,
        code TEXT NOT NULL,
        asset_type TEXT NOT NULL,
        amount INTEGER NOT NULL,
        item_id INTEGER,
        weight INTEGER NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 1,
        UNIQUE(box_id, code),
        FOREIGN KEY(box_id) REFERENCES shop_boxes(box_id),
        FOREIGN KEY(item_id) REFERENCES collectible_items(item_id)
      )''',
      '''CREATE TABLE shop_open_records (
        open_id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        box_id INTEGER NOT NULL,
        request_id TEXT NOT NULL,
        reward_id INTEGER NOT NULL,
        collectible_item_id INTEGER,
        box_name TEXT NOT NULL,
        item_name TEXT,
        item_rarity TEXT,
        item_image_path TEXT,
        item_description TEXT,
        price_coin INTEGER NOT NULL,
        reward_type TEXT NOT NULL,
        reward_amount INTEGER NOT NULL,
        coin_balance_after INTEGER,
        exp_balance_after INTEGER,
        water_balance_after INTEGER,
        created_at TEXT NOT NULL,
        UNIQUE(user_id, request_id),
        FOREIGN KEY(box_id) REFERENCES shop_boxes(box_id),
        FOREIGN KEY(reward_id) REFERENCES shop_rewards(reward_id),
        FOREIGN KEY(collectible_item_id) REFERENCES collectible_items(item_id)
      )''',
      '''CREATE TABLE app_settings (
        setting_key TEXT PRIMARY KEY,
        setting_value TEXT NOT NULL,
        update_time TEXT NOT NULL
      )''',
      'CREATE INDEX idx_tasks_user_status ON tasks(user_id, status)',
      'CREATE INDEX idx_tasks_user_end ON tasks(user_id, end_time)',
      'CREATE INDEX idx_task_records_date ON task_records(record_date, task_id)',
      'CREATE INDEX idx_habits_user_status ON habits(user_id, status)',
      'CREATE INDEX idx_habit_records_date ON habit_records(record_date, habit_id)',
      'CREATE INDEX idx_time_records_user_date ON time_records(user_id, record_date, start_time)',
      'CREATE INDEX idx_asset_records_user_time ON asset_records(user_id, create_time)',
      'CREATE INDEX idx_shop_open_user_time ON shop_open_records(user_id, created_at)',
      'CREATE INDEX idx_collectible_pack_order ON collectible_items(pack_id, sort_order)',
    ];

    for (final statement in statements) {
      await db.execute(statement);
    }
    await _seedCatalog(db);
    await _createCustomShopSchema(db);
    await _upgradeProductCategories(db);
    await _createWellbeingSchema(db);
  }

  /// 每日情绪、经期、日记（与账号资料分离），数据库升级只新增表，不清空旧数据。
  Future<void> _createWellbeingSchema(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS wellbeing_entries (
      user_id INTEGER NOT NULL,
      business_date TEXT NOT NULL,
      mood_name TEXT,
      mood_emoji TEXT,
      period INTEGER NOT NULL DEFAULT 0 CHECK(period IN (0,1)),
      diary TEXT NOT NULL DEFAULT '',
      update_time TEXT NOT NULL,
      PRIMARY KEY(user_id, business_date)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS wellbeing_moods (
      user_id INTEGER NOT NULL,
      name TEXT NOT NULL,
      emoji TEXT NOT NULL,
      created_at TEXT NOT NULL,
      PRIMARY KEY(user_id, name),
      UNIQUE(user_id, emoji)
    )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_wellbeing_diary_date ON wellbeing_entries(user_id, business_date)');
  }

  /// 自定义商品、购买与仓库，与现有盲盒业务独立。
  Future<void> _createCustomShopSchema(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS custom_products (
      product_id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL,
      name TEXT NOT NULL,
      description TEXT NOT NULL DEFAULT '',
      image_base64 TEXT,
      price_coin INTEGER NOT NULL CHECK(price_coin >= 0),
      stock INTEGER NOT NULL DEFAULT 0 CHECK(stock >= 0),
      kind TEXT NOT NULL CHECK(kind IN ('CONSUMABLE','COLLECTIBLE')),
      enabled INTEGER NOT NULL DEFAULT 1,
      create_time TEXT NOT NULL,
      update_time TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS custom_inventory (
      user_id INTEGER NOT NULL,
      product_id INTEGER NOT NULL,
      quantity INTEGER NOT NULL DEFAULT 0 CHECK(quantity >= 0),
      update_time TEXT NOT NULL,
      PRIMARY KEY (user_id, product_id),
      FOREIGN KEY(product_id) REFERENCES custom_products(product_id)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS custom_purchase_records (
      purchase_id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL,
      product_id INTEGER NOT NULL,
      request_id TEXT NOT NULL,
      price_coin INTEGER NOT NULL,
      create_time TEXT NOT NULL,
      UNIQUE(user_id, request_id),
      FOREIGN KEY(product_id) REFERENCES custom_products(product_id)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS custom_use_records (
      use_id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL,
      product_id INTEGER NOT NULL,
      quantity INTEGER NOT NULL DEFAULT 1,
      create_time TEXT NOT NULL,
      FOREIGN KEY(product_id) REFERENCES custom_products(product_id)
    )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_custom_products_user ON custom_products(user_id, enabled, product_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_custom_purchases_user ON custom_purchase_records(user_id, create_time)');
  }

  /// 商品种类和消耗属性彼此独立，旧商品自动归入「默认」。
  Future<void> _upgradeProductCategories(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS custom_product_categories (
      category_id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL,
      name TEXT NOT NULL,
      UNIQUE(user_id, name)
    )''');
    final columns = await db.rawQuery('PRAGMA table_info(custom_products)');
    if (!columns.any((column) => column['name'] == 'category_name')) {
      await db.execute("ALTER TABLE custom_products ADD COLUMN category_name TEXT NOT NULL DEFAULT '默认'");
    }
  }

  Future<void> _seedCatalog(DatabaseExecutor db) async {
    await db.insert('content_packs', {
      'pack_id': 1,
      'pack_key': 'butterfly-pack',
      'name': '蝴蝶图鉴',
      'description': '以不同艺术风格呈现的蝴蝶收藏系列。',
      'version': '1.0.0',
      'unlock_level': 1,
      'status': 'PUBLISHED',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    const items = <Map<String, Object>>[
      {'item_id': 1, 'item_key': 'oil_blue_yellow', 'name': '油彩花草蝶', 'rarity': 'COMMON', 'description': '蓝黄蝶翼在油画般的花草间展开。', 'image_path': '/collectibles/butterfly/butterfly_oil_meadow.png', 'sort_order': 1},
      {'item_id': 2, 'item_key': 'warm_lattice_shadow', 'name': '暖影镂彩蝶', 'rarity': 'RARE', 'description': '暖金色镂空蝶翼，带有皮影艺术的装饰感。', 'image_path': '/collectibles/butterfly/butterfly_warm_shadow.png', 'sort_order': 2},
      {'item_id': 3, 'item_key': 'gothic_moon_beaded', 'name': '月下哥特蝶', 'rarity': 'LEGENDARY', 'description': '暗红珠饰与哥特花纹构成神秘的月下蝶影。', 'image_path': '/collectibles/butterfly/butterfly_gothic_moon.png', 'sort_order': 3},
      {'item_id': 4, 'item_key': 'violet_garden_dream', 'name': '紫罗兰梦蝶', 'rarity': 'RARE', 'description': '紫罗兰色蝶翼融入柔和的梦幻花园。', 'image_path': '/collectibles/butterfly/butterfly_violet_garden.png', 'sort_order': 4},
      {'item_id': 5, 'item_key': 'crystal_ice_realm', 'name': '冰晶幻蝶', 'rarity': 'EPIC', 'description': '由晶莹冰晶与冷色光芒构成的幻想蝶翼。', 'image_path': '/collectibles/butterfly/butterfly_crystal_ice.png', 'sort_order': 5},
      {'item_id': 6, 'item_key': 'pop_art_colorful', 'name': '波普彩蝶', 'rarity': 'COMMON', 'description': '以高饱和撞色和波普艺术风格呈现的缤纷蝶翼。', 'image_path': '/collectibles/butterfly/butterfly_pop_art.png', 'sort_order': 6},
      {'item_id': 7, 'item_key': 'pointillism_dream', 'name': '点彩幻蝶', 'rarity': 'COMMON', 'description': '细密色点汇聚成梦境般的彩色蝶翼。', 'image_path': '/collectibles/butterfly/butterfly_pointillism.png', 'sort_order': 7},
      {'item_id': 8, 'item_key': 'mechanical_gear_realm', 'name': '齿轮机械蝶', 'rarity': 'EPIC', 'description': '精密齿轮与金属结构环绕发光的机械蝶翼。', 'image_path': '/collectibles/butterfly/butterfly_mechanical_gear.png', 'sort_order': 8},
      {'item_id': 9, 'item_key': 'embroidered_garden', 'name': '锦绣花园蝶', 'rarity': 'COMMON', 'description': '以花卉刺绣和丰富纹样装饰的彩翼蝴蝶。', 'image_path': '/collectibles/butterfly/butterfly_embroidery_garden.png', 'sort_order': 9},
      {'item_id': 10, 'item_key': 'golden_sakura_waves', 'name': '金彩樱海蝶', 'rarity': 'RARE', 'description': '金色纹样、樱花与海浪元素交织成华丽蝶翼。', 'image_path': '/collectibles/butterfly/butterfly_golden_sakura.png', 'sort_order': 10},
      {'item_id': 11, 'item_key': 'gilded_ice_blue_silk', 'name': '鎏金冰纱蝶', 'rarity': 'EPIC', 'description': '鎏金边饰与冰蓝薄纱交织出轻盈而华丽的蝶翼。', 'image_path': '/collectibles/butterfly/butterfly_gilded_ice_silk.png', 'sort_order': 11},
      {'item_id': 12, 'item_key': 'cosmic_nebula', 'name': '星云宇宙蝶', 'rarity': 'LEGENDARY', 'description': '霓虹蓝紫色蝶翼仿佛映照着遥远星云。', 'image_path': '/collectibles/butterfly/butterfly_cosmic_nebula.png', 'sort_order': 12},
    ];
    for (final item in items) {
      await db.insert('collectible_items', {
        'pack_id': 1,
        'enabled': 1,
        ...item,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    await db.insert('shop_boxes', {
      'box_id': 1,
      'code': 'NORMAL',
      'name': '普通盲盒',
      'description': '用金币兑换一次小惊喜',
      'price_coin': 50,
      'enabled': 1,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert('shop_boxes', {
      'box_id': 2,
      'code': 'PREMIUM',
      'name': '高级盲盒',
      'description': '奖励更丰富的进阶盲盒',
      'price_coin': 200,
      'enabled': 1,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    const normalRewards = <Map<String, Object?>>[
      {'code': 'COIN_15', 'asset_type': 'COIN', 'amount': 15, 'weight': 50},
      {'code': 'EXP_30', 'asset_type': 'EXP', 'amount': 30, 'weight': 35},
      {'code': 'BFLY_OIL_MEADOW', 'asset_type': 'COLLECTIBLE', 'amount': 1, 'item_id': 1, 'weight': 3},
      {'code': 'BFLY_WARM_SHADOW', 'asset_type': 'COLLECTIBLE', 'amount': 1, 'item_id': 2, 'weight': 2},
      {'code': 'BFLY_GOTHIC_MOON', 'asset_type': 'COLLECTIBLE', 'amount': 1, 'item_id': 3, 'weight': 1},
      {'code': 'BFLY_VIOLET_GARDEN', 'asset_type': 'COLLECTIBLE', 'amount': 1, 'item_id': 4, 'weight': 2},
      {'code': 'BFLY_CRYSTAL_ICE', 'asset_type': 'COLLECTIBLE', 'amount': 1, 'item_id': 5, 'weight': 1},
      {'code': 'BFLY_POP_ART', 'asset_type': 'COLLECTIBLE', 'amount': 1, 'item_id': 6, 'weight': 3},
      {'code': 'BFLY_POINTILLISM', 'asset_type': 'COLLECTIBLE', 'amount': 1, 'item_id': 7, 'weight': 3},
      {'code': 'BFLY_MECHANICAL_GEAR', 'asset_type': 'COLLECTIBLE', 'amount': 1, 'item_id': 8, 'weight': 1},
      {'code': 'BFLY_EMBROIDERY', 'asset_type': 'COLLECTIBLE', 'amount': 1, 'item_id': 9, 'weight': 3},
      {'code': 'BFLY_GOLDEN_SAKURA', 'asset_type': 'COLLECTIBLE', 'amount': 1, 'item_id': 10, 'weight': 2},
      {'code': 'BFLY_GILDED_ICE_SILK', 'asset_type': 'COLLECTIBLE', 'amount': 1, 'item_id': 11, 'weight': 1},
      {'code': 'BFLY_COSMIC_NEBULA', 'asset_type': 'COLLECTIBLE', 'amount': 1, 'item_id': 12, 'weight': 1},
    ];
    const premiumRewards = <Map<String, Object?>>[
      {'code': 'COIN_100', 'asset_type': 'COIN', 'amount': 100, 'weight': 40},
      {'code': 'EXP_200', 'asset_type': 'EXP', 'amount': 200, 'weight': 40},
      {'code': 'BFLY_OIL_MEADOW', 'asset_type': 'COLLECTIBLE', 'amount': 1, 'item_id': 1, 'weight': 3},
      {'code': 'BFLY_WARM_SHADOW', 'asset_type': 'COLLECTIBLE', 'amount': 1, 'item_id': 2, 'weight': 4},
      {'code': 'BFLY_GOTHIC_MOON', 'asset_type': 'COLLECTIBLE', 'amount': 1, 'item_id': 3, 'weight': 5},
      {'code': 'BFLY_VIOLET_GARDEN', 'asset_type': 'COLLECTIBLE', 'amount': 1, 'item_id': 4, 'weight': 4},
      {'code': 'BFLY_CRYSTAL_ICE', 'asset_type': 'COLLECTIBLE', 'amount': 1, 'item_id': 5, 'weight': 6},
      {'code': 'BFLY_POP_ART', 'asset_type': 'COLLECTIBLE', 'amount': 1, 'item_id': 6, 'weight': 3},
      {'code': 'BFLY_POINTILLISM', 'asset_type': 'COLLECTIBLE', 'amount': 1, 'item_id': 7, 'weight': 3},
      {'code': 'BFLY_MECHANICAL_GEAR', 'asset_type': 'COLLECTIBLE', 'amount': 1, 'item_id': 8, 'weight': 6},
      {'code': 'BFLY_EMBROIDERY', 'asset_type': 'COLLECTIBLE', 'amount': 1, 'item_id': 9, 'weight': 3},
      {'code': 'BFLY_GOLDEN_SAKURA', 'asset_type': 'COLLECTIBLE', 'amount': 1, 'item_id': 10, 'weight': 4},
      {'code': 'BFLY_GILDED_ICE_SILK', 'asset_type': 'COLLECTIBLE', 'amount': 1, 'item_id': 11, 'weight': 6},
      {'code': 'BFLY_COSMIC_NEBULA', 'asset_type': 'COLLECTIBLE', 'amount': 1, 'item_id': 12, 'weight': 5},
    ];
    for (final reward in normalRewards) {
      await db.insert('shop_rewards', {
        'box_id': 1,
        'enabled': 1,
        ...reward,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    for (final reward in premiumRewards) {
      await db.insert('shop_rewards', {
        'box_id': 2,
        'enabled': 1,
        ...reward,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }
}
