# PlanBlindBox MOD P0-2 实施报告

**文档编号：** PBB-MOD-P0-2-001\
**版本：** Draft 0.1\
**日期：** 2026-11-10\
**状态：** 源码补丁已生成；Flutter/Dart
自动化测试待在项目工具链环境执行\
**适用范围：** `1111.zip` 源码快照；建议在 P0-1 补丁基础上应用

------------------------------------------------------------------------

## 1. 本批完成内容

P0-2 将 MOD 安装状态、权限授权、审计事件和 MOD 自有存储从原先的全局
`app_settings` JSON 注册表拆分为独立 SQLite 表。

### 已修改文件

  ------------------------------------------------------------------------------------------------------------------------
  文件                                                          改动
  ------------------------------------------------------------- ----------------------------------------------------------
  `frontend/lib/data/local/local_database.dart`                 SQLite schema 从 v7 升至 v8；增加 MOD
                                                                安装、授权、审计和存储表；升级时移除旧 `mods.registry.*`
                                                                设置键

  `frontend/lib/data/local/local_plan_repository.dart`          MOD 数据按账号 owner 分区；备份/恢复、数据重置和 guest
                                                                owner 映射改造

  `frontend/lib/services/mod_registry.dart`                     保留原声明式任务模板 API，底层改用规范化 MOD
                                                                Store，不再读写 `app_settings`

  `frontend/lib/mod_platform/storage/mod_platform_store.dart`   新增安装、升级、启停、卸载、授权撤销、审计和本地存储服务

  `frontend/test/mod_registry_test.dart`                        扩展账号隔离、升级撤权、备份重新授权、保留数据、Profile
                                                                隔离、存储配额和权限组合测试
  ------------------------------------------------------------------------------------------------------------------------

## 2. 新增数据库表

  ------------------------------------------------------------------------------------------------------------
  表                        作用                                                是否进入用户备份
  ------------------------- --------------------------------------------------- ------------------------------
  `mod_installations`       安装实例、Publisher、版本、Manifest、包摘要、有效   是；恢复后禁用并要求重新授权
                            Profile、启用状态、存储命名空间                     

  `mod_permission_grants`   用户实际授予的                                      **否**
                            capability、Scope、授权时间、撤销时间和策略版本     

  `mod_audit_events`        安装、升级、启停、卸载和权限撤销事件                **否**

  `mod_storage_metadata`    MOD 私有存储命名空间、Profile、配额、用量和保留状态 是

  `mod_storage_entries`     MOD 自有 JSON 键值数据                              仅导出非
                                                                                `host_integrated_offline`
                                                                                Profile 的数据
  ------------------------------------------------------------------------------------------------------------

所有 MOD 数据使用 `owner_id` 分区。Guest 的 MOD owner 映射为
`-1`，与现有私密数据仓库的 guest 隔离方式一致；登录账号使用其账号
ID。这样避免 guest 的默认 `userId=1` 与账号 ID 空间混淆。

`mod_installations`、`mod_permission_grants` 和 MOD 存储均不加入
`CoreSyncStore` 的宿主同步白名单。

## 3. 授权生命周期

### 安装

-   安装记录生成 `installation_id`。
-   授权记录单独写入 `mod_permission_grants`。
-   只写入安装确认流程本次明确传入的授权集合。
-   不从旧版本或其他安装实例自动继承授权。
-   Profile 与获批权限组合不一致时，存储层拒绝安装。

### 升级

-   相同 Publisher、相同 Profile：保留本地存储命名空间。
-   每次升级都按本次确认集合重建 grants；旧 grants 不自动继承。
-   Publisher 或 Profile 改变：创建新的安装实例和新的存储命名空间。
-   旧命名空间可以保留，但新 Profile 不会读取旧 Profile 的数据。

### 权限撤销

-   对应 grant 写入 `revoked_at`。
-   当前过渡阶段先禁用 MOD，采用 fail-closed 策略。
-   P0-3 Runtime Session / Capability Broker 完成后，再接入即时 Session
    终止。

### 卸载

-   默认 `keepData=false`：删除安装、授权、存储元数据和存储数据。
-   `keepData=true`：删除安装和全部授权，但保留对应 Publisher/Profile
    的存储命名空间。
-   之后重新安装同一 MOD、同一 Publisher、同一 Profile
    时，可以重新挂载保留的数据；所有权限仍必须重新授权。
-   不同 Publisher 或不同 Profile 不会复用该命名空间。

## 4. 备份与恢复

### 备份导出

-   导出当前 owner 的安装元数据和 MOD 私有存储。
-   不导出 `mod_permission_grants`。
-   不导出 `mod_audit_events`。
-   过滤旧 `mods.registry.*` app_settings 键。
-   `standalone_networked` 和 `standalone_offline` 的 MOD
    自有数据可以随用户手动备份。
-   **不导出 `host_integrated_offline` 的 MOD 存储条目。**
    这类存储可能混有从宿主 API
    读取的数据，单靠本地标签无法证明其内容纯属 MOD
    自有数据，因此采用更严格的备份策略。元数据可以恢复，但 `used_bytes`
    归零。

### 备份恢复

恢复安装元数据时：

1.  生成新的 `installation_id`。
2.  强制 `enabled=0`。
3.  强制 `status=requires_reauthorization`。
4.  不恢复任何 grant。
5.  不恢复 audit events。
6.  保留符合备份策略的 MOD 自有存储数据；对应存储空间标记为 retained。
7.  用户重新安装/确认后，才能重新启用并挂载同 Publisher/Profile 的存储。

旧版数据库 v1-v7 的备份可以按已有兼容规则恢复到 v8；缺失的新 MOD
表按空数据处理。旧 `mods.registry.*` 不再恢复。

## 5. Profile 约束

存储层再次执行 D-SEC-001：

-   `host_integrated_offline` 不得拥有 `network.fetch`、MOD
    间消息、外部跳转等外发能力。
-   `standalone_networked` 不得拥有宿主业务 API。
-   `standalone_offline` 不得拥有宿主业务 API 或外发能力。
-   旧 `tasks.create` 作为过渡 capability 也被视为宿主业务写入能力。

注意：当前旧版 `ModRegistry` 仍只支持声明式任务模板。它根据已知的旧
`tasks.create` 权限将 MOD 标记为 `host_integrated_offline`。新 Manifest
V1 的完整权限审批、Publisher 审核和 Store Attestation
仍待后续安装/审核链路接入；不能把本批存储层改造视为完整信任链已经完成。

## 6. 测试覆盖

新增/更新测试覆盖：

-   旧声明式 Manifest 参数校验和白名单。
-   安装、启停、卸载及审计。
-   依赖和升级版本保护。
-   升级时不继承旧权限。
-   撤销权限后禁用 MOD。
-   备份恢复后安装进入 `requires_reauthorization` 且无 grants。
-   重新授权后才能启用。
-   多账号安装状态和存储命名空间隔离。
-   重置当前账号数据不影响其他账号 MOD。
-   卸载保留数据后，同 Publisher/Profile 重新安装可恢复 MOD 自有数据。
-   Profile 变化时不跨 Profile 读取存储。
-   `storage.local` 权限检查和 UTF-8 字节配额。
-   Host business 与 egress capability 混合时拒绝。
-   standalone MOD 自有数据备份恢复。
-   host-integrated offline MOD 存储条目不进入备份。
-   v7 备份恢复到 v8。

## 7. 验证结果与限制

本次执行了 SQLite DDL 验证：

-   五张表可以在 SQLite 中成功创建。
-   复合外键拒绝跨 owner 写入。
-   删除存储 metadata 会级联删除 installation、grants 和 storage
    entries。

当前执行环境没有 Flutter/Dart SDK，因此没有运行
`flutter test`、`dart analyze` 或
`dart format`。这些测试必须在项目开发环境中执行。本报告不把 SQLite DDL
检查等同于 Flutter 集成测试通过。

## 8. 尚未完成

本批不包含：

-   新 Manifest V1 与当前 `ModRegistry` 安装流程的最终接线。
-   管理员批准权限与用户授权的完整三方权限计算。
-   Store Attestation / Publisher 签名验证。
-   ZIP 包安装和安全解压。
-   Runtime Session 终止及 Capability Broker。
-   Android/Web 的网络外发阻断。
-   MOD 存储的跨设备云同步。

这些分别属于后续 P0-3、P0-4、P0-5
阶段。当前补丁不会开放第三方可执行代码。
