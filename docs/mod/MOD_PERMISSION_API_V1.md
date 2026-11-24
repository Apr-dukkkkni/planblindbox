# PlanBlindBox MOD 权限模型与 Host API V1 规范

**文档编号：** PBB-MOD-API-001\
**版本：** Draft 0.1\
**日期：** 2026-11-09\
**状态：** 权限和 API 草案；具体数据字段与业务操作白名单待冻结

------------------------------------------------------------------------

## 0. 目标

建立一套可执行的权限系统，使 MOD 只能获得：

-   Manifest 声明的能力。
-   平台管理员审核通过的能力。
-   当前用户明确授予的能力。
-   当前 Runtime 实际支持的能力。
-   与当前安全 Profile 兼容的能力。

权限系统必须支持申请、审核、授权、查看、撤销、版本升级重新授权和审计。

## 1. 生效权限模型

``` text
P_effective =
    P_declared
  ∩ P_admin_approved
  ∩ P_user_granted
  ∩ P_runtime_supported
  ∩ P_security_profile_allowed
```

任何一项不满足，都必须拒绝调用。

管理员审批不是用户授权；用户授权也不能绕过 Runtime 安全策略。

## 2. 权限分类

### 2.1 MOD 自有资源

  -----------------------------------------------------------------------------------
  Capability                  用途                           默认
  --------------------------- ------------------------------ ------------------------
  `storage.local`             MOD 独立本地数据库/键值存储    按隔离空间和配额

  `storage.files`             MOD 独立文件空间               默认拒绝，申请后审核

  `network.fetch`             访问开发者自有云端或公开服务   默认拒绝，精确域名审核

  `host.external_link.open`   用户主动点击后打开外部网页或   默认拒绝
                              App Link                       

  `host.ui.notification`      使用宿主通知能力               默认拒绝

  `host.ui.home_widget`       未来在首页放置卡片             首期不开放

  `mods.message.send`         向其他 MOD 发送事件            首期不开放

  `mods.message.subscribe`    订阅其他 MOD 事件              首期不开放
  -----------------------------------------------------------------------------------

### 2.2 宿主只读数据

候选目录：

  Capability                      数据范围                                 敏感等级
  ------------------------------- ---------------------------------------- ----------
  `host.data.tasks.read`          任务标题、状态、目标、日期等白名单字段   高
  `host.data.habits.read`         习惯和习惯打卡字段                       高
  `host.data.checkins.read`       打卡日期、状态等                         高
  `host.data.time_records.read`   时间记录                                 高
  `host.data.diary.read`          日记文本和日期                           极高
  `host.data.mood.read`           情绪、经期和自定义情绪                   极高

以上是候选目录，不代表首期全部开放。日记、情绪和经期数据建议经过更严格的管理员审核和单独用户确认。

### 2.3 宿主有限业务操作

不提供通用 `host.database.write`。

候选操作：

  ---------------------------------------------------------------------------------------
  Capability                    操作                         返回值限制
  ----------------------------- ---------------------------- ----------------------------
  `host.tasks.create`           创建一个任务，字段白名单     只返回成功/失败和 MOD 自己的
                                                             request
                                                             ID，不返回完整宿主记录

  `host.tasks.update_limited`   修改平台明确允许的少数字段   需要额外确认是否纳入首期

  `host.habits.create`          创建一个习惯                 只返回最小操作结果

  `host.habits.check_in`        对已授权的特定习惯执行打卡   需要用户明确操作或额外授权
  ---------------------------------------------------------------------------------------

以上操作必须由平台逐个实现和审核。Manifest
声明一个操作不能自动获得同一业务域的其他操作。

## 3. 安全 Profile 与权限组合

### 3.1 `standalone_networked`

允许：

-   MOD 自己的数据库和文件。
-   经审核的 `network.fetch`。
-   MOD 自有数据同步。
-   用户主动点击的外部链接。

禁止：

-   所有 `host.data.*.read`。
-   任何能够返回已有宿主记录的 API。
-   通过 MOD 间消息间接取得宿主数据。

### 3.2 `host_integrated_local`

允许：

-   经审核并由用户授权的宿主只读数据 API。
-   受限的本地业务操作。
-   MOD 自己的本地存储（若 Runtime 能保证切换网络 Profile 前彻底清除）。

禁止：

-   `network.fetch` 和所有其他网络外发。
-   WebSocket、SSE、sendBeacon 等外发通道。
-   MOD 间通信。
-   系统分享、剪贴板写入和 MOD 文件导出。
-   外部应用跳转。
-   后台网络任务。

用户撤销宿主数据权限后，Runtime 必须结束当前 Session。若以后要切换为
`standalone_networked`，必须先清除该 MOD 的全部持久化状态。

### 3.3 `host_write_only`

只允许平台明确批准的写入型操作，不允许读取已有宿主数据。

例如 `host.tasks.create` 可以接收由 MOD UI
提供的任务字段，但返回结果不包含宿主记录内容。它是否能与网络权限同时存在，必须根据请求字段来源、返回值和具体业务操作审核。默认不推导出其他
Host API 权限。

### 3.4 禁止组合

首期强制：

``` text
host.data.*.read  + network.fetch  => DENY
host.data.*.read  + mods.message.* => DENY
host.data.*.read  + external export/share/clipboard => DENY
```

如果某平台无法在 Runtime
层证明这些通道被阻断，则不授予该平台的宿主数据读取权限。

## 4. 权限声明、审批和用户授权

### 4.1 开发者声明

每个权限声明必须包含：

-   `capability`
-   `required`
-   `reason`
-   `scope`

敏感权限还需说明：

-   使用目的。
-   读取的字段。
-   时间范围或记录范围。
-   调用频率。
-   是否会在后台使用。
-   是否可能通过网络访问（宿主数据读取时必须为否）。

### 4.2 管理员审核

管理员审核：

-   MOD 包内容和运行行为。
-   权限必要性。
-   权限 Scope 是否过宽。
-   网络域名、方法和路径。
-   Publisher 身份与签名密钥。
-   是否违反宿主数据外发规则。
-   审核策略版本。

管理员审批记录必须绑定：

-   MOD ID。
-   MOD 版本。
-   包摘要。
-   Publisher Key ID。
-   Capability 和批准 Scope。
-   审核状态。
-   审核人和时间。
-   审核策略版本。

### 4.3 用户授权

用户看到的授权说明必须用普通语言解释：

-   MOD 要访问什么数据。
-   访问目的。
-   字段和范围。
-   是否持续授权。
-   是否允许后台访问。
-   是否使用网络。
-   网络访问的域名。
-   是否需要私密仓库解锁。

用户可以逐项拒绝可选权限。必需权限被拒绝时，MOD
应明确说明哪些功能不可用，而不是悄悄降级为越权操作。

### 4.4 授权粒度

建议授权记录至少绑定：

-   user/account scope。
-   `mod_id`。
-   `installation_id`。
-   MOD 版本或权限声明摘要。
-   capability。
-   允许 Scope。
-   授权时间。
-   到期时间（若有）。
-   撤销时间。
-   用户确认的政策版本。

同一 Publisher 的其他 MOD 不得继承授权。

## 5. Host Bridge / RPC

MOD 不直接调用 Flutter 对象或 Repository。建议使用版本化 JSON-RPC over
MessageChannel。

### 5.1 请求格式示例

``` json
{
  "protocolVersion": 1,
  "requestId": "uuid",
  "method": "host.tasks.create",
  "params": {
    "title": "阅读 20 分钟",
    "note": "",
    "targetCount": 1,
    "importance": 3,
    "difficulty": 2
  }
}
```

### 5.2 响应格式示例

``` json
{
  "protocolVersion": 1,
  "requestId": "uuid",
  "ok": true,
  "result": {
    "accepted": true
  }
}
```

### 5.3 RPC 要求

-   每个方法有固定 Schema。
-   拒绝未知字段。
-   限制消息大小。
-   限制调用频率和并发。
-   每个请求绑定 Runtime Session。
-   不能由 MOD 指定任意宿主方法名。
-   错误返回稳定错误码，不泄露内部堆栈。
-   Broker 每次调用检查权限，不只在安装时检查一次。
-   撤销权限后旧 Session 和旧 Capability Token 立即失效。

建议错误码：

  错误码                          含义
  ------------------------------- -------------------------
  `MOD_PERMISSION_NOT_DECLARED`   Manifest 未声明
  `MOD_PERMISSION_NOT_APPROVED`   管理员未批准
  `MOD_PERMISSION_NOT_GRANTED`    用户未授权
  `MOD_PERMISSION_REVOKED`        权限已撤销
  `MOD_SCOPE_EXCEEDED`            请求超出批准范围
  `MOD_PROFILE_CONFLICT`          与当前安全 Profile 冲突
  `MOD_RUNTIME_UNSUPPORTED`       当前平台 Runtime 不支持
  `MOD_VAULT_LOCKED`              私密数据仓库未解锁
  `MOD_RATE_LIMITED`              调用频率超限

## 6. Host API 候选方法

以下是方法设计候选，不代表所有方法已批准。

### 6.1 任务读取

``` text
host.data.tasks.list
host.data.tasks.get
```

要求：

-   只返回字段白名单。
-   分页。
-   每次最多返回有限记录。
-   日期范围和状态范围受 Scope 限制。
-   不返回数据库主键以外的内部实现信息；优先使用不透明业务标识。
-   不能查询用户未授权的其他账号数据。

### 6.2 习惯和打卡读取

``` text
host.data.habits.list
host.data.checkins.list
```

同样要求字段白名单、分页、时间范围、最大记录数和频率限制。

### 6.3 私密日记读取

``` text
host.data.diary.list
host.data.diary.get
```

要求：

-   独立高敏感权限。
-   私密仓库必须已解锁。
-   Host 内部通过 `PrivateVaultStore` 读取和解密。
-   MOD 只得到授权范围的字段。
-   不返回 AMK、密文密钥材料或 OPAQUE 凭据。
-   当前 Session 结束时清理 Host 侧临时明文缓冲区。
-   与网络能力、外部分享和 MOD 间消息互斥。

### 6.4 写入型业务操作

``` text
host.tasks.create
```

首期优先只实现最小业务操作。输入字段必须白名单校验，返回只包含
`accepted` 和 request correlation，不返回完整宿主对象。

其他操作如
`host.tasks.update_limited`、`host.habits.check_in`，必须有独立的权限、确认体验和验收测试。

## 7. Network API

### 7.1 请求入口

``` text
mod.network.fetch
```

SDK 不把用户 JWT 交给 MOD。请求必须经过 Broker 和 Network Gateway。

### 7.2 域名 Scope

建议字段：

-   `domains`：精确域名列表，不允许任意通配符。
-   `methods`：HTTP 方法白名单。
-   `pathPrefixes`：路径前缀白名单。
-   `maxRequestsPerMinute`。
-   `maxRequestBytes`。
-   `maxResponseBytes`。
-   `timeoutMs`。

### 7.3 请求限制

-   默认 HTTPS。
-   阻止 loopback、私网、链路本地和云元数据 IP。
-   DNS 解析后检查 IP。
-   检查每次重定向的最终目标。
-   限制请求体、响应体、超时、并发和速率。
-   不自动附加宿主身份 Token。
-   不共享宿主 Cookie 或认证头。
-   域名变化必须重新审核。
-   用户撤销后立即阻断。

## 8. 安装、升级和撤销

### 8.1 首次安装

1.  校验包和签名。
2.  获取管理员审核状态。
3.  展示开发者声明的权限。
4.  用户逐项授权。
5.  创建新的 `installation_id`。
6.  创建独立 MOD 存储空间。
7.  启动 Runtime。

### 8.2 版本升级

-   新版本增加权限：重新管理员审核和用户授权。
-   新版本扩大 Scope：重新审核和用户授权。
-   权限缩小：可以保留缩小后的交集，但必须重新计算有效权限。
-   Publisher Key 变化：验证轮换链和平台登记状态。
-   包摘要变化：必须重新验证和审核。
-   不能只因 MOD ID 相同就自动信任新包。

### 8.3 卸载和重装

-   卸载时可选择删除或保留 MOD 自有数据。
-   权限授权和安装实例记录撤销。
-   保留的数据不保留权限。
-   重新安装创建新 `installation_id`，所有宿主权限重新授权。
-   从集成模式切换网络模式时先清空持久化数据。

### 8.4 撤销

撤销必须使新调用立即失败，终止相关 Runtime
Session，取消在途任务并记录审计。

## 9. 数据库模型候选

以下表名是候选，不应在检查现有实体和 Flyway 迁移后直接照抄建表。

  表                          作用
  --------------------------- ----------------------------
  `mod_publishers`            Publisher 身份
  `mod_publisher_members`     组织成员和角色
  `mod_publisher_keys`        Publisher 公钥、轮换和撤销
  `mod_artifacts`             包摘要、对象存储位置、大小
  `mod_reviews`               包审核记录
  `mod_review_capabilities`   审核批准的权限及 Scope
  `mod_store_attestations`    平台签名的审核证明
  `mod_installations`         用户安装实例
  `mod_permission_grants`     用户授权
  `mod_permission_audit`      授权、撤销和访问审计
  `mod_network_domains`       域名审核记录
  `mod_runtime_sessions`      运行 Session 元数据
  `mod_message_permissions`   后续 MOD 间通信授权

关键约束：

-   管理员审批与用户授权分表。
-   权限声明绑定版本和包摘要。
-   用户授权绑定安装实例。
-   新版本新增权限不能自动继承。
-   卸载保留数据不保留授权。
-   审计不记录日记正文、任务内容或其他敏感 Payload。

## 10. API 路由草案

### 10.1 Publisher

  Method   Endpoint                                      作用
  -------- --------------------------------------------- ----------------
  POST     `/api/v1/publisher/mods`                      创建 MOD 身份
  POST     `/api/v1/publisher/mods/{id}/versions`        上传版本和制品
  POST     `/api/v1/publisher/mods/{id}/submit-review`   提交审核
  GET      `/api/v1/publisher/mods/{id}/reviews`         查看审核结果
  POST     `/api/v1/publisher/keys`                      登记公钥
  POST     `/api/v1/publisher/keys/{keyId}/rotate`       轮换密钥

### 10.2 用户权限

  ----------------------------------------------------------------------------------------------------
  Method                  Endpoint                                             作用
  ----------------------- ---------------------------------------------------- -----------------------
  GET                     `/api/v1/me/mods/{id}/installations`                 查看安装实例

  GET                     `/api/v1/me/mods/{id}/permissions`                   查看权限和 Scope

  POST                    `/api/v1/me/mods/{id}/permission-grants`             授予权限

  DELETE                  `/api/v1/me/mods/{id}/permission-grants/{grantId}`   撤销权限
  ----------------------------------------------------------------------------------------------------

### 10.3 管理员审核

  Method   Endpoint                                       作用
  -------- ---------------------------------------------- ------------
  GET      `/api/v1/admin/mods/reviews`                   待审核列表
  GET      `/api/v1/admin/mods/{id}/reviews/{reviewId}`   审核详情
  POST     `/api/v1/admin/mods/{id}/reviews`              批准或拒绝
  POST     `/api/v1/admin/mods/{id}/domains/review`       域名审核
  POST     `/api/v1/admin/mods/{id}/revoke`               紧急撤销

管理员 API 应采用有角色、审计和可轮换凭据的认证机制，不继续把单一全局
`MOD_ADMIN_TOKEN` 作为完整开发者平台的长期管理体系。

## 11. 审计原则

记录：

-   MOD ID、Publisher ID、版本、包摘要。
-   Installation ID、Session ID。
-   Capability、Scope。
-   调用时间、结果、拒绝原因。
-   管理员审核、用户授权和撤销操作。
-   网络目标域名、方法、状态码、流量大小（不记录请求正文）。

不得记录：

-   日记正文。
-   情绪文本。
-   任务备注等宿主数据正文。
-   AMK、OPAQUE 凭据、JWT。
-   MOD 自有业务数据正文（除非独立的用户故障诊断流程另有授权）。

## 12. 待确认事项

1.  首期宿主只读 API 具体字段和记录范围。
2.  首期写入 API 是否只实现 `host.tasks.create`。
3.  `host.tasks.create` 是否允许与网络权限共存。
4.  日记读取是否纳入首期，还是待 Web Runtime 安全验证后开放。
5.  权限是否支持一次性、持续和每次确认三种授权时长。
6.  后台访问和通知权限的策略。
7.  MOD 间通信的消息 Schema、消息保留和授权关系。
8.  权限审计保留周期。
9.  组织 Publisher 的成员角色和双人审批规则。

------------------------------------------------------------------------

**Host API 是稳定的业务能力契约，不是宿主数据库的远程代理。**
