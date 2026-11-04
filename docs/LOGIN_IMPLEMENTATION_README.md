# PlanBlindBox 登录 / 注册 / 忘记密码 / 我的资料（源码补丁）

## 包内文件是什么

这不是一个完整 Flutter 工程，也不是完整旧 Java 项目，而是基于已上传 `frontend-lib.zip` 和资料库 `PlanBlindBox.zip` 逐文件制作的源码补丁：

- `frontend/lib/`：只含新增 / 已修改的 Dart 文件，直接合并进现有 `frontend/lib/`；其他 Dart 文件不动。
- `mod-server/`：只含新增 / 已修改的 Java、SQL、配置及测试文件，合并进现有 `mod-server/`。
- **项目根目录 `src/` 不在补丁中，也不会被覆盖或依赖。**
- 原项目 `mod-server` 的 V1 / V2 Flyway 迁移不修改。本次新增 V3 / V4；如果你本机已有 V3、V4，先调整迁移版本号再启动。

## 已完成的功能与规则

- 启动提供邮箱登录 / 注册 / 游客入口；登录成功进入现有五栏页面，游客可使用本地 SQLite。
- 名称 `username` 去首尾空白，1～50 字，允许重名；`email` 规范为 trim + 小写，最多 100 字，唯一索引。
- 密码不 trim，8～64 Unicode 字符，UTF-8 <=72 字节，后端 BCrypt(12) 哈希。
- 注册性别必选 MALE/FEMALE/UNDISCLOSED，头像 NULL；注册后返回登录并预填邮箱。
- 忘记密码：邮件六位随机码，10 分钟有效；HMAC-SHA256 保存验证码摘要；限流 / 5 次失败预算 / 一次性消费；修改密码会撤销旧 JWT。
- 登录后 `我的` 可以修改名称、性别、生日、PNG/JPEG 头像，邮箱只读，不返回 password_hash。
- 游客可浏览 Mod 列表、详情、排行榜；实际下载和 manifest 由 mod-server 的 JWT 鉴权保护。
- 账号云端进度：提供明确确认的**手动上传/恢复** JSON 快照与 revision 乐观并发控制；登录不自动覆盖本机 SQLite。
- 原管理员 Bearer token 仍单独由 `ModAdminController.authorize()` 校验，不作为普通用户 JWT。

## 一次性接入步骤（Windows PowerShell）

先备份项目或提交 Git；一定从项目根目录操作：

```powershell
cd E:\CODE\code\PlanBlindBox
# 下载后的 ZIP 请填写实际所在路径
Expand-Archive -Path 'C:\Downloads\PlanBlindBox-login-account-patch.zip' -DestinationPath . -Force
cd .\frontend
flutter pub add flutter_secure_storage image_picker
flutter pub get
flutter analyze
```

`frontend/lib` 已给出全部被修改的目标文件，但**资料库源包没有 `pubspec.yaml` 与 Android 原生配置**，所以只能由 `flutter pub add` 向你的实际工程加入依赖。不要把 `pubspec.yaml`、android/ 目录重新创建或覆盖。

后端按 Spring Boot 3.2.5 / Java 21 使用：

```powershell
cd E:\CODE\code\PlanBlindBox\mod-server
# 下一节配置完成后运行：
mvn test
mvn spring-boot:run
```

## 必需的服务端环境变量

需要**两把不同的随机密钥**，各至少 32 字节。以 PowerShell 5.1 兼容方式生成：

```powershell
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$a = New-Object byte[] 32
$b = New-Object byte[] 32
$rng.GetBytes($a)
$rng.GetBytes($b)
$env:APP_JWT_SECRET_BASE64 = [Convert]::ToBase64String($a)
$env:PASSWORD_RESET_HMAC_SECRET_BASE64 = [Convert]::ToBase64String($b)
$rng.Dispose()
```

以上只设置当前窗口的临时变量，**实际部署时要在安全配置中持久保管**，否则重启后旧 token / 尚未使用的验证码可能失效。不要将密钥提交到 Git、APK 或贴进公开日志。

实际邮箱找回密码还需要 SMTP：

```powershell
$env:MAIL_HOST = '你的 SMTP 主机'
$env:MAIL_PORT = '587'
$env:MAIL_USERNAME = '发件邮箱的 SMTP 用户名'
$env:MAIL_PASSWORD = 'SMTP 授权码或应用密码'
$env:MAIL_FROM = '发件邮箱地址'
```

默认使用 587/STARTTLS；需要 465/SSL 的邮件供应商应按要求修改 `application.yml`。没有有效 SMTP 配置时，找回密码请求会返回 503，不会假装成功。账号注册本身不发送邮箱验证码，因此只校验格式，不验证邮箱所有权。

后端仍使用原来的 `MOD_DB_URL`、`MOD_DB_USER`、`MOD_DB_PASSWORD`，数据库默认 `plan_mod_market`，服务端口默认 `8091`。Flyway 启动时需要创建新表的权限；请先核对数据库账号授权，不要在生产环境随意扩大权限。

## Flutter 连接地址（很重要）

`ApiConfig.baseUrl` 的 `local://sqlite` 不要修改：它负责本地计划。新增认证与 Mod 市场共同使用 `MOD_MARKET_URL`：

浏览器（开发机）示例：

```powershell
cd E:\CODE\code\PlanBlindBox\frontend
flutter run -d chrome --web-port=3000 --dart-define=MOD_MARKET_URL=http://127.0.0.1:8091
```

**真机中的 localhost 指手机，不是开发机。** 开发测试把 `MOD_MARKET_URL` 改成手机可访问的局域网 IP；发布 APK 应使用有效的 HTTPS 服务地址，并确保 AndroidManifest.xml 有 INTERNET 权限。临时使用明文 HTTP 可能还需要开发环境 cleartext 配置，不要把此设定用到正式发布版。

示例：

```powershell
flutter build apk --release --dart-define=MOD_MARKET_URL=https://api.example.com
```

## 接口速查

| 方法 | 接口 | 认证 |
|---|---|---|
| POST | `/api/v1/auth/register` | 公开 |
| POST | `/api/v1/auth/login` | 公开 |
| POST | `/api/v1/auth/password/forgot` | 公开 + 限流 |
| POST | `/api/v1/auth/password/reset` | 验证邮箱验证码 |
| POST | `/api/v1/auth/logout` | JWT（全设备撤销） |
| GET/PUT | `/api/v1/me` | JWT |
| POST/DELETE | `/api/v1/me/avatar` | JWT |
| GET/PUT | `/api/v1/me/progress` | JWT |
| GET | `/api/v1/mods`、`/api/v1/mods/ranking`、`/api/v1/mods/{id}` | 公开 |
| POST | `/api/v1/mods/{id}/versions/{version}/download` | JWT |
| GET | `/api/v1/mods/{id}/versions/{version}/manifest` | JWT |

JWT 使用 HMAC HS256，issuer=`planblindbox`，audience=`planblindbox-api`，有效期默认 2 小时；每次受保护请求检查用户 ACTIVE 与 credential_version。退出登录 / 重置密码会让全部旧 token 失效。

## 原后端 src 与 app_user

根据你的明确要求，此版**完全不改项目根目录旧后端 `src/`**。由于 `mod-server` 连接的是独立 MySQL 库，旧库里的 `app_user` 不能直接用作新账号表；本版在 Mod 库新建 `community_user`，**沿用字段名称** `username` / `email`，而不是复用旧账号记录。原有账户数据不会自动迁入。如果需要延续老账号，必须单独做审计后的数据迁移。

## 数据库与同步注意事项

- 云端仅保存手动上传的个人 JSON 快照，不是自动实时双向合并；`expectedRevision` 不匹配时返回 409。
- 同步页面在覆盖本机数据之前会警告。建议始终在原来的“设置”中额外导出本地备份。
- Flutter 本地 SQLite 仍是一份设备内数据，`userId` 现在仍是本地分区标识。切换账号不会自动清除或切换数据库，客户端使用本地 owner 标记避免将已关联其他账户的数据误上传。以后如需完整的多用户本地隔离，应该额外做账户独立数据文件方案。
- 既有坚果云 WebDAV 功能没有更改；新功能是另一条账号云端快照链路。
- 头像只接受实际可解析的 PNG/JPEG，最大 2MiB，目录由 `APP_AVATAR_DIR` 配置，必须是**持久化磁盘**或正式部署所对应的挂载目录。
- 本次修改使原本匿名可访问的 Mod download/manifest 改为需 JWT。测试文件已相应调整，游客仍能浏览公开 Mod 元数据。
- `password_reset_rate` 与 `password_reset_cooldown` 用 MySQL 保存限流计数和状态，建议生产运维定期清理过期记录；限流服务数据库不可用时会拒绝请求，不会绕过限制。

## 交付状态与尚未在当前环境执行的验证

这里交付的是**源码和测试代码**，不是已构建或已验证安装的 APK。当前执行环境没有 Flutter SDK 或 Maven，因此没有运行 `flutter analyze`、`mvn test` 或真实 SMTP / MySQL / Android 端到端联调，不宣称它们已通过。

接入后一次性执行 `flutter analyze` 和 `mvn test` 即可检查编译、既有测试与新增认证测试；随后在自己的测试环境执行一次注册→登录→改资料→找回密码→游客查看 Mod→登录下载→手动上传/恢复。**不需要追加排行榜性能压测。**
