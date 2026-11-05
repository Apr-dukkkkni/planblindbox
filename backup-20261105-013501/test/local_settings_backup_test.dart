import 'package:flutter_test/flutter_test.dart';
import 'package:plan_blind_box/data/local/local_database.dart';
import 'package:plan_blind_box/data/local/local_plan_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late LocalDatabase database;
  late LocalPlanRepository repository;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    database = LocalDatabase.forTesting(factory: databaseFactoryFfi);
    await database.initialize();
    repository = LocalPlanRepository(userId: 1, localDatabase: database);
    await repository.ensureReady();
  });

  tearDown(() async {
    await database.close();
  });

  test('每日签到分别返回月度连续、历史连续和累计天数', () async {
    final first = await repository.dailySignIn();
    expect(first['granted'], true);
    expect(first['monthlyStreakDay'], 1);
    expect(first['allTimeStreakDay'], 1);
    expect(first['totalSignInDays'], 1);

    final repeated = await repository.dailySignIn();
    expect(repeated['granted'], false);
    expect(repeated['monthlyStreakDay'], 1);
    expect(repeated['allTimeStreakDay'], 1);
    expect(repeated['totalSignInDays'], 1);

    final stats = await repository.getDailySignInStats();
    expect(stats['monthlyStreakDay'], 1);
    expect(stats['allTimeStreakDay'], 1);
    expect(stats['longestStreakDay'], 1);
    expect(stats['totalSignInDays'], 1);
  });

  test('月初重置月度连续，但历史连续和累计天数跨月保留', () async {
    final db = await database.database;
    final repositoryAtMonthStart = LocalPlanRepository(
      userId: 1,
      localDatabase: database,
      clock: () => DateTime(2026, 11, 1, 6),
    );

    for (final date in ['2026-10-30', '2026-10-31']) {
      await db.insert('daily_sign_ins', {
        'user_id': 1,
        'business_date': date,
        'streak_day': date.endsWith('30') ? 30 : 31,
        'base_water': 5,
        'bonus_water': 0,
        'total_water': 5,
        'create_time': '${date}T06:00:00',
      });
    }

    final result = await repositoryAtMonthStart.dailySignIn();

    expect(result['monthlyStreakDay'], 1);
    expect(result['allTimeStreakDay'], 3);
    expect(result['longestStreakDay'], 3);
    expect(result['totalSignInDays'], 3);
    expect(result['bonusWater'], 0);
    expect(result['totalWater'], 5);
  });

  test('本地备份可以完整恢复业务数据和偏好设置', () async {
    await repository.createTask(
      title: '备份测试任务',
      note: '需要被恢复',
      targetCount: 2,
      importance: 3,
      difficulty: 3,
      categoryId: 0,
      recordRule: const {'mode': 'DEFAULT'},
    );
    await repository.setAppSetting('default_tab', 'stats');
    await repository.setAppSetting('show_daily_sign_in_notice', 'false');

    final backup = await repository.exportBackupJson();
    await repository.resetLocalData(resetPreferences: true);
    expect(await repository.getAllTasks(), isEmpty);

    await repository.restoreBackupJson(backup);

    final tasks = await repository.getAllTasks();
    expect(tasks, hasLength(1));
    expect(tasks.single['title'], '备份测试任务');
    expect(await repository.getAppSetting('default_tab'), 'stats');
    expect(await repository.getAppSetting('show_daily_sign_in_notice'), 'false');
    expect(await repository.getTaskCategories(), hasLength(6));
    expect(await repository.getShopBoxes(), isNotEmpty);
  });

  test('重置只清理个人进度并重新初始化默认资产和分类', () async {
    await repository.createTask(
      title: '待清理任务',
      note: '',
      targetCount: 1,
      importance: 2,
      difficulty: 2,
      categoryId: 0,
      recordRule: const {'mode': 'DEFAULT'},
    );
    await repository.setAppSetting('default_tab', 'mine');

    await repository.resetLocalData(resetPreferences: true);

    expect(await repository.getAllTasks(), isEmpty);
    expect(await repository.getTaskCategories(), hasLength(6));
    expect(await repository.getShopBoxes(), isNotEmpty);
    expect(await repository.getAppSetting('default_tab'), isNull);
    final today = await repository.getToday();
    expect(today['assets'], containsPair('coin', 0));
  });

  test('存储状态返回引擎、版本和业务表记录数', () async {
    final status = await repository.getStorageStatus();
    expect(status['engine'], contains('SQLite'));
    expect(status['schemaVersion'], 1);
    expect(status['counts'], isA<Map<String, int>>());
    expect(status['totalRecords'], greaterThan(0));
  });
}
