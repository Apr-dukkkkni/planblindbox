# PlanBlindBox Step3 — 完成任务后结算奖励

基础：已经合并 Step1（TaskRecord）与 Step2（Task Complete），并且 Step2 的 `POST /tasks/{id}/complete` 能正常累计进度。

## 本阶段行为

* 任务进度未达 `target_count` 时只累计执行次数，`reward` 为 `null`，不动资产。
* **首次**达到 `target_count` 时，更新任务为 `COMPLETED`，同一数据库事务中：
  1. 查找 `reward_config.type = 'TASK_COMPLETE'`。
  2. 如果规则启用且有正数奖励，对 `user_asset` 原子加币 / 经验 / 水滴（无用户资产行时自动新建）。
  3. 每种非零资产写一条 `asset_record` 流水：`action='TASK_COMPLETE'`、`source='TASK'`、`source_id=task_id`。
  4. 返回本次奖励与资产余额。
* 如果规则明确禁用，任务仍能完成，但奖励为零，不产生流水。
* 如果缺少规则或奖励数值非法，**拒绝完成并回滚任务进度和状态**。先执行示例配置 SQL。
* 同一任务的并发完成请求由 `SELECT ... FOR UPDATE` 串行执行。完成后再提交会返回 HTTP 409，不会再发奖励。

## 先配置规则，不需要建新表

在 MySQL 的 `plan_blind_box` 库执行本包 `docs/dev/task-reward-step3.sql`。

示例数值：每完成一个任务，`coin=10`、`exp=20`、`water=2`。这个值仅供开发验证，**不是产品最终规则**。

SQL 的 `ON DUPLICATE KEY UPDATE type=type` 表示如果已有同名规则就不覆盖既有数值。请用 SQL SELECT 查看实际奖励配置；若已经存在但 `enabled=false`，请先决定是否启用。

## 文件合并

压缩包中仅提供本次新增或调整的文件，均按相同相对路径合并到原 PlanBlindBox 项目。先 Git 提交再覆盖这 3 个旧文件：

* 修改：`service/impl/TaskServiceImpl.java` — 首次达到目标后结算奖励。
* 修改：`dto/response/TaskCompleteResponse.java` — 增加 reward 字段。
* 修改：`src/test/java/com/planblindbox/TaskCompleteServiceTest.java` — 给旧测试提供规则，避免旧测试因缺规则失败。
* 新增：`entity/RewardConfig.java`、`entity/UserAsset.java`、`entity/AssetRecord.java`。
* 新增：`mapper/RewardConfigMapper.java`、`mapper/UserAssetMapper.java`、`mapper/AssetRecordMapper.java`。
* 新增：`service/RewardService.java`。
* 新增：`dto/response/TaskRewardResponse.java`。
* 新增：`src/test/java/com/planblindbox/TaskRewardIntegrationTest.java`。

数据库表结构不用改；不会用到 Security、Redis、JWT、MyBatis-Plus。

## 测试指令

```powershell
.\mvnw.cmd "-Dtest=TaskCompleteServiceTest,TaskRewardIntegrationTest,TaskCompleteControllerTest" test
```

> 本代码包只做了静态检查。由于制作环境无法连接你的本地 MySQL、也未装 Maven，没有在这里实际运行 Maven 集成测试；请以你本地结果为准。

### Apifox 手测（用新的任务 ID）

创建 `targetCount=60` 的**新任务**（之前已完成的任务 9 不会自动补发奖励）：

```http
POST http://localhost:8080/tasks/{新taskId}/complete?userId=1
Content-Type: application/json

{"actualCount":30}
```

第一次应返回 `status=IN_PROGRESS`、`reward=null`。

再次提交相同的 `actualCount=30`，应返回 `status=COMPLETED`，`reward` 类似：

```json
{
  "granted": true,
  "coin": 10,
  "exp": 20,
  "water": 2,
  "coinBalance": 10,
  "expBalance": 20,
  "waterBalance": 2
}
```

以上余额示例假设该用户此前三种资产均为 0；若已有余额则按原值累加。

再执行这两条 SQL（用真实任务、用户 ID 替换）：

```sql
SELECT user_id, coin, exp, water FROM user_asset WHERE user_id=1;

SELECT action, asset_type, amount, source, source_id, create_time
FROM asset_record
WHERE user_id=1 AND source='TASK' AND source_id=你的新任务ID
ORDER BY record_id;
```

三种奖励金额均大于零时，应看到三条资产流水。第四次重复提交应返回 HTTP 409，资产不再次增加。

## 仍然存在的约束（后面处理）

1. **只有任务最终完成时奖励一次**，而不是每提交一次增量奖励一次。
2. **未完成任务的重复请求仍不幂等**：如果目标还没达到，请求被客户端重试会重复叠加执行量。以后用请求幂等键处理。
3. 本阶段不处理经验等级升级奖励，也不追溯 Step2 已完成任务的历史奖励。
4. 现在的用户 ID 由请求传入，后续有 JWT 才从登录身份读取。
5. 数据库没有新增唯一奖励业务键；重复领奖目前通过 **task 行锁 + status 状态** 保护正常 API 流程，不承诺可抵御人为直接修改表或绕过服务层写入。
