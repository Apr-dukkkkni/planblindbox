# PlanBlindBox MOD 平台安全架构规范

**文档编号：** PBB-MOD-SEC-001\
**版本：** Draft 0.1\
**日期：** 2026-11-09\
**状态：** 安全设计草案；宿主数据与网络能力互斥规则需要重点评审

------------------------------------------------------------------------

## 0. 安全目标

MOD 平台必须同时满足：

1.  第三方 MOD 可以自由实现自己的业务逻辑。
2.  MOD 自有数据可以本地保存，也可以同步到开发者自己的云端。
3.  MOD 不能读取未授权的宿主数据。
4.  MOD 不能把宿主数据或其衍生结果外发。
5.  MOD 不能通过另一个
    MOD、剪贴板、外部跳转、文件导出等通道绕过数据边界。
6.  MOD 不能获取宿主数据库、JWT、OPAQUE 凭据、AMK 或其他密钥。
7.  用户撤销权限后，新的调用必须立即被拒绝，正在运行的相关 Session
    必须终止或降级。
8.  管理员审核、Publisher 签名和用户授权分别承担不同责任，不得相互替代。

## 1. 数据分类与来源标记

### 1.1 数据类别

  -----------------------------------------------------------------------------------------------------------------
  标签                    定义                                           外发规则
  ----------------------- ---------------------------------------------- ------------------------------------------
  `PUBLIC`                公开网络内容、公开资源                         按网络权限和域名策略

  `MOD_OWNED`             MOD 自己创建、用户在 MOD 内输入或 MOD          可按用户授权同步到开发者云端
                          自身业务产生的数据                             

  `HOST_ACTIVITY`         PlanBlindBox                                   禁止通过 MOD 外发
                          任务、习惯、打卡、时间记录、奖励等             

  `HOST_PRIVATE`          日记、情绪、经期等私密数据                     禁止通过 MOD 外发

  `HOST_DERIVED`          根据宿主数据产生的摘要、统计、分类、预测、AI   禁止通过 MOD 外发
                          分析结果                                       

  `MIXED_HOST_DERIVED`    同时使用 MOD 数据和宿主数据生成的结果          只要宿主数据对结果有贡献，按宿主数据处理
  -----------------------------------------------------------------------------------------------------------------

### 1.2 来源规则

-   宿主 API 返回的数据属于宿主数据。
-   对宿主数据进行格式转换、摘要、聚合、Embedding、分类、翻译或 AI
    分析，不改变其所有权。
-   MOD 不能把宿主数据复制进自己的数据库后就将其重新标记为 `MOD_OWNED`。
-   用户通过 PlanBlindBox
    自己的导出功能主动导出数据，是用户主动行为；MOD
    不得调用宿主导出接口。
-   MOD 自己创建的游戏进度、Anki 卡片、健身记录等属于 MOD
    自有数据，可同步。
-   若用户在 MOD 内输入内容并通过写入型 Host API
    创建宿主记录，写入请求本身可被视为 MOD 来源输入；Host API
    不得返回多余宿主记录内容。具体写操作能否与网络权限共存，必须逐项审核。

## 2. 核心安全不变量

### 2.1 宿主数据不得进入外发通道

安全目标：

``` text
HOST_ACTIVITY
HOST_PRIVATE
HOST_DERIVED
MIXED_HOST_DERIVED
        |
        X
        |
Network / MOD Message / Clipboard / Share / Export / External Link
```

### 2.2 权限声明不是安全边界

以下权限分开声明，并不能自动阻止外发：

-   `host.data.diary.read`
-   `network.fetch`

恶意 MOD 可以在读取日记后，将明文放入 HTTP 请求。因此必须由 Runtime 和
Broker 执行互斥策略，而不是只在安装界面显示两个独立复选框。

### 2.3 第一版建议的安全配置

\[架构建议，需产品评审\]

  -------------------------------------------------------------------------------------------------------------------------------------------------
  Profile                             宿主数据读取                               MOD 本地持久化             网络外发   MOD 间通信   外部分享/剪贴板
  ------------------------- ---------------------- -------------------------------------------- -------------------- ------------ -----------------
  `standalone_networked`                      禁止                                         允许         经审核后允许     首期关闭    按独立权限控制

  `host_integrated_local`           用户授权后允许   可本地保存，但切换到网络模式前必须整体清除                 禁止         禁止              禁止

  `host_write_only`           禁止读取已有宿主数据                                         允许 是否允许按具体写 API     首期关闭    按独立权限控制
                                                                                                                审核              

  `declarative`                   仅执行声明式能力                                   由宿主管理   不执行任意网络代码       不适用            不适用
  -------------------------------------------------------------------------------------------------------------------------------------------------

**强制规则：任何具有 `host.data.*.read` 有效权限的可执行
Runtime，不得同时拥有有效网络外发能力。**

`host_integrated_local` 下如果允许持久化 MOD 存储，则在切换为
`standalone_networked` 或授予网络能力之前，必须清除该 MOD
的全部持久化状态，包括数据库、文件、缓存、LocalStorage、IndexedDB、Cache
Storage、Service Worker
和可恢复会话。若某个平台无法可靠完成清理，则该平台的集成模式不得启用持久化存储。

### 2.4 为什么不能只靠数据标签

任意 JavaScript 取得宿主明文后，可以：

-   复制到普通对象。
-   拼接字符串。
-   压缩或编码。
-   写入 MOD 本地数据库。
-   延迟到以后再发送。

因此，仅在 SDK 对象上附加 `HOST_DATA`
标签，无法对任意第三方代码提供可靠的端到端污点追踪。

第一版必须通过安全配置互斥和通道隔离实现边界。未来若要同时支持宿主数据读取与
MOD 云端同步，必须有新的、可验证的隔离架构；不能仅放宽权限组合。

## 3. 威胁模型

### 3.1 需要防御的主体

-   恶意或疏忽的 MOD 开发者。
-   Publisher 私钥泄露或被盗用。
-   被篡改的 MOD ZIP。
-   恶意依赖 MOD。
-   通过 MOD-to-MOD 消息绕过权限的 MOD。
-   利用 WebView、iframe、脚本、导航或网络请求绕过代理的代码。
-   恶意或错误配置的第三方服务端。
-   资源消耗型 MOD。
-   被下架或撤销信任的旧版本。

### 3.2 主要资产

-   用户日记、情绪和经期数据。
-   任务、习惯、打卡、时间记录和奖励数据。
-   AMK、OPAQUE export key、JWT 和设备安全存储。
-   Host 数据库与私密仓库。
-   MOD 自有数据。
-   Publisher 身份和签名密钥。
-   市场审核证明和安装包。
-   用户授权记录。

### 3.3 信任边界

``` text
[PlanBlindBox Host]
  - Account / Auth
  - Core Domain Services
  - Private Vault
  - Local SQLite
        |
        | Host API only
        v
[Capability Broker]
        |
        | scoped RPC
        v
[Untrusted MOD Runtime]
        |
        +--> MOD-owned storage
        |
        +--> Network Gateway (standalone profile only)
```

MOD Runtime 始终视为不可信。通过官方市场发布、Publisher
签名或人工审核，不会改变这一信任假设。

## 4. Runtime 隔离

### 4.1 Content Runtime

-   不执行第三方任意程序代码。
-   只解析平台定义的 JSON Schema / DSL。
-   限制内容数量、字符串长度、嵌套深度、资源大小和计算复杂度。
-   奖励规则使用受限 DSL，不允许 `eval`、任意脚本或任意函数调用。
-   链接入口只能触发受限的用户点击跳转。

### 4.2 Web Runtime

必须验证：

-   MOD 与宿主使用不同 Origin。
-   不共享 Cookie、DOM、LocalStorage、IndexedDB 或 Service Worker。
-   不允许访问宿主任意文件路径。
-   JS Bridge 只暴露明确的 RPC 方法。
-   每个 RPC 请求验证来源、Session、请求 ID、方法名、参数
    Schema、超时和调用频率。
-   不允许通过导航跳转逃逸到宿主或其他 MOD Origin。
-   不允许未授权下载、文件选择、剪贴板、系统分享或任意 Intent。
-   资源和脚本加载遵循宿主生成的 CSP。
-   不允许 MOD 自行放宽宿主设置的 CSP。

建议从严格 CSP 起步，例如：

``` text
default-src 'none';
script-src 'self';
style-src 'self';
img-src 'self' data:;
font-src 'self';
connect-src 'none';
form-action 'none';
frame-src 'none';
object-src 'none';
base-uri 'none';
worker-src 'none';
```

实际策略必须根据资源需求逐项放开。`standalone_networked`
的网络请求应通过受控 Network Gateway；不得让 MOD 直接绕过 Broker
发起请求。

必须验证的网络通道至少包括：

-   `fetch`
-   XMLHttpRequest
-   WebSocket
-   EventSource / SSE
-   `sendBeacon`
-   `<img>`、`<script>`、`<link>`、CSS `url()`
-   表单提交
-   iframe / frame
-   Worker / Service Worker
-   重定向
-   下载
-   `window.open`
-   外部导航和 Deep Link

如果某平台无法证明 `host_integrated_local`
的所有外发通道均被阻断，则该平台不得向 Web Runtime
授予宿主数据读取权限。

### 4.3 WASM Runtime（后续）

-   只使用受限 WASM Runtime。
-   不默认提供 WASI 网络、任意文件系统和进程能力。
-   宿主能力通过明确导入的函数接口提供。
-   限制内存、燃料/指令预算、执行时间和并发。
-   WASM 不能因为编译语言不同而绕过 Capability Broker。

### 4.4 Web 平台与桌面平台

Flutter Web 的 MOD iframe 必须使用独立 Origin 和 sandbox。仅使用
`iframe sandbox` 属性不能单独证明安全。

Windows 等桌面平台需单独评估 WebView2 或其他 Runtime
的隔离能力。未通过安全验证的平台，不开放宿主私密数据读取权限。

## 5. Private Vault 安全边界

当前源码确认：

-   AMK 是客户端生成的 32 字节随机密钥。
-   `AccountMasterKeyEnvelope` 使用 OPAQUE export key 经 HKDF-SHA256
    派生包装密钥，再用 AES-256-GCM 包装 AMK。
-   `PrivateSyncVault` 在内存中持有 AMK，并可从设备安全存储恢复。
-   日记和自定义情绪记录以 AES-256-GCM 信封保存在
    `private_vault_records`。
-   `PrivateVaultStore` 负责解密和写入私密记录。
-   私密同步服务端校验密文信封，不需要获取日记明文。

MOD 安全规则：

1.  MOD 不得获取 AMK。
2.  MOD 不得获取 OPAQUE export key。
3.  MOD 不得获取用户 JWT 或其他认证 Token。
4.  MOD 不得直接访问 `PrivateVaultStore`、`PrivateSyncVault`
    或数据库句柄。
5.  日记读取必须由 Host API 代为解密，并且仅返回用户授权的字段和范围。
6.  只有私密仓库已解锁时，Host 才能提供日记/情绪数据；锁定时拒绝。
7.  日记、情绪和经期读取属于高敏感权限，建议每次启动集成 Session
    时再次展示清晰提示。
8.  Host API 不得把明文写入 MOD 日志、崩溃报告或审计记录。

## 6. Host API 安全

### 6.1 不允许的接口

-   任意 SQL。
-   数据库连接或 ORM 对象。
-   任意表/列读取。
-   任意文件系统访问。
-   返回认证 Token。
-   返回 AMK 或密钥。
-   任意对象反射或动态方法调用。
-   无限制批量导出。

### 6.2 必须具备的控制

-   字段白名单。
-   记录范围。
-   分页和每次最大记录数。
-   频率限制。
-   Session 绑定。
-   用户授权状态实时检查。
-   输入和输出 Schema 校验。
-   敏感字段最小化。
-   审计只记录元数据，不记录数据正文。

## 7. 网络安全

### 7.1 MOD 自有数据同步

允许 `standalone_networked` MOD 使用开发者自己的服务端和数据库，但必须：

-   在 Manifest 声明精确域名、方法和路径范围。
-   通过 Network Gateway 或等价的强制控制层。
-   默认 HTTPS。
-   拒绝本机、内网、云元数据地址。
-   校验 DNS 解析和最终 IP，防止 DNS Rebinding。
-   校验重定向后的最终目标。
-   限制请求体、响应体、超时、并发和速率。
-   不自动附加 PlanBlindBox 用户 Token。
-   不共享宿主 Cookie、客户端证书或认证头。
-   用户撤销网络权限后立即阻断后续请求。

### 7.2 宿主数据禁止外发

具有宿主数据读取权限时，以下能力全部默认禁止：

-   `network.fetch`
-   WebSocket / SSE 等长连接
-   MOD 间消息发送或订阅
-   系统分享
-   剪贴板写入
-   MOD 文件导出
-   外部应用跳转（除非能证明不带任何宿主数据且经过单独评审；首期建议全部关闭）
-   后台网络任务

### 7.3 不能承诺的事项

平台无法阻止用户自己截图、拍照、手工抄录或主动通过 PlanBlindBox
自身导出功能使用数据。安全承诺应限定为：平台禁止 MOD
通过其受控运行环境和 API
将宿主数据外发，不宣称可以阻止用户本人主动复制屏幕可见内容。

## 8. ZIP、签名和供应链安全

安装器必须防止：

-   `../` 路径穿越。
-   绝对路径、盘符路径和 NUL 字符。
-   ZIP 炸弹和极端压缩比。
-   符号链接逃逸。
-   重复文件覆盖。
-   大小写折叠后的路径冲突。
-   未规范化的 Unicode 路径。
-   Manifest 声明与实际文件不一致。
-   校验后、加载前包内容被替换。

签名体系建议：

-   Publisher 使用 Ed25519 私钥签署包摘要。
-   平台使用独立的审核签名密钥签署 Store Attestation。
-   密钥有 key ID、有效期、轮换和撤销状态。
-   平台私钥放入受控 KMS/HSM 或等价安全设施。
-   不自创签名算法、密钥交换或加密协议。
-   Manifest 与 checksums 的规范化和签名字节必须在 Package
    规范中精确冻结。

## 9. 权限撤销和事件响应

撤销后必须：

1.  将授权记录标记为 `REVOKED`。
2.  使相关 Capability Session 立即失效。
3.  拒绝新请求。
4.  取消可取消的在途请求。
5.  停止依赖该权限的 Runtime Session。
6.  清理临时解密数据和临时缓冲区。
7.  记录撤销原因、操作者和时间。
8.  如属于恶意版本，撤销对应 Store Attestation，并可阻止该包启动。

撤销不能追回已经被 MOD
读取或复制到其本地存储中的数据；这也是集成模式切换到网络模式前必须清理存储的原因。

## 10. 安全测试与验收

### 10.1 Host Data Egress 测试

在 `host_integrated_local` 中分别尝试：

-   `fetch`、XHR、WebSocket、SSE、sendBeacon。
-   图片、脚本、CSS、字体等资源请求。
-   表单提交、iframe、Worker、Service Worker。
-   外部导航、下载、Deep Link、系统分享。
-   剪贴板。
-   MOD Event Broker。
-   关闭后重启、卸载保留数据、重新安装、切换网络 Profile 后延迟外发。

预期：所有外发路径均被阻断；切换到网络 Profile 前存储清理可验证。

### 10.2 Host API 测试

-   未声明权限调用失败。
-   未经管理员审批调用失败。
-   未经用户授权调用失败。
-   Scope 超限调用失败。
-   版本升级新增权限必须重新审核和授权。
-   撤销后旧 Session 不能继续调用。
-   Private Vault 锁定时拒绝日记读取。
-   MOD 无法取得 AMK、JWT、OPAQUE 凭据或数据库对象。

### 10.3 Package 测试

-   篡改任意文件后拒绝安装。
-   替换 checksums 后签名失败。
-   替换 Manifest 后签名失败。
-   Publisher Key 撤销后拒绝启动。
-   Store Attestation 不匹配包摘要时拒绝市场安装。
-   ZIP 路径穿越和解压炸弹样本被拒绝。

------------------------------------------------------------------------

**安全底线：如果某个平台无法证明宿主数据不会通过 MOD
可控通道外发，就不要在该平台向第三方可执行代码开放宿主数据读取权限。**
