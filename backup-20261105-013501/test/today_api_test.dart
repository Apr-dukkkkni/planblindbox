import 'package:flutter_test/flutter_test.dart';
import 'package:plan_blind_box/data/today_api.dart';
import 'package:plan_blind_box/data/local/local_database.dart';
import 'package:plan_blind_box/data/local/local_plan_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late LocalDatabase database;
  late LocalPlanRepository repository;
  late TodayApi api;

  setUp(() async {
    sqfliteFfiInit();
    database = LocalDatabase.forTesting(factory: databaseFactoryFfi);
    await database.initialize();
    repository = LocalPlanRepository(userId: 1, localDatabase: database);
    api = TodayApi(baseUrl: 'local://sqlite', userId: 1, repository: repository);
    await repository.ensureReady();
  });

  tearDown(() async {
    await database.close();
  });

  test('今日数据从本地 SQLite 读取，默认分类自动初始化', () async {
    await api.createTask(
      title: '本地测试任务',
      note: 'SQLite repository',
      targetCount: 2,
      importance: 3,
      difficulty: 3,
      categoryId: 0,
      recordRule: const {'mode': 'DEFAULT'},
    );

    final today = await api.getToday(sort: 'importance');
    expect(today.tasks, hasLength(1));
    expect(today.tasks.single.title, '本地测试任务');
    expect(today.tasks.single.remainingCount, 2);
    expect(today.assets.coin, 0);

    final categories = await api.getTaskCategories();
    expect(categories, hasLength(6));
  });

  test('任务完成按本次增量累计，达到目标时只发放一次奖励', () async {
    await api.createTask(
      title: '完成任务',
      note: '',
      targetCount: 2,
      importance: 3,
      difficulty: 3,
      categoryId: 0,
      recordRule: const {'mode': 'DEFAULT'},
    );
    final task = (await api.getAllTasks()).single;
    final taskId = (task['taskId'] as num).toInt();

    final first = await api.completeTask(taskId: taskId, actualCount: 1);
    expect(first.granted, false);

    final second = await api.completeTask(taskId: taskId, actualCount: 1);
    expect(second.granted, true);
    expect(second.coin, 8);
    expect(second.exp, 80);

    final today = await api.getToday();
    expect(today.assets.coin, 8);
    expect(today.assets.exp, 80);
    expect(today.tasks, hasLength(1));
    expect(today.tasks.single.completedToday, true);
  });

  test('习惯打卡保存记录并阻止同一业务日重复打卡', () async {
    final habit = await repository.createHabit(
      name: '每天阅读',
      note: '',
      startDate: _businessDate(DateTime.now()),
      repeatRule: const {'type': 'DAILY'},
      importance: 3,
      difficulty: 3,
    );
    final habitId = (habit['habitId'] as num).toInt();
    final reward = await api.checkInHabit(habitId);
    expect(reward.granted, true);
    expect(reward.coin, 2);
    expect(reward.exp, 5);

    await expectLater(
      api.checkInHabit(habitId),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 409)),
    );

    final stats = await repository.getHabitCheckInStats(habitId);
    expect(stats['checkedInToday'], true);
    expect(stats['totalCheckInDays'], 1);
  });



  test('习惯归档与恢复保留历史打卡进度', () async {
    final habit = await repository.createHabit(
      name: '可恢复习惯',
      note: '',
      startDate: _businessDate(DateTime.now()),
      repeatRule: const {'type': 'DAILY'},
      importance: 3,
      difficulty: 3,
    );
    final habitId = (habit['habitId'] as num).toInt();
    await api.checkInHabit(habitId);
    await repository.archiveHabit(habitId);

    expect(await repository.getHabits(), isEmpty);
    final archived = await repository.getHabits(includeArchived: true);
    expect(archived.single['status'], 'ARCHIVED');

    await repository.restoreHabit(habitId);
    final restored = (await repository.getHabits()).single;
    expect(restored['status'], 'ACTIVE');
    final stats = await repository.getHabitCheckInStats(habitId);
    expect(stats['totalCheckInDays'], 1);
    expect(stats['checkedInToday'], true);
  });

  test('本地图鉴预置 12 个藏品，开盒幂等且不会重复扣款', () async {
    final packs = await repository.getCollectionPacks();
    expect(packs, hasLength(1));
    expect(packs.single['totalItems'], 12);

    final db = await database.database;
    await db.rawUpdate('UPDATE user_assets SET coin = 500 WHERE user_id = 1');
    const requestId = '123e4567-e89b-42d3-a456-426614174000';
    final first = await repository.openBox(boxId: 1, requestId: requestId);
    final retry = await repository.openBox(boxId: 1, requestId: requestId);

    expect(retry['openId'], first['openId']);
    final balance = await repository.getShopBalance();
    final rewardCoin = first['rewardType'] == 'COIN' ? first['rewardAmount'] as int : 0;
    expect(balance['coin'], 500 - 50 + rewardCoin);
    expect(await repository.getShopHistory(), hasLength(1));
  });

  test('每日签到幂等，重复调用不重复增加水滴', () async {
    final first = await api.dailySignIn();
    final second = await api.dailySignIn();
    expect(first['granted'], true);
    expect(second['granted'], false);
    expect(second['waterBalance'], 5);
  });
}

String _businessDate(DateTime now) {
  final date = now.hour < 5 ? now.subtract(const Duration(days: 1)) : now;
  return date.toIso8601String().substring(0, 10);
}
