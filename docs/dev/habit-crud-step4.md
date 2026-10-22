# PlanBlindBox Step4 — Habit 习惯管理（CRUD）

## 依赖和范围

- 依赖现有 `plan_blind_box` 数据库内的 `app_user`、`habit` 表，不需要改表。
- 基于已通过测试的 Task + Reward 项目添加新模块，**本包只包含新文件**，不覆盖已经验收通过的 Task 类。
- 本步骤仅实现习惯的创建、读取、列表、更新、归档；暂不实现每日打卡、连续 streak、Habits 奖励、Today 首页。
- `habit`（长期规则）和以后要开发的 `habit_record`（每天打卡）继续分离。

## 新增接口

| HTTP | URL | 说明 |
| --- | --- | --- |
| POST | `/habits` | 创建新习惯，初始状态 ACTIVE |
| GET | `/habits/{habitId}?userId=1` | 查询单个习惯（包含已归档，用于查看历史） |
| GET | `/habits?userId=1` | 查询习惯列表（只排除 ARCHIVED；PAUSED 保留） |
| PUT | `/habits/{habitId}?userId=1` | 选择性更新名称、日期、周期与 ACTIVE/PAUSED |
| DELETE | `/habits/{habitId}?userId=1` | 软归档为 ARCHIVED，不物理删除 |

## 创建请求示例（Apifox）

每日习惯：

```http
POST http://localhost:8080/habits
Content-Type: application/json
```

```json
{
  "userId": 1,
  "name": "每天阅读 30 分钟",
  "note": "晚饭后阅读",
  "startDate": "2026-10-22",
  "repeatRule": {"type": "DAILY"}
}
```

每周一、三、五执行（数字 1 表示周一，7 表示周日）：

```json
{
  "userId": 1,
  "name": "每周运动",
  "startDate": "2026-10-22",
  "endDate": "2026-12-31",
  "repeatRule": {"type": "WEEKLY", "daysOfWeek": [1, 3, 5]}
}
```

`repeatRule` 的数据库列为 JSON，Request / Response 也保持 JSON 对象；Service 负责校验格式并转为数据库 JSON 字符串。

允许周期：

- `{"type":"DAILY"}` —— 每天。
- `{"type":"WEEKLY","daysOfWeek":[1,3,5]}` —— 每周指定的日期；1=周一、7=周日；不允许重复或空数组。

本阶段暂不支持 MONTHLY、工作日自动跳过节假日等特殊周期。若无结束期限，创建时不传 `endDate`。

## 示例修改和归档

```http
PUT http://localhost:8080/habits/1?userId=1
Content-Type: application/json
```

```json
{"name":"运动 20 分钟", "status":"PAUSED", "repeatRule":{"type":"WEEKLY", "daysOfWeek":[2,4,6]}}
```

```http
DELETE http://localhost:8080/habits/1?userId=1
```

与 Task 一致，成功结果用 `Result<T>`，如 `{ "code":200,"message":"success","data":{...} }`；归档成功则 data 为 null。错误目前仍由 `ResponseStatusException` 抛出，待统一异常处理阶段再改成标准错误 JSON。

## 自测步骤

1. 在 Git 提交现有项目（确保 Step3 通过）。
2. 将本包 `src` 文件夹**合并**到项目根目录的 `src`（全是新增文件）。不需要执行 SQL，不修改数据库表。
3. IDEA 终端运行：

```powershell
.\mvnw.cmd -Dtest=HabitCrudIntegrationTest test
```

4. 查看 `Tests run: 5, Failures: 0, Errors: 0` 和 `BUILD SUCCESS`。该测试真实访问 MySQL，并使用 `@Transactional` 测试回滚，不留下测试习惯/用户。
5. 可在 Apifox 创建并查询真实习惯。检查数据库：

```sql
USE plan_blind_box;
SELECT habit_id, user_id, name, start_date, end_date, repeat_rule, status
FROM habit WHERE user_id = 1 ORDER BY habit_id DESC;
```

## 有意保留的 MVP 限制

- 目前用户 ID 仍由前端传，不等于身份认证；真正的访问保护需要后续 Spring Security/JWT。
- Update 使用 null 表示“不改字段”，暂时不支持将 `note`/`endDate` 设置回 SQL NULL（以后可用明确的清空操作）。
- 目前没有 `targetCount`：`habit_record.actual_count` 后续可存“当天执行次数”，本阶段的习惯完成定义将按“当天成功打卡一次”处理，再决定是否需要目标计数。
- 不校验 `startDate` 必须小于今天或大于今天，只校验 `endDate >= startDate`。
- 暂不提供 `/habits/{id}/check-in`、`/habits/today`；后续先实现 HabitRecord，再加 Today。
- 更新与归档暂时没有加入行锁/版本控制；写入 SQL 已包含所有权条件、归档保护。并发精细冲突留到后续优化。

## 后续 Step5

`POST /habits/{habitId}/check-in` → `habit_record`（一天一条）→ 根据 repeatRule 判断当天是否应执行 → streak → 奖励流水。请不要把 `HabitRecord` 当成 `Habit` 的字段来反复覆盖。
