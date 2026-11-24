# PlanBlindBox MOD Manifest 与 Package V1 规范

**文档编号：** PBB-MOD-PKG-001\
**版本：** Draft 0.1\
**日期：** 2026-11-09\
**状态：** 格式草案；正式冻结前需完成 Schema、签名和跨语言测试

------------------------------------------------------------------------

## 0. 目标

定义一个可验证、可分发、可升级的 MOD 安装包格式，覆盖：

-   Manifest 身份与运行描述。
-   Runtime 和平台兼容性。
-   UI 展示模式。
-   本地存储和权限声明。
-   依赖关系。
-   ZIP 目录规范。
-   文件完整性校验。
-   Publisher 签名。
-   平台审核证明。

Manifest 只描述 MOD，不承载全部业务内容，也不重复保存文件哈希。

## 1. 版本和兼容性

### 1.1 Manifest 版本

使用整数 `manifestVersion: 1`
表示规范主版本。未来出现不兼容结构变化时升级为 2。

### 1.2 MOD 版本

使用 SemVer 2.0.0。建议首期允许完整 `major.minor.patch`，可支持预发布和
build metadata；具体版本比较必须使用标准 SemVer 规则，不得按字符串排序。

### 1.3 Host API 兼容性

`compatibility.hostApi` 使用 SemVer range。平台只允许 MOD
调用其声明并且宿主实际支持的 API。

### 1.4 旧版兼容

\[已确认\] 不提供旧版 `schemaVersion: 1` 的长期兼容层。旧版测试 MOD
可以清理或重新打包为新规范。

## 2. Manifest 结构

建议字段：

  字段                         必填 用途
  ---------------------- ---------- ------------------------------
  `manifestVersion`              是 Manifest 规范版本
  `id`                           是 全局 MOD ID，反向域名格式
  `version`                      是 MOD SemVer
  `name`                         是 多语言名称
  `description`                  否 简介
  `publisher.id`                 是 Publisher 身份
  `type`                         是 `content` 或 `app`
  `contentKind`            条件必填 声明式内容子类型
  `runtime.type`                 是 `declarative`、`web`、`wasm`
  `runtime.apiVersion`           是 Runtime API 版本
  `runtime.entrypoint`           是 包内入口文件
  `securityProfile`              是 独立或宿主集成安全配置
  `compatibility`                是 Host API 与平台范围
  `ui`                           是 允许的窗口展示模式
  `storage`                      是 本地存储需求和配额
  `permissions`                  是 能力声明
  `dependencies`                 否 依赖及版本范围
  `assets.icon`                  否 包内图标路径

### 2.1 产品类型建议

-   `content`：由宿主解析，不执行任意第三方代码。
-   `app`：可执行独立应用。

`contentKind` 候选：

-   `task_template`
-   `theme`
-   `shop_resource_pack`
-   `reward_rules`
-   `link_hub`

`link_hub` 是声明式快捷入口集合，目标为 HTTPS 或经过验证的 App Link /
Deep Link。

### 2.2 Runtime 类型

-   `declarative`：平台定义的 JSON/DSL。
-   `web`：HTML/CSS/JavaScript。
-   `wasm`：后续扩展，必须使用受限 WASM Host。

Content 类型必须使用 `declarative` Runtime。App 可选择平台已支持的可执行
Runtime。

### 2.3 UI 展示模式

-   `full_screen`
-   `modal`
-   `overlay`

`overlay` 仅为 PlanBlindBox 内部覆盖层。Host
可以限制尺寸、数量、生命周期和层级。

### 2.4 安全配置

-   `standalone_networked`：可申请 MOD
    自有本地存储和网络访问；不得读取宿主数据。
-   `host_integrated_local`：可申请宿主数据访问；网络和其他外发通道由安全策略禁止。若保留持久化
    MOD 数据，切换网络 Profile 前必须整体清除。
-   `host_write_only`：仅使用明确的写入型 Host
    API，不读取已有宿主数据；网络能否同时启用按操作 API 逐项审核。

## 3. 权限声明

权限使用对象，不再使用旧版字符串数组：

``` json
{
  "capability": "network.fetch",
  "required": false,
  "reason": "同步农场 MOD 自己的游戏进度",
  "scope": {
    "domains": ["api.farm.example"],
    "methods": ["GET", "POST"],
    "pathPrefixes": ["/v1/"],
    "maxRequestsPerMinute": 30,
    "maxResponseBytes": 1048576
  }
}
```

建议的 capability 命名空间：

  命名空间            示例
  ------------------- ----------------------------------------------------
  `storage.*`         `storage.local`、`storage.files`
  `network.*`         `network.fetch`
  `host.data.*`       `host.data.tasks.read`、`host.data.diary.read`
  `host.tasks.*`      `host.tasks.create`
  `host.ui.*`         `host.ui.notification`、未来 `host.ui.home_widget`
  `host.external.*`   `host.external_link.open`
  `mods.message.*`    后续 MOD 间通信

权限目录由平台定义。开发者不得自行发明一个 capability
并期待宿主自动授予。

### 3.1 关键组合约束

Manifest Schema 负责结构校验；平台语义校验还必须执行：

-   声明任何 `host.data.*.read` 时，不得同时生效 `network.fetch`。
-   宿主数据读取 Profile 禁止 MOD 间消息、外部分享、剪贴板写入和 MOD
    文件导出。
-   `host_integrated_local` 切换为网络 Profile 前，必须清空所有持久化
    MOD 状态。
-   `host.tasks.create`
    等写入型能力只能执行平台定义的有限业务操作，不能推导出任意数据库写权限。
-   Host API 不得返回超出操作所需的宿主记录信息。

## 4. Package ZIP 目录规范

建议结构：

``` text
<mod-id>-<version>.mod.zip
│
├── manifest.json
├── checksums.json
├── signatures.json
│
├── content/
│   ├── task-templates.json
│   ├── theme.json
│   ├── reward-rules.json
│   └── link-hub.json
│
├── web/
│   ├── index.html
│   ├── app.js
│   └── styles.css
│
├── wasm/
│   └── module.wasm
│
├── assets/
│   ├── icons/
│   ├── images/
│   └── sounds/
│
└── locales/
    ├── zh-CN.json
    └── en-US.json
```

以上目录按 Runtime/内容类型选择，不要求每个 MOD 都包含全部目录。

### 4.1 路径规则

-   使用相对 POSIX 路径 `/`。
-   禁止绝对路径、盘符路径、`..`、NUL、反斜杠路径和符号链接。
-   禁止大小写折叠后冲突的路径。
-   建议路径使用 Unicode NFC 规范化。
-   不允许 ZIP 中重复路径覆盖。
-   解压前先完整扫描并验证，不得边解压边信任。
-   资源路径必须位于包根目录内部。

### 4.2 包大小限制

\[待确认\] 建议初始上限：

  项目                       建议上限
  ------------------ ----------------
  Manifest                     64 KiB
  文件数量                     10,000
  单文件解压后大小             20 MiB
  总解压后大小                100 MiB
  压缩比                        100:1
  文件名长度           240 UTF-8 字节

平台应根据实际资源类型、移动设备内存和 CDN 成本调整。不能只依赖 ZIP
文件的压缩大小。

## 5. checksums.json

职责：列出安装包中所有需要验证的内容文件的大小和 SHA-256。

示例：

``` json
{
  "formatVersion": 1,
  "algorithm": "SHA-256",
  "files": [
    {
      "path": "manifest.json",
      "size": 1234,
      "sha256": "64位小写十六进制摘要"
    },
    {
      "path": "web/index.html",
      "size": 2048,
      "sha256": "64位小写十六进制摘要"
    },
    {
      "path": "web/app.js",
      "size": 8192,
      "sha256": "64位小写十六进制摘要"
    }
  ]
}
```

规则：

1.  `files` 必须覆盖所有需要安装和运行的内容文件。
2.  不包含 `checksums.json` 和 `signatures.json` 自身，避免循环依赖。
3.  文件路径排序规则必须固定；建议按 UTF-8 路径字节升序。
4.  每个文件都要重新计算大小和 SHA-256。
5.  缺失文件、多余文件、重复路径、大小不符或摘要不符均拒绝安装。
6.  SHA-256 只证明文件与清单一致，不证明 Publisher 身份。

## 6. 签名与审核证明

### 6.1 建议算法

-   文件摘要：SHA-256。
-   Publisher 签名：Ed25519。
-   平台审核证明：独立 Ed25519 平台签名。
-   JSON 规范化：RFC 8785 JCS。

这些是建议的标准化组合，最终需以 Dart、Java、CLI
三端一致性测试冻结。不得自创密码学算法。

### 6.2 签名覆盖内容

定义：

-   `manifestBytes`：`manifest.json` 的原始 UTF-8 字节。
-   `checksumsBytes`：`checksums.json` 的原始 UTF-8 字节。
-   `manifestSha256`：Manifest 原始字节的 SHA-256。
-   `checksumsSha256`：checksums 原始字节的 SHA-256。

建议 `checksums.json` 自身使用 JCS 规范化后写入包；Manifest 也使用 JCS
规范化后写入包。安装时拒绝非规范化 JSON，以减少多端签名歧义。

Publisher 签名消息采用固定域分隔格式：

``` text
PBB-MOD-PUBLISHER-V1
<mod-id>
<version>
<manifest-sha256>
<checksums-sha256>
```

编码为 UTF-8 后使用 Publisher 私钥签名。

平台审核证明应签署：

``` text
PBB-MOD-STORE-ATTESTATION-V1
<mod-id>
<version>
<manifest-sha256>
<checksums-sha256>
<publisher-key-id>
<review-status>
<policy-version>
<reviewed-at>
```

所有字段顺序、换行、编码和时间格式必须由正式规范固定；不得由各端自行拼接。

### 6.3 signatures.json 示例

``` json
{
  "formatVersion": 1,
  "publisherSignature": {
    "algorithm": "Ed25519",
    "keyId": "publisher-key-001",
    "signature": "base64签名"
  },
  "storeAttestation": {
    "algorithm": "Ed25519",
    "keyId": "planblindbox-store-key-001",
    "reviewStatus": "APPROVED",
    "policyVersion": "1",
    "reviewedAt": "2026-11-09T00:00:00Z",
    "signature": "base64签名"
  }
}
```

`signatures.json` 不纳入 checksums，也不签署自身。签名覆盖的是 Manifest
和 checksums 的摘要。

### 6.4 信任规则

  -----------------------------------------------------------------------------------
  来源                    验证要求                 安装策略
  ----------------------- ------------------------ ----------------------------------
  官方市场                Publisher 签名 + Store   按审核结果和用户授权
                          Attestation + 文件摘要   

  ZIP 导入                文件摘要、Publisher      无平台证明时标记未审核并限制能力
                          签名（若存在）           

  开发者调试              开发密钥或临时未签名包   仅开发环境和测试账号能力
  -----------------------------------------------------------------------------------

开发者调试模式不得成为正式用户设备上绕过安全策略的通道。

## 7. Manifest 示例

### 7.1 独立联网农场 MOD

``` json
{
  "manifestVersion": 1,
  "id": "com.example.farm",
  "version": "1.0.0",
  "name": {
    "zh-CN": "我的农场",
    "en-US": "My Farm"
  },
  "description": "独立运行的农场养成应用",
  "publisher": {
    "id": "publisher.example"
  },
  "type": "app",
  "runtime": {
    "type": "web",
    "apiVersion": "1",
    "entrypoint": "web/index.html"
  },
  "securityProfile": "standalone_networked",
  "compatibility": {
    "hostApi": "^1.0.0",
    "platforms": ["android", "web"]
  },
  "ui": {
    "allowedModes": ["full_screen", "modal"],
    "defaultMode": "full_screen"
  },
  "storage": {
    "local": {
      "enabled": true,
      "quotaMiB": 50,
      "persistent": true
    }
  },
  "permissions": [
    {
      "capability": "storage.local",
      "required": true,
      "reason": "保存农场游戏进度"
    },
    {
      "capability": "network.fetch",
      "required": false,
      "reason": "同步 MOD 自己的游戏进度",
      "scope": {
        "domains": ["api.farm.example"],
        "methods": ["GET", "POST"],
        "pathPrefixes": ["/v1/"],
        "maxRequestsPerMinute": 30,
        "maxResponseBytes": 1048576
      }
    }
  ],
  "dependencies": [],
  "assets": {
    "icon": "assets/icons/app.png"
  }
}
```

### 7.2 宿主数据集成型 MOD（本地模式）

``` json
{
  "manifestVersion": 1,
  "id": "com.example.diary-insight",
  "version": "1.0.0",
  "name": {
    "zh-CN": "本地日记分析"
  },
  "description": "仅在设备本地分析经用户授权的日记",
  "publisher": {
    "id": "publisher.example"
  },
  "type": "app",
  "runtime": {
    "type": "web",
    "apiVersion": "1",
    "entrypoint": "web/index.html"
  },
  "securityProfile": "host_integrated_local",
  "compatibility": {
    "hostApi": "^1.0.0",
    "platforms": ["android"]
  },
  "ui": {
    "allowedModes": ["full_screen"],
    "defaultMode": "full_screen"
  },
  "storage": {
    "local": {
      "enabled": true,
      "quotaMiB": 10,
      "persistent": true
    }
  },
  "permissions": [
    {
      "capability": "host.data.diary.read",
      "required": false,
      "reason": "在本机分析用户主动授权的日记内容",
      "scope": {
        "fields": ["date", "content", "mood"],
        "maxRecordsPerRequest": 30
      }
    }
  ],
  "dependencies": [],
  "assets": {
    "icon": "assets/icons/app.png"
  }
}
```

注意：这个示例没有网络权限。若用户以后要切换到联网 Profile，必须先清除该
MOD 的所有持久化状态。具体的日记字段、范围和 Runtime 平台支持仍需审核。

## 8. 校验顺序

安装前必须按顺序执行：

1.  ZIP 结构检查。
2.  路径安全检查。
3.  文件数量、大小和压缩比检查。
4.  Manifest JSON 严格解析（拒绝重复键和尾随内容）。
5.  JSON Schema 校验。
6.  跨字段语义校验。
7.  Runtime / 平台兼容性检查。
8.  checksums 完整性检查。
9.  Publisher 签名验证。
10. Store Attestation 验证（市场包必须）。
11. 依赖和版本冲突检查。
12. 管理员审批状态检查。
13. 用户授权。
14. 安全解压到隔离目录。
15. 安装记录提交。

校验完成后到实际加载前，必须保证加载的是同一份已验证制品；不能让包内容在校验后被替换。

## 9. 开发者 CLI

建议命令：

``` bash
pbb mod create farm
pbb mod configure
pbb mod permissions
pbb mod validate
pbb mod build
pbb mod sign
pbb mod publish
pbb mod test
```

CLI 负责：

-   生成模板项目。
-   生成 Manifest。
-   检查权限组合。
-   校验 JSON Schema。
-   计算 checksums。
-   规范化 JSON。
-   生成签名。
-   构建 ZIP。
-   本地启动调试 Runtime。
-   模拟用户授权和权限撤销。
-   上传市场并查看审核状态。

第三方开发者不需要下载 PlanBlindBox 全部源码才能开发 MOD。

## 10. 待确认事项

1.  `manifestVersion` 是否采用整数版本。
2.  `contentKind` 的最终枚举。
3.  `securityProfile` 是否采用本文三个候选值。
4.  SemVer 是否允许预发布版本。
5.  包大小和资源限制。
6.  签名是否正式采用 Ed25519 + RFC 8785 JCS。
7.  Publisher Key 的生成、托管、备份和轮换方式。
8.  ZIP 导入的信任等级与默认限制。
9.  首期支持哪些 Runtime 和平台。
10. 是否允许宿主集成 Profile 持久化本地 MOD 数据。

------------------------------------------------------------------------

**本规范要求 Manifest、checksums 和 signatures 的职责分离。Manifest 描述
MOD，checksums 描述内容完整性，signatures
描述签署者身份和平台审核证明。**
