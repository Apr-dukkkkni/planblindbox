# PlanBlindBox MOD 安全架构评审报告

**文档编号：** PBB-MOD-SEC-REVIEW-001\
**版本：** Draft 0.3\
**日期：** 2026-11-09\
**评审对象：** MOD 平台安全架构草案 Draft 0.1 与 `1111.zip` 源码快照\
**结论：**
核心方向正确，但安全规范尚不宜冻结；需先修正权限组合、网络出口、存储隔离和账户生命周期约束。

------------------------------------------------------------------------

## 1. 执行摘要

本轮评审的核心问题是：

> 如果一个第三方 MOD
> 开发者是恶意的，并且会主动尝试绕过权限系统，PlanBlindBox
> 是否仍能阻止它将宿主数据发送到外部？

结论：

1.  当前 `1111.zip` 中的 MOD 仍是 JSON 声明式任务模板，没有第三方可执行
    Runtime。因此当前版本尚未形成"恶意 MOD 代码读取宿主数据"的攻击面。
2.  Draft 0.1
    正确识别了最重要的风险：**只要同一段不可信代码同时能读取宿主数据和访问网络，就不能靠权限声明或数据标签保证不外发。**
3.  Draft 0.1 仍有一个重要缺口：`host_integrated_offline` 的写入型能力
    的网络组合尚未明确。只要 MOD
    可以创建/修改宿主记录，它就知道写入内容；如果同时能联网，就可能把同一内容上传。
4.  `securityProfile` 不应由开发者在 Manifest
    中自行决定并作为权威值。它应由平台根据经过审核的权限集合、Runtime
    能力和包摘要计算，并写入平台签名的审核证明。
5.  Web Runtime 的网络访问不能只靠 SDK 约定。所有 MOD
    的直接网络请求都应被阻断；独立联网 MOD 也只能通过宿主的 Network
    Gateway 发请求。
6.  宿主集成模式不应通过"切换前删除同一份存储"来实现网络隔离。应使用不同安装实例、不同
    Origin 和不同存储命名空间；不允许把离线集成数据自动迁移到联网实例。
7.  首期必须禁止宿主集成 MOD 使用 MOD
    间消息、剪贴板写入、系统分享、外部跳转、文件导出、通知/首页 Widget
    和第三方遥测等潜在外发通道。

**建议的首期安全模型：**

-   `standalone_networked`：可同步 MOD
    自己的数据；不得调用任何宿主业务读写 API。
-   `host_integrated_offline`：可申请宿主只读和有限业务操作；不得访问任何外部网络或外发通道。
-   `declarative`：不执行任意第三方代码；仅开放具体内容类型允许的宿主动作。
-   以上执行配置由平台计算，不由开发者自行声明为可信事实。

------------------------------------------------------------------------

## 2. 本轮实际核查的源码依据

以下结论来自本次打开的源码文件，不代表已经逐行审计整个仓库。

### 2.1 当前 MOD 客户端

  --------------------------------------------------------------------------------------------------------------------------------------------------------
  文件                                               实际行为                                                       安全含义
  -------------------------------------------------- -------------------------------------------------------------- --------------------------------------
  `frontend/lib/services/mod_registry.dart`          只解析 `schemaVersion: 1` JSON；权限只有                       当前是声明式配置，不是可执行插件系统
                                                     `tasks.create`；只支持 `taskTemplates`；注册表存入             
                                                     `app_settings` 的 `mods.registry.v1`                           

  `frontend/lib/services/mod_import_flow.dart`       只允许导入                                                     当前没有任意第三方代码执行入口
                                                     JSON；导入时展示权限勾选对话框；注释明确说明不执行第三方代码   

  `frontend/lib/data/mod_market_api.dart`            下载 Manifest，并对服务端返回的 Manifest SHA-256               哈希校验不等于 Publisher
                                                     做一致性校验；下载请求使用 `AuthSession` 中的 Bearer Token     身份认证；未来 MOD Runtime 不得获得该
                                                                                                                    AuthSession 或 Token

  `frontend/lib/services/private_sync_vault.dart`    管理 AMK 的内存副本和设备安全存储副本；提供私密记录加解密      MOD 不得接触该单例或密钥

  `frontend/lib/services/private_vault_store.dart`   将日记、自定义情绪等记录以加密信封存入                         MOD 只能通过经授权的 Host API
                                                     `private_vault_records`，读取时由 Host 解密                    获取受限明文，不能访问 Store 或数据库
  --------------------------------------------------------------------------------------------------------------------------------------------------------

### 2.2 当前 MOD 服务端

  -------------------------------------------------------------------------------------------------------------
  文件                        实际行为                       安全含义
  --------------------------- ------------------------------ --------------------------------------------------
  `ManifestValidator.java`    限制旧版 JSON Manifest；启用   服务端严格解析值得保留
                              JSON 重复字段检测              

  `ModCatalogService.java`    保存 Manifest JSON             当前没有安装包制品存储或签名链
                              和版本；下载返回               
                              Manifest；下载统计使用事务与   
                              Outbox                         

  `ModAdminController.java`   使用单一 `mod.admin-token`     只适合当前小规模管理原型，不适合作为开放 Publisher
                              Bearer Token                   平台的长期身份与审核体系

  `SecurityConfig.java`       Admin Filter Chain 对          未来应改为管理员身份认证、RBAC、审计和可撤销凭据
                              `/api/v1/admin/**` 使用        
                              `permitAll()`，实际由          
                              Controller 手动校验共享令牌    
  -------------------------------------------------------------------------------------------------------------

### 2.3 一个解析一致性问题

当前 Java `ManifestValidator` 使用 `STRICT_DUPLICATE_DETECTION`；Dart
`ModRegistry.parseManifest` 使用普通
`jsonDecode`，没有对应的重复键拒绝逻辑。

新 Manifest V1 必须让客户端、服务端、CLI
对重复键、未知字段、数字类型、Unicode 规范化和签名字节得到一致结论。JSON
Schema 本身不能代替解析器的重复键检测。

------------------------------------------------------------------------

## 3. 安全发现与整改要求

严重程度：

-   **Critical**：不修复就不应开放宿主数据 API 或可执行 Runtime。
-   **High**：首期正式发布前必须完成。
-   **Medium**：首期发布前完成，或明确列入受控的后续阶段。

### SEC-01 --- 宿主写入 API 与网络权限组合不明确

`<badge>`{=html}Critical`</badge>`{=html}

Draft 0.1 已禁止 `host.data.*.read + network.fetch`，但
`host_integrated_offline` 的写入型能力 仍保留了"是否允许网络由具体 API
审核"的开放口子。

问题示例：

1.  MOD 请求 `host.tasks.create`。
2.  用户在 MOD 中填写任务标题和备注。
3.  MOD 调用 Host API 创建任务。
4.  同一 MOD 仍持有 `network.fetch`，可以把刚才的标题和备注上传。

即使 MOD 没有读取旧任务，它仍知道自己刚写入的内容。若用户要求所有
PlanBlindBox 任务数据不得通过 MOD 外发，这个组合无法被可靠地允许。

**整改建议：**

首期把所有宿主业务读写能力统一归为 `host_integrated_offline`：

-   任何 `host.data.*.read`：禁止网络。
-   任何 `host.*.create/update/check_in/delete`
    等宿主业务写操作：同样禁止网络。
-   同时禁止 MOD
    消息、剪贴板写入、系统分享、外部跳转、文件导出和远程遥测。
-   只有不含任何宿主业务 API 的独立 MOD 才能申请 `network.fetch`。

若未来确实需要一个 MOD 同时"访问宿主数据 +
同步自己的数据"，必须设计不同信任域的独立组件和严格数据通道；不能仅通过两个权限复选框实现。

**需要产品方确认：** 由 MOD 创建后写入 PlanBlindBox
的任务标题、备注等内容，是否也必须视为宿主数据，禁止 MOD
随后上传？本报告建议按"是"处理。

### SEC-02 --- `securityProfile` 不能由 Manifest 自我授权

`<badge>`{=html}Critical`</badge>`{=html}

Draft 0.1 建议在 Manifest 中声明 `securityProfile`。但 Manifest
是开发者提供的不可信输入，不能让开发者通过填入某个字符串决定自己运行时的安全边界。

**整改建议：**

-   Manifest 只声明能力请求，不把 `securityProfile` 当作可信授权。
-   平台根据审核批准的权限、用户授权、Runtime 类型和平台能力计算
    `effectiveProfile`。
-   `effectiveProfile` 由平台签名的 Store Attestation 绑定到 MOD
    ID、版本、包摘要、Publisher Key ID 和策略版本。
-   客户端安装时重新计算并比对；Manifest 请求与 Attestation
    不一致则拒绝安装。
-   Runtime Manager 每次创建 Session 时再检查有效 Profile。

建议首期只保留两个可执行 Profile：

  Profile                     宿主业务 API                   MOD 自有网络
  --------------------------- ------------------------------ ----------------------
  `standalone_networked`      全部禁止                       经 Broker 审核后允许
  `host_integrated_offline`   只读和有限写操作，按用户授权   全部禁止

`declarative` 是内容执行方式，不应与可执行 App 的安全 Profile 混为一谈。

### SEC-03 --- Network Gateway 必须是唯一外部网络出口

`<badge>`{=html}Critical`</badge>`{=html}

Draft 0.1 提到了 Network Gateway，但没有明确规定 MOD 的直接网络 API
必须全部失效。

仅提供 `mod.network.fetch()` SDK 不够。第三方代码仍可能直接使用：

-   `fetch` / XHR
-   WebSocket / EventSource / sendBeacon
-   图片、脚本、字体、CSS URL
-   表单提交
-   iframe、Worker、Service Worker
-   导航、下载、弹窗和 Deep Link

**整改建议：**

1.  Web Runtime 的所有直接外部网络请求默认阻断。
2.  `connect-src` 默认 `none`，禁止远程脚本、远程字体、远程图片和远程
    iframe。
3.  MOD 的网络请求只能通过 Host Bridge 调用 `network.fetch`，再由原生
    Network Gateway 发出。
4.  首期不提供 WebSocket、SSE、Service Worker 和动态远程代码加载。
5.  Network Gateway 只允许 Manifest/审核记录中精确批准的 HTTPS
    域名、HTTP 方法和路径。
6.  每次请求校验 DNS 解析结果和重定向目标，阻止
    loopback、私网、链路本地、云元数据 IP 和不允许端口。
7.  Network Gateway 使用独立 HTTP Client；不得复用 `AuthSession`、宿主
    JWT、Cookie 或核心同步认证拦截器。
8.  远程响应只作为数据返回，不允许作为脚本或模块执行。

### SEC-04 --- 离线集成模式切换到联网模式的存储残留

`<badge>`{=html}High`</badge>`{=html}

Draft 0.1 提出在授予网络能力前清理数据库、LocalStorage、IndexedDB、Cache
Storage、Service Worker 等。但仅调用删除操作不能可靠保证 SQLite
WAL、浏览器缓存、闪存旧页和备份中的数据都被物理清除。

**整改建议：**

-   不允许同一个安装实例从 `host_integrated_offline` 原地切换为
    `standalone_networked`。
-   切换 Profile 必须创建新的 `installation_id`、新的 Runtime Origin
    和新的存储命名空间。
-   联网实例永远不能挂载离线集成实例的数据库、文件、缓存或 Web Storage。
-   不提供离线集成存储到联网实例的自动迁移。
-   MOD 自有存储使用每安装实例独立的加密密钥；删除安装实例时销毁该密钥。
-   Web Runtime 不应把不可控的浏览器持久化空间作为唯一数据存储；优先通过
    Storage Manager 提供隔离、配额受控的持久化 API。

这样即使旧离线数据的物理页尚未被覆盖，新联网实例也没有访问它的路径。

### SEC-05 --- 宿主数据外发通道不能只考虑 HTTP

`<badge>`{=html}High`</badge>`{=html}

宿主数据外发不限于 `fetch`。在 `host_integrated_offline`
中，首期必须同时禁用：

-   网络请求和后台网络任务。
-   MOD-to-MOD 消息。
-   系统分享和文件导出。
-   剪贴板写入。
-   外部应用跳转、任意 Intent 和外部浏览器导航。
-   通知内容、首页 Widget 等可能暴露数据的宿主扩展。
-   第三方崩溃上报和遥测。
-   外部文件写入或系统文件选择器导出。

用户可以通过 PlanBlindBox 自己的导出功能主动导出数据；MOD
不得调用该功能或接管导出流程。

### SEC-06 --- 账号、私密仓库和 MOD Session 的生命周期没有完整绑定

`<badge>`{=html}High`</badge>`{=html}

当前私密仓库由 `PrivateSyncVault` 管理 AMK，`PrivateVaultStore`
负责解密。未来 MOD Session 必须绑定用户身份和私密仓库状态。

**整改建议：**

-   MOD Session 绑定 `user_id`、`installation_id`、包摘要和权限版本。
-   用户登出、切换账号、锁定私密仓库、撤销日记权限时，立即终止相关集成
    Session。
-   私密仓库锁定后，日记 API 必须失败；不能继续使用之前的长效授权。
-   不向 MOD 暴露 `AuthSession`、JWT、AMK、OPAQUE export
    key、`PrivateSyncVault`、`PrivateVaultStore`、Repository
    或数据库句柄。
-   Host API 只返回字段白名单和必要数据。
-   Session 结束后销毁 WebView/Runtime 实例，清理 Host
    侧临时明文缓冲区；不承诺 JavaScript 内存能被精确物理清零。

### SEC-07 --- 当前 SHA-256 校验不是包真实性验证

`<badge>`{=html}High`</badge>`{=html}

当前 `ModMarketApi` 校验服务端返回的 Manifest 与服务端同时给出的 SHA-256
是否一致。这可以发现传输或存储中的部分意外损坏，但如果响应和哈希来自同一被攻陷的服务端，攻击者可以同时替换两者。

**整改建议：**

-   Publisher Ed25519 签名覆盖 Manifest 和全部文件摘要。
-   Platform Store Attestation
    由独立平台密钥签名，并绑定同一包摘要、审核状态和权限批准。
-   安装器内置或安全获取平台信任根。
-   所有可执行脚本、WASM 和依赖必须包含在已签名包中。
-   禁止运行时从 CDN 或开发者服务器下载并执行代码。
-   ZIP 解压前完整验证路径、文件数量、压缩比、文件大小和所有摘要。
-   官方市场、手动 ZIP
    和开发者调试使用不同信任等级；未审核包不得获得宿主数据权限。

### SEC-08 --- 当前管理员共享令牌不适合开放 Publisher 平台

`<badge>`{=html}High`</badge>`{=html}

当前 `ModAdminController` 使用单一 `mod.admin-token`，而
`SecurityConfig` 的 Admin Chain 对路径 `permitAll()`，最终依赖
Controller 手动比较共享令牌。

**整改建议：**

正式市场采用管理员身份认证和 RBAC：

-   `MOD_REVIEWER`
-   `MOD_SECURITY_ADMIN`
-   `MOD_MARKET_OPERATOR`
-   `MOD_PUBLISHER`

所有审核、发布、下架、撤销和密钥操作均记录操作者、时间、对象摘要和原因。紧急撤销需要独立权限和审计。

### SEC-09 --- 客户端和服务端 Manifest 解析不一致

`<badge>`{=html}Medium`</badge>`{=html}

Java 服务端启用重复键检测，Dart 客户端当前使用普通 `jsonDecode`。

**整改建议：**

-   Flutter、Java、CLI 使用一致的严格 JSON 解析规则。
-   拒绝重复键、未知字段、尾随内容和非法 Unicode。
-   对签名 JSON 使用固定规范化规则。
-   通过跨语言测试向量验证相同输入产生相同摘要和校验结果。

### SEC-10 --- `required` 权限的安装语义未冻结

`<badge>`{=html}Medium`</badge>`{=html}

新 Manifest 草案包含 `required`
字段，但需要明确用户拒绝必需权限时的行为。

**整改建议：**

-   用户拒绝任何 `required=true`
    权限：阻止安装，或安装为明确标记的受限状态；首期建议阻止启用。
-   用户拒绝 `required=false` 权限：允许安装，但相应功能必须不可用。
-   升级新增权限或扩大 Scope：重新审核和重新授权。
-   权限授权绑定 `installation_id`，不能按 MOD ID 或 Publisher
    自动继承。

### SEC-11 --- Runtime 资源消耗与崩溃隔离

`<badge>`{=html}Medium`</badge>`{=html}

需要补充
CPU、内存、存储、网络速率、请求体、响应体、并发、启动时间和后台运行限制。MOD
崩溃不得拖垮 Host；异常退出后不应自动无限重启。

### SEC-12 --- 平台能力必须逐平台验收

`<badge>`{=html}High`</badge>`{=html}

Android WebView、Flutter Web iframe、Windows WebView2
的安全能力并不相同。

**整改建议：**

-   每个平台单独维护安全能力矩阵。
-   只有通过直接网络阻断、导航阻断、存储隔离、桥接隔离和恶意测试的平台，才能开放宿主数据
    API。
-   某平台尚未通过验证时，仍可运行独立联网 MOD，但不能授予宿主数据权限。
-   不以"理论上支持 WebView/iframe"代替实际安全验收。

------------------------------------------------------------------------

## 4. 建议冻结的首期安全模型

### 4.1 权限组合矩阵

  ---------------------------------------------------------------------------------------------
  能力                         独立联网 MOD    宿主集成离线 MOD            声明式内容
  -------------------------- ---------------- ------------------ ------------------------------
  MOD 自有本地存储                 允许         允许，隔离存储            由 Host 管理

  MOD 自有云端同步             允许，经审核          禁止              不执行任意网络代码

  宿主任务/习惯/打卡读取           禁止           申请后允许         仅限内容类型定义的动作

  宿主日记/情绪读取                禁止        高敏感审批后允许         禁止任意明文读取

  宿主任务创建/有限操作            禁止           申请后允许            允许特定模板动作

  外部分享/剪贴板/文件导出    按独立权限控制         禁止         仅用户主动点击允许的固定链接

  MOD 间通信                     首期关闭            禁止                    不适用

  宿主 JWT/OPAQUE/AMK              禁止              禁止                     禁止
  ---------------------------------------------------------------------------------------------

### 4.2 Profile 由平台计算

建议 Manifest 只声明能力请求。平台按审核结果计算：

``` text
if any host business read/write capability:
    effectiveProfile = host_integrated_offline
else if network.fetch is approved:
    effectiveProfile = standalone_networked
else:
    effectiveProfile = standalone_offline
```

如果 Manifest 同时请求宿主业务 API
和网络权限，首期直接拒绝该组合并要求开发者拆分功能或选择一种运行模式。

`effectiveProfile` 必须写入平台签名的审核证明，并绑定包摘要。

### 4.3 网络出口

``` text
MOD Web Runtime
   |
   | typed RPC: network.fetch
   v
Capability Broker
   |
   | verify install/session/profile/domain/method/path/quota
   v
Network Gateway
   |
   | separate HTTP client, no Host credentials
   v
Developer-approved HTTPS endpoint
```

Web Runtime 直接 `fetch`、XHR、WebSocket、资源加载和导航均不得作为绕过
Gateway 的替代出口。

------------------------------------------------------------------------

## 5. 首期 Host API 建议分阶段开放

建议不要一开始就开放全部宿主数据：

  ------------------------------------------------------------------------------
  阶段             API                    原因
  ---------------- ---------------------- --------------------------------------
  H0               不开放任何宿主业务 API 先完成 Runtime 和网络隔离

  H1               `host.tasks.create`    验证 Host Bridge、用户授权和撤销
                   等有限写操作           

  H2               任务、习惯、打卡只读   验证字段白名单、分页和数据最小化
                   API                    

  H3               日记、情绪等 Private   高敏感数据，需单独安全评审和专门验收
                   Vault API              
  ------------------------------------------------------------------------------

H1/H2/H3 的宿主集成 MOD 都采用离线 Profile。是否允许把 H1 与联网 Profile
混合，需要先解决 SEC-01 中的数据归属问题；本报告建议首期不混合。

------------------------------------------------------------------------

## 6. 必须通过的安全验收用例

### 6.1 宿主数据外发测试

在宿主集成离线 MOD 中尝试：

-   `fetch`、XHR、WebSocket、SSE、sendBeacon。
-   `<img>`、`<script>`、CSS、字体、iframe、表单。
-   `window.location`、`window.open`、下载、Deep Link。
-   剪贴板、系统分享、文件导出。
-   通知、Widget、后台任务。
-   MOD-to-MOD 消息。
-   错误上报、崩溃上报和遥测。
-   用户登出、切换账号、锁定 Vault、撤销权限后的旧 Session。

预期：任何 MOD 可控的外发通道都失败；旧 Session 立即失效。

### 6.2 Profile 与存储隔离测试

-   离线集成 MOD 不能访问联网 MOD 的存储。
-   联网 MOD 不能访问离线集成 MOD 的数据库、文件、缓存和 Web Storage。
-   Profile 变更创建新的 `installation_id` 和存储命名空间。
-   不允许自动迁移离线存储。
-   删除离线实例后，旧密钥销毁。
-   重新安装不继承旧宿主权限。

### 6.3 Host API 测试

-   未声明、未审核、未授权的 API 调用全部拒绝。
-   越过字段、日期范围、分页、记录数和速率限制全部拒绝。
-   Private Vault 锁定时日记读取失败。
-   登出、切换账号、撤销权限时 Session 失效。
-   MOD 无法读取 Host 数据库、AMK、OPAQUE 凭据和 JWT。

### 6.4 Package 测试

-   修改任意脚本、WASM 或资源后 Publisher 签名失败。
-   Manifest、checksums 或签名不匹配时拒绝安装。
-   Publisher Key 撤销后拒绝启动。
-   Store Attestation 与包摘要不匹配时拒绝市场安装。
-   ZIP 路径穿越、重复文件、压缩炸弹和大小写冲突均拒绝。

------------------------------------------------------------------------

## 7. 已确认的产品边界

\[产品方已确认，2026-11-09；决策编号 D-SEC-001\]

任何获得宿主业务 API 的
MOD，无论只读还是写入，都不能同时联网或使用其他外发/跨 MOD 通道。

因此，`host.tasks.create` 接收的任务标题、备注等字段，以及 Host API
返回结果，均按宿主数据处理，不得同步到开发者服务器。

V1 规则：

-   `standalone_networked`：可以同步 MOD
    自有数据，但不能调用任何宿主业务 API。
-   `host_integrated_offline`：可以申请宿主只读和有限写入
    API，但完全离线。
-   `standalone_offline`：无宿主业务 API、无外部网络能力。

同一个 MOD 同时需要宿主业务 API
与自有云同步的场景，留待未来更强隔离架构单独评审；V1
不通过权限例外放行。

------------------------------------------------------------------------

## 8. 最终评审结论

Draft 0.1 的方向正确，但以下四项在冻结安全规范前必须修改：

1.  不再保留独立的只写 Profile；所有宿主业务写入 API 均纳入
    `host_integrated_offline`。
2.  `securityProfile` 改为平台计算和签名，不由 Manifest 自我声明。
3.  所有 MOD 的外部网络访问统一经过 Network Gateway；Web Runtime
    直接网络出口必须阻断。
4.  离线集成与联网模式使用不同安装实例和存储空间，不允许自动迁移或恢复离线集成数据。

此外，必须补充 Host API
生命周期、外发通道、市场签名和跨平台安全验收。产品边界 D-SEC-001
已确认，但相关安全机制仍未实现，不能将决策确认等同于安全验收通过。

**在上述问题解决前，不应向第三方可执行 MOD
开放日记、情绪、任务、习惯或打卡等宿主数据 API。**
