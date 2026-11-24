# PlanBlindBox MOD P0-3 实施报告

**文档编号：** PBB-MOD-P0-3-001  
**版本：** Draft 0.1  
**日期：** 2026-11-10  
**状态：** 源码补丁已生成；Flutter/Dart 集成测试待项目工具链执行  
**前置依赖：** P0-1 Manifest V1 + P0-2 本地安装/授权/审计存储补丁

---

## 1. 本批目标

P0-3 将 MOD 对宿主业务的调用从页面直接写入 `TodayApi` 改为统一的 Capability Broker。首期只开放 H1：`host.tasks.create`。不开放任务/习惯/日记读取，不开放任意 SQL，也不开放第三方可执行代码。

本批没有新增 SQLite 表或升级数据库版本；继续使用 P0-2 的 schema v8。

## 2. 新增和修改文件

| 文件 | 改动 |
|---|---|
| `frontend/lib/mod_platform/runtime/mod_runtime_session.dart` | 新增进程内 Runtime Session；15 分钟过期；支持按安装、账号或全局终止 |
| `frontend/lib/mod_platform/runtime/mod_permission_policy.dart` | 新增集中权限策略：账号、安装状态、Manifest、Publisher、用户授权、管理员审批、Profile、Runtime 和 Scope 检查 |
| `frontend/lib/mod_platform/runtime/mod_capability_broker.dart` | 新增 Broker、一次性用户确认凭据、最小 Host API 结果和 `ModHostApi` |
| `frontend/lib/data/local/local_plan_repository.dart` | 新增 `createTaskFromMod()`；在任务写入的同一 SQLite 事务内再次检查安装、Profile、授权、全局开关和 Session |
| `frontend/lib/mod_platform/storage/mod_platform_store.dart` | 安装投影补充数据库安装身份、安装版本和原始 Manifest；增加 capability 审计记录方法 |
| `frontend/lib/services/mod_registry.dart` | 升级、禁用、撤权、卸载时终止对应 Runtime Session；模板上下文带安装实例 ID |
| `frontend/lib/screens/mod_hub_drawer.dart` | 移除直接调用 `TodayApi.createTask`，改为 Broker |
| `frontend/lib/screens/mod_management_page.dart` | 移除直接调用 `TodayApi.createTask`，改为 Broker；展示恢复后重新授权状态和审批说明 |
| `frontend/lib/screens/settings_page.dart` | 全局关闭 MOD 时立即终止所有 Session |
| `frontend/lib/auth/auth_session.dart` | 登录、登出、会话过期/清理和启动恢复时终止进程内 MOD Session |
| `frontend/test/mod_platform/capability_broker_test.dart` | 新增 15 项 Broker/Host API 测试 |
| `frontend/test/mod_platform/mod_runtime_session_test.dart` | 新增 3 项 Session 生命周期测试 |

## 3. Broker 每次调用的权限检查

`ModPermissionPolicy.authorize()` 在每次签发用户确认凭据和每次实际调用前重新检查：

1. Runtime Session 是否仍有效、是否过期、是否被终止。
2. Session owner 是否等于当前 MOD 数据 owner。
3. 全局 MOD 开关是否开启。
4. 安装实例 ID、MOD ID、数据库安装状态和启用状态是否一致。
5. Manifest 原文、ID、版本、Publisher 是否与安装记录一致。
6. Manifest 是否声明 `host.tasks.create`（旧版过渡映射只接受 `tasks.create`）。
7. 当前用户是否明确授予对应权限。
8. 可信 `ModApprovalProvider` 是否确认管理员批准了该 capability。
9. 有效 Profile 是否为 `host_integrated_offline`。
10. Runtime 是否为平台支持的 declarative 类型。
11. 请求是否属于 MOD 已声明的任务模板；若 Manifest 有 Scope，还要检查操作和字段范围。

Manifest V1 使用 P0-1 的 `ModManifestV1Validator` 再次校验。V1 的包内容/资源入口尚未接入安装器和 Declarative Runtime，因此本批不会执行 V1 包中的任务模板；这是有意的 fail-closed 行为。

## 4. 管理员审批：默认拒绝

`ModApprovalProvider` 是与后续平台审核证明对接的信任边界。当前生产默认实现为 `DenyAllModApprovalProvider`：

- 没有管理员审批证明：拒绝。
- 审批服务不可用或抛错：拒绝。
- 不把用户同意等同于管理员审批。
- 不把本地导入或 Manifest 自我声明当作管理员批准。

因此，应用当前 UI 中的任务模板仍可查看，但在 P0-5 将签名审核证明接入 Provider 之前，任务创建会被拒绝。测试使用仅存在于测试代码中的 fake provider 验证允许路径，不会进入生产构建。

## 5. 一次性用户确认

用户确认凭据具备以下约束：

- 只由宿主 UI 在用户确认后申请。
- 绑定 Session、安装实例、capability 和请求 payload 指纹。
- 30 秒后过期。
- 只能使用一次。
- 不能把用户确认的模板替换成另一份任务内容。

这不是给 MOD Runtime 的通用令牌。后续可执行 Runtime 只能通过受控的 typed RPC 接口调用 Broker，不能获得 `TodayApi`、Repository 或数据库句柄。

## 6. Host API：最小写入面

当前只实现 `host.tasks.create`，允许字段严格限定为：

- `title`：1–100 字符
- `note`：最多 500 字符
- `targetCount`：1–999
- `importance`：1–5
- `difficulty`：1–5

不接受 `categoryId`、`recordRule`、用户 ID、任务 ID、SQL 或其他未知字段。宿主固定使用默认分类和默认记录规则。

成功结果只返回 `status` 和随机 `requestId`，不返回完整任务记录或数据库主键。

## 7. 事务内二次校验与审计

Broker 的异步权限检查之后，`createTaskFromMod()` 仍会在 SQLite 写事务中重新检查：

- 安装实例属于当前 owner、MOD ID 匹配、状态 installed、enabled=1。
- Profile 仍为 `host_integrated_offline`。
- 用户授权仍有效，未撤销。
- 全局 MOD 开关仍开启。
- Session 在事务执行期间仍有效。
- Manifest 仍声明任务创建权限，且请求字段与已声明模板匹配。

如果任一条件在事务执行期间失效，事务回滚，任务不会写入。

成功审计与任务创建在同一事务内写入。拒绝/错误审计只记录 MOD ID、安装实例、capability、结果和时间；不记录任务标题、备注、日记、私密字段或完整请求体。审计保留最近 500 条。

## 8. Session 终止时机

以下动作会终止相关 Session：

- MOD 禁用、撤权、升级、卸载。
- 全局 MOD 开关关闭。
- 登录、登出、会话过期、清理本地认证状态。
- 应用进程结束时，Session 随进程内存自然消失。

Session 不进入 SQLite、用户备份或云同步。

## 9. 测试与验证

新增测试共 18 项：

- Broker 正常调用与最小返回结果。
- 无管理员审批时默认拒绝。
- 审批服务异常时 fail-closed。
- 用户确认凭据只能使用一次、绑定具体 payload。
- 禁用、撤权、升级、卸载、账号切换后的 Session 失效。
- 全局 MOD 开关关闭时拒绝。
- Host API 未知字段拒绝。
- 非 declarative Runtime 拒绝。
- Host API 事务内复核安装、授权、Session 和全局开关。
- 不允许为 Manifest 未声明的任务内容签发用户确认。
- Session 到期、按安装/账号/全局终止。

本次已执行：

- 17 项源码静态一致性检查：全部通过。
- SQLite 事务谓词 smoke test：通过，验证撤权和全局关闭会阻止写入。
- Flutter/Dart `flutter test`、`dart analyze`、`dart format`：未执行。当前工作环境没有 Flutter/Dart SDK；不得将静态检查或 SQLite smoke test 等同于 Flutter 集成测试通过。

## 10. 明确未完成的边界

- P0-5 才会接入真实的 Publisher 签名、Store Attestation 和管理员审批 Provider。当前默认拒绝是预期行为。
- P0-4 才会完成 Declarative Runtime Manager 和资源包加载；当前 V1 包内容不执行。
- 本批不开放 `host.data.*` 读取能力，尤其不开放日记、情绪、Private Vault。
- 本批不开放 `network.fetch`、MOD 间消息、Web Runtime、WASM Runtime 或任意 Dart/JavaScript 执行。
- 当前旧 JSON 任务模板适配器仍是过渡层；最终 `.mod.zip` 安装流程和 Manifest V1 内容资产映射仍需后续完成。

---

**结论：** P0-3 的 H1 Broker/Session/Host API 代码边界已形成；管理员审批和 V1 内容 Runtime 仍采用 fail-closed，占位 Provider 不构成完整市场信任链。完成 P0-5/P0-4 并通过 Flutter 安全测试后，才可考虑对外开放。
