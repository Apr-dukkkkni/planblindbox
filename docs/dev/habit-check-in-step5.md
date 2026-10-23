# PlanBlindBox Step5 — Habit Check-in + Streak + Reward

## 这一步的范围

- 基于 Step4 Habit CRUD 和 Step3 Task Reward 的代码继续开发，不重建数据库。
- `POST /habits/{habitId}/check-in?userId=1`：对**当天**打一次卡，不需要 Body。
- `GET /habits/{habitId}/check-in-status?userId=1`：查看当天已打卡状态、连续打卡次数和总打卡天数（不会发奖励）。
- `habit_record` 一天一条完成记录，`status=COMPLETED`、`actual_count=1`、`finish_time`为实际打卡时间。
- `reward_config.type = HABIT_CHECK_IN`，调用现有 `RewardService`，事务内更新 `user_asset` 并写 `asset_record`。
- 资产流水 `action=HABIT_CHECK_IN`、`source=HABIT_RECORD`、`source_id=habit_record_id`，可以追溯具体哪天打卡所得。
- 修改、归档、打卡都对同一 habit 行使用 `FOR UPDATE` 锁；数据库唯一约束 `(habit_id, record_date)` 是第二层保护。

## 如何安装

1. 先 Git 提交现有可运行代码。
2. 将此包中的 `src` 合并到项目根目录对应路径（含新增文件及以下四个需覆盖文件）：
   - `controller/HabitController.java`
   - `mapper/HabitMapper.java`
   - `service/impl/HabitServiceImpl.java`
   - `service/RewardService.java`
3. 打开 MySQL，执行 `docs/dev/habit-check-in-step5.sql` 初始化奖励配置。
4. 重启 Spring Boot 后运行：

```powershell
.\mvnw.cmd "-Dtest=HabitCheckInIntegrationTest,HabitCheckInControllerTest,HabitCrudIntegrationTest,TaskRewardIntegrationTest" test
```

因为 RewardService 发生复用改造，**要同时回归跑 TaskRewardIntegrationTest**；建议最后运行 `./mvnw.cmd test` 运行全量测试。

### 使用 Apifox 检验用户 1 的 habitId=7

上个阶段已创建习惯 `habitId=7`，规则 `DAILY`，状态 `ACTIVE`，今天属于其计划日期，可测试：

```http
POST http://localhost:8080/habits/7/check-in?userId=1
```

无需 JSON Body，第一次响应示例（余额受历史资产影响）：

```json
{
  "code": 200,
  "message": "success",
  "data": {
    "habitId": 7,
    "recordDate": "2026-10-22",
    "checkedInToday": true,
    "currentStreak": 1,
    "totalCheckInDays": 1,
    "reward": {
      "granted": true,
      "coin": 2,
      "exp": 5,
      "water": 1,
      "coinBalance": 22,
      "expBalance": 45,
      "waterBalance": 1
    }
  }
}
```

以上仅为**数据形状的示例**，`recordDate` 取服务器实际日期，所有具体奖励和资产余额以实际配置与数据为准。

再调用相同 POST，应该返回 HTTP `409 Conflict`，而不是第二次发奖。

查看状态（无需请求 Body）：

```http
GET http://localhost:8080/habits/7/check-in-status?userId=1
```

不会触发新的奖励；`reward` 应为 `null`。

### MySQL 验收

```sql
USE plan_blind_box;

SELECT * FROM habit_record WHERE habit_id = 7 ORDER BY record_date DESC;

SELECT * FROM user_asset WHERE user_id = 1;

SELECT a.*
FROM asset_record a
JOIN habit_record r
  ON a.source = 'HABIT_RECORD' AND a.source_id = r.habit_record_id
WHERE r.habit_id = 7 AND a.user_id = 1
ORDER BY a.record_id DESC;
```

如果奖励配置 `enabled=0`，打卡依旧成功，但不发奖励；如缺少 `HABIT_CHECK_IN` 配置，服务器报错并回滚打卡，避免记录成功但没有结算。

## 连续打卡计算口径（当前 MVP）

- DAILY：每天都是应打卡日。今天尚未打卡时，仍展示截至昨天的连续次数；昨天若漏打卡，则连续数归零。
- WEEKLY：`daysOfWeek` 对应 1=周一 ... 7=周日。只统计计划中的应打卡日，非计划日会跳过；例如周一、三、五都打卡算连续 3 次。
- 今天打卡后，连续数从今天往前追溯，遇到第一个漏打的应打卡日即停止。
- `totalCheckInDays` 是当前习惯历史已完成打卡天数总和，非奖励总次数。

## 目前明确不做

- 补签、撤销打卡、一次完成多次、签到冻结卡；`actual_count` 固定为 1。
- 手机用户时区设置：暂时以 **Spring Boot 所在服务器的系统默认时区**为“今天”；以后加用户时区配置后再统一。
- 修改习惯周期后，过去打卡的连续数按**最新周期**重新计算；以后如果需要保留当时历史周期，需要引入规则版本或日历快照，本阶段不改表。
- 统一异常 JSON：业务异常仍沿用 HTTP 409/404 等原有处理机制，等 GlobalExceptionHandler 阶段统一。
- 大规模历史打卡性能优化：暂时查询该习惯的全部完成日期并在 Java 中计算 streak，适合个人 MVP。
