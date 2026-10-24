# Step 5.1｜Today 双排序 + 区分重要程度与难度

## 版本基线

基于用户此前上传的 PlanBlindBox.zip 与已交付的 Today Step2 / Step4 增量代码制作，**不是用户本地最新源码的完整快照**。覆盖前请先对比本地 Today 文件；保留你自己的后续改动。已保留 TodayResponse.date 的 `@JsonFormat` 修复。

## 本步骤范围

- `GET /today?userId=1` 默认 `time` 模式；兼容原接口。
- `GET /today?userId=1&sort=time` 截止时间升序，未设截止时间排最后；相同截止时间重要程度高的优先。
- `GET /today?userId=1&sort=importance` 重要程度 5→1；同等级按截止时间升序；未设截止时间排最后。
- 两种排序都把今天已经完成的任务放在待完成任务之后；所有规则最后以 taskId 升序作为稳定排序。
- `importance` 为空时，**仅比较排序时按 3**；接口仍返回 null，不自动改数据库。
- 首页任务 DTO 增加 `importance`、`difficulty`；难度不影响任务排序。
- 不触碰 Task Complete、RewardService、RewardConfig、Habit、资产流水或数据库表。
- 不实现逾期弹窗、跨日处理、奖励按难度发放（后续独立步骤）。

## 两类字段与未来奖励的约定

| 字段 | 输入范围 | 业务含义 | 本步骤动作 |
|---|---|---|---|
| importance | 1..5 | 用户定义优先程度 | 用于首页排序 |
| difficulty | 1..5 | 用户感知的任务难度 | 只回传，不参与排序及奖励 |
| estimatedMinutes | 正整数 | 预计投入时长 | 暂不用于奖励 |
| priorityScore | 可空 | 旧综合评分预留 | 暂不计算 |

难度奖励下一步单独设计：可以把 difficulty 1-2 → EASY、3 → NORMAL、4-5 → HARD，然后从 `reward_config` 读取对应奖励值；具体数值由业务配置确定，**此步骤没有实现**。目前全部任务仍使用 `TASK_COMPLETE` 统一基础奖励。

## 文件清单

新增/替换文件：

```
src/main/java/com/planblindbox/controller/TodayController.java
src/main/java/com/planblindbox/dto/response/TodayResponse.java
src/main/java/com/planblindbox/service/TodayService.java
src/main/java/com/planblindbox/service/impl/TodayServiceImpl.java
src/test/java/com/planblindbox/TodaySortServiceTest.java
src/test/java/com/planblindbox/TodaySortControllerTest.java
docs/dev/step5-1-task-sorting.md
```

## 本地测试

项目根目录 PowerShell：

```powershell
.\mvnw.cmd "-Dtest=TodaySortServiceTest,TodaySortControllerTest,TodayServiceTest,TodayControllerTest" test
.\mvnw.cmd test
```

增量新测试 **7 项**，如果原本 40 项完整通过且测试基线没有增加，预期总数为 **47 项**。这个数字是预期，须以本地日志为准。

## Apifox 真实验收

```
GET http://localhost:8080/today?userId=1
GET http://localhost:8080/today?userId=1&sort=time
GET http://localhost:8080/today?userId=1&sort=importance
GET http://localhost:8080/today?userId=1&sort=unknown
```

- 默认排序和 `time` 排序一致。
- `importance` 改变顺序；任务本身的进度、状态、资产和完成率不改变。
- `sort=unknown` 返回 HTTP 400，统一格式应为 code/message/data。
- 没有 important/difficulty 的旧任务仍能显示，不会强制修改旧数据。
- **无数据库迁移，无奖励变化。**

## 当前环境说明

产物包含源码和测试源码，但当前执行环境没有可用的 Maven 命令或可用的 Maven 依赖仓库，未能本地运行完整 JUnit；请以你的 Windows Maven 结果完成验收。
