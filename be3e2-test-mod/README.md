# PlanBlindBox — BE-3E-2 Manifest V1 联调测试包

仅供本地开发环境使用，不修改任何 Spring Boot / Flutter 生产源码。

## 文件

- `task-template-v1.zip`：Flutter V1 安装器可导入的 ZIP。**不要把最外层交付包当成 MOD ZIP 导入。**
- `task-template-v1/manifest.json`：用于发布到 `mod-server` 的**精确原始字节**。
- `task-template-v1/content/task-templates.json`：任务模板数据。
- `task-template-v1/integrity.json`：Manifest 与内容字节 SHA-256 清单。
- `PublisherSigner.java`：JDK 17+ 单文件工具；在你的电脑上生成 Publisher Ed25519 密钥并签名。
- `publish-test-mod.ps1`：登记 Publisher 公钥、发布 Manifest；带 `-ApproveCapability` 时由管理员批准测试权限。
- `probe-user-proof.ps1`：可选；通过真实用户 JWT 测试授权、签发、在线验证以及撤权后旧 JWS 失效。

## 测试身份

- `modId`: `com.planblindbox.test.task`
- `version`: `1.0.0`
- `publisherId`: `com.planblindbox.testpublisher`
- `capability`: `host.tasks.create`
- `manifestSha256`: `91c8a58d0f9b8ab4d2d13c481ec0ce113d5cda6a03865317af0a0f43b01b7d2c`

## 第 1 步：管理员登记公钥 + 发布 + 审批

确保 `mod-server` 已启动，且服务器进程已经配置 `MOD_ADMIN_TOKEN`。平台 JWS 签名密钥也要处于 ACTIVE 状态。

将**整个交付包**解压到 `E:\CODE\code\PlanBlindBox\`，得到：

```text
E:\CODE\code\PlanBlindBox\be3e2-test-mod\
  README.md
  PublisherSigner.java
  publish-test-mod.ps1
  probe-user-proof.ps1
  task-template-v1.zip
  task-template-v1\manifest.json
  task-template-v1\integrity.json
  task-template-v1\content\task-templates.json
```

PowerShell：

```powershell
cd E:\CODE\code\PlanBlindBox\be3e2-test-mod
.\publish-test-mod.ps1 -ApproveCapability
```

会提示输入本地后端使用的 `MOD_ADMIN_TOKEN`；输入过程不回显，不会写入文件。脚本先在你的用户主目录下创建 **`%USERPROFILE%\.planblindbox-be3e2-publisher`**，写入 `publisher-private.pkcs8` 和 `publisher-public.x509`。**私钥永远不会放进交付包或上传给后端。**

脚本完成：公钥登记 → 原始 Manifest Ed25519 签名 → 发布 `/api/v1/admin/mods/publish` → 管理员批准 `host.tasks.create`。如果同版本已经发布，只在摘要和 Publisher Key ID 均相同时允许继续；不会覆盖不同版本内容。

`-ApproveCapability` 每次执行都会更新审批授权版本号，可能导致此前的旧 JWS 失效；**完成初次发布后不要无故重复执行此命令。**

**预期：** `Published ...`、`Admin approval: True`、`Package enabled: True`。`userGranted` 此时仍应为 false 或不存在，因为用户授权必须独立完成。

## 第 2 步：验证真实用户授权 + JWS

有真实登录用户 JWT 后，使用：

```powershell
.\probe-user-proof.ps1 -GrantCapability
```

输入 JWT 时不会回显。脚本以该用户身份：授予权限 → 查看 effective → 签发 JWS → 服务端在线校验，预期：

```text
adminApproved=True; userGranted=True; packageEnabled=True; effective=True
JWS issued, kid=...
Online proof verified: active=true
```

测试**撤权后旧 JWS 不可用**：

```powershell
.\probe-user-proof.ps1 -GrantCapability -RevokeAfterTest
```

预期 `Revocation check passed: old proof rejected with HTTP 403.`。请勿把 JWT 或 JWS 粘贴进聊天。

## 第 3 步：Flutter 侧安装和 Host API 验收

在 MOD 管理入口选择 `task-template-v1.zip`，并确保该用户已登录同一个后端环境（模拟器与真机访问本机的地址可能不同）。该 ZIP 仅含三份 JSON 文件，不能执行第三方代码。Flutter 完成安装、授予权限、打开模板并创建任务后，再执行撤权测试，确保新 Host API 调用被拒绝。以上运行时操作未在本交付环境中实测。

**重要区别：** `task-template-v1.zip` 的 `integrity.json` 只保证内容与摘要一致；Publisher 签名在服务端发布接口登记，并非 ZIP 自带的身份凭证。本地导入 ZIP ≠ 自动完成 Publisher 签名鉴权、后台审批或用户授权。真实联调时必须在 Flutter 中选择与服务端 Manifest **字节一致**的版本。

## 故障定位

- **503**：服务端 `MOD_ADMIN_TOKEN` / 平台签名密钥未配置（看具体 API 返回）；若是 Publisher 管理 API 503，通常是管理员令牌未配置。
- **401**：管理员令牌或用户 JWT 不正确，或 JWT 失效。
- **403**：签名/Capability/审批/用户授权校验未通过；在线撤权后的旧 JWS 返回 403 是预期结果。
- **409**：同版本已存在且内容不同，或 Publisher 公钥重复/冲突；脚本不会自动覆盖。
- **公钥被吊销**：不应复用旧测试密钥伪造新身份；明确更新 Publisher ID 和版本再重新准备测试数据。

只用于本地测试，不要把 `MOD_ADMIN_TOKEN`、用户 JWT、`publisher-private.pkcs8` 或其他私钥放入仓库、截图或聊天。
