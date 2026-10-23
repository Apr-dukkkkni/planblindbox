# Today Step 2（只读首页聚合接口）

## 增量文件

- `src/main/java/com/planblindbox/controller/TodayController.java`
- `src/main/java/com/planblindbox/service/TodayService.java`
- `src/main/java/com/planblindbox/service/impl/TodayServiceImpl.java`
- `src/main/java/com/planblindbox/dto/response/TodayResponse.java`
- `src/test/java/com/planblindbox/TodayServiceTest.java`
- `src/test/java/com/planblindbox/TodayControllerTest.java`

## 接口

`GET /today?userId=1`

### 筛选规则

- Task：`PENDING`/`IN_PROGRESS` 且开始日期未超过今天；`COMPLETED` 仅当今日执行记录为 `COMPLETED` 才出现；排除 `CANCELLED`/`ARCHIVED`。
- Task 进度：今日数量来自 `task_record.actual_count`；总数量来自所有日期记录的 SUM；不以今日数量充当历史数量。
- `overdue`：仍未整体完成，且当前服务器时间已超过任务截止时间。
- Habit：仅 `ACTIVE` 且今日处于起止日期内，DAILY 每天展示、WEEKLY 仅计划星期展示。
- Habit 状态/连续次数：复用 `HabitCheckInService.getTodayStatus()`。
- Asset：若 user_asset 尚无记录，返回金币/经验/水滴全 0。
- 概览：完成率为 `(今日整体完成任务数+今日已打卡习惯数)/(今日展示任务数+今日展示习惯数)*100`，保留两位小数；无事项时返回 0。
- 用户不存在返回 404，userId 非正数返回 400。
- 接口为只读，不修改数据库，不触发打卡/完成/奖励。

## 测试

新增无数据库依赖的单元测试：

```bash
./mvnw -Dtest=TodayServiceTest,TodayControllerTest test
```

注意：此交付环境无法下载 Maven 3.10.0，故未能在此运行 JUnit 或进行 Maven 编译。请在本地执行命令并检查输出。

## Apifox 验收

1. `GET http://localhost:8080/today?userId=1`，期望 `code: 200` 且包含 `date`, `tasks`, `habits`, `assets`, `summary`。
2. 对照 task_record 校验 `todayActualCount` 与 `totalActualCount`；对照 habit_record 校验 `checkedInToday` 与 `currentStreak`。
3. 对照 user_asset 校验余额；刷新 GET 两次后核对 asset_record 数量未增加。
4. 验证 `GET /today?userId=-1` 返回 400，未知用户 ID 返回 404。

## 现阶段的已知取舍

- 复用现有 Mapper，每项任务查询当日及历史记录，每项应执行习惯调用已有状态查询。在个人 MVP 的数据规模内先保证正确；未来任务/习惯数量大时再将查询优化为批量聚合。
- Today 与原有 Task/Habit API 都使用服务器默认时区。跨时区、午夜边界需要在登录系统上线时统一处理。
- 首页只返回 `priorityScore`，暂无新排序算法；当前列表顺序沿用已有 Mapper 的创建时间倒序。
- 若用户后续修改已完成任务的开始日期等，首页筛选按照最新定义判断；历史当日快照暂未设计。
