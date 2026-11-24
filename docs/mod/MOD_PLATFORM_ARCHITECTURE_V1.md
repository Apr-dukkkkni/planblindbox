# PlanBlindBox MOD 平台总体架构规范

**文档编号：** PBB-MOD-ARCH-001\
**版本：** Draft 0.1\
**日期：** 2026-11-09\
**状态：** 架构草案，供产品与技术评审；不是已实现功能\
**依据：** 用户已确认的产品决策、《PlanBlindBox MOD 平台开发交接文档》及
`1111.zip` 源码快照

------------------------------------------------------------------------

## 0. 规范用语与状态标记

本文中的：

-   **必须（MUST）**：正式规范要求。
-   **不得（MUST NOT）**：禁止行为。
-   **建议（SHOULD）**：默认采用；有充分理由时可调整。
-   **待确认（OPEN）**：尚未由产品方最终确认，不能当作冻结规范。

决策状态：

-   **\[已确认\]**：用户明确作出的产品决定。
-   **\[架构建议\]**：根据目标和源码提出的技术方案。
-   **\[待确认\]**：需要后续评审后才能冻结。

## 1. 产品定位与设计原则

### 1.1 平台定位

\[已确认\]

PlanBlindBox 是一个开放式 MOD 应用平台。宿主负责提供：

1.  MOD 发现、安装、更新、卸载和版本管理。
2.  MOD 运行环境与窗口容器。
3.  独立存储空间。
4.  开发者身份、市场分发和包完整性验证。
5.  可选的宿主业务 API。
6.  权限申请、管理员审核、用户授权和撤销。

第三方 MOD 可以拥有自己的业务逻辑、界面、本地数据库和云端服务。MOD
不必依赖 PlanBlindBox 的任务、习惯、打卡或日记数据。

PlanBlindBox 不负责统一所有 MOD 的业务逻辑，也不要求所有 MOD
使用相同数据库、语言或云服务。

### 1.2 核心原则

1.  独立 MOD 默认不访问宿主业务数据。
2.  MOD 自有数据可以存储在本地，也可以同步到开发者自己的云端。
3.  宿主数据及其衍生数据不得通过 MOD 外发。
4.  宿主 API 只能通过 Capability Broker
    暴露，不开放数据库连接、SQL、文件路径或密钥。
5.  管理员审核不能代替用户授权。
6.  MOD UI 与宿主 UI 分离；宿主只管理窗口、入口和生命周期。
7.  多 Runtime 通过 Adapter 扩展，不将生态永久绑定到 Flutter、JavaScript
    或某一种语言。
8.  首期先实现 Content Runtime 与 Web Runtime；WASM 等后续扩展。
9.  旧版 MOD Manifest
    不要求兼容；测试数据允许清理。但不得因此无理由重置账号、OPAQUE、私密仓库或核心业务数据库。

### 1.3 已确认的产品决定

  维度               决策
  ------------------ ----------------------------------------------------------
  旧版 MOD 兼容      不需要；可以替换旧 MOD 规范和测试数据
  MOD 定位           可独立运行的扩展应用平台
  MOD UI             全屏、弹窗、宿主内部悬浮组件
  MOD 入口           默认全部放在左侧侧边栏
  侧边栏唤出         首页叶子按钮；首页右滑/边缘滑动
  首页卡片           首期不强制；未来可按需提供
  MOD 自有数据       隔离本地存储
  MOD 自有云端       允许开发者自行提供和同步
  宿主数据访问       默认禁止；可申请只读和有限业务操作
  宿主数据外发       禁止，包括由宿主数据产生的摘要、统计和分析结果
  用户导出           用户可以通过 PlanBlindBox 自己的导出功能导出，再自行使用
  宿主主题 API       不提供
  宿主导航控制 API   不提供
  关闭 MOD           返回 PlanBlindBox 首页
  卸载               可选择保留或删除 MOD 自有数据
  重新安装           可以恢复保留的数据，但所有宿主权限必须重新授权
  MOD 间通信         产品方向允许；首期不开放，后续经 Broker 和授权实现
  快捷入口构建器     规划支持，优先采用声明式低代码方式

## 2. 范围与非目标

### 2.1 本规范范围

-   Host、MOD Shell、Runtime Manager、Runtime Adapter。
-   Package Manager、Marketplace、Publisher。
-   Capability Broker、Storage Manager、Network Policy。
-   MOD UI 入口、窗口和生命周期。
-   MOD 自有数据与宿主数据边界。
-   从现有任务模板 MOD 原型迁移到开放平台的总体路线。

### 2.2 非目标

首期不实现：

-   允许 MOD 加载任意 Android APK、DEX、动态原生库。
-   允许 MOD 直接操作宿主数据库或执行 SQL。
-   允许 MOD 修改宿主主题、底部导航、页面路由或宿主布局。
-   允许 MOD 在其他 APP 上方任意显示系统级悬浮窗。
-   无限制的 MOD-to-MOD RPC 或共享数据库。
-   把宿主的用户 JWT、OPAQUE 凭据、AMK 交给 MOD。
-   为旧版 `schemaVersion: 1` 任务模板格式提供长期兼容层。

## 3. 概念模型：产品类型、Runtime 与安全配置分离

这三个维度不能混为一谈。

### 3.1 产品类型（建议枚举）

\[架构建议，枚举待确认\]

  ---------------------------------------------------------------------------------------------------
  `type`          说明                               示例
  --------------- ---------------------------------- ------------------------------------------------
  `content`       声明式内容，不执行第三方任意代码   任务模板、主题、商店资源包、奖励规则、快捷入口

  `app`           可执行的独立应用                   农场、宠物、Anki、健身、小游戏、AI 工具
  ---------------------------------------------------------------------------------------------------

`contentKind` 可进一步区分：

-   `task_template`
-   `theme`
-   `shop_resource_pack`
-   `reward_rules`
-   `link_hub`

`link_hub` 是低代码快捷入口集合，不需要为了简单跳转就运行任意
JavaScript。

### 3.2 Runtime 类型（建议枚举）

  Runtime            首期    用途
  --------------- ---------- --------------------------
  `declarative`       是     解析 Schema 化内容
  `web`               是     HTML/CSS/JavaScript 应用
  `wasm`           否，后续  受限的高性能模块
  其他 Runtime       后续    通过 Adapter 扩展

产品类型与 Runtime 独立。例如：

-   主题：`type=content`、`runtime=declarative`。
-   农场：`type=app`、`runtime=web`。
-   Anki：`type=app`、`runtime=web`。
-   快捷入口：`type=content`、`contentKind=link_hub`、`runtime=declarative`。

### 3.3 安全配置（建议）

建议在 Manifest 中声明 `securityProfile`：

-   `standalone_networked`：独立应用，可使用 MOD
    自有持久化存储和获批网络访问，不可读取宿主数据。
-   `host_integrated_local`：可申请宿主数据读取；运行环境不允许网络外发，且必须限制外部通道。持久化数据在切换到网络模式前必须整体清除。
-   `host_write_only`：只申请明确的写入型宿主操作，不读取已有宿主数据；是否允许与网络能力共存，须按具体操作
    API 单独审核。

`securityProfile` 是运行时安全约束，不是展示标签。Runtime Manager 和
Capability Broker 必须执行，不能只相信 Manifest 自我声明。

## 4. 总体架构

``` text
第三方开发者
    |
    v
MOD Developer SDK / CLI
    |
    v
Marketplace / Publisher Platform
    |  发布、审核、签名证明、版本、分发
    v
MOD Package Manager
    |  下载、校验、安装、升级、卸载
    v
MOD Platform Manager
    +-----------------------------+
    |                             |
    v                             v
MOD Shell                    Capability Broker
    |                             |
    |                             +--> Host Business APIs
    |                             +--> Private Vault Adapter
    |                             +--> Network Policy / Proxy
    |                             +--> Storage Manager
    |                             +--> (later) MOD Event Broker
    |
    v
Runtime Manager
    |
    +--> Content Runtime Adapter
    +--> Web Runtime Adapter
    +--> (later) WASM Runtime Adapter
    |
    v
第三方 MOD
```

### 4.1 Host

Host 是 PlanBlindBox 核心应用，负责：

-   账号和会话。
-   核心任务、习惯、打卡、奖励等业务。
-   私密数据仓库。
-   宿主自己的云同步。
-   MOD 平台入口和生命周期协调。

Host 不向 MOD 暴露内部 Repository、SQLite Database、JWT 或密钥。

### 4.2 MOD Shell

MOD Shell 是统一的应用窗口容器，负责：

-   从左侧侧边栏列出已安装并启用的 MOD。
-   根据 Manifest 中的 UI 声明打开全屏、弹窗或宿主内部悬浮组件。
-   管理窗口栈和 Android 返回键。
-   关闭 MOD 后返回 PlanBlindBox 首页。
-   在未来按用户选择提供首页卡片入口。
-   显示 MOD 名称、图标、运行错误和必要的权限提示。

MOD 不得自行改变宿主底部导航、主题、页面路由或任意宿主 UI。

### 4.3 Runtime Manager

统一管理：

-   包验证与 Runtime 兼容性。
-   Session 创建和销毁。
-   启动、暂停、恢复、停止。
-   资源限额。
-   崩溃隔离和错误日志。
-   权限上下文绑定。
-   运行环境清理。

每个 Runtime Adapter 实现统一接口，但不要求内部实现相同。

### 4.4 Capability Broker

所有宿主能力必须经过 Broker。Broker 至少验证：

1.  MOD ID。
2.  Publisher 身份。
3.  安装实例 ID。
4.  Runtime Session ID。
5.  当前 MOD 版本和包摘要。
6.  Manifest 声明。
7.  管理员审批。
8.  用户授权。
9.  当前 Runtime 和安全配置是否支持。
10. 参数 Schema、范围、频率和资源限制。

任何检查失败均默认拒绝。

### 4.5 Storage Manager

为每个 MOD 提供独立存储命名空间：

-   数据库。
-   文件。
-   缓存。
-   Web Storage / IndexedDB（Web Runtime 适用时）。
-   配额。
-   备份、导入和导出。
-   数据保留和删除。

MOD 不能指定宿主文件系统的任意路径。

## 5. MOD UI 与入口

### 5.1 统一入口

所有已安装 MOD 默认出现在左侧 MOD
侧边栏。首页叶子按钮用于打开侧边栏；首页右滑/边缘滑动也可以打开。

现有源码已通过 `AppShell` 的 `Scaffold.drawer` 挂载
`ModHubDrawer`，TodayPage 顶部叶子按钮已经调用 `openDrawer()`。Flutter
Scaffold 自带边缘拖动开 Drawer
的行为，但需要在实际目标平台验证；当前源码未发现单独实现的全屏右滑手势。

### 5.2 展示模式

Manifest 可声明允许的模式：

-   `full_screen`
-   `modal`
-   `overlay`

`overlay` 仅指 PlanBlindBox 内部悬浮层，不代表 Android 系统级悬浮窗。

Host 决定最终窗口尺寸、层级、关闭方式和返回行为。MOD
不得强迫宿主接受不受限制的窗口配置。

### 5.3 首页卡片

首期不要求每个 MOD 都提供首页卡片。未来可增加 `host.home_widget` 能力：

-   用户主动授权。
-   宿主控制尺寸、位置和刷新频率。
-   MOD 只能提交受限 Widget 描述或渲染内容。
-   不允许通过 Widget 绕过宿主数据权限。

### 5.4 外部应用跳转

快捷入口 MOD 可声明外部链接。建议采用 `host.external_link.open`：

-   只能在用户明确点击后触发。
-   只允许 HTTPS URL 或经审核的 App Link / Deep Link。
-   不允许 `file://`、任意 Intent action 或隐式传递宿主数据。
-   无法打开目标应用时显示失败提示或提供网页回退。

## 6. 生命周期与状态模型

安装、信任、启用和运行状态相互独立，不能用一个互斥枚举表达全部状态。

  维度      示例状态
  --------- ----------------------------------------------------------
  Trust     `UNREVIEWED`、`APPROVED`、`REVOKED`
  Install   `DOWNLOADED`、`VERIFIED`、`INSTALLED`、`FAILED`
  Enable    `ENABLED`、`DISABLED`
  Runtime   `STOPPED`、`STARTING`、`RUNNING`、`SUSPENDED`、`CRASHED`

### 6.1 系统进程回收

Android 因内存压力结束 WebView/应用进程，不等于用户卸载 MOD：

-   安装记录保留。
-   用户授权保留（除非已撤销、过期或版本变化要求重新授权）。
-   MOD 自有持久化数据保留。
-   Runtime Session 销毁。
-   下次打开时创建新 Session 并从持久化状态恢复。

### 6.2 用户卸载

卸载时允许：

-   删除 MOD 及其本地数据。
-   卸载 MOD 但保留其数据。

保留的数据必须处于不可运行状态，不得保留旧权限。

### 6.3 重新安装

重新安装时：

-   生成新的 `installation_id`。
-   所有宿主权限重新申请和授权。
-   如果用户选择恢复保留的数据，必须验证 MOD ID、Publisher
    身份和数据格式。
-   如果安全配置从 `host_integrated_local` 切换为
    `standalone_networked`，在开放网络之前清空该 MOD
    的全部持久化数据、缓存、Web Storage、Service Worker
    和相关运行状态，防止此前缓存的宿主数据延迟外发。

## 7. MOD 数据与宿主数据

### 7.1 数据所有权

-   MOD 自己创建的数据：属于 MOD
    自有数据，可以按授权同步到开发者自己的云端。
-   PlanBlindBox 提供的数据：属于宿主数据。
-   从宿主数据计算、摘要、汇总、分类、预测或 AI
    分析得到的结果：仍属于宿主数据。
-   混合使用宿主数据和 MOD
    数据产生的结果：只要宿主数据对结果有贡献，按宿主数据处理。
-   用户在 MOD 内自行输入的数据：属于 MOD
    数据；若被写入宿主业务，宿主只接受经过授权的业务操作。

### 7.2 禁止外发原则

MOD 不得通过网络、MOD
间消息、剪贴板、系统分享、文件导出、外部跳转参数或其他应用可控通道外发宿主数据。

用户主动使用 PlanBlindBox 自己的导出功能导出数据，不属于 MOD 外发；MOD
不得调用或模拟该导出流程。

### 7.3 与现有私密数据仓库集成

当前源码中：

-   `PrivateSyncVault` 持有 256-bit AMK
    的内存副本，并可从设备安全存储恢复。
-   `AccountMasterKeyEnvelope` 使用 OPAQUE export key 派生包装密钥，使用
    AES-256-GCM 包装 AMK。
-   `PrivateVaultStore` 将日记和自定义情绪数据保存为 AES-GCM 密文信封。
-   `WellbeingRepository` 通过 PrivateVaultStore
    读写日记、情绪和经期字段。
-   任务和习惯数据在本地 SQLite 的普通业务表中，并通过核心同步机制处理。

未来 MOD 只能调用 Host API。私密仓库解密由 Host 完成；AMK、OPAQUE export
key、JWT、数据库句柄和 SQL 均不得交给 MOD。

## 8. 开发者与市场

市场至少需要：

-   Publisher 个人/组织身份。
-   MOD ID 所有权。
-   Publisher Key 注册、轮换和撤销。
-   MOD 版本与不可变安装包制品。
-   自动化包检查。
-   权限和域名审核。
-   人工审核记录。
-   平台审核证明。
-   下架、撤销、申诉和安全公告。
-   安装包对象存储及 CDN 分发。

市场发布不能再等同于"保存 Manifest 后立即 PUBLISHED"。

## 9. 平台支持策略

`1111.zip` 包含 Flutter Android、Web 和 Windows
工程结构；这不等于这些平台已经具备 MOD Runtime。

建议为每个 Runtime Adapter 和平台维护能力矩阵：

  -----------------------------------------------------------------------------------
  能力           Android                Flutter Web            Windows
  -------------- ---------------------- ---------------------- ----------------------
  Content        待实现                 待实现                 待实现
  Runtime                                                      

  Web Runtime    待安全验证             待安全验证             待选型

  宿主数据集成   仅隔离验证通过后开放   仅隔离验证通过后开放   仅隔离验证通过后开放

  网络代理       待实现                 待实现                 待实现

  悬浮 UI        宿主内覆盖层           宿主内覆盖层           宿主内覆盖层
  -----------------------------------------------------------------------------------

若某个平台无法证明 Web Runtime
对宿主数据的网络隔离，就不得在该平台授予宿主数据读取权限。

## 10. 现有源码基线与改造边界

### 10.1 当前已存在的 MOD 能力

  ----------------------------------------------------------------------------------------
  源码位置                                          当前行为
  ------------------------------------------------- --------------------------------------
  `frontend/lib/services/mod_registry.dart`         `schemaVersion: 1` JSON
                                                    Manifest；只支持 `tasks.create` 和
                                                    `taskTemplates`；注册表写入
                                                    `app_settings` 的 `mods.registry.v1`

  `frontend/lib/services/mod_import_flow.dart`      只导入 JSON
                                                    文件；展示权限确认；不执行第三方代码

  `frontend/lib/data/mod_market_api.dart`           查询市场元数据；下载 Manifest
                                                    文本；校验 Manifest 的 SHA-256

  `frontend/lib/screens/mod_hub_drawer.dart`        侧边栏展示任务模板、市场和 JSON 导入

  `frontend/lib/screens/mod_management_page.dart`   管理启停、卸载和模板

  `frontend/lib/screens/app_shell.dart`             `Scaffold.drawer` 挂载 MOD 侧边栏

  `mod-server/.../ManifestValidator.java`           服务端校验旧 Manifest，限制唯一权限为
                                                    `tasks.create`

  `mod-server/.../ModCatalogService.java`           保存 Manifest JSON；下载返回
                                                    Manifest；下载统计使用事务和 Outbox

  `mod-server/.../ModAdminController.java`          使用单一 `MOD_ADMIN_TOKEN`
                                                    发布和控制上架状态
  ----------------------------------------------------------------------------------------

### 10.2 当前尚不存在的能力

-   ZIP 安装包上传、存储、下载。
-   Publisher 账户和密钥管理。
-   Publisher 签名与 Store Attestation。
-   Manifest v1 新 Schema。
-   Runtime Manager / Adapter。
-   可执行 MOD 的隔离运行环境。
-   MOD Shell 窗口管理。
-   Capability Broker。
-   宿主 API 权限目录和授权记录。
-   MOD 独立数据库和文件配额。
-   网络代理与外发隔离。
-   MOD Event Broker。
-   依赖 SemVer 约束。
-   开发者 SDK / CLI。

注意：`webview_flutter` 目前在 OPAQUE 客户端实现中被使用；源码中没有发现
MOD Web Runtime。不能把已有 OPAQUE WebView 当作 MOD 沙箱。

### 10.3 数据库现状

当前 MOD 市场 Flyway V1/V2 主要建立：

-   `mod_packages`
-   `mod_versions`
-   `mod_download_events`
-   `mod_download_outbox`

尚无 Publisher、安装包制品、权限审批、用户授权和安装实例表。

现有 `mod_download_events` 与 `mod_download_outbox`
的事务幂等设计值得保留。市场升级时不应破坏这条下载统计链路。

### 10.4 重构原则

-   旧 MOD Manifest 和本地 `mods.registry.v1` 不提供兼容承诺。
-   MOD 专属数据可以重建。
-   不因 MOD 重构而删除核心账号、OPAQUE、AMK、私密仓库或任务习惯数据表。
-   已应用的 Flyway
    迁移不应直接改写；测试环境可以重建数据库，正式迁移仍需新增版本迁移。
-   保留现有市场下载 Outbox
    的可靠投递思想，并重新设计安装包下载的幂等接口。

### 10.5 源码归档卫生

本次 `1111.zip` 还包含 `frontend/.dart_tool/chrome-device/Default/`
浏览器用户目录，其中可见 Cookies、Login Data、History、IndexedDB
等浏览器配置/数据文件；同时归档中还包含若干构建缓存、Gradle
缓存、`android/local.properties` 和嵌套 ZIP。

这些内容不是 MOD
平台源码的必要组成部分，可能包含本机路径、浏览器会话或开发环境信息。后续分享源码前建议排除：

-   `.dart_tool/`
-   `build/`
-   `.gradle/`
-   `.kotlin/`
-   `windows/flutter/ephemeral/`
-   `android/local.properties`
-   本地浏览器用户目录
-   无需随源码分发的嵌套构建 ZIP

如果该浏览器目录曾登录真实账号，应按可能包含会话凭据处理，并在必要时注销/撤销相关会话。这里不据此断言文件中一定存在有效登录凭据。

## 11. 建议实施阶段

  阶段   目标
  ------ -----------------------------------------------------
  P0     冻结安全模型、数据流规则、Manifest/Package 核心约束
  P1     Manifest、Package、签名和校验工具
  P2     MOD Shell、Content Runtime、安装管理
  P3     Publisher、审核、制品存储和市场分发
  P4     Web Runtime、Capability Broker、网络策略
  P5     独立存储、窗口和生命周期
  P6     JavaScript SDK、CLI、示例 MOD、低代码快捷入口构建器
  P7     MOD Event Broker、WASM Runtime 和更多语言

## 12. 待确认事项

1.  首期正式支持哪些运行平台：Android、Flutter Web、Windows
    是否同时上线？
2.  `type`、`contentKind`、`securityProfile` 最终枚举。
3.  宿主只读 API 的第一批数据域和字段范围。
4.  首期有限写操作的具体白名单。
5.  宿主数据集成模式下是否允许持久化 MOD
    自有本地数据；若允许，平台切换到网络模式时必须整体清除。
6.  全屏、弹窗、悬浮组件的尺寸、数量和资源上限。
7.  首页 Widget 是否纳入首期以外的正式路线。
8.  Publisher 是否首期就支持组织账号。

------------------------------------------------------------------------

**本规范的目标不是让所有 MOD 变成 PlanBlindBox 的子功能，而是让
PlanBlindBox 成为一个有明确安全边界、可以托管独立应用的开放平台。**
