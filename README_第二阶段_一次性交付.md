# PlanBlindBox 第二阶段：一轮合并版（2026-11-05）

## 本轮范围与真实状态

**代码已编写、已做 ZIP/静态结构检查、SQLite 同步触发器实际测试。**
当前运行环境没有 Flutter/Dart SDK、Maven 或 MySQL，因此没有通过 `flutter analyze`、`flutter test`、`mvn test` 或 Android 真机验收。**不要直接部署到生产数据库或存储真实隐私数据。**

本交付在最新版 `mod-server.zip`、`lib.zip` 上叠加此前验收过的“任务、习惯自动双向同步”合并版以及 V6 `sync_cursor` 保留字修复，不重新设计账号、水滴或任务习惯的业务规则。

## 已实现的代码

- 任务/习惯：继续使用此前已经跨 Edge/Chrome 实测通过的 UUID、SQLite 变更触发器、待传队列、幂等操作、删除墓碑、15 秒轮询和冲突救援记录。
- 私密日记录：本地 SQLite v6 增加同步 UUID 和变更触发器；将同一业务日的情绪、月经、日记作为**一条** AES-256-GCM 加密记录传输，避免三个字段各自覆盖。跨设备记录 UUID 使用密钥派生的 HMAC 标识，不直接发送日期；自定义情绪列表也加密同步。
- 跨设备密钥恢复：服务器 Flyway V7 建立 `user_sync_crypto_config`。客户端第一次解锁时用独立恢复口令经 PBKDF2-HMAC-SHA256 派生 256 位密钥，创建只写一次的密钥盐和 AEAD 校验信封；其他设备输入同一恢复口令以验证并解密。服务器不收到密码或密钥。Android 可用系统安全存储缓存派生密钥；浏览器会话需重新输入。
- 未解锁时：本地私密写入不受影响；下发的密文先存 `core_sync_deferred`，不丢弃；任务/习惯继续正常同步。解锁后处理暂存密文，冲突先留存双方版本。
- 坚果云：新备份 `archiveVersion=2`，客户端用**独立备份密码** PBKDF2 + AES-256-GCM 加密整个备份，再上传；下载先校验 SHA-256 和 AEAD 标签、账号，再预览记录数量和事务恢复。旧版明文 `archiveVersion=1` 只允许用户明确二次确认后恢复，不再上传新的明文备份。
- 云同步订阅：保留 V6 `user_sync_entitlement` 的到期控制，返回 ¥9.90/年方案标识、到期时间、是否可以上传。过期时服务器拒绝新写入，但允许拉取已经存储的变更。旧版服务器明文整库快照上传按钮禁用。

**尚未完成的外部依赖：** 正式支付渠道和支付回调核验（暂用测试账号手动授权）；生产环境容量限制、数据保留周期、备份密钥找回和完整密钥轮换需要运营方案。客户端本地 SQLite 依旧由设备/系统保护，并非 SQLCipher 整库加密。

## 安装（当前项目根目录：E:\\CODE\\code\\PlanBlindBox）

1. 备份现有 `frontend/lib`、`frontend/test`、`mod-server` 和 **MySQL 数据库**，不要直接使用真实个人日记测试。
2. 解压此 ZIP 到项目根目录，允许覆盖同名代码文件。仅含 `frontend/lib` 与测试、后端改动文件及 V7 迁移文件，没有覆盖你的 `pubspec.yaml`、生产密钥或数据库文件。
3. 前端增加唯一新的依赖：

   ```powershell
   cd E:\CODE\code\PlanBlindBox\frontend
   flutter pub add cryptography
   flutter pub get
   flutter analyze
   flutter test test/cloud_archive_service_test.dart
   flutter test test/private_sync_crypto_test.dart
   flutter test test/core_sync_client_test.dart
   ```

4. 后端：

   ```powershell
   cd E:\CODE\code\PlanBlindBox\mod-server
   mvn clean test
   mvn spring-boot:run
   ```

   Flyway 自动从已经成功的 V6 升至 V7。**不需要删除 V6 数据、修改旧迁移校验和、`repair` 或手动建 V7 表。** 如果启动失败，查看最早的 `Caused by`。

5. MySQL 检查：

   ```sql
   USE plan_mod_market;
   SELECT version, description, success FROM flyway_schema_history ORDER BY installed_rank DESC LIMIT 3;
   SHOW TABLES LIKE 'user_sync_crypto_config';
   ```

6. 如果测试账号订阅没有激活，使用原有的后台授权方式（仅测试环境）：

   ```sql
   INSERT INTO user_sync_entitlement(user_id,expires_at)
   SELECT user_id,DATE_ADD(NOW(),INTERVAL 30 DAY) FROM community_user
   WHERE email IN ('11111@test.local','22222@test.local')
   ON DUPLICATE KEY UPDATE expires_at=VALUES(expires_at);
   ```

## 测试顺序（先用两浏览器，之后 Android）

1. 同一账号 Edge 新建任务，Chrome 自动拉取，Chrome 打卡，Edge 再看到结果；断网新增/删除后恢复网络并核对记录与删除墓碑。
2. 两设备离线同时编辑一条记录，恢复网络后应产生 409 冲突，不静默覆盖；冲突页面选择一个版本，另一个版本留存在本机救援记录中。
3. Edge 登录 `11111@test.local`，在“我的 → 账号云端进度”输入**新的私密同步恢复口令（>=10位）**。新建日记/情绪/经期记录，等同步完成。Chrome 同账号进入同一页面输入**同一口令**，确认内容出现。再用 `22222@test.local` 验证互不串数据。
4. 故意输入错误私密同步口令，应拒绝解锁，不得覆盖已有密文。
5. 坚果云上传：输入独立备份密码（>=10位）和确认密码；检查云端档案里没有可见日记正文。下载时错误密码须失败，正确密码显示任务/习惯/私密天数预览，再确认恢复。
6. 把测试账户订阅改成过期，`GET /api/v1/me/sync/changes` 应仍可拉取，`PUT /api/v1/me/sync/records` 应返回 403；无有效订阅时不可首次初始化云端私密密钥。
7. Android 真机联调：登录、加密同步解锁、网络切换、App 重启/账号切换、WebDAV 恢复；测试时更新 APK 使用的 API_BASE_URL / MOD_MARKET_URL，不能指向手机自身 localhost。

## 重要安全限制

- **忘记私密同步恢复口令，服务器无法替你解密。** 在至少两台设备实际完成恢复验证前，不要把密文当成唯一备份。
- **私密同步恢复口令和坚果云备份密码是两套独立密码**，账户登录密码也不应复用。
- **本地 SQLite 仍有未加密字段**；E2EE 是针对服务器云同步的。坚果云新的 v2 备份整体加密；本地手动导出的 JSON 原文件不是自动加密。
- 当前测试账号密码太弱；通过 Cloudflare 公网临时隧道访问时必须使用独立测试数据，生产部署前修改密码并限制公开端点。
- `core_sync_rescue` 保留本地冲突双方版本以便恢复，因此可能含有本地明文日记；本地设备的安全存储、锁屏与备份同样重要。
- 如果你的后端已经有一个成功执行的 Flyway `V7`，请不要覆盖它或重复创建同号迁移，需先核对命名版本。
