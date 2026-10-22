# PlanBlindBox — Task Complete 第二步（进度 / 状态）

本包需要在已经合并 **TaskRecord Step1** 的 PlanBlindBox 项目基础上合并。

## 范围

本次增加 `POST /tasks/{taskId}/complete?userId=...`：

```http
POST http://localhost:8080/tasks/123/complete?userId=1
Content-Type: application/json

{"actualCount": 30}
```

这里 `actualCount` **是这次要追加的数量**，不是今日总数、也不是历史累计数。
例如某个任务 `target_count=100`，今天先提交 30、再提交 40，则今日记录累计 70。昨天如果已经记录了 20，那么历史总进度 90。

响应示例（假设新建任务还没有其他历史记录）：

```json
{
  "code": 200,
  "message": "success",
  "data": {
    "taskId": 123,
    "recordDate": "2026-10-22",
    "incrementCount": 30,
    "todayActualCount": 30,
    "totalActualCount": 30,
    "targetCount": 100,
    "remainingCount": 70,
    "status": "IN_PROGRESS"
  }
}
```

达到目标时：`Task.status -> COMPLETED`；当天 `TaskRecord.status -> COMPLETED` 且 `finish_time` 写入完成时间。没有达到目标时，任务为 `IN_PROGRESS`。

## 事务与并发控制

- `@Transactional` 包裹读取任务、写入/更新当日记录、更新任务状态。
- `SELECT ... FOR UPDATE` 锁住 Task 行，**同一个任务的并发完成请求串行执行**，防止两个请求同时发现“当天还没有记录”并撞上唯一约束、或重复执行最后一步。
- 完成后再次提交返回 HTTP 409，不会再次追加进度。
- `actualCount <= 0` 或没有提供该字段返回 HTTP 400；提交量大于剩余量时也返回 400，**不自动截断数量**。
- 取消 / 归档 / 已完成的任务不能继续执行；不存在/非本人任务返回 404。
- 限制 `PUT /tasks/{id}` 不能将状态直接设置为 `COMPLETED`；修改目标数时不得小于已有进度，不能使未完成任务靠修改目标直接达到完成条件；已完成任务不能修改目标/改回其他状态。

> **幂等限制**：目前是“完成后不可重复完成”，不是“每次按钮点击都能防重”。例如目标 100，客户端误连续提交两次 `+10`，仍会记为 `+20`。以后可以加请求幂等键。当前请勿启用前端自动重试完成请求。

## 重要：奖励尚未接入

这一步**没有**更新 `reward_config`、`user_asset`、`asset_record`，也不会发金币或经验。
下一步将在当前事务内添加奖励、资产更新、流水写入。请先用 **测试任务** 做验证，暂时不要用真实任务累积奖励，避免已有已完成任务缺少奖励流水。

## 合并文件

以下文件覆盖/合并到你现有项目同路径（不含整项目文件、数据库配置与密码）：

```text
src/main/java/com/planblindbox/controller/TaskController.java       （修改）
src/main/java/com/planblindbox/service/TaskService.java            （修改）
src/main/java/com/planblindbox/service/impl/TaskServiceImpl.java   （修改）
src/main/java/com/planblindbox/mapper/TaskMapper.java              （修改）
src/main/java/com/planblindbox/dto/request/TaskCompleteRequest.java（新增）
src/main/java/com/planblindbox/dto/response/TaskCompleteResponse.java（新增）
src/test/java/com/planblindbox/TaskCompleteServiceTest.java        （新增）
src/test/java/com/planblindbox/TaskCompleteControllerTest.java     （新增）
```

请先保存原项目（Git commit）再覆盖修改的 4 个文件，确保之前自己做的其他改动没有被覆盖。**本包假设你的现有文件与此前上传的 PlanBlindBox.zip 一致，且已合并 Step1。**

## 验证

在 IDEA 终端执行（Windows PowerShell）：

```powershell
.\mvnw.cmd "-Dtest=TaskCompleteServiceTest,TaskCompleteControllerTest" test
```

测试使用真实 MySQL：`TaskCompleteServiceTest` 里新建测试用户、任务并通过 `@Transactional` 在结束时回滚；`TaskCompleteControllerTest` 只测试缺少 `actualCount` 的 HTTP 400 校验。

通过后用新建的测试任务手动执行 POST：第一次提交 30、第二次提交 40、第三次提交 30，观察进度到 100 后状态 `COMPLETED`。第四次再提交应返回 HTTP 409。

**尚未在交付环境运行 Maven/MySQL 测试**，请以你本地运行结果为准。如果出错，将完整错误日志发来即可按你的工程环境继续排查。
