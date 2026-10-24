import 'package:flutter_test/flutter_test.dart';
import 'package:plan_blind_box/models/today_models.dart';

void main() {
  test('解析 2026-10-23 Today 真实响应结构', () {
    final today = TodayData.fromJson({
      'date': '2026-10-23',
      'tasks': [{
        'taskId': 4,
        'title': '复习 Java 锁',
        'endTime': '2026-10-23T18:00:00',
        'importance': 5,
        'difficulty': 3,
        'status': 'IN_PROGRESS',
        'targetCount': 5,
        'todayActualCount': 2,
        'totalActualCount': 3,
        'remainingCount': 2,
        'completedToday': false,
        'overdue': false,
      }],
      'habits': [{
        'habitId': 7,
        'name': '每天阅读30分钟',
        'checkedInToday': true,
        'currentStreak': 2,
        'totalCheckInDays': 2,
      }],
      'assets': {'coin': 32, 'exp': 65, 'water': 1},
      'summary': {
        'taskTotal': 1,
        'taskCompleted': 0,
        'habitTotal': 1,
        'habitCheckedIn': 1,
        'completionRate': 50.00,
      }
    });
    expect(today.tasks.single.importance, 5);
    expect(today.tasks.single.progress, closeTo(.6, .001));
    expect(today.habits.single.checkedInToday, true);
    expect(today.summary.completionRate, 50);
    expect(today.assets.exp, 65);
  });

  test('缺失难度、重要程度与资产时不抛异常', () {
    final today = TodayData.fromJson({
      'date': '2026-10-23',
      'tasks': [{
        'taskId': 1, 'title': '学习', 'targetCount': 0, 'remainingCount': 0,
      }],
      'habits': [],
    });
    expect(today.tasks.single.importance, isNull);
    expect(today.tasks.single.difficulty, isNull);
    expect(today.tasks.single.progress, 0);
    expect(today.assets.coin, 0);
    expect(today.summary.total, 0);
  });
}
