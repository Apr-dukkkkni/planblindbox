# PlanBlindBox Step 4：全局异常处理（第一批，兼容式）

## 内容

新增 3 个 Java 文件：

- `src/main/java/com/planblindbox/exception/BusinessException.java`
- `src/main/java/com/planblindbox/exception/GlobalExceptionHandler.java`
- `src/test/java/com/planblindbox/GlobalExceptionHandlerTest.java`

**不替换**已有的 Task、Habit、Today、Reward、Mapper、Result、pom.xml、application.yml，不修改数据库。

## 错误协议

HTTP 400/404/409/500 等和 JSON `code` 一致，统一返回：

```json
{"code":409,"message":"今天已经打过卡了","data":null}
```

新代码以后可使用：

```java
throw new BusinessException(HttpStatus.NOT_FOUND, "任务不存在");
```

现有 Service 的 `ResponseStatusException` 继续可用，并由同一全局处理器转换为 `Result`；已有 Service 单元测试直接断言该异常类型，因此不在这一步强行替换。

## 本地测试

在项目根目录 PowerShell 执行：

```powershell
.\mvnw.cmd "-Dtest=GlobalExceptionHandlerTest" test
.\mvnw.cmd test
```

新增独立测试共有 9 个用例（包括参数化的 3 个状态码）。建议优先确保全量测试无回归。

## Apifox 手工检查（请启动后端）

1. `POST /tasks/123/complete?userId=1` + Body `{}` -> 400，`code=400`，`data=null`。
2. `GET /tasks/999999999?userId=1` -> 404，`code=404`，`data=null`。（确认该 ID 不存在）
3. `GET /today?userId=abc` -> 400，`code=400`，`data=null`。
4. 在可控的**已打卡习惯**上重复调用 POST /habits/{habitId}/check-in?userId=... -> 409；不要对没有打卡的习惯发起测试请求，否则会真实打卡并发放奖励。
5. `GET /today?userId=1` -> 仍然返回 200 和既有 Today 数据结构。

## 已知范围

- 本包只统一 HTTP 错误处理并提供 BusinessException；**尚未迁移**原 Service 中的 ResponseStatusException，因为已有测试需要保持兼容。
- 任何 500 异常仅返回通用文案，详细堆栈仅在服务端日志输出。
- 未修改请求 DTO 约束，因此不会额外改变业务校验规则。
- 新增测试不依赖 MySQL；但原项目中其他集成测试可能依赖真实 MySQL。
- 本地环境没有 Maven 命令和完整依赖缓存，**新文件未实际编译/执行 JUnit**；请以你 Windows 本地输出为准。
