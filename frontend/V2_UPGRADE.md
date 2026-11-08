# PlanBlindBox V2 隐私与认证升级（开发预览）

## V2 安全边界

- 登录认证：OPAQUE RFC 9807，固定依赖 `@serenity-kit/opaque@1.1.0`。
- 账号主密钥：客户端生成 32-byte AMK；用 OPAQUE `exportKey` 经 HKDF-SHA256 + AES-256-GCM 包装后保存到服务端。OPAQUE 使用随机不可变账号标识，不直接使用可变邮箱作为协议身份或密钥包装 AAD。
- 服务端：只保存 OPAQUE registration record、AMK 包装信封和私密同步密文，不持有 OPAQUE export key 或 AMK 明文。
- 本地私密数据：日记、情绪、自定义情绪、生理期记录进入 `private_vault_records`，内容使用 AMK + AES-256-GCM 加密；日期和正文均在密文内。
- 云端私密同步：协议升级到 `/api/v2/me/sync`，服务端只接受五字段 V2 密文信封。
- 设备：`flutter_secure_storage` 保存设备上的 AMK 副本；显式退出登录会删除该设备副本。

## 重要：先生成并保管 OPAQUE server setup

在 `../opaque-service` 或单独安全环境中执行：

```bash
npx @serenity-kit/opaque@1.1.0 create-server-setup
```

将输出的 setup 字符串保存到服务器密钥管理系统，不要提交 Git、不要放入普通配置文件、不要发给客户端。然后提取公钥：

```bash
npx @serenity-kit/opaque@1.1.0 get-server-public-key "<OPAQUE_SERVER_SETUP>"
```

把公钥作为 `--dart-define=OPAQUE_SERVER_PUBLIC_KEY=<public-key>` 注入正式客户端构建；客户端同时使用本机安全存储做 TOFU pinning。OPAQUE server setup 一旦更换，已有 OPAQUE registration records 将无法继续登录。

## 启动 OPAQUE sidecar

```bash
cd opaque-service
npm install
export OPAQUE_SERVER_SETUP='<server setup>'
export OPAQUE_INTERNAL_SECRET='<至少 32 字节随机值>'
node server.js
```

sidecar 默认只监听 `127.0.0.1:8092`，应与 Java 服务放在同一主机/网络命名空间。若放在独立容器，可设置 `OPAQUE_BIND_HOST=0.0.0.0`，但必须只在容器内网开放，并且不得把 `/internal/*` 暴露到公网。Java 与 sidecar 的 `OPAQUE_INTERNAL_SECRET` 必须一致。

## 构建客户端 OPAQUE WASM bundle

```bash
cd opaque-client
npm install
npm run build
```

构建脚本会生成并复制：

- `web/opaque_client.js`
- `assets/opaque/opaque_client.js`

仓库内的同名 placeholder 只用于让 Flutter 工程在未构建 OPAQUE bundle 时仍能完成资源解析；它会明确报错，不能用于真实注册/登录。

## Flutter 与 Java 构建

```bash
flutter pub get
flutter test
flutter build web --dart-define=API_BASE_URL=https://你的服务端 --dart-define=OPAQUE_SERVER_PUBLIC_KEY=你的OPAQUE公钥
flutter build apk --dart-define=API_BASE_URL=https://你的服务端 --dart-define=OPAQUE_SERVER_PUBLIC_KEY=你的OPAQUE公钥
```

Java 服务需要设置：

```bash
OPAQUE_SERVICE_URL=http://127.0.0.1:8092
OPAQUE_INTERNAL_SECRET='<与 sidecar 相同的随机值>'
```

Flyway 会应用 `V8__opaque_v2_auth_and_amk.sql` 和 `V9__opaque_stable_user_identifier.sql`。新账号使用 `/api/v2/auth/*`；旧 `/api/v1/auth/register`、`/login` 和仅邮件验证码重置密码的接口已停用。

## 测试账号迁移说明

现有 V1 测试账号只有 BCrypt password hash，没有 OPAQUE registration record 和 AMK wrapper。V2 不会把 BCrypt hash 转成 OPAQUE credential，也不会把 V1 恢复口令伪装成 OPAQUE export key。测试阶段请用新邮箱注册 V2 账号；旧 V1 云端私密记录会被标记为不可由 V2 解密的旧版本记录，不会被当作 V2 数据覆盖。

## 当前实现边界 / 尚未完成

- Android 使用本地 WebView 执行 OPAQUE WASM；Web 使用同一 bundle。
- 当前未上传 iOS 工程，因此 iOS Keychain / Face ID / 构建签名适配尚未验证；后续可在 iOS 工程加入相同 JS/WASM bridge 和平台安全存储适配。
- OPAQUE sidecar 的 login state 暂存在单进程内存，适合单实例测试部署；多实例部署前必须改为 Redis/共享状态存储并配置限流。
- 旧式邮箱密码重置已停用。V2 的可信设备批准 / 恢复码流程尚未实现；丢失密码且没有可信设备或恢复材料时，服务端无法恢复 AMK，这是端到端加密的预期安全结果。
- 日记访问锁（账号级访问口令 + 本机生物识别）是独立于底层 E2EE 的下一项 UI/策略工作；本次 V2 已先完成数据仓库加密和账号密钥包装，不能把“本地加密已完成”误认为“日记访问锁已完成”。

## 安全注意

OPAQUE 使用 `memory-constrained` Argon2id profile（64 MiB、3 次迭代、并行度 4），以兼顾手机可用性；库文档说明 RFC recommended profile 更强但可能显著增加内存和耗时。部署前应在目标 Android 设备上测量耗时与内存，再决定是否提高参数。
