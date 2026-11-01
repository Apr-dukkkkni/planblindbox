# PlanBlindBox V2.1–V2.5 集成版本（一次性整合）

此目录是以 **V1 本地优先完整源码** 为基础，依照版本顺序合并 V2.1、V2.2、V2.3（fixed）、V2.4、V2.5 阶段的代码及最终修复补丁而成。**不是从用户目前正在运行的 Windows 项目目录抓取的快照。** 如果你在本地有未上传的额外改动，请先备份，对比后再替换。

## 包含
- V1 本地任务、习惯、奖励和备份功能。
- V2.1 Mod 安装/授权/依赖/模板。
- V2.2 在线 Mod 市场及首页抽屉入口。
- V2.3 RabbitMQ+Redis ZSet+MySQL Outbox；使用修复后的 Flyway 版本及页面。
- V2.4 并发幂等、Outbox 测试隔离、KeyHolder 修复。
- V2.5 最低宿主版本、Redis 限流、SHA-256 清单校验、排行榜方法及 Mockito 修复。

## 快速本地验收（Windows PowerShell）
进入解压出的 `PlanBlindBox` 目录，运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run-all-tests.ps1
```

它依次执行：`mod-server/mvn clean test`、`frontend/flutter pub get`、`frontend/flutter test`。测试使用 H2 内存库；脚本临时清除 `MOD_ADMIN_TOKEN`，结束后恢复。**不会重新创建生产数据库、启动/停止 Docker 容器或写入 MySQL 业务数据。**

如需手动测试真实环境：在独立窗口启动 `mod-server`（先设置你自己有效的数据库及 RabbitMQ/Redis 环境变量）和 Flutter Web：

```powershell
cd .\mod-server
mvn spring-boot:run
```

```powershell
cd .\frontend
flutter run -d edge --web-port=3000
```

请参见 `docs/patch-notes/` 下各版 README，注意当前改动需要 Java 21、Maven、Flutter，以及真实部署时的 MySQL、Redis、RabbitMQ。**不要把任何真实密钥写入 ZIP。**

## 当前验证程度
- 历史：用户已在自己机器上通过各阶段回归与真实接口测试。
- 本整合包：已进行本地结构及文件合并检查；由于生成环境缺少 Maven 和 Flutter，**整合包本身尚未执行 `mvn clean test` 或 `flutter test`**。请以新的统一回归测试结果为准，不要将历史测试当作整合包测试。

## 注意
- 文件版本冲突以最新版修复为准。
- `frontend/pubspec.yaml` 已添加 `crypto: ^3.0.3`；请运行 `flutter pub get` 更新锁文件。
- 本项目 `mod-server` 独立于主后端模块，Mod 市场运行在 8091 端口。
- 生产环境的数据库表由 Flyway 迁移；不要直接清空现有 MySQL 库。
