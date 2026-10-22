# TaskRecord 第一步：每日执行记录持久层

本次只新增 4 个文件：`TaskRecord`、`TaskRecordStatus`、`TaskRecordMapper`、`TaskRecordMapperTest`。
没有修改 Task CRUD、SQL 建表、Spring 配置和现有接口，也**没有**新增独立写入记录的 HTTP 接口。

## 设计约定

- `task_record` 每个 Task 每天最多一条记录：`UNIQUE(task_id, record_date)`（已有数据库约束）。
- `actual_count` 是**当天累计**完成数量；`SUM(actual_count)` 才是任务的**历史累计**完成数量。
- 同一天有新进度，执行 `incrementActualCount()` 原子累加；第一次执行使用 `insert()`。
- `TaskRecordStatus` 表示每日记录状态；`TaskStatus` 表示整个任务状态，两者不要混淆。
- 当前只提供 Mapper，暂时不允许绕过后续 `/complete` 接口修改执行记录，防止绕过奖励结算。

## 如何验证

先确认本地 `plan_blind_box` 库已执行 `docs/database/source/table1012.sql` 中建表 SQL。

Windows 终端（项目根目录）：

```powershell
.\mvnw.cmd -Dtest=TaskRecordMapperTest test
```

Linux / macOS：

```bash
./mvnw -Dtest=TaskRecordMapperTest test
```

测试在一个事务里：临时新建用户、新建目标为 100 的任务、写入昨天 30 和今天 40 的记录；
确认累计 70，再给今天原子增加 30，确认今天 70、历史累计 100、仍然只有两条日记录。
测试结束将临时数据回滚（InnoDB）。

注意：该测试属于**真实 MySQL 集成测试**，本机必须能连到数据库。

## 下一步（还没实现）

添加 `POST /tasks/{taskId}/complete?userId=...` 的请求/响应 DTO、Service 事务流程和 Task 行锁，
统一处理归属检查、每日新增/累加、全任务进度及状态；随后接入奖励、资产与流水。

`TaskUpdateRequest` 目前仍允许传 `status`，未来奖励逻辑接入时应限制外部直接将任务改为 `COMPLETED`，
避免绕过完整的完成流程。
